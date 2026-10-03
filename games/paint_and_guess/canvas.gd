extends Node3D
## The easel: a dark canvas board on wooden legs, facing +Z (towards the artist). Strokes live in
## canvas coordinates (metres, origin at the canvas centre, x right, y up) and are drawn as glowing
## ribbons stuck to the board: the stroke being painted has its own mesh, finished ones are baked in chunks.
## Also owns the paint pots on the tray, the CLEAR and NEW WORD bubbles, the brush cursor dot, the
## header labels and a row of little "audience" blobs (one per guesser) that hop when someone guesses.

const W := 1.3
const H := 0.9
const MAX_STROKE_POINTS := 400
const MAX_POINTS := 7000
const COLORS: Array[Color] = [Color(1, 1, 1), Color(1.0, 0.25, 0.25), Color(1.0, 0.6, 0.15), Color(1.0, 0.92, 0.2),
	Color(0.3, 0.95, 0.35), Color(0.25, 0.85, 1.0), Color(0.6, 0.4, 1.0), Color(1.0, 0.45, 0.8)]
const COLOR_NAMES: Array[String] = ["WHITE", "RED", "ORANGE", "YELLOW", "GREEN", "SKY BLUE", "PURPLE", "PINK"]
const SECRET_LAYER := 2  # visual layer bit for things only the artist may see (the word)

var main
var cy := 1.25  # canvas centre height
const CHUNK := 24  # finished strokes baked per mesh
var strokes: Array = []  # [{id, col, w, pts, z, mi (while live), im, dirty, chunk}]
var by_id := {}
var live := {}  # the stroke being painted (own mesh)
var chunks: Array = []  # [{mi, im, ids, dirty}]
var paint_mat: StandardMaterial3D
var point_count := 0
var rev := 0
var seq := 0

var board_root: Node3D  # moves with the height; everything below hangs off it
var stroke_root: Node3D
var cursor: MeshInstance3D
var pots: Array[MeshInstance3D] = []
var clear_bubble: MeshInstance3D
var skip_bubble: MeshInstance3D
var word_label: Label3D  # secret: layer 2 only
var hint_label: Label3D
var info_label: Label3D  # how-to / reveal text written on the board
var score_label: Label3D
var audience: Array[Node3D] = []
var legs: Array[MeshInstance3D] = []
var pulse := {}  # node -> time left of a squash animation


func _ready() -> void:
	board_root = Node3D.new()
	add_child(board_root)
	var wood: StandardMaterial3D = main.make_material(Color(0.62, 0.42, 0.25), 0.0)
	var frame := MeshInstance3D.new()
	frame.mesh = main.box_mesh(Vector3(W + 0.08, H + 0.08, 0.03))
	frame.material_override = wood
	frame.position = Vector3(0, 0, -0.025)
	board_root.add_child(frame)
	var surf := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(W, H)
	surf.mesh = qm
	surf.material_override = main.flat_material(Color(0.07, 0.08, 0.15))
	board_root.add_child(surf)
	# Tray with the paint pots.
	var tray := MeshInstance3D.new()
	tray.mesh = main.box_mesh(Vector3(W + 0.1, 0.03, 0.12))
	tray.material_override = wood
	tray.position = Vector3(0, -H * 0.5 - 0.06, 0.04)
	board_root.add_child(tray)
	for i in COLORS.size():
		var pot := MeshInstance3D.new()
		pot.mesh = main.sphere_mesh(0.035)
		pot.material_override = main.flat_material(COLORS[i])
		pot.position = pot_local(i)
		board_root.add_child(pot)
		pots.append(pot)
	clear_bubble = _bubble("CLEAR", Color(0.4, 0.8, 1.0), Vector3(W * 0.5 + 0.17, H * 0.25, 0.08))
	skip_bubble = _bubble("NEW\nWORD", Color(1.0, 0.75, 0.3), Vector3(W * 0.5 + 0.17, -H * 0.15, 0.08))
	stroke_root = Node3D.new()
	board_root.add_child(stroke_root)
	cursor = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.014
	cm.bottom_radius = 0.014
	cm.height = 0.004
	cm.radial_segments = 12
	cm.rings = 1
	cursor.mesh = cm
	cursor.rotation.x = PI * 0.5
	cursor.material_override = main.flat_material(Color(1, 1, 1))
	board_root.add_child(cursor)
	cursor.visible = false
	word_label = _label(64, Color(1.0, 0.95, 0.6), Vector3(0, H * 0.5 + 0.24, 0.0))
	word_label.layers = SECRET_LAYER
	hint_label = _label(54, Color(0.7, 0.95, 1.0), Vector3(0, H * 0.5 + 0.24, 0.0))
	info_label = _label(40, Color(1, 1, 1), Vector3(0, 0, 0.012))
	info_label.width = (W - 0.1) / info_label.pixel_size
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	score_label = _label(34, Color(1.0, 0.9, 0.75), Vector3(-W * 0.5 - 0.28, H * 0.2, 0.0))
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	score_label.pixel_size = 0.0011
	score_label.visible = false
	# Wooden legs (rebuilt for the height).
	for i in 3:
		var leg := MeshInstance3D.new()
		leg.material_override = wood
		add_child(leg)
		legs.append(leg)
	set_height(cy)


func _bubble(text: String, col: Color, pos: Vector3) -> MeshInstance3D:
	var b := MeshInstance3D.new()
	b.mesh = main.sphere_mesh(0.075)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	b.material_override = m
	b.position = pos
	board_root.add_child(b)
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.outline_size = 12
	l.pixel_size = 0.0011
	l.position = Vector3(0, 0, 0.08)
	b.add_child(l)
	return b


func _label(size: int, col: Color, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.font_size = size
	l.outline_size = 14
	l.pixel_size = 0.0014
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0)
	l.position = pos
	board_root.add_child(l)
	return l


func set_height(y: float) -> void:
	cy = clampf(y, 0.75, 1.65)
	board_root.position = Vector3(0, cy, 0)
	var bottom := cy - H * 0.5 - 0.08
	var lh := maxf(0.1, bottom + 0.05)
	for i in legs.size():
		var leg := legs[i]
		var h := lh if i < 2 else lh + 0.4
		leg.mesh = main.box_mesh(Vector3(0.04, h, 0.04))
		if i < 2:
			leg.position = Vector3((-1.0 if i == 0 else 1.0) * (W * 0.5 - 0.05), h * 0.5, -0.05)
		else:
			leg.position = Vector3(0, h * 0.5, -0.35)
			leg.rotation.x = -0.35


func pot_local(i: int) -> Vector3:
	var n := COLORS.size()
	return Vector3(-W * 0.5 + 0.08 + (W - 0.16) * float(i) / float(n - 1), -H * 0.5 - 0.02, 0.06)


func pot_world(i: int) -> Vector3:
	return board_root.to_global(pot_local(i))


func clear_world() -> Vector3:
	return clear_bubble.global_position


func skip_world() -> Vector3:
	return skip_bubble.global_position


## Canvas-local coordinates of a world point (z = distance in front of the board).
func to_canvas(world: Vector3) -> Vector3:
	return board_root.to_local(world)


func canvas_to_world(p: Vector2, z: float = 0.0) -> Vector3:
	return board_root.to_global(Vector3(p.x, p.y, z))


func normal() -> Vector3:
	return board_root.global_basis.z.normalized()


func inside(p: Vector2, margin: float = 0.0) -> bool:
	return absf(p.x) <= W * 0.5 + margin and absf(p.y) <= H * 0.5 + margin


func clamp_point(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, -W * 0.5 + 0.01, W * 0.5 - 0.01), clampf(p.y, -H * 0.5 + 0.01, H * 0.5 - 0.01))


func set_cursor(p: Vector2, on: bool, col: Color, drawing: bool) -> void:
	cursor.visible = on
	if not on:
		return
	cursor.position = Vector3(p.x, p.y, 0.012)
	cursor.material_override = main.flat_material(col)
	var s := 1.4 if drawing else 1.0
	cursor.scale = Vector3(s, 1.0, s)


# --- Strokes -----------------------------------------------------------------------

func is_full() -> bool:
	return point_count >= MAX_POINTS


## A new stroke gets its own small mesh while it is being painted; when the next one starts, it is
## baked into a shared chunk mesh (vertex colours, one draw call per CHUNK strokes) to keep draw calls low.
func begin_stroke(id: int, col: int, w: float, p: Vector2) -> void:
	if by_id.has(id):
		return
	_bake_live()
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mi.mesh = im
	mi.material_override = _paint_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stroke_root.add_child(mi)
	seq += 1
	var pts := PackedVector2Array()
	pts.append(clamp_point(p))
	var s := {"id": id, "col": clampi(col, 0, COLORS.size() - 1), "w": w, "pts": pts,
		"z": 0.003 + float(seq % 300) * 0.00002, "mi": mi, "im": im, "dirty": true}
	strokes.append(s)
	by_id[id] = s
	live = s
	point_count += 1


func add_points(id: int, pts: PackedVector2Array) -> void:
	if not by_id.has(id):
		return
	var s: Dictionary = by_id[id]
	var have: PackedVector2Array = s["pts"]
	for p in pts:
		have.append(clamp_point(p))
	s["pts"] = have
	s["dirty"] = true
	point_count += pts.size()
	if not is_same(s, live):
		_mark_chunk_dirty(s)  # late points for an already baked stroke


func stroke_len(id: int) -> int:
	if not by_id.has(id):
		return 0
	var pts: PackedVector2Array = by_id[id]["pts"]
	return pts.size()


func clear_all() -> void:
	for s in strokes:
		var mi = s["mi"]
		if mi != null and is_instance_valid(mi):
			mi.queue_free()
	for c in chunks:
		var cmi: MeshInstance3D = c["mi"]
		cmi.queue_free()
	chunks.clear()
	strokes.clear()
	by_id.clear()
	live = {}
	point_count = 0


## Everything on the canvas, for a TV machine that joined late.
func export_strokes() -> Array:
	var out: Array = []
	for s in strokes:
		out.append([s["id"], s["col"], s["w"], s["pts"]])
	return out


func import_strokes(data: Array) -> void:
	clear_all()
	for e in data:
		var a: Array = e
		var pts: PackedVector2Array = a[3]
		if pts.is_empty():
			continue
		begin_stroke(int(a[0]), int(a[1]), float(a[2]), pts[0])
		if pts.size() > 1:
			add_points(int(a[0]), pts.slice(1))


func _paint_material() -> StandardMaterial3D:
	if paint_mat == null:
		paint_mat = StandardMaterial3D.new()
		paint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		paint_mat.vertex_color_use_as_albedo = true
	return paint_mat


func _bake_live() -> void:
	if live.is_empty():
		return
	var s := live
	live = {}
	var mi = s["mi"]
	if mi != null and is_instance_valid(mi):
		mi.queue_free()
	s["mi"] = null
	if chunks.is_empty() or (chunks[chunks.size() - 1]["ids"] as Array).size() >= CHUNK:
		var cmi := MeshInstance3D.new()
		var cim := ImmediateMesh.new()
		cmi.mesh = cim
		cmi.material_override = _paint_material()
		cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stroke_root.add_child(cmi)
		chunks.append({"mi": cmi, "im": cim, "ids": [], "dirty": false})
	var c: Dictionary = chunks[chunks.size() - 1]
	var ids: Array = c["ids"]
	ids.append(s["id"])
	s["chunk"] = chunks.size() - 1
	s["dirty"] = false
	c["dirty"] = true


func _mark_chunk_dirty(s: Dictionary) -> void:
	var ci: int = s.get("chunk", -1)
	if ci >= 0 and ci < chunks.size():
		chunks[ci]["dirty"] = true


func _process(delta: float) -> void:
	if not live.is_empty() and live["dirty"]:
		live["dirty"] = false
		var im: ImmediateMesh = live["im"]
		im.clear_surfaces()
		_stroke_tris(im, live)
	for c in chunks:
		if c["dirty"]:
			c["dirty"] = false
			var cim: ImmediateMesh = c["im"]
			cim.clear_surfaces()
			var ids: Array = c["ids"]
			var any := false
			for id in ids:
				if by_id.has(id):
					var st: Dictionary = by_id[id]
					var pts: PackedVector2Array = st["pts"]
					if pts.size() > 0:
						any = true
			if not any:
				continue
			cim.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			for id in ids:
				if by_id.has(id):
					_ribbons(cim, by_id[id])
			cim.surface_end()
	# Squash-and-stretch on pressed bubbles and hopping audience blobs.
	for n in pulse.keys():
		var node := n as Node3D
		var t: float = float(pulse[n]) - delta
		if node == null or not is_instance_valid(node):
			pulse.erase(n)
			continue
		if t <= 0.0:
			pulse.erase(n)
			node.scale = Vector3.ONE
			if node.has_meta("base_y"):
				node.position.y = float(node.get_meta("base_y"))
			continue
		pulse[n] = t
		var k := sin(t * 18.0) * t * 0.6
		node.scale = Vector3(1.0 + k, 1.0 - k, 1.0 + k)
		if node.has_meta("base_y"):
			node.position.y = float(node.get_meta("base_y")) + absf(sin(t * 9.0)) * 0.06 * t * 2.0


func poke(node: Node3D, t: float = 0.5) -> void:
	pulse[node] = t


func _stroke_tris(im: ImmediateMesh, s: Dictionary) -> void:
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_ribbons(im, s)
	im.surface_end()


## Coloured outer ribbon plus a whiter core on top: reads as a glowing neon line.
func _ribbons(im: ImmediateMesh, s: Dictionary) -> void:
	var pts: PackedVector2Array = s["pts"]
	var col: Color = COLORS[int(s["col"])]
	var w: float = s["w"]
	var z: float = s["z"]
	im.surface_set_color(col)
	_ribbon(im, pts, w, z)
	im.surface_set_color(col.lerp(Color(1, 1, 1), 0.7))
	_ribbon(im, pts, w * 0.4, z + 0.0008)


## A flat ribbon with round dots at the ends and every few points (so corners and taps look like paint).
func _ribbon(im: ImmediateMesh, pts: PackedVector2Array, w: float, z: float) -> void:
	var r := w * 0.5
	var n := pts.size()
	for i in n - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		if d.length() < 0.0001:
			continue
		var nn := Vector2(-d.y, d.x).normalized() * r
		_tri(im, a + nn, a - nn, b + nn, z)
		_tri(im, b + nn, a - nn, b - nn, z)
	for i in n:
		if i == 0 or i == n - 1 or i % 3 == 0:
			_dot(im, pts[i], r, z)


func _tri(im: ImmediateMesh, a: Vector2, b: Vector2, c: Vector2, z: float) -> void:
	im.surface_add_vertex(Vector3(a.x, a.y, z))
	im.surface_add_vertex(Vector3(b.x, b.y, z))
	im.surface_add_vertex(Vector3(c.x, c.y, z))


func _dot(im: ImmediateMesh, c: Vector2, r: float, z: float) -> void:
	var seg := 8
	for k in seg:
		var a0 := TAU * float(k) / seg
		var a1 := TAU * float(k + 1) / seg
		_tri(im, c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r, z)


# --- Audience (one blob per guesser) ---------------------------------------------------

func ensure_audience(count: int, colors: Array[Color]) -> void:
	while audience.size() < count:
		var i := audience.size()
		var blob := Node3D.new()
		var body := MeshInstance3D.new()
		body.mesh = main.sphere_mesh(0.045)
		body.material_override = main.make_material(colors[(i + 1) % colors.size()], 0.3)
		blob.add_child(body)
		for sx in [-1.0, 1.0]:
			var eye := MeshInstance3D.new()
			eye.mesh = main.sphere_mesh(0.009)
			eye.material_override = main.flat_material(Color(0.05, 0.05, 0.1))
			eye.position = Vector3(sx * 0.016, 0.01, 0.04)
			blob.add_child(eye)
		var x := -W * 0.5 + 0.1 + float(i) * 0.11
		blob.position = Vector3(x, H * 0.5 + 0.09, 0.04)
		blob.set_meta("base_y", blob.position.y)
		board_root.add_child(blob)
		blob.visible = false
		audience.append(blob)


func set_audience(i: int, on: bool, got: bool) -> void:
	if i < 0 or i >= audience.size():
		return
	var b := audience[i]
	b.visible = on
	# Blobs sit on the top edge of the frame; ones who got it wear a little gold glow.
	var y := H * 0.5 + 0.09
	b.set_meta("base_y", y)
	if not pulse.has(b):
		b.position.y = y
	var body := b.get_child(0) as MeshInstance3D
	body.scale = Vector3.ONE * (1.25 if got else 1.0)


func hop(i: int) -> void:
	if i >= 0 and i < audience.size():
		poke(audience[i], 0.9)
