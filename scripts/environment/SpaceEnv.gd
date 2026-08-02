class_name SpaceEnv
extends Node3D
## Builds the world: sky, sun, planets, lighting, environment settings.

var world_env: WorldEnvironment
var sun_light: DirectionalLight3D
var sun_visual: MeshInstance3D
var deep_sky: DeepSky

## Named deep-sky objects every mission gets unless it overrides them.
##
## Andromeda is the hero: 26 deg across, inclined 77 deg, at a bearing that puts
## it high and off to port from the usual launch heading, so it is something the
## player finds by looking around rather than something parked on the crosshair.
## The two companions exist for depth — a sky with exactly one galaxy in it reads
## as a decal.
const DEFAULT_DEEP_SKY := [
	{"dir": Vector3(-0.52, 0.34, -0.78), "angular_deg": 26.0, "res": 2048,
		"inclination": 77.0, "position_angle": 38.0, "winding": 2.4,
		"brightness": 1.0, "gain": 1.0},
	# a face-on grand-design spiral, much smaller and further away
	{"dir": Vector3(0.72, 0.12, -0.68), "angular_deg": 7.0, "res": 1024,
		"inclination": 22.0, "position_angle": -14.0, "winding": 3.1,
		"brightness": 0.62, "gain": 0.85,
		"core": Color(1.0, 0.90, 0.72), "arm": Color(0.66, 0.80, 1.0)},
	# an edge-on lenticular, almost a sliver
	{"dir": Vector3(0.18, -0.42, 0.88), "angular_deg": 5.0, "res": 1024,
		"inclination": 86.0, "position_angle": 62.0, "winding": 1.8,
		"brightness": 0.5, "gain": 0.7,
		"core": Color(1.0, 0.82, 0.60), "arm": Color(0.85, 0.86, 0.95)},
]

func build(cfg: Dictionary) -> void:
	# ---- environment / sky
	world_env = WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/space_sky.gdshader")
	mat.set_shader_parameter("nebula_a", cfg.get("neb_a", Color(0.16, 0.05, 0.28)))
	mat.set_shader_parameter("nebula_b", cfg.get("neb_b", Color(0.02, 0.16, 0.30)))
	mat.set_shader_parameter("nebula_c", cfg.get("neb_c", Color(0.30, 0.10, 0.05)))
	mat.set_shader_parameter("nebula_intensity", cfg.get("neb_i", 1.0))
	sky.sky_material = mat
	# The sky drives every specular reflection on the hulls; 64 px was too coarse
	# to carry the nebula's colour into the metal. QUALITY mode is essential
	# here: the default re-derives the radiance cubemap EVERY frame, and at
	# 128 px that alone cost ~8 fps for a sky that never changes after its bake.
	var p: Dictionary = Game.preset()
	sky.radiance_size = [
		Sky.RADIANCE_SIZE_32, Sky.RADIANCE_SIZE_64,
		Sky.RADIANCE_SIZE_128, Sky.RADIANCE_SIZE_256,
	][clampi(int(Game.settings.preset), 0, 3)] as Sky.RadianceSize
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = cfg.get("ambient", Color(0.36, 0.40, 0.52))
	env.ambient_light_sky_contribution = 0.7
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# ACES holds highlight colour instead of racing everything bright to white,
	# which matters when the whole game is emissive engines and tracer fire
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 8.0
	env.glow_enabled = p.glow
	env.glow_intensity = 0.62 * float(p.glow_quality)
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	# a low threshold plus SCREEN blending lifted the entire frame toward white
	# and flattened the nebula; only genuinely over-range pixels should bloom
	env.glow_hdr_threshold = 1.35
	env.glow_hdr_scale = 2.0
	# a wide, gently-weighted mip stack reads as a lens bloom rather than the
	# hard halo a single strong level produces
	env.set_glow_level(1, 0.35)
	env.set_glow_level(2, 0.75)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 0.75)
	env.set_glow_level(5, 0.45)
	env.set_glow_level(6, 0.25)
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.12
	world_env.environment = env
	add_child(world_env)
	# ---- sun: rendered inside the sky shader (disc + corona + rays),
	# so it is correctly occluded by planets/asteroids and feeds the bloom.
	var sun_dir: Vector3 = cfg.get("sun_dir", Vector3(-0.45, -0.25, -0.6)).normalized()
	mat.set_shader_parameter("sun_dir", -sun_dir)
	var sun_col: Color = cfg.get("sun_color", Color(1.0, 0.88, 0.6))
	mat.set_shader_parameter("sun_tint", sun_col)
	sun_light = DirectionalLight3D.new()
	sun_light.light_color = cfg.get("sun_color", Color(1.0, 0.93, 0.82))
	# vacuum has one hard key light and almost no fill; a strong sun against a
	# modest ambient is what gives hulls their shape and keeps the paint colour
	sun_light.light_energy = 2.1
	sun_light.light_specular = 0.85
	sun_light.shadow_enabled = p.shadows
	# one split instead of two halves the shadow-pass geometry; at a 350 m shadow
	# distance the extra cascade bought nothing visible
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	# Shadow-casting geometry tripled with the greeble pass, and the shadow pass
	# re-draws every triangle in range. At dogfight scale nothing beyond ~350 m
	# reads as a shadow anyway, so this is free quality.
	sun_light.directional_shadow_max_distance = float(p.shadow_distance)
	add_child(sun_light)
	sun_light.look_at_from_position(Vector3.ZERO, sun_dir, Vector3.UP if absf(sun_dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT)
	# soft cool fill from the opposite side so ships never go pitch black
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.5, 0.65, 0.9)
	fill.light_energy = 0.5
	fill.shadow_enabled = false
	add_child(fill)
	fill.look_at_from_position(Vector3.ZERO, -sun_dir + Vector3(0.2, 0.3, 0.2), Vector3.UP)
	# ---- planets
	for pl in cfg.get("planets", []):
		_add_planet(pl, -sun_dir, cfg.get("sun_color", Color(1.0, 0.93, 0.82)))
	# ---- deep-sky objects that need more angular resolution than the panorama
	if not "--nodeep" in OS.get_cmdline_user_args():
		deep_sky = DeepSky.new()
		add_child(deep_sky)
		deep_sky.build.call_deferred(cfg.get("deep_sky", DEFAULT_DEEP_SKY))
	# bake the sky to a static panorama (huge GPU saving, cooler laptops)
	_bake_sky.call_deferred(env, cfg, -sun_dir, sun_col)

func _bake_sky(env: Environment, cfg: Dictionary, dir_to_sun: Vector3, sun_col: Color) -> void:
	var vp := SubViewport.new()
	# 2048x1024 across a full sphere is ~0.17 deg/texel, roughly 4x coarser than
	# a 1080p screen pixel at this FOV — which is why the old starfield was a
	# field of soft blobs. 4096 matches the screen closely enough; the bake still
	# happens exactly once per mission.
	vp.size = Game.preset().sky_size
	vp.disable_3d = true
	vp.use_hdr_2d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cr := ColorRect.new()
	cr.size = Vector2(vp.size)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/sky_bake.gdshader")
	m.set_shader_parameter("nebula_a", cfg.get("neb_a", Color(0.16, 0.05, 0.28)))
	m.set_shader_parameter("nebula_b", cfg.get("neb_b", Color(0.02, 0.16, 0.30)))
	m.set_shader_parameter("nebula_c", cfg.get("neb_c", Color(0.30, 0.10, 0.05)))
	m.set_shader_parameter("nebula_intensity", cfg.get("neb_i", 1.0))
	m.set_shader_parameter("sun_dir", dir_to_sun)
	m.set_shader_parameter("sun_tint", sun_col)
	cr.material = m
	vp.add_child(cr)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null:
		return
	# RGBE9995 keeps the HDR range the sun disc and bloom need at 4 bytes/texel
	# instead of the 8 that RGBAH costs — 33 MB rather than 67 MB of VRAM.
	img.convert(Image.FORMAT_RGBE9995)
	var tex := ImageTexture.create_from_image(img)
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = tex
	pano.filter = true
	if env.sky:
		env.sky.sky_material = pano

func _add_planet(pl: Dictionary, dir_to_sun: Vector3, sun_col: Color) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	var r: float = pl.get("radius", 3000.0)
	sm.radius = r
	sm.height = r * 2.0
	# Preset-driven tessellation makes Ultra visibly crisper at a planet limb,
	# while lower tiers avoid spending vertices on distant silhouettes.
	var p: Dictionary = Game.preset()
	sm.radial_segments = int(p.planet_segments)
	sm.rings = int(p.planet_rings)
	mi.mesh = sm
	mi.set_meta("quality_planet", true)
	var rocky: float = pl.get("rocky", 0.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/planet.gdshader")
	for key in ["col_a", "col_b", "col_c", "atmo"]:
		if pl.has(key):
			mat.set_shader_parameter(key, pl[key])
	mat.set_shader_parameter("band_freq", pl.get("band_freq", 9.0))
	mat.set_shader_parameter("rocky", rocky)
	mat.set_shader_parameter("atmo_strength", pl.get("atmo_strength", 1.2))
	mat.set_shader_parameter("sun_dir", dir_to_sun)
	mat.set_shader_parameter("sun_color", sun_col)
	# sensible per-archetype defaults so existing mission defs gain the new
	# features without every entry having to spell them out
	mat.set_shader_parameter("cloud_amount", pl.get("clouds", 0.62 if rocky < 0.5 else 0.30))
	mat.set_shader_parameter("city_lights", pl.get("cities", 0.0))
	mat.set_shader_parameter("ice_caps", pl.get("ice", 0.0 if rocky < 0.5 else 0.55))
	mat.set_shader_parameter("water_level", pl.get("water", 0.0))
	mat.set_shader_parameter("exposure", pl.get("exposure", 1.6))
	mat.set_shader_parameter("spin", pl.get("spin", 0.004))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# a 30 km sphere must never be culled by the shadow/reflection passes
	mi.extra_cull_margin = r
	add_child(mi)
	mi.position = pl.get("pos", Vector3(8000, 2000, -14000))
	mi.rotation_degrees.z = pl.get("tilt", 12.0)
	if pl.has("rings"):
		_add_rings(mi, r, pl)

## Saturn-style ring plane: a flat annulus with procedural gaps, lit by the same
## sun uniform as its planet.
func _add_rings(parent: Node3D, r: float, pl: Dictionary) -> void:
	var rings := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	var outer: float = r * float(pl.get("ring_outer", 2.3))
	pm.size = Vector2(outer * 2.0, outer * 2.0)
	pm.subdivide_width = 2
	pm.subdivide_depth = 2
	rings.mesh = pm
	var rm := ShaderMaterial.new()
	rm.shader = load("res://shaders/rings.gdshader")
	rm.set_shader_parameter("inner_frac", float(pl.get("ring_inner", 1.28)) * r / outer)
	rm.set_shader_parameter("outer_radius", outer)
	rm.set_shader_parameter("ring_color", pl.get("ring_color", Color(0.78, 0.70, 0.56)))
	rings.material_override = rm
	rings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rings.extra_cull_margin = outer
	parent.add_child(rings)

func apply_preset() -> void:
	var p: Dictionary = Game.preset()
	if world_env:
		world_env.environment.glow_enabled = p.glow
		world_env.environment.glow_intensity = 0.62 * float(p.glow_quality)
	if sun_light:
		sun_light.shadow_enabled = p.shadows
		sun_light.directional_shadow_max_distance = float(p.shadow_distance)
	for child in get_children():
		if child is MeshInstance3D and child.has_meta("quality_planet"):
			var sphere := (child as MeshInstance3D).mesh as SphereMesh
			if sphere:
				sphere.radial_segments = int(p.planet_segments)
				sphere.rings = int(p.planet_rings)
