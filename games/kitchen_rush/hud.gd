extends Control
## One player's screen HUD: runners get a crosshair, what they carry, what the button does here, and the
## order list; the button chef gets its controls and what it's holding.
## Simple mode (main.simple): no words at all (visual teaching). Low in the view a pulsing glowing button
## in this player's own controls plus an icon shows what the button does right here: runners A / E /
## ENTER + an up arrow (pick up) at a crate or a ready plate, + a down arrow (put down) at the pass, +
## a heart (serve) at the customer; the button chef X / SHIFT + a knife (chop), A / SPACE + up / down
## arrow (grab / put down) and STICK / an arrow key + an arrow (move the hand) towards the next thing;
## a pulsing bolt when a runner's controller is unplugged. Each cue goes once the player has done it
## twice (main.cue_did / main.cue_learned). The glowing 3D arrows (guide.gd) show where to go.

const ItemScript := preload("res://games/kitchen_rush/item.gd")
const UiKit := preload("res://core/ui_kit.gd")

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
var cue_box: Control  # simple mode: the picture cue (glow + a row of button and icon)
var cue_a := 0.0
var cue_sig := ""


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
	if main.simple:  # no lists or panels, not even for the first frame
		job_panel.visible = false
		orders_label.visible = false
		carry_label.visible = false
		hint_label.visible = false
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
		# Simple mode: no lists, paragraphs or prompts - the arrow shows the way, a picture cue the button.
		orders_label.visible = false
		job_panel.visible = false
		carry_label.visible = false
		hint_label.text = ""
		hint_label.visible = false
		_update_cue(get_process_delta_time())
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


# --- Simple mode picture cues ------------------------------------------------------

## What this player's cue is right now: [key, dir] ("" = none).
func _cue_key() -> Array:
	if main.input_blocked() or (main.net.mode == "client" and not main.synced):
		return ["", ""]
	if chef:
		var c: Dictionary = main.chef_cue(player)
		return [str(c.get("key", "")), str(c.get("dir", ""))]
	if not player.active:
		return ["", ""]
	if player.lost_joy >= 0 and player.joy < 0:
		return ["plug", ""]
	var r: Dictionary = main.resolve(player)
	var k: String = main.runner_cue_key(str(r.get("act", "")))
	if k == "" or main.cue_learned(player, k):
		return ["", ""]
	return [k, ""]


## This player's own button for a cue.
func _button(key: String, dir: String, s: float) -> Control:
	var pad: bool = player.joy >= 0
	if chef:
		match key:
			"chop":
				return UiKit.glyph("X" if pad else "SHIFT", s)
			"move":
				if pad:
					return UiKit.glyph("STICK", s)
				return _arrow_key(dir, s)
		return UiKit.glyph("A" if pad else "SPACE", s)
	if pad or player.keys() < 0:
		return UiKit.glyph("A", s)
	if player.keys() == 1:
		return UiKit.glyph("ENTER", s)
	return UiKit.glyph("E", s)


## A key cap with an arrow on it (WASD for the button chef).
func _arrow_key(dir: String, s: float) -> Control:
	var g := UiKit.glyph("KEY", s)
	(g.get_child(0) as Label).text = ""
	var ic := UiKit.icon("arrow_" + dir, Color.WHITE, 26.0 * s)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.add_child(ic)
	return g


func _cue_icon(key: String, dir: String, s: float) -> Control:
	match key:
		"chop":
			return UiKit.icon("sword", Color(0.85, 0.95, 1.0), 56.0 * s)
		"grab", "take":
			return UiKit.icon("arrow_up", Color(1.0, 0.9, 0.4), 48.0 * s)
		"drop":
			return UiKit.icon("arrow_down", Color(1.0, 0.9, 0.4), 48.0 * s)
		"serve":
			return UiKit.icon("heart", Color(1.0, 0.45, 0.55), 56.0 * s)
		"spray":
			return UiKit.icon("drop", Color(0.5, 0.8, 1.0), 56.0 * s)
		"move":
			return UiKit.icon("arrow_" + dir, Color(1.0, 0.9, 0.4), 48.0 * s)
	return UiKit.icon("dot", Color.WHITE, 40.0 * s)


## The soft halo behind a cue's button.
class CueGlow extends Control:
	var r := 30.0
	var a := 1.0

	func _draw() -> void:
		for i in 3:
			draw_circle(Vector2.ZERO, r * (1.0 + 0.35 * i), Color(1.0, 0.95, 0.6, 0.17 * a * (1.0 - 0.3 * i)))


func _update_cue(delta: float) -> void:
	var kd := _cue_key()
	var key: String = kd[0]
	var dir: String = kd[1]
	player.set_meta("cue", key)
	var s := 1.9 * ui_scale
	if cue_box == null:
		cue_box = Control.new()
		cue_box.name = "Cue"
		cue_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cue_box)
		var glow := CueGlow.new()
		glow.name = "Glow"
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cue_box.add_child(glow)
		player.set_meta("cue_box", cue_box)
	var full := "%s|%s|%d/%d|%.2f" % [key, dir, player.joy, player.keys() if not chef else -9, s]
	if key != "" and full != cue_sig:
		if cue_sig.get_slice("|", 0) != key:
			cue_a = 0.0  # a new cue fades in
		cue_sig = full
		var old := cue_box.get_node_or_null("Row")
		if old != null:
			cue_box.remove_child(old)
			old.queue_free()
		var row := HBoxContainer.new()
		row.name = "Row"
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", int(10 * s))
		var items: Array = []
		if key == "plug":
			items = [UiKit.icon("bolt", Color(1.0, 0.75, 0.3), 56.0 * s)]
		else:
			items = [_button(key, dir, s), _cue_icon(key, dir, s)]
		for k in items.size():
			var c: Control = items[k]
			if k == 0:
				c.name = "Button"
			c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(c)
		cue_box.add_child(row)
	cue_a = minf(1.0, cue_a + delta * 4.0) if key != "" else maxf(0.0, cue_a - delta * 2.5)
	var rw := cue_box.get_node_or_null("Row") as Control
	cue_box.visible = cue_a > 0.01 and rw != null
	if not cue_box.visible:
		if cue_a <= 0.01:
			cue_sig = ""
		return
	rw.size = rw.get_combined_minimum_size()
	var k2 := absf(sin(Time.get_ticks_msec() * 0.004))
	var at := Vector2(size.x * 0.5, size.y * 0.84)
	cue_box.position = at - Vector2(rw.size.x * 0.5, rw.size.y + 10.0 * k2)
	rw.position = Vector2.ZERO
	cue_box.modulate = Color(1.0 + 0.3 * k2, 1.0 + 0.3 * k2, 1.0 + 0.3 * k2, cue_a * (0.8 + 0.2 * k2))
	var btn := rw.get_node_or_null("Button") as Control
	var glow2 := cue_box.get_node_or_null("Glow") as CueGlow
	if btn != null:
		btn.pivot_offset = btn.size * 0.5
		btn.scale = Vector2.ONE * (1.0 + 0.15 * k2)
		if glow2 != null:
			glow2.position = btn.position + btn.size * 0.5
			glow2.r = btn.size.y * 0.75 * (1.0 + 0.2 * k2)
			glow2.a = cue_a
			glow2.queue_redraw()
