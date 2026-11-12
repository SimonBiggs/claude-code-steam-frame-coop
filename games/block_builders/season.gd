extends Node3D
## BLOCK BUILDERS: the seasonal build site (deep.gd SEASONS, Seeded.season on the host; sent in the "deep" state).
## Every machine dresses the sky the same: big seasonal things (core/season_kit.gd props: tulips, sunflowers, a
## pumpkin, a snowman) on little floating rocks behind the course (past the friend's side island, in front of Puff's
## town; never on the course where runners walk), and the season's petals / pollen / leaves / snow drifting gently
## over the course (one particle node). One merged mesh: cheap on the Frame and the Decks.
##   set_season(name)

const MeshKit := preload("res://core/mesh_kit.gd")
const SeasonKit := preload("res://core/season_kit.gd")
const Deep := preload("res://games/block_builders/deep.gd")

## Where the rocks float (x, y of their top, z): behind the course and the friend's side island (z -7..-4).
const SPOTS: Array[Vector3] = [Vector3(-9.0, -0.5, -10.0), Vector3(0.0, 0.5, -10.5), Vector3(9.0, -0.5, -10.0)]
const SIZE := 1.6
const ROCK_TOP := Color(0.55, 0.78, 0.45)
const ROCK := Color(0.5, 0.42, 0.36)

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
		var p: Vector3 = SPOTS[i]
		b.cylinder(1.3, 1.3, 0.3, MeshKit.at(p + Vector3(0, -0.15, 0)), ROCK_TOP if s != "winter" else Color(0.93, 0.96, 1.0), 10)
		b.cone(1.25, 1.6, MeshKit.at(p + Vector3(0, -1.1, 0), Vector3.ONE, Vector3(PI, 0, 0)), ROCK, 10)
		SeasonKit.prop(b, s, p, i, SIZE, Vector3(-p.x * 0.1, 0.0, 1.0).normalized())  # facing the course and the builder
	props = MeshKit.instance(b.build(), false)
	props.name = "SeasonProps"
	add_child(props)
	drift = SeasonKit.drift(Deep.season_data(s).drift, s, {"box": Vector3(13.0, 0.5, 6.0), "at": Vector3(0.0, 9.0, -1.0),
		"amount": 70, "size": 0.18})
	add_child(drift)
	print("Block Builders: %s build site" % s)
