extends RefCounted
## FRUIT CATCH meshes: every shape is a cached, merged, vertex-coloured mesh (one draw call each).

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

const ROTTEN := 4  ## fruit kind index of the rotten apple
const FRUIT_COLORS: Array[Color] = [Color(0.95, 0.12, 0.12), Color(1.0, 0.55, 0.05), Color(0.75, 0.9, 0.15),
	Color(0.62, 0.2, 0.85), Color(0.42, 0.3, 0.12)]
const LEAF := Color(0.25, 0.75, 0.25)
const STUMP_TOP := 0.45  ## Nutmeg sits on a stump this high
const STUMP_R := 0.35
const NUTMEG_SCALE := 1.7  ## Nutmeg is a big, easy-to-see squirrel
const SIGN_LOW_Y := 1.15  ## the sign's lower board (Nutmeg's recipe)
const FUR := Color(0.85, 0.45, 0.18)
const BARK := Color(0.5, 0.32, 0.18)


## One fruit, centred on its origin (radius about 0.17 m).
static func fruit(kind: int) -> Mesh:
	return ResCache.get_or_make("fruit_catch_fruit_v2_%d" % kind, func() -> Mesh:
		var b := MeshKit.Builder.new()
		var c: Color = FRUIT_COLORS[clampi(kind, 0, FRUIT_COLORS.size() - 1)]
		if kind == 2:  # pear
			b.ellipsoid(Vector3(0.15, 0.2, 0.15), MeshKit.at(Vector3(0.0, -0.02, 0.0)), c, 12)
			b.sphere(0.1, MeshKit.at(Vector3(0.0, 0.13, 0.0)), c, 10)
		else:
			b.ellipsoid(Vector3(0.17, 0.155, 0.17), Transform3D.IDENTITY, c, 12)
		b.tube(Vector3(0.0, 0.12, 0.0), Vector3(0.02, 0.24, 0.0), 0.02, 0.015, BARK.darkened(0.3), 5)
		if kind == ROTTEN:
			for i in 4:  # mouldy spots
				var a := i * 1.7
				b.sphere(0.05, MeshKit.at(Vector3(cos(a) * 0.14, sin(i * 2.3) * 0.07, sin(a) * 0.14)), Color(0.3, 0.42, 0.1), 6)
		else:
			b.ellipsoid(Vector3(0.08, 0.02, 0.04), MeshKit.at(Vector3(0.07, 0.21, 0.0), Vector3.ONE, Vector3(0.0, 0.0, 0.5)), LEAF, 6)
		return b.build())


## The giant tree: trunk and a big leafy crown (bottom of the leaves at about 4.2 m).
static func tree() -> Mesh:
	return ResCache.get_or_make("fruit_catch_tree_v1", func() -> Mesh:
		var b := MeshKit.Builder.new()
		b.cylinder(0.45, 0.75, 5.2, MeshKit.at(Vector3(0.0, 2.6, 0.0)), BARK, 14)
		b.cylinder(0.9, 1.1, 0.25, MeshKit.at(Vector3(0.0, 0.1, 0.0)), BARK.darkened(0.15), 14)
		var blobs: Array = [[Vector3(0.0, 6.0, 0.0), 2.6]]
		for i in 7:
			var a := i * TAU / 7.0
			blobs.append([Vector3(cos(a) * 2.6, 5.3 + 0.5 * sin(i * 1.9), sin(a) * 2.6), 1.6])
		for bl in blobs:
			var p: Vector3 = bl[0]
			var r: float = bl[1]
			b.ellipsoid(Vector3(r, r * 0.78, r), MeshKit.at(p), LEAF.lerp(Color(0.15, 0.55, 0.2), fmod(p.x * 0.37 + 1.0, 1.0)), 14)
		for i in 22:  # fruit dotted over the crown
			var a := i * 2.4
			var h := 4.7 + fmod(i * 0.61, 2.2)
			var rr := 3.7 - absf(h - 5.4) * 0.6
			var c: Color = FRUIT_COLORS[i % 4]
			b.sphere(0.2, MeshKit.at(Vector3(cos(a) * rr, h, sin(a) * rr)), c, 8)
		return b.build())


## A branch pointing along -Z, `length` long, with a leafy, fruity tip you can grab.
static func branch(length: float) -> Mesh:
	return ResCache.get_or_make("fruit_catch_branch_v1_%d" % int(length * 100.0), func() -> Mesh:
		var b := MeshKit.Builder.new()
		b.tube(Vector3.ZERO, Vector3(0.0, 0.0, -length), 0.16, 0.07, BARK, 8)
		b.tube(Vector3(0.0, 0.0, -length * 0.55), Vector3(0.35, 0.25, -length * 0.8), 0.06, 0.03, BARK, 6)
		b.ellipsoid(Vector3(0.42, 0.3, 0.42), MeshKit.at(Vector3(0.0, 0.08, -length)), LEAF.lightened(0.1), 12)
		b.ellipsoid(Vector3(0.28, 0.22, 0.28), MeshKit.at(Vector3(0.35, 0.3, -length * 0.8)), LEAF, 10)
		for i in 3:
			var a := i * TAU / 3.0 + 0.4
			b.sphere(0.11, MeshKit.at(Vector3(cos(a) * 0.3, -0.2, -length + sin(a) * 0.3)), FRUIT_COLORS[i], 8)
		return b.build())


## The basket a TV player wears on their head.
static func basket() -> Mesh:
	return ResCache.get_or_make("fruit_catch_basket_v1", func() -> Mesh:
		var b := MeshKit.Builder.new()
		var c := Color(0.85, 0.6, 0.3)
		b.cylinder(0.36, 0.26, 0.26, MeshKit.at(Vector3(0.0, 0.13, 0.0)), c, 14)
		b.disc(0.33, MeshKit.at(Vector3(0.0, 0.265, 0.0)), c.darkened(0.45), 14)
		b.torus(0.36, 0.04, MeshKit.at(Vector3(0.0, 0.26, 0.0)), c.darkened(0.2), 16, 6)
		b.torus(0.31, 0.025, MeshKit.at(Vector3(0.0, 0.12, 0.0)), c.darkened(0.25), 16, 5)
		return b.build())


## The big fruit bowl (rim at BOWL_TOP).
static func bowl(top: float, radius: float) -> Mesh:
	return ResCache.get_or_make("fruit_catch_bowl_v1", func() -> Mesh:
		var b := MeshKit.Builder.new()
		var c := Color(0.25, 0.65, 1.0)
		b.cylinder(radius, radius * 0.55, top - 0.15, MeshKit.at(Vector3(0.0, 0.15 + (top - 0.15) * 0.5, 0.0)), c, 20)
		b.cylinder(radius * 0.4, radius * 0.5, 0.15, MeshKit.at(Vector3(0.0, 0.075, 0.0)), c.darkened(0.2), 16)
		b.disc(radius - 0.06, MeshKit.at(Vector3(0.0, top - 0.02, 0.0)), Color(0.1, 0.25, 0.45), 20)
		b.torus(radius, 0.07, MeshKit.at(Vector3(0.0, top, 0.0)), Color(1.0, 1.0, 1.0), 24, 8)
		return b.build())


## A soft round shadow (drawn under falling fruit so the TV players see where it lands).
static func shadow_mesh() -> Mesh:
	return ResCache.get_or_make("fruit_catch_shadow_v1", func() -> Mesh:
		var m := CylinderMesh.new()
		m.top_radius = 0.3
		m.bottom_radius = 0.3
		m.height = 0.01
		m.radial_segments = 14
		m.rings = 1
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.05, 0.1, 0.0, 0.4)
		m.material = mat
		return m)


## A wooden sign post (board centred at 2.1 m, facing +Z).
static func sign_post() -> Mesh:
	return ResCache.get_or_make("fruit_catch_sign_v2", func() -> Mesh:
		var b := MeshKit.Builder.new()
		b.cylinder(0.07, 0.08, 1.7, MeshKit.at(Vector3(-0.55, 0.85, -0.05)), BARK, 8)
		b.cylinder(0.07, 0.08, 1.7, MeshKit.at(Vector3(0.55, 0.85, -0.05)), BARK, 8)
		b.rounded_box(Vector3(1.4, 0.95, 0.1), 0.06, MeshKit.at(Vector3(0.0, 2.1, 0.0)), Color(0.72, 0.5, 0.3))
		b.sphere(0.12, MeshKit.at(Vector3(0.0, 2.65, 0.02)), FRUIT_COLORS[0], 10)
		b.rounded_box(Vector3(1.4, 0.5, 0.08), 0.05, MeshKit.at(Vector3(0.0, SIGN_LOW_Y, -0.01)), Color(0.95, 0.88, 0.7))
		return b.build())


## Nutmeg's tree stump (top at STUMP_TOP).
static func stump() -> Mesh:
	return ResCache.get_or_make("fruit_catch_stump_v1", func() -> Mesh:
		var b := MeshKit.Builder.new()
		b.cylinder(STUMP_R * 0.9, STUMP_R, STUMP_TOP, MeshKit.at(Vector3(0.0, STUMP_TOP * 0.5, 0.0)), BARK, 12)
		b.disc(STUMP_R * 0.85, MeshKit.at(Vector3(0.0, STUMP_TOP + 0.001, 0.0)), Color(0.85, 0.68, 0.45), 12)
		b.ellipsoid(Vector3(0.12, 0.08, 0.12), MeshKit.at(Vector3(STUMP_R * 0.9, 0.04, 0.1)), LEAF, 8)
		return b.build())


## Nutmeg the squirrel (sits at the origin, faces +Z): round body, big curly tail, a white chef's hat.
static func squirrel() -> Mesh:
	return ResCache.get_or_make("fruit_catch_squirrel_v1", func() -> Mesh:
		var b := MeshKit.Builder.new()
		var cream := Color(1.0, 0.9, 0.75)
		b.ellipsoid(Vector3(0.17, 0.2, 0.15), MeshKit.at(Vector3(0.0, 0.2, 0.0)), FUR, 12)  # body
		b.ellipsoid(Vector3(0.1, 0.13, 0.06), MeshKit.at(Vector3(0.0, 0.2, 0.11)), cream, 10)  # tummy
		b.sphere(0.14, MeshKit.at(Vector3(0.0, 0.47, 0.03)), FUR, 12)  # head
		b.ellipsoid(Vector3(0.07, 0.05, 0.05), MeshKit.at(Vector3(0.0, 0.43, 0.14)), cream, 8)  # muzzle
		b.sphere(0.022, MeshKit.at(Vector3(0.0, 0.45, 0.19)), Color(0.25, 0.12, 0.1), 6)  # nose
		for s in [-1.0, 1.0]:
			b.sphere(0.03, MeshKit.at(Vector3(0.055 * s, 0.51, 0.13)), Color(0.08, 0.06, 0.06), 6)  # eyes
			b.sphere(0.01, MeshKit.at(Vector3(0.05 * s, 0.52, 0.157)), Color.WHITE, 4)
			b.cone(0.045, 0.1, MeshKit.at(Vector3(0.08 * s, 0.6, 0.0)), FUR.darkened(0.15), 6)  # ears
			b.ellipsoid(Vector3(0.05, 0.05, 0.07), MeshKit.at(Vector3(0.08 * s, 0.03, 0.08)), FUR.darkened(0.1), 8)  # feet
			b.ellipsoid(Vector3(0.035, 0.06, 0.035), MeshKit.at(Vector3(0.1 * s, 0.24, 0.12)), FUR, 6)  # paws
		b.sphere(0.06, MeshKit.at(Vector3(0.0, 0.25, 0.18)), FRUIT_COLORS[0], 8)  # she holds an apple
		# The tail: a big fluffy curl up the back.
		b.ellipsoid(Vector3(0.12, 0.2, 0.12), MeshKit.at(Vector3(0.0, 0.25, -0.2)), FUR.darkened(0.05), 10)
		b.ellipsoid(Vector3(0.13, 0.15, 0.13), MeshKit.at(Vector3(0.0, 0.5, -0.27)), FUR.darkened(0.05), 10)
		b.ellipsoid(Vector3(0.1, 0.1, 0.1), MeshKit.at(Vector3(0.0, 0.65, -0.2)), FUR.lightened(0.15), 10)
		# Chef's hat.
		b.cylinder(0.09, 0.09, 0.08, MeshKit.at(Vector3(0.0, 0.62, 0.02)), Color.WHITE, 10)
		b.ellipsoid(Vector3(0.13, 0.08, 0.13), MeshKit.at(Vector3(0.0, 0.69, 0.02)), Color.WHITE, 10)
		return b.build())


## An orchard tree: stage 1 sapling, 2 blossom, 3 full of fruit (kind's colour); golden = TODAY'S HARVEST.
static func orchard_tree(kind: int, stage: int, golden: bool) -> Mesh:
	return ResCache.get_or_make("fruit_catch_otree_v1_%d_%d_%d" % [kind, stage, int(golden)], func() -> Mesh:
		var b := MeshKit.Builder.new()
		var s := [0.0, 0.45, 0.75, 1.0][clampi(stage, 1, 3)] as float
		var leaf := Color(0.95, 0.78, 0.25) if golden else LEAF.darkened(0.05 * kind)
		b.cylinder(0.08 * s + 0.03, 0.13 * s + 0.04, 1.6 * s, MeshKit.at(Vector3(0.0, 0.8 * s, 0.0)), BARK, 8)
		b.ellipsoid(Vector3(0.9, 0.75, 0.9) * s, MeshKit.at(Vector3(0.0, 1.9 * s, 0.0)), leaf, 12)
		b.ellipsoid(Vector3(0.55, 0.45, 0.55) * s, MeshKit.at(Vector3(0.5 * s, 1.6 * s, 0.2 * s)), leaf.darkened(0.08), 10)
		b.ellipsoid(Vector3(0.5, 0.42, 0.5) * s, MeshKit.at(Vector3(-0.45 * s, 1.65 * s, -0.15 * s)), leaf.darkened(0.12), 10)
		if stage >= 2:
			var dots := 6 if stage == 2 else 9
			for i in dots:
				var a := i * 2.4
				var p := Vector3(cos(a) * 0.75 * s, 1.75 * s + sin(i * 1.7) * 0.35 * s, sin(a) * 0.75 * s)
				var c: Color = Color(1.0, 0.75, 0.85) if stage == 2 else FRUIT_COLORS[clampi(kind, 0, 3)]
				b.sphere(0.07 if stage == 2 else 0.11, MeshKit.at(p), c, 6)
		if golden:
			b.sphere(0.12, MeshKit.at(Vector3(0.0, 1.9 * s + 0.8 * s, 0.0)), Color(1.0, 0.9, 0.3), 8)
		return b.build())
