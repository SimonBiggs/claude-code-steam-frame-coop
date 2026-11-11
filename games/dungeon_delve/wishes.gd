extends RefCounted
## CINDER'S WISH (Dungeon Delve, BRAVE / HEROIC / daily floors). Every floor Cinder wishes for one thing, shown
## as a picture and a number next to the floor name (no reading needed):
##   eye     find the hidden room          bag x3  open 3 chests          lock   open the switch door
##   heart   nobody knocked out this floor sword x12 bop 12 monsters
## Keep the wish: everyone gets a heart back and Cinder's hoard gets a gold pile; the family's kept wishes are
## saved (deep.wishes) and count in the Trophy Hall. A "heart" wish is kept on leaving the floor with nobody
## knocked out, and lost the moment anyone is.
## pick() is seeded by the floor (the same wish on every machine) and only wishes what this floor makes
## possible; problem() is the validator (tests/dungeon_delve_wish_test.gd runs it over many seeds and floors).

const FloorGen := preload("res://games/dungeon_delve/floorgen.gd")

## id -> picture (UiKit icon), its colour (UiKit.NAMED) and the tally key in deep.gd that counts it.
const KINDS := {
	"secret": {"icon": "eye", "color": "magic", "tally": "secrets"},
	"chests": {"icon": "bag", "color": "gold", "tally": "chests"},
	"puzzle": {"icon": "lock", "color": "accent", "tally": "puzzles"},
	"safe": {"icon": "heart", "color": "hp", "tally": "downs"},
	"bops": {"icon": "sword", "color": "text", "tally": "kills"},
}
const MAX_CHESTS := 3
const BOPS_SHARE := 0.6  ## of the monsters placed on the floor (bigger parties get extra ones: easier, never harder)
const MIN_BOPS := 5


## What this floor could wish for: id -> how many (only things the floor really has, reachable from the start).
static func options(f: Dictionary) -> Dictionary:
	var out := {}
	if f.is_empty() or String(f.get("kind", "floor")) == "shop":
		return out
	var reach := FloorGen.solve(f)
	var rooms: Array = f["rooms"]
	var chests := 0
	for c in FloorGen.chest_list(f):
		if reach.has(int((c as Array)[0])) and String(((rooms[int((c as Array)[0])]) as Dictionary)["role"]) != "boss":
			chests += 1
	var mons := 0
	var secret := false
	for i in rooms.size():
		var r: Dictionary = rooms[i]
		if not reach.has(i):
			continue
		if String(r["role"]) == "secret":
			secret = true
		for fo in r["foes"]:
			if int((fo as Array)[0]) < FloorGen.B_SLIME:  # bosses don't count (the enum lists them after the monsters)
				mons += 1
	var puzzle := false
	for d in f["doors"]:
		if int((d as Dictionary)["type"]) == FloorGen.PUZZLE and reach.has(int((d as Dictionary)["a"])) and reach.has(int((d as Dictionary)["b"])):
			puzzle = true
	if secret:
		out["secret"] = 1
	if chests >= 2:
		out["chests"] = mini(MAX_CHESTS, chests)
	if puzzle:
		out["puzzle"] = 1
	if int(mons * BOPS_SHARE) >= MIN_BOPS:
		out["bops"] = int(mons * BOPS_SHARE)
	out["safe"] = 1
	return out


## This floor's wish: {"id", "n"} ({} for a shop camp). Seeded: every machine picks the same one.
static func pick(f: Dictionary) -> Dictionary:
	var opts := options(f)
	if opts.is_empty():
		return {}
	var ids: Array = opts.keys()
	ids.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(f.get("seed", 0)), int(f.get("zone", 0)), int(f.get("floor", 0)), "wish"])
	# The heart wish is the hard one: rarer, but the boss floor always gets it (beat the boss with nobody out!).
	if FloorGen.is_boss_floor(int(f.get("floor", 0))):
		return {"id": "safe", "n": 1}
	var weights := {"secret": 3.0, "chests": 3.0, "puzzle": 2.0, "bops": 3.0, "safe": 1.0}
	var total := 0.0
	for id in ids:
		total += float(weights[id])
	var x := rng.randf() * total
	for id in ids:
		x -= float(weights[id])
		if x <= 0.0:
			return {"id": String(id), "n": int(opts[id])}
	return {"id": String(ids.back()), "n": int(opts[ids.back()])}


## "" when the wish w is fair on floor f, else what's wrong (the validator).
static func problem(f: Dictionary, w: Dictionary) -> String:
	if String(f.get("kind", "floor")) == "shop":
		return "" if w.is_empty() else "a wish in the shop camp"
	if w.is_empty():
		return "no wish on a dungeon floor"
	var id := String(w.get("id", ""))
	if not KINDS.has(id):
		return "unknown wish " + id
	var opts := options(f)
	if not opts.has(id):
		return "wish %s is impossible on this floor" % id
	if int(w.get("n", 0)) < 1 or int(w.get("n", 0)) > int(opts[id]):
		return "wish %s wants %d (the floor has %d)" % [id, int(w.get("n", 0)), int(opts[id])]
	if w != pick(f):
		return "the wish isn't the same every time (machines would disagree)"
	return ""
