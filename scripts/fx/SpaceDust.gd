class_name SpaceDust
extends MultiMeshInstance3D
## Passing dust motes around the camera — sells speed. Streaks along velocity.
##
## The multimesh is built once and never touched again: the node follows the
## player and a vertex shader does the per-mote wrap and velocity stretch.
## (The previous version wrote 220 instance transforms from GDScript every
## frame, which is pure main-thread cost in a game that is already CPU-bound.)

const COUNT := 260
const RANGE := 130.0

var player: Node3D = null
var _mat: ShaderMaterial

func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, 1.0)
	mm.mesh = bm
	mm.instance_count = COUNT
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for i in COUNT:
		# instances sit on a static lattice; the shader wraps them around the
		# player, so this transform is written exactly once
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(
			rng.randf_range(-RANGE, RANGE),
			rng.randf_range(-RANGE, RANGE),
			rng.randf_range(-RANGE, RANGE))))
	multimesh = mm
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/space_dust.gdshader")
	_mat.set_shader_parameter("range_half", RANGE)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# world-space wrap means the motes leave the mesh's own bounds
	custom_aabb = AABB(Vector3(-RANGE, -RANGE, -RANGE) * 1.2, Vector3(RANGE, RANGE, RANGE) * 2.4)
	top_level = true

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
	global_position = player.global_position
	global_rotation = Vector3.ZERO
	# two uniforms per frame replace 260 instance-transform writes
	_mat.set_shader_parameter("vel_dir", vel / maxf(speed, 0.001))
	_mat.set_shader_parameter("stretch", clampf(speed * 0.045, 0.4, 9.0))
	_mat.set_shader_parameter("origin", player.global_position)
