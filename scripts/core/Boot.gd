extends Node
## Boot: apply settings then hand off to the main menu.

func _ready() -> void:
	# when launched with `-- --mission=x` (automated testing) Game already queued the battle
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mission="):
			return
	SceneFlow.transition_to.call_deferred("res://scenes/MainMenu.tscn", {
		"kind": "boot",
		"eyebrow": "HELION COMMAND  //  COLD START",
		"title": "VANGUARD SYSTEMS",
		"subtitle": "Establishing a secure flight-deck link",
		"detail": "Synchronising navigation, rendering and tactical services",
	})
