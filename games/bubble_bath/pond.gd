extends Node3D
## MAMA'S POND and the seasonal bathroom (deep.gd POND / SEASONS):
##   set_pieces(n, pop)  every POND_EVERY goals the little pond behind the far rim (right of Mama Duck, seen over the
##                       tub from the TV cameras and the splasher) gets a new piece for good - LILY PADS, a FROG, a DUCK
##                       HOUSE, a FOUNTAIN, a SAILBOAT, a LIGHTHOUSE, BUTTERFLIES and a RAINBOW. Every machine builds the
##                       same from the piece count (the "pond" state); the newest piece pops in. The pond's water is
##                       there from the start (an empty pond waiting to be filled).
##   set_season(s)       SeasonKit props on the bathroom floor round the tub (clear of the bath mat and the pond) and
##                       the season's drift (blossom / summer fluff / leaves / snow) coming in through the open window.
## One merged mesh each, one CPUParticles3D: cheap on the Frame.

const MeshKit := preload("res://core/mesh_kit.gd")
const SeasonKit := preload("res://core/season_kit.gd")  # (the props and the drift: shared with the other seasonal games)
const Deep := preload("res://games/bubble_bath/deep.gd")

const POND_WATER := Color(0.25, 0.62, 0.85)
const BANK := Color(0.45, 0.72, 0.4)
## Season props on the floor: round the tub's sides and far end (the bath mat is at the near end, the pond far right).
const SPOTS: Array[Vector3] = [Vector3(-6.2, 0, -3.6), Vector3(-6.6, 0, -0.6), Vector3(-6.2, 0, 2.4), Vector3(6.4, 0, 2.6),
	Vector3(6.6, 0, -0.4), Vector3(-2.6, 0, -5.4), Vector3(6.2, 0, -4.4)]

var main
var count := -1
var water: MeshInstance3D
var body: MeshInstance3D
var season := ""
var props: MeshInstance3D
var drift: CPUParticles3D


func _ready() -> void:
	name = "Pond"
	var b := MeshKit.Builder.new()
	var h := Deep.POND_HALF
	b.cylinder(1.0, 1.0, 0.08, MeshKit.at(Deep.POND_AT + Vector3(0, 0.04, 0), Vector3(h.x + 0.35, 1.0, h.y + 0.35)), BANK, 28)
	b.cylinder(1.0, 1.0, 0.04, MeshKit.at(Deep.POND_AT + Vector3(0, 0.09, 0), Vector3(h.x, 1.0, h.y)), POND_WATER, 28)
	water = MeshKit.instance(b.build(), false)
	water.name = "PondWater"
	add_child(water)


func set_pieces(n: int, pop: bool = false) -> void:
	n = clampi(n, 0, Deep.POND.size())
	if n == count:
		return
	var grew := count >= 0 and n > count
	count = n
	if body != null and is_instance_valid(body):
		body.queue_free()
	body = null
	if n == 0:
		return
	var b := MeshKit.Builder.new()
	for i in n:
		_piece(b, Deep.POND[i], Deep.pond_spot(i))
	body = MeshKit.instance(b.build(), false)
	body.name = "PondPieces"
	add_child(body)
	if grew and pop:
		var at := Deep.pond_spot(n - 1)
		main.burst(at + Vector3(0, 0.8, 0), Color(1.0, 0.85, 0.3), 26, 3.5)
		main.sfx.play_at("sparkle", at, -2.0, 1.0)


## One pond piece at `at` (on the floor / the water), facing the tub (+Z).
func _piece(b: MeshKit.Builder, kind: String, at: Vector3) -> void:
	var y := 0.11 if Deep.POND_IN.has(kind) else 0.08
	var p := at + Vector3(0, y, 0)
	match kind:
		"lily":  # three lily pads, one with a pink flower
			var green := Color(0.3, 0.75, 0.35)
			for k in 3:
				var o := Vector3([0.0, 0.32, -0.25][k], 0.0, [0.0, 0.18, 0.22][k])
				b.cylinder(0.2, 0.2, 0.02, MeshKit.at(p + o), green, 14)
			b.sphere(0.08, MeshKit.at(p + Vector3(0, 0.06, 0), Vector3(1, 0.7, 1)), Color(1.0, 0.6, 0.8), 8)
		"frog":  # a green frog on a stone
			b.sphere(0.22, MeshKit.at(p + Vector3(0, 0.1, 0), Vector3(1.3, 0.6, 1.1)), Color(0.6, 0.6, 0.65), 10)
			b.ellipsoid(Vector3(0.18, 0.13, 0.16), MeshKit.at(p + Vector3(0, 0.3, 0)), Color(0.35, 0.8, 0.3), 10)
			for s in [-1.0, 1.0]:
				b.sphere(0.06, MeshKit.at(p + Vector3(0.09 * s, 0.42, 0.06)), Color.WHITE, 8)
				b.sphere(0.03, MeshKit.at(p + Vector3(0.09 * s, 0.43, 0.11)), Color(0.1, 0.1, 0.1), 6)
		"house":  # a little duck house on the bank
			b.box(Vector3(0.6, 0.45, 0.5), MeshKit.at(p + Vector3(0, 0.23, 0)), Color(0.95, 0.6, 0.3))
			b.cone(0.5, 0.35, MeshKit.at(p + Vector3(0, 0.62, 0), Vector3(1.0, 1.0, 0.85)), Color(0.85, 0.25, 0.25), 4)
			b.cylinder(0.12, 0.12, 0.02, MeshKit.at(p + Vector3(0, 0.22, 0.26), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.2, 0.12, 0.08), 12)
		"fountain":  # a stone fountain with a blue spout
			b.cylinder(0.32, 0.36, 0.18, MeshKit.at(p + Vector3(0, 0.09, 0)), Color(0.85, 0.85, 0.9), 16)
			b.cylinder(0.06, 0.06, 0.4, MeshKit.at(p + Vector3(0, 0.38, 0)), Color(0.85, 0.85, 0.9), 8)
			b.sphere(0.13, MeshKit.at(p + Vector3(0, 0.62, 0), Vector3(1, 1.4, 1)), Color(0.55, 0.85, 1.0), 10)
		"boat":  # a little sailboat
			b.ellipsoid(Vector3(0.22, 0.08, 0.36), MeshKit.at(p + Vector3(0, 0.05, 0)), Color(0.95, 0.35, 0.3), 10)
			b.cylinder(0.015, 0.015, 0.5, MeshKit.at(p + Vector3(0, 0.33, 0)), Color(0.5, 0.35, 0.2), 6)
			b.cone(0.18, 0.4, MeshKit.at(p + Vector3(0, 0.36, -0.05), Vector3(0.15, 1.0, 1.0)), Color.WHITE, 3)
		"lighthouse":  # a striped lighthouse on the bank
			for k in 4:
				b.cylinder(0.2 - k * 0.025, 0.22 - k * 0.025, 0.25, MeshKit.at(p + Vector3(0, 0.125 + k * 0.25, 0)),
					Color(0.95, 0.25, 0.25) if k % 2 == 0 else Color.WHITE, 12)
			b.sphere(0.13, MeshKit.at(p + Vector3(0, 1.1, 0)), Color(1.0, 0.92, 0.4), 10)
			b.cone(0.17, 0.18, MeshKit.at(p + Vector3(0, 1.27, 0)), Color(0.85, 0.25, 0.25), 10)
		"butterfly":  # two butterflies over a flower patch
			for k in 3:
				b.sphere(0.07, MeshKit.at(p + Vector3((k - 1) * 0.18, 0.08, 0.05 * k)), [Color(1.0, 0.85, 0.2), Color(0.95, 0.5, 0.9), Color(1.0, 1.0, 1.0)][k], 8)
			for k in 2:
				var c := p + Vector3(-0.15 + k * 0.35, 0.55 + k * 0.15, 0)
				var col := Color(0.55, 0.6, 1.0) if k == 0 else Color(1.0, 0.6, 0.3)
				b.ellipsoid(Vector3(0.12, 0.02, 0.09), MeshKit.at(c + Vector3(-0.1, 0, 0), Vector3.ONE, Vector3(0, 0, 0.5)), col, 8)
				b.ellipsoid(Vector3(0.12, 0.02, 0.09), MeshKit.at(c + Vector3(0.1, 0, 0), Vector3.ONE, Vector3(0, 0, -0.5)), col, 8)
		"rainbow":  # a rainbow arching over the back of the pond
			var cols := [Color(0.95, 0.3, 0.3), Color(1.0, 0.65, 0.2), Color(1.0, 0.92, 0.3), Color(0.4, 0.85, 0.4), Color(0.4, 0.6, 1.0)]
			for k in cols.size():
				b.torus(1.5 - k * 0.1, 0.05, MeshKit.at(p, Vector3(1.0, 1.0, 1.0), Vector3(PI * 0.5, 0, 0)), cols[k], 32, 4)


func set_season(s: String) -> void:
	if s == season or not Deep.SEASONS.has(s):
		return
	season = s
	for n in [props, drift]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	var sd := Deep.season_data(s)
	var b := MeshKit.Builder.new()
	for i in SPOTS.size():
		var p: Vector3 = SPOTS[i]
		SeasonKit.prop(b, s, p, i, 1.3, -Vector3(p.x, 0.0, p.z).normalized())  # facing the tub
	props = MeshKit.instance(b.build(), false)
	props.name = "SeasonProps"
	add_child(props)
	drift = SeasonKit.drift(sd.drift, s, {"amount": 70 if s == "winter" else 50, "lifetime": 8.0, "box": Vector3(7.0, 0.5, 5.0),
		"at": Vector3(0.0, 6.5, -1.0), "size": 0.1, "speed": Vector2(0.5, 1.0)})
	add_child(drift)
	print("Bubble Bath: %s bathroom" % s)