extends RefCounted
## CINDER'S LOST FRIENDS (Dungeon Delve, BRAVE / HEROIC / daily floors). Each biome has three little friends who got
## lost in the dungeon. On some floors one sits in a gold CAGE in a fight room (the cage glows; a pulsing ring round it).
## Clear the room, then bonk the cage (or touch it, VR knight): the friend hops out, says thank you on a story card,
## everyone gets a heart back and Cinder's hoard a little pile. Friends found go home to CINDER'S CAMP for good (saved
## as deep.friends): at every camp between floors they sit round the campfire and each one brings the party a coin.
## pick() is seeded by the floor (every machine puts the same friend in the same cage) and only uses rooms you can
## reach (FloorGen.solve), on walkable floor clear of pillars, traps, biome hazards, chests, pots, keys and switches;
## problem() is the validator (tests/dungeon_delve_friends_test.gd runs it over many seeds, floors and 400+ days).

const FloorGen := preload("res://games/dungeon_delve/floorgen.gd")
const WarnRings := preload("res://core/warn_rings.gd")

## Biome id -> its three friends: id, NAME (story card), creature kind (core/creatures.gd) and colour.
const BY_ZONE := {
	"caves": [{"id": "pip", "name": "PIP", "kind": "frog", "color": Color(0.55, 0.9, 0.35)},
		{"id": "moss", "name": "MOSS", "kind": "mushroom", "color": Color(1.0, 0.45, 0.4)},
		{"id": "bun", "name": "BUN", "kind": "bunny", "color": Color(1.0, 0.95, 0.9)}],
	"crypt": [{"id": "whisk", "name": "WHISK", "kind": "cat", "color": Color(1.0, 0.7, 0.35)},
		{"id": "patch", "name": "PATCH", "kind": "dog", "color": Color(0.85, 0.65, 0.45)},
		{"id": "squeak", "name": "SQUEAK", "kind": "pig", "color": Color(1.0, 0.72, 0.78)}],
	"crystal": [{"id": "glim", "name": "GLIM", "kind": "penguin", "color": Color(0.95, 0.97, 1.0)},
		{"id": "nip", "name": "NIP", "kind": "crab", "color": Color(1.0, 0.45, 0.3)},
		{"id": "fizz", "name": "FIZZ", "kind": "bee", "color": Color(1.0, 0.85, 0.25)}],
	"forge": [{"id": "rusty", "name": "RUSTY", "kind": "fox", "color": Color(1.0, 0.55, 0.2)},
		{"id": "cog", "name": "COG", "kind": "robot", "color": Color(0.7, 0.85, 1.0)},
		{"id": "puff", "name": "PUFF", "kind": "sheep", "color": Color(0.97, 0.96, 0.92)}],
}
const CAGE_COLOR := Color(1.0, 0.8, 0.3)  ## gold bars (palette.gd: seen on every zone's floor)
const CHANCE := 0.55  ## a friend on floors 1 and 3 of a biome; floor 2 always has one; never the boss floor
const CAGE_R := 0.55  ## the cage's radius (not solid: kept clear of walls and pillars so you can walk all round it)
const CLEAR := 1.3  ## the cage keeps this far from chests, pots, keys, switches, stairs and doors
const HOARD := 10  ## a freed friend adds this (x biome) to Cinder's hoard
const CAMP_SPOTS: Array[Vector2] = [  ## where friends sit at the camp (room-local; round the campfire at (-3.2, 2.8), then the walls)
	Vector2(-2.0, 2.6), Vector2(-2.3, 3.8), Vector2(-3.4, 4.3), Vector2(-4.5, 3.6), Vector2(-4.5, 2.2), Vector2(-3.6, 1.6),
	Vector2(-4.7, 0.2), Vector2(-4.7, -1.1), Vector2(-4.7, -2.4), Vector2(4.7, 0.2), Vector2(4.7, -1.1), Vector2(4.7, -2.4)]


## Every friend, in a fixed order (biome by biome).
static func all() -> Array:
	var out: Array = []
	for z in FloorGen.ZONES:
		out.append_array(BY_ZONE[String((z as Dictionary)["id"])])
	return out


static func info(id: String) -> Dictionary:
	for fr in all():
		if String((fr as Dictionary)["id"]) == id:
			return fr
	return {}


## This floor's caged friend: {"id", "room", "p": Vector2 room-local} or {} (none here). Seeded.
static func pick(f: Dictionary) -> Dictionary:
	if f.is_empty() or String(f.get("kind", "floor")) != "floor":
		return {}
	var fl := int(f.get("floor", 0))
	if FloorGen.is_boss_floor(fl):
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(f.get("seed", 0)), int(f.get("zone", 0)), fl, "friend"])
	if fl != 1 and rng.randf() >= CHANCE:
		return {}
	var friends: Array = BY_ZONE[String(FloorGen.zone_data(int(f.get("zone", 0)))["id"])]
	var fr: Dictionary = friends[rng.randi_range(0, friends.size() - 1)]
	var reach := FloorGen.solve(f)
	var rooms: Array = f["rooms"]
	var cands: Array = []
	for i in rooms.size():
		if reach.has(i) and String((rooms[i] as Dictionary)["role"]) in ["fight", "treasure"]:
			cands.append(i)
	# The deepest rooms first (a friend is something to explore for), ties by room number.
	cands.sort_custom(func(a: int, b: int) -> bool:
		var da := int((rooms[a] as Dictionary)["depth"])
		var db := int((rooms[b] as Dictionary)["depth"])
		return da > db or (da == db and a < b))
	for ri in cands:
		for t in 24:
			var p := Vector2(rng.randf_range(-3.4, 3.4), rng.randf_range(-3.4, 3.4))
			if spot_problem(f, int(ri), p) == "":
				return {"id": String(fr["id"]), "room": int(ri), "p": p}
	return {}


## "" when a cage at room-local p in room ri is fine, else why not.
static func spot_problem(f: Dictionary, ri: int, p: Vector2) -> String:
	var r: Dictionary = (f["rooms"] as Array)[ri]
	if absf(p.x) > FloorGen.HALF - 1.2 or absf(p.y) > FloorGen.HALF - 1.2:
		return "too near a wall"
	var w := FloorGen.to_world(f, ri, p)
	if not FloorGen.walkable(FloorGen.walk_rects(f, -1), FloorGen.obstacle_rects(f), w, CAGE_R + 0.2):
		return "in a pillar"
	var near: Array = []
	for ch in r["chests"]:
		near.append((ch as Array)[0])
	near.append_array(r["pots"])
	if r.has("key_at"):
		near.append(r["key_at"])
	if r.has("stairs"):
		near.append(r["stairs"])
	for sid in r["switches"]:
		near.append(((f["switches"] as Array)[int(sid)] as Dictionary)["p"])
	for d in (r["doors"] as Dictionary):
		near.append(FloorGen.door_local(int(d)))
	for q in near:
		if (q as Vector2).distance_to(p) < CLEAR:
			return "too near a chest, pot, key, switch, the stairs or a door"
	for fe in r.get("features", []):
		var fd: Dictionary = fe
		var fp: Vector2 = fd["p"]
		if String(fd["kind"]) == "vents":
			if fp.distance_to(p) < float(FloorGen.FEATURE["vents"]["radius"]) + CAGE_R + 0.6:
				return "on a lava vent"
		else:
			var dv := Vector2(FloorGen.DIRS[int(fd["dir"])])
			if WarnRings.inside("line", Vector3(fp.x, 0, fp.y), Vector3(dv.x, 0, dv.y), Vector2(float(FloorGen.FEATURE["shards"]["len"]), float(FloorGen.FEATURE["shards"]["width"])), Vector3(p.x, 0, p.y), CAGE_R + 0.4):
				return "in a crystal shard lane"
	for ti in r["traps"]:
		if String(((f["traps"] as Array)[int(ti)] as Dictionary)["kind"]) != "":
			return "in a trap room"
	return ""


## "" when c (pick(f)) is a fair caged friend on floor f, else what's wrong (the validator).
static func problem(f: Dictionary, c: Dictionary) -> String:
	if c.is_empty():
		if String(f.get("kind", "floor")) == "floor" and int(f.get("floor", 0)) == 1:
			return "no friend on a biome's 2nd floor (it always has one)"
		return ""
	if String(f.get("kind", "floor")) != "floor":
		return "a caged friend in the camp"
	if FloorGen.is_boss_floor(int(f.get("floor", 0))):
		return "a caged friend on a boss floor"
	var fr := info(String(c.get("id", "")))
	if fr.is_empty():
		return "unknown friend " + String(c.get("id", ""))
	var zid := String(FloorGen.zone_data(int(f.get("zone", 0)))["id"])
	if not (BY_ZONE[zid] as Array).has(fr):
		return "%s isn't lost in the %s" % [String(fr["id"]), zid]
	var ri := int(c.get("room", -1))
	if ri <= 0 or ri >= (f["rooms"] as Array).size():
		return "the cage isn't in a room past the start"
	var role := String(((f["rooms"] as Array)[ri] as Dictionary)["role"])
	if not role in ["fight", "treasure"]:
		return "the cage is in a %s room" % role
	if not FloorGen.solve(f).has(ri):
		return "the cage can't be reached"
	var sp := spot_problem(f, ri, c["p"])
	if sp != "":
		return "the cage is " + sp
	if c != pick(f):
		return "the cage isn't the same every time (machines would disagree)"
	return ""
