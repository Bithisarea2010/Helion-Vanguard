class_name Turret
extends Subsystem
## Articulated defence turret: tracks, leads, fires; doubles as point-defence.

var battle: Node
var team := 1
var wpn_id := "e_turret"
var yoke: Node3D = null
var barrels: Node3D = null
var target: Node3D = null
var _cd := 0.0
var _burst := 0
var _retarget := 0.0
var slew := 1.8                    # rad/s
var pd_capable := true

func build(batl: Node, own_team: int, weapon := "e_turret", ship: Node3D = null) -> void:
	battle = batl
	team = own_team
	wpn_id = weapon
	owner_ship = ship
	setup("turret", 140.0, ship, "Defence Turret")
	collision_layer = 4
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.2, 3.6, 3.2)
	cs.shape = box
	cs.position.y = 1.6
	add_child(cs)
	if ResourceLoader.exists("res://assets/models/turret.glb"):
		var inst: Node3D = (load("res://assets/models/turret.glb") as PackedScene).instantiate()
		add_child(inst)
		HullMaterial.apply(inst, {
			"glow": Color(1.0, 0.3, 0.12) if team == Combatant.TEAM_HOSTILE else Color(0.4, 0.75, 1.0),
			"plate_scale": 1.6, "wear": 0.6, "grime": 0.55, "bolts": 0.8,
			"stripe_amount": 0.0, "rim_strength": 0.8,
		})
		mesh_node = inst
		yoke = inst.find_child("TurretYoke*", true, false)
		if yoke:
			barrels = yoke.find_child("TurretBarrels*", true, false)
	destroyed.connect(_on_destroyed)

func _physics_process(delta: float) -> void:
	if not alive:
		return
	_cd -= delta
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = 0.5
		_pick_target()
	if target == null or not is_instance_valid(target):
		return
	if "alive" in target and not target.alive:
		target = null
		return
	var w := ShipDB.weapon(wpn_id)
	var tvel: Vector3 = target.get_velocity() if target.has_method("get_velocity") else Vector3.ZERO
	var aim: Vector3 = Projectiles.lead_point(global_position, Vector3.ZERO,
		target.global_position, tvel, Vector3.ZERO, w.speed)
	var to_local_aim := to_local(aim)
	# yaw the yoke (around Y), pitch the barrels (around X)
	if yoke:
		var want_yaw := atan2(-to_local_aim.x, -to_local_aim.z)
		yoke.rotation.y = lerp_angle(yoke.rotation.y, want_yaw + PI, clampf(slew * delta, 0.0, 1.0))
	if barrels:
		var horiz := Vector2(to_local_aim.x, to_local_aim.z).length()
		var want_pitch := atan2(to_local_aim.y, horiz)
		barrels.rotation.x = lerp_angle(barrels.rotation.x, clampf(want_pitch, -0.3, 1.2), clampf(slew * delta, 0.0, 1.0))
	# fire when roughly aligned
	var dir := (aim - global_position).normalized()
	var muzzle: Vector3 = barrels.global_position + dir * 3.5 if barrels else global_position + dir * 3.5
	var dist := global_position.distance_to(target.global_position)
	if _cd <= 0.0 and dist < w.range:
		_cd = 1.0 / w.rof
		if target is Missile:
			# point defence: chance to kill the missile
			battle.projectiles.fire_bullet(self, muzzle, dir, w, team, Vector3.ZERO)
			if randf() < 0.22:
				(target as Missile)._detonate(false)
				target = null
		else:
			battle.projectiles.fire_bullet(self, muzzle, dir, w, team, Vector3.ZERO)

func _pick_target() -> void:
	var best: Node3D = null
	var best_d := 1600.0 * 1600.0
	# point defence priority: hostile torpedoes near our ship
	if pd_capable:
		for m in battle.get_children():
			if m is Missile and (m as Missile).team != team:
				var d: float = global_position.distance_squared_to(m.global_position)
				if d < 500.0 * 500.0:
					target = m
					return
	var cands: Array = battle.friendly_targets() if team == Combatant.TEAM_HOSTILE else battle.hostile_targets()
	for c in cands:
		if not is_instance_valid(c):
			continue
		var d2: float = global_position.distance_squared_to(c.global_position)
		if d2 < best_d:
			# line of sight
			var space := get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 4.0, c.global_position)
			q.exclude = [get_rid()]
			var hit := space.intersect_ray(q)
			if hit.is_empty() or hit.collider == c:
				best_d = d2
				best = c
	target = best

func _on_destroyed(_s) -> void:
	FX.explosion(battle, global_position, 1)
	if mesh_node:
		mesh_node.visible = false
	set_physics_process(false)
	collision_layer = 0
