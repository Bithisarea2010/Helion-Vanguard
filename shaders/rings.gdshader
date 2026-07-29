shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_opaque, shadows_disabled;
// Helion Vanguard — planetary ring plane. A single quad; the annulus, its gaps
// and its density are all radial functions, so there is no ring geometry and no
// texture. Drawn unshaded because the parent planet is too far out for the
// scene's directional light budget.

uniform vec3 ring_color : source_color = vec3(0.78, 0.70, 0.56);
uniform float inner_frac : hint_range(0.0, 1.0) = 0.55;
uniform float outer_radius = 1.0;     // model-space radius of the ring edge
uniform float density : hint_range(0.0, 2.0) = 0.9;

varying vec2 v_plane;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	return fract((p + p) * p);
}

float bands(float r) {
	// layered sine octaves read as thousands of individual ringlets without any
	// texture fetch; the low frequencies carve the big Cassini-style divisions
	float v = 0.55
		+ 0.25 * sin(r * 240.0)
		+ 0.14 * sin(r * 91.0 + 1.7)
		+ 0.10 * sin(r * 37.0 + 4.1);
	float gap1 = smoothstep(0.015, 0.055, abs(r - 0.62));
	float gap2 = smoothstep(0.010, 0.030, abs(r - 0.79));
	float gap3 = smoothstep(0.008, 0.022, abs(r - 0.45));
	return clamp(v, 0.0, 1.0) * gap1 * gap2 * gap3;
}

void vertex() {
	v_plane = VERTEX.xz;
}

void fragment() {
	// PlaneMesh spans -size/2..+size/2 in model space, so outer_radius is size/2
	float r = length(v_plane) / max(outer_radius, 0.001);
	float t = (r - inner_frac) / max(1.0 - inner_frac, 0.001);
	if (t < 0.0 || t > 1.0) {
		discard;
	}
	float shape = bands(t);
	// soften both edges so the annulus does not end on a hard line
	shape *= smoothstep(0.0, 0.06, t) * (1.0 - smoothstep(0.90, 1.0, t));
	// grazing angles look through more material and read denser
	float graze = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float alpha = clamp(shape * density * (0.35 + graze * 0.9), 0.0, 0.95);
	ALBEDO = vec3(0.0);
	EMISSION = ring_color * (0.55 + shape * 0.9);
	ALPHA = alpha;
}
