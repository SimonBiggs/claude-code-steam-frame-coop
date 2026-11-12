extends Node3D
## COASTER CREW seasonal park (deep.gd SEASONS, Seeded.season on the host; "season" in the state store): every machine
## dresses the table the same - spring tulips, summer sunflowers, autumn pumpkins, winter snowmen (core/season_kit.gd)
## round the table's rim, the grass tinted for the season (a thin mat over the table top) and blossom / leaves / snow
## drifting down over the park. One merged mesh, one mat, one CPUParticles3D: cheap on the Frame. A child of the park.
##   set_season(name)

const MeshKit := preload("res://core/mesh_kit.gd")
const SeasonKit := preload("res://core/season_kit.gd")
const Track := preload("res://games/roller_coaster/track.gd")
const Deep := preload("res://games/roller_coaster/deep.gd")

## Props: on the table's rim between the trees, clear of the station and Buttons' corner (+Z, the builder's side).
const SPOTS: Array[Vector3] = [Vector3(11.2, 0, -1.6), Vector3(-11.3, 0, 1.2), Vector3(7.0, 0, -8.8), Vector3(-6.0, 0, -9.9),
	Vector3(0.6, 0, -11.3), Vector3(11.0, 0, 3.6)]
const SIZE := 1.1

var season := ""
var props: MeshInstance3D
var mat: MeshInstance3D
var drift: CPUParticles3D


func set_season(s: String) -> void:
	if s == season or not Deep.SEASONS.has(s):
		return
	season = s
	for n in [props, mat, drift]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	var b := MeshKit.Builder.new()
	for i in SPOTS.size():
		SeasonKit.prop(b, s, SPOTS[i], i, SIZE, -SPOTS[i].normalized())  # (facing the middle of the table)
	props = MeshKit.instance(b.build(), false)
	props.name = "SeasonProps"
	add_child(props)
	var g: Color = Deep.season_data(s).grass
	if g != Track.PARK_GRASS:
		var mb := MeshKit.Builder.new()
		mb.cylinder(Track.TABLE_R - 0.02, Track.TABLE_R - 0.02, 0.01, Transform3D(Basis(), Vector3(0, 0.004, 0)), g, 40)
		mat = MeshKit.instance(mb.build(), false)
		mat.name = "SeasonGrass"
		add_child(mat)
	drift = SeasonKit.drift(Deep.season_data(s).drift, s, {"box": Vector3(11.0, 0.5, 11.0), "at": Vector3(0.0, 11.0, 0.0), "amount": 70, "size": 0.3})
	add_child(drift)
	print("Coaster Crew: %s park" % s)
