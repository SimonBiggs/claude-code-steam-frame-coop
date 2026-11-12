extends RefCounted
## RUMBLY FLOORS (Dungeon Delve, BRAVE / HEROIC / daily): on some floors the ceiling shakes while you fight. Every few
## seconds things fall from above, each one TOLD FIRST by a flashing orange circle on the floor (core/warn_rings.gd via
## deep.gd hazard, WARN seconds) and a rumble with a little shake; then it lands: one heart if you're still in the circle,
## and it bops monsters too. What falls is the biome's own: goo DRIPS in the Slime Caves, ROCKS in the Bone Crypt,
## ICICLES in the Crystal Caves, EMBERS in the Lava Forge. The floor's banner says it (a picture + one word) when you arrive.
## Never on a biome's first floor of the run (depth 1), a boss floor or the camp; never in the boss room.
## on() is seeded by the floor (every machine agrees); problem() is the validator (tests/dungeon_delve_friends_test.gd).

const FloorGen := preload("res://games/dungeon_delve/floorgen.gd")

## Biome id -> what falls: the banner word and its colour (deep.gd draws the falling thing in it).
const LOOKS := {
	"caves": {"word": "DRIPS!", "color": Color(0.5, 1.0, 0.45), "shape": "drip"},
	"crypt": {"word": "ROCKS!", "color": Color(0.62, 0.58, 0.55), "shape": "rock"},
	"crystal": {"word": "ICICLES!", "color": Color(0.7, 0.95, 1.0), "shape": "icicle"},
	"forge": {"word": "EMBERS!", "color": Color(1.0, 0.55, 0.15), "shape": "ember"},
}
const WARN := 1.6  ## seconds the circle flashes before it lands (>= FloorGen.MIN_WARN; tests)
const RADIUS := 0.85
const FIRST := 2.5  ## seconds after a fight starts before the first fall
const PERIOD := Vector2(6.5, 9.0)  ## seconds between falls (random in this range)
const CHANCE := 0.35  ## of floors past the first (the endless depths: ENDLESS_CHANCE)
const ENDLESS_CHANCE := 0.5


static func on(f: Dictionary) -> bool:
	if f.is_empty() or String(f.get("kind", "floor")) != "floor":
		return false
	var z := int(f.get("zone", 0))
	var fl := int(f.get("floor", 0))
	if FloorGen.global_floor(z, fl) == 0 or FloorGen.is_boss_floor(fl):
		return false
	var x := float(absi(hash([int(f.get("seed", 0)), z, fl, "rumble"])) % 1000) / 1000.0
	return x < (ENDLESS_CHANCE if z >= FloorGen.ZONE_COUNT else CHANCE)


static func look(f: Dictionary) -> Dictionary:
	return LOOKS[String(FloorGen.zone_data(int(f.get("zone", 0)))["id"])]


## How many fall at once (deeper = one more).
static func count(f: Dictionary) -> int:
	return 2 if FloorGen.global_floor(int(f.get("zone", 0)), int(f.get("floor", 0))) < 8 else 3


## Can falls come in room ri? (the rooms you fight in; never the boss room or the start)
static func in_room(f: Dictionary, ri: int) -> bool:
	if not on(f) or ri <= 0 or ri >= (f["rooms"] as Array).size():
		return false
	return String(((f["rooms"] as Array)[ri] as Dictionary)["role"]) in ["fight", "trap", "exit"]


## "" when floor f's rumble is fair, else what's wrong.
static func problem(f: Dictionary) -> String:
	if WARN < FloorGen.MIN_WARN:
		return "falls glow for less than %.1f s" % FloorGen.MIN_WARN
	if not on(f):
		return ""
	if String(f.get("kind", "floor")) != "floor":
		return "rumbles in the camp"
	if FloorGen.global_floor(int(f.get("zone", 0)), int(f.get("floor", 0))) == 0:
		return "rumbles on the very first floor"
	if FloorGen.is_boss_floor(int(f.get("floor", 0))):
		return "rumbles on a boss floor"
	var any := false
	for i in (f["rooms"] as Array).size():
		if in_room(f, i):
			any = true
		if in_room(f, i) and String(((f["rooms"] as Array)[i] as Dictionary)["role"]) == "boss":
			return "rumbles in the boss room"
	if not any:
		return "a rumbly floor with no room to rumble in"
	return ""
