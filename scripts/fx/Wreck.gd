class_name Wreck
extends RigidBody3D
## Shootable burning hulk: rigid-body drift, repeated impact feedback, no breakup.

const LIFE := 15.0
var _t := 0.0
var _fires: Array[GPUParticles3D] = []
var _lamp: OmniLight3D
var _flick := 0.0
var _popped := false
var _hit_fx_cd := 0.0
var _hit_glow := 0.0
var team := -1
var alive := false
var display_name := "Burning wreck"

## Detach `model` from the dying ship and turn it into a drifting burning wreck.
static func spawn(battle: Node, model: Node3D, xform: Transform3D,
		lin_vel: Vector3, size := 1.0) -> Wreck:
	var w := Wreck.new()
	battle.add_child(w)
	w.global_transform = xform
	w.mass = maxf(4.0, 12.0 * size)
	w.gravity_scale = 0.0
	w.linear_damp = 0.25
	w.angular_damp = 0.12
	w.can_sleep = false
	w.collision_layer = 8
	w.collision_mask = 1 | 2 | 4 | 8
	w.contact_monitor = true
	w.max_contacts_reported = 2
	w.add_to_group("reactive_surface")
	w.add_to_group("wrecks")
	w.set_meta("surface_kind", "metal")
	if model.get_parent():
		model.get_parent().remove_child(model)
	w.add_child(model)
	model.transform = Transform3D.IDENTITY
	var bounds := _model_bounds(model)
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(
		maxf(bounds.size.x * 0.72, 0.8),
		maxf(bounds.size.y * 0.72, 0.5),
		maxf(bounds.size.z * 0.82, 1.2))
	shape_node.shape = box
	shape_node.position = bounds.get_center()
	w.add_child(shape_node)
	w.linear_velocity = lin_vel * 0.55 + Vector3(
		randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
	w.angular_velocity = Vector3(
		randf_range(-1.4, 1.4), randf_range(-1.4, 1.4), randf_range(-1.4, 1.4))
	# char the hull
	HullMaterial.set_damage(model, 1.0)
	for mi in model.find_children("*", "MeshInstance3D", true):
		var m3 := mi as MeshInstance3D
		for s in m3.mesh.get_surface_count():
			var src := m3.get_surface_override_material(s)
			if src == null:
				src = m3.mesh.surface_get_material(s)
			if src is StandardMaterial3D:
				var sm: StandardMaterial3D = src.duplicate()
				sm.albedo_color = Color(sm.albedo_color.r * 0.16, sm.albedo_color.g * 0.14, sm.albedo_color.b * 0.13)
				sm.metallic = 0.6
				sm.roughness = 0.85
				if sm.emission_enabled:
					sm.emission = Color(1.0, 0.25, 0.05)
					sm.emission_energy_multiplier = 1.2
				m3.set_surface_override_material(s, sm)
	# fires at 2-3 points
	var n_fires := 2 if size < 1.5 else 3
	for i in n_fires:
		var off := Vector3(randf_range(-1.2, 1.2), randf_range(-0.4, 0.6), randf_range(-2.0, 2.0)) * size
		w._fires.append(FX.fire_emitter(w, off, 0.9 * size, Color(1.0, 0.55, 0.12)))
		if i == 0:
			w._fires.append(FX.smoke_emitter(w, off, 1.4 * size))
	# flickering ember light
	w._lamp = OmniLight3D.new()
	w._lamp.light_color = Color(1.0, 0.42, 0.1)
	w._lamp.omni_range = 14.0 * size
	w._lamp.light_energy = 2.2
	w._lamp.shadow_enabled = false
	w.add_child(w._lamp)
	# secondary pop shortly after death
	var wreck_id := w.get_instance_id()
	var battle_id := battle.get_instance_id()
	battle.get_tree().create_timer(randf_range(0.7, 2.2)).timeout.connect(func():
		var live_wreck := instance_from_id(wreck_id) as Node3D
		var live_battle := instance_from_id(battle_id) as Node
		if is_instance_valid(live_wreck) and is_instance_valid(live_battle):
			FX.explosion(live_battle, live_wreck.global_position, 0))
	return w

static func _model_bounds(root: Node3D) -> AABB:
	var out := AABB(Vector3(-1, -0.5, -2), Vector3(2, 1, 4))
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := mi.transform
		var p := mi.get_parent()
		while p and p != root:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var ab := xf * mi.get_aabb()
		out = ab if first else out.merge(ab)
		first = false
	return out

func get_velocity() -> Vector3:
	return linear_velocity

func take_hit(dmg: float, pos: Vector3, dir: Vector3, _pen := 0.2,
		_sh_mult := 1.0, _hu_mult := 1.0, _attacker: Node = null,
		surface_normal := Vector3.ZERO) -> void:
	if not is_finite(dmg) or dmg <= 0.0:
		return
	var normal := surface_normal
	if normal.length_squared() < 0.01:
		normal = (pos - global_position).normalized()
	if normal.length_squared() < 0.01:
		normal = -dir.normalized()
	var make_mark := _hit_fx_cd <= 0.0
	if make_mark:
		_hit_fx_cd = 0.06
	FX.surface_impact(get_parent(), self, pos, normal, "metal", dmg, make_mark)
	# Hits cannot split the hulk, but they transfer a bounded linear/off-axis
	# impulse and briefly re-ignite its ember light.
	var travel := dir.normalized() if dir.length_squared() > 0.0001 else -normal
	var impulse := travel * clampf(dmg * 0.11, 0.3, 18.0)
	var offset := pos - global_position
	if offset.length() > 60.0:
		offset = offset.normalized() * 60.0
	apply_impulse(impulse, offset)
	_hit_glow = minf(_hit_glow + clampf(dmg * 0.04, 0.2, 2.8), 4.0)

func _process(delta: float) -> void:
	_t += delta
	_flick += delta * 30.0
	_hit_fx_cd = maxf(_hit_fx_cd - delta, 0.0)
	_hit_glow = maxf(_hit_glow - delta * 3.0, 0.0)
	var burn := clampf(1.0 - (_t - 10.0) / 4.0, 0.0, 1.0)   # fade fire 10→14 s
	if _lamp:
		_lamp.light_energy = (1.4 + sin(_flick) * 0.5 + sin(_flick * 2.7) * 0.35) * burn + _hit_glow
	if _t > 10.0 and not _popped:
		_popped = true
		for f in _fires:
			f.emitting = false
	if _t >= LIFE:
		queue_free()
