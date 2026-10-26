extends RefCounted
## MARBLE MAZE story and progression: BOBO, a friendly little monster, looks after the shiny marbles of
## MARBLE TOWN (the toy town round the table). Bobo tripped and the shiny marbles rolled away into the
## mazes! After the seven lesson mazes, the STORY goes place by place: three seeded mazes per place,
## and finishing a place's third maze lights that place up in Marble Town (it stays, saved). Every
## story maze hides one SHINY marble off the way (a detour: grab it or not); shinies go in the big jar
## by the table and stay there (the collection: each one has its own colour and name). After the seven
## places: BONUS places, round again, each a little harder (narrower rooms, more holes, fewer loops).
## The first maze of each day is TODAY'S MAZE (the same maze on every machine that day; a golden
## shiny). Lines are a few words (kids read them; simple mode, picture first).
## Pure data + small pure functions (no nodes), so tests and every machine agree.

const MazeGen := preload("res://games/marble_maze/mazegen.gd")
const Seeded := preload("res://core/seeded.gd")

const MAZES_PER_PLACE := 3
const BOBO_COLOR := Color(0.72, 0.5, 1.0)

## place: shown name. pic: core/story_card.gd picture or core/ui_kit.gd icon. tile: the new thing this
## place brings (it sparkles in the first maze's intro). spec: core of the mazegen spec.
const PLACES: Array[Dictionary] = [
	{"name": "FLOWER PARK", "theme": "garden", "pic": "tree", "tile": "O", "color": Color(0.45, 0.85, 0.4),
		"intro": "My marbles rolled away!", "done": "The flowers are back!",
		"spec": {"holes": 2, "loops": 3, "minw": 2, "maxw": 3, "door": 0.6}},
	{"name": "SEASIDE", "theme": "beach", "pic": "wave", "tile": "B", "color": Color(0.35, 0.75, 1.0),
		"intro": "Boing! Bumpers by the sea!", "done": "Splash! The pier is fixed!",
		"spec": {"holes": 2, "bumpers": 3, "loops": 3, "minw": 2, "maxw": 3, "door": 0.6}},
	{"name": "CANDY SHOP", "theme": "candy", "pic": "heart", "tile": ">", "color": Color(1.0, 0.5, 0.75),
		"intro": "Zoom arrows! Wheee!", "done": "Sweets for everyone!",
		"spec": {"holes": 2, "bumpers": 2, "arrows": 2, "loops": 2, "minw": 1, "maxw": 3, "door": 0.5}},
	{"name": "ICE CAVE", "theme": "ice", "pic": "snowman", "tile": "I", "color": Color(0.6, 0.85, 1.0),
		"intro": "Slippy slidey ice!", "done": "The ice cave sparkles!",
		"spec": {"holes": 2, "ice": 2, "loops": 2, "minw": 2, "maxw": 3, "door": 0.5}},
	{"name": "CASTLE", "theme": "castle", "pic": "castle", "tile": "P", "color": Color(0.55, 0.65, 1.0),
		"intro": "Blue pads open the gate!", "done": "The castle flags fly!",
		"spec": {"holes": 2, "bumpers": 1, "pads": true, "loops": 2, "minw": 1, "maxw": 3, "door": 0.5}},
	{"name": "STAR PARK", "theme": "space", "pic": "star", "tile": "T", "color": Color(0.7, 0.5, 1.0),
		"intro": "Zap! Swirly teleporters!", "done": "The stars twinkle again!",
		"spec": {"holes": 3, "arrows": 1, "tp": true, "loops": 2, "minw": 1, "maxw": 3, "door": 0.5}},
	{"name": "RAINBOW HILL", "theme": "rainbow", "pic": "sun", "tile": "", "color": Color(1.0, 0.75, 0.3),
		"intro": "The last shiny marbles!", "done": "Marble Town is shining!",
		"spec": {"holes": 3, "bumpers": 1, "ice": 1, "arrows": 1, "tp": true, "pads": true, "loops": 1, "minw": 1, "maxw": 3, "door": 0.45}},
]

## The shiny marbles to collect: [name, colour]. Story maze i holds shiny i % size (so the jar fills
## with every kind, then doubles up). The daily maze holds a golden one.
const SHINIES: Array = [["SUNNY", Color(1.0, 0.85, 0.2)], ["OCEAN", Color(0.2, 0.55, 1.0)], ["MINTY", Color(0.4, 1.0, 0.7)],
	["ROSY", Color(1.0, 0.45, 0.6)], ["GRAPE", Color(0.6, 0.35, 1.0)], ["LAVA", Color(1.0, 0.35, 0.15)],
	["FROSTY", Color(0.8, 0.95, 1.0)], ["LEAFY", Color(0.35, 0.8, 0.3)], ["PEACHY", Color(1.0, 0.7, 0.5)],
	["MIDNIGHT", Color(0.2, 0.2, 0.55)], ["BUBBLEGUM", Color(1.0, 0.6, 0.9)], ["LEMON", Color(0.95, 1.0, 0.4)],
	["COCOA", Color(0.55, 0.35, 0.2)], ["SKY", Color(0.55, 0.85, 1.0)], ["CHERRY", Color(0.85, 0.1, 0.25)],
	["PEARL", Color(0.97, 0.95, 0.9)]]
const GOLDEN := ["GOLDEN", Color(1.0, 0.78, 0.15)]

const BOBO_LINES: Array[String] = ["Roll roll roll!", "You found one!", "Shiny!", "Hooray!", "Nearly there!"]


static func place(i: int) -> Dictionary:
	return PLACES[posmod(i, PLACES.size())]


## The save's default data (core/save.gd fills missing keys from this).
static func save_defaults() -> Dictionary:
	return {"lessons_done": false, "story_i": 0, "world": -1, "shinies": {}, "places": 0, "daily": {},
		"mazes": 0, "falls": 0}


## Story maze index i -> [place index (0..), maze within it (0..2), lap (0 = the story, 1+ bonus)].
static func where(i: int) -> Array:
	var place_i := i / MAZES_PER_PLACE
	return [place_i % PLACES.size(), i % MAZES_PER_PLACE, place_i / PLACES.size()]


## The mazegen spec for story maze i (rising: the bonus laps get more holes, narrower rooms, fewer loops).
static func spec(i: int) -> Dictionary:
	var w := where(i)
	var pl := place(int(w[0]))
	var s: Dictionary = (pl.spec as Dictionary).duplicate()
	var lap: int = w[2]
	var step: int = w[1]
	s["theme"] = pl.theme
	s["name"] = "%s %d" % [pl.name, step + 1]
	s["new"] = pl.tile if step == 0 and lap == 0 else ""
	s["shiny"] = true
	s["holes"] = int(s.get("holes", 0)) + mini(3, lap) + (1 if step == 2 else 0)
	if lap > 0:
		s["minw"] = 1
		s["loops"] = maxi(0, int(s.get("loops", 2)) - lap)
		s["door"] = maxf(0.34, float(s.get("door", 0.5)) - 0.05 * lap)
		s["bumpers"] = int(s.get("bumpers", 0)) + (1 if lap >= 2 else 0)
		s["name"] = "%s %d" % [pl.name, step + 1 + MAZES_PER_PLACE * lap]
	return s


## Story maze i of the world `world` (a save's own seed).
static func maze(world: int, i: int) -> Dictionary:
	return MazeGen.generate(Seeded.derive(world, "maze%d" % i), spec(i))


## Today's maze: a mixed bag of things, the same on every machine (pass `date` in tests).
static func daily(date: String = "") -> Dictionary:
	var sd := Seeded.daily_seed("marble_maze", date)
	var r := Seeded.rng(sd, "daily")
	var pl := place(r.randi() % PLACES.size())
	var s := {"name": "TODAY", "theme": pl.theme, "new": "", "shiny": true, "holes": r.randi_range(2, 4),
		"bumpers": r.randi_range(0, 2), "ice": r.randi_range(0, 1), "arrows": r.randi_range(0, 2),
		"tp": r.randf() < 0.4, "pads": r.randf() < 0.4, "loops": r.randi_range(1, 2), "minw": 1, "maxw": 3, "door": 0.5}
	return MazeGen.generate(sd, s)


## The shiny marble story maze i holds (the daily maze: GOLDEN).
static func shiny_of(i: int) -> Array:
	return GOLDEN if i < 0 else SHINIES[i % SHINIES.size()]


## How many places are lit after clearing story maze i (counting every lap's places, capped at 7).
static func places_lit(story_i: int) -> int:
	return mini(PLACES.size(), story_i / MAZES_PER_PLACE)


static func shiny_total(shinies: Dictionary) -> int:
	var n := 0
	for k in shinies:
		n += int(shinies[k])
	return n
