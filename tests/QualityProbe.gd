extends Node
## Bounded real-renderer integration run. Synthetic inputs go through Godot's
## Input event path; scenario placement is explicit. Never writes player saves.

var passed := 0
var failed := 0
var master_peak_db := -100.0
const OUT := "res://docs/evidence/quality-2026-09-13/after/final/"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start.call_deferred()

func _process(_delta: float) -> void:
	master_peak_db = maxf(master_peak_db, maxf(
		AudioServer.get_bus_peak_volume_left_db(0, 0), AudioServer.get_bus_peak_volume_right_db(0, 0)))

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("[PLAYTEST] PASS ", label)
	else:
		failed += 1
		push_error("[PLAYTEST] FAIL " + label)

func pause_for(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func tap(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await pause_for(0.12)
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await pause_for(0.12)

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	check(image != null and image.save_png(OUT + label + ".png") == OK, "screenshot " + label)

func launch(id: String) -> Node:
	var started := Time.get_ticks_msec()
	var previous_scene := get_tree().current_scene.get_instance_id() if is_instance_valid(get_tree().current_scene) else 0
	Game.start_mission(id)
	await get_tree().process_frame
	while Time.get_ticks_msec() - started < 45000:
		var scene := get_tree().current_scene
		if is_instance_valid(scene) and scene.get_instance_id() != previous_scene and scene.has_method("loading_in_progress") \
				and scene.mission_id == id and not scene.loading_in_progress():
			check(true, "launch " + id + " in %.2fs" % ((Time.get_ticks_msec() - started) / 1000.0))
			return scene
		await get_tree().process_frame
	check(false, "launch timed out: " + id)
	finish()
	return null

func _start() -> void:
	reparent(Game)
	get_tree().create_timer(240.0, true, false, true).timeout.connect(func():
		check(false, "integration watchdog expired")
		finish())
	var battle := await launch("training")
	if battle == null:
		return
	check(get_window().size == Vector2i(1280, 720), "window override reaches real 1280 x 720 drawable")
	var start: Vector3 = battle.player.global_position
	Input.action_press("thrust_forward")
	await pause_for(1.3)
	Input.action_release("thrust_forward")
	check(battle.player.global_position.distance_to(start) > 10, "held thrust produces real flight")
	await tap("pause")
	check(get_tree().paused and battle._pause_panel != null, "pause action opens paused menu")
	var focus := get_viewport().gui_get_focus_owner()
	check(focus is Button and focus.text == "RESUME", "pause gives controller and keyboard focus to Resume")
	await capture("pause")
	await tap("pause")
	check(not get_tree().paused, "pause action resumes flight")
	await tap("camera_cycle")
	check(battle.cam_rig.mode == CameraRig.Mode.COCKPIT, "camera input enters cockpit")
	await capture("cockpit")
	await tap("photo_mode")
	check(get_tree().paused and battle.player.model_root.visible, "photo input from cockpit reveals ship")
	await tap("photo_mode")
	check(not get_tree().paused and not battle.player.model_root.visible, "photo input restores cockpit")
	for i in 3:
		await tap("camera_cycle")
	# Physical ring aperture, tested against the actual PhysicsServer shapes.
	await get_tree().physics_frame
	var pos: Vector3 = battle.relay.global_position
	var space: PhysicsDirectSpaceState3D = battle.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0, 40), pos - Vector3(0, 0, 40), 2)
	check(space.intersect_ray(q).is_empty(), "relay aperture has no invisible collision wall")
	q.from += Vector3(102, 0, 0)
	q.to += Vector3(102, 0, 0)
	check(not space.intersect_ray(q).is_empty(), "relay armor blocks physical ray")
	battle.player.global_position = pos + Vector3(0, 0, 125)
	battle.player.global_basis = Basis.IDENTITY
	battle.player.linear_velocity = Vector3.ZERO
	battle.player.mouse_offset = Vector2.ZERO
	Input.action_press("thrust_forward")
	await pause_for(3.2)
	Input.action_release("thrust_forward")
	check(battle.relay.traversed and battle.score >= 150, "real flight through relay awards one navigation bonus")
	# Staggered formation creation must leave ALL practice drones passive.
	battle.player.global_position = Vector3(0, 0, -2600)
	battle.player.linear_velocity = Vector3.ZERO
	battle._train_step = 1
	await pause_for(0.6)
	var drones := get_tree().get_nodes_in_group("hostiles")
	check(drones.size() == 3, "training formation fully drains its spawn queue")
	for drone in drones:
		check(drone.freeze and not drone.is_physics_processing(), "queued practice drone remains passive")
	battle.cam_rig.toggle_photo()
	battle.cam_rig.global_position = pos + Vector3(210, 95, 310)
	battle.cam_rig.look_at(pos + Vector3(0, -15, 0))
	await capture("relay-in-game")
	battle.cam_rig.toggle_photo()
	battle.open_pause_menu()
	battle._open_settings()
	await pause_for(0.15)
	var settings: SettingsPanel = get_tree().get_first_node_in_group("settings_panel")
	var tabs: TabContainer = settings.find_children("*", "TabContainer", true, false)[0]
	tabs.current_tab = 2
	await capture("comfort-settings")
	settings._close()
	battle.close_pause_menu()
	# Every existing mission still constructs its full playable scene.
	for id in ["instant_action", "patrol", "convoy", "station_defence", "capital_strike", "fleet_action", "main", "survival", "arena"]:
		battle = await launch(id)
		if battle == null:
			return
		await pause_for(0.6)
		check(battle.player.alive and battle.player.weapons != null and battle.hud.visible, "playable state " + id)
		if id == "survival":
			battle._spawn_cd = 0.0
			await pause_for(0.4)
			var previous_wave: int = battle._wave_no
			for enemy in get_tree().get_nodes_in_group("hostiles"):
				if enemy is EnemyShip:
					enemy._finish_death(battle.player)
			battle.player.hull = battle.player.hull_max * 0.5
			battle.player.missiles_left = 0
			battle._spawn_cd = 0.0
			await pause_for(0.4)
			check(battle._wave_no == previous_wave + 1 and battle.player.missiles_left == 2,
				"cleared survival wave advances and supplies missiles")
			check(battle.player.hull > battle.player.hull_max * 0.60, "survival repair applies in live director")
		if id == "arena":
			battle.player.missiles_left = 0
			await pause_for(0.15)
			check(battle.player.missiles_left == int(battle.player.sdef.missile_cap), "arena reloads live missile stores")
			var before: int = battle.shots_fired
			Input.action_press("fire_primary")
			await pause_for(1.0)
			Input.action_release("fire_primary")
			check(battle.shots_fired > before, "held primary input fires real projectiles")
			await capture("combat-hud")
			get_window().size = Vector2i(960, 540)
			await pause_for(0.2)
			await capture("hud-960x540")
			get_window().size = Vector2i(1280, 720)
	for ship_id in ["vanguard", "peregrine", "aegis"]:
		Game.save.selected_ship = ship_id
		battle = await launch("instant_action")
		if battle == null:
			return
		battle._autotest = true
		await pause_for(5.0)
		check(battle.player.alive and battle.shots_fired > 0, "new hull flies and fires: " + ship_id)
		check(battle.player.model_root.find_children("*", "MeshInstance3D", true, false).size() == 8,
			"new hull imports eight material batches: " + ship_id)
		await capture(ship_id + "-combat")
		battle._autotest = false
		battle.cam_rig.toggle_photo()
		var ship_pos: Vector3 = battle.player.global_position
		battle.cam_rig.global_position = ship_pos + battle.player.global_basis * Vector3(17, 13, -22)
		battle.cam_rig.look_at(ship_pos + Vector3(0, 0, -1))
		battle.cam_rig.cam.fov = 56
		await capture(ship_id + "-in-game")
		battle.cam_rig.toggle_photo()
	Game.save.selected_ship = "vanguard"
	Game.goto_menu()
	await pause_for(2.0)
	var until := Time.get_ticks_msec() + 20000
	while (SceneFlow._active or get_tree().current_scene == null) and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	check(not SceneFlow._active, "return to main menu completes")
	await capture("main-menu")
	get_tree().current_scene._show_hangar()
	await pause_for(0.2)
	await capture("eight-ship-hangar")
	finish()

func finish() -> void:
	print("[AUDIO] live master peak %.2f dBFS" % master_peak_db)
	check(master_peak_db > -60.0 and master_peak_db <= 0.0, "live mix produces non-clipping output")
	print("[PLAYTEST] pass=%d fail=%d" % [passed, failed])
	Game.prepare_shutdown()
	get_tree().quit(0 if failed == 0 else 1)
