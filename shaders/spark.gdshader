shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Helion Vanguard — additive particle billboard for sparks, embers, impacts.
//
// Replaces a StandardMaterial3D + GradientTexture2D dot. That combination went
// wrong twice: BLEND_MODE_ADD does not switch on an alpha pipeline, so with the
// default TRANSPARENCY_DISABLED the texture's alpha was thrown away and every
// particle drew as a hard opaque square; and once transparency was enabled the
// radial GradientTexture2D fought the BILLBOARD_PARTICLES UV remap and produced
// bullseye rings. Computing the falloff from UV here removes the texture, the
// remap and the ambiguity, and costs less than the fetch it replaces.

uniform float softness : hint_range(0.5, 6.0) = 2.4;
uniform float core : hint_range(0.0, 1.0) = 0.30;   // fraction that stays full

void vertex() {
	// standard particle billboard: keep the camera basis, keep the per-particle
	// scale that the process material baked into MODEL_MATRIX
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;      // 0 centre, 1 at edge midpoint
	float t = clamp((r - core) / max(1.0 - core, 0.001), 0.0, 1.0);
	float a = pow(1.0 - t, softness);
	ALBEDO = COLOR.rgb;
	ALPHA = a * COLOR.a;
}
