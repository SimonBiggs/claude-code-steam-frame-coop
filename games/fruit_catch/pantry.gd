extends Node3D
## NUTMEG'S PANTRY (deep.gd PANTRY): every PANTRY_EVERY finished dishes the pantry beside the park (right of the
## giant, just outside the park) gets a new piece for good - a JAM SHELF, a PIE TABLE, a JUICE BARREL, HONEY POTS, a
## big CAKE, FRUIT CRATES, LANTERNS and an APPLE CART. Every machine builds the same from the piece count (the "pantry"
## state). The newest piece pops in. One merged mesh, facing the park.
##   set_pieces(n, pop)

const MeshKit := preload("res://core/mesh_kit.gd")
const Deep := preload("res://games/fruit_catch/deep.gd")
const Art := preload("res://games/fruit_catch/art.gd")

var main
var count := -1
var body: MeshInstance3D


func set_pieces(n: int, pop: bool = false) -> void:
	n = clampi(n, 0, Deep.PANTRY.size())
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
		_piece(b, Deep.PANTRY[i], Deep.pantry_spot(i))
	body = MeshKit.instance(b.build(), false)
	body.name = "Pantry"
	add_child(body)
	if grew and pop:
		var at := Deep.pantry_spot(n - 1)
		main.burst(at + Vector3(0, 1.2, 0), Color(1.0, 0.85, 0.3), 26, 3.5)
		main.sfx.play_at("sparkle", at, -2.0, 1.0)


## One piece standing at `at`, its front towards the park (-X).
func _piece(b: MeshKit.Builder, kind: String, at: Vector3) -> void:
	var wood := Art.BARK
	var face := Basis(Vector3.UP, -PI * 0.5)  # +Z (a piece's front) turned to -X (the park)
	var xf := func(p: Vector3, sc: Vector3 = Vector3.ONE) -> Transform3D:
		return Transform3D(face, at) * MeshKit.at(p, sc)
	match kind:
		"jam":  # a shelf of jam jars
			b.box(Vector3(1.2, 0.08, 0.4), xf.call(Vector3(0, 0.6, 0)), wood)
			b.box(Vector3(1.2, 0.08, 0.4), xf.call(Vector3(0, 1.1, 0)), wood)
			for s in [-0.58, 0.58]:
				b.box(Vector3(0.06, 1.3, 0.4), xf.call(Vector3(s, 0.65, 0)), wood.darkened(0.15))
			for k in 8:
				var c: Color = Art.FRUIT_COLORS[k % 4]
				b.cylinder(0.08, 0.08, 0.18, xf.call(Vector3(-0.42 + (k % 4) * 0.28, 0.74 + 0.5 * float(k / 4), 0.05)), c, 8)
				b.cylinder(0.09, 0.09, 0.04, xf.call(Vector3(-0.42 + (k % 4) * 0.28, 0.85 + 0.5 * float(k / 4), 0.05)), Color(0.95, 0.2, 0.25), 8)
		"pies":  # a table with three pies
			b.box(Vector3(1.2, 0.08, 0.7), xf.call(Vector3(0, 0.7, 0)), wood)
			for s in [Vector3(-0.5, 0.35, -0.28), Vector3(0.5, 0.35, -0.28), Vector3(-0.5, 0.35, 0.28), Vector3(0.5, 0.35, 0.28)]:
				b.box(Vector3(0.07, 0.7, 0.07), xf.call(s), wood.darkened(0.15))
			for k in 3:
				b.cylinder(0.17, 0.15, 0.09, xf.call(Vector3(-0.38 + k * 0.38, 0.79, 0)), Color(0.92, 0.7, 0.38), 12)
				b.cylinder(0.13, 0.13, 0.02, xf.call(Vector3(-0.38 + k * 0.38, 0.84, 0)), Art.FRUIT_COLORS[k], 12)
		"juice":  # a juice barrel and bottles
			b.cylinder(0.38, 0.42, 0.9, xf.call(Vector3(0, 0.45, 0)), wood, 14)
			b.cylinder(0.43, 0.43, 0.06, xf.call(Vector3(0, 0.25, 0)), Color(0.4, 0.4, 0.45), 14)
			b.cylinder(0.43, 0.43, 0.06, xf.call(Vector3(0, 0.7, 0)), Color(0.4, 0.4, 0.45), 14)
			for k in 3:
				b.cylinder(0.06, 0.07, 0.3, xf.call(Vector3(-0.2 + k * 0.2, 1.05, 0)), Art.FRUIT_COLORS[1].lightened(0.1 * k), 8)
		"honey":  # golden honey pots on a stump
			b.cylinder(0.35, 0.4, 0.45, xf.call(Vector3(0, 0.22, 0)), wood, 12)
			for k in 3:
				var p := Vector3(-0.17 + k * 0.17, 0.6, 0.06 * (k % 2))
				b.sphere(0.13, xf.call(p, Vector3(1.0, 0.9, 1.0)), Color(1.0, 0.72, 0.15), 10)
				b.cylinder(0.08, 0.08, 0.05, xf.call(p + Vector3(0, 0.12, 0)), Color(0.85, 0.55, 0.1), 8)
		"cake":  # a big three-tier fruit cake
			b.cylinder(0.45, 0.45, 0.3, xf.call(Vector3(0, 0.15, 0)), Color(1.0, 0.92, 0.85), 16)
			b.cylinder(0.33, 0.33, 0.28, xf.call(Vector3(0, 0.44, 0)), Color(1.0, 0.75, 0.82), 16)
			b.cylinder(0.21, 0.21, 0.26, xf.call(Vector3(0, 0.71, 0)), Color(1.0, 0.92, 0.85), 16)
			for k in 4:
				b.sphere(0.06, xf.call(Vector3(cos(k * 1.57) * 0.1, 0.88, sin(k * 1.57) * 0.1)), Art.FRUIT_COLORS[k], 6)
		"crates":  # crates of each fruit
			for k in 4:
				var p := Vector3(-0.35 + (k % 2) * 0.7, 0.2 + 0.4 * float(k / 2), 0.0)
				b.box(Vector3(0.6, 0.38, 0.5), xf.call(p), wood.lightened(0.15))
				for j in 4:
					b.sphere(0.09, xf.call(p + Vector3(-0.15 + (j % 2) * 0.3, 0.2, -0.1 + float(j / 2) * 0.2)), Art.FRUIT_COLORS[k], 6)
		"lanterns":  # a post with glowing lanterns
			b.cylinder(0.05, 0.06, 2.2, xf.call(Vector3(0, 1.1, 0)), wood.darkened(0.2), 8)
			b.box(Vector3(1.1, 0.06, 0.06), xf.call(Vector3(0, 2.1, 0)), wood.darkened(0.2))
			for s in [-0.45, 0.45]:
				b.box(Vector3(0.2, 0.28, 0.2), xf.call(Vector3(s, 1.85, 0)), Color(1.0, 0.85, 0.4), true)
		_:  # cart: an apple cart with big wheels
			b.box(Vector3(1.3, 0.35, 0.8), xf.call(Vector3(0, 0.6, 0)), wood.lightened(0.1))
			for s in [-1.0, 1.0]:
				b.cylinder(0.32, 0.32, 0.08, Transform3D(face, at) * MeshKit.at(Vector3(0.3 * s, 0.32, 0.44 * s), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), wood.darkened(0.25), 12)
				b.cylinder(0.32, 0.32, 0.08, Transform3D(face, at) * MeshKit.at(Vector3(-0.3 * s, 0.32, 0.44 * s), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), wood.darkened(0.25), 12)
			for j in 10:
				b.sphere(0.11, xf.call(Vector3(-0.45 + (j % 5) * 0.22, 0.86 + 0.08 * float(j / 5), -0.15 + 0.3 * float(j / 5))), Art.FRUIT_COLORS[0], 8)
