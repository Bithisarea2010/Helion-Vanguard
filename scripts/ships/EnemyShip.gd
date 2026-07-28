class_name EnemyShip
extends Combatant
## AI fighter/bomber/drone: state machine with predicted aim, evasion, countermeasures.

enum S { PATROL, PURSUE, ATTACK, BREAK, EVADE, RETREAT, ESCORT }

var eid := "jackal"
var edef: Dictionary
var battle: Node
var weapons: WeaponSystem
var state: int = S.PATROL
var target: Node3D = null
var escort: Node3D = null           # ship to protect (bomber escort duty)
var patrol_center := Vector3.ZERO
var accel_estimate := Vector3.ZERO
var _vel_prev := Vector3.ZERO

var _think := 0.0
var _state_t := 0.0
var _break_dir := Vector3.ZERO
var _jink := Vector3.ZERO
var _jink_t := 0.0
var _aim_point := Vector3.ZERO
var _aim_refresh := 0.0
var _msl_cd := 8.0
var cm_left := 6
var _cm_cd := 0.0
var _has_token := false
var _acc := 0.65
var _reaction := 0.5
var _aggression := 1.0
var _model_root: Node3D

func _init() -> void:
	team = TEAM_HOSTILE

func setup(id: String, batl: Node, spawn_team := TEAM_HOSTILE) -> void:
	eid = id
	battle = batl
	team = spawn_team
	edef = ShipDB.ENEMIES[id]
	var diff: Dictionary = Game.difficulty_scale()
	combat_setup(edef.hull, edef.shield, edef.shield_regen, 0.2)
	cm_left = edef.cm_count
	score_value = edef.score
	display_name = edef.label
	_acc = edef.acc * diff.accuracy
	_reaction = clampf(0.35 * diff.reaction / maxf(edef.acc, 0.2), 0.12, 1.4)
	_aggression = diff.aggression
	mass = 10.0 * edef.scale
	gravity_scale = 0.0
	can_sleep = false
	linear_damp = 0.0
	angular_damp = 2.0
	collision_layer = 1
	collision_mask = 1 | 2 | 4
	add_to_group("hostiles" if team == TEAM_HOSTILE else "friendlies")
	_load_model()
	weapons = WeaponSystem.new()
	add_child(weapons)
	var ma: Array[Vector3] = []
	for v in edef.get("muzzles", [Vector3(0.7, 0, -6.0), Vector3(-0.7, 0, -6.0)]):
		ma.append(v)
	weapons.setup(self, battle.projectiles, edef.weapon, edef.weapon, ma, ma)
	weapons.group = 0
	_msl_cd = randf_range(6.0, 14.0)
	patrol_center = global_position

func _load_model() -> void:
	_model_root = Node3D.new()
	add_child(_model_root)
	var aabb := AABB(Vector3(-3, -1, -6), Vector3(6, 2, 12))
	if ResourceLoader.exists(edef.model):
		var inst: Node3D = (load(edef.model) as PackedScene).instantiate()
		_model_root.add_child(inst)
		inst.scale = Vector3.ONE * edef.scale
		var first := true
		for mi in inst.find_children("*", "MeshInstance3D", true):
			var ab: AABB = (mi as MeshInstance3D).get_aabb()
			ab = (mi as MeshInstance3D).transform * ab
			aabb = ab if first else aabb.merge(ab)
			first = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size * edef.scale * 0.6
	cs.shape = box
	add_child(cs)
	# engine stripe (hostile red / friendly blue)
	var sock := Node3D.new()
	add_child(sock)
	sock.position = Vector3(0, 0, (aabb.position.z + aabb.size.z) * edef.scale * 0.9)
	var tcol := Color(1.0, 0.25, 0.12) if team == TEAM_HOSTILE else Color(0.35, 0.7, 1.0)
	EngineTrail.attach(battle, sock, tcol, 0.45 * edef.scale, self)

func consume_fire_cost(_e: float, _h: float) -> bool:
	return true

# ================================================================ THINK
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not alive:
		return
	_think -= delta
	_state_t -= delta
	_msl_cd -= delta
	_cm_cd -= delta
	_jink_t -= delta
	_aim_refresh -= delta
	if _spiraling:
		# out of control: thrust + tumble, then blow
		_spiral_t -= delta
		linear_velocity += (-global_transform.basis.z) * edef.accel * 0.7 * delta
		if _spiral_t <= 0.0:
			_spiraling = false
			_finish_death(_killer)
		return
	if _think <= 0.0:
		_think = 0.2
		_decide()
	_steer_and_fire(delta)
	accel_estimate = (linear_velocity - _vel_prev) / maxf(delta, 0.001)
	_vel_prev = linear_velocity

func _decide() -> void:
	if target == null or not is_instance_valid(target) or ("alive" in target and not target.alive):
		target = _pick_target()
	if state == S.EVADE or state == S.BREAK:
		if _state_t > 0.0:
			return
	# retreat check
	if hull_frac() < (1.0 - edef.brave) * 0.6:
		state = S.RETREAT
		_release_token()
		return
	if escort and is_instance_valid(escort) and ("alive" not in escort or escort.alive):
		var threat := _pick_target()
		if threat and escort.global_position.distance_to(threat.global_position) < 1100.0:
			target = threat
			state = S.PURSUE
		else:
			state = S.ESCORT
			return
	if target == null:
		state = S.PATROL
		return
	var d := global_position.distance_to(target.global_position)
	match state:
		S.PATROL, S.ESCORT, S.RETREAT:
			if d < 2600.0 * _aggression:
				state = S.PURSUE
		S.PURSUE:
			if d < 850.0 and _has_attack_permission():
				state = S.ATTACK
		S.ATTACK:
			if d < 160.0 + 60.0 * edef.scale:
				_start_break()
		_:
			pass

func _pick_target() -> Node3D:
	var candidates: Array = battle.friendly_targets() if team == TEAM_HOSTILE else battle.hostile_targets()
	var best: Node3D = null
	var best_d := INF
	for c in candidates:
		if not is_instance_valid(c):
			continue
		var d: float = global_position.distance_squared_to(c.global_position)
		# prefer the player slightly
		if c.is_in_group("player"):
			d *= 0.55
		if d < best_d:
			best_d = d
			best = c
	return best

func _has_attack_permission() -> bool:
	if _has_token:
		return true
	_has_token = battle.request_attack_token(self)
	return _has_token

func _release_token() -> void:
	if _has_token:
		battle.release_attack_token(self)
		_has_token = false

func _start_break() -> void:
	state = S.BREAK
	_state_t = randf_range(1.8, 3.0)
	var side := global_transform.basis.x * (1.0 if randf() < 0.5 else -1.0)
	var vert := global_transform.basis.y * randf_range(-0.6, 1.0)
	_break_dir = (side + vert).normalized()
	_release_token()

func ai_missile_warning(_m: Node) -> void:
	if not alive:
		return
	state = S.EVADE
	_state_t = randf_range(1.6, 2.6)
	var diff: Dictionary = Game.difficulty_scale()
	if cm_left > 0 and _cm_cd <= 0.0 and randf() < diff.cm:
		cm_left -= 1
		_cm_cd = 2.0
		for i in 2:
			Flare.deploy(battle, global_position, linear_velocity, team)

func take_hit(dmg: float, pos: Vector3, dir: Vector3, pen := 0.2,
		sh_mult := 1.0, hu_mult := 1.0, attacker: Node = null) -> void:
	super.take_hit(dmg, pos, dir, pen, sh_mult, hu_mult, attacker)
	if alive and randf() < 0.35 and state != S.EVADE:
		state = S.EVADE
		_state_t = randf_range(0.8, 1.6)
	if alive and attacker and attacker is Node3D and target == null:
		target = attacker

# ================================================================ STEER + FIRE
func _steer_and_fire(delta: float) -> void:
	var desired := -global_transform.basis.z
	var throttle := 0.75
	var want_fire := false
	match state:
		S.PATROL:
			var to_c := patrol_center - global_position
			if to_c.length() > 900.0:
				desired = to_c.normalized()
			else:
				desired = (-global_transform.basis.z).rotated(Vector3.UP, delta * 0.15)
			throttle = 0.45
		S.ESCORT:
			if escort and is_instance_valid(escort):
				var slot := escort.global_position + escort.global_transform.basis.x * 60.0 + escort.global_transform.basis.y * 20.0
				var to_s := slot - global_position
				desired = to_s.normalized() if to_s.length() > 30.0 else -escort.global_transform.basis.z
				throttle = clampf(to_s.length() / 300.0, 0.3, 1.0)
		S.PURSUE:
			if target:
				var standoff := target.global_position
				if not _has_token:
					# orbit at distance until a slot frees up
					var off := (global_position - target.global_position).normalized().cross(Vector3.UP)
					standoff = target.global_position + off * 700.0 + Vector3.UP * 120.0
					_has_attack_permission()
				desired = (standoff - global_position).normalized()
				throttle = 1.0
		S.ATTACK:
			if target:
				_refresh_aim()
				desired = (_aim_point - global_position).normalized()
				throttle = clampf(global_position.distance_to(target.global_position) / 500.0, 0.35, 0.95)
				var ang := (-global_transform.basis.z).angle_to(desired)
				var d := global_position.distance_to(target.global_position)
				if ang < deg_to_rad(4.0 + 8.0 * _acc) and d < ShipDB.weapon(edef.weapon).range:
					want_fire = true
				_try_missile(d, ang)
		S.BREAK:
			desired = _break_dir
			throttle = 1.0
		S.EVADE:
			if _jink_t <= 0.0:
				_jink_t = randf_range(0.35, 0.7)
				_jink = (global_transform.basis.x * randf_range(-1, 1)
					+ global_transform.basis.y * randf_range(-1, 1)).normalized()
			desired = (_jink + -global_transform.basis.z * 0.6).normalized()
			throttle = 1.0
		S.RETREAT:
			if target and is_instance_valid(target):
				desired = (global_position - target.global_position).normalized()
			throttle = 1.0
			if hull_frac() > 0.55:
				state = S.PATROL
	# asteroid avoidance
	desired = _avoid(desired)
	# rotate toward desired
	var fwd := -global_transform.basis.z
	var ang_to := fwd.angle_to(desired)
	var turn_speed: float = 1.6 * edef.turn
	if ang_to > 0.001:
		var axis := fwd.cross(desired)
		if axis.length_squared() > 0.0001:
			axis = axis.normalized()
			var want_ang := axis * minf(ang_to * 3.0, turn_speed)
			angular_velocity = angular_velocity.lerp(want_ang, 1.0 - exp(-7.0 * delta))
	# roll to keep target upright-ish
	# thrust
	var max_spd: float = edef.speed
	linear_velocity += (-global_transform.basis.z) * edef.accel * throttle * delta
	if linear_velocity.length() > max_spd:
		linear_velocity = linear_velocity.normalized() * max_spd
	# slight assist damping
	var lateral := linear_velocity - (-global_transform.basis.z) * linear_velocity.dot(-global_transform.basis.z)
	linear_velocity -= lateral * (1.0 - exp(-1.2 * delta))
	weapons.process_fire(delta, want_fire, (_aim_point - global_position).normalized() if want_fire else -global_transform.basis.z)

func _refresh_aim() -> void:
	if _aim_refresh > 0.0 or target == null:
		return
	_aim_refresh = _reaction
	var w := ShipDB.weapon(edef.weapon)
	var tvel: Vector3 = target.get_velocity() if target.has_method("get_velocity") else Vector3.ZERO
	var tacc: Vector3 = target.accel_estimate if "accel_estimate" in target else Vector3.ZERO
	_aim_point = Projectiles.lead_point(global_position, linear_velocity,
		target.global_position, tvel, tacc, w.speed)
	# accuracy error, scaled by target speed and skill
	var err := (1.0 - clampf(_acc, 0.05, 0.95)) * 18.0
	_aim_point += Vector3(randf_range(-err, err), randf_range(-err, err), randf_range(-err, err))

func _try_missile(dist: float, ang: float) -> void:
	if edef.missile == "" or _msl_cd > 0.0 or target == null:
		return
	if ang > deg_to_rad(12.0) or dist > 1800.0 or dist < 300.0:
		return
	_msl_cd = randf_range(9.0, 16.0) / maxf(_aggression, 0.3)
	var mdef: Dictionary = ShipDB.MISSILES[edef.missile]
	Missile.launch(battle, global_position - global_transform.basis.z * 3.0,
		-global_transform.basis.z, linear_velocity, mdef, target, team, self)

func _avoid(desired: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var ahead := global_position + linear_velocity.normalized() * clampf(linear_velocity.length() * 1.8, 60.0, 260.0)
	var q := PhysicsRayQueryParameters3D.create(global_position, ahead)
	q.exclude = [get_rid()]
	q.collision_mask = 2 | 4
	var hit := space.intersect_ray(q)
	if hit:
		var away: Vector3 = hit.normal
		if away.length_squared() < 0.1:
			away = global_transform.basis.y
		return (desired + away * 2.2).normalized()
	return desired

var _spiraling := false
var _spiral_t := 0.0
var _killer: Node = null

func die(killer: Node = null) -> void:
	if not alive or _spiraling:
		return
	# some kills enter a burning death spiral before detonating
	if not _spiraling and randf() < 0.45 and linear_velocity.length() > 25.0:
		_spiraling = true
		_spiral_t = randf_range(0.9, 1.6)
		_killer = killer
		hull = 1.0
		state = S.EVADE
		set_physics_process(true)
		FX.fire_emitter(self, Vector3(0, 0.2, 0.5), 0.8 * edef.scale)
		FX.explosion(battle, global_position, 0)
		angular_velocity = Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-4, 4))
		return
	_finish_death(killer)

func _finish_death(killer: Node) -> void:
	_release_token()
	super.die(killer)
	FX.explosion(battle, global_position, 2 if eid == "mauler" else 1)
	# leave a burning wreck drifting for ~15 s
	if _model_root and _model_root.get_child_count() > 0:
		Wreck.spawn(battle, _model_root, global_transform, linear_velocity, edef.scale)
		_model_root = null
	if battle.has_method("on_kill"):
		battle.on_kill(self, killer)
	queue_free()
