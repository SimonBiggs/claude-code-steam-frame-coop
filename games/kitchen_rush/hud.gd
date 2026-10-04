extends Control
## One player's screen HUD: runners get a crosshair, what they carry, what the button does here, and the
## order list; the button chef gets its controls and what it's holding.

const ItemScript := preload("res://games/kitchen_rush/item.gd")

var player
var main
var chef := false
var hint_label: Label
var carry_label: Label
var orders_label: Label
var cross: ColorRect
var job_panel: PanelContainer
var job_label: Label
var ui_scale := 1.0  # shrinks with the split-screen view (1.0 at half a 1080p screen or bigger)
var fonts := {}  # Label -> base font size


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	orders_label = _label(24, Color(1.0, 0.97, 0.85))
	add_child(orders_label)
	orders_label.position = Vector2(24, 70)
	carry_label = _label(30, player.color.lightened(0.35))
	add_child(carry_label)
	hint_label = _label(28, Color(1.0, 0.92, 0.45))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint_label)
	job_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.1, 0.72)
	sb.border_color = player.color.lightened(0.2)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	job_panel.add_theme_stylebox_override("panel", sb)
	job_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(job_panel)
	job_label = _label(30, Color(1.0, 0.95, 0.6))
	job_panel.add_child(job_label)
	if not chef:
		cross = ColorRect.new()
		cross.color = Color(1, 1, 1, 0.8)
		cross.size = Vector2(8, 8)
		cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cross)


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", maxi(6, size / 4))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fonts[l] = size
	return l


## Scale every label with the view: 2x2 and 3x2 grids get smaller text so the picture stays visible.
func _update_scale() -> void:
	var s := clampf(minf(size.x / 960.0, size.y / 1000.0), 0.55, 1.0)
	if absf(s - ui_scale) < 0.01 and not fonts.is_empty() and has_meta("scaled"):
		return
	set_meta("scaled", true)
	ui_scale = s
	for l in fonts:
		var base: int = fonts[l]
		var fs := maxi(12, int(round(base * s)))
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_constant_override("outline_size", maxi(4, fs / 4))


func _process(_delta: float) -> void:
	if chef and fonts.get(carry_label, 0) != 22:
		fonts[carry_label] = 22
		remove_meta("scaled")
	_update_scale()
	var s := ui_scale
	if cross:
		cross.position = size * 0.5 - Vector2(4, 4)
	orders_label.position = Vector2(24, 130) * s
	carry_label.position = Vector2(24 * s, size.y - 120 * s)
	hint_label.position = Vector2(0, size.y * 0.5 + 60 * s)
	hint_label.size = Vector2(size.x, 40 * s)
	if main.simple:
		# Simple mode: no lists or paragraphs - the arrow shows the way, one short button prompt.
		orders_label.visible = false
		job_panel.visible = false
		carry_label.visible = false
		if chef:
			hint_label.text = main.chef_prompt(player)
		else:
			hint_label.text = ("PRESS " + _button_name()) if main.resolve(player).has("act") and not main.input_blocked() else ""
		return
	orders_label.text = main.orders_text()
	# Your job right now, big and clear (the arrow in the world points at it).
	var job_text := ""
	if chef:
		job_text = str(main.chef_task.get("text", ""))
	else:
		job_text = str(main.runner_job(player).get("text", ""))
	job_panel.visible = job_text != "" and not main.game_over
	job_label.text = ("NEXT: " if chef else "YOUR JOB: ") + job_text
	job_panel.size = Vector2.ZERO
	job_panel.position = Vector2((size.x - job_panel.size.x) * 0.5, 64.0 * s)
	if chef:
		var held = player.held[0]
		var what := "nothing"
		if held != null and is_instance_valid(held):
			what = main.item_label(held)
		carry_label.text = "Holding: %s\nWASD / d-pad: move hand   Space / A: grab or place   Shift / X: CHOP" % what
		hint_label.text = main.chef_hint(player)
		return
	var c: String = player.carry_kind
	var what2 := "nothing"
	if c == "extinguisher":
		what2 = "FIRE EXTINGUISHER"
	elif c.begins_with("plate:"):
		what2 = c.substr(6) + " (finished!)"
	elif c != "":
		what2 = ItemScript.display_name(c)
	carry_label.text = "P%d carrying: %s" % [player.index + 1, what2]
	var r: Dictionary = main.resolve(player)
	var t: String = r.get("text", "")
	if r.has("act"):
		t = "[%s]  %s" % [_button_name(), t]
	hint_label.text = t


func _button_name() -> String:
	if player.joy >= 0 or player.keys() < 0:
		return "A"
	return "E / click" if player.keys() == 0 else "Enter"
