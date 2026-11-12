extends Node3D
## ELEMENTAL BENDER: the season on every island (deep.gd SEASONS; the host picks it with Deep.season() and sends it
## in the sticky "temple" event, so every machine dresses the same). The shared core/season_kit.gd props (a tub of
## tulips, sunflowers, a pumpkin on leaves, a snowman) stand round the beach rim (Deep.season_spots: outside every
## portal and every raider's walk; decoration only, no collision), facing the temple, and the season's petals /
## pollen / leaves / snow drift over the island. One merged mesh + one particle node (cheap on the Frame and Decks).
##   dress(season, island layout)

const MeshKit := preload("res://core/mesh_kit.gd")
const SeasonKit := preload("res://core/season_kit.gd")
const Deep := preload("res://games/elemental_bender/deep.gd")

const SIZE := 1.6

var season := ""
var key := ""


func dress(s: String, lay: Dictionary) -> void:
	var k := "%s|%s|%d" % [s, String(lay.get("id", "")), int(lay.get("seed", 0))]
	if k == key or not Deep.SEASONS.has(s):
		return
	key = k
	season = s
	for c in get_children():
		c.queue_free()
	var b := MeshKit.Builder.new()
	var sp := Deep.season_spots(lay)
	for i in sp.size():
		var p: Vector3 = sp[i]
		SeasonKit.prop(b, s, p, i, SIZE, Vector3(-p.x, 0.0, -p.z).normalized())
	var props := MeshKit.instance(b.build(), false)
	props.name = "SeasonProps"
	add_child(props)
	var drift := SeasonKit.drift(Deep.season_data(s).drift, s, {"box": Vector3(26.0, 0.5, 26.0), "at": Vector3(0.0, 12.0, 0.0),
		"amount": 70, "size": 0.32, "speed": Vector2(0.8, 1.6), "lifetime": 10.0})
	add_child(drift)
	print("Elemental Bender: %s on %s" % [s, String(lay.get("id", "?"))])
