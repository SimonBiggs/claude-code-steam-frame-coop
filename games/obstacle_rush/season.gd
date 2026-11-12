extends Node3D
## OBSTACLE RUSH: the seasonal course (deep.gd SEASONS, Seeded.season on the host; sent in the "deep" state). Every
## machine dresses the garden the same: big seasonal things (core/season_kit.gd props: tulips, sunflowers, a pumpkin, a
## snowman) on the lawn round the picnic table (seen past the course from the runners' views and beyond the table by
## the VR giant, never on the course), and the season's petals / pollen / leaves / snow drifting gently over the table
## (one particle node). One merged mesh: cheap on the Frame and the Decks.
##   set_season(name)

const MeshKit := preload("res://core/mesh_kit.gd")
const SeasonKit := preload("res://core/season_kit.gd")
const Deep := preload("res://games/obstacle_rush/deep.gd")

const LAWN_Y := -11.5  # (main.gd: the lawn under the table, giant.gd TABLE_Y - 0.8 * S)
## Where the props stand (x, z) on the lawn: past the table's ends (|x| > 23) and beyond its far side (z < -11),
## clear of the giant's walk (z 5..10 along the near side) and inside the trees (main.gd scatters them 60 m out).
const SPOTS: Array[Vector2] = [Vector2(-27.0, -3.0), Vector2(27.0, -3.0), Vector2(-27.0, 5.0), Vector2(27.0, 5.0),
	Vector2(-13.0, -14.0), Vector2(13.0, -14.0), Vector2(0.0, -16.0), Vector2(-26.0, -12.0), Vector2(26.0, -12.0)]
const SIZE := 7.0

var season := ""
var props: MeshInstance3D
var drift: CPUParticles3D


func set_season(s: String) -> void:
	if s == season or not Deep.SEASONS.has(s):
		return
	season = s
	for n in [props, drift]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	var b := MeshKit.Builder.new()
	for i in SPOTS.size():
		var p: Vector2 = SPOTS[i]
		SeasonKit.prop(b, s, Vector3(p.x, LAWN_Y, p.y), i, SIZE, Vector3(-p.x, 0.0, -p.y).normalized())  # facing the table
	props = MeshKit.instance(b.build(), false)
	props.name = "SeasonProps"
	add_child(props)
	drift = SeasonKit.drift(Deep.season_data(s).drift, s, {"box": Vector3(20.0, 0.5, 7.0), "at": Vector3(0.0, 8.0, -1.0),
		"amount": 70, "size": 0.16})
	add_child(drift)
	print("Obstacle Rush: %s course" % s)
