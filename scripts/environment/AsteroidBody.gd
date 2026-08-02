class_name AsteroidBody
extends StaticBody3D
## Pooled collision proxy for a MultiMesh asteroid. It never destroys the rock;
## every projectile/beam hit produces repeatable dust, sparks and a fading scar.

var field: AsteroidField
var rock_radius := 1.0
var rock_index := -1
var team := -1
var alive := true
var display_name := "Asteroid"
var _fx_cooldown := 0.0

func setup(owner_field: AsteroidField) -> void:
	field = owner_field
	collision_layer = 2
	collision_mask = 0
	add_to_group("asteroid")
	add_to_group("reactive_surface")
	set_meta("surface_kind", "rock")

func _physics_process(delta: float) -> void:
	_fx_cooldown = maxf(_fx_cooldown - delta, 0.0)

func get_velocity() -> Vector3:
	return Vector3.ZERO

func take_hit(dmg: float, pos: Vector3, dir: Vector3, _pen := 0.2,
		_sh_mult := 1.0, _hu_mult := 1.0, _attacker: Node = null,
		surface_normal := Vector3.ZERO) -> void:
	if field == null or not is_instance_valid(field):
		return
	if not is_finite(dmg) or dmg <= 0.0:
		return
	var normal := surface_normal
	if normal.length_squared() < 0.01:
		normal = (pos - global_position).normalized()
	if normal.length_squared() < 0.01:
		normal = -dir.normalized()
	# Continuous beams can call every physics tick. Keep the response lively
	# without constructing sixty particle emitters and scars per second.
	var make_mark := _fx_cooldown <= 0.0
	if make_mark:
		_fx_cooldown = 0.075
	FX.surface_impact(field, field, pos, normal, "rock", dmg, make_mark)
