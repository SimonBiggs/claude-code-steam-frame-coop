extends Node3D
## TumTum's park: the story you can see. Every round the family finishes plants something beside the court
## (a daisy, a sunflower, a little tree, balloons, a bunny, a toadstool, a duckling); each grows a stage every
## play-day after it came (courtgen.gd park_stage), and the ones from TODAY'S PARK are golden. Saved on the
## host (main.gd save.park) and sent as the "park" / "days" state, so every machine draws the same park.
## Cheap: one merged mesh per thing, at most CourtGen.PARK_SLOTS of them, a gentle sway per frame.
##   park.set_items([[kind, joined_day, golden], ...], days)   # oldest first
##   park.cheer()                                              # the newest one hops

const MeshKit := preload("res://core/mesh_kit.gd")
const CourtGen := preload("res://games/dodge_ball/courtgen.gd")

const GOLD := Color(1.0, 0.8, 0.25)
const BALLOON_COLS: Array[Color] = [Color(1.0, 0.4, 0.45), Color(0.4, 0.7, 1.0), Color(1.0, 0.85, 0.3), Color(0.6, 0.9, 0.5)]

var things: Array[Node3D] = []
var hop := 0.0
var _key := ""
var _t := 0.0


func set_items(list: Array, days: int) -> void:
	var key := var_to_str([list, days])
	if key == _key:
		return
	_key = key
	for n in things:
		n.queue_free()
	things.clear()
	for i in mini(list.size(), CourtGen.PARK_SLOTS):
		var e: Array = list[i]
		var kind: String = CourtGen.PARK_KINDS[int(e[0]) % CourtGen.PARK_KINDS.size()]
		var stage := CourtGen.park_stage(int(e[1]), days)
		var at := CourtGen.park_slot(i)
		var n := Node3D.new()
		n.name = "Park%d" % i
		n.position = at
		var to := Vector3(0.0, 0.0, 1.0) - at
		n.rotation.y = atan2(to.x, to.z)  # faces the court
		var b := MeshKit.Builder.new()
		_thing(b, kind, stage, bool(e[2]) if e.size() > 2 else false, i)
		n.add_child(MeshKit.instance(b.build(), false))
		add_child(n)
		things.append(n)


func cheer() -> void:
	hop = 1.0


func _process(delta: float) -> void:
	_t += delta
	hop = move_toward(hop, 0.0, delta * 0.8)
	for i in things.size():
		var n := things[i]
		n.rotation.z = 0.04 * sin(_t * 1.3 + float(i))
		n.position.y = 0.0
		if i == things.size() - 1 and hop > 0.0:
			n.position.y = absf(sin(hop * 12.0)) * 0.35 * hop


func _thing(b: MeshKit.Builder, kind: String, stage: int, golden: bool, i: int) -> void:
	var s := 0.6 + 0.15 * float(stage)  # grows a stage a day
	var gold := func(c: Color) -> Color: return GOLD if golden else c
	match kind:
		"daisy":
			for k in 1 + mini(stage, 2):
				var off := Vector3(0.22 * float(k) - 0.22, 0.0, 0.12 * float(k % 2))
				var h := (0.45 + 0.1 * float(k % 2)) * s
				b.cylinder(0.02, 0.025, h, MeshKit.at(off + Vector3(0.0, h * 0.5, 0.0)), Color(0.3, 0.7, 0.3), 6)
				for p in 6:
					var a := TAU * float(p) / 6.0
					b.ellipsoid(Vector3(0.07, 0.02, 0.035) * s, MeshKit.at(off + Vector3(cos(a) * 0.07 * s, h, sin(a) * 0.07 * s), Vector3.ONE, Vector3(0.0, -a, 0.0)), gold.call(Color.WHITE), 8)
				b.sphere(0.04 * s, MeshKit.at(off + Vector3(0.0, h + 0.01, 0.0)), Color(1.0, 0.8, 0.2), 8)
		"sunflower":
			var h := 1.1 * s
			b.cylinder(0.035, 0.045, h, MeshKit.at(Vector3(0.0, h * 0.5, 0.0)), Color(0.3, 0.65, 0.25), 8)
			b.ellipsoid(Vector3(0.12, 0.03, 0.06), MeshKit.at(Vector3(0.08, h * 0.45, 0.0)), Color(0.3, 0.7, 0.3), 8)
			var head := Vector3(0.0, h, 0.04)
			for p in 10:
				var a := TAU * float(p) / 10.0
				b.ellipsoid(Vector3(0.05, 0.11, 0.02) * s, MeshKit.at(head + Vector3(cos(a), sin(a), 0.0) * 0.13 * s, Vector3.ONE, Vector3(0.0, 0.0, a - PI * 0.5)), gold.call(Color(1.0, 0.82, 0.15)), 8)
			b.ellipsoid(Vector3(0.1, 0.1, 0.04) * s, MeshKit.at(head + Vector3(0.0, 0.0, 0.01)), Color(0.45, 0.28, 0.12), 12)
		"sapling":
			var h := 0.7 * s * (1.0 + 0.25 * float(stage))
			b.cylinder(0.05 * s, 0.07 * s, h, MeshKit.at(Vector3(0.0, h * 0.5, 0.0)), Color(0.55, 0.35, 0.2), 8)
			var crown := 0.3 * s * (1.0 + 0.2 * float(stage))
			b.sphere(crown, MeshKit.at(Vector3(0.0, h + crown * 0.6, 0.0)), gold.call(Color(0.35, 0.75, 0.35)), 12)
			b.sphere(crown * 0.7, MeshKit.at(Vector3(crown * 0.6, h + crown * 0.3, 0.0)), gold.call(Color(0.4, 0.8, 0.4)), 10)
			if stage >= 3:  # apples
				for k in 4:
					var a := TAU * float(k) / 4.0
					b.sphere(0.05, MeshKit.at(Vector3(cos(a) * crown * 0.8, h + crown * 0.4, sin(a) * crown * 0.8 + 0.05)), Color(0.9, 0.2, 0.2), 8)
		"balloon":
			for k in 1 + stage:
				var a := float(k) * 1.4 + float(i)
				var top := Vector3(cos(a) * 0.15 * float(mini(k, 1)), 1.2 + 0.12 * float(k % 2), sin(a) * 0.15 * float(mini(k, 1)))
				b.tube(Vector3(0.0, 0.05, 0.0), top, 0.006, 0.006, Color(0.95, 0.95, 0.95), 4)
				b.ellipsoid(Vector3(0.13, 0.16, 0.13), MeshKit.at(top + Vector3(0.0, 0.15, 0.0)), gold.call(BALLOON_COLS[(i + k) % BALLOON_COLS.size()]), 10)
			b.cylinder(0.06, 0.07, 0.08, MeshKit.at(Vector3(0.0, 0.04, 0.0)), Color(0.6, 0.45, 0.3), 8)  # a little weight
		"bunny":
			for k in 1 + (1 if stage >= 2 else 0):
				var sc := s if k == 0 else s * 0.6
				var off := Vector3(0.3 * float(k), 0.0, 0.1 * float(k))
				var fur: Color = gold.call(Color(0.95, 0.93, 0.92))
				b.ellipsoid(Vector3(0.16, 0.14, 0.2) * sc, MeshKit.at(off + Vector3(0.0, 0.14 * sc, 0.0)), fur, 10)
				b.sphere(0.12 * sc, MeshKit.at(off + Vector3(0.0, 0.32 * sc, 0.12 * sc)), fur, 10)
				for ex in [-0.05, 0.05]:
					b.ellipsoid(Vector3(0.03, 0.11, 0.02) * sc, MeshKit.at(off + Vector3(float(ex) * sc, 0.48 * sc, 0.1 * sc)), fur, 6)
					b.sphere(0.018 * sc, MeshKit.at(off + Vector3(float(ex) * sc, 0.35 * sc, 0.23 * sc)), Color(0.1, 0.1, 0.12), 6)
				b.sphere(0.02 * sc, MeshKit.at(off + Vector3(0.0, 0.3 * sc, 0.24 * sc)), Color(1.0, 0.55, 0.6), 6)
				b.sphere(0.05 * sc, MeshKit.at(off + Vector3(0.0, 0.16 * sc, -0.2 * sc)), Color.WHITE, 6)
		"toadstool":
			for k in 1 + mini(stage, 2):
				var sc := s * (1.0 - 0.25 * float(k))
				var off := Vector3(0.25 * float(k) * (1.0 if k % 2 == 1 else -1.0), 0.0, 0.1 * float(k))
				b.cylinder(0.06 * sc, 0.08 * sc, 0.3 * sc, MeshKit.at(off + Vector3(0.0, 0.15 * sc, 0.0)), Color(0.97, 0.94, 0.86), 8)
				b.dome(0.22 * sc, MeshKit.at(off + Vector3(0.0, 0.28 * sc, 0.0)), gold.call(Color(0.9, 0.2, 0.2)), 12)
				for p in 4:
					var a := TAU * float(p) / 4.0 + 0.4
					b.sphere(0.035 * sc, MeshKit.at(off + Vector3(cos(a) * 0.13 * sc, 0.4 * sc, sin(a) * 0.13 * sc)), Color.WHITE, 6)
		"duckling":
			for k in 1 + mini(stage, 3):
				var sc := s * (1.0 if k == 0 else 0.7)
				var off := Vector3(0.0, 0.0, -0.3 * float(k))  # in a row behind mum
				var y: Color = gold.call(Color(1.0, 0.88, 0.3))
				b.ellipsoid(Vector3(0.13, 0.11, 0.17) * sc, MeshKit.at(off + Vector3(0.0, 0.11 * sc, 0.0)), y, 10)
				b.sphere(0.09 * sc, MeshKit.at(off + Vector3(0.0, 0.27 * sc, 0.1 * sc)), y, 10)
				b.ellipsoid(Vector3(0.04, 0.015, 0.05) * sc, MeshKit.at(off + Vector3(0.0, 0.25 * sc, 0.2 * sc)), Color(1.0, 0.55, 0.15), 6)
				for ex in [-0.04, 0.04]:
					b.sphere(0.015 * sc, MeshKit.at(off + Vector3(float(ex) * sc, 0.3 * sc, 0.17 * sc)), Color(0.1, 0.1, 0.12), 6)
