extends Node3D
## PAINT AND GUESS: SMUDGE'S MUSEUM (deep.gd MUSEUM_* / treasure_kind): every finished game adds a treasure on a plinth
## along the side walls, under the family gallery - vases, flower pots, sculptures, trophies, golden frames and a cat
## statue every tenth. Each plinth has a band in the colour of the mode the game was played in. Saved on the host
## (museum, museum_n) and sent as the "museum" state, so every machine shows the same museum; the newest treasure
## bounces in. Gifts open as it grows (deep.gd GIFTS unlock). One merged mesh: cheap.
##   set_museum(total, list)   list: [[kind index, mode], ...] (the newest deep.gd MUSEUM_SHOWN)

const MeshKit := preload("res://core/mesh_kit.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const Deep := preload("res://games/paint_and_guess/deep.gd")

const STONE := Color(0.93, 0.9, 0.84)
const GOLD := Color(1.0, 0.8, 0.3)
const POTS: Array[Color] = [Color(0.35, 0.6, 0.95), Color(0.95, 0.45, 0.4), Color(0.55, 0.85, 0.6), Color(0.85, 0.6, 1.0)]

var total := -1
var shown := 0
var mesh_node: MeshInstance3D
var newest: Node3D
var pop := 0.0


## Every machine: the museum (total treasures, the newest shown ones).
func set_museum(new_total: int, list: Array) -> void:
	if new_total == total and list.size() == shown:
		return
	var grew := total >= 0 and new_total > total
	total = new_total
	shown = list.size()
	for n in [mesh_node, newest]:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	mesh_node = null
	newest = null
	if list.is_empty():
		return
	var b := MeshKit.Builder.new()
	for i in list.size():
		if grew and i == list.size() - 1:
			continue  # (the newest bounces in on its own node)
		_treasure(b, list[i], i, Vector3.ZERO)
	if not b.is_empty():
		mesh_node = MeshKit.instance(b.build(), false)
		mesh_node.name = "MuseumMesh"
		add_child(mesh_node)
	if grew:
		var nb := MeshKit.Builder.new()
		var sp := Deep.museum_spot(list.size() - 1)
		_treasure(nb, list[list.size() - 1], list.size() - 1, -sp)
		newest = MeshKit.instance(nb.build(), false)
		newest.name = "NewTreasure"
		newest.position = sp
		newest.scale = Vector3.ONE * 0.05
		add_child(newest)
		pop = 0.0


func _process(delta: float) -> void:
	if newest == null or not is_instance_valid(newest):
		return
	pop = minf(1.0, pop + delta * 1.4)
	var s := 1.0 + sin(pop * PI) * 0.35 if pop > 0.5 else pop * 2.0
	newest.scale = Vector3.ONE * maxf(0.05, s)


## One treasure on its plinth at its spot (shift: added to its place, for the newest one's own node).
static func _treasure(b: MeshKit.Builder, item: Variant, i: int, shift: Vector3) -> void:
	var a: Array = item if item is Array else [0, "brave"]
	var kind: String = Deep.TREASURES[clampi(int(a[0]) if a.size() > 0 else 0, 0, Deep.TREASURES.size() - 1)]
	var band := PickOrbs.mode_color(String(a[1]) if a.size() > 1 else "brave", Color(0.35, 0.75, 1.0))
	var o := Deep.museum_spot(i) + shift
	var face := -signf(Deep.museum_spot(i).x)  # (turned to the room)
	var xf := func(p: Vector3, sc: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> Transform3D:
		return MeshKit.at(o + p, sc, rot)
	var top := Deep.PLINTH_H
	b.box(Vector3(0.34, top - 0.06, 0.34), xf.call(Vector3(0, (top - 0.06) * 0.5, 0)), STONE)
	b.box(Vector3(0.38, 0.06, 0.38), xf.call(Vector3(0, top - 0.03, 0)), STONE.lightened(0.3))
	b.box(Vector3(0.345, 0.05, 0.345), xf.call(Vector3(0, top * 0.6, 0)), band)
	var pot: Color = POTS[i % POTS.size()]
	match kind:
		"vase":
			b.sphere(0.11, xf.call(Vector3(0, top + 0.12, 0), Vector3(1.0, 1.15, 1.0)), pot, 10)
			b.cylinder(0.05, 0.06, 0.12, xf.call(Vector3(0, top + 0.27, 0)), pot.darkened(0.1), 10)
			b.torus(0.06, 0.012, xf.call(Vector3(0, top + 0.33, 0)), pot.lightened(0.3), 10, 4)
		"flowerpot":
			b.cylinder(0.11, 0.08, 0.16, xf.call(Vector3(0, top + 0.08, 0)), Color(0.85, 0.5, 0.35), 10)
			b.cylinder(0.008, 0.008, 0.16, xf.call(Vector3(0, top + 0.22, 0)), Color(0.3, 0.6, 0.3), 6)
			for k in 5:
				var ang := TAU * k / 5.0
				b.sphere(0.04, xf.call(Vector3(cos(ang) * 0.045, top + 0.31, sin(ang) * 0.045)), pot.lightened(0.2), 8)
			b.sphere(0.03, xf.call(Vector3(0, top + 0.31, 0)), Color(1.0, 0.85, 0.2), 8)
		"sculpture":
			b.sphere(0.09, xf.call(Vector3(0, top + 0.09, 0)), pot, 10)
			b.box(Vector3(0.1, 0.1, 0.1), xf.call(Vector3(0.0, top + 0.22, 0), Vector3.ONE, Vector3(0.6, 0.6, 0.0)), pot.lightened(0.3))
			b.sphere(0.045, xf.call(Vector3(0, top + 0.34, 0)), GOLD, 8)
		"trophy":
			b.box(Vector3(0.14, 0.05, 0.14), xf.call(Vector3(0, top + 0.025, 0)), Color(0.45, 0.3, 0.2))
			b.cylinder(0.02, 0.03, 0.1, xf.call(Vector3(0, top + 0.1, 0)), GOLD, 8)
			b.cylinder(0.1, 0.05, 0.14, xf.call(Vector3(0, top + 0.22, 0)), GOLD, 12)
			for s in [-1.0, 1.0]:
				b.torus(0.04, 0.01, xf.call(Vector3(s * 0.1, top + 0.23, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), GOLD, 10, 4)
		"goldframe":
			b.box(Vector3(0.04, 0.34, 0.3), xf.call(Vector3(0, top + 0.17, 0)), GOLD)
			b.box(Vector3(0.045, 0.26, 0.22), xf.call(Vector3(face * 0.003, top + 0.17, 0)), Color(0.12, 0.14, 0.3))
			b.sphere(0.04, xf.call(Vector3(face * 0.03, top + 0.2, 0.02)), Color(1.0, 0.85, 0.3), 8, true)
		"catstatue":  # a golden Smudge sitting up, in her beret
			b.sphere(0.11, xf.call(Vector3(0, top + 0.11, 0), Vector3(1.0, 1.1, 0.9)), GOLD, 10)
			b.sphere(0.08, xf.call(Vector3(0, top + 0.28, 0)), GOLD, 10)
			for s in [-1.0, 1.0]:
				b.cone(0.03, 0.06, xf.call(Vector3(0, top + 0.37, s * 0.05)), GOLD, 6)
			b.ellipsoid(Vector3(0.07, 0.02, 0.07), xf.call(Vector3(0.0, top + 0.35, 0)), Color(0.85, 0.2, 0.35), 10)
			b.cylinder(0.015, 0.02, 0.18, xf.call(Vector3(-face * 0.1, top + 0.08, 0), Vector3.ONE, Vector3(0.0, 0.0, face * 0.6)), GOLD, 6)
