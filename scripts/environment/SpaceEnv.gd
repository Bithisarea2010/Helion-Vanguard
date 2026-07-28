class_name SpaceEnv
extends Node3D
## Builds the world: sky, sun, planets, lighting, environment settings.

var world_env: WorldEnvironment
var sun_light: DirectionalLight3D
var sun_visual: MeshInstance3D

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
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = cfg.get("ambient", Color(0.36, 0.40, 0.52))
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	var p: Dictionary = Game.preset()
	env.glow_enabled = p.glow
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.12
	env.set_glow_level(1, 0.5)
	env.set_glow_level(2, 0.9)
	env.set_glow_level(3, 0.7)
	env.set_glow_level(5, 0.35)
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.04
	env.adjustment_saturation = 1.08
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
	sun_light.light_energy = 1.8
	sun_light.shadow_enabled = p.shadows
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun_light.directional_shadow_max_distance = 900.0
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
		_add_planet(pl)
	# bake the sky to a static panorama (huge GPU saving, cooler laptops)
	_bake_sky.call_deferred(env, cfg, -sun_dir, sun_col)

func _bake_sky(env: Environment, cfg: Dictionary, dir_to_sun: Vector3, sun_col: Color) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(2048, 1024)
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
	var tex := ImageTexture.create_from_image(img)
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = tex
	pano.filter = true
	if env.sky:
		env.sky.sky_material = pano

func _add_planet(pl: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	var r: float = pl.get("radius", 3000.0)
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 48
	sm.rings = 24
	mi.mesh = sm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/planet.gdshader")
	for key in ["col_a", "col_b", "col_c", "atmo"]:
		if pl.has(key):
			mat.set_shader_parameter(key, pl[key])
	mat.set_shader_parameter("band_freq", pl.get("band_freq", 9.0))
	mat.set_shader_parameter("rocky", pl.get("rocky", 0.0))
	mat.set_shader_parameter("atmo_strength", pl.get("atmo_strength", 1.2))
	mi.material_override = mat
	add_child(mi)
	mi.position = pl.get("pos", Vector3(8000, 2000, -14000))
	mi.rotation_degrees.z = pl.get("tilt", 12.0)

func apply_preset() -> void:
	var p: Dictionary = Game.preset()
	if world_env:
		world_env.environment.glow_enabled = p.glow
	if sun_light:
		sun_light.shadow_enabled = p.shadows
