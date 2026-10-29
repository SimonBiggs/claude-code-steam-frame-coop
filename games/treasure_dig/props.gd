extends RefCounted
## Treasure Dig: the game's own meshes and little effects (all code-made, cached via ResCache).

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Story := preload("res://games/treasure_dig/story.gd")

const KIND_COIN := 0
const KIND_GEM := 1
const KIND_BOOT := 2
const KIND_MAP := 3  ## a torn piece of Captain Peg's map (story.gd)
const KIND_RELIC := 4  ## Peg's relic under the X (variant = which relic)
const VALUES: Array[int] = [1, 3, 1, 0, 10]
const KIND_SCALE := 1.9


## A treasure (coin, gem or a silly old boot) as one MeshInstance3D, origin at its base.
## `variant` picks the gem colour (pass the item id so every machine shows the same gem).
static func item_mesh(kind: int, variant: int = -1) -> MeshInstance3D:
	var mi: MeshInstance3D
	match kind:
		KIND_COIN:
			mi = MeshKit.instance(MeshKit.prop("coin"), false)
		KIND_GEM:
			mi = MeshKit.instance(MeshKit.prop("gem", posmod(variant, 4) if variant >= 0 else randi() % 4), false)
		KIND_MAP:
			mi = MeshKit.instance(map_piece(), false)
		KIND_RELIC:
			mi = MeshKit.instance(relic(maxi(0, variant)), false)
		_:
			mi = MeshKit.instance(boot(), false)
	mi.scale = Vector3.ONE * KIND_SCALE
	return mi


static func boot() -> ArrayMesh:
	return ResCache.get_or_make("td_boot_v1", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		var leather := Color(0.45, 0.28, 0.16)
		b.rounded_box(Vector3(0.16, 0.3, 0.18), 0.05, MeshKit.at(Vector3(0, 0.2, -0.03)), leather)
		b.rounded_box(Vector3(0.17, 0.12, 0.34), 0.05, MeshKit.at(Vector3(0, 0.07, 0.05)), leather.darkened(0.1))
		b.box(Vector3(0.18, 0.03, 0.36), MeshKit.at(Vector3(0, 0.015, 0.05)), Color(0.2, 0.15, 0.1))
		b.torus(0.07, 0.015, MeshKit.at(Vector3(0, 0.36, -0.03)), leather.lightened(0.15), 10, 4)
		b.sphere(0.03, MeshKit.at(Vector3(0.05, 0.4, 0.06)), Color(0.4, 0.8, 0.3), 6)  # a bit of seaweed
		return b.build()) as ArrayMesh


## The big treasure chest's base (origin at the bottom centre, front +Z).
static func chest_base() -> ArrayMesh:
	return ResCache.get_or_make("td_chest_base_v1", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		var wood := Color(0.62, 0.36, 0.18)
		var gold := Color(1.0, 0.8, 0.3)
		b.rounded_box(Vector3(1.8, 0.9, 1.2), 0.08, MeshKit.at(Vector3(0, 0.45, 0)), wood)
		b.box(Vector3(1.6, 0.05, 1.0), MeshKit.at(Vector3(0, 0.88, 0)), Color(1.0, 0.85, 0.3), true)  # gold inside
		for x in [-0.6, 0.6]:
			b.box(Vector3(0.14, 0.92, 1.24), MeshKit.at(Vector3(x, 0.45, 0)), gold)
		b.rounded_box(Vector3(0.26, 0.3, 0.06), 0.04, MeshKit.at(Vector3(0, 0.7, 0.62)), gold)
		return b.build()) as ArrayMesh


## The lid, hinged at its back edge (origin on the hinge).
static func chest_lid() -> ArrayMesh:
	return ResCache.get_or_make("td_chest_lid_v1", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		var wood := Color(0.68, 0.4, 0.2)
		var gold := Color(1.0, 0.8, 0.3)
		b.cylinder(0.6, 0.6, 1.8, MeshKit.at(Vector3(0, 0.0, 0.6), Vector3(1, 1, 0.6), Vector3(0, 0, PI * 0.5)), wood, 14)
		for x in [-0.6, 0.6]:
			b.cylinder(0.62, 0.62, 0.14, MeshKit.at(Vector3(x, 0.0, 0.6), Vector3(1, 1, 0.6), Vector3(0, 0, PI * 0.5)), gold, 14)
		return b.build()) as ArrayMesh


## The giant's magic telescope (points along -Z, like the controller's aim pose).
static func telescope() -> ArrayMesh:
	return ResCache.get_or_make("td_telescope_v1", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		var brass := Color(0.95, 0.72, 0.3)
		var wood := Color(0.5, 0.3, 0.16)
		var fwd := Vector3(0, 0, -1)
		b.cylinder(0.022, 0.026, 0.12, MeshKit.aim(Vector3(0, 0, -0.04), fwd), wood, 10)
		b.cylinder(0.03, 0.03, 0.1, MeshKit.aim(Vector3(0, 0, -0.14), fwd), brass, 10)
		b.cylinder(0.036, 0.036, 0.04, MeshKit.aim(Vector3(0, 0, -0.21), fwd), brass.lightened(0.2), 10)
		b.sphere(0.03, MeshKit.at(Vector3(0, 0, -0.23), Vector3(1, 1, 0.4)), Color(0.5, 0.9, 1.0), 10, true)
		return b.build()) as ArrayMesh


## A sparkle "dig here!" marker: a glowing star over a ring (1 draw call + particles).
static func sparkle_marker() -> Node3D:
	var n := Node3D.new()
	var mesh: ArrayMesh = ResCache.get_or_make("td_sparkle_v1", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		b.star(5, 0.45, 0.2, 0.12, MeshKit.at(Vector3(0, 1.6, 0)), Color(1.0, 0.95, 0.4), true)
		b.torus(0.8, 0.07, MeshKit.at(Vector3(0, 0.05, 0)), Color(1.0, 0.9, 0.35), 20, 4, true)
		b.cylinder(0.04, 0.04, 1.1, MeshKit.at(Vector3(0, 0.6, 0)), Color(1.0, 0.95, 0.6), 6, true)
		return b.build())
	var mi := MeshKit.instance(mesh, false)
	mi.name = "Star"
	n.add_child(mi)
	var p := CPUParticles3D.new()
	p.local_coords = true
	p.amount = 14
	p.lifetime = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.7
	p.direction = Vector3.UP
	p.spread = 25.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.8
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.12
	bm.material = MeshKit.material(Color(1.0, 0.95, 0.5), 3.0)
	p.mesh = bm
	n.add_child(p)
	return n


## A one-shot burst of little cubes (sand, splashes, sparkles). Local to `parent`.
static func burst(parent: Node3D, pos: Vector3, color: Color, amount: int = 16, speed: float = 3.0,
		size: float = 0.14, glow: float = 0.0, gravity: float = -12.0) -> void:
	var p := CPUParticles3D.new()
	p.local_coords = true
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 60.0
	p.gravity = Vector3(0, gravity, 0)
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.mesh = ResCache.get_or_make("td_bit_%s_%.2f_%.1f" % [color.to_html(false), size, glow], func() -> Resource:
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * size
		bm.material = MeshKit.material(color, glow)
		return bm)
	parent.add_child(p)
	p.position = pos
	p.emitting = true
	p.get_tree().create_timer(1.2).timeout.connect(p.queue_free)


## A rolled-up piece of the treasure map with a red ribbon.
static func map_piece() -> ArrayMesh:
	return ResCache.get_or_make("td_map_v1", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		b.cylinder(0.11, 0.11, 0.5, MeshKit.at(Vector3(0, 0.12, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.96, 0.88, 0.66), 12)
		b.cylinder(0.12, 0.12, 0.06, MeshKit.at(Vector3(0, 0.12, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.9, 0.2, 0.2), 12)
		b.box(Vector3(0.04, 0.02, 0.22), MeshKit.at(Vector3(0.02, 0.24, 0.0)), Color(0.9, 0.2, 0.2))
		return b.build()) as ArrayMesh


## Peg's relic i (story.gd RELICS): a little treasure about 0.45 high, origin at its base.
static func relic(i: int) -> ArrayMesh:
	return ResCache.get_or_make("td_relic_%d" % i, func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		var c: Color = Story.RELICS[i % Story.RELICS.size()][1]
		match i % Story.RELICS.size():
			0:  # golden duck
				b.ellipsoid(Vector3(0.2, 0.14, 0.14), MeshKit.at(Vector3(0, 0.14, 0)), c, 12, true)
				b.sphere(0.1, MeshKit.at(Vector3(0.14, 0.32, 0)), c, 10, true)
				b.cone(0.05, 0.1, MeshKit.at(Vector3(0.26, 0.31, 0), Vector3.ONE, Vector3(0, 0, -PI * 0.5)), Color(1.0, 0.5, 0.1), 8)
			1:  # crown
				b.cylinder(0.18, 0.18, 0.14, MeshKit.at(Vector3(0, 0.07, 0)), c, 14, true)
				for k in 5:
					var a := k * TAU / 5.0
					b.cone(0.05, 0.14, MeshKit.at(Vector3(cos(a) * 0.15, 0.2, sin(a) * 0.15)), c, 6, true)
					b.sphere(0.03, MeshKit.at(Vector3(cos(a) * 0.18, 0.08, sin(a) * 0.18)), Color(0.9, 0.15, 0.3), 6, true)
			2:  # a ship in a bottle
				b.cylinder(0.12, 0.12, 0.4, MeshKit.at(Vector3(0, 0.12, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.6, 0.85, 0.95), 12)
				b.cylinder(0.05, 0.06, 0.12, MeshKit.at(Vector3(0.26, 0.12, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.6, 0.85, 0.95), 8)
				b.box(Vector3(0.24, 0.05, 0.08), MeshKit.at(Vector3(0, 0.07, 0)), c)
				b.box(Vector3(0.1, 0.12, 0.02), MeshKit.at(Vector3(0, 0.16, 0)), Color.WHITE)
			3:  # compass
				b.cylinder(0.18, 0.18, 0.06, MeshKit.at(Vector3(0, 0.03, 0)), c, 16, true)
				b.cylinder(0.15, 0.15, 0.065, MeshKit.at(Vector3(0, 0.035, 0)), Color(0.95, 0.95, 0.9), 16)
				b.box(Vector3(0.03, 0.02, 0.24), MeshKit.at(Vector3(0, 0.075, 0)), Color(0.9, 0.15, 0.15))
			4:  # a giant pearl in its shell
				b.dome(0.22, MeshKit.at(Vector3(0, 0.0, -0.02), Vector3(1, 0.5, 1)), Color(1.0, 0.75, 0.8), 12)
				b.sphere(0.13, MeshKit.at(Vector3(0, 0.15, 0.05)), c, 12, true)
			5:  # teapot
				b.sphere(0.17, MeshKit.at(Vector3(0, 0.17, 0), Vector3(1, 0.85, 1)), c, 12)
				b.cone(0.04, 0.16, MeshKit.at(Vector3(0.19, 0.2, 0), Vector3.ONE, Vector3(0, 0, -0.9)), c, 6)
				b.torus(0.08, 0.02, MeshKit.at(Vector3(-0.17, 0.2, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), c, 10, 4)
				b.sphere(0.04, MeshKit.at(Vector3(0, 0.33, 0)), Color(1, 1, 1), 6)
			6:  # parrot statue
				b.ellipsoid(Vector3(0.1, 0.17, 0.1), MeshKit.at(Vector3(0, 0.2, 0)), c, 10)
				b.sphere(0.08, MeshKit.at(Vector3(0, 0.38, 0.02)), Color(0.95, 0.25, 0.2), 8)
				b.cone(0.03, 0.08, MeshKit.at(Vector3(0, 0.36, 0.1), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.8, 0.2), 6)
				b.box(Vector3(0.24, 0.04, 0.12), MeshKit.at(Vector3(0, 0.02, 0)), Color(0.6, 0.45, 0.3))
			7:  # ruby
				b.prism(6, 0.16, 0.12, MeshKit.at(Vector3(0, 0.18, 0)), c, true)
				b.cone(0.16, 0.14, MeshKit.at(Vector3(0, 0.06, 0), Vector3.ONE, Vector3(PI, 0, 0)), c, 6, true)
			8:  # trumpet
				b.cylinder(0.025, 0.025, 0.4, MeshKit.at(Vector3(0, 0.08, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5)), c, 8, true)
				b.cone(0.11, 0.14, MeshKit.at(Vector3(0.26, 0.08, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5)), c, 12, true)
			_:  # star
				b.star(5, 0.22, 0.1, 0.07, MeshKit.at(Vector3(0, 0.24, 0)), c, true)
		return b.build()) as ArrayMesh


## The big red X where the relic is buried (flat on the sand).
static func x_mark() -> ArrayMesh:
	return ResCache.get_or_make("td_x_v1", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		for a in [PI * 0.25, -PI * 0.25]:
			b.box(Vector3(1.9, 0.06, 0.38), MeshKit.at(Vector3(0, 0.04, 0), Vector3.ONE, Vector3(0, a, 0)), Color(0.9, 0.12, 0.12), true)
		return b.build()) as ArrayMesh


## A signpost for an island kind: a post, a flag in the island's colours and a little island on top.
static func signpost(sand: Color, rim: Color, accent: Color) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.cylinder(0.08, 0.1, 2.2, MeshKit.at(Vector3(0, 1.1, 0)), Color(0.55, 0.35, 0.2), 8)
	b.rounded_box(Vector3(1.3, 0.8, 0.1), 0.06, MeshKit.at(Vector3(0, 1.9, 0)), rim)
	b.rounded_box(Vector3(1.1, 0.6, 0.12), 0.05, MeshKit.at(Vector3(0, 1.9, 0)), sand)
	b.cylinder(0.32, 0.42, 0.18, MeshKit.at(Vector3(0, 2.45, 0)), sand, 12)
	b.cone(0.22, 0.5, MeshKit.at(Vector3(0, 2.75, 0)), accent, 8)
	return b.build()


## A little stone pedestal for a found relic.
static func pedestal() -> ArrayMesh:
	return ResCache.get_or_make("td_pedestal_v1", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		b.cylinder(0.32, 0.38, 0.5, MeshKit.at(Vector3(0, 0.25, 0)), Color(0.82, 0.8, 0.76), 10)
		b.cylinder(0.36, 0.36, 0.06, MeshKit.at(Vector3(0, 0.52, 0)), Color(0.9, 0.88, 0.84), 10)
		return b.build()) as ArrayMesh
