extends Node3D
## SOFT DODGEBALL: TumTum's seasonal park (deep.gd SEASONS, Seeded.season on the host; sent in the "deep" state).
## Every machine dresses the park the same: big seasonal things (core/season_kit.gd props: tulips, sunflowers, a
## pumpkin, a snowman) on the lawn behind and beside the stage (seen past TumTum from the TV views, never on the
## court), and the season's petals / pollen / leaves / snow drifting gently over the park (one particle node).
## One merged mesh: cheap on the Frame and the Decks.
##   set_season(name)

const MeshKit := preload("res://core/mesh_kit.gd")
const SeasonKit := preload("res://core/season_kit.gd")
const Deep := preload("res://games/dodge_ball/deep.gd")

## Where the props stand (x, z) and how big they are: behind the stage (z < -9.2) and beside it (|x| > 4), inside
## the ring of trees (world.gd: 11.4 m and more from (0, -1)).
const SPOTS: Array[Vector2] = [Vector2(-5.0, -9.9), Vector2(5.0, -9.9), Vector2(-7.2, -8.6), Vector2(7.2, -8.6),
	Vector2(-2.2, -10.9), Vector2(2.2, -10.9)]
const SIZE := 1.7

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
		SeasonKit.prop(b, s, Vector3(p.x, 0.0, p.y), i, SIZE, Vector3(-p.x, 0.0, 6.0 - p.y).normalized())  # facing the court
	props = MeshKit.instance(b.build(), false)
	props.name = "SeasonProps"
	add_child(props)
	drift = SeasonKit.drift(Deep.season_data(s).drift, s, {"box": Vector3(10.0, 0.5, 8.0), "at": Vector3(0.0, 7.0, 0.5),
		"amount": 50, "size": 0.12})
	add_child(drift)
	print("Soft Dodgeball: %s park" % s)
