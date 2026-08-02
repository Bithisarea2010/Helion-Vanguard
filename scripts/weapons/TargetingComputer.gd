class_name TargetingComputer
extends Node
## Adaptive fire-control: holds the player's hit rate inside a requested band.
##
## "Always 80-90%" is a control problem, not an aim assist. A fixed aim error
## produces a hit rate that swings with range, target speed and how hard the
## target is jinking — it is 99% against a drone at 200 m and 30% against a Razor
## crossing at 900 m. So this measures the actual rolling hit rate and servos a
## single assist knob to hold it at the setpoint.
##
## The knob spans both directions around neutral, which is what makes the band
## reachable from below as well as above:
##
##   assist < 0.5   deliberately inject aim error (the shot is TOO accurate)
##   assist > 0.5   fire smart rounds that correct in flight (not accurate enough)
##
## Without the upper half the loop would saturate at "aim perfectly" and still
## sit under 80% against an evading fighter, because a ballistic round cannot
## answer a target that accelerates after it was fired.

## Scatter authority at assist = 0. Raised from 0.055: the line-of-fire and
## overkill inhibits deliberately delete the shots that were going to miss, so
## the natural rate with the computer fitted is high enough that 3.1 deg of
## dispersion could not pull the measured rate back down to the setpoint —
## missions settled 1-2 points ABOVE the band instead of on it.
const MAX_ERROR := 0.095          # rad of injected error at assist = 0
# 14 rad/s at 750 m/s is a ~54 m turn radius: enough to answer a fighter that
# breaks after the trigger was pulled, not enough to look like a homing missile.
# The first tuning pass used 5.2 and the loop saturated at assist = 1.0 with the
# measured rate still stuck around 0.59, i.e. the band was unreachable from below.
const MAX_GUIDE := 26.0           # rad/s of in-flight correction at assist = 1
const WINDOW := 42.0              # effective sample count of the rolling filter
## The loop steps once per SHOT, not once per frame.
##
## A per-frame integrator runs at 60 Hz regardless of how fast the guns are
## firing, so at one shot a second it applied sixty corrections per new sample
## and slammed the assist onto its rails and back. Stepping per shot makes
## convergence proportional to evidence: ~20 rounds to settle at any rate of fire.
const GAIN := 0.34                # assist change per shot per unit of rate error
const DEADBAND := 0.02            # no correction inside this, or the loop dithers
const MIN_SAMPLES := 6.0          # do not servo off two shots of noise

var ship: Node3D                  # PlayerShip
var target: Node3D = null         # written by the owner each frame
## Trigger inhibit. A fire-control computer does not fire into a rock, and it
## certainly does not fire through a wingman. Without this the arena mission —
## whose asteroid cluster sits directly between the firing position and the
## targets — measured 49% while the servo sat saturated at full guidance, because
## no amount of in-flight correction can route a round around a 40 m rock.
var los_blocked := false
var saturated := false            # enough damage already in flight to kill it
var _los_t := 0.0
var _pm: Node = null
## The opening value matters more than it looks: the loop only starts correcting
## after MIN_SAMPLES rounds, so this is what the first burst of every mission
## flies with, and in a short engagement it dominates the session average.
##
## Tuned twice. 0.50 (neutral) left the session average under the band because
## the first rounds were unguided; 0.80 overshot to 0.95 in a 59-shot mission
## because the opening burst was almost perfectly guided. 0.68 starts modestly
## guided and lets the servo take it from there.
var assist := 0.68
var _shots := 0.0                 # decaying counters, not integers
var _hits := 0.0
var _rate := 0.85
var enabled := true

func setup(p: Node3D, projectiles: Node) -> void:
	ship = p
	_pm = projectiles
	enabled = Game.cap("targeting")
	if projectiles and projectiles.has_signal("player_hit_confirmed"):
		projectiles.player_hit_confirmed.connect(_on_hit)

func setpoint() -> float:
	return Game.targeting_setpoint()

func hit_rate() -> float:
	return _rate

func note_shot(count := 1) -> void:
	var decay := pow(1.0 - 1.0 / WINDOW, float(count))
	_shots = _shots * decay + float(count)
	_hits *= decay
	_servo(count)

## One correction step per shot fired.
func _servo(steps := 1) -> void:
	if _shots < MIN_SAMPLES:
		return
	_rate = clampf(_hits / maxf(_shots, 1.0), 0.0, 1.0)
	var err := _rate - setpoint()
	if absf(err) <= DEADBAND:
		return
	# too accurate -> assist down (more scatter); not accurate enough -> assist up
	assist = clampf(assist - err * GAIN * float(steps), 0.0, 1.0)

func _on_hit(_target: Node, _was_shield: bool) -> void:
	# A hit can never outnumber the shots that produced it. Chain lightning and
	# shotgun pellets each report several confirmations for one trigger pull, and
	# without this clamp the measured rate would read above 1.0 and the servo
	# would wind the assist all the way down chasing a number it cannot reach.
	_hits = minf(_hits + 1.0, _shots)

## A hit is evidence too — crediting it immediately keeps the loop from lagging a
## whole burst behind when rounds are in flight.
func _process(_delta: float) -> void:
	if _shots >= MIN_SAMPLES:
		_rate = clampf(_hits / maxf(_shots, 1.0), 0.0, 1.0)

## Line-of-fire check at 10 Hz. Anything closer than the target that is not
## itself a hostile blocks the solution.
func _physics_process(delta: float) -> void:
	_los_t -= delta
	if _los_t > 0.0:
		return
	_los_t = 0.1
	los_blocked = false
	saturated = false
	if not enabled or target == null or not is_instance_valid(target):
		return
	if ship == null or not is_instance_valid(ship):
		return
	# --- overkill inhibit ---------------------------------------------------
	if _pm and is_instance_valid(_pm) and "hull" in target:
		var hp: float = float(target.hull)
		if "shield_front" in target:
			hp += maxf(float(target.shield_front), float(target.shield_rear))
		saturated = _pm.pending_damage_to(target) >= hp * 1.05
		if saturated:
			return
	var space := ship.get_world_3d().direct_space_state
	var to: Vector3 = target.global_position
	var q := PhysicsRayQueryParameters3D.create(ship.global_position, to)
	q.exclude = [ship.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var n: Node = hit.collider
	while n:
		if n == target:
			return                      # the target itself: clear
		if n.has_method("take_hit"):
			# another hostile in the way is a bonus, not a block
			if "team" in n and int(n.team) != int(ship.team):
				return
			break
		n = n.get_parent()
	# far enough from the target that the round would be eaten well short
	los_blocked = (hit.position as Vector3).distance_to(to) > 25.0

func inhibited() -> bool:
	return enabled and (los_blocked or saturated)

func inhibit_reason() -> String:
	if not enabled:
		return ""
	if los_blocked:
		return "FCS — LINE OF FIRE BLOCKED"
	if saturated:
		return "FCS — TARGET SATURATED"
	return ""

## Aim error to add, in radians. Zero once the loop is in its guided half.
func error_radians() -> float:
	if not enabled:
		return 0.0
	return maxf(0.5 - assist, 0.0) * 2.0 * MAX_ERROR

## In-flight correction rate for rounds fired now, rad/s. Zero in the lower half.
func guidance() -> float:
	if not enabled:
		return 0.0
	return maxf(assist - 0.5, 0.0) * 2.0 * MAX_GUIDE

## The direction to actually fire. `fallback` is the player's own boresight/lead.
func aim(fallback: Vector3, target: Node3D, proj_speed: float) -> Vector3:
	if not enabled or target == null or not is_instance_valid(target):
		return fallback
	if "alive" in target and not target.alive:
		return fallback
	var tvel: Vector3 = target.get_velocity() if target.has_method("get_velocity") else Vector3.ZERO
	var tacc: Vector3 = target.accel_estimate if "accel_estimate" in target else Vector3.ZERO
	var lead := Projectiles.lead_point(ship.global_position, ship.linear_velocity,
		target.global_position, tvel, tacc, proj_speed)
	var dir := (lead - ship.global_position)
	if dir.length_squared() < 0.01:
		return fallback
	dir = dir.normalized()
	# The computer only takes the shot the pilot was already roughly taking:
	# a fire-control system that swings the guns 90 degrees onto a target behind
	# you is not fire control, it is an aimbot, and it feels awful to use.
	if fallback.angle_to(dir) > deg_to_rad(22.0):
		return fallback
	var e := error_radians()
	if e > 0.0001:
		var axis := dir.cross(Vector3.UP)
		if axis.length_squared() < 0.001:
			axis = dir.cross(Vector3.RIGHT)
		dir = dir.rotated(axis.normalized(), randf_range(-e, e))
		dir = dir.rotated(dir.cross(axis).normalized(), randf_range(-e, e))
	return dir.normalized()

func status_text() -> String:
	if not enabled:
		return ""
	return "FCS %d%%" % int(round(_rate * 100.0))
