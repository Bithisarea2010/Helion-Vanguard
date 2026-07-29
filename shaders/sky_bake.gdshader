shader_type canvas_item;
// =============================================================================
// Helion Vanguard — deep-space backdrop, baked to an equirect panorama ONCE per
// mission. After the bake the sky costs a single texture fetch per pixel, so
// this shader can be as expensive as it likes: everything below is paid for in
// one frame at load and never again.
//
// Layers:
//   * domain-warped nebula in three emission colours, with a dense galactic
//     band and dark absorption lanes cutting through it
//   * a separate dust layer that OCCLUDES stars behind it (the old version
//     added nebula and stars independently, so bright stars sat on top of thick
//     cloud and the volume read flat)
//   * four star scales with colour temperature, plus rare bright stars that get
//     a small diffraction cross
//   * a couple of distant galaxies
//   * the local sun: disc, corona, wide glare and six-spoke diffraction rays
// =============================================================================

uniform vec3 nebula_a : source_color = vec3(0.16, 0.05, 0.28);
uniform vec3 nebula_b : source_color = vec3(0.02, 0.16, 0.30);
uniform vec3 nebula_c : source_color = vec3(0.30, 0.10, 0.05);
uniform float nebula_intensity : hint_range(0.0, 3.0) = 1.0;
uniform float star_brightness : hint_range(0.0, 4.0) = 1.6;
uniform float band_tilt = 0.2;
uniform vec3 sun_dir = vec3(0.45, 0.25, 0.6);
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
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
		mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
		mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p, int oct) {
	float a = 0.5;
	float r = 0.0;
	for (int i = 0; i < oct; i++) {
		r += a * vnoise(p);
		p = p * 2.03 + vec3(1.7);
		a *= 0.5;
	}
	return r;
}

// ridged noise gives the filament structure real emission nebulae have
float ridged(vec3 p, int oct) {
	float a = 0.5;
	float r = 0.0;
	for (int i = 0; i < oct; i++) {
		float n = 1.0 - abs(vnoise(p) * 2.0 - 1.0);
		r += a * n * n;
		p = p * 2.17 + vec3(3.3);
		a *= 0.5;
	}
	return r;
}

// swirl the sample point by a lower-frequency noise field: turns smooth blobs
// into the wispy, curdled structure that reads as gas
vec3 warp(vec3 p, float amount) {
	vec3 o = vec3(fbm(p * 1.3 + vec3(0.0), 3), fbm(p * 1.3 + vec3(17.0), 3),
		fbm(p * 1.3 + vec3(43.0), 3)) - vec3(0.5);
	return p + o * amount;
}

float star_layer(vec3 d, float scale, float thresh, out float tint, out float bright) {
	vec3 sp = d * scale;
	vec3 cell = floor(sp);
	float h = hash13(cell);
	tint = hash13(cell + 13.37);
	bright = 0.0;
	if (h > thresh) {
		// jitter the star inside its cell so the field is not a visible lattice
		vec3 jit = vec3(hash13(cell + 5.1), hash13(cell + 9.7), hash13(cell + 2.3)) * 0.6 + 0.2;
		vec3 c = fract(sp) - jit;
		float r = length(c);
		float m = smoothstep(0.34, 0.0, r);
		bright = (h - thresh) / (1.0 - thresh);
		return m * m * bright;
	}
	return 0.0;
}

void fragment() {
	float az = (UV.x - 0.5) * TAU;
	float el = (0.5 - UV.y) * PI;
	vec3 d = vec3(sin(az) * cos(el), sin(el), -cos(az) * cos(el));

	// --- galactic band -------------------------------------------------------
	float band = exp(-abs(d.y + band_tilt) * 3.0);
	float band_tight = exp(-abs(d.y + band_tilt) * 8.0);

	// --- nebula --------------------------------------------------------------
	vec3 w1 = warp(d * 2.2 + vec3(9.2), 0.55);
	vec3 w2 = warp(d * 4.4 + vec3(3.1), 0.35);
	float n1 = ridged(w1, 5);
	float n2 = fbm(w2, 5);
	float n3 = ridged(warp(d * 1.15 + vec3(21.0), 0.8), 4);
	vec3 neb = nebula_a * pow(n1, 2.1) * 2.6
		+ nebula_b * pow(n2, 2.6) * 2.2
		+ nebula_c * pow(n3, 2.9) * 3.0 * band;
	neb *= (0.26 + 0.95 * band) * nebula_intensity;

	// hot cores: the brightest filaments bleach toward white
	float core = smoothstep(0.55, 0.95, n1 * n3);
	neb += mix(nebula_a, vec3(1.0), 0.7) * core * 0.9 * band;

	// --- dark dust lanes -----------------------------------------------------
	// these both eat nebula emission AND occlude the stars behind them, which is
	// what gives the backdrop a sense of depth instead of layered decals
	float dust = smoothstep(0.42, 0.78, fbm(warp(d * 3.1 + vec3(61.0), 0.6), 4));
	float dust_mask = 1.0 - dust * (0.55 + 0.4 * band_tight);
	neb *= dust_mask;

	// --- stars ---------------------------------------------------------------
	float t1; float t2; float t3; float t4;
	float b1; float b2; float b3; float b4;
	float s1 = star_layer(d, 620.0, 0.9975, t1, b1);
	float s2 = star_layer(d, 300.0, 0.9968, t2, b2);
	float s3 = star_layer(d, 130.0, 0.9982, t3, b3);
	float s4 = star_layer(d, 58.0, 0.9992, t4, b4);
	// O-B blue through K-M red, weighted the way a real field looks
	vec3 sc1 = mix(vec3(0.70, 0.80, 1.0), vec3(1.0, 0.86, 0.68), t1);
	vec3 sc2 = mix(vec3(0.78, 0.86, 1.0), vec3(1.0, 0.80, 0.60), t2);
	vec3 sc3 = mix(vec3(0.85, 0.92, 1.0), vec3(1.0, 0.72, 0.48), t3);
	vec3 sc4 = mix(vec3(0.90, 0.95, 1.0), vec3(1.0, 0.68, 0.42), t4);
	// the galactic band is crowded with unresolved stars
	float crowd = 0.55 + 1.9 * band;
	vec3 stars = (s1 * sc1 * 0.8 + s2 * sc2 * 1.2 + s3 * sc3 * 2.0) * crowd;
	// rare bright stars get a diffraction cross
	if (s4 > 0.0) {
		vec3 sp = d * 58.0;
		vec3 c = fract(sp) - 0.5;
		float cross_h = smoothstep(0.30, 0.0, abs(c.y)) * smoothstep(0.42, 0.0, abs(c.x));
		float cross_v = smoothstep(0.30, 0.0, abs(c.x)) * smoothstep(0.42, 0.0, abs(c.y));
		stars += sc4 * (s4 * 3.2 + (cross_h + cross_v) * b4 * 0.5);
	}
	stars *= star_brightness * dust_mask;

	// --- two distant galaxies ------------------------------------------------
	vec3 g_dir = normalize(vec3(-0.62, 0.44, 0.65));
	float g_ang = acos(clamp(dot(d, g_dir), -1.0, 1.0));
	float galaxy = exp(-g_ang * 52.0) * 0.55 + exp(-g_ang * 150.0) * 1.1;
	vec3 g_dir2 = normalize(vec3(0.74, -0.30, -0.60));
	float g_ang2 = acos(clamp(dot(d, g_dir2), -1.0, 1.0));
	galaxy += exp(-g_ang2 * 95.0) * 0.4;
	vec3 galaxies = mix(vec3(0.85, 0.88, 1.0), vec3(1.0, 0.92, 0.78), 0.4) * galaxy;

	// --- the local sun -------------------------------------------------------
	vec3 sdn = normalize(sun_dir);
	float ang = acos(clamp(dot(d, sdn), -1.0, 1.0));
	// a tight, very bright disc: the bloom pass does the flare, so an oversized
	// soft disc just reads as a fuzzy ball rather than a star
	float disc = smoothstep(0.0062, 0.0042, ang);
	float limb = smoothstep(0.0062, 0.0052, ang);          // slight limb darkening
	float corona = exp(-ang * 90.0);
	float glare = exp(-ang * 13.0) * 0.4;
	float halo = exp(-ang * 2.2) * 0.05;
	vec3 ref_up = abs(sdn.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 tx = normalize(cross(ref_up, sdn));
	vec3 ty = cross(sdn, tx);
	float phi = atan(dot(d, ty), dot(d, tx));
	// six short spokes. exp(-ang * 11) reached ~17 deg and turned the star into
	// a lens-flare starburst that dominated the frame
	float rays = pow(abs(cos(phi * 3.0)), 16.0) * exp(-ang * 42.0) * 0.55;
	vec3 sun_col = mix(sun_tint, vec3(1.0), 0.75) * disc * (60.0 - limb * 12.0)
		+ sun_tint * (corona * 3.0 + glare * 0.5 + rays + halo);

	COLOR = vec4(neb + stars + galaxies + sun_col + vec3(0.004, 0.005, 0.010), 1.0);
}
