class_name CameraRig
extends Node3D
## Chase / cockpit / orbit / cinematic / photo cameras.

enum Mode { CHASE, COCKPIT, ORBIT, CINEMATIC, PHOTO }

var ship: PlayerShip
var cam: Camera3D
var mode: int = Mode.CHASE
var _shake := 0.0
var _shake_t := 0.0
var _orbit_ang := 0.0
var _cine_pos := Vector3.ZERO
var _cine_timer := 0.0
var _photo_prev_mode := 0
var cockpit_model: Node3D = null
var base_fov := 72.0
var _yoke: Node3D = null
var _wheel: Node3D = null
var _throttle: Node3D = null
var _needles: Array = []            # [spd, pwr, heat]
var _yoke_base := Vector3.ZERO
var _thr_base := Vector3.ZERO
var head_look := Vector2.ZERO       # free-look: x yaw rad, y pitch rad
# chase framing, derived from the hull's own bounds in _frame_from_hull()
var _tail_z := 10.8                 # aft-most point of the hull, ship-local
var _standoff := 9.5                # gap between that point and the lens
var _rise := 3.6                    # how far above the centreline the lens sits

func setup(s: PlayerShip) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # must hear input while photo-paused
	ship = s
	ship.cam_rig = self
	_frame_from_hull()
	cam = Camera3D.new()
	cam.fov = base_fov
	cam.near = 0.15
	cam.far = 60000.0
	add_child(cam)
	cam.current = true
	if ResourceLoader.exists("res://assets/models/cockpit.glb"):
		var scn: PackedScene = load("res://assets/models/cockpit.glb")
		cockpit_model = scn.instantiate()
		cam.add_child(cockpit_model)
		cockpit_model.position = Vector3(0, -0.03, 0.08)
		cockpit_model.visible = false
		# Practical lighting. The interior sits in the ship's own shadow with
		# almost no ambient, so without local lights every surface crushed to
		# black and the cockpit read as a flat slab regardless of its geometry.
		_add_practical(Vector3(0.0, 0.42, 0.35), Color(0.72, 0.85, 1.0), 1.9, 3.2)
		_add_practical(Vector3(0.0, -0.10, -0.55), Color(0.45, 0.80, 1.0), 1.1, 1.8)
		_add_practical(Vector3(0.0, 0.10, 0.95), Color(1.0, 0.72, 0.42), 0.8, 2.2)
		# same procedural hull treatment as the exterior, tuned for an interior:
		# fine plating, heavy wear at the touch points, warm instrument bounce
		HullMaterial.apply(cockpit_model, {
			"paint": Color(0.17, 0.18, 0.21),
			"plate_scale": 14.0,
			"wear": 0.55,
			"grime": 0.45,
			"bolts": 0.9,
			"stripe_amount": 0.0,
			"rim": Color(0.35, 0.55, 0.85),
			"rim_strength": 0.25,
			"glass_tint": Color(0.03, 0.05, 0.07),
			"detail_fade_start": 6.0,
			"detail_fade_end": 24.0,
		})
		# flight-sim controls: yoke, throttle and gauge needles animate live
		_yoke = cockpit_model.find_child("Yoke*", true, false)
		if _yoke:
			_wheel = _yoke.find_child("YokeWheel*", true, false)
			_yoke_base = _yoke.rotation
		_throttle = cockpit_model.find_child("Throttle*", true, false)
		if _throttle:
			_thr_base = _throttle.rotation
		_needles = [cockpit_model.find_child("Needle_spd*", true, false),
			cockpit_model.find_child("Needle_pwr*", true, false),
			cockpit_model.find_child("Needle_heat*", true, false)]
	top_level = true

## Work the chase standoff out from the hull the player actually flies.
##
## The old rig was a fixed +10.4 m on Z. Every player hull is 15-19 m long with
## its tail at roughly +10.8, so the lens sat INSIDE the engine block: the near
## plane clipped through the hull and only the wingtips ever reached the frame.
## Measuring from the tail instead makes "the whole ship is visible" true for
## every ship in the roster rather than for none of them.
func _frame_from_hull() -> void:
	var ab: AABB = ship.model_aabb
	_tail_z = ab.position.z + ab.size.z
	# distance at which the widest transverse span fills a little over half the
	# vertical frame; the horizontal FOV is far wider, so wingtips always clear
	var half_span := maxf(ab.size.x, ab.size.y) * 0.5
	var mult: float = clampf(Game.settings.get("cam_distance", 1.0), 0.6, 2.0)
	_standoff = clampf(half_span / tan(deg_to_rad(base_fov * 0.5) * 0.58), 6.0, 30.0) * mult
	_rise = clampf(ab.size.y * 1.0, 2.2, 6.0) * mult

func refresh_camera_settings() -> void:
	if is_instance_valid(ship):
		_frame_from_hull()

func _add_practical(pos: Vector3, col: Color, energy: float, range_m: float) -> void:
	var l := OmniLight3D.new()
	l.light_energy = energy
	l.omni_range = range_m
	l.light_color = col
	l.shadow_enabled = false
	l.light_specular = 0.6
	cockpit_model.add_child(l)
	l.position = pos

func cycle() -> void:
	if mode == Mode.PHOTO:
		return
	mode = (mode + 1) % 4
	if cockpit_model:
		cockpit_model.visible = (mode == Mode.COCKPIT)
	# first-person: hide the exterior hull so we don't sit inside it
	if ship and is_instance_valid(ship) and ship.model_root:
		ship.model_root.visible = (mode != Mode.COCKPIT) and ship.alive
	AudioMgr.play_ui("ui_click")

func toggle_photo() -> void:
	if mode == Mode.PHOTO:
		mode = _photo_prev_mode
		get_tree().paused = false
		if cockpit_model:
			cockpit_model.visible = (mode == Mode.COCKPIT)
	else:
		_photo_prev_mode = mode
		mode = Mode.PHOTO
		if cockpit_model:
			cockpit_model.visible = false
		get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS

func add_shake(v: float) -> void:
	_shake = minf(_shake + v * Game.settings.camera_shake, 1.2)

func aim_ray(screen_pos: Vector2) -> Array:
	return [cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos)]

func _process(delta: float) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	_shake = maxf(0.0, _shake - delta * 2.2)
	_shake_t += delta * 34.0
	match mode:
		Mode.CHASE: _chase(delta)
		Mode.COCKPIT: _cockpit(delta)
		Mode.ORBIT: _orbit(delta)
		Mode.CINEMATIC: _cinematic(delta)
		Mode.PHOTO: _photo(delta)

func _shake_off() -> Vector3:
	if _shake <= 0.001:
		return Vector3.ZERO
	var n := Vector3(
		sin(_shake_t * 1.1) + sin(_shake_t * 2.3) * 0.5,
		cos(_shake_t * 1.7) + sin(_shake_t * 3.1) * 0.5,
		sin(_shake_t * 1.3) * 0.3)
	return n * _shake * 0.25

func _chase(delta: float) -> void:
	var b := ship.global_transform.basis
	var speed := ship.linear_velocity.length()
	var smooth: float = clampf(Game.settings.get("control_smoothing", 0.55), 0.0, 1.0)
	# boost slides the lens further back — the ship shrinking away reads as speed
	var boost_pull := 1.22 if ship.boost_on else 1.0
	var want_pos := ship.global_position + b * Vector3(0, _rise, _tail_z + _standoff * boost_pull)
	# softer follow than the old rig, which was welded to the hull at 26/s. The
	# camera now trails slightly through a hard turn, so the turn reads as one.
	global_position = global_position.lerp(want_pos, 1.0 - exp(-lerpf(20.0, 9.5, smooth) * delta))
	# aim ahead of the nose so the hull sits low in frame with sky above it;
	# the distance scales with the hull, so every ship frames the same way
	var look_pt := ship.global_position + (-b.z) * (_standoff * 6.0) + b.y * (_rise * 0.35)
	if ship.target and is_instance_valid(ship.target):
		var to_t := (ship.target.global_position - ship.global_position)
		if to_t.length() < 2500.0 and (-b.z).angle_to(to_t.normalized()) < deg_to_rad(40.0):
			look_pt = look_pt.lerp(ship.target.global_position, 0.18)
	var up := b.y
	var tr := Transform3D(Basis.looking_at(look_pt - global_position, up), global_position)
	global_transform = global_transform.interpolate_with(tr, 1.0 - exp(-lerpf(18.0, 9.0, smooth) * delta))
	global_position += global_transform.basis * _shake_off()
	var want_fov := base_fov + clampf(speed / ship.sdef.speed, 0.0, 2.2) * 9.0
	cam.fov = lerpf(cam.fov, want_fov, 1.0 - exp(-4.0 * delta))
	# anti-clip: ease the lens in when a rock blocks the view. Snapping to the
	# hit point (the old behaviour) is far more visible now that the standoff is
	# long enough for something to actually get between ship and camera.
	var space := ship.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		ship.global_position + b * Vector3(0, _rise * 0.5, 0), global_position)
	q.exclude = [ship.get_rid()]
	var hit := space.intersect_ray(q)
	if hit:
		var safe: Vector3 = hit.position + (ship.global_position - hit.position).normalized() * 0.6
		global_position = global_position.lerp(safe, 1.0 - exp(-25.0 * delta))

func _cockpit(delta: float) -> void:
	# eye raised + pulled back so the whole office is visible by default
	var eye: Vector3 = ship.sdef.get("eye", Vector3(0, 0.62, -1.6)) + Vector3(0, 0.10, 0.22)
	var b := ship.global_transform.basis
	global_position = ship.global_position + b * eye
	var vib := _shake_off() * 0.5
	vib += Vector3(sin(_shake_t * 0.31), cos(_shake_t * 0.41), 0) * 0.006 * clampf(ship.linear_velocity.length() / 80.0, 0.2, 1.5)
	# head: spring back when not holding look; subtle lean into the aim
	if not Input.is_action_pressed("look_around"):
		head_look = head_look.lerp(Vector2.ZERO, 1.0 - exp(-6.0 * delta))
	var sway := Vector2(ship.mouse_offset.x, -ship.mouse_offset.y) * 0.10
	# +0.14 rad default down-tilt: dash, gauges and yoke sit in frame
	var h := head_look + sway + Vector2(0.0, 0.14)
	var hb := b.rotated(b.y, -h.x)
	hb = hb.rotated(hb.x, -h.y)
	global_transform = Transform3D(hb, global_position + b * vib)
	# cockpit stays bolted to the SHIP while the head turns inside it
	if cockpit_model:
		cockpit_model.global_transform = Transform3D(b, global_position + b * (vib + Vector3(0, -0.03, 0.08)))
	# wide sim lens: the full dash + consoles fit the frame
	cam.fov = lerpf(cam.fov, base_fov + 14.0 + (6.0 if ship.boost_on else 0.0), 1.0 - exp(-4.0 * delta))
	# animate the sim controls from live flight inputs
	var k := 1.0 - exp(-10.0 * delta)
	if _yoke:
		_yoke.rotation.x = lerpf(_yoke.rotation.x, _yoke_base.x - ship.input_pitch * 0.30, k)
	if _wheel:
		_wheel.rotation.y = lerpf(_wheel.rotation.y, -ship.input_yaw * 0.85, k)
	if _throttle:
		_throttle.rotation.x = lerpf(_throttle.rotation.x, _thr_base.x + ship.input_thrust * 0.55, k)
	if _needles.size() == 3:
		var vals := [clampf(ship.linear_velocity.length() / (ship.sdef.speed * ship.sdef.boost_mult), 0, 1),
			ship.energy / ship.sdef.energy, ship.heat / ship.sdef.heat_cap]
		for i in 3:
			var n: Node3D = _needles[i]
			if n:
				n.rotation.z = lerpf(n.rotation.z, deg_to_rad(120.0) - vals[i] * deg_to_rad(240.0), k)

func _orbit(delta: float) -> void:
	_orbit_ang += delta * 0.25
	var r: float = (_tail_z + _standoff) * 1.25
	var pos := ship.global_position + Vector3(cos(_orbit_ang) * r, r * 0.35, sin(_orbit_ang) * r)
	global_position = global_position.lerp(pos, 1.0 - exp(-6.0 * delta))
	look_at(ship.global_position, Vector3.UP)
	cam.fov = base_fov

func _cinematic(delta: float) -> void:
	_cine_timer -= delta
	if _cine_timer <= 0.0 or _cine_pos.distance_to(ship.global_position) > 700.0:
		_cine_timer = 6.0
		var fwd := -ship.global_transform.basis.z
		_cine_pos = ship.global_position + fwd * randf_range(80, 200) \
			+ Vector3(randf_range(-60, 60), randf_range(-30, 40), randf_range(-60, 60))
	global_position = _cine_pos
	look_at(ship.global_position, Vector3.UP)
	var d := _cine_pos.distance_to(ship.global_position)
	cam.fov = clampf(2000.0 / maxf(d, 10.0), 20.0, 65.0)

func _photo(delta: float) -> void:
	var mv := Vector3.ZERO
	if Input.is_action_pressed("thrust_forward"): mv.z -= 1
	if Input.is_action_pressed("thrust_back"): mv.z += 1
	if Input.is_action_pressed("strafe_left"): mv.x -= 1
	if Input.is_action_pressed("strafe_right"): mv.x += 1
	if Input.is_action_pressed("move_up"): mv.y += 1
	if Input.is_action_pressed("move_down"): mv.y -= 1
	var spd := 60.0 if Input.is_action_pressed("boost") else 20.0
	global_position += global_transform.basis * mv * spd * delta

func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.PHOTO:
		return
	# photo mode pauses the tree, so exits MUST be handled here (ALWAYS node)
	if event.is_action_pressed("photo_mode") or event.is_action_pressed("pause"):
		toggle_photo()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		rotate_y(-mm.relative.x * 0.003)
		rotate_object_local(Vector3.RIGHT, -mm.relative.y * 0.003)
