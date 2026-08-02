shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Helion Vanguard — speed dust. Each instance is a static lattice point; this
// shader wraps it into the box travelling with the player and stretches it
// along the velocity vector, so the CPU only pushes three uniforms per frame.

uniform vec3 vel_dir = vec3(0.0, 0.0, -1.0);
uniform float stretch = 1.0;
uniform float range_half = 130.0;
uniform vec3 origin = vec3(0.0);
uniform vec3 dust_color : source_color = vec3(0.60, 0.68, 0.82);

varying float v_fade;

void vertex() {
	// The node rides with the player, so the instance's local translation is the
	// mote's fixed lattice point. Subtracting the player position INSIDE the mod
	// is what makes the motes world-static and the ship fly through them.
	vec3 lattice = MODEL_MATRIX[3].xyz - origin;
	vec3 span = vec3(range_half * 2.0);
	vec3 inst = mod(lattice - origin + vec3(range_half), span) - vec3(range_half);

	// build an orthonormal frame with +Z along velocity, then scale Z by stretch
	vec3 bz = normalize(vel_dir);
	vec3 up = abs(bz.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 bx = normalize(cross(up, bz));
	vec3 by = cross(bz, bx);
	vec3 local = VERTEX;
	vec3 world_off = bx * local.x + by * local.y + bz * (local.z * stretch);

	VERTEX = inst + world_off;
	// fade motes near the box edge so they do not pop when they wrap
	float edge = max(max(abs(inst.x), abs(inst.y)), abs(inst.z)) / range_half;
	v_fade = 1.0 - smoothstep(0.72, 1.0, edge);
}

void fragment() {
	ALBEDO = dust_color * v_fade;
	ALPHA = v_fade;
}
