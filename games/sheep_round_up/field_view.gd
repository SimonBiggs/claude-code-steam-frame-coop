extends RefCounted
## SHEEP ROUND-UP: draws a generated field (games/sheep_round_up/fieldgen.gd) and Bo's home farm
## (games/sheep_round_up/farm.gd) on every machine. Everything on the field is merged into a few meshes
## (hedges + bushes + bridges = one draw call, the stream one, flowers / trees one MultiMesh each) so
## big fields stay at 60 fps on a Deck and in VR. Nothing on the field is taller than FieldGen.LOW,
## and the farm's tall things sit beyond FieldGen.CAMERA_RING: a follow camera never ends up behind a
## bush or inside a tree.

const FieldGen := preload("res://games/sheep_round_up/fieldgen.gd")
const Farm := preload("res://games/sheep_round_up/farm.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Creatures := preload("res://core/creatures.gd")
const UiKit := preload("res://core/ui_kit.gd")
const SheepScript := preload("res://games/sheep_round_up/sheep.gd")

const WOOD := Color(0.62, 0.4, 0.22)
const HEDGE := Color(0.24, 0.55, 0.24)
const WATER := Color(0.3, 0.62, 0.95)


## The pen: straw floor, a wooden fence; open gates have glowing dots leading in, shut ones a gate.
static func build_pen(gates: int) -> MeshInstance3D:
	var pen := FieldGen.PEN
	var gap := FieldGen.GAP
	var b := MeshKit.Builder.new()
	b.box(Vector3(pen * 2.0, 0.03, pen * 2.0), MeshKit.at(Vector3(0.0, 0.015, 0.0)), Color(0.95, 0.8, 0.42))
	for side in 4:
		var rot := Basis(Vector3.UP, side * PI * 0.5)
		for seg in [-1.0, 1.0]:
			var s: float = seg
			var a := rot * Vector3(s * gap, 0.0, pen)
			var c := rot * Vector3(s * pen, 0.0, pen)
			for h in [0.22, 0.45]:
				b.tube(a + Vector3.UP * h, c + Vector3.UP * h, 0.04, 0.04, WOOD)
			b.box(Vector3(0.12, 0.62, 0.12), MeshKit.at(a + Vector3.UP * 0.31), WOOD.darkened(0.15))
			b.box(Vector3(0.12, 0.62, 0.12), MeshKit.at(c + Vector3.UP * 0.31), WOOD.darkened(0.15))
		if FieldGen.gate_open(gates, side):
			for k in 3:
				b.sphere(0.06 + k * 0.015, MeshKit.at(rot * Vector3(0.0, 0.08, pen + 1.3 - k * 0.4)), Color(1.0, 0.85, 0.2), 8, true)
		else:
			# A shut gate: white planks with a cross brace (sheep can't get through).
			var gate_c := Color(0.95, 0.93, 0.88)
			for h in [0.16, 0.32, 0.48]:
				b.tube(rot * Vector3(-gap, h, pen), rot * Vector3(gap, h, pen), 0.035, 0.035, gate_c)
			b.tube(rot * Vector3(-gap, 0.14, pen), rot * Vector3(gap, 0.5, pen), 0.03, 0.03, gate_c.darkened(0.1))
	# Sign post on the north fence; the board sits high (2.1 m+) so a camera looking past it sees under it.
	b.box(Vector3(0.12, 2.5, 0.12), MeshKit.at(Vector3(0.0, 1.25, -pen - 0.3)), WOOD.darkened(0.2))
	b.rounded_box(Vector3(1.3, 0.6, 0.08), 0.06, MeshKit.at(Vector3(0.0, 2.45, -pen - 0.3)), Color(0.75, 0.52, 0.3))
	return MeshKit.instance(b.build())


const SIGN_Y := 2.45


## Everything that changes field to field: hedges, bushes, the stream and its bridges, flowers, trees.
static func build_field(f: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Field"
	var b := MeshKit.Builder.new()
	for h in f.get("hedges", []):
		var a := Vector3(h[0], 0.0, h[1])
		var c := Vector3(h[2], 0.0, h[3])
		var d := c - a
		var ln := d.length()
		var yaw := atan2(-d.z, d.x)
		var mid := (a + c) * 0.5
		var hr := FieldGen.HEDGE_R
		var hh := FieldGen.HEDGE_H
		b.rounded_box(Vector3(ln + hr * 2.0, hh * 0.85, hr * 2.0), 0.12, Transform3D(Basis(Vector3.UP, yaw), mid + Vector3.UP * hh * 0.425), HEDGE)
		var k := int(ln / 0.45) + 1
		for i in k + 1:
			var p := a.lerp(c, float(i) / float(k))
			b.sphere(hr * 0.95, MeshKit.at(p + Vector3.UP * (hh - hr * 0.95)), HEDGE.lightened(0.08 * (i % 3)), 7)
	for bu in f.get("bushes", []):
		var p := Vector3(bu[0], 0.0, bu[1])
		var r := float(bu[2])
		b.sphere(r * 0.6, MeshKit.at(p + Vector3.UP * r * 0.55), Color(0.3, 0.62, 0.28), 9)
		for k in 5:
			var a := TAU * k / 5.0 + r * 7.0
			b.sphere(r * 0.45, MeshKit.at(p + Vector3(cos(a) * r * 0.5, r * 0.42, sin(a) * r * 0.5)), Color(0.34, 0.68, 0.3).lightened(0.05 * (k % 3)), 7)
		if int(r * 100.0) % 3 == 0:  # some bushes have berries
			for k in 4:
				var a := TAU * k / 4.0 + 0.4
				b.sphere(0.05, MeshKit.at(p + Vector3(cos(a) * r * 0.7, r * 0.75, sin(a) * r * 0.7)), Color(0.95, 0.25, 0.35), 5)
	var st: Dictionary = f.get("stream", {})
	if not st.is_empty():
		var n := Vector3(float(st.n[0]), 0.0, float(st.n[1]))
		var t := Vector3(-n.z, 0.0, n.x)
		var d := float(st.d)
		var w := float(st.w)
		var half := sqrt(maxf(0.0, (FieldGen.ARENA + 0.2) * (FieldGen.ARENA + 0.2) - (d + w) * (d + w)))
		var basis := Basis(t, Vector3.UP, n)  # x along the stream, z across it
		var water := MeshKit.Builder.new()
		water.box(Vector3(half * 2.0 + 0.6, 0.03, w * 2.0), Transform3D(basis, n * d + Vector3.UP * 0.012), WATER)
		var wm := MeshKit.instance(water.build(), false)
		wm.material_override = MeshKit.material(WATER, 0.25)
		root.add_child(wm)
		for s in [-1.0, 1.0]:  # muddy banks
			b.box(Vector3(half * 2.0 + 0.6, 0.02, 0.18), Transform3D(basis, n * (d + s * (w + 0.06)) + Vector3.UP * 0.01), Color(0.5, 0.42, 0.26))
		for bt in st.bridges:
			var c := n * d + t * float(bt)
			var bw := FieldGen.BRIDGE_W
			b.box(Vector3(bw * 2.0, 0.1, w * 2.0 + 0.7), Transform3D(basis, c + Vector3.UP * 0.06), WOOD.lightened(0.1))
			for k in 6:
				var x := -bw + 0.18 + k * (bw * 2.0 - 0.36) / 5.0
				b.box(Vector3(0.04, 0.012, w * 2.0 + 0.7), Transform3D(basis, c + t * x + Vector3.UP * 0.115), WOOD.darkened(0.2))
			for s in [-1.0, 1.0]:
				var rail: Vector3 = c + t * (float(s) * (bw - 0.05))
				b.tube(rail - n * (w + 0.3) + Vector3.UP * 0.35, rail + n * (w + 0.3) + Vector3.UP * 0.35, 0.035, 0.035, WOOD)
				for e in [-1.0, 1.0]:
					b.box(Vector3(0.08, 0.38, 0.08), MeshKit.at(rail + n * e * (w + 0.3) + Vector3.UP * 0.19), WOOD.darkened(0.15))
	if not b.is_empty():
		root.add_child(MeshKit.instance(b.build()))
	var fl: Array = []
	var cols := PackedColorArray()
	var pal := [Color(1.0, 0.5, 0.6), Color(1.0, 0.9, 0.4), Color(0.75, 0.6, 1.0), Color(1.0, 1.0, 1.0)]
	for fw in f.get("flowers", []):
		fl.append(Transform3D(Basis(Vector3.UP, float(fw[0]) * 3.1), Vector3(fw[0], 0.0, fw[1])))
		cols.append(pal[int(fw[2]) % pal.size()])
	if not fl.is_empty():
		root.add_child(MeshKit.scatter(MeshKit.prop("flower"), fl, cols, PackedColorArray(), false))
	var tr: Array = []
	for tt in f.get("trees", []):
		tr.append(Transform3D(Basis(Vector3.UP, float(tt[1]) * 1.7).scaled(Vector3.ONE * float(tt[2])), Vector3(tt[0], 0.0, tt[1])))
	if not tr.is_empty():
		root.add_child(MeshKit.scatter(MeshKit.prop("tree"), tr))
	return root


## A low dry-stone wall round the field's edge (knee high: cameras look over it).
static func build_edge() -> MeshInstance3D:
	var b := MeshKit.Builder.new()
	var r := FieldGen.ARENA + 0.25
	for k in 64:
		var a := TAU * k / 64.0
		var p := Vector3(cos(a), 0.0, sin(a)) * r
		var g := Color(0.62, 0.6, 0.58).lerp(Color(0.55, 0.5, 0.44), float(k % 3) / 2.0)
		b.rounded_box(Vector3(0.95, 0.38, 0.4), 0.1, Transform3D(Basis(Vector3.UP, -a + PI * 0.5), p + Vector3.UP * 0.19), g)
	return MeshKit.instance(b.build())


## Bo's home farm north of the field: a paddock with the rescued flock (some of them drawn: the sign
## says how many), Bo by the gate, and whatever the farm has built (Farm.MILESTONES).
class FarmNode extends Node3D:
	var bo: Node3D
	var sign: Label3D
	var flock: Array = []  # [sheep node, target]
	var rng := RandomNumberGenerator.new()
	const HALF := Vector2(4.6, 2.6)

	func setup(home: int, breeds: Dictionary) -> void:
		rng.seed = home * 31 + 7
		var c := FieldGen.FARM_CENTER
		var b := MeshKit.Builder.new()
		b.box(Vector3(HALF.x * 2.0, 0.02, HALF.y * 2.0), MeshKit.at(c + Vector3.UP * 0.01), Color(0.52, 0.82, 0.38))
		# Paddock fence with a gap (the gate) in the middle of the south side.
		var corners := [Vector3(-HALF.x, 0.0, -HALF.y), Vector3(HALF.x, 0.0, -HALF.y), Vector3(HALF.x, 0.0, HALF.y), Vector3(-HALF.x, 0.0, HALF.y)]
		for i in 4:
			var a: Vector3 = c + corners[i]
			var e: Vector3 = c + corners[(i + 1) % 4]
			var parts: Array = [[a, e]]
			if i == 2:  # south side: leave the gate open
				parts = [[a, c + Vector3(0.7, 0.0, HALF.y)], [c + Vector3(-0.7, 0.0, HALF.y), e]]
			for pr in parts:
				var p0: Vector3 = pr[0]
				var p1: Vector3 = pr[1]
				for h in [0.25, 0.5]:
					b.tube(p0 + Vector3.UP * h, p1 + Vector3.UP * h, 0.04, 0.04, WOOD)
				var k := int(p0.distance_to(p1) / 1.2) + 1
				for j in k + 1:
					b.box(Vector3(0.1, 0.62, 0.1), MeshKit.at(p0.lerp(p1, float(j) / k) + Vector3.UP * 0.31), WOOD.darkened(0.15))
		var built := Farm.built_for(home)
		if built.has("barn"):
			var bp := c + Vector3(-7.4, 0.0, -0.6)
			b.box(Vector3(3.0, 2.0, 2.4), MeshKit.at(bp + Vector3.UP * 1.0), Color(0.85, 0.22, 0.2))
			b.prism(3, 1.75, 2.5, Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, PI * 0.5), bp + Vector3.UP * 2.45), Color(0.45, 0.3, 0.25))
			b.box(Vector3(1.1, 1.4, 0.06), MeshKit.at(bp + Vector3(0.0, 0.7, 1.22)), Color(0.98, 0.95, 0.9))
			b.box(Vector3(0.9, 1.2, 0.07), MeshKit.at(bp + Vector3(0.0, 0.7, 1.23)), Color(0.75, 0.18, 0.16))
		if built.has("hay"):
			for k in 3:
				var hp := c + Vector3(6.4 + (k % 2) * 1.1, 0.0, -1.2 + k * 1.0)
				b.cylinder(0.5, 0.55, 0.8, MeshKit.at(hp + Vector3.UP * 0.4, Vector3.ONE, Vector3(PI * 0.5, 0.3 * k, 0.0)), Color(0.95, 0.8, 0.35))
		if built.has("windmill"):
			var wp := c + Vector3(8.6, 0.0, -3.2)
			b.cylinder(0.7, 1.1, 4.0, MeshKit.at(wp + Vector3.UP * 2.0), Color(0.95, 0.93, 0.88))
			b.cone(0.95, 1.0, MeshKit.at(wp + Vector3.UP * 4.5), Color(0.45, 0.3, 0.25))
		if built.has("pond"):
			b.disc(1.6, MeshKit.at(c + Vector3(-3.6, 0.03, -4.4), Vector3(1.4, 1.0, 1.0)), WATER)
			for k in 2:
				var dp := c + Vector3(-4.2 + k * 1.0, 0.1, -4.6 + k * 0.4)
				b.sphere(0.13, MeshKit.at(dp), Color(1.0, 1.0, 0.95), 7)
				b.sphere(0.08, MeshKit.at(dp + Vector3(0.1, 0.12, 0.0)), Color(1.0, 1.0, 0.95), 6)
				b.cone(0.04, 0.08, MeshKit.at(dp + Vector3(0.2, 0.12, 0.0), Vector3.ONE, Vector3(0.0, 0.0, -PI * 0.5)), Color(1.0, 0.6, 0.15), 5)
		if built.has("oak"):
			b.add_mesh(MeshKit.prop("tree"), Transform3D(Basis().scaled(Vector3.ONE * 2.2), c + Vector3(1.5, 0.0, -6.2)))
		if built.has("bunting"):
			var cols := [Color(1.0, 0.4, 0.4), Color(1.0, 0.85, 0.3), Color(0.4, 0.7, 1.0), Color(0.5, 0.9, 0.5)]
			for k in 12:
				var x := -HALF.x + k * HALF.x * 2.0 / 11.0
				var y := 1.4 - 0.25 * sin(PI * k / 11.0)
				b.cone(0.13, 0.26, MeshKit.at(c + Vector3(x, y, HALF.y), Vector3.ONE, Vector3(PI, 0.0, 0.0)), cols[k % 4], 3)
			for e in [-1.0, 1.0]:
				b.box(Vector3(0.08, 1.5, 0.08), MeshKit.at(c + Vector3(e * HALF.x, 0.75, HALF.y)), WOOD)
		add_child(MeshKit.instance(b.build()))
		# Bo at the paddock gate, looking at the field.
		bo = Creatures.humanoid({"class": "farmer", "hat": "straw", "outfit": Farm.BO_COLOR, "hair": Color(0.95, 0.75, 0.35),
			"hair_style": "long", "weapon": "none", "seed": 3, "lod": "far"})
		bo.position = c + Vector3(1.4, 0.0, HALF.y + 0.5)
		add_child(bo)
		sign = UiKit.label3d("HOME %d" % home, 0.5, "gold", true)
		sign.outline_size = 24
		sign.position = c + Vector3(0.0, 1.5, HALF.y + 0.2)
		add_child(sign)
		# The flock at home: every breed the farm has, roughly in proportion.
		var shown := mini(home, Farm.HOME_SHOWN)
		var list: Array = []
		for k in breeds:
			for i in maxi(1, int(round(float(breeds[k]) / maxf(1.0, home) * shown))):
				list.append(int(k))
		while list.size() > shown:
			list.remove_at(list.find(FieldGen.WHITE) if list.count(FieldGen.WHITE) > 1 else list.size() - 1)
		for i in list.size():
			var s: Node3D = SheepScript.new()
			s.set("breed", list[i])
			s.position = c + Vector3(rng.randf_range(-HALF.x + 0.5, HALF.x - 0.5), 0.0, rng.randf_range(-HALF.y + 0.5, HALF.y - 0.5))
			add_child(s)
			s.set("penned", true)
			flock.append([s, s.position])

	func cheer() -> void:
		if bo != null:
			Creatures.anim(bo).play("cheer", 1.2)

	func _process(delta: float) -> void:
		var c := FieldGen.FARM_CENTER
		for e in flock:
			var s: Node3D = e[0]
			var to: Vector3 = e[1]
			if s.position.distance_to(to) < 0.1:
				if rng.randf() < delta * 0.3:
					e[1] = c + Vector3(rng.randf_range(-HALF.x + 0.5, HALF.x - 0.5), 0.0, rng.randf_range(-HALF.y + 0.5, HALF.y - 0.5))
				continue
			s.position = s.position.move_toward(to, delta * 0.45)
