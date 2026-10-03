extends Control
## Launcher for the collection. Goes straight into a game when there's only one, when the machine
## is part of a networked VR + TV session, or when ARCADE_GAME=<id> is set; otherwise it shows a
## simple controller-friendly picker on the TV.

const GAMES := [
	{"id": "duo_arena", "name": "DUO ARENA", "scene": "res://games/duo_arena/main.tscn",
		"blurb": "Neon first-person co-op arena shooter  ·  VR + TV  ·  up to 3 players"},
]


func _ready() -> void:
	var wanted := OS.get_environment("ARCADE_GAME") if OS.has_environment("ARCADE_GAME") else ""
	var xr := XRServer.find_interface("OpenXR")
	var networked := OS.has_environment("DUO_JOIN") or OS.has_environment("DUO_HOST") \
		or (xr != null and xr.is_initialized())
	if wanted != "" or networked or GAMES.size() == 1:
		_start(_find(wanted))
		return
	_build_menu()


func _find(id: String) -> Dictionary:
	for g in GAMES:
		if g.id == id:
			return g
	return GAMES[0]


func _start(game: Dictionary) -> void:
	print("Arcade: starting %s" % game.name)
	get_tree().change_scene_to_file.call_deferred(game.scene)


func _build_menu() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.08)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	var title := Label.new()
	title.text = "LIVING ROOM ARCADE"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var first: Button
	for g in GAMES:
		var b := Button.new()
		b.text = "%s\n%s" % [g.name, g.blurb]
		b.custom_minimum_size = Vector2(900, 110)
		b.add_theme_font_size_override("font_size", 30)
		b.pressed.connect(_start.bind(g))
		box.add_child(b)
		if first == null:
			first = b
	var soon := Label.new()
	soon.text = "More games coming: just ask Claude!"
	soon.add_theme_font_size_override("font_size", 24)
	soon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(soon)
	first.grab_focus()
