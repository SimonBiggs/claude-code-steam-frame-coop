extends Node3D
## PARTY BOARD: the season on every board (deep.gd SEASONS, Seeded.season on the host; sent in the "deep" state).
## Every machine dresses the island the same: big seasonal things (core/season_kit.gd props: tulips, sunflowers, a
## pumpkin, a snowman) on the beach between Mango's festival pieces and the lanterns, and the season's petals / pollen /
## leaves / snow drifting gently over the island. Under main.stage (board units: the same on the TV and the VR table).
## One merged mesh + one particle node: cheap on the Frame and the Decks.
##   set_season(name)

const MeshKit := preload("res://core/mesh_kit.gd")
const SeasonKit := preload("res://core/season_kit.gd")
const BD := preload("res://games/party_board/board_data.gd")
const Deep := preload("res://games/party_board/deep.gd")

## Beach spots: angle round the island (degrees, 0 = south / START) - clear of the festival pieces, the lanterns,
## the trophy wall / party hall and START's bunting.
const ANGLES: Array[float] = [36.0, 132.0, 224.0, 324.0]
const R := 12.45
const SIZE := 1.5
const DRIFT_BOX := Vector3(11.0, 0.5, 11.0)
const DRIFT_Y := 6.0

var season := ""
var props: MeshInstance3D
var drift: CPUParticles3D


static func spots() -> Array:
	var out: Array = []
	for a in ANGLES:
		var r := deg_to_rad(a)
		var x := sin(r) * R
		var z := cos(r) * R
		out.append(Vector3(x, maxf(BD.height(x, z), 0.1), z))
	return out


func set_season(s: String) -> void:
	if s == season or not Deep.SEASONS.has(s):
		return
	season = s
	for n in [props, drift]:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	var b := MeshKit.Builder.new()
	var sp := spots()
	for i in sp.size():
		var p: Vector3 = sp[i]
		SeasonKit.prop(b, s, p, i, SIZE, Vector3(-p.x, 0.0, -p.z).normalized())  # facing the island
	props = MeshKit.instance(b.build(), false)
	props.name = "SeasonProps"
	add_child(props)
	drift = SeasonKit.drift(Deep.season_data(s).drift, s, {"box": DRIFT_BOX, "at": Vector3(0.0, DRIFT_Y, 0.0), "amount": 40,
		"size": 0.3, "speed": Vector2(0.6, 1.2), "lifetime": 9.0})
	drift.local_coords = true  # (under the scaled stage: tiny on the VR table, big on the TV; the billboarded leaves
	((drift.mesh as QuadMesh).material as StandardMaterial3D).billboard_keep_scale = true  # keep the stage's scale too)
	add_child(drift)
	print("Party Board: %s island" % s)
