extends Node
## Real rendered input-driven round trip. No save/settings writes. Screenshots are not benchmarks.
var passed := 0
var failed := 0
var world: ExploreWorld
var output := "/tmp/helion-v2-evidence/roundtrip"
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	Game._hermetic=true
	Game.settings=Game.SETTINGS_DEFAULTS.duplicate(true)
	Game.settings.display_mode=Game.DisplayMode.WINDOWED
	Game.settings.window_size=Vector2i(1280,720)
	Game.settings.preset=1
	Game.apply_video_settings()
	DirAccess.make_dir_recursive_absolute(output)
	start.call_deferred()

func check(ok: bool,label: String) -> void:
	if ok: passed+=1; print("[EXPLORE_PLAYTEST] PASS ",label)
	else: failed+=1; push_error("[EXPLORE_PLAYTEST] FAIL "+label)

func wait_until(predicate: Callable, timeout: float, label: String) -> bool:
	var deadline := Time.get_ticks_msec()+int(timeout*1000.0)
	while Time.get_ticks_msec()<deadline:
		if predicate.call(): check(true,label); return true
		await get_tree().process_frame
	check(false,label); return false

func key(code: int) -> void:
	var event := InputEventKey.new(); event.physical_keycode=code; event.pressed=true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event=InputEventKey.new(); event.physical_keycode=code; event.pressed=false
	Input.parse_input_event(event)
	await get_tree().process_frame

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output+"/"+label+".png")==OK,"capture "+label)

func hold(action: String,seconds: float) -> void:
	Input.action_press(action)
	await get_tree().create_timer(seconds,true,false,true).timeout
	Input.action_release(action)
	await get_tree().physics_frame

func start() -> void:
	reparent(Game)
	get_tree().create_timer(180.0,true,false,true).timeout.connect(func(): check(false,"watchdog"); finish())
	Game.start_explore()
	if not await wait_until(func(): return get_tree().current_scene is ExploreWorld and get_tree().current_scene.initialized,45.0,"Explore scene initializes"):
		finish(); return
	world=get_tree().current_scene
	check(world.altitude>9000,"starts above atmosphere")
	check(get_tree().get_nodes_in_group("hostiles").is_empty(),"peaceful expedition has no combat enemies")
	await capture("orbit")
	await key(KEY_ESCAPE)
	check(get_tree().paused,"Escape pauses")
	await key(KEY_ESCAPE)
	check(not get_tree().paused,"Escape resumes")
	await key(KEY_N)
	check(world.ship.autopilot==1,"N engages descent through input")
	if not await wait_until(func(): return world.altitude<4000,45.0,"crosses atmosphere continuously"):
		finish(); return
	check(world.ship.flight.hull_temperature>288,"descent heats hull")
	await capture("atmosphere")
	if not await wait_until(func(): return world.ship.landed,45.0,"lands on surface"):
		finish(); return
	check(world.frame.rebase_count>10,"descent rebases local origin")
	check(world.ship.position.length()<600,"physics stays near origin")
	check(world.terrain.collision_count>0 and world.terrain.collision_count<=16,"bounded nearby terrain collision")
	await capture("landing")
	await key(KEY_H)
	check(world.astronaut!=null and world.astronaut.inside,"H leaves seat into ship-local interior")
	await capture("interior")
	await hold("thrust_back",2.0)
	await key(KEY_F)
	check(world.interior.open,"F opens nearby airlock")
	await get_tree().create_timer(0.8).timeout
	await hold("thrust_back",2.5)
	check(not world.astronaut.inside,"walking through airlock reaches planetary frame")
	await key(KEY_C)
	await capture("first-footfall")
	await hold("thrust_forward",2.5)
	print("[EXPLORE_PLAYTEST] boarding local=",world.ship.to_local(world.astronaut.global_position))
	await key(KEY_F)
	if world.astronaut==null:
		check(false,"boarding must not accidentally enter pilot seat"); finish(); return
	check(world.astronaut.inside,"F boards spacecraft at airlock")
	await hold("thrust_forward",2.5)
	print("[EXPLORE_PLAYTEST] cockpit local=",world.ship.to_local(world.astronaut.global_position))
	await key(KEY_F)
	check(world.astronaut==null and world.ship.piloted,"return to pilot seat")
	await key(KEY_N)
	if not await wait_until(func(): return world.altitude>15000,60.0,"takes off and returns to orbit"):
		finish(); return
	check(not world.ship.landed,"takeoff clears landed state")
	await capture("return-orbit")
	finish()

func finish() -> void:
	print("[EXPLORE_PLAYTEST] pass=%d fail=%d" % [passed,failed])
	Game.prepare_shutdown(); get_tree().quit(0 if failed==0 else 1)
