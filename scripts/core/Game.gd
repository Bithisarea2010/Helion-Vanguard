extends Node
## Helion Vanguard — global game state, settings, input map, save system.

signal settings_changed
signal mission_ended(victory: bool, stats: Dictionary)

const VERSION := "1.0.0"
const SETTINGS_PATH := "user://settings.cfg"
const SAVE_PATH := "user://save.cfg"

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
var settings := {
	"fullscreen": true,
	"resolution_scale": 0.85,       # render scale 0.5 .. 1.0 (0.85 ≈ native feel on Retina)
	"vsync": true,
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

const PRESET_NAMES := ["Low", "Medium", "High", "Ultra"]
# preset: msaa, glow, shadows, asteroid_density, particles, debris_life, res_scale_hint
const PRESETS := [
	{"msaa": 0, "glow": false, "shadows": false, "ast_density": 0.45, "particles": 0.5, "debris": 3.0},
	{"msaa": 0, "glow": true, "shadows": false, "ast_density": 0.7, "particles": 0.75, "debris": 5.0},
	{"msaa": 1, "glow": true, "shadows": true, "ast_density": 1.0, "particles": 1.0, "debris": 8.0},
	{"msaa": 2, "glow": true, "shadows": true, "ast_density": 1.35, "particles": 1.3, "debris": 12.0},
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
			settings.fullscreen = false
			var win := get_window()
			win.mode = Window.MODE_WINDOWED
			win.size = Vector2i(1280, 720)
			win.move_to_center()
		elif arg.begins_with("--renderscale="):
			settings.resolution_scale = clampf(float(arg.get_slice("=", 1)), 0.25, 1.0)
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
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# during shutdown the autoload is already detached; get_tree() would
		# assert ("Parameter data.tree is null") on every quit
		if not is_inside_tree():
			return
		var tree := get_tree()
		if tree and not tree.paused and is_instance_valid(tree.current_scene) \
				and tree.current_scene.has_method("open_pause_menu"):
			tree.current_scene.call("open_pause_menu")

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
	_setup_input_map()
	save_settings()

func reset_bindings() -> void:
	settings.bindings = {}
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
	return " / ".join(parts) if parts.size() > 0 else "—"

# =================================================================== SETTINGS
func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	for k in settings.keys():
		settings[k] = cf.get_value("settings", k, settings[k])

func save_settings() -> void:
	if _hermetic:
		return
	var cf := ConfigFile.new()
	for k in settings.keys():
		cf.set_value("settings", k, settings[k])
	cf.save(SETTINGS_PATH)

func apply_video_settings() -> void:
	var win := get_window()
	if settings.fullscreen:
		win.mode = Window.MODE_FULLSCREEN
	else:
		if win.mode == Window.MODE_FULLSCREEN:
			win.mode = Window.MODE_WINDOWED
			win.size = Vector2i(1600, 900)
			win.move_to_center()
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(settings.fps_limit)
	get_viewport().scaling_3d_scale = clampf(settings.resolution_scale, 0.5, 1.0)
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR

func apply_preset() -> void:
	var p: Dictionary = PRESETS[clampi(settings.preset, 0, 3)]
	var vp := get_viewport()
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][int(p.msaa)] as Viewport.MSAA
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
	var cf := ConfigFile.new()
	for k in save.keys():
		cf.set_value("save", k, save[k])
	cf.save(SAVE_PATH)

func loadout_for(ship_id: String) -> Dictionary:
	var lo: Dictionary = save.loadouts.get(ship_id, {})
	var def: Dictionary = ShipDB.SHIPS[ship_id]
	return {
		"primary": lo.get("primary", def.default_primary),
		"primary2": lo.get("primary2", def.default_primary2),
		"missile": lo.get("missile", def.default_missile),
		"paint": lo.get("paint", def.paint),
		"glow": lo.get("glow", def.glow),
	}

func set_loadout(ship_id: String, lo: Dictionary) -> void:
	save.loadouts[ship_id] = lo
	save_game()

func record_mission(id: String, stats: Dictionary) -> void:
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
	save_game()

# =================================================================== FLOW
func goto_menu(tab := "") -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var err := get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	assert(err == OK)

func start_mission(id: String) -> void:
	current_mission = id
	get_tree().paused = false
	var err := get_tree().change_scene_to_file("res://scenes/Battle.tscn")
	assert(err == OK)

func difficulty_scale() -> Dictionary:
	match int(settings.difficulty):
		0: return {"accuracy": 0.5, "reaction": 1.6, "aggression": 0.6, "count": 0.7, "cm": 0.4}
		2: return {"accuracy": 1.25, "reaction": 0.65, "aggression": 1.3, "count": 1.3, "cm": 0.9}
		_: return {"accuracy": 1.0, "reaction": 1.0, "aggression": 1.0, "count": 1.0, "cm": 0.65}
