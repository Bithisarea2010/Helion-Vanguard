class_name SpaceDust
extends MultiMeshInstance3D
## Passing dust motes around the camera — sells speed. Streaks along velocity.

const COUNT := 220
const RANGE := 130.0

var player: Node3D = null
var _pts: Array[Vector3] = []

func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, 1.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.55, 0.62, 0.75, 1.0)
	m.disable_receive_shadows = true
	bm.material = m
	mm.mesh = bm
	mm.instance_count = COUNT
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in COUNT:
		_pts.append(Vector3(randf_range(-RANGE, RANGE), randf_range(-RANGE, RANGE), randf_range(-RANGE, RANGE)))

func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		visible = false
		return
	var vel: Vector3 = player.linear_velocity if player is RigidBody3D else Vector3.ZERO
	var speed := vel.length()
	if speed < 25.0:
		visible = false
		return
	visible = true
	var ctr: Vector3 = player.global_position
	var stretch := clampf(speed * 0.045, 0.4, 9.0)
	var dirv := vel.normalized()
	var basis_z := dirv
	var up := Vector3.UP if absf(basis_z.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var bx := up.cross(basis_z).normalized()
	var by := basis_z.cross(bx)
	var b := Basis(bx, by, basis_z).scaled(Vector3(1, 1, stretch))
	for i in COUNT:
		# wrap each mote into the moving box around the player
		var rel := _pts[i] - ctr
		rel.x = wrapf(rel.x, -RANGE, RANGE)
		rel.y = wrapf(rel.y, -RANGE, RANGE)
		rel.z = wrapf(rel.z, -RANGE, RANGE)
		_pts[i] = ctr + rel
		multimesh.set_instance_transform(i, Transform3D(b, _pts[i]))
