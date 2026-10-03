extends Node
## Drop-in join: sees controller presses before the pause menu does (it is a later sibling, and _input
## runs in reverse tree order), so A on a controller that has no player yet joins the game as a new bee.
## (Start still opens the shared pause menu.)

var main


func _input(event: InputEvent) -> void:
	if main != null and main.handle_join_input(event):
		get_viewport().set_input_as_handled()
