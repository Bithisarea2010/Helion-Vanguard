class_name Wreck
extends Node3D
## Burning hulk left behind when a ship dies: tumbles, burns ~15 s, fades out.

const LIFE := 15.0
var vel := Vector3.ZERO
var ang := Vector3.ZERO
var _t := 0.0
var _fires: Array[GPUParticles3D] = []
var _lamp: OmniLight3D
var _flick := 0.0
var _popped := false

## Detach `model` from the dying ship and turn it into a drifting burning wreck.
static func spawn(battle: Node, model: Node3D, xform: Transform3D,
		lin_vel: Vector3, size := 1.0) -> Wreck:
	var w := Wreck.new()
	battle.add_child(w)
	w.global_transform = xform
	w.vel = lin_vel * 0.55 + Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
	w.ang = Vector3(randf_range(-1.4, 1.4), randf_range(-1.4, 1.4), randf_range(-1.4, 1.4))
	if model.get_parent():
		model.get_parent().remove_child(model)
	w.add_child(model)
	model.transform = Transform3D.IDENTITY
	# char the hull
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
	battle.get_tree().create_timer(randf_range(0.7, 2.2)).timeout.connect(func():
		if is_instance_valid(w):
			FX.explosion(battle, w.global_position, 0))
	return w

func _process(delta: float) -> void:
	_t += delta
	_flick += delta * 30.0
	global_position += vel * delta
	vel *= exp(-0.25 * delta)
	rotate_x(ang.x * delta)
	rotate_y(ang.y * delta)
	rotate_z(ang.z * delta)
	ang *= exp(-0.12 * delta)
	var burn := clampf(1.0 - (_t - 10.0) / 4.0, 0.0, 1.0)   # fade fire 10→14 s
	if _lamp:
		_lamp.light_energy = (1.4 + sin(_flick) * 0.5 + sin(_flick * 2.7) * 0.35) * burn
	if _t > 10.0 and not _popped:
		_popped = true
		for f in _fires:
			f.emitting = false
	if _t >= LIFE:
		queue_free()
