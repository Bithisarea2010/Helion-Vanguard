class_name NavigationRelay
extends Node3D
## Original Blender landmark. The aperture is real navigable space; simple
## static boxes surround it without creating an invisible wall across the ring.

const MODEL := preload("res://assets/models/helion_relay.glb")
const CLEAR_RADIUS := 77.0 # leaves room for every selectable fighter's wings
var battle: Node = null
var traversed := false
var _previous := Vector3.ZERO
var _tracking := false

func build(with_collision := true) -> void:
	name = "HelionRelay07"
	add_child(MODEL.instantiate())
	if not with_collision:
		set_physics_process(false)
		return
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	add_child(body)
	for i in 24:
		var a := TAU * float(i) / 24.0
		_box(body, Vector3(cos(a), sin(a), 0) * 102.0,
			Vector3(22, 27, 24), a)
	for i in 4:
		var a := PI * 0.25 + PI * 0.5 * float(i)
		_box(body, Vector3(cos(a), sin(a), 0) * 133.0,
			Vector3(59, 12, 14), a)
	_box(body, Vector3(0, -131, -5), Vector3(61, 26, 30))
	for side in [-1, 1]:
		_box(body, Vector3(side * 83, -142, -7), Vector3(57, 32, 4))

func _box(body: StaticBody3D, pos: Vector3, dimensions: Vector3, angle := 0.0) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = dimensions
	collision.shape = shape
	body.add_child(collision)
	collision.position = pos
	collision.rotation.z = angle

func _physics_process(_delta: float) -> void:
	if traversed or not is_instance_valid(battle) or battle.loading_in_progress():
		return
	var player: PlayerShip = battle.player
	if not is_instance_valid(player) or not player.alive or battle.over:
		return
	var local := to_local(player.global_position)
	if _tracking and _previous.z > 0.0 and local.z <= 0.0:
		# Intersect the swept path with the plane, so boosting cannot skip it.
		var crossing := _previous.lerp(local, _previous.z / (_previous.z - local.z))
		if Vector2(crossing.x, crossing.y).length() < CLEAR_RADIUS \
				and _previous.distance_to(local) < 150.0:
			traversed = true
			battle.score += 150
			player.energy = minf(player.energy + 25.0, float(player.sdef.energy))
			battle.hud.kill_feed("CLEAN TRANSIT   +150")
			battle.hud.comms("RELAY 07", "Flight corridor cleared. Navigation bonus awarded; capacitor topped up.")
			AudioMgr.play_ui("hv_transit", -6.0)
	_previous = local
	_tracking = true
