class_name Missile
extends Node3D
## Guided missile with proportional navigation, countermeasure spoofing, proximity fuse.

var mdef: Dictionary
var team := 1
var shooter: Node3D
var target: Node3D = null          # Combatant, Subsystem, Flare or null
var vel := Vector3.ZERO
var speed_max := 300.0
var _ttl := 20.0
var _armed := false
var _arm_t := 0.4
var _cm_checked := {}
var _battle: Node = null
var _plume: ExhaustPlume = null
var _light: OmniLight3D = null
var _flicker := 0.0

static func launch(battle: Node, from: Vector3, dir: Vector3, inherit_vel: Vector3,
		def: Dictionary, tgt: Node3D, own_team: int, own: Node3D) -> Missile:
	var m := Missile.new()
	m.mdef = def
	m.team = own_team
	m.shooter = own
	m.target = tgt
	m.speed_max = def.speed
	m.vel = dir * maxf(def.speed * 0.35, 60.0) + inherit_vel
	m._ttl = def.range / def.speed * 2.2
	m._battle = battle
	battle.add_child(m)
	m.global_position = from
	m._build_visual()
	FX.launch_flash(battle, from, dir)
	AudioMgr.play_3d("missile_launch", from, 2.0)
	# warn the target if it's the player
	if tgt and tgt.is_in_group("player") and tgt.has_method("incoming_missile"):
		tgt.incoming_missile(m)
	if tgt and tgt.has_method("ai_missile_warning"):
		tgt.ai_missile_warning(m)
	return m

func _build_visual() -> void:
	# body + red nose + 4 tail fins
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.085; cm.bottom_radius = 0.085
	cm.height = 1.05; cm.radial_segments = 12
	body.mesh = cm
	body.rotation_degrees = Vector3(-90, 0, 0)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.78, 0.79, 0.84); bm.metallic = 0.85; bm.roughness = 0.28
	body.material_override = bm
	add_child(body)
	# warning band aft of the seeker, the one detail that reads at 30 m
	var band := MeshInstance3D.new()
	var bcm := CylinderMesh.new()
	bcm.top_radius = 0.092; bcm.bottom_radius = 0.092
	bcm.height = 0.13; bcm.radial_segments = 12
	band.mesh = bcm
	band.rotation_degrees = Vector3(-90, 0, 0)
	band.position.z = -0.34
	var bandm := StandardMaterial3D.new()
	bandm.albedo_color = Color(0.85, 0.55, 0.05); bandm.metallic = 0.2; bandm.roughness = 0.6
	band.material_override = bandm
	add_child(band)
	var nose := MeshInstance3D.new()
	var ncm := CylinderMesh.new()
	ncm.top_radius = 0.0; ncm.bottom_radius = 0.085
	ncm.height = 0.36; ncm.radial_segments = 12
	nose.mesh = ncm
	nose.rotation_degrees = Vector3(-90, 0, 0)
	nose.position.z = -0.68
	var nm := StandardMaterial3D.new()
	nm.albedo_color = Color(0.30, 0.05, 0.04); nm.metallic = 0.3; nm.roughness = 0.25
	nm.emission_enabled = true
	nm.emission = Color(1.0, 0.18, 0.10)      # live seeker head
	nm.emission_energy_multiplier = 1.4
	nose.material_override = nm
	add_child(nose)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.20, 0.21, 0.25); fm.metallic = 0.8; fm.roughness = 0.35
	for k in 4:
		var fin := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(0.02, 0.20, 0.26)
		fin.mesh = fb
		fin.material_override = fm
		add_child(fin)
		fin.position = Vector3(0, 0, 0.42)
		fin.rotation_degrees = Vector3(0, 0, 45 + k * 90)
		fin.position += fin.transform.basis.y * 0.11
	# Motor: one additive cone shell, the same construction as the ship engines.
	# The old version was a particle fire emitter, which at missile scale was a
	# handful of overlapping billboards that clipped into an orange rectangle.
	_plume = ExhaustPlume.create(self, Vector3(0, 0, 0.60), Color(1.0, 0.42, 0.12), 0.11, 1.5)
	_plume.set_power(1.0, false)
	FX.rocket_smoke(self, Vector3(0, 0, 0.72), 0.55)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.4, 0.12)
	_light.light_energy = 2.4
	_light.omni_range = 11.0
	_light.shadow_enabled = false
	add_child(_light)
	# red-hot exhaust stripe
	var sock := Node3D.new()
	add_child(sock)
	sock.position = Vector3(0, 0, 0.6)
	var tr := EngineTrail.new()
	tr.socket = sock
	tr.color = Color(1.0, 0.34, 0.10)
	tr.width = 0.16
	tr.life = 0.55
	tr.min_speed = 0.0
	_battle.add_child(tr)

func _physics_process(delta: float) -> void:
	_ttl -= delta
	_arm_t -= delta
	# solid-motor roughness: the plume and its light breathe together, so the
	# missile pulses instead of towing a constant-brightness lamp
	_flicker += delta * 34.0
	var burn := 0.82 + 0.18 * sin(_flicker) + 0.10 * sin(_flicker * 2.7)
	if _plume:
		_plume.set_power(clampf(burn, 0.0, 1.0), false)
	if _light:
		_light.light_energy = 2.4 * burn
	if _arm_t <= 0.0:
		_armed = true
	if _ttl <= 0.0:
		_detonate(false)
		return
	# --- countermeasure seduction ---
	if _battle and target and is_instance_valid(target) and not (target is Flare):
		for fl in _battle.flares:
			if not is_instance_valid(fl) or _cm_checked.has(fl.get_instance_id()):
				continue
			if fl.team == team:
				continue
			var d := global_position.distance_to(fl.global_position)
			if d < 350.0:
				_cm_checked[fl.get_instance_id()] = true
				var spoof_chance: float = fl.strength * (1.0 - mdef.cm_resist)
				if randf() < spoof_chance:
					target = fl
	# --- guidance: proportional navigation ---
	var desired := -global_transform.basis.z
	if target and is_instance_valid(target) and (not ("alive" in target) or target.alive or target is Flare):
		var tpos: Vector3 = target.global_position
		var tvel: Vector3 = target.get_velocity() if target.has_method("get_velocity") else Vector3.ZERO
		var aim := Projectiles.lead_point(global_position, Vector3.ZERO, tpos, tvel, Vector3.ZERO, maxf(vel.length(), 50.0))
		desired = (aim - global_position).normalized()
		# proximity fuse
		if _armed and global_position.distance_to(tpos) < (8.0 if not (target is Flare) else 4.0):
			_detonate(true)
			return
	var fwd := vel.normalized() if vel.length() > 1.0 else -global_transform.basis.z
	var max_turn: float = deg_to_rad(mdef.turn) * delta
	var ang := fwd.angle_to(desired)
	if ang > 0.0001 and mdef.turn > 0.0:
		var axis := fwd.cross(desired).normalized()
		if axis.is_finite() and axis.length_squared() > 0.5:
			fwd = fwd.rotated(axis, minf(ang, max_turn))
	var spd := minf(vel.length() + mdef.accel * delta, speed_max)
	vel = fwd * spd
	# collision check
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + vel * delta)
	if shooter is CollisionObject3D and is_instance_valid(shooter):
		q.exclude = [shooter.get_rid()]
	var hit := space.intersect_ray(q)
	if hit:
		global_position = hit.position
		var recv: Node = hit.collider
		while recv and not recv.has_method("take_hit"):
			recv = recv.get_parent()
		if recv and _armed:
			recv.take_hit(mdef.dmg, hit.position, vel.normalized(), 0.5, 1.0, 1.0, shooter)
		_detonate(false)
		return
	global_position += vel * delta
	if vel.length() > 1.0:
		look_at(global_position + vel.normalized(), Vector3.UP if absf(vel.normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT)

func _detonate(direct: bool) -> void:
	if direct and target and is_instance_valid(target) and target.has_method("take_hit"):
		target.take_hit(mdef.dmg, global_position, vel.normalized(), 0.5, 1.0, 1.0, shooter)
	elif _armed:
		# splash to nearby combatants
		if _battle:
			for c in _battle.all_combatants():
				if is_instance_valid(c) and c.alive and c.team != team:
					var d: float = global_position.distance_to(c.global_position)
					if d < 25.0:
						c.take_hit(mdef.dmg * clampf(1.0 - d / 25.0, 0.0, 0.6), global_position, vel.normalized(), 0.4, 1.0, 1.0, shooter)
	# a warhead is not a stray cannon round: kind 1 gives it the shockwave,
	# debris and smoke the old kind-0 burst skipped entirely
	FX.explosion(get_parent(), global_position, 1)
	queue_free()
