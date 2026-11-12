extends Node3D
## FRUIT CATCH seasonal orchard (deep.gd SEASONS, Seeded.season on the host; sent in the "deep" state): every machine
## dresses the park the same - spring blossom, summer sunflowers, autumn leaves and pumpkins, and in winter Nutmeg's
## MAGIC SNOW GLOBE: snow drifts down and snowmen stand round the park (core/season_kit.gd) - with a few seasonal props
## just outside the park on the left and behind the giant (clear of the orchard behind the big tree and Nutmeg's
## pantry on the right). The drift falls from high above the tree over the whole park. One merged mesh + one
## CPUParticles3D: cheap on the Frame.
##   set_season(name)

const MeshKit := preload("res://core/mesh_kit.gd")
const SeasonKit := preload("res://core/season_kit.gd")  # (the props and the drift: shared with the other seasonal games)
const Deep := preload("res://games/fruit_catch/deep.gd")

## Props: left of the park and behind the giant (z > 0), all just outside the park's edge (radius 8.5).
const SPOTS: Array[Vector3] = [Vector3(-9.6, 0, -1.0), Vector3(-9.9, 0, 1.6), Vector3(-9.2, 0, 4.2), Vector3(-7.4, 0, 6.6),
	Vector3(-4.6, 0, 8.6), Vector3(-1.6, 0, 9.5), Vector3(2.4, 0, 9.4), Vector3(5.4, 0, 8.0)]

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
	var b := MeshKit.Builder.new()
	for i in SPOTS.size():
		var p: Vector3 = SPOTS[i]
		SeasonKit.prop(b, s, p, i, 1.5, -Vector3(p.x, 0.0, p.z).normalized())  # facing the park
	props = MeshKit.instance(b.build(), false)
	props.name = "SeasonProps"
	add_child(props)
	drift = SeasonKit.drift(sd.drift, s, {"amount": 110 if s == "winter" else 80, "lifetime": 9.0, "box": Vector3(11.0, 0.5, 11.0),
		"at": Vector3(0.0, 9.5, 0.0), "size": 0.15, "speed": Vector2(0.7, 1.3)})
	add_child(drift)
	print("Fruit Catch: %s orchard" % s)
