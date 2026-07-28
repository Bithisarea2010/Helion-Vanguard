class_name Flare
extends Node3D
## Countermeasure flare: seduces heat/radar seekers while it burns.

var team := 0
var vel := Vector3.ZERO
var strength := 0.85
var _ttl := 3.0

static func deploy(battle: Node, pos: Vector3, base_vel: Vector3, own_team: int) -> Flare:
	var f := Flare.new()
	f.team = own_team
	f.vel = base_vel * 0.4 + Vector3(randf_range(-14, 14), randf_range(-14, 14), randf_range(-14, 14))
	battle.add_child(f)
	f.global_position = pos
	f._build()
	battle.flares.append(f)
	AudioMgr.play_3d("flare", pos, -4.0)
	return f

func get_velocity() -> Vector3:
	return vel

func _build() -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.35)
	l.light_energy = 3.0
	l.omni_range = 20.0
	l.shadow_enabled = false
	add_child(l)
	var p := GPUParticles3D.new()
	p.amount = 30
	p.lifetime = 0.6
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.spread = 180.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.4; pm.scale_max = 1.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.45, 1.0))
	grad.set_color(1, Color(1.0, 0.4, 0.1, 0.0))
	var gt := GradientTexture1D.new(); gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new(); quad.size = Vector2(0.8, 0.8)
	p.draw_pass_1 = quad
	p.material_override = FX._add_mat(Color(1, 1, 1))
	add_child(p)
	p.emitting = true

func _physics_process(delta: float) -> void:
	_ttl -= delta
	global_position += vel * delta
	vel *= 0.98
	if _ttl <= 0.0:
		queue_free()
