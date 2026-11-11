extends Node
## Esc pauses Duo Arena and a second Esc resumes it (keyboard pause, no controller). Prints MENU TEST: PASS / FAIL
## and exits with the number of failures (dev.land runs it with the other repo guards).
var main
var f := 0
var fails: Array = []


func _ready():
	main = load("res://games/duo_arena/main.tscn").instantiate()
	add_child(main)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _esc():
	var e := InputEventKey.new(); e.physical_keycode = KEY_ESCAPE; e.pressed = true
	Input.parse_input_event(e)
	var u := InputEventKey.new(); u.physical_keycode = KEY_ESCAPE; u.pressed = false
	Input.parse_input_event(u)


func _process(_d):
	f += 1
	if f == 30: _esc()
	if f == 40 and not get_tree().paused: fails.append("Esc did not pause")
	if f == 50: _esc()
	if f == 60:
		if get_tree().paused: fails.append("a second Esc did not resume")
		print("MENU TEST: %s%s" % ["PASS" if fails.is_empty() else "FAIL ", ", ".join(fails)])
		preload("res://tests/bot_end.gd").quit_quietly(get_tree(), fails.size())
