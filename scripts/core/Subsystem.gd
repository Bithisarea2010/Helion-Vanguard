class_name Subsystem
extends StaticBody3D
## Destructible component of a capital ship / base (turret socket, shield gen, reactor...).

signal destroyed(sub)

var kind := "generic"          # shieldgen | reactor | radar | launcher | hangar | command | engine | turret
var hp := 200.0
var hp_max := 200.0
var owner_ship: Node3D = null
var alive := true
var display_name := "Subsystem"
var mesh_node: Node3D = null

func setup(k: String, health: float, ship: Node3D, label: String) -> void:
	kind = k
	hp = health; hp_max = health
	owner_ship = ship
	display_name = label

func take_hit(dmg: float, pos: Vector3, dir: Vector3, pen := 0.2,
		sh_mult := 1.0, hu_mult := 1.0, attacker: Node = null) -> void:
	if not alive:
		return
	# capital shield soaks first if the owner still has shield generators online
	if owner_ship and owner_ship.has_method("absorb_with_shield"):
		dmg = owner_ship.absorb_with_shield(dmg * sh_mult, pos)
		if dmg <= 0.01:
			return
	hp -= dmg * hu_mult
	if owner_ship and owner_ship.has_method("notify_sub_hit"):
		owner_ship.notify_sub_hit(self, dmg, pos)
	if hp <= 0.0:
		alive = false
		destroyed.emit(self)

func hp_frac() -> float:
	return clampf(hp / hp_max, 0.0, 1.0)
