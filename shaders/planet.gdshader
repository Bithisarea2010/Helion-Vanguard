shader_type spatial;
render_mode cull_back, shadows_disabled, unshaded;
// =============================================================================
// Helion Vanguard — planet.
//
// Fully self-lit against an explicit sun direction rather than relying on the
// scene's DirectionalLight3D: planets sit 8-30 km out, far outside the shadow
// and light-culling ranges tuned for dogfight scale, and driving the terminator
// from a uniform makes it exact and art-directable.
//
// Adds over the original banded-sphere shader: a real day/night terminator with
// warm scattering at the edge, weather-layer clouds with their own shadow, polar
// caps, night-side city lights on the rocky variant, specular sun glint on
// water, and a physically-shaped atmospheric limb that brightens toward the sun.
// One sphere per planet, 2-3 of them per mission: pure per-pixel cost.
// =============================================================================

uniform vec3 col_a : source_color = vec3(0.85, 0.55, 0.3);
uniform vec3 col_b : source_color = vec3(0.5, 0.25, 0.12);
uniform vec3 col_c : source_color = vec3(0.95, 0.85, 0.7);
uniform vec3 atmo : source_color = vec3(0.5, 0.7, 1.0);
uniform float band_freq = 9.0;
uniform float turbulence = 1.4;
uniform float atmo_power = 3.0;
uniform float atmo_strength = 1.2;
uniform float rocky : hint_range(0.0, 1.0) = 0.0;

uniform vec3 sun_dir = vec3(0.45, 0.25, 0.6);       // direction TOWARD the sun
uniform vec3 sun_color : source_color = vec3(1.0, 0.93, 0.82);
uniform float exposure = 1.6;
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.55;
uniform float city_lights : hint_range(0.0, 1.0) = 0.0;
uniform float ice_caps : hint_range(0.0, 1.0) = 0.0;
uniform float water_level : hint_range(0.0, 1.0) = 0.0;
uniform float spin = 0.004;                          // radians/second

varying vec3 v_obj;
varying vec3 v_world_n;

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
		p = p * 2.1 + vec3(3.7);
		a *= 0.5;
	}
	return r;
}

vec3 rot_y(vec3 p, float a) {
	float s = sin(a);
	float c = cos(a);
	return vec3(p.x * c - p.z * s, p.y, p.x * s + p.z * c);
}

void vertex() {
	v_obj = normalize(VERTEX);
	v_world_n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 p = normalize(v_obj);
	vec3 n = normalize(v_world_n);
	vec3 L = normalize(sun_dir);

	// ---------------------------------------------------------------- surface
	// `rocky` is a per-planet uniform, so these branches are uniform across the
	// draw and cost nothing to skip. Evaluating BOTH the gas-giant and the
	// terrestrial paths for every pixel (as the first version did) doubled the
	// noise bill on the largest objects on screen.
	vec3 base;
	float cap = 0.0;
	float shininess = 0.0;
	float land_h = 0.0;
	if (rocky < 0.5) {
		float turb = fbm(p * 3.0, 4) * turbulence;
		float bands = sin((p.y + turb * 0.35) * band_freq) * 0.5 + 0.5;
		float detail = fbm(p * 6.0, 3);
		base = mix(col_a, col_b, bands);
		base = mix(base, col_c, pow(detail, 2.6) * 0.8);
		// storm ovals in the gas bands, reusing the turbulence field
		float storm = smoothstep(0.66, 0.90, turb / max(turbulence, 0.001));
		base = mix(base, col_c * 1.15, storm * 0.5);
	} else {
		// continents, seas and mountain speckle instead of bands
		land_h = fbm(p * 3.4 + vec3(11.0), 4);
		float sea = smoothstep(water_level + 0.02, water_level - 0.02, land_h);
		base = mix(col_b, col_a, smoothstep(0.35, 0.65, land_h * 1.2));
		base = mix(base, col_c, pow(fbm(p * 14.0, 2), 3.0));
		if (water_level > 0.001) {
			vec3 ocean = mix(col_a * 0.25, col_a * 0.55, smoothstep(0.0, 0.35, land_h));
			base = mix(base, ocean, sea);
			shininess = sea;
		}
		if (ice_caps > 0.001) {
			cap = smoothstep(0.62, 0.86, abs(p.y) + land_h * 0.12) * ice_caps;
			base = mix(base, vec3(0.90, 0.94, 0.98), cap);
			shininess *= 1.0 - cap;
		}
	}

	// ---------------------------------------------------------------- clouds
	float cl = 0.0;
	if (cloud_amount > 0.001) {
		vec3 cp = rot_y(p, TIME * spin) * 4.2;
		cl = smoothstep(0.50, 0.78, fbm(cp + vec3(fbm(cp * 0.6, 2) * 1.4), 4)) * cloud_amount;
	}

	// ---------------------------------------------------------- day and night
	float ndl = dot(n, L);
	// wide soft terminator; real planets do not have a knife edge because the
	// atmosphere scatters light past the geometric limb
	float day = smoothstep(-0.16, 0.22, ndl);
	// warm forward-scattered band right at the terminator
	float twilight = exp(-pow((ndl + 0.02) * 5.5, 2.0)) * 0.65;

	vec3 lit = base * sun_color * day;
	// clouds sit above the surface: they light up and cast a soft shadow down
	lit = mix(lit, vec3(0.92, 0.94, 0.98) * sun_color * day, cl * 0.85);
	lit *= 1.0 - cl * 0.25;
	lit += vec3(1.0, 0.55, 0.28) * twilight * (0.35 + cl * 0.5);

	// sun glint off water
	if (shininess > 0.001) {
		vec3 V = normalize(-VERTEX);
		vec3 Lv = normalize((VIEW_MATRIX * vec4(L, 0.0)).xyz);
		vec3 Nv = normalize(NORMAL);
		float spec = pow(max(dot(reflect(-Lv, Nv), V), 0.0), 90.0);
		lit += sun_color * spec * shininess * (1.0 - cl) * 1.6 * day;
	}

	// night side: starlight/nebula fill so a backlit world still reads as a
	// sphere instead of the flat black hole punched in the sky it used to be
	float night = 1.0 - day;
	lit += base * 0.10 * night;
	if (city_lights > 0.001) {
		float pop = smoothstep(0.55, 0.80, land_h) * (1.0 - shininess) * (1.0 - cap);
		float grid = smoothstep(0.60, 0.95, fbm(p * 26.0 + vec3(7.0), 2));
		lit += vec3(1.0, 0.80, 0.45) * pop * grid * night * city_lights * 1.4 * (1.0 - cl * 0.8);
	}

	// ------------------------------------------------------------- atmosphere
	// limb glow: strongest where the line of sight grazes the surface AND the
	// atmosphere is lit, so the crescent wraps the day side
	vec3 Vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(n, Vw), 0.0, 1.0), atmo_power);
	float atmo_lit = smoothstep(-0.35, 0.45, ndl);
	vec3 air = atmo * fres * atmo_strength * (0.22 + atmo_lit * 1.25);
	air += vec3(1.0, 0.62, 0.36) * fres * twilight * atmo_strength * 0.9;

	// Forward scattering. When the planet sits between the camera and the sun it
	// is not a black disc — the atmosphere lights up into a brilliant ring,
	// brightest on the limb nearest the star. This is the single thing that
	// makes a backlit world read as a world.
	// -Vw is the camera's view direction; when it points at the sun the planet
	// is eclipsing the star and the atmosphere should blaze
	float back = clamp(dot(-Vw, L), 0.0, 1.0);
	float limb = pow(1.0 - clamp(dot(n, Vw), 0.0, 1.0), 7.0);
	float ring_side = smoothstep(-0.55, 0.35, ndl);
	air += mix(atmo, vec3(1.0, 0.85, 0.66), 0.45) * limb
		* (0.35 + ring_side * 2.4) * back * back * atmo_strength * 2.6;

	// `unshaded` discards EMISSION entirely — the final colour has to go to
	// ALBEDO, which still carries above 1.0 into the HDR buffer for the bloom.
	ALBEDO = (lit + air) * exposure;
}
