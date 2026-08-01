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
//
// 1.2 adds the things that make a rocket read as a rocket rather than a glow:
//   * shock diamonds — the standing Mach nodes in an under-expanded nozzle.
//     They live on the AXIS (low graze), march down the plume, and both
//     brighten and multiply as the afterburner lights.
//   * an afterburner colour stage: the core runs blue-white at high `mach`.
//   * turbulence whose frequency tracks throttle instead of a fixed flicker,
//     so an idling engine shimmers and a burning one roars.

uniform vec3 core_color : source_color = vec3(0.85, 0.95, 1.0);
uniform vec3 tail_color : source_color = vec3(0.20, 0.55, 1.0);
uniform vec3 burn_color : source_color = vec3(0.70, 0.86, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float mach : hint_range(0.0, 1.0) = 0.0;   // 0 idle .. 1 afterburner
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
	// hot white core collapsing into the ship's glow colour; the afterburner
	// stage pushes the near field toward blue-white
	vec3 hot = mix(core_color, burn_color, mach);
	vec3 col = mix(hot, tail_color, smoothstep(0.0, 0.55, t));
	// length falloff: bright and tight at the throat, long soft decay
	float along = exp(-t * mix(3.4, 2.1, mach)) * (1.0 - smoothstep(0.82, 1.0, t));
	// hollow-shell falloff — edge-on parts of the tube are the brightest, which
	// is what gives a plume its bright rim and translucent middle
	float graze = 1.0 - abs(dot(normalize(v_normal), normalize(VIEW)));
	float shell = 0.25 + graze * graze * 1.15;
	// combustion turbulence; an engine under power roars faster than it idles
	float fs = flicker_speed * (0.6 + 0.9 * intensity);
	float flick = 0.88 + 0.12 * sin(TIME * fs + seed)
		* sin(TIME * fs * 0.37 + seed * 2.1);

	// --- shock diamonds ---------------------------------------------------
	// Standing Mach nodes sit on the axis of the jet, so they are strongest
	// where the shell is FACING us (low graze) — putting them on the rim like
	// the rest of the plume made them read as stripes painted on a tube.
	float nodes = 4.0 + 5.0 * mach;
	float phase = t * nodes * PI - TIME * 1.6 * (0.3 + mach);
	float diamond = pow(max(sin(phase), 0.0), 10.0);
	diamond *= exp(-t * 3.0) * (1.0 - graze) * mach;

	vec3 rgb = col * along * shell * intensity * flick;
	rgb += mix(hot, vec3(1.0), 0.5) * diamond * intensity * 2.2;
	ALBEDO = rgb;
	ALPHA = clamp(along * shell * 0.9 + diamond * 0.6, 0.0, 1.0);
}
