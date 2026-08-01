class_name ExhaustPlume
extends MeshInstance3D
## A single additive cone behind an engine nozzle, scaled by throttle.
##
## One mesh instance per engine, one draw call, no particle simulation and no
## additive self-overdraw. `set_power()` is the only per-frame work and it just
## writes a transform plus two shader uniforms.
##
## 1.2 additions:
##   * a nozzle iris — the throat radius contracts with throttle and flares
##     open under afterburner, so the engine has visible mechanical state
##   * thrust vectoring via `set_vector()`: the cone gimbals with the pilot's
##     pitch/yaw demand instead of staying welded to the hull axis
##   * optional refractive heat wash (player ship, High/Ultra only)

var _mat: ShaderMaterial
var _base_len := 4.0
var _base_rad := 0.45
var _nozzle := Vector3.ZERO
var _gimbal := Vector2.ZERO          # x = pitch rad, y = yaw rad
var _haze: MeshInstance3D = null
var _haze_mat: ShaderMaterial = null

static func create(parent: Node3D, at: Vector3, glow: Color, radius := 0.45,
		length := 4.0) -> ExhaustPlume:
	var p := ExhaustPlume.new()
	var cyl := CylinderMesh.new()
	# mesh runs along +Y; after the +90 deg X rotation below, +Y maps to +Z,
	# which is aft on these ships. Top == tail, so the top is the flared end.
	cyl.top_radius = radius * 1.5
	cyl.bottom_radius = radius * 0.42
	cyl.height = 1.0
	cyl.radial_segments = 14
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	p.mesh = cyl
	p._base_len = length
	p._base_rad = radius
	p._mat = ShaderMaterial.new()
	p._mat.shader = load("res://shaders/exhaust.gdshader")
	p._mat.set_shader_parameter("tail_color", glow)
	p._mat.set_shader_parameter("core_color",
		Color(minf(glow.r * 0.4 + 0.62, 1.0), minf(glow.g * 0.4 + 0.66, 1.0),
			minf(glow.b * 0.4 + 0.7, 1.0)))
	p._mat.set_shader_parameter("seed", randf() * 12.0)
	p.material_override = p._mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p._nozzle = at
	p.position = at
	p.rotation = Vector3(PI * 0.5, 0, 0)
	p.visible = false
	return p

## Screen-space refraction behind the throat. Deliberately opt-in: it is the only
## effect in the game that samples the screen, so it is fitted to the player's
## ship alone rather than to every hull in the fleet.
func enable_haze() -> void:
	if _haze != null or "--nohaze" in OS.get_cmdline_user_args():
		return
	var cyl := CylinderMesh.new()
	# Radii are multiples of the base radius, exactly like the plume mesh — the
	# per-frame transform then scales both by the same amount. Kept close to the
	# plume's own width on purpose: a wide haze cone smears a visibly swirled
	# copy of whatever is behind the ship across a third of the frame, which
	# reads as a rendering fault rather than as hot air.
	cyl.top_radius = _base_rad * 3.0
	cyl.bottom_radius = _base_rad * 1.2
	cyl.height = 1.0
	cyl.radial_segments = 12
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_haze = MeshInstance3D.new()
	_haze.mesh = cyl
	_haze_mat = ShaderMaterial.new()
	_haze_mat.shader = load("res://shaders/heat_haze.gdshader")
	_haze_mat.set_shader_parameter("seed", randf() * 20.0)
	_haze.material_override = _haze_mat
	_haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# drawn before the additive plume so the plume lands on top of the distortion
	_haze.sorting_offset = -0.5
	add_child(_haze)

## Nozzle gimbal, radians. Small: real vectoring nozzles move a few degrees.
func set_vector(pitch: float, yaw: float) -> void:
	_gimbal = Vector2(clampf(pitch, -0.35, 0.35), clampf(yaw, -0.35, 0.35))

## power 0..1 (throttle); boost lengthens, brightens and lights the afterburner
func set_power(power: float, boost := false) -> void:
	if power <= 0.02:
		if visible:
			visible = false
		return
	visible = true
	var length := _base_len * (0.35 + power * 0.65) * (1.55 if boost else 1.0)
	# nozzle iris: the throat pinches as throttle comes up (higher exit velocity)
	# and flares open when the afterburner lights
	var iris := lerpf(1.0, 0.72, power) * (1.30 if boost else 1.0)
	var rad := _base_rad * (0.72 + power * 0.28) * iris
	# gimbal in the PARENT frame, then re-apply the mesh's own +90 deg X so the
	# cone still runs aft rather than up
	var basis := Basis(Vector3.RIGHT, _gimbal.x) * Basis(Vector3.UP, _gimbal.y) \
		* Basis.from_euler(Vector3(PI * 0.5, 0, 0))
	var aft := basis * Vector3(0, 1, 0)
	# The cone's origin is its centre, so push it aft by half its length to keep
	# the throat pinned to the nozzle — along the GIMBALED axis, not the hull's.
	#
	# The scale MUST be right-multiplied. `Basis.scaled()` scales in the PARENT
	# frame, so `basis.scaled(rad, length, rad)` stretches along the ship's up
	# axis instead of along the plume's own length: every engine in the game
	# became a several-hundred-metre vertical lens standing on the hull, and the
	# refractive haze child inherited it as a dark spindle across the whole frame.
	transform = Transform3D(basis * Basis.from_scale(Vector3(rad, length, rad)),
		_nozzle + aft * (length * 0.5))
	var mach := clampf((power - 0.45) / 0.55, 0.0, 1.0) * (1.0 if boost else 0.45)
	_mat.set_shader_parameter("intensity", (0.55 + power * 0.75) * (1.35 if boost else 1.0))
	_mat.set_shader_parameter("mach", mach)
	if _haze_mat:
		_haze_mat.set_shader_parameter("power", clampf(power * (1.6 if boost else 1.0), 0.0, 1.6))
