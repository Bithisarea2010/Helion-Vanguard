shader_type sky;
uniform vec3 sun_direction = vec3(0.4,0.65,0.2);
uniform vec3 up_direction = vec3(0,1,0);
uniform float altitude = 12000.0;
uniform float atmosphere_height = 9000.0;
uniform float overcast = 0.0;
void sky() {
	vec3 ray = normalize(EYEDIR);
	float height = dot(ray, up_direction);
	float sunlight = dot(normalize(sun_direction), up_direction);
	float mu = dot(ray, normalize(sun_direction));
	float air = exp(-max(altitude,0.0) / max(atmosphere_height * 0.25, 1.0));
	float optical = 1.0 / max(0.13, abs(height) + 0.10);
	vec3 rayleigh = vec3(0.14,0.38,0.82) * (0.75 + 0.75 * mu * mu);
	float mie = pow(max(mu,0.0),24.0) * 0.7;
	float day = smoothstep(-0.18,0.22,sunlight);
	vec3 haze = mix(vec3(0.85,0.24,0.09),vec3(0.48,0.63,0.78),smoothstep(0.02,0.45,sunlight));
	vec3 sky_color = mix(rayleigh, haze, clamp(optical * 0.12,0.0,0.85)) * (day * 0.85 + 0.03);
	sky_color += vec3(1.0,0.69,0.35) * mie * day;
	sky_color = mix(sky_color, vec3(0.26,0.31,0.37) * (day + 0.05), overcast * 0.7);
	vec3 cell = floor(ray * 650.0);
	float star = step(0.9991,fract(sin(dot(cell,vec3(12.91,78.23,43.1))) * 43758.54));
	vec3 space = vec3(0.001,0.002,0.006) + star * vec3(0.55,0.66,0.9);
	COLOR = mix(space,sky_color,clamp(air,0.0,1.0));
	COLOR += vec3(1.0,0.85,0.62) * smoothstep(0.99988,0.99997,mu) * 8.0 * (1.0-overcast*0.9);
}
