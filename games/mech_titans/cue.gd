extends Control
## SIMPLE_MODE picture cue (visual teaching, no words): low in one TV player's view, a pulsing glowing
## pad button in that player's own controls plus a picture of what to do, on a soft dark pill.
## teach.gd adds one per view and calls show_cue() every frame with a key ("" = none). Rows are built
## ONCE per key (add_row, when the view is made) and only shown / hidden after that: no nodes,
## materials or style boxes are made while playing. A new cue fades in, no cue fades out.
## Also: EdgeArrow (a big glowing arrow at the view's edge pointing the way to something off screen),
## the little pictures (a fist, a beam, a practice bat, a kaiju, the Titan, the four vehicles, a glowing
## ring, people, a shelter) and the glowing 3D arrow (make_arrow).

const UiKit := preload("res://core/ui_kit.gd")

var key := ""        ## the cue showing now ("" = none, fading out)
var a := 0.0         ## fade
var s := 1.0         ## the scale the rows were built at
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


## A soft dark pill behind the row, so the pictures stand out on the bright city.
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
	return snappedf(clampf(2.2 * UiKit.scale_for_size(p.size), 0.9, 2.4), 0.1)


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
	position = Vector2(ps.x * 0.5 - _row.size.x * 0.5, ps.y * 0.86 - _row.size.y - 8.0 * k2)
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

## The Titan's fist punching forward (with speed lines).
class FistIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var k := absf(sin(Time.get_ticks_msec() * 0.008))
		var c := size * 0.5 + Vector2(h * (0.08 * k - 0.04), 0.0)
		for i in 3:
			var y := c.y + (i - 1) * h * 0.2
			draw_line(Vector2(c.x - h * 0.62, y), Vector2(c.x - h * 0.36, y), Color(1, 1, 1, 0.75), maxf(2.0, h * 0.05), true)
		var body := Rect2(c + Vector2(-h * 0.3, -h * 0.3), Vector2(h * 0.6, h * 0.6))
		var sb := Color(0.55, 0.65, 0.85)
		draw_rect(body, sb)
		for i in 4:
			draw_circle(c + Vector2(h * 0.3, -h * 0.22 + i * h * 0.148), h * 0.09, sb.lightened(0.15))
		for i in 3:
			var y2 := c.y - h * 0.15 + i * h * 0.148
			draw_line(Vector2(c.x - h * 0.05, y2), Vector2(c.x + h * 0.32, y2), Color(0.25, 0.3, 0.45), maxf(1.5, h * 0.03))
		draw_rect(body, Color(0.15, 0.18, 0.3, 0.9), false, maxf(2.0, h * 0.04))


## The chest beam: a glowing cyan ray from a little emitter.
class BeamIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var k := absf(sin(Time.get_ticks_msec() * 0.012))
		var y := size.y * 0.5
		var x0 := size.x * 0.12
		var x1 := size.x * 0.95
		draw_line(Vector2(x0, y), Vector2(x1, y), Color(0.5, 0.95, 1.0, 0.35), h * (0.34 + 0.08 * k), true)
		draw_line(Vector2(x0, y), Vector2(x1, y), Color(0.8, 1.0, 1.0), h * 0.14, true)
		draw_circle(Vector2(x0, y), h * 0.2, Color(0.3, 0.8, 1.0))
		draw_circle(Vector2(x0, y), h * 0.1, Color(1, 1, 1))


## The glowing practice bat (what to hit in the warm-up).
class BatIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var c := size * 0.5
		var k := absf(sin(Time.get_ticks_msec() * 0.006))
		draw_circle(c, h * (0.46 + 0.04 * k), Color(1.0, 0.9, 0.4, 0.25))
		var col := Color(0.75, 0.55, 1.0)
		for sx in [-1.0, 1.0]:
			draw_colored_polygon(PackedVector2Array([c + Vector2(sx * h * 0.12, -h * 0.08), c + Vector2(sx * h * 0.48, -h * 0.22),
				c + Vector2(sx * h * 0.36, h * 0.02), c + Vector2(sx * h * 0.4, h * 0.14), c + Vector2(sx * h * 0.12, h * 0.08)]), col)
		draw_circle(c, h * 0.18, col.lightened(0.1))
		draw_circle(c + Vector2(-h * 0.07, -h * 0.03), h * 0.045, Color.WHITE)
		draw_circle(c + Vector2(h * 0.07, -h * 0.03), h * 0.045, Color.WHITE)


## A friendly kaiju: a green blob with spikes and big eyes.
class KaijuIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var c := size * 0.5 + Vector2(0, h * 0.06)
		var col := Color(0.45, 0.85, 0.4)
		for i in 3:
			var x := (i - 1) * h * 0.2
			draw_colored_polygon(PackedVector2Array([c + Vector2(x - h * 0.08, -h * 0.28), c + Vector2(x, -h * 0.46),
				c + Vector2(x + h * 0.08, -h * 0.28)]), Color(1.0, 0.75, 0.3))
		draw_circle(c, h * 0.36, col)
		draw_circle(c + Vector2(-h * 0.13, -h * 0.06), h * 0.1, Color.WHITE)
		draw_circle(c + Vector2(h * 0.13, -h * 0.06), h * 0.1, Color.WHITE)
		draw_circle(c + Vector2(-h * 0.12, -h * 0.05), h * 0.05, Color(0.1, 0.1, 0.15))
		draw_circle(c + Vector2(h * 0.14, -h * 0.05), h * 0.05, Color(0.1, 0.1, 0.15))
		draw_arc(c + Vector2(0, h * 0.1), h * 0.12, 0.3, PI - 0.3, 10, Color(0.15, 0.3, 0.1), maxf(2.0, h * 0.04), true)


## The Titan's head: a blue robot with a glowing visor.
class TitanIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var c := size * 0.5
		draw_rect(Rect2(c + Vector2(-h * 0.04, -h * 0.48), Vector2(h * 0.08, h * 0.14)), Color(0.8, 0.8, 0.9))
		draw_circle(c + Vector2(0, -h * 0.48), h * 0.06, Color(1.0, 0.4, 0.3))
		var head := Rect2(c + Vector2(-h * 0.36, -h * 0.34), Vector2(h * 0.72, h * 0.7))
		draw_rect(head, Color(0.3, 0.5, 0.95))
		draw_rect(Rect2(c + Vector2(-h * 0.26, -h * 0.16), Vector2(h * 0.52, h * 0.18)), Color(0.6, 1.0, 1.0))
		draw_rect(Rect2(c + Vector2(-h * 0.16, h * 0.14), Vector2(h * 0.32, h * 0.08)), Color(0.15, 0.2, 0.4))
		draw_rect(head, Color(0.1, 0.15, 0.35, 0.9), false, maxf(2.0, h * 0.04))


## A support vehicle: "jet", "truck", "drone" or "tank".
class VehicleIcon extends Control:
	var kind := "jet"
	var color := Color.WHITE

	func _draw() -> void:
		var h := minf(size.x, size.y)
		var c := size * 0.5
		var ink := Color(0.1, 0.12, 0.2, 0.9)
		match kind:
			"jet":
				var pts := PackedVector2Array([c + Vector2(h * 0.5, 0), c + Vector2(-h * 0.1, -h * 0.1), c + Vector2(-h * 0.25, -h * 0.42),
					c + Vector2(-h * 0.36, -h * 0.42), c + Vector2(-h * 0.3, -h * 0.1), c + Vector2(-h * 0.5, -h * 0.1),
					c + Vector2(-h * 0.5, h * 0.1), c + Vector2(-h * 0.3, h * 0.1), c + Vector2(-h * 0.36, h * 0.42),
					c + Vector2(-h * 0.25, h * 0.42), c + Vector2(-h * 0.1, h * 0.1)])
				draw_colored_polygon(pts, color)
				draw_circle(c + Vector2(h * 0.18, 0), h * 0.07, Color(0.8, 0.95, 1.0))
			"truck":
				draw_rect(Rect2(c + Vector2(-h * 0.5, -h * 0.24), Vector2(h * 0.62, h * 0.4)), color)
				draw_rect(Rect2(c + Vector2(h * 0.12, -h * 0.1), Vector2(h * 0.36, h * 0.26)), color.lightened(0.2))
				draw_rect(Rect2(c + Vector2(h * 0.22, -h * 0.06), Vector2(h * 0.18, h * 0.1)), Color(0.75, 0.9, 1.0))
				draw_rect(Rect2(c + Vector2(-h * 0.26, -h * 0.14), Vector2(h * 0.14, h * 0.2)), Color.WHITE)
				draw_rect(Rect2(c + Vector2(-h * 0.33, -h * 0.07), Vector2(h * 0.28, h * 0.06)), Color.WHITE)
				for wx in [-0.32, 0.3]:
					draw_circle(c + Vector2(h * wx, h * 0.2), h * 0.11, ink)
			"drone":
				draw_rect(Rect2(c + Vector2(-h * 0.36, -h * 0.03), Vector2(h * 0.72, h * 0.06)), Color(0.85, 0.9, 0.95))
				for sx in [-1.0, 1.0]:
					draw_line(c + Vector2(sx * h * 0.48, -h * 0.12), c + Vector2(sx * h * 0.24, -h * 0.12), Color(0.85, 0.9, 0.95), maxf(2.0, h * 0.05))
					draw_line(c + Vector2(sx * h * 0.36, -h * 0.12), c + Vector2(sx * h * 0.36, 0), Color(0.85, 0.9, 0.95), maxf(2.0, h * 0.04))
				draw_circle(c + Vector2(0, h * 0.06), h * 0.2, color)
				draw_rect(Rect2(c + Vector2(-h * 0.04, -h * 0.04), Vector2(h * 0.08, h * 0.2)), Color.WHITE)
				draw_rect(Rect2(c + Vector2(-h * 0.1, h * 0.02), Vector2(h * 0.2, h * 0.08)), Color.WHITE)
			"tank":
				draw_line(c + Vector2(0, -h * 0.12), c + Vector2(h * 0.45, -h * 0.34), color.lightened(0.2), maxf(3.0, h * 0.1))
				draw_rect(Rect2(c + Vector2(-h * 0.2, -h * 0.24), Vector2(h * 0.4, h * 0.2)), color.lightened(0.1))
				draw_rect(Rect2(c + Vector2(-h * 0.45, -h * 0.06), Vector2(h * 0.9, h * 0.22)), color)
				draw_rect(Rect2(c + Vector2(-h * 0.48, h * 0.14), Vector2(h * 0.96, h * 0.16)), ink)
				for i in 4:
					draw_circle(c + Vector2(-h * 0.33 + i * h * 0.22, h * 0.22), h * 0.06, Color(0.6, 0.6, 0.7))


## A glowing ring standing up (fly / drive through it), green or gold.
class RingIcon extends Control:
	var color := Color(0.45, 1.0, 0.7)

	func _draw() -> void:
		var h := minf(size.x, size.y)
		var c := size * 0.5
		var k := absf(sin(Time.get_ticks_msec() * 0.006))
		draw_set_transform(c, 0.0, Vector2(0.62, 1.0))
		for i in 3:
			draw_arc(Vector2.ZERO, h * (0.36 + 0.05 * i) + h * 0.03 * k, 0.0, TAU, 28,
				Color(color.r, color.g, color.b, 0.95 - 0.3 * i), maxf(2.0, h * (0.1 - 0.03 * i)), true)
		draw_set_transform(Vector2.ZERO)


## A little green shelter: a house with a glowing green beam above it.
class ShelterIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var c := size * 0.5 + Vector2(0, h * 0.14)
		draw_rect(Rect2(c + Vector2(-h * 0.12, -h * 0.5), Vector2(h * 0.24, h * 0.4)), Color(0.3, 1.0, 0.45, 0.3))
		draw_rect(Rect2(c + Vector2(-h * 0.3, -h * 0.1), Vector2(h * 0.6, h * 0.42)), Color(0.85, 1.0, 0.85))
		draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.4, -h * 0.08), c + Vector2(0, -h * 0.38),
			c + Vector2(h * 0.4, -h * 0.08)]), Color(0.3, 0.85, 0.4))
		draw_rect(Rect2(c + Vector2(-h * 0.07, h * 0.1), Vector2(h * 0.14, h * 0.22)), Color(0.25, 0.5, 0.3))


## People jumping up and down (they want rescuing).
class PeopleIcon extends Control:
	func _draw() -> void:
		var h := minf(size.x, size.y)
		var t := Time.get_ticks_msec() * 0.008
		var cols := [Color(1.0, 0.8, 0.3), Color(0.5, 0.8, 1.0), Color(1.0, 0.5, 0.6)]
		for i in 3:
			var x := size.x * (0.22 + 0.28 * i)
			var y := size.y * 0.62 - maxf(0.0, sin(t + i * 2.0)) * h * 0.14
			draw_circle(Vector2(x, y - h * 0.24), h * 0.1, Color(1.0, 0.85, 0.7))
			draw_rect(Rect2(Vector2(x - h * 0.09, y - h * 0.14), Vector2(h * 0.18, h * 0.3)), cols[i])


static func _sized(c: Control, px: Vector2) -> Control:
	c.custom_minimum_size = px
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func fist_icon(px: float) -> Control:
	return _sized(FistIcon.new(), Vector2(px * 1.4, px))


static func beam_icon(px: float) -> Control:
	return _sized(BeamIcon.new(), Vector2(px * 1.6, px))


static func bat_icon(px: float) -> Control:
	return _sized(BatIcon.new(), Vector2(px * 1.2, px))


static func kaiju_icon(px: float) -> Control:
	return _sized(KaijuIcon.new(), Vector2(px, px))


static func titan_icon(px: float) -> Control:
	return _sized(TitanIcon.new(), Vector2(px, px))


static func vehicle_icon(kind: String, col: Color, px: float) -> Control:
	var v := VehicleIcon.new()
	v.kind = kind
	v.color = col
	return _sized(v, Vector2(px * 1.2, px))


static func ring_icon(px: float, col: Color = Color(0.45, 1.0, 0.7)) -> Control:
	var r := RingIcon.new()
	r.color = col
	return _sized(r, Vector2(px * 0.8, px))


static func shelter_icon(px: float) -> Control:
	return _sized(ShelterIcon.new(), Vector2(px, px))


static func people_icon(px: float) -> Control:
	return _sized(PeopleIcon.new(), Vector2(px * 1.3, px))


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


## A big glowing arrow at the edge of a view, pointing the way to `target` (when on is true and the
## target is off screen). Redraws only while it shows.
class EdgeArrow extends Control:
	var cam: Camera3D
	var target := Vector3.ZERO
	var on := false
	var _drawn := false

	func _ready() -> void:
		name = "EdgeArrow"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiKit.pin(self, Control.PRESET_FULL_RECT, false)

	## Is the target inside the view (with a margin)?
	func target_in_view() -> bool:
		if cam == null or not is_instance_valid(cam) or cam.is_position_behind(target):
			return false
		var vs := size
		var sp := cam.unproject_position(target)
		var mg := vs * 0.1
		return sp.x > mg.x and sp.y > mg.y and sp.x < vs.x - mg.x and sp.y < vs.y - mg.y

	func _process(_delta: float) -> void:
		if on or _drawn:
			queue_redraw()

	func _draw() -> void:
		_drawn = false
		if not on or cam == null or not is_instance_valid(cam):
			return
		_drawn = true
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
		var reach := minf(size.x, size.y) * 0.36
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
		draw_colored_polygon(pts, Color(1.0, 0.8, 0.3, 0.75 + 0.25 * k))
		draw_polyline(outline, Color(0.3, 0.2, 0.05, 0.8), maxf(2.0, 3.0 * ui), true)


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
