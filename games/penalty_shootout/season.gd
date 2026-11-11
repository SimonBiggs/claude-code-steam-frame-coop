extends Node3D
## PENALTY SHOOTOUT seasonal pitch (deep.gd SEASONS, Seeded.season on the host; synced in the snapshot): every machine
## dresses the stadium the same - spring blossom, summer sunflowers, autumn leaves and pumpkins, winter snow and
## snowmen (core/season_kit.gd) - with things drifting down over the far pitch and the stands (never in front of the keeper's face: they
## stay beyond the penalty spot) and a few seasonal props along the touchlines and right of the goal, well clear of
## every kick's path and of Leo's corner on the left. One merged mesh + one CPUParticles3D: cheap on the Frame.
##   set_season(name)

const CoreMeshKit := preload("res://core/mesh_kit.gd")
const SeasonKit := preload("res://core/season_kit.gd")  # (the props and the drift: shared with the other seasonal games)
const Deep := preload("res://games/penalty_shootout/deep.gd")

## Props: right of the goal (behind the line) and along both touchlines towards the strikers.
const SPOTS: Array[Vector3] = [Vector3(8.0, 0, -1.5), Vector3(9.6, 0, -0.6), Vector3(11.2, 0, -1.8), Vector3(12.8, 0, -0.8),
	Vector3(-17.0, 0, 14.0), Vector3(17.0, 0, 15.0), Vector3(-18.0, 0, 22.0), Vector3(18.0, 0, 24.0)]

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
	var sd := Deep.season_data(s)
	var b := CoreMeshKit.Builder.new()
	for i in SPOTS.size():
		SeasonKit.prop(b, s, SPOTS[i], i, 1.6)
	props = CoreMeshKit.instance(b.build(), false)
	props.name = "SeasonProps"
	add_child(props)
	# from z 14 to 46: beyond the spot, over the far pitch and the stands
	drift = SeasonKit.drift(sd.drift, s, {"amount": 90, "lifetime": 9.0, "box": Vector3(30.0, 0.5, 16.0), "at": Vector3(0.0, 14.0, 30.0),
		"size": 0.18, "speed": Vector2(1.0, 2.0)})
	add_child(drift)
	print("Penalty Shootout: %s pitch" % s)
