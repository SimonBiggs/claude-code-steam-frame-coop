extends Control
## Simple mode picture cue (visual teaching, no words): low in one player's view, a pulsing glowing
## pad button in that player's own controls plus a picture of what to do. main.gd calls set_cue()
## every frame with a key ("" = none) and a builder that makes the row (the first item pulses and
## glows). A new cue fades in; no cue fades out. Also: EdgeArrow (a big glowing arrow at the view's
## edge pointing the way to the goal when it's off screen) and the little pictures (the practice
## ring, the goal hole, a tilting table).

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


## A soft dark pill behind the row, so the pictures stand out on the bright board.
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


## A key cap with an arrow on it (instead of a letter).
static func arrow_key(dir: String, s: float) -> Control:
	var g := UiKit.glyph("KEY", s)
	(g.get_child(0) as Label).text = ""
	var ic := UiKit.icon("arrow_" + dir, Color.WHITE, 26.0 * s)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.add_child(ic)
	return g


## The practice ring: a glowing yellow hoop lying on the floor.
class RingIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var c := size * 0.5
		var k := absf(sin(Time.get_ticks_msec() * 0.006))
		for i in 3:
			draw_set_transform(c, 0.0, Vector2(1.0, 0.55))
			draw_arc(Vector2.ZERO, h * (0.42 + 0.06 * i) + h * 0.03 * k, 0.0, TAU, 28,
				Color(1.0, 0.95, 0.45, 0.9 - 0.3 * i), maxf(2.0, h * (0.1 - 0.03 * i)), true)
		draw_set_transform(Vector2.ZERO)

	func _process(_delta: float) -> void:
		queue_redraw()


## The goal: a dark hole with a glowing green ring round it and a marble just about to drop in.
class GoalIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var c := size * 0.5 + Vector2(0, h * 0.12)
		draw_set_transform(c, 0.0, Vector2(1.0, 0.55))
		draw_circle(Vector2.ZERO, h * 0.4, Color(0.05, 0.08, 0.06))
		draw_arc(Vector2.ZERO, h * 0.44, 0.0, TAU, 28, Color(0.4, 1.0, 0.5), maxf(3.0, h * 0.09), true)
		draw_set_transform(Vector2.ZERO)
		var k := fmod(Time.get_ticks_msec() * 0.0008, 1.0)
		var m := c + Vector2(-h * 0.5 * (1.0 - k), -h * 0.3 * (1.0 - k) - h * 0.05)
		draw_circle(m, h * 0.13, Color(1.0, 0.4, 0.35, minf(1.0, (1.0 - k) * 3.0)))
		draw_circle(m + Vector2(-h * 0.04, -h * 0.04), h * 0.04, Color(1.0, 0.85, 0.8, minf(1.0, (1.0 - k) * 3.0)))

	func _process(_delta: float) -> void:
		queue_redraw()


## A table top seen from the side, rocking one way and the other, with a marble rolling on it.
class TiltIcon extends Control:
	var dir := 1.0  # which way it tips (1 = right side down)

	func _draw() -> void:
		var h := minf(size.x, size.y)
		var c := size * 0.5 + Vector2(0, h * 0.1)
		var k := sin(Time.get_ticks_msec() * 0.004)
		var ang := 0.28 * dir * (0.6 + 0.4 * k)
		var half := Vector2(cos(ang), sin(ang)) * h * 0.6
		draw_line(c - half, c + half, Color(0.75, 0.55, 0.32), maxf(4.0, h * 0.12), true)
		draw_line(c, c + Vector2(0, h * 0.4), Color(0.45, 0.32, 0.2), maxf(3.0, h * 0.08), true)
		var along := 0.45 * dir * (0.4 + 0.6 * absf(k))
		var up := Vector2(-sin(ang), cos(ang)) * -h * 0.16
		draw_circle(c + half * along + up, h * 0.12, Color(1.0, 0.4, 0.35))

	func _process(_delta: float) -> void:
		queue_redraw()


static func _sized(c: Control, px: Vector2) -> Control:
	c.custom_minimum_size = px
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func ring_icon(px: float) -> Control:
	return _sized(RingIcon.new(), Vector2(px * 1.3, px))


static func goal_icon(px: float) -> Control:
	return _sized(GoalIcon.new(), Vector2(px * 1.3, px))


static func tilt_icon(px: float, dir: float) -> Control:
	var t := TiltIcon.new()
	t.dir = dir
	return _sized(t, Vector2(px * 1.4, px))


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
			draw_circle(at, r * (1.0 + 0.35 * i), Color(0.6, 1.0, 0.65, 0.12 * (1.0 - 0.3 * i)))
		var tip := at + d * r
		var pts := PackedVector2Array([tip, at - d * r * 0.2 + side * r * 0.75, at - d * r * 0.2 + side * r * 0.25,
			at - d * r * 0.9 + side * r * 0.25, at - d * r * 0.9 - side * r * 0.25, at - d * r * 0.2 - side * r * 0.25,
			at - d * r * 0.2 - side * r * 0.75])
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_colored_polygon(pts, Color(0.45, 1.0, 0.55, 0.75 + 0.25 * k))
		draw_polyline(outline, Color(0.05, 0.25, 0.08, 0.8), maxf(2.0, 3.0 * ui), true)
