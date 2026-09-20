shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float heat=0.0;
varying vec3 local;
void vertex() { local=VERTEX; }
void fragment() {
	float streak=pow(0.5+0.5*sin(local.x*7.0+local.y*4.0+TIME*28.0),3.0);
	float rim=pow(1.0-abs(dot(NORMAL,VIEW)),2.4);
	float front=1.0-smoothstep(-2.0,4.5,local.z);
	vec3 hot=mix(vec3(1.0,0.12,0.015),vec3(0.18,0.36,1.0),smoothstep(1.0,3.0,heat));
	ALBEDO=hot*3.0;
	ALPHA=clamp(heat*0.7,0.0,0.85)*front*(rim*0.65+streak*0.12);
}
