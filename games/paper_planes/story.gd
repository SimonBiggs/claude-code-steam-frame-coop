extends RefCounted
## PAPER PLANES story and progression data: Pip the post bird's letters blew away in a big wind.
## Five chapters of three flights each; every flight with at least one star builds a piece of that
## chapter's place in the valley (it stays, saved). Lines are short and kind (kids read them).
## Pure data + small pure functions (no nodes), so tests and every machine agree.

const FLIGHTS_PER_CHAPTER := 3
const MIXED := 5  ## the chapter id of DAILY skies and bonus skies after the story (everything mixed)

## id: chapter index. sky: core/sky_kit.gd preset. ground: grass colour. place: what gets built.
## pic: core/story_card.gd picture. new: the new thing this chapter brings (shown on its first flight).
const CHAPTERS: Array[Dictionary] = [
	{"name": "SUNNY MEADOW", "sky": "day", "ground": Color(0.5, 0.78, 0.38), "place": "FARMHOUSE", "pic": "house",
		"who": "FARMER ROSA", "intro": "Oh no! The big wind took all my letters!", "new": "Fly them through the hoops!",
		"done": "Rosa got her letters! Look, her farmhouse!"},
	{"name": "APPLE ORCHARD", "sky": "morning", "ground": Color(0.45, 0.74, 0.34), "place": "APPLE BARN", "pic": "tree",
		"who": "GRANNY OAK", "intro": "Some letters landed in the apple trees!", "new": "Fly the numbers in order: 1, 2, 3!",
		"done": "Granny Oak's barn is full of apples!"},
	{"name": "SEASIDE", "sky": "sunset", "ground": Color(0.86, 0.8, 0.55), "place": "LIGHTHOUSE", "pic": "wave",
		"who": "CAPTAIN FINN", "intro": "Letters for the boats! Tiny ones too!", "new": "Tiny pink hoops are worth 2!",
		"done": "The lighthouse shines again!"},
	{"name": "STORMY PEAKS", "sky": "stormy", "ground": Color(0.5, 0.62, 0.48), "place": "MOUNTAIN HUT", "pic": "storm",
		"who": "GRUMPY CLOUDS", "intro": "Grr! Grumpy clouds float up here.", "new": "Fly around the grey clouds!",
		"done": "The clouds smiled! Snug hut is fixed."},
	{"name": "CLOUD CASTLE", "sky": "dawn", "ground": Color(0.62, 0.8, 0.5), "place": "CLOUD CASTLE", "pic": "sprite",
		"who": "GUST", "intro": "Hee hee! I'm Gust. I blew the letters away!", "new": "Catch my golden hoop! It's worth 5!",
		"done": "Gust was lonely. Now she has friends!"},
	{"name": "BONUS SKY", "sky": "day", "ground": Color(0.5, 0.78, 0.38), "place": "", "pic": "envelope",
		"who": "PIP", "intro": "Extra letters! Let's fly!", "new": "",
		"done": "Lovely flying!"},
]

## Pip's lines between flights (one picked by the flight number).
const PIP_LINES: Array[String] = ["Ready? Let's fly!", "You're a super post pilot!", "Whoosh! Here we go!",
	"Thank you for helping me!", "The valley loves its letters!"]
const PIP_RETRY: Array[String] = ["So close! Let's try again!", "Nearly! Pip believes in you!", "Again! You can do it!"]

## Breezes: the team picks one before each flight by flying (or throwing) through its gate.
## id -> [label, ui icon, colour]
const BREEZES := {
	"big": ["BIG HOOPS", "plus", Color(0.4, 0.85, 0.5)],
	"tail": ["MORE TIME", "clock", Color(0.4, 0.7, 1.0)],
	"lucky": ["RAINBOWS", "star", Color(1.0, 0.8, 0.3)],
	"magnet": ["MAGNET", "bolt", Color(1.0, 0.5, 0.75)],
	"slow": ["SLOW HOOPS", "heart", Color(0.75, 0.6, 1.0)],
	"streak": ["LONG COMBO", "crown", Color(1.0, 0.6, 0.3)],
}
const DAILY_GATE := "daily"

## Unlocks by stamps (total stars ever): [stamps, id, label].
const UNLOCKS: Array = [[3, "rainbow_trail", "RAINBOW TRAILS"], [9, "sparkle_trail", "SPARKLE TRAILS"],
	[18, "comet_trail", "COMET TRAILS"], [30, "gold", "GOLDEN PLANES"], [45, "crown", "PILOT CROWNS"]]


static func chapter(c: int) -> Dictionary:
	return CHAPTERS[clampi(c, 0, CHAPTERS.size() - 1)]


## The save's default data (core/save.gd fills missing keys from this, so old saves just gain them).
static func save_defaults() -> Dictionary:
	return {"best": 0, "chapter": 0, "flight": 0, "stars": {}, "misses": 0, "laps": 0, "daily": {},
		"flights": 0, "extra_stamps": 0}


## Total stars ever earned (each flight counts its best).
static func stamps(stars: Dictionary) -> int:
	var n := 0
	for k in stars:
		n += int(stars[k])
	return n


static func unlocked(stamp_count: int) -> Array:
	var out: Array = []
	for u in UNLOCKS:
		if stamp_count >= int(u[0]):
			out.append(String(u[1]))
	return out


## Which unlocks a stamp change just reached (labels).
static func newly_unlocked(before: int, after: int) -> Array:
	var out: Array = []
	for u in UNLOCKS:
		if before < int(u[0]) and after >= int(u[0]):
			out.append(String(u[2]))
	return out


## Star goals for a flight: [1 star, 2 stars, 3 stars] in points. Scales with the number of fliers
## (VR thrower counts as one), gets a little harder per chapter and per lap after the story, and
## kinder after misses on the same flight (never below half).
static func goals(players: int, chap: int, misses: int, laps: int, seconds: float) -> Array:
	var p := maxi(1, players)
	var per_min := 7.0 + 4.0 * float(p - 1)  # points per minute for one star
	var hard := 1.0 + 0.06 * float(mini(chap, 4)) + 0.15 * float(laps)
	var kind := maxf(0.5, 1.0 - 0.18 * float(misses))
	var g1 := maxi(3, int(round(per_min * seconds / 60.0 * hard * kind)))
	return [g1, int(round(g1 * 1.7)), int(round(g1 * 2.5))]


static func stars_for(score: int, g: Array) -> int:
	var s := 0
	for v in g:
		if score >= int(v):
			s += 1
	return s


## Progress after a story flight: returns {chapter, flight, laps, misses, advanced, chapter_done, story_done}.
static func advance(chap: int, flight: int, laps: int, misses: int, stars: int) -> Dictionary:
	var r := {"chapter": chap, "flight": flight, "laps": laps, "misses": misses, "advanced": false,
		"chapter_done": false, "story_done": false}
	if stars <= 0:
		r["misses"] = misses + 1
		return r
	r["misses"] = 0
	r["advanced"] = true
	if chap >= MIXED:  # bonus skies: every flight is its own lap step
		r["laps"] = laps + 1 if flight >= FLIGHTS_PER_CHAPTER - 1 else laps
		r["flight"] = (flight + 1) % FLIGHTS_PER_CHAPTER
		return r
	if flight + 1 >= FLIGHTS_PER_CHAPTER:
		r["chapter_done"] = true
		r["flight"] = 0
		r["chapter"] = chap + 1
		if chap + 1 >= MIXED:
			r["story_done"] = true
	else:
		r["flight"] = flight + 1
	return r


## How many pieces of each place are built (0-3) from the best stars per flight.
static func village(stars: Dictionary) -> Array:
	var out: Array = []
	for c in MIXED:
		var n := 0
		for f in FLIGHTS_PER_CHAPTER:
			if int(stars.get("%d-%d" % [c, f], 0)) > 0:
				n += 1
		out.append(n)
	return out


## Two different breezes for a flight seed (plus the DAILY gate).
static func gate_choices(r: RandomNumberGenerator) -> Array:
	var ids: Array = BREEZES.keys()
	var a := r.randi() % ids.size()
	var b := (a + 1 + r.randi() % (ids.size() - 1)) % ids.size()
	return [ids[a], ids[b], DAILY_GATE]
