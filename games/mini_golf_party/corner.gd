extends Node3D
## GUS'S GARDEN CORNER (deep.gd CORNER): every CORNER_EVERY gold stars the column down the left of Gus's lawn gets a
## new piece for good - a VEG PATCH, a GREENHOUSE, a POND with a duck, a BEEHIVE, a SCARECROW, a RAINBOW ARCH, a garden
## WINDMILL and a TREEHOUSE. Every machine builds the same from the star count (main.gd's "garden" state). The newest
## piece pops in with confetti. One merged mesh; the windmill's sails turn slowly.
##   set_pieces(n, pop)

const MeshKit := preload("res://core/mesh_kit.gd")
const Deep := preload("res://games/mini_golf_party/deep.gd")

var main
var count := -1
var body: MeshInstance3D
var sails: Node3D
var t := 0.0


func set_pieces(n: int, pop: bool = false) -> void:
	n = clampi(n, 0, Deep.CORNER.size())
	if n == count:
		return
	var grew := count >= 0 and n > count
	count = n
	for c in get_children():
		c.queue_free()
	body = null
	sails = null
	if n == 0:
		return
	var b := MeshKit.Builder.new()
	for i in n:
		var p := Deep.corner_spot(i)
		_piece(b, Deep.CORNER[i], Vector3(p.x, 0.0, p.y))
	body = MeshKit.instance(b.build())
	body.name = "GardenCorner"
	add_child(body)
	if grew and pop:
		var at := Deep.corner_spot(n - 1)
		main.celebrate_fx(Vector3(at.x, 1.2, at.y), Color(1.0, 0.85, 0.3))


func _piece(b: MeshKit.Builder, kind: String, at: Vector3) -> void:
	var wood := Color(0.6, 0.4, 0.22)
	match kind:
		"veg":  # three rows of carrots and cabbages in a wooden bed
			b.box(Vector3(1.1, 0.12, 0.9), MeshKit.at(at + Vector3(0, 0.06, 0)), wood)
			b.box(Vector3(1.0, 0.04, 0.8), MeshKit.at(at + Vector3(0, 0.12, 0)), Color(0.4, 0.26, 0.15))
			for r in 3:
				for c in 4:
					var p := at + Vector3(-0.36 + c * 0.24, 0.14, -0.27 + r * 0.27)
					if r == 1:
						b.sphere(0.08, MeshKit.at(p + Vector3(0, 0.05, 0)), Color(0.45, 0.8, 0.35), 8)
					else:
						b.cone(0.05, 0.12, MeshKit.at(p + Vector3(0, 0.06, 0)), Color(0.3, 0.7, 0.3), 6)
						b.sphere(0.03, MeshKit.at(p), Color(1.0, 0.55, 0.1), 6)
		"greenhouse":
			b.box(Vector3(1.0, 0.7, 0.8), MeshKit.at(at + Vector3(0, 0.35, 0)), Color(0.75, 0.92, 1.0))
			b.cone(0.72, 0.35, MeshKit.at(at + Vector3(0, 0.88, 0), Vector3(1.0, 1.0, 0.8), Vector3(0, PI * 0.25, 0)), Color(0.8, 0.95, 1.0), 4)
			for x in [-0.5, 0.5]:
				b.box(Vector3(0.04, 0.72, 0.82), MeshKit.at(at + Vector3(x, 0.36, 0)), Color.WHITE)
			b.sphere(0.12, MeshKit.at(at + Vector3(-0.2, 0.2, 0.1)), Color(0.95, 0.25, 0.25), 8)
			b.sphere(0.12, MeshKit.at(at + Vector3(0.2, 0.2, -0.1)), Color(0.4, 0.8, 0.35), 8)
		"pond":
			b.cylinder(0.6, 0.6, 0.03, MeshKit.at(at + Vector3(0, 0.015, 0)), Color(0.35, 0.7, 1.0), 18)
			b.torus(0.62, 0.06, MeshKit.at(at + Vector3(0, 0.03, 0)), Color(0.72, 0.7, 0.66), 18, 5)
			b.ellipsoid(Vector3(0.09, 0.07, 0.12), MeshKit.at(at + Vector3(0.1, 0.08, 0)), Color(1.0, 0.88, 0.2), 10)
			b.sphere(0.055, MeshKit.at(at + Vector3(0.1, 0.17, -0.08)), Color(1.0, 0.9, 0.25), 8)
			b.cone(0.025, 0.05, MeshKit.at(at + Vector3(0.1, 0.16, -0.14), Vector3.ONE, Vector3(-PI * 0.5, 0, 0)), Color(1.0, 0.5, 0.15), 6)
			b.cylinder(0.12, 0.12, 0.01, MeshKit.at(at + Vector3(-0.25, 0.035, 0.2)), Color(0.3, 0.7, 0.35), 10)
		"hive":
			b.box(Vector3(0.08, 0.5, 0.08), MeshKit.at(at + Vector3(0, 0.25, 0)), wood)
			for k in 4:
				b.cylinder(0.24 - k * 0.03, 0.26 - k * 0.03, 0.12, MeshKit.at(at + Vector3(0, 0.56 + k * 0.11, 0)), Color(1.0, 0.8, 0.3), 12)
			b.sphere(0.04, MeshKit.at(at + Vector3(0, 0.6, -0.25)), Color(0.15, 0.1, 0.05), 6)
			for k in 3:
				var a := TAU * k / 3.0
				b.ellipsoid(Vector3(0.03, 0.025, 0.02), MeshKit.at(at + Vector3(cos(a) * 0.4, 0.9 + 0.1 * k, sin(a) * 0.4)), Color(1.0, 0.85, 0.1), 6)
		"scarecrow":
			b.box(Vector3(0.06, 1.2, 0.06), MeshKit.at(at + Vector3(0, 0.6, 0)), wood)
			b.box(Vector3(0.9, 0.06, 0.06), MeshKit.at(at + Vector3(0, 0.95, 0)), wood)
			b.box(Vector3(0.4, 0.45, 0.2), MeshKit.at(at + Vector3(0, 0.85, 0)), Color(0.35, 0.55, 0.9))
			b.sphere(0.15, MeshKit.at(at + Vector3(0, 1.25, 0)), Color(0.95, 0.85, 0.6), 10)
			b.cylinder(0.25, 0.25, 0.03, MeshKit.at(at + Vector3(0, 1.36, 0)), Color(0.85, 0.7, 0.3), 12)
			b.cone(0.13, 0.14, MeshKit.at(at + Vector3(0, 1.44, 0)), Color(0.85, 0.7, 0.3), 10)
			b.sphere(0.03, MeshKit.at(at + Vector3(0, 1.24, -0.15)), Color(1.0, 0.5, 0.1), 6)
		"arch":
			var cols: Array[Color] = [Color(1, 0.3, 0.3), Color(1, 0.6, 0.2), Color(1, 0.9, 0.2), Color(0.3, 0.9, 0.4), Color(0.3, 0.6, 1)]
			for k in 11:
				var a := PI * float(k) / 10.0
				for c in cols.size():
					var r := 0.6 - 0.07 * c
					b.box(Vector3(0.08, 0.08, 0.08), MeshKit.at(at + Vector3(cos(a) * r, 0.1 + sin(a) * r * 1.5, 0)), cols[c])
		"windmill":
			b.cylinder(0.25, 0.35, 1.2, MeshKit.at(at + Vector3(0, 0.6, 0)), Color(0.98, 0.92, 0.8), 8)
			b.cone(0.32, 0.35, MeshKit.at(at + Vector3(0, 1.38, 0)), Color(0.9, 0.3, 0.3), 8)
			b.box(Vector3(0.16, 0.26, 0.03), MeshKit.at(at + Vector3(0, 0.15, -0.34)), Color(0.5, 0.32, 0.18))
			sails = Node3D.new()
			sails.position = at + Vector3(0, 1.05, -0.36)
			var sb := MeshKit.Builder.new()
			for s in 4:
				var ang := s * PI * 0.5
				sb.box(Vector3(0.12, 0.5, 0.02), Transform3D(Basis(Vector3.BACK, ang), Vector3(sin(ang), -cos(ang), 0.0) * 0.28),
					Color(1.0, 0.97, 0.9) if s % 2 == 0 else Color(1.0, 0.45, 0.4))
			sb.sphere(0.05, MeshKit.at(Vector3.ZERO), Color(1.0, 0.85, 0.3), 8)
			sails.add_child(MeshKit.instance(sb.build(), false))
			add_child(sails)
		_:  # treehouse: a big tree with a little red-roofed house in it and a ladder
			b.cylinder(0.14, 0.2, 1.4, MeshKit.at(at + Vector3(0, 0.7, 0)), Color(0.5, 0.33, 0.18), 8)
			b.sphere(0.65, MeshKit.at(at + Vector3(0, 1.8, 0)), Color(0.3, 0.65, 0.3), 10)
			b.box(Vector3(0.55, 0.4, 0.5), MeshKit.at(at + Vector3(0, 1.35, -0.25)), Color(0.85, 0.6, 0.35))
			b.cone(0.45, 0.25, MeshKit.at(at + Vector3(0, 1.67, -0.25), Vector3.ONE, Vector3(0, PI * 0.25, 0)), Color(0.9, 0.3, 0.3), 4)
			b.box(Vector3(0.14, 0.16, 0.02), MeshKit.at(at + Vector3(0, 1.35, -0.51)), Color(0.4, 0.75, 1.0))
			for k in 5:
				b.box(Vector3(0.22, 0.03, 0.03), MeshKit.at(at + Vector3(0.3, 0.2 + k * 0.22, -0.4)), wood)


func _process(delta: float) -> void:
	t += delta
	if sails != null and is_instance_valid(sails):
		sails.rotation.z = t * 0.9
