shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform float coverage = 0.55;
uniform vec3 sun_direction = vec3(0.4,0.65,0.2);
varying vec3 direction;
float hash(vec3 p) { return fract(sin(dot(p,vec3(12.9898,78.233,54.53)))*43758.5453); }
float noise(vec3 p) {
	vec3 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() { direction = normalize(VERTEX); }
void fragment() {
	vec3 p=direction*26.0+vec3(TIME*0.003,0,TIME*0.001);
	float n=noise(p)*0.65+noise(p*2.1)*0.25+noise(p*4.2)*0.1;
	float cloud=smoothstep(0.72-coverage*0.45,0.89-coverage*0.37,n);
	float lit=clamp(dot(direction,sun_direction)*0.65+0.45,0.12,1.0);
	ALBEDO=vec3(0.83,0.88,0.95)*lit;
	EMISSION=ALBEDO*0.22;
	ROUGHNESS=1.0;
	ALPHA=cloud*0.88;
}
