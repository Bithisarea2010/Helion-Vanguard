shader_type spatial;
render_mode cull_disabled;
uniform sampler2D foliage_noise : filter_linear_mipmap, repeat_enable;
uniform float wind_strength=0.4;
varying float foliage;
void vertex() {
	foliage=COLOR.a;
	VERTEX.x+=sin(TIME*1.4+MODEL_MATRIX[3].x*0.1+VERTEX.y*0.7)*min(VERTEX.y*0.02,0.18)*wind_strength*foliage;
}
void fragment() {
	float grain=texture(foliage_noise,UV*vec2(7.0,3.0)).r;
	ALBEDO=COLOR.rgb*mix(0.7,1.2,grain);
	ROUGHNESS=0.95;
	SPECULAR=0.1;
	BACKLIGHT=COLOR.rgb*0.2;
}
