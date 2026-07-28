extends Node
## Boot: apply settings then hand off to the main menu.

func _ready() -> void:
	# when launched with `-- --mission=x` (automated testing) Game already queued the battle
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mission="):
			return
	get_tree().change_scene_to_file.call_deferred("res://scenes/MainMenu.tscn")
