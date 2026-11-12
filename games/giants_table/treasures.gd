extends Node3D
## GIANT'S TABLE: SPARKY'S TABLE TREASURES grow on the rim (deep.gd TREASURES, one every TREASURE_EVERY waves cleared,
## saved for good; the "treasures" state tells every machine how many). They sit between the lantern posts, nearest
## the Giant first: a candle, a teacup, a cupcake, a toy drum, a flowerpot, a bell, a lollipop, a toy boat, a jar of
## sweets, a cocoa mug. The village houses never grow (David): the table's edge does. A new one pops in.
## One merged mesh for the lot (Deck / VR 60 fps), rebuilt only when the count changes.
##   set_count(n, pop)

const MeshKit := preload("res://core/mesh_kit.gd")
const Deep := preload("res://games/giants_table/deep.gd")

const SIZE := 1.0  # ~5 cm for the VR Giant

var main
var count := -1
var mesh: MeshInstance3D
var fresh: MeshInstance3D  # the newest one (pops in)


func set_count(n: int, pop: bool = false) -> void:
	n = clampi(n, 0, Deep.TREASURES.size())
	if n == count:
		return
	var grew := count >= 0 and n > count
	count = n
	for m in [mesh, fresh]:
		if m != null and is_instance_valid(m):
			m.queue_free()
	mesh = null
	fresh = null
	var last := n - 1 if grew and pop else n
	if last > 0:
		var b := MeshKit.Builder.new()
		for i in last:
			_treasure(b, i, Transform3D.IDENTITY)
		mesh = MeshKit.instance(b.build(), false)
		mesh.name = "Treasures"
		add_child(mesh)
	if last < n:
		var b2 := MeshKit.Builder.new()
		_treasure(b2, n - 1, Transform3D.IDENTITY, true)
		fresh = MeshKit.instance(b2.build(), false)
		fresh.name = "NewTreasure"
		add_child(fresh)
		var at := Deep.treasure_slot(n - 1)
		fresh.position = at
		fresh.scale = Vector3.ONE * 0.05
		create_tween().tween_property(fresh, "scale", Vector3.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		main.burst(at + Vector3.UP * 0.8, Color(1.0, 0.85, 0.4), 20, 0.15, false)


## Treasure i into the builder (local: at its rim slot; or around the origin when it pops in on its own).
func _treasure(b: MeshKit.Builder, i: int, _xf: Transform3D, local: bool = false) -> void:
	var at := Vector3.ZERO if local else Deep.treasure_slot(i)
	var face := -Deep.treasure_slot(i)  # facing the fire
	var yaw := atan2(face.x, face.z)
	var s := SIZE
	var x := func(p: Vector3, sc: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> Transform3D:
		return Transform3D(Basis(Vector3.UP, yaw), at) * MeshKit.at(p * s, sc * s, rot)
	match Deep.TREASURES[i]:
		"candle":
			b.cylinder(0.3, 0.32, 0.06, x.call(Vector3(0, 0.03, 0)), Color(0.9, 0.75, 0.3), 12)
			b.cylinder(0.14, 0.14, 0.55, x.call(Vector3(0, 0.33, 0)), Color(0.95, 0.3, 0.3), 10)
			b.cone(0.07, 0.2, x.call(Vector3(0, 0.7, 0)), Color(1.0, 0.75, 0.25), 8, true)
		"teacup":
			b.cylinder(0.32, 0.32, 0.04, x.call(Vector3(0, 0.02, 0)), Color(1.0, 1.0, 1.0), 14)
			b.cylinder(0.24, 0.16, 0.28, x.call(Vector3(0, 0.18, 0)), Color(0.98, 0.98, 1.0), 14)
			b.cylinder(0.22, 0.22, 0.02, x.call(Vector3(0, 0.31, 0)), Color(0.6, 0.35, 0.18), 12)
			b.torus(0.08, 0.025, x.call(Vector3(0.27, 0.19, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.3, 0.55, 1.0), 10, 5)
			b.cylinder(0.245, 0.245, 0.04, x.call(Vector3(0, 0.26, 0)), Color(0.3, 0.55, 1.0), 14)
		"cupcake":
			b.cylinder(0.22, 0.16, 0.25, x.call(Vector3(0, 0.125, 0)), Color(0.4, 0.65, 1.0), 12)
			b.dome(0.25, x.call(Vector3(0, 0.25, 0)), Color(1.0, 0.7, 0.85), 12)
			b.sphere(0.07, x.call(Vector3(0, 0.52, 0)), Color(0.9, 0.12, 0.2), 8)
		"drum":
			b.cylinder(0.3, 0.3, 0.4, x.call(Vector3(0, 0.2, 0)), Color(0.9, 0.2, 0.25), 14)
			b.cylinder(0.31, 0.31, 0.04, x.call(Vector3(0, 0.41, 0)), Color(0.97, 0.95, 0.88), 14)
			for y in [0.03, 0.38]:
				b.cylinder(0.315, 0.315, 0.05, x.call(Vector3(0, y, 0)), Color(1.0, 0.8, 0.25), 14)
			for k in 2:
				b.cylinder(0.02, 0.02, 0.5, x.call(Vector3(-0.1 + k * 0.2, 0.55, 0), Vector3.ONE, Vector3(0, 0, -0.5 + k)), Color(0.85, 0.65, 0.35), 5)
		"flowerpot":
			b.cylinder(0.24, 0.18, 0.32, x.call(Vector3(0, 0.16, 0)), Color(0.8, 0.42, 0.25), 12)
			for k in 3:
				var p := Vector3(-0.12 + k * 0.12, 0.6 + 0.05 * (k % 2), 0.0)
				b.cylinder(0.015, 0.015, 0.3, x.call(p - Vector3(0, 0.15, 0)), Color(0.3, 0.6, 0.25), 4)
				b.sphere(0.08, x.call(p), [Color(1.0, 0.4, 0.6), Color(1.0, 0.85, 0.2), Color(0.55, 0.6, 1.0)][k], 8)
		"bell":
			b.dome(0.26, x.call(Vector3(0, 0.05, 0), Vector3(1.0, 1.6, 1.0)), Color(1.0, 0.8, 0.25), 14)
			b.torus(0.26, 0.03, x.call(Vector3(0, 0.05, 0)), Color(0.95, 0.7, 0.2), 14, 5)
			b.sphere(0.06, x.call(Vector3(0, 0.03, 0)), Color(0.75, 0.55, 0.15), 6)
			b.torus(0.06, 0.02, x.call(Vector3(0, 0.5, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.95, 0.7, 0.2), 8, 4)
		"lollipop":
			b.cylinder(0.02, 0.02, 0.5, x.call(Vector3(0, 0.25, 0)), Color(1.0, 1.0, 1.0), 5)
			b.cylinder(0.22, 0.22, 0.06, x.call(Vector3(0, 0.62, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.35, 0.6), 16)
			b.cylinder(0.14, 0.14, 0.07, x.call(Vector3(0, 0.62, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.9, 0.95), 14)
			b.cylinder(0.06, 0.06, 0.08, x.call(Vector3(0, 0.62, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.4, 0.8, 1.0), 10)
		"boat":
			b.box(Vector3(0.24, 0.14, 0.6), x.call(Vector3(0, 0.07, 0)), Color(0.85, 0.3, 0.25))
			b.box(Vector3(0.26, 0.04, 0.62), x.call(Vector3(0, 0.15, 0)), Color(0.97, 0.95, 0.9))
			b.cylinder(0.015, 0.015, 0.55, x.call(Vector3(0, 0.42, 0)), Color(0.55, 0.35, 0.18), 5)
			b.box(Vector3(0.02, 0.34, 0.26), x.call(Vector3(0, 0.45, 0.13)), Color(1.0, 1.0, 1.0))
			b.box(Vector3(0.02, 0.08, 0.14), x.call(Vector3(0, 0.66, 0.06)), Color(0.3, 0.55, 1.0))
		"jar":
			b.cylinder(0.22, 0.22, 0.42, x.call(Vector3(0, 0.21, 0)), Color(0.75, 0.9, 1.0), 12)
			b.cylinder(0.24, 0.24, 0.07, x.call(Vector3(0, 0.45, 0)), Color(0.9, 0.3, 0.3), 12)
			for k in 6:
				var a := k * TAU / 6.0
				b.sphere(0.07, x.call(Vector3(cos(a) * 0.12, 0.1 + 0.11 * (k % 3), sin(a) * 0.12)),
					[Color(1.0, 0.85, 0.2), Color(1.0, 0.35, 0.6), Color(0.4, 0.85, 0.4)][k % 3], 6)
		_:  # cocoa mug with a marshmallow
			b.cylinder(0.22, 0.2, 0.38, x.call(Vector3(0, 0.19, 0)), Color(0.35, 0.6, 0.95), 12)
			b.cylinder(0.2, 0.2, 0.02, x.call(Vector3(0, 0.37, 0)), Color(0.45, 0.25, 0.12), 12)
			b.box(Vector3(0.1, 0.08, 0.1), x.call(Vector3(0.04, 0.41, 0.02)), Color(1.0, 0.95, 0.95))
			b.torus(0.09, 0.03, x.call(Vector3(0.25, 0.2, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.35, 0.6, 0.95), 10, 5)
