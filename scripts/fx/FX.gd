class_name FX
## Programmatic visual effects: explosions, sparks, shield ripples, debris, smoke.

static var _mat_cache := {}
static var _live_explosions := 0
static var _dot_tex: GradientTexture2D = null
static var _ring_tex: GradientTexture2D = null

static func ring_tex() -> GradientTexture2D:
	if _ring_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.0))
		g.add_point(0.62, Color(1, 1, 1, 0.0))
		g.add_point(0.78, Color(1, 1, 1, 1.0))
		g.set_color(1, Color(1, 1, 1, 0.0))
		_ring_tex = GradientTexture2D.new()
		_ring_tex.gradient = g
		_ring_tex.fill = GradientTexture2D.FILL_RADIAL
		_ring_tex.fill_from = Vector2(0.5, 0.5)
		_ring_tex.fill_to = Vector2(0.99, 0.5)
		_ring_tex.width = 256
		_ring_tex.height = 256
	return _ring_tex

## Expanding shockwave ring billboard.
static func shockwave(parent: Node, pos: Vector3, radius: float, col := Color(1.0, 0.7, 0.4)) -> void:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(col.r, col.g, col.b, 0.9)
	m.albedo_texture = ring_tex()
	m.disable_receive_shadows = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.5
	var tw := parent.get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.55)
	tw.chain().tween_callback(mi.queue_free)

## Shared soft radial dot — REQUIRED on every additive particle quad,
## otherwise they render as hard squares.
static func dot_tex() -> GradientTexture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.add_point(0.55, Color(1, 1, 1, 0.35))
		g.set_color(1, Color(1, 1, 1, 0.0))
		_dot_tex = GradientTexture2D.new()
		_dot_tex.gradient = g
		_dot_tex.fill = GradientTexture2D.FILL_RADIAL
		_dot_tex.fill_from = Vector2(0.5, 0.5)
		_dot_tex.fill_to = Vector2(0.99, 0.5)
		_dot_tex.width = 128
		_dot_tex.height = 128
	return _dot_tex

static func _add_mat(color: Color) -> StandardMaterial3D:
	var key := "add_" + color.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.albedo_texture = dot_tex()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.disable_receive_shadows = true
	m.no_depth_test = false
	_mat_cache[key] = m
	return m

static func _particles(parent: Node, pos: Vector3, amount: int, life: float,
		vel_min: float, vel_max: float, scale_min: float, scale_max: float,
		color_a: Color, color_b: Color, gravity := Vector3.ZERO,
		spread := 180.0, dir := Vector3.UP, damping := 0.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.fixed_fps = 0
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = vel_min
	pm.initial_velocity_max = vel_max
	pm.gravity = gravity
	pm.damping_min = damping
	pm.damping_max = damping * 1.5
	pm.scale_min = scale_min
	pm.scale_max = scale_max
	var grad := Gradient.new()
	grad.set_color(0, color_a)
	grad.set_color(1, color_b)
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	var sc := CurveTexture.new()
	var cur := Curve.new()
	cur.add_point(Vector2(0, 1)); cur.add_point(Vector2(1, 0.05))
	sc.curve = cur
	pm.scale_curve = sc
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	p.draw_pass_1 = quad
	p.material_override = _add_mat(Color(1, 1, 1))
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var t := parent.get_tree().create_timer(life * 2.0 + 0.5)
	t.timeout.connect(func():
		if is_instance_valid(p): p.queue_free())
	return p

## kind: 0 small (fighter hit), 1 medium (fighter death), 2 large (bomber/corvette), 3 huge (base)
static func explosion(parent: Node, pos: Vector3, kind := 1) -> void:
	if _live_explosions > 24:
		return
	_live_explosions += 1
	parent.get_tree().create_timer(3.0).timeout.connect(func(): _live_explosions -= 1)
	var s: float = [0.6, 1.0, 2.2, 6.0][clampi(kind, 0, 3)]
	var pq: float = Game.preset().particles
	# fireball
	_particles(parent, pos, int(20 * pq), 0.55 * s if kind < 2 else 1.0 * s, 2.0 * s, 9.0 * s,
		1.6 * s, 3.2 * s, Color(1.0, 0.9, 0.5, 1.0), Color(0.9, 0.25, 0.03, 0.0))
	# sparks
	_particles(parent, pos, int(30 * pq), 0.8, 18.0 * s, 46.0 * s,
		0.12 * s, 0.3 * s, Color(1.0, 0.85, 0.4, 1.0), Color(1.0, 0.4, 0.05, 0.0))
	# smoke
	if kind >= 1 and pq > 0.6:
		_particles(parent, pos, int(10 * pq), 2.2 * s, 1.0, 4.0,
			2.0 * s, 4.0 * s, Color(0.25, 0.22, 0.2, 0.5), Color(0.05, 0.05, 0.05, 0.0))
	# flash light
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 6.0 * s
	l.omni_range = 30.0 * s
	l.shadow_enabled = false
	parent.add_child(l)
	l.global_position = pos
	var tw := parent.get_tree().create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.5 * s)
	tw.tween_callback(l.queue_free)
	# shockwave ring + debris + delayed secondary bursts (AAA feel)
	if kind >= 1:
		shockwave(parent, pos, 14.0 * s)
		debris(parent, pos, 3 + kind * 3, s)
		var n_sec := 1 if kind == 1 else 3
		for i in n_sec:
			var t := parent.get_tree().create_timer(randf_range(0.15, 0.6) * (i + 1))
			t.timeout.connect(func():
				if is_instance_valid(parent):
					var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 3.5 * s
					_particles(parent, pos + off, int(12 * pq), 0.4 * s, 4.0 * s, 16.0 * s,
						0.8 * s, 1.8 * s, Color(1.0, 0.85, 0.45, 1.0), Color(0.9, 0.3, 0.05, 0.0))
					AudioMgr.play_3d("explosion_small", pos + off, -6.0))
	# audio
	var snd := "explosion_small" if kind == 0 else ("explosion_big" if kind >= 2 else "explosion")
	AudioMgr.play_3d(snd, pos, 2.0 if kind >= 2 else 0.0, 1.0, 2500.0)

static func debris(parent: Node, pos: Vector3, count: int, s: float) -> void:
	var life: float = Game.preset().debris
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.11)
	mat.metallic = 0.8
	for i in count:
		var rb := RigidBody3D.new()
		rb.gravity_scale = 0.0
		rb.collision_layer = 0
		rb.collision_mask = 0
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(0.2, 0.7), randf_range(0.2, 0.7), randf_range(0.2, 0.7)) * s
		mi.mesh = bm
		mi.material_override = mat
		rb.add_child(mi)
		parent.add_child(rb)
		rb.global_position = pos + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * s
		rb.linear_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(6.0, 20.0) * s
		rb.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
		var t := parent.get_tree().create_timer(life * randf_range(0.6, 1.0))
		t.timeout.connect(func():
			if is_instance_valid(rb): rb.queue_free())

static func impact(parent: Node, pos: Vector3, color: Color, big := false) -> void:
	var n := 8 if not big else 16
	_particles(parent, pos, n, 0.35, 6.0, 18.0, 0.15, 0.35,
		Color(color.r, color.g, color.b, 1.0), Color(color.r, color.g, color.b, 0.0))

static func shield_hit(parent: Node, pos: Vector3) -> void:
	_particles(parent, pos, 10, 0.4, 2.0, 8.0, 0.5, 1.2,
		Color(0.4, 0.7, 1.0, 0.8), Color(0.2, 0.4, 1.0, 0.0))

static func muzzle_flash(parent: Node, pos: Vector3, color: Color) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 2.0
	l.omni_range = 8.0
	l.shadow_enabled = false
	parent.add_child(l)
	l.global_position = pos
	var tw := parent.get_tree().create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.08)
	tw.tween_callback(l.queue_free)

## Continuous licking fire (wrecks, missile exhausts). Cheap: 30 fps sim.
static func fire_emitter(parent: Node3D, offset: Vector3, size := 1.0,
		col := Color(1.0, 0.55, 0.12)) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = int(22 * size)
	p.lifetime = 0.55
	p.local_coords = false
	p.fixed_fps = 30
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 24.0
	pm.initial_velocity_min = 1.6 * size
	pm.initial_velocity_max = 3.6 * size
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5 * size
	pm.scale_max = 1.1 * size
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35 * size
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.9, 0.5, 1.0))
	grad.add_point(0.35, Color(col.r, col.g * 0.7, col.b * 0.3, 0.85))
	grad.set_color(1, Color(0.45, 0.06, 0.01, 0.0))
	var gt := GradientTexture1D.new(); gt.gradient = grad
	pm.color_ramp = gt
	var sc := CurveTexture.new()
	var cur := Curve.new()
	cur.add_point(Vector2(0, 0.6)); cur.add_point(Vector2(0.3, 1.0)); cur.add_point(Vector2(1, 0.1))
	sc.curve = cur
	pm.scale_curve = sc
	p.process_material = pm
	var quad := QuadMesh.new(); quad.size = Vector2(1, 1)
	p.draw_pass_1 = quad
	p.material_override = _add_mat(Color(1, 1, 1))
	parent.add_child(p)
	p.position = offset
	p.emitting = true
	return p

static func smoke_emitter(parent: Node3D, offset: Vector3, size := 1.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 2.4
	p.local_coords = false
	p.fixed_fps = 30
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 20.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.6
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.9 * size
	pm.scale_max = 2.0 * size
	var grad := Gradient.new()
	grad.set_color(0, Color(0.18, 0.16, 0.15, 0.45))
	grad.set_color(1, Color(0.04, 0.04, 0.04, 0.0))
	var gt := GradientTexture1D.new(); gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new(); quad.size = Vector2(1, 1)
	p.draw_pass_1 = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = dot_tex()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.disable_receive_shadows = true
	p.material_override = m
	parent.add_child(p)
	p.position = offset
	p.emitting = true
	return p

## Attach persistent damage smoke/fire to a damaged ship
static func damage_smoke(target: Node3D, offset: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 24
	p.lifetime = 1.2
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 15.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5; pm.scale_max = 1.4
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.5, 0.15, 0.8))
	grad.set_color(1, Color(0.12, 0.12, 0.12, 0.0))
	var gt := GradientTexture1D.new(); gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new(); quad.size = Vector2(1, 1)
	p.draw_pass_1 = quad
	p.material_override = _add_mat(Color(1, 1, 1))
	target.add_child(p)
	p.position = offset
	p.emitting = true
	return p
