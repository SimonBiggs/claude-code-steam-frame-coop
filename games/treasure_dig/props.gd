extends RefCounted
## Treasure Dig: the game's own meshes and little effects (all code-made, cached via ResCache).

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

const KIND_COIN := 0
const KIND_GEM := 1
const KIND_BOOT := 2
const VALUES: Array[int] = [1, 3, 1]
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
