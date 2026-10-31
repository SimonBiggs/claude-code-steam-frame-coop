extends RefCounted
## KART RACE cups, karts, parts and speeds: pure data + small pure functions (tests/kart_trackgen_test.gd checks
## them over many seeds; main.gd + pit.gd use them).
##  - BOLT'S CUPS: four cups of three seeded tracks each (made by trackgen.gd from the save's world seed, so every
##    family's cups are their own), each with its own theme and HAZARDS: CANDY (sticky chocolate puddles, bouncy
##    gumdrops), JUNGLE (mud puddles, mossy rocks), ICE (slippy ice, snowballs) and SPACE (floaty moon pads that
##    hop you up, meteor rocks). The cup's champ drives CPU slot 0. Points over the three races (the full game's
##    POINTS) decide the cup: the best human's place gives a GOLD / SILVER / BRONZE cup for BOLT'S TROPHY SHELF
##    (GENTLE: everyone who finishes a cup gets at least bronze).
##  - KARTS: LIGHT (zippy, quick to speed up, turns tight, gets bumped about), MEDIUM, HEAVY (a little faster at
##    the top, slower to get going, shoves others). Picked per seat at the PIT STOP gates, saved in the garage.
##  - PARTS: cosmetic kart parts (spoiler, flag, ducky, crown, flames, balloon), one more for every new cup medal
##    on the shelf; the spanner gate at the pit stop fits the next one.
##  - SPEEDS: GENTLE (the simple game: strong catch-up, CPUs ease off), ZOOM (150cc-style: faster karts, weaker
##    catch-up, CPUs drive their best and dodge puddles, more hazards) and TIME TRIAL (no CPUs, no boxes: race
##    the ghost of your best lap).

const Seeded := preload("res://core/seeded.gd")

const RACES := 3
const CUPS: Array[Dictionary] = [
	{"id": "candy", "name": "CANDY CUP", "palette": 1, "pic": "lollipop", "color": Color(1.0, 0.5, 0.75), "hz": "candy", "hills": 4.0,
		"champ": "GUMMY", "champ_color": Color(1.0, 0.4, 0.45), "intro": "Sticky sweet roads!", "done": "Yummy racing!"},
	{"id": "jungle", "name": "JUNGLE CUP", "palette": 5, "pic": "toucan", "color": Color(0.35, 0.85, 0.4), "hz": "jungle", "hills": 3.0,
		"champ": "MONKEY", "champ_color": Color(0.7, 0.45, 0.25), "intro": "Mud and rocks ahead!", "done": "Ooh ooh! Hooray!"},
	{"id": "ice", "name": "ICE CUP", "palette": 4, "pic": "snowflake", "color": Color(0.65, 0.9, 1.0), "hz": "ice", "hills": 4.5,
		"champ": "PENGU", "champ_color": Color(0.3, 0.35, 0.5), "intro": "Slippy slidey ice!", "done": "Brrr-illiant!"},
	{"id": "space", "name": "SPACE CUP", "palette": 6, "pic": "planet", "color": Color(0.7, 0.5, 1.0), "hz": "space", "hills": 2.0,
		"champ": "COMET", "champ_color": Color(0.45, 1.0, 0.85), "intro": "Bounce on the moon!", "done": "Out of this world!"},
]
## What each cup's hazards do: patch = a patch on the road (slow: top speed down; ice: hardly any grip; float: a
## floaty hop), bump = a round thing on the road you bounce off. Names are for the log and the look.
const HAZARDS := {
	"candy": {"patch": "slow", "patch_look": "chocolate", "bump_look": "gumdrop"},
	"jungle": {"patch": "slow", "patch_look": "mud", "bump_look": "rock"},
	"ice": {"patch": "ice", "patch_look": "ice", "bump_look": "snowball"},
	"space": {"patch": "float", "patch_look": "moon", "bump_look": "meteor"},
}
const SLOW_TOP := 0.62  # top speed on a sticky patch (chocolate / mud)
const ICE_GRIP := 0.45  # turning on ice
const FLOAT_HOP := 4.0  # m/s up from a floaty moon pad
const FLOAT_GRAVITY := 0.55  # gravity while floating (x normal)

## Kart classes: top speed / acceleration / turning / how far bumps push you / size.
const KART_ORDER: Array[String] = ["light", "medium", "heavy"]
const KARTS := {
	"light": {"pic": "kartsmall", "top": 0.97, "accel": 1.22, "turn": 1.12, "push": 1.4, "shove": 0.7, "scale": 0.86},
	"medium": {"pic": "kart", "top": 1.0, "accel": 1.0, "turn": 1.0, "push": 1.0, "shove": 1.0, "scale": 1.0},
	"heavy": {"pic": "kartbig", "top": 1.04, "accel": 0.84, "turn": 0.92, "push": 0.55, "shove": 1.5, "scale": 1.16},
}
## Cosmetic parts in the order they unlock (one per cup medal on the shelf) and their pictures.
const PARTS: Array[String] = ["spoiler", "flag", "duck", "crown", "flames", "balloon"]
const PART_PICS := {"spoiler": "spoiler", "flag": "flag", "duck": "duckling", "crown": "crown", "flames": "fire", "balloon": "balloon"}

## Speeds. speed/accel: kart multipliers; catch: the most a kart far behind the leader speeds up; cpu_skill: CPU top
## speed (x a human kart's); cpu_ease: CPUs slow down when well ahead of the humans; cpu_dodge: CPUs steer round
## puddles too (they always dodge bumpers); hazards: more of them; cpus/boxes: CPU buddies and ? boxes at all.
const MODE_ORDER: Array[String] = ["gentle", "zoom", "trial"]
const MODES := {
	"gentle": {"pic": "snail", "speed": 1.0, "accel": 1.0, "catch": 0.22, "cpu_skill": 0.92, "cpu_ease": true, "cpu_dodge": false,
		"hazards": 0, "cpus": true, "boxes": true, "slip": 0.7},
	"zoom": {"pic": "rocket", "speed": 1.18, "accel": 1.15, "catch": 0.11, "cpu_skill": 0.99, "cpu_ease": false, "cpu_dodge": true,
		"hazards": 1, "cpus": true, "boxes": true, "slip": 1.1},
	"trial": {"pic": "clock", "speed": 1.0, "accel": 1.0, "catch": 0.0, "cpu_skill": 0.92, "cpu_ease": true, "cpu_dodge": false,
		"hazards": 0, "cpus": false, "boxes": false, "slip": 0.7},
}
const MEDALS: Array[String] = ["", "BRONZE", "SILVER", "GOLD"]
const MEDAL_COLORS: Array[Color] = [Color(0.6, 0.6, 0.65), Color(0.85, 0.5, 0.25), Color(0.85, 0.88, 0.95), Color(1.0, 0.82, 0.2)]
const POINTS: Array[int] = [10, 8, 6, 5, 4, 3, 2, 1, 1, 1]


static func cup(i: int) -> Dictionary:
	return CUPS[posmod(i, CUPS.size())]


static func mode(m: String) -> Dictionary:
	return MODES.get(m, MODES["gentle"])


static func kart(c: String) -> Dictionary:
	return KARTS.get(c, KARTS["medium"])


## The trackgen spec for race r (0..2) of cup c at speed m: each cup's tracks grow (bigger, ramps, split lanes)
## and get more hazards; ZOOM adds a few more.
static func spec(c: int, r: int, m: String = "gentle") -> Dictionary:
	var cp := cup(c)
	var extra := int(mode(m).hazards)
	var s := {"palette": int(cp.palette), "size": 0.6 + 0.3 * r, "twist": clampf(0.4 + 0.14 * r + 0.03 * c, 0.0, 1.0),
		"hills": float(cp.hills), "ramps": 1 + (1 if r >= 1 else 0), "pads": 2 + (1 if r == 2 else 0), "rows": 3,
		"splits": 0 if r == 0 else 1, "hz": String(cp.hz), "patches": 1 + mini(r, 1) + extra, "bumpers": r + (extra if r < 2 else 0)}
	return s


## A race description the host sends (every machine rebuilds the same track from it, see story.gd).
static func desc(world: int, c: int, r: int, m: String) -> Array:
	return [2, Seeded.derive(world, "cup%d_%d" % [posmod(c, CUPS.size()), r]), posmod(c, CUPS.size()), r, m]


## The medal (0 none .. 3 gold) for finishing a cup in `place` (the best human's place on points).
static func medal_for(place: int, m: String) -> int:
	if m == "trial":
		return 0
	var md := clampi(4 - place, 0, 3)
	if m == "gentle":
		md = maxi(1, md)  # gentle: finishing a cup always wins a cup for the shelf
	return md


## Shelf key: "candy:gentle".
static func shelf_key(c: int, m: String) -> String:
	return "%s:%s" % [String(cup(c).id), m]


## How many medals are on the shelf (any colour).
static func medals(shelf: Variant) -> int:
	var n := 0
	if shelf is Dictionary:
		for k in shelf:
			if int(shelf[k]) > 0:
				n += 1
	return n


## Golds on the shelf.
static func golds(shelf: Variant) -> int:
	var n := 0
	if shelf is Dictionary:
		for k in shelf:
			if int(shelf[k]) >= 3:
				n += 1
	return n


## The parts unlocked by the shelf (one per medal, in PARTS order).
static func parts_unlocked(shelf: Variant) -> Array[String]:
	var out: Array[String] = []
	for i in mini(medals(shelf), PARTS.size()):
		out.append(PARTS[i])
	return out


## The part after `part` among the unlocked ones (wraps to none: "").
static func next_part(part: String, shelf: Variant) -> String:
	var un := parts_unlocked(shelf)
	if un.is_empty():
		return ""
	var i := un.find(part)
	if i < 0:
		return un[0]
	return "" if i == un.size() - 1 else un[i + 1]


## The first cup without a medal at speed m (else the next after `after`).
static func next_cup(shelf: Variant, m: String, after: int = -1) -> int:
	for k in CUPS.size():
		var c := posmod(after + 1 + k, CUPS.size())
		if not (shelf is Dictionary and int((shelf as Dictionary).get(shelf_key(c, m), 0)) > 0):
			return c
	return posmod(after + 1, CUPS.size())


## Cup points for the places of a race (same order as `places`).
static func points(place: int) -> int:
	return POINTS[clampi(place - 1, 0, POINTS.size() - 1)]


## Problems with the data (empty = fine): every cup has a known hazard set and a picture, kart classes are
## balanced (no class best at everything), modes have what main.gd reads, CPUs are never faster than humans.
static func check(has_picture: Callable) -> Array[String]:
	var why: Array[String] = []
	if CUPS.size() < 3 or CUPS.size() > 4:
		why.append("3-4 cups (%d)" % CUPS.size())
	var ids := {}
	for c in CUPS:
		if not HAZARDS.has(String(c.hz)):
			why.append("%s: unknown hazards %s" % [c.name, c.hz])
		if not has_picture.call(String(c.pic)):
			why.append("%s: no picture %s" % [c.name, c.pic])
		if ids.has(c.id):
			why.append("two cups called %s" % c.id)
		ids[c.id] = true
	for k in KART_ORDER:
		var kc: Dictionary = KARTS[k]
		if not has_picture.call(String(kc.pic)):
			why.append("kart %s: no picture" % k)
		var best := 0
		for stat in ["top", "accel", "turn"]:
			var top := true
			for o in KART_ORDER:
				if o != k and float(KARTS[o][stat]) >= float(kc[stat]):
					top = false
			best += 1 if top else 0
		if best > 2:
			why.append("kart %s is best at too much" % k)
		# Balance: a kart's top-speed edge costs it acceleration (and the other way round).
		if float(kc.top) > 1.0 and float(kc.accel) >= 1.0 or float(kc.accel) > 1.0 and float(kc.top) >= 1.0:
			why.append("kart %s has no trade-off" % k)
	for p in PARTS:
		if not PART_PICS.has(p) or not has_picture.call(String(PART_PICS[p])):
			why.append("part %s: no picture" % p)
	for m in MODE_ORDER:
		var md: Dictionary = MODES[m]
		for key in ["pic", "speed", "accel", "catch", "cpu_skill", "cpu_ease", "cpu_dodge", "hazards", "cpus", "boxes", "slip"]:
			if not md.has(key):
				why.append("mode %s lacks %s" % [m, key])
		if not has_picture.call(String(md.get("pic", ""))):
			why.append("mode %s: no picture" % m)
		# CPU fairness: a CPU (medium kart, with the catch-up) never out-tops a human medium kart with the catch-up.
		if float(md.get("cpu_skill", 1.0)) > 1.0:
			why.append("mode %s: CPUs faster than people" % m)
	if float(MODES.gentle.catch) <= float(MODES.zoom.catch):
		why.append("gentle has the stronger catch-up")
	if float(MODES.gentle.cpu_skill) >= float(MODES.zoom.cpu_skill):
		why.append("zoom CPUs are the better drivers")
	return why
