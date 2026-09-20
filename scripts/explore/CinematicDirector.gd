class_name CinematicDirector
extends RefCounted
## Brief, one-shot camera moves. Controls and physics continue; any flight input skips them.
var mode := 1 # full, reduced, gameplay only
var seen: Dictionary = {}
var active := ""
var clock := 0.0
var duration := 3.2

func trigger(event: String) -> bool:
	if seen.has(event): return false
	seen[event]=true
	if mode==2 or (mode==1 and event not in ["Planet reveal","Landing","Discovery"]): return false
	active=event; clock=0.0
	duration=4.0 if mode==0 else 2.4
	return true

func skip() -> void:
	active=""

func apply(dt: float,world: ExploreWorld) -> void:
	if active.is_empty(): return
	clock+=dt
	if clock>duration: skip(); return
	var focus := world.ship.position
	var up := (focus-world.terrain.position).normalized()
	var angle := lerpf(-0.6,0.15,smoothstep(0.0,1.0,clock/duration))
	var distance := 32.0
	if world.astronaut!=null:
		focus=world.astronaut.global_position+up*1.2; distance=6.0
	var side := world.ship.basis.x*cos(angle)+world.ship.basis.z*sin(angle)
	world.camera.position=focus+side*distance+up*(distance*0.3)
	world.camera.look_at(focus+up*0.8,up)
