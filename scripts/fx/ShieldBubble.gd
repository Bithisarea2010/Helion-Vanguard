class_name ShieldBubble
extends MeshInstance3D
## Icosahedral shield matrix — visible only where and when it is hit.
##
## One geodesic icosphere per ship, hidden until a round lands. Each impact
## lights the hemisphere facing it with an expanding lattice ring; when the last
## ring decays the node hides again, so an unhit ship pays nothing at all.
##
## The mesh is built once and shared by every ship in the game. It is built
## NON-INDEXED with barycentric coordinates in COLOR so `shaders/shield.gdshader`
## can draw the sphere's own triangulation as a true wireframe — a procedural
## triangle pattern cannot be made to line up with a geodesic sphere's faces.

const MAX_IMPACTS := 6
const IMPACT_LIFE := 0.85          # seconds for a ring to sweep and fade
const IDLE_EPS := 0.001

static var _shared_mesh: ArrayMesh = null
static var _shader: Shader = null

var _mat: ShaderMaterial = null
var _dirs: PackedVector3Array = PackedVector3Array()
var _ages: PackedFloat32Array = PackedFloat32Array()
var _host: Node3D = null
var _charge := 1.0
var _live := 0

static func clear_cache() -> void:
	_shared_mesh = null
	_shader = null

## Geodesic icosphere: an icosahedron subdivided `subdiv` times, each triangle
## emitted as three independent vertices carrying barycentric coordinates.
static func icosphere(subdiv := 2) -> ArrayMesh:
	if _shared_mesh != null:
		return _shared_mesh
	var t := (1.0 + sqrt(5.0)) * 0.5
	var base := [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	for i in base.size():
		base[i] = (base[i] as Vector3).normalized()
	var faces := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]
	var tris: Array = []
	for f in faces:
		tris.append([base[f[0]], base[f[1]], base[f[2]]])
	for _s in subdiv:
		var out: Array = []
		for tri in tris:
			var a: Vector3 = tri[0]
			var b: Vector3 = tri[1]
			var c: Vector3 = tri[2]
			var ab := ((a + b) * 0.5).normalized()
			var bc := ((b + c) * 0.5).normalized()
			var ca := ((c + a) * 0.5).normalized()
			out.append([a, ab, ca])
			out.append([b, bc, ab])
			out.append([c, ca, bc])
			out.append([ab, bc, ca])
		tris = out
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	const BARY := [Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1)]
	for tri in tris:
		for i in 3:
			var v: Vector3 = tri[i]
			verts.append(v)
			norms.append(v)
			cols.append(BARY[i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# an inflated custom AABB stops the shell popping out at grazing angles when
	# the ship is near the edge of frame
	am.custom_aabb = AABB(Vector3(-1.2, -1.2, -1.2), Vector3(2.4, 2.4, 2.4))
	_shared_mesh = am
	return am

## `bounds` is the host's model AABB; the shell is sized to enclose it.
static func attach(host: Node3D, bounds: AABB, color: Color) -> ShieldBubble:
	var sb := ShieldBubble.new()
	sb.mesh = icosphere(2)
	sb._host = host
	sb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sb.visible = false
	# radius from the hull's own half-diagonal plus a little standoff, so a
	# gunship's shell is a gunship-sized shell
	var r := maxf(bounds.size.length() * 0.5, 2.0) * 1.12
	sb.scale = Vector3.ONE * r
	sb.position = bounds.position + bounds.size * 0.5
	sb.set_meta("shield_color", color)
	host.add_child(sb)
	return sb

func _ensure_material() -> void:
	if _mat != null:
		return
	if _shader == null:
		_shader = load("res://shaders/shield.gdshader")
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.set_shader_parameter("shield_color", get_meta("shield_color", Color(0.35, 0.68, 1.0)))
	material_override = _mat
	_dirs.resize(MAX_IMPACTS)
	_ages.resize(MAX_IMPACTS)
	for i in MAX_IMPACTS:
		_ages[i] = 1.0

## `world_pos` is where the round actually landed. `charge` is the shield's
## remaining fraction, which drives the colour shift and crazing.
func register_hit(world_pos: Vector3, charge := 1.0) -> void:
	_ensure_material()
	_charge = clampf(charge, 0.0, 1.0)
	var local := (to_local(world_pos)).normalized()
	if not local.is_finite() or local.length_squared() < 0.5:
		local = Vector3.FORWARD
	# reuse the oldest slot: a burst of autocannon fire must not starve the ring
	# buffer and leave the newest (most visible) hit undrawn
	var slot := 0
	var oldest := -1.0
	for i in MAX_IMPACTS:
		if _ages[i] >= 1.0:
			slot = i
			break
		if _ages[i] > oldest:
			oldest = _ages[i]
			slot = i
	_dirs[slot] = local
	_ages[slot] = 0.0
	visible = true
	set_process(true)

func _process(delta: float) -> void:
	if _mat == null:
		set_process(false)
		return
	var step := delta / IMPACT_LIFE
	var pack := PackedVector4Array()
	pack.resize(MAX_IMPACTS)
	_live = 0
	for i in MAX_IMPACTS:
		var age := _ages[i]
		if age < 1.0:
			age = minf(age + step, 1.0)
			_ages[i] = age
			if age < 1.0:
				_live += 1
		var d := _dirs[i]
		pack[i] = Vector4(d.x, d.y, d.z, age)
	_mat.set_shader_parameter("impacts", pack)
	_mat.set_shader_parameter("impact_count", MAX_IMPACTS)
	_mat.set_shader_parameter("charge", _charge)
	if _live == 0:
		visible = false
		set_process(false)

## Shield dropped to zero: one last full-shell flare, then dark.
func collapse() -> void:
	_ensure_material()
	_charge = 0.0
	for i in 4:
		var a := TAU * float(i) / 4.0
		_dirs[i] = Vector3(cos(a), 0.35, sin(a)).normalized()
		_ages[i] = 0.0
	visible = true
	set_process(true)
	AudioMgr.play_3d("shield_down", global_position, -2.0)
