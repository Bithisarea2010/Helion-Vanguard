shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Helion Vanguard — engine exhaust plume.
//
// Replaces a stack of ~22 additive billboard quads per engine. Twenty-two
// overlapping quads at any alpha bright enough to see summed past 1.0 across
// the whole quad, so the soft radial texture clipped into a solid white
// rectangle and every ship flew with two white bricks bolted to its tail.
//
// A single cone shell has no self-overdraw: the fragment count is bounded by
// the silhouette, brightness is an explicit function of position, and the
// hollow-tube falloff (alpha rising toward grazing angles) is what makes a
// plume look like hot gas rather than a solid object.

uniform vec3 core_color : source_color = vec3(0.85, 0.95, 1.0);
uniform vec3 tail_color : source_color = vec3(0.20, 0.55, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float flicker_speed = 26.0;
uniform float seed = 0.0;

varying float v_t;
varying vec3 v_normal;

void vertex() {
	// derive the 0..1 nozzle-to-tail parameter from the vertex itself rather
	// than trusting CylinderMesh's UV orientation
	v_t = clamp(VERTEX.y + 0.5, 0.0, 1.0);
	v_normal = NORMAL;
}

void fragment() {
	float t = v_t;
	// hot white core collapsing into the ship's glow colour
	vec3 col = mix(core_color, tail_color, smoothstep(0.0, 0.55, t));
	// length falloff: bright and tight at the throat, long soft decay
	float along = exp(-t * 3.1) * (1.0 - smoothstep(0.82, 1.0, t));
	// hollow-shell falloff — edge-on parts of the tube are the brightest, which
	// is what gives a plume its bright rim and translucent middle
	float graze = 1.0 - abs(dot(normalize(v_normal), normalize(VIEW)));
	float shell = 0.25 + graze * graze * 1.15;
	// combustion flicker
	float flick = 0.88 + 0.12 * sin(TIME * flicker_speed + seed)
		* sin(TIME * flicker_speed * 0.37 + seed * 2.1);
	ALBEDO = col * along * shell * intensity * flick;
	ALPHA = clamp(along * shell * 0.9, 0.0, 1.0);
}
