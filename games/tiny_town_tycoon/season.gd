extends Node3D
## TINY TOWN TYCOON: Benny's islands by season (deep.gd SEASONS, Seeded.season on the host; sent in the "deep" state).
## Every machine dresses the garden the same: big seasonal things (core/season_kit.gd props: tulips, sunflowers, a
## pumpkin, a snowman) on the lawn round the garden table (behind the island from the TV views, outside where the VR
## mayor can walk), and the season's petals / pollen / leaves / snow drifting gently down over the toy town (one
## particle node, toy-sized). One merged mesh: cheap on the Frame and the Decks.
##   set_season(name)

const MeshKit := preload("res://core/mesh_kit.gd")
const SeasonKit := preload("res://core/season_kit.gd")
const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const Deep := preload("res://games/tiny_town_tycoon/deep.gd")

## Where the props stand: angles round the table (radians from +X towards +Z; the mayor stands at +Z), RING metres
## out: past the VR mayor's walking square (main.gd vr_rig.bounds, 1.8 m) and the garden chairs (1.25 m).
const ANGLES: Array[float] = [-PI * 0.5, -PI * 0.5 - 0.7, -PI * 0.5 + 0.7, PI - 0.25, 0.25, -PI * 0.5 - 1.3, -PI * 0.5 + 1.3]
const RING := 2.7
const SIZE := 0.75

var season := ""
var props: MeshInstance3D
var drift: CPUParticles3D


static func spots() -> Array:
	var out: Array = []
	for a in ANGLES:
		out.append(Vector3(cos(a) * RING, 0.0, sin(a) * RING))
	return out


func set_season(s: String) -> void:
	if s == season or not Deep.SEASONS.has(s):
		return
	season = s
	for n in [props, drift]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	var b := MeshKit.Builder.new()
	var sp := spots()
	for i in sp.size():
		var p: Vector3 = sp[i]
		SeasonKit.prop(b, s, p, i, SIZE, (-p).normalized())  # facing the table
	props = MeshKit.instance(b.build(), false)
	props.name = "SeasonProps"
	add_child(props)
	drift = SeasonKit.drift(Deep.season_data(s).drift, s, {"box": Vector3(0.75, 0.05, 0.75), "at": Vector3(0.0, Defs.GROUND_Y + 0.55, 0.0),
		"amount": 40, "size": 0.012, "speed": Vector2(0.02, 0.05), "lifetime": 9.0, "dir": Vector3(0.2, -1.0, 0.0)})
	drift.gravity = Vector3(0.0, -0.01, 0.0)  # (a toy town: petals drift down slowly, not a metre a second)
	add_child(drift)
	print("Tiny Town Tycoon: %s island" % s)
