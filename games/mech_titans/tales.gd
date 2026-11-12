extends RefCounted
## MECH TITANS LOST-TOY TALES (deep2-mech): every made round's lost kaiju has a little story: it lost its TOY
## somewhere in the city (a teddy, a balloon, a beach ball, an ice cream, a pumpkin, mittens, a scarf, a kite - the
## season picks which ones turn up). The toy stands on a street corner under a tall beam of light in its colour, so
## the VR pilot and every TV jet / truck can see it from anywhere. Walk the Titan up to it (or fly / drive a support
## vehicle through it) and it zooms back to the kaiju: the kaiju is happy (hearts, a dizzy smile, a lot calmer:
## TOY_CALM of its health goes), the team gets a bonus sanctuary heart, and the toy moves into MOMO'S TOY PARK on
## the hills by the city, which keeps growing (saved: data["toys"], every toy ever found, data["toys_n"]).
## SEASONS (Seeded.season of the round's date, the same on every machine: roundgen.gd puts it in the round):
## the lost kaiju wear a seasonal hat (bobble hat / leaf crown / flower crown / sun hat), the season's toys are
## likelier, and main.gd dresses the city (core/season_kit.gd props + drift).
## Pure data + meshes so tests/mech_titans_rounds_test.gd can prove every toy is reachable in every city (check()).

const Data := preload("res://games/mech_titans/data.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Seeded := preload("res://core/seeded.gd")

## id: name (one or two capital words: the story card), pic (story picture), color (the beam and the card),
## seasons it turns up in (doubly likely in its own seasons; TEDDY turns up in any season).
const TOYS := {
	"teddy": {"name": "TEDDY", "pic": "teddy", "color": Color(0.62, 0.3, 0.12), "seasons": []},
	"balloon": {"name": "BALLOON", "pic": "balloon", "color": Color(0.98, 0.25, 0.35), "seasons": ["spring", "summer"]},
	"beachball": {"name": "BEACH BALL", "pic": "beachball", "color": Color(0.0, 0.55, 0.85), "seasons": ["summer"]},
	"icecream": {"name": "ICE CREAM", "pic": "icecream", "color": Color(1.0, 0.5, 0.78), "seasons": ["summer", "spring"]},
	"kite": {"name": "KITE", "pic": "kite", "color": Color(0.85, 0.3, 0.95), "seasons": ["spring", "autumn"]},
	"pumpkin": {"name": "PUMPKIN", "pic": "pumpkin", "color": Color(1.0, 0.52, 0.08), "seasons": ["autumn"]},
	"mittens": {"name": "MITTENS", "pic": "mittens", "color": Color(0.25, 0.5, 1.0), "seasons": ["winter"]},
	"scarf": {"name": "SCARF", "pic": "scarf", "color": Color(0.95, 0.2, 0.25), "seasons": ["winter", "autumn"]},
}
const ORDER: Array[String] = ["teddy", "balloon", "beachball", "icecream", "kite", "pumpkin", "mittens", "scarf"]
## The lost kaiju's seasonal hat.
const HATS := {"winter": "bobble", "autumn": "leaves", "spring": "flowers", "summer": "sunhat"}
const TOY_CALM := 0.3  ## the found toy takes this much of each lost kaiju's health (it's much happier)
const TOY_HEARTS := 1  ## bonus sanctuary hearts for a found toy
const TOUCH_TITAN := 7.5  ## m from the toy to the Titan's middle
const TOUCH_VEH := 6.5
const TOY_SIZE := 4.5  ## m: a toy is about this tall in the city
const BEAM_H := 46.0
## Street corners a toy can stand on (road crossings between the blocks, north of the Titan's start).
const CORNER_X: Array[float] = [-39.0, -13.0, 13.0, 39.0]
const CORNER_Z: Array[float] = [-39.0, -13.0, 13.0]
const MIN_FROM_START := 30.0
const PARK_MAX := 24  ## toys standing in Momo's toy park (the newest)
const PARK_EVERY := 4  ## a TOY PARK GROWS card every this many toys found


static func info(id: String) -> Dictionary:
	return TOYS.get(id, TOYS["teddy"])


## A made round's toy for this season (seeded; its own rng so the rest of the round is unchanged).
static func pick(r: RandomNumberGenerator, season: String) -> String:
	var w: Array = []
	for id in ORDER:
		var ss: Array = TOYS[id]["seasons"]
		w.append(1.0 if ss.is_empty() else (2.0 if ss.has(season) else 0.0))
	return ORDER[Seeded.weighted(r, w)]


static func hat(season: String) -> String:
	return String(HATS.get(season, "sunhat"))


## The street corner the round's toy stands on (the same on every machine: the city and the seed decide).
static func spot(city: Node, toy_seed: int) -> Vector3:
	var cands: Array = []
	for x in CORNER_X:
		for z in CORNER_Z:
			var p := Vector3(x, 0.0, z)
			if p.distance_to(Data.MECH_START) >= MIN_FROM_START:
				cands.append(p)
	var r := Seeded.rng(toy_seed, "toyspot")
	var at: Vector3 = cands[r.randi() % cands.size()]
	if city != null:
		at = city.push_out(at, 4.0)
	at.y = 0.0
	return at


## Where the n-th toy of Momo's toy park stands: rows on the hills just outside the city's east and west edges
## (past the sanctuary homes), facing in.
static func park_spot(i: int) -> Vector3:
	var side := -1.0 if i % 2 == 0 else 1.0
	var row := (i / 2) % 6
	var col := (i / 2) / 6
	return Vector3(side * (92.0 + col * 10.0), 0.0, 30.0 - row * 13.0 + col * 6.0)


## Why a round's tale is wrong (empty = fine).
static func check(m: Dictionary) -> Array:
	var out: Array = []
	var toy := String(m.get("toy", ""))
	if not bool(m.get("gen", false)):
		if toy != "":
			out.append("a lesson has a toy")
		return out
	if not TOYS.has(toy):
		out.append("unknown toy '%s'" % toy)
		return out
	var season := String(m.get("season", ""))
	if not HATS.has(season):
		out.append("unknown season '%s'" % season)
	var ss: Array = TOYS[toy]["seasons"]
	if not ss.is_empty() and not ss.has(season):
		out.append("%s turned up in %s" % [toy, season])
	var nm := String(TOYS[toy]["name"])
	if nm.split(" ", false).size() > 2 or nm != nm.to_upper():
		out.append("toy name '%s' must be one or two capital words" % nm)
	var v: Dictionary = m.get("variant", {})
	if String(m.get("bigboss", "")) == "" and String(v.get("hat", "")) != hat(season):
		out.append("the lost kaiju isn't wearing the %s hat" % season)
	return out


## Every season has at least two toys (so the tales vary all year).
static func check_seasons() -> Array:
	var out: Array = []
	for s in HATS:
		var n := 0
		for id in ORDER:
			var ss: Array = TOYS[id]["seasons"]
			if ss.is_empty() or ss.has(s):
				n += 1
		if n < 3:
			out.append("%s has only %d toys" % [s, n])
	return out


# --- Meshes (every machine) -------------------------------------------------------------------------------

## A toy about 1 m tall standing on y = 0 (scale it by TOY_SIZE).
static func toy_mesh(id: String) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var c: Color = info(id)["color"]
	match id:
		"teddy":
			var fur := c
			b.ellipsoid(Vector3(0.26, 0.3, 0.22), MeshKit.at(Vector3(0, 0.32, 0)), fur, 12)
			b.ellipsoid(Vector3(0.16, 0.2, 0.06), MeshKit.at(Vector3(0, 0.3, 0.18)), fur.lightened(0.35), 10)
			b.sphere(0.2, MeshKit.at(Vector3(0, 0.74, 0)), fur, 12)
			b.sphere(0.08, MeshKit.at(Vector3(0, 0.7, 0.17)), fur.lightened(0.4), 8)
			b.sphere(0.03, MeshKit.at(Vector3(0, 0.73, 0.24)), Color(0.15, 0.1, 0.08), 6)
			for sx in [-1.0, 1.0]:
				b.sphere(0.075, MeshKit.at(Vector3(sx * 0.15, 0.92, 0)), fur, 8)
				b.sphere(0.03, MeshKit.at(Vector3(sx * 0.07, 0.8, 0.17)), Color(0.1, 0.08, 0.08), 6)
				b.sphere(0.09, MeshKit.at(Vector3(sx * 0.26, 0.42, 0.06)), fur, 8)
				b.sphere(0.1, MeshKit.at(Vector3(sx * 0.14, 0.08, 0.1)), fur, 8)
			b.box(Vector3(0.3, 0.06, 0.06), MeshKit.at(Vector3(0, 0.57, 0.14)), Color(0.3, 0.6, 1.0))
		"balloon":
			b.cylinder(0.008, 0.008, 0.55, MeshKit.at(Vector3(0, 0.3, 0)), Color(0.95, 0.95, 0.95), 4)
			b.cylinder(0.12, 0.15, 0.08, MeshKit.at(Vector3(0, 0.04, 0)), Color(0.55, 0.55, 0.6), 8)
			b.ellipsoid(Vector3(0.24, 0.3, 0.24), MeshKit.at(Vector3(0, 0.85, 0)), c, 14)
			b.cone(0.04, 0.06, MeshKit.at(Vector3(0, 0.56, 0), Vector3.ONE, Vector3(PI, 0, 0)), c.darkened(0.2), 6)
		"beachball":
			var cols := [c, Color(0.95, 0.2, 0.25), Color(1, 1, 1), Color(0.2, 0.5, 1.0)]
			for k in 4:
				b.ellipsoid(Vector3(0.42 - k * 0.002, 0.42, 0.42 - k * 0.002) * (1.0 - 0.001 * k),
					MeshKit.at(Vector3(0, 0.42, 0), Vector3(1.0, 1.0, 0.35 + 0.0 * k), Vector3(0, k * PI * 0.25, 0)), cols[k], 14)
			b.sphere(0.1, MeshKit.at(Vector3(0, 0.84, 0)), Color(1, 1, 1), 8)
		"icecream":
			b.cone(0.18, 0.55, MeshKit.at(Vector3(0, 0.275, 0), Vector3.ONE, Vector3(PI, 0, 0)), Color(0.85, 0.62, 0.32), 10)
			b.sphere(0.21, MeshKit.at(Vector3(0, 0.62, 0)), c, 12)
			b.sphere(0.18, MeshKit.at(Vector3(0, 0.84, 0)), Color(0.98, 0.95, 0.85), 12)
			b.sphere(0.05, MeshKit.at(Vector3(0, 1.02, 0)), Color(0.9, 0.1, 0.2), 6)
		"kite":
			b.cylinder(0.01, 0.01, 0.6, MeshKit.at(Vector3(0, 0.3, 0)), Color(0.9, 0.9, 0.9), 4)
			var k_xf := MeshKit.at(Vector3(0, 0.85, 0), Vector3(1, 1, 1), Vector3(0, 0, PI * 0.25))
			b.box(Vector3(0.38, 0.38, 0.03), k_xf, c)
			b.box(Vector3(0.04, 0.5, 0.04), MeshKit.at(Vector3(0, 0.85, 0.02)), Color(1, 1, 1))
			b.box(Vector3(0.5, 0.04, 0.04), MeshKit.at(Vector3(0, 0.85, 0.02)), Color(1, 1, 1))
			for k in 3:
				b.box(Vector3(0.1, 0.06, 0.02), MeshKit.at(Vector3(0.05 * (k % 2), 0.5 - k * 0.12, 0.0), Vector3.ONE, Vector3(0, 0, 0.4)), [Color(1, 0.85, 0.2), Color(0.3, 0.8, 1.0), Color(0.4, 0.9, 0.4)][k])
		"pumpkin":
			for k in 6:
				var a := k * TAU / 6.0
				b.ellipsoid(Vector3(0.22, 0.3, 0.22), MeshKit.at(Vector3(cos(a) * 0.17, 0.3, sin(a) * 0.17)), c if k % 2 == 0 else c.darkened(0.1), 10)
			b.cylinder(0.04, 0.05, 0.16, MeshKit.at(Vector3(0, 0.66, 0)), Color(0.3, 0.5, 0.15), 6)
			b.ellipsoid(Vector3(0.14, 0.02, 0.08), MeshKit.at(Vector3(0.1, 0.66, 0), Vector3.ONE, Vector3(0, 0, -0.4)), Color(0.35, 0.65, 0.2), 6)
		"mittens":
			for sx in [-1.0, 1.0]:
				var xf := MeshKit.at(Vector3(sx * 0.2, 0.0, 0), Vector3.ONE, Vector3(0, 0, -sx * 0.15))
				b.ellipsoid(Vector3(0.17, 0.3, 0.1), xf * MeshKit.at(Vector3(0, 0.5, 0)), c, 10)
				b.ellipsoid(Vector3(0.07, 0.13, 0.08), xf * MeshKit.at(Vector3(sx * 0.16, 0.45, 0), Vector3.ONE, Vector3(0, 0, sx * 0.6)), c, 8)
				b.cylinder(0.17, 0.17, 0.12, xf * MeshKit.at(Vector3(0, 0.2, 0)), Color(1, 1, 1), 10)
			b.tube(Vector3(-0.2, 0.15, 0), Vector3(0.2, 0.15, 0), 0.015, 0.015, Color(1, 1, 1), 4)
		"scarf":
			for k in 7:
				var y := 0.05 + k * 0.13
				var col := c if k % 2 == 0 else Color(1, 1, 1)
				b.box(Vector3(0.36, 0.13, 0.08), MeshKit.at(Vector3(sin(k * 0.8) * 0.06, y, 0), Vector3.ONE, Vector3(0, 0, sin(k * 0.8) * 0.15)), col)
			b.torus(0.18, 0.06, MeshKit.at(Vector3(0, 0.98, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), c, 12, 6)
	return b.build()


## The lost kaiju's seasonal hat, about 1 m across, sitting on y = 0 (kaiju.gd scales and places it on the head).
static func hat_mesh(id: String) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	match id:
		"bobble":
			b.dome(0.42, MeshKit.at(Vector3.ZERO, Vector3(1, 1.1, 1)), Color(0.95, 0.25, 0.3), 14)
			b.cylinder(0.45, 0.45, 0.14, MeshKit.at(Vector3(0, 0.05, 0)), Color(1, 1, 1), 14)
			b.sphere(0.14, MeshKit.at(Vector3(0, 0.5, 0)), Color(1, 1, 1), 8)
		"leaves":
			for k in 8:
				var a := k * TAU / 8.0
				var col := [Color(1.0, 0.55, 0.1), Color(0.95, 0.3, 0.15), Color(1.0, 0.8, 0.2)][k % 3] as Color
				b.ellipsoid(Vector3(0.16, 0.05, 0.1), MeshKit.at(Vector3(cos(a) * 0.38, 0.06, sin(a) * 0.38), Vector3.ONE, Vector3(0, -a, 0.5)), col, 6)
			b.torus(0.38, 0.04, MeshKit.at(Vector3(0, 0.03, 0)), Color(0.5, 0.3, 0.15), 14, 4)
		"flowers":
			b.torus(0.38, 0.05, MeshKit.at(Vector3(0, 0.03, 0)), Color(0.35, 0.7, 0.3), 14, 4)
			for k in 7:
				var a := k * TAU / 7.0
				var col := [Color(1.0, 0.45, 0.65), Color(1, 1, 1), Color(1.0, 0.85, 0.25), Color(0.7, 0.55, 1.0)][k % 4] as Color
				b.sphere(0.1, MeshKit.at(Vector3(cos(a) * 0.38, 0.1, sin(a) * 0.38)), col, 8)
		_:  # sunhat
			b.cylinder(0.62, 0.62, 0.04, MeshKit.at(Vector3(0, 0.02, 0)), Color(1.0, 0.88, 0.5), 18)
			b.cylinder(0.3, 0.34, 0.3, MeshKit.at(Vector3(0, 0.17, 0)), Color(1.0, 0.88, 0.5), 14)
			b.cylinder(0.345, 0.345, 0.08, MeshKit.at(Vector3(0, 0.08, 0)), Color(0.95, 0.35, 0.4), 14)
	return b.build()
