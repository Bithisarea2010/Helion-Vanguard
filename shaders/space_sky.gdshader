shader_type sky;
// Helion Vanguard — procedural nebula + starfield sky (original)

uniform vec3 nebula_a : source_color = vec3(0.16, 0.05, 0.28);
uniform vec3 nebula_b : source_color = vec3(0.02, 0.16, 0.30);
uniform vec3 nebula_c : source_color = vec3(0.30, 0.10, 0.05);
uniform float nebula_intensity : hint_range(0.0, 3.0) = 1.0;
uniform float star_brightness : hint_range(0.0, 4.0) = 1.6;
uniform float band_tilt = 0.2;
uniform vec3 sun_dir = vec3(0.45, 0.25, 0.6);      // direction TOWARD the sun
uniform vec3 sun_tint : source_color = vec3(1.0, 0.85, 0.55);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1, 0, 0));
	float n010 = hash13(i + vec3(0, 1, 0));
	float n110 = hash13(i + vec3(1, 1, 0));
	float n001 = hash13(i + vec3(0, 0, 1));
	float n101 = hash13(i + vec3(1, 0, 1));
	float n011 = hash13(i + vec3(0, 1, 1));
	float n111 = hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float r = 0.0;
	for (int i = 0; i < 4; i++) {
		r += a * vnoise(p);
		p = p * 2.03 + vec3(1.7);
		a *= 0.5;
	}
	return r;
}

float star_layer(vec3 d, float scale, float thresh, out float tint) {
	vec3 sp = d * scale;
	vec3 cell = floor(sp);
	float h = hash13(cell);
	tint = hash13(cell + 13.37);
	if (h > thresh) {
		vec3 c = fract(sp) - 0.5;
		float r = length(c);
		float m = smoothstep(0.32, 0.0, r);
		return m * m * (h - thresh) / (1.0 - thresh);
	}
	return 0.0;
}

void sky() {
	vec3 d = EYEDIR;
	// nebula clouds
	float n1 = fbm(d * 2.6 + vec3(9.2));
	float n2 = fbm(d * 5.2 + vec3(3.1));
	float n3 = fbm(d * 1.4 + vec3(21.0));
	float band = exp(-abs(d.y + band_tilt) * 3.0);
	vec3 neb = nebula_a * pow(n1, 2.3) * 2.4
		+ nebula_b * pow(n2, 2.8) * 2.0
		+ nebula_c * pow(n3, 3.4) * 2.6 * band;
	neb *= (0.30 + 0.9 * band) * nebula_intensity;
	// stars, two scales
	float t1;
	float t2;
	float s1 = star_layer(d, 340.0, 0.9965, t1);
	float s2 = star_layer(d, 120.0, 0.998, t2);
	vec3 sc1 = mix(vec3(1.0, 0.95, 0.9), vec3(0.75, 0.85, 1.0), t1);
	vec3 sc2 = mix(vec3(1.0, 0.9, 0.8), vec3(0.85, 0.9, 1.0), t2);
	vec3 stars = (s1 * sc1 + s2 * sc2 * 1.6) * star_brightness;
	// --- the sun: white-hot disc, tight corona, wide warm glare, faint rays
	vec3 sdn = normalize(sun_dir);
	float ang = acos(clamp(dot(d, sdn), -1.0, 1.0));
	float disc = smoothstep(0.013, 0.0105, ang);
	float corona = exp(-ang * 34.0);
	float glare = exp(-ang * 6.5) * 0.5;
	// subtle 6-spoke diffraction rays around the sun
	vec3 ref_up = abs(sdn.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 tx = normalize(cross(ref_up, sdn));
	vec3 ty = cross(sdn, tx);
	float phi = atan(dot(d, ty), dot(d, tx));
	float rays = pow(abs(cos(phi * 3.0)), 14.0) * exp(-ang * 11.0) * 0.5;
	vec3 sun_col = mix(sun_tint, vec3(1.0), 0.65) * disc * 22.0
		+ sun_tint * (corona * 2.4 + glare * 0.5 + rays);
	COLOR = neb + stars + sun_col + vec3(0.004, 0.005, 0.010);
}
