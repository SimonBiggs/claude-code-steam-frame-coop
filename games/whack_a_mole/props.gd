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


## A silly mole, origin at its base, facing +Z (towards the VR player). About 0.42 m tall.
static func mole_mesh(gold: bool) -> ArrayMesh:
	var b := MeshKit.builder()
	var fur := Color(1.0, 0.78, 0.15) if gold else Color(0.55, 0.36, 0.24)
	var belly := Color(1.0, 0.95, 0.6) if gold else Color(0.9, 0.74, 0.55)
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
	if gold:
		b.cone(0.07, 0.1, MeshKit.at(Vector3(0.0, 0.47, 0.0)), Color(1.0, 0.9, 0.3), 5, true)  # a little crown
	return b.build()


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
