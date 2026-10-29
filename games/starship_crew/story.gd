extends RefCounted
## STARSHIP CREW story: CAPTAIN WHISKERS (a ginger space cat in a bubble helmet) runs the little
## starship and dreams of the BEST SPACE STATION IN THE SKY. Every trip home builds the station a new
## part (solar panels, a garden dome, party lights, a second wheel ...), and the parts STAY (saved):
## the crew sees the station grow every time they dock, and the pilot keeps a tiny glowing model of it
## on the dashboard. Every trip also visits new planets with silly names; the captain's STAR MAP keeps
## them all.
## TRIPS: the family's very first trip is the four lessons (rings, rocks, aliens, home). After that every
## trip is three seeded missions (missiongen.gd) from this family's own world seed, picked from rings,
## rocks, aliens and a mixed STAR PARTY, then HOME; one tier harder as the trips go by (faster ship, bigger
## ring swerves, more rocks, wigglier aliens). The first trip of each day opens with TODAY'S MISSION
## (the same everywhere all day).

const Seeded := preload("res://core/seeded.gd")
const MissionGen := preload("res://games/starship_crew/missiongen.gd")

const GAME_ID := "starship_crew"
const CAPTAIN := "CAPTAIN WHISKERS"
const CAPTAIN_COLOR := Color(1.0, 0.62, 0.25)
const MISSIONS := 4  ## per trip (the last one is always HOME)
const LESSONS: Array[String] = ["rings", "rocks", "aliens", "home"]
const POOL: Array[String] = ["rings", "rocks", "aliens", "mixed"]
const NAMES := {"rings": "STAR RINGS!", "rocks": "SPACE ROCKS!", "aliens": "SILLY ALIENS!", "mixed": "STAR PARTY!", "home": "HOME!"}
const DAILY_NAME := "TODAY'S MISSION!"

## Station parts, one per trip home (art.gd station() draws the first `parts` of these).
const PARTS: Array[Dictionary] = [
	{"id": "panels", "pic": "sun", "line": "Solar panels!"},
	{"id": "dome", "pic": "tree", "line": "A garden dome!"},
	{"id": "antenna", "pic": "station", "line": "A big antenna!"},
	{"id": "lights", "pic": "star", "line": "Party lights!"},
	{"id": "wheel", "pic": "station", "line": "A second wheel!"},
	{"id": "rocket", "pic": "rocket", "line": "A rocket dock!"},
	{"id": "disco", "pic": "music", "line": "A disco ball!"},
	{"id": "bridge", "pic": "station", "line": "A sky bridge!"},
	{"id": "topstar", "pic": "star", "line": "A giant star!"},
	{"id": "gold", "pic": "crown", "line": "A GOLDEN station!"},
]

const SYLLABLES: Array[String] = ["ZOO", "BLIP", "MOO", "WIB", "ZAP", "PIP", "NOO", "FIZ", "LOLO", "TOOT", "BOP", "YAY", "WOO", "GLOB", "MIM", "ZUZU"]
const PLANET_COLS: Array[Color] = [Color(1.0, 0.6, 0.4), Color(0.5, 0.75, 1.0), Color(0.75, 0.5, 1.0), Color(1.0, 0.85, 0.35),
	Color(1.0, 0.55, 0.75), Color(0.45, 0.95, 0.85), Color(0.95, 0.45, 0.4), Color(0.7, 0.9, 0.45)]
const HOME_LOOK := [Color(0.5, 0.95, 0.6), Color(0.9, 1.0, 0.8), 3]
const STAR_MAP_MAX := 60

const LINES := {
	"welcome": "Welcome aboard, crew!",
	"new_trip": ["New planets to see!", "Off we go, crew!", "Strap in! Let's fly!", "To the stars!"],
	"daily": "TODAY'S MISSION!",
	"rings": ["Fly through the rings!", "Ring time!"],
	"rocks": ["Space rocks! Zap!", "Rocks ahead!"],
	"aliens": ["Silly aliens!", "Wave at the aliens!"],
	"mixed": ["A star party!", "Everything at once!"],
	"home": ["Home time!", "Back to the station!"],
	"planet": "Planet %s!",
	"docked": ["Home sweet home!", "Purr-fect flying!", "What a crew!"],
}


static func save_defaults() -> Dictionary:
	return {"trips": 0, "world": -1, "daily": {}, "planets": [], "stars": 0, "missions": 0}


## How hard trip number `trips` is (0 = the lessons).
static func tier_for(trips: int) -> int:
	return clampi(trips, 0, MissionGen.TIERS - 1)


## The four missions of trip number `trips`: [{"k": kind, "s": seed, "tier": t, "daily": bool, "planet": seed or -1}].
static func trip(trips: int, world: int, daily_due: bool, date: String = "") -> Array:
	var out: Array = []
	if trips <= 0:
		for i in MISSIONS:
			out.append({"k": LESSONS[i], "s": Seeded.derive(world, "lesson%d" % i), "tier": 0, "daily": false,
				"planet": -1 if i == MISSIONS - 1 else Seeded.derive(world, "lessonplanet%d" % i)})
		return out
	var r := Seeded.rng(world, "trip%d" % trips)
	var kinds := Seeded.shuffled(r, POOL)
	for i in MISSIONS - 1:
		var s := Seeded.derive(world, "trip%d/%d" % [trips, i])
		out.append({"k": String(kinds[i]), "s": s, "tier": tier_for(trips), "daily": false, "planet": Seeded.derive(s, "planet")})
	out.append({"k": "home", "s": Seeded.derive(world, "trip%d/home" % trips), "tier": tier_for(trips), "daily": false, "planet": -1})
	if daily_due:
		out[0] = daily_mission(date)
	return out


static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed(GAME_ID, date)


## TODAY'S MISSION: a kind and seed from the date, the same on every machine all day.
static func daily_mission(date: String = "") -> Dictionary:
	var s := daily_seed(date)
	var r := Seeded.rng(s, "daily")
	return {"k": String(Seeded.pick(r, POOL)), "s": s, "tier": 2, "daily": true, "planet": Seeded.derive(s, "planet")}


static func mission_name(m: Dictionary) -> String:
	return DAILY_NAME if bool(m.get("daily", false)) else String(NAMES.get(String(m.k), "GO!"))


## A planet's look from its seed: [body colour, ring colour (alpha 0 = no rings), sky spot 0..3].
static func planet_look(seed_value: int) -> Array:
	if seed_value < 0:
		return HOME_LOOK.duplicate()
	var r := Seeded.rng(seed_value, "look")
	var col: Color = PLANET_COLS[r.randi() % PLANET_COLS.size()]
	var ring := Color(0, 0, 0, 0)
	if r.randf() < 0.6:
		ring = PLANET_COLS[r.randi() % PLANET_COLS.size()].lightened(0.35)
	return [col, ring, r.randi() % 4]


## A planet's silly name from its seed (two syllables: "ZOOBLIP").
static func planet_name(seed_value: int) -> String:
	var r := Seeded.rng(seed_value, "name")
	var a := r.randi() % SYLLABLES.size()
	var b := (a + 1 + r.randi() % (SYLLABLES.size() - 1)) % SYLLABLES.size()
	return SYLLABLES[a] + SYLLABLES[b]


## Station parts built after this many trips home.
static func parts_for(trips: int) -> int:
	return clampi(trips, 0, PARTS.size())


static func pick(r: RandomNumberGenerator, key: String) -> String:
	var v: Variant = LINES.get(key, "")
	if v is Array:
		return String(Seeded.pick(r, v))
	return String(v)


## Story rules the tests check.
static func self_check() -> Array:
	var why: Array = []
	for i in MISSIONS:
		var m: Dictionary = trip(0, 5, true)[i]
		if String(m.k) != LESSONS[i] or int(m.tier) != 0:
			why.append("the first trip isn't the lessons")
	var t1 := trip(1, 5, true, "2026-10-29")
	if not bool(t1[0].daily) or bool(t1[1].daily):
		why.append("TODAY'S MISSION doesn't open the day's first trip")
	if String(t1[MISSIONS - 1].k) != "home" or int(t1[MISSIONS - 1].planet) != -1:
		why.append("a trip doesn't end at home")
	var kinds := {}
	for i in MISSIONS - 1:
		kinds[String(trip(3, 5, false)[i].k)] = true
	if kinds.size() != MISSIONS - 1:
		why.append("a trip repeats a mission kind")
	if var_to_str(trip(3, 5, false)) == var_to_str(trip(4, 5, false)):
		why.append("two trips are the same")
	if tier_for(1) != 1 or tier_for(99) != MissionGen.TIERS - 1:
		why.append("tiers don't rise (or run past the last)")
	if parts_for(0) != 0 or parts_for(1) != 1 or parts_for(999) != PARTS.size():
		why.append("parts_for is off")
	var names := {}
	for s in 200:
		var n := planet_name(s * 31 + 7)
		names[n] = true
		if n.length() > 9:
			why.append("planet name too long: %s" % n)
	if names.size() < 100:
		why.append("planet names repeat too much (%d of 200)" % names.size())
	for key in LINES:
		var v: Variant = LINES[key]
		for line in (v if v is Array else [v]):
			if String(line).length() > 24:
				why.append("line too long: %s" % line)
	for p in PARTS:
		if String(p.line).length() > 24:
			why.append("part line too long: %s" % p.line)
	return why
