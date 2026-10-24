extends Control
## Simple mode picture cue (visual teaching, no words): low in one player's view, a pulsing glowing
## pad button in that player's own controls plus an icon for what to do. The owner calls set_cue()
## every frame with a key ("" = none) and a builder that makes the row's controls (the first one is
## the button, which pulses and glows). A new cue fades in; no cue fades out.

const UiKit := preload("res://core/ui_kit.gd")

var key := ""      # the cue showing now ("" = none, fading out)
var a := 0.0       # fade
var sig := ""
var s := 1.0       # UI scale for this view


## The soft halo behind the cue's button.
class CueGlow extends Control:
	var r := 30.0
	var a := 1.0

	func _draw() -> void:
		for i in 3:
			draw_circle(Vector2.ZERO, r * (1.0 + 0.35 * i), Color(1.0, 0.95, 0.6, 0.17 * a * (1.0 - 0.3 * i)))


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
	s = clampf(2.6 * UiKit.scale_for_size(vs), 1.2, 3.2)
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
	var at := Vector2(vs.x * 0.5, vs.y * 0.86)
	position = at - Vector2(rw.size.x * 0.5, rw.size.y + 10.0 * k2)
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


## A daisy (pink petals, yellow middle): "fly into the flower".
class FlowerIcon extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		for i in 6:
			var ang := TAU * i / 6.0
			var p := c + Vector2(cos(ang), sin(ang)) * r * 0.55
			draw_circle(p, r * 0.36, Color(0.15, 0.1, 0.05, 0.6))
			draw_circle(p, r * 0.3, Color(1.0, 0.75, 0.9))
		draw_circle(c, r * 0.34, Color(0.15, 0.1, 0.05, 0.6))
		draw_circle(c, r * 0.28, Color(1.0, 0.82, 0.15))


## A honeycomb cell with a honey drop: "take the pollen to the hive".
class HiveIcon extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.48
		var pts := PackedVector2Array()
		for i in 6:
			var ang := TAU * i / 6.0 + PI / 6.0
			pts.append(c + Vector2(cos(ang), sin(ang)) * r)
		draw_colored_polygon(pts, Color(0.95, 0.65, 0.12))
		pts.append(pts[0])
		draw_polyline(pts, Color(0.45, 0.25, 0.05), maxf(2.0, r * 0.12))
		draw_circle(c + Vector2(0, r * 0.12), r * 0.3, Color(1.0, 0.88, 0.35))
		draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.26, r * 0.02), c + Vector2(r * 0.26, r * 0.02),
			c + Vector2(0, -r * 0.45)]), Color(1.0, 0.88, 0.35))


static func flower_icon(px: float) -> Control:
	var ic := FlowerIcon.new()
	ic.custom_minimum_size = Vector2(px, px)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic


static func hive_icon(px: float) -> Control:
	var ic := HiveIcon.new()
	ic.custom_minimum_size = Vector2(px, px)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic
