extends RefCounted
## TREASURE DIG story: CAPTAIN PEG, a friendly pirate, lost her treasures on the islands of her map.
## Every round is a new island (islandgen.gd, from a seed). Before it, the team picks WHICH island from
## two signposts on the sand (dig at one / poke it): each kind of island has its own look and its own
## mix - JUNGLE has more gems but more boots, ICE has the shiniest gems, VOLCANO the biggest relics.
## On every island three MAP PIECES are buried among the coins; carry all three to the chest and a big
## red X appears: dig there for Peg's RELIC (worth 10). Each relic found stays on the pedestals round the
## island for good (saved: Peg's collection grows over the days). More islands = more silly boots and
## the map pieces deeper in the pile. The first island each day is TODAY'S ISLAND (the same everywhere).
## Pure data + small functions. Lines are a few words (kids read them).

const Seeded := preload("res://core/seeded.gd")

const PEG_COLOR := Color(0.95, 0.35, 0.35)
const KIND_COIN := 0
const KIND_GEM := 1
const KIND_BOOT := 2
const KIND_MAP := 3
const KIND_RELIC := 4
const VALUES: Array[int] = [1, 3, 1, 0, 10]
## Island kinds: name, story picture, sand / rim colours, palm count, chances (coin, gem, boot), relics.
const ISLANDS: Array[Dictionary] = [
	{"id": "sunny", "name": "SUNNY ISLE", "pic": "sun", "sand": Color(0.98, 0.87, 0.6), "rim": Color(0.85, 0.72, 0.48),
		"sky": "day", "palms": 5, "mix": [0.62, 0.22, 0.16], "line": "Sunny island!"},
	{"id": "jungle", "name": "JUNGLE ISLE", "pic": "tree", "sand": Color(0.75, 0.82, 0.5), "rim": Color(0.55, 0.65, 0.38),
		"sky": "day", "palms": 8, "mix": [0.4, 0.35, 0.25], "line": "Jungle island!"},
	{"id": "ice", "name": "ICE ISLE", "pic": "snowman", "sand": Color(0.9, 0.95, 1.0), "rim": Color(0.7, 0.8, 0.92),
		"sky": "day", "palms": 2, "mix": [0.5, 0.35, 0.15], "line": "Brrr! Ice island!"},
	{"id": "volcano", "name": "VOLCANO ISLE", "pic": "storm", "sand": Color(0.6, 0.5, 0.45), "rim": Color(0.4, 0.33, 0.3),
		"sky": "sunset", "palms": 3, "mix": [0.5, 0.25, 0.25], "line": "Hot hot hot!"},
]
## Peg's relics (in the order they're found): name, colour (props.gd draws each).
const RELICS: Array = [["GOLDEN DUCK", Color(1.0, 0.82, 0.2)], ["CROWN", Color(1.0, 0.75, 0.15)], ["SHIP", Color(0.6, 0.4, 0.25)],
	["COMPASS", Color(0.85, 0.7, 0.35)], ["PEARL", Color(0.95, 0.95, 1.0)], ["TEAPOT", Color(0.5, 0.8, 1.0)],
	["PARROT", Color(0.3, 0.85, 0.35)], ["RUBY", Color(0.95, 0.15, 0.3)], ["TRUMPET", Color(1.0, 0.85, 0.35)],
	["STAR", Color(1.0, 0.95, 0.4)]]
const MAP_PIECES := 3


static func save_defaults() -> Dictionary:
	return {"best": 0, "world": -1, "islands": 0, "relics": [], "daily": {}, "visits": {}}


static func island(i: int) -> Dictionary:
	return ISLANDS[posmod(i, ISLANDS.size())]


static func island_index(id: String) -> int:
	for i in ISLANDS.size():
		if ISLANDS[i].id == id:
			return i
	return 0


## The two signposts before island n (n >= 1): two different kinds, the least visited first.
static func offers(world: int, n: int, visits: Dictionary) -> Array:
	var r := Seeded.rng(world, "offers%d" % n)
	var ids: Array = []
	for isl in ISLANDS:
		ids.append(isl.id)
	ids = Seeded.shuffled(r, ids)
	ids.sort_custom(func(a: String, b: String) -> bool: return int(visits.get(a, 0)) < int(visits.get(b, 0)))
	return ids.slice(0, 2)


## The next relic to find (cycles once every relic is home).
static func next_relic(found: Array) -> int:
	for i in RELICS.size():
		if not found.has(i):
			return i
	return found.size() % RELICS.size()


## TODAY'S ISLAND: the island kind and seed for today (the same on every machine).
static func daily(date: String = "") -> Array:
	var sd := Seeded.daily_seed("treasure_dig", date)
	return [sd, ISLANDS[Seeded.rng(sd, "kind").randi() % ISLANDS.size()].id]
