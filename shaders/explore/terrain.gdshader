shader_type spatial;
render_mode cull_disabled;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform bool lunar = false;
uniform sampler2D micro_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
void fragment() {
	float grain = texture(micro_texture, UV * 0.027).r * 0.7 + texture(micro_texture, UV * 0.35).r * 0.3;
	float near_detail = 1.0 - smoothstep(80.0, 450.0, length(VERTEX));
	vec3 ground = texture(ground_albedo, UV / 3.2).rgb;
	float forest = smoothstep(0.0, 0.07, COLOR.g-COLOR.r) * (1.0-smoothstep(0.28,0.55,COLOR.r));
	vec3 soil = mix(COLOR.rgb * mix(0.65, 1.12, grain), ground * vec3(0.65,0.80,0.57), forest*near_detail*0.75);
	ALBEDO = soil * (1.0-wetness*0.35);
	ROUGHNESS = mix(0.95,0.28,wetness);
	if (near_detail>0.001 && !lunar) {
		vec3 map = texture(ground_normal,UV/3.2).xyz*2.0-1.0;
		vec3 dp1=dFdx(VERTEX), dp2=dFdy(VERTEX);
		vec2 duv1=dFdx(UV), duv2=dFdy(UV);
		vec3 t=cross(dp2,NORMAL)*duv1.x+cross(NORMAL,dp1)*duv2.x;
		vec3 b=cross(dp2,NORMAL)*duv1.y+cross(NORMAL,dp1)*duv2.y;
		float inv=inversesqrt(max(max(dot(t,t),dot(b,b)),0.000001));
		NORMAL=normalize(NORMAL+mat3(t*inv,b*inv,NORMAL)*vec3(map.xy*(1.0-smoothstep(4.0,25.0,length(VERTEX)))*0.22,0.0));
	}
}
