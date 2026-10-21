extends Control
## SIMPLE_MODE picture cue (visual teaching, no words) for ONE TV seat on the shared TV view: a pulsing
## glowing pad button in that player's own controls (UiKit.glyph: A / SPACE, STICK / WASD) plus a
## little picture of what to do, on a soft dark pill with a rim in the player's colour (so everyone can
## see whose cue it is). hud.gd makes one per TV seat when the HUD is built and calls show_cue() every
## frame with a key ("" = none). Rows are built ONCE per key (add_row) and only shown / hidden after
## that: no nodes, materials or style boxes are made while playing. A new cue fades in, no cue fades
## out. Also the little pictures (a die, a coin dropping on a runner, a kart, a balloon), the pulsing
## A + plus + person join row and the glowing 3D arrow (make_arrow) used on the board and in VR.

const UiKit := preload("res://core/ui_kit.gd")

var key := ""          ## the cue showing now ("" = none, fading out)
var a := 0.0           ## fade
var s := 1.0           ## the scale the rows were built at
var at := Vector2(-1.0, -1.0)  ## centre-bottom point in the parent the row sits on (x < 0: middle, y < 0: 88% down)
var shrink := 1.0      ## extra scale when several cues share the view
var rows := {}         ## key -> Control (built once)
var shown := {}        ## bots: every key this cue has shown
var color := Color(1.0, 0.9, 0.5)  ## the player's colour (the pill's rim)
var _anim := {}        ## key -> Array of Controls that animate (redrawn only while showing)
var _row: Control
var _back: Backing
var _glow: CueGlow


## The soft halo behind the cue's first item.
class CueGlow extends Control:
	var r := 30.0
	var a := 1.0

	func _draw() -> void:
		for i in 3:
			draw_circle(Vector2.ZERO, r * (1.0 + 0.35 * i), Color(1.0, 0.9, 0.6, 0.17 * a * (1.0 - 0.3 * i)))


## A soft dark pill behind the row (rim in the player's colour), so the pictures stand out on the island.
class Backing extends Control:
	var sb: StyleBoxFlat

	func _init() -> void:
		sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.07, 0.14, 0.62)
		sb.set_border_width_all(4)

	func _draw() -> void:
		sb.set_corner_radius_all(int(size.y * 0.5))
		draw_style_box(sb, Rect2(Vector2.ZERO, size))


func _ready() -> void:
	name = "Cue"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back = Backing.new()
	_back.name = "Back"
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_back)
	_glow = CueGlow.new()
	_glow.name = "Glow"
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glow)
	visible = false


## The scale rows should be built at for this view (0 until the view has a size).
func want_scale() -> float:
	var p := get_parent() as Control
	if p == null or p.size.x < 2.0:
		return 0.0
	return snappedf(clampf(2.2 * UiKit.scale_for_size(p.size), 1.0, 2.6), 0.1)


## Drop every row (the player's controls or the view's size changed): they're built again once.
func clear_rows() -> void:
	for k in rows:
		var r: Control = rows[k]
		remove_child(r)
		r.queue_free()
	rows.clear()
	_anim.clear()
	_row = null
	key = ""
	a = 0.0
	visible = false


## Build the row for `k` once: items (Controls) with the button first; `anim` are the ones that move.
func add_row(k: String, items: Array, anim: Array = []) -> void:
	if rows.has(k):
		return
	var row := HBoxContainer.new()
	row.name = "Row_" + k
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(10 * s))
	for i in items.size():
		var c: Control = items[i]
		if i == 0:
			c.name = "Button"
		c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(c)
	row.visible = false
	add_child(row)
	rows[k] = row
	_anim[k] = anim


## The row's size once shown (scaled), for laying several cues out.
func row_size() -> Vector2:
	if _row == null:
		return Vector2.ZERO
	return _row.get_combined_minimum_size() * shrink


## Load-time warm up: every row drawn once, almost invisible (fonts / glyph panels are ready then).
func warm(on: bool) -> void:
	for k in rows:
		(rows[k] as Control).visible = on
	visible = on
	modulate = Color(1, 1, 1, 0.02 if on else 1.0)
	if not on:
		_row = null
		key = ""
		a = 0.0


## Every frame: show the row for `k` ("" = none) with the pulse and glow.
func show_cue(k: String, delta: float) -> void:
	if k != "" and not rows.has(k):
		k = ""
	if k != "" and k != key:
		if _row != null:
			_row.visible = false
		_row = rows[k]
		_row.visible = true
		a = 0.0  # a new cue fades in
		shown[k] = true
	key = k
	a = minf(1.0, a + delta * 4.0) if k != "" else maxf(0.0, a - delta * 2.5)
	visible = a > 0.01 and _row != null
	if not visible:
		return
	var p := get_parent() as Control
	var ps: Vector2 = p.size if p != null else Vector2(1920, 1080)
	var rs := _row.get_combined_minimum_size()
	if _row.size != rs:
		_row.size = rs
	var k2 := absf(sin(Time.get_ticks_msec() * 0.004))
	var cx := at.x if at.x >= 0.0 else ps.x * 0.5
	var by := at.y if at.y >= 0.0 else ps.y * 0.88
	scale = Vector2.ONE * shrink
	position = Vector2(cx - rs.x * 0.5 * shrink, by - (rs.y + 8.0 * k2) * shrink)
	_row.position = Vector2.ZERO
	var pad := Vector2(18.0, 10.0) * s
	_back.position = -pad
	if _back.size != rs + pad * 2.0 or _back.sb.border_color != color:
		_back.size = rs + pad * 2.0
		_back.sb.border_color = color
		_back.queue_redraw()
	modulate = Color(1.0 + 0.3 * k2, 1.0 + 0.3 * k2, 1.0 + 0.3 * k2, a * (0.8 + 0.2 * k2))
	var btn := _row.get_node_or_null("Button") as Control
	if btn != null:
		btn.pivot_offset = btn.size * 0.5
		btn.scale = Vector2.ONE * (1.0 + 0.15 * k2)
		_glow.position = btn.position + btn.size * 0.5
		_glow.r = btn.size.y * 0.75 * (1.0 + 0.2 * k2)
		_glow.a = a
		_glow.queue_redraw()
	for c in _anim.get(key, []):
		(c as Control).queue_redraw()


# --- Little pictures (drawn, no textures; animated ones are redrawn by show_cue) -----------------

## A white die tumbling a little, with pips (hit the dice block).
class DieIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var c := size * 0.5
		var ang := 0.25 * sin(Time.get_ticks_msec() * 0.005)
		draw_set_transform(c, ang, Vector2.ONE)
		var r := Rect2(Vector2(-h * 0.4, -h * 0.4), Vector2(h * 0.8, h * 0.8))
		draw_rect(r, Color(1.0, 0.97, 0.9))
		draw_rect(r, Color(1.0, 0.75, 0.25), false, maxf(2.0, h * 0.06))
		for pp in [Vector2(-0.2, -0.2), Vector2(0.2, -0.2), Vector2(0, 0), Vector2(-0.2, 0.2), Vector2(0.2, 0.2)]:
			draw_circle((pp as Vector2) * h, h * 0.075, Color(0.15, 0.2, 0.45))
		draw_set_transform(Vector2.ZERO)


## A runner in the player's colour sliding side to side while a gold coin drops on them (catch it).
class CatchIcon extends Control:
	var color := Color(1.0, 0.75, 0.25)

	func _draw() -> void:
		var h := minf(size.x, size.y)
		var t := Time.get_ticks_msec() * 0.001
		var k := fmod(t * 0.9, 1.0)
		var x := size.x * 0.5 + sin(t * 2.0) * size.x * 0.12
		var body := Vector2(x, size.y - h * 0.22)
		draw_circle(body, h * 0.17, color)
		draw_circle(body + Vector2(0, -h * 0.24), h * 0.11, color.lightened(0.35))
		var coin := Vector2(size.x * 0.5, lerpf(h * 0.1, h * 0.55, k))
		draw_circle(coin, h * 0.12, Color(1.0, 0.8, 0.25, 1.0 - k * 0.3))
		draw_circle(coin, h * 0.07, Color(1.0, 0.93, 0.55, 1.0 - k * 0.3))


## A little kart zooming right with speed lines (mash to go fast).
class KartIcon extends Control:
	var color := Color(1.0, 0.75, 0.25)

	func _draw() -> void:
		var h := minf(size.x, size.y)
		var t := Time.get_ticks_msec() * 0.001
		var k := fmod(t * 1.6, 1.0)
		var at := Vector2(size.x * 0.58 + sin(t * 9.0) * h * 0.03, size.y * 0.55)
		for i in 3:
			var y := at.y - h * 0.2 + i * h * 0.16
			var x0 := at.x - h * 0.6 - (k * h * 0.3) - i * h * 0.05
			draw_line(Vector2(x0, y), Vector2(x0 + h * 0.25, y), Color(1, 1, 1, 0.7), maxf(2.0, h * 0.05))
		draw_rect(Rect2(at + Vector2(-h * 0.4, -h * 0.16), Vector2(h * 0.8, h * 0.26)), color)
		draw_circle(at + Vector2(-h * 0.05, -h * 0.22), h * 0.12, color.lightened(0.35))
		for wx in [-0.26, 0.26]:
			draw_circle(at + Vector2(h * wx, h * 0.14), h * 0.12, Color(0.15, 0.15, 0.2))
			draw_circle(at + Vector2(h * wx, h * 0.14), h * 0.05, Color(0.8, 0.8, 0.85))


## A balloon bobbing on its string (jump and pop it).
class BalloonIcon extends Control:
	var color := Color(1.0, 0.4, 0.45)

	func _draw() -> void:
		var h := minf(size.x, size.y)
		var t := Time.get_ticks_msec() * 0.001
		var c := Vector2(size.x * 0.5, size.y * 0.4 + sin(t * 3.0) * h * 0.04)
		draw_set_transform(c, 0.0, Vector2(0.82, 1.0))
		draw_circle(Vector2.ZERO, h * 0.3, color)
		draw_circle(Vector2(-h * 0.1, -h * 0.1), h * 0.08, color.lightened(0.5))
		draw_set_transform(Vector2.ZERO)
		var knot := c + Vector2(0, h * 0.3)
		draw_line(knot, knot + Vector2(sin(t * 3.0) * h * 0.05, h * 0.3), Color(1, 1, 1, 0.8), maxf(1.5, h * 0.025))


static func _sized(c: Control, px: Vector2) -> Control:
	c.custom_minimum_size = px
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func die_icon(px: float) -> Control:
	return _sized(DieIcon.new(), Vector2(px, px))


static func catch_icon(px: float, col: Color) -> Control:
	var c := CatchIcon.new()
	c.color = col
	return _sized(c, Vector2(px * 1.2, px))


static func kart_icon(px: float, col: Color) -> Control:
	var c := KartIcon.new()
	c.color = col
	return _sized(c, Vector2(px * 1.5, px))


static func balloon_icon(px: float) -> Control:
	return _sized(BalloonIcon.new(), Vector2(px * 0.9, px))


## The pulsing A + plus + person (a spare controller can join), built once.
static func join_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "JoinCue"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(UiKit.glyph("A", 1.4))
	row.add_child(UiKit.icon("plus", Color(1.0, 0.9, 0.6), 34.0))
	row.add_child(UiKit.icon("person", Color(1.0, 0.9, 0.6), 58.0))
	for c in row.get_children():
		(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return row


# --- The glowing 3D arrow ------------------------------------------------------------------------------

## A glowing arrow pointing down (origin at the tip), `length` long, sharing `mat`.
static func make_arrow(mat: Material, length: float) -> Node3D:
	var root := Node3D.new()
	var hl := length * 0.45
	var head := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = length * 0.3
	cm.bottom_radius = 0.0
	cm.height = hl
	cm.radial_segments = 12
	cm.rings = 1
	head.mesh = cm
	head.position.y = hl * 0.5
	var shaft := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = length * 0.1
	sm.bottom_radius = length * 0.1
	sm.height = length - hl
	sm.radial_segments = 8
	sm.rings = 1
	shaft.mesh = sm
	shaft.position.y = hl + (length - hl) * 0.5
	for m in [head, shaft]:
		(m as MeshInstance3D).material_override = mat
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(m)
	return root
