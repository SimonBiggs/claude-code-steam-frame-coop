extends RefCounted
## TINY TOWN TYCOON: shared constants and data tables (no state). Every other script preloads this.
##
## World layout (metres, real scale): the town is a 1.2 m island on a garden table, so the VR mayor
## sees it as a tabletop model at arm's length and the TV players drive 4 cm toy vehicles on it.
## The island is a GRID x GRID board of CELL-sized squares; a cell's centre is cell_center(x, z).
## Building meshes are designed in "cell units" (1.0 = one cell, origin at the ground, door +Z) and
## scaled by CELL when drawn.

const GRID := 22
const CELL := 0.055
const TABLE_Y := 0.80  ## table top (metres above the garden lawn)
const SEA_Y := 0.812  ## sea surface on the table
const GROUND_Y := 0.835  ## island grass level
const HALF := GRID * CELL * 0.5
const CENTER := Vector3(0.0, GROUND_Y, 0.0)

# Terrain per cell.
const T_WATER := 0
const T_GRASS := 1
const T_SAND := 2
const T_ROCK := 3

# Transport layer per cell.
const L_NONE := 0
const L_ROAD := 1
const L_RAIL := 2
const L_CROSS := 3  ## road and rail together (level crossing)

# Needs bits (building "needs" flags, shown as icons in the bubbles).
const N_POWER := 1
const N_WATER := 2
const N_ROAD := 4
const N_JOBS := 8
const N_SHOP := 16
const N_FUN := 32
const N_WORKERS := 64
const N_STOCK := 128  ## a consumer's shelves are empty / a producer has nothing to make it from
const N_FIRE := 256

const RESOURCES: Array[String] = ["food", "bread", "wood"]
const RES_NAMES := {"food": "FOOD", "bread": "BREAD", "wood": "WOOD", "bricks": "BRICKS", "people": "PEOPLE"}
const RES_COLORS := {"food": Color(0.55, 0.85, 0.3), "bread": Color(0.95, 0.7, 0.35), "wood": Color(0.7, 0.48, 0.28),
	"bricks": Color(0.85, 0.42, 0.32), "people": Color(0.5, 0.75, 1.0)}

## Town sizes. Reaching a population unlocks the next tier (new buildings + a celebration).
const TIERS: Array[String] = ["HAMLET", "VILLAGE", "TOWN", "CITY"]
const TIER_POP: Array[int] = [0, 15, 40, 80]

## Everything the mayor can place, in tray order. Tools ("tool": true) are painted cell by cell.
## size: footprint (1 = 1x1, 2 = 2x2). cost: coins. tier: unlocked at that town size.
## homes / jobs: residents and workplaces. makes / needs: produced / consumed resource.
## power / water / fun / safety: radius (cells) of the service. mats: construction loads.
const KINDS: Array[String] = ["road", "house", "farm", "shop", "windmill", "water", "park", "bulldozer",
	"bakery", "sawmill", "school", "fire_station", "rail", "station", "landmark", "ferris", "hall"]
const B := {
	"road": {"name": "ROAD", "size": 1, "cost": 0, "tier": 0, "tool": true, "icon": "road",
		"desc": "Hold the trigger and draw roads. They join up by themselves!"},
	"rail": {"name": "RAIL TRACK", "size": 1, "cost": 1, "tier": 2, "tool": true,
		"desc": "Draw train tracks between two stations."},
	"bulldozer": {"name": "BULLDOZER", "size": 1, "cost": 0, "tier": 0, "tool": true,
		"desc": "Hold the trigger and sweep to clear roads and tracks."},
	"house": {"name": "HOUSE", "size": 1, "cost": 10, "tier": 0, "homes": 4, "mats": 1,
		"desc": "Homes for 4 people. Needs power, water and a road."},
	"farm": {"name": "FARM", "size": 2, "cost": 20, "tier": 0, "jobs": 3, "makes": "food", "mats": 2,
		"desc": "Grows FOOD. Trucks take it to shops."},
	"shop": {"name": "SHOP", "size": 1, "cost": 15, "tier": 0, "jobs": 2, "sells": ["food", "bread"], "fun": 4, "mats": 1,
		"desc": "Sells food to homes nearby. Earns coins!"},
	"windmill": {"name": "WINDMILL", "size": 1, "cost": 12, "tier": 0, "power": 5, "mats": 1,
		"desc": "Power for homes nearby."},
	"water": {"name": "WATER TOWER", "size": 1, "cost": 12, "tier": 0, "water": 5, "mats": 1,
		"desc": "Water for homes nearby."},
	"park": {"name": "PARK", "size": 1, "cost": 5, "tier": 0, "fun": 3, "mats": 1,
		"desc": "Trees and a fountain: people nearby are happier."},
	"bakery": {"name": "BAKERY", "size": 1, "cost": 20, "tier": 1, "jobs": 2, "needs": "food", "makes": "bread", "mats": 2,
		"desc": "Bakes BREAD from food. Shops love it!"},
	"sawmill": {"name": "SAWMILL", "size": 2, "cost": 20, "tier": 1, "jobs": 3, "makes": "wood", "mats": 2,
		"desc": "Makes WOOD: cranes build twice as fast with it."},
	"school": {"name": "SCHOOL", "size": 2, "cost": 30, "tier": 1, "jobs": 3, "fun": 5, "mats": 3,
		"desc": "Kids learn here. Families love living nearby."},
	"fire_station": {"name": "FIRE STATION", "size": 1, "cost": 25, "tier": 1, "jobs": 2, "safety": 6, "mats": 2,
		"desc": "Fewer fires nearby. Home of the fire engine."},
	"station": {"name": "TRAIN STATION", "size": 2, "cost": 40, "tier": 2, "jobs": 2, "mats": 3,
		"desc": "Join two stations with rails: trains bring visitors!"},
	"landmark": {"name": "CLOCK TOWER", "size": 2, "cost": 60, "tier": 2, "fun": 8, "mats": 4,
		"desc": "A grand landmark. Everyone is proud of it!"},
	"ferris": {"name": "BIG WHEEL", "size": 2, "cost": 80, "tier": 3, "fun": 10, "jobs": 2, "mats": 4,
		"desc": "A funfair wheel for a real city!"},
	"hall": {"name": "TOWN HALL", "size": 2, "cost": 0, "tier": 99, "jobs": 2, "fun": 2, "mats": 0,
		"desc": "The mayor's office and the builders' yard (BRICKS)."},
}

## The building blocks in the tray (the town hall is placed at the start, not bought).
const TRAY: Array[String] = ["road", "house", "farm", "shop", "windmill", "water", "park", "bulldozer",
	"bakery", "sawmill", "school", "fire_station", "rail", "station", "landmark", "ferris"]

## The vehicles TV players drive (and AI drives when nobody does).
const VEHICLES: Array[String] = ["truck", "bus", "fire", "crane", "police"]
const V := {
	"truck": {"name": "DELIVERY TRUCK", "job": "deliver", "desc": "Carry food, bread and wood to shops.", "color": Color(0.95, 0.55, 0.2)},
	"bus": {"name": "BUS", "job": "bus", "desc": "Pick people up at their homes and take them out.", "color": Color(1.0, 0.82, 0.2)},
	"fire": {"name": "FIRE ENGINE", "job": "fire", "desc": "Rush to fires and splash them out.", "color": Color(0.92, 0.2, 0.18)},
	"crane": {"name": "CONSTRUCTION CRANE", "job": "build", "desc": "Bring bricks to new buildings so they get built.", "color": Color(1.0, 0.72, 0.1)},
	"police": {"name": "POLICE CAR", "job": "help", "desc": "Help out: stray cows, parades and more.", "color": Color(0.25, 0.45, 0.95)},
}
## Vehicles the town always has (AI drives the ones no player picked).
const CORE_FLEET: Array[String] = ["truck", "crane", "bus", "fire"]

## Islands: the campaign (three goals = three stars each) plus free build.
## Goal kinds: pop N, build kind N, train N (stations joined by rail), festival N, deliver N, happy N.
const ISLANDS: Array[Dictionary] = [
	{"id": "meadow", "name": "MEADOW ISLE", "blurb": "Green fields and sunny skies.", "seed": 11, "tree": "tree",
		"grass": Color(0.47, 0.74, 0.33), "grass2": Color(0.42, 0.68, 0.3), "sand": Color(0.93, 0.85, 0.6),
		"rock": Color(0.6, 0.6, 0.62), "sea": Color(0.25, 0.62, 0.85), "shape": 9.3, "rocks": 1, "lakes": 1, "start_coins": 120,
		"goals": [["pop", 20, "", "Reach 20 citizens"], ["build", 1, "bakery", "Open a bakery"], ["pop", 50, "", "Reach 50 citizens"]]},
	{"id": "snowy", "name": "SNOWY HILLS", "blurb": "Cosy cabins and snowy peaks.", "seed": 23, "tree": "pine",
		"grass": Color(0.88, 0.92, 0.97), "grass2": Color(0.82, 0.88, 0.95), "sand": Color(0.75, 0.8, 0.86),
		"rock": Color(0.55, 0.58, 0.66), "sea": Color(0.3, 0.52, 0.72), "shape": 9.6, "rocks": 3, "lakes": 1, "start_coins": 130, "snow": true,
		"goals": [["build", 3, "windmill", "Build 3 windmills"], ["train", 1, "", "Build a train line"], ["pop", 60, "", "Reach 60 citizens"]]},
	{"id": "tropic", "name": "TROPICAL BAY", "blurb": "Palm trees, sunshine and festivals.", "seed": 37, "tree": "palm",
		"grass": Color(0.42, 0.78, 0.4), "grass2": Color(0.36, 0.72, 0.36), "sand": Color(0.98, 0.9, 0.62),
		"rock": Color(0.62, 0.55, 0.48), "sea": Color(0.15, 0.75, 0.82), "shape": 9.0, "rocks": 1, "lakes": 2, "start_coins": 140,
		"goals": [["festival", 1, "", "Hold a festival"], ["build", 1, "landmark", "Build a landmark"], ["pop", 80, "", "Reach 80 citizens"]]},
	{"id": "free", "name": "FREE BUILD", "blurb": "Every building unlocked, coins for days.", "seed": 5, "tree": "tree",
		"grass": Color(0.5, 0.76, 0.36), "grass2": Color(0.45, 0.7, 0.33), "sand": Color(0.94, 0.86, 0.62),
		"rock": Color(0.6, 0.6, 0.62), "sea": Color(0.25, 0.62, 0.85), "shape": 10.2, "rocks": 1, "lakes": 0, "start_coins": 5000, "free": true,
		"goals": []},
]

## Friendly building names (picked from the building id, the same on every machine).
const NAME_PARTS := {
	"house": ["Rose", "Daisy", "Maple", "Honey", "Pebble", "Willow", "Clover", "Puddle", "Acorn", "Bluebell"],
	"farm": ["Sunny", "Happy Cow", "Green Acre", "Buttercup", "Haystack"],
	"shop": ["Corner", "Penny", "Lucky", "Tiny", "Village"],
	"bakery": ["Crusty", "Sweet Bun", "Warm Loaf"],
	"sawmill": ["Timber", "Oak", "Pine"],
	"school": ["Little Owls", "Bright Stars"],
	"fire_station": ["Brave", "Station No."],
	"station": ["Central", "Seaside", "Hilltop"],
	"park": ["Duck Pond", "Picnic", "Sunflower"],
	"windmill": ["Breezy", "Whirly", "Old"],
	"water": ["Splashy", "Blue", "Tall"],
	"landmark": ["Town"],
	"ferris": ["Twinkle"],
	"hall": ["Town"],
}
const NAME_SUFFIX := {
	"house": "Cottage", "farm": "Farm", "shop": "Shop", "bakery": "Bakery", "sawmill": "Sawmill",
	"school": "School", "fire_station": "Fire Station", "station": "Station", "park": "Park",
	"windmill": "Windmill", "water": "Water Tower", "landmark": "Clock Tower", "ferris": "Big Wheel", "hall": "Hall",
}


static func def(kind: String) -> Dictionary:
	return B.get(kind, {})


static func kind_index(kind: String) -> int:
	return KINDS.find(kind)


static func kind_at(i: int) -> String:
	return KINDS[i] if i >= 0 and i < KINDS.size() else ""


static func size_of(kind: String) -> int:
	return int(def(kind).get("size", 1))


static func is_tool_kind(kind: String) -> bool:
	return bool(def(kind).get("tool", false))


static func cost_of(kind: String) -> int:
	return int(def(kind).get("cost", 0))


static func tier_for_pop(pop: int) -> int:
	var t := 0
	for i in TIER_POP.size():
		if pop >= TIER_POP[i]:
			t = i
	return t


static func island(i: int) -> Dictionary:
	return ISLANDS[clampi(i, 0, ISLANDS.size() - 1)]


static func island_index(id: String) -> int:
	for i in ISLANDS.size():
		if String(ISLANDS[i]["id"]) == id:
			return i
	return 0


## World position of a cell's centre (on the grass).
static func cell_center(x: int, z: int) -> Vector3:
	return Vector3(-HALF + (x + 0.5) * CELL, GROUND_Y, -HALF + (z + 0.5) * CELL)


## World position of a building's footprint centre (size 1 or 2 cells, x/z = its min corner).
static func foot_center(x: int, z: int, size: int) -> Vector3:
	return Vector3(-HALF + (x + size * 0.5) * CELL, GROUND_Y, -HALF + (z + size * 0.5) * CELL)


## The cell under a world point (may be outside the grid: check inside()).
static func world_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori((p.x + HALF) / CELL), floori((p.z + HALF) / CELL))


static func inside(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < GRID and z < GRID


## A friendly name for a building ("Daisy Cottage").
static func building_name(kind: String, id: int) -> String:
	var parts: Array = NAME_PARTS.get(kind, ["Little"])
	var first: String = String(parts[(id * 7 + 3) % parts.size()])
	var suffix: String = String(NAME_SUFFIX.get(kind, String(def(kind).get("name", "Place")).capitalize()))
	if kind == "fire_station" and first == "Station No.":
		return "Fire Station No. %d" % (id % 9 + 1)
	return "%s %s" % [first, suffix]


## Quantise a world position for snapshots (half a millimetre steps).
static func q(v: float) -> int:
	return int(round(v * 2000.0))


static func dq(i: int) -> float:
	return float(i) / 2000.0
