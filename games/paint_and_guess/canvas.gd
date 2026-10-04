# Label sizes x1.8 (2026-10-04): the artist now stands 1.5 m back instead of 0.85 m (Simon).
extends Node3D
## The easel: a dark canvas board on wooden legs, facing +Z (towards the artist). Strokes live in
## canvas coordinates (metres, origin at the canvas centre, x right, y up) and are drawn as glowing
## ribbons stuck to the board. Geometry is built INCREMENTALLY (only the newest segment is triangulated
## in GDScript; the rest is packed arrays uploaded natively), so several painters at once (TEAM PAINT)
## stay cheap: every painter's stroke in progress has its own small mesh, finished ones are baked into
## chunk meshes (a handful of draw calls for the whole picture).
## Also owns the paint pots (incl. RAINBOW and SPARKLE), the CLEAR / UNDO / NEW WORD bubbles, the
## brush cursor, the TV painters' cursor rings, the answer balloons (TEAM PAINT: the VR player guesses),
## the vote grid, a timer bar, the header labels and the audience critters (one per TV player).

const MeshKit := preload("res://games/paint_and_guess/mesh_kit.gd")

const W := 1.3
const H := 0.9
const SEG_POINTS := 90  # a painter starts a fresh piece after this many points (keeps the live mesh cheap)
const MAX_POINTS := 9000
const COLORS: Array[Color] = [Color(1, 1, 1), Color(1.0, 0.25, 0.25), Color(1.0, 0.6, 0.15), Color(1.0, 0.92, 0.2),
	Color(0.3, 0.95, 0.35), Color(0.25, 0.85, 1.0), Color(0.6, 0.4, 1.0), Color(1.0, 0.45, 0.8),
	Color(1.0, 0.5, 0.5), Color(1.0, 0.85, 0.35)]
const COLOR_NAMES: Array[String] = ["WHITE", "RED", "ORANGE", "YELLOW", "GREEN", "SKY BLUE", "PURPLE", "PINK",
	"RAINBOW", "SPARKLE"]
const RAINBOW := 8
const SPARKLE := 9
const TEAM_BASE := 10  # TV painters' strokes: TEAM_BASE + player index (their own colour)
const SECRET_LAYER := 2  # visual layer bit for things only the artist may see (the word)
const CHUNK := 10  # finished strokes baked per mesh
const PAINT_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
varying vec3 lp;
void vertex() {
	lp = VERTEX;
}
vec3 hue_rgb(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}
void fragment() {
	vec3 c = COLOR.rgb;
	if (COLOR.a < 0.4) {
		c = mix(hue_rgb(fract(COLOR.r - TIME * 0.25)), vec3(1.0), COLOR.b);
	} else if (COLOR.a < 0.75) {
		c *= 0.75 + 0.7 * max(0.0, sin(TIME * 7.0 + lp.x * 90.0 + lp.y * 70.0));
	}
	ALBEDO = c;
}
"""

var main
var cy := 1.25  # canvas centre height
var strokes: Array = []  # [{id, col, w, pts, z, owner, v, c, acc, mi, mesh, live, chunk}]
var by_id := {}
var lives := {}  # owner -> the stroke that painter is painting (own mesh)
var chunks: Array = []  # [{mi, mesh, ids, dirty}]
var paint_mat: ShaderMaterial
var point_count := 0
var rev := 0
var seq := 0
var anim_t := 0.0

var board_root: Node3D  # moves with the height; everything below hangs off it
var stroke_root: Node3D
var cursor: MeshInstance3D
var cursor_mat: StandardMaterial3D
var pots_mm: MultiMeshInstance3D
var pot_scale: Array[float] = []
var clear_bubble: MeshInstance3D
var undo_bubble: MeshInstance3D
var skip_bubble: MeshInstance3D
var word_label: Label3D  # secret: layer 2 only
var hint_label: Label3D
var info_label: Label3D  # how-to / reveal text written on the board
var tip_label: Label3D  # short contextual tips at the bottom of the board
var score_label: Label3D
var timer_bar: MeshInstance3D
var timer_mat: StandardMaterial3D
var audience: Array[Node3D] = []
var crown: MeshInstance3D
var legs: MeshInstance3D
var pulse := {}  # node -> time left of a squash animation
var tv_cursors: MultiMeshInstance3D
var balloons: Array[Node3D] = []
var balloon_popped: Array[bool] = [false, false, false, false]
var vote_root: Node3D
var vote_cells: Array[Vector2] = []
var vote_marks: MultiMeshInstance3D


func _ready() -> void:
	board_root = Node3D.new()
	add_child(board_root)
	var wood := Color(0.62, 0.42, 0.25)
	var dark_wood := Color(0.45, 0.29, 0.16)
	# Frame, tray, a brush cup and a palette hanging on the side: one mesh, one draw call.
	var parts: Array = [
		[MeshKit.box(Vector3(W + 0.08, H + 0.08, 0.03)), MeshKit.at(Vector3(0, 0, -0.025)), wood],
		[MeshKit.box(Vector3(W + 0.1, 0.03, 0.12)), MeshKit.at(Vector3(0, -H * 0.5 - 0.06, 0.04)), dark_wood],
		[MeshKit.box(Vector3(W + 0.1, 0.015, 0.02)), MeshKit.at(Vector3(0, -H * 0.5 - 0.04, 0.095)), wood],
		[MeshKit.cyl(0.03, 0.026, 0.07, 10), MeshKit.at(Vector3(-W * 0.5 - 0.11, -H * 0.5 - 0.02, 0.05)), Color(0.35, 0.55, 0.85)],
		[MeshKit.box(Vector3(0.12, 0.03, 0.12)), MeshKit.at(Vector3(-W * 0.5 - 0.11, -H * 0.5 - 0.06, 0.04)), dark_wood],
	]
	for k in 3:
		parts.append([MeshKit.cyl(0.004, 0.005, 0.16, 6), MeshKit.at(Vector3(-W * 0.5 - 0.12 + k * 0.012, -H * 0.5 + 0.05, 0.05),
			Vector3.ONE, Vector3(0, 0, 0.15 - k * 0.15)), Color(0.85, 0.7, 0.45)])
		parts.append([MeshKit.sphere(0.009, 8), MeshKit.at(Vector3(-W * 0.5 - 0.12 + k * 0.012 - (0.15 - k * 0.15) * 0.08 * -1.0,
			-H * 0.5 + 0.13, 0.05), Vector3(0.8, 1.5, 0.8)), COLORS[[1, 5, 3][k]]])
	# The palette (decoration) on the left edge of the frame.
	parts.append([MeshKit.cyl(0.11, 0.11, 0.012, 16), MeshKit.at(Vector3(-W * 0.5 - 0.06, H * 0.32, 0.0), Vector3(1.0, 1.0, 0.75),
		Vector3(PI * 0.5, 0, 0.3)), Color(0.85, 0.66, 0.42)])
	for k in 5:
		var ang := 0.6 + k * 0.55
		parts.append([MeshKit.sphere(0.018, 8), MeshKit.at(Vector3(-W * 0.5 - 0.06 + cos(ang) * 0.07, H * 0.32 + sin(ang) * 0.055, 0.01),
			Vector3(1.0, 1.0, 0.4)), COLORS[[1, 3, 4, 5, 7][k]]])
	var static_mi := MeshInstance3D.new()
	static_mi.mesh = MeshKit.merge(parts)
	static_mi.material_override = MeshKit.vertex_material(main.mats)
	board_root.add_child(static_mi)
	var surf := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(W, H)
	surf.mesh = qm
	surf.material_override = main.flat_material(Color(0.07, 0.08, 0.15))
	board_root.add_child(surf)
	_build_pots()
	clear_bubble = _bubble("CLEAR", Color(0.4, 0.8, 1.0), Vector3(W * 0.5 + 0.15, H * 0.3, 0.08))
	undo_bubble = _bubble("UNDO", Color(0.6, 1.0, 0.5), Vector3(W * 0.5 + 0.15, H * 0.02, 0.08))
	skip_bubble = _bubble("NEW\nWORD", Color(1.0, 0.75, 0.3), Vector3(W * 0.5 + 0.15, -H * 0.26, 0.08))
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
	cursor_mat = StandardMaterial3D.new()
	cursor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cursor.material_override = cursor_mat
	board_root.add_child(cursor)
	cursor.visible = false
	word_label = _label(64, Color(1.0, 0.95, 0.6), Vector3(0, H * 0.5 + 0.24, 0.0))
	word_label.layers = SECRET_LAYER
	hint_label = _label(54, Color(0.7, 0.95, 1.0), Vector3(0, H * 0.5 + 0.24, 0.0))
	info_label = _label(40, Color(1, 1, 1), Vector3(0, 0, 0.012))
	info_label.width = (W - 0.1) / info_label.pixel_size
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label = _label(30, Color(1.0, 0.95, 0.7), Vector3(0, -H * 0.5 + 0.07, 0.014))
	tip_label.width = (W - 0.1) / tip_label.pixel_size
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	score_label = _label(34, Color(1.0, 0.9, 0.75), Vector3(-W * 0.5 - 0.3, H * 0.05, 0.0))
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	score_label.pixel_size = 0.00198
	score_label.visible = false
	timer_bar = MeshInstance3D.new()
	timer_bar.mesh = MeshKit.box(Vector3(1.0, 0.022, 0.012))
	timer_mat = StandardMaterial3D.new()
	timer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	timer_bar.material_override = timer_mat
	timer_bar.position = Vector3(0, H * 0.5 + 0.02, 0.004)
	board_root.add_child(timer_bar)
	timer_bar.visible = false
	legs = MeshInstance3D.new()
	legs.material_override = MeshKit.vertex_material(main.mats)
	add_child(legs)
	_build_tv_cursors()
	_build_balloons()
	set_height(cy)


func _build_pots() -> void:
	pots_mm = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = MeshKit.sphere(0.035, 14)
	mm.instance_count = COLORS.size()
	pots_mm.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pots_mm.material_override = mat
	board_root.add_child(pots_mm)
	pot_scale.clear()
	for i in COLORS.size():
		pot_scale.append(0.0)
		mm.set_instance_transform(i, Transform3D(Basis(), pot_local(i)))
		mm.set_instance_color(i, COLORS[i])


func _bubble(text: String, col: Color, pos: Vector3) -> MeshInstance3D:
	var b := MeshInstance3D.new()
	b.mesh = main.sphere_mesh(0.07)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	b.material_override = m
	b.position = pos
	board_root.add_child(b)
	var l := Label3D.new()
	l.text = text
	l.font_size = 38
	l.outline_size = 12
	l.pixel_size = 0.00198
	l.position = Vector3(0, 0, 0.075)
	b.add_child(l)
	return b


func _label(size: int, col: Color, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.font_size = size
	l.outline_size = 14
	l.pixel_size = 0.00252
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
	var wood := Color(0.55, 0.37, 0.21)
	var parts: Array = []
	for i in 3:
		var h := lh if i < 2 else lh + 0.4
		var sz := Vector3(0.045, h, 0.045)
		if i < 2:
			parts.append([MeshKit.box(sz), MeshKit.at(Vector3((-1.0 if i == 0 else 1.0) * (W * 0.5 - 0.05), h * 0.5, -0.05),
				Vector3.ONE, Vector3(0, 0, (-1.0 if i == 0 else 1.0) * -0.04)), wood])
		else:
			parts.append([MeshKit.box(sz), MeshKit.at(Vector3(0, h * 0.5, -0.35), Vector3.ONE, Vector3(-0.35, 0, 0)), wood])
	legs.mesh = MeshKit.merge(parts)


func pot_local(i: int) -> Vector3:
	var n := COLORS.size()
	return Vector3(-W * 0.5 + 0.07 + (W - 0.14) * float(i) / float(n - 1), -H * 0.5 - 0.02, 0.06)


func pot_world(i: int) -> Vector3:
	return board_root.to_global(pot_local(i))


func clear_world() -> Vector3:
	return clear_bubble.global_position


func undo_world() -> Vector3:
	return undo_bubble.global_position


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


## The colour a brush shows in the UI (rainbow cycles; TV painters use their own colour).
func ui_color(col: int) -> Color:
	if col == RAINBOW:
		return Color.from_hsv(fmod(anim_t * 0.25, 1.0), 0.75, 1.0)
	if col >= TEAM_BASE:
		var pc: Array[Color] = main.PLAYER_COLORS
		return pc[(col - TEAM_BASE) % pc.size()]
	return COLORS[clampi(col, 0, COLORS.size() - 1)]


func set_cursor(p: Vector2, on: bool, col: Color, drawing: bool) -> void:
	cursor.visible = on
	if not on:
		return
	cursor.position = Vector3(p.x, p.y, 0.012)
	cursor_mat.albedo_color = col
	var s := 1.4 if drawing else 1.0
	cursor.scale = Vector3(s, 1.0, s)


## Easel controls (pots and bubbles) only make sense while the artist paints.
func show_tools(on: bool) -> void:
	pots_mm.visible = on
	clear_bubble.visible = on
	undo_bubble.visible = on
	skip_bubble.visible = on


func set_timer(frac: float, on: bool) -> void:
	timer_bar.visible = on and frac > 0.0
	if not timer_bar.visible:
		return
	frac = clampf(frac, 0.0, 1.0)
	timer_bar.scale = Vector3(W * frac, 1.0, 1.0)
	timer_bar.position.x = -W * 0.5 + W * frac * 0.5
	var c := Color(0.35, 1.0, 0.45) if frac > 0.5 else (Color(1.0, 0.85, 0.2) if frac > 0.2 else Color(1.0, 0.3, 0.25))
	if frac <= 0.2 and fmod(anim_t, 0.5) < 0.25:
		c = c.lightened(0.5)
	timer_mat.albedo_color = c


# --- Strokes -----------------------------------------------------------------------

func is_full() -> bool:
	return point_count >= MAX_POINTS


## A new stroke gets its own small mesh while its painter paints it; when that painter starts the next
## one (or lifts the brush), it is baked into a shared chunk mesh.
func begin_stroke(id: int, col: int, w: float, p: Vector2, owner: int = 0) -> void:
	if by_id.has(id):
		return
	end_stroke(owner)
	var mi := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	mi.mesh = mesh
	mi.material_override = _paint_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stroke_root.add_child(mi)
	seq += 1
	var pts := PackedVector2Array()
	pts.append(clamp_point(p))
	var s := {"id": id, "col": col, "w": w, "pts": pts, "z": 0.003 + float(seq % 300) * 0.00002, "owner": owner,
		"v": PackedVector3Array(), "c": PackedColorArray(), "acc": 0.0, "mi": mi, "mesh": mesh, "live": true,
		"dirty": true, "chunk": -1}
	_geo_point(s, 0)
	strokes.append(s)
	by_id[id] = s
	lives[owner] = s
	point_count += 1


func add_points(id: int, pts: PackedVector2Array) -> void:
	if not by_id.has(id):
		return
	var s: Dictionary = by_id[id]
	var have: PackedVector2Array = s["pts"]
	for p in pts:
		have.append(clamp_point(p))
		if s["live"]:
			s["pts"] = have
			_geo_point(s, have.size() - 1)
	s["pts"] = have
	s["dirty"] = true
	point_count += pts.size()
	if not s["live"]:
		_geo_rebuild(s)  # late points for an already baked stroke
		_mark_chunk_dirty(s)


func stroke_len(id: int) -> int:
	if not by_id.has(id):
		return 0
	var pts: PackedVector2Array = by_id[id]["pts"]
	return pts.size()


## The painter lifted the brush: bake their stroke into a chunk.
func end_stroke(owner: int) -> void:
	if not lives.has(owner):
		return
	var s: Dictionary = lives[owner]
	lives.erase(owner)
	if not by_id.has(s["id"]):
		return
	s["live"] = false
	var mi = s["mi"]
	if mi != null and is_instance_valid(mi):
		mi.queue_free()
	s["mi"] = null
	s["mesh"] = null
	_geo_cap(s)
	if chunks.is_empty() or (chunks[chunks.size() - 1]["ids"] as Array).size() >= CHUNK:
		var cmi := MeshInstance3D.new()
		var cmesh := ArrayMesh.new()
		cmi.mesh = cmesh
		cmi.material_override = _paint_material()
		cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stroke_root.add_child(cmi)
		chunks.append({"mi": cmi, "mesh": cmesh, "ids": [], "dirty": false})
	var c: Dictionary = chunks[chunks.size() - 1]
	var ids: Array = c["ids"]
	ids.append(s["id"])
	s["chunk"] = chunks.size() - 1
	c["dirty"] = true


## Undo: take one stroke off the canvas. Returns how many points it had.
func remove_stroke(id: int) -> int:
	if not by_id.has(id):
		return 0
	var s: Dictionary = by_id[id]
	var n := (s["pts"] as PackedVector2Array).size()
	if s["live"]:
		for k in lives.keys():
			if is_same(lives[k], s):
				lives.erase(k)
		var mi = s["mi"]
		if mi != null and is_instance_valid(mi):
			mi.queue_free()
	else:
		_mark_chunk_dirty(s)
		var ci: int = s["chunk"]
		if ci >= 0 and ci < chunks.size():
			(chunks[ci]["ids"] as Array).erase(id)
	by_id.erase(id)
	for i in range(strokes.size() - 1, -1, -1):
		if int(strokes[i]["id"]) == id:
			strokes.remove_at(i)
			break
	point_count -= n
	return n


## The newest stroke still on the canvas (for UNDO), or -1.
func last_stroke_id(owner: int = -1) -> int:
	for i in range(strokes.size() - 1, -1, -1):
		var s: Dictionary = strokes[i]
		if owner < 0 or int(s["owner"]) == owner:
			return int(s["id"])
	return -1


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
	lives.clear()
	point_count = 0


## Everything on the canvas, for a TV machine that joined late.
func export_strokes() -> Array:
	var out: Array = []
	for s in strokes:
		out.append([s["id"], s["col"], s["w"], s["pts"], s["owner"]])
	return out


func import_strokes(data: Array) -> void:
	clear_all()
	for e in data:
		var a: Array = e
		var pts: PackedVector2Array = a[3]
		if pts.is_empty():
			continue
		var owner: int = int(a[4]) if a.size() > 4 else 0
		begin_stroke(int(a[0]), int(a[1]), float(a[2]), pts[0], 100 + int(a[0]))  # unique owner: bakes cleanly
		if pts.size() > 1:
			add_points(int(a[0]), pts.slice(1))
		end_stroke(100 + int(a[0]))
		if by_id.has(int(a[0])):
			by_id[int(a[0])]["owner"] = owner


## The whole picture as one mesh (for the gallery wall and the vote), or null when the canvas is empty.
func build_picture() -> ArrayMesh:
	var v := PackedVector3Array()
	var c := PackedColorArray()
	for s in strokes:
		v.append_array(s["v"])
		c.append_array(s["c"])
	if v.size() < 3:
		return null
	return _arrays_mesh(v, c)


func _arrays_mesh(v: PackedVector3Array, c: PackedColorArray) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_COLOR] = c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _paint_material() -> ShaderMaterial:
	if paint_mat == null:
		var sh := Shader.new()
		sh.code = PAINT_SHADER
		paint_mat = ShaderMaterial.new()
		paint_mat.shader = sh
	return paint_mat


func paint_material() -> ShaderMaterial:
	return _paint_material()


func _mark_chunk_dirty(s: Dictionary) -> void:
	var ci: int = s.get("chunk", -1)
	if ci >= 0 and ci < chunks.size():
		chunks[ci]["dirty"] = true


# --- Stroke geometry (canvas-local triangles + colours) ------------------------------

## Vertex colour for a piece of a stroke: alpha flags the shader effect (1 plain, 0.5 sparkle, 0.25 rainbow).
func _vcol(s: Dictionary, along: float, core: bool) -> Color:
	var col: int = s["col"]
	if col == RAINBOW:
		return Color(fposmod(along * 1.7, 1.0), 0.0, 0.55 if core else 0.0, 0.25)
	if col == SPARKLE:
		return Color(1.0, 1.0, 0.85, 0.5) if core else Color(1.0, 0.78, 0.25, 0.5)
	var base := ui_color(col)
	return base.lerp(Color(1, 1, 1), 0.7) if core else base


## Append the triangles for point i of a live stroke (the segment to it, round joints, sparkles).
func _geo_point(s: Dictionary, i: int) -> void:
	var pts: PackedVector2Array = s["pts"]
	var v: PackedVector3Array = s["v"]
	var c: PackedColorArray = s["c"]
	var w: float = s["w"]
	var z: float = s["z"]
	var r := w * 0.5
	if i == 0:
		_dot(v, c, pts[0], r, z, _vcol(s, 0.0, false))
		_dot(v, c, pts[0], r * 0.4, z + 0.0008, _vcol(s, 0.0, true))
	else:
		var a := pts[i - 1]
		var b := pts[i]
		var d := b - a
		if d.length() > 0.0001:
			var acc0: float = s["acc"]
			var acc1 := acc0 + d.length()
			s["acc"] = acc1
			var nn := Vector2(-d.y, d.x).normalized()
			_quad(v, c, a, b, nn * r, z, _vcol(s, acc0, false), _vcol(s, acc1, false))
			_quad(v, c, a, b, nn * r * 0.4, z + 0.0008, _vcol(s, acc0, true), _vcol(s, acc1, true))
			if i % 3 == 0:
				_dot(v, c, b, r, z, _vcol(s, acc1, false))
				_dot(v, c, b, r * 0.4, z + 0.0008, _vcol(s, acc1, true))
			if int(s["col"]) == SPARKLE and i % 2 == 0:
				var h := fposmod(sin(float(i) * 12.9898 + float(int(s["id"])) * 78.233) * 43758.5453, 1.0)
				var h2 := fposmod(h * 91.7, 1.0)
				var sp := b + Vector2(h - 0.5, h2 - 0.5) * w * 2.2
				_star(v, c, sp, w * (0.35 + h2 * 0.35), z + 0.0012, Color(1, 1, 1, 0.5) if h > 0.5 else Color(1.0, 0.6, 0.9, 0.5))
	s["v"] = v
	s["c"] = c


func _geo_cap(s: Dictionary) -> void:
	var pts: PackedVector2Array = s["pts"]
	if pts.size() < 2:
		return
	var v: PackedVector3Array = s["v"]
	var c: PackedColorArray = s["c"]
	var r: float = float(s["w"]) * 0.5
	var acc: float = s["acc"]
	_dot(v, c, pts[pts.size() - 1], r, s["z"], _vcol(s, acc, false))
	_dot(v, c, pts[pts.size() - 1], r * 0.4, float(s["z"]) + 0.0008, _vcol(s, acc, true))
	s["v"] = v
	s["c"] = c


func _geo_rebuild(s: Dictionary) -> void:
	s["v"] = PackedVector3Array()
	s["c"] = PackedColorArray()
	s["acc"] = 0.0
	var pts: PackedVector2Array = s["pts"]
	for i in pts.size():
		_geo_point(s, i)
	if not s["live"]:
		_geo_cap(s)


func _quad(v: PackedVector3Array, c: PackedColorArray, a: Vector2, b: Vector2, nn: Vector2, z: float, ca: Color, cb: Color) -> void:
	var a0 := Vector3(a.x + nn.x, a.y + nn.y, z)
	var a1 := Vector3(a.x - nn.x, a.y - nn.y, z)
	var b0 := Vector3(b.x + nn.x, b.y + nn.y, z)
	var b1 := Vector3(b.x - nn.x, b.y - nn.y, z)
	v.append(a0)
	v.append(a1)
	v.append(b0)
	v.append(b0)
	v.append(a1)
	v.append(b1)
	c.append(ca)
	c.append(ca)
	c.append(cb)
	c.append(cb)
	c.append(ca)
	c.append(cb)


func _dot(v: PackedVector3Array, c: PackedColorArray, p: Vector2, r: float, z: float, col: Color) -> void:
	var seg := 7
	var ctr := Vector3(p.x, p.y, z)
	for k in seg:
		var a0 := TAU * float(k) / seg
		var a1 := TAU * float(k + 1) / seg
		v.append(ctr)
		v.append(Vector3(p.x + cos(a0) * r, p.y + sin(a0) * r, z))
		v.append(Vector3(p.x + cos(a1) * r, p.y + sin(a1) * r, z))
		c.append(col)
		c.append(col)
		c.append(col)


## A little four-pointed twinkle for the SPARKLE brush.
func _star(v: PackedVector3Array, c: PackedColorArray, p: Vector2, r: float, z: float, col: Color) -> void:
	var t := r * 0.22
	for dir in [Vector2(1, 0), Vector2(0, 1)]:
		var d: Vector2 = dir
		var n := Vector2(-d.y, d.x)
		var tip0 := p + d * r
		var tip1 := p - d * r
		v.append(Vector3(tip0.x, tip0.y, z))
		v.append(Vector3(p.x + n.x * t, p.y + n.y * t, z))
		v.append(Vector3(tip1.x, tip1.y, z))
		v.append(Vector3(tip0.x, tip0.y, z))
		v.append(Vector3(tip1.x, tip1.y, z))
		v.append(Vector3(p.x - n.x * t, p.y - n.y * t, z))
		for k in 6:
			c.append(col)


# --- Per frame --------------------------------------------------------------------------

func _process(delta: float) -> void:
	anim_t += delta
	for k in lives.keys():
		var s: Dictionary = lives[k]
		if s["dirty"]:
			s["dirty"] = false
			var mesh: ArrayMesh = s["mesh"]
			var v: PackedVector3Array = s["v"]
			if mesh != null and v.size() >= 3:
				mesh.clear_surfaces()
				var arrays: Array = []
				arrays.resize(Mesh.ARRAY_MAX)
				arrays[Mesh.ARRAY_VERTEX] = v
				arrays[Mesh.ARRAY_COLOR] = s["c"]
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	for ch in chunks:
		if not ch["dirty"]:
			continue
		ch["dirty"] = false
		var cmesh: ArrayMesh = ch["mesh"]
		cmesh.clear_surfaces()
		var v2 := PackedVector3Array()
		var c2 := PackedColorArray()
		for id in ch["ids"]:
			if by_id.has(id):
				var st: Dictionary = by_id[id]
				v2.append_array(st["v"])
				c2.append_array(st["c"])
		if v2.size() >= 3:
			var arrays2: Array = []
			arrays2.resize(Mesh.ARRAY_MAX)
			arrays2[Mesh.ARRAY_VERTEX] = v2
			arrays2[Mesh.ARRAY_COLOR] = c2
			cmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays2)
	_animate_pots(delta)
	_animate_audience(delta)
	_animate_balloons()
	# Squash-and-stretch on pressed bubbles and hopping critters.
	for n in pulse.keys():
		var node := n as Node3D
		var t: float = float(pulse[n]) - delta
		if node == null or not is_instance_valid(node):
			pulse.erase(n)
			continue
		if t <= 0.0:
			pulse.erase(n)
			node.scale = Vector3.ONE
			continue
		pulse[n] = t
		var k2 := sin(t * 18.0) * t * 0.6
		node.scale = Vector3(1.0 + k2, 1.0 - k2, 1.0 + k2)


func poke(node: Node3D, t: float = 0.5) -> void:
	pulse[node] = t


func poke_pot(i: int) -> void:
	if i >= 0 and i < pot_scale.size():
		pot_scale[i] = 0.5


func _animate_pots(delta: float) -> void:
	if not pots_mm.visible:
		return
	var mm := pots_mm.multimesh
	for i in pot_scale.size():
		var t: float = pot_scale[i]
		var s := 1.0
		if t > 0.0:
			t = maxf(0.0, t - delta)
			pot_scale[i] = t
			s = 1.0 + sin(t * 18.0) * t * 0.8
		if i == RAINBOW or i == SPARKLE or t > 0.0 or s != 1.0:
			var bob := 0.004 * sin(anim_t * 3.0 + i) if i >= RAINBOW else 0.0
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, 1.0 / maxf(s, 0.3), s)), pot_local(i) + Vector3(0, bob, 0)))
	mm.set_instance_color(RAINBOW, ui_color(RAINBOW))
	mm.set_instance_color(SPARKLE, COLORS[SPARKLE].lightened(0.35 * maxf(0.0, sin(anim_t * 9.0))))


# --- Audience critters (one per TV player) ------------------------------------------------

func ensure_audience(count: int, colors: Array[Color]) -> void:
	var hats: Array[Color] = [Color(1.0, 0.85, 0.2), Color(0.3, 0.8, 1.0), Color(1.0, 0.4, 0.7), Color(0.5, 1.0, 0.5),
		Color(1.0, 0.55, 0.2), Color(0.75, 0.55, 1.0)]
	while audience.size() < count:
		var i := audience.size()
		var col: Color = colors[(i + 1) % colors.size()]
		var dark := col.darkened(0.3)
		var r := 0.05
		var parts: Array = [
			[MeshKit.sphere(r, 14), MeshKit.at(Vector3.ZERO, Vector3(1.0, 0.92, 0.9)), col],
			[MeshKit.sphere(r * 0.62, 12), MeshKit.at(Vector3(0, -0.013, 0.024), Vector3(1.0, 1.0, 0.6)), col.lightened(0.45)],
			[MeshKit.sphere(0.0075, 8), MeshKit.at(Vector3(-0.031, -0.002, 0.04)), Color(1.0, 0.55, 0.6)],
			[MeshKit.sphere(0.0075, 8), MeshKit.at(Vector3(0.031, -0.002, 0.04)), Color(1.0, 0.55, 0.6)],
			[MeshKit.cyl(0.0, 0.017, 0.04, 8), MeshKit.at(Vector3(0.012, 0.058, 0.0), Vector3.ONE, Vector3(0, 0, -0.3)), hats[i % hats.size()]],
			[MeshKit.sphere(0.006, 6), MeshKit.at(Vector3(0.018, 0.079, 0.0)), Color(1, 1, 1)],
		]
		for sx in [-1.0, 1.0]:
			parts.append([MeshKit.sphere(0.014, 10), MeshKit.at(Vector3(sx * 0.018, 0.016, 0.037)), Color(1, 1, 1)])
			parts.append([MeshKit.sphere(0.0075, 8), MeshKit.at(Vector3(sx * 0.018, 0.017, 0.05)), Color(0.05, 0.05, 0.1)])
			parts.append([MeshKit.sphere(0.016, 8), MeshKit.at(Vector3(sx * 0.032, 0.042, -0.004), Vector3(0.9, 1.4, 0.6)), dark])
			parts.append([MeshKit.sphere(0.015, 8), MeshKit.at(Vector3(sx * 0.02, -0.044, 0.014), Vector3(1.2, 0.6, 1.4)), dark])
			parts.append([MeshKit.sphere(0.012, 8), MeshKit.at(Vector3(sx * 0.05, -0.008, 0.008), Vector3(0.7, 1.2, 0.8)), dark])
		var key := "critter%d" % i
		var mesh: ArrayMesh
		if main.meshes.has(key):
			mesh = main.meshes[key]
		else:
			mesh = MeshKit.merge(parts)
			main.meshes[key] = mesh
		var blob := Node3D.new()
		var body := MeshInstance3D.new()
		body.mesh = mesh
		body.material_override = MeshKit.vertex_material(main.mats)
		blob.add_child(body)
		blob.position = audience_pos(i)
		board_root.add_child(blob)
		blob.visible = false
		blob.set_meta("hop", 0.0)
		blob.set_meta("mood", 0.0)
		audience.append(blob)


## Critters sit on the top corners of the frame (3 left, 3 right), clear of the VR text above the middle.
func audience_pos(i: int) -> Vector3:
	var k := i / 2
	var side := -1.0 if i % 2 == 0 else 1.0
	return Vector3(side * (W * 0.5 - 0.07 - k * 0.12), H * 0.5 + 0.09, 0.03)


func set_audience(i: int, on: bool, got: bool) -> void:
	if i < 0 or i >= audience.size():
		return
	var b := audience[i]
	b.visible = on
	b.set_meta("got", got)


## The critter of guesser i jumps for joy (ok) or droops (not ok).
func hop(i: int, ok: bool = true) -> void:
	if i >= 0 and i < audience.size():
		audience[i].set_meta("hop", 1.0 if ok else 0.0)
		audience[i].set_meta("mood", 0.0 if ok else 1.0)
		if ok:
			poke(audience[i].get_child(0), 0.9)


func wiggle(i: int) -> void:
	if i >= 0 and i < audience.size():
		audience[i].set_meta("wig", 1.0)


func _animate_audience(delta: float) -> void:
	for i in audience.size():
		var b := audience[i]
		if not b.visible:
			continue
		var base := audience_pos(i)
		var hopv: float = maxf(0.0, float(b.get_meta("hop", 0.0)) - delta * 1.1)
		b.set_meta("hop", hopv)
		var mood: float = maxf(0.0, float(b.get_meta("mood", 0.0)) - delta * 0.8)
		b.set_meta("mood", mood)
		var wig: float = maxf(0.0, float(b.get_meta("wig", 0.0)) - delta * 1.5)
		b.set_meta("wig", wig)
		var party: bool = b.get_meta("party", false)
		var y := base.y + 0.004 * sin(anim_t * 2.6 + i * 1.3)
		if hopv > 0.0:
			y += absf(sin(hopv * 9.0)) * 0.07 * hopv
		if party:
			y += absf(sin(anim_t * 7.0 + i)) * 0.04
		b.position = Vector3(base.x, y - mood * 0.012, base.z)
		var got: bool = b.get_meta("got", false)
		var s := 1.18 if got else 1.0
		b.scale = Vector3(s, s * (1.0 - mood * 0.25), s)
		b.rotation = Vector3(mood * 0.35, sin(anim_t * 1.3 + i) * 0.25, sin(wig * 20.0) * wig * 0.5)


## Give the winner a crown (index < 0: nobody).
func set_crown(i: int) -> void:
	if crown == null:
		var gold := Color(1.0, 0.82, 0.2)
		var parts: Array = [[MeshKit.cyl(0.03, 0.032, 0.022, 12), MeshKit.at(Vector3.ZERO), gold]]
		for k in 5:
			var a := TAU * k / 5.0
			parts.append([MeshKit.sphere(0.009, 6), MeshKit.at(Vector3(cos(a) * 0.03, 0.02, sin(a) * 0.03)), Color(1.0, 0.35, 0.4) if k % 2 == 0 else Color(0.4, 0.8, 1.0)])
		crown = MeshInstance3D.new()
		crown.mesh = MeshKit.merge(parts)
		crown.material_override = MeshKit.vertex_material(main.mats, true)
	var parent: Node = audience[i] if i >= 0 and i < audience.size() else board_root
	if crown.get_parent() != parent:
		if crown.get_parent() != null:
			crown.get_parent().remove_child(crown)
		parent.add_child(crown)
	crown.position = Vector3(0, 0.06, 0)
	crown.visible = parent != board_root
	for k in audience.size():
		audience[k].set_meta("party", i >= 0)


# --- TEAM PAINT: the TV players' brush rings and the VR player's answer balloons -------------

func _build_tv_cursors() -> void:
	tv_cursors = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var tm := TorusMesh.new()
	tm.inner_radius = 0.014
	tm.outer_radius = 0.022
	tm.rings = 14
	tm.ring_segments = 6
	mm.mesh = tm
	mm.instance_count = 6
	mm.visible_instance_count = 0
	tv_cursors.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tv_cursors.material_override = mat
	board_root.add_child(tv_cursors)


## cursors: Array of [Vector2 pos, Color, bool painting]
func set_tv_cursors(cursors: Array) -> void:
	var mm := tv_cursors.multimesh
	var n := mini(cursors.size(), mm.instance_count)
	mm.visible_instance_count = n
	for k in n:
		var cur: Array = cursors[k]
		var p: Vector2 = cur[0]
		var s := 1.35 if cur[2] else 1.0
		mm.set_instance_transform(k, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(s, s, s)), Vector3(p.x, p.y, 0.014)))
		mm.set_instance_color(k, cur[1])


const BALLOON_COLS: Array[Color] = [Color(1.0, 0.35, 0.35), Color(0.35, 0.65, 1.0), Color(1.0, 0.85, 0.25), Color(0.45, 0.9, 0.45)]


func _build_balloons() -> void:
	for i in 4:
		var col := BALLOON_COLS[i]
		var parts: Array = [
			[MeshKit.sphere(0.075, 14), MeshKit.at(Vector3.ZERO, Vector3(1.0, 1.15, 1.0)), col],
			[MeshKit.cyl(0.0, 0.012, 0.018, 8), MeshKit.at(Vector3(0, -0.092, 0)), col.darkened(0.2)],
			[MeshKit.sphere(0.018, 8), MeshKit.at(Vector3(-0.03, 0.04, 0.055), Vector3(0.7, 1.0, 0.4)), col.lightened(0.6)],
		]
		var b := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = MeshKit.merge(parts)
		mi.material_override = MeshKit.vertex_material(main.mats)
		b.add_child(mi)
		var l := Label3D.new()
		l.font_size = 40
		l.outline_size = 14
		l.pixel_size = 0.00207
		l.position = Vector3(0, 0, 0.09)
		l.render_priority = 3
		l.outline_render_priority = 2
		b.add_child(l)
		b.position = balloon_local(i)
		board_root.add_child(b)
		b.visible = false
		balloons.append(b)


## Balloons float in a row in front of the lower part of the board (waist height, arm's length).
func balloon_local(i: int) -> Vector3:
	return Vector3(-0.48 + 0.32 * i, -H * 0.5 + 0.12, 0.2)


func balloon_world(i: int) -> Vector3:
	return balloons[i].global_position


func show_balloons(words: Array, on: bool, popped_mask: int) -> void:
	for i in 4:
		var b := balloons[i]
		var pop := (popped_mask >> i) & 1 == 1
		b.visible = on and i < words.size() and not pop
		if i < words.size():
			var l := b.get_child(1) as Label3D
			l.text = str(words[i]).to_upper()
		balloon_popped[i] = pop


func _animate_balloons() -> void:
	for i in balloons.size():
		var b := balloons[i]
		if b.visible:
			b.position = balloon_local(i) + Vector3(0, 0.012 * sin(anim_t * 2.0 + i * 1.7), 0)
			b.rotation.z = 0.08 * sin(anim_t * 1.4 + i)


# --- The vote: every picture of the game on the board, pick your favourite -------------------

func show_vote(pics: Array) -> void:
	hide_vote()
	vote_root = Node3D.new()
	board_root.add_child(vote_root)
	vote_cells.clear()
	var n := pics.size()
	var cols := 3 if n > 4 else 2
	var rows := int(ceil(float(n) / cols))
	var cw := W / cols
	var ch := H / maxi(rows, 1)
	var sc := minf(cw * 0.86 / W, ch * 0.7 / H)
	for k in n:
		var col := k % cols
		var row := k / cols
		var center := Vector2(-W * 0.5 + cw * (col + 0.5), H * 0.5 - ch * (row + 0.5) + ch * 0.08)
		vote_cells.append(center)
		var entry: Array = pics[k]
		var mesh: ArrayMesh = entry[0]
		if mesh != null:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = _paint_material()
			mi.scale = Vector3(sc, sc, 0.3)
			mi.position = Vector3(center.x, center.y, 0.004)
			vote_root.add_child(mi)
		var l := Label3D.new()
		l.text = "%d" % (k + 1)
		l.font_size = 48
		l.outline_size = 14
		l.pixel_size = 0.00216
		l.modulate = Color(1.0, 0.9, 0.5)
		l.position = Vector3(center.x - cw * 0.42, center.y + ch * 0.3, 0.02)
		vote_root.add_child(l)
		var wl := Label3D.new()
		wl.text = str(entry[1]).to_upper()
		wl.font_size = 30
		wl.outline_size = 10
		wl.pixel_size = 0.00180
		wl.position = Vector3(center.x, center.y - ch * 0.42, 0.02)
		vote_root.add_child(wl)
	vote_marks = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = MeshKit.sphere(0.018, 10)
	mm.instance_count = 7
	mm.visible_instance_count = 0
	vote_marks.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vote_marks.material_override = mat
	vote_root.add_child(vote_marks)


## marks: Array of [picture index, Color] (one per voter), drawn as dots under the pictures.
func set_vote_marks(marks: Array) -> void:
	if vote_marks == null or not is_instance_valid(vote_marks):
		return
	var mm := vote_marks.multimesh
	var n := mini(marks.size(), mm.instance_count)
	mm.visible_instance_count = n
	var per := {}
	for k in n:
		var m: Array = marks[k]
		var pic: int = m[0]
		if pic < 0 or pic >= vote_cells.size():
			mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0, 0, -1)))
			continue
		var slot: int = per.get(pic, 0)
		per[pic] = slot + 1
		var c := vote_cells[pic]
		mm.set_instance_transform(k, Transform3D(Basis(), Vector3(c.x - 0.1 + slot * 0.04, c.y - H * 0.13, 0.03)))
		mm.set_instance_color(k, m[1])


func vote_cell_at(p: Vector2) -> int:
	if vote_cells.is_empty():
		return -1
	var best := -1
	var bd := 1e9
	for k in vote_cells.size():
		var d := vote_cells[k].distance_to(p)
		if d < bd:
			bd = d
			best = k
	return best if bd < 0.3 else -1


func hide_vote() -> void:
	if vote_root != null and is_instance_valid(vote_root):
		vote_root.queue_free()
	vote_root = null
	vote_marks = null
	vote_cells.clear()
