shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Helion Vanguard — pooled tracer rounds, drawn as ONE MultiMesh.
//
// Every bullet in flight used to be its own MeshInstance3D: up to 320 nodes and,
// with distinct materials per weapon colour, up to 320 draw calls in a heavy
// furball. Colour and brightness now ride in INSTANCE_CUSTOM, so a single
// instanced draw covers the whole pool no matter how many weapons are firing.
//
// The capsule is unit-sized; the per-instance transform carries length, radius
// and orientation (length axis is +Y, matching CapsuleMesh).

varying vec4 v_tint;
varying vec3 v_local;

void vertex() {
	v_tint = INSTANCE_CUSTOM;
	v_local = VERTEX;
}

void fragment() {
	// hot core along the axis falling off to the weapon colour at the skin —
	// a flat additive capsule reads as a plastic pill at close range
	float radial = clamp(1.0 - length(v_local.xz) * 2.0, 0.0, 1.0);
	vec3 col = mix(v_tint.rgb, mix(v_tint.rgb, vec3(1.0), 0.75), radial * radial);
	ALBEDO = col * v_tint.a * (0.55 + 0.85 * radial);
	ALPHA = 1.0;
}
