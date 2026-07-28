extends Node3D
## Cinematic main menu: 3D hangar backdrop + mission select / hangar / settings / credits.

var env: SpaceEnv
var display_ship: Node3D = null
var cam: Camera3D
var ui: CanvasLayer
var content: Control          # right-side swap area
var _t := 0.0
var _sel_mission := "instant_action"

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	env = SpaceEnv.new()
	add_child(env)
	env.build({
		"neb_a": Color(0.14, 0.05, 0.26), "neb_b": Color(0.02, 0.15, 0.3), "neb_c": Color(0.3, 0.11, 0.05),
		"planets": [{"pos": Vector3(-9000, 1500, -14000), "radius": 4200.0,
			"col_a": Color(0.85, 0.5, 0.25), "col_b": Color(0.5, 0.22, 0.1), "atmo": Color(1.0, 0.6, 0.3)}],
	})
	var field := AsteroidField.new()
	add_child(field)
	field.populate_cluster(Vector3(60, -30, -220), 160.0, 40, 77)
	field.populate_belt(Vector3(0, -100, -1500), 900.0, 260.0, 320, 78)
	field.commit()
	cam = Camera3D.new()
	cam.fov = 55
	cam.far = 60000.0
	add_child(cam)
	cam.position = Vector3(0, 2.5, 20)
	# hangar key light so the display ship reads clearly
	var key := OmniLight3D.new()
	key.light_energy = 2.6
	key.omni_range = 60.0
	key.light_color = Color(1.0, 0.92, 0.8)
	add_child(key)
	key.position = Vector3(8, 8, 14)
	var rim := OmniLight3D.new()
	rim.light_energy = 1.4
	rim.omni_range = 50.0
	rim.light_color = Color(0.45, 0.7, 1.0)
	add_child(rim)
	rim.position = Vector3(-9, 3, -6)
	_show_ship(Game.save.selected_ship)
	ui = CanvasLayer.new()
	add_child(ui)
	_build_ui()
	AudioMgr.play_music("menu")

func _process(delta: float) -> void:
	_t += delta
	if display_ship:
		display_ship.rotation.y += delta * 0.25
		display_ship.position.y = sin(_t * 0.7) * 0.4
	cam.position.x = sin(_t * 0.11) * 1.5
	cam.look_at(Vector3(0, 0, 0))

func _show_ship(id: String) -> void:
	if display_ship:
		display_ship.queue_free()
		display_ship = null
	var sdef: Dictionary = ShipDB.SHIPS[id]
	if not ResourceLoader.exists(sdef.model):
		return
	display_ship = Node3D.new()
	add_child(display_ship)
	var inst: Node3D = (load(sdef.model) as PackedScene).instantiate()
	display_ship.add_child(inst)
	display_ship.position = Vector3(3.5, 0, 0)
	display_ship.rotation.y = 0.6
	var lo: Dictionary = Game.loadout_for(id)
	for mi in inst.find_children("*", "MeshInstance3D", true):
		var m3 := mi as MeshInstance3D
		for s in m3.mesh.get_surface_count():
			var mat := m3.mesh.surface_get_material(s)
			if mat is BaseMaterial3D:
				var nm := mat.resource_name.to_lower()
				if nm.ends_with("_hull") and not nm.ends_with("2_hull"):
					var dup: BaseMaterial3D = mat.duplicate()
					dup.albedo_color = lo.paint
					m3.set_surface_override_material(s, dup)
				elif nm.find("_engine") != -1:
					var dup2: StandardMaterial3D = mat.duplicate()
					dup2.emission = lo.glow
					m3.set_surface_override_material(s, dup2)

# =================================================================== UI
func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(root)
	# left column
	var left := VBoxContainer.new()
	left.position = Vector2(60, 70)
	left.add_theme_constant_override("separation", 10)
	root.add_child(left)
	var title := Styles.label("HELION", 64, Color(0.95, 0.97, 1.0), true)
	var title2 := Styles.label("VANGUARD", 64, Styles.ORANGE, true)
	title2.position.y = -18
	left.add_child(title)
	left.add_child(title2)
	left.add_child(Styles.label("Deep-belt space combat  ·  v%s" % Game.VERSION, 14, Styles.DIM))
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 26
	left.add_child(spacer)
	var entries := [
		["INSTANT ACTION", func(): Game.start_mission("instant_action")],
		["MISSIONS", func(): _show_missions()],
		["HANGAR", func(): _show_hangar()],
		["SETTINGS", func(): _show_settings()],
		["CREDITS & LICENCES", func(): _show_credits()],
		["QUIT", func(): _quit()],
	]
	for e in entries:
		var b := Styles.button(e[0], 21)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.x = 330
		b.pressed.connect(e[1])
		left.add_child(b)
	if not Game.save.training_done:
		var hint := Styles.label("New pilot? Fly FLIGHT ACADEMY under MISSIONS first.", 14, Styles.CYAN)
		left.add_child(hint)
	# right content area
	content = PanelContainer.new()
	content.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	content.position = Vector2(-40, 0)
	content.anchor_left = 0.44
	content.anchor_right = 0.97
	content.anchor_top = 0.08
	content.anchor_bottom = 0.92
	content.offset_left = 0; content.offset_right = 0
	content.offset_top = 0; content.offset_bottom = 0
	(content as PanelContainer).add_theme_stylebox_override("panel", Styles.panel())
	content.visible = false
	root.add_child(content)

func _clear_content() -> Control:
	for c in content.get_children():
		c.queue_free()
	content.visible = true
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	content.add_child(vb)
	var close := Styles.button("← BACK", 14)
	close.pressed.connect(func(): content.visible = false)
	vb.add_child(close)
	return vb

# ------------------------------------------------------------------ missions
func _show_missions() -> void:
	var vb := _clear_content()
	vb.add_child(Styles.label("MISSIONS", 26, Styles.CYAN, true))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	for id in MissionDefs.ORDER:
		var m: Dictionary = MissionDefs.get_mission(id)
		var hb := HBoxContainer.new()
		var b := Styles.button(m.title, 17)
		b.custom_minimum_size.x = 320
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var mid: String = id
		b.pressed.connect(func(): _show_briefing(mid))
		hb.add_child(b)
		var done: bool = Game.save.missions_done.has(id)
		var tag := Styles.label(("★ %d" % Game.save.missions_done[id].score) if done else m.mode, 14,
			Styles.GREEN if done else Styles.DIM)
		hb.add_child(tag)
		list.add_child(hb)

func _show_briefing(id: String) -> void:
	_sel_mission = id
	var m: Dictionary = MissionDefs.get_mission(id)
	var vb := _clear_content()
	vb.add_child(Styles.label(m.title, 28, Styles.ORANGE, true))
	vb.add_child(Styles.label(m.mode.to_upper() + " BRIEFING", 14, Styles.DIM, true))
	vb.add_child(HSeparator.new())
	var desc := Styles.label(m.desc, 16)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(desc)
	vb.add_child(HSeparator.new())
	for line in m.briefing:
		var l := Styles.label("▸  " + line, 15, Color(0.8, 0.88, 0.95))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(l)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(sp)
	var ship_line := Styles.label("Ship: %s   ·   Difficulty: %s" %
		[ShipDB.SHIPS[Game.save.selected_ship].label, ["Easy", "Normal", "Hard"][Game.settings.difficulty]], 14, Styles.DIM)
	vb.add_child(ship_line)
	var launch := Styles.button("LAUNCH  ▸", 24, Styles.GREEN)
	launch.pressed.connect(func(): Game.start_mission(id))
	vb.add_child(launch)

# ------------------------------------------------------------------ hangar
func _show_hangar() -> void:
	var vb := _clear_content()
	vb.add_child(Styles.label("HANGAR", 26, Styles.CYAN, true))
	var ships_row := HBoxContainer.new()
	ships_row.add_theme_constant_override("separation", 6)
	vb.add_child(ships_row)
	for id in ShipDB.SHIPS:
		var sdef: Dictionary = ShipDB.SHIPS[id]
		var unlocked: bool = id in Game.save.unlocked_ships
		var b := Styles.button(sdef.label if unlocked else "🔒 " + sdef.label, 14)
		var sid: String = id
		b.disabled = not unlocked
		if id == Game.save.selected_ship:
			b.add_theme_color_override("font_color", Styles.ORANGE)
		b.pressed.connect(func():
			Game.save.selected_ship = sid
			Game.save_game()
			_show_ship(sid)
			# deferred: rebuilding now would free the button mid-signal
			_show_hangar.call_deferred())
		ships_row.add_child(b)
	var sdef: Dictionary = ShipDB.SHIPS[Game.save.selected_ship]
	var lo: Dictionary = Game.loadout_for(Game.save.selected_ship)
	vb.add_child(Styles.label("%s — %s" % [sdef.label, sdef.role], 19, Styles.ORANGE, true))
	var d := Styles.label(sdef.desc, 14, Styles.DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(d)
	# stat bars
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 14)
	vb.add_child(stats)
	for st in [["Speed", sdef.speed / 140.0], ["Agility", sdef.turn / 1.4],
			["Hull", sdef.hull / 260.0], ["Shields", sdef.shield / 180.0],
			["Energy", sdef.energy / 150.0], ["Missiles", float(sdef.missile_cap) / 18.0]]:
		stats.add_child(Styles.label(st[0], 13, Styles.DIM))
		var pb := ProgressBar.new()
		pb.min_value = 0; pb.max_value = 1; pb.value = st[1]
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(240, 12)
		stats.add_child(pb)
	vb.add_child(HSeparator.new())
	# loadout selectors
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)
	grid.add_child(Styles.label("Primary group A", 14))
	grid.add_child(_weapon_select("primary", lo.primary))
	grid.add_child(Styles.label("Primary group B", 14))
	grid.add_child(_weapon_select("primary2", lo.primary2))
	grid.add_child(Styles.label("Missiles", 14))
	grid.add_child(_missile_select(lo.missile))
	# paint swatches
	grid.add_child(Styles.label("Paint", 14))
	grid.add_child(_swatch_row("paint", [Color(0.85, 0.36, 0.045), Color(0.8, 0.15, 0.1),
		Color(0.2, 0.5, 0.55), Color(0.55, 0.6, 0.65), Color(0.15, 0.25, 0.5),
		Color(0.75, 0.65, 0.2), Color(0.25, 0.25, 0.28), Color(0.55, 0.2, 0.5)]))
	grid.add_child(Styles.label("Engine glow", 14))
	grid.add_child(_swatch_row("glow", [Color(0.25, 0.65, 1.0), Color(0.55, 0.35, 1.0),
		Color(1.0, 0.45, 0.15), Color(0.3, 1.0, 0.6), Color(1.0, 0.25, 0.3)]))
	var note := Styles.label("Loadout is saved automatically and applies to every mission.", 12, Styles.DIM)
	vb.add_child(note)

func _weapon_select(slot: String, current: String) -> OptionButton:
	var ob := OptionButton.new()
	var ids := ShipDB.primary_ids()
	for i in ids.size():
		var w: Dictionary = ShipDB.WEAPONS[ids[i]]
		ob.add_item(w.label, i)
		ob.set_item_tooltip(i, w.desc)
		if ids[i] == current:
			ob.selected = i
	ob.item_selected.connect(func(i):
		var lo := Game.loadout_for(Game.save.selected_ship)
		lo[slot] = ids[i]
		Game.set_loadout(Game.save.selected_ship, lo))
	return ob

func _missile_select(current: String) -> OptionButton:
	var ob := OptionButton.new()
	var ids := ShipDB.missile_ids()
	for i in ids.size():
		var m: Dictionary = ShipDB.MISSILES[ids[i]]
		ob.add_item(m.label, i)
		ob.set_item_tooltip(i, m.desc)
		if ids[i] == current:
			ob.selected = i
	ob.item_selected.connect(func(i):
		var lo := Game.loadout_for(Game.save.selected_ship)
		lo.missile = ids[i]
		Game.set_loadout(Game.save.selected_ship, lo))
	return ob

func _swatch_row(slot: String, colors: Array) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	for c in colors:
		var b := Button.new()
		b.custom_minimum_size = Vector2(30, 24)
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(3)
		sb.set_border_width_all(1)
		sb.border_color = Color(1, 1, 1, 0.4)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		var col: Color = c
		b.pressed.connect(func():
			var lo := Game.loadout_for(Game.save.selected_ship)
			lo[slot] = col
			Game.set_loadout(Game.save.selected_ship, lo)
			_show_ship(Game.save.selected_ship)
			AudioMgr.play_ui("ui_click"))
		hb.add_child(b)
	return hb

# ------------------------------------------------------------------ settings & credits
func _show_settings() -> void:
	var sp := SettingsPanel.new()
	ui.add_child(sp)
	sp.closed.connect(func(): sp.queue_free())

func _show_credits() -> void:
	var vb := _clear_content()
	vb.add_child(Styles.label("CREDITS & LICENCES", 26, Styles.CYAN, true))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(sc)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(tv)
	var credits := """HELION VANGUARD  v%s
An original space-combat game built with the Godot Engine.

— PRODUCTION —
Design, code, 3D models, VFX, missions, audio synthesis:
Original Games automated production team

— TECHNOLOGY —
Godot Engine 4 — MIT licence (godotengine.org)
Ships, stations & cockpit modelled procedurally in Blender

— THIRD-PARTY ASSETS —
“Aerial Rocks 02” texture — Poly Haven (polyhaven.com) — CC0
Orbitron typeface — Matt McInerney — SIL Open Font Licence 1.1
Exo 2 typeface — Natanael Gama — SIL Open Font Licence 1.1

All sound effects and music are procedurally synthesised
originals created for this game.

Full licence texts: LICENSES.md inside the project folder.
No assets were taken from any commercial game.
""" % Game.VERSION
	var l := Styles.label(credits, 15)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(l)

func _quit() -> void:
	Game.save_settings()
	Game.save_game()
	get_tree().quit()
