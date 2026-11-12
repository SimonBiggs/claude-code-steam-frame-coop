extends Node3D
## TINY TOWN TYCOON: BENNY'S BUILDER GIFTS at work on every machine (deep.gd GIFTS; the day's gift comes in the "deep"
## state). The host does what each gift does (main.gd / sim.gd / jobs.gd); this draws it:
##   SPEEDY CRANE   a golden sparkle trail behind every crane (bricks two at a time, sites pop up fast).
##   DOUBLE HOUSES  (a twin house blueprint pops up next to each new house: main.gd)
##   HAPPY PARK     a bunch of balloons bobs over every park (people near a park move in twice as fast).
##   ZOOMY WHEELS   a blue speed trail behind every vehicle (they all drive faster).
##   SUNNY DAY      (the weather is gentle all day: deep.gd effect())
## Cheap: one shared trail mesh, one balloon multimesh rebuilt only when the parks change.
##   set_gift(id), follow(delta) every frame

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const Deep := preload("res://games/tiny_town_tycoon/deep.gd")

const BALLOON_COLORS: Array[Color] = [Color(1.0, 0.35, 0.4), Color(1.0, 0.85, 0.25), Color(0.4, 0.75, 1.0)]
const BALLOON_UP := 0.07

var main
var gift := ""
var trails := {}  # vid -> CPUParticles3D
var balloons: MultiMeshInstance3D
var _parks_key := ""
var _t := 0.0


func _ready() -> void:
	name = "Gifts"
	balloons = MultiMeshInstance3D.new()
	balloons.name = "ParkBalloons"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _balloon_mesh()
	balloons.multimesh = mm
	balloons.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(balloons)


## Every machine: today's gift ("" none).
func set_gift(id: String) -> void:
	if id == gift:
		return
	gift = id
	for vid in trails.keys():
		_drop_trail(vid)
	_parks_key = "?"


func _wants_trail(v: Node3D) -> bool:
	return gift == "zoomy" or (gift == "crane" and String(v.get("kind")) == "crane")


## Every frame: trails ride with their vehicles; the park balloons bob (rebuilt when the parks change).
func follow(delta: float) -> void:
	_t += delta
	var vehicles: Dictionary = main.fleet.vehicles
	for vid in trails.keys():
		if not vehicles.has(vid) or not _wants_trail(vehicles[vid]):
			_drop_trail(vid)
	for vid in vehicles:
		var v: Node3D = vehicles[vid]
		if _wants_trail(v) and not trails.has(vid):
			var p := CPUParticles3D.new()
			p.name = "GiftTrail"
			p.amount = 12
			p.lifetime = 0.6
			p.local_coords = false
			p.mesh = _spark_mesh()
			p.color = Deep.gift(gift).get("color", Color.WHITE)
			p.gravity = Vector3(0.0, 0.02, 0.0)
			p.initial_velocity_min = 0.0
			p.initial_velocity_max = 0.01
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.0
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			p.position = Vector3(0.0, 0.01, -Defs.CELL * 0.3)
			v.add_child(p)
			trails[vid] = p
	if gift != "park":
		if balloons.multimesh.instance_count > 0:
			balloons.multimesh.instance_count = 0
		return
	var parks: Array = []
	for id in main.town.buildings:
		var b: Dictionary = main.town.buildings[id]
		if String(b["kind"]) == "park" and int(b["stage"]) >= 1:
			parks.append(main.town.center_of(b))
	var k := str(parks)
	var mm := balloons.multimesh
	if k != _parks_key:
		_parks_key = k
		mm.instance_count = parks.size() * 3
		for i in parks.size():
			for j in 3:
				mm.set_instance_color(i * 3 + j, BALLOON_COLORS[j])
	for i in parks.size():
		for j in 3:
			var c: Vector3 = parks[i]
			var a := float(j) * TAU / 3.0 + _t * 0.6
			var bob := sin(_t * 2.0 + float(i) + j) * 0.004
			mm.set_instance_transform(i * 3 + j, Transform3D(Basis(), c + Vector3(cos(a) * 0.008, BALLOON_UP + bob + j * 0.006, sin(a) * 0.008)))


func _drop_trail(vid: Variant) -> void:
	var p: Node = trails.get(vid, null)
	if p != null and is_instance_valid(p):
		p.queue_free()
	trails.erase(vid)


static func _spark_mesh() -> Mesh:
	return ResCache.get_or_make("town_gift_spark", func() -> Resource:
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * 0.004
		var m := MeshKit.material(Color.WHITE, 1.8).duplicate() as StandardMaterial3D
		m.vertex_color_use_as_albedo = true
		bm.material = m
		return bm) as Mesh


static func _balloon_mesh() -> Mesh:
	return ResCache.get_or_make("town_park_balloon", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.sphere(0.009, MeshKit.at(Vector3.ZERO, Vector3(1.0, 1.2, 1.0)), Color.WHITE, 10)
		b.box(Vector3(0.0006, 0.05, 0.0006), MeshKit.at(Vector3(0.0, -0.035, 0.0)), Color(0.95, 0.95, 0.95))
		return b.build()) as Mesh  # (vertex colours: each balloon's instance colour tints it)
