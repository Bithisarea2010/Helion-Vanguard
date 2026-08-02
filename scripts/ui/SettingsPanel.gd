class_name SettingsPanel
extends Control
## Responsive settings UI with persistent display resolution, real quality
## presets, live render-resolution feedback, audio/gameplay controls and full
## keyboard/mouse/gamepad rebinding.

signal closed

const WINDOW_SIZES := [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(2880, 1800), Vector2i(3840, 2160),
	Vector2i(4096, 2160), Vector2i(5120, 2880), Vector2i(6016, 3384),
	Vector2i(7680, 4320),
]
const FPS_LIMITS := [0, 30, 60, 90, 120, 144, 165, 240]
const SCALE_VALUES := [0.50, 0.67, 0.75, 0.85, 1.00, 1.25, 1.50, 2.00]
const QUALITY_SUMMARIES := [
	"Fastest • FXAA • no bloom or dynamic shadows • 45% asteroid density",
	"Efficient • SMAA • bloom • 70% asteroid density • no dynamic shadows",
	"Recommended • 2× MSAA • 2K shadows • full effects and asteroid density",
	"Maximum • 4× MSAA + TAA • 4K/560 m shadows • 135% rocks • 130% effects",
]

var _rebind_action := ""
var _rebind_button: Button = null
var _controls_box: VBoxContainer
var _render_readout: Label
var _quality_readout: Label
var _size_select: OptionButton
var _screen_select: OptionButton

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("settings_panel")

	var dim := ColorRect.new()
	dim.color = Color(0.005, 0.012, 0.025, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var cc := CenterContainer.new()
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(cc)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Styles.panel(
		Color(0.025, 0.045, 0.080, 0.99), 10, Color(Styles.CYAN.r, Styles.CYAN.g, Styles.CYAN.b, 0.42)))
	var available := get_viewport_rect().size - Vector2(56, 48)
	panel.custom_minimum_size = Vector2(minf(980.0, available.x), minf(760.0, available.y))
	cc.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	vb.add_child(_header())

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_override("font", Styles.title_font())
	tabs.add_theme_font_size_override("font_size", 14)
	tabs.add_theme_color_override("font_selected_color", Styles.CYAN)
	tabs.add_theme_color_override("font_unselected_color", Styles.DIM)
	tabs.add_child(_video_tab())
	tabs.add_child(_audio_tab())
	tabs.add_child(_game_tab())
	tabs.add_child(_capabilities_tab())
	tabs.add_child(_controls_tab())
	vb.add_child(tabs)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	var defaults := Styles.button("RESTORE RECOMMENDED VIDEO", 13, Styles.ORANGE)
	defaults.pressed.connect(func():
		Game.reset_video_defaults()
		_rebuild_panel())
	footer.add_child(defaults)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var close := Styles.button("APPLY & CLOSE", 16, Styles.GREEN)
	close.custom_minimum_size.x = 220
	close.pressed.connect(_close)
	footer.add_child(close)
	vb.add_child(footer)

func _header() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var accent := ColorRect.new()
	accent.color = Styles.ORANGE
	accent.custom_minimum_size = Vector2(5, 54)
	hb.add_child(accent)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", -2)
	text.add_child(Styles.label("SYSTEM CONFIGURATION", 25, Color.WHITE, true))
	text.add_child(Styles.label(
		"Display, rendering, audio, flight assists and controls", 13, Styles.DIM))
	hb.add_child(text)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)
	var version := Styles.label("BUILD %s" % Game.VERSION, 12, Styles.CYAN, true)
	version.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(version)
	return hb

func _rebuild_panel() -> void:
	# The panel is compact enough that rebuilding is safer than trying to keep a
	# web of controls synchronized after a whole-profile reset.
	var parent := get_parent()
	if parent == null:
		return
	var fresh := SettingsPanel.new()
	parent.add_child(fresh)
	fresh.closed.connect(func(): fresh.queue_free())
	queue_free()

func _close() -> void:
	Game.save_settings()
	closed.emit()

func _section(parent: Node, title: String, text: String = "") -> void:
	var l := Styles.label(title, 15, Styles.CYAN, true)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	parent.add_child(l)
	if text != "":
		var d := Styles.label(text, 12, Styles.DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(d)

func _row(parent: Node, title: String, description: String, control: Control) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Styles.panel(
		Color(0.045, 0.075, 0.115, 0.72), 5, Color(0.25, 0.5, 0.7, 0.16)))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	card.add_child(hb)
	var copy := VBoxContainer.new()
	copy.custom_minimum_size.x = 360
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", -1)
	copy.add_child(Styles.label(title, 15, Color(0.90, 0.95, 1.0)))
	var d := Styles.label(description, 11, Styles.DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(d)
	hb.add_child(copy)
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, 280.0)
	control.size_flags_horizontal = Control.SIZE_SHRINK_END
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_input(control)
	hb.add_child(control)
	parent.add_child(card)

func _style_input(control: Control) -> void:
	control.add_theme_font_override("font", Styles.body_font())
	control.add_theme_font_size_override("font_size", 14)
	if control is OptionButton or control is CheckButton:
		var normal := Styles.panel(Color(0.035, 0.065, 0.105, 1.0), 4,
			Color(Styles.CYAN.r, Styles.CYAN.g, Styles.CYAN.b, 0.32))
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color(0.06, 0.11, 0.17, 1.0)
		hover.border_color = Styles.CYAN
		control.add_theme_stylebox_override("normal", normal)
		control.add_theme_stylebox_override("hover", hover)
		control.add_theme_stylebox_override("focus", hover)

func _scroll_tab(name_text: String) -> Array:
	var sc := ScrollContainer.new()
	sc.name = name_text
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	return [sc, vb]

func _mark() -> void:
	Game.mark_settings_dirty()

func _scale_text(v: float) -> String:
	return "%d%%" % int(round(v * 100.0))

func _refresh_render_readout() -> void:
	if _render_readout == null:
		return
	var output := get_window().size
	var internal := Game.render_resolution()
	var super_text := " • supersampled" if float(Game.settings.resolution_scale) > 1.0 else ""
	_render_readout.text = "%s • output %d × %d • 3D %d × %d%s" % [
		Game.display_mode_name(), output.x, output.y, internal.x, internal.y, super_text]

func _available_window_sizes() -> Array[Vector2i]:
	var found := {}
	for size in WINDOW_SIZES:
		found[size] = true
	for i in DisplayServer.get_screen_count():
		var native := DisplayServer.screen_get_size(i)
		if native.x >= 960 and native.y >= 540:
			found[native] = true
	found[Game.settings.window_size] = true
	var sizes: Array[Vector2i] = []
	for size in found:
		sizes.append(size)
	sizes.sort_custom(func(a: Vector2i, b: Vector2i):
		var ap := a.x * a.y
		var bp := b.x * b.y
		return ap < bp or (ap == bp and a.x < b.x))
	return sizes

# ------------------------------------------------------------------ video
func _video_tab() -> Control:
	var pair := _scroll_tab("VIDEO")
	var vb: VBoxContainer = pair[1]
	_section(vb, "DISPLAY", "Output mode and window dimensions. Borderless uses the monitor's native resolution.")

	var mode := OptionButton.new()
	for label in ["Windowed", "Borderless fullscreen (native)", "Exclusive fullscreen"]:
		mode.add_item(label)
	mode.selected = int(Game.settings.display_mode)
	mode.item_selected.connect(func(i):
		Game.settings.display_mode = i
		_mark()
		Game.apply_video_settings()
		_refresh_render_readout())
	_row(vb, "Display mode", "Borderless is the reliable native-resolution mode on macOS.", mode)

	if DisplayServer.get_screen_count() > 1:
		_screen_select = OptionButton.new()
		for i in DisplayServer.get_screen_count():
			var size := DisplayServer.screen_get_size(i)
			_screen_select.add_item("Display %d  —  %d × %d" % [i + 1, size.x, size.y])
		_screen_select.selected = clampi(int(Game.settings.display_screen), 0,
			DisplayServer.get_screen_count() - 1)
		_screen_select.item_selected.connect(func(i):
			Game.settings.display_screen = i
			_mark()
			Game.apply_video_settings()
			_refresh_render_readout())
		_row(vb, "Active display", "Moves the window or fullscreen output to another monitor.", _screen_select)

	_size_select = OptionButton.new()
	var selected_size := 0
	var window_sizes := _available_window_sizes()
	for i in window_sizes.size():
		var size: Vector2i = window_sizes[i]
		_size_select.add_item("%d × %d" % [size.x, size.y])
		if size == Game.settings.window_size:
			selected_size = i
	_size_select.selected = selected_size
	_size_select.item_selected.connect(func(i):
		Game.settings.window_size = window_sizes[i]
		_mark()
		if int(Game.settings.display_mode) == Game.DisplayMode.WINDOWED:
			Game.apply_video_settings()
		_refresh_render_readout())
	_row(vb, "Window resolution", "Persists correctly; applies immediately in Windowed mode.", _size_select)

	_section(vb, "RENDER RESOLUTION", "The UI stays native. Values above 100% render 3D above output resolution and downsample it.")
	var scale_box := VBoxContainer.new()
	var scale := Styles.hslider(Game.MIN_RENDER_SCALE, Game.MAX_RENDER_SCALE,
		Game.settings.resolution_scale, 0.01)
	var scale_value := Styles.label(_scale_text(Game.settings.resolution_scale), 14, Styles.ORANGE, true)
	scale_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scale_box.add_child(scale_value)
	scale_box.add_child(scale)
	scale.value_changed.connect(func(v):
		Game.settings.resolution_scale = snappedf(v, 0.01)
		scale_value.text = _scale_text(v)
		_mark()
		Game.apply_video_settings()
		_refresh_render_readout())
	_row(vb, "3D render scale", "50–100% upscales for speed; 125–200% enables true high-resolution supersampling.", scale_box)

	var scaling := OptionButton.new()
	for label in ["Bilinear", "FSR 1 — sharp spatial", "FSR 2 — temporal", "MetalFX Temporal — macOS"]:
		scaling.add_item(label)
	scaling.selected = int(Game.settings.scaling_mode)
	scaling.item_selected.connect(func(i):
		Game.settings.scaling_mode = i
		_mark()
		Game.apply_video_settings())
	_row(vb, "Scaling filter", "Temporal modes improve sub-native clarity; supersampling always uses direct bilinear downsampling.", scaling)

	_render_readout = Styles.label("", 12, Styles.CYAN, true)
	_render_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_render_readout)
	_refresh_render_readout.call_deferred()

	_section(vb, "FRAME PACING")
	var vsync := OptionButton.new()
	for label in ["Off", "On", "Adaptive"]:
		vsync.add_item(label)
	vsync.selected = int(Game.settings.vsync_mode)
	vsync.item_selected.connect(func(i):
		Game.settings.vsync_mode = i
		_mark()
		Game.apply_video_settings())
	_row(vb, "V-Sync", "Adaptive sync prevents tearing but releases the cap when the frame misses refresh.", vsync)

	var fps := OptionButton.new()
	for limit in FPS_LIMITS:
		fps.add_item("Uncapped" if limit == 0 else "%d fps" % limit)
	var fps_idx := FPS_LIMITS.find(int(Game.settings.fps_limit))
	fps.selected = maxi(fps_idx, 0)
	fps.item_selected.connect(func(i):
		Game.settings.fps_limit = FPS_LIMITS[i]
		_mark()
		Game.apply_video_settings())
	_row(vb, "Frame-rate limit", "A cap below the display refresh reduces power, fan noise and GPU load.", fps)

	_section(vb, "QUALITY")
	var preset := OptionButton.new()
	for name in Game.PRESET_NAMES:
		preset.add_item(name)
	preset.selected = int(Game.settings.preset)
	preset.item_selected.connect(func(i):
		Game.settings.preset = i
		_mark()
		Game.apply_preset()
		_quality_readout.text = QUALITY_SUMMARIES[i])
	_row(vb, "Quality preset", "Ultra now changes AA, shadow resolution/range, geometry density and effect density.", preset)
	_quality_readout = Styles.label(QUALITY_SUMMARIES[int(Game.settings.preset)], 12, Styles.ORANGE, true)
	_quality_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_quality_readout)
	var reload_note := Styles.label(
		"Asteroid and planet density refresh when a mission or the menu is loaded; AA, bloom and shadows apply now.",
		11, Styles.DIM)
	reload_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(reload_note)

	var shake := _labeled_slider(0.0, 1.5, Game.settings.camera_shake, 0.05, "×")
	var shake_slider := shake.get_meta("slider") as HSlider
	shake_slider.value_changed.connect(func(v):
		Game.settings.camera_shake = v
		_update_labeled_slider(shake, v, "×")
		_mark())
	_row(vb, "Camera shake", "Impact feedback strength; zero disables shake without disabling hit effects.", shake)

	var camd := _labeled_slider(0.6, 2.0, Game.settings.cam_distance, 0.05, "×")
	var camd_slider := camd.get_meta("slider") as HSlider
	camd_slider.value_changed.connect(func(v):
		Game.settings.cam_distance = v
		_update_labeled_slider(camd, v, "×")
		_mark()
		var live_player := get_tree().get_first_node_in_group("player")
		if live_player and "cam_rig" in live_player and is_instance_valid(live_player.cam_rig):
			live_player.cam_rig.refresh_camera_settings())
	_row(vb, "Chase camera distance", "Standoff multiplier; the whole hull remains framed for every ship.", camd)
	return pair[0]

# ------------------------------------------------------------------ audio
func _audio_tab() -> Control:
	var pair := _scroll_tab("AUDIO")
	var vb: VBoxContainer = pair[1]
	_section(vb, "MIXER", "Changes are heard immediately and stored when the panel closes.")
	for cfg in [["Master volume", "vol_master", "Final output level"],
			["Music", "vol_music", "Combat and menu score"],
			["Effects", "vol_sfx", "Weapons, engines, impacts and explosions"],
			["Interface", "vol_ui", "Warnings, radio and menu feedback"]]:
		var key: String = cfg[1]
		var box := _labeled_slider(0.0, 1.0, Game.settings[key], 0.01, "%", 100.0)
		var slider := box.get_meta("slider") as HSlider
		slider.value_changed.connect(func(v):
			Game.settings[key] = v
			_update_labeled_slider(box, v, "%", 100.0)
			_mark()
			AudioMgr.apply_volumes())
		_row(vb, cfg[0], cfg[2], box)
	return pair[0]

# ------------------------------------------------------------------ gameplay
func _game_tab() -> Control:
	var pair := _scroll_tab("GAMEPLAY")
	var vb: VBoxContainer = pair[1]
	_section(vb, "FLIGHT FEEL")
	var sens := _labeled_slider(0.2, 3.0, Game.settings.mouse_sens, 0.05, "×")
	var sens_slider := sens.get_meta("slider") as HSlider
	sens_slider.value_changed.connect(func(v):
		Game.settings.mouse_sens = v
		_update_labeled_slider(sens, v, "×")
		_mark())
	_row(vb, "Mouse / trackpad sensitivity", "Scales the virtual flight cursor without changing the expo curve.", sens)

	var csm := _labeled_slider(0.0, 1.0, Game.settings.control_smoothing, 0.05, "%", 100.0)
	var csm_slider := csm.get_meta("slider") as HSlider
	csm_slider.value_changed.connect(func(v):
		Game.settings.control_smoothing = v
		_update_labeled_slider(csm, v, "%", 100.0)
		_mark())
	_row(vb, "Control smoothing", "Zero is immediate; higher values soften cursor, rotation and thruster steps.", csm)

	var inv := CheckButton.new()
	inv.text = "Enabled"
	inv.button_pressed = Game.settings.invert_y
	inv.toggled.connect(func(on):
		Game.settings.invert_y = on
		_mark())
	_row(vb, "Invert Y axis", "Reverses pitch input for mouse and gamepad.", inv)

	var assist := CheckButton.new()
	assist.text = "Enabled"
	assist.button_pressed = Game.settings.aim_assist
	assist.toggled.connect(func(on):
		Game.settings.aim_assist = on
		_mark())
	_row(vb, "Aim assist", "Gently converges on a valid lead point inside 3.5°.", assist)

	var diff := OptionButton.new()
	for d in ["Easy", "Normal", "Hard"]:
		diff.add_item(d)
	diff.selected = int(Game.settings.difficulty)
	diff.item_selected.connect(func(i):
		Game.settings.difficulty = i
		_mark())
	_row(vb, "Difficulty", "Adjusts enemy accuracy, reaction, aggression, group size and countermeasures.", diff)
	return pair[0]

# ------------------------------------------------------------- capabilities
## The master switch is deliberately its own control at the top of the tab: with
## it off the ship is exactly the 1.1 fighter, which is the only way to judge
## what the new systems actually change.
func _capabilities_tab() -> Control:
	var pair := _scroll_tab("CAPABILITIES")
	var vb: VBoxContainer = pair[1]
	_section(vb, "ADVANCED CAPABILITIES",
		"Next-generation prototype systems. Turn the master switch off to fly the ship exactly as it shipped in 1.1. Changes apply when the next mission loads.")

	var sub_rows: Array[Control] = []
	var master := CheckButton.new()
	master.text = "Enabled"
	master.button_pressed = bool(Game.settings.advanced_caps)
	master.toggled.connect(func(on):
		Game.settings.advanced_caps = on
		_mark()
		for r in sub_rows:
			r.modulate = Color(1, 1, 1, 1.0 if on else 0.42))
	_row(vb, "Master switch", "Gates every system below at once.", master)

	for cfg in [
			["cap_ftl", "Lightspeed drive", "Hold the FTL key to spool a warp tunnel. Weapons go offline and the hull becomes intangible while cruising. Needs clear space to engage."],
			["cap_shield", "Icosahedral shield matrix", "A geodesic field that stays invisible until it is hit, then lights the hemisphere facing the impact."],
			["cap_arsenal", "Extended arsenal", "Railgun, arc projector, flak, phase disruptor, scatter repeater and singularity lance, plus EMP, cluster and mine warheads. Cycle primaries in flight."],
			["cap_targeting", "Adaptive targeting computer", "Closed-loop fire control that holds your hit rate at the band below, scattering when you are too accurate and guiding rounds when you are not accurate enough."]]:
		var key: String = cfg[0]
		var cb := CheckButton.new()
		cb.text = "Enabled"
		cb.button_pressed = bool(Game.settings[key])
		cb.toggled.connect(func(on):
			Game.settings[key] = on
			_mark())
		var before := vb.get_child_count()
		_row(vb, cfg[1], cfg[2], cb)
		sub_rows.append(vb.get_child(before) as Control)

	_section(vb, "FIRE CONTROL BAND",
		"The targeting computer servos your measured rolling hit rate to this value. It is clamped to 80-90% by design.")
	var band := _labeled_slider(0.80, 0.90, Game.targeting_setpoint(), 0.01, "%", 100.0)
	var band_slider := band.get_meta("slider") as HSlider
	band_slider.value_changed.connect(func(v):
		Game.settings.targeting_hit_rate = v
		_update_labeled_slider(band, v, "%", 100.0)
		_mark())
	_row(vb, "Target hit rate", "Applies immediately; the loop takes a few seconds of sustained fire to settle.", band)

	var enabled_now: bool = bool(Game.settings.advanced_caps)
	for r in sub_rows:
		r.modulate = Color(1, 1, 1, 1.0 if enabled_now else 0.42)
	return pair[0]

func _labeled_slider(minimum: float, maximum: float, value: float, step: float,
		suffix: String, multiplier := 1.0) -> VBoxContainer:
	var box := VBoxContainer.new()
	var value_label := Styles.label("", 13, Styles.ORANGE, true)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(value_label)
	var slider := Styles.hslider(minimum, maximum, value, step)
	box.add_child(slider)
	box.set_meta("slider", slider)
	box.set_meta("value_label", value_label)
	_update_labeled_slider(box, value, suffix, multiplier)
	return box

func _update_labeled_slider(box: Control, value: float, suffix: String,
		multiplier := 1.0) -> void:
	var label := box.get_meta("value_label") as Label
	label.text = "%.0f%s" % [value * multiplier, suffix] if multiplier != 1.0 \
		else "%.2f%s" % [value, suffix]

# ------------------------------------------------------------------ controls
func _controls_tab() -> Control:
	var pair := _scroll_tab("CONTROLS")
	_controls_box = pair[1]
	_rebuild_controls()
	return pair[0]

func _rebuild_controls() -> void:
	for c in _controls_box.get_children():
		c.queue_free()
	_section(_controls_box, "INPUT BINDINGS",
		"Select a binding, then press a key, mouse button, gamepad button or move an axis past 65%. Esc cancels.")
	for action in Game.ACTION_LABELS:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		var l := Styles.label(Game.ACTION_LABELS[action], 14)
		l.custom_minimum_size.x = 300
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(l)
		var b := Styles.button(Game.binding_text(action), 12)
		b.custom_minimum_size.x = 300
		var act: String = action
		b.pressed.connect(func(): _start_rebind(act, b))
		hb.add_child(b)
		_controls_box.add_child(hb)
	var reset := Styles.button("RESET ALL BINDINGS", 13, Styles.ORANGE)
	reset.pressed.connect(func():
		Game.reset_bindings()
		_rebuild_controls())
	_controls_box.add_child(reset)

func _start_rebind(action: String, button: Button) -> void:
	if _rebind_button:
		_rebind_button.text = Game.binding_text(_rebind_action)
	_rebind_action = action
	_rebind_button = button
	button.text = "WAITING FOR INPUT…"

func _input(event: InputEvent) -> void:
	if _rebind_action == "" and event.is_action_pressed("pause"):
		_close()
		get_viewport().set_input_as_handled()
		return
	if _rebind_action == "":
		return
	var done := false
	if event is InputEventKey and event.pressed:
		if (event as InputEventKey).physical_keycode != KEY_ESCAPE:
			Game.rebind_action(_rebind_action, event)
		done = true
	elif event is InputEventMouseButton and event.pressed:
		Game.rebind_action(_rebind_action, event)
		done = true
	elif event is InputEventJoypadButton and event.pressed:
		Game.rebind_action(_rebind_action, event)
		done = true
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) >= 0.65:
		Game.rebind_action(_rebind_action, event)
		done = true
	if event is InputEventKey and event.pressed \
			and ((event as InputEventKey).physical_keycode == KEY_ESCAPE \
			or (event as InputEventKey).keycode == KEY_ESCAPE):
		done = true
	if done:
		get_viewport().set_input_as_handled()
		_rebind_action = ""
		_rebind_button = null
		_rebuild_controls()
