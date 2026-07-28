shader_type spatial;
render_mode cull_back, shadows_disabled;
// Banded gas giant / rocky planet with fresnel atmosphere. Original shader.

uniform vec3 col_a : source_color = vec3(0.85, 0.55, 0.3);
uniform vec3 col_b : source_color = vec3(0.5, 0.25, 0.12);
uniform vec3 col_c : source_color = vec3(0.95, 0.85, 0.7);
uniform vec3 atmo : source_color = vec3(0.5, 0.7, 1.0);
uniform float band_freq = 9.0;
uniform float turbulence = 1.4;
uniform float atmo_power = 3.0;
uniform float atmo_strength = 1.2;
uniform float rocky : hint_range(0.0, 1.0) = 0.0;

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

float fbm(vec3 p) {
	float a = 0.5;
	float r = 0.0;
	for (int i = 0; i < 4; i++) {
		r += a * vnoise(p);
		p = p * 2.1 + vec3(3.7);
		a *= 0.5;
	}
	return r;
}

void vertex() {
	v_obj = normalize(VERTEX);
}

void fragment() {
	vec3 p = v_obj;
	float turb = fbm(p * 3.0) * turbulence;
	float bands = sin((p.y + turb * 0.35) * band_freq) * 0.5 + 0.5;
	float detail = fbm(p * 6.0 + vec3(11.0));
	vec3 gas = mix(col_a, col_b, bands);
	gas = mix(gas, col_c, pow(detail, 2.6) * 0.8);
	// rocky variant: noise patches instead of bands
	float rockmask = fbm(p * 5.0);
	vec3 rock = mix(col_b, col_a, smoothstep(0.35, 0.65, rockmask));
	rock = mix(rock, col_c, pow(fbm(p * 14.0), 3.0));
	vec3 base = mix(gas, rock, rocky);
	ALBEDO = base;
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
	// fresnel atmosphere
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), atmo_power);
	EMISSION = atmo * fres * atmo_strength;
}
