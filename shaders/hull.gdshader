shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// =============================================================================
// Helion Vanguard — procedural hard-surface hull.
//
// The ship meshes carry POSITION + NORMAL only (no UVs, no textures), which is
// why they shipped looking like flat plastic. Rather than unwrap and author a
// texture set per ship, every surface detail here is generated in OBJECT space:
// the meshes are rigid and never deform, so object-space detail is rock-stable,
// costs zero VRAM, adds zero draw calls, and works on every hull, capital,
// turret and station mesh in the game from one shader.
//
// COST DISCIPLINE. A first version used a 3x3x3 Worley lattice sampled four
// times per fragment for the bump gradient; it looked right and cost 20 fps.
// This version keeps the look and is roughly an order of magnitude cheaper:
//   * plating is an O(1) rectangular lattice (ships are panelled, not cellular)
//   * the seam height is evaluated ONCE and the normal comes from screen-space
//     derivatives via Mikkelsen surface gradients, not from extra field taps
//   * hashes are multiply-shift, never trigonometric
//   * every noise layer is gated behind a distance LOD
//
// Layers: plating -> seams -> bolts -> edge wear -> grime -> accent stripe ->
//         fresnel rim -> battle damage.
// =============================================================================

uniform vec3 base_color : source_color = vec3(0.55, 0.56, 0.60);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_albedo_tex = false;
uniform float metallic_amt : hint_range(0.0, 1.0) = 0.85;
uniform float roughness_amt : hint_range(0.0, 1.0) = 0.42;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;

uniform float plate_scale = 2.6;          // panel cells per object-space unit
uniform float seam_depth : hint_range(0.0, 2.0) = 0.55;
uniform float plate_variation : hint_range(0.0, 1.0) = 0.35;
uniform float wear : hint_range(0.0, 1.0) = 0.45;
uniform float grime : hint_range(0.0, 1.0) = 0.40;
uniform float bolts : hint_range(0.0, 1.0) = 0.6;

uniform vec3 stripe_color : source_color = vec3(0.95, 0.55, 0.10);
uniform float stripe_amount : hint_range(0.0, 1.0) = 0.0;

uniform vec3 rim_color : source_color = vec3(0.32, 0.46, 0.80);
uniform float rim_strength : hint_range(0.0, 4.0) = 1.0;

uniform float damage : hint_range(0.0, 1.0) = 0.0;   // 0 pristine, 1 wreck
uniform float detail_fade_start = 90.0;
uniform float detail_fade_end = 320.0;
uniform float ao_amount : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_obj;
// COLOR_0 carries the ambient occlusion baked by blender_src/detail_pass.py.
// Meshes without the attribute get white from Godot, so this degrades cleanly.
varying float v_ao;

// ------------------------------------------------------------------ noise kit
// multiply-shift hash: no sin(), which is what made the first draft expensive
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
		mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
		mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// distance from the point to the nearest wall of its lattice cell (0 at the
// seam, 0.5 at the plate centre) plus a stable per-plate random id
vec2 lattice(vec3 q) {
	vec3 d = vec3(0.5) - abs(fract(q) - 0.5);
	return vec2(min(min(d.x, d.y), d.z), hash13(floor(q)));
}

void vertex() {
	v_obj = VERTEX;
	v_ao = mix(1.0, COLOR.r, ao_amount);
}

void fragment() {
	vec3 albedo = base_color;
	if (use_albedo_tex) {
		albedo *= texture(albedo_tex, UV).rgb;
	}
	float rough = roughness_amt;
	float metal = metallic_amt;
	vec3 emit = emission_color * emission_energy;

	// the fresnel rim must come from the GEOMETRIC normal: taking it after the
	// seam bump lights up every panel gap and the hull turns into a glowing
	// wireframe grid
	vec3 geo_n = normalize(NORMAL);

	float dist = length(VERTEX);
	float lod = 1.0 - smoothstep(detail_fade_start, detail_fade_end, dist);

	if (lod > 0.004) {
		// --- plating ---------------------------------------------------------
		// two lattices at different scales and orientations, warped by a single
		// low-frequency noise, so plates read as irregular hull sections rather
		// than graph paper
		float w = vnoise(v_obj * 0.55) - 0.5;
		vec3 q = v_obj * plate_scale + vec3(w * 0.9);

		// Procedural mip. `px` is roughly how many lattice cells one pixel spans;
		// once a cell is smaller than a pixel the pattern must dissolve into its
		// average or it aliases into glitter (which is exactly what the first
		// tuning pass did to the wings).
		float px = length(fwidth(q));
		float sharp = lod * (1.0 - smoothstep(0.10, 0.55, px));

		vec2 a = lattice(q);
		// second lattice: coarser, rotated 30 deg in XZ, offset
		vec3 q2 = vec3(q.x * 0.866 - q.z * 0.5, q.y, q.x * 0.5 + q.z * 0.866) * 0.47
			+ vec3(3.7, 1.9, 8.1);
		vec2 b = lattice(q2);
		float border = min(a.x, b.x);
		float plate_rand = fract(a.y + b.y * 0.61);

		// seam width tracks the pixel footprint, so gaps stay one crisp line
		// close up and blur away smoothly instead of shimmering
		float sw = 0.030;
		float aa = max(px * 0.5, 0.002);
		float seam = (1.0 - smoothstep(sw - aa, sw + aa, border)) * sharp;

		// per-plate tonal and roughness jitter — the thing that makes a hull
		// look assembled from parts instead of moulded in one piece
		albedo *= 1.0 + (plate_rand - 0.5) * plate_variation * sharp;
		rough = clamp(rough + (plate_rand - 0.5) * 0.22 * sharp, 0.05, 1.0);

		// --- bolts ------------------------------------------------------------
		float bolt_field = 0.0;
		if (bolts > 0.001 && sharp > 0.35) {
			vec3 bq = q * 2.0;
			vec3 bcell = floor(bq);
			if (hash13(bcell + 5.31) > 1.0 - bolts * 0.16) {
				float br = length(fract(bq) - 0.5);
				bolt_field = smoothstep(0.22, 0.11, br) * smoothstep(0.09, 0.02, border) * sharp;
			}
		}

		// --- seam + bolt height, ONE evaluation ------------------------------
		float height = -seam + bolt_field * 0.7;

		// Mikkelsen surface-gradient bump: derive the normal tilt from the
		// screen-space derivatives of the height we already computed, instead of
		// re-sampling the field three more times
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 r1 = cross(dpdy, geo_n);
		vec3 r2 = cross(geo_n, dpdx);
		float det = dot(dpdx, r1);
		vec3 sgrad = sign(det) * (dFdx(height) * r1 + dFdy(height) * r2);
		NORMAL = normalize(abs(det) * geo_n - (seam_depth * 0.05) * sgrad);

		albedo *= 1.0 - seam * 0.45;
		rough = clamp(rough + seam * 0.26, 0.05, 1.0);
		albedo = mix(albedo, albedo * 1.5, bolt_field * 0.45);
		rough = clamp(rough - bolt_field * 0.18, 0.05, 1.0);

		// --- edge wear + grime, sharing one noise lookup ----------------------
		float dirt = vnoise(v_obj * 1.1 + vec3(41.0));
		float wear_mask = wear * smoothstep(0.16, 0.02, border) * smoothstep(0.45, 0.75, dirt) * sharp;
		albedo = mix(albedo, vec3(0.66, 0.67, 0.70), wear_mask * 0.32);
		metal = mix(metal, 1.0, wear_mask * 0.55);
		rough = clamp(rough - wear_mask * 0.18, 0.05, 1.0);

		// grime is low frequency, so it survives the whole LOD range
		float soot = smoothstep(0.58, 0.88, dirt) * grime * lod;
		albedo *= 1.0 - soot * 0.40;
		rough = clamp(rough + soot * 0.30, 0.05, 1.0);
		metal *= 1.0 - soot * 0.45;
	}

	// --- faction accent stripes ----------------------------------------------
	if (stripe_amount > 0.001) {
		float band = abs(fract(v_obj.z * 0.09 + 0.5) - 0.5) * 2.0;
		float s = smoothstep(0.88, 0.97, band) * step(0.15, abs(v_obj.x));
		albedo = mix(albedo, stripe_color, s * stripe_amount);
		metal = mix(metal, 0.35, s * stripe_amount);
	}

	// --- battle damage --------------------------------------------------------
	if (damage > 0.004) {
		float burn = vnoise(v_obj * 2.2 + vec3(77.0));
		float scorch = smoothstep(0.95 - damage * 0.75, 1.02 - damage * 0.75, burn);
		albedo = mix(albedo, vec3(0.045, 0.035, 0.030), scorch * 0.85);
		rough = clamp(rough + scorch * 0.4, 0.05, 1.0);
		metal *= 1.0 - scorch * 0.7;
		emit += vec3(1.0, 0.30, 0.06) * smoothstep(0.90, 1.0, burn) * damage * 2.6;
	}

	// baked contact occlusion: darkens the crevices between greebles and hull,
	// the one cue the procedural layers above cannot invent
	// Baked contact occlusion darkens the crevices between greebles and hull —
	// the one cue the procedural layers cannot invent. Applied ONCE and gently:
	// stacking it into albedo, specular and AO together crushed the hulls black.
	ALBEDO = albedo * (0.72 + 0.28 * v_ao);
	METALLIC = metal;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
	AO = v_ao;
	AO_LIGHT_AFFECT = 0.30;

	float fres = pow(1.0 - clamp(dot(geo_n, VIEW), 0.0, 1.0), 4.0);
	EMISSION = emit + rim_color * fres * rim_strength * 0.35;
}
