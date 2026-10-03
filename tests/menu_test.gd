extends Node
# Throwaway test: press Esc, check pause, press Esc again, check resume.
var main
var f := 0
func _ready():
	main = load("res://main.tscn").instantiate()
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
	if f == 40: print("after esc: paused=", get_tree().paused)
	if f == 50: _esc()
	if f == 60: print("after 2nd esc: paused=", get_tree().paused); get_tree().quit()
