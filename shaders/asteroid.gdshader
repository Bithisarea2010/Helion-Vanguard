shader_type spatial;
render_mode cull_back, specular_schlick_ggx;
// Helion Vanguard — shared asteroid surface. One material for all four rock
// variants, with procedural object-space detail so 1,280-triangle rocks read as
// pitted, cratered stone up close and still hold a silhouette at 3 km.
//
// All added cost is per-pixel ALU, which this game has in abundance: profiling
// showed frame time is CPU-bound and identical at 640x360 and 1920x1080.
//
// Per-instance variation comes through INSTANCE_CUSTOM, which AsteroidField
// packs as (hue roll, brightness roll, crater seed, ice roll). Without it 1,700
// rocks cut from four meshes read as four rocks repeated 425 times.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 tint : source_color = vec3(0.70, 0.66, 0.61);
uniform vec3 cavity_tint : source_color = vec3(0.20, 0.17, 0.15);
uniform vec3 warm_tint : source_color = vec3(0.78, 0.58, 0.40);   // iron-rich rock
uniform vec3 cold_tint : source_color = vec3(0.56, 0.60, 0.68);   // grey-blue silicate
uniform vec3 ice_tint : source_color = vec3(0.82, 0.90, 1.00);    // volatile deposits
uniform float detail_scale = 1.1;
uniform float detail_strength : hint_range(0.0, 3.0) = 1.35;
uniform float crater_strength : hint_range(0.0, 2.0) = 1.0;
uniform float rim_strength : hint_range(0.0, 4.0) = 0.9;
uniform vec3 rim_color : source_color = vec3(0.30, 0.42, 0.72);
uniform float fill_light : hint_range(0.0, 1.0) = 0.16;  // keeps unlit sides readable
uniform float fade_start = 700.0;   // procedural detail fades out past this
uniform float fade_end = 2600.0;

varying vec3 v_obj;
varying float v_freq;
varying vec4 v_inst;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
		mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
		mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm4(vec3 p) {
	float a = 0.5;
	float r = 0.0;
	for (int i = 0; i < 4; i++) {
		r += a * vnoise(p);
		p = p * 2.07 + vec3(5.1);
		a *= 0.5;
	}
	return r;
}

// Bowl-shaped craters on a jittered lattice. One cell plus its 8 in-plane
// neighbours would be a full Worley pass; sampling only the nearest cell and
// its 2x2x2 corner set keeps it to 8 hashes and the artefacts fall below the
// noise floor once the fbm is layered on top.
float craters(vec3 p, float seed) {
	vec3 i = floor(p);
	vec3 f = p - i;
	float acc = 0.0;
	for (int k = 0; k < 8; k++) {
		vec3 o = vec3(float(k & 1), float((k >> 1) & 1), float((k >> 2) & 1));
		vec3 c = i + o;
		vec3 jitter = vec3(hash13(c + seed), hash13(c + seed + 17.0), hash13(c + seed + 39.0));
		float d = length(f - o - (jitter - 0.5) * 0.75);
		// only about a third of cells actually hold a crater
		float present = step(0.63, hash13(c + seed + 71.0));
		float r = mix(0.18, 0.46, hash13(c + seed + 5.0));
		float t = clamp(d / r, 0.0, 1.0);
		// floor -> wide low ejecta rim -> flat. Both terms reach exactly 0 at
		// t = 1, so SUMMING overlapping craters stays continuous.
		//
		// Picking the nearest crater instead (the obvious implementation) is
		// not: the winner flips between adjacent pixels, and since the bump
		// normal comes from dFdx/dFdy of this height, that step became an
		// infinite gradient — a hard dark circle outlining every crater, which
		// read as decals stamped on the rock rather than as dents in it.
		acc += present * (-(1.0 - t * t) * 0.75
			+ smoothstep(0.45, 0.9, t) * (1.0 - smoothstep(0.9, 1.0, t)) * 0.3);
	}
	return acc;
}

void vertex() {
	v_obj = VERTEX;
	// MultiMesh bakes each rock's scale into the model matrix. Scaling the noise
	// frequency by it keeps crater size roughly constant in world space, so a
	// 60 m boulder does not look like a smeared copy of a 2 m pebble.
	float inst_scale = length(MODEL_MATRIX[0].xyz);
	v_freq = detail_scale * mix(1.0, inst_scale, 0.8);
	v_inst = INSTANCE_CUSTOM;
}

void fragment() {
	// per-rock mineral mix, so neighbouring rocks are not the same grey
	vec3 mineral = mix(cold_tint, warm_tint, v_inst.x);
	// keep the variation subtle: at 0.75 blend and 1.55 gain the rocks read as
	// tinted plastic instead of as stone that happens to differ slightly
	vec3 base = texture(albedo_tex, UV).rgb * tint * mix(vec3(1.0), mineral * 1.45, 0.4);
	base *= 0.82 + 0.34 * v_inst.y;
	float dist = length(VERTEX);
	float detail_fade = 1.0 - smoothstep(fade_start, fade_end, dist);
	vec3 n = normalize(NORMAL);
	if (detail_fade > 0.002) {
		float seed = v_inst.z * 64.0;
		vec3 q = v_obj * v_freq;
		// ONE height evaluation. The first version of this shader sampled the
		// field four times (value + three offsets) to build a gradient;
		// asteroids cover most of the screen in the belt missions, so that was
		// the single most expensive thing in the frame. Screen-space
		// derivatives of one sample give the same bump for the cost of a
		// quad-neighbour fetch (Mikkelsen surface gradients).
		vec3 warp = vec3(vnoise(q * 0.5 + seed), vnoise(q * 0.5 + seed + 3.3),
			vnoise(q * 0.5 + seed + 7.7)) - 0.5;
		float rough_form = fbm4(q + warp * 1.6);
		float crat = craters(q * 0.42 + seed, seed) * crater_strength;
		float h0 = rough_form + crat * 0.55;
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 r1 = cross(dpdy, n);
		vec3 r2 = cross(n, dpdx);
		float det = dot(dpdx, r1);
		vec3 sgrad = sign(det) * (dFdx(h0) * r1 + dFdy(h0) * r2);
		n = normalize(abs(det) * n - (detail_strength * detail_fade * 0.5) * sgrad);
		NORMAL = n;
		// crater floors and cracks go dark and smooth; ejecta rims go pale and
		// dusty, which is what actually sells the shape at a distance
		float cav = smoothstep(0.62, 0.24, rough_form) + clamp(-crat, 0.0, 1.0) * 0.8;
		cav = clamp(cav, 0.0, 1.0);
		float rim_dust = clamp(crat, 0.0, 1.0);
		float speck = vnoise(q * 7.0);
		base = mix(base, base * cavity_tint * 2.2, cav * 0.5 * detail_fade);
		base = mix(base, base * 1.35, rim_dust * 0.35 * detail_fade);
		base *= 0.9 + 0.2 * speck * detail_fade;
		// Volatile deposits, on a minority of rocks only, in broad patches. Two
		// earlier masks failed here: high-frequency speckle made the belt look
		// like blue-and-white camouflage, and the fbm form made it look flecked
		// with bird droppings. Only a low-frequency field gives deposits.
		float ice = smoothstep(0.86, 0.99, v_inst.w)
			* smoothstep(0.46, 0.68, vnoise(q * 0.28 + seed));
		base = mix(base, ice_tint * 0.7, ice * 0.25 * detail_fade);
		ROUGHNESS = clamp(0.80 + 0.16 * (rough_form - 0.5) - 0.14 * cav - 0.2 * ice, 0.28, 1.0);
	} else {
		ROUGHNESS = 0.84;
	}
	ALBEDO = base;
	METALLIC = 0.0;
	SPECULAR = 0.24;
	// nebula-tinted rim so unlit silhouettes still separate from black space
	// exponent 4, not 3: at 3 the tint crept well off the silhouette and washed
	// whole faces of the big boulders blue
	float fres = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 4.0);
	// plus a flat ambient term: the belt has one star and no bounce, so without
	// it every rock facing away from it was a pure black hole in the frame
	EMISSION = rim_color * fres * rim_strength * 0.35 + base * fill_light;
}
