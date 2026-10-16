extends RefCounted
## ELEMENTAL BENDER: the low-poly looks, each baked into one cached mesh (MeshKit: a lit surface and
## a glow surface = 2 draw calls). Origins at the feet, characters face -Z (like the source game).
## - Bender: robe in the element's colour, glowing sash and hands, and a headband in the player's
##   colour so everyone can find themselves.
## - Shadow Raider: dark robe and hood, pale mask with red eyes, a glowing sash in its element
##   (its element orb floats above the head as a separate node so it can bob).
## - Practice dummy: a straw dummy on a post.
## - Projectiles: fire blast, water whip, boulder, air gust (and a dark core on enemy shots).

const E := preload("res://games/elemental_bender/elem.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

const SKIN := Color(0.93, 0.76, 0.6)


static func bender(e: int, band: Color) -> ArrayMesh:
	return ResCache.get_or_make("eb_bender_%d_%s_v1" % [e, band.to_html(false)], func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cylinder(0.26, 0.46, 1.15, MeshKit.at(Vector3(0, 0.6, 0)), E.ROBES[e], 12)
		b.cylinder(0.31, 0.34, 0.14, MeshKit.at(Vector3(0, 0.85, 0)), E.COLORS[e], 12, true)
		b.sphere(0.28, MeshKit.at(Vector3(0, 1.48, 0)), SKIN, 12)
		b.cylinder(0.29, 0.29, 0.09, MeshKit.at(Vector3(0, 1.6, 0)), band, 12, true)
		for x in [-0.09, 0.09]:
			b.sphere(0.04, MeshKit.at(Vector3(float(x), 1.5, -0.25)), Color(0.05, 0.05, 0.1), 6)
		for x in [-0.42, 0.42]:
			var xf := float(x)
			b.capsule(0.08, 0.6, MeshKit.at(Vector3(xf, 1.0, -0.15), Vector3.ONE, Vector3(1.1, 0, 0)), SKIN, 8)
			b.sphere(0.12, MeshKit.at(Vector3(xf, 1.12, -0.42)), E.COLORS[e], 8, true)
		return b.build())


static func raider(e: int, boss: bool) -> ArrayMesh:
	return ResCache.get_or_make("eb_raider_%d_%s_v1" % [e, boss], func() -> Resource:
		var b := MeshKit.Builder.new()
		var dark := Color(0.12, 0.1, 0.15)
		b.cylinder(0.28, 0.48, 1.2, MeshKit.at(Vector3(0, 0.6, 0)), dark, 12)
		b.cylinder(0.33, 0.36, 0.12, MeshKit.at(Vector3(0, 0.85, 0)), E.COLORS[e], 12, true)
		b.sphere(0.27, MeshKit.at(Vector3(0, 1.45, 0)), Color(0.85, 0.85, 0.8), 12)
		for x in [-0.09, 0.09]:
			b.sphere(0.05, MeshKit.at(Vector3(float(x), 1.5, -0.24)), Color(1, 0.1, 0.1), 6, true)
		b.cylinder(0.0, 0.33, 0.45, MeshKit.at(Vector3(0, 1.75, 0)), Color(0.1, 0.08, 0.12), 10)
		for x in [-0.4, 0.4]:
			b.capsule(0.08, 0.6, MeshKit.at(Vector3(float(x), 1.0, -0.12), Vector3.ONE, Vector3(0.9, 0, 0)), dark, 6)
		if boss:
			b.torus(0.26, 0.04, MeshKit.at(Vector3(0, 1.68, 0)), Color(1, 0.8, 0.2), 12, 6, true)
			for k in 5:
				var a := k * TAU / 5.0
				b.cone(0.05, 0.16, MeshKit.at(Vector3(cos(a) * 0.26, 1.78, sin(a) * 0.26)), Color(1, 0.8, 0.2), 4, true)
		return b.build())


static func orb(radius: float, segs: int = 10) -> SphereMesh:
	return ResCache.get_or_make("eb_orb_%.2f_%d" % [radius, segs], func() -> Resource:
		var s := SphereMesh.new()
		s.radius = radius
		s.height = radius * 2.0
		s.radial_segments = segs
		s.rings = maxi(segs / 2, 4)
		return s)


static func dummy() -> ArrayMesh:
	return ResCache.get_or_make("eb_dummy_v1", func() -> Resource:
		var b := MeshKit.Builder.new()
		var wood := Color(0.45, 0.3, 0.17)
		var straw := Color(0.86, 0.72, 0.38)
		b.cylinder(0.07, 0.08, 1.9, MeshKit.at(Vector3(0, 0.95, 0)), wood, 6)
		b.cylinder(0.05, 0.05, 1.3, MeshKit.at(Vector3(0, 1.25, 0), Vector3.ONE, Vector3(0, 0, PI / 2)), wood, 6)
		b.capsule(0.3, 0.9, MeshKit.at(Vector3(0, 1.1, 0)), straw, 10)
		b.sphere(0.24, MeshKit.at(Vector3(0, 1.75, 0)), straw, 10)
		b.cylinder(0.33, 0.33, 0.1, MeshKit.at(Vector3(0, 0.95, 0)), Color(0.6, 0.2, 0.15), 10)
		b.cylinder(0.5, 0.6, 0.15, MeshKit.at(Vector3(0, 0.07, 0)), Color(0.5, 0.47, 0.43), 10)
		return b.build())


static func shot(e: int, radius: float, enemy: bool) -> ArrayMesh:
	return ResCache.get_or_make("eb_shot_%d_%.2f_%s_v1" % [e, radius, enemy], func() -> Resource:
		var b := MeshKit.Builder.new()
		var c: Color = E.COLORS[e]
		match e:
			E.FIRE:
				b.sphere(radius * 0.8, MeshKit.at(Vector3.ZERO), Color(1.0, 0.75, 0.2), 8, true)
				b.sphere(radius * 1.05, MeshKit.at(Vector3.ZERO), c, 8, true)
			E.WATER:
				b.sphere(radius, MeshKit.at(Vector3.ZERO, Vector3(0.8, 0.8, 1.6)), c, 10, true)
			E.EARTH:
				b.box(Vector3.ONE * radius * 1.6, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(0.4, 0.7, 0.2)), E.ROCK)
			_:
				b.torus(radius * 0.8, radius * 0.2, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI / 2, 0, 0)), c, 12, 6, true)
		if enemy:
			b.sphere(radius * 0.45, MeshKit.at(Vector3.ZERO), Color(0.35, 0.0, 0.5), 6, true)
		return b.build())


## A white flash drawn over a mesh for a moment when it is hit.
static func flash_material() -> StandardMaterial3D:
	return ResCache.get_or_make("eb_flash_v1", func() -> Resource:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1, 1, 1, 0.7)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		return m)


## The see-through ice block a Healing Tide freezes raiders in.
static func ice() -> ArrayMesh:
	return ResCache.get_or_make("eb_ice_v1", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cylinder(0.55, 0.65, 2.0, MeshKit.at(Vector3(0, 1.0, 0)), Color(0.7, 0.9, 1.0, 0.5), 8)
		return b.build(MeshKit.vertex_material(true, true)))
