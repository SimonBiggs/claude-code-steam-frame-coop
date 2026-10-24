extends Control
## Simple mode picture cue (visual teaching, no words): low in one crew member's view, a pulsing glowing
## pad button in that player's own controls (or a talking face) plus a picture of what to do. main.gd
## calls set_cue() every frame with a key ("" = none) and a builder that makes the row (the first item
## pulses and glows). A new cue fades in; no cue fades out. Also: EdgeArrow (a big glowing arrow at the
## view's edge pointing the way to an off-screen blueprint board) and the little pictures (a blueprint
## board, a talking face, the launch lever).

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


func _ready() -> void:
	name = "Cue"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow := CueGlow.new()
	glow.name = "Glow"
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	visible = false


## k: the cue key ("" = none). extra: anything that changes the row (controls, direction).
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
	var at := Vector2(vs.x * 0.5, vs.y * 0.88)
	position = at - Vector2(rw.size.x * 0.5, rw.size.y + 8.0 * k2)
	rw.position = Vector2.ZERO
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


## A key cap with an arrow on it (instead of a letter).
static func arrow_key(dir: String, s: float) -> Control:
	var g := UiKit.glyph("KEY", s)
	(g.get_child(0) as Label).text = ""
	var ic := UiKit.icon("arrow_" + dir, Color.WHITE, 26.0 * s)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.add_child(ic)
	return g


## A blueprint board on the wall: a wooden frame, blue paper and a few coloured blobs.
class BoardIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var r := Rect2(size * 0.5 - Vector2(h * 0.62, h * 0.42), Vector2(h * 1.24, h * 0.84))
		draw_rect(r, Color(0.55, 0.36, 0.22))
		var inner := r.grow(-h * 0.07)
		draw_rect(inner, Color(0.16, 0.3, 0.62))  # the blueprint paper
		var cols := [Color(1.0, 0.3, 0.3), Color(0.3, 0.6, 1.0), Color(1.0, 0.85, 0.2)]
		for i in 3:
			draw_circle(inner.position + Vector2(inner.size.x * (0.22 + 0.28 * i), inner.size.y * 0.5), h * 0.11, cols[i])
		draw_rect(r, Color(0.2, 0.12, 0.05, 0.8), false, maxf(2.0, h * 0.04))


## A face that talks: a round head with an open mouth and sound waves going right ("tell the pilot").
class TalkIcon extends Control:
	var col := Color(1.0, 0.85, 0.65)

	func _draw() -> void:
		var h := minf(size.x, size.y)
		var c := Vector2(h * 0.42, size.y * 0.5)
		var r := h * 0.36
		var ink := Color(0.15, 0.08, 0.1)
		draw_circle(c, r, col)
		draw_arc(c, r, 0.0, TAU, 24, Color(0.2, 0.1, 0.05, 0.8), maxf(2.0, h * 0.04), true)
		draw_circle(c + Vector2(-r * 0.3, -r * 0.25), r * 0.12, ink)
		draw_circle(c + Vector2(r * 0.3, -r * 0.25), r * 0.12, ink)
		draw_circle(c + Vector2(0, r * 0.35), r * 0.22, Color(0.55, 0.12, 0.15))
		var k := absf(sin(Time.get_ticks_msec() * 0.008))
		for i in 3:
			var rr := r * (0.95 + 0.35 * i) + h * 0.03 * k
			draw_arc(c, rr, -0.55, 0.55, 8, Color(1.0, 0.95, 0.6, 0.9 - 0.2 * i), maxf(2.0, h * 0.05), true)

	func _process(_delta: float) -> void:
		queue_redraw()  # the sound waves wobble


## The big launch lever: a box base, a stick leaning over and a red ball on top.
class LeverIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var base := Rect2(Vector2(size.x * 0.5 - h * 0.32, size.y * 0.5 + h * 0.22), Vector2(h * 0.64, h * 0.2))
		var pivot := Vector2(size.x * 0.5, size.y * 0.5 + h * 0.24)
		var top := pivot + Vector2(h * 0.26, -h * 0.58)
		draw_line(pivot, top, Color(0.75, 0.78, 0.85), maxf(3.0, h * 0.09), true)
		draw_rect(base, Color(0.35, 0.38, 0.45))
		draw_rect(base, Color(0.1, 0.1, 0.15, 0.8), false, maxf(2.0, h * 0.03))
		draw_circle(top, h * 0.14, Color(1.0, 0.25, 0.2))
		draw_circle(top + Vector2(-h * 0.04, -h * 0.04), h * 0.04, Color(1.0, 0.7, 0.65))


static func _sized(c: Control, px: Vector2) -> Control:
	c.custom_minimum_size = px
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func board_icon(px: float) -> Control:
	return _sized(BoardIcon.new(), Vector2(px * 1.3, px))


static func talk_icon(px: float) -> Control:
	return _sized(TalkIcon.new(), Vector2(px * 1.35, px))


static func lever_icon(px: float) -> Control:
	return _sized(LeverIcon.new(), Vector2(px, px))


## A big glowing arrow at the edge of a view, pointing the way to `target` (when on is true).
class EdgeArrow extends Control:
	var cam: Camera3D
	var target := Vector3.ZERO
	var on := false

	func _ready() -> void:
		name = "EdgeArrow"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if not on or cam == null or not is_instance_valid(cam):
			return
		var loc: Vector3 = cam.global_basis.inverse() * (target - cam.global_position)
		var d := Vector2(loc.x, -loc.y)
		if loc.z > 0.0:
			d = Vector2(1.0 if loc.x >= 0.0 else -1.0, 0.0)  # behind: point round the short way
		if d.length() < 0.001:
			d = Vector2.RIGHT
		d = d.normalized()
		var ui := clampf(minf(size.x, size.y) / 700.0, 0.5, 1.6)
		var c := size / 2.0
		var k := absf(sin(Time.get_ticks_msec() * 0.005))
		var reach := minf(size.x, size.y) * 0.38
		var at := c + d * (reach + 14.0 * k * ui)
		var r := (46.0 + 10.0 * k) * ui
		var side := Vector2(-d.y, d.x)
		for i in 3:
			draw_circle(at, r * (1.0 + 0.35 * i), Color(1.0, 0.95, 0.6, 0.12 * (1.0 - 0.3 * i)))
		var tip := at + d * r
		var pts := PackedVector2Array([tip, at - d * r * 0.2 + side * r * 0.75, at - d * r * 0.2 + side * r * 0.25,
			at - d * r * 0.9 + side * r * 0.25, at - d * r * 0.9 - side * r * 0.25, at - d * r * 0.2 - side * r * 0.25,
			at - d * r * 0.2 - side * r * 0.75])
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_colored_polygon(pts, Color(1.0, 0.75, 0.3, 0.75 + 0.25 * k))
		draw_polyline(outline, Color(0.3, 0.2, 0.05, 0.8), maxf(2.0, 3.0 * ui), true)
