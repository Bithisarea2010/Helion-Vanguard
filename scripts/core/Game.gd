extends Node
## Helion Vanguard — global game state, settings, input map, save system.

signal settings_changed
signal mission_ended(victory: bool, stats: Dictionary)

const VERSION := "1.1.0"
const SETTINGS_PATH := "user://settings.cfg"
const SAVE_PATH := "user://save.cfg"
const MIN_RENDER_SCALE := 0.50
const MAX_RENDER_SCALE := 2.00

enum DisplayMode { WINDOWED, BORDERLESS, EXCLUSIVE }
enum VSyncMode { OFF, ON, ADAPTIVE }

# ------------------------------------------------------------------ input map
# Each binding: {t:"key", c:physical keycode} | {t:"mouse", b:index}
#             | {t:"jbtn", b:index} | {t:"jaxis", a:axis, v:sign}
const DEFAULT_BINDINGS := {
	"thrust_forward": [{"t": "key", "c": KEY_W}, {"t": "jaxis", "a": JOY_AXIS_TRIGGER_RIGHT, "v": 1.0}],
	"thrust_back": [{"t": "key", "c": KEY_S}, {"t": "jaxis", "a": JOY_AXIS_TRIGGER_LEFT, "v": 1.0}],
	"strafe_left": [{"t": "key", "c": KEY_A}, {"t": "jaxis", "a": JOY_AXIS_RIGHT_X, "v": -1.0}],
	"strafe_right": [{"t": "key", "c": KEY_D}, {"t": "jaxis", "a": JOY_AXIS_RIGHT_X, "v": 1.0}],
	"roll_left": [{"t": "key", "c": KEY_Q}, {"t": "jbtn", "b": JOY_BUTTON_DPAD_LEFT}],
	"roll_right": [{"t": "key", "c": KEY_E}, {"t": "jbtn", "b": JOY_BUTTON_DPAD_RIGHT}],
	"move_up": [{"t": "key", "c": KEY_SPACE}, {"t": "jaxis", "a": JOY_AXIS_RIGHT_Y, "v": -1.0}],
	"move_down": [{"t": "key", "c": KEY_CTRL}, {"t": "jaxis", "a": JOY_AXIS_RIGHT_Y, "v": 1.0}],
	"boost": [{"t": "key", "c": KEY_SHIFT}, {"t": "jbtn", "b": JOY_BUTTON_A}],
	"fire_primary": [{"t": "mouse", "b": MOUSE_BUTTON_LEFT}, {"t": "jbtn", "b": JOY_BUTTON_RIGHT_SHOULDER}],
	"fire_secondary": [{"t": "mouse", "b": MOUSE_BUTTON_RIGHT}, {"t": "jbtn", "b": JOY_BUTTON_LEFT_SHOULDER}],
	"cycle_target": [{"t": "key", "c": KEY_R}, {"t": "jbtn", "b": JOY_BUTTON_X}],
	"target_crosshair": [{"t": "key", "c": KEY_T}, {"t": "jbtn", "b": JOY_BUTTON_Y}],
	"match_velocity": [{"t": "key", "c": KEY_X}, {"t": "jbtn", "b": JOY_BUTTON_LEFT_STICK}],
	"countermeasure": [{"t": "key", "c": KEY_G}, {"t": "jbtn", "b": JOY_BUTTON_B}],
	"weapon_group": [{"t": "key", "c": KEY_V}, {"t": "jbtn", "b": JOY_BUTTON_DPAD_UP}],
	"camera_cycle": [{"t": "key", "c": KEY_C}, {"t": "jbtn", "b": JOY_BUTTON_BACK}],
	"tactical_map": [{"t": "key", "c": KEY_B}, {"t": "jbtn", "b": JOY_BUTTON_DPAD_DOWN}],
	"flight_assist": [{"t": "key", "c": KEY_M}],
	"look_around": [{"t": "key", "c": KEY_ALT}],
	"photo_mode": [{"t": "key", "c": KEY_P}],
	"pause": [{"t": "key", "c": KEY_ESCAPE}, {"t": "jbtn", "b": JOY_BUTTON_START}],
	"pitch_up": [{"t": "jaxis", "a": JOY_AXIS_LEFT_Y, "v": 1.0}],
	"pitch_down": [{"t": "jaxis", "a": JOY_AXIS_LEFT_Y, "v": -1.0}],
	"yaw_left": [{"t": "jaxis", "a": JOY_AXIS_LEFT_X, "v": -1.0}],
	"yaw_right": [{"t": "jaxis", "a": JOY_AXIS_LEFT_X, "v": 1.0}],
}

const ACTION_LABELS := {
	"thrust_forward": "Forward thrust", "thrust_back": "Brake / reverse",
	"strafe_left": "Strafe left", "strafe_right": "Strafe right",
	"roll_left": "Roll left", "roll_right": "Roll right",
	"move_up": "Move up", "move_down": "Move down", "boost": "Boost",
	"fire_primary": "Primary weapon", "fire_secondary": "Missile / secondary",
	"cycle_target": "Cycle hostile targets", "target_crosshair": "Target under crosshair",
	"match_velocity": "Match target velocity", "countermeasure": "Countermeasures",
	"weapon_group": "Change weapon group", "camera_cycle": "Change camera",
	"tactical_map": "Tactical map", "flight_assist": "Toggle flight assist",
	"look_around": "Look around (hold, cockpit)",
	"photo_mode": "Photo mode", "pause": "Pause",
}

# ------------------------------------------------------------------ settings
const SETTINGS_DEFAULTS := {
	"display_mode": DisplayMode.BORDERLESS,
	"display_screen": 0,
	"window_size": Vector2i(1600, 900),
	"resolution_scale": 0.85,       # 0.5 .. 2.0; >1 is supersampling
	"scaling_mode": 1,              # 0 bilinear, 1 FSR1, 2 FSR2, 3 MetalFX temporal
	"vsync_mode": VSyncMode.ON,
	"fps_limit": 0,                 # 0 = uncapped
	"preset": 2,                    # 0 low 1 medium 2 high 3 ultra
	"mouse_sens": 1.0,
	"control_smoothing": 0.55,      # 0 = raw and twitchy, 1 = heavily filtered
	"invert_y": false,
	"aim_assist": true,
	"camera_shake": 1.0,
	"cam_distance": 1.0,            # chase-cam standoff multiplier, 0.7 .. 1.8
	"vol_master": 0.9, "vol_music": 0.7, "vol_sfx": 1.0, "vol_ui": 0.9,
	"difficulty": 1,                # 0 easy 1 normal 2 hard
	"momentum_mode": false,         # flight assist off by default? no: assist on
	"bindings": {},                 # action -> serialized override list
}
var settings: Dictionary = SETTINGS_DEFAULTS.duplicate(true)

const PRESET_NAMES := ["Low", "Medium", "High", "Ultra"]
# Every field is consumed. Ultra is intentionally more than a renamed MSAA
# toggle: it extends shadow distance/resolution, enables temporal AA, raises
# sky/planet detail, and increases scene/effect density on the next mission.
const PRESETS := [
	{"msaa": 0, "screen_aa": 1, "taa": false, "glow": false, "glow_quality": 0.0,
		"shadows": false, "shadow_size": 1024, "shadow_distance": 0.0,
		"ast_density": 0.45, "particles": 0.50, "debris": 3.0,
		"sky_size": Vector2i(2048, 1024), "planet_segments": 48, "planet_rings": 24},
	{"msaa": 0, "screen_aa": 2, "taa": false, "glow": true, "glow_quality": 0.72,
		"shadows": false, "shadow_size": 1024, "shadow_distance": 0.0,
		"ast_density": 0.70, "particles": 0.75, "debris": 5.0,
		"sky_size": Vector2i(3072, 1536), "planet_segments": 72, "planet_rings": 36},
	{"msaa": 1, "screen_aa": 0, "taa": false, "glow": true, "glow_quality": 1.0,
		"shadows": true, "shadow_size": 2048, "shadow_distance": 350.0,
		"ast_density": 1.0, "particles": 1.0, "debris": 8.0,
		"sky_size": Vector2i(4096, 2048), "planet_segments": 96, "planet_rings": 48},
	{"msaa": 2, "screen_aa": 0, "taa": true, "glow": true, "glow_quality": 1.18,
		"shadows": true, "shadow_size": 4096, "shadow_distance": 560.0,
		"ast_density": 1.35, "particles": 1.30, "debris": 12.0,
		"sky_size": Vector2i(4096, 2048), "planet_segments": 128, "planet_rings": 64},
]

# ------------------------------------------------------------------ save data
var save := {
	"selected_ship": "vanguard",
	"unlocked_ships": ["vanguard", "wasp"],
	"credits": 0,
	"missions_done": {},            # id -> best stats dict
	"loadouts": {},                 # ship_id -> {primary, secondary, missile, paint, glow}
	"training_done": false,
}

var current_mission := "instant_action"
var _hermetic := false          # --defaults: ignore and never write settings.cfg
var _settings_dirty := false
var _save_dirty := false
var battle_stats := {}
var last_debrief := {}
var rng := RandomNumberGenerator.new()

func _enter_tree() -> void:
	# CRITICAL: autoloads default to PAUSABLE — without ALWAYS, no input
	# handling runs while the tree is paused (photo mode / pause menu traps).
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	# `--defaults` makes a run hermetic: start from the built-in settings and
	# never write them back. Without it the harness is NOT reproducible —
	# settings.cfg is saved on quit, so `--preset=0` silently leaks into every
	# later run, and an A/B series measures whatever the previous run left
	# behind. This invalidated a whole benchmark batch before it was noticed.
	_hermetic = "--defaults" in OS.get_cmdline_user_args()
	if not _hermetic:
		_load_settings()
	_load_save()
	_normalize_settings()
	_normalize_save()
	_setup_input_map()

func _ready() -> void:
	get_tree().set_auto_accept_quit(true)
	apply_video_settings()
	apply_preset()
	# automated testing hook:  godot -- --mission=instant_action
	for arg in OS.get_cmdline_user_args():
		if arg == "--uncapped":
			# profiling: remove the vsync ceiling so [BENCH] shows real headroom
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
		elif arg == "--windowed":
			# Godot's own --resolution is USELESS here: apply_video_settings()
			# runs first and forces MODE_FULLSCREEN, so every benchmark this
			# project has ever run measured the same native 2880x1800 buffer.
			# That is why "frame time is identical at 640x360 and 1920x1080"
			# looked true and the game was misdiagnosed as CPU-bound.
			settings.display_mode = DisplayMode.WINDOWED
			settings.window_size = Vector2i(1280, 720)
			var win := get_window()
			win.mode = Window.MODE_WINDOWED
			win.size = Vector2i(1280, 720)
			win.move_to_center()
		elif arg.begins_with("--renderscale="):
			settings.resolution_scale = clampf(float(arg.get_slice("=", 1)), 0.25, MAX_RENDER_SCALE)
			get_viewport().scaling_3d_scale = settings.resolution_scale
		elif arg.begins_with("--preset="):
			settings.preset = clampi(int(arg.get_slice("=", 1)), 0, 3)
			apply_preset()
		elif arg.begins_with("--mission="):
			var mid := arg.get_slice("=", 1)
			if MissionDefs.MISSIONS.has(mid):
				start_mission.call_deferred(mid)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		save_settings()
		save_game()
		if what == NOTIFICATION_WM_CLOSE_REQUEST:
			prepare_shutdown()
		if what == NOTIFICATION_EXIT_TREE:
			FX.clear_caches()
			HullMaterial.clear_cache()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# during shutdown the autoload is already detached; get_tree() would
		# assert ("Parameter data.tree is null") on every quit
		if not is_inside_tree():
			return
		var tree := get_tree()
		if tree and not tree.paused and is_instance_valid(tree.current_scene) \
				and tree.current_scene.has_method("open_pause_menu"):
			tree.current_scene.call("open_pause_menu")

func prepare_shutdown() -> void:
	if is_instance_valid(AudioMgr):
		AudioMgr.shutdown()
	if is_inside_tree():
		for player in get_tree().get_nodes_in_group("player"):
			if is_instance_valid(player) and player.has_method("shutdown_audio"):
				player.shutdown_audio()
	FX.clear_caches()
	HullMaterial.clear_cache()

func _input(event: InputEvent) -> void:
	# the battle scene is PAUSABLE, so while paused ONLY this autoload can hear Esc
	if get_tree().paused and event.is_action_pressed("pause"):
		# a settings panel handles its own Esc — don't unpause underneath it
		if get_tree().get_first_node_in_group("settings_panel"):
			return
		var cs := get_tree().current_scene
		if is_instance_valid(cs) and cs.has_method("close_pause_menu"):
			cs.call("close_pause_menu")
			get_viewport().set_input_as_handled()

# =================================================================== INPUT MAP
func _make_event(b: Dictionary) -> InputEvent:
	match b.get("t", ""):
		"key":
			var ev := InputEventKey.new()
			ev.physical_keycode = int(b.c) as Key
			return ev
		"mouse":
			var ev := InputEventMouseButton.new()
			ev.button_index = int(b.b) as MouseButton
			return ev
		"jbtn":
			var ev := InputEventJoypadButton.new()
			ev.button_index = int(b.b) as JoyButton
			return ev
		"jaxis":
			var ev := InputEventJoypadMotion.new()
			ev.axis = int(b.a) as JoyAxis
			ev.axis_value = float(b.v)
			return ev
	return null

func _setup_input_map() -> void:
	for action in DEFAULT_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		InputMap.action_erase_events(action)
		var binds: Array = settings.bindings.get(action, DEFAULT_BINDINGS[action])
		for b in binds:
			var ev := _make_event(b)
			if ev:
				InputMap.action_add_event(action, ev)

func rebind_action(action: String, ev: InputEvent) -> void:
	if not DEFAULT_BINDINGS.has(action):
		return
	var b := {}
	if ev is InputEventKey:
		var code := (ev as InputEventKey).physical_keycode
		if code == KEY_NONE:
			code = (ev as InputEventKey).keycode
		b = {"t": "key", "c": code}
	elif ev is InputEventMouseButton:
		b = {"t": "mouse", "b": (ev as InputEventMouseButton).button_index}
	elif ev is InputEventJoypadButton:
		b = {"t": "jbtn", "b": (ev as InputEventJoypadButton).button_index}
	elif ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		b = {"t": "jaxis", "a": m.axis, "v": signf(m.axis_value)}
	else:
		return
	# keep gamepad bindings when rebinding kb/mouse and vice versa
	var kind_gamepad: bool = b.t in ["jbtn", "jaxis"]
	var current: Array = settings.bindings.get(action, DEFAULT_BINDINGS[action].duplicate(true))
	var kept: Array = []
	for old in current:
		var old_gp: bool = old.t in ["jbtn", "jaxis"]
		if old_gp != kind_gamepad:
			kept.append(old)
	kept.append(b)
	settings.bindings[action] = kept
	mark_settings_dirty()
	_setup_input_map()
	save_settings()

func reset_bindings() -> void:
	settings.bindings = {}
	mark_settings_dirty()
	_setup_input_map()
	save_settings()

func binding_text(action: String) -> String:
	var parts: PackedStringArray = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			parts.append(OS.get_keycode_string(code))
		elif ev is InputEventMouseButton:
			match (ev as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT: parts.append("Left Mouse")
				MOUSE_BUTTON_RIGHT: parts.append("Right Mouse")
				MOUSE_BUTTON_MIDDLE: parts.append("Middle Mouse")
				_: parts.append("Mouse %d" % (ev as InputEventMouseButton).button_index)
		elif ev is InputEventJoypadButton:
			parts.append("Pad %s" % _joy_button_name((ev as InputEventJoypadButton).button_index))
		elif ev is InputEventJoypadMotion:
			var jm := ev as InputEventJoypadMotion
			parts.append("Pad axis %d%s" % [jm.axis, "+" if jm.axis_value > 0.0 else "−"])
	return " / ".join(parts) if parts.size() > 0 else "—"

func _joy_button_name(button: JoyButton) -> String:
	var names := {
		JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
		JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
		JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
		JOY_BUTTON_START: "Start", JOY_BUTTON_BACK: "Back",
		JOY_BUTTON_DPAD_UP: "D-pad ↑", JOY_BUTTON_DPAD_DOWN: "D-pad ↓",
		JOY_BUTTON_DPAD_LEFT: "D-pad ←", JOY_BUTTON_DPAD_RIGHT: "D-pad →",
	}
	return names.get(button, str(int(button)))

# =================================================================== SETTINGS
func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	for k in settings.keys():
		settings[k] = cf.get_value("settings", k, settings[k])
	# v1.0 migration: fullscreen/vsync were booleans and window size was never
	# persisted. Read them only when the new keys are absent.
	if not cf.has_section_key("settings", "display_mode") \
			and cf.has_section_key("settings", "fullscreen"):
		settings.display_mode = DisplayMode.BORDERLESS \
			if bool(cf.get_value("settings", "fullscreen", true)) else DisplayMode.WINDOWED
	if not cf.has_section_key("settings", "vsync_mode") \
			and cf.has_section_key("settings", "vsync"):
		settings.vsync_mode = VSyncMode.ON \
			if bool(cf.get_value("settings", "vsync", true)) else VSyncMode.OFF

func save_settings() -> void:
	if _hermetic or not _settings_dirty:
		return
	var cf := ConfigFile.new()
	for k in settings.keys():
		cf.set_value("settings", k, settings[k])
	var err := cf.save(SETTINGS_PATH)
	if err == OK:
		_settings_dirty = false
	else:
		push_error("Could not save settings (%s)" % error_string(err))

func mark_settings_dirty() -> void:
	_settings_dirty = true

func _normalize_settings() -> void:
	var before := settings.duplicate(true)
	var d := SETTINGS_DEFAULTS
	settings.display_mode = clampi(_as_int(settings.get("display_mode"), d.display_mode),
		DisplayMode.WINDOWED, DisplayMode.EXCLUSIVE)
	settings.display_screen = clampi(_as_int(settings.get("display_screen"), d.display_screen),
		0, maxi(DisplayServer.get_screen_count() - 1, 0))
	settings.window_size = _as_vec2i(settings.get("window_size"), d.window_size)
	settings.window_size.x = clampi(settings.window_size.x, 960, 7680)
	settings.window_size.y = clampi(settings.window_size.y, 540, 4320)
	settings.resolution_scale = clampf(_as_float(settings.get("resolution_scale"),
		d.resolution_scale), MIN_RENDER_SCALE, MAX_RENDER_SCALE)
	settings.scaling_mode = clampi(_as_int(settings.get("scaling_mode"), d.scaling_mode), 0, 3)
	settings.vsync_mode = clampi(_as_int(settings.get("vsync_mode"), d.vsync_mode),
		VSyncMode.OFF, VSyncMode.ADAPTIVE)
	settings.fps_limit = clampi(_as_int(settings.get("fps_limit"), d.fps_limit), 0, 500)
	settings.preset = clampi(_as_int(settings.get("preset"), d.preset), 0, PRESETS.size() - 1)
	settings.mouse_sens = clampf(_as_float(settings.get("mouse_sens"), d.mouse_sens), 0.2, 3.0)
	settings.control_smoothing = clampf(_as_float(settings.get("control_smoothing"),
		d.control_smoothing), 0.0, 1.0)
	settings.invert_y = bool(settings.get("invert_y", d.invert_y))
	settings.aim_assist = bool(settings.get("aim_assist", d.aim_assist))
	settings.camera_shake = clampf(_as_float(settings.get("camera_shake"), d.camera_shake), 0.0, 1.5)
	settings.cam_distance = clampf(_as_float(settings.get("cam_distance"), d.cam_distance), 0.6, 2.0)
	for key in ["vol_master", "vol_music", "vol_sfx", "vol_ui"]:
		settings[key] = clampf(_as_float(settings.get(key), d[key]), 0.0, 1.0)
	settings.difficulty = clampi(_as_int(settings.get("difficulty"), d.difficulty), 0, 2)
	settings.momentum_mode = bool(settings.get("momentum_mode", d.momentum_mode))
	settings.bindings = _sanitize_bindings(settings.get("bindings", {}))
	if settings != before:
		_settings_dirty = true

func _sanitize_bindings(raw: Variant) -> Dictionary:
	var clean := {}
	if not raw is Dictionary:
		return clean
	for action in raw:
		if not DEFAULT_BINDINGS.has(action) or not raw[action] is Array:
			continue
		var events: Array = []
		for value in raw[action]:
			if not value is Dictionary:
				continue
			var b: Dictionary = value
			match str(b.get("t", "")):
				"key":
					var code := _as_int(b.get("c"), 0)
					if code > 0:
						events.append({"t": "key", "c": code})
				"mouse":
					var button := _as_int(b.get("b"), 0)
					if button > 0 and button <= 16:
						events.append({"t": "mouse", "b": button})
				"jbtn":
					var button := _as_int(b.get("b"), -1)
					if button >= 0 and button <= 31:
						events.append({"t": "jbtn", "b": button})
				"jaxis":
					var axis := _as_int(b.get("a"), -1)
					var direction := _as_float(b.get("v"), 0.0)
					if axis >= 0 and axis <= 15 and absf(direction) > 0.01:
						events.append({"t": "jaxis", "a": axis, "v": signf(direction)})
		if not events.is_empty():
			clean[action] = events
	return clean

func _as_int(value: Variant, fallback: int) -> int:
	return int(value) if value is int or value is float or value is bool else fallback

func _as_float(value: Variant, fallback: float) -> float:
	return float(value) if value is int or value is float else fallback

func _as_vec2i(value: Variant, fallback: Vector2i) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(value)
	return fallback

func reset_video_defaults() -> void:
	for key in ["display_mode", "display_screen", "window_size", "resolution_scale",
			"scaling_mode", "vsync_mode", "fps_limit", "preset", "camera_shake",
			"cam_distance"]:
		settings[key] = SETTINGS_DEFAULTS[key]
	mark_settings_dirty()
	apply_video_settings()
	apply_preset()

func display_mode_name() -> String:
	return ["Windowed", "Borderless fullscreen", "Exclusive fullscreen"][
		clampi(int(settings.display_mode), 0, 2)]

func render_resolution() -> Vector2i:
	var base := get_window().size
	return Vector2i(Vector2(base) * float(settings.resolution_scale))

func apply_video_settings() -> void:
	_normalize_settings()
	var win := get_window()
	var screen := clampi(int(settings.display_screen), 0, maxi(DisplayServer.get_screen_count() - 1, 0))
	if win.current_screen != screen:
		win.current_screen = screen
	match int(settings.display_mode):
		DisplayMode.WINDOWED:
			if win.mode != Window.MODE_WINDOWED:
				win.mode = Window.MODE_WINDOWED
			if win.size != settings.window_size:
				win.size = settings.window_size
				win.move_to_center()
		DisplayMode.EXCLUSIVE:
			if win.mode != Window.MODE_EXCLUSIVE_FULLSCREEN:
				win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		_:
			if win.mode != Window.MODE_FULLSCREEN:
				win.mode = Window.MODE_FULLSCREEN
	var vsync_modes := [
		DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ENABLED, DisplayServer.VSYNC_ADAPTIVE]
	DisplayServer.window_set_vsync_mode(vsync_modes[int(settings.vsync_mode)])
	Engine.max_fps = int(settings.fps_limit)
	var vp := get_viewport()
	vp.scaling_3d_scale = clampf(settings.resolution_scale, MIN_RENDER_SCALE, MAX_RENDER_SCALE)
	var scaling_modes := [
		Viewport.SCALING_3D_MODE_BILINEAR,
		Viewport.SCALING_3D_MODE_FSR,
		Viewport.SCALING_3D_MODE_FSR2,
		Viewport.SCALING_3D_MODE_METALFX_TEMPORAL,
	]
	# Temporal upscalers are for sub-native rendering. Supersampling is a direct
	# high-resolution request and must not be handed to an upscaler.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR \
		if settings.resolution_scale > 1.0 else scaling_modes[int(settings.scaling_mode)]

func apply_preset() -> void:
	_normalize_settings()
	var p: Dictionary = PRESETS[clampi(settings.preset, 0, 3)]
	var vp := get_viewport()
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][int(p.msaa)] as Viewport.MSAA
	vp.screen_space_aa = [
		Viewport.SCREEN_SPACE_AA_DISABLED,
		Viewport.SCREEN_SPACE_AA_FXAA,
		Viewport.SCREEN_SPACE_AA_SMAA,
	][int(p.screen_aa)] as Viewport.ScreenSpaceAA
	vp.use_taa = bool(p.taa)
	vp.anisotropic_filtering_level = [
		Viewport.ANISOTROPY_4X, Viewport.ANISOTROPY_8X,
		Viewport.ANISOTROPY_16X, Viewport.ANISOTROPY_16X,
	][clampi(int(settings.preset), 0, 3)] as Viewport.AnisotropicFiltering
	RenderingServer.directional_shadow_atlas_set_size(int(p.shadow_size), true)
	settings_changed.emit()

func preset() -> Dictionary:
	return PRESETS[clampi(settings.preset, 0, 3)]

func apply_audio_settings() -> void:
	AudioMgr.apply_volumes()

# =================================================================== SAVE DATA
func _load_save() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	for k in save.keys():
		save[k] = cf.get_value("save", k, save[k])

func save_game() -> void:
	if not _save_dirty:
		return
	var cf := ConfigFile.new()
	for k in save.keys():
		cf.set_value("save", k, save[k])
	var err := cf.save(SAVE_PATH)
	if err == OK:
		_save_dirty = false
	else:
		push_error("Could not save game (%s)" % error_string(err))

func mark_save_dirty() -> void:
	_save_dirty = true

func _normalize_save() -> void:
	var before := save.duplicate(true)
	if not save.get("selected_ship", "") in ShipDB.SHIPS:
		save.selected_ship = "vanguard"
	if not save.get("unlocked_ships", []) is Array:
		save.unlocked_ships = ["vanguard", "wasp"]
	save.unlocked_ships = save.unlocked_ships.filter(func(id): return id in ShipDB.SHIPS)
	if not "vanguard" in save.unlocked_ships:
		save.unlocked_ships.append("vanguard")
	if not save.get("missions_done", {}) is Dictionary:
		save.missions_done = {}
	else:
		for id in save.missions_done.keys():
			if not MissionDefs.MISSIONS.has(id) or not save.missions_done[id] is Dictionary:
				save.missions_done.erase(id)
	if not save.get("loadouts", {}) is Dictionary:
		save.loadouts = {}
	else:
		for id in save.loadouts.keys():
			if not ShipDB.SHIPS.has(id) or not save.loadouts[id] is Dictionary:
				save.loadouts.erase(id)
	save.credits = maxi(_as_int(save.get("credits"), 0), 0)
	save.training_done = bool(save.get("training_done", false))
	if save != before:
		_save_dirty = true

func loadout_for(ship_id: String) -> Dictionary:
	if not ShipDB.SHIPS.has(ship_id):
		ship_id = "vanguard"
	var lo: Dictionary = save.loadouts.get(ship_id, {})
	var def: Dictionary = ShipDB.SHIPS[ship_id]
	var primary: String = lo.get("primary", def.default_primary)
	var primary2: String = lo.get("primary2", def.default_primary2)
	var missile: String = lo.get("missile", def.default_missile)
	return {
		"primary": primary if ShipDB.WEAPONS.has(primary) else def.default_primary,
		"primary2": primary2 if ShipDB.WEAPONS.has(primary2) else def.default_primary2,
		"missile": missile if ShipDB.MISSILES.has(missile) else def.default_missile,
		"paint": lo.get("paint", def.paint) if lo.get("paint", def.paint) is Color else def.paint,
		"glow": lo.get("glow", def.glow) if lo.get("glow", def.glow) is Color else def.glow,
	}

func set_loadout(ship_id: String, lo: Dictionary) -> void:
	if not ShipDB.SHIPS.has(ship_id):
		return
	save.loadouts[ship_id] = lo
	mark_save_dirty()
	save_game()

func record_mission(id: String, stats: Dictionary) -> void:
	if not MissionDefs.MISSIONS.has(id):
		return
	var prev: Dictionary = save.missions_done.get(id, {})
	if prev.is_empty() or int(stats.get("score", 0)) > int(prev.get("score", 0)):
		save.missions_done[id] = stats
	# unlock progression
	if id == "main" and stats.get("victory", false):
		for s in ["raptor", "hammer"]:
			if not s in save.unlocked_ships:
				save.unlocked_ships.append(s)
	if id == "instant_action" and stats.get("victory", false):
		if not "raptor" in save.unlocked_ships:
			save.unlocked_ships.append("raptor")
	if stats.get("victory", false) and not "hammer" in save.unlocked_ships \
			and save.missions_done.size() >= 3:
		save.unlocked_ships.append("hammer")
	save.credits = int(save.credits) + int(stats.get("score", 0) / 10.0)
	mark_save_dirty()
	save_game()

# =================================================================== FLOW
func goto_menu(tab := "") -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var err := get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	if err != OK:
		push_error("Could not open main menu: %s" % error_string(err))

func start_mission(id: String) -> void:
	if not MissionDefs.MISSIONS.has(id):
		push_warning("Unknown mission '%s'; using instant_action" % id)
		id = "instant_action"
	current_mission = id
	get_tree().paused = false
	var err := get_tree().change_scene_to_file("res://scenes/Battle.tscn")
	if err != OK:
		push_error("Could not open battle scene: %s" % error_string(err))

func difficulty_scale() -> Dictionary:
	match int(settings.difficulty):
		0: return {"accuracy": 0.5, "reaction": 1.6, "aggression": 0.6, "count": 0.7, "cm": 0.4}
		2: return {"accuracy": 1.25, "reaction": 0.65, "aggression": 1.3, "count": 1.3, "cm": 0.9}
		_: return {"accuracy": 1.0, "reaction": 1.0, "aggression": 1.0, "count": 1.0, "cm": 0.65}
