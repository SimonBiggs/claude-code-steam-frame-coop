extends RefCounted
## SHEEP ROUND-UP story: Bo's farm. A storm scattered Bo's sheep over the hills; every field the dogs
## (and the giant farmer) round up brings sheep home for good. Every sheep that reaches a pen joins
## Bo's HOME FIELD (north of the play field, it fills up and stays), new breeds join the farm the first
## time one is rescued, and the farm grows things at milestones (a barn, haystacks, a windmill, a duck
## pond, a big oak). Clearing a field (every sheep home) opens the next, harder field. The first round
## of each day (once the family has cleared a field) is TODAY'S FIELD, the same on every machine.
## Pure rules and words; main.gd plays them, field_view.gd draws them.

const FieldGen := preload("res://games/sheep_round_up/fieldgen.gd")
const Seeded := preload("res://core/seeded.gd")

const BO_COLOR := Color(0.95, 0.45, 0.6)  ## Bo's bonnet (the "shepherd" story picture)
## [sheep at home, thing, picture, Bo's line]
const MILESTONES: Array = [
	[10, "barn", "house", "A red barn! Cosy!"],
	[25, "hay", "sun", "Haystacks! Yum!"],
	[45, "windmill", "cloud", "A windmill! Whoosh!"],
	[70, "pond", "wave", "A duck pond! Quack!"],
	[100, "oak", "tree", "A big oak tree!"],
	[150, "bunting", "star", "Party flags! Hooray!"],
]
const CHEERS: Array[String] = ["All home! Hooray!", "Good dogs!", "Woof woof! Well done!", "What a team!", "Baa-rilliant!"]
## New things a field brings the first time (field level they start at -> Bo's tip).
const TIPS := {1: ["Mind the bushes!", "tree"], 2: ["Hedges! Go round!", "tree"], 3: ["Use the bridges!", "wave"],
	4: ["Some gates are shut!", "house"]}
const HOME_SHOWN := 18  ## sheep drawn in the home field (the sign shows the real number)


static func save_defaults() -> Dictionary:
	return {"best": 0, "level": 0, "home": 0, "breeds": {}, "built": [], "rounds": 0, "world": -1,
		"daily": {}, "stars": {}, "tips": [], "met_bo": false}


## The field a farm is on next: its seed (this family's own fields) and spec.
static func next_field(data: Dictionary, players: int, time: float) -> Dictionary:
	var lv := int(data.get("level", 0))
	return {"k": "story", "seed": Seeded.derive(int(data.get("world", 0)), "f%d/%d" % [lv, int(data.get("rounds", 0))]),
		"spec": FieldGen.spec(lv, players, time)}


## Stars for a cleared field: by how much of the clock was left.
static func stars(all_home: bool, time_left: float, time: float) -> int:
	if not all_home:
		return 0
	var k := time_left / maxf(1.0, time)
	return 3 if k >= 0.4 else (2 if k >= 0.15 else 1)


## Milestones newly reached going from `before` to `after` sheep at home.
static func new_milestones(before: int, after: int) -> Array:
	var out: Array = []
	for m in MILESTONES:
		if before < int(m[0]) and after >= int(m[0]):
			out.append(m)
	return out


## The things built on the farm for a number of sheep at home.
static func built_for(home: int) -> Array:
	var out: Array = []
	for m in MILESTONES:
		if home >= int(m[0]):
			out.append(String(m[1]))
	return out


## The next milestone ([need, thing, pic, line]) or [] when everything is built.
static func next_milestone(home: int) -> Array:
	for m in MILESTONES:
		if home < int(m[0]):
			return m
	return []
