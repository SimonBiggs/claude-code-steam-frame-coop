extends RefCounted
## FISHING LAKE seasons (third pass; pure data, fast, no nodes).
##  * The season (SeasonKit.override(GAME_ID, Seeded.season())): ARCADE_SEASON / ARCADE_SEASON_FISHING_LAKE
##    dress the lake for a season in tests. It changes the weather mix (lakegen.gd WEATHER_W), the trees, what
##    drifts down (SeasonKit.drift), two seasonal props by the jetty foot, ice along the shore in winter, and
##    WHO FLIES IN: Mama Duck's friends (ducks in spring, gulls in summer, geese in autumn, swans in winter).
##  * FLOCK VISITS (lakegen.gd visits): a flock lands on the water a few times a day. A pink warn ring on the
##    water TELLS where, the birds fly in during the tell, then SPLASH: fish there swim off, a nibble there is
##    lost, boats there bob out of the way. Reel your bobber out of the ring in time! After they fly off they
##    leave a little treasure bubbling up where they sat.
##  * OLLIE'S SHORE GARDEN: every time Ollie's wish is caught he plants a keepsake of the season on the shore
##    (tulips, sunflowers, a pumpkin, a snowman: core/season_kit.gd props) - the year the family fished, round
##    the lake. keepsake_spots() places them; check_spots() proves they stand on the grassy bank, apart, clear
##    of the jetty, the pond and the boards.

const SeasonKit := preload("res://core/season_kit.gd")
const Lake := preload("res://games/fishing_lake/lake.gd")

const SEASONS: Array[String] = ["spring", "summer", "autumn", "winter"]
## Weather weights [sunny, rain, evening] per season ("" = the old mix).
const WEATHER_W := {"": [3, 2, 2], "spring": [2, 3, 1], "summer": [4, 1, 2], "autumn": [2, 2, 3], "winter": [2, 1, 4]}
## The flock that visits, per season: name, story picture, body / head / beak colours, size, how many.
const FLOCKS := {
	"spring": {"name": "DUCKS", "pic": "duckling", "body": Color(1.0, 0.86, 0.3), "head": Color(1.0, 0.86, 0.3),
		"beak": Color(1.0, 0.55, 0.1), "size": 0.75, "n": 5},
	"summer": {"name": "GULLS", "pic": "bird", "body": Color(0.92, 0.93, 0.95), "head": Color(0.97, 0.97, 0.97),
		"beak": Color(1.0, 0.8, 0.1), "size": 0.9, "n": 4},
	"autumn": {"name": "GEESE", "pic": "goose", "body": Color(0.55, 0.45, 0.35), "head": Color(0.12, 0.12, 0.12),
		"beak": Color(0.15, 0.15, 0.15), "size": 1.15, "n": 4},
	"winter": {"name": "SWANS", "pic": "bird", "body": Color(0.98, 0.98, 1.0), "head": Color(0.98, 0.98, 1.0),
		"beak": Color(1.0, 0.45, 0.1), "size": 1.4, "n": 3},
}
## Ollie's season card at the start of a visit: line, picture, colour.
const CARDS := {
	"spring": ["Spring! Blossom time!", "wildflowers", Color(1.0, 0.6, 0.8)],
	"summer": ["Sunny summer lake!", "sunflower", Color(1.0, 0.85, 0.2)],
	"autumn": ["Autumn leaves!", "pumpkin", Color(1.0, 0.55, 0.15)],
	"winter": ["Snow on the lake!", "snowflake", Color(0.75, 0.9, 1.0)],
}
const DRIFT := {"spring": Color(1.0, 0.75, 0.88), "summer": Color(1.0, 1.0, 0.92), "autumn": Color(0.95, 0.5, 0.12),
	"winter": Color(0.97, 0.98, 1.0)}
## The flock's warn ring: pink, unlike Old Whiskers' orange (palette.gd checks it on every water).
const RING := Color(1.0, 0.4, 0.85)
const WHISKERS_RING := Color(1.0, 0.6, 0.2)  # Old Whiskers' pull tells (main.gd on_boss_tell)
const VISIT_R := 2.6
const VISIT_FROM := 0.16  # no flock in the first part of the day (fish first)
const VISIT_TO := 0.84
const VISIT_GAP := 0.18  # day fractions between two flocks
const SIT_SECS := 7.0  # how long they paddle before flying off
const MAX_KEEPSAKES := 24
const GARDEN_R := Lake.LAKE_R + 1.5  # on the grassy bank (the sand ends at LAKE_R + 0.4)


static func valid(s: String) -> String:
	return s if SEASONS.has(s) else "summer"


static func index(s: String) -> int:
	return maxi(0, SEASONS.find(s))


static func flock(s: String) -> Dictionary:
	return FLOCKS[valid(s)]


## Where keepsake i stands (on the bank round the near half of the lake, left and right of the jetty in turn,
## the first ones nearest the jetty so a VR angler sees them by turning their head).
static func keepsake_spots(n: int = MAX_KEEPSAKES) -> Array:
	var out: Array = []
	for i in mini(n, MAX_KEEPSAKES):
		var side := -1.0 if i % 2 == 0 else 1.0
		var step := i / 2
		var a := side * (0.42 + 0.105 * float(step))
		out.append(Lake.LAKE_C + Vector3(sin(a) * GARDEN_R, 0.0, cos(a) * GARDEN_R))
	return out


## Problems with the garden spots (empty = fine).
static func check_spots(spots: Array) -> Array:
	var why: Array = []
	for i in spots.size():
		var p: Vector3 = spots[i]
		var lc := Vector2(p.x - Lake.LAKE_C.x, p.z - Lake.LAKE_C.z).length()
		if lc < Lake.LAKE_R + 0.9 or lc > Lake.LAKE_R + 2.4:
			why.append("keepsake %d not on the grassy bank (%.1f m from the middle)" % [i, lc])
		if absf(p.x) < Lake.JETTY_HALF + 3.0 and p.z > Lake.JETTY_END_Z:
			why.append("keepsake %d on the jetty path" % i)
		if Vector2(p.x - Lake.POND_C.x, p.z - Lake.POND_C.z).length() < Lake.POND_R + 1.5:
			why.append("keepsake %d in Ollie's pond" % i)
		for j in i:
			var q: Vector3 = spots[j]
			if Vector2(p.x - q.x, p.z - q.z).length() < 1.6:
				why.append("keepsakes %d and %d touch" % [j, i])
	return why
