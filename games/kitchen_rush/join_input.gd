extends Node
## Drop-in join: sees controller presses before the pause menu does (it sits later in the tree, and
## _input runs in reverse tree order), so Start on a controller nobody owns yet joins instead of pausing.

var main


func _input(event: InputEvent) -> void:
	if main != null and main.on_join_input(event):
		get_viewport().set_input_as_handled()
