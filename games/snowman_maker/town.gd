extends Node3D
## TUMBLE'S SNOW TOWN (deep.gd TOWN): every TOWN_EVERY snowmen the family makes, the town beside the garden gets a new
## piece for good - an IGLOO house, a SNOW DOG, a lit SNOWY TREE, a SNOW BEAR, a SLED, an ice TOWER, a LAMP post, a
## frozen FOUNTAIN, a COCOA stall and a little snow CASTLE, alternately left and right of the garden. Every machine
## builds the same from the piece count (the "town" state). The newest piece pops in. One merged mesh.
##   set_pieces(n, pop)

const MeshKit := preload("res://core/mesh_kit.gd")
const Deep := preload("res://games/snowman_maker/deep.gd")

const SNOW := Color(0.97, 0.98, 1.0)
const ICE := Color(0.62, 0.85, 1.0)
const WOOD := Color(0.55, 0.36, 0.2)
const COAL := Color(0.12, 0.12, 0.15)

var main
var count := -1
var body: MeshInstance3D


func set_pieces(n: int, pop: bool = false) -> void:
	n = clampi(n, 0, Deep.TOWN.size())
	if n == count:
		return
	var grew := count >= 0 and n > count
	count = n
	if body != null and is_instance_valid(body):
		body.queue_free()
	body = null
	if n == 0:
		return
	var b := MeshKit.Builder.new()
	for i in n:
		_piece(b, Deep.TOWN[i], Deep.town_spot(i))
	body = MeshKit.instance(b.build(), false)
	body.name = "SnowTown"
	add_child(body)
	if grew and pop:
		var at := Deep.town_spot(n - 1)
		main.burst_at(at + Vector3(0, 1.5, 0), [Color(1.0, 0.85, 0.3), Color(0.5, 0.85, 1.0), Color(1, 1, 1)])
		main.sfx.play_at("achievement", at, -2.0, 1.0)


## One piece standing at `at`, its front (+Z) turned to the garden's middle.
func _piece(b: MeshKit.Builder, kind: String, at: Vector3) -> void:
	var to := -Vector3(at.x, 0.0, at.z)
	var face := Basis(Vector3.UP, atan2(to.x, to.z))
	var xf := func(p: Vector3, sc: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> Transform3D:
		return Transform3D(face, at) * MeshKit.at(p, sc, rot)
	match kind:
		"igloo":  # a snow-block igloo with a door tunnel
			b.sphere(1.0, xf.call(Vector3(0, 0, 0), Vector3(1.0, 0.85, 1.0)), SNOW, 14)
			b.cylinder(0.42, 0.42, 0.8, xf.call(Vector3(0, 0.35, 0.95), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), SNOW.darkened(0.04), 12)
			b.cylinder(0.3, 0.3, 0.05, xf.call(Vector3(0, 0.35, 1.36), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), COAL.lightened(0.15), 12)
			b.box(Vector3(0.5, 0.05, 0.05), xf.call(Vector3(0, 0.95, 0.0)), Color(1.0, 0.35, 0.35))
		"dog":  # a snow dog sitting with a red collar
			b.sphere(0.45, xf.call(Vector3(0, 0.45, 0), Vector3(1.0, 1.0, 1.25)), SNOW, 12)
			b.sphere(0.32, xf.call(Vector3(0, 1.05, 0.25)), SNOW, 12)
			b.sphere(0.14, xf.call(Vector3(0, 0.98, 0.55)), SNOW, 8)
			b.sphere(0.05, xf.call(Vector3(0, 1.0, 0.68)), COAL, 6)
			for s in [-1.0, 1.0]:
				b.sphere(0.12, xf.call(Vector3(0.22 * s, 1.3, 0.2), Vector3(0.8, 1.4, 0.6)), SNOW, 8)
				b.sphere(0.04, xf.call(Vector3(0.11 * s, 1.12, 0.52)), COAL, 6)
			b.cylinder(0.24, 0.24, 0.07, xf.call(Vector3(0, 0.8, 0.2)), Color(0.95, 0.2, 0.25), 12)
			b.sphere(0.1, xf.call(Vector3(0, 0.25, -0.6)), SNOW, 8)
		"tree":  # a snowy pine with coloured lights
			b.cylinder(0.12, 0.15, 0.6, xf.call(Vector3(0, 0.3, 0)), WOOD, 8)
			for k in 3:
				b.cone(0.95 - k * 0.25, 0.9, xf.call(Vector3(0, 0.75 + k * 0.6, 0)), Color(0.2, 0.5, 0.3), 12)
				b.cone(0.9 - k * 0.25, 0.25, xf.call(Vector3(0, 1.0 + k * 0.6, 0)), SNOW, 12)
			for k in 8:
				var a := float(k) * TAU / 8.0
				var h := 0.9 + float(k % 3) * 0.5
				var rr := 0.75 - float(k % 3) * 0.22
				b.sphere(0.07, xf.call(Vector3(cos(a) * rr, h, sin(a) * rr)), [Color(1.0, 0.3, 0.3), Color(1.0, 0.85, 0.2), Color(0.3, 0.7, 1.0)][k % 3], 6)
			b.sphere(0.13, xf.call(Vector3(0, 2.75, 0)), Color(1.0, 0.85, 0.2), 8)
		"bear":  # a big snow bear with a blue scarf
			b.sphere(0.6, xf.call(Vector3(0, 0.6, 0), Vector3(1.0, 1.05, 0.9)), SNOW, 12)
			b.sphere(0.4, xf.call(Vector3(0, 1.45, 0.05)), SNOW, 12)
			b.sphere(0.16, xf.call(Vector3(0, 1.36, 0.38)), SNOW.darkened(0.05), 8)
			b.sphere(0.06, xf.call(Vector3(0, 1.42, 0.52)), COAL, 6)
			for s in [-1.0, 1.0]:
				b.sphere(0.13, xf.call(Vector3(0.3 * s, 1.78, 0.0)), SNOW, 8)
				b.sphere(0.05, xf.call(Vector3(0.14 * s, 1.55, 0.36)), COAL, 6)
				b.sphere(0.2, xf.call(Vector3(0.35 * s, 0.18, 0.35)), SNOW, 8)
			b.cylinder(0.36, 0.38, 0.12, xf.call(Vector3(0, 1.15, 0.03)), Color(0.25, 0.5, 1.0), 12)
		"sled":  # a red sled with a snowman riding it
			b.box(Vector3(0.7, 0.08, 1.4), xf.call(Vector3(0, 0.3, 0)), Color(0.9, 0.2, 0.2))
			for s in [-1.0, 1.0]:
				b.box(Vector3(0.05, 0.05, 1.5), xf.call(Vector3(0.3 * s, 0.08, 0.05)), Color(0.6, 0.6, 0.65))
				b.box(Vector3(0.05, 0.25, 0.05), xf.call(Vector3(0.3 * s, 0.18, 0.4)), Color(0.6, 0.6, 0.65))
				b.box(Vector3(0.05, 0.25, 0.05), xf.call(Vector3(0.3 * s, 0.18, -0.4)), Color(0.6, 0.6, 0.65))
			b.sphere(0.3, xf.call(Vector3(0, 0.6, -0.2)), SNOW, 10)
			b.sphere(0.2, xf.call(Vector3(0, 1.0, -0.2)), SNOW, 10)
			b.cone(0.04, 0.16, xf.call(Vector3(0, 1.0, 0.0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.5, 0.1), 6)
		"tower":  # an ice tower with a flag
			b.cylinder(0.55, 0.65, 2.4, xf.call(Vector3(0, 1.2, 0)), ICE, 12)
			for k in 6:
				var a := float(k) * TAU / 6.0
				b.box(Vector3(0.28, 0.3, 0.28), xf.call(Vector3(cos(a) * 0.5, 2.55, sin(a) * 0.5)), ICE.lightened(0.2))
			b.cylinder(0.03, 0.03, 1.0, xf.call(Vector3(0, 3.0, 0)), WOOD, 6)
			b.box(Vector3(0.5, 0.3, 0.03), xf.call(Vector3(0.25, 3.3, 0)), Color(0.4, 0.75, 1.0))
		"lamp":  # a lamp post with a warm light, snow on top
			b.cylinder(0.06, 0.08, 2.4, xf.call(Vector3(0, 1.2, 0)), COAL.lightened(0.2), 8)
			b.box(Vector3(0.36, 0.42, 0.36), xf.call(Vector3(0, 2.55, 0)), Color(1.0, 0.85, 0.45), true)
			b.cone(0.3, 0.2, xf.call(Vector3(0, 2.86, 0)), SNOW, 8)
			b.cylinder(0.3, 0.38, 0.12, xf.call(Vector3(0, 0.06, 0)), SNOW, 10)
		"fountain":  # a frozen fountain with icicles
			b.cylinder(0.9, 1.0, 0.45, xf.call(Vector3(0, 0.22, 0)), SNOW.darkened(0.04), 16)
			b.cylinder(0.75, 0.75, 0.05, xf.call(Vector3(0, 0.46, 0)), ICE, 16)
			b.cylinder(0.12, 0.15, 1.0, xf.call(Vector3(0, 0.95, 0)), SNOW, 8)
			b.cylinder(0.45, 0.3, 0.15, xf.call(Vector3(0, 1.45, 0)), SNOW, 12)
			for k in 6:
				var a := float(k) * TAU / 6.0
				b.cone(0.05, 0.4, xf.call(Vector3(cos(a) * 0.4, 1.2, sin(a) * 0.4), Vector3.ONE, Vector3(PI, 0, 0)), ICE, 6)
		"cocoa":  # a cocoa stall with a striped roof and mugs
			b.box(Vector3(1.4, 0.9, 0.6), xf.call(Vector3(0, 0.45, 0)), WOOD.lightened(0.15))
			for s in [-1.0, 1.0]:
				b.cylinder(0.04, 0.04, 1.0, xf.call(Vector3(0.65 * s, 1.4, 0.25)), WOOD, 6)
			for k in 4:
				b.box(Vector3(0.38, 0.06, 0.9), xf.call(Vector3(-0.55 + k * 0.37, 1.95, 0.1)), [Color(0.95, 0.25, 0.3), SNOW][k % 2])
			for k in 3:
				b.cylinder(0.07, 0.07, 0.14, xf.call(Vector3(-0.35 + k * 0.35, 0.97, 0.15)), [Color(0.3, 0.6, 1.0), Color(1.0, 0.8, 0.2), Color(0.5, 0.85, 0.4)][k], 8)
				b.cylinder(0.06, 0.06, 0.02, xf.call(Vector3(-0.35 + k * 0.35, 1.04, 0.15)), Color(0.45, 0.28, 0.15), 8)
		_:  # castle: a little snow castle with four towers
			b.box(Vector3(1.6, 1.0, 1.4), xf.call(Vector3(0, 0.5, 0)), SNOW)
			for c in [Vector3(-0.8, 0, -0.7), Vector3(0.8, 0, -0.7), Vector3(-0.8, 0, 0.7), Vector3(0.8, 0, 0.7)]:
				b.cylinder(0.28, 0.3, 1.6, xf.call(c + Vector3(0, 0.8, 0)), SNOW.darkened(0.03), 10)
				b.cone(0.33, 0.5, xf.call(c + Vector3(0, 1.85, 0)), Color(0.4, 0.6, 1.0), 10)
			b.box(Vector3(0.45, 0.6, 0.05), xf.call(Vector3(0, 0.3, 0.71)), ICE)
			b.sphere(0.12, xf.call(Vector3(0, 1.2, 0)), Color(1.0, 0.85, 0.2), 8)
