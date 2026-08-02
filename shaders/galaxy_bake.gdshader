shader_type canvas_item;
// =============================================================================
// Helion Vanguard — Andromeda (M31), baked ONCE to a square texture at load.
//
// Why this is not in the sky panorama: the sky bakes a full sphere into
// 4096x2048, which is ~0.09 deg per texel. A galaxy spanning 26 deg of sky would
// get ~290 texels across and read as a smudge no matter how good the maths is.
// A dedicated 2048² card covering the same 26 deg is ~0.013 deg per texel —
// roughly seven times finer — so the dust lanes and star clouds survive all the
// way into photo mode. Both bakes cost one frame at mission load and nothing
// afterwards.
//
// Structure, following the real M31:
//   * inclination 77 deg — nearly edge-on, which is why it reads as a lens
//   * de Vaucouleurs bulge, exponential disc
//   * two logarithmic spiral arms at ~12 deg pitch, plus a flocculent component
//   * the prominent dust ring, offset from the arms and DARKER than the disc
//   * pink HII knots along the arms, blue OB associations between them
//   * a resolved-star layer that keeps producing individual points down to the
//     texel — this is what makes it read as billions of stars rather than paint
//   * globular halo, and the M32 / M110 satellites
// =============================================================================

uniform float inclination_deg = 77.0;
uniform float position_angle_deg = 38.0;
// Windings of the arm pattern across the visible disc, NOT the astronomical
// pitch angle. Deriving the log-spiral rate from a 12 deg pitch gives
// log(r)/tan(12 deg) ~ 4.7 radians per e-fold, which over the disc's radius
// range is about six full turns — the galaxy came out as a set of concentric
// rings. Real grand-design spirals show roughly one and a half.
uniform float winding = 2.6;
uniform float brightness : hint_range(0.0, 4.0) = 1.0;
uniform vec3 core_color : source_color = vec3(1.0, 0.86, 0.62);
uniform vec3 arm_color : source_color = vec3(0.72, 0.82, 1.0);
uniform vec3 hii_color : source_color = vec3(1.0, 0.42, 0.55);
uniform vec3 dust_color : source_color = vec3(0.24, 0.15, 0.11);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x),
		mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p, int oct) {
	float a = 0.5;
	float r = 0.0;
	for (int i = 0; i < oct; i++) {
		r += a * vnoise(p);
		p = p * 2.07 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return r;
}

// A patch of resolved stars: dense enough that individual points survive at
// texel scale, weighted so the brightest ones are rare.
float star_field(vec2 p, float scale, float thresh) {
	vec2 sp = p * scale;
	vec2 cell = floor(sp);
	float h = hash12(cell);
	if (h < thresh) {
		return 0.0;
	}
	vec2 jit = vec2(hash12(cell + 5.1), hash12(cell + 9.7)) * 0.7 + 0.15;
	float d = length(fract(sp) - jit);
	float m = smoothstep(0.30, 0.0, d);
	return m * m * (h - thresh) / (1.0 - thresh);
}

void fragment() {
	// screen coords, -1..1, centred
	vec2 uv = (UV - 0.5) * 2.0;

	float pa = radians(position_angle_deg);
	float cs = cos(pa);
	float sn = sin(pa);
	vec2 rot = vec2(uv.x * cs - uv.y * sn, uv.x * sn + uv.y * cs);

	// de-project: the disc is a circle seen at `inclination`, so undo the
	// foreshortening along the minor axis to get true disc-plane radius
	float cos_i = max(cos(radians(inclination_deg)), 0.08);
	vec2 disc = vec2(rot.x, rot.y / cos_i);
	float r = length(disc);
	float theta = atan(disc.y, disc.x);

	// --- bulge + disc ------------------------------------------------------
	// de Vaucouleurs r^(1/4): a plain exponential gives a bulge that is far too
	// soft, and the nucleus is the brightest thing in the frame
	float bulge = exp(-7.67 * (pow(max(r, 0.001) / 0.115, 0.25) - 1.0)) * 0.06;
	float nucleus = exp(-r * 90.0) * 0.9;
	float disc_i = exp(-r / 0.30) * smoothstep(1.15, 0.55, r);

	// --- spiral arms -------------------------------------------------------
	float phase = theta - log(max(r, 0.02)) * winding;
	// the two arms are not identical: a pure cos(2x) is visibly synthetic
	float arm = 0.5 + 0.5 * cos(2.0 * phase + 0.30 * sin(phase));
	arm = pow(arm, 2.2);
	// flocculent break-up and spurs: real arms are not two clean sinusoids
	arm *= 0.45 + 0.85 * fbm(disc * 5.5 + vec2(11.0), 4);
	arm += 0.22 * pow(max(0.5 + 0.5 * cos(4.0 * phase + 1.1), 0.0), 4.0)
		* fbm(disc * 9.0 + vec2(53.0), 3);
	float arm_i = arm * disc_i * 2.1;

	// --- the dust ring -----------------------------------------------------
	// M31's signature: a dark ring at ~0.45 disc radii, offset in phase from the
	// arms so the lanes sit on the inner edge of the bright material
	float ring = exp(-pow((r - 0.46) / 0.085, 2.0));
	float dust_spiral = 0.5 + 0.5 * cos(2.0 * (phase + 0.55));
	float dust = clamp(ring * (0.35 + 0.75 * pow(dust_spiral, 2.0))
		* (0.6 + 0.7 * fbm(disc * 8.0 + vec2(41.0), 3)), 0.0, 1.0);
	dust += 0.35 * exp(-pow((r - 0.72) / 0.07, 2.0)) * pow(dust_spiral, 2.0);

	// --- populations -------------------------------------------------------
	// HII knots ride the arms; OB associations sit slightly outside them
	float knots = star_field(disc, 78.0, 0.982) * arm * disc_i;
	float ob = star_field(disc + vec2(7.3), 130.0, 0.988) * arm * disc_i;
	// the resolved field: three scales so points keep appearing as you zoom
	float res = star_field(disc, 210.0, 0.9905) * 0.55
		+ star_field(disc + vec2(3.1), 420.0, 0.9945) * 0.35
		+ star_field(disc + vec2(9.7), 820.0, 0.9975) * 0.22;
	res *= (bulge * 6.0 + disc_i * 1.4 + arm_i * 0.8);

	// --- halo + globular clusters -----------------------------------------
	float halo = exp(-r * 2.6) * 0.045;
	float globs = star_field(rot * 1.0, 46.0, 0.9965) * exp(-length(rot) * 2.2) * 0.5;

	// --- satellites: M32 (compact) and M110 (diffuse) ----------------------
	float m32 = exp(-pow(length(rot - vec2(0.30, -0.20)) / 0.030, 1.6)) * 0.55;
	float m110 = exp(-pow(length(rot - vec2(-0.26, 0.34)) / 0.075, 1.5)) * 0.22;

	// --- compose ------------------------------------------------------------
	vec3 col = core_color * (bulge + nucleus + m32 + halo * 0.8);
	col += mix(core_color, arm_color, 0.75) * (disc_i * 0.55 + arm_i);
	col += arm_color * (ob * 2.2 + res * 1.5);
	col += hii_color * knots * 3.4;
	col += core_color * (globs + m110);

	// dust extinction multiplies what is BEHIND it and adds its own faint
	// reddened emission — a purely subtractive lane goes black and looks like a
	// hole punched in the galaxy
	col *= (1.0 - dust * 0.82);
	col += dust_color * dust * 0.10;

	col *= brightness;
	// alpha carries luminance so the card can be alpha-blended if additive ever
	// proves too hot against a bright nebula
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	COLOR = vec4(col, clamp(lum * 3.0, 0.0, 1.0));
}
