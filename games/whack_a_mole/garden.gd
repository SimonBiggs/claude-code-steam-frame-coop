extends Node3D
## FARMER FIG'S GARDEN round the table (story.gd): one soil bed per crop in a ring behind and beside the
## table (never in front of the VR player). The bed growing now sprouts while the team bonks (every point
## is a veg: plants pop up and swell), full beds stay for good (saved), and a crop grown twice or more is
## GIANT. Fig stands by the bed she's growing and cheers when it fills. No words: pictures and plants.
## The host owns the numbers (net state "garden": {beds, cur, fill, need}); every machine draws them.
## Cheap: one merged soil mesh, one MultiMesh of PLANTS instances per bed, one shared mesh per crop.

const Story := preload("res://games/whack_a_mole/story.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Creatures := preload("res://core/creatures.gd")
const ResCache := preload("res://core/res_cache.gd")

const RADIUS := 3.7
const PLANTS := 8  ## per bed: 2 rows of 4
const BED := Vector2(1.5, 0.7)
const GIANT := 1.6

var beds: Array[MultiMesh] = []
var bed_roots: Array[Node3D] = []
var fig: Node3D
var state := {}
var shown := {}  # crop -> visible plants (for pop sounds / bounces)
var cheer_t := -1.0
var cheer_bed := -1
var t := 0.0
var sfx: Node


func _ready() -> void:
	var soil := MeshKit.builder()
	for i in Story.CROPS.size():
		var xf := spot(i)
		soil.rounded_box(Vector3(BED.x + 0.16, 0.12, BED.y + 0.16), 0.05, xf * MeshKit.at(Vector3(0.0, 0.04, 0.0)), Color(0.62, 0.42, 0.26))
		soil.box(Vector3(BED.x, 0.03, BED.y), xf * MeshKit.at(Vector3(0.0, 0.1, 0.0)), Color(0.4, 0.26, 0.16))
		for k in 3:  # little furrows
			soil.box(Vector3(BED.x - 0.1, 0.02, 0.05), xf * MeshKit.at(Vector3(0.0, 0.115, -0.2 + k * 0.2)), Color(0.33, 0.21, 0.12))
	add_child(MeshKit.instance(soil.build(), false))
	for i in Story.CROPS.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = plant_mesh(String(Story.CROPS[i].id))
		mm.instance_count = PLANTS
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var root := Node3D.new()
		root.transform = spot(i)
		add_child(root)
		root.add_child(mmi)
		beds.append(mm)
		bed_roots.append(root)
	fig = Creatures.humanoid({"class": "farmer", "outfit": Story.FIG_COLOR, "seed": 7, "scale": 0.8})
	fig.name = "Fig"
	add_child(fig)
	apply({"beds": {}, "cur": Story.FIRST_CROP, "fill": 0, "need": Story.bed_need(0)})


## Where crop bed i sits: a ring behind and beside the table, facing it (the front stays open).
static func spot(i: int) -> Transform3D:
	var n := Story.CROPS.size()
	var a := deg_to_rad(lerpf(-118.0, 118.0, float(i) / float(n - 1)))
	var p := Vector3(sin(a) * RADIUS, 0.0, -cos(a) * RADIUS * 0.85)
	return Transform3D(Basis(Vector3.UP, -a), p)


## The garden's numbers from the host. Plants pop up / grow; a bed that just filled cheers.
func apply(s: Dictionary) -> void:
	var old := state
	state = s.duplicate(true)
	var bd: Dictionary = s.get("beds", {})
	var cur := String(s.get("cur", ""))
	var frac := clampf(float(s.get("fill", 0)) / maxf(1.0, float(s.get("need", 1))), 0.0, 1.0)
	for i in Story.CROPS.size():
		var id := String(Story.CROPS[i].id)
		var times := int(bd.get(id, 0))
		var mm := beds[i]
		var size := GIANT if times >= 2 else 1.0
		var grow := 0.0
		if id == cur:  # growing now: a grown bed grows again towards giant
			grow = frac
			if times >= 1:
				size = lerpf(1.0, GIANT, frac)
		var n := 0
		for k in PLANTS:
			var sc := size if times >= 1 or id != cur else clampf(grow * PLANTS - k, 0.0, 1.0) * size
			if times >= 1 and id != cur:
				sc = size
			if sc <= 0.02:
				continue
			var x := (float(k % 4) - 1.5) * BED.x / 4.0
			var z := (float(k / 4) - 0.5) * BED.y * 0.55
			var wob := Basis(Vector3.UP, float(k) * 1.7) * Basis.from_scale(Vector3.ONE * sc)
			mm.set_instance_transform(n, Transform3D(wob, Vector3(x, 0.1, z)))
			n += 1
		if n > int(shown.get(id, 0)) and not old.is_empty() and sfx != null:
			sfx.play_at("pop", bed_roots[i].global_position, -10.0, randf_range(1.3, 1.6))
		shown[id] = n
		mm.visible_instance_count = n
	var ob: Dictionary = old.get("beds", {})
	for i in Story.CROPS.size():
		var id := String(Story.CROPS[i].id)
		if int(bd.get(id, 0)) > int(ob.get(id, 0)) and not old.is_empty():
			cheer(i)
	_place_fig(cur if cur != "" else String(old.get("cur", Story.FIRST_CROP)))


func _place_fig(cur: String) -> void:
	var i := Story.crop_index(cur)
	var xf := spot(i)
	fig.position = xf * Vector3(BED.x * 0.5 + 0.35, 0.0, 0.0)
	fig.rotation.y = atan2(-fig.position.x, -fig.position.z)  # faces the table


## A bed just filled: it bounces, Fig cheers.
func cheer(i: int) -> void:
	cheer_bed = i
	cheer_t = 0.0
	if fig != null:
		Creatures.anim(fig).play("cheer", 1.2)
	if sfx != null:
		sfx.play_at("fanfare", bed_roots[i].global_position, -4.0)


func _process(delta: float) -> void:
	t += delta
	if cheer_bed >= 0:
		cheer_t += delta
		var s := 1.0 + sin(cheer_t * 12.0) * 0.15 * maxf(0.0, 1.0 - cheer_t / 1.5)
		bed_roots[cheer_bed].scale = Vector3(1.0, s, 1.0)
		if cheer_t > 1.5:
			bed_roots[cheer_bed].scale = Vector3.ONE
			cheer_bed = -1
	if fig != null:
		Creatures.anim(fig).walk(0.0)


## One veg plant (about 0.2-0.6 m), origin on the soil. Cached per crop.
static func plant_mesh(id: String) -> Mesh:
	return ResCache.get_or_make("wam_plant_" + id, func() -> Resource: return _build_plant(id))


static func _build_plant(id: String) -> ArrayMesh:
	var b := MeshKit.builder()
	var leaf := Color(0.35, 0.72, 0.3)
	var c: Color = Story.crop(id).color
	match id:
		"LETTUCE":
			for k in 5:
				var a := k * TAU / 5.0
				b.ellipsoid(Vector3(0.08, 0.06, 0.08), MeshKit.at(Vector3(cos(a) * 0.05, 0.06, sin(a) * 0.05)), c.darkened(0.1 * (k % 2)), 8)
			b.sphere(0.06, MeshKit.at(Vector3(0.0, 0.1, 0.0)), c.lightened(0.3), 8)
		"CARROTS":
			b.cone(0.045, 0.06, MeshKit.at(Vector3(0.0, 0.02, 0.0)), c, 8)
			for k in 3:
				b.cone(0.025, 0.2, MeshKit.at(Vector3((k - 1) * 0.03, 0.14, 0.0), Vector3.ONE, Vector3(0.0, 0.0, (k - 1) * 0.3)), leaf, 5)
		"PUMPKINS":
			b.ellipsoid(Vector3(0.13, 0.09, 0.13), MeshKit.at(Vector3(0.0, 0.09, 0.0)), c, 12)
			b.cylinder(0.015, 0.02, 0.06, MeshKit.at(Vector3(0.0, 0.2, 0.0)), Color(0.4, 0.5, 0.2), 6)
			b.ellipsoid(Vector3(0.07, 0.01, 0.05), MeshKit.at(Vector3(0.09, 0.03, 0.08)), leaf, 6)
		"SUNFLOWERS":
			b.cylinder(0.015, 0.02, 0.6, MeshKit.at(Vector3(0.0, 0.3, 0.0)), leaf, 6)
			b.ellipsoid(Vector3(0.06, 0.01, 0.03), MeshKit.at(Vector3(0.04, 0.3, 0.0)), leaf, 6)
			var head := MeshKit.at(Vector3(0.0, 0.62, 0.02), Vector3.ONE, Vector3(PI * 0.4, 0.0, 0.0))
			b.cylinder(0.11, 0.11, 0.02, head, Color(1.0, 0.85, 0.2), 12)
			b.cylinder(0.06, 0.06, 0.03, head, Color(0.45, 0.28, 0.12), 10)
		"STRAWBERRIES":
			b.ellipsoid(Vector3(0.1, 0.05, 0.1), MeshKit.at(Vector3(0.0, 0.05, 0.0)), leaf, 8)
			for k in 3:
				var a := k * TAU / 3.0
				b.cone(0.035, 0.06, MeshKit.at(Vector3(cos(a) * 0.08, 0.06, sin(a) * 0.08), Vector3.ONE, Vector3(PI, 0.0, 0.0)), c, 8)
		"CORN":
			b.cylinder(0.015, 0.025, 0.7, MeshKit.at(Vector3(0.0, 0.35, 0.0)), leaf, 6)
			b.ellipsoid(Vector3(0.035, 0.09, 0.035), MeshKit.at(Vector3(0.04, 0.42, 0.0)), c, 8)
			b.ellipsoid(Vector3(0.1, 0.012, 0.03), MeshKit.at(Vector3(-0.07, 0.3, 0.0), Vector3.ONE, Vector3(0.0, 0.0, -0.4)), leaf, 6)
		"MELONS":
			b.ellipsoid(Vector3(0.14, 0.1, 0.11), MeshKit.at(Vector3(0.0, 0.1, 0.0)), c, 12)
			for k in 3:
				b.ellipsoid(Vector3(0.142, 0.02, 0.112), MeshKit.at(Vector3(0.0, 0.1, 0.0), Vector3.ONE, Vector3((k - 1) * 0.6, 0.0, PI * 0.5)), c.lightened(0.35), 10)
		"APPLES":
			b.cylinder(0.03, 0.04, 0.4, MeshKit.at(Vector3(0.0, 0.2, 0.0)), Color(0.5, 0.32, 0.18), 6)
			b.sphere(0.2, MeshKit.at(Vector3(0.0, 0.5, 0.0)), Color(0.3, 0.68, 0.3), 10)
			for k in 4:
				var a := k * TAU / 4.0 + 0.4
				b.sphere(0.035, MeshKit.at(Vector3(cos(a) * 0.17, 0.45 + (k % 2) * 0.1, sin(a) * 0.17)), c, 6)
	return b.build()
