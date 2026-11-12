extends RefCounted
## WHACK-A-MOLE second pass (pure data + small functions; tests/whack_a_mole_deep_test.gd validates it):
##   MODES     GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES), picked on the pick orbs once a session: how long a
##             mole stays up, how busy the round is, how many warned tricks a minute, how long they are told first,
##             how long a stampede sits a hammer-kid down.
##   GIFTS     FIG'S HAMMER GIFTS, three offered on the pick orbs before every round: BIG HAMMER (bonks reach further),
##             SLEEPY DUST (moles stay up longer), GOLD GLOVE (more golden moles), BOING HAMMER (a bonk bonks the moles
##             next to it too), CARROT BAG (a bunny left alone gives double carrots). More unlock as the holiday
##             garden grows.
##   TRICKS    told first by core/warn_rings.gd on every machine, then they happen (tricks.gd):
##               GOLD      a gold disc on a hole: a golden mole pops out there (worth 5) - get ready!
##               STAMPEDE  a red band across a row of holes: a line of moles runs along it and pops up in every hole
##                         of the row at once. Hammer-kids standing in it get bumped (GENTLE: just a hop).
##             tricks(seed, spec, round) is the same list on every machine; problems() proves it fair against the
##             round's own moles (never on the KING, never two golden moles at once, time to step out of the band).
##   SEASONS   the garden dresses for the season (Seeded.season): spring flowers, summer sunflowers, autumn leaves and
##             pumpkins, winter snow; the season leans the tricks (spring gold, summer stampedes).
##   HOLIDAY   every HOLIDAY_EVERY moles bonked, a tired mole goes on holiday to the deckchairs round Fig's garden
##             (saved, it stays for good): the holiday garden only grows.

const Seeded := preload("res://core/seeded.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const RoundGen := preload("res://games/whack_a_mole/roundgen.gd")
const Props := preload("res://games/whack_a_mole/props.gd")

## stay / gap: roundgen.gd multipliers (moles stay up longer / waves further apart on GENTLE); tricks_min: warned tricks
## a minute; warn: seconds told first; stun: seconds a stampede sits a hammer-kid (0 = just a hop); gold_stay /
## herd_stay: seconds a trick's golden mole / stampede moles stay up; herd: moles in a stampede (holes of the row).
const MODES := {
	"gentle": {"stay": 1.35, "gap": 1.2, "tricks_min": 1.5, "warn": 3.0, "stun": 0.0, "gold_stay": 3.0, "herd_stay": 2.2, "herd": 3},
	"brave": {"stay": 1.0, "gap": 1.0, "tricks_min": 2.2, "warn": 2.4, "stun": 0.7, "gold_stay": 2.2, "herd_stay": 1.6, "herd": 4},
	"hard": {"stay": 0.85, "gap": 0.85, "tricks_min": 3.0, "warn": 1.9, "stun": 1.2, "gold_stay": 1.6, "herd_stay": 1.2, "herd": 4},
}
const MIN_WARN := 1.5
const KID_SPEED := 2.2  # main.gd KID_SPEED (table metres a second)
const GAP := 3.5  # quiet seconds between two tricks
const STAY := 0.5  # seconds a tell glows hot while it goes off
const START := 6.0  # no trick in the first seconds of a round (or 20% of a short one)
const END := 3.0
const BAND_W := 0.62  # the stampede band's width (a row of holes is Props.SPACING.y apart)
const GOLD_R := 0.25
const GOLD_COLOR := Color(1.0, 0.68, 0.0)  # a warm gold: shows on the green table top (palette.gd)
const HERD_COLOR := Color(0.95, 0.15, 0.3)  # red: "look out, moles coming!"
const KINDS: Array[String] = ["gold", "stampede"]
## Season -> trick weights (gold, stampede), the garden's dress and sky, Fig's line.
const SEASONS := {
	"spring": {"weights": [1.6, 1.0], "pic": "daisy", "line": "Spring garden!", "sky": "day"},
	"summer": {"weights": [1.0, 1.6], "pic": "sun", "line": "Sunny summer!", "sky": "day"},
	"autumn": {"weights": [1.0, 1.2], "pic": "acorn", "line": "Autumn leaves!", "sky": "day"},
	"winter": {"weights": [1.2, 1.0], "pic": "snowman", "line": "Snowy garden!", "sky": "snowy"},
}
## Fig's hammer gifts: id, name, picture, a short line, holiday moles needed.
const GIFTS: Array[Dictionary] = [
	{"id": "big", "name": "BIG HAMMER", "pic": "bighammer", "line": "Big bonks!", "color": Color(0.95, 0.45, 0.3), "unlock": 0},
	{"id": "sleepy", "name": "SLEEPY DUST", "pic": "sleepydust", "line": "Sleepy moles!", "color": Color(0.55, 0.6, 1.0), "unlock": 0},
	{"id": "gold", "name": "GOLD GLOVE", "pic": "goldglove", "line": "More gold!", "color": Color(1.0, 0.82, 0.25), "unlock": 0},
	{"id": "boing", "name": "BOING HAMMER", "pic": "boinghammer", "line": "Boing! Bonk two!", "color": Color(0.4, 0.9, 0.6), "unlock": 3},
	{"id": "carrot", "name": "CARROT BAG", "pic": "carrotbag", "line": "Bunny treats!", "color": Color(1.0, 0.55, 0.15), "unlock": 8},
]
const BIG_REACH := 1.5  # BIG HAMMER: a hammer-kid's bonk reach times this; the mallet head this much bigger
const SLEEPY_STAY := 1.25  # SLEEPY DUST: moles stay up this much longer
const GOLD_ADD := 0.08  # GOLD GLOVE: golden mole chance added (+ one more golden trick)
const BOING_R := 0.9  # BOING HAMMER: other moles up this near a bonked one are bonked too (holes are 0.72 / 0.78 apart)
const CARROT_X := 2  # CARROT BAG: a bunny left alone gives this many times the carrots
const HOLIDAY_EVERY := 25  # moles bonked for each one going on holiday
const MAX_HOLIDAY := 42
const HOLIDAY_RING := 14  # deckchairs in each ring
const HOLIDAY_R := 5.7  # the first ring's radius (garden.gd beds sit at 4.1)
const HOLIDAY_STEP := 0.75
const HOLIDAY_ARC := 150.0  # degrees either side of straight behind the table (the front, where the VR player stands, stays open)
## The holiday moles' looks, in the order they arrive (roundgen.gd kinds; drawn sitting in deckchairs).
const HOLIDAY_LOOKS: Array[int] = [RoundGen.NORMAL, RoundGen.SPEEDY, RoundGen.HELMET, RoundGen.NORMAL, RoundGen.GOLD,
	RoundGen.SPEEDY, RoundGen.NORMAL, RoundGen.HELMET, RoundGen.KING]


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
	for k in ["tricks_min", "stun", "herd"]:  # more of these is harder
		if not (float(g[k]) <= float(b[k]) and float(b[k]) <= float(h[k])):
			out.append("%s not gentle <= brave <= hard" % k)
	for k in ["stay", "gap", "warn", "gold_stay", "herd_stay"]:  # more of these is gentler
		if not (float(g[k]) >= float(b[k]) and float(b[k]) >= float(h[k])):
			out.append("%s not longest on gentle" % k)
	if float(h.warn) < MIN_WARN:
		out.append("hard warns under %.1f s" % MIN_WARN)
	if float(g.stun) > 0.0:
		out.append("gentle sits a hammer-kid down")
	for m in MODES:
		if float(MODES[m].gold_stay) < 1.2 or float(MODES[m].herd_stay) < 0.9:
			out.append("%s: trick moles too quick to bonk" % m)
	return out


static func season_data(season: String) -> Dictionary:
	return SEASONS.get(season, SEASONS.spring)


## The round's spec for roundgen.gd with the mode and the gift folded in (story.gd spec / daily_spec make the rest).
static func round_spec(sp: Dictionary, mode: String, gift_id: String) -> Dictionary:
	var out := sp.duplicate()
	var md := mode_data(mode)
	out["stay_x"] = float(md.stay) * (SLEEPY_STAY if gift_id == "sleepy" else 1.0)
	out["gap_x"] = float(md.gap)
	if gift_id == "gold":
		out["gold"] = float(sp.get("gold", 0.06)) + GOLD_ADD
	if gift_id == "carrot":
		out["carrot_x"] = CARROT_X
	return out


# --- Tricks -----------------------------------------------------------------------------------------------

## A stampede's band over row r: [from, dir, size] for warn_rings' "line" (table-top world coordinates).
static func band(row: int) -> Array:
	var z := (row - (RoundGen.ROWS - 1) * 0.5) * Props.SPACING.y
	return [Vector3(-Props.HALF.x - 0.05, Props.TABLE_Y, z), Vector3.RIGHT, Vector2(Props.HALF.x * 2.0 + 0.1, BAND_W)]


## The holes of a stampede over row r (GENTLE: the middle few).
static func herd_holes(row: int, mode: String) -> Array:
	var n := int(mode_data(mode).herd)
	var out: Array = []
	var skip := (RoundGen.COLS - n) / 2
	for c in range(skip, skip + n):
		out.append(RoundGen.hole_of(c, row))
	return out


## This round's tricks: [[t, "gold", hole], [t, "stampede", row]] sorted by t (seconds into the round, when it
## happens; its tell starts `warn` before). spec: {mode, time, season, extra_gold, scale (bots: more)}. rd: the round
## (roundgen.gd) so a trick never lands on the KING or makes two golden moles at once.
static func tricks(seed_value: int, spec: Dictionary, rd: Dictionary) -> Array:
	var r := Seeded.rng(seed_value, "tricks")
	var mode := String(spec.get("mode", "brave"))
	var md := mode_data(mode)
	var time := float(spec.get("time", 120.0))
	var warn := float(md.warn)
	var start := minf(START, time * 0.2)
	var stop := time - minf(END, time * 0.15) - float(md.gold_stay)
	var n := roundi(float(md.tricks_min) * time / 60.0 * float(spec.get("scale", 1.0)))
	var w: Array = season_data(String(spec.get("season", "spring"))).weights
	var kinds: Array = []
	for k in n:
		kinds.append(KINDS[Seeded.weighted(r, w)])
	for k in int(spec.get("extra_gold", 0)):
		kinds.append("gold")
	var slot := warn + STAY + GAP
	var fit := floori((stop - start - warn) / slot) + 1
	kinds = Seeded.shuffled(r, kinds).slice(0, maxi(0, fit))
	var out: Array = []
	if kinds.is_empty() or stop <= start + warn:
		return out
	var span := stop - start - warn
	var each := span / kinds.size()
	for i in kinds.size():
		var t := snappedf(minf(start + warn + each * i + r.randf_range(0.0, maxf(0.0, each - slot)), stop), 0.01)
		# The kind drawn, else the other one: a trick that can't go off then (a golden mole already up, every row's herd
		# path crossing the KING) used to be dropped, so a short round could end with none (2026-11-12: the bot's 14 s
		# rounds, "tricks happened" failed now and then).
		var first := String(kinds[i])
		for kind in [first, "stampede" if first == "gold" else "gold"]:
			var e := _trick_at(r, rd, md, mode, kind, t, warn)
			if not e.is_empty():
				out.append(e)
				break
	return out


static func _trick_at(r: RandomNumberGenerator, rd: Dictionary, md: Dictionary, mode: String, kind: String, t: float, warn: float) -> Array:
	match kind:
		"gold":
			if _gold_busy(rd, t, float(md.gold_stay)):
				return []  # a golden mole is up then already: never two at once
			var holes: Array = []
			for h in RoundGen.HOLES:
				if not _king_on(rd, h, t - warn, t + float(md.gold_stay)):
					holes.append(h)
			return [] if holes.is_empty() else [t, "gold", int(holes[r.randi() % holes.size()])]
		"stampede":
			var rows: Array = []
			for row in RoundGen.ROWS:
				var free := true
				for h in herd_holes(row, mode):
					free = free and not _king_on(rd, int(h), t - warn, t + float(md.herd_stay) + RoundGen.HOLE_REST)
				if free:
					rows.append(row)
			return [] if rows.is_empty() else [t, "stampede", int(rows[r.randi() % rows.size()])]
	return []


## Is the KING in hole h at any time in [from, to]?
static func _king_on(rd: Dictionary, h: int, from: float, to: float) -> bool:
	for s in rd.get("spawns", []):
		if int(s[2]) == RoundGen.KING and int(s[1]) == h and float(s[0]) - 0.5 < to and float(s[0]) + float(s[3]) + RoundGen.HOLE_REST > from:
			return true
	return false


## Is one of the round's own golden moles up in [t - 0.5, t + stay + 0.5]?
static func _gold_busy(rd: Dictionary, t: float, stay: float) -> bool:
	for s in rd.get("spawns", []):
		if int(s[2]) == RoundGen.GOLD and float(s[0]) <= t + stay + 0.5 and float(s[0]) + float(s[3]) + 0.5 > t:
			return true
	return false


## Reasons this round's tricks are unfair (empty = fine): told too late, too close together, outside the round, on
## the KING, two golden moles at once, a band too wide to step out of while it is told.
static func problems(list: Array, spec: Dictionary, rd: Dictionary) -> Array:
	var why: Array = []
	var mode := String(spec.get("mode", "brave"))
	var md := mode_data(mode)
	var warn := float(md.warn)
	var time := float(spec.get("time", 120.0))
	if warn < MIN_WARN:
		why.append("told only %.1f s early" % warn)
	# Anyone in a band steps out of it (half its width, sideways) before it goes off.
	if (BAND_W * 0.5 + 0.1) / KID_SPEED > warn - 0.4:
		why.append("a stampede band too wide to step out of")
	var last := -INF
	for e in list:
		var t := float(e[0])
		if t - warn < 0.5 or t + float(md.gold_stay) > time - 0.5:
			why.append("a trick at %.1f s outside the round" % t)
		if t - last < warn + STAY + GAP - 0.01:
			why.append("two tricks %.1f s apart" % (t - last))
		last = t
		match String(e[1]):
			"gold":
				var h := int(e[2])
				if h < 0 or h >= RoundGen.HOLES:
					why.append("a golden trick in no hole (%d)" % h)
				elif _king_on(rd, h, t - warn, t + float(md.gold_stay)):
					why.append("a golden trick on the KING at %.1f" % t)
				if _gold_busy(rd, t, float(md.gold_stay)):
					why.append("two golden moles at once at %.1f" % t)
			"stampede":
				var row := int(e[2])
				if row < 0 or row >= RoundGen.ROWS:
					why.append("a stampede on no row (%d)" % row)
					continue
				for h in herd_holes(row, mode):
					if _king_on(rd, int(h), t - warn, t + float(md.herd_stay) + RoundGen.HOLE_REST):
						why.append("a stampede over the KING at %.1f" % t)
				var b := band(row)
				for h in herd_holes(row, mode):
					var p: Vector3 = Props.holes()[int(h)]
					if absf(p.z - (b[0] as Vector3).z) > BAND_W * 0.5:
						why.append("a stampede hole outside its band")
			_:
				why.append("an unknown trick %s" % str(e[1]))
	return why


# --- Gifts ------------------------------------------------------------------------------------------------

static func unlocked(holiday: int) -> Array:
	var out: Array = []
	for g in GIFTS:
		if holiday >= int(g.unlock):
			out.append(String(g.id))
	return out


static func gift(id: String) -> Dictionary:
	for g in GIFTS:
		if String(g.id) == id:
			return g
	return GIFTS[0]


## Three different unlocked gifts: the newest unlock always among them, not the last one again when there are others
## (the same on every machine for a seed).
static func gift_choices(holiday: int, last: String, seed_value: int) -> Array:
	var un := unlocked(holiday)
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
	return Seeded.shuffled(Seeded.rng(seed_value, "gift order"), out)


# --- The holiday garden -------------------------------------------------------------------------------------

static func holiday(bonked_total: int) -> int:
	return mini(MAX_HOLIDAY, maxi(0, bonked_total) / HOLIDAY_EVERY)


## Where holiday mole i sits (rings round Fig's beds, behind and beside the table), facing the table.
static func holiday_spot(i: int) -> Transform3D:
	var ring := i / HOLIDAY_RING
	var k := i % HOLIDAY_RING
	var f := (float(k) + (0.5 if ring % 2 == 1 else 0.0)) / float(HOLIDAY_RING - 1)
	var a := deg_to_rad(lerpf(-HOLIDAY_ARC, HOLIDAY_ARC, clampf(f, 0.0, 1.0)))
	var rad := HOLIDAY_R + HOLIDAY_STEP * ring
	var p := Vector3(sin(a) * rad, 0.0, -cos(a) * rad)
	return Transform3D(Basis(Vector3.UP, atan2(-p.x, -p.z)), p)


static func holiday_look(i: int) -> int:
	return HOLIDAY_LOOKS[i % HOLIDAY_LOOKS.size()]