extends RefCounted
## KART RACE story and progression: BOLT, a friendly robot, builds race tracks all over the land and wants
## the family to drive the GRAND TOUR. Six places, three new tracks each (made by games/kart_race/trackgen.gd
## from the save's own world seed, so every family's tour is different, and every place gets a little
## bigger and trickier: more ramps, split lanes with a secret shortcut, hills). Each place has a CHAMP who
## races you there (a CPU buddy wearing that place's hat); finishing a place's third race wins its HAT, and
## from then on the drivers wear the hats they have won (saved). After RAINBOW ROAD the tour goes round
## again (bonus tours: bigger, twistier tracks). The first race of every session is TODAY'S TRACK: the same
## track on every machine all day, with a GHOST of the day's best run to race (saved per day).
## Lines are a few words (kids read them; simple mode, picture first). Pure data + small pure functions.

const TrackGen := preload("res://games/kart_race/trackgen.gd")
const Cups := preload("res://games/kart_race/cups.gd")
const Seeded := preload("res://core/seeded.gd")

const GAME_ID := "kart_race"
const RACES_PER_PLACE := 3
const BOLT_COLOR := Color(0.55, 0.75, 1.0)
## Hats in the order they are won: [name, story card picture, colour].
const HATS: Array = [["PARTY HAT", "partyhat", Color(1.0, 0.4, 0.65)], ["TOP HAT", "tophat", Color(0.12, 0.12, 0.16)],
	["COWBOY HAT", "cowboy", Color(0.68, 0.45, 0.25)], ["WIZARD HAT", "wizard", Color(0.55, 0.35, 1.0)],
	["WOOLLY HAT", "beanie", Color(0.9, 0.22, 0.28)], ["CROWN", "crown", Color(1.0, 0.82, 0.2)]]

## name, track palette (track.gd TRACKS), night / rainbow looks, card picture and colour, the champ who
## races there (name, colour), and the place's lines. spec: trackgen extras for its tracks.
const PLACES: Array[Dictionary] = [
	{"name": "SUNNY MEADOW", "palette": 0, "pic": "tree", "color": Color(0.45, 0.85, 0.4), "hills": 2.0,
		"champ": "BUNNY", "champ_color": Color(1.0, 0.7, 0.85), "intro": "Let's race round the land!", "done": "Hop hop! You did it!"},
	{"name": "CANDY HILLS", "palette": 1, "pic": "heart", "color": Color(1.0, 0.5, 0.75), "hills": 4.0,
		"champ": "GUMMY", "champ_color": Color(1.0, 0.4, 0.45), "intro": "Sweet hills ahead!", "done": "Yummy racing!"},
	{"name": "DINO DESERT", "palette": 2, "pic": "sun", "color": Color(1.0, 0.7, 0.3), "hills": 2.5,
		"champ": "DINO", "champ_color": Color(0.55, 0.8, 0.3), "intro": "Big jumps in the sand!", "done": "Roar! Great driving!"},
	{"name": "MOONLIGHT BAY", "palette": 3, "pic": "star", "color": Color(0.55, 0.6, 1.0), "hills": 1.5,
		"champ": "OWL", "champ_color": Color(0.75, 0.55, 1.0), "intro": "Race under the stars!", "done": "Hoot hoot! Hooray!"},
	{"name": "SNOWY PEAKS", "palette": 4, "pic": "snowman", "color": Color(0.7, 0.9, 1.0), "hills": 6.0,
		"champ": "PENGU", "champ_color": Color(0.3, 0.35, 0.5), "intro": "Up the snowy hills!", "done": "Brrr-illiant!"},
	{"name": "RAINBOW ROAD", "palette": 1, "night": true, "rainbow": true, "pic": "crown", "color": Color(1.0, 0.8, 0.3), "hills": 5.0,
		"champ": "BOLT", "champ_color": BOLT_COLOR, "intro": "The last road! Race me!", "done": "You are tour champs!"},
]


static func place(i: int) -> Dictionary:
	return PLACES[posmod(i, PLACES.size())]


## The save's default data (core/save.gd fills missing keys from this).
static func save_defaults() -> Dictionary:
	return {"world": -1, "story_i": 0, "hats": 0, "champs": 0, "golds": 0, "races": 0, "tours": 0,
		"daily": {"date": "", "time": 0.0, "ghost": [], "laps": 0, "frac": 1.0},
		"shelf": {}, "garage": {}, "laps": {}, "mode": "gentle", "cups": 0}


## Story race i -> [place (0..5), race within it (0..2), tour (0 = the story, 1+ bonus tours)].
static func where(i: int) -> Array:
	var pl_i := i / RACES_PER_PLACE
	return [pl_i % PLACES.size(), i % RACES_PER_PLACE, pl_i / PLACES.size()]


## The trackgen spec for story race i (each place's three tracks grow: bigger, more ramps, split lanes).
static func spec(i: int) -> Dictionary:
	var w := where(i)
	var pl := place(int(w[0]))
	var step: int = w[1]
	var tour: int = w[2]
	var first := int(w[0]) == 0 and tour == 0
	var s := {"palette": int(pl.palette), "size": clampf(0.25 + 0.25 * step + 0.15 * tour, 0.0, 1.0),
		"twist": clampf(0.35 + 0.15 * step + 0.1 * tour + 0.04 * int(w[0]), 0.0, 1.0), "hills": float(pl.hills),
		"ramps": 1 + (1 if step >= 1 else 0) + (1 if tour >= 1 and step == 2 else 0),
		"pads": 2 + (1 if step == 2 else 0), "rows": 3,
		"splits": 0 if (first and step == 0) else 1}
	if pl.has("night"):
		s["night"] = bool(pl.night)
	if pl.has("rainbow"):
		s["rainbow"] = true
	return s


## Today's track spec: a place picked by the date, a middling track with a bit of everything.
static func daily_spec(date: String = "") -> Dictionary:
	var r := Seeded.rng(Seeded.daily_seed(GAME_ID, date), "dailyspec")
	var pl_i := r.randi() % PLACES.size()
	var pl := place(pl_i)
	var s := {"palette": int(pl.palette), "size": r.randf_range(0.3, 0.8), "twist": r.randf_range(0.4, 0.8),
		"hills": float(pl.hills), "ramps": r.randi_range(1, 2), "pads": 3, "rows": 3, "splits": 1, "place": pl_i}
	if pl.has("night"):
		s["night"] = bool(pl.night)
	if pl.has("rainbow"):
		s["rainbow"] = true
	return s


## A race description the host sends (a few numbers; every machine rebuilds the same track from it):
## [kind (0 story, 1 today's track), seed, story index (-1 for today's), date's daily spec seed].
static func story_desc(world: int, i: int) -> Array:
	return [0, Seeded.derive(world, "race%d" % i), i, 0]


static func daily_desc(date: String = "") -> Array:
	return [1, Seeded.daily_seed(GAME_ID, date), -1, 0, date if date != "" else Seeded.today()]


static func is_daily(desc: Array) -> bool:
	return desc.size() > 0 and int(desc[0]) == 1


## A cup race (cups.gd desc: [2, seed, cup, race, speed]).
static func is_cup(desc: Array) -> bool:
	return desc.size() > 4 and int(desc[0]) == 2


## A Grand Tour race.
static func is_tour(desc: Array) -> bool:
	return desc.size() > 2 and int(desc[0]) == 0


## The spec for a description.
static func desc_spec(desc: Array) -> Dictionary:
	if is_cup(desc):
		return Cups.spec(int(desc[2]), int(desc[3]), String(desc[4]))
	if is_daily(desc):
		return daily_spec(String(desc[4]) if desc.size() > 4 else "")
	return spec(int(desc[2]))


## The place a description races in.
static func desc_place(desc: Array) -> int:
	if is_cup(desc):
		return -1
	if is_daily(desc):
		return int(daily_spec(String(desc[4]) if desc.size() > 4 else "").get("place", 0))
	return int(where(int(desc[2]))[0])


## The build key for a description (cheap: no generating).
static func key_for(desc: Array) -> String:
	var sp := desc_spec(desc)
	sp.erase("place")
	return TrackGen.key_of(int(desc[1]), sp)


## [track info, key] for a description (deterministic: the same on every machine).
static func track_for(desc: Array) -> Array:
	var sp := desc_spec(desc)
	sp.erase("place")
	var info := TrackGen.generate(int(desc[1]), sp)
	if is_daily(desc):
		info["name"] = "TODAY'S TRACK"
	return [info, TrackGen.key_of(int(desc[1]), sp)]


## How many hats are won after finishing story race i (one per place done, all six at most).
static func hats_after(i: int) -> int:
	return mini(HATS.size(), (i + 1) / RACES_PER_PLACE)


## Which hat kart slot k wears when `won` hats are won (-1: none). Everyone gets one, the newest first.
static func hat_for(slot: int, won: int) -> int:
	if won <= 0:
		return -1
	return posmod(won - 1 - slot, won)
