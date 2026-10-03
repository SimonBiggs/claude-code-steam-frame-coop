extends Node
## Catches A / Start from controllers that aren't playing yet, so they join the game instead of
## opening the pause menu. Added after the pause menu, so it sees input first.

var main


func _input(event: InputEvent) -> void:
	if main != null and main.handle_join_input(event):
		get_viewport().set_input_as_handled()
