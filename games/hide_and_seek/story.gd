extends RefCounted
## HIDE AND SEEK story: PIP, the family's puppy, LOVES hide and seek. Every round Pip hides somewhere on
## the map too (main.gd picks one of the map's hiding spots). Whoever finds Pip first (the seeker with the
## torch or a touch, or a hider who runs into him) gets PIP_POINTS, and Pip brings a new TOY home to his
## kennel in the garden: the toys stay there for good (saved), so the pile grows over the days.
## Toys unlock new house looks (THEMES): seaside, snowy, spooky.
## THE HOUSE is new every visit (housegen.gd, from a seed): more houses explored = bigger houses (four
## rooms wide from house 5), more decoys and Pip hiding further away. The first house each day is
## TODAY'S HOUSE (the same on every machine). Pure data + small functions. Lines are a few words.

const Seeded := preload("res://core/seeded.gd")

const PIP_COLOR := Color(0.95, 0.72, 0.42)
const PIP_POINTS := 20
const GAME_ID := "hide_and_seek"
## Pip's toys, in the order he brings them home: name, colour (map_house.gd draws each by index).
const TOYS: Array = [["BALL", Color(1.0, 0.3, 0.3)], ["BONE", Color(0.98, 0.95, 0.88)], ["DUCK", Color(1.0, 0.85, 0.2)],
	["FRISBEE", Color(0.3, 0.6, 1.0)], ["ROPE", Color(0.9, 0.45, 0.85)], ["SLIPPER", Color(0.6, 0.4, 0.9)],
	["CARROT", Color(1.0, 0.55, 0.15)], ["STAR", Color(1.0, 0.9, 0.3)], ["TEDDY", Color(0.72, 0.48, 0.3)],
	["RING", Color(0.3, 0.85, 0.5)], ["BALL", Color(0.3, 0.75, 1.0)], ["BONE", Color(1.0, 0.8, 0.6)]]
const MAX_TOYS_SHOWN := 24
## House looks: id, name, toys needed, story picture, wall tint (mixed in), garden ground, sky, one line.
const THEMES: Array[Dictionary] = [
	{"id": "cosy", "name": "COSY HOUSE", "need": 0, "pic": "house", "tint": Color(1, 1, 1), "mix": 0.0,
		"ground": Color(0.4, 0.7, 0.32), "sky": Color(0.45, 0.55, 0.8), "line": "A cosy house!"},
	{"id": "seaside", "name": "SEASIDE HOUSE", "need": 3, "pic": "wave", "tint": Color(0.82, 0.94, 1.0), "mix": 0.4,
		"ground": Color(0.95, 0.86, 0.6), "sky": Color(0.5, 0.75, 0.95), "line": "A seaside house!"},
	{"id": "snowy", "name": "SNOWY HOUSE", "need": 6, "pic": "snowman", "tint": Color(0.97, 0.98, 1.0), "mix": 0.45,
		"ground": Color(0.92, 0.95, 1.0), "sky": Color(0.7, 0.78, 0.9), "line": "A snowy house!"},
	{"id": "spooky", "name": "SPOOKY HOUSE", "need": 9, "pic": "pumpkin", "tint": Color(0.62, 0.5, 0.78), "mix": 0.45,
		"ground": Color(0.3, 0.45, 0.28), "sky": Color(0.22, 0.18, 0.35), "line": "A spooky house!"},
]


static func save_defaults() -> Dictionary:
	return {"world": -1, "houses": 0, "toys": 0, "pips": 0, "daily": {}, "best_finds": 0}


static func theme(i: int) -> Dictionary:
	return THEMES[posmod(i, THEMES.size())]


## Themes unlocked with this many toys (indices).
static func unlocked(toys: int) -> Array:
	var out: Array = []
	for i in THEMES.size():
		if toys >= int(THEMES[i].need):
			out.append(i)
	return out


## The theme a new toy count just unlocked (-1 if none).
static func new_theme(toys_before: int, toys_after: int) -> int:
	for i in THEMES.size():
		var need := int(THEMES[i].need)
		if need > 0 and toys_before < need and toys_after >= need:
			return i
	return -1


static func toy(i: int) -> Array:
	return TOYS[posmod(i, TOYS.size())]


## House number n (0-based) of this family's world: {seed, level, theme}. A just-unlocked theme comes first.
static func house_spec(world: int, n: int, toys: int) -> Dictionary:
	var r := Seeded.rng(world, "theme%d" % n)
	var open := unlocked(toys)
	var th: int = open[r.randi() % open.size()]
	if open.size() > 1 and n % 3 == 0:
		th = open[-1]  # the newest look comes round often
	return {"seed": Seeded.derive(world, "house%d" % n), "level": n, "theme": th, "daily": false}


## TODAY'S HOUSE: the same seed and look on every machine all day (a medium-sized house).
static func daily(date: String = "") -> Dictionary:
	var sd := Seeded.daily_seed(GAME_ID, date)
	return {"seed": sd, "level": 3, "theme": Seeded.rng(sd, "theme").randi() % THEMES.size(), "daily": true}


## Rooms across: three, four from the fifth house on.
static func columns(level: int) -> int:
	return 3 if level < 4 else 4


## Decoys per room: a few more as the houses go on.
static func decoys_per_room(level: int) -> int:
	return 2 + mini(level, 6) / 3
