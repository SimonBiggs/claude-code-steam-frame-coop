extends Control
## Picture cue (visual teaching, no words): low in one player's view, a pulsing glowing button in that
## player's own controls plus a picture of what to do. hud.gd calls set_cue() every frame with a key
## ("" = none) and a builder that makes the row (the first item pulses and glows). A new cue fades in;
## no cue fades out. Also: Pointer (a big glowing arrow at the view's edge pointing the way to something
## off screen, or bouncing over it when it's in view) and the little pictures (a torch, a critter, a
## cardboard box, the jail bell, a squeak, a sniffing nose, the moon). Same idea as rocket_workshop/cue.gd.

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


## k: the cue key ("" = none). extra: anything that changes the row (controls, colour).
## build: Callable(s: float) -> Array of Controls (button first).
func set_cue(k: String, extra: String, build: Callable, delta: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	s = clampf(2.2 * UiKit.scale_for_size(vs), 0.8, 2.6)
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


## A torch: a grey handle, a lens and a warm beam going right.
class TorchIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var y := size.y * 0.5
		var x0 := size.x * 0.5 - h * 0.7
		var beam := PackedVector2Array([Vector2(x0 + h * 0.55, y - h * 0.1), Vector2(x0 + h * 1.45, y - h * 0.45),
			Vector2(x0 + h * 1.45, y + h * 0.45), Vector2(x0 + h * 0.55, y + h * 0.1)])
		var k := absf(sin(Time.get_ticks_msec() * 0.006))
		draw_colored_polygon(beam, Color(1.0, 0.95, 0.55, 0.45 + 0.25 * k))
		draw_rect(Rect2(Vector2(x0, y - h * 0.1), Vector2(h * 0.42, h * 0.2)), Color(0.45, 0.48, 0.55))
		draw_rect(Rect2(Vector2(x0 + h * 0.38, y - h * 0.17), Vector2(h * 0.18, h * 0.34)), Color(0.6, 0.63, 0.7))
		draw_rect(Rect2(Vector2(x0 + h * 0.52, y - h * 0.15), Vector2(h * 0.05, h * 0.3)), Color(1.0, 0.97, 0.75))
		draw_rect(Rect2(Vector2(x0, y - h * 0.1), Vector2(h * 0.56, h * 0.2)), Color(0.1, 0.1, 0.15, 0.8), false, maxf(2.0, h * 0.03))

	func _process(_delta: float) -> void:
		queue_redraw()


## A hider critter: a round body in the player's colour with two big eyes.
class CritterIcon extends Control:
	var col := Color(0.5, 0.85, 1.0)
	var glow_eyes := false

	func _draw() -> void:
		var h := minf(size.x, size.y)
		var c := size * 0.5 + Vector2(0, h * 0.06)
		var r := h * 0.38
		draw_circle(c, r, col)
		draw_arc(c, r, 0.0, TAU, 24, Color(0.1, 0.08, 0.1, 0.8), maxf(2.0, h * 0.04), true)
		for sx in [-1.0, 1.0]:
			var e: Vector2 = c + Vector2(sx * r * 0.38, -r * 0.2)
			if glow_eyes:
				draw_circle(e, r * 0.34, Color(1.0, 1.0, 0.5, 0.35))
			draw_circle(e, r * 0.22, Color.WHITE if not glow_eyes else Color(1.0, 1.0, 0.6))
			draw_circle(e + Vector2(0, r * 0.04), r * 0.1, Color(0.05, 0.05, 0.1))


## A cardboard box (one of the things a hider can turn into).
class BoxIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var r := Rect2(size * 0.5 - Vector2(h * 0.4, h * 0.3), Vector2(h * 0.8, h * 0.66))
		draw_rect(r, Color(0.78, 0.58, 0.34))
		draw_rect(Rect2(r.position, Vector2(r.size.x, h * 0.12)), Color(0.66, 0.47, 0.26))
		draw_rect(Rect2(r.position + Vector2(r.size.x * 0.42, 0), Vector2(r.size.x * 0.16, r.size.y * 0.45)), Color(0.9, 0.85, 0.7))
		draw_rect(r, Color(0.25, 0.15, 0.05, 0.85), false, maxf(2.0, h * 0.04))


## The golden jail bell.
class BellIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var c := size * 0.5
		var ring := Time.get_ticks_msec() * 0.008
		var tilt := sin(ring) * 0.25
		var pts := PackedVector2Array()
		var outline := [Vector2(-0.12, -0.42), Vector2(0.12, -0.42), Vector2(0.24, -0.2), Vector2(0.3, 0.12),
			Vector2(0.42, 0.28), Vector2(-0.42, 0.28), Vector2(-0.3, 0.12), Vector2(-0.24, -0.2)]
		for v in outline:
			pts.append(c + (v as Vector2).rotated(tilt) * h)
		draw_colored_polygon(pts, Color(1.0, 0.8, 0.2))
		var line := pts.duplicate()
		line.append(pts[0])
		draw_polyline(line, Color(0.35, 0.22, 0.02, 0.9), maxf(2.0, h * 0.04), true)
		draw_circle(c + Vector2(0, h * 0.36).rotated(tilt * 1.6), h * 0.08, Color(0.85, 0.6, 0.1))
		draw_circle(c + Vector2(0, -h * 0.46).rotated(tilt), h * 0.06, Color(0.85, 0.6, 0.1))
		var k := absf(sin(ring))
		for side in [-1.0, 1.0]:
			draw_arc(c, h * (0.5 + 0.04 * k), PI * 0.5 - side * PI * 0.5 - 0.35, PI * 0.5 - side * PI * 0.5 + 0.35, 6,
				Color(1.0, 0.95, 0.6, 0.8), maxf(2.0, h * 0.04), true)

	func _process(_delta: float) -> void:
		queue_redraw()


## A squeak: a little critter mouth with sound waves going out.
class SqueakIcon extends Control:
	var col := Color(1.0, 0.8, 0.35)

	func _draw() -> void:
		var h := minf(size.x, size.y)
		var c := Vector2(h * 0.36, size.y * 0.5)
		var r := h * 0.3
		draw_circle(c, r, col)
		draw_circle(c + Vector2(r * 0.35, r * 0.15), r * 0.28, Color(0.55, 0.12, 0.15))
		draw_circle(c + Vector2(-r * 0.15, -r * 0.35), r * 0.13, Color(0.05, 0.05, 0.1))
		var k := absf(sin(Time.get_ticks_msec() * 0.01))
		for i in 3:
			var rr := r * (1.1 + 0.4 * i) + h * 0.03 * k
			draw_arc(c, rr, -0.6, 0.6, 8, Color(1.0, 0.95, 0.6, 0.9 - 0.22 * i), maxf(2.0, h * 0.05), true)

	func _process(_delta: float) -> void:
		queue_redraw()


## A nose sniffing: a big pink nose with wavy smell lines going up into it.
class NoseIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var c := size * 0.5 + Vector2(-h * 0.12, h * 0.1)
		var nose := PackedVector2Array([c + Vector2(-h * 0.06, -h * 0.36), c + Vector2(h * 0.08, -h * 0.36),
			c + Vector2(h * 0.26, h * 0.12), c + Vector2(h * 0.14, h * 0.24), c + Vector2(-h * 0.2, h * 0.24), c + Vector2(-h * 0.26, h * 0.12)])
		draw_colored_polygon(nose, Color(1.0, 0.7, 0.62))
		var line := nose.duplicate()
		line.append(nose[0])
		draw_polyline(line, Color(0.35, 0.15, 0.1, 0.9), maxf(2.0, h * 0.04), true)
		draw_circle(c + Vector2(-h * 0.1, h * 0.17), h * 0.045, Color(0.3, 0.1, 0.08))
		draw_circle(c + Vector2(h * 0.08, h * 0.17), h * 0.045, Color(0.3, 0.1, 0.08))
		var t := Time.get_ticks_msec() * 0.006
		for i in 3:
			var pts := PackedVector2Array()
			for j in 7:
				var f := float(j) / 6.0
				var x := c.x + h * 0.3 + h * 0.12 * i + sin(t + f * 6.0 + i) * h * 0.04
				pts.append(Vector2(x, c.y + h * 0.35 - f * h * 0.6))
			draw_polyline(pts, Color(0.75, 1.0, 0.7, 0.85), maxf(2.0, h * 0.04), true)

	func _process(_delta: float) -> void:
		queue_redraw()


## A crescent moon (night round).
class MoonIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var c := size * 0.5
		draw_circle(c, h * 0.4, Color(1.0, 0.95, 0.65))
		draw_circle(c + Vector2(h * 0.18, -h * 0.1), h * 0.34, Color(0.08, 0.1, 0.25))


static func _sized(c: Control, px: Vector2) -> Control:
	c.custom_minimum_size = px
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func torch_icon(px: float) -> Control:
	return _sized(TorchIcon.new(), Vector2(px * 1.5, px))


static func critter_icon(px: float, col: Color, glow_eyes: bool = false) -> Control:
	var c := CritterIcon.new()
	c.col = col
	c.glow_eyes = glow_eyes
	return _sized(c, Vector2(px, px))


static func box_icon(px: float) -> Control:
	return _sized(BoxIcon.new(), Vector2(px, px))


static func bell_icon(px: float) -> Control:
	return _sized(BellIcon.new(), Vector2(px, px))


static func squeak_icon(px: float, col: Color) -> Control:
	var c := SqueakIcon.new()
	c.col = col
	return _sized(c, Vector2(px * 1.4, px))


static func nose_icon(px: float) -> Control:
	return _sized(NoseIcon.new(), Vector2(px * 1.2, px))


static func moon_icon(px: float) -> Control:
	return _sized(MoonIcon.new(), Vector2(px, px))


## A key cap with an arrow on it (instead of a letter).
static func arrow_key(dir: String, sc: float) -> Control:
	var g := UiKit.glyph("KEY", sc)
	(g.get_child(0) as Label).text = ""
	var ic := UiKit.icon("arrow_" + dir, Color.WHITE, 26.0 * sc)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.add_child(ic)
	return g


## A big glowing arrow showing the way to `target` (when on is true): at the view's edge pointing round
## when it's off screen, bouncing just above it (pointing down) when it's in view.
class Pointer extends Control:
	var cam: Camera3D
	var target := Vector3.ZERO
	var on := false
	var col := Color(1.0, 0.8, 0.3)

	func _ready() -> void:
		name = "Pointer"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _process(_delta: float) -> void:
		queue_redraw()

	func in_view() -> bool:
		if cam == null or not is_instance_valid(cam) or cam.is_position_behind(target):
			return false
		var sp := cam.unproject_position(target)
		var mg := size * 0.1
		return sp.x > mg.x and sp.y > mg.y and sp.x < size.x - mg.x and sp.y < size.y - mg.y

	func _draw() -> void:
		if not on or cam == null or not is_instance_valid(cam):
			return
		var ui := clampf(minf(size.x, size.y) / 700.0, 0.45, 1.6)
		var k := absf(sin(Time.get_ticks_msec() * 0.005))
		var at: Vector2
		var d: Vector2
		if in_view():
			d = Vector2.DOWN
			at = cam.unproject_position(target) - Vector2(0, (70.0 + 18.0 * k) * ui)
		else:
			var loc: Vector3 = cam.global_basis.inverse() * (target - cam.global_position)
			d = Vector2(loc.x, -loc.y)
			if loc.z > 0.0:
				d = Vector2(1.0 if loc.x >= 0.0 else -1.0, 0.0)  # behind: point round the short way
			if d.length() < 0.001:
				d = Vector2.RIGHT
			d = d.normalized()
			at = size / 2.0 + d * (minf(size.x, size.y) * 0.36 + 14.0 * k * ui)
		var r := (40.0 + 8.0 * k) * ui
		var side := Vector2(-d.y, d.x)
		for i in 3:
			draw_circle(at, r * (1.0 + 0.35 * i), Color(col.r, col.g, col.b, 0.12 * (1.0 - 0.3 * i)))
		var tip := at + d * r
		var pts := PackedVector2Array([tip, at - d * r * 0.2 + side * r * 0.75, at - d * r * 0.2 + side * r * 0.25,
			at - d * r * 0.9 + side * r * 0.25, at - d * r * 0.9 - side * r * 0.25, at - d * r * 0.2 - side * r * 0.25,
			at - d * r * 0.2 - side * r * 0.75])
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.75 + 0.25 * k))
		draw_polyline(outline, Color(0.3, 0.2, 0.05, 0.8), maxf(2.0, 3.0 * ui), true)
