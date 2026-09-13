extends CanvasLayer
## Persistent FTL loading / waiting-screen coordinator.
##
## Scene resources are tiny code-built stubs in Helion Vanguard, so Game,
## MainMenu and Battle publish honest semantic milestones through report().

const WALLPAPER := "res://assets/loading/helion_corridor.png"
const COMBAT_REEL := "res://assets/loading/combat_reel.ogv"
const PROGRESS_SCRIPT := preload("res://scripts/ui/LoadingProgress.gd")
## Intentional presentation windows measured from begin(). Real loading may
## take longer, but a fast machine still gets time to show the cinematic UI.
const PRESENT_SECONDS := {
	"boot": 8.0,
	"mission": 9.0,
	"return": 7.0,
	"uplink": 7.5,
}

var _root: Control
var _wallpaper: TextureRect
var _video: VideoStreamPlayer
var _dim: ColorRect
var _flash: ColorRect
var _brand: Label
var _eyebrow: Label
var _title: Label
var _subtitle: Label
var _build: Label
var _progress: Control
var _ambient: AudioStreamPlayer
var _ship_container: SubViewportContainer
var _ship_viewport: SubViewport
var _ship_root: Node3D
var _orbit_a: Line2D
var _orbit_b: Line2D
var _motes: Array[ColorRect] = []
var _active := false
var _busy := false
var _finishing := false
var _faulted := false
var _started_msec := 0
var _last_stage := ""
var _reported_progress := 0.0
var _watchdog_serial := 0
var _retry_path := ""
var _retry_context: Dictionary = {}
var _kind := "boot"
var _minimum_present_seconds := 8.0
var _time := 0.0
var _parallax := Vector2.ZERO

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()
	set_process(true)

func begin(context: Dictionary = {}) -> void:
	if _root == null:
		return
	_active = true
	_finishing = false
	_faulted = false
	_watchdog_serial += 1
	_started_msec = Time.get_ticks_msec()
	_last_stage = ""
	_reported_progress = 0.0
	_kind = str(context.get("kind", "boot"))
	_minimum_present_seconds = clampf(float(context.get("min_present_seconds",
		PRESENT_SECONDS.get(_kind, 8.0))), 0.0, 10.0)
	if bool(Game.settings.quick_transitions):
		_minimum_present_seconds = minf(_minimum_present_seconds, 1.2 if _kind == "boot" else 0.45)
	_progress.call("reset")
	_eyebrow.text = str(context.get("eyebrow", "HELION COMMAND  //  FTL INSERTION"))
	_title.text = str(context.get("title", "VANGUARD SYSTEMS"))
	_subtitle.text = str(context.get("subtitle", "Establishing the launch corridor"))
	_build.text = "BUILD %s  //  %s  //  SECURE LINK" % [Game.VERSION,
		Game.PRESET_NAMES[clampi(int(Game.settings.preset), 0, Game.PRESET_NAMES.size() - 1)]]
	_select_wallpaper(context)
	_root.visible = true
	_root.modulate = Color(1, 1, 1, 0)
	_flash.color = Color(0.8, 0.95, 1.0, 0.0)
	_wallpaper.visible = true
	_start_cinematic(str(context.get("kind", "")) in ["mission", "uplink"])
	_build_ship_diorama(str(context.get("ship_id", "")) if str(context.get("kind", "")) == "mission" else "")
	_start_ambience(str(context.get("kind", "")))
	report(0.0, "FTL CORRIDOR", str(context.get("detail", "Awaiting flight-control telemetry")))
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_root, "modulate:a", 1.0, 0.26).set_trans(Tween.TRANS_QUAD)
	_progress.grab_focus.call_deferred()

func transition_to(path: String, context: Dictionary = {}) -> void:
	if _busy:
		return
	_busy = true
	begin(context)
	_retry_path = path
	_retry_context = context.duplicate(true)
	_arm_watchdog(path, context, _watchdog_serial, 35.0)
	await get_tree().process_frame
	await get_tree().process_frame
	report(0.025, "TRANSFER GATE", "Opening secure scene channel")
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("SceneFlow could not open %s: %s" % [path, error_string(err)])
		_enter_fault(path, context, "TRANSFER FAULT",
			"Scene channel rejected (%s) — pulse the FTL field to retry" % error_string(err))

## First-time renderer work can block a frame beyond the initial 35-second
## transfer deadline. Give a scene which has reported initialization milestones
## a bounded grace period; missing resources still fail at the normal deadline.
func _watchdog_grace_seconds() -> float:
	if _reported_progress <= 0.025 or _reported_progress >= 1.0:
		return 0.0
	var elapsed := float(Time.get_ticks_msec() - _started_msec) / 1000.0
	return clampf(120.0 - elapsed, 0.0, 35.0)

func _arm_watchdog(path: String, context: Dictionary, serial: int, seconds: float) -> void:
	get_tree().create_timer(seconds, true, false, true).timeout.connect(func():
		if not _active or not _busy or serial != _watchdog_serial:
			return
		var grace := _watchdog_grace_seconds()
		if grace > 0.1:
			_progress.call("set_progress", _reported_progress, _last_stage,
				"Preparing the scene — first use of a graphics profile can take longer")
			_arm_watchdog(path, context, serial, grace)
			return
		push_warning("SceneFlow watchdog held a stalled transition to %s" % path)
		_enter_fault(path, context, "TRANSFER HOLD",
			"Scene channel timed out — pulse the FTL field to retry"))

## Keep the overlay between the player and a missing or half-initialised scene.
## The focused FTL instrument becomes a retry control; unlike finish(), this
## path never plays clearance audio or claims that systems are green.
func _enter_fault(path: String, context: Dictionary, stage: String, detail: String) -> void:
	if not _active or _finishing:
		return
	_busy = false
	_faulted = true
	_watchdog_serial += 1
	_retry_path = path
	_retry_context = context.duplicate(true)
	_title.text = "TRANSFER INTERRUPTED"
	_subtitle.text = "Flight control is holding the corridor open"
	report(_reported_progress, stage, detail)
	_stop_ambience()
	AudioMgr.play_ui("ui_deny", -2.0)
	_progress.grab_focus.call_deferred()

func report(value: float, stage: String, detail := "") -> void:
	if not _active or _progress == null:
		return
	_reported_progress = maxf(_reported_progress, clampf(value, 0.0, 1.0))
	_progress.call("set_progress", _reported_progress, stage, detail)
	if stage != "" and stage != _last_stage:
		_last_stage = stage
		var pitch := lerpf(0.86, 1.18, _reported_progress)
		AudioMgr.play_ui("ui_target", -17.0, pitch)

func finish() -> void:
	if not _active or _finishing or _faulted:
		return
	# Set the guard and invalidate the watchdog before the first await so a late
	# timeout cannot enter a second flash/fade coroutine.
	_finishing = true
	_watchdog_serial += 1
	var elapsed := float(Time.get_ticks_msec() - _started_msec) / 1000.0
	var remaining := maxf(0.0, _minimum_present_seconds - elapsed)
	if remaining > 0.0:
		var hold_stage := _hold_stage()
		while remaining > 0.01 and _active and not _faulted:
			var hold_detail := _hold_detail(remaining)
			if _last_stage != hold_stage:
				report(_reported_progress, hold_stage, hold_detail)
			else:
				# Countdown updates should not replay the stage-change tone.
				_progress.call("set_progress", _reported_progress, hold_stage, hold_detail)
			var slice := minf(0.25, remaining)
			await get_tree().create_timer(slice, true, false, true).timeout
			elapsed = float(Time.get_ticks_msec() - _started_msec) / 1000.0
			remaining = maxf(0.0, _minimum_present_seconds - elapsed)
	if _kind == "uplink":
		report(1.0, "UPLINK COMPLETE", "Debrief package authenticated — channel released")
	else:
		report(1.0, "LAUNCH CLEARANCE", "All systems green — insertion authorised")
	AudioMgr.play_ui("ftl_breach", -3.0)
	AudioMgr.play_ui("ui_ready", -1.0, 1.04)
	_flash.color = Color(0.78, 0.93, 1.0, 0.0)
	var flash_tw := create_tween()
	flash_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	flash_tw.tween_property(_flash, "color:a", 0.32 * float(Game.settings.flash_intensity), 0.10)
	flash_tw.tween_property(_flash, "color:a", 0.0, 0.34)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(0.16)
	tw.tween_property(_root, "modulate:a", 0.0, 0.38).set_trans(Tween.TRANS_QUAD)
	await tw.finished
	_stop_ambience()
	_stop_cinematic()
	_clear_ship_diorama()
	_root.visible = false
	_active = false
	_busy = false
	_finishing = false
	_retry_path = ""
	_retry_context.clear()

func _hold_stage() -> String:
	match _kind:
		"mission":
			return "INSERTION VECTOR"
		"return":
			return "FLIGHT-DECK APPROACH"
		"uplink":
			return "DEBRIEF CHANNEL"
		_:
			return "FTL WINDOW"

func _hold_detail(remaining: float) -> String:
	var countdown := "%.1f S" % remaining
	match _kind:
		"mission":
			return "Combat insertion window opens in %s  //  FTL field interactive" % countdown
		"return":
			return "Flight-deck approach completes in %s  //  FTL field interactive" % countdown
		"uplink":
			return "Debrief channel opens in %s  //  Flight recorder secured" % countdown
		_:
			return "Cold-start corridor opens in %s  //  FTL field interactive" % countdown

func _build_interface() -> void:
	_root = Control.new()
	_root.name = "FTLLoadingScreen"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)

	_wallpaper = TextureRect.new()
	_wallpaper.name = "HelionCorridorWallpaper"
	_wallpaper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wallpaper.offset_left = -48
	_wallpaper.offset_top = -48
	_wallpaper.offset_right = 48
	_wallpaper.offset_bottom = 48
	_wallpaper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wallpaper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_wallpaper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(WALLPAPER):
		_wallpaper.texture = load(WALLPAPER)
	_root.add_child(_wallpaper)

	_video = VideoStreamPlayer.new()
	_video.name = "GameplayCinematic"
	_video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_video.expand = true
	_video.loop = true
	_video.volume_db = -80.0
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video.visible = false
	_root.add_child(_video)

	_ship_container = SubViewportContainer.new()
	_ship_container.anchor_left = 0.52
	_ship_container.anchor_right = 0.98
	_ship_container.anchor_top = 0.08
	_ship_container.anchor_bottom = 0.69
	_ship_container.stretch = true
	_ship_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ship_container.modulate = Color(1, 1, 1, 0.84)
	_ship_container.visible = false
	_root.add_child(_ship_container)

	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.006, 0.014, 0.035, 0.40)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)

	_build_orbits()
	_build_motes()

	var top := MarginContainer.new()
	top.anchor_left = 0.045
	top.anchor_right = 0.72
	top.anchor_top = 0.055
	top.anchor_bottom = 0.47
	top.add_theme_constant_override("margin_left", 0)
	top.add_theme_constant_override("margin_top", 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(top)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 7)
	top.add_child(vb)
	_brand = Styles.label("HELION  /  VANGUARD", 13, Styles.ORANGE, true)
	vb.add_child(_brand)
	_eyebrow = Styles.label("HELION COMMAND  //  FTL INSERTION", 12, Styles.CYAN, true)
	vb.add_child(_eyebrow)
	_title = Styles.label("VANGUARD SYSTEMS", 48, Color(0.96, 0.98, 1.0), true)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_title)
	_subtitle = Styles.label("Establishing the launch corridor", 17,
		Color(0.79, 0.86, 0.94))
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_subtitle)
	_build = Styles.label("BUILD", 11, Styles.DIM, true)
	vb.add_child(_build)

	_progress = PROGRESS_SCRIPT.new()
	_progress.anchor_left = 0.045
	_progress.anchor_right = 0.955
	_progress.anchor_top = 0.69
	_progress.anchor_bottom = 0.94
	_progress.offset_left = 0
	_progress.offset_right = 0
	_progress.offset_top = 0
	_progress.offset_bottom = 0
	_progress.pulse_requested.connect(_on_progress_pulse)
	_root.add_child(_progress)

	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(0.8, 0.95, 1.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)

	_ambient = AudioStreamPlayer.new()
	_ambient.bus = "UI"
	_ambient.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ambient)

func _build_orbits() -> void:
	_orbit_a = Line2D.new()
	_orbit_a.width = 1.4
	_orbit_a.default_color = Color(Styles.CYAN.r, Styles.CYAN.g, Styles.CYAN.b, 0.22)
	_orbit_a.closed = true
	for i in 96:
		var a := TAU * float(i) / 96.0
		_orbit_a.add_point(Vector2(cos(a) * 330.0, sin(a) * 118.0))
	_root.add_child(_orbit_a)
	_orbit_b = Line2D.new()
	_orbit_b.width = 1.0
	_orbit_b.default_color = Color(Styles.ORANGE.r, Styles.ORANGE.g, Styles.ORANGE.b, 0.15)
	_orbit_b.closed = true
	for i in 80:
		var a := TAU * float(i) / 80.0
		_orbit_b.add_point(Vector2(cos(a) * 232.0, sin(a) * 170.0))
	_root.add_child(_orbit_b)

func _build_motes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x48454C494F4E
	for i in 30:
		var mote := ColorRect.new()
		var s := rng.randf_range(1.0, 3.2)
		mote.size = Vector2(s * (2.4 if i % 7 == 0 else 1.0), s)
		mote.color = Color(Styles.ORANGE.r, Styles.ORANGE.g, Styles.ORANGE.b, 0.65) \
			if i % 6 == 0 else Color(Styles.CYAN.r, Styles.CYAN.g, Styles.CYAN.b, 0.52)
		mote.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mote.set_meta("seed", Vector3(rng.randf(), rng.randf(), rng.randf_range(0.6, 1.8)))
		_root.add_child(mote)
		_motes.append(mote)

func _process(delta: float) -> void:
	if not _active or _root == null or not _root.visible:
		return
	_time += delta
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		return
	var pointer := get_viewport().get_mouse_position() / vp - Vector2(0.5, 0.5)
	var motion_scale := clampf(float(Game.settings.get("camera_shake", 1.0)), 0.0, 1.0)
	_parallax = _parallax.lerp(pointer * -22.0 * motion_scale, 1.0 - exp(-3.8 * delta))
	_wallpaper.position = Vector2(-48, -48) + _parallax
	_orbit_a.position = vp * Vector2(0.77, 0.40) + _parallax * 0.35
	_orbit_b.position = vp * Vector2(0.77, 0.40) + _parallax * 0.18
	_orbit_a.rotation = _time * 0.035
	_orbit_b.rotation = -_time * 0.022
	for i in _motes.size():
		var mote := _motes[i]
		var seed: Vector3 = mote.get_meta("seed")
		var x := fposmod(seed.x * vp.x + _time * 22.0 * seed.z, vp.x + 80.0) - 40.0
		var y := seed.y * vp.y + sin(_time * seed.z + float(i)) * 14.0
		mote.position = Vector2(x, y) + _parallax * seed.z
	if _ship_root:
		_ship_root.rotation.y += delta * 0.28
		_ship_root.rotation.z = sin(_time * 0.44) * 0.08
		_ship_root.position.y = sin(_time * 0.72) * 0.20

func _on_progress_pulse() -> void:
	AudioMgr.play_ui("radar_ping", -9.0, randf_range(0.96, 1.08))
	if _faulted and _retry_path != "":
		var path := _retry_path
		var context := _retry_context.duplicate(true)
		_faulted = false
		_retry_path = ""
		_retry_context.clear()
		transition_to(path, context)
		return
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_orbit_a, "modulate", Color(1.7, 1.7, 1.7, 1), 0.08)
	tw.tween_property(_orbit_a, "modulate", Color.WHITE, 0.42)

func _start_ambience(kind: String) -> void:
	_stop_ambience()
	var sound := "ftl_cruise" if kind == "mission" else "ftl_spool"
	var stream: AudioStream = AudioMgr.stream(sound)
	if stream == null:
		return
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = int(stream.get_length() * (stream as AudioStreamWAV).mix_rate)
	_ambient.stream = stream
	_ambient.volume_db = -17.0
	_ambient.play()

func _stop_ambience() -> void:
	if _ambient and _ambient.playing:
		_ambient.stop()
	if _ambient:
		_ambient.stream = null

func _start_cinematic(allow: bool) -> void:
	_stop_cinematic()
	if not allow or not ResourceLoader.exists(COMBAT_REEL):
		return
	var stream := load(COMBAT_REEL) as VideoStream
	if stream == null:
		return
	_video.stream = stream
	_video.modulate = Color(0.76, 0.86, 1.0, 0.58)
	_video.visible = true
	_video.play()

func _select_wallpaper(context: Dictionary) -> void:
	var kind := str(context.get("kind", ""))
	var mission := str(context.get("mission_id", ""))
	var ship_id := str(context.get("ship_id", ""))
	var candidate := WALLPAPER
	# The corridor is the dramatic, instant cold-start master. The calmer fleet
	# plates are reserved for contexts where the pictured hull reinforces the
	# operation instead of becoming a generic background on every launch.
	if kind == "return" or ship_id == "paladin":
		candidate = "res://assets/loading/helion_hangar.png"
	elif mission == "capital_strike":
		candidate = "res://assets/loading/helion_plate_sovereign.jpg"
	elif mission in ["fleet_action", "main"]:
		candidate = "res://assets/loading/helion_leviathan.png"
	elif kind in ["mission", "uplink"]:
		# The combat reel supplies the moving belt imagery. Keep the cinematic
		# corridor as its deterministic first-frame/fallback plate.
		candidate = WALLPAPER
	if not ResourceLoader.exists(candidate):
		candidate = WALLPAPER
	if ResourceLoader.exists(candidate):
		_wallpaper.texture = load(candidate)

func _stop_cinematic() -> void:
	if _video == null:
		return
	if _video.is_playing():
		_video.stop()
	_video.visible = false
	_video.stream = null

func _build_ship_diorama(ship_id: String) -> void:
	_clear_ship_diorama()
	if ship_id == "" or not ShipDB.SHIPS.has(ship_id):
		return
	var sdef: Dictionary = ShipDB.SHIPS[ship_id]
	var path := str(sdef.get("model", ""))
	if path == "" or not ResourceLoader.exists(path):
		return
	_ship_viewport = SubViewport.new()
	_ship_viewport.size = Vector2i(720, 720)
	_ship_viewport.transparent_bg = true
	_ship_viewport.own_world_3d = true
	_ship_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_ship_container.add_child(_ship_viewport)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 2.2, 18.0)
	cam.fov = 48.0
	cam.near = 0.1
	cam.far = 200.0
	_ship_viewport.add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	var key := OmniLight3D.new()
	key.position = Vector3(8, 9, 12)
	key.light_color = Color(1.0, 0.68, 0.36)
	key.light_energy = 5.5
	key.omni_range = 60.0
	_ship_viewport.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-10, 1, -8)
	rim.light_color = Styles.CYAN
	rim.light_energy = 6.0
	rim.omni_range = 60.0
	_ship_viewport.add_child(rim)
	_ship_root = Node3D.new()
	_ship_viewport.add_child(_ship_root)
	var scene := load(path) as PackedScene
	if scene == null:
		_clear_ship_diorama()
		return
	var inst := scene.instantiate()
	_ship_root.add_child(inst)
	var lo: Dictionary = Game.loadout_for(ship_id)
	HullMaterial.apply(inst, {
		"paint": lo.paint, "glow": lo.glow, "plate_scale": 0.8,
		"wear": 0.34, "grime": 0.22, "bolts": 0.75,
		"stripe": lo.glow, "stripe_amount": 0.55,
		"rim": Color(0.34, 0.55, 0.92), "rim_strength": 0.9,
	})
	_ship_root.rotation = Vector3(-0.08, 0.62, -0.08)
	_ship_container.visible = true

func _clear_ship_diorama() -> void:
	_ship_container.visible = false
	_ship_root = null
	if _ship_viewport:
		_ship_viewport.queue_free()
		_ship_viewport = null

func _exit_tree() -> void:
	# Autoload teardown can happen in the middle of a transition during a quit or
	# test harness exit; release decoder and playback resources explicitly.
	_stop_ambience()
	_stop_cinematic()
	_clear_ship_diorama()
