extends Node3D
## PARTY BOARD: MANGO'S PARTY HALL (deep.gd HALL_STEPS): Mango's trophy wall (festival.gd) grows into a party hall, one
## step per finished party with a person playing (saved hall_n on the host, sent in the "deep" state): posts, bunting,
## a striped roof, balloons, a disco ball, fairy lights, a giant cake on the roof and a gold star on top - and a
## present for every party stacked beside the wall (up to deep.gd HALL_PRESENTS). The newest step bounces in. Gifts
## open as it grows (deep.gd GIFTS unlock). Under main.stage (board units), one merged mesh: cheap.
##   set_hall(n)

const MeshKit := preload("res://core/mesh_kit.gd")
const Festival := preload("res://games/party_board/festival.gd")
const Deep := preload("res://games/party_board/deep.gd")

const MANGO := Color(1.0, 0.6, 0.15)
const WHITE := Color(0.97, 0.96, 0.92)
const GOLD := Color(1.0, 0.82, 0.25)
const COLS: Array[Color] = [Color(1.0, 0.35, 0.4), Color(1.0, 0.85, 0.3), Color(0.35, 0.65, 1.0), Color(0.5, 0.9, 0.45),
	Color(0.85, 0.5, 1.0)]
## (wall-local: +x along the wall, +z towards the island, y up; the wall is 3.4 wide and 3 tall)
const POST_X := 2.05
const POST_Z: Array[float] = [-0.45, 0.85]
const POST_H := 3.9
const ROOF_R := 2.4
const ROOF_Z := 0.2

var n := -1
var mesh_node: MeshInstance3D
var pop := 0.0


## Every machine: the hall after n finished parties.
func set_hall(new_n: int) -> void:
	if new_n == n:
		return
	var grew := n >= 0 and new_n > n
	n = new_n
	if mesh_node != null and is_instance_valid(mesh_node):
		mesh_node.queue_free()
	mesh_node = null
	if n <= 0:
		return
	mesh_node = MeshKit.instance(build(n), false)
	mesh_node.name = "PartyHall"
	add_child(mesh_node)
	pop = 0.0 if grew else 1.0
	if grew:
		mesh_node.scale = Vector3(1.0, 0.7, 1.0)


func _process(delta: float) -> void:
	if mesh_node == null or not is_instance_valid(mesh_node) or pop >= 1.0:
		return
	pop = minf(1.0, pop + delta * 1.5)
	mesh_node.scale = Vector3(1.0, 0.7 + 0.3 * pop + 0.15 * sin(pop * PI), 1.0)


static func build(count: int) -> ArrayMesh:
	var b := MeshKit.builder()
	var p := Festival.wall_spot()
	var inward := Vector3(-p.x, 0, -p.z).normalized()
	var basis := Basis(Vector3.UP, atan2(inward.x, inward.z))
	var at := func(v: Vector3, sc: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> Transform3D:
		return Transform3D(basis * Basis.from_euler(rot).scaled(sc), p + basis * v)
	var steps := Deep.hall_steps(count)
	if steps.has("posts"):
		for sx in [-POST_X, POST_X]:
			for z in POST_Z:
				b.cylinder(0.12, 0.15, POST_H, at.call(Vector3(sx, POST_H * 0.5, z)), WHITE, 8)
				b.torus(0.16, 0.05, at.call(Vector3(sx, 0.6, z)), MANGO, 10, 4)
	if steps.has("bunting"):
		for z in POST_Z:
			for k in 7:
				var f := (k + 0.5) / 7.0
				var q := Vector3(lerpf(-POST_X, POST_X, f), POST_H - 0.25 - sin(f * PI) * 0.45, z)
				b.cone(0.2, 0.4, at.call(q + Vector3(0, -0.18, 0), Vector3(1, 1, 0.2), Vector3(PI, 0, 0)), COLS[k % COLS.size()], 4)
	if steps.has("roof"):  # a striped party-tent roof: an orange cone with white ribs
		var base := Vector3(0, POST_H, ROOF_Z)
		b.cone(ROOF_R, 1.5, at.call(base + Vector3(0, 0.75, 0)), MANGO, 16)
		var tip := base + Vector3(0, 1.5, 0)
		for k in 8:
			var a := k * TAU / 8.0
			var rim := base + Vector3(cos(a) * ROOF_R, 0.0, sin(a) * ROOF_R)
			var d := (tip - rim).normalized()
			var tg := Vector3(-sin(a), 0.0, cos(a))
			var nb := Basis(tg, d, tg.cross(d))
			var mid := (rim + tip) * 0.5 + tg.cross(d) * 0.04
			b.box(Vector3(0.2, rim.distance_to(tip), 0.05), Transform3D(basis * nb, p + basis * mid), WHITE)
		b.torus(ROOF_R * 0.98, 0.08, at.call(base + Vector3(0, 0.02, 0)), GOLD, 20, 4)
	if steps.has("balloons"):
		var k2 := 0
		for sx in [-POST_X, POST_X]:
			for z in POST_Z:
				for j in 3:
					var off := Vector3(0.25 * (j - 1), 0.3 * (j % 2), 0.15 * (j - 1))
					b.sphere(0.32, at.call(Vector3(sx, POST_H - 1.0, z) + Vector3(0, -0.4, 0) + off + Vector3(0, -0.6, 0), Vector3(1, 1.2, 1)),
						COLS[(k2 + j) % COLS.size()], 10)
				k2 += 1
	if steps.has("disco"):
		b.cylinder(0.02, 0.02, 0.6, at.call(Vector3(0, POST_H - 0.3, ROOF_Z + 0.6)), Color(0.3, 0.3, 0.35), 4)
		b.sphere(0.42, at.call(Vector3(0, POST_H - 0.85, ROOF_Z + 0.6)), Color(0.85, 0.9, 1.0), 12, true)
	if steps.has("lights"):
		for k in 16:
			var a := k * TAU / 16.0
			b.sphere(0.1, at.call(Vector3(cos(a) * ROOF_R * 0.97, POST_H - 0.05, ROOF_Z + sin(a) * ROOF_R * 0.97)), COLS[k % COLS.size()], 6, true)
	var top := POST_H + 1.5 if steps.has("roof") else POST_H
	if steps.has("cake"):
		for k in 3:
			var r := 0.75 - k * 0.2
			b.cylinder(r, r, 0.4, at.call(Vector3(0, top + 0.2 + k * 0.4, ROOF_Z)), [Color(1.0, 0.75, 0.85), WHITE, Color(0.75, 0.55, 0.4)][k], 14)
		top += 1.2
	if steps.has("star"):
		b.sphere(0.35, at.call(Vector3(0, top + 0.5, ROOF_Z)), GOLD, 10, true)
		for k in 5:
			var a := k * TAU / 5.0
			b.cone(0.16, 0.45, at.call(Vector3(cos(a) * 0.4, top + 0.5 + sin(a) * 0.4, ROOF_Z), Vector3.ONE, Vector3(0, 0, a - PI * 0.5)), GOLD, 4, true)
	# A present for every party, stacked in two piles beside the wall.
	for i in mini(count, Deep.HALL_PRESENTS):
		var side := -1.0 if i % 2 == 0 else 1.0
		var level := i / 2
		var sz := 0.62 - 0.06 * level
		var q := Vector3(side * (POST_X + 0.75), 0.05 + sz * 0.5 + level * 0.56 - 0.03 * level * level, 0.25)
		b.box(Vector3(sz, sz, sz), at.call(q, Vector3.ONE, Vector3(0, 0.3 * side * level, 0)), COLS[i % COLS.size()])
		b.box(Vector3(sz * 1.02, sz * 1.02, 0.08), at.call(q, Vector3.ONE, Vector3(0, 0.3 * side * level, 0)), GOLD)
	return b.build()
