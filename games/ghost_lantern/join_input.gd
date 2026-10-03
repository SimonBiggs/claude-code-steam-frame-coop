extends Node
## Ghost Lantern drop-in join: sees controller buttons before the pause menu, so pressing A or Start on a
## spare controller joins the hunt instead of opening the menu. Added lazily by main.gd.

var main


func _input(event: InputEvent) -> void:
	if main != null and event is InputEventJoypadButton and main.on_join_input(event):
		get_viewport().set_input_as_handled()
