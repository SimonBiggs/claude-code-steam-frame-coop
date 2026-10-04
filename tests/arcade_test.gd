extends Node
## Headless test of the arcade launcher: category tabs, cards, keyboard/controller tab switching and
## selection sync (no lobby partner, nothing is launched).

var arcade: Node
var t := 0


func _ready() -> void:
	arcade = load("res://arcade.tscn").instantiate()
	add_child(arcade)


func _process(_delta: float) -> void:
	t += 1
	if t == 5:
		var tabs: Array[int] = arcade.tabs()
		print("ARCADE TEST: %d tabs, %d games, %d cards on the first tab" % [tabs.size(), arcade.GAMES.size(), arcade.cards.size()])
		for k in tabs.size():
			arcade._show_category(k, true)
			print("  tab %s: %d cards" % [arcade.CATEGORIES[tabs[k]].name, arcade.cards.size()])
	if t == 10:
		var e := InputEventJoypadButton.new()
		e.button_index = JOY_BUTTON_RIGHT_SHOULDER
		e.pressed = true
		arcade._unhandled_input(e)
		var k := InputEventKey.new()
		k.physical_keycode = KEY_Q
		k.pressed = true
		arcade._unhandled_input(k)
		print("ARCADE TEST: tab after RB then Q = %d" % arcade.cat)
	if t == 15:
		for i in arcade.GAMES.size():
			arcade._select(i, false)  # as if the other machine picked it
			if not arcade.cards.has(i):
				push_error("selected game %d is not on the shown tab" % i)
		print("ARCADE TEST: remote selection always shows the right tab")
	if t == 20:
		get_tree().quit()
