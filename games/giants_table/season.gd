extends Node3D
## GIANT'S TABLE seasonal dressing (deep.gd SEASONS, Seeded.season on the host; sent in the "deep" state): every
## machine dresses the table the same -
##   - a seasonal TABLECLOTH hangs off the rim all the way round (spring green with pink trim, summer sunny with a
##     blue trim, autumn orange with a red trim, winter red with snowy white trim);
##   - Sparky's CENTREPIECE: a wreath on the stones round the campfire (spring flowers, summer sunflowers, autumn
##     leaves and little pumpkins, winter holly berries and snow puffs);
##   - big seasonal things standing in the room round the table (core/season_kit.gd props: a snowman, a pumpkin,
##     tulips, sunflowers), away from the Giant's seat.
## No rain and nothing falls from the sky (David). One merged mesh each: cheap on the Frame and the Decks.
##   set_season(name)

const MeshKit := preload("res://core/mesh_kit.gd")
const SeasonKit := preload("res://core/season_kit.gd")  # (the room props: shared with the other seasonal games)
const Deep := preload("res://games/giants_table/deep.gd")
const W := preload("res://games/giants_table/world.gd")

## The tablecloth's cloth and trim colours, and the wreath's green.
const CLOTH := {
	"spring": [Color(0.72, 0.9, 0.62), Color(1.0, 0.6, 0.78)],
	"summer": [Color(1.0, 0.93, 0.6), Color(0.35, 0.65, 1.0)],
	"autumn": [Color(0.92, 0.55, 0.22), Color(0.7, 0.18, 0.15)],
	"winter": [Color(0.75, 0.12, 0.15), Color(0.97, 0.97, 1.0)],
}
const CLOTH_DROP := 5.0  # how far the cloth hangs down
const WREATH_R := 1.35  # on the fire's stones (world.gd FIRE_R 1.1)
const ROOM_R := 24.0  # the room props stand this far out, on the rug
const ROOM_ANGLES: Array[float] = [3.6, 4.2, 4.7, 5.25, 5.85, 0.3, 2.85]  # (never near the Giant's seat at PI/2)
const ROOM_SIZE := 9.0

var main
var season := ""
var cloth: MeshInstance3D
var wreath: MeshInstance3D
var props: MeshInstance3D


func set_season(s: String) -> void:
	if s == season or not Deep.SEASONS.has(s):
		return
	season = s
	for n in [cloth, wreath, props]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	cloth = _cloth(s)
	add_child(cloth)
	wreath = _wreath(s)
	add_child(wreath)
	var b := MeshKit.Builder.new()
	for i in ROOM_ANGLES.size():
		var a: float = ROOM_ANGLES[i]
		var p := Vector3(cos(a), 0.0, sin(a)) * ROOM_R + Vector3(0.0, W.FLOOR_Y, 0.0)
		SeasonKit.prop(b, s, p, i, ROOM_SIZE, -Vector3(p.x, 0.0, p.z).normalized())  # facing the table
	props = MeshKit.instance(b.build(), false)
	props.name = "SeasonProps"
	add_child(props)
	print("Giant's Table: %s table" % s)


## The tablecloth: a skirt round the table's edge with a trim band and a row of little scallops.
func _cloth(s: String) -> MeshInstance3D:
	var cols: Array = CLOTH[s]
	var b := MeshKit.Builder.new()
	var r := W.EDGE + 0.06
	b.cylinder(r, r, CLOTH_DROP, MeshKit.at(Vector3(0, -CLOTH_DROP * 0.5 + 0.02, 0)), cols[0], 48, false, false)
	b.cylinder(r + 0.04, r + 0.04, 0.7, MeshKit.at(Vector3(0, -CLOTH_DROP + 0.4, 0)), cols[1], 48, false, false)
	b.cylinder(r + 0.03, r + 0.03, 0.18, MeshKit.at(Vector3(0, -0.12, 0)), cols[1], 48, false, false)
	for i in 36:  # scallops along the hem
		var a := i * TAU / 36.0
		b.sphere(0.32, MeshKit.at(Vector3(cos(a), 0, sin(a)) * (r + 0.02) + Vector3(0, -CLOTH_DROP + 0.05, 0), Vector3(1.0, 0.6, 0.35),
			Vector3(0, -a + PI * 0.5, 0)), cols[1], 8)
	var mi := MeshKit.instance(b.build(), false)
	mi.name = "Tablecloth"
	return mi


## Sparky's wreath: a green ring on the fire's stones dressed for the season.
func _wreath(s: String) -> MeshInstance3D:
	var b := MeshKit.Builder.new()
	var y := 0.12
	var green := Color(0.25, 0.55, 0.25) if s != "autumn" else Color(0.55, 0.45, 0.2)
	b.torus(WREATH_R, 0.13, MeshKit.at(Vector3(0, y, 0)), green, 32, 6)
	for i in 16:
		var a := i * TAU / 16.0
		var p := Vector3(cos(a), 0, sin(a)) * WREATH_R + Vector3(0, y + 0.1, 0)
		match s:
			"spring":
				b.sphere(0.11, MeshKit.at(p), [Color(1.0, 0.5, 0.7), Color(1.0, 1.0, 1.0), Color(1.0, 0.85, 0.3)][i % 3], 8)
			"summer":
				if i % 2 == 0:
					b.cylinder(0.14, 0.14, 0.04, MeshKit.at(p + Vector3(0, 0.03, 0)), Color(1.0, 0.82, 0.15), 10)
					b.cylinder(0.06, 0.06, 0.05, MeshKit.at(p + Vector3(0, 0.05, 0)), Color(0.4, 0.25, 0.1), 8)
				else:
					b.sphere(0.08, MeshKit.at(p), Color(1.0, 1.0, 1.0), 6)
			"autumn":
				if i % 4 == 0:
					b.sphere(0.15, MeshKit.at(p + Vector3(0, 0.03, 0), Vector3(1.25, 0.85, 1.25)), Color(1.0, 0.55, 0.1), 8)
				else:
					b.ellipsoid(Vector3(0.14, 0.03, 0.09), MeshKit.at(p, Vector3.ONE, Vector3(0, a * 2.0, 0)),
						[Color(0.9, 0.35, 0.1), Color(0.95, 0.7, 0.15), Color(0.7, 0.2, 0.1)][i % 3], 6)
			_:  # winter: holly berries and snow puffs
				if i % 2 == 0:
					for k in 3:
						b.sphere(0.05, MeshKit.at(p + Vector3(0.05 * (k - 1), 0.02 * (k % 2), 0.04 * (k % 2))), Color(0.9, 0.08, 0.1), 6)
				else:
					b.sphere(0.1, MeshKit.at(p), Color(0.97, 0.98, 1.0), 6)
	var mi := MeshKit.instance(b.build(), false)
	mi.name = "Centrepiece"
	return mi
