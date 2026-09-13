extends SceneTree
## Run with the packaged executable, --main-pack /absolute/game.pck and
## --script /absolute/tools/inspect_local_pack.gd -- --defaults.
## Let audio initialize before inspecting and shut down after its first mix.
func _initialize() -> void:
	_inspect.call_deferred()
func _inspect() -> void:
	await create_timer(0.2).timeout
	var game := root.get_node_or_null("Game")
	var audio := root.get_node_or_null("AudioMgr")
	var checks := {
		"game_version_1_3_0": game != null and game.VERSION == "1.3.0",
		"no_mcp_autoload": root.get_node_or_null("MCPRuntimeServer") == null and str(ProjectSettings.get_setting("autoload/MCPRuntimeServer", "")) == "",
		"no_addon_directory": not DirAccess.dir_exists_absolute("res://addons/godot_mcp_toolkit"),
		"no_local_mcp_configuration": not FileAccess.file_exists("res://.mcp.json"),
		"new_hulls_in_pack": ResourceLoader.exists("res://assets/models/ship_aegis.glb") and ResourceLoader.exists("res://assets/models/ship_peregrine.glb") and ResourceLoader.exists("res://assets/models/ship_vanguard_mk3.glb"),
		"relay_in_pack": ResourceLoader.exists("res://assets/models/helion_relay.glb"),
		"new_audio_bank_loaded": audio != null and audio.has_sound("hv_rail") and audio.has_sound("hv_flight_bed") and audio.has_sound("hv_resupply"),
		"eight_playable_ships": load("res://scripts/core/ShipDB.gd").SHIPS.size() == 8,
	}
	print("[PACK] ", JSON.stringify(checks))
	var ok := true
	for value in checks.values():
		ok = ok and bool(value)
	if game:
		game.prepare_shutdown()
	await create_timer(0.2).timeout
	quit(0 if ok else 1)
