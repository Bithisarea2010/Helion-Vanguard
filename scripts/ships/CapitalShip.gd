class_name CapitalShip
extends Combatant
## Corvette / carrier / command base: destructible subsystems, turrets, staged death.

signal subsystem_destroyed(sub: Subsystem)
signal capital_destroyed(ship)

const CAPS := {
	"kraken": {"model": "res://assets/models/capital_kraken.glb", "hull": 2600.0,
		"shield": 900.0, "regen": 18.0, "turret_wpn": "e_turret", "name": "VEX Kraken Corvette",
		"sub_hp": {"engine": 420.0}, "radar": 3.0, "score": 1200, "shield_pool": 0.0},
	"carrier": {"model": "res://assets/models/capital_carrier.glb", "hull": 9000.0,
		"shield": 1500.0, "regen": 30.0, "turret_wpn": "e_turret", "name": "ANV Solace Carrier",
		"sub_hp": {}, "radar": 5.0, "score": 0, "shield_pool": 0.0},
	"bastion": {"model": "res://assets/models/base_bastion.glb", "hull": 4000.0,
		"shield": 0.0, "regen": 0.0, "turret_wpn": "e_flak", "name": "VEX Bastion Command Base",
		"sub_hp": {"shieldgen": 300.0, "radar": 350.0, "launcher": 380.0, "hangar": 500.0,
			"command": 600.0, "reactor": 900.0},
		"radar": 8.0, "score": 5000, "shield_pool": 2600.0},
}

var cap_id := "kraken"
var cdef: Dictionary
var battle: Node
var turrets: Array[Turret] = []
var shield_pool := 0.0
var shield_pool_max := 0.0
var shieldgens_alive := 0
var reactor: Subsystem = null
var engines_alive := 0
var _launcher_cd := 6.0
var _model: Node3D
var dying := false

func _init() -> void:
	team = TEAM_HOSTILE

func setup(id: String, batl: Node, own_team: int) -> void:
	cap_id = id
	battle = batl
	team = own_team
	cdef = CAPS[id]
	is_capital = true
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	gravity_scale = 0.0
	collision_layer = 4
	collision_mask = 0
	combat_setup(cdef.hull, cdef.shield, cdef.regen, 0.5)
	shield_pool_max = cdef.shield_pool
	shield_pool = shield_pool_max
	display_name = cdef.name
	radar_size = cdef.radar
	score_value = cdef.score
	shield_delay = 6.0
	add_to_group("hostiles" if team == TEAM_HOSTILE else "friendlies")
	add_to_group("capitals")
	_load_model()

func _load_model() -> void:
	_model = Node3D.new()
	add_child(_model)
	if not ResourceLoader.exists(cdef.model):
		return
	var inst: Node3D = (load(cdef.model) as PackedScene).instantiate()
	_model.add_child(inst)
	# capitals are hundreds of metres long, so plating runs at a much coarser
	# object-space frequency than a fighter's or the panels turn into moire
	var hostile := team == TEAM_HOSTILE
	HullMaterial.apply(inst, {
		"glow": Color(1.0, 0.35, 0.16) if hostile else Color(0.4, 0.75, 1.0),
		"plate_scale": 0.30,
		"wear": 0.6,
		"grime": 0.65,
		"bolts": 0.5,
		"stripe": Color(0.75, 0.12, 0.08) if hostile else Color(0.25, 0.6, 1.0),
		"stripe_amount": 0.35,
		"rim": Color(0.45, 0.28, 0.32) if hostile else Color(0.28, 0.45, 0.85),
		"rim_strength": 0.8,
		"detail_fade_end": 1400.0,
	})
	# main hull collision from big meshes; subsystems + mounts wired by name
	for child in inst.get_children():
		var nm: String = child.name
		if nm.begins_with("MOUNT"):
			var t := Turret.new()
			add_child(t)
			t.position = (child as Node3D).position
			t.build(battle, team, cdef.turret_wpn, self)
			t.destroyed.connect(_on_sub_destroyed)
			turrets.append(t)
		elif nm.begins_with("SUB_") and child is Node3D:
			_wire_subsystem(child as Node3D, nm)
		elif child is MeshInstance3D or child is Node3D:
			_add_hull_collision(child)

func _mesh_aabb(root: Node3D) -> AABB:
	var aabb := AABB()
	var first := true
	if root is MeshInstance3D:
		aabb = (root as MeshInstance3D).get_aabb()
		aabb = root.transform * aabb
		first = false
	for mi in root.find_children("*", "MeshInstance3D", true):
		var ab: AABB = (mi as MeshInstance3D).get_aabb()
		var xf: Transform3D = (mi as Node3D).transform
		var p: Node = mi.get_parent()
		while p and p != root:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		ab = root.transform * (xf * ab)
		aabb = ab if first else aabb.merge(ab)
		first = false
	return aabb

func _add_hull_collision(node: Node) -> void:
	if not node is Node3D:
		return
	var aabb := _mesh_aabb(node as Node3D)
	if aabb.size.length() < 1.0:
		return
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size * 0.85
	cs.shape = box
	cs.position = aabb.get_center()
	add_child(cs)

func _wire_subsystem(mesh_root: Node3D, nm: String) -> void:
	var kind := "generic"
	var label := nm.trim_prefix("SUB_")
	for k in ["shieldgen", "shield", "reactor", "radar", "launcher", "hangar", "command", "engine"]:
		if nm.to_lower().find(k) != -1:
			kind = "shieldgen" if k == "shield" else k
			break
	var hp: float = cdef.sub_hp.get(kind, 300.0)
	var sub := Subsystem.new()
	add_child(sub)
	var aabb := _mesh_aabb(mesh_root)
	sub.position = aabb.get_center()
	sub.setup(kind, hp, self, label.capitalize().replace("_", " "))
	sub.mesh_node = mesh_root
	sub.collision_layer = 4
	sub.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size
	cs.shape = box
	sub.add_child(cs)
	sub.destroyed.connect(_on_sub_destroyed)
	subsystems.append(sub)
	match kind:
		"shieldgen": shieldgens_alive += 1
		"reactor": reactor = sub
		"engine": engines_alive += 1

## Capital shield: soaks subsystem/hull damage while generators are online.
func absorb_with_shield(dmg: float, pos: Vector3, shield_multiplier := 1.0) -> float:
	if shield_pool_max <= 0.0 or shieldgens_alive <= 0 or shield_pool <= 0.0:
		return dmg
	var mult := maxf(shield_multiplier, 0.01)
	var absorbed_base := minf(dmg, shield_pool / mult)
	shield_pool = maxf(0.0, shield_pool - absorbed_base * mult)
	if is_instance_valid(battle):
		FX.shield_hit(battle, pos)
	return maxf(dmg - absorbed_base, 0.0)

func notify_sub_hit(_sub: Subsystem, _dmg: float, pos: Vector3) -> void:
	if randf() < 0.3:
		FX.impact(battle, pos, Color(1.0, 0.6, 0.3))

func take_hit(dmg: float, pos: Vector3, dir: Vector3, pen := 0.2,
		sh_mult := 1.0, hu_mult := 1.0, attacker: Node = null,
	surface_normal := Vector3.ZERO) -> void:
	if shield_pool_max > 0.0:
		dmg = absorb_with_shield(dmg, pos, sh_mult)
		if dmg <= 0.0:
			return
		# bastion hull is only killable through the reactor
		if reactor and reactor.alive:
			dmg *= 0.15
	super.take_hit(dmg, pos, dir, pen, sh_mult, hu_mult, attacker, surface_normal)
	if _model and hull_frac() < 0.85:
		HullMaterial.set_damage(_model, clampf((0.85 - hull_frac()) / 0.85, 0.0, 1.0))

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not alive or dying:
		return
	# shield pool slow regen while generators remain
	if shield_pool_max > 0.0 and shieldgens_alive > 0:
		shield_pool = minf(shield_pool + 12.0 * delta, shield_pool_max)
	# missile launcher subsystems fire salvos
	_launcher_cd -= delta
	if _launcher_cd <= 0.0:
		_launcher_cd = randf_range(14.0, 22.0)
		for sub in subsystems:
			if sub.alive and sub.kind == "launcher":
				var tgt := _nearest_enemy()
				if tgt and sub.global_position.distance_to(tgt.global_position) < 3500.0:
					var mdef: Dictionary = ShipDB.MISSILES.radar
					Missile.launch(battle, sub.global_position + Vector3.UP * 6.0,
						(tgt.global_position - sub.global_position).normalized(),
						Vector3.ZERO, mdef, tgt, team, sub)

func _nearest_enemy() -> Node3D:
	var cands: Array = battle.friendly_targets() if team == TEAM_HOSTILE else battle.hostile_targets()
	var best: Node3D = null
	var bd := INF
	for c in cands:
		if is_instance_valid(c):
			var d: float = global_position.distance_squared_to(c.global_position)
			if d < bd:
				bd = d
				best = c
	return best

func _on_sub_destroyed(sub) -> void:
	FX.explosion(battle, sub.global_position, 2)
	if sub is Subsystem and (sub as Subsystem).mesh_node:
		(sub as Subsystem).mesh_node.visible = false
	if sub is CollisionObject3D:
		(sub as CollisionObject3D).collision_layer = 0
	match sub.kind if "kind" in sub else "":
		"shieldgen":
			shieldgens_alive -= 1
			if shieldgens_alive <= 0:
				shield_pool = 0.0
		"engine":
			engines_alive -= 1
			velocity_hint = Vector3.ZERO
		"reactor":
			die(sub.last_attacker if "last_attacker" in sub else null)
	subsystem_destroyed.emit(sub)
	if battle.has_method("on_subsystem_destroyed"):
		battle.on_subsystem_destroyed(self, sub)

func subs_alive(kind: String) -> int:
	var n := 0
	for s in subsystems:
		if s.alive and s.kind == kind:
			n += 1
	return n

func die(killer: Node = null) -> void:
	if dying or not alive:
		return
	dying = true
	alive = false
	# staged destruction sequence
	var seq := create_tween()
	var steps := 6 if cap_id == "bastion" else 4
	for i in steps:
		seq.tween_interval(0.45)
		seq.tween_callback(func():
			var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * radar_size * 12.0
			FX.explosion(battle, global_position + off, 2))
	seq.tween_interval(0.5)
	seq.tween_callback(func():
		FX.explosion(battle, global_position, 3)
		died.emit(killer)
		capital_destroyed.emit(self)
		if battle.has_method("on_kill"):
			battle.on_kill(self, killer)
		if _model:
			Wreck.spawn(battle, _model, global_transform, velocity_hint, radar_size)
			_model = null
		collision_layer = 0
		for t in turrets:
			t.set_physics_process(false)
		set_physics_process(false))
