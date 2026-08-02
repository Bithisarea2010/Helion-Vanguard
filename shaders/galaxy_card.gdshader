shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Helion Vanguard — the quad that carries a baked galaxy.
//
// Additive, so it stacks correctly on the nebula behind it, and depth-tested so
// planets and hulls still occlude it. The only per-pixel work is one texture
// fetch plus a soft edge, because all the structure was baked in one frame at
// mission load (see `shaders/galaxy_bake.gdshader`).

uniform sampler2D galaxy_tex : source_color, filter_linear_mipmap;
uniform float gain : hint_range(0.0, 4.0) = 1.0;

void fragment() {
	vec4 t = texture(galaxy_tex, UV);
	// feather the card boundary; a hard rectangle edge against a starfield is
	// the single most obvious way to give away that a sky object is a billboard
	vec2 d = abs(UV - 0.5) * 2.0;
	float edge = (1.0 - smoothstep(0.80, 1.0, d.x)) * (1.0 - smoothstep(0.80, 1.0, d.y));
	ALBEDO = t.rgb * gain * edge;
	ALPHA = 1.0;
}
