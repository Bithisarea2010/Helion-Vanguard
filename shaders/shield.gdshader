shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;
// =============================================================================
// Helion Vanguard — icosahedral shield matrix.
//
// The shell is a geodesic icosphere built at runtime. It is INVISIBLE until
// something hits it: each impact lights the hemisphere facing the hit with an
// expanding ring of lattice, and the shell goes dark again when the last ring
// has decayed. There is no permanent bubble.
//
// The lattice is a true wireframe of the icosphere's own triangulation, not a
// procedural pattern: the mesh is built non-indexed with barycentric
// coordinates in COLOR, so `min(bary)` is the distance to the nearest edge and
// `fwidth()` keeps the line one pixel wide at any distance. A procedural
// triangle field cannot be made to line up with a geodesic sphere's actual
// faces, and the mismatch reads immediately as "texture on a ball".
//
// Cost when idle is zero — ShieldBubble hides the MeshInstance3D outright
// rather than leaving a transparent shell in the draw list.
// =============================================================================

const int MAX_IMPACTS = 6;

// xyz = unit direction of the impact in object space, w = age 0..1 (1 = expired)
uniform vec4 impacts[MAX_IMPACTS];
uniform int impact_count = 0;
uniform vec3 shield_color : source_color = vec3(0.35, 0.68, 1.0);
uniform vec3 fail_color : source_color = vec3(1.0, 0.32, 0.16);
uniform float charge : hint_range(0.0, 1.0) = 1.0;   // shield strength 0..1
uniform float lattice_width : hint_range(0.5, 4.0) = 1.6;
uniform float gain : hint_range(0.0, 4.0) = 1.0;

varying vec3 v_bary;
varying vec3 v_obj_normal;

void vertex() {
	v_bary = COLOR.rgb;
	v_obj_normal = normalize(VERTEX);
}

void fragment() {
	vec3 n = normalize(v_obj_normal);

	// --- accumulate impact energy over the shell -------------------------
	float ring_e = 0.0;   // the travelling wavefront
	float core_e = 0.0;   // the bright flash at the point of impact
	for (int i = 0; i < MAX_IMPACTS; i++) {
		if (i >= impact_count) {
			break;
		}
		vec4 im = impacts[i];
		float age = im.w;
		if (age >= 1.0) {
			continue;
		}
		float facing = dot(n, im.xyz);
		// hemisphere gate: the far side of the shell never lights, which is what
		// makes this read as a directional half-dome instead of a glowing ball
		float hemi = smoothstep(-0.08, 0.55, facing);
		if (hemi <= 0.0) {
			continue;
		}
		float ang = acos(clamp(facing, -1.0, 1.0));
		float life = 1.0 - age;
		// the front sweeps out to ~110 deg and thins as it goes
		float radius = age * 1.95;
		float width = mix(0.14, 0.045, age);
		float ring = smoothstep(width, 0.0, abs(ang - radius));
		ring_e += ring * life * life * hemi;
		core_e += exp(-ang * 9.0) * pow(life, 3.0) * hemi;
	}
	float energy = clamp(ring_e + core_e * 1.6, 0.0, 3.0);

	// --- geodesic lattice -------------------------------------------------
	// screen-space-constant line width from the barycentric gradient
	vec3 d = fwidth(v_bary);
	vec3 a = smoothstep(vec3(0.0), d * lattice_width, v_bary);
	float edge = 1.0 - min(min(a.x, a.y), a.z);

	// --- limb: a shield is a shell, so the grazing rim is denser ----------
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);

	// --- a failing shield crazes and goes red ----------------------------
	vec3 col = mix(fail_color, shield_color, smoothstep(0.05, 0.55, charge));
	float craze = (1.0 - charge) * edge * energy * 0.6;

	float lit = energy * (edge * 0.85 + 0.10) + energy * fres * 0.45 + craze;
	ALBEDO = col * lit * gain * (1.4 + 1.6 * charge);
	ALPHA = clamp(lit * gain, 0.0, 1.0);
}
