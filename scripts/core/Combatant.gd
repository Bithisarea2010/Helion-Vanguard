class_name Combatant
extends RigidBody3D
## Base class for every damageable vessel: shields, hull, armor, subsystems.

signal died(killer: Node)
signal damaged(amount: float, pos: Vector3, was_shield: bool)
signal shield_state_changed(front: float, rear: float)

const TEAM_FRIEND := 0
const TEAM_HOSTILE := 1

@export var team := TEAM_HOSTILE
var hull := 100.0
var hull_max := 100.0
var armor := 0.2                    # 0..1 damage reduction vs low-pen weapons
var shield_front := 50.0
var shield_rear := 50.0
var shield_max := 50.0
var shield_regen := 5.0
var shield_delay := 4.0             # seconds after hit before regen
var _shield_cd := 0.0
var alive := true
var targetable := true # burning death spirals remain alive for their final animation
var score_value := 100
var display_name := "Contact"
var radar_size := 1.0               # HUD blip scale
var subsystems: Array = []          # Subsystem nodes register here
var is_capital := false
var velocity_hint := Vector3.ZERO   # for aim prediction on frozen bodies
var shield_vis: ShieldBubble = null # icosahedral matrix; null when disabled

## Give this ship a visible shield matrix. Safe to call on ships with no shield —
## it simply does nothing, so callers do not have to special-case drones.
func setup_shield_visual(bounds: AABB, color := Color(0.35, 0.68, 1.0)) -> void:
	if shield_max <= 0.0 or not Game.cap("shield"):
		return
	shield_vis = ShieldBubble.attach(self, bounds, color)

func combat_setup(hp: float, sh: float, sh_regen: float, arm: float) -> void:
	hull = hp; hull_max = hp
	shield_max = sh; shield_front = sh; shield_rear = sh
	shield_regen = sh_regen
	armor = arm

func _physics_process(delta: float) -> void:
	if not alive:
		return
	if _shield_cd > 0.0:
		_shield_cd -= delta
	elif shield_max > 0.0 and (shield_front < shield_max or shield_rear < shield_max):
		shield_front = minf(shield_front + shield_regen * delta, shield_max)
		shield_rear = minf(shield_rear + shield_regen * delta, shield_max)
		shield_state_changed.emit(shield_front, shield_rear)

func get_velocity() -> Vector3:
	if freeze:
		return velocity_hint
	return linear_velocity

## Central damage entry point. dir = direction the projectile was travelling.
func take_hit(dmg: float, pos: Vector3, dir: Vector3, pen := 0.2,
		sh_mult := 1.0, hu_mult := 1.0, attacker: Node = null,
		surface_normal := Vector3.ZERO) -> void:
	if not alive:
		return
	if not is_finite(dmg) or dmg <= 0.0:
		return
	var travel_dir := dir.normalized() if dir.length_squared() > 0.0001 else -global_transform.basis.z
	var local := to_local(pos)
	var from_front := local.z < 0.0   # ship forward is -Z
	var was_shield := false
	var remaining := dmg
	# directional shields
	var sh := shield_front if from_front else shield_rear
	if sh > 0.0:
		was_shield = true
		var absorbed := minf(sh, remaining * sh_mult)
		sh -= absorbed
		remaining = maxf(0.0, remaining - absorbed / maxf(sh_mult, 0.01))
		if from_front: shield_front = sh
		else: shield_rear = sh
		shield_state_changed.emit(shield_front, shield_rear)
		# `absorbed == 0` means a shield-bypassing round (sh_mult 0) went straight
		# through — the matrix must not light up for a hit it never stopped
		if absorbed > 0.001 and shield_vis and is_instance_valid(shield_vis):
			if sh <= 0.0:
				shield_vis.collapse()
			else:
				shield_vis.register_hit(pos, shield_frac())
	_shield_cd = shield_delay
	if remaining > 0.01:
		# armor: angle + penetration model
		var n := surface_normal.normalized() if surface_normal.length_squared() > 0.01 \
			else (global_position - pos).normalized()
		var angle_factor := clampf(absf(n.dot(travel_dir)), 0.25, 1.0)
		var reduction := armor * (1.0 - pen) * (2.0 - angle_factor)
		reduction = clampf(reduction, 0.0, 0.85)
		var hull_dmg := remaining * hu_mult * (1.0 - reduction)
		hull = maxf(hull - hull_dmg, 0.0)
		damaged.emit(hull_dmg, pos, false)
	else:
		damaged.emit(dmg, pos, true)
	# Even arcade projectiles should transfer momentum. The cap prevents rapid
	# cannons from turning a hit into an uncontrollable physics exploit.
	if not freeze:
		var impulse := travel_dir * clampf(dmg * 0.055, 0.05, 12.0)
		var offset := pos - global_position
		if offset.length() > 30.0:
			offset = offset.normalized() * 30.0
		apply_impulse(impulse, offset)
	if hull <= 0.0:
		die(attacker)

func die(killer: Node = null) -> void:
	if not alive:
		return
	alive = false
	died.emit(killer)

func hull_frac() -> float:
	return clampf(hull / maxf(hull_max, 0.001), 0.0, 1.0)

func shield_frac() -> float:
	if shield_max <= 0.0:
		return 0.0
	return clampf((shield_front + shield_rear) / (2.0 * shield_max), 0.0, 1.0)
