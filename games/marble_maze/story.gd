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
## THIRD PASS: TWELVE places (five new ones between the old seven: MAGNET MINE, CLOCK TOWER, WARP WOODS, SKY
## ISLANDS, PINBALL PIER), each maze of a place on its own BOARD TYPE (mazegen.gd styles: rooms, islands, pinball,
## zigzag) so even the first places mix it up. TODAY'S RACE (daily(date, mode, wd, leg)) is three mazes against one
## clock; medal() turns the team's time into a gold / silver / bronze cup for Bobo's trophy shelf (main.gd keeps the
## family's BEST TIMES board). Old saves move their story_i onto the new list (progress.gd migrate_save).
## Pure data + small pure functions (no nodes), so tests and every machine agree.

const MazeGen := preload("res://games/marble_maze/mazegen.gd")
const Seeded := preload("res://core/seeded.gd")
const Worlds := preload("res://games/marble_maze/worlds.gd")

const MAZES_PER_PLACE := 3
const RACE_LEGS := 3  # TODAY'S RACE: three mazes, one clock
## Race cups: seconds per step of the shortest way (every leg added up) for GOLD / SILVER (else BRONZE), a bit
## more per extra marble (the team's time is the LAST marble home).
const GOLD_PER_STEP := 0.75
const SILVER_PER_STEP := 1.15
const PER_MARBLE := 0.12
const MEDALS := {"gold": Color(1.0, 0.8, 0.2), "silver": Color(0.8, 0.84, 0.9), "bronze": Color(0.85, 0.52, 0.3)}
## The old seven places' new spots in PLACES (progress.gd migrate_save: a save from before the third pass).
const OLD_PLACES: Array[int] = [0, 1, 3, 5, 7, 9, 11]
const BOBO_COLOR := Color(0.72, 0.5, 1.0)

## place: shown name. pic: core/story_card.gd picture or core/ui_kit.gd icon. tile: the new thing this
## place brings (it sparkles in the first maze's intro). spec: core of the mazegen spec. styles: each of its three
## mazes' board type (mazegen.gd STYLES). at: [angle (degrees), distance] of its little model in Marble Town (town.gd;
## the old seven stand on the inner arc, the five new ones behind the gaps).
const PLACES: Array[Dictionary] = [
	{"name": "FLOWER PARK", "theme": "garden", "pic": "tree", "tile": "O", "color": Color(0.45, 0.85, 0.4),
		"intro": "My marbles rolled away!", "done": "The flowers are back!", "styles": ["rooms", "rooms", "zigzag"], "at": [-68.0, 1.85],
		"spec": {"holes": 2, "loops": 3, "minw": 2, "maxw": 3, "door": 0.6}},
	{"name": "SEASIDE", "theme": "beach", "pic": "wave", "tile": "B", "color": Color(0.35, 0.75, 1.0),
		"intro": "Boing! Bumpers by the sea!", "done": "Splash! The pier is fixed!", "styles": ["rooms", "pinball", "rooms"], "at": [-45.33, 1.85],
		"spec": {"holes": 2, "bumpers": 3, "loops": 3, "minw": 2, "maxw": 3, "door": 0.6}},
	{"name": "MAGNET MINE", "theme": "volcano", "pic": "mmmagnet", "tile": "N", "color": Color(1.0, 0.35, 0.3),
		"intro": "Magnets! They pull you!", "done": "The mine carts roll!", "styles": ["rooms", "rooms", "zigzag"], "at": [-34.0, 2.6],
		"spec": {"holes": 2, "magnets": 2, "loops": 2, "minw": 2, "maxw": 3, "door": 0.55}},
	{"name": "CANDY SHOP", "theme": "candy", "pic": "heart", "tile": ">", "color": Color(1.0, 0.5, 0.75),
		"intro": "Zoom arrows! Wheee!", "done": "Sweets for everyone!", "styles": ["rooms", "zigzag", "rooms"], "at": [-22.67, 1.85],
		"spec": {"holes": 2, "bumpers": 2, "arrows": 2, "loops": 2, "minw": 1, "maxw": 3, "door": 0.5}},
	{"name": "CLOCK TOWER", "theme": "toys", "pic": "mmclock", "tile": "H", "color": Color(1.0, 0.6, 0.15),
		"intro": "Tick tock! Moving walls!", "done": "The big clock chimes!", "styles": ["zigzag", "rooms", "zigzag"], "at": [-11.33, 2.6],
		"spec": {"holes": 2, "movers": 2, "loops": 2, "minw": 2, "maxw": 3, "door": 0.5}},
	{"name": "ICE CAVE", "theme": "ice", "pic": "snowman", "tile": "I", "color": Color(0.6, 0.85, 1.0),
		"intro": "Slippy slidey ice!", "done": "The ice cave sparkles!", "styles": ["rooms", "pinball", "rooms"], "at": [0.0, 1.85],
		"spec": {"holes": 2, "ice": 2, "loops": 2, "minw": 2, "maxw": 3, "door": 0.5}},
	{"name": "WARP WOODS", "theme": "jungle", "pic": "mmwarp", "tile": "W", "color": Color(0.75, 0.4, 1.0),
		"intro": "Whoosh! Warp holes!", "done": "The woods glow!", "styles": ["rooms", "zigzag", "rooms"], "at": [11.33, 2.6],
		"spec": {"holes": 2, "warp": true, "patches": 1, "loops": 2, "minw": 2, "maxw": 3, "door": 0.5}},
	{"name": "CASTLE", "theme": "castle", "pic": "castle", "tile": "P", "color": Color(0.55, 0.65, 1.0),
		"intro": "Blue pads open the gate!", "done": "The castle flags fly!", "styles": ["rooms", "rooms", "rooms"], "at": [22.67, 1.85],
		"spec": {"holes": 2, "bumpers": 1, "pads": true, "loops": 2, "minw": 1, "maxw": 3, "door": 0.5}},
	{"name": "SKY ISLANDS", "theme": "farm", "pic": "mmisland", "tile": "-", "color": Color(0.45, 0.8, 1.0),
		"intro": "Planks in the sky!", "done": "The islands float!", "styles": ["islands", "islands", "islands"], "at": [34.0, 2.6],
		"spec": {"holes": 1, "loops": 2, "minw": 2, "maxw": 3, "rails": 0.5}},
	{"name": "STAR PARK", "theme": "space", "pic": "star", "tile": "T", "color": Color(0.7, 0.5, 1.0),
		"intro": "Zap! Swirly teleporters!", "done": "The stars twinkle again!", "styles": ["rooms", "zigzag", "rooms"], "at": [45.33, 1.85],
		"spec": {"holes": 3, "arrows": 1, "tp": true, "loops": 2, "minw": 1, "maxw": 3, "door": 0.5}},
	{"name": "PINBALL PIER", "theme": "race", "pic": "mmpinball", "tile": "", "color": Color(1.0, 0.3, 0.6),
		"intro": "Ping! Pinball time!", "done": "The pier lights flash!", "styles": ["pinball", "pinball", "pinball"], "at": [56.67, 2.6],
		"spec": {"holes": 2, "bumpers": 6, "magnets": 1, "loops": 2}},
	{"name": "RAINBOW HILL", "theme": "rainbow", "pic": "sun", "tile": "", "color": Color(1.0, 0.75, 0.3),
		"intro": "The last shiny marbles!", "done": "Marble Town is shining!", "styles": ["rooms", "islands", "zigzag"], "at": [68.0, 1.85],
		"spec": {"holes": 3, "bumpers": 1, "ice": 1, "arrows": 1, "tp": true, "pads": true, "magnets": 1, "warp": true, "movers": 1,
			"loops": 1, "minw": 1, "maxw": 3, "door": 0.45}},
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
		"mazes": 0, "falls": 0, "jar": [], "mode": "brave", "gift": "", "rack": [], "gifts": {}, "events": 0,
		"race": {}, "race_best": [], "cups": [], "ghost": {}, "races": 0}


## Story maze index i -> [place index (0..), maze within it (0..2), lap (0 = the story, 1+ bonus)].
static func where(i: int) -> Array:
	var place_i := i / MAZES_PER_PLACE
	return [place_i % PLACES.size(), i % MAZES_PER_PLACE, place_i / PLACES.size()]


## Bobo's line after story maze i is cleared, when it isn't the place's last: how many mazes are left before the place
## lights up in the town (a reason for one more maze; 2026-11-15 the family stopped right after FLOWER PARK 1, which
## said nothing). "" after a place's last maze (that one has its own "done" beat).
static func progress_line(i: int) -> String:
	var w := where(i)
	var left: int = MAZES_PER_PLACE - 1 - int(w[1])
	if left <= 0:
		return ""
	var pl := place(int(w[0]))
	if int(w[2]) > 0:
		return "%d more for a %s bonus star!" % [left, str(pl.name)]
	return "%d more to light up %s!" % [left, str(pl.name)]


## The mazegen spec for story maze i (rising: the bonus laps get more holes, narrower rooms, fewer loops).
static func spec(i: int) -> Dictionary:
	var w := where(i)
	var pl := place(int(w[0]))
	var s: Dictionary = (pl.spec as Dictionary).duplicate()
	var lap: int = w[2]
	var step: int = w[1]
	s["theme"] = pl.theme
	s["style"] = str((pl.styles as Array)[step])
	if s.style == "pinball":
		s["bumpers"] = int(s.get("bumpers", 0)) + 4  # a pinball hall is all about bouncing
		s["holes"] = maxi(1, int(s.get("holes", 0)) - 1)
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


## Story maze i of the world `world` (a save's own seed), in a mode (worlds.gd MODES) on today's world (worlds.gd
## WORLDS: "" = none, the first pass's mazes).
static func maze(world: int, i: int, mode: String = "", wd: String = "") -> Dictionary:
	var s := spec(i)
	if mode != "" or wd != "":
		s = Worlds.apply(s, mode if mode != "" else "brave", wd if wd != "" else "sunny")
	return MazeGen.generate(Seeded.derive(world, "maze%d" % i), s)


## TODAY'S RACE, leg 0..2: a mixed bag of things, the same on every machine (pass `date` in tests). Leg 0 is a rooms
## maze, the next two each a different other board type, every leg with a gadget or two.
static func daily(date: String = "", mode: String = "", wd: String = "", leg: int = 0) -> Dictionary:
	var sd := Seeded.daily_seed("marble_maze", date)
	var r := Seeded.rng(sd, "daily")
	var pl := place(r.randi() % PLACES.size())
	var s := {"name": "TODAY", "theme": pl.theme, "new": "", "shiny": true, "holes": r.randi_range(2, 4),
		"bumpers": r.randi_range(0, 2), "ice": r.randi_range(0, 1), "arrows": r.randi_range(0, 2),
		"tp": r.randf() < 0.4, "pads": r.randf() < 0.4, "loops": r.randi_range(1, 2), "minw": 1, "maxw": 3, "door": 0.5}
	var others: Array = Seeded.shuffled(Seeded.rng(sd, "daily_styles"), ["islands", "pinball", "zigzag"])
	var rg := Seeded.rng(sd, "daily_leg%d" % leg)
	s["style"] = "rooms" if leg <= 0 else str(others[(leg - 1) % others.size()])
	var gadgets: Array = Seeded.shuffled(rg, ["magnets", "warp", "movers", "patches"])
	for k in gadgets.slice(0, rg.randi_range(1, 2)):
		s[k] = true if k == "warp" else rg.randi_range(1, 2)
	if s.style == "pinball":
		s["bumpers"] = int(s.bumpers) + 4
	if leg > 0:
		var pl2 := place(rg.randi() % PLACES.size())
		s["theme"] = pl2.theme
		s["tp"] = s.style != "pinball" and rg.randf() < 0.3
	s["name"] = "TODAY" if leg <= 0 else "TODAY %d" % (leg + 1)
	if mode != "" or wd != "":
		s = Worlds.apply(s, mode if mode != "" else "brave", wd if wd != "" else "sunny")
	return MazeGen.generate(sd if leg <= 0 else Seeded.derive(sd, "leg%d" % leg), s)


## The race cup for a team time: "gold", "silver" or "bronze". steps: the three legs' shortest ways added up.
static func medal(secs: float, steps: int, marbles: int) -> String:
	var k := 1.0 + PER_MARBLE * maxi(0, marbles - 1)
	if secs <= steps * GOLD_PER_STEP * k:
		return "gold"
	if secs <= steps * SILVER_PER_STEP * k:
		return "silver"
	return "bronze"


## A race time as the board shows it: 0:42 (minutes:seconds), or 1:05.
static func clock(secs: float) -> String:
	var s := int(floor(maxf(0.0, secs)))
	return "%d:%02d" % [s / 60, s % 60]


## An old (before the third pass) story index on the twelve-place list: the same place and maze, the same lap.
static func migrate_story_i(old_i: int) -> int:
	var per_lap := 7 * MAZES_PER_PLACE
	var lap := old_i / per_lap
	var in_lap := old_i % per_lap
	return lap * PLACES.size() * MAZES_PER_PLACE + OLD_PLACES[in_lap / MAZES_PER_PLACE] * MAZES_PER_PLACE + in_lap % MAZES_PER_PLACE


## The shiny marble story maze i holds (the daily maze: GOLDEN).
static func shiny_of(i: int) -> Array:
	return GOLDEN if i < 0 else SHINIES[i % SHINIES.size()]


## How many places are lit after clearing story maze i (counting every lap's places, capped at all of them).
static func places_lit(story_i: int) -> int:
	return mini(PLACES.size(), story_i / MAZES_PER_PLACE)


static func shiny_total(shinies: Dictionary) -> int:
	var n := 0
	for k in shinies:
		n += int(shinies[k])
	return n
