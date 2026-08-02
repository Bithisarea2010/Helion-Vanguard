shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Helion Vanguard — expanding fireball shell for FX.explosion().
//
// One sphere per blast instead of a stack of additive billboards. Billboards
// were the previous approach everywhere in this game and they always failed the
// same way: the sum saturates past 1.0 across the whole quad, so the soft
// texture clips into a hard-edged brick (see ExhaustPlume for the same lesson).
// A single shell has no self-overdraw, so it can hold a real colour ramp.
//
// NOTE: `render_mode unshaded` DISCARDS EMISSION in Godot 4.7. The final colour
// must go to ALBEDO; values above 1.0 still reach the HDR buffer and bloom.

uniform float life : hint_range(0.0, 1.0) = 0.0;   // 0 = ignition, 1 = burnt out
uniform float seed = 0.0;
uniform float turbulence : hint_range(0.0, 2.0) = 1.0;
uniform float intensity = 1.0;
uniform vec3 hot : source_color = vec3(1.00, 0.96, 0.80);
uniform vec3 mid : source_color = vec3(1.00, 0.42, 0.07);
uniform vec3 cool : source_color = vec3(0.30, 0.04, 0.01);

varying vec3 v_dir;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = p - i;
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
		p = p * 2.11 + vec3(4.7);
		a *= 0.5;
	}
	return r;
}

void vertex() {
	v_dir = normalize(VERTEX);
	// boil the shell outward so the silhouette is lumpy rather than a clean ball
	float n = fbm3(v_dir * 2.4 + vec3(seed) + vec3(0.0, life * 1.1, 0.0));
	VERTEX *= 1.0 + (n - 0.5) * turbulence * 0.5;
}

void fragment() {
	float n = fbm3(v_dir * 3.4 + vec3(seed * 1.7) + vec3(0.0, life * 1.8, 0.0));
	// facing dot is 1 at the centre of the disc, 0 at the silhouette edge. The
	// exponent rises with age, so the ball starts solid and hollows into a shell.
	float f = clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0);
	float shell = pow(f, mix(0.55, 2.6, life));
	// dissolve: holes open in the cooling gas and eat the fireball from inside
	float burn = smoothstep(0.10 + life * 0.72, 0.88, n);
	float a = shell * (1.0 - burn) * (1.0 - life * life);
	vec3 c = mix(hot, mid, smoothstep(0.0, 0.42, life));
	c = mix(c, cool, smoothstep(0.38, 1.0, life));
	ALBEDO = c * intensity * (0.55 + 1.6 * n);
	ALPHA = clamp(a, 0.0, 1.0);
}
