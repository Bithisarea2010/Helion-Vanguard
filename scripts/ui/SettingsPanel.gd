class_name SettingsPanel
extends Control
## Full settings UI: video (fullscreen/window/scale), audio, gameplay, control remap.

signal closed

var _rebind_action := ""
var _rebind_button: Button = null
var _controls_box: VBoxContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("settings_panel")   # Game.gd skips its Esc-unpause while we exist
	var dim := ColorRect.new()
	dim.color = Color(0, 0.01, 0.03, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Styles.panel(Styles.BG_SOLID))
	panel.custom_minimum_size = Vector2(760, 620)
	cc.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var title := Styles.label("SETTINGS", 28, Styles.CYAN, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_override("font", Styles.title_font())
	tabs.add_theme_font_size_override("font_size", 15)
	vb.add_child(tabs)
	tabs.add_child(_video_tab())
	tabs.add_child(_audio_tab())
	tabs.add_child(_game_tab())
	tabs.add_child(_controls_tab())
	var close := Styles.button("SAVE & CLOSE", 18)
	close.pressed.connect(func():
		Game.save_settings()
		closed.emit())
	vb.add_child(close)

func _row(parent: Node, label_text: String, control: Control) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	var l := Styles.label(label_text, 16)
	l.custom_minimum_size.x = 260
	hb.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(control)
	parent.add_child(hb)

func _scroll_tab(nm: String) -> Array:
	var sc := ScrollContainer.new()
	sc.name = nm
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	return [sc, vb]

# ------------------------------------------------------------------ video
func _video_tab() -> Control:
	var pair := _scroll_tab("VIDEO")
	var vb: VBoxContainer = pair[1]
	# display mode — explicit, reliable macOS handling
	var mode := OptionButton.new()
	mode.add_item("Fullscreen", 0)
	mode.add_item("Windowed", 1)
	mode.selected = 0 if Game.settings.fullscreen else 1
	mode.item_selected.connect(func(i):
		Game.settings.fullscreen = (i == 0)
		Game.apply_video_settings())
	_row(vb, "Display mode", mode)
	var res := OptionButton.new()
	for r in ["1280 × 720", "1600 × 900", "1920 × 1080", "2560 × 1440"]:
		res.add_item(r)
	res.selected = 1
	res.item_selected.connect(func(i):
		if not Game.settings.fullscreen:
			var sizes := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
			var win := get_window()
			win.size = sizes[i]
			win.move_to_center())
	_row(vb, "Window size (windowed)", res)
	var scale := Styles.hslider(0.5, 1.0, Game.settings.resolution_scale, 0.05)
	scale.value_changed.connect(func(v):
		Game.settings.resolution_scale = v
		Game.apply_video_settings())
	_row(vb, "Render scale", scale)
	var vsync := CheckButton.new()
	vsync.button_pressed = Game.settings.vsync
	vsync.toggled.connect(func(on):
		Game.settings.vsync = on
		Game.apply_video_settings())
	_row(vb, "V-Sync", vsync)
	var fps := OptionButton.new()
	for f in ["Uncapped", "60 fps", "120 fps"]:
		fps.add_item(f)
	fps.selected = {0: 0, 60: 1, 120: 2}.get(int(Game.settings.fps_limit), 0)
	fps.item_selected.connect(func(i):
		Game.settings.fps_limit = [0, 60, 120][i]
		Game.apply_video_settings())
	_row(vb, "Frame-rate limit", fps)
	var preset := OptionButton.new()
	for p in Game.PRESET_NAMES:
		preset.add_item(p)
	preset.selected = int(Game.settings.preset)
	preset.item_selected.connect(func(i):
		Game.settings.preset = i
		Game.apply_preset())
	_row(vb, "Quality preset", preset)
	var shake := Styles.hslider(0.0, 1.5, Game.settings.camera_shake, 0.1)
	shake.value_changed.connect(func(v): Game.settings.camera_shake = v)
	_row(vb, "Camera shake", shake)
	return pair[0]

# ------------------------------------------------------------------ audio
func _audio_tab() -> Control:
	var pair := _scroll_tab("AUDIO")
	var vb: VBoxContainer = pair[1]
	for cfg in [["Master volume", "vol_master"], ["Music", "vol_music"],
			["Effects", "vol_sfx"], ["Interface", "vol_ui"]]:
		var s := Styles.hslider(0.0, 1.0, Game.settings[cfg[1]], 0.02)
		var key: String = cfg[1]
		s.value_changed.connect(func(v):
			Game.settings[key] = v
			AudioMgr.apply_volumes())
		_row(vb, cfg[0], s)
	return pair[0]

# ------------------------------------------------------------------ gameplay
func _game_tab() -> Control:
	var pair := _scroll_tab("GAMEPLAY")
	var vb: VBoxContainer = pair[1]
	var sens := Styles.hslider(0.2, 3.0, Game.settings.mouse_sens, 0.05)
	sens.value_changed.connect(func(v): Game.settings.mouse_sens = v)
	_row(vb, "Mouse / trackpad sensitivity", sens)
	var inv := CheckButton.new()
	inv.button_pressed = Game.settings.invert_y
	inv.toggled.connect(func(on): Game.settings.invert_y = on)
	_row(vb, "Invert Y axis", inv)
	var assist := CheckButton.new()
	assist.button_pressed = Game.settings.aim_assist
	assist.toggled.connect(func(on): Game.settings.aim_assist = on)
	_row(vb, "Aim assist", assist)
	var diff := OptionButton.new()
	for d in ["Easy", "Normal", "Hard"]:
		diff.add_item(d)
	diff.selected = int(Game.settings.difficulty)
	diff.item_selected.connect(func(i): Game.settings.difficulty = i)
	_row(vb, "Difficulty", diff)
	return pair[0]

# ------------------------------------------------------------------ controls
func _controls_tab() -> Control:
	var pair := _scroll_tab("CONTROLS")
	_controls_box = pair[1]
	_rebuild_controls()
	return pair[0]

func _rebuild_controls() -> void:
	for c in _controls_box.get_children():
		c.queue_free()
	var hint := Styles.label("Click a binding, then press the new key / mouse button. Esc cancels.", 13, Styles.DIM)
	_controls_box.add_child(hint)
	for action in Game.ACTION_LABELS:
		var hb := HBoxContainer.new()
		var l := Styles.label(Game.ACTION_LABELS[action], 15)
		l.custom_minimum_size.x = 280
		hb.add_child(l)
		var b := Styles.button(Game.binding_text(action), 13)
		b.custom_minimum_size.x = 220
		var act: String = action
		b.pressed.connect(func(): _start_rebind(act, b))
		hb.add_child(b)
		_controls_box.add_child(hb)
	var reset := Styles.button("RESET TO DEFAULTS", 14, Styles.ORANGE)
	reset.pressed.connect(func():
		Game.reset_bindings()
		_rebuild_controls())
	_controls_box.add_child(reset)

func _start_rebind(action: String, b: Button) -> void:
	if _rebind_button:
		_rebind_button.text = Game.binding_text(_rebind_action)
	_rebind_action = action
	_rebind_button = b
	b.text = "PRESS A KEY…"

func _input(event: InputEvent) -> void:
	# Esc closes the panel (when not waiting for a rebind key)
	if _rebind_action == "" and event.is_action_pressed("pause"):
		Game.save_settings()
		closed.emit()
		get_viewport().set_input_as_handled()
		return
	if _rebind_action == "":
		return
	var done := false
	if event is InputEventKey and event.pressed:
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			done = true # cancel
		else:
			Game.rebind_action(_rebind_action, event)
			done = true
	elif event is InputEventMouseButton and event.pressed:
		Game.rebind_action(_rebind_action, event)
		done = true
	elif event is InputEventJoypadButton and event.pressed:
		Game.rebind_action(_rebind_action, event)
		done = true
	if done:
		get_viewport().set_input_as_handled()
		_rebind_action = ""
		_rebind_button = null
		_rebuild_controls()
