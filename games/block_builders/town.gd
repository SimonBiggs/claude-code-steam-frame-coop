extends Node3D
## BLOCK BUILDERS: PUFF'S TOWN (deep.gd TOWN_*): every finished sky course adds a little building - houses, towers,
## windmills, lighthouses, tree houses and a castle every tenth - on a floating island below and behind the course
## (seen past the course by the VR builder and to the left of the runners' views). Roofs in the colour of the mode the
## course was built in. Saved on the host (town) and sent as the "town" state, so every machine draws the same town.
## The island only appears once the first building stands; the newest one bounces in. One merged mesh: cheap.
##   set_town(total, list)   list: [[kind index, mode], ...] (the newest deep.gd TOWN_SHOWN)

const MeshKit := preload("res://core/mesh_kit.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const Deep := preload("res://games/block_builders/deep.gd")

const ISLAND_TOP := Color(0.5, 0.82, 0.42)
const ISLAND_SIDE := Color(0.55, 0.4, 0.28)
const WALLS: Array[Color] = [Color(1.0, 0.92, 0.75), Color(0.85, 0.92, 1.0), Color(1.0, 0.82, 0.82), Color(0.9, 1.0, 0.85)]

var total := -1
var shown := 0
var mesh_node: MeshInstance3D
var newest: Node3D
var pop := 0.0


## Every machine: the town (total built, the newest shown ones).
func set_town(new_total: int, list: Array) -> void:
	if new_total == total and list.size() == shown:
		return
	var grew := total >= 0 and new_total > total
	total = new_total
	shown = list.size()
	if mesh_node != null and is_instance_valid(mesh_node):
		mesh_node.queue_free()
	if newest != null and is_instance_valid(newest):
		newest.queue_free()
	mesh_node = null
	newest = null
	if list.is_empty():
		return  # (no empty island: it appears with the first building)
	var b := MeshKit.Builder.new()
	var rows := (list.size() + Deep.TOWN_COLS - 1) / Deep.TOWN_COLS
	var cols := mini(list.size(), Deep.TOWN_COLS)
	var w := float(cols) * Deep.TOWN_GAP + 1.2
	var d := float(rows) * Deep.TOWN_GAP + 1.2
	var first := Deep.town_spot(0)
	var last_col := Deep.town_spot(cols - 1)
	var cx := (first.x + last_col.x) * 0.5
	var cz := first.y - float(rows - 1) * Deep.TOWN_GAP * 0.5
	var top := Deep.TOWN_AT.y
	b.box(Vector3(w, 0.4, d), MeshKit.at(Vector3(cx, top - 0.2, cz)), ISLAND_TOP)
	b.box(Vector3(w - 0.4, 1.2, d - 0.4), MeshKit.at(Vector3(cx, top - 1.0, cz)), ISLAND_SIDE)
	b.cone(minf(w, d) * 0.4, 1.6, MeshKit.at(Vector3(cx, top - 1.6, cz), Vector3.ONE, Vector3(PI, 0.0, 0.0)), ISLAND_SIDE.darkened(0.2), 10)
	for i in list.size():
		if grew and i == list.size() - 1:
			continue  # (the newest bounces in on its own node)
		_building(b, list[i], i, Vector3.ZERO)
	mesh_node = MeshKit.instance(b.build(), false)
	mesh_node.name = "TownMesh"
	add_child(mesh_node)
	if grew:
		var nb := MeshKit.Builder.new()
		var sp := Deep.town_spot(list.size() - 1)
		_building(nb, list[list.size() - 1], list.size() - 1, -Vector3(sp.x, top, sp.y))
		newest = MeshKit.instance(nb.build(), false)
		newest.name = "NewBuilding"
		newest.position = Vector3(sp.x, top, sp.y)
		newest.scale = Vector3.ONE * 0.05
		add_child(newest)
		pop = 0.0


func _process(delta: float) -> void:
	if newest == null or not is_instance_valid(newest):
		return
	pop = minf(1.0, pop + delta * 1.4)
	var s := 1.0 + sin(pop * PI) * 0.35 if pop > 0.5 else pop * 2.0
	newest.scale = Vector3.ONE * maxf(0.05, s)


## One building at its spot (shift: added to its place, for the newest one's own node).
static func _building(b: MeshKit.Builder, item: Variant, i: int, shift: Vector3) -> void:
	var a: Array = item if item is Array else [0, "brave"]
	var kind: String = Deep.TOWN_KINDS[clampi(int(a[0]) if a.size() > 0 else 0, 0, Deep.TOWN_KINDS.size() - 1)]
	var roof := PickOrbs.mode_color(String(a[1]) if a.size() > 1 else "brave", Color(0.35, 0.75, 1.0))
	var wall: Color = WALLS[i % WALLS.size()]
	var sp := Deep.town_spot(i)
	var o := Vector3(sp.x, Deep.TOWN_AT.y, sp.y) + shift
	var xf := func(p: Vector3, sc: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> Transform3D:
		return MeshKit.at(o + p, sc, rot)
	var door := Color(0.45, 0.28, 0.16)
	match kind:
		"tower":
			b.cylinder(0.45, 0.5, 2.0, xf.call(Vector3(0, 1.0, 0)), wall, 10)
			b.cone(0.6, 0.8, xf.call(Vector3(0, 2.4, 0)), roof, 10)
			b.box(Vector3(0.3, 0.5, 0.05), xf.call(Vector3(0, 0.25, 0.48)), door)
		"windmill":
			b.cylinder(0.4, 0.55, 1.6, xf.call(Vector3(0, 0.8, 0)), wall, 10)
			b.cone(0.5, 0.5, xf.call(Vector3(0, 1.85, 0)), roof, 10)
			for k in 4:
				b.box(Vector3(0.14, 0.9, 0.04), xf.call(Vector3(0, 1.5, 0.5), Vector3.ONE, Vector3(0, 0, k * PI * 0.5 + 0.3)) * Transform3D(Basis(), Vector3(0, 0.45, 0)), Color(0.98, 0.98, 1.0))
		"lighthouse":
			for k in 4:
				b.cylinder(0.38 - k * 0.04, 0.42 - k * 0.04, 0.5, xf.call(Vector3(0, 0.25 + k * 0.5, 0)), [Color(0.98, 0.98, 1.0), Color(0.95, 0.3, 0.3)][k % 2], 10)
			b.cylinder(0.3, 0.3, 0.3, xf.call(Vector3(0, 2.15, 0)), Color(1.0, 0.95, 0.55), 10, true)
			b.cone(0.35, 0.35, xf.call(Vector3(0, 2.47, 0)), roof, 10)
		"treehouse":
			b.cylinder(0.14, 0.18, 1.4, xf.call(Vector3(0, 0.7, 0)), Color(0.5, 0.33, 0.2), 8)
			b.sphere(0.75, xf.call(Vector3(0, 2.0, 0), Vector3(1.0, 0.8, 1.0)), Color(0.35, 0.72, 0.35), 10)
			b.box(Vector3(0.8, 0.55, 0.7), xf.call(Vector3(0, 1.45, 0.25)), wall)
			_roof(b, o + Vector3(0, 1.72, 0.25), Vector2(0.95, 0.8), roof)
		"castle":
			b.box(Vector3(1.7, 1.0, 1.2), xf.call(Vector3(0, 0.5, 0)), Color(0.82, 0.82, 0.88))
			for sx in [-1.0, 1.0]:
				b.cylinder(0.32, 0.32, 1.6, xf.call(Vector3(sx * 0.85, 0.8, 0)), Color(0.86, 0.86, 0.92), 10)
				b.cone(0.42, 0.6, xf.call(Vector3(sx * 0.85, 1.9, 0)), roof, 10)
			b.box(Vector3(0.4, 0.6, 0.05), xf.call(Vector3(0, 0.3, 0.61)), door)
			b.box(Vector3(0.04, 0.5, 0.04), xf.call(Vector3(0, 1.25, 0)), Color(0.4, 0.4, 0.4))
			b.box(Vector3(0.35, 0.2, 0.03), xf.call(Vector3(0.18, 1.4, 0)), roof)
		_:  # a little house
			b.box(Vector3(1.0, 0.8, 0.9), xf.call(Vector3(0, 0.4, 0)), wall)
			_roof(b, o + Vector3(0, 0.8, 0), Vector2(1.15, 1.0), roof)
			b.box(Vector3(0.28, 0.45, 0.05), xf.call(Vector3(0, 0.23, 0.46)), door)
			b.box(Vector3(0.22, 0.2, 0.05), xf.call(Vector3(0.3, 0.5, 0.46)), Color(0.6, 0.85, 1.0))


## A pitched roof from its eaves at `at` (size: width along x, depth along z): two tilted boards.
static func _roof(b: MeshKit.Builder, at: Vector3, size: Vector2, col: Color) -> void:
	var half := size.y * 0.5
	var tilt := 0.7
	var board := half / cos(tilt) + 0.06
	for s in [-1.0, 1.0]:
		var mid := at + Vector3(0.0, sin(tilt) * board * 0.5, s * (half - cos(tilt) * board * 0.5))
		b.box(Vector3(size.x, 0.07, board), MeshKit.at(mid, Vector3.ONE, Vector3(s * tilt, 0.0, 0.0)), col)
