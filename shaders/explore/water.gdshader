shader_type spatial;
render_mode cull_disabled;
uniform float wind_strength=1.0;
varying vec3 radial;
void vertex() { radial=normalize(VERTEX); }
void fragment() {
	float detail_fade=1.0-smoothstep(0.2,1.0,length(fwidth(radial*3200.0)));
	float wave=sin(radial.x*3200.0+TIME*1.3)*sin(radial.z*2900.0-TIME*0.8)*detail_fade;
	float fresnel=pow(1.0-clamp(dot(NORMAL,VIEW),0.0,1.0),4.0);
	ALBEDO=mix(vec3(0.008,0.075,0.095),vec3(0.16,0.30,0.36),fresnel)+wave*0.012*wind_strength;
	ROUGHNESS=0.18+abs(wave)*0.12;
	METALLIC=0.3;
	NORMAL=normalize(NORMAL+vec3(wave*0.065*wind_strength,cos(radial.z*8500.0+TIME)*0.045,0));
}
