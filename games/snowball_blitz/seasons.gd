extends Node3D
## SNOWBALL BLITZ seasons (third pass): it always snows on Bobo's hill, but the square dresses for the real season
## (Seeded.season on the host, ARCADE_SEASON / ARCADE_SEASON_SNOWBALL_BLITZ in tests through core/season_kit.gd; the
## host shares it in net state "season", so every machine dresses the same):
##   spring  tubs of tulips round the square, pink blossom drifting with the snow, snowmen in flower-pink hats
##   summer  tall sunflowers, golden pollen, snowmen in straw sun hats (wide brims)
##   autumn  pumpkins on leaves, orange leaves drifting, snowmen in pumpkin-orange hats
##   winter  the square as it always was (the snowmen's black top hats); no extra props (a SeasonKit snowman prop
##           would look like one of the snowmen marching in)
## Props stand in a ring outside the arena (past the lamps, inside the picket fence gaps), one merged mesh.
##   set_season(name)          # every machine

const MeshKit := preload("res://core/mesh_kit.gd")
const SeasonKit := preload("res://core/season_kit.gd")

const SEASONS: Array[String] = ["spring", "summer", "autumn", "winter"]
const PICS := {"spring": "daisy", "summer": "sun", "autumn": "pumpkin", "winter": "snowflake"}
const LINES := {"spring": "Spring snow!", "summer": "Summer snow!", "autumn": "Autumn snow!", "winter": "Winter!"}
const CARD_COLORS := {"spring": Color(1.0, 0.55, 0.75), "summer": Color(1.0, 0.8, 0.2), "autumn": Color(0.95, 0.5, 0.15),
	"winter": Color(0.55, 0.8, 1.0)}
## The snowmen's hats (main.mat "hat").
const HATS := {"spring": Color(0.92, 0.35, 0.6), "summer": Color(0.9, 0.75, 0.35), "autumn": Color(0.9, 0.42, 0.1),
	"winter": Color(0.12, 0.1, 0.14)}
const BRIM := {"summer": 1.7}  # brim width times the top hat's
const DRIFT := {"spring": Color(1.0, 0.7, 0.85), "summer": Color(1.0, 0.85, 0.3), "autumn": Color(0.9, 0.45, 0.12)}
const PROP_R := 22.3  # between the lamps (21.4) and the picket fence (23.2)
const PROP_N := 10
const PROP_SIZE := 1.3
const TREE_GAP := 0.35  # radians kept clear round the big tree straight ahead (-Z)

var season := ""
var props: MeshInstance3D
var drift: CPUParticles3D


static func hat(s: String) -> Color:
	return HATS.get(s, HATS["winter"])


## Where the props stand: evenly round the square, skipping the big tree straight ahead.
static func spots() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in PROP_N:
		var a := -PI / 2.0 + TREE_GAP + (TAU - 2.0 * TREE_GAP) * (float(i) + 0.5) / float(PROP_N)
		out.append(Vector3(cos(a), 0.0, sin(a)) * PROP_R)
	return out


func set_season(s: String) -> void:
	if s == season or not SEASONS.has(s):
		return
	season = s
	for n in [props, drift]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	props = null
	drift = null
	if s != "winter":
		var b := MeshKit.Builder.new()
		var sp := spots()
		for i in sp.size():
			SeasonKit.prop(b, s, sp[i], i, PROP_SIZE, -sp[i].normalized())  # facing the fort
		props = MeshKit.instance(b.build(), false)
		props.name = "SeasonProps"
		add_child(props)
		drift = SeasonKit.drift(DRIFT[s], s, {"box": Vector3(16.0, 0.5, 16.0), "at": Vector3(0.0, 9.0, 0.0),
			"amount": 70, "size": 0.16})
		add_child(drift)
	print("Snowball Blitz: %s square" % s)