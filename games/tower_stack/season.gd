extends Node3D
## SEASONS (Tower Stack, third pass): the park dresses for the season (core/season_kit.gd props round the walk edge
## and the season's drift: blossom, butterflies of light, leaves, snow), the grass follows it (winter is snowy, autumn
## golden, spring meadow green, summer the job's own meadow or beach) and Rolo's rolling ball changes with it
## (rollers.gd BALLS). The host picks it (Seeded.season(), or ARCADE_SEASON / ARCADE_SEASON_TOWER_STACK in tests and
## What's New "try") and shares it as the "season" state, so every machine dresses the same.
##   Season.pick() -> season    Season.ground(season, job_ground) -> towergen ground    node.dress(season)

const G := preload("res://games/tower_stack/towergen.gd")
const Seeded := preload("res://core/seeded.gd")
const SeasonKit := preload("res://core/season_kit.gd")
const MeshKit := preload("res://core/mesh_kit.gd")

const DRIFT := {"spring": Color(1.0, 0.75, 0.85), "summer": Color(1.0, 0.95, 0.6), "autumn": Color(0.95, 0.5, 0.15), "winter": Color(1, 1, 1)}
const LINES := {"spring": "Spring!", "summer": "Summer!", "autumn": "Autumn!", "winter": "Winter!"}
const PICS := {"spring": "sapling", "summer": "sun", "autumn": "pumpkin", "winter": "snowman"}
## Prop spots just outside the walk edge, mostly at the back where the TV camera and the giant look (in front of the
## town rows), clear of the village green.
const SPOTS: Array[float] = [-0.3, -0.85, -1.9, -2.95, 0.4]  # radians (x = cos, z = sin)
const SPOT_R := 9.6

var season := ""
var _node: Node3D


static func pick() -> String:
	return SeasonKit.override(G.GAME_ID, Seeded.season(), SeasonKit.SEASONS)


## The grass the park shows in this season (the job's own ground in summer: meadow or beach).
static func ground(s: String, job_ground: String) -> String:
	match s:
		"winter":
			return "snow"
		"autumn":
			return "autumn"
		"spring":
			return "meadow"
	return job_ground if job_ground == "beach" else "meadow"


func _ready() -> void:
	name = "Season"


## Every machine: dress the park for season s (again only when it changes).
func dress(s: String) -> void:
	if s == season or not SeasonKit.SEASONS.has(s):
		return
	season = s
	if _node != null:
		_node.queue_free()
	_node = Node3D.new()
	add_child(_node)
	var b := MeshKit.Builder.new()
	for i in SPOTS.size():
		var a: float = SPOTS[i]
		var at := Vector3(cos(a), 0.0, sin(a)) * SPOT_R
		SeasonKit.prop(b, s, at, i, 1.2, -at.normalized())
	_node.add_child(MeshKit.instance(b.build(), false))
	_node.add_child(SeasonKit.drift(DRIFT[s], s, {"box": Vector3(10.0, 0.5, 8.0), "at": Vector3(0.0, 7.0, -1.0), "amount": 50 if s == "summer" else 80}))
