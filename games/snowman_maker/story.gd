extends RefCounted
## SNOWMAN MAKER story and progression: Tumble the penguin is getting the snowy village ready for the
## Winter Fair. Every snow day, visitors come and wish for a snowman (a picture of the hat they want);
## a day with at least one star builds a piece of that chapter's place round the garden (it stays,
## saved). Five chapters of three days, then bonus days; the first game of each date is the DAILY
## GARDEN (the same garden on every machine that day). Lines are short and kind (kids read them).
## Pure data + small pure functions (no nodes), so tests and every machine agree.

const DAYS_PER_CHAPTER := 3
const MIXED := 5  ## the chapter id of DAILY gardens and bonus days after the story (everything mixed)

# Item kinds (carried, in boxes, on snowmen). 0 = carrot, 1.. = hats.
const CARROT := 0
const TOP_HAT := 1
const BEANIE := 2
const CROWN := 3
const HAT_NAMES := ["CARROT", "TOP HAT", "WOOLLY HAT", "CROWN"]

## sky: core/sky_kit.gd preset. place: what gets built. pic: core/story_card.gd picture.
## hats: the hats that day's boxes hold (and visitors wish for). new: shown on the chapter's first day.
const CHAPTERS: Array[Dictionary] = [
	{"name": "COSY GARDEN", "sky": "day", "place": "IGLOO", "pic": "penguin", "hats": [TOP_HAT],
		"who": "TUMBLE", "intro": "Brrr! Let's make snow friends for the Winter Fair!", "new": "Roll, stack, nose, hat!",
		"done": "My igloo is ready! Thank you!"},
	{"name": "PINE WOOD", "sky": "morning", "place": "COCOA HUT", "pic": "tree", "hats": [TOP_HAT, BEANIE],
		"who": "OLLIE OWL", "intro": "Hoo! Trees grew in the garden!", "new": "Look! Which hat do they wish for?",
		"done": "Warm cocoa for everyone!"},
	{"name": "FROZEN POND", "sky": "dawn", "place": "SKATING RINK", "pic": "wave", "hats": [TOP_HAT, BEANIE],
		"who": "SKIP THE SEAL", "intro": "Wheee! The pond froze over!", "new": "Snowballs slide on the ice!",
		"done": "The skating rink is open!"},
	{"name": "DEEP DRIFTS", "sky": "sunset", "place": "SLED HILL", "pic": "cloud", "hats": [TOP_HAT, BEANIE],
		"who": "BIG BUNNY", "intro": "So much snow fell last night!", "new": "Deep snow makes big snowballs fast!",
		"done": "Sleds ready! Whoosh!"},
	{"name": "NORTH STAR", "sky": "stormy", "place": "ICE CASTLE", "pic": "castle", "hats": [TOP_HAT, BEANIE, CROWN],
		"who": "THE SNOW QUEEN", "intro": "I come for the Winter Fair!", "new": "A crown! Make a royal snowman!",
		"done": "The Winter Fair is ready! Hooray!"},
	{"name": "SNOW DAY", "sky": "day", "place": "", "pic": "snowman", "hats": [TOP_HAT, BEANIE, CROWN],
		"who": "TUMBLE", "intro": "More snow! Let's play!", "new": "", "done": "What a snowy day!"},
]

## Visitors who wish for snowmen: [creatures.gd monster kind, name, colour html].
const VISITORS: Array = [["bunny", "BUNNY", "f2a7c3"], ["fox", "FOX", "ff9a4d"], ["cat", "KITTY", "c9a0ff"],
	["dog", "PUPPY", "c79a6b"], ["frog", "FROG", "7fd36a"], ["penguin", "BABY PENGUIN", "8ec5ff"]]

const TUMBLE_LINES: Array[String] = ["Let's roll!", "You are snow good at this!", "Big ball at the bottom!",
	"Brrr! Building keeps us warm!", "The village loves snowmen!"]
const TUMBLE_RETRY: Array[String] = ["Nearly! Let's try again!", "Snow problem! Again!", "We can do it together!"]

## Unlocks by snowflakes (total stars ever): [flakes, id, label]. All show on the snowmen.
const UNLOCKS: Array = [[3, "scarf", "SCARVES"], [8, "buttons", "SWEETIE BUTTONS"], [15, "gold_carrot", "GOLDEN CARROTS"],
	[24, "fireworks", "SNOW FIREWORKS"], [36, "rainbow", "RAINBOW SNOW"]]


static func chapter(c: int) -> Dictionary:
	return CHAPTERS[clampi(c, 0, CHAPTERS.size() - 1)]


## The save's default data (core/save.gd fills missing keys from this, so old saves just gain them).
static func save_defaults() -> Dictionary:
	return {"best": 0, "chapter": 0, "day": 0, "stars": {}, "misses": 0, "laps": 0, "daily": {},
		"days": 0, "extra_flakes": 0, "made": 0, "wishes": 0}


## Total stars ever earned (each story day counts its best) plus bonus-day stars.
static func flakes(stars: Dictionary, extra: int = 0) -> int:
	var n := extra
	for k in stars:
		n += int(stars[k])
	return n


static func unlocked(flake_count: int) -> Array:
	var out: Array = []
	for u in UNLOCKS:
		if flake_count >= int(u[0]):
			out.append(String(u[1]))
	return out


static func newly_unlocked(before: int, after: int) -> Array:
	var out: Array = []
	for u in UNLOCKS:
		if before < int(u[0]) and after >= int(u[0]):
			out.append(String(u[2]))
	return out


## Points for a day: every snowman 1, every granted wish 1 more.
static func points(snowmen: int, wishes: int) -> int:
	return snowmen + wishes


## Star goals for a day [1, 2, 3 stars] in points. builders = TV players + the VR builder (Tumble helps
## a lone builder, so one builder is still a team). A little harder per chapter and per lap after the
## story; kinder after missed days (never below half).
static func goals(builders: int, chap: int, misses: int, laps: int, seconds: float) -> Array:
	var b := clampi(builders, 1, 8)
	var per_min := 1.0 + 0.45 * float(b - 1)  # points per minute for one star
	var hard := 1.0 + 0.05 * float(mini(chap, 4)) + 0.12 * float(laps)
	var kind := maxf(0.5, 1.0 - 0.2 * float(misses))
	var g1 := maxi(1, int(round(per_min * seconds / 60.0 * hard * kind)))
	return [g1, maxi(g1 + 1, int(round(g1 * 1.8))), maxi(g1 + 2, int(round(g1 * 2.6)))]


static func stars_for(score: int, g: Array) -> int:
	var s := 0
	for v in g:
		if score >= int(v):
			s += 1
	return s


## Progress after a story / bonus day: {chapter, day, laps, misses, advanced, chapter_done, story_done}.
static func advance(chap: int, day: int, laps: int, misses: int, stars: int) -> Dictionary:
	var r := {"chapter": chap, "day": day, "laps": laps, "misses": misses, "advanced": false,
		"chapter_done": false, "story_done": false}
	if stars <= 0:
		r["misses"] = misses + 1
		return r
	r["misses"] = 0
	r["advanced"] = true
	if chap >= MIXED:
		r["laps"] = laps + 1 if day >= DAYS_PER_CHAPTER - 1 else laps
		r["day"] = (day + 1) % DAYS_PER_CHAPTER
		return r
	if day + 1 >= DAYS_PER_CHAPTER:
		r["chapter_done"] = true
		r["day"] = 0
		r["chapter"] = chap + 1
		r["story_done"] = chap + 1 >= MIXED
	else:
		r["day"] = day + 1
	return r


## How many pieces of each place are built (0-3) from the best stars per day.
static func village(stars: Dictionary) -> Array:
	var out: Array = []
	for c in MIXED:
		var n := 0
		for d in DAYS_PER_CHAPTER:
			if int(stars.get("%d-%d" % [c, d], 0)) > 0:
				n += 1
		out.append(n)
	return out


## Which round to play next: [mode, chapter, day]. The first round of each date is the daily garden
## (once the first chapter is done, so a brand-new builder starts gently in the cosy garden).
static func next_round(data: Dictionary, today_key: String) -> Array:
	var daily: Dictionary = data.get("daily", {})
	var chap := mini(int(data.get("chapter", 0)), MIXED)
	if chap >= 1 and not daily.has(today_key):
		return ["daily", MIXED, 0]
	return ["bonus" if chap >= MIXED else "story", chap, int(data.get("day", 0))]
