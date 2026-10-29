extends RefCounted
## Gus the gopher's garden round the hole: it GROWS and stays (saved on the host):
##   - one garden ornament for every play-day (a flower pot, a mushroom, a gnome, a sunflower...), up to
##     MAX_PIECES, set on the lawn round whichever hole is being played (never on the green, the toys or the board);
##   - a little gold-centred flower in front of the flag board for every gold star the family has won (up to
##     MAX_FLOWERS).
## Built the same on every machine from [days, stars] (main.gd's "garden" state). One merged mesh, cheap for the Frame.

const MeshKit := preload("res://core/mesh_kit.gd")
const HoleGen := preload("res://games/mini_golf_party/holegen.gd")

const KINDS: Array[String] = ["flowerpot", "mushroom", "gnome", "sunflower", "birdhouse", "fountain", "lantern",
	"appletree", "bench", "rosebush", "snail", "pumpkin"]
const MAX_PIECES := 14
const MAX_FLOWERS := 24
const PETALS: Array[Color] = [Color(1.0, 0.55, 0.7), Color(1.0, 1.0, 1.0), Color(0.75, 0.6, 1.0), Color(1.0, 0.6, 0.35)]


## The garden for hole `d`: `days` ornaments and `stars` star flowers.
static func build(d: Dictionary, days: int, stars: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Garden"
	var b := MeshKit.Builder.new()
	var n := clampi(days, 0, MAX_PIECES)
	var sp := spots(d, n)
	for i in sp.size():
		var p: Vector2 = sp[i]
		var yaw := atan2(-((d["cup"] as Vector2).x - p.x), -((d["cup"] as Vector2).y - p.y))  # faces the hole
		_piece(b, KINDS[i % KINDS.size()], Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0.0, p.y)))
	var bp := HoleGen.board_pos(d)
	for k in clampi(stars, 0, MAX_FLOWERS):
		var row := k / 12
		var x := -0.77 + (k % 12) * 0.14 + row * 0.07
		var at := Vector3(bp.x + x, 0.0, bp.y + 0.16 + row * 0.12)
		b.tube(at, at + Vector3(0.0, 0.1, 0.0), 0.006, 0.006, Color(0.3, 0.6, 0.3), 4)
		for q in 5:
			var a := TAU * q / 5.0
			b.sphere(0.018, MeshKit.at(at + Vector3(cos(a) * 0.022, 0.1, sin(a) * 0.022)), PETALS[k % PETALS.size()], 5)
		b.sphere(0.014, MeshKit.at(at + Vector3(0.0, 0.11, 0.0)), Color(1.0, 0.85, 0.2), 5)
	if not b.is_empty():
		root.add_child(MeshKit.instance(b.build(), false))
	return root


## Where the ornaments go: round the hole's edges, off the green, clear of the toys, the board and Gus,
## nearest the cup first (the end every camera looks at). Deterministic for the hole.
static func spots(d: Dictionary, count: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if count <= 0:
		return out
	var ol: Array = d["outline"]
	var poly := PackedVector2Array(ol)
	var r := Rect2(ol[0], Vector2.ZERO)
	for p in ol:
		r = r.expand(p)
	var cand: Array = []
	for ring in [0.75, 1.5]:
		var g := r.grow(ring)
		var steps_z := maxi(2, int(g.size.y / 0.8))
		for k in steps_z + 1:
			var z := g.position.y + g.size.y * k / steps_z
			cand.append(Vector2(g.position.x, z))
			cand.append(Vector2(g.end.x, z))
		var steps_x := maxi(2, int(g.size.x / 0.8))
		for k in range(1, steps_x):
			cand.append(Vector2(g.position.x + g.size.x * k / steps_x, g.position.y))
		# The inside of a bend (an L or a dogleg leaves lawn there).
		for k in steps_z + 1:
			for j in range(1, steps_x):
				cand.append(Vector2(r.position.x + r.size.x * j / steps_x, r.position.y + r.size.y * k / steps_z))
	var cup: Vector2 = d["cup"]
	cand.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(cup) < b.distance_squared_to(cup))
	var clear := HoleGen.keep_clear(d)
	for p in cand:
		if out.size() >= count:
			break
		if Geometry2D.is_point_in_polygon(p, poly) or HoleGen.wall_dist(ol, p) < 0.4:
			continue
		var ok := true
		for kc in clear:
			if p.distance_to(kc[0]) < float(kc[1]) + 0.35:
				ok = false
				break
		for q in out:
			if p.distance_to(q) < 0.6:
				ok = false
				break
		if ok:
			out.append(p)
	return out


## One ornament on its own (tests, and anything that wants to show one).
static func piece(kind: String) -> Node3D:
	var b := MeshKit.Builder.new()
	_piece(b, kind, Transform3D.IDENTITY)
	if b.is_empty():
		return null
	var n := Node3D.new()
	n.add_child(MeshKit.instance(b.build(), false))
	return n


static func _piece(b: MeshKit.Builder, kind: String, xf: Transform3D) -> void:
	match kind:
		"flowerpot":
			b.cylinder(0.12, 0.09, 0.16, _at(xf, Vector3(0, 0.08, 0)), Color(0.85, 0.45, 0.3), 10)
			b.sphere(0.12, _at(xf, Vector3(0, 0.2, 0)), Color(0.3, 0.65, 0.3), 8)
			for k in 4:
				var a := TAU * k / 4.0
				b.sphere(0.04, _at(xf, Vector3(cos(a) * 0.08, 0.27, sin(a) * 0.08)), PETALS[k], 6)
		"mushroom":
			b.cylinder(0.05, 0.06, 0.16, _at(xf, Vector3(0, 0.08, 0)), Color(0.98, 0.95, 0.88), 8)
			b.dome(0.16, _at(xf, Vector3(0, 0.15, 0), Vector3(1.0, 0.75, 1.0)), Color(0.95, 0.25, 0.25), 12)
			for k in 5:
				var a := TAU * k / 5.0
				b.sphere(0.025, _at(xf, Vector3(cos(a) * 0.1, 0.22, sin(a) * 0.1)), Color.WHITE, 5)
		"gnome":
			b.cone(0.11, 0.24, _at(xf, Vector3(0, 0.12, 0)), Color(0.3, 0.45, 0.9), 10)
			b.sphere(0.065, _at(xf, Vector3(0, 0.27, 0)), Color(1.0, 0.8, 0.7), 10)
			b.cone(0.06, 0.12, _at(xf, Vector3(0, 0.22, -0.05), Vector3.ONE, Vector3(PI, 0, 0)), Color.WHITE, 8)
			b.cone(0.07, 0.2, _at(xf, Vector3(0, 0.4, 0)), Color(0.9, 0.2, 0.25), 10)
			b.sphere(0.02, _at(xf, Vector3(0, 0.28, -0.065)), Color(1.0, 0.6, 0.6), 5)
		"sunflower":
			b.tube(xf * Vector3(0, 0, 0), xf * Vector3(0, 0.6, 0), 0.02, 0.015, Color(0.3, 0.6, 0.3), 6)
			b.cylinder(0.14, 0.14, 0.02, _at(xf, Vector3(0, 0.66, -0.02), Vector3.ONE, Vector3(PI * 0.4, 0, 0)), Color(1.0, 0.85, 0.15), 12)
			b.cylinder(0.07, 0.07, 0.03, _at(xf, Vector3(0, 0.66, -0.03), Vector3.ONE, Vector3(PI * 0.4, 0, 0)), Color(0.45, 0.28, 0.12), 10)
			b.ellipsoid(Vector3(0.08, 0.02, 0.04), _at(xf, Vector3(0.07, 0.3, 0)), Color(0.3, 0.65, 0.3), 6)
		"birdhouse":
			b.box(Vector3(0.05, 0.6, 0.05), _at(xf, Vector3(0, 0.3, 0)), Color(0.6, 0.4, 0.25))
			b.box(Vector3(0.2, 0.2, 0.2), _at(xf, Vector3(0, 0.7, 0)), Color(0.4, 0.75, 1.0))
			b.cone(0.18, 0.14, _at(xf, Vector3(0, 0.87, 0), Vector3.ONE, Vector3(0, PI * 0.25, 0)), Color(0.9, 0.3, 0.3), 4)
			b.cylinder(0.035, 0.035, 0.02, _at(xf, Vector3(0, 0.72, -0.1), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.15, 0.1, 0.1), 8)
		"fountain":
			b.cylinder(0.3, 0.32, 0.14, _at(xf, Vector3(0, 0.07, 0)), Color(0.8, 0.8, 0.82), 16)
			b.cylinder(0.27, 0.27, 0.02, _at(xf, Vector3(0, 0.13, 0)), Color(0.4, 0.75, 1.0), 16)
			b.cylinder(0.04, 0.05, 0.35, _at(xf, Vector3(0, 0.3, 0)), Color(0.8, 0.8, 0.82), 8)
			b.cylinder(0.12, 0.06, 0.06, _at(xf, Vector3(0, 0.48, 0)), Color(0.8, 0.8, 0.82), 12)
			b.sphere(0.05, _at(xf, Vector3(0, 0.55, 0)), Color(0.6, 0.85, 1.0), 8)
		"lantern":
			b.box(Vector3(0.04, 0.7, 0.04), _at(xf, Vector3(0, 0.35, 0)), Color(0.25, 0.25, 0.3))
			b.sphere(0.08, _at(xf, Vector3(0, 0.76, 0)), Color(1.0, 0.85, 0.4), 10, true)
			b.cone(0.1, 0.07, _at(xf, Vector3(0, 0.86, 0)), Color(0.25, 0.25, 0.3), 8)
		"appletree":
			b.cylinder(0.05, 0.07, 0.5, _at(xf, Vector3(0, 0.25, 0)), Color(0.55, 0.38, 0.22), 8)
			b.sphere(0.3, _at(xf, Vector3(0, 0.7, 0)), Color(0.3, 0.68, 0.32), 10)
			for k in 5:
				var a := TAU * k / 5.0 + 0.3
				b.sphere(0.045, _at(xf, Vector3(cos(a) * 0.26, 0.62 + (k % 2) * 0.12, sin(a) * 0.26)), Color(0.95, 0.2, 0.2), 6)
		"bench":
			b.box(Vector3(0.6, 0.04, 0.2), _at(xf, Vector3(0, 0.22, 0)), Color(0.75, 0.5, 0.3))
			b.box(Vector3(0.6, 0.16, 0.03), _at(xf, Vector3(0, 0.36, 0.09)), Color(0.75, 0.5, 0.3))
			for sx in [-0.26, 0.26]:
				b.box(Vector3(0.04, 0.22, 0.18), _at(xf, Vector3(sx, 0.11, 0)), Color(0.3, 0.3, 0.32))
		"rosebush":
			b.sphere(0.2, _at(xf, Vector3(0, 0.18, 0), Vector3(1.2, 0.9, 1.0)), Color(0.22, 0.55, 0.28), 10)
			for k in 7:
				var a := TAU * k / 7.0
				b.sphere(0.04, _at(xf, Vector3(cos(a) * 0.17, 0.22 + (k % 3) * 0.05, sin(a) * 0.15)), Color(1.0, 0.35, 0.5), 6)
		"snail":
			b.ellipsoid(Vector3(0.05, 0.035, 0.16), _at(xf, Vector3(0, 0.035, 0)), Color(0.75, 0.85, 0.5), 8)
			b.torus(0.07, 0.04, _at(xf, Vector3(0, 0.11, 0.03), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.95, 0.6, 0.3), 12, 6)
			b.sphere(0.03, _at(xf, Vector3(0, 0.11, 0.03)), Color(0.85, 0.45, 0.25), 6)
			b.tube(xf * Vector3(0.02, 0.05, -0.13), xf * Vector3(0.03, 0.12, -0.16), 0.006, 0.006, Color(0.75, 0.85, 0.5), 4)
			b.tube(xf * Vector3(-0.02, 0.05, -0.13), xf * Vector3(-0.03, 0.12, -0.16), 0.006, 0.006, Color(0.75, 0.85, 0.5), 4)
		"pumpkin":
			for k in 6:
				var a := TAU * k / 6.0
				b.ellipsoid(Vector3(0.09, 0.13, 0.09), _at(xf, Vector3(cos(a) * 0.08, 0.13, sin(a) * 0.08)), Color(1.0, 0.55, 0.15), 8)
			b.cylinder(0.015, 0.02, 0.08, _at(xf, Vector3(0, 0.28, 0)), Color(0.35, 0.5, 0.2), 6)


static func _at(xf: Transform3D, p: Vector3, s: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> Transform3D:
	return xf * MeshKit.at(p, s, rot)
