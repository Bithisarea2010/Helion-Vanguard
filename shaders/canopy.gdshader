shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx, diffuse_burley;
// Helion Vanguard — cockpit canopy glass. Thin, dark and slightly iridescent,
// with a bright grazing-angle sheen so the bubble reads as glass instead of the
// opaque black hole a plain transparent StandardMaterial3D produces in space.

uniform vec3 tint : source_color = vec3(0.10, 0.16, 0.22);
uniform vec3 sheen_color : source_color = vec3(0.55, 0.78, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.16;
uniform float sheen_strength : hint_range(0.0, 4.0) = 1.4;
uniform float smudge : hint_range(0.0, 1.0) = 0.35;

varying vec3 v_obj;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
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

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	// faint polishing swirl so the canopy is not a perfect mirror
	float dirt = vnoise(v_obj * 14.0) * 0.5 + vnoise(v_obj * 41.0) * 0.5;
	ALBEDO = tint;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ROUGHNESS = mix(0.04, 0.18, dirt * smudge);
	// thin-film style tint shift across the curve of the bubble
	vec3 sheen = mix(sheen_color, sheen_color.bgr, clamp(fres * 1.3, 0.0, 1.0));
	EMISSION = sheen * fres * sheen_strength * 0.30;
	ALPHA = clamp(base_alpha + fres * 0.55 + dirt * smudge * 0.10, 0.0, 0.92);
}
