class_name FX
## Programmatic visual effects: explosions, sparks, shield ripples, debris, smoke.

static var _mat_cache := {}
static var _live_explosions := 0
static var _ring_tex: GradientTexture2D = null
static var _ball_mesh: SphereMesh = null
static var _fire_shader: Shader = null
static var _quad_mesh: QuadMesh = null
static var _scar_tex: GradientTexture2D = null
static var _live_muzzle_lights := 0
static var _live_impact_marks := 0
const MAX_MUZZLE_LIGHTS := 8
const MAX_IMPACT_MARKS := 56

static func clear_caches() -> void:
	_mat_cache.clear()
	_ring_tex = null
	_ball_mesh = null
	_fire_shader = null
	_quad_mesh = null
	_scar_tex = null
	_live_explosions = 0
	_live_muzzle_lights = 0
	_live_impact_marks = 0

static func quad_mesh() -> QuadMesh:
	if _quad_mesh == null:
		_quad_mesh = QuadMesh.new()
		_quad_mesh.size = Vector2(1, 1)
	return _quad_mesh

## Shared low-poly sphere for fireballs. The shader boils the silhouette, so the
## tessellation only has to be dense enough to carry the vertex displacement.
static func ball_mesh() -> SphereMesh:
	if _ball_mesh == null:
		_ball_mesh = SphereMesh.new()
		_ball_mesh.radius = 1.0
		_ball_mesh.height = 2.0
		# dense enough that the vertex displacement reads as boiling gas rather
		# than as a faceted low-poly shell
		_ball_mesh.radial_segments = 40
		_ball_mesh.rings = 22
	return _ball_mesh

## Expanding fireball shell. `radius` is the final radius in metres.
static func fireball(parent: Node, pos: Vector3, radius: float, dur: float,
		turb := 1.0, energy := 1.0) -> void:
	if _fire_shader == null:
		_fire_shader = load("res://shaders/fireball.gdshader")
	var mi := MeshInstance3D.new()
	mi.mesh = ball_mesh()
	var m := ShaderMaterial.new()
	m.shader = _fire_shader
	m.set_shader_parameter("seed", randf() * 40.0)
	m.set_shader_parameter("turbulence", turb)
	m.set_shader_parameter("intensity", energy)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = radius
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * radius * 0.22
	var tw := parent.get_tree().create_tween()
	tw.set_parallel(true)
	# expo-out: the blast front is fastest in the first few frames, then coasts
	tw.tween_property(mi, "scale", Vector3.ONE * radius, dur) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): m.set_shader_parameter("life", v), 0.0, 1.0, dur)
	tw.chain().tween_callback(mi.queue_free)

static func ring_tex() -> GradientTexture2D:
	if _ring_tex == null:
		var g := Gradient.new()
		# thin, hard-edged front with a short inner wake — a wide soft ring read
		# as a glowing disc rather than a blast front
		g.set_color(0, Color(1, 1, 1, 0.0))
		g.add_point(0.70, Color(1, 1, 1, 0.0))
		g.add_point(0.86, Color(1, 1, 1, 0.55))
		g.add_point(0.93, Color(1, 1, 1, 1.0))
		g.add_point(0.97, Color(1, 1, 1, 0.35))
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
	# same trap as the spark material: without an explicit alpha pipeline the
	# ring texture's coverage is discarded, the quad draws as a solid additive
	# square, and the alpha tween below silently does nothing
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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
	# expo-out on the radius and a held-then-dumped alpha: the front should
	# outrun the fireball and vanish, not dissolve evenly as it grows
	tw.tween_property(mi, "scale", Vector3.ONE * radius, 0.48) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.42).set_delay(0.06) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)

## Alpha-blended particle material for smoke and dust.
static func _smoke_mat() -> Material:
	if not _mat_cache.has("smoke"):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/smoke.gdshader")
		_mat_cache["smoke"] = m
	return _mat_cache["smoke"]

## Additive particle material. See shaders/spark.gdshader for why this is a
## custom shader rather than a StandardMaterial3D with a soft dot texture.
static func _add_mat(_color: Color, softness := 2.4, core := 0.30) -> Material:
	var key := "spark_%.2f_%.2f" % [softness, core]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/spark.gdshader")
	m.set_shader_parameter("softness", softness)
	m.set_shader_parameter("core", core)
	_mat_cache[key] = m
	return m

static func _particles(parent: Node, pos: Vector3, amount: int, life: float,
		vel_min: float, vel_max: float, scale_min: float, scale_max: float,
		color_a: Color, color_b: Color, gravity := Vector3.ZERO,
		spread := 180.0, dir := Vector3.UP, damping := 0.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	# Simulating at an uncapped render rate made particles 2–3× more expensive
	# on high-refresh displays without adding visible motion samples.
	p.fixed_fps = 60
	p.interpolate = true
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
	p.draw_pass_1 = quad_mesh()
	p.material_override = _add_mat(Color(1, 1, 1))
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var t := parent.get_tree().create_timer(life * 2.0 + 0.5)
	t.timeout.connect(func():
		if is_instance_valid(p): p.queue_free())
	return p

## kind: 0 small (fighter hit), 1 medium (fighter death), 2 large (bomber/corvette), 3 huge (base)
##
## Layered the way a real blast reads: a white flash frame, a boiling fireball
## shell, radial sparks, drifting embers, a shockwave ring, lingering smoke and
## hot debris. Each layer peaks at a different time — the flash is gone in two
## frames, the smoke is still there four seconds later — which is what stops it
## looking like one puff of orange particles.
static func explosion(parent: Node, pos: Vector3, kind := 1) -> void:
	if _live_explosions > 24:
		return
	_live_explosions += 1
	var tree := parent.get_tree()
	tree.create_timer(4.0).timeout.connect(func(): _live_explosions -= 1)
	var s: float = [0.6, 1.0, 2.2, 6.0][clampi(kind, 0, 3)]
	var pq: float = Game.preset().particles
	# --- 1. ignition flash: over almost before it registers, but its absence is
	# what made the old blast feel soft
	fireball(parent, pos, 3.4 * s, 0.11, 0.35, 5.0)
	# --- 2. main fireball shell
	fireball(parent, pos, 8.0 * s, 0.42 + 0.30 * s, 1.0, 1.7)
	if kind >= 2:
		# big kills get offset secondary lobes so the shape is not a clean ball
		for i in 2:
			var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 3.0 * s
			fireball(parent, pos + off, 5.5 * s, 0.5 + 0.3 * s, 1.25, 1.3)
	# --- 3. sparks: fast, thin, short-lived
	_particles(parent, pos, int(34 * pq), 0.85, 22.0 * s, 58.0 * s,
		0.10 * s, 0.26 * s, Color(1.0, 0.92, 0.55, 1.0), Color(1.0, 0.35, 0.04, 0.0),
		Vector3.ZERO, 180.0, Vector3.UP, 0.6)
	# --- 4. embers: slow, dim, still glowing seconds later
	if pq > 0.5:
		_particles(parent, pos, int(16 * pq), 2.6 * s, 3.0 * s, 13.0 * s,
			0.16 * s, 0.4 * s, Color(1.0, 0.55, 0.15, 0.9), Color(0.6, 0.09, 0.01, 0.0),
			Vector3.ZERO, 180.0, Vector3.UP, 1.1)
	# --- 5. smoke: dark, slow, outlives everything else
	if kind >= 1 and pq > 0.6:
		_smoke_puff(parent, pos, int(14 * pq), 3.4 * s, 2.6 * s, 5.5 * s)
	# --- 6. light: a hard spike that decays fast, then a slow ember glow, rather
	# than one linear ramp to zero
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.72, 0.36)
	l.light_energy = 11.0 * s
	l.omni_range = 42.0 * s
	l.shadow_enabled = false
	parent.add_child(l)
	l.global_position = pos
	var tw := tree.create_tween()
	tw.tween_property(l, "light_energy", 2.4 * s, 0.14).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(l, "light_color", Color(1.0, 0.34, 0.10), 0.6 * s)
	tw.parallel().tween_property(l, "light_energy", 0.0, 0.9 * s).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(l.queue_free)
	# --- 7. shockwave ring + debris + delayed cook-offs
	if kind >= 1:
		shockwave(parent, pos, 16.0 * s, Color(1.0, 0.78, 0.5))
		if kind >= 2:
			var t2 := tree.create_timer(0.12)
			t2.timeout.connect(func():
				if is_instance_valid(parent):
					shockwave(parent, pos, 30.0 * s, Color(0.8, 0.6, 1.0)))
		debris(parent, pos, 3 + kind * 3, s)
		var n_sec := 1 if kind == 1 else 3
		for i in n_sec:
			var t := tree.create_timer(randf_range(0.15, 0.6) * (i + 1))
			t.timeout.connect(func():
				if is_instance_valid(parent):
					var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 3.5 * s
					fireball(parent, pos + off, 3.6 * s, 0.34 * s + 0.2, 1.1, 1.4)
					_particles(parent, pos + off, int(12 * pq), 0.4 * s, 4.0 * s, 16.0 * s,
						0.5 * s, 1.1 * s, Color(1.0, 0.85, 0.45, 1.0), Color(0.9, 0.3, 0.05, 0.0))
					AudioMgr.play_3d("explosion_small", pos + off, -6.0))
	# audio
	var snd := "explosion_small" if kind == 0 else ("explosion_big" if kind >= 2 else "explosion")
	AudioMgr.play_3d(snd, pos, 2.0 if kind >= 2 else 0.0, 1.0, 2500.0)

## Alpha-blended smoke burst. Kept out of _particles() because that helper is
## hard-wired to the additive material, and additive smoke just brightens the
## scene instead of darkening it.
static func _smoke_puff(parent: Node, pos: Vector3, amount: int, life: float,
		scale_min: float, scale_max: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.75
	p.fixed_fps = 30
	p.interpolate = true
	var pm := ParticleProcessMaterial.new()
	pm.spread = 180.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 7.0
	pm.damping_min = 1.2
	pm.damping_max = 2.4
	pm.angular_velocity_min = -35.0
	pm.angular_velocity_max = 35.0
	pm.scale_min = scale_min
	pm.scale_max = scale_max
	var grad := Gradient.new()
	grad.set_color(0, Color(0.55, 0.34, 0.20, 0.0))
	grad.add_point(0.08, Color(0.42, 0.26, 0.16, 0.75))
	grad.add_point(0.45, Color(0.14, 0.12, 0.11, 0.55))
	grad.set_color(1, Color(0.05, 0.05, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	var sc := CurveTexture.new()
	var cur := Curve.new()
	cur.add_point(Vector2(0, 0.35)); cur.add_point(Vector2(1, 1.0))
	sc.curve = cur
	pm.scale_curve = sc
	p.process_material = pm
	p.draw_pass_1 = quad_mesh()
	p.material_override = _smoke_mat()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var t := parent.get_tree().create_timer(life * 2.0 + 0.5)
	t.timeout.connect(func():
		if is_instance_valid(p): p.queue_free())

static func debris(parent: Node, pos: Vector3, count: int, s: float) -> void:
	var life: float = Game.preset().debris
	for i in count:
		var rb := RigidBody3D.new()
		rb.gravity_scale = 0.0
		rb.collision_layer = 0
		rb.collision_mask = 0
		var mi := MeshInstance3D.new()
		# mixed plate and spar shapes: uniform cubes read as a bag of dice
		var bm := BoxMesh.new()
		if randf() < 0.45:
			bm.size = Vector3(randf_range(0.5, 1.6), randf_range(0.06, 0.2), randf_range(0.4, 1.3)) * s
		else:
			bm.size = Vector3(randf_range(0.15, 0.5), randf_range(0.15, 0.5), randf_range(0.6, 2.2)) * s
		mi.mesh = bm
		# each chunk owns its material so it can cool independently; they are
		# torn out of a fireball, so they start glowing and fade to cold metal
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.11, 0.10, 0.11)
		mat.metallic = 0.85
		mat.roughness = 0.45
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.42, 0.10)
		mat.emission_energy_multiplier = randf_range(1.6, 4.0)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rb.add_child(mi)
		parent.add_child(rb)
		rb.global_position = pos + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * s
		rb.linear_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(6.0, 20.0) * s
		rb.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
		var chunk_life: float = life * randf_range(0.6, 1.0)
		var tw := parent.get_tree().create_tween()
		tw.tween_property(mat, "emission_energy_multiplier", 0.0, minf(chunk_life * 0.7, 2.5)) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		var t := parent.get_tree().create_timer(chunk_life)
		t.timeout.connect(func():
			if is_instance_valid(rb): rb.queue_free())

static func impact(parent: Node, pos: Vector3, color: Color, big := false) -> void:
	var n := int((8 if not big else 16) * float(Game.preset().particles))
	_particles(parent, pos, n, 0.35, 6.0, 18.0, 0.15, 0.35,
		Color(color.r, color.g, color.b, 1.0), Color(color.r, color.g, color.b, 0.0))

static func _scar_texture() -> GradientTexture2D:
	if _scar_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.95))
		g.add_point(0.32, Color(1, 1, 1, 0.78))
		g.add_point(0.68, Color(1, 1, 1, 0.20))
		g.set_color(1, Color(1, 1, 1, 0.0))
		_scar_tex = GradientTexture2D.new()
		_scar_tex.gradient = g
		_scar_tex.fill = GradientTexture2D.FILL_RADIAL
		_scar_tex.fill_from = Vector2(0.5, 0.5)
		_scar_tex.fill_to = Vector2(0.98, 0.5)
		_scar_tex.width = 128
		_scar_tex.height = 128
	return _scar_tex

static func _scar_material(kind: String) -> StandardMaterial3D:
	var key := "scar_" + kind
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = _scar_texture()
	m.albedo_color = Color(0.045, 0.025, 0.015, 0.82) if kind == "rock" \
		else Color(0.025, 0.018, 0.016, 0.88)
	m.disable_receive_shadows = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_mat_cache[key] = m
	return m

## Persistent-but-bounded scorch mark. It follows moving ships/wrecks when
## attached to them, while asteroid marks stay in world space. Marks do not
## collide and never alter or break the underlying mesh.
static func surface_scar(parent: Node3D, pos: Vector3, normal: Vector3,
		kind := "metal", size := 0.8, life := 9.0) -> void:
	if _live_impact_marks >= MAX_IMPACT_MARKS or parent == null or not is_instance_valid(parent):
		return
	if normal.length_squared() < 0.01:
		normal = Vector3.UP
	normal = normal.normalized()
	var mi := MeshInstance3D.new()
	mi.mesh = quad_mesh()
	mi.material_override = _scar_material(kind)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * size
	mi.visibility_range_end = 1800.0
	mi.visibility_range_end_margin = 120.0
	parent.add_child(mi)
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	# QuadMesh faces +Z; Basis.looking_at(-normal) points +Z along the normal.
	mi.global_transform = Transform3D(Basis.looking_at(-normal, up),
		pos + normal * maxf(size * 0.018, 0.012))
	_live_impact_marks += 1
	var tree := parent.get_tree()
	var fade := tree.create_tween()
	fade.tween_interval(maxf(life - 1.5, 0.1))
	fade.tween_property(mi, "transparency", 1.0, 1.5)
	tree.create_timer(life + 0.1, true, false, true).timeout.connect(func():
		_live_impact_marks = maxi(_live_impact_marks - 1, 0)
		if is_instance_valid(mi):
			mi.queue_free())

## Sparks/dust + a persistent mark for any repeatable surface hit.
static func surface_impact(fx_parent: Node, attach_to: Node3D, pos: Vector3,
		normal: Vector3, kind := "metal", energy := 10.0, make_mark := true) -> void:
	if normal.length_squared() < 0.01:
		normal = Vector3.UP
	normal = normal.normalized()
	var col := Color(0.76, 0.70, 0.58) if kind == "rock" else Color(1.0, 0.68, 0.26)
	var count := int(clampf(5.0 + energy * 0.20, 5.0, 18.0) * float(Game.preset().particles))
	_particles(fx_parent, pos, count, 0.42, 5.0, clampf(12.0 + energy * 0.25, 14.0, 34.0),
		0.10, 0.30, Color(col.r, col.g, col.b, 1.0),
		Color(col.r * 0.45, col.g * 0.30, col.b * 0.20, 0.0),
		Vector3.ZERO, 58.0, normal, 0.8)
	if kind == "rock" and energy > 8.0 and _live_explosions < 20:
		_smoke_puff(fx_parent, pos + normal * 0.05,
			maxi(int(4 * float(Game.preset().particles)), 2), 1.15, 0.25, 0.75)
	if make_mark and attach_to and is_instance_valid(attach_to):
		surface_scar(attach_to, pos, normal, kind,
			clampf(0.35 + sqrt(maxf(energy, 0.0)) * 0.08, 0.4, 1.5),
			11.0 if kind == "rock" else 8.0)

static func shield_hit(parent: Node, pos: Vector3) -> void:
	_particles(parent, pos, 10, 0.4, 2.0, 8.0, 0.5, 1.2,
		Color(0.4, 0.7, 1.0, 0.8), Color(0.2, 0.4, 1.0, 0.0))

## Rocket motor exhaust smoke. World-space, so it lays a trail behind the
## missile instead of riding along with it.
static func rocket_smoke(parent: Node3D, offset: Vector3, size := 1.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = int(30 * size)
	p.lifetime = 1.5
	p.local_coords = false
	p.fixed_fps = 30
	var pm := ParticleProcessMaterial.new()
	pm.spread = 180.0
	pm.initial_velocity_min = 0.4 * size
	pm.initial_velocity_max = 2.2 * size
	pm.damping_min = 0.8
	pm.damping_max = 1.6
	pm.angular_velocity_min = -50.0
	pm.angular_velocity_max = 50.0
	pm.scale_min = 0.30 * size
	pm.scale_max = 0.85 * size
	var grad := Gradient.new()
	grad.set_color(0, Color(0.9, 0.5, 0.25, 0.0))
	grad.add_point(0.07, Color(0.55, 0.34, 0.22, 0.5))
	grad.add_point(0.4, Color(0.24, 0.22, 0.21, 0.34))
	grad.set_color(1, Color(0.10, 0.10, 0.10, 0.0))
	var gt := GradientTexture1D.new(); gt.gradient = grad
	pm.color_ramp = gt
	var sc := CurveTexture.new()
	var cur := Curve.new()
	cur.add_point(Vector2(0, 0.3)); cur.add_point(Vector2(1, 1.0))
	sc.curve = cur
	pm.scale_curve = sc
	p.process_material = pm
	p.draw_pass_1 = quad_mesh()
	p.material_override = _smoke_mat()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.position = offset
	p.emitting = true
	return p

## Rail launch: motor ignition flash, the blowback puff off the pylon and a
## fan of sparks kicked forward along the launch axis.
static func launch_flash(parent: Node, pos: Vector3, dir: Vector3) -> void:
	fireball(parent, pos, 2.6, 0.16, 0.5, 2.6)
	_particles(parent, pos, int(14 * Game.preset().particles), 0.35, 10.0, 34.0,
		0.09, 0.22, Color(1.0, 0.88, 0.5, 1.0), Color(1.0, 0.35, 0.05, 0.0),
		Vector3.ZERO, 34.0, dir, 1.2)
	_smoke_puff(parent, pos, int(8 * Game.preset().particles), 1.4, 0.7, 1.8)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.22)
	l.light_energy = 5.5
	l.omni_range = 22.0
	l.shadow_enabled = false
	parent.add_child(l)
	l.global_position = pos
	var tw := parent.get_tree().create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.22).set_trans(Tween.TRANS_EXPO)
	tw.tween_callback(l.queue_free)

static func muzzle_flash(parent: Node, pos: Vector3, color: Color) -> void:
	if _live_muzzle_lights >= MAX_MUZZLE_LIGHTS:
		return
	var cam := parent.get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_squared_to(pos) > 850.0 * 850.0:
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 2.0
	l.omni_range = 8.0
	l.shadow_enabled = false
	parent.add_child(l)
	l.global_position = pos
	_live_muzzle_lights += 1
	var tw := parent.get_tree().create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.08)
	parent.get_tree().create_timer(0.10, true, false, true).timeout.connect(func():
		_live_muzzle_lights = maxi(_live_muzzle_lights - 1, 0)
		if is_instance_valid(l):
			l.queue_free())

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
	p.draw_pass_1 = quad_mesh()
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
	p.draw_pass_1 = quad_mesh()
	p.material_override = _smoke_mat()
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
	p.draw_pass_1 = quad_mesh()
	p.material_override = _add_mat(Color(1, 1, 1))
	target.add_child(p)
	p.position = offset
	p.emitting = true
	return p
