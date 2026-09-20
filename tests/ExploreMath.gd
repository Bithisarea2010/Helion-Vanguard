extends Node
var passed := 0
var failed := 0
func check(ok: bool, label: String) -> void:
	if ok: passed+=1
	else: failed+=1; push_error("[EXPLORE_TEST] " + label)

func _ready() -> void:
	var planet: PlanetDefinition=load("res://data/explore/elysian.tres")
	var moon: PlanetDefinition=load("res://data/explore/selene.tres")
	check(planet.density_at(0)>1.0,"sea level density")
	check(planet.density_at(planet.atmosphere_height)==0.0,"vacuum above atmosphere")
	check(moon.density_at(0)==0.0,"airless moon")
	check(absf(planet.gravity_at(planet.radius)-planet.surface_gravity/4.0)<0.001,"inverse square gravity")
	var origin := OriginFrame.new()
	origin.origin=PackedFloat64Array([1e12,-1e12,3e12])
	var point := Vector3(0.125,-0.25,0.5)
	check(origin.to_local(origin.to_world(point)).is_equal_approx(point),"sub-metre coordinates survive trillion-metre origin")
	var a := Node3D.new(); var b := Node3D.new()
	add_child(a); add_child(b); a.position=Vector3(800,2,3); b.position=Vector3(808,2,3)
	var before := origin.to_world(a.position)
	origin.rebase(a,[a,b])
	check(a.position.length()<128.0,"local physics rebased")
	check(absf(a.position.distance_to(b.position)-8)<0.001,"relative positions invariant")
	check(origin.to_world(a.position)==before,"absolute position invariant")
	var sampler := PlanetSampler.new(planet)
	var repeated := PlanetSampler.new(planet)
	for face in 6:
		for u in [-1.0,0.0,1.0]:
			var direction := PlanetSampler.cube_direction(face,u,0.5)
			check(absf(direction.length()-1.0)<0.00001,"unit cube projection")
			check(sampler.height(direction)==repeated.height(direction),"deterministic terrain")
	var edge_a := PlanetSampler.cube_direction(0,1.0,0.3)
	var edge_b := PlanetSampler.cube_direction(5,-1.0,0.3)
	check(edge_a.is_equal_approx(edge_b),"adjacent cube-face directions match")
	check(absf(sampler.height(edge_a)-sampler.height(edge_b))<0.001,"height seam matches")
	var flight := AtmosphericFlightModel.new()
	flight.step(1.0/60.0,planet,0.0,Vector3(0,0,-1200),Vector3.ZERO,Vector3.UP,Basis.IDENTITY)
	check(flight.heating>0.5 and flight.hull_temperature>288,"re-entry heat responds to airspeed")
	flight.step(1.0/60.0,planet,planet.atmosphere_height+1,Vector3(0,0,-1200),Vector3.ZERO,Vector3.UP,Basis.IDENTITY)
	check(flight.density==0 and flight.dynamic_pressure==0 and flight.heating==0,"vacuum has no aerodynamic heating")
	print("[EXPLORE_TEST] pass=%d fail=%d" % [passed,failed])
	Game.prepare_shutdown()
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if failed==0 else 1)
