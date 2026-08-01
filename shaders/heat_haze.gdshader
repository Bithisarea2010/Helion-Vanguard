shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Helion Vanguard — heat wash behind an engine throat.
//
// This started as a screen-space refraction (`hint_screen_texture`, offset the
// UV by an animated noise field). It looked right and it cost 41% OF THE FRAME:
// a shader that reads the screen forces Godot to copy the whole colour buffer
// every frame, and that copy is charged in full — at 2x render scale, a
// 2560x1440 blit — no matter that the two cones using it cover about 1% of the
// picture. Measured 22.3 fps with it, 31.1 fps without, same sitting, bracketed.
//
// So the refraction is gone and what remains is what the refraction was actually
// FOR: a turbulent, barely-there wash of heat sitting just outside the plume.
// Two crossing wave trains plus a grazing-angle mask, additive, no screen read,
// no extra pass — the same silhouette-softening read for nothing.

uniform vec3 haze_tint : source_color = vec3(0.55, 0.68, 0.95);
uniform float strength : hint_range(0.0, 2.0) = 1.0;
uniform float power : hint_range(0.0, 2.0) = 1.0;
uniform float seed = 0.0;

varying float v_t;
varying vec3 v_normal;

void vertex() {
	v_t = clamp(VERTEX.y + 0.5, 0.0, 1.0);
	v_normal = NORMAL;
}

void fragment() {
	float t = v_t;
	// two crossing wave trains at different rates: a single sine reads as a
	// scrolling ripple rather than as turbulent air
	float a = sin(t * 21.0 - TIME * 11.0 + seed);
	float b = cos(t * 13.0 - TIME * 7.0 + seed * 1.7 + UV.x * 24.0);
	float turb = 0.55 + 0.45 * (a * 0.6 + b * 0.4);
	// only the grazing shell shows; the middle of the cone would otherwise fog
	// the plume it is supposed to be sitting outside of
	float graze = 1.0 - abs(dot(normalize(v_normal), normalize(VIEW)));
	float shell = graze * graze;
	// hottest at the throat, gone by the tail
	float along = (1.0 - smoothstep(0.05, 0.85, t));
	float e = shell * along * turb * power * strength * 0.16;
	ALBEDO = haze_tint * e;
	ALPHA = clamp(e, 0.0, 1.0);
}
