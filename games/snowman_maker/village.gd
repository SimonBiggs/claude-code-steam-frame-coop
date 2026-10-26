extends RefCounted
## SNOWMAN MAKER village: the five places round the garden (story.gd chapters 0-4) that grow a piece
## for every story day with a star (saved), the garden's pines, ice and drifts, and Tumble's scarf.
## Pure mesh builders (cached), the same on every machine.

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

## Where each place stands [position, yaw]: round the far side of the garden, facing the VR builder.
const PLACES: Array = [
	[Vector3(-11.0, 0.0, -6.5), 1.0], [Vector3(-5.0, 0.0, -12.0), 0.4], [Vector3(3.5, 0.0, -12.5), -0.3],
	[Vector3(10.5, 0.0, -7.5), -0.95], [Vector3(0.0, 0.0, -17.0), 0.0],
]
const SNOW := Color(0.96, 0.98, 1.0)
const ICE := Color(0.62, 0.85, 1.0)


## One place built up to `stage` (0 = an empty lot with a crate and a flag, 1-3 = more of it).
static func place(chapter: int, stage: int) -> ArrayMesh:
	return ResCache.get_or_make("sm_place_%d_%d_v1" % [chapter, stage], func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		var wood := Color(0.62, 0.42, 0.25)
		if stage <= 0:
			b.box(Vector3(0.8, 0.8, 0.8), MeshKit.at(Vector3(0.6, 0.4, 0.4)), wood)
			b.cylinder(0.04, 0.04, 2.0, MeshKit.at(Vector3(-0.6, 1.0, 0.0)), wood.darkened(0.3), 6)
			b.box(Vector3(0.7, 0.45, 0.03), MeshKit.at(Vector3(-0.25, 1.75, 0.0)), Color(0.4, 0.75, 1.0))
			return b.build()
		match chapter:
			0:  # Tumble's igloo: a ring of blocks, then the dome, then the door tunnel and a flag
				if stage == 1:
					b.cylinder(1.6, 1.7, 0.7, MeshKit.at(Vector3(0.0, 0.35, 0.0)), SNOW, 18)
				else:
					b.dome(1.7, MeshKit.at(Vector3.ZERO), SNOW, 18)
					for i in 4:
						b.torus(1.62 - i * 0.28, 0.03, MeshKit.at(Vector3(0.0, 0.3 + i * 0.38, 0.0)), Color(0.82, 0.88, 0.98))
				if stage >= 3:
					b.cylinder(0.6, 0.6, 1.2, MeshKit.at(Vector3(0.0, 0.5, 1.5), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), SNOW, 12)
					b.disc(0.45, MeshKit.at(Vector3(0.0, 0.5, 2.11), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), Color(0.15, 0.2, 0.35), 12)
			1:  # cocoa hut: walls, then roof and door, then a chimney, a cup sign and lit windows
				var hut := Color(0.7, 0.45, 0.28)
				b.box(Vector3(2.8, 1.0 if stage == 1 else 1.9, 2.2), MeshKit.at(Vector3(0.0, 0.5 if stage == 1 else 0.95, 0.0)), hut)
				if stage >= 2:
					b.prism(3, 1.4, 3.0, MeshKit.at(Vector3(0.0, 2.45, 0.0), Vector3(1.0, 0.85, 1.0), Vector3(0.0, 0.0, PI * 0.5)), SNOW)
					b.box(Vector3(0.6, 1.0, 0.05), MeshKit.at(Vector3(0.0, 0.5, 1.12)), Color(0.4, 0.22, 0.12))
				if stage >= 3:
					b.box(Vector3(0.35, 0.9, 0.35), MeshKit.at(Vector3(0.8, 3.0, -0.3)), Color(0.55, 0.55, 0.6))
					for x in [-0.9, 0.9]:
						b.box(Vector3(0.45, 0.45, 0.05), MeshKit.at(Vector3(x, 1.2, 1.12)), Color(1.0, 0.85, 0.45), true)
					b.cylinder(0.25, 0.2, 0.4, MeshKit.at(Vector3(0.0, 2.3, 1.25)), Color(0.95, 0.95, 1.0), 10)
					b.disc(0.22, MeshKit.at(Vector3(0.0, 2.51, 1.25)), Color(0.45, 0.25, 0.12), 10)
			2:  # skating rink: the ice, then a fence, then lamps and a little bench
				b.cylinder(2.4, 2.4, 0.06, MeshKit.at(Vector3(0.0, 0.03, 0.0), Vector3(1.0, 1.0, 0.7)), ICE, 20, true)
				if stage >= 2:
					for i in 16:
						var a := TAU * i / 16.0
						b.box(Vector3(0.08, 0.5, 0.08), MeshKit.at(Vector3(cos(a) * 2.5, 0.25, sin(a) * 2.5 * 0.7)), wood)
					b.torus(2.5, 0.04, MeshKit.at(Vector3(0.0, 0.45, 0.0), Vector3(1.0, 1.0, 0.7)), Color(0.9, 0.25, 0.3))
				if stage >= 3:
					for x in [-2.2, 2.2]:
						b.cylinder(0.05, 0.05, 2.2, MeshKit.at(Vector3(x, 1.1, -1.4)), Color(0.2, 0.2, 0.25), 6)
						b.sphere(0.2, MeshKit.at(Vector3(x, 2.3, -1.4)), Color(1.0, 0.9, 0.5), 8, true)
					b.box(Vector3(1.2, 0.1, 0.35), MeshKit.at(Vector3(0.0, 0.45, 2.1)), wood)
			3:  # sled hill: a snow hill, then a ramp, then sleds and a flag
				b.dome(2.2, MeshKit.at(Vector3.ZERO, Vector3(1.0, 0.45 if stage == 1 else 0.8, 1.0)), SNOW, 16)
				if stage >= 2:
					b.wedge(Vector3(1.2, 1.4, 2.4), MeshKit.at(Vector3(0.0, 0.7, 2.6), Vector3.ONE, Vector3(0.0, PI, 0.0)), Color(0.88, 0.94, 1.0))
				if stage >= 3:
					for k in 2:
						var sx := -0.9 + k * 1.8
						b.box(Vector3(0.5, 0.08, 0.9), MeshKit.at(Vector3(sx, 0.12, 3.2)), [Color(0.9, 0.25, 0.3), Color(0.25, 0.55, 0.95)][k])
						b.box(Vector3(0.06, 0.12, 0.9), MeshKit.at(Vector3(sx - 0.22, 0.04, 3.2)), Color(0.3, 0.3, 0.35))
						b.box(Vector3(0.06, 0.12, 0.9), MeshKit.at(Vector3(sx + 0.22, 0.04, 3.2)), Color(0.3, 0.3, 0.35))
			_:  # ice castle: a wall, then towers, then a big tower with a star
				var wall := Color(0.78, 0.9, 1.0)
				b.box(Vector3(3.6, 1.2 if stage == 1 else 2.2, 1.8), MeshKit.at(Vector3(0.0, 0.6 if stage == 1 else 1.1, 0.0)), wall)
				if stage >= 2:
					for x in [-1.9, 1.9]:
						b.cylinder(0.55, 0.6, 3.2, MeshKit.at(Vector3(x, 1.6, 0.0)), wall, 12)
						b.cone(0.7, 1.1, MeshKit.at(Vector3(x, 3.75, 0.0)), Color(0.55, 0.65, 1.0), 12)
					b.box(Vector3(0.8, 1.2, 0.05), MeshKit.at(Vector3(0.0, 0.6, 0.92)), Color(0.45, 0.55, 0.95))
				if stage >= 3:
					b.cylinder(0.6, 0.65, 2.0, MeshKit.at(Vector3(0.0, 3.2, 0.0)), wall, 12)
					b.cone(0.8, 1.4, MeshKit.at(Vector3(0.0, 4.9, 0.0)), Color(0.55, 0.65, 1.0), 12)
					b.star(5, 0.4, 0.18, 0.1, MeshKit.at(Vector3(0.0, 6.0, 0.0)), Color(1.0, 0.85, 0.3), true)
		if stage >= 3 and chapter != 4:  # a flag on every finished place
			b.cylinder(0.03, 0.03, 1.0, MeshKit.at(Vector3(-1.3, 2.9, 0.0)), Color(0.4, 0.3, 0.2), 5)
			b.box(Vector3(0.5, 0.3, 0.02), MeshKit.at(Vector3(-1.05, 3.25, 0.0)), Color(0.4, 0.75, 1.0))
		return b.build()) as ArrayMesh


## A garden pine with snow on its branches (origin at the ground).
static func snowy_pine() -> ArrayMesh:
	return ResCache.get_or_make("sm_pine_v1", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		b.cylinder(0.12, 0.16, 0.7, MeshKit.at(Vector3(0.0, 0.35, 0.0)), Color(0.42, 0.28, 0.16), 7)
		for k in 4:
			var r := 0.75 - k * 0.16
			b.cone(r, 0.8, MeshKit.at(Vector3(0.0, 0.85 + k * 0.45, 0.0)), Color(0.17, 0.45, 0.33).lightened(0.05 * k), 9)
			b.cone(r * 0.55, 0.32, MeshKit.at(Vector3(0.0, 1.1 + k * 0.45, 0.0)), SNOW, 9)
		return b.build()) as ArrayMesh


## An icy patch (a flat glossy disc of radius 1).
static func ice_patch() -> ArrayMesh:
	return ResCache.get_or_make("sm_ice_v1", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		b.cylinder(1.0, 1.0, 0.03, MeshKit.at(Vector3(0.0, 0.015, 0.0)), ICE, 24, true)
		for i in 5:  # little shine streaks
			var a := i * 1.3
			b.box(Vector3(0.5, 0.01, 0.04), MeshKit.at(Vector3(cos(a) * 0.45, 0.035, sin(a) * 0.45), Vector3.ONE, Vector3(0.0, a, 0.0)), Color(0.92, 0.97, 1.0), true)
		return b.build()) as ArrayMesh


## A deep drift (soft mounds within radius 1).
static func drift() -> ArrayMesh:
	return ResCache.get_or_make("sm_drift_v1", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		b.dome(1.0, MeshKit.at(Vector3.ZERO, Vector3(1.0, 0.16, 1.0)), Color(0.99, 1.0, 1.0), 18)
		for q in [Vector3(0.4, 0.0, 0.2), Vector3(-0.35, 0.0, -0.3), Vector3(-0.2, 0.0, 0.45)]:
			b.dome(0.4, MeshKit.at(q + Vector3.UP * 0.05, Vector3(1.0, 0.45, 1.0)), Color(0.95, 0.97, 1.0), 10)
		return b.build()) as ArrayMesh


## A wish bubble (a round cloud with a tail, origin at the tail's tip).
static func bubble() -> ArrayMesh:
	return ResCache.get_or_make("sm_bubble_v1", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		b.sphere(0.42, MeshKit.at(Vector3(0.0, 0.62, 0.0), Vector3(1.0, 0.85, 0.35)), Color(1.0, 1.0, 1.0), 14)
		b.sphere(0.09, MeshKit.at(Vector3(-0.05, 0.12, 0.0)), Color(1.0, 1.0, 1.0), 8)
		b.sphere(0.05, MeshKit.at(Vector3(-0.1, 0.0, 0.0)), Color(1.0, 1.0, 1.0), 6)
		return b.build()) as ArrayMesh


## Tumble's red scarf (fits a penguin of scale ~1.2).
static func scarf() -> ArrayMesh:
	return ResCache.get_or_make("sm_scarf_v1", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		var red := Color(0.92, 0.2, 0.25)
		b.torus(0.2, 0.06, MeshKit.at(Vector3.ZERO), red)
		b.box(Vector3(0.1, 0.3, 0.04), MeshKit.at(Vector3(0.1, -0.14, 0.2), Vector3.ONE, Vector3(0.2, 0.0, 0.2)), red)
		return b.build()) as ArrayMesh
