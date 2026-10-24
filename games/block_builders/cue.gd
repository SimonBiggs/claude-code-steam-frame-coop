extends Control
## SIMPLE_MODE picture cue (visual teaching, no words): low in one player's view, a pulsing glowing
## pad button in that player's own controls plus a picture of what to do. main.gd calls set_cue()
## every frame with a key ("" = none) and a builder that makes the row (the first item pulses and
## glows). A new cue fades in; no cue fades out. Also the little pictures: a runner hopping, a
## glowing see-through block (where the next block goes) and a mouse with its left button lit.

const UiKit := preload("res://core/ui_kit.gd")

var key := ""      # the cue showing now ("" = none, fading out)
var a := 0.0       # fade
var sig := ""
var s := 1.0       # UI scale for this view


## The soft halo behind the cue's first item.
class CueGlow extends Control:
	var r := 30.0
	var a := 1.0

	func _draw() -> void:
		for i in 3:
			draw_circle(Vector2.ZERO, r * (1.0 + 0.35 * i), Color(1.0, 0.9, 0.6, 0.17 * a * (1.0 - 0.3 * i)))


## A soft dark pill behind the row, so the pictures stand out on the bright sky.
class Backing extends Control:
	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.07, 0.14, 0.6)
		sb.set_corner_radius_all(int(size.y * 0.5))
		draw_style_box(sb, Rect2(Vector2.ZERO, size))


func _ready() -> void:
	name = "Cue"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := Backing.new()
	back.name = "Back"
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	var glow := CueGlow.new()
	glow.name = "Glow"
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	visible = false


## k: the cue key ("" = none). extra: anything that changes the row (controls).
## build: Callable(s: float) -> Array of Controls (button first).
func set_cue(k: String, extra: String, build: Callable, delta: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	s = clampf(2.6 * UiKit.scale_for_size(vs), 1.0, 3.0)
	key = k
	var full := "%s|%s|%.2f" % [k, extra, s]
	if k != "" and full != sig:
		if sig.get_slice("|", 0) != k:
			a = 0.0  # a new cue fades in
		sig = full
		var old := get_node_or_null("Row")
		if old != null:
			remove_child(old)
			old.queue_free()
		var row := HBoxContainer.new()
		row.name = "Row"
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", int(10 * s))
		var items: Array = build.call(s)
		for i in items.size():
			var c: Control = items[i]
			if i == 0:
				c.name = "Button"
			c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(c)
		add_child(row)
	a = minf(1.0, a + delta * 4.0) if k != "" else maxf(0.0, a - delta * 2.5)
	var rw := get_node_or_null("Row") as Control
	visible = a > 0.01 and rw != null
	if not visible:
		if a <= 0.01:
			sig = ""
		return
	rw.size = rw.get_combined_minimum_size()
	var k2 := absf(sin(Time.get_ticks_msec() * 0.004))
	var at := Vector2(vs.x * 0.5, vs.y * 0.9)
	position = at - Vector2(rw.size.x * 0.5, rw.size.y + 8.0 * k2)
	rw.position = Vector2.ZERO
	var back := get_node_or_null("Back") as Control
	if back != null:
		var pad := Vector2(18.0, 10.0) * s
		back.position = -pad
		back.size = rw.size + pad * 2.0
		back.queue_redraw()
	modulate = Color(1.0 + 0.3 * k2, 1.0 + 0.3 * k2, 1.0 + 0.3 * k2, a * (0.8 + 0.2 * k2))
	var btn := rw.get_node_or_null("Button") as Control
	var glow := get_node_or_null("Glow") as CueGlow
	if btn != null:
		btn.pivot_offset = btn.size * 0.5
		btn.scale = Vector2.ONE * (1.0 + 0.15 * k2)
		if glow != null:
			glow.position = btn.position + btn.size * 0.5
			glow.r = btn.size.y * 0.75 * (1.0 + 0.2 * k2)
			glow.a = a
			glow.queue_redraw()


## A little runner hopping up and down, with a shadow on the ground (jump).
class JumpIcon extends Control:
	var col := Color(1.0, 0.6, 0.4)

	func _draw() -> void:
		var h := minf(size.x, size.y)
		var k := absf(sin(Time.get_ticks_msec() * 0.005))
		var ground := Vector2(size.x * 0.5, size.y * 0.92)
		draw_set_transform(ground, 0.0, Vector2(1.0, 0.3))
		draw_circle(Vector2.ZERO, h * (0.22 - 0.08 * k), Color(0.0, 0.0, 0.0, 0.35))
		draw_set_transform(Vector2.ZERO)
		var body := ground + Vector2(0.0, -h * 0.28 - h * 0.4 * k)
		draw_circle(body, h * 0.17, col)
		draw_circle(body + Vector2(0.0, -h * 0.2), h * 0.12, col.lightened(0.25))
		draw_circle(body + Vector2(-h * 0.04, -h * 0.22), h * 0.025, Color(0.1, 0.1, 0.15))
		draw_circle(body + Vector2(h * 0.04, -h * 0.22), h * 0.025, Color(0.1, 0.1, 0.15))

	func _process(_delta: float) -> void:
		queue_redraw()


## A glowing see-through block (the hint block on the course: a block goes there).
class BlockIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
		var c := size * 0.5
		var w := h * 0.38
		var top := PackedVector2Array([c + Vector2(-w, -w * 0.45), c + Vector2(0, -w * 0.9), c + Vector2(w, -w * 0.45), c + Vector2(0, 0)])
		var left := PackedVector2Array([c + Vector2(-w, -w * 0.45), c, c + Vector2(0, w * 0.9), c + Vector2(-w, w * 0.45)])
		var right := PackedVector2Array([c, c + Vector2(w, -w * 0.45), c + Vector2(w, w * 0.45), c + Vector2(0, w * 0.9)])
		var base := Color(0.4, 0.95, 1.0)
		draw_colored_polygon(top, Color(base, 0.35 + 0.25 * k))
		draw_colored_polygon(left, Color(base.darkened(0.2), 0.3 + 0.2 * k))
		draw_colored_polygon(right, Color(base.darkened(0.35), 0.3 + 0.2 * k))
		for poly in [top, left, right]:
			var o: PackedVector2Array = poly.duplicate()
			o.append(poly[0])
			draw_polyline(o, Color(0.8, 1.0, 1.0, 0.7 + 0.3 * k), maxf(2.0, h * 0.04), true)

	func _process(_delta: float) -> void:
		queue_redraw()


## A mouse with its left button glowing (click).
class MouseIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var k := absf(sin(Time.get_ticks_msec() * 0.006))
		var w := h * 0.62
		var r := Rect2(size * 0.5 - Vector2(w * 0.5, h * 0.45), Vector2(w, h * 0.9))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.85, 0.87, 0.93)
		sb.set_corner_radius_all(int(w * 0.48))
		draw_style_box(sb, r)
		var lb := Rect2(r.position + Vector2(w * 0.08, h * 0.06), Vector2(w * 0.38, h * 0.32))
		var sl := StyleBoxFlat.new()
		sl.bg_color = Color(0.4, 1.0, 0.5).lerp(Color(1.0, 1.0, 0.6), k)
		sl.corner_radius_top_left = int(w * 0.4)
		sl.corner_radius_bottom_left = int(w * 0.06)
		sl.corner_radius_bottom_right = int(w * 0.06)
		sl.corner_radius_top_right = int(w * 0.06)
		draw_style_box(sl, lb)
		draw_line(r.position + Vector2(w * 0.5, h * 0.04), r.position + Vector2(w * 0.5, h * 0.4), Color(0.3, 0.32, 0.4), maxf(2.0, h * 0.03))

	func _process(_delta: float) -> void:
		queue_redraw()


static func _sized(c: Control, px: Vector2) -> Control:
	c.custom_minimum_size = px
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func jump_icon(px: float, col: Color) -> Control:
	var j := JumpIcon.new()
	j.col = col
	return _sized(j, Vector2(px * 0.9, px * 1.2))


static func block_icon(px: float) -> Control:
	return _sized(BlockIcon.new(), Vector2(px, px))


static func mouse_icon(px: float) -> Control:
	return _sized(MouseIcon.new(), Vector2(px * 0.8, px))
