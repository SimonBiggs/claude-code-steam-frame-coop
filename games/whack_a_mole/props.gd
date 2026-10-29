extends RefCounted
## Whack-a-Mole meshes: the table, a mole (normal / golden) and the VR player's soft mallet.
## Everything is baked into a few vertex-coloured meshes (cheap on the Frame).

const MeshKit := preload("res://core/mesh_kit.gd")

const TABLE_Y := 0.75  ## the table top: moles pop out of it and the TV kids run on it
const HALF := Vector2(1.7, 1.2)  ## half size of the table top (x, z)
const COLS := 4
const ROWS := 3
const SPACING := Vector2(0.78, 0.72)
const HOLE_R := 0.17


## Hole centres on the table top (row 0 is the far side, row ROWS-1 the VR player's side).
static func holes() -> PackedVector3Array:
	var out := PackedVector3Array()
	for r in ROWS:
		for c in COLS:
			out.append(Vector3((c - (COLS - 1) * 0.5) * SPACING.x, TABLE_Y, (r - (ROWS - 1) * 0.5) * SPACING.y))
	return out


## The big table: a solid cabinet (so hidden moles can't be seen), green felt, a yellow rim and the holes.
static func table_mesh() -> ArrayMesh:
	var b := MeshKit.builder()
	var w := HALF.x * 2.0
	var d := HALF.y * 2.0
	b.rounded_box(Vector3(w + 0.16, TABLE_Y - 0.04, d + 0.16), 0.06, MeshKit.at(Vector3(0.0, (TABLE_Y - 0.04) * 0.5, 0.0)), Color(0.93, 0.3, 0.33))
	# White polka band round the cabinet
	b.box(Vector3(w + 0.18, 0.08, d + 0.18), MeshKit.at(Vector3(0.0, TABLE_Y * 0.45, 0.0)), Color(1.0, 0.95, 0.85))
	b.box(Vector3(w, 0.06, d), MeshKit.at(Vector3(0.0, TABLE_Y - 0.03, 0.0)), Color(0.38, 0.8, 0.36))
	# Rim
	for s in [-1.0, 1.0]:
		var sf: float = s
		b.rounded_box(Vector3(w + 0.2, 0.1, 0.12), 0.04, MeshKit.at(Vector3(0.0, TABLE_Y, sf * (HALF.y + 0.04))), Color(1.0, 0.82, 0.25))
		b.rounded_box(Vector3(0.12, 0.1, d + 0.2), 0.04, MeshKit.at(Vector3(sf * (HALF.x + 0.04), TABLE_Y, 0.0)), Color(1.0, 0.82, 0.25))
	for p in holes():
		b.torus(HOLE_R + 0.01, 0.035, MeshKit.at(p + Vector3(0.0, 0.005, 0.0)), Color(0.55, 0.38, 0.22), 16, 6)
		b.cylinder(HOLE_R, HOLE_R, 0.012, MeshKit.at(p + Vector3(0.0, 0.004, 0.0)), Color(0.06, 0.04, 0.03), 16)
	return b.build()


## Fur colour of each mole kind (roundgen.gd kinds) and its story-card colour (helmet red, speedy blue).
const KIND_FUR: Array[Color] = [Color(0.55, 0.36, 0.24), Color(1.0, 0.78, 0.15), Color(0.55, 0.36, 0.24),
	Color(0.5, 0.42, 0.36), Color(0.97, 0.97, 1.0), Color(0.45, 0.3, 0.5), Color.WHITE, Color(0.55, 0.36, 0.24)]
const KIND_CARD: Array[Color] = [Color(0.55, 0.36, 0.24), Color(1.0, 0.8, 0.2), Color(0.95, 0.3, 0.3),
	Color(0.35, 0.6, 1.0), Color(0.97, 0.97, 1.0), Color(0.7, 0.45, 0.9), Color.WHITE, Color(0.55, 0.36, 0.24)]


## A mole of roundgen.gd kind: 0 plain, 1 golden (a crown), 2 helmet (a red bump helmet), 3 speedy
## (blue headband and sunglasses), 4 bunny (a white friend with long ears), 5 KING (a big crown and a
## red cape: drawn 1.5x), 7 a helmet mole whose helmet popped off (the plain look).
static func kind_mesh(kind: int) -> ArrayMesh:
	match kind:
		1:
			return mole_mesh(true)
		2:
			var b := _mole(KIND_FUR[0], Color(0.9, 0.74, 0.55))
			b.dome(0.155, MeshKit.at(Vector3(0.0, 0.36, 0.0)), Color(0.95, 0.25, 0.25), 14)
			b.cylinder(0.165, 0.165, 0.025, MeshKit.at(Vector3(0.0, 0.365, 0.0)), Color(1.0, 0.95, 0.9), 14)
			b.sphere(0.03, MeshKit.at(Vector3(0.0, 0.52, 0.0)), Color(1.0, 0.85, 0.3), 8)
			return b.build()
		3:
			var b := _mole(KIND_FUR[3], Color(0.85, 0.78, 0.7))
			b.cylinder(0.143, 0.143, 0.04, MeshKit.at(Vector3(0.0, 0.4, 0.0)), Color(0.3, 0.55, 1.0), 14)
			b.box(Vector3(0.17, 0.045, 0.02), MeshKit.at(Vector3(0.0, 0.335, 0.15)), Color(0.08, 0.08, 0.12))
			for s in [-1.0, 1.0]:
				var sf: float = s
				b.box(Vector3(0.04, 0.02, 0.1), MeshKit.at(Vector3(sf * 0.11, 0.42, -0.1), Vector3.ONE, Vector3(0.0, sf * 0.5, 0.0)), Color(0.3, 0.55, 1.0))
			return b.build()
		4:
			var b := MeshKit.builder()
			var fur := KIND_FUR[4]
			var pink := Color(1.0, 0.6, 0.72)
			b.capsule(0.13, 0.4, MeshKit.at(Vector3(0.0, 0.19, 0.0)), fur, 14)
			b.ellipsoid(Vector3(0.09, 0.1, 0.05), MeshKit.at(Vector3(0.0, 0.16, 0.1)), Color(1.0, 0.92, 0.95), 12)
			for s in [-1.0, 1.0]:
				var sf: float = s
				b.ellipsoid(Vector3(0.035, 0.13, 0.02), MeshKit.at(Vector3(sf * 0.055, 0.5, 0.0), Vector3.ONE, Vector3(0.0, 0.0, sf * -0.15)), fur, 10)
				b.ellipsoid(Vector3(0.02, 0.1, 0.01), MeshKit.at(Vector3(sf * 0.055, 0.5, 0.012), Vector3.ONE, Vector3(0.0, 0.0, sf * -0.15)), pink, 8)
				b.sphere(0.03, MeshKit.at(Vector3(sf * 0.05, 0.31, 0.11)), Color(0.08, 0.08, 0.12), 10)
				b.sphere(0.01, MeshKit.at(Vector3(sf * 0.045, 0.32, 0.138)), Color.WHITE, 6)
			b.sphere(0.025, MeshKit.at(Vector3(0.0, 0.26, 0.13)), pink, 8)
			return b.build()
		5:
			var b := _mole(KIND_FUR[5], Color(0.85, 0.75, 0.9))
			b.cylinder(0.11, 0.12, 0.08, MeshKit.at(Vector3(0.0, 0.43, 0.0)), Color(1.0, 0.82, 0.2), 10, true)
			for k in 5:
				var a := k * TAU / 5.0
				b.cone(0.03, 0.07, MeshKit.at(Vector3(cos(a) * 0.1, 0.5, sin(a) * 0.1)), Color(1.0, 0.85, 0.25), 5, true)
			b.sphere(0.025, MeshKit.at(Vector3(0.0, 0.44, 0.115)), Color(0.95, 0.2, 0.3), 8, true)
			b.ellipsoid(Vector3(0.16, 0.14, 0.06), MeshKit.at(Vector3(0.0, 0.16, -0.08)), Color(0.85, 0.15, 0.25), 12)
			return b.build()
	return mole_mesh(false)


## A seed packet on a stick for the pick phase: a white packet in the crop's colour with the crop's own
## plant on top (garden.gd plant_mesh), so kids see what they'd grow.
static func seed_mesh(color: Color, plant: Mesh) -> ArrayMesh:
	var b := MeshKit.builder()
	b.cylinder(0.02, 0.02, 0.2, MeshKit.at(Vector3(0.0, 0.1, 0.0)), Color(0.75, 0.55, 0.35), 6)
	b.rounded_box(Vector3(0.26, 0.3, 0.05), 0.02, MeshKit.at(Vector3(0.0, 0.33, 0.0)), Color(1.0, 0.97, 0.9))
	b.rounded_box(Vector3(0.22, 0.2, 0.055), 0.02, MeshKit.at(Vector3(0.0, 0.31, 0.0)), color)
	b.add_mesh(plant, MeshKit.at(Vector3(0.0, 0.48, 0.0), Vector3.ONE * 0.75))
	return b.build()


## A silly mole, origin at its base, facing +Z (towards the VR player). About 0.42 m tall.
static func mole_mesh(gold: bool) -> ArrayMesh:
	var b := _mole(Color(1.0, 0.78, 0.15) if gold else Color(0.55, 0.36, 0.24), Color(1.0, 0.95, 0.6) if gold else Color(0.9, 0.74, 0.55), gold)
	if gold:
		b.cone(0.07, 0.1, MeshKit.at(Vector3(0.0, 0.47, 0.0)), Color(1.0, 0.9, 0.3), 5, true)  # a little crown
	return b.build()


static func _mole(fur: Color, belly: Color, gold: bool = false) -> MeshKit.Builder:
	var b := MeshKit.builder()
	var pink := Color(1.0, 0.55, 0.65)
	b.capsule(0.14, 0.44, MeshKit.at(Vector3(0.0, 0.2, 0.0)), fur, 14, gold)
	b.ellipsoid(Vector3(0.1, 0.12, 0.06), MeshKit.at(Vector3(0.0, 0.17, 0.1)), belly, 12)
	for s in [-1.0, 1.0]:
		var sf: float = s
		b.sphere(0.034, MeshKit.at(Vector3(sf * 0.055, 0.33, 0.115)), Color.WHITE, 10)
		b.sphere(0.019, MeshKit.at(Vector3(sf * 0.055, 0.33, 0.143)), Color(0.05, 0.05, 0.08), 8)
		b.sphere(0.04, MeshKit.at(Vector3(sf * 0.1, 0.4, 0.0)), fur, 8, gold)
		b.ellipsoid(Vector3(0.045, 0.03, 0.035), MeshKit.at(Vector3(sf * 0.13, 0.17, 0.08)), pink, 8)
	b.sphere(0.04, MeshKit.at(Vector3(0.0, 0.28, 0.14)), pink, 10)
	b.box(Vector3(0.05, 0.035, 0.012), MeshKit.at(Vector3(0.0, 0.23, 0.135)), Color.WHITE)
	return b


## The giant soft mallet, in the right controller's space ("aim" pose: -Z forward).
## Returns [root, head] so the head can squash on a hit. The head centre is at HEAD_OFFSET.
const HEAD_OFFSET := Vector3(0.0, 0.0, -0.62)
const HEAD_R := 0.14

static func mallet() -> Array:
	var root := Node3D.new()
	root.name = "Mallet"
	var hb := MeshKit.builder()
	hb.cylinder(0.024, 0.03, 0.6, MeshKit.at(Vector3(0.0, 0.0, -0.28), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), Color(0.95, 0.75, 0.35), 8)
	hb.sphere(0.04, MeshKit.at(Vector3(0.0, 0.0, 0.03)), Color(0.3, 0.6, 1.0), 8)
	var handle := MeshKit.instance(hb.build(), false)
	root.add_child(handle)
	var head := Node3D.new()
	head.name = "Head"
	head.position = HEAD_OFFSET
	root.add_child(head)
	var b := MeshKit.builder()
	b.cylinder(HEAD_R, HEAD_R, 0.3, Transform3D.IDENTITY, Color(1.0, 0.35, 0.45), 16)
	for s in [-1.0, 1.0]:
		var sf: float = s
		b.cylinder(HEAD_R + 0.01, HEAD_R + 0.01, 0.05, MeshKit.at(Vector3(0.0, sf * 0.16, 0.0)), Color(1.0, 0.97, 0.9), 16)
		b.sphere(HEAD_R * 0.98, MeshKit.at(Vector3(0.0, sf * 0.18, 0.0), Vector3(1.0, 0.35, 1.0)), Color(1.0, 0.97, 0.9), 12)
	var hm := MeshKit.instance(b.build(), false)
	head.add_child(hm)
	return [root, head]
