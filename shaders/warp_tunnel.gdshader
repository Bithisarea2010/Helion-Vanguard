shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never, shadows_disabled;
// =============================================================================
// Helion Vanguard — lightspeed tunnel.
//
// One open cylinder wrapped around the camera, seen from the inside
// (`cull_front`). Everything is a function of the tube's own UV, so the cost is
// bounded by the silhouette and there is no particle simulation, no overdraw
// stack and no per-frame CPU work beyond writing `warp`.
//
// Depth TEST is deliberately left on. The tube's radius is larger than the
// chase-camera standoff, so the player's hull sits inside it and occludes the
// far wall exactly the way it should — a depth-disabled tunnel painted straight
// over the ship and the set piece lost its subject.
//
// Layers, cheapest first:
//   * tube wall glow — a soft along-length gradient, the "throat" of the tunnel
//   * three star-filament layers at different angular densities and speeds,
//     each streak a sharp head with an exponential tail
//   * a chromatic leading edge: the head of every filament is shifted toward
//     cyan and its tail toward magenta, which is what sells the velocity
//   * a breach ring that sweeps the length once when the drive engages
// =============================================================================

uniform float warp : hint_range(0.0, 1.0) = 0.0;      // master intensity
uniform float speed : hint_range(0.0, 4.0) = 1.0;     // filament scroll rate
uniform float breach : hint_range(0.0, 1.0) = 0.0;    // one-shot entry ring
uniform vec3 core_tint : source_color = vec3(0.72, 0.90, 1.0);
uniform vec3 edge_tint : source_color = vec3(0.35, 0.30, 1.0);
uniform vec3 hot_tint : source_color = vec3(1.0, 0.86, 0.72);

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

// One layer of angular filaments. `dens` is streak count around the tube.
float filaments(vec2 uv, float dens, float rate, float phase, out float head) {
	float a = uv.x * dens;
	float cell = floor(a);
	float fa = fract(a) - 0.5;
	float h = hash11(cell + phase);
	float h2 = hash11(cell + phase + 91.7);
	// thin streaks with a variable width; the narrow ones read as distant stars
	float width = 0.035 + 0.30 * h * h;
	float band = smoothstep(width, 0.0, abs(fa));
	if (band <= 0.0) {
		head = 0.0;
		return 0.0;
	}
	// sharp head, exponential tail: pow() on a sawtooth is far cheaper than the
	// exp() a physically-derived tail would need and is visually identical here
	float f = fract(uv.y - TIME * rate * (0.55 + 0.9 * h2) + h * 7.31);
	float tail = pow(1.0 - f, mix(26.0, 5.0, h));
	head = pow(1.0 - f, 90.0) * band;
	return tail * band * (0.35 + 0.9 * h2);
}

void fragment() {
	vec2 uv = UV;
	// --- tube wall: bright at the far end (the "throat"), dark at the near end
	float along = uv.y;
	float throat = smoothstep(0.0, 0.55, along) * smoothstep(1.0, 0.72, along);
	float wall = throat * 0.18;

	// --- three filament layers -------------------------------------------
	float h1; float h2; float h3;
	float s1 = filaments(uv, 130.0, 1.7 * speed, 0.0, h1);
	float s2 = filaments(uv, 64.0, 1.15 * speed, 41.0, h2);
	float s3 = filaments(uv, 28.0, 0.78 * speed, 173.0, h3);
	float streaks = s1 * 0.55 + s2 * 0.85 + s3 * 1.25;
	float heads = h1 * 0.6 + h2 * 1.0 + h3 * 1.6;

	// --- chromatic split: heads run cyan-white, tails fall to violet -------
	vec3 col = mix(edge_tint, core_tint, clamp(streaks * 1.6, 0.0, 1.0));
	col = mix(col, hot_tint, clamp(heads, 0.0, 1.0));
	vec3 rgb = col * (streaks * 2.6 + heads * 5.0) + core_tint * wall;

	// --- entry shock ring sweeping the tube once --------------------------
	if (breach > 0.001) {
		float ring = smoothstep(0.10, 0.0, abs(along - (1.0 - breach)));
		rgb += vec3(1.0) * ring * breach * 6.0;
	}

	// warp scales brightness superlinearly so the spool ramp feels like a
	// charge rather than a dimmer
	float w = warp * warp * (3.0 - 2.0 * warp);
	ALBEDO = rgb * w;
	ALPHA = clamp((streaks + heads * 2.0 + wall) * w, 0.0, 1.0);
}
