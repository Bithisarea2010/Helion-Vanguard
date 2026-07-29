shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// Helion Vanguard — shared asteroid surface. One material for all four rock
// variants (the source GLBs embed identical texture sets), with procedural
// object-space detail so 1,280-triangle rocks read as pitted stone up close.
// All added cost is per-pixel ALU, which this game has in abundance: profiling
// showed frame time is CPU-bound and identical at 640x360 and 1920x1080.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 tint : source_color = vec3(0.66, 0.62, 0.58);
uniform vec3 cavity_tint : source_color = vec3(0.22, 0.19, 0.17);
uniform float detail_scale = 1.1;
uniform float detail_strength : hint_range(0.0, 3.0) = 1.0;
uniform float rim_strength : hint_range(0.0, 4.0) = 0.9;
uniform vec3 rim_color : source_color = vec3(0.30, 0.42, 0.72);
uniform float fade_start = 260.0;   // procedural detail fades out past this
uniform float fade_end = 900.0;

varying vec3 v_obj;
varying vec3 v_nobj;
varying float v_freq;

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

float fbm3(vec3 p) {
	float a = 0.5;
	float r = 0.0;
	for (int i = 0; i < 3; i++) {
		r += a * vnoise(p);
		p = p * 2.07 + vec3(5.1);
		a *= 0.5;
	}
	return r;
}

void vertex() {
	v_obj = VERTEX;
	v_nobj = NORMAL;
	// MultiMesh bakes each rock's scale into the model matrix. Scaling the noise
	// frequency by it keeps crater size roughly constant in world space, so a
	// 60 m boulder does not look like a smeared copy of a 2 m pebble.
	float inst_scale = length(MODEL_MATRIX[0].xyz);
	v_freq = detail_scale * mix(1.0, inst_scale, 0.8);
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb * tint;
	float dist = length(VERTEX);
	float detail_fade = 1.0 - smoothstep(fade_start, fade_end, dist);
	if (detail_fade > 0.002) {
		vec3 q = v_obj * v_freq;
		// ONE noise evaluation. The first version sampled the field four times
		// (value + three offsets) to build a gradient; asteroids cover most of
		// the screen in the belt missions, so that was the single most expensive
		// thing in the frame. Screen-space derivatives of the one sample give
		// the same bump for the cost of a quad-neighbour fetch.
		float n0 = fbm3(q);
		vec3 n = normalize(NORMAL);
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 r1 = cross(dpdy, n);
		vec3 r2 = cross(n, dpdx);
		float det = dot(dpdx, r1);
		vec3 sgrad = sign(det) * (dFdx(n0) * r1 + dFdy(n0) * r2);
		NORMAL = normalize(abs(det) * n - (detail_strength * detail_fade * 0.5) * sgrad);
		// crater/cavity darkening plus fine mineral speckle
		float cav = smoothstep(0.62, 0.28, n0);
		float speck = vnoise(q * 7.0);
		base = mix(base, base * cavity_tint * 2.2, cav * 0.55 * detail_fade);
		base *= 0.85 + 0.30 * speck * detail_fade;
		ROUGHNESS = clamp(0.78 + 0.18 * (n0 - 0.5) - 0.12 * cav, 0.30, 1.0);
	} else {
		ROUGHNESS = 0.82;
	}
	ALBEDO = base;
	METALLIC = 0.0;
	SPECULAR = 0.22;
	// nebula-tinted rim so unlit silhouettes still separate from black space
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_color * fres * rim_strength * 0.35;
}
