class_name EngineTrail
extends MeshInstance3D
## Additive exhaust ribbon behind an engine socket.
## Camera-facing strip rebuilt each frame from a position history.
##
## The ribbon is built with a THREE-vertex profile (edge / hot core / edge) so it
## has a soft falloff across its width. The previous two-vertex strip painted one
## flat colour edge to edge, and because the material is additive the overlapping
## segments saturated into the solid white slabs that hung behind every ship.

const MAX_PTS := 40
const MAX_LEN := 42.0                # metres of ribbon, regardless of speed

var socket: Node3D = null            # world-space emitter to follow
var color := Color(0.3, 0.7, 1.0)
var width := 0.55
var life := 0.5                      # seconds a point survives
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
	# THE reason this ribbon has always drawn as a solid white slab. Additive
	# blending does not switch on an alpha pipeline in Godot: with the default
	# TRANSPARENCY_DISABLED the generated shader hard-codes ALPHA = 1.0, so
	# every per-vertex alpha below — the age fade, the view-alignment fade, the
	# near fade and the soft edge-to-core falloff — was computed and then
	# discarded, and every quad drew at full colour.
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material_override = m

static func attach(parent_world: Node, emitter: Node3D, col: Color, w := 0.55,
		vel_ref: Node3D = null) -> EngineTrail:
	if "--notrails" in OS.get_cmdline_user_args():
		return null
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
	if speed > min_speed:
		var p: Vector3 = socket.global_position
		if _pts.is_empty() or _pts[0].p.distance_squared_to(p) > 0.09:
			_pts.push_front({"p": p, "t": 0.0})
			if _pts.size() > MAX_PTS:
				_pts.pop_back()
	# Hard length cap. Age alone let the ribbon reach speed x life ~ 125 m at
	# combat speed; anything past MAX_LEN is behind the chase camera anyway, so
	# it only ever contributed additive haze the fades then had to fight.
	var head: Vector3 = _pts[0].p if not _pts.is_empty() else Vector3.ZERO
	while _pts.size() > 3 and head.distance_squared_to(_pts[_pts.size() - 1].p) > MAX_LEN * MAX_LEN:
		_pts.pop_back()
	_rebuild()

func _rebuild() -> void:
	_im.clear_surfaces()
	if _pts.size() < 3:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cam_pos := cam.global_position
	var cam_fwd := -cam.global_transform.basis.z
	var n := _pts.size()
	# precompute the ribbon spine so the triangle pass stays a flat loop
	var core: PackedVector3Array = PackedVector3Array()
	var side: PackedVector3Array = PackedVector3Array()
	var alpha: PackedFloat32Array = PackedFloat32Array()
	core.resize(n); side.resize(n); alpha.resize(n)
	for idx in n:
		var pt: Dictionary = _pts[idx]
		var pp: Vector3 = pt.p
		var head_t := float(idx) / float(n - 1)
		var age_f: float = 1.0 - float(pt.t) / life
		# narrow at the nozzle, swell over the first third, taper to the tail
		var swell := lerpf(0.35, 1.0, clampf(head_t * 3.0, 0.0, 1.0)) * (1.0 - head_t * 0.55)
		var dirv: Vector3
		if idx < n - 1:
			dirv = (_pts[idx + 1].p as Vector3) - pp
		else:
			dirv = pp - (_pts[idx - 1].p as Vector3)
		if dirv.length_squared() < 0.0001:
			dirv = Vector3.FORWARD
		dirv = dirv.normalized()
		var cam_d := (cam_pos - pp).length()
		var to_cam: Vector3 = (cam_pos - pp) / maxf(cam_d, 0.001)
		var s := dirv.cross(to_cam)
		if s.length_squared() < 0.0001:
			s = Vector3.UP
		core[idx] = pp
		side[idx] = s.normalized() * width * boost_gain * swell
		# The chase camera looks straight down its own ship's trail. Seen end-on
		# a ribbon has no real width, but the billboarded strip keeps its full
		# width and every segment stacks additively into a solid white column.
		# Fading by view alignment is both the fix and the physically honest
		# behaviour for a flat ribbon.
		var align := absf(dirv.dot(to_cam))
		var align_fade := 1.0 - align * align * align
		# Fade out as a point approaches, then passes, the lens. Fading on raw
		# DISTANCE (what this did before) is wrong in a chase view: the ribbon
		# always overshoots the camera, and once a point is behind it the distance
		# starts growing again — so the overshot half came back to full brightness
		# and painted the white wedges across the lower half of the frame. Depth
		# along the view axis goes negative back there and stays faded.
		var depth := (pp - cam_pos).dot(cam_fwd)
		var near_fade := clampf((depth - 2.5) / 14.0, 0.0, 1.0)
		alpha[idx] = age_f * age_f * (1.0 - head_t * 0.35) * near_fade * align_fade

	var edge := Color(color.r * 0.5, color.g * 0.58, color.b * 0.72)
	# keep the core tinted rather than near-white: additive segments seen
	# broadside stack, and a white core reached 1.0 across the whole ribbon
	var hot := Color(color.r * 0.85 + 0.16, color.g * 0.85 + 0.2, color.b * 0.85 + 0.24)
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for idx in n - 1:
		# these were tuned while ALPHA was being discarded, i.e. against a
		# constant 1.0 — now that the fades apply they have to come back up
		var e0 := Color(edge.r, edge.g, edge.b, alpha[idx] * 0.18)
		var e1 := Color(edge.r, edge.g, edge.b, alpha[idx + 1] * 0.18)
		var h0 := Color(hot.r, hot.g, hot.b, alpha[idx] * 0.45)
		var h1 := Color(hot.r, hot.g, hot.b, alpha[idx + 1] * 0.45)
		var l0: Vector3 = core[idx] - side[idx]
		var r0: Vector3 = core[idx] + side[idx]
		var l1: Vector3 = core[idx + 1] - side[idx + 1]
		var r1: Vector3 = core[idx + 1] + side[idx + 1]
		# left half: edge -> hot core, then right half: hot core -> edge
		_quad(l0, e0, core[idx], h0, core[idx + 1], h1, l1, e1)
		_quad(core[idx], h0, r0, e0, r1, e1, core[idx + 1], h1)
	_im.surface_end()

## One quad as two triangles, each corner carrying its own colour + alpha.
func _quad(p0: Vector3, c0: Color, p1: Vector3, c1: Color,
		p2: Vector3, c2: Color, p3: Vector3, c3: Color) -> void:
	_im.surface_set_color(c0); _im.surface_add_vertex(p0)
	_im.surface_set_color(c1); _im.surface_add_vertex(p1)
	_im.surface_set_color(c2); _im.surface_add_vertex(p2)
	_im.surface_set_color(c0); _im.surface_add_vertex(p0)
	_im.surface_set_color(c2); _im.surface_add_vertex(p2)
	_im.surface_set_color(c3); _im.surface_add_vertex(p3)
