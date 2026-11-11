extends Node3D
## RHYTHM BAND seasonal stage (deep.gd SEASONS, Seeded.season on the host; synced in the snapshot): every machine
## dresses the concert the same - spring tulips, summer sunflowers, autumn pumpkins, winter snowmen (core/season_kit.gd)
## - with blossom / leaves / snow drifting down over the crowd field (never on the stage in the drummer's face) and
## the props on the grass either side of the stage front, clear of the crowd, the festival and the TV views.
## One merged mesh + one CPUParticles3D: cheap on the Frame.
##   set_season(name)

const MeshKit := preload("res://core/mesh_kit.gd")
const SeasonKit := preload("res://core/season_kit.gd")
const Deep := preload("res://games/rhythm_band/deep.gd")

## Props: on the grass left and right of the stage front.
const SPOTS: Array[Vector3] = [Vector3(-5.6, 0, -3.2), Vector3(5.6, 0, -3.2), Vector3(-6.0, 0, -6.8), Vector3(6.0, 0, -6.8),
	Vector3(-9.0, 0, -2.6), Vector3(9.0, 0, -2.6)]
const SIZE := 1.5

var main
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
		SeasonKit.prop(b, s, SPOTS[i], i, SIZE, Vector3.FORWARD)  # (facing the crowd and the TV cameras: -Z)
	props = MeshKit.instance(b.build(), false)
	props.name = "SeasonProps"
	add_child(props)
	drift = SeasonKit.drift(Deep.season_data(s).drift, s, {"box": Vector3(12.0, 0.5, 5.0), "at": Vector3(0.0, 8.0, -9.0), "amount": 80})
	add_child(drift)
	print("Rhythm Band: %s stage" % s)
