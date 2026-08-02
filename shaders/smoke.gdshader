shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// Helion Vanguard — alpha-blended particle billboard for smoke and dust.
// Same construction as spark.gdshader but mixed rather than added: additive
// smoke brightens the scene instead of obscuring it, which is the opposite of
// what smoke is for.

uniform float softness : hint_range(0.5, 6.0) = 1.6;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float r = clamp(length(UV - vec2(0.5)) * 2.0, 0.0, 1.0);
	ALBEDO = COLOR.rgb;
	ALPHA = pow(1.0 - r, softness) * COLOR.a;
}
