extends RefCounted
## CRYSTAL SAGA's REALM: the family's own seeded overworld map (seed = the save's "world"). Willowbrook sits at
## the bottom; roads lead north to EIGHT REGIONS, each its own biome (BIOMES: a meadow, a wood, a cave, a snowy
## peak, dunes, a fen, a cloud isle, ember hills) with:
##  - a QUEST GIVER waiting at the region's gate with a picture quest (find the lost lambs, light the lanterns,
##    collect the gems ...: a picture and dots, no words needed),
##  - its own monsters (the same hop / walk / flutter moves, dressed for the biome),
##  - a CRYSTAL GUARDIAN at the end (a giant in dark mist) with the region's signature attack, every attack
##    shown first by its own glowing tell (sagagen.gd guardian(): STOMP ring, CRYSTAL RAIN circles, ROLL lane,
##    CALL sparkle rings).
## Regions sit in rows (DEPTHS: 1 = next to home ... 4 = the far north); a region OPENS when a road reaches it
## from home or from a region whose guardian the family has beaten (its crystal brought home). Roads only join
## neighbouring rows, so a newly opened region is never more than one step harder than the hardest one done.
## The journey's tier (sagagen.gd TIERS) comes from the region's row, +1 replaying a beaten region, +1 in
## BRAVE (hard) mode.
## check(realm) is the validator (tests/crystal_saga_gen_test.gd): every region reachable by clearing open
## regions one by one, roads only between neighbouring rows, every biome once, and difficulty climbing
## smoothly along every possible order of play.

const Seeded := preload("res://core/seeded.gd")

const SIZE := 8
const DEPTHS: Array[int] = [1, 2, 2, 3, 3, 3, 4, 4]  ## the row of each map slot (slot 0 = the first region)
const TIERS := 6  ## = sagagen.gd TIERS

## The biomes. name: region name choices (<= 14 letters); deep: the name of its inner place (zone 2);
## giant: the guardian's short name ("%s GIANT!"); pic: a story picture for the region; sky: SkyKit presets
## (outside, inside); path: ground colours (zone 1, zone 2); leaf / gem: tints; skins: [hopper, walker, flyer]
## Creatures monster kinds; quest: [giver name, giver picture, giver look (Creatures class), item kind, item
## picture]; sig: the guardian's signature attack; body / glow: the guardian's colours.
const BIOMES: Array[Dictionary] = [
	{"id": "meadow", "ground": Color(0.45, 0.72, 0.32), "name": ["BUNNY MEADOW", "CLOVER FIELDS", "DAISY DOWNS"], "deep": ["BURROW CAVE", "ROOT CAVE"],
		"giant": "CLOVER", "pic": "sunflower", "sky": ["day", "dungeon"], "path": [Color(0.66, 0.6, 0.36), Color(0.45, 0.38, 0.3)],
		"leaf": Color(0.85, 1.0, 0.7), "gem": Color(0.6, 1.0, 0.6), "skins": ["slime", "mushroom", "bee"],
		"quest": ["SHEPHERD", "shepherd", "farmer", "sheep", "sheep"], "sig": "stomp",
		"body": Color(0.45, 0.6, 0.38), "glow": Color(0.7, 1.0, 0.45)},
	{"id": "wood", "ground": Color(0.3, 0.52, 0.26), "name": ["WHISPER WOOD", "OWL WOOD", "FERN FOREST"], "deep": ["HOLLOW CAVE", "MOSS CAVE"],
		"giant": "MOSS", "pic": "tree", "sky": ["dawn", "dungeon"], "path": [Color(0.6, 0.5, 0.34), Color(0.38, 0.36, 0.48)],
		"leaf": Color(0.8, 1.0, 0.8), "gem": Color(0.5, 1.0, 0.75), "skins": ["slime", "mushroom", "bat"],
		"quest": ["GRANNY OAK", "granny", "villager", "lantern", "lantern"], "sig": "call",
		"body": Color(0.4, 0.55, 0.38), "glow": Color(0.6, 1.0, 0.4)},
	{"id": "cave", "ground": Color(0.42, 0.5, 0.4), "name": ["GLITTER CAVE", "ECHO HILLS", "GEM VALLEY"], "deep": ["GEM TUNNEL", "STAR CAVERN"],
		"giant": "STONE", "pic": "shard", "sky": ["dawn", "dungeon"], "path": [Color(0.55, 0.52, 0.5), Color(0.38, 0.36, 0.48)],
		"leaf": Color(1.0, 0.85, 1.0), "gem": Color(0.5, 0.85, 1.0), "skins": ["slime", "spider", "bat"],
		"quest": ["GNOME GIL", "gnome", "scientist", "gem", "shard"], "sig": "rain",
		"body": Color(0.5, 0.45, 0.6), "glow": Color(0.8, 0.4, 1.0)},
	{"id": "snow", "ground": Color(0.9, 0.93, 0.97), "name": ["FROSTY PEAK", "SNOWY HILLS", "ICICLE VALE"], "deep": ["ICE CAVE", "FROST TUNNEL"],
		"giant": "SNOW", "pic": "snowflake", "sky": ["snowy", "dungeon"], "path": [Color(0.86, 0.9, 0.95), Color(0.6, 0.7, 0.85)],
		"leaf": Color(0.9, 0.95, 1.0), "gem": Color(0.6, 0.9, 1.0), "skins": ["slime", "penguin", "bird"],
		"quest": ["POLAR POP", "polarbear", "farmer", "penguin", "penguin"], "sig": "roll",
		"body": Color(0.8, 0.85, 0.95), "glow": Color(0.5, 0.8, 1.0)},
	{"id": "dunes", "ground": Color(0.9, 0.78, 0.5), "name": ["SUNNY DUNES", "GOLDEN SANDS", "SANDY SHORE"], "deep": ["SAND TOMB", "SUN TEMPLE"],
		"giant": "SAND", "pic": "sun", "sky": ["sunset", "indoor"], "path": [Color(0.92, 0.8, 0.52), Color(0.7, 0.58, 0.4)],
		"leaf": Color(1.0, 0.9, 0.6), "gem": Color(1.0, 0.75, 0.45), "skins": ["slime", "crab", "bird"],
		"quest": ["CAPTAIN", "captain", "pirate", "star", "starfish"], "sig": "roll",
		"body": Color(0.78, 0.66, 0.45), "glow": Color(1.0, 0.75, 0.3)},
	{"id": "fen", "ground": Color(0.33, 0.45, 0.3), "name": ["FROGGY FEN", "MISTY MARSH", "LILY BOG"], "deep": ["MUD BURROW", "GLOOM CAVE"],
		"giant": "BOG", "pic": "frog", "sky": ["spooky", "dungeon"], "path": [Color(0.45, 0.5, 0.35), Color(0.32, 0.36, 0.3)],
		"leaf": Color(0.75, 0.95, 0.75), "gem": Color(0.6, 1.0, 0.7), "skins": ["frog", "mushroom", "ghost"],
		"quest": ["MOSSY MAGE", "wizard", "mage", "frog", "frog"], "sig": "call",
		"body": Color(0.35, 0.45, 0.35), "glow": Color(0.5, 1.0, 0.6)},
	{"id": "cloud", "ground": Color(0.85, 0.9, 1.0), "name": ["CLOUD ISLE", "STAR HEIGHTS", "SKY GARDEN"], "deep": ["STORM CAVE", "WIND TUNNEL"],
		"giant": "CLOUD", "pic": "cloud", "sky": ["day", "stormy"], "path": [Color(0.92, 0.94, 1.0), Color(0.68, 0.7, 0.85)],
		"leaf": Color(1.0, 0.95, 1.0), "gem": Color(1.0, 0.95, 0.6), "skins": ["slime", "mushroom", "bird"],
		"quest": ["SKY BIRD", "bird", "bard", "balloon", "balloon"], "sig": "rain",
		"body": Color(0.85, 0.85, 0.95), "glow": Color(1.0, 0.95, 0.5)},
	{"id": "ember", "ground": Color(0.45, 0.3, 0.27), "name": ["EMBER HILLS", "LAVA PEAK", "SMOKY RIDGE"], "deep": ["LAVA TUNNEL", "FIRE CAVE"],
		"giant": "EMBER", "pic": "fireball", "sky": ["sunset", "dungeon"], "path": [Color(0.5, 0.36, 0.32), Color(0.36, 0.26, 0.28)],
		"leaf": Color(1.0, 0.8, 0.6), "gem": Color(1.0, 0.55, 0.35), "skins": ["slime", "goblin", "dragon"],
		"quest": ["BABY DRAGON", "dragon", "healer", "bell", "bell"], "sig": "roll",
		"body": Color(0.7, 0.42, 0.32), "glow": Color(1.0, 0.55, 0.35)},
]
const QUEST_NEED := 3  ## things to find (one more is hidden as a spare in gentle mode)


## The family's map: {"seed", "regions": [{"biome", "name", "depth", "x", "links": [slots]}...]}. Slot 0 (the
## first region, row 1) is always the meadow; the rest of the biomes are shuffled into rows 2..4.
static func generate(seed_value: int) -> Dictionary:
	var r := Seeded.rng(seed_value, "realm")
	var rest: Array = Seeded.shuffled(r, [1, 2, 3, 4, 5, 6, 7])
	var biomes: Array = [0] + rest
	var regions: Array = []
	var row_n := {}
	for d in DEPTHS:
		row_n[d] = int(row_n.get(d, 0)) + 1
	var row_i := {}
	for i in SIZE:
		var d: int = DEPTHS[i]
		var k := int(row_i.get(d, 0))
		row_i[d] = k + 1
		var n: int = row_n[d]
		var x := 0.0 if n == 1 else lerpf(-0.8, 0.8, float(k) / float(n - 1)) + r.randf_range(-0.1, 0.1)
		var b: Dictionary = BIOMES[int(biomes[i])]
		var names: Array = b.name
		regions.append({"biome": int(biomes[i]), "name": String(names[r.randi() % names.size()]), "depth": d,
			"x": snappedf(x, 0.01), "links": []})
	# Roads: each region of row d > 1 joins the nearest one or two of row d - 1 (by x); sometimes a road
	# along the row too.
	for i in SIZE:
		var d: int = regions[i].depth
		if d == 1:
			continue
		var below: Array = []
		for j in SIZE:
			if int(regions[j].depth) == d - 1:
				below.append(j)
		below.sort_custom(func(a: int, c: int) -> bool:
			return absf(float(regions[a].x) - float(regions[i].x)) < absf(float(regions[c].x) - float(regions[i].x)))
		_link(regions, i, int(below[0]))
		if below.size() > 1 and r.randf() < 0.45:
			_link(regions, i, int(below[1]))
	for i in SIZE - 1:
		if int(regions[i].depth) == int(regions[i + 1].depth) and int(regions[i].depth) > 1 and r.randf() < 0.3:
			_link(regions, i, i + 1)
	return {"seed": seed_value, "regions": regions}


static func _link(regions: Array, a: int, b: int) -> void:
	if not (regions[a].links as Array).has(b):
		(regions[a].links as Array).append(b)
	if not (regions[b].links as Array).has(a):
		(regions[b].links as Array).append(a)


static func biome(realm: Dictionary, slot: int) -> Dictionary:
	return BIOMES[int(realm.regions[clampi(slot, 0, SIZE - 1)].biome)]


## Is a region open (a road reaches it from home or from a beaten region)? cleared: slots beaten.
static func is_open(realm: Dictionary, slot: int, cleared: Array) -> bool:
	if slot < 0 or slot >= SIZE:
		return false
	if int(realm.regions[slot].depth) == 1 or cleared.has(slot):
		return true
	for j in realm.regions[slot].links:
		if cleared.has(int(j)):
			return true
	return false


static func open_slots(realm: Dictionary, cleared: Array) -> Array:
	var out: Array = []
	for i in SIZE:
		if is_open(realm, i, cleared):
			out.append(i)
	return out


## The journey's tier for a region: its row, +1 replaying a beaten one, +1 brave.
static func tier_of(realm: Dictionary, slot: int, cleared: Array, hard: bool) -> int:
	var t := int(realm.regions[slot].depth) - 1
	if cleared.has(slot):
		t += 1
	if hard:
		t += 1
	return clampi(t, 0, TIERS - 1)


## Where the family might go next (the stones on the village's map): new regions first (nearest row first), then
## beaten ones to replay; at most `n`. The first is the one Lumi suggests.
static func choices(realm: Dictionary, cleared: Array, n: int = 3) -> Array:
	var fresh: Array = []
	var again: Array = []
	for i in open_slots(realm, cleared):
		if cleared.has(i):
			again.append(i)
		else:
			fresh.append(i)
	fresh.sort_custom(func(a: int, b: int) -> bool: return int(realm.regions[a].depth) < int(realm.regions[b].depth) or (int(realm.regions[a].depth) == int(realm.regions[b].depth) and a < b))
	again.sort_custom(func(a: int, b: int) -> bool: return int(realm.regions[a].depth) > int(realm.regions[b].depth) or (int(realm.regions[a].depth) == int(realm.regions[b].depth) and a < b))
	var out: Array = fresh + again
	return out.slice(0, n)


## TODAY'S QUEST's region: the same for the whole day (picked by the day's seed among the open ones).
static func daily_slot(realm: Dictionary, cleared: Array, day_seed: int) -> int:
	var open := open_slots(realm, cleared)
	return int(open[absi(day_seed) % open.size()])


# --- The validator ------------------------------------------------------------------------------------

## Everything wrong with a realm (empty = fine).
static func check(realm: Dictionary) -> Array:
	var why: Array = []
	var regions: Array = realm.regions
	if regions.size() != SIZE:
		return ["the realm has %d regions" % regions.size()]
	var seen := {}
	for i in SIZE:
		var g: Dictionary = regions[i]
		seen[int(g.biome)] = true
		if String(g.name).length() > 14 or String(g.name) == "":
			why.append("region %d's name '%s' doesn't fit" % [i, g.name])
		if absf(float(g.x)) > 1.0:
			why.append("region %d is off the map (x %.2f)" % [i, float(g.x)])
		for j in g.links:
			if absi(int(regions[int(j)].depth) - int(g.depth)) > 1:
				why.append("a road jumps rows: %d (row %d) to %d (row %d)" % [i, int(g.depth), int(j), int(regions[int(j)].depth)])
			if not (regions[int(j)].links as Array).has(i):
				why.append("the road %d-%d only goes one way" % [i, int(j)])
	if seen.size() != SIZE:
		why.append("biomes repeat (%d different)" % seen.size())
	if int(regions[0].biome) != 0 or int(regions[0].depth) != 1:
		why.append("the first region isn't the meadow next to home")
	# Every region reachable: clear open regions one by one until nothing new opens.
	var cleared: Array = []
	var guard := 0
	while guard < SIZE * 2:
		guard += 1
		var next := -1
		for i in open_slots(realm, cleared):
			if not cleared.has(i):
				next = i
				break
		if next < 0:
			break
		cleared.append(next)
	if cleared.size() != SIZE:
		var lost: Array = []
		for i in SIZE:
			if not cleared.has(i):
				lost.append(i)
		why.append("regions %s can never be reached" % str(lost))
	why.append_array(_check_climb(realm))
	return why


## Difficulty climbs smoothly along every order of play: each new region's tier is at most one above the
## hardest tier played so far, never below the first, and tiers fit TIERS (gentle and brave).
static func _check_climb(realm: Dictionary) -> Array:
	var why: Array = []
	for hard in [false, true]:
		var orders := 0
		var stack: Array = [[]]
		while not stack.is_empty() and orders < 400:
			var cleared: Array = stack.pop_back()
			var fresh: Array = []
			for i in open_slots(realm, cleared):
				if not cleared.has(i):
					fresh.append(i)
			if fresh.is_empty():
				orders += 1
				continue
			var top := -1
			for c in cleared:
				top = maxi(top, tier_of(realm, int(c), [], hard))
			for i in fresh:
				var t := tier_of(realm, int(i), cleared, hard)
				if top >= 0 and t > top + 1:
					why.append("%s: after %s, region %d jumps to tier %d (hardest so far %d)" % ["brave" if hard else "gentle", str(cleared), int(i), t, top])
					return why
				stack.append(cleared + [i])
		if orders == 0:
			why.append("no way through the realm")
	return why


## The order a family clears the realm if it always takes the first open region (for tests and old saves).
static func clear_order(realm: Dictionary, n: int = SIZE) -> Array:
	var cleared: Array = []
	while cleared.size() < mini(n, SIZE):
		var next := -1
		for i in open_slots(realm, cleared):
			if not cleared.has(i):
				next = i
				break
		if next < 0:
			break
		cleared.append(next)
	return cleared
