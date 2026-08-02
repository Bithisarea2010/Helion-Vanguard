extends Node3D
## Battle: builds the world for the selected mission, runs the mission director,
## owns pause/debrief overlays and mouse-capture lifecycle.

var mission_id := "instant_action"
var mdef: Dictionary
var projectiles: Projectiles
var flares: Array = []
var env: SpaceEnv
var field: AsteroidField
var player: PlayerShip
var cam_rig: CameraRig
var hud: HUD
var hud_layer: CanvasLayer
var overlay_layer: CanvasLayer
var _pause_panel: Control = null
var _debrief_panel: Control = null

# director state
var stage := 0
var stage_t := 0.0
var mission_time := 0.0
var over := false
var victory := false
var _wave_no := 0
var _spawn_cd := 0.0
var _spawn_queue: Array = []    # wingmen waiting to be built, one per frame
var _attack_tokens: Array = []
var _target_cache_stamp := -10.0
var _cached_combatants: Array = []
var _cached_hostiles: Array = []
var _cached_friendlies: Array = []
var _convoy: Array = []
var _haulers_alive := 0
var _capitals: Array = []
var _bastion: CapitalShip = null
var _carrier: CapitalShip = null
var _leviathan: CapitalShip = null
var _sovereign: CapitalShip = null
var _escorts: Array = []
var _turret_line: Array = []
var _train_step := 0
var _train_flag := false

# stats
var shots_fired := 0
var shots_hit := 0
var kills := 0
var score := 0
var _autotest := false
var _at_msl_t := 0.0
var _at_cam_t := 14.0
var _cinematic_reel := false
var _cine_mode_idx := 0

# ------------------------------------------------------------- capture harness
# `-- --autotest --shotdir=<abs> --quitafter=<s> [--nocamcycle]`
var _shot_dir := ""
var _quit_after := 0.0
var _cam_cycle := true
var _shot_idx := 0
var _shot_t := 3.0
var _bench_t := 0.0
var _bench_frames := 0
var _bench_worst := 0.0
var _bench_samples: Array[float] = []
var _harness_quitting := false
var _initializing := true

func _ready() -> void:
	# MainMenu deliberately caps itself at 60 fps; restore the gameplay limit
	# (including uncapped) before building the mission.
	Game.apply_video_settings()
	Game.apply_preset()
	mission_id = Game.current_mission
	mdef = MissionDefs.get_mission(mission_id)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	SceneFlow.report(0.05, "MISSION PACKAGE", "Decrypting operation parameters")
	await get_tree().process_frame
	# world
	SceneFlow.report(0.13, "STELLAR CARTOGRAPHY", "Baking the mission sky and solar lighting")
	env = SpaceEnv.new()
	add_child(env)
	env.build(mdef.env)
	await RenderingServer.frame_post_draw
	SceneFlow.report(0.24, "COMBAT SIMULATION", "Charging the projectile and countermeasure lattice")
	projectiles = Projectiles.new()
	add_child(projectiles)
	# Chain lightning and shotgun pellets each report several confirmations for
	# one trigger pull, so hits are clamped to shots — "accuracy" above 100% is
	# not a thing, and the fire-control servo reads this same number.
	projectiles.player_hit_confirmed.connect(func(_t, _s): shots_hit = mini(shots_hit + 1, shots_fired))
	SceneFlow.report(0.34, "ASTEROID GRID", "Streaming belt geometry and collision sectors")
	field = AsteroidField.new()
	add_child(field)
	await get_tree().process_frame
	SceneFlow.report(0.47, "NAVIGATION MESH", "Committing tactical obstacles and approach lanes")
	_build_field()
	await get_tree().process_frame
	# player
	SceneFlow.report(0.60, "VANGUARD FRAME", "Applying hull, loadout and engine signature")
	player = PlayerShip.new()
	add_child(player)
	player.setup(Game.save.selected_ship, self)
	player.global_position = Vector3.ZERO
	player.died_final.connect(_on_player_died)
	field.player = player
	SceneFlow.report(0.69, "OPTICAL LINK", "Calibrating third-person combat camera")
	cam_rig = CameraRig.new()
	add_child(cam_rig)
	cam_rig.setup(player)
	await get_tree().process_frame
	SceneFlow.report(0.77, "HOSTILE SIGNATURES", "Prewarming enemy hull and material telemetry")
	_prewarm_enemy_hulls()
	await get_tree().process_frame
	if not "--nodust" in OS.get_cmdline_user_args():
		var dust := SpaceDust.new()
		add_child(dust)
		dust.player = player
	# UI
	SceneFlow.report(0.86, "COCKPIT LINK", "Synchronising targeting, comms and flight recorder")
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)
	hud = HUD.new()
	hud_layer.add_child(hud)
	hud.setup(player, self)
	if "--nohud" in OS.get_cmdline_user_args():
		hud.visible = false
		hud.process_mode = Node.PROCESS_MODE_DISABLED
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 10
	add_child(overlay_layer)
	overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	SceneFlow.report(0.92, "MISSION DIRECTOR", "Authorising launch sequence")
	_title_card()
	_mission_start()
	AudioMgr.play_music("combat")
	Game.settings_changed.connect(_on_settings_changed)
	_parse_harness_args()
	# Keep the corridor over the first frame-driven HDR/deep-sky passes. The
	# shader work happens on the render server; these checkpoints make the wait
	# legible without pretending the tiny Battle.tscn resource is the workload.
	for i in 3:
		await RenderingServer.frame_post_draw
		SceneFlow.report(0.94 + float(i) * 0.02, "LAUNCH CLEARANCE",
			"Locking insertion vector %d / 3" % (i + 1))
	await SceneFlow.finish()
	_initializing = false
	capture_mouse()

func _on_settings_changed() -> void:
	if env:
		env.apply_preset()

func loading_in_progress() -> bool:
	return _initializing

func _build_field() -> void:
	match mission_id:
		"training", "arena":
			field.populate_cluster(Vector3(0, 0, -2600), 1400.0, 260, 5)
		"convoy":
			field.populate_belt(Vector3(0, 0, 0), 3000.0, 700.0, 1300, 11)
		"station_defence":
			field.populate_cluster(Vector3(2500, 400, -2500), 1500.0, 420, 21)
		"main":
			field.populate_belt(Vector3(0, 0, -4000), 3600.0, 800.0, 1500, 31)
			field.populate_cluster(Vector3(0, 0, -9000), 2000.0, 500, 32)
		_:
			field.populate_belt(Vector3(0, 0, -1500), 2600.0, 650.0, 1400, 7)
			field.populate_cluster(Vector3(1800, 300, -3400), 1200.0, 300, 8)
	if "--noast" in OS.get_cmdline_user_args():
		return
	field.commit()

# =================================================================== MOUSE CAPTURE
## macOS-friendly capture lifecycle: captured only while actively flying.
func capture_mouse() -> void:
	if get_tree().paused or over:
		return
	if player == null or not player.alive:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if not _initializing and not get_tree().paused and not over:
			open_pause_menu()
	elif what == NOTIFICATION_WM_MOUSE_EXIT:
		pass # captured mode keeps the pointer; nothing to do

func _unhandled_input(event: InputEvent) -> void:
	# click to (re)capture after alt-tab or overlay
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and not get_tree().paused and not over:
		capture_mouse()
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if _initializing or cam_rig == null or hud == null:
		return
	if event.is_action_pressed("pause"):
		if cam_rig.mode == CameraRig.Mode.PHOTO:
			cam_rig.toggle_photo()
			capture_mouse()
		elif hud.show_tacmap:
			hud.show_tacmap = false
		elif get_tree().paused:
			close_pause_menu()
		elif not over:
			open_pause_menu()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _initializing or over or get_tree().paused:
		return
	mission_time += delta
	_drain_spawn_queue()
	if Input.is_action_just_pressed("cycle_target"):
		player.cycle_target()
	if Input.is_action_just_pressed("target_crosshair"):
		player.target_under_crosshair()
	if Input.is_action_just_pressed("camera_cycle"):
		cam_rig.cycle()
	if Input.is_action_just_pressed("photo_mode"):
		cam_rig.toggle_photo()  # keeps mouse captured for free-look
	_director_tick(delta)
	hud.score = score
	if _autotest:
		_autotest_tick(delta)
	if _shot_dir != "" or _quit_after > 0.0:
		_harness_tick(delta)

# =================================================================== HARNESS
func _parse_harness_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--autotest":
			_autotest = true
		elif arg == "--cinematicreel":
			# Self-driving, HUD-free capture companion. Camera modes deliberately
			# exclude COCKPIT/PHOTO so every frame stays third-person/no-person.
			_autotest = true
			_cinematic_reel = true
			_cam_cycle = false
			_at_cam_t = 0.6
		elif arg == "--nocamcycle":
			_cam_cycle = false
		elif arg.begins_with("--shotdir="):
			_shot_dir = arg.get_slice("=", 1)
			DirAccess.make_dir_recursive_absolute(_shot_dir)
		elif arg.begins_with("--quitafter="):
			_quit_after = float(arg.get_slice("=", 1))
			# Hard watchdog. The normal deadline is checked in _process, but this
			# node is PROCESS_MODE_PAUSABLE and both mission completion and the
			# photo-mode self-test pause the tree — so _process simply stops and
			# the run hangs forever. `escort` and `survival` finish early often
			# enough that this cost several six-minute timeouts before it was
			# noticed. A SceneTreeTimer with process_always fires regardless.
			get_tree().create_timer(_quit_after + 8.0, true, false, true) \
				.timeout.connect(func():
					print("[BENCH] harness watchdog fired (tree paused or mission over)")
					_quit_harness_cleanly())

## Screenshots on a fixed cadence + frame-time telemetry printed once a second.
func _harness_tick(delta: float) -> void:
	_bench_frames += 1
	_bench_t += delta
	_bench_samples.append(delta)
	_bench_worst = maxf(_bench_worst, delta)
	if _bench_t >= 1.0:
		_bench_samples.sort()
		var p95: float = _bench_samples[mini(int(_bench_samples.size() * 0.95), _bench_samples.size() - 1)]
		var acc := 0.0
		if shots_fired > 0:
			acc = float(shots_hit) / float(shots_fired)
		var fcs_assist := -1.0
		var fcs_rate := -1.0
		if player and is_instance_valid(player) and player.fcs:
			fcs_assist = player.fcs.assist
			fcs_rate = player.fcs.hit_rate()
		print("[BENCH] t=%.1f fps=%.1f p95=%.2fms worst=%.2fms cpu=%.2fms phys=%.2fms acc=%.3f fcs=%.3f shots=%d assist=%.2f hostiles=%d stage=%d objects=%d prims=%d drawcalls=%d vram=%.1fMB nodes=%d" % [
			mission_time, float(_bench_frames) / _bench_t, p95 * 1000.0, _bench_worst * 1000.0,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			acc, fcs_rate, shots_fired, fcs_assist, hostile_fighters_alive(), stage,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576.0,
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
		_bench_t = 0.0
		_bench_frames = 0
		_bench_worst = 0.0
		_bench_samples.clear()
	if _shot_dir != "":
		_shot_t -= delta
		if _shot_t <= 0.0:
			_shot_t = 4.0
			_grab_shot()
	if _quit_after > 0.0 and mission_time >= _quit_after:
		_quit_after = 0.0
		if _shot_dir != "":
			_grab_shot()
		print("[BENCH] harness complete, shots=%d" % _shot_idx)
		_quit_harness_cleanly(0.4)

func _quit_harness_cleanly(delay := 0.25) -> void:
	if _harness_quitting:
		return
	_harness_quitting = true
	Game.prepare_shutdown()
	await get_tree().create_timer(delay, true, false, true).timeout
	get_tree().quit()

func _grab_shot() -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	_shot_idx += 1
	img.save_png("%s/%s_%02d.png" % [_shot_dir, mission_id, _shot_idx])

## Demo/testing bot: chases the nearest hostile and fires. `-- --autotest`
func _autotest_tick(delta: float) -> void:
	if player == null or not player.alive:
		return
	_at_cam_t -= delta
	if _at_cam_t <= 0.0:
		if _cinematic_reel:
			_at_cam_t = 2.8
			var reel_modes := [CameraRig.Mode.CINEMATIC, CameraRig.Mode.ORBIT,
				CameraRig.Mode.CHASE, CameraRig.Mode.CINEMATIC]
			cam_rig.mode = reel_modes[_cine_mode_idx % reel_modes.size()]
			_cine_mode_idx += 1
			if cam_rig.cockpit_model:
				cam_rig.cockpit_model.visible = false
			if player.model_root:
				player.model_root.visible = player.alive
		else:
			_at_cam_t = 14.0
		if _cam_cycle and not _cinematic_reel:
			cam_rig.cycle()
	# scripted photo-mode enter/exit self-test at ~26 s (real input events)
	if mission_time > 26.0 and _shot_dir == "" and not has_meta("at_photo_done"):
		set_meta("at_photo_done", true)
		var ev := InputEventAction.new()
		ev.action = "photo_mode"
		ev.pressed = true
		Input.parse_input_event(ev)
		var t := get_tree().create_timer(3.0)   # fires even while paused
		t.timeout.connect(func():
			var ex := InputEventAction.new()
			ex.action = "pause"
			ex.pressed = true
			Input.parse_input_event(ex)
			print("AUTOTEST: photo exit sent, paused=", get_tree().paused))
		var t2 := get_tree().create_timer(3.5)
		t2.timeout.connect(func():
			print("AUTOTEST: after exit, paused=", get_tree().paused, " mode=", cam_rig.mode))
	var hostiles := hostile_targets()
	if hostiles.is_empty():
		Input.action_release("fire_primary")
		Input.action_release("thrust_forward")
		return
	var best: Node3D = null
	var bd := INF
	for h in hostiles:
		if not is_instance_valid(h):
			continue
		var d: float = player.global_position.distance_squared_to(h.global_position)
		if d < bd:
			bd = d
			best = h
	if best == null:
		Input.action_release("fire_primary")
		return
	if player.target != best:
		player.set_target(best)
	var cam := get_viewport().get_camera_3d()
	var lead := Projectiles.lead_point(player.global_position, player.linear_velocity,
		best.global_position, best.get_velocity() if best.has_method("get_velocity") else Vector3.ZERO,
		Vector3.ZERO, player.weapons.current_speed())
	var vp := get_viewport().get_visible_rect().size
	if not cam.is_position_behind(lead):
		var sp := cam.unproject_position(lead)
		player.steer_to(((sp - vp * 0.5) / (vp.y * 0.35)).limit_length(1.0))
	else:
		player.steer_to(Vector2(0.9, 0))
	var dist := player.global_position.distance_to(best.global_position)
	if dist > 350.0:
		Input.action_press("thrust_forward")
	else:
		Input.action_release("thrust_forward")
	# Close the distance instead of loitering, but never run the cell dry: boost
	# both drains the energy the guns need and cuts the turn rate by 45%, so a bot
	# that boosts on every approach ends up unable to shoot OR turn.
	if dist > 1200.0 and player.energy > player.sdef.energy * 0.5:
		Input.action_press("boost")
	else:
		Input.action_release("boost")
	# The gate opens with the fire-control assist: a 6 deg boresight tolerance was
	# right for unguided rounds, but with smart munitions fitted the bot should
	# take the shot the computer can actually finish.
	# Capped deliberately: a tolerance that keeps growing with the assist is
	# positive feedback — the bot takes worse and worse shots exactly as the loop
	# is trying to raise the hit rate, and the two fight each other.
	var tol := 7.0
	if player.fcs and player.fcs.enabled:
		tol += 5.0 * player.fcs.assist
	var aim_ok := (-player.global_transform.basis.z).angle_to(
		(lead - player.global_position).normalized()) < deg_to_rad(tol)
	if aim_ok and dist < player.weapons.current_range():
		Input.action_press("fire_primary")
	else:
		Input.action_release("fire_primary")
	_at_msl_t -= delta
	if player.locked and _at_msl_t <= 0.0:
		_at_msl_t = 3.0
		Input.action_press("fire_secondary")
		get_tree().create_timer(0.1).timeout.connect(func(): Input.action_release("fire_secondary"))
	if not player.incoming.is_empty() and randf() < delta * 2.0:
		Input.action_press("countermeasure")
		get_tree().create_timer(0.1).timeout.connect(func(): Input.action_release("countermeasure"))


# =================================================================== TARGET LISTS
## Force the next query to rebuild. A ship that dies inside the 80 ms cache
## window leaves a freed object in the array, and every consumer that walks it
## without an `is_instance_valid` guard then throws. Kills are rare compared to
## queries, so invalidating on death is far cheaper than validating on read.
func invalidate_target_cache() -> void:
	_target_cache_stamp = -10.0

func _refresh_target_cache() -> void:
	# HUD, turrets, missiles and every fighter used to rebuild the same scene
	# group arrays independently. An 80 ms cache is below targeting reaction
	# time but removes dozens of allocations/group walks per rendered frame.
	if mission_time - _target_cache_stamp < 0.08:
		return
	_target_cache_stamp = mission_time
	_cached_combatants.clear()
	_cached_hostiles.clear()
	_cached_friendlies.clear()
	for n in get_tree().get_nodes_in_group("hostiles"):
		if n is Combatant and (n as Combatant).alive:
			_cached_combatants.append(n)
			_cached_hostiles.append(n)
			if n is CapitalShip:
				for s in (n as CapitalShip).subsystems:
					if is_instance_valid(s) and s.alive:
						_cached_hostiles.append(s)
				for t in (n as CapitalShip).turrets:
					if is_instance_valid(t) and t.alive:
						_cached_hostiles.append(t)
	for n in get_tree().get_nodes_in_group("friendlies"):
		if n is Combatant and (n as Combatant).alive:
			_cached_combatants.append(n)
			_cached_friendlies.append(n)
	if player and player.alive:
		_cached_combatants.append(player)
		_cached_friendlies.append(player)
	for t in _turret_line:
		if is_instance_valid(t) and t.alive:
			_cached_hostiles.append(t)

func all_combatants() -> Array:
	_refresh_target_cache()
	return _cached_combatants

func hostile_targets() -> Array:
	_refresh_target_cache()
	return _cached_hostiles

func friendly_targets() -> Array:
	_refresh_target_cache()
	return _cached_friendlies

func request_attack_token(who: Node) -> bool:
	_attack_tokens = _attack_tokens.filter(func(w): return is_instance_valid(w))
	var max_tokens := 2 + int(Game.difficulty_scale().count * 1.5)
	if who in _attack_tokens:
		return true
	if _attack_tokens.size() < max_tokens:
		_attack_tokens.append(who)
		return true
	return false

func release_attack_token(who: Node) -> void:
	_attack_tokens.erase(who)

# =================================================================== SPAWNING
## Pay the per-hull-type cost up front instead of on the frame a wave arrives.
##
## `spawn_enemy` used to parse the GLB and build every HullMaterial signature
## the first time each type appeared, which landed as a 31-39 ms spike exactly
## when the player was being attacked. Loading each PackedScene here puts it in
## the resource cache, and running HullMaterial over one throwaway instance
## populates the shared material cache, so later spawns are pure node
## construction. Costs ~50 ms once, during the frame the mission is already
## loading in.
func _prewarm_enemy_hulls() -> void:
	var seen := {}
	for eid in ShipDB.ENEMIES:
		var path: String = ShipDB.ENEMIES[eid].model
		if seen.has(path) or not ResourceLoader.exists(path):
			continue
		seen[path] = true
		var scn := load(path) as PackedScene
		if scn == null:
			continue
		# never parented: HullMaterial only walks the node tree and reads mesh
		# AABBs, so an orphan is enough and nothing touches the live scene
		var inst := scn.instantiate()
		for hostile in [true, false]:
			HullMaterial.apply(inst, EnemyShip.hull_opts(hostile))
		inst.free()

func spawn_enemy(eid: String, pos: Vector3, team := Combatant.TEAM_HOSTILE) -> EnemyShip:
	var e := EnemyShip.new()
	add_child(e)
	e.global_position = pos
	e.setup(eid, self, team)
	e.look_at(player.global_position if player else Vector3.ZERO, Vector3.UP)
	return e

## Spawn a formation. The leader appears immediately; the rest trickle in one
## per frame.
##
## Even with the hull prewarm, building 3-4 fighters in a single frame cost
## 20-28 ms — a guaranteed dropped frame every single wave, right as the fight
## started. Waves arrive 2+ km away, so a ~50 ms stagger between wingmen is
## invisible, and the frame budget stops being blown.
##
## `on_spawned` is called as (ship, lead) for each ship as it actually appears,
## which is how callers tag roles now that the full array is not available
## synchronously.
func spawn_wave(comp: Array, center: Vector3, radius := 300.0,
		team := Combatant.TEAM_HOSTILE, on_spawned := Callable()) -> Array:
	var out: Array = []
	var lead: EnemyShip = null
	for i in comp.size():
		var pos := center + Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * radius
		if i == 0:
			lead = spawn_enemy(comp[i], pos, team)
			out.append(lead)
			if on_spawned.is_valid():
				on_spawned.call(lead, lead)
		else:
			_spawn_queue.append({"eid": comp[i], "pos": pos, "team": team,
				"cb": on_spawned, "lead": lead})
	AudioMgr.play_ui("radar_ping", -6.0)
	return out

## One queued wingman per frame.
func _drain_spawn_queue() -> void:
	if _spawn_queue.is_empty():
		return
	var j: Dictionary = _spawn_queue.pop_front()
	var e := spawn_enemy(j.eid, j.pos, j.team)
	var cb: Callable = j.cb
	if cb.is_valid():
		cb.call(e, j.lead if is_instance_valid(j.lead) else e)

func spawn_capital(cap_id: String, pos: Vector3, team := Combatant.TEAM_HOSTILE, yaw := 0.0) -> CapitalShip:
	var c := CapitalShip.new()
	add_child(c)
	c.global_position = pos
	c.rotation.y = yaw
	c.setup(cap_id, self, team)
	_capitals.append(c)
	return c

func hostile_fighters_alive() -> int:
	# queued wingmen count as alive: mission logic gates the next wave (and
	# mission completion) on this reaching zero, and a wave still trickling in
	# must not read as cleared
	var n := 0
	for j in _spawn_queue:
		if int(j.team) == Combatant.TEAM_HOSTILE:
			n += 1
	for h in get_tree().get_nodes_in_group("hostiles"):
		if h is EnemyShip and (h as EnemyShip).alive:
			n += 1
	return n

var _streak := 0
var _streak_t := -99.0

func on_kill(victim: Node, killer: Node) -> void:
	invalidate_target_cache()
	if "team" in victim and victim.team == Combatant.TEAM_HOSTILE:
		if killer == player or (killer != null and is_instance_valid(killer) and killer is Node and (killer as Node).is_in_group("player")):
			kills += 1
			score += victim.score_value if "score_value" in victim else 100
			# kill streak bonus: chained kills within 8 s
			if mission_time - _streak_t < 8.0:
				_streak += 1
				var bonus := 50 * _streak
				score += bonus
				hud.kill_feed("STREAK ×%d   +%d" % [_streak, bonus])
				AudioMgr.play_ui("ui_ready", 0.0, 1.0 + 0.07 * mini(_streak, 6))
			else:
				_streak = 1
			_streak_t = mission_time
		hud.kill_feed("%s destroyed" % (victim.display_name if "display_name" in victim else "Hostile"))
	elif "display_name" in victim:
		hud.kill_feed("%s LOST" % victim.display_name)

## One trigger pull by the player, whatever it launched. The fire-control servo
## counts trigger pulls, not projectiles, so a seven-pellet flak burst is one
## sample rather than seven.
func note_shot(_weapon_id: String, _projectiles: int) -> void:
	if player and is_instance_valid(player) and player.fcs:
		player.fcs.note_shot(1)

func on_subsystem_destroyed(ship: Node, sub) -> void:
	hud.kill_feed("%s — %s destroyed" % [ship.display_name, sub.display_name])
	var attacker: Node = sub.last_attacker if "last_attacker" in sub else null
	if "team" in ship and ship.team == Combatant.TEAM_HOSTILE \
			and is_instance_valid(attacker) and attacker.is_in_group("player"):
		score += 150

# =================================================================== UI OVERLAYS
func _title_card() -> void:
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := Styles.label(mdef.title, 44, Styles.CYAN, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var m := Styles.label(mdef.mode.to_upper(), 16, Styles.DIM, true)
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	vb.add_child(m)
	cc.add_child(vb)
	overlay_layer.add_child(cc)
	var tw := create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(cc, "modulate:a", 0.0, 0.8)
	tw.tween_callback(cc.queue_free)

func open_pause_menu() -> void:
	if over or _pause_panel != null:
		return
	get_tree().paused = true
	release_mouse()
	_pause_panel = _build_menu_panel("PAUSED", [
		["RESUME", func(): close_pause_menu()],
		["RESTART MISSION", func(): Game.start_mission(mission_id)],
		["SETTINGS", func(): _open_settings()],
		["ABANDON — MAIN MENU", func(): Game.goto_menu()],
	])
	overlay_layer.add_child(_pause_panel)

func close_pause_menu() -> void:
	# Esc while in photo mode exits photo mode instead of unpausing blindly
	if _pause_panel == null and cam_rig and cam_rig.mode == CameraRig.Mode.PHOTO:
		cam_rig.toggle_photo()
		capture_mouse()
		return
	if _pause_panel:
		_pause_panel.queue_free()
		_pause_panel = null
	get_tree().paused = false
	capture_mouse()

func _open_settings() -> void:
	var sp := SettingsPanel.new()
	sp.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay_layer.add_child(sp)
	sp.closed.connect(func(): sp.queue_free())

func _build_menu_panel(title: String, entries: Array) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.03, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(cc)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Styles.panel())
	cc.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var t := Styles.label(title, 30, Styles.CYAN, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	for e in entries:
		var b := Styles.button(e[0], 18)
		b.pressed.connect(e[1])
		vb.add_child(b)
	return root

func _on_player_died() -> void:
	if over:
		return
	over = true
	victory = false
	release_mouse()
	await _flight_recorder_uplink(false, "Vanguard signal lost — sealing the recorder capsule")
	_show_debrief(false)

func mission_complete() -> void:
	if over:
		return
	over = true
	victory = true
	var stats := _stats_dict()
	Game.record_mission(mission_id, stats)
	Game.mission_ended.emit(true, stats)
	release_mouse()
	await _flight_recorder_uplink(true, "Command confirms objective completion")
	_show_debrief(true)

func mission_failed(reason := "") -> void:
	if over:
		return
	over = true
	victory = false
	if reason != "":
		hud.comms("COMMAND", reason)
	release_mouse()
	await _flight_recorder_uplink(false,
		reason if reason != "" else "Mission telemetry marked incomplete")
	_show_debrief(false)

## Turn the old unexplained post-combat delay into an in-fiction waiting screen.
## The recorder stages are short, deterministic and driven by the stats that
## will appear on the debrief, so the player always knows what is happening.
func _flight_recorder_uplink(win: bool, note: String) -> void:
	var s := _stats_dict()
	SceneFlow.begin({
		"kind": "uplink",
		"eyebrow": "FLIGHT RECORDER  //  SECURE UPLINK",
		"title": "MISSION VERIFIED" if win else "MISSION INTERRUPTED",
		"subtitle": mdef.title,
		"detail": note,
		"ship_id": Game.save.selected_ship,
	})
	SceneFlow.report(0.18, "RECORDER CAPSULE", "Sealing combat event stream")
	AudioMgr.play_ui("radio", -8.0)
	await get_tree().create_timer(0.34, true, false, true).timeout
	SceneFlow.report(0.46, "WEAPONS TELEMETRY", "%d confirmed eliminations  •  %d shots" %
		[int(s.kills), shots_fired])
	AudioMgr.play_ui("ui_target", -10.0, 0.9)
	await get_tree().create_timer(0.34, true, false, true).timeout
	SceneFlow.report(0.74, "COMBAT ANALYSIS", "Accuracy %d%%  •  Score %d" %
		[int(float(s.accuracy) * 100.0), int(s.score)])
	AudioMgr.play_ui("radar_ping", -12.0, 1.08)
	await get_tree().create_timer(0.34, true, false, true).timeout
	SceneFlow.report(0.96, "UPLINK AUTHENTICATION", "Finalising the debrief package")
	await SceneFlow.finish()

func _stats_dict() -> Dictionary:
	var acc := 0.0
	if shots_fired > 0:
		acc = clampf(float(shots_hit) / float(shots_fired), 0.0, 1.0)
	return {"victory": victory, "score": score, "kills": kills,
		"accuracy": acc, "time": mission_time}

func _show_debrief(win: bool) -> void:
	release_mouse()
	var s := _stats_dict()
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.03, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(cc)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Styles.panel(Styles.BG_SOLID))
	cc.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.custom_minimum_size.x = 460
	panel.add_child(vb)
	var t := Styles.label("MISSION COMPLETE" if win else "MISSION FAILED", 34,
		Styles.GREEN if win else Styles.RED, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var sub := Styles.label(mdef.title, 15, Styles.DIM, true)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	vb.add_child(HSeparator.new())
	var mins := int(s.time) / 60
	var secs := int(s.time) % 60
	for line in [
		"Score            %d" % s.score,
		"Kills            %d" % s.kills,
		"Accuracy         %d%%" % int(s.accuracy * 100.0),
		"Mission time     %d:%02d" % [mins, secs],
	]:
		var l := Styles.label(line, 17)
		vb.add_child(l)
	vb.add_child(HSeparator.new())
	var again := Styles.button("FLY AGAIN" if not win else "REPLAY MISSION", 18)
	again.pressed.connect(func(): Game.start_mission(mission_id))
	vb.add_child(again)
	var menu := Styles.button("MAIN MENU", 18)
	menu.pressed.connect(func(): Game.goto_menu())
	vb.add_child(menu)
	overlay_layer.add_child(root)
	_debrief_panel = root
	AudioMgr.play_music("menu" if win else "combat", 2.0)
	AudioMgr.play_ui("mission_win" if win else "mission_fail")

# =================================================================== DIRECTOR
func _mission_start() -> void:
	stage = 0
	stage_t = 0.0
	for line in mdef.briefing:
		pass # briefing was shown on the menu; opening radio below
	match mission_id:
		"training":
			hud.comms("INSTRUCTOR", "Throttle up with W and follow the marker. Space/Ctrl move you vertically.")
			hud.set_objective("Reach the nav point", "W thrust • mouse steers • Shift boost", Vector3(0, 0, -1200))
		"instant_action":
			hud.comms("COMMAND", "Multiple bandits in the belt. Weapons free.")
			spawn_wave(["razor", "razor", "jackal"], Vector3(300, 50, -1400))
			hud.set_objective("Destroy all hostiles")
		"patrol":
			hud.comms("COMMAND", "Sweep the belt. Three raider flights on the scope.")
			spawn_wave(["razor", "razor"], Vector3(-600, 100, -1800))
			hud.set_objective("Destroy the raider flights", "Flight 1 of 3")
		"convoy":
			_spawn_convoy()
			hud.comms("HAULER LEAD", "Escort, we're spinning up. Keep those raiders off our backs.")
			hud.set_objective("Protect the haulers", "At least one must survive")
		"station_defence":
			_carrier = spawn_capital("carrier", Vector3(0, -40, -900), Combatant.TEAM_FRIEND, 0.3)
			hud.comms("SOLACE ACTUAL", "All fighters: bombers inbound. Do not let them line up on us.")
			hud.set_objective("Defend the Solace", "Survive 4 bomber waves")
			_wave_no = 0
			_spawn_cd = 4.0
		"capital_strike":
			var k1 := spawn_capital("kraken", Vector3(-900, 80, -2600), Combatant.TEAM_HOSTILE, 0.4)
			var k2 := spawn_capital("kraken", Vector3(900, -60, -3100), Combatant.TEAM_HOSTILE, -0.6)
			spawn_wave(["jackal", "jackal", "razor"], Vector3(0, 0, -2400))
			hud.comms("COMMAND", "Two Krakens on the picket. Engines first, then take them apart.")
			hud.set_objective("Destroy both corvettes", "Tip: kill the engine pods first")
		"survival":
			_wave_no = 0
			_spawn_cd = 2.0
			hud.comms("SIM DECK", "Wave one inbound. Good luck, pilot.")
			hud.set_objective("Survive", "Wave 1")
		"arena":
			_spawn_arena_targets()
			hud.comms("RANGE CONTROL", "Range is hot. V cycles weapon groups; right mouse fires missiles.")
			hud.set_objective("Free fire exercise", "Destroy targets at will — Esc to leave")
		"fleet_action":
			_leviathan = spawn_capital("leviathan", Vector3(0, -140, 900), Combatant.TEAM_FRIEND, 0.0)
			_leviathan.velocity_hint = Vector3.ZERO
			for i in 2:
				var f := spawn_capital("talon", Vector3(-700 + i * 1400, -40, 260),
					Combatant.TEAM_FRIEND, 0.12 * (1 if i == 0 else -1))
				_escorts.append(f)
			spawn_wave(["razor", "razor", "jackal"], Vector3(400, 120, -2600))
			hud.comms("LEVIATHAN ACTUAL", "Vanguard, you are the screen. Anything that gets past you lands on my deck.")
			hud.set_objective("Break the VEX screen", "Destroyers and fighters inbound")
			_wave_no = 0
			_spawn_cd = 12.0
		"main":
			_carrier = spawn_capital("carrier", Vector3(150, -60, 500), Combatant.TEAM_FRIEND, 0.0)
			hud.comms("SOLACE ACTUAL", "Vanguard flight, you are clear to launch. Nav point in the belt.")
			hud.set_objective("Cross the asteroid belt", "Follow the nav marker", Vector3(0, 0, -3800))

func _director_tick(delta: float) -> void:
	stage_t += delta
	_spawn_cd -= delta
	match mission_id:
		"training": _dir_training()
		"instant_action": _dir_clear_all()
		"patrol": _dir_patrol()
		"convoy": _dir_convoy(delta)
		"station_defence": _dir_station()
		"capital_strike": _dir_capital_strike()
		"fleet_action": _dir_fleet_action(delta)
		"survival": _dir_survival()
		"arena": pass
		"main": _dir_main(delta)

func _dir_clear_all() -> void:
	if stage == 0 and stage_t > 5.0 and hostile_fighters_alive() == 0 and _capitals.is_empty():
		stage = 1
		stage_t = 0.0
		spawn_wave(["jackal", "jackal", "stinger", "razor"], player.global_position + Vector3(600, 120, -1600))
		var k := spawn_capital("kraken", player.global_position + Vector3(-400, 0, -2600), Combatant.TEAM_HOSTILE, 0.2)
		hud.comms("COMMAND", "Second wave — and they brought a corvette. Engines first!")
		hud.set_objective("Destroy the second wave", "Kraken corvette on the scope")
	elif stage == 1 and stage_t > 6.0 and hostile_fighters_alive() == 0 and _capitals_alive() == 0:
		hud.comms("COMMAND", "Sector clear. Outstanding flying, Vanguard.")
		mission_complete()

func _capitals_alive() -> int:
	var n := 0
	for c in _capitals:
		if is_instance_valid(c) and c.alive and c.team == Combatant.TEAM_HOSTILE:
			n += 1
	return n

func _dir_patrol() -> void:
	if stage_t < 4.0:
		return
	if hostile_fighters_alive() > 0:
		return
	stage += 1
	stage_t = 0.0
	match stage:
		1:
			spawn_wave(["razor", "jackal", "jackal"], player.global_position + Vector3(-900, -100, -1500))
			hud.set_objective("Destroy the raider flights", "Flight 2 of 3")
			hud.comms("COMMAND", "Second flight hiding behind the big rocks. Stay sharp.")
		2:
			spawn_wave(["brute", "jackal", "stinger", "razor"], player.global_position + Vector3(700, 200, -1900))
			hud.set_objective("Destroy the raider flights", "Flight 3 of 3 — heavy fighters")
			hud.comms("COMMAND", "Last flight is armored. Watch the Brute's plasma.")
		3:
			hud.comms("COMMAND", "Belt is clean. The Guild owes you a drink.")
			mission_complete()

func _spawn_convoy() -> void:
	for i in 3:
		var h := spawn_enemy("mauler", Vector3(-200 + i * 120, -30 + i * 25, 600 + i * 180), Combatant.TEAM_FRIEND)
		h.display_name = "Ore Hauler %d" % (i + 1)
		h.score_value = 0
		h.patrol_center = Vector3(0, 0, -5200)
		h.state = EnemyShip.S.PATROL
		h.edef = h.edef.duplicate()
		h.edef.speed = 46.0
		_convoy.append(h)
	_haulers_alive = 3

func _dir_convoy(_delta: float) -> void:
	_haulers_alive = 0
	var lead_pos := Vector3.ZERO
	for h in _convoy:
		if is_instance_valid(h) and h.alive:
			_haulers_alive += 1
			lead_pos = h.global_position
			h.patrol_center = Vector3(0, 0, -5200)
	if _haulers_alive == 0:
		mission_failed("All haulers lost. The ore is stardust.")
		return
	hud.set_objective("Protect the haulers (%d/3 alive)" % _haulers_alive,
		"Wave %d of 4" % clampi(_wave_no, 1, 4), lead_pos)
	if _wave_no < 4 and _spawn_cd <= 0.0:
		_wave_no += 1
		_spawn_cd = 45.0
		var comps := [["razor", "razor"], ["razor", "jackal", "razor"],
			["stinger", "jackal", "razor"], ["brute", "jackal", "stinger", "razor"]]
		var w := spawn_wave(comps[_wave_no - 1], lead_pos + Vector3(randf_range(-1500, 1500), 300, -2200))
		hud.comms("COMMAND", "Raider wave %d inbound — vector on the haulers!" % _wave_no)
	if _wave_no >= 4 and hostile_fighters_alive() == 0 and stage_t > 30.0:
		hud.comms("HAULER LEAD", "Gate in sight. Drinks are on us, escort.")
		mission_complete()

func _dir_station() -> void:
	if _carrier == null or not is_instance_valid(_carrier) or not _carrier.alive:
		mission_failed("The Solace is gone. There was nothing left to defend.")
		return
	if _wave_no < 4 and _spawn_cd <= 0.0 and hostile_fighters_alive() == 0:
		_wave_no += 1
		_spawn_cd = 10.0
		var comps := [["mauler", "razor", "razor"], ["mauler", "mauler", "jackal"],
			["mauler", "stinger", "stinger", "razor"], ["mauler", "mauler", "brute", "jackal"]]
		# bombers hunt the carrier, everyone else escorts the wave leader.
		# Roles are assigned per ship as it arrives, because wingmen now spawn
		# one per frame and the full array is not available synchronously.
		spawn_wave(comps[_wave_no - 1],
			_carrier.global_position + Vector3(randf_range(-2500, 2500), randf_range(-300, 500), -3400),
			300.0, Combatant.TEAM_HOSTILE,
			func(e: EnemyShip, lead: EnemyShip):
				if e.eid == "mauler":
					e.target = _carrier
				else:
					e.escort = lead)
		hud.set_objective("Defend the Solace", "Bomber wave %d of 4" % _wave_no)
		hud.comms("SOLACE ACTUAL", "Wave %d on the scope. Splash those Maulers!" % _wave_no)
	if _wave_no >= 4 and hostile_fighters_alive() == 0 and stage_t > 20.0:
		hud.comms("SOLACE ACTUAL", "Deck reports zero contacts. You just saved eight hundred souls.")
		mission_complete()

func _dir_capital_strike() -> void:
	if stage_t > 8.0 and _capitals_alive() == 0 and hostile_fighters_alive() == 0:
		hud.comms("COMMAND", "Both Krakens broken. The picket line is open.")
		mission_complete()

# ------------------------------------------------------------- fleet action
## Three escalating stages built around the new capital line: a destroyer screen,
## then the Sovereign's approach, then taking it apart subsystem by subsystem.
## Losing the Leviathan is an instant fail, which is what makes the screening job
## on stage 0 matter rather than being a warm-up.
func _dir_fleet_action(_delta: float) -> void:
	if _leviathan == null or not is_instance_valid(_leviathan) or not _leviathan.alive:
		mission_failed("The Leviathan is gone. Eleven thousand hands with her.")
		return
	match stage:
		0:
			if _spawn_cd <= 0.0 and _wave_no < 2:
				_wave_no += 1
				_spawn_cd = 34.0
				var w := spawn_capital("warden",
					Vector3(randf_range(-1400, 1400), randf_range(-200, 300), -3600),
					Combatant.TEAM_HOSTILE, randf_range(-0.4, 0.4))
				spawn_wave(["stinger", "jackal", "razor"],
					w.global_position + Vector3(0, 120, 500))
				hud.comms("LEVIATHAN ACTUAL", "Warden destroyer on the scope, bearing marked. Break it.")
				hud.set_objective("Break the VEX screen", "Destroyer %d of 2" % _wave_no)
			if _wave_no >= 2 and stage_t > 12.0 and _capitals_alive() == 0 \
					and hostile_fighters_alive() == 0:
				_advance(1)
				_sovereign = spawn_capital("sovereign", Vector3(300, 60, -6200),
					Combatant.TEAM_HOSTILE, 0.05)
				spawn_wave(["brute", "jackal", "jackal", "razor"], Vector3(300, 60, -5400))
				hud.comms("LEVIATHAN ACTUAL", "Screen is down — and there she is. Sovereign, closing.")
				hud.comms("COMMAND", "Kill her engines first. A dreadnought that cannot close is a target range.")
				hud.set_objective("Disable the Sovereign", "Destroy all three engine blocks",
					Vector3(300, 60, -6200))
		1:
			if _sovereign and is_instance_valid(_sovereign) and _sovereign.subs_alive("engine") == 0:
				_advance(2)
				hud.comms("COMMAND", "She's dead in the water. Capacitor bank amidships — that spinal gun still works.")
				hud.set_objective("Silence the spinal mass driver", "Capacitor bank, ventral hull")
		2:
			if _sovereign and is_instance_valid(_sovereign) and _sovereign.subs_alive("launcher") == 0:
				_advance(3)
				hud.comms("LEVIATHAN ACTUAL", "Spinal gun is cold. Finish her — reactor, underside, aft of centre.")
				hud.set_objective("DESTROY THE REACTOR", "Ventral hull, aft of amidships")
		3:
			if _sovereign == null or not is_instance_valid(_sovereign) or not _sovereign.alive:
				_advance(4)
				score += 3000
				hud.comms("LEVIATHAN ACTUAL", "Sovereign is breaking up. Deck's yours whenever you want it, Vanguard.")
				mission_complete()

func _dir_survival() -> void:
	if _spawn_cd <= 0.0 and hostile_fighters_alive() <= 1:
		_wave_no += 1
		_spawn_cd = 8.0
		var comp: Array = []
		var budget := 2 + _wave_no
		var menu := ["razor", "razor", "jackal", "jackal", "stinger", "brute", "widow", "mauler"]
		while budget > 0 and comp.size() < 8:
			var pick: String = menu[randi() % mini(menu.size(), 2 + _wave_no)]
			comp.append(pick)
			budget -= 2 if pick in ["brute", "mauler"] else 1
		spawn_wave(comp, player.global_position + Vector3(randf_range(-1800, 1800), randf_range(-300, 400), randf_range(-2400, -1200)))
		hud.set_objective("Survive", "Wave %d" % _wave_no)
		hud.comms("SIM DECK", "Wave %d. Score %d." % [_wave_no, score])
		score += 50 * maxi(_wave_no - 1, 0)

func _spawn_arena_targets() -> void:
	for i in 10:
		var pos := Vector3(randf_range(-700, 700), randf_range(-200, 300), randf_range(-1600, -500))
		var e := spawn_enemy("widow", pos)
		e.set_physics_process(false)
		e.display_name = "Target Drone"
	var k := spawn_capital("kraken", Vector3(0, 0, -2600), Combatant.TEAM_HOSTILE, 0.0)
	for t in k.turrets:
		t.set_physics_process(false)

# ------------------------------------------------------------------- training
func _dir_training() -> void:
	match _train_step:
		0:
			if player.global_position.distance_to(Vector3(0, 0, -1200)) < 160.0:
				_train_step = 1
				hud.comms("INSTRUCTOR", "Good. Now hold Shift and boost through the rock cluster ahead.")
				hud.set_objective("Boost to the far marker", "Hold Shift — watch your energy", Vector3(0, 0, -2600))
		1:
			if player.global_position.distance_to(Vector3(0, 0, -2600)) < 200.0:
				_train_step = 2
				spawn_wave(["widow", "widow", "widow"], Vector3(0, 50, -3200))
				for h in get_tree().get_nodes_in_group("hostiles"):
					if h is EnemyShip:
						(h as EnemyShip).set_physics_process(false)
						(h as EnemyShip).display_name = "Practice Drone"
				hud.comms("INSTRUCTOR", "Practice drones released. R cycles targets, guns on left mouse.")
				hud.set_objective("Destroy the practice drones", "R to target • left mouse to fire")
		2:
			if hostile_fighters_alive() == 0:
				_train_step = 3
				var d := spawn_enemy("razor", Vector3(300, 100, -3400))
				d.display_name = "Evasive Drone"
				d.edef = d.edef.duplicate()
				d.edef.acc = 0.0
				d.weapons.wpn_a = "e_light"
				hud.comms("INSTRUCTOR", "This one dodges. Hold the lock reticle on it and fire a missile — right mouse.")
				hud.set_objective("Missile kill the evasive drone", "T targets it • hold lock • right mouse")
		3:
			if hostile_fighters_alive() == 0:
				_train_step = 4
				stage_t = 0.0
				hud.comms("INSTRUCTOR", "Last drill: when you hear the missile tone, hit G for flares and turn hard.")
				var m := spawn_enemy("stinger", player.global_position + Vector3(0, 0, 900))
				m.display_name = "Instructor Drone"
				m.edef = m.edef.duplicate()
				m.edef.acc = 0.0
				m._msl_cd = 1.0
				hud.set_objective("Survive the missile drill", "G deploys flares • keep turning")
		4:
			if stage_t > 22.0 or hostile_fighters_alive() == 0:
				for h in get_tree().get_nodes_in_group("hostiles"):
					if h is Combatant:
						(h as Combatant).die(null)
				Game.save.training_done = true
				Game.mark_save_dirty()
				Game.save_game()
				hud.comms("INSTRUCTOR", "That's a pass, pilot. The fleet needs you — report to the Solace.")
				mission_complete()

# ------------------------------------------------------------------- main op
func _dir_main(delta: float) -> void:
	match stage:
		0: # transit the belt
			hud.set_objective("Cross the asteroid belt", "Follow the nav marker", Vector3(0, 0, -3800))
			if player.global_position.z < -3400.0:
				_advance(1)
				spawn_wave(["razor", "razor", "razor"], Vector3(0, 100, -4600))
				hud.comms("SOLACE ACTUAL", "Scouts on the scope. If one escapes, the Bastion knows we're coming.")
				hud.set_objective("Destroy the VEX scouts", "Leave no survivors")
		1: # scouts
			if stage_t > 4.0 and hostile_fighters_alive() == 0:
				_advance(2)
				_spawn_convoy()
				_wave_no = 0
				_spawn_cd = 6.0
				hud.comms("HAULER LEAD", "Escort, our torpedo re-supply is crossing your position.")
				hud.set_objective("Protect the supply haulers", "Two raids expected")
		2: # convoy micro-defence
			var alive := 0
			var lead := Vector3.ZERO
			for h in _convoy:
				if is_instance_valid(h) and h.alive:
					alive += 1
					lead = h.global_position
			if alive == 0:
				mission_failed("The supply haulers are gone — no torpedoes, no strike.")
				return
			if _wave_no < 2 and _spawn_cd <= 0.0:
				_wave_no += 1
				_spawn_cd = 40.0
				spawn_wave(["razor", "jackal"] if _wave_no == 1 else ["stinger", "jackal", "razor"],
					lead + Vector3(randf_range(-1200, 1200), 250, -1800))
				hud.comms("COMMAND", "Raiders vectoring on the haulers!")
			if _wave_no >= 2 and hostile_fighters_alive() == 0 and stage_t > 30.0:
				_advance(3)
				spawn_wave(["stinger", "stinger", "stinger", "stinger"], player.global_position + Vector3(0, -200, -2000), 700.0)
				hud.comms("COMMAND", "AMBUSH! Missile fighters, all quadrants — flares ready!")
				hud.set_objective("Survive the missile ambush", "G for flares • keep moving")
		3: # ambush
			if stage_t > 5.0 and hostile_fighters_alive() == 0:
				_advance(4)
				_place_turret_line(Vector3(0, 0, -7200))
				hud.comms("COMMAND", "Their outer sensor line: gun platforms on the big rocks. Take them out.")
				hud.set_objective("Destroy the 4 gun platforms", "", Vector3(0, 0, -7200))
		4: # turret line
			var t_alive := 0
			for t in _turret_line:
				if is_instance_valid(t) and t.alive:
					t_alive += 1
			hud.set_objective("Destroy the gun platforms (%d left)" % t_alive, "", Vector3(0, 0, -7200) if t_alive > 0 else Vector3.INF)
			if t_alive == 0:
				_advance(5)
				var k := spawn_capital("kraken", Vector3(200, 0, -8800), Combatant.TEAM_HOSTILE, 0.1)
				spawn_wave(["jackal", "jackal"], Vector3(0, 100, -8500))
				hud.comms("COMMAND", "Picket corvette dead ahead. Break its engines, then burn it down.")
				hud.set_objective("Destroy the Kraken corvette", "Engines are the weak point")
		5: # corvette
			if stage_t > 6.0 and _capitals_alive() == 0:
				_advance(6)
				_bastion = spawn_capital("bastion", Vector3(0, 0, -12500), Combatant.TEAM_HOSTILE, 0.0)
				hud.comms("SOLACE ACTUAL", "There it is. The Bastion. Shields up — find the four generator domes on the ring.")
				hud.set_objective("Approach the Bastion", "", Vector3(0, 0, -11000))
		6: # approach
			if player.global_position.z < -10200.0:
				_advance(7)
				hud.comms("COMMAND", "In range. Generators first — the core is invulnerable until they're down.")
				hud.set_objective("Destroy the 4 shield generators", "Blue domes on the ring")
				_spawn_cd = 20.0
		7: # shields
			_reinforce(delta, 3)
			if _bastion and _bastion.subs_alive("shieldgen") == 0:
				_advance(8)
				hud.comms("COMMAND", "Shield collapse confirmed! Radar mast and missile batteries next.")
				hud.set_objective("Destroy radar + missile launchers", "Optional: the hangar stops reinforcements")
		8: # subsystems
			_reinforce(delta, 3)
			if _bastion and _bastion.subs_alive("radar") == 0 and _bastion.subs_alive("launcher") == 0:
				_advance(9)
				hud.comms("SOLACE ACTUAL", "The reactor is exposed on the underside. Put everything you have into it.")
				hud.set_objective("DESTROY THE REACTOR", "Underside of the core sphere")
		9: # reactor
			_reinforce(delta, 2)
			if _bastion and _bastion.reactor and not _bastion.reactor.alive:
				_advance(10)
				hud.comms("SOLACE ACTUAL", "Reactor cascade! Vanguard, burn for the extraction point NOW!")
				hud.set_objective("ESCAPE THE BLAST", "Reach the extraction marker!", Vector3(0, 400, -6500))
		10: # escape
			if player.global_position.distance_to(Vector3(0, 400, -6500)) < 350.0 or stage_t > 60.0:
				_advance(11)
				score += 2500
				hud.comms("SOLACE ACTUAL", "The Bastion is a new star, and you put it in the sky. Come home, Vanguard.")
				mission_complete()

func _advance(s: int) -> void:
	stage = s
	stage_t = 0.0
	AudioMgr.play_ui("objective")

func _place_turret_line(center: Vector3) -> void:
	for i in 4:
		var t := Turret.new()
		add_child(t)
		var pos := center + Vector3(randf_range(-900, 900), randf_range(-250, 250), randf_range(-500, 500))
		t.global_position = pos
		t.build(self, Combatant.TEAM_HOSTILE, "e_turret", null)
		t.display_name = "Gun Platform %d" % (i + 1)
		_turret_line.append(t)

func _reinforce(_delta: float, cap: int) -> void:
	if _spawn_cd <= 0.0 and hostile_fighters_alive() < cap and _bastion and _bastion.alive:
		_spawn_cd = 26.0
		if _bastion.subs_alive("hangar") > 0:
			spawn_wave(["razor", "jackal"], _bastion.global_position + Vector3(0, -50, 300))
			hud.comms("COMMAND", "Fresh fighters from the Bastion's hangar!")
