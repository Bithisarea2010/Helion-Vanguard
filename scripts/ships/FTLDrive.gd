class_name FTLDrive
extends Node3D
## Lightspeed drive: a four-phase set piece, not a speed multiplier.
##
## SPOOL   hold the key; the coil charges, the lens pulls in, star points begin
##         to elongate. Releasing early aborts and refunds nothing.
## BREACH  one white frame, a shock ring down the tunnel, the lens snaps wide.
## CRUISE  the tunnel is live, the hull is intangible, weapons are offline and
##         the speed cap is multiplied by CRUISE_MULT.
## FALLBACK the tunnel collapses inward and the lens settles back.
##
## The tunnel is one open cylinder around the camera (see
## `shaders/warp_tunnel.gdshader`); the only per-frame CPU work is placing that
## cylinder and writing two shader uniforms.

signal phase_changed(phase: int)

enum Phase { IDLE, SPOOL, BREACH, CRUISE, FALLBACK }

const SPOOL_TIME := 1.7          # seconds of hold to reach breach
const BREACH_TIME := 0.42
const FALLBACK_TIME := 1.25
const CRUISE_MULT := 48.0        # speed-cap multiplier while in the tunnel
const SPOOL_DRAIN := 14.0        # energy/s while charging
const CRUISE_DRAIN := 9.0        # energy/s while cruising
const MIN_ENERGY := 26.0         # refuse to start below this
const TUBE_RADIUS := 56.0        # must exceed the chase standoff, or the tunnel
                                 # draws over the ship instead of around it
const TUBE_LENGTH := 1400.0

var ship: PlayerShip
var phase: int = Phase.IDLE
var charge := 0.0                # 0..1 spool progress
var _t := 0.0                    # phase timer
var _tube: MeshInstance3D
var _mat: ShaderMaterial
var _warp := 0.0                 # smoothed visual intensity
var _cruise_snd: AudioStreamPlayer
var _saved_layer := 0
var _saved_mask := 0
var _lockout := 0.0              # brief cooldown after a fallback

func setup(p: PlayerShip) -> void:
	ship = p
	top_level = true
	_build_tube()
	_cruise_snd = AudioStreamPlayer.new()
	_cruise_snd.bus = "SFX"
	if AudioMgr.has_sound("ftl_cruise"):
		var st: AudioStream = AudioMgr.stream("ftl_cruise")
		if st is AudioStreamWAV:
			var w := st as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_end = w.data.size() / 2
		_cruise_snd.stream = st
	_cruise_snd.volume_db = -60.0
	add_child(_cruise_snd)

func _build_tube() -> void:
	_tube = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = TUBE_RADIUS
	cyl.bottom_radius = TUBE_RADIUS * 0.55   # slight taper: the far end narrows
	cyl.height = TUBE_LENGTH
	cyl.radial_segments = 40
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_tube.mesh = cyl
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/warp_tunnel.gdshader")
	_mat.set_shader_parameter("warp", 0.0)
	_tube.material_override = _mat
	_tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tube.extra_cull_margin = TUBE_LENGTH
	_tube.visible = false
	add_child(_tube)

# =================================================================== QUERIES
func active() -> bool:
	return phase == Phase.BREACH or phase == Phase.CRUISE

func engaged() -> bool:
	return phase != Phase.IDLE

func blocks_weapons() -> bool:
	return phase == Phase.BREACH or phase == Phase.CRUISE

func speed_multiplier() -> float:
	match phase:
		Phase.BREACH: return lerpf(1.0, CRUISE_MULT, _t / BREACH_TIME)
		Phase.CRUISE: return CRUISE_MULT
		Phase.FALLBACK: return lerpf(CRUISE_MULT, 1.0, minf(_t / FALLBACK_TIME, 1.0))
	return 1.0

## Extra FOV the camera should add. The spool pulls IN (compression), the breach
## snaps WIDE — the reversal is what makes the jump feel like a release.
func fov_offset() -> float:
	match phase:
		Phase.SPOOL: return -13.0 * charge
		Phase.BREACH: return lerpf(-13.0, 34.0, _ease_out(_t / BREACH_TIME))
		Phase.CRUISE: return 24.0
		Phase.FALLBACK: return lerpf(24.0, 0.0, minf(_t / FALLBACK_TIME, 1.0))
	return 0.0

func status_text() -> String:
	match phase:
		Phase.SPOOL: return "FTL SPOOL %d%%" % int(charge * 100.0)
		Phase.BREACH: return "BREACH"
		Phase.CRUISE: return "LIGHTSPEED"
		Phase.FALLBACK: return "FALLBACK"
	return ""

static func _ease_out(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return 1.0 - (1.0 - c) * (1.0 - c)

# =================================================================== DRIVE
func _physics_process(delta: float) -> void:
	if ship == null or not is_instance_valid(ship) or not ship.alive:
		if phase != Phase.IDLE:
			_to_phase(Phase.FALLBACK)
		return
	_lockout = maxf(0.0, _lockout - delta)
	_t += delta
	var want: bool = Game.cap("ftl") and Input.is_action_pressed("ftl_drive") \
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	match phase:
		Phase.IDLE:
			if want and _lockout <= 0.0 and _can_engage():
				_to_phase(Phase.SPOOL)
		Phase.SPOOL:
			charge = minf(charge + delta / SPOOL_TIME, 1.0)
			ship.energy = maxf(ship.energy - SPOOL_DRAIN * delta, 0.0)
			if not want or ship.energy <= 0.5:
				_abort()
			elif charge >= 1.0:
				_to_phase(Phase.BREACH)
		Phase.BREACH:
			if _t >= BREACH_TIME:
				_to_phase(Phase.CRUISE)
		Phase.CRUISE:
			ship.energy = maxf(ship.energy - CRUISE_DRAIN * delta, 0.0)
			# a tap of the key drops out; running the coil dry drops out too
			if not want or ship.energy <= 0.5:
				_to_phase(Phase.FALLBACK)
		Phase.FALLBACK:
			if _t >= FALLBACK_TIME:
				_to_phase(Phase.IDLE)
	_drive_flight(delta)

## While the tunnel is up the ship flies itself: full throttle along its own
## nose, rotation heavily damped. Steering a hull at 48x cruise speed with the
## normal turn rate would sling the player kilometres off course per frame.
func _drive_flight(delta: float) -> void:
	if not active():
		return
	var fwd := -ship.global_transform.basis.z
	var want_speed: float = ship.sdef.speed * speed_multiplier()
	var cur := ship.linear_velocity.dot(fwd)
	ship.linear_velocity = fwd * lerpf(cur, want_speed, 1.0 - exp(-2.6 * delta))
	ship.angular_velocity *= exp(-6.0 * delta)

func _can_engage() -> bool:
	if ship.energy < MIN_ENERGY:
		return false
	# A drive that works mid-furball is an escape button. Requiring clear space
	# makes it a traversal and repositioning tool, which is the interesting use.
	if not ship.incoming.is_empty():
		return false
	if ship.battle and ship.battle.has_method("hostile_targets"):
		for h in ship.battle.hostile_targets():
			if is_instance_valid(h) and ship.global_position.distance_squared_to(
					h.global_position) < 420.0 * 420.0:
				return false
	return true

func _abort() -> void:
	charge = 0.0
	_to_phase(Phase.IDLE)
	AudioMgr.play_ui("ui_deny", -6.0)

func _to_phase(p: int) -> void:
	if phase == p:
		return
	var prev := phase
	phase = p
	_t = 0.0
	match p:
		Phase.IDLE:
			charge = 0.0
			_restore_collision()
			if prev == Phase.FALLBACK:
				_lockout = 0.8
		Phase.SPOOL:
			AudioMgr.play_ui("ftl_spool", -4.0)
		Phase.BREACH:
			_suspend_collision()
			AudioMgr.play_ui("ftl_breach", 0.0)
			FX.shockwave(ship.battle, ship.global_position
				+ -ship.global_transform.basis.z * 26.0, 160.0, Color(0.7, 0.85, 1.0))
			FX.fireball(ship.battle, ship.global_position
				+ -ship.global_transform.basis.z * 20.0, 22.0, 0.30, 0.5, 4.0)
			if ship.cam_rig and ship.cam_rig.has_method("add_shake"):
				ship.cam_rig.add_shake(1.0)
		Phase.CRUISE:
			if _cruise_snd and _cruise_snd.stream:
				_cruise_snd.volume_db = -14.0
				_cruise_snd.play()
		Phase.FALLBACK:
			AudioMgr.play_ui("ftl_exit", -3.0)
			FX.shockwave(ship.battle, ship.global_position, 90.0, Color(0.55, 0.7, 1.0))
			if _cruise_snd and _cruise_snd.playing:
				_cruise_snd.stop()
	phase_changed.emit(p)

## Intangible during the jump. Restoring the exact saved values (rather than
## assuming the constructor defaults) keeps this correct if a mission ever spawns
## the player on a different layer.
func _suspend_collision() -> void:
	if _saved_layer != 0 or _saved_mask != 0:
		return
	_saved_layer = ship.collision_layer
	_saved_mask = ship.collision_mask
	ship.collision_layer = 0
	ship.collision_mask = 0

func _restore_collision() -> void:
	if _saved_layer == 0 and _saved_mask == 0:
		return
	ship.collision_layer = _saved_layer
	ship.collision_mask = _saved_mask
	_saved_layer = 0
	_saved_mask = 0

# =================================================================== VISUAL
func _process(delta: float) -> void:
	var target := 0.0
	match phase:
		Phase.SPOOL: target = charge * 0.42
		Phase.BREACH: target = 1.0
		Phase.CRUISE: target = 1.0
		Phase.FALLBACK: target = maxf(1.0 - _t / FALLBACK_TIME, 0.0)
	_warp = lerpf(_warp, target, 1.0 - exp(-9.0 * delta))
	var lit := _warp > 0.004
	if _tube.visible != lit:
		# hidden, not merely transparent: an invisible additive tube still costs a
		# full-screen worth of fragments every frame
		_tube.visible = lit
	if not lit or ship == null or not is_instance_valid(ship):
		return
	_mat.set_shader_parameter("warp", _warp)
	_mat.set_shader_parameter("speed", 0.35 + _warp * 1.8)
	_mat.set_shader_parameter("breach",
		clampf(1.0 - _t / BREACH_TIME, 0.0, 1.0) if phase == Phase.BREACH else 0.0)
	# park the tube on the camera, aimed down the nose, biased forward so most of
	# its length is ahead of the lens
	var cam := get_viewport().get_camera_3d()
	var origin: Vector3 = cam.global_position if cam else ship.global_position
	var fwd := -ship.global_transform.basis.z
	var up := ship.global_transform.basis.y
	# CylinderMesh runs along +Y; rotate so +Y maps to the ship's forward axis
	var basis := Basis(fwd.cross(up).normalized(), fwd, up.normalized())
	_tube.global_transform = Transform3D(basis, origin + fwd * (TUBE_LENGTH * 0.34))

func shutdown() -> void:
	if is_instance_valid(_cruise_snd):
		_cruise_snd.stop()
		_cruise_snd.stream = null
	_restore_collision()

func _exit_tree() -> void:
	shutdown()
