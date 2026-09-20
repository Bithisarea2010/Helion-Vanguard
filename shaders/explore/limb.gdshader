shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;
uniform vec3 sun_direction = vec3(0.4,0.65,0.2);
varying vec3 radial;
void vertex() { radial = normalize(MODEL_NORMAL_MATRIX * NORMAL); }
void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL),VIEW)),3.4);
	float lit = smoothstep(-0.2,0.4,dot(radial,sun_direction));
	ALBEDO = mix(vec3(0.8,0.18,0.07),vec3(0.10,0.40,0.95),lit) * rim;
	ALPHA = rim * lit * 0.45;
}
