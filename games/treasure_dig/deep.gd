extends RefCounted
## TREASURE DIG second pass (pure data + small functions; tests/treasure_dig_deep_test.gd validates it):
##   MODES     GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES), picked on the pick orbs once a session: how many
##             warned events a minute, how long they are told first, how long a bonk sits a digger down, how many
##             silly boots in the pile, how often a sparkle shows treasure by itself.
##   GIFTS     CAPTAIN PEG'S TOOLS, three offered on the pick orbs before every island: BIG SPADE (digs wider),
##             DETECTOR (beeps: treasure near a digger sparkles), PEG'S MAP (map pieces sparkle), POLLY (the parrot
##             drops extra golden gems), LUCKY CHARM (boots turn into coins). More unlock as the museum grows.
##   EVENTS    told first by core/warn_rings.gd on every machine, then they happen (events.gd):
##               TIDE      a blue band rolls in from the shore: diggers in it are knocked over (GENTLE: just a push),
##                         and the sea leaves a few coins behind on the sand.
##               DROP      round rings where coconuts fall (snowballs on ice / in winter, lava rocks on the volcano):
##                         a digger under one is bonked (drops what they carry, sits down a moment).
##               GOLD      a gold disc where Polly the parrot drops a golden gem (+3): run there!
##             events(seed, spec) is the same list on every machine; problems() proves it fair.
##   SEASONS   the island dresses for the season (flowers, sun hats, falling leaves, snow) and the season leans the
##             events (summer tides, autumn coconuts, spring gold, winter snowballs). Seeded.season().
##   MUSEUM    every treasure banked goes into Peg's museum for good (saved); a new glass case every CASE_EVERY.

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const IslandGen := preload("res://games/treasure_dig/islandgen.gd")

## events_min: events a minute; warn: seconds told first; stun: seconds a bonked digger sits (0 = just a push);
## drop: carried treasure falls out on a bonk; boots: added to the island's boot share; auto: seconds between
## the helpful sparkles that show buried treasure by themselves; drops: coconuts in one DROP.
const MODES := {
	"gentle": {"events_min": 1.2, "warn": 3.0, "stun": 0.0, "drop": false, "boots": -0.08, "auto": 4.0, "drops": 2},
	"brave": {"events_min": 2.0, "warn": 2.3, "stun": 0.8, "drop": true, "boots": 0.0, "auto": 5.0, "drops": 3},
	"hard": {"events_min": 3.0, "warn": 1.7, "stun": 1.4, "drop": true, "boots": 0.06, "auto": 7.0, "drops": 4},
}
const MIN_WARN := 1.5
const SPEED := 4.5  # main.gd SPEED (beach units a second)
const GAP := 3.0  # quiet seconds between two events
const STAY := 0.6  # seconds a tell glows hot while it goes off
const START := 8.0  # no event in the first seconds of a round (or 20% of a short one)
const END := 5.0
## Tide: a band this deep from the shore inwards, this wide.
const TIDE_DEPTH := 2.8
const TIDE_WIDTH := 6.0
const TIDE_COINS := {"gentle": 3, "brave": 2, "hard": 2}
const DROP_R := 1.1
const GOLD_R := 0.9
const TIDE_COLOR := Color(0.0, 0.45, 1.0)  # sea blue (a deep blue read lilac over the pale sand)
const DROP_COLOR := Color(1.0, 0.2, 0.2)  # red: "look out" (gold is the good one)
const GOLD_COLOR := Color(0.9, 0.48, 0.0)  # a deep gold: shows on the pale sunny and jungle sand (palette.gd)
const KINDS: Array[String] = ["tide", "drop", "gold"]
## Season -> event weights (tide, drop, gold) and how the island dresses.
const SEASONS := {
	"spring": {"weights": [1.0, 1.0, 1.6], "deco": "flowers", "pic": "daisy", "line": "Spring flowers!"},
	"summer": {"weights": [1.8, 0.8, 1.0], "deco": "hats", "pic": "sun", "line": "Summer tides!"},
	"autumn": {"weights": [0.8, 1.8, 1.0], "deco": "leaves", "pic": "acorn", "line": "Coconut season!"},
	"winter": {"weights": [1.0, 1.4, 1.0], "deco": "snow", "pic": "snowman", "line": "Snowy island!"},
}
## What falls in a DROP: [name, colour, picture].
const DROPS := {"coconut": ["COCONUT", Color(0.45, 0.28, 0.15)], "snowball": ["SNOWBALL", Color(0.92, 0.96, 1.0)],
	"lava": ["LAVA ROCK", Color(0.9, 0.25, 0.05)]}
## Peg's tools: id, name, picture, a short line, museum cases needed.
const GIFTS: Array[Dictionary] = [
	{"id": "spade", "name": "BIG SPADE", "pic": "bigspade", "line": "Dig big!", "color": Color(0.95, 0.65, 0.3), "unlock": 0},
	{"id": "detector", "name": "DETECTOR", "pic": "detector", "line": "Beep beep!", "color": Color(0.5, 0.85, 1.0), "unlock": 0},
	{"id": "map", "name": "PEG'S MAP", "pic": "treasuremap", "line": "Find the map!", "color": Color(1.0, 0.45, 0.4), "unlock": 0},
	{"id": "parrot", "name": "POLLY", "pic": "parrot", "line": "Polly helps!", "color": Color(0.45, 0.95, 0.45), "unlock": 2},
	{"id": "lucky", "name": "LUCKY CHARM", "pic": "horseshoe", "line": "No more boots!", "color": Color(1.0, 0.85, 0.3), "unlock": 5},
]
const SPADE_X := 1.6  # BIG SPADE: dig radius times this
const DETECT_R := 3.5  # DETECTOR: treasure this near a digger sparkles
const DETECT_EVERY := 3.0
const PARROT_GOLD := 2  # POLLY: extra golden gems a round
const CASE_EVERY := 20  # treasures banked for each new museum case
const MAX_CASES := 30
const MUSEUM_KINDS: Array[String] = ["coins", "gems", "boots", "maps", "golden"]


static func mode_of(id: String) -> String:
	var m := String(PickOrbs.ALIASES.get(id, id))
	return m if MODES.has(m) else "brave"


static func mode_data(id: String) -> Dictionary:
	return MODES[mode_of(id)]


## Problems with the mode table (GENTLE <= BRAVE <= HARD in every way that makes it harder).
static func ordered() -> Array:
	var out: Array = []
	var g: Dictionary = MODES.gentle
	var b: Dictionary = MODES.brave
	var h: Dictionary = MODES.hard
	for k in ["events_min", "stun", "boots", "auto", "drops"]:
		if not (float(g[k]) <= float(b[k]) and float(b[k]) <= float(h[k])):
			out.append("%s not gentle <= brave <= hard" % k)
	if not (float(g.warn) >= float(b.warn) and float(b.warn) >= float(h.warn)):
		out.append("warnings not longest on gentle")
	if float(h.warn) < MIN_WARN:
		out.append("hard warns under %.1f s" % MIN_WARN)
	if bool(g.drop):
		out.append("gentle drops carried treasure")
	return out


static func season_data(season: String) -> Dictionary:
	return SEASONS.get(season, SEASONS.summer)


## What falls in a DROP on this island in this season.
static func drop_kind(island_kind: String, season: String) -> String:
	if island_kind == "volcano":
		return "lava"
	if island_kind == "ice" or season == "winter":
		return "snowball"
	return "coconut"


## The island's spec with the mode's boots (islandgen.gd reads spec.boots_add).
static func island_spec(desc: Dictionary, mode: String) -> Dictionary:
	var sp := desc.duplicate()
	sp["boots_add"] = float(mode_data(mode).boots)
	return sp


## This round's events: [[t, "tide", angle], [t, "drop", [Vector3...]], [t, "gold", Vector3]] (beach-local,
## sorted by t). spec: {mode, time, season, kind, rocks (islandgen rocks), extra_gold, scale (bots: more events)}.
static func events(seed_value: int, spec: Dictionary) -> Array:
	var r := Seeded.rng(seed_value, "events")
	var md := mode_data(String(spec.get("mode", "brave")))
	var time := float(spec.get("time", 120.0))
	var warn := float(md.warn)
	var start := minf(START, time * 0.2)
	var stop := time - minf(END, time * 0.15)
	var n := roundi(float(md.events_min) * time / 60.0 * float(spec.get("scale", 1.0)))
	var w: Array = season_data(String(spec.get("season", "summer"))).weights
	var kinds: Array = []
	for k in n:
		kinds.append(KINDS[Seeded.weighted(r, w)])
	for k in int(spec.get("extra_gold", 0)):
		kinds.append("gold")
	var slot := warn + STAY + GAP
	var fit := floori((stop - start) / slot) + 1
	kinds = Seeded.shuffled(r, kinds).slice(0, maxi(0, fit))
	var out: Array = []
	if kinds.is_empty():
		return out
	# Spread evenly with a little jitter, never closer than one slot.
	var span := stop - start
	var each := span / kinds.size()
	var rocks: Array = spec.get("rocks", [])
	for i in kinds.size():
		var t := start + warn + each * i + r.randf_range(0.0, maxf(0.0, each - slot))
		t = minf(t, stop)
		match String(kinds[i]):
			"tide":
				out.append([t, "tide", r.randf() * TAU])
			"drop":
				var pts: Array = []
				for tries in 60:
					if pts.size() >= int(md.drops):
						break
					var p := _spot(r, IslandGen.CHEST_CLEAR + DROP_R, IslandGen.R - DROP_R * 0.5)
					if _clear(p, pts, DROP_R * 2.0 + 0.4, rocks):
						pts.append(p)
				out.append([t, "drop", pts])
			"gold":
				var g := Vector3.ZERO
				for tries in 40:
					g = _spot(r, IslandGen.CHEST_CLEAR + 0.5, IslandGen.R - 1.0)
					if _clear(g, [], 0.0, rocks):
						break
				out.append([t, "gold", g])
	out.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	return out


static func _spot(r: RandomNumberGenerator, lo: float, hi: float) -> Vector3:
	var a := r.randf() * TAU
	return Vector3(cos(a), 0.0, sin(a)) * sqrt(r.randf_range(lo * lo, hi * hi))


static func _clear(p: Vector3, pts: Array, gap: float, rocks: Array) -> bool:
	for q in pts:
		if (q as Vector3).distance_to(p) < gap:
			return false
	for rk in rocks:
		if (rk[0] as Vector3).distance_to(p) < float(rk[1]) + 0.6:
			return false
	return true


## Tide band: [from (on the shore), dir (inwards), size (depth, width)] for warn_rings' "line".
static func tide_band(angle: float) -> Array:
	var out_dir := Vector3(cos(angle), 0.0, sin(angle))
	return [out_dir * (IslandGen.ISLAND + 0.3), -out_dir, Vector2(TIDE_DEPTH + 0.3 + (IslandGen.ISLAND - IslandGen.R), TIDE_WIDTH)]


## Where the sea leaves its coins after a tide (on the sand inside the band).
static func tide_coins(angle: float, mode: String, seed_value: int) -> Array:
	var r := Seeded.rng(seed_value, "tide%.3f" % angle)
	var out_dir := Vector3(cos(angle), 0.0, sin(angle))
	var side := Vector3(-out_dir.z, 0.0, out_dir.x)
	var out: Array = []
	var n := int(TIDE_COINS[mode_of(mode)])
	for k in n:
		var across := (float(k) - (n - 1) * 0.5) * 1.4 + r.randf_range(-0.2, 0.2)
		out.append(out_dir * (IslandGen.R - 1.2 - r.randf_range(0.0, 0.8)) + side * across)
	return out


## Reasons this round's events are unfair (empty = fine): told too late, too close together, on the chest,
## off the island, under a rock, overlapping, or too big to walk out of while it is told.
static func problems(list: Array, spec: Dictionary) -> Array:
	var why: Array = []
	var md := mode_data(String(spec.get("mode", "brave")))
	var warn := float(md.warn)
	var time := float(spec.get("time", 120.0))
	if warn < MIN_WARN:
		why.append("told only %.1f s early" % warn)
	var last := -INF
	for e in list:
		var t := float(e[0])
		if t - warn < 0.0 or t > time:
			why.append("an event at %.1f s outside the round" % t)
		if t - last < warn + STAY + GAP - 0.01:
			why.append("two events %.1f s apart" % (t - last))
		last = t
		match String(e[1]):
			"tide":
				var band := tide_band(float(e[2]))
				var sz: Vector2 = band[2]
				# Anyone in the band walks out of it (inwards past its depth, or sideways) before it hits.
				var out_d := minf(sz.x - (IslandGen.ISLAND - IslandGen.R), sz.y * 0.5)
				if out_d / SPEED > warn - 0.4:
					why.append("a tide too big to walk out of (%.1f)" % out_d)
				if sz.x > IslandGen.ISLAND - IslandGen.CHEST_CLEAR:
					why.append("a tide reaching the chest")
				for c in tide_coins(float(e[2]), String(spec.get("mode", "brave")), 1):
					var d := Vector2((c as Vector3).x, (c as Vector3).z).length()
					if d > IslandGen.R - 0.3 or d < IslandGen.CHEST_CLEAR:
						why.append("a tide coin off the sand (%.2f)" % d)
			"drop":
				var pts: Array = e[2]
				if pts.is_empty():
					why.append("a drop with nothing falling")
				if pts.size() > int(md.drops):
					why.append("too many drops")
				if DROP_R / SPEED > warn - 0.4:
					why.append("a drop too big to step out of")
				for i in pts.size():
					var p: Vector3 = pts[i]
					var d := Vector2(p.x, p.z).length()
					if d < IslandGen.CHEST_CLEAR + DROP_R - 0.01:
						why.append("a drop on the chest (%.2f)" % d)
					if d > IslandGen.R:
						why.append("a drop in the sea (%.2f)" % d)
					for j in range(i + 1, pts.size()):
						if p.distance_to(pts[j]) < DROP_R * 2.0 + 0.39:
							why.append("two drops overlap")
			"gold":
				var g: Vector3 = e[2]
				var gd := Vector2(g.x, g.z).length()
				if gd > IslandGen.R - 0.5 or gd < IslandGen.CHEST_CLEAR:
					why.append("a gold drop out of reach (%.2f)" % gd)
				for rk in spec.get("rocks", []):
					if (rk[0] as Vector3).distance_to(g) < float(rk[1]) + 0.5:
						why.append("a gold drop under a rock")
			_:
				why.append("an unknown event %s" % str(e[1]))
	return why


# --- Gifts ------------------------------------------------------------------------------------------------

static func unlocked(cases: int) -> Array:
	var out: Array = []
	for g in GIFTS:
		if cases >= int(g.unlock):
			out.append(String(g.id))
	return out


static func gift(id: String) -> Dictionary:
	for g in GIFTS:
		if String(g.id) == id:
			return g
	return GIFTS[0]


## Three different unlocked tools: the newest unlock always among them, not the last one again when there are
## others (the same on every machine for a seed).
static func gift_choices(cases: int, last: String, seed_value: int) -> Array:
	var un := unlocked(cases)
	var newest: String = un[un.size() - 1]
	var pool: Array = []
	for id in un:
		if id != newest and (id != last or un.size() <= 3):
			pool.append(id)
	pool = Seeded.shuffled(Seeded.rng(seed_value, "gifts"), pool)
	var out: Array = [newest] if newest != last or un.size() <= 3 else []
	for id in pool:
		if out.size() >= 3:
			break
		out.append(id)
	if out.size() < 3:
		for id in un:
			if out.size() < 3 and not out.has(id):
				out.append(id)
	return Seeded.shuffled(Seeded.rng(seed_value, "gift order"), out)  # (the newest not always on the same orb)


# --- Museum -----------------------------------------------------------------------------------------------

static func museum_total(m: Dictionary) -> int:
	var n := 0
	for k in MUSEUM_KINDS:
		n += int(m.get(k, 0))
	return n


static func cases(m: Dictionary) -> int:
	return mini(MAX_CASES, museum_total(m) / CASE_EVERY)


## What a museum case shows (cycles through the kinds of treasure, the first ones coins and gems).
static func case_kind(i: int) -> String:
	return ["coins", "gems", "maps", "coins", "gems", "golden", "boots"][i % 7]
