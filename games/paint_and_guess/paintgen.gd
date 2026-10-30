extends RefCounted
## Paint and Guess's seeded games: SMUDGE the gallery cat's studio. A whole game (5 rounds) is built from
## one code (seed, themes unlocked, daily) so the host sends a single number and every machine knows the
## same game. Everything is a PICTURE (core/story_card.gd pictures), so kids who can't read yet can play:
## the artist sees a picture of what to paint, every guesser picks one of four PICTURE answers, the VR
## player's TEAM PAINT balloons carry pictures too. The words are only small captions.
## A game: per round its THEME (a picture pack), the THING to paint, and each seat's four answers (the same
## four for everyone, each seat in its own order). Readable rising challenge: round 1 asks for the easiest
## things (a sun, an apple) and its wrong answers never share the right one's shape; later rounds ask for
## trickier things with look-alike shapes; TEAM PAINT (the TV players paint together) is always easy.
## TODAY'S GALLERY: the first game each day uses the day's seed (Seeded.daily_seed) with the five starting
## themes, the same on every machine. More themes unlock as the family's gallery grows (themes_unlocked).
## FAIR AND PLAYABLE (check()): every answer has a picture, the right one is there exactly once for every
## seat, no look-alike pairs, all four from the round's theme (the theme never gives it away), the right
## answer's place moves about between rounds and seats, nothing is asked twice in a game, and a small kid who
## picks wrong three times (LOCKOUT each) still has time to find it. tests/paint_and_guess_gen_test.gd
## proves it over many seeds. The family gallery (saved paintings, main.gd + room.gd) packs strokes small
## with pack_strokes / unpack_strokes.

const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")

const GAME_ID := "paint_and_guess"
const ROUND_PLAN: Array[String] = ["paint", "paint", "team", "speed", "final"]
const ROUNDS := 5
## Must match main.gd round_time() and LOCKOUT (the test checks).
const ROUND_TIMES := {"paint": 60.0, "team": 50.0, "speed": 35.0, "final": 60.0}
const LOCKOUT := 3.0
const MAX_PLAYERS := 7  # seat 0 = the artist (TEAM PAINT: the VR player's balloons), 1-6 the guessers
const MIN_LOOK := 15.0  # seconds a kid needs to see the painting grow before guessing
## How hard a thing may be to paint, per round (1 = one or two shapes .. 3 = tricky).
const MAX_TIER: Array[int] = [1, 2, 1, 2, 3]
const MIN_TIER: Array[int] = [1, 1, 1, 1, 2]
## Rounds (0-based) whose wrong answers never share the right answer's shape (easy to tell apart).
const SHAPE_APART := [0, 2]
const BASE_THEMES := 5
const UNLOCK_EVERY := 6  # paintings in the family gallery per new theme
const GALLERY_MAX := 20  # paintings kept in the family gallery (oldest go)
const PACK_POINTS := 420  # most points a saved painting keeps

## id (a story picture name) -> [caption, paint tier, shape, look-alike group ("" = none)]
const THINGS := {
	# Animals
	"bunny": ["bunny", 2, "critter", "longears"], "frog": ["frog", 2, "round", ""], "lion": ["lion", 3, "critter", "bigcat"],
	"sheep": ["sheep", 3, "fluffy", "fluffy"], "penguin": ["penguin", 3, "tall", "bird"], "duckling": ["duck", 2, "critter", "bird"],
	"puppy": ["puppy", 3, "critter", "dog"], "fish": ["fish", 1, "long", "fish"], "snake": ["snake", 1, "long", ""],
	"butterfly": ["butterfly", 1, "wide", ""], "squirrel": ["squirrel", 3, "critter", "rodent"], "polarbear": ["polar bear", 3, "fluffy", "fluffy"],
	# Yummy food
	"apple": ["apple", 1, "round", "roundfruit"], "carrot": ["carrot", 1, "pointy", ""], "icecream": ["ice cream", 1, "pointy", "cone"],
	"pear": ["pear", 1, "round", "pear"], "strawberry": ["strawberry", 2, "pointy", "berry"], "melon": ["melon", 2, "round", "roundfruit"],
	"orange": ["orange", 1, "round", "roundfruit"], "pie": ["pie", 2, "wide", ""], "corn": ["corn", 2, "tall", ""],
	"juice": ["juice", 2, "tall", "cup"], "lettuce": ["lettuce", 2, "round", "leafy"], "cocoamug": ["hot cocoa", 2, "wide", "cup"],
	# Outdoors
	"sun": ["sun", 1, "spiky", "sun"], "tree": ["tree", 1, "tall", "tree"], "rainbow": ["rainbow", 1, "wide", ""],
	"cloud": ["cloud", 1, "fluffy", "cloud"], "snowman": ["snowman", 1, "tall", ""], "snowflake": ["snowflake", 2, "spiky", "sun"],
	"tent": ["tent", 2, "pointy", "tent"], "pumpkin": ["pumpkin", 1, "round", "roundfruit"], "sunflower": ["flower", 2, "tall", "flower"],
	"toadstool": ["mushroom", 2, "wide", "mushroom"], "house": ["house", 1, "pointy", "tent"], "igloo": ["igloo", 2, "wide", "dome"],
	# Party and play
	"balloon": ["balloon", 1, "round", "balloon"], "gift": ["present", 1, "boxy", ""], "drum": ["drum", 2, "boxy", "drum"],
	"guitar": ["guitar", 3, "long", ""], "partyhat": ["party hat", 1, "pointy", "cone"], "beachball": ["beach ball", 1, "round", "ball"],
	"football": ["football", 1, "round", "ball"], "trophy": ["trophy", 2, "tall", ""], "musicnote": ["music", 2, "tall", ""],
	"bell": ["bell", 2, "pointy", ""], "carousel": ["merry-go-round", 3, "wide", ""], "smiley": ["happy face", 1, "round", "face"],
	# Sea and sky
	"whale": ["whale", 2, "long", "fish"], "starfish": ["starfish", 1, "spiky", "star"], "anchor": ["anchor", 2, "tall", ""],
	"pearl": ["pearl shell", 3, "wide", ""], "boat": ["boat", 1, "wide", "boat"], "island": ["island", 2, "wide", ""],
	"rocket": ["rocket", 2, "tall", "rocket"], "planet": ["planet", 1, "round", "ball"], "storm": ["rain cloud", 2, "fluffy", "cloud"],
	"bird": ["bird", 2, "critter", "bird"],
	# Magic and monsters (unlocks)
	"dragon": ["dragon", 3, "critter", ""], "wizard": ["wizard hat", 2, "pointy", "cone"], "castle": ["castle", 2, "boxy", ""],
	"crown": ["crown", 1, "spiky", ""], "robot": ["robot", 2, "boxy", ""], "pirate": ["pirate", 3, "round", "face"],
	"alien": ["alien", 2, "round", "face"], "kaiju": ["monster", 2, "critter", ""], "dino": ["dinosaur", 3, "critter", ""],
	"kingghost": ["ghost", 1, "tall", ""], "longsword": ["sword", 1, "long", ""], "treasuremap": ["treasure map", 3, "boxy", ""],
	# Around town (unlocks)
	"kart": ["car", 3, "wide", "car"], "ferris": ["big wheel", 3, "round", ""], "fountain": ["fountain", 2, "wide", ""],
	"tower": ["tower", 1, "tall", ""], "windmill": ["windmill", 3, "tall", ""], "bathtub": ["bath", 2, "wide", ""],
	"hive": ["beehive", 1, "round", ""], "coastercar": ["roller coaster", 3, "wide", "car"], "honeyjar": ["honey", 1, "boxy", ""],
}

## [name, picture, things] - the first BASE_THEMES are there from the start, the rest unlock.
const THEMES: Array = [
	["ANIMALS", "puppy", ["bunny", "frog", "lion", "sheep", "penguin", "duckling", "puppy", "fish", "snake", "butterfly", "squirrel", "polarbear"]],
	["YUMMY FOOD", "apple", ["apple", "carrot", "icecream", "pear", "strawberry", "melon", "orange", "pie", "corn", "juice", "lettuce", "cocoamug"]],
	["OUTDOORS", "tree", ["sun", "tree", "rainbow", "cloud", "snowman", "snowflake", "tent", "pumpkin", "sunflower", "toadstool", "house", "igloo"]],
	["PARTY AND PLAY", "balloon", ["balloon", "gift", "drum", "guitar", "partyhat", "beachball", "football", "trophy", "musicnote", "bell", "carousel", "smiley"]],
	["SEA AND SKY", "whale", ["whale", "starfish", "anchor", "pearl", "boat", "island", "rocket", "planet", "storm", "bird"]],
	["MAGIC AND MONSTERS", "castle", ["dragon", "wizard", "castle", "crown", "robot", "pirate", "alien", "kaiju", "dino", "kingghost", "longsword", "treasuremap"]],
	["AROUND TOWN", "ferris", ["kart", "ferris", "fountain", "tower", "windmill", "bathtub", "hive", "coastercar", "honeyjar"]],
]

const ADJ: Array[String] = ["SUNNY", "SPARKLY", "HAPPY", "COSY", "JOLLY", "GIGGLY", "BRIGHT", "SPLASHY", "SWIRLY", "DOTTY"]
const NOUN: Array[String] = ["SHOW", "GALLERY", "STUDIO", "EXHIBIT", "PARADE", "FAIR"]
const GOLD := Color(1.0, 0.82, 0.25)


static func caption(id: String) -> String:
	return str(THINGS[id][0]) if THINGS.has(id) else id


static func tier(id: String) -> int:
	return int(THINGS[id][1]) if THINGS.has(id) else 9


static func shape(id: String) -> String:
	return str(THINGS[id][2]) if THINGS.has(id) else ""


static func group(id: String) -> String:
	return str(THINGS[id][3]) if THINGS.has(id) else ""


static func theme_name(i: int) -> String:
	return str(THEMES[posmod(i, THEMES.size())][0])


static func theme_pic(i: int) -> String:
	return str(THEMES[posmod(i, THEMES.size())][1])


static func theme_things(i: int) -> Array:
	return THEMES[posmod(i, THEMES.size())][2]


## How many themes the family has, from the paintings in their gallery (ever).
static func themes_unlocked(paintings: int) -> int:
	return clampi(BASE_THEMES + maxi(0, paintings) / UNLOCK_EVERY, BASE_THEMES, THEMES.size())


## Paintings still to go until the next theme (0 = all unlocked).
static func paintings_to_unlock(paintings: int) -> int:
	if themes_unlocked(paintings) >= THEMES.size():
		return 0
	return UNLOCK_EVERY - posmod(maxi(0, paintings), UNLOCK_EVERY)


# --- Codes ----------------------------------------------------------------------------------------------

static func code_of(seed_v: int, themes_n: int, daily: bool) -> int:
	return seed_v * 100 + clampi(themes_n, BASE_THEMES, THEMES.size()) * 2 + (1 if daily else 0)


static func seed_of(code: int) -> int:
	return code / 100


static func themes_of(code: int) -> int:
	return (code % 100) / 2


static func daily_of(code: int) -> bool:
	return code % 2 == 1


static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed(GAME_ID, date)


## The code of game `game_no` (1-based) of a session: TODAY'S GALLERY first when it's due today (always
## the starting themes, so it's the same on every machine), then games from the session seed.
static func code_at(session_seed: int, game_no: int, daily_due: bool, themes_n: int, date: String = "") -> int:
	if daily_due and game_no == 1:
		return code_of(daily_seed(date), BASE_THEMES, true)
	return code_of(Seeded.derive(session_seed, game_no), themes_n, false)


# --- Building a game ------------------------------------------------------------------------------------

## The game for a code (plain Dictionary; deterministic).
static func build(code: int) -> Dictionary:
	var s := seed_of(code)
	var tn := themes_of(code)
	var daily := daily_of(code)
	var r := Seeded.rng(s, "game")
	var d := {"code": code, "seed": s, "themes": tn, "daily": daily}
	d["name"] = "TODAY'S GALLERY" if daily else "%s %s" % [Seeded.pick(r, ADJ), Seeded.pick(r, NOUN)]
	# Five different themes (newly unlocked ones come up more often, so the family meets them).
	var pool: Array = range(tn)
	var weights: Array = []
	for i in pool:
		weights.append(3.0 if i >= BASE_THEMES else 1.0)
	var order: Array = []
	var tr := Seeded.rng(s, "themes")
	while order.size() < ROUNDS and not pool.is_empty():
		var k := Seeded.weighted(tr, weights)
		order.append(pool[k])
		pool.remove_at(k)
		weights.remove_at(k)
	var used: Array = []
	var rounds: Array = []
	for ri in ROUNDS:
		var th: int = order[ri % order.size()]
		var rd := _make_round(s, ri, th, Seeded.rng(s, "round%d" % ri), used)
		used.append(rd["target"])
		rounds.append(rd)
	d["rounds"] = rounds
	return d


## One round: the thing to paint from theme `th` (never one in `used`) and every seat's four answers.
static func _make_round(s: int, ri: int, th: int, rr: RandomNumberGenerator, used: Array) -> Dictionary:
	var target := _pick_target(rr, th, ri, used)
	var four := _pick_set(rr, th, ri, target)
	var base_slot := Seeded.rng(s, "slots").randi() % 4
	var opts: Array = []
	for seat in MAX_PLAYERS:
		# The right answer's place: moves one along every round and differs between neighbouring seats.
		var slot := (base_slot + ri + seat * 3) % 4
		var others: Array = Seeded.shuffled(Seeded.rng(s, "seat%d/%d/%s" % [ri, seat, target]), four.slice(1))
		var o: Array = []
		for k in 4:
			o.append(target if k == slot else others.pop_back())
		opts.append(o)
	var type: String = ROUND_PLAN[ri]
	return {"type": type, "theme": th, "target": target, "opts": opts, "time": float(ROUND_TIMES[type])}


## Round `ri` of a game; reroll > 0 = the artist asked for a NEW ONE (the reroll-th time): another thing from the
## same theme (none of `used`, none of the game's other rounds), built by the same fair rules.
static func round_of(d: Dictionary, ri: int, used: Array = [], reroll: int = 0) -> Dictionary:
	var rounds: Array = d["rounds"]
	var rd: Dictionary = rounds[clampi(ri, 0, rounds.size() - 1)]
	if reroll <= 0:
		return rd.duplicate(true)
	var avoid: Array = used.duplicate()
	for o in rounds:
		avoid.append(o["target"])
	var s := int(d["seed"])
	return _make_round(s, ri, int(rd["theme"]), Seeded.rng(s, "reroll%d/%d" % [ri, reroll]), avoid)


static func _pick_target(r: RandomNumberGenerator, th: int, ri: int, used: Array) -> String:
	var cands: Array = []
	for id in theme_things(th):
		if not used.has(id) and tier(id) <= MAX_TIER[ri] and tier(id) >= MIN_TIER[ri] and StoryCard.has_picture(id):
			cands.append(id)
	if cands.is_empty():  # (never for the packs above; the test proves it) fall back to any easy one
		for id in theme_things(th):
			if not used.has(id) and tier(id) <= MAX_TIER[ri]:
				cands.append(id)
	return str(Seeded.pick(r, cands))


## The four answers (target first): three more from the same theme, no look-alikes, and in the easy rounds
## none with the target's shape.
static func _pick_set(r: RandomNumberGenerator, th: int, ri: int, target: String) -> Array:
	var four: Array = [target]
	var pool: Array = Seeded.shuffled(r, theme_things(th))
	for strict in [true, false]:
		for id in pool:
			if four.size() >= 4:
				break
			if _decoy_ok(id, four, target, ri if strict else -1):
				four.append(id)
	return four


static func _decoy_ok(id: String, four: Array, target: String, ri: int) -> bool:
	if four.has(id) or not THINGS.has(id) or not StoryCard.has_picture(id):
		return false
	if SHAPE_APART.has(ri) and shape(id) == shape(target):
		return false
	for o in four:
		if group(id) != "" and group(id) == group(str(o)):
			return false
	return true


## Everything wrong with a game (empty = fair and playable by small kids).
static func check(d: Dictionary) -> Array:
	var why: Array = []
	var tn := int(d["themes"])
	if tn < BASE_THEMES or tn > THEMES.size():
		why.append("%d themes" % tn)
	if bool(d["daily"]) and (tn != BASE_THEMES or str(d["name"]) != "TODAY'S GALLERY"):
		why.append("TODAY'S GALLERY must use the starting themes")
	var rounds: Array = d["rounds"]
	if rounds.size() != ROUNDS:
		return why + ["%d rounds" % rounds.size()]
	var targets := {}
	var themes := {}
	var slots_by_seat := {}
	for ri in ROUNDS:
		var rd: Dictionary = rounds[ri]
		var tag := "round %d" % (ri + 1)
		var target := str(rd["target"])
		var th := int(rd["theme"])
		if str(rd["type"]) != ROUND_PLAN[ri]:
			why.append("%s is %s" % [tag, rd["type"]])
		if th < 0 or th >= tn:
			why.append("%s theme %d is not unlocked" % [tag, th])
		themes[th] = true
		if not THINGS.has(target) or not theme_things(th).has(target):
			why.append("%s: %s is not in %s" % [tag, target, theme_name(th)])
		if not StoryCard.has_picture(target):
			why.append("%s: no picture of %s" % [tag, target])
		if tier(target) > MAX_TIER[ri] or tier(target) < MIN_TIER[ri]:
			why.append("%s: %s is tier %d" % [tag, target, tier(target)])
		if targets.has(target):
			why.append("%s: %s asked twice" % [tag, target])
		targets[target] = true
		if float(rd["time"]) < MIN_LOOK + 3.0 * LOCKOUT + 5.0:
			why.append("%s: %.0f s is too short to find it after three wrong picks" % [tag, float(rd["time"])])
		var opts: Array = rd["opts"]
		if opts.size() != MAX_PLAYERS:
			why.append("%s: answers for %d seats" % [tag, opts.size()])
			continue
		var first_set := ""
		var round_slots := {}
		for seat in opts.size():
			var o: Array = opts[seat]
			if o.size() != 4:
				why.append("%s seat %d: %d answers" % [tag, seat, o.size()])
				continue
			if o.count(target) != 1:
				why.append("%s seat %d: the right answer is there %d times" % [tag, seat, o.count(target)])
			var sorted := o.duplicate()
			sorted.sort()
			if first_set == "":
				first_set = str(sorted)
			elif str(sorted) != first_set:
				why.append("%s seat %d: different answers from the others" % [tag, seat])
			var slot := o.find(target)
			round_slots[slot] = true
			if not slots_by_seat.has(seat):
				slots_by_seat[seat] = {}
			slots_by_seat[seat][slot] = true
			for i in 4:
				var a := str(o[i])
				if not StoryCard.has_picture(a):
					why.append("%s: no picture of %s" % [tag, a])
				if not theme_things(th).has(a):
					why.append("%s: %s is not from the theme" % [tag, a])
				for j in range(i + 1, 4):
					var b := str(o[j])
					if a == b:
						why.append("%s seat %d: %s twice" % [tag, seat, a])
					elif group(a) != "" and group(a) == group(b):
						why.append("%s: %s and %s look alike" % [tag, a, b])
				if SHAPE_APART.has(ri) and a != target and shape(a) == shape(target):
					why.append("%s: %s has the same shape as %s" % [tag, a, target])
		if round_slots.size() < 3:
			why.append("%s: the right answer sits in the same place for everyone" % tag)
	if themes.size() < mini(ROUNDS, tn):
		why.append("only %d different themes" % themes.size())
	for seat in slots_by_seat:
		if (slots_by_seat[seat] as Dictionary).size() < 3:
			why.append("seat %d: the right answer hardly moves" % seat)
	return why


## Static data checks (the packs themselves): every thing has a picture and a known shape, every theme can
## fill every round, captions are short. Empty = fine.
static func check_packs() -> Array:
	var why: Array = []
	var seen := {}
	for t in THEMES:
		var things: Array = t[2]
		if not StoryCard.has_picture(str(t[1])):
			why.append("theme %s has no picture" % t[0])
		for id in things:
			if seen.has(id):
				why.append("%s is in two themes" % id)
			seen[id] = true
			if not THINGS.has(id):
				why.append("%s has no entry in THINGS" % id)
			elif not StoryCard.has_picture(id):
				why.append("%s has no picture" % id)
			elif str(THINGS[id][0]).length() > 15:
				why.append("caption %s is long" % THINGS[id][0])
		for ri in ROUNDS:
			var n := 0
			for id in things:
				if tier(id) <= MAX_TIER[ri] and tier(id) >= MIN_TIER[ri]:
					n += 1
			if n < 3:
				why.append("theme %s has only %d things for round %d" % [t[0], n, ri + 1])
	for id in THINGS:
		if not seen.has(id):
			why.append("%s is in no theme" % id)
	return why


# --- The family gallery ---------------------------------------------------------------------------------

## A painting packed small for the save and the network: [[colour, width (mm), PackedByteArray x,y,...], ...]
## (canvas.gd export_strokes() in; points squeezed into a byte each across the canvas, thinned to PACK_POINTS).
static func pack_strokes(strokes: Array, w: float, h: float) -> Array:
	var total := 0
	for s in strokes:
		total += (s[3] as PackedVector2Array).size()
	var step := maxi(1, ceili(float(total) / float(PACK_POINTS)))
	var out: Array = []
	for s in strokes:
		var pts: PackedVector2Array = s[3]
		if pts.is_empty():
			continue
		var b := PackedByteArray()
		for i in pts.size():
			if i % step != 0 and i != pts.size() - 1:
				continue
			b.append(clampi(roundi((pts[i].x / w + 0.5) * 255.0), 0, 255))
			b.append(clampi(roundi((pts[i].y / h + 0.5) * 255.0), 0, 255))
		out.append([int(s[1]), roundi(float(s[2]) * 1000.0), b])
	return out


## Back to canvas.gd's stroke format: [[id, colour, width, PackedVector2Array, owner], ...].
static func unpack_strokes(packed: Array, w: float, h: float) -> Array:
	var out: Array = []
	var id := 1
	for e in packed:
		if not (e is Array) or (e as Array).size() < 3:
			continue
		var b: PackedByteArray = e[2]
		var pts := PackedVector2Array()
		for i in range(0, b.size() - 1, 2):
			pts.append(Vector2((float(b[i]) / 255.0 - 0.5) * w, (float(b[i + 1]) / 255.0 - 0.5) * h))
		if not pts.is_empty():
			out.append([id, int(e[0]), float(e[1]) / 1000.0, pts, 0])
			id += 1
	return out


## Bytes a packed painting takes (the test keeps the save and the network message small).
static func packed_size(packed: Array) -> int:
	var n := 0
	for e in packed:
		n += 8 + (e[2] as PackedByteArray).size()
	return n


## Where family painting `i` hangs (x, y, z) on the studio's side walls (room.gd), Vector3.INF past the end.
static func family_slot(i: int) -> Vector3:
	if i < 0 or i >= GALLERY_MAX:
		return Vector3.INF
	var side := -1.0 if i % 2 == 0 else 1.0
	var k := i / 2
	var row := k / 5
	var col := k % 5
	return Vector3(side * 4.13, 1.55 + 0.7 * float(row), 0.75 + 0.78 * float(col))
