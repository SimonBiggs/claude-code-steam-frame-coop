extends Control
## SIMPLE_MODE picture cue (visual teaching, no words): low in one TV player's view, a pulsing glowing
## pad button in that player's own controls plus a picture of what to do, on a soft dark pill.
## hud.gd adds one per view and calls show_cue() every frame with a key ("" = none). Rows are built
## ONCE per key (add_row, when the view is made) and only shown / hidden after that: no nodes,
## materials or style boxes are made while playing (Tiny Town hitches in VR, so this stays cheap).
## A new cue fades in, no cue fades out. Also the little pictures (a glowing ring, a road, a house)
## and the glowing 3D arrow (make_arrow) that bobs over the tray block / the place to build.

const UiKit := preload("res://core/ui_kit.gd")

var key := ""        ## the cue showing now ("" = none, fading out)
var a := 0.0         ## fade
var s := 1.0         ## the scale the rows were built at
var bottom := -1.0   ## y (in the parent) the row sits on; < 0 = 88% down the view
var rows := {}       ## key -> Control (built once)
var _anim := {}      ## key -> Array of Controls that animate (redrawn only while showing)
var shown := {}      ## bots: every key this cue has shown
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


## A soft dark pill behind the row, so the pictures stand out on the bright town.
class Backing extends Control:
	var sb: StyleBoxFlat

	func _init() -> void:
		sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.07, 0.14, 0.6)

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
	return snappedf(clampf(2.4 * UiKit.scale_for_size(p.size), 1.0, 2.6), 0.1)


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


func has_row(k: String) -> bool:
	return rows.has(k)


## Build the row for `k` once: items (Controls) with the button first; `anim` are the ones that move.
func add_row(k: String, items: Array, anim: Array = []) -> void:
	if rows.has(k):
		return
	var row := HBoxContainer.new()
	row.name = "Row_" + k.replace("|", "_")
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
	_row.size = _row.get_combined_minimum_size()
	var k2 := absf(sin(Time.get_ticks_msec() * 0.004))
	var by := bottom if bottom >= 0.0 else ps.y * 0.88
	position = Vector2(ps.x * 0.5 - _row.size.x * 0.5, by - _row.size.y - 8.0 * k2)
	_row.position = Vector2.ZERO
	var pad := Vector2(18.0, 10.0) * s
	_back.position = -pad
	if _back.size != _row.size + pad * 2.0:
		_back.size = _row.size + pad * 2.0
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

## The glowing ring the mayor's cursor / a driver should go to (a yellow hoop lying on the grass).
class RingIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var c := size * 0.5
		var k := absf(sin(Time.get_ticks_msec() * 0.006))
		draw_set_transform(c, 0.0, Vector2(1.0, 0.55))
		draw_circle(Vector2.ZERO, h * 0.5, Color(0.35, 0.75, 0.35))
		for i in 3:
			draw_arc(Vector2.ZERO, h * (0.36 + 0.06 * i) + h * 0.03 * k, 0.0, TAU, 28,
				Color(1.0, 0.92, 0.4, 0.95 - 0.3 * i), maxf(2.0, h * (0.1 - 0.03 * i)), true)
		draw_set_transform(Vector2.ZERO)


## A bit of road: a grey strip with white dashes, going away from you.
class RoadIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var c := size * 0.5
		var pts := PackedVector2Array([c + Vector2(-h * 0.22, -h * 0.45), c + Vector2(h * 0.22, -h * 0.45),
			c + Vector2(h * 0.45, h * 0.45), c + Vector2(-h * 0.45, h * 0.45)])
		draw_colored_polygon(pts, Color(0.42, 0.43, 0.48))
		for i in 3:
			var y0 := -h * 0.38 + i * h * 0.3
			draw_line(c + Vector2(0, y0), c + Vector2(0, y0 + h * 0.14), Color(1, 1, 1, 0.9), maxf(2.0, h * 0.05 + i * h * 0.015))


## A little house: walls, a red roof and a door.
class HouseIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var c := size * 0.5 + Vector2(0, h * 0.08)
		draw_rect(Rect2(c + Vector2(-h * 0.32, -h * 0.12), Vector2(h * 0.64, h * 0.46)), Color(1.0, 0.93, 0.78))
		draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.44, -h * 0.1), c + Vector2(0, -h * 0.5),
			c + Vector2(h * 0.44, -h * 0.1)]), Color(0.9, 0.35, 0.3))
		draw_rect(Rect2(c + Vector2(-h * 0.08, h * 0.1), Vector2(h * 0.16, h * 0.24)), Color(0.55, 0.35, 0.22))


## A toy car driving towards a glowing ring (the driver's job: go there).
class CarIcon extends Control:
	var color := Color(1.0, 0.75, 0.25)

	func _draw() -> void:
		var h := minf(size.x, size.y)
		var c := size * 0.5
		var k := fmod(Time.get_ticks_msec() * 0.0006, 1.0)
		var x := lerpf(-size.x * 0.12, size.x * 0.12, k)
		var at := c + Vector2(x, h * 0.08)
		draw_rect(Rect2(at + Vector2(-h * 0.42, -h * 0.18), Vector2(h * 0.84, h * 0.3)), color)
		draw_rect(Rect2(at + Vector2(-h * 0.06, -h * 0.42), Vector2(h * 0.4, h * 0.26)), color.lightened(0.3))
		draw_rect(Rect2(at + Vector2(0.0, -h * 0.36), Vector2(h * 0.26, h * 0.15)), Color(0.75, 0.9, 1.0))
		for wx in [-0.24, 0.24]:
			draw_circle(at + Vector2(h * wx, h * 0.14), h * 0.13, Color(0.15, 0.15, 0.2))
			draw_circle(at + Vector2(h * wx, h * 0.14), h * 0.05, Color(0.8, 0.8, 0.85))


static func _sized(c: Control, px: Vector2) -> Control:
	c.custom_minimum_size = px
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func ring_icon(px: float) -> Control:
	return _sized(RingIcon.new(), Vector2(px * 1.3, px))


## The block `kind` as a little picture: a road, else a house.
static func block_icon(kind: String, px: float) -> Control:
	if kind == "road":
		return _sized(RoadIcon.new(), Vector2(px, px))
	return _sized(HouseIcon.new(), Vector2(px, px))


static func car_icon(px: float, col: Color) -> Control:
	var c := CarIcon.new()
	c.color = col
	return _sized(c, Vector2(px * 1.5, px))


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

## A glowing arrow pointing down (origin at the tip), `length` metres long, sharing `mat`.
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
