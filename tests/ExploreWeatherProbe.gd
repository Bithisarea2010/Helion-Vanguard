extends "res://tests/ExploreProbe.gd"
## Weather/re-entry integration and rendering, separate from the uncaptured performance run.
func start() -> void:
	reparent(Game)
	output="/tmp/helion-v2-evidence/weather"
	DirAccess.make_dir_recursive_absolute(output)
	get_tree().create_timer(150.0,true,false,true).timeout.connect(func(): check(false,"weather watchdog"); finish())
	Game.start_explore({"ship":"vanguard","weather":6,"hostility":0})
	if not await wait_until(func(): return get_tree().current_scene is ExploreWorld and get_tree().current_scene.initialized,45.0,"weather expedition initializes"):
		finish(); return
	world=get_tree().current_scene
	await key(KEY_N)
	if not await wait_until(func(): return world.ship.flight.heating>0.04,35.0,"plasma responds to live aerodynamic heating"):
		finish(); return
	check(world.effects.plasma.visible,"plasma mesh visible")
	await capture("reentry")
	if not await wait_until(func(): return world.altitude<2400,35.0,"enters cloud altitude"):
		finish(); return
	await key(KEY_X)
	world.ship.velocity=Vector3.ZERO
	await get_tree().create_timer(2.0).timeout
	check(world.weather.cloud_immersion>0.5,"inside-cloud density")
	check(world.environment.fog_density>0.006,"cloud density controls camera fog")
	await capture("inside-cloud")
	await key(KEY_N)
	if not await wait_until(func(): return world.ship.landed,40.0,"lands in storm"):
		finish(); return
	check(world.weather.wind.length()>15,"weather changes atmospheric wind")
	check(world.weather.wetness>0.4,"rain gradually wets terrain")
	await key(KEY_H)
	await hold("thrust_back",2.0); await key(KEY_F)
	await get_tree().create_timer(0.8).timeout
	await hold("thrust_back",2.5)
	check(not world.astronaut.inside,"storm EVA exits compartment")
	await get_tree().create_timer(1.0).timeout
	check(world.weather.precipitation.emitting,"rain is visible outdoors")
	await capture("storm-surface")
	var before := world.weather.values
	world.weather.set_weather(0)
	await get_tree().create_timer(0.2).timeout
	check(world.weather.values.y>0.8,"weather does not pop instantly")
	await get_tree().create_timer(22.0).timeout
	check(world.weather.values.y<0.1,"weather fades to clear")
	await capture("clearing")
	finish()
