extends "res://tests/ExploreProbe.gd"
func approach(target: Vector3,seconds: float) -> bool:
	Input.action_press("thrust_forward"); Input.action_press("boost")
	var deadline := Time.get_ticks_msec()+seconds*1000
	while Time.get_ticks_msec()<deadline and world.astronaut.global_position.distance_to(target)>7.0:
		var up := (world.astronaut.global_position-world.terrain.position).normalized()
		var base := Basis.looking_at(Vector3.FORWARD.slide(up).normalized(),up)
		var delta := base.inverse()*(target-world.astronaut.global_position).normalized()
		world.astronaut.yaw=atan2(-delta.x,-delta.z)
		await get_tree().physics_frame
	Input.action_release("thrust_forward"); Input.action_release("boost")
	return world.astronaut.global_position.distance_to(target)<8.0

func start() -> void:
	reparent(Game)
	output="/tmp/helion-v2-evidence/survey"; DirAccess.make_dir_recursive_absolute(output)
	get_tree().create_timer(180.0,true,false,true).timeout.connect(func(): check(false,"survey watchdog"); finish())
	Game.start_explore({"ship":"vanguard","cinematics":0,"hostility":0})
	if not await wait_until(func(): return get_tree().current_scene is ExploreWorld and get_tree().current_scene.initialized,45.0,"survey initializes"):
		finish(); return
	world=get_tree().current_scene
	check(not world.director.active.is_empty(),"full cinematic begins with planet reveal")
	await key(KEY_N)
	check(world.director.active.is_empty(),"flight input skips cinematic immediately")
	if not await wait_until(func(): return world.ship.landed,65.0,"survey landing"):
		finish(); return
	check(world.mission.journal.data.planets.has("elysian"),"landing recorded in journal")
	check(world.soundscape.layers.engine.playing,"engine audio loop playing")
	check(world.soundscape.layers.orbit_pad.playing,"original exploration music playing")
	await key(KEY_H); await hold("thrust_back",2.0); await key(KEY_F)
	await get_tree().create_timer(0.8).timeout; await hold("thrust_back",2.5)
	await key(KEY_R)
	check(world.mission.scanned,"scanner records surface survey")
	check(world.mission.journal.data.biomes.size()==1,"biome discovery deduplicated")
	await key(KEY_R)
	check(world.mission.journal.data.biomes.size()==1,"repeated scan does not duplicate record")
	check(await approach(world.mission.signal_marker.global_position,25.0),"walks to lost signal through physical terrain")
	await key(KEY_R)
	check(world.mission.recovered,"nearby signal recovered with scanner")
	await key(KEY_P)
	await get_tree().create_timer(1.0).timeout
	check(world.mission.photographed,"photograph saved")
	check(world.mission.journal.data.photographs.size()==1,"photograph catalogued")
	await key(KEY_TAB)
	check(get_tree().paused and world.pause_panel!=null,"database opens and pauses")
	await capture("database")
	await key(KEY_ESCAPE)
	await key(KEY_C)
	await capture("survey-site")
	check(await approach(world.ship.to_global(Vector3(0,-3.2,13.2)),25.0),"walks back to ship")
	# Cover the final interaction radius without bypassing collision.
	world.astronaut.yaw=world.ship.heading
	await hold("thrust_forward",1.0); await key(KEY_F)
	check(world.astronaut!=null and world.astronaut.inside,"boards after survey")
	await hold("thrust_forward",2.5); await key(KEY_F)
	if world.astronaut!=null:
		await hold("thrust_forward",1.5); await key(KEY_F)
	check(world.astronaut==null,"returns to pilot seat after survey")
	await key(KEY_N)
	if not await wait_until(func(): return world.mission.complete,60.0,"peaceful survey mission completes in orbit"):
		finish(); return
	check(world.mission.journal.data.missions.has("elysian_survey"),"mission history recorded")
	var storage := "/tmp/helion-v2-evidence/survey-save.json"
	var writer := ExplorationJournal.new(true,storage)
	writer.record("planets","test","Persistence test")
	var reader := ExplorationJournal.new(true,storage)
	check(reader.data.planets.has("test") and writer.last_error==OK,"atomic journal save reload")
	finish()
