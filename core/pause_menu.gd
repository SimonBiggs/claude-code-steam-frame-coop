extends CanvasLayer
## Pause menu. Esc or controller Start toggles it (Steam's desktop layout sends Esc for Start).
## Only a controller that is in play may open it: with a core/party.gd PartyManager on main
## (`main.party`) that means a pad the party owns; older games fall back to their players' `joy`.
## In group "pause_menu": core/net.gd calls sync_remote_pause() when the other machine resumes.

var main
var panel: ColorRect
var buttons: Array[Button] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	add_to_group("pause_menu")
	panel = ColorRect.new()
	panel.color = Color(0.02, 0.03, 0.06, 0.75)
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 80)
	box.add_child(title)

	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(0.3, 0.95, 1.0)
	focus.set_border_width_all(5)
	focus.set_corner_radius_all(8)
	for item in [["Resume", _resume], ["Restart", _restart], ["Back to Arcade", _arcade], ["Fullscreen", _fullscreen], ["Quit game", _quit]]:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(460, 76)
		b.add_theme_font_size_override("font_size", 38)
		b.add_theme_stylebox_override("focus", focus)
		b.pressed.connect(item[1])
		box.add_child(b)
		buttons.append(b)

	var hint := Label.new()
	hint.text = "D-pad / arrows to choose  ·  A / Enter to select  ·  Start / Esc to resume"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 22)
	box.add_child(hint)
	panel.visible = false


func _input(event: InputEvent) -> void:
	var toggle := false
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
		toggle = true
	var pad := event as InputEventJoypadButton
	if pad and pad.pressed and pad.button_index == JOY_BUTTON_START and (panel.visible or _pad_in_play(pad.device)):
		toggle = true
	if not toggle:
		return
	get_viewport().set_input_as_handled()
	if panel.visible:
		_resume()
	else:
		_open()


## Start on a spare controller nobody is playing with (left on the couch, or a test machine's pads)
## shouldn't pause everyone. A pad counts if a player owns it via `joy`, or if no player owns any pad.
func _pad_in_play(device: int) -> bool:
	if main == null:
		return true
	var party = main.get("party")
	if party != null and is_instance_valid(party) and party.has_method("owner_of"):
		return int(party.owner_of(device)) >= 0
	if not ("players" in main):
		return true
	var any_owned := false
	for p in main.players:
		if p == null or not is_instance_valid(p) or not ("joy" in p):
			continue
		var j: int = int(p.get("joy"))
		if j < 0:
			continue
		any_owned = true
		if j == device:
			return true
	return not any_owned


func _open() -> void:
	panel.visible = true
	get_tree().paused = true
	if main and main.net:
		main.net.send_action("pause", [true])  # networked co-op: pause the host too
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	buttons[0].grab_focus()


func _resume() -> void:
	panel.visible = false
	get_tree().paused = false
	if main and main.net:
		main.net.send_action("pause", [false])
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The other machine resumed (VR wrist RESUME, or the TV's menu): close this menu without
## sending anything back. Called by core/net.gd through the "pause_menu" group.
func sync_remote_pause(paused: bool) -> void:
	if not paused and panel != null and panel.visible:
		panel.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _arcade() -> void:
	panel.visible = false
	if main and main.get("net") != null:
		main.net.go_to_arcade()
	else:
		get_tree().paused = false
		get_tree().change_scene_to_file("res://arcade.tscn")


func _fullscreen() -> void:
	var w := get_window()
	w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


func _quit() -> void:
	get_tree().quit()
