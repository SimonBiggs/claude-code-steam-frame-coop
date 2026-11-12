extends Node3D
## PAINT AND GUESS: Smudge's seasonal studio (deep.gd SEASONS, Seeded.season on the host; sent in the "deep" state).
## Every machine dresses the studio the same: the view out of the window (spring blossom, summer green, autumn leaves,
## winter snow), big seasonal things (core/season_kit.gd props: tulips, sunflowers, a pumpkin, a snowman) in the two
## back corners beside the plants, and the season's petals / pollen / leaves / snow drifting gently down there (never
## over the easel: the guessers watch it). One merged mesh: cheap on the Frame and the Decks.
##   set_season(name)

const MeshKit := preload("res://core/mesh_kit.gd")
const SeasonKit := preload("res://core/season_kit.gd")
const Deep := preload("res://games/paint_and_guess/deep.gd")

## Where the props stand (on the floor): the back corners, beside the plants, seen past the easel.
const SPOTS: Array[Vector3] = [Vector3(-2.75, 0.0, -2.55), Vector3(2.75, 0.0, -2.55)]
const SIZE := 0.75
const WINDOW := Vector3(-4.13, 1.85, -0.6)  # (room.gd: the window on the left wall)

var season := ""
var props: MeshInstance3D
var drifts: Array = []


func set_season(s: String) -> void:
	if s == season or not Deep.SEASONS.has(s):
		return
	season = s
	if props != null and is_instance_valid(props):
		props.queue_free()
	for d in drifts:
		if is_instance_valid(d):
			(d as Node).queue_free()
	drifts.clear()
	var sd := Deep.season_data(s)
	var b := MeshKit.Builder.new()
	for i in SPOTS.size():
		var p: Vector3 = SPOTS[i]
		SeasonKit.prop(b, s, p, i, SIZE, Vector3(-p.x * 0.3, 0.0, 1.0).normalized())  # facing the artist
	# The window: the season's sky and ground just inside the glass, with a few seasonal blobs (trees / snow).
	var sky: Color = sd.sky
	var ground: Color = sd.ground
	b.box(Vector3(0.006, 0.7, 1.56), MeshKit.at(WINDOW + Vector3(0.012, 0.22, 0.0)), sky, true)
	b.box(Vector3(0.006, 0.42, 1.56), MeshKit.at(WINDOW + Vector3(0.014, -0.34, 0.0)), ground, true)
	for k in 4:
		var z := -0.55 + k * 0.37
		var col: Color = [Color(1.0, 0.75, 0.88), Color(0.3, 0.65, 0.3), Color(0.95, 0.55, 0.15), Color(0.97, 0.98, 1.0)][SeasonKit.SEASONS.find(s)]
		b.sphere(0.09 + 0.02 * (k % 2), MeshKit.at(WINDOW + Vector3(0.018, -0.12 + 0.04 * (k % 2), z), Vector3(0.2, 1.0, 1.0)), col, 8, true)
	props = MeshKit.instance(b.build(), false)
	props.name = "SeasonProps"
	add_child(props)
	for i in SPOTS.size():
		var d := SeasonKit.drift(sd.drift, s, {"box": Vector3(0.9, 0.2, 0.7), "at": SPOTS[i] + Vector3(0.0, 2.6, 0.2),
			"amount": 16, "size": 0.06, "speed": Vector2(0.15, 0.35), "lifetime": 7.0})
		add_child(d)
		drifts.append(d)
	print("Paint and Guess: %s studio" % s)
