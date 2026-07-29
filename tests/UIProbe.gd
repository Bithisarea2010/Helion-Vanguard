extends Control
## Deterministic settings-panel capture for visual review.

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.01, 0.025, 0.055)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var glow := ColorRect.new()
	glow.color = Color(0.02, 0.12, 0.20, 0.35)
	glow.position = Vector2(0, 520)
	glow.size = Vector2(1280, 200)
	backdrop.add_child(glow)
	var panel := SettingsPanel.new()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	var margin := panel.get_child(1) as Control
	var center := margin.get_child(0) as Control
	var card := center.get_child(0) as Control
	print("[UIPROBE] root=%s margin=%s center=%s card=%s pos=%s" % [
		panel.size, margin.size, center.size, card.size, card.position])
	await get_tree().create_timer(0.25).timeout
	var shot_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shotdir="):
			shot_dir = arg.get_slice("=", 1)
	if shot_dir != "":
		DirAccess.make_dir_recursive_absolute(shot_dir)
		var image := get_viewport().get_texture().get_image()
		var err := image.save_png(shot_dir.path_join("settings_panel.png"))
		print("[UIPROBE] %s" % ("saved" if err == OK else error_string(err)))
	Game.prepare_shutdown()
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()
