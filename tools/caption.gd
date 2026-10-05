extends Node
## "Claude:" captions in every game (created by the gdev bridge). Polls res://.dev/caption.txt,
## written by `frame-say`, and shows the text without a box:
## - VR: world-locked Label3D ~2 m in front of the player, slightly below eye level. It only moves
##   when the player has turned well away (lazy follow) and is never attached to the head.
## - Flat screen / TV: a line at the bottom of the window.

const FILE := "res://.dev/caption.txt"
const DIST := 2.0
const FOLLOW_DEG := 35.0

var poll_t := 0.0
var show_t := 0.0
var label3d: Label3D
var layer: CanvasLayer
var label2d: Label


func _process(delta: float) -> void:
	poll_t -= delta
	if poll_t <= 0.0:
		poll_t = 0.25
		_poll()
	if show_t > 0.0:
		show_t -= delta
		if show_t <= 0.0:
			_hide()
		else:
			_place()


func _poll() -> void:
	var path := ProjectSettings.globalize_path(FILE)
	if not FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(path).strip_edges()
	DirAccess.remove_absolute(path)
	if text != "":
		show_text("Claude: " + text)


func show_text(text: String) -> void:
	show_t = 5.0 + text.length() * 0.07
	var cam := get_viewport().get_camera_3d()
	if cam is XRCamera3D:
		if not is_instance_valid(label3d):
			label3d = Label3D.new()
			label3d.font_size = 56
			label3d.outline_size = 14
			label3d.width = 900.0
			label3d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label3d.no_depth_test = true
			label3d.render_priority = 20
			label3d.modulate = Color(1.0, 0.95, 0.75)
			get_tree().root.add_child(label3d)
		label3d.text = text
		label3d.visible = true
		_place(true)
	else:
		if not is_instance_valid(layer):
			layer = CanvasLayer.new()
			layer.layer = 100
			label2d = Label.new()
			label2d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label2d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label2d.add_theme_font_size_override("font_size", 34)
			label2d.add_theme_constant_override("outline_size", 12)
			label2d.add_theme_color_override("font_outline_color", Color.BLACK)
			label2d.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
			label2d.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			label2d.offset_top = -150.0
			label2d.offset_bottom = -40.0
			layer.add_child(label2d)
			get_tree().root.add_child(layer)
		label2d.text = text
		layer.visible = true


func _place(force: bool = false) -> void:
	if not is_instance_valid(label3d) or not label3d.visible:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var s: float = XRServer.world_scale
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return
	fwd = fwd.normalized()
	var to_label := label3d.global_position - cam.global_position
	to_label.y = 0.0
	if not force and to_label.length() > 0.01 and rad_to_deg(fwd.angle_to(to_label.normalized())) < FOLLOW_DEG:
		return  # still roughly in view: stay world-locked
	label3d.global_position = cam.global_position + fwd * DIST * s + Vector3(0.0, -0.3 * s, 0.0)
	label3d.pixel_size = 0.0022 * s
	var d := label3d.global_position - cam.global_position
	# A Label3D's readable side is +Z: point +Z back at the player (the other sign mirrors it).
	label3d.global_rotation = Vector3(0.0, atan2(-d.x, -d.z), 0.0)


func _hide() -> void:
	if is_instance_valid(label3d):
		label3d.visible = false
	if is_instance_valid(layer):
		layer.visible = false
