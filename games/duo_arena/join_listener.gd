extends Node
## Drop-in join: sees controller presses before the pause menu does (it is a later sibling, and _input
## runs in reverse tree order), so A / Start on a controller that has no player yet joins the game
## instead of opening the menu.

var main


func _input(event: InputEvent) -> void:
	if main != null and main.handle_join_input(event):
		get_viewport().set_input_as_handled()
