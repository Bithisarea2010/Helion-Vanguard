class_name PlayerShip
extends Combatant
## The player's fighter: arcade 6-DOF flight, weapons, missiles, countermeasures.

signal missile_warning
signal target_changed(t: Node)
signal died_final

const AIM_CONVERGE := 900.0
const STICK_DEADZONE := 0.25
const EXPO := 0.45                     # cubic blend: fine near centre, full at the stops

var ship_id := "vanguard"
var sdef: Dictionary
var loadout: Dictionary
var battle: Node = null
var weapons: WeaponSystem
var cam_rig: Node = null

# flight
var flight_assist := true
var boost_on := false
var match_vel_target := false
var mouse_offset := Vector2.ZERO       # smoothed virtual cursor, -1..1 of half-screen
var _cursor_raw := Vector2.ZERO        # what the mouse actually writes, pre-filter
var turn_rate_base := 1.7              # rad/s at full deflection
var input_pitch := 0.0                 # exposed for cockpit yoke animation
var input_yaw := 0.0
var input_thrust := 0.0
var _cmd := Vector3.ZERO               # smoothed pitch / yaw / roll demand
var _wish := Vector3.ZERO              # smoothed strafe / lift / thrust demand
var _accel_prev := Vector3.ZERO
var accel_estimate := Vector3.ZERO
var _vel_prev := Vector3.ZERO
var model_aabb := AABB(Vector3(-2, -1, -7), Vector3(4, 2, 14))  # hull bounds, for the camera

# resources
var energy := 100.0
var heat := 0.0
var overheated := false
var missiles_left := 8
var cm_left := 10
var _cm_cd := 0.0
var _msl_cd := 0.0

# targeting
var target: Node3D = null
var lock_progress := 0.0
var locked := false
var incoming: Array = []

# fx
var _plumes: Array[ExhaustPlume] = []
var _trails: Array[EngineTrail] = []
var _smoke: GPUParticles3D = null
var model_root: Node3D
var _engine_snd: AudioStreamPlayer
var _boost_was := false

func _init() -> void:
	team = TEAM_FRIEND

func setup(id: String, batl: Node) -> void:
	ship_id = id
	battle = batl
	sdef = ShipDB.SHIPS[id]
	loadout = Game.loadout_for(id)
	combat_setup(sdef.hull, sdef.shield, sdef.shield_regen, sdef.armor)
	energy = sdef.energy
	missiles_left = sdef.missile_cap
	cm_left = sdef.cm_count
	turn_rate_base = 1.7 * sdef.turn
	mass = sdef.mass
	display_name = sdef.label
	score_value = 0
	gravity_scale = 0.0
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 4
	linear_damp = 0.0
	angular_damp = 2.0
	collision_layer = 1
	collision_mask = 1 | 2 | 4
	add_to_group("player")
	_load_model()
	_setup_weapons()
	body_entered.connect(_on_body_entered)
	# continuous engine loop, pitch/volume follow throttle
	_engine_snd = AudioStreamPlayer.new()
	_engine_snd.bus = "SFX"
	if ResourceLoader.exists("res://assets/audio/sfx/engine_loop.wav"):
		var st: AudioStreamWAV = load("res://assets/audio/sfx/engine_loop.wav")
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_end = st.data.size() / 2
		_engine_snd.stream = st
	add_child(_engine_snd)
	_engine_snd.volume_db = -18.0
	_engine_snd.play()

func _load_model() -> void:
	model_root = Node3D.new()
	add_child(model_root)
	var scn: PackedScene = load(sdef.model) if ResourceLoader.exists(sdef.model) else null
	var aabb := AABB(Vector3(-2, -1, -7), Vector3(4, 2, 14))
	if scn:
		var inst := scn.instantiate()
		model_root.add_child(inst)
		aabb = _tint_and_measure(inst)
	model_aabb = aabb
	# collision approximated with 3 boxes (body + wings)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(aabb.size.x * 0.35, aabb.size.y * 0.6, aabb.size.z * 0.85)
	cs.shape = box
	add_child(cs)
	var cs2 := CollisionShape3D.new()
	var box2 := BoxShape3D.new()
	box2.size = Vector3(aabb.size.x * 0.9, aabb.size.y * 0.25, aabb.size.z * 0.4)
	cs2.shape = box2
	cs2.position.z = aabb.position.z + aabb.size.z * 0.6
	add_child(cs2)
	_add_thrusters(aabb)

func _tint_and_measure(inst: Node) -> AABB:
	# hero ship: strongest procedural detail budget in the game
	return HullMaterial.apply(inst, {
		"paint": loadout.paint,
		"glow": loadout.glow,
		"plate_scale": 0.78,
		"wear": 0.42,
		"grime": 0.34,
		"bolts": 0.7,
		"stripe": loadout.glow,
		"stripe_amount": 0.55,
		"rim": Color(0.34, 0.48, 0.85),
		"rim_strength": 1.0,
	})

func _add_thrusters(aabb: AABB) -> void:
	var rear_z := aabb.position.z + aabb.size.z - 0.4
	var offs: Array = sdef.get("thrusters", [Vector3(0.8, 0, 0), Vector3(-0.8, 0, 0)])
	var glow: Color = loadout.glow
	var rad: float = clampf(aabb.size.x * 0.09, 0.28, 0.75)
	for o in offs:
		var plume := ExhaustPlume.create(self, Vector3(o.x, o.y, rear_z), glow, rad, 5.2)
		_plumes.append(plume)
		# sleek ribbon "jet stripe" behind each engine
		_trails.append(EngineTrail.attach(battle, plume, glow, 0.42, self))

func _setup_weapons() -> void:
	weapons = WeaponSystem.new()
	add_child(weapons)
	var ma: Array[Vector3] = []
	var mb: Array[Vector3] = []
	for v in sdef.get("muzzles_a", [Vector3(0.4, -0.1, -7.0), Vector3(-0.4, -0.1, -7.0)]):
		ma.append(v)
	for v in sdef.get("muzzles_b", [Vector3(3.5, -1.0, 0.0), Vector3(-3.5, -1.0, 0.0)]):
		mb.append(v)
	weapons.setup(self, battle.projectiles, loadout.primary, loadout.primary2, ma, mb)

# ============================================================= INPUT + FLIGHT
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# hold Alt in cockpit: the mouse moves your HEAD, not the ship
		if cam_rig and cam_rig.mode == CameraRig.Mode.COCKPIT \
				and Input.is_action_pressed("look_around"):
			cam_rig.head_look += (event as InputEventMouseMotion).relative * 0.0032
			cam_rig.head_look.x = clampf(cam_rig.head_look.x, -2.2, 2.2)
			cam_rig.head_look.y = clampf(cam_rig.head_look.y, -0.5, 0.85)
			return
		var vp := get_viewport().get_visible_rect().size
		var sens: float = Game.settings.mouse_sens * 2.2
		# raw target only; _flight filters it into mouse_offset
		_cursor_raw += (event as InputEventMouseMotion).relative * sens / vp.y
		_cursor_raw = _cursor_raw.limit_length(1.0)

## Cubic expo blend — precise around centre, still reaches full deflection.
static func _curve(x: float) -> float:
	var a := absf(x)
	return signf(x) * ((1.0 - EXPO) * a + EXPO * a * a * a)

## Signed axis with the dead zone rescaled out. Godot zeroes anything below the
## action's dead zone but passes the raw value above it, so a stick leaving the
## zone jumps straight to 0.25 — a visible flick on every small correction.
func _stick(pos: String, neg: String) -> float:
	var v := Input.get_action_strength(pos) - Input.get_action_strength(neg)
	var a := absf(v)
	if a <= STICK_DEADZONE:
		return 0.0
	return signf(v) * minf((a - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 1.0)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not alive:
		return
	_flight(delta)
	_resources(delta)
	_weapons_input(delta)
	_lock_update(delta)
	_cleanup_incoming()
	accel_estimate = (linear_velocity - _vel_prev) / maxf(delta, 0.001)
	_vel_prev = linear_velocity

func _flight(delta: float) -> void:
	var smooth: float = clampf(Game.settings.control_smoothing, 0.0, 1.0)
	# --- 1. virtual cursor. Mouse deltas arrive in ragged bursts of wildly
	# different size; filtering the CURSOR rather than the ship removes that
	# jitter without decoupling where you aim from where you point.
	_cursor_raw = _cursor_raw.lerp(Vector2.ZERO, 1.0 - exp(-0.85 * delta))
	mouse_offset = mouse_offset.lerp(_cursor_raw, 1.0 - exp(-lerpf(55.0, 16.0, smooth) * delta))
	# --- 2. rotation demand, expo-curved per axis so small corrections stay small
	var inv := -1.0 if Game.settings.invert_y else 1.0
	var pitch_in := clampf((_curve(-mouse_offset.y) + _curve(_stick("pitch_up", "pitch_down"))) * inv, -1, 1)
	var yaw_in := clampf(_curve(-mouse_offset.x) - _curve(_stick("yaw_right", "yaw_left")), -1, 1)
	var roll_in := Input.get_action_strength("roll_right") - Input.get_action_strength("roll_left")
	# --- 3. filter the demand itself: a flick of the wrist becomes a sweep, and
	# the rigid body never has to chase a step discontinuity in target velocity.
	_cmd = _cmd.lerp(Vector3(pitch_in, yaw_in, roll_in),
		1.0 - exp(-lerpf(38.0, 13.0, smooth) * delta))
	var tr := turn_rate_base
	if boost_on:
		tr *= 0.55
	input_pitch = _cmd.x
	input_yaw = _cmd.y
	var target_ang_local := Vector3(_cmd.x * tr, _cmd.y * tr, -_cmd.z * tr * 1.6)
	var target_ang := global_transform.basis * target_ang_local
	# the demand is already smooth, so this stage can stay quick and precise
	angular_velocity = angular_velocity.lerp(target_ang, 1.0 - exp(-17.0 * delta))
	# --- 4. translation. Keyboard thrust is binary; ramping it gives the
	# thrusters a spool-up instead of a step, which is most of what read as jerky.
	var thrust_raw := Input.get_action_strength("thrust_forward") - Input.get_action_strength("thrust_back")
	_wish = _wish.lerp(Vector3(
			Input.get_action_strength("strafe_right") - Input.get_action_strength("strafe_left"),
			Input.get_action_strength("move_up") - Input.get_action_strength("move_down"),
			thrust_raw),
		1.0 - exp(-lerpf(26.0, 9.0, smooth) * delta))
	var thrust := _wish.z
	boost_on = Input.is_action_pressed("boost") and energy > 2.0 and thrust_raw > 0.1
	var max_spd: float = sdef.speed * (sdef.boost_mult if boost_on else 1.0)
	var acc: float = sdef.accel * (1.6 if boost_on else 1.0)
	var wish_local := Vector3(_wish.x * 0.8, _wish.y * 0.7, -thrust)
	if wish_local.length() > 1.0:
		wish_local = wish_local.normalized()
	var wish_world := global_transform.basis * wish_local
	linear_velocity += wish_world * acc * delta
	if boost_on:
		energy -= sdef.boost_drain * delta
	# flight assist / momentum
	if flight_assist:
		var ref_vel := Vector3.ZERO
		if match_vel_target and target and is_instance_valid(target) and target.has_method("get_velocity"):
			ref_vel = target.get_velocity()
		var rel := linear_velocity - ref_vel
		if wish_local.length() < 0.05:
			linear_velocity = ref_vel + rel * exp(-1.4 * delta)
		# clamp speed
		rel = linear_velocity - ref_vel
		if rel.length() > max_spd:
			linear_velocity = ref_vel + rel.normalized() * lerpf(rel.length(), max_spd, 1.0 - exp(-2.5 * delta))
	else:
		if linear_velocity.length() > sdef.speed * sdef.boost_mult * 1.3:
			linear_velocity = linear_velocity.normalized() * sdef.speed * sdef.boost_mult * 1.3
	# thruster fx intensity: idle glow at zero throttle, full cone under power
	var plume_power := clampf(0.18 + absf(thrust) * 0.82, 0.0, 1.0)
	for pl in _plumes:
		if is_instance_valid(pl):
			pl.set_power(plume_power, boost_on)
	for etr in _trails:
		if is_instance_valid(etr):
			etr.boost_gain = lerpf(etr.boost_gain, 1.8 if boost_on else 1.0, 1.0 - exp(-6.0 * delta))
	# engine audio follows throttle; boost whoosh on rising edge
	if _engine_snd and _engine_snd.stream:
		var spd_f := clampf(linear_velocity.length() / maxf(sdef.speed, 1.0), 0.0, 1.6)
		_engine_snd.pitch_scale = lerpf(_engine_snd.pitch_scale, 0.8 + spd_f * 0.5 + (0.25 if boost_on else 0.0), 1.0 - exp(-3.0 * delta))
		var want_db := -26.0 + absf(thrust) * 10.0 + spd_f * 6.0 + (4.0 if boost_on else 0.0)
		_engine_snd.volume_db = lerpf(_engine_snd.volume_db, want_db, 1.0 - exp(-4.0 * delta))
	if boost_on and not _boost_was:
		AudioMgr.play_ui("boost", -8.0)
	_boost_was = boost_on
	input_thrust = thrust

func aim_direction() -> Vector3:
	# orbit/cinematic/photo cameras give nonsense aim rays — use boresight
	if cam_rig and cam_rig.mode > CameraRig.Mode.COCKPIT:
		return -global_transform.basis.z
	# aim through the virtual crosshair toward convergence point
	if cam_rig and cam_rig.has_method("aim_ray"):
		var r: Array = cam_rig.aim_ray(crosshair_screen_pos())
		var to: Vector3 = r[0] + r[1] * AIM_CONVERGE
		var dir: Vector3 = (to - global_position).normalized()
		# soft aim assist
		if Game.settings.aim_assist and target and is_instance_valid(target) and "alive" in target and target.alive:
			var lead := Projectiles.lead_point(global_position, linear_velocity,
				target.global_position, target.get_velocity(),
				target.accel_estimate if "accel_estimate" in target else Vector3.ZERO,
				weapons.current_speed())
			var ld := (lead - global_position).normalized()
			if dir.angle_to(ld) < deg_to_rad(3.5):
				dir = dir.slerp(ld, 0.65)
		return dir
	return -global_transform.basis.z

func crosshair_screen_pos() -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	return vp * 0.5 + mouse_offset * vp.y * 0.35

func _weapons_input(delta: float) -> void:
	weapons.process_fire(delta, Input.is_action_pressed("fire_primary") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, aim_direction())
	_msl_cd = maxf(0.0, _msl_cd - delta)
	_cm_cd = maxf(0.0, _cm_cd - delta)
	if Input.is_action_just_pressed("fire_secondary"):
		_fire_missile()
	if Input.is_action_just_pressed("countermeasure") and cm_left > 0 and _cm_cd <= 0.0:
		cm_left -= 1
		_cm_cd = 1.2
		for i in 3:
			Flare.deploy(battle, global_position - global_transform.basis.z * -2.0, linear_velocity, team)
	if Input.is_action_just_pressed("weapon_group"):
		weapons.cycle_group()
		AudioMgr.play_ui("ui_click")
	if Input.is_action_just_pressed("flight_assist"):
		flight_assist = not flight_assist
		AudioMgr.play_ui("ui_click")
	if Input.is_action_just_pressed("match_velocity"):
		match_vel_target = not match_vel_target
		AudioMgr.play_ui("ui_click")

func _fire_missile() -> void:
	var mdef: Dictionary = ShipDB.MISSILES[loadout.missile]
	if missiles_left <= 0 or _msl_cd > 0.0:
		AudioMgr.play_ui("ui_deny")
		return
	var need_lock: bool = mdef.guidance != "none"
	var tgt: Node3D = target if (locked and need_lock) else null
	if need_lock and tgt == null:
		AudioMgr.play_ui("ui_deny")
		return
	_msl_cd = mdef.reload
	var salvo: int = int(mdef.salvo)
	missiles_left -= 1
	for i in salvo:
		var off := global_transform.basis.x * (0.8 if i % 2 == 0 else -0.8) + global_transform.basis.y * -0.4
		var m := Missile.launch(battle, global_position + off, aim_direction(),
			linear_velocity, mdef, tgt, team, self)
		if salvo > 1:
			m.vel += global_transform.basis.x * randf_range(-20, 20) + global_transform.basis.y * randf_range(-10, 20)

func _resources(delta: float) -> void:
	energy = clampf(energy + sdef.energy_regen * delta, 0.0, sdef.energy)
	var cool: float = sdef.cool * (1.5 if not Input.is_action_pressed("fire_primary") else 1.0)
	heat = maxf(0.0, heat - cool * delta)
	if overheated and heat < sdef.heat_cap * 0.4:
		overheated = false
		AudioMgr.play_ui("ui_ready")

func consume_fire_cost(e: float, h: float) -> bool:
	if overheated or energy < e:
		return false
	energy -= e
	heat += h
	if heat >= sdef.heat_cap:
		overheated = true
		AudioMgr.play_ui("alarm_heat")
	return true

# ============================================================= TARGETING
func cycle_target() -> void:
	var hostiles: Array = battle.hostile_targets()
	if hostiles.is_empty():
		set_target(null)
		return
	hostiles.sort_custom(func(a, b):
		return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	var idx := hostiles.find(target)
	set_target(hostiles[(idx + 1) % hostiles.size()])
	AudioMgr.play_ui("ui_target")

func target_under_crosshair() -> void:
	var dir := aim_direction()
	var best: Node3D = null
	var best_ang := deg_to_rad(10.0)
	for h in battle.hostile_targets():
		var to: Vector3 = h.global_position - global_position
		if to.length() > 4000.0:
			continue
		var ang := dir.angle_to(to.normalized())
		if ang < best_ang:
			best_ang = ang
			best = h
	if best:
		set_target(best)
		AudioMgr.play_ui("ui_target")

func set_target(t: Node3D) -> void:
	target = t
	lock_progress = 0.0
	locked = false
	target_changed.emit(t)

func _lock_update(delta: float) -> void:
	var mdef: Dictionary = ShipDB.MISSILES[loadout.missile]
	if mdef.guidance == "none" or target == null or not is_instance_valid(target) \
			or ("alive" in target and not target.alive):
		if target and (not is_instance_valid(target) or ("alive" in target and not target.alive)):
			set_target(null)
		lock_progress = 0.0
		locked = false
		return
	var to := target.global_position - global_position
	var in_cone: bool = (-global_transform.basis.z).angle_to(to.normalized()) < deg_to_rad(mdef.lock_cone)
	var in_range: bool = to.length() < float(mdef.range)
	if in_cone and in_range and missiles_left > 0:
		var was := locked
		lock_progress = minf(lock_progress + delta / mdef.lock_time, 1.0)
		locked = lock_progress >= 1.0
		if locked and not was:
			AudioMgr.play_ui("lock_tone")
	else:
		lock_progress = maxf(0.0, lock_progress - delta * 2.0)
		locked = false

func incoming_missile(m: Node) -> void:
	incoming.append(m)
	missile_warning.emit()
	AudioMgr.play_ui("alarm_missile")

func _cleanup_incoming() -> void:
	incoming = incoming.filter(func(m): return is_instance_valid(m))

# ============================================================= DAMAGE / DEATH
func _on_body_entered(body: Node) -> void:
	var rel_speed := linear_velocity.length()
	if body is RigidBody3D:
		rel_speed = (linear_velocity - (body as RigidBody3D).linear_velocity).length()
	if rel_speed > 12.0:
		var dmg := rel_speed * rel_speed * 0.02
		take_hit(dmg, global_position + linear_velocity.normalized() * 2.0, linear_velocity.normalized(), 0.9, 1.0, 1.0, body)
		AudioMgr.play_3d("collision", global_position, 2.0)
		if cam_rig and cam_rig.has_method("add_shake"):
			cam_rig.add_shake(clampf(dmg * 0.04, 0.2, 1.0))

func take_hit(dmg: float, pos: Vector3, dir: Vector3, pen := 0.2,
		sh_mult := 1.0, hu_mult := 1.0, attacker: Node = null) -> void:
	super.take_hit(dmg, pos, dir, pen, sh_mult, hu_mult, attacker)
	if cam_rig and cam_rig.has_method("add_shake"):
		cam_rig.add_shake(clampf(dmg * 0.02, 0.05, 0.6))
	if hull_frac() < 0.35 and _smoke == null:
		_smoke = FX.damage_smoke(self, Vector3(0, 0.3, 1.5))
	# scorch the hull and open glowing heat cracks as integrity falls
	var dmg_f := clampf(1.0 - hull_frac(), 0.0, 1.0)
	if dmg_f > 0.15 and model_root:
		HullMaterial.set_damage(model_root, (dmg_f - 0.15) / 0.85)

func die(killer: Node = null) -> void:
	if not alive:
		return
	super.die(killer)
	FX.explosion(battle, global_position, 2)
	model_root.visible = false
	for pl in _plumes:
		if is_instance_valid(pl):
			pl.visible = false
	for etr in _trails:
		if is_instance_valid(etr):
			etr.queue_free()   # otherwise a frozen glow blob hangs at the death spot
	_trails.clear()
	# don't leave the camera inside an invisible hull
	if cam_rig and cam_rig.mode == CameraRig.Mode.COCKPIT:
		cam_rig.mode = CameraRig.Mode.CHASE
		if cam_rig.cockpit_model:
			cam_rig.cockpit_model.visible = false
	set_deferred("freeze", true)
	died_final.emit()
