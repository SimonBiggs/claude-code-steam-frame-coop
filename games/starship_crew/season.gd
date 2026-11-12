extends Node3D
## STARSHIP CREW seasonal STAR SECTORS (deep.gd SEASONS, Seeded.season on the host; sent in the "deep" state): every
## machine dresses space the same - the spring NEBULA GARDEN (pink petals of space dust and tulip tubs), the summer SUN
## SECTOR (gold dust and sunflowers), the autumn COMET SECTOR (orange comet sparks and pumpkins) and the winter ICE
## SECTOR (ice crystals and snowmen). Seasonal dust streams past the ship (one CPUParticles3D) and a few little
## floating SECTOR ISLANDS, each with a seasonal prop on top (core/season_kit.gd), glide slowly past far out to the
## sides (clear of the rings, the pick orbs and the surprises, which all stay within space.gd LIMIT + a few metres).
## One merged mesh per island + one particle node (the dust fades before it reaches the ship: never a big square in
## the pilot's face or the TV camera): cheap on the Frame.
##   set_season(name)

const MeshKit := preload("res://core/mesh_kit.gd")
const SeasonKit := preload("res://core/season_kit.gd")  # (the props and the drift: shared with the other seasonal games)
const Deep := preload("res://games/starship_crew/deep.gd")
const Art := preload("res://games/starship_crew/art.gd")

## Islands: [x, y, start z] far out to the sides; they glide past at a share of the ship's speed and come round again.
const ISLANDS: Array[Vector3] = [Vector3(-19.0, -3.0, -40.0), Vector3(20.0, 4.0, -80.0), Vector3(-22.0, 6.0, -120.0), Vector3(18.0, -5.0, -150.0)]
const GLIDE := 0.35  # share of the ship's speed
const FAR_Z := -170.0
const NEAR_Z := 20.0

var main
var season := ""
var islands: Array = []  # MeshInstance3D
var drift: CPUParticles3D
var _t := 0.0


func set_season(s: String) -> void:
	if s == season or not Deep.SEASONS.has(s):
		return
	season = s
	for n in islands:
		if is_instance_valid(n):
			(n as Node).queue_free()
	islands = []
	if drift != null and is_instance_valid(drift):
		drift.queue_free()
	var sd := Deep.season_data(s)
	for i in ISLANDS.size():
		var b := MeshKit.Builder.new()
		var rock: Color = Art.ROCK_COLORS[i % Art.ROCK_COLORS.size()]
		b.ellipsoid(Vector3(2.6, 0.7, 2.2), MeshKit.at(Vector3(0, -0.4, 0)), rock, 12)
		b.cone(1.8, 2.2, MeshKit.at(Vector3(0, -1.6, 0), Vector3.ONE, Vector3(PI, 0, 0)), rock.darkened(0.2), 10)
		b.cylinder(2.3, 2.4, 0.15, MeshKit.at(Vector3(0, 0.25, 0)), _ground(s), 14)
		SeasonKit.prop(b, s, Vector3(-0.8, 0.3, 0.3), i, 1.6, Vector3(signf(-ISLANDS[i].x), 0, 1).normalized())
		SeasonKit.prop(b, s, Vector3(0.9, 0.3, -0.4), i + 1, 1.2, Vector3(signf(-ISLANDS[i].x), 0, 1).normalized())
		var mi := MeshKit.instance(b.build(), false)
		mi.name = "SectorIsland%d" % i
		add_child(mi)
		mi.position = ISLANDS[i]
		islands.append(mi)
	drift = SeasonKit.drift(sd.drift, s, {"amount": 90, "lifetime": 2.4, "box": Vector3(18.0, 9.0, 30.0),
		"at": Vector3(0.0, 2.0, -95.0), "size": 0.45 if s == "winter" else 0.55, "speed": Vector2(14.0, 22.0), "dir": Vector3(0.0, 0.0, 1.0)})
	drift.spread = 4.0
	drift.gravity = Vector3.ZERO
	add_child(drift)
	print("Starship Crew: the %s" % String(sd.name))


## The island's top: grass in spring and summer, leaves in autumn, snow in winter.
static func _ground(s: String) -> Color:
	match s:
		"winter":
			return Color(0.95, 0.97, 1.0)
		"autumn":
			return Color(0.85, 0.45, 0.15)
		"summer":
			return Color(0.45, 0.75, 0.3)
	return Color(0.55, 0.85, 0.45)


func _process(delta: float) -> void:
	if islands.is_empty() or main == null or main.space == null:
		return
	_t += delta
	var sp: float = main.space.speed
	for i in islands.size():
		var n: Node3D = islands[i]
		if not is_instance_valid(n):
			continue
		var p := n.position
		p.z += sp * GLIDE * delta
		if p.z > NEAR_Z:
			p.z = FAR_Z
		p.y = ISLANDS[i].y + sin(_t * 0.5 + i) * 0.4
		n.position = p
		n.rotation.y += delta * 0.08