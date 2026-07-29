class_name ExhaustPlume
extends MeshInstance3D
## A single additive cone behind an engine nozzle, scaled by throttle.
##
## One mesh instance per engine, one draw call, no particle simulation and no
## additive self-overdraw. `set_power()` is the only per-frame work and it just
## writes a scale plus one shader uniform.

var _mat: ShaderMaterial
var _base_len := 4.0
var _base_rad := 0.45
var _nozzle_z := 0.0

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
	p.rotation_degrees = Vector3(90, 0, 0)
	p._nozzle_z = at.z
	p.position = at
	p.visible = false
	return p

## power 0..1 (throttle); boost lengthens and brightens the plume
func set_power(power: float, boost := false) -> void:
	if power <= 0.02:
		visible = false
		return
	visible = true
	var length := _base_len * (0.35 + power * 0.65) * (1.55 if boost else 1.0)
	var rad := _base_rad * (0.72 + power * 0.28) * (1.12 if boost else 1.0)
	scale = Vector3(rad, length, rad)
	# the cone's origin is its centre, so push it aft by half its length to keep
	# the throat pinned to the nozzle
	position.z = _nozzle_z + length * 0.5
	_mat.set_shader_parameter("intensity", (0.55 + power * 0.75) * (1.35 if boost else 1.0))
