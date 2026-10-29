extends Node3D
## POPPY'S FAIR round the park (story.gd): one spot per ride in an arc on the far side (in front of the VR
## player and at the top of every TV view). The ride being built rises out of the grass while the team
## pops (every point is a ticket), finished rides stay for good (saved) and come alive (the carousel and
## the big wheel turn, the castle bounces, the hot-air balloon bobs, fireworks go off); a ride built
## twice or more gets lights. Poppy stands at the park's edge by the ride being built, holding a bunch of
## balloons, and cheers when one is finished. No words: pictures and rides.
## The host owns the numbers (net state "fair": {rides, cur, fill, need}); every machine draws them.
## Cheap: per ride one static mesh + one moving part (cached per ride), Poppy is one humanoid.

const Story := preload("res://games/balloon_pop/story.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Creatures := preload("res://core/creatures.gd")
const ResCache := preload("res://core/res_cache.gd")

const RADIUS := 11.5
const ANGLES: Array[float] = [-18.0, 18.0, -44.0, 44.0, -70.0, 70.0, -96.0, 96.0]
const BULBS := Color(1.0, 0.92, 0.55)
const STRIPES: Array[Color] = [Color(1.0, 0.35, 0.4), Color(1.0, 0.85, 0.3), Color(0.35, 0.65, 1.0),
	Color(0.5, 0.9, 0.45), Color(0.85, 0.5, 1.0), Color(1.0, 0.55, 0.15)]

var roots: Array[Node3D] = []  # per ride: the whole ride (scaled while it grows)
var parts: Array[Node3D] = []  # per ride: the moving part (or null)
var lights: Array[MeshInstance3D] = []
var poppy: Node3D
var bunch: Node3D
var state := {}
var cheer_t := -1.0
var cheer_i := -1
var t := 0.0
var boom_t := 2.0
var sfx: Node


func _ready() -> void:
	for i in Story.RIDES.size():
		var id := String(Story.RIDES[i].id)
		var root := Node3D.new()
		root.name = id
		root.transform = spot(i)
		add_child(root)
		var base := MeshInstance3D.new()
		base.mesh = ride_mesh(id)
		root.add_child(base)
		var pm := part_mesh(id)
		var part: Node3D = null
		if pm != null:
			part = Node3D.new()
			part.position = part_pivot(id)
			root.add_child(part)
			var mi := MeshInstance3D.new()
			mi.mesh = pm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			part.add_child(mi)
		var lm := MeshInstance3D.new()
		lm.mesh = lights_mesh(id)
		lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lm.visible = false
		root.add_child(lm)
		root.visible = false
		roots.append(root)
		parts.append(part)
		lights.append(lm)
	poppy = Creatures.humanoid({"class": "host", "hat": "party", "outfit": Story.POPPY_COLOR, "outfit2": Color(1.0, 0.85, 0.3),
		"seed": 11, "scale": 0.9})
	poppy.name = "Poppy"
	add_child(poppy)
	bunch = Node3D.new()
	var bm := MeshInstance3D.new()
	bm.mesh = bunch_mesh()
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bunch.add_child(bm)
	add_child(bunch)
	apply({"rides": {}, "cur": Story.FIRST_RIDE, "fill": 0, "need": Story.ride_need(0)})


## Where ride i stands: an arc on the far side of the park, facing the middle. The first rides stand
## straight ahead (in every TV view and in front of the VR player), later ones round the sides.
static func spot(i: int) -> Transform3D:
	var a := deg_to_rad(ANGLES[i % ANGLES.size()])
	var p := Vector3(sin(a) * RADIUS, 0.0, -cos(a) * RADIUS)
	return Transform3D(Basis(Vector3.UP, -a), p)


## The fair's numbers from the host. The ride being built grows; a ride just finished cheers.
func apply(s: Dictionary) -> void:
	var old := state
	state = s.duplicate(true)
	var rd: Dictionary = s.get("rides", {})
	var cur := String(s.get("cur", ""))
	var frac := clampf(float(s.get("fill", 0)) / maxf(1.0, float(s.get("need", 1))), 0.0, 1.0)
	for i in Story.RIDES.size():
		var id := String(Story.RIDES[i].id)
		var times := int(rd.get(id, 0))
		var root := roots[i]
		lights[i].visible = times >= 2 or (times >= 1 and id == cur and frac > 0.5)
		if id == cur and times == 0:
			root.visible = frac > 0.0
			var g := 0.15 + 0.85 * frac
			root.scale = Vector3(lerpf(0.6, 1.0, frac), g, lerpf(0.6, 1.0, frac))
		else:
			root.visible = times >= 1
			root.scale = Vector3.ONE
	var ob: Dictionary = old.get("rides", {})
	for i in Story.RIDES.size():
		var id := String(Story.RIDES[i].id)
		if int(rd.get(id, 0)) > int(ob.get(id, 0)) and not old.is_empty():
			cheer(i)
	_place_poppy(cur if cur != "" else String(old.get("cur", Story.FIRST_RIDE)))


## Poppy stands at the edge of the park in front of the ride being built, facing the middle.
func _place_poppy(cur: String) -> void:
	var i := Story.ride_index(cur)
	var a := deg_to_rad(ANGLES[i % ANGLES.size()]) * 0.8
	poppy.position = Vector3(sin(a) * 8.2, 0.0, -cos(a) * 8.2)
	poppy.rotation.y = atan2(-poppy.position.x, -poppy.position.z)


## A ride was just finished (or chosen): it bounces, Poppy cheers.
func cheer(i: int) -> void:
	cheer_i = i
	cheer_t = 0.0
	roots[i].visible = true
	if poppy != null:
		Creatures.anim(poppy).play("cheer", 1.2)
	if sfx != null:
		sfx.play_at("fanfare", roots[i].global_position, -4.0)


func _process(delta: float) -> void:
	t += delta
	if cheer_i >= 0:
		cheer_t += delta
		var s := 1.0 + sin(cheer_t * 12.0) * 0.12 * maxf(0.0, 1.0 - cheer_t / 1.5)
		roots[cheer_i].scale = Vector3(1.0, s, 1.0)
		if cheer_t > 1.5:
			roots[cheer_i].scale = Vector3.ONE
			cheer_i = -1
			apply(state)
	for i in parts.size():
		var p := parts[i]
		if p == null or not roots[i].visible:
			continue
		match String(Story.RIDES[i].id):
			"CAROUSEL":
				p.rotation.y = t * 0.8
			"FERRIS":
				p.rotation.z = t * 0.35
			"HOTAIR":
				p.position.y = part_pivot("HOTAIR").y + sin(t * 0.7) * 0.5
			"CASTLE":
				p.scale = Vector3(1.0, 1.0 + sin(t * 5.0) * 0.04, 1.0)
	var fi := Story.ride_index("FIREWORKS")
	if roots[fi].visible and roots[fi].scale.y > 0.99:
		boom_t -= delta
		if boom_t <= 0.0:
			boom_t = randf_range(2.5, 5.0)
			_firework(roots[fi].global_position + Vector3(randf_range(-1.5, 1.5), randf_range(7.0, 9.0), randf_range(-1.0, 1.0)))
	if poppy != null:
		Creatures.anim(poppy).walk(0.0)
		bunch.global_position = poppy.global_position + poppy.global_basis * Vector3(0.35, 1.2, 0.1)
		bunch.rotation.z = sin(t * 1.3) * 0.08


func _firework(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 40
	p.lifetime = 1.4
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector3(0.0, -2.5, 0.0)
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 4.5
	p.damping_min = 1.0
	p.damping_max = 1.5
	p.mesh = ResCache.get_or_make("bp_spark_%d" % (randi() % STRIPES.size()), func() -> Resource:
		var m := SphereMesh.new()
		m.radius = 0.08
		m.height = 0.16
		m.radial_segments = 6
		m.rings = 3
		m.material = MeshKit.material(STRIPES[randi() % STRIPES.size()], 3.0)
		return m)
	add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
	if sfx != null:
		sfx.play_at("pop", at, -8.0, 0.5)


# --- Ride meshes (shared, cached: the choice balloons carry small copies) ---------------------------

## The ride's still part (origin on the grass, facing +Z = the park).
static func ride_mesh(id: String) -> Mesh:
	return ResCache.get_or_make("bp_ride_%s_v1" % id, func() -> Resource: return _build_ride(id))


## The ride's moving part (around part_pivot), or null.
static func part_mesh(id: String) -> Mesh:
	if not ["CAROUSEL", "FERRIS", "HOTAIR", "CASTLE"].has(id):
		return null
	return ResCache.get_or_make("bp_part_%s_v1" % id, func() -> Resource: return _build_part(id))


static func part_pivot(id: String) -> Vector3:
	match id:
		"FERRIS":
			return Vector3(0.0, 3.4, 0.0)
		"HOTAIR":
			return Vector3(0.0, 3.2, 0.0)
	return Vector3.ZERO


## Glowing bulbs for a ride built twice or more.
static func lights_mesh(id: String) -> Mesh:
	return ResCache.get_or_make("bp_lights_%s_v1" % id, func() -> Resource:
		var b := MeshKit.builder()
		var top := 3.6
		match id:
			"BUNTING":
				top = 2.6
			"ICECREAM":
				top = 3.4
			"FERRIS":
				top = 6.4
			"HOTAIR":
				top = 1.3
			"FIREWORKS":
				top = 4.6
		for k in 8:
			var a := k * TAU / 8.0
			b.sphere(0.12, MeshKit.at(Vector3(cos(a) * 1.6, top, sin(a) * 1.0)), BULBS, 6, true)
		return b.build())


static func bunch_mesh() -> Mesh:
	return ResCache.get_or_make("bp_bunch_v1", func() -> Resource:
		var b := MeshKit.builder()
		for k in 5:
			var a := k * TAU / 5.0
			var top := Vector3(cos(a) * 0.22, 1.1 + (k % 2) * 0.15, sin(a) * 0.22)
			b.tube(Vector3.ZERO, top, 0.006, 0.006, Color(0.95, 0.95, 0.95), 3)
			b.ellipsoid(Vector3(0.17, 0.21, 0.17), MeshKit.at(top + Vector3(0.0, 0.2, 0.0)), STRIPES[k], 10)
		return b.build())


static func _build_ride(id: String) -> ArrayMesh:
	var b := MeshKit.builder()
	var white := Color(0.97, 0.97, 0.95)
	match id:
		"BUNTING":  # three lines of little flags on poles
			var poles: Array[Vector3] = [Vector3(-2.6, 0.0, 0.4), Vector3(-0.9, 0.0, -0.3), Vector3(0.9, 0.0, -0.3), Vector3(2.6, 0.0, 0.4)]
			for p in poles:
				b.cylinder(0.07, 0.09, 2.8, MeshKit.at(p + Vector3(0.0, 1.4, 0.0)), white, 6)
				b.sphere(0.12, MeshKit.at(p + Vector3(0.0, 2.85, 0.0)), Color(1.0, 0.85, 0.3), 6)
			for k in poles.size() - 1:
				for j in 6:
					var f := (j + 0.5) / 6.0
					var q: Vector3 = poles[k].lerp(poles[k + 1], f) + Vector3(0.0, 2.65 - sin(f * PI) * 0.5, 0.0)
					b.cone(0.18, 0.38, MeshKit.at(q + Vector3(0.0, -0.18, 0.0), Vector3(1.0, 1.0, 0.2), Vector3(PI, 0.0, 0.0)), STRIPES[(k * 6 + j) % STRIPES.size()], 4)
		"ICECREAM":  # a cart with a stripy umbrella and a giant cone on top
			b.rounded_box(Vector3(2.0, 1.0, 1.0), 0.08, MeshKit.at(Vector3(0.0, 0.75, 0.0)), Color(1.0, 0.8, 0.88))
			b.box(Vector3(2.05, 0.18, 1.05), MeshKit.at(Vector3(0.0, 1.2, 0.0)), Color(0.55, 0.85, 1.0))
			for sx in [-0.7, 0.7]:
				b.cylinder(0.25, 0.25, 0.1, MeshKit.at(Vector3(sx, 0.25, 0.52), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), Color(0.3, 0.3, 0.35), 12)
			b.cylinder(0.04, 0.04, 1.6, MeshKit.at(Vector3(-0.6, 2.0, 0.0)), white, 6)
			for k in 6:
				b.dome(1.0, MeshKit.at(Vector3(-0.6, 2.75, 0.0), Vector3(1.0, 0.45, 1.0), Vector3(0.0, k * TAU / 6.0, 0.0)),
					STRIPES[k % 2] if k % 2 == 0 else white, 10)
			b.cone(0.3, 0.9, MeshKit.at(Vector3(0.6, 1.75, 0.0), Vector3.ONE, Vector3(PI, 0.0, 0.0)), Color(0.85, 0.6, 0.3), 10)
			b.sphere(0.32, MeshKit.at(Vector3(0.6, 2.3, 0.0)), Color(1.0, 0.75, 0.85), 10)
			b.sphere(0.28, MeshKit.at(Vector3(0.6, 2.7, 0.0)), Color(0.55, 0.35, 0.25), 10)
			b.sphere(0.07, MeshKit.at(Vector3(0.6, 3.0, 0.0)), Color(0.9, 0.15, 0.2), 6)
		"CAROUSEL":  # the still base (the roof and horses turn: part)
			b.cylinder(1.9, 2.0, 0.3, MeshKit.at(Vector3(0.0, 0.15, 0.0)), Color(0.95, 0.85, 0.6), 20)
		"CASTLE":  # the bouncy castle's mat (the castle bounces: part)
			b.rounded_box(Vector3(3.4, 0.25, 3.0), 0.1, MeshKit.at(Vector3(0.0, 0.12, 0.0)), Color(0.35, 0.65, 1.0))
		"BIGTOP":  # a striped circus tent with a flag
			for k in 12:
				var a := k * TAU / 12.0
				b.box(Vector3(0.95, 2.0, 0.08), MeshKit.at(Vector3(cos(a) * 1.75, 1.0, sin(a) * 1.75), Vector3.ONE, Vector3(0.0, -a + PI * 0.5, 0.0)),
					Color(0.95, 0.25, 0.3) if k % 2 == 0 else white)
			b.cone(2.2, 1.8, MeshKit.at(Vector3(0.0, 2.9, 0.0)), Color(0.95, 0.25, 0.3), 12)
			b.cylinder(0.04, 0.04, 0.9, MeshKit.at(Vector3(0.0, 4.1, 0.0)), white, 5)
			b.box(Vector3(0.5, 0.3, 0.03), MeshKit.at(Vector3(0.25, 4.4, 0.0)), Color(1.0, 0.85, 0.3))
			b.box(Vector3(0.9, 1.4, 0.1), MeshKit.at(Vector3(0.0, 0.7, 1.78)), Color(0.2, 0.15, 0.2))
		"FERRIS":  # two A-frame legs (the wheel turns: part)
			for sz in [-0.5, 0.5]:
				for sx in [-1.0, 1.0]:
					b.tube(Vector3(sx * 1.4, 0.0, sz), Vector3(0.0, 3.4, sz), 0.08, 0.07, Color(0.85, 0.85, 0.9), 6)
			b.cylinder(0.12, 0.12, 1.2, MeshKit.at(Vector3(0.0, 3.4, 0.0), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), Color(0.6, 0.6, 0.65), 8)
			b.rounded_box(Vector3(1.6, 0.3, 1.0), 0.05, MeshKit.at(Vector3(0.0, 0.15, 0.9)), Color(1.0, 0.8, 0.25))
		"HOTAIR":  # a landing mat and ropes' pegs (the balloon floats: part)
			b.cylinder(1.4, 1.4, 0.05, MeshKit.at(Vector3(0.0, 0.03, 0.0)), Color(0.95, 0.85, 0.5), 16)
			for k in 4:
				var a := k * TAU / 4.0 + 0.4
				b.cylinder(0.05, 0.05, 0.4, MeshKit.at(Vector3(cos(a) * 1.2, 0.2, sin(a) * 1.2)), Color(0.5, 0.35, 0.2), 5)
		"FIREWORKS":  # a launch tower with rockets
			for k in 4:
				var a := k * TAU / 4.0 + PI * 0.25
				b.cylinder(0.07, 0.07, 3.2, MeshKit.at(Vector3(cos(a) * 0.7, 1.6, sin(a) * 0.7)), Color(0.55, 0.4, 0.3), 6)
			b.box(Vector3(1.8, 0.15, 1.8), MeshKit.at(Vector3(0.0, 3.2, 0.0)), Color(0.45, 0.32, 0.25))
			for k in 3:
				b.cylinder(0.14, 0.14, 0.8, MeshKit.at(Vector3(-0.5 + k * 0.5, 3.7, 0.0)), STRIPES[k], 8)
				b.cone(0.16, 0.3, MeshKit.at(Vector3(-0.5 + k * 0.5, 4.25, 0.0)), white, 8)
	return b.build()


static func _build_part(id: String) -> ArrayMesh:
	var b := MeshKit.builder()
	var white := Color(0.97, 0.97, 0.95)
	match id:
		"CAROUSEL":  # a striped roof, a middle pole and four horses on poles
			b.cylinder(0.2, 0.2, 2.8, MeshKit.at(Vector3(0.0, 1.7, 0.0)), Color(1.0, 0.85, 0.3), 8)
			for k in 8:
				b.dome(2.1, MeshKit.at(Vector3(0.0, 3.1, 0.0), Vector3(1.0, 0.5, 1.0), Vector3(0.0, k * TAU / 8.0, 0.0)),
					Color(0.4, 0.7, 1.0) if k % 2 == 0 else white, 10)
			b.sphere(0.2, MeshKit.at(Vector3(0.0, 4.2, 0.0)), Color(1.0, 0.85, 0.3), 8)
			for k in 4:
				var a := k * TAU / 4.0
				var p := Vector3(cos(a) * 1.4, 0.0, sin(a) * 1.4)
				b.cylinder(0.04, 0.04, 2.9, MeshKit.at(p + Vector3(0.0, 1.75, 0.0)), Color(1.0, 0.85, 0.3), 5)
				var face := Vector3(0.0, -a, 0.0)
				b.ellipsoid(Vector3(0.45, 0.22, 0.16), MeshKit.at(p + Vector3(0.0, 1.2 + (k % 2) * 0.3, 0.0), Vector3.ONE, face), STRIPES[k], 8)
				b.ellipsoid(Vector3(0.14, 0.2, 0.12), MeshKit.at(p + Vector3(0.0, 1.45 + (k % 2) * 0.3, 0.0) + Basis.from_euler(face) * Vector3(0.38, 0.0, 0.0)), STRIPES[k], 8)
		"CASTLE":  # a puffy castle in purple and yellow
			b.rounded_box(Vector3(3.0, 1.2, 2.6), 0.35, MeshKit.at(Vector3(0.0, 0.85, 0.0)), Color(0.75, 0.5, 1.0))
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var p := Vector3(sx * 1.35, 0.0, sz * 1.15)
					b.cylinder(0.38, 0.4, 2.4, MeshKit.at(p + Vector3(0.0, 1.4, 0.0)), Color(1.0, 0.85, 0.3), 10)
					b.dome(0.45, MeshKit.at(p + Vector3(0.0, 2.6, 0.0)), Color(1.0, 0.4, 0.5), 10)
			b.dome(0.7, MeshKit.at(Vector3(0.0, 0.25, 1.3), Vector3(1.0, 1.2, 0.3)), Color(0.25, 0.2, 0.35), 10)
		"FERRIS":  # the wheel (pivot at its middle), spokes and coloured cars
			b.torus(2.6, 0.08, MeshKit.at(Vector3(0.0, 0.0, 0.0), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), Color(1.0, 0.8, 0.25), 24, 5)
			for k in 8:
				var a := k * TAU / 8.0
				var p := Vector3(cos(a) * 2.6, sin(a) * 2.6, 0.0)
				b.tube(Vector3.ZERO, p, 0.04, 0.04, white, 4)
				b.rounded_box(Vector3(0.5, 0.45, 0.6), 0.08, MeshKit.at(p + Vector3(0.0, -0.3, 0.0)), STRIPES[k % STRIPES.size()])
		"HOTAIR":  # a striped balloon (pivot at its middle) with a basket
			for k in 8:
				b.ellipsoid(Vector3(1.3, 1.5, 1.3), MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(0.0, k * TAU / 8.0, 0.0)),
					Color(1.0, 0.55, 0.15) if k % 2 == 0 else Color(1.0, 0.85, 0.3), 10)
			for k in 4:
				var a := k * TAU / 4.0 + 0.4
				b.tube(Vector3(cos(a) * 0.7, -1.25, sin(a) * 0.7), Vector3(cos(a) * 0.35, -2.1, sin(a) * 0.35), 0.02, 0.02, Color(0.5, 0.35, 0.2), 3)
			b.rounded_box(Vector3(0.8, 0.5, 0.8), 0.06, MeshKit.at(Vector3(0.0, -2.3, 0.0)), Color(0.6, 0.42, 0.25))
	return b.build()
