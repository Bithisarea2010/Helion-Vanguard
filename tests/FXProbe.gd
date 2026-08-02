extends Node3D
## Visual probe for the explosion / missile / asteroid FX.
##
## The battle harness screenshots on a fixed 4 s cadence, which almost never
## lines up with a blast — verifying explosion work from it is guesswork. This
## scene parks a static camera, fires one effect at a known time and grabs the
## frame at a known offset after ignition, so the same shot is reproducible run
## to run.
##
##   Godot --path . --resolution 1280x720 tests/FXProbe.tscn -- --shotdir=/abs/dir

var _shot_dir := ""
var _script: Array = []          # [{t, fn}] sorted by time
var _t := 0.0
var _next := 0
var _idx := 0
var _cam: Camera3D

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shotdir="):
			_shot_dir = arg.get_slice("=", 1)
			DirAccess.make_dir_recursive_absolute(_shot_dir)
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 40000.0
	add_child(_cam)
	_cam.position = Vector3(0, 3, 34)
	_cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	_cam.current = true
	var key := DirectionalLight3D.new()
	key.light_energy = 1.6
	key.rotation_degrees = Vector3(-28, 34, 0)
	add_child(key)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# near-neutral, dim ambient. A saturated blue fill here made the rocks look
	# like blue glass and sent me chasing a shader bug that was the probe's own
	# lighting; the real belt gets its fill from SpaceEnv's baked panorama.
	e.ambient_light_color = Color(0.20, 0.20, 0.21)
	e.ambient_light_energy = 0.35
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_bloom = 0.25
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	add_child(env)
	_build_script()

func _build_script() -> void:
	# medium blast, sampled through its whole life
	_add(0.5, func(): FX.explosion(self, Vector3.ZERO, 1))
	_add(0.56, _grab); _add(0.72, _grab); _add(1.05, _grab); _add(2.0, _grab)
	# large blast
	_add(3.2, func(): FX.explosion(self, Vector3.ZERO, 2))
	_add(3.30, _grab); _add(3.60, _grab); _add(4.3, _grab)
	# missile: launched unguided across the frame. Missile only touches
	# _battle.flares / all_combatants() when it has a target, so passing this
	# probe as the battle node is enough with tgt = null.
	_add(4.8, func():
		_cam.position = Vector3(0, 2, 26)
		_cam.look_at(Vector3(0, 0, -10), Vector3.UP)
		Missile.launch(self, Vector3(-16, -1, -6), Vector3(1, 0, 0.05).normalized(),
			Vector3.ZERO, ShipDB.MISSILES.values()[0], null, 1, null))
	_add(4.95, _grab)
	_add(5.35, _grab)
	# rock field: one overview, one close pass. The camera must stay OUTSIDE the
	# cluster — a shot taken from inside a 60 m boulder says nothing about how
	# the surface reads in the belt.
	_add(6.0, func():
		var f := AsteroidField.new()
		add_child(f)
		# populate_cluster spreads rocks by radius*0.4 in sigma, so a radius of
		# 70 reaches ~60 m and swallowed the camera at z = -56
		f.populate_cluster(Vector3(0, 0, -190), 55.0, 150, 3)
		f.commit()
		_cam.position = Vector3(0, 12, -20)
		_cam.look_at(Vector3(0, 0, -190), Vector3.UP))
	_add(6.5, _grab)
	_add(7.2, func():
		_cam.position = Vector3(0, 5, -90)
		_cam.look_at(Vector3(0, 0, -190), Vector3.UP))
	_add(7.7, _grab)
	_add(8.4, _quit)

func _add(t: float, fn: Callable) -> void:
	_script.append({"t": t, "fn": fn})

func _process(delta: float) -> void:
	_t += delta
	while _next < _script.size() and _t >= float(_script[_next].t):
		(_script[_next].fn as Callable).call()
		_next += 1

func _grab() -> void:
	if _shot_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_idx += 1
	img.save_png("%s/fx_%02d.png" % [_shot_dir, _idx])
	print("[FXPROBE] shot %d at t=%.2f" % [_idx, _t])

func _quit() -> void:
	print("[FXPROBE] done, shots=%d" % _idx)
	Game.prepare_shutdown()
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()
