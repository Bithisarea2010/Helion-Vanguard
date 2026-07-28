class_name EngineTrail
extends MeshInstance3D
## Sleek additive ribbon trail behind an engine socket ("jet stripes").
## Camera-facing strip rebuilt each frame from a position history.

var socket: Node3D = null            # world-space emitter to follow
var color := Color(0.3, 0.7, 1.0)
var width := 0.55
var life := 0.55                     # seconds a point survives
var boost_gain := 1.0                # external intensity multiplier (boost)
var min_speed := 6.0                 # below this the ribbon fades out

var _pts: Array = []                 # [{p: Vector3, t: age}]
var _im: ImmediateMesh
var _vel_ref: Node3D = null          # body whose speed gates the trail

func _init() -> void:
	_im = ImmediateMesh.new()
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	material_override = m

static func attach(parent_world: Node, emitter: Node3D, col: Color, w := 0.55,
		vel_ref: Node3D = null) -> EngineTrail:
	var t := EngineTrail.new()
	t.socket = emitter
	t.color = col
	t.width = w
	t._vel_ref = vel_ref
	parent_world.add_child(t)
	return t

func _process(delta: float) -> void:
	if socket == null or not is_instance_valid(socket):
		queue_free()
		return
	global_position = Vector3.ZERO
	global_rotation = Vector3.ZERO
	# age and expire
	var i := _pts.size() - 1
	while i >= 0:
		_pts[i].t += delta
		if _pts[i].t > life:
			_pts.remove_at(i)
		i -= 1
	# sample
	var speed := 999.0
	if _vel_ref and is_instance_valid(_vel_ref) and _vel_ref is RigidBody3D:
		speed = (_vel_ref as RigidBody3D).linear_velocity.length()
	var emitting := speed > min_speed
	if emitting:
		var p: Vector3 = socket.global_position
		if _pts.is_empty() or _pts[0].p.distance_squared_to(p) > 0.04:
			_pts.push_front({"p": p, "t": 0.0})
			if _pts.size() > 60:
				_pts.pop_back()
	_rebuild()

func _rebuild() -> void:
	_im.clear_surfaces()
	if _pts.size() < 2:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cam_pos := cam.global_position
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for idx in _pts.size():
		var pt: Dictionary = _pts[idx]
		var pp: Vector3 = pt.p
		var frac := 1.0 - float(idx) / float(_pts.size())
		var age_f: float = 1.0 - float(pt.t) / life
		var fade: float = age_f * frac
		# profile: narrow at the nozzle, swell over the first third, taper to the tail
		var head_t := float(idx) / maxf(float(_pts.size() - 1), 1.0)
		var swell := lerpf(0.30, 1.0, clampf(head_t * 3.2, 0.0, 1.0))
		fade *= lerpf(0.45, 1.0, clampf(head_t * 4.0, 0.0, 1.0))
		var dirv: Vector3
		if idx < _pts.size() - 1:
			dirv = (_pts[idx + 1].p as Vector3) - pp
		else:
			dirv = pp - (_pts[idx - 1].p as Vector3)
		if dirv.length_squared() < 0.0001:
			dirv = Vector3.FORWARD
		dirv = dirv.normalized()
		var cam_d := (cam_pos - pp).length()
		var to_cam: Vector3 = (cam_pos - pp) / maxf(cam_d, 0.001)
		var side := dirv.cross(to_cam)
		if side.length_squared() < 0.0001:
			side = Vector3.UP
		side = side.normalized() * width * boost_gain * swell * (0.25 + 0.75 * age_f)
		# fade out when the ribbon sweeps close to the camera (prevents the
		# fullscreen wedge when the chase cam sits inside a turning trail)
		var near_fade := clampf((cam_d - 2.5) / 7.0, 0.0, 1.0)
		var c := Color(color.r * 1.35, color.g * 1.35, color.b * 1.35, fade * 0.7 * near_fade)
		_im.surface_set_color(c)
		_im.surface_add_vertex(pp - side)
		_im.surface_set_color(c)
		_im.surface_add_vertex(pp + side)
	_im.surface_end()
