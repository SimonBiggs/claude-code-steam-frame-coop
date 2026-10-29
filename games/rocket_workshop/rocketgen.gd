extends RefCounted
## ROCKET WORKSHOP generator: every rocket is made from a seed, so the same seed gives the same rocket
## (its puzzles AND its look) on every machine, and tests/rocket_workshop_gen_test.gd can prove over
## thousands of seeds that every rocket is solvable and fair for every crew size.
##   var rk := RocketGen.rocket(seed, n, crew, simple, launched_total, daily)
##   rk = {name, modules, time, look, level, seed, daily}
## Story: SPROCKET the robot engineer (sprocket.gd) builds the rockets; every rocket that reaches its
## planet comes home as a little model on ROCKET ROW (museum.gd, saved, grows over days). Rockets the
## family launches (in total, saved) unlock new PARTS (fins, noses, stripes, boosters, a space ring,
## colours) that later rockets are built from, so the rockets on the pad and on Rocket Row get fancier.
## TODAY'S ROCKET: the first session each day, rocket DAILY_N is a GOLD rocket made from today's seed:
## the same puzzles and look on every machine all day, wearing a sneak peek of parts not unlocked yet.
## A session gets a fresh seed; rocket n's seed is derived from it (rocket_seed).

const Seeded := preload("res://core/seeded.gd")
const P := preload("res://games/rocket_workshop/puzzles.gd")

const GAME_ID := "rocket_workshop"
const DAILY_N := 2  # TODAY'S ROCKET comes right after the practice rocket

const BODY_COLORS: Array[Color] = [Color(0.95, 0.95, 0.98), Color(1.0, 0.85, 0.4), Color(0.6, 0.85, 1.0),
	Color(1.0, 0.7, 0.8), Color(0.75, 0.95, 0.6), Color(0.85, 0.75, 1.0)]
const TRIM_COLORS: Array[Color] = [Color(0.95, 0.25, 0.25), Color(0.25, 0.5, 1.0), Color(1.0, 0.5, 0.15),
	Color(0.95, 0.35, 0.7), Color(0.2, 0.7, 0.45), Color(0.55, 0.3, 0.9), Color(1.0, 0.78, 0.15)]
const GOLD := 6  # the TRIM_COLORS index only TODAY'S ROCKET wears
const FINS: Array[String] = ["classic", "swept", "round", "four"]
const NOSES: Array[String] = ["cone", "bubble", "needle"]
const EXTRAS: Array[String] = ["none", "stripes", "boosters", "ring"]
## look = [body colour, trim colour, fins, nose, extra, gold (0/1)]
const L_BODY := 0
const L_TRIM := 1
const L_FINS := 2
const L_NOSE := 3
const L_EXTRA := 4
const L_GOLD := 5
## What the family starts with, then one new part every few rockets launched (in total, over days).
const START := {"body": [0, 1, 2], "trim": [0, 1, 2], "fins": [0], "nose": [0], "extra": [0]}
const UNLOCKS: Array[Dictionary] = [
	{"at": 2, "kind": "fins", "v": 1, "line": "Zoomy fins!"},
	{"at": 4, "kind": "nose", "v": 1, "line": "A bubble nose!"},
	{"at": 6, "kind": "extra", "v": 1, "line": "Stripes!"},
	{"at": 8, "kind": "colour", "v": 3, "line": "Pink paint!"},
	{"at": 10, "kind": "fins", "v": 2, "line": "Round fins!"},
	{"at": 13, "kind": "extra", "v": 2, "line": "Boosters!"},
	{"at": 16, "kind": "nose", "v": 2, "line": "A pointy nose!"},
	{"at": 19, "kind": "colour", "v": 4, "line": "Green paint!"},
	{"at": 22, "kind": "extra", "v": 3, "line": "A space ring!"},
	{"at": 26, "kind": "fins", "v": 3, "line": "Four fins!"},
	{"at": 30, "kind": "colour", "v": 5, "line": "Purple paint!"},
]
## Rocket Row: rows of plinths behind the launch pad (just past where the crew can walk).
const ROW_Z: Array[float] = [-18.4, -20.0, -21.6]
const ROW_RISE: Array[float] = [0.0, 0.45, 0.9]
const ROW_STEP := 1.5
const ROW_HALF := 9.0
const MUSEUM_KEEP := 60  # entries saved (the newest are shown)
const MODEL_SCALE := 0.27


static func rocket_seed(session_seed: int, n: int) -> int:
	return Seeded.derive(session_seed, "rocket%d" % n)


static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed(GAME_ID, date)


## One rocket: puzzles (puzzles.gd, seeded) + its look. daily: TODAY'S ROCKET (gold, sneak-peek parts).
static func rocket(seed_value: int, n: int, crew: int, simple: bool, launched_total: int, daily: bool = false) -> Dictionary:
	var pr := Seeded.rng(seed_value, "puzzles")
	var r := P.make_simple_rocket(n, pr) if simple else P.make_rocket(n, crew, pr)
	r["look"] = look(Seeded.rng(seed_value, "look"), launched_total, daily)
	r["level"] = level(n, simple)
	r["seed"] = seed_value
	r["daily"] = daily
	return r


## The readable challenge step (1-3): the rocket on the pad grows taller with it.
static func level(n: int, simple: bool) -> int:
	return P.simple_level(n) if simple else clampi(1 + (n - 1) / 3, 1, 3)


## Parts the family has after launched_total rockets: {body, trim, fins, nose, extra: [ids]}.
static func unlocked(launched_total: int) -> Dictionary:
	var u := START.duplicate(true)
	for k in UNLOCKS:
		if launched_total >= int(k.at):
			if k.kind == "colour":
				(u.body as Array).append(int(k.v))
				(u.trim as Array).append(int(k.v))
			else:
				(u[k.kind] as Array).append(int(k.v))
	return u


## The unlocks reached going from 'before' to 'after' launches (usually none or one).
static func new_unlocks(before: int, after: int) -> Array:
	var out: Array = []
	for k in UNLOCKS:
		if before < int(k.at) and after >= int(k.at):
			out.append(k)
	return out


## Pick a look. A part unlocked within the last two launches is shown off on the next rockets.
static func look(r: RandomNumberGenerator, launched_total: int, daily: bool) -> Array:
	if daily:  # a sneak peek at everything, with gold trim
		return [r.randi() % BODY_COLORS.size(), GOLD, r.randi() % FINS.size(), r.randi() % NOSES.size(),
			1 + r.randi() % (EXTRAS.size() - 1), 1]
	var u := unlocked(launched_total)
	var body: int = Seeded.pick(r, u.body)
	var trims: Array = (u.trim as Array).duplicate()
	var lk := [body, int(Seeded.pick(r, trims)), int(Seeded.pick(r, u.fins)), int(Seeded.pick(r, u.nose)),
		int(Seeded.pick(r, u.extra)), 0]
	for k in new_unlocks(maxi(0, launched_total - 2), launched_total):
		match String(k.kind):
			"fins":
				lk[L_FINS] = int(k.v)
			"nose":
				lk[L_NOSE] = int(k.v)
			"extra":
				lk[L_EXTRA] = int(k.v)
			"colour":
				lk[L_BODY] = int(k.v)
	return lk


## Where museum model i stands (0 = front row, leftmost). Vector3.INF past the last slot.
static func museum_slot(i: int) -> Vector3:
	var k := i
	for row in ROW_Z.size():
		var count := row_count(row)
		if k < count:
			var x0 := -ROW_HALF + (ROW_STEP * 0.5 if row % 2 == 1 else 0.0)
			return Vector3(x0 + k * ROW_STEP, ROW_RISE[row], ROW_Z[row])
		k -= count
	return Vector3.INF


static func row_count(row: int) -> int:
	return int(floor(ROW_HALF * 2.0 / ROW_STEP)) + (0 if row % 2 == 1 else 1)


static func museum_size() -> int:
	var n := 0
	for row in ROW_Z.size():
		n += row_count(row)
	return n


## A saved museum entry -> the compact array the host sends: [look (6)..., planet].
static func entry_pack(e: Dictionary) -> Array:
	var a: Array = (e.get("look", [0, 0, 0, 0, 0, 0]) as Array).duplicate()
	a.append(int(e.get("planet", 0)))
	return a


# --- Validator -------------------------------------------------------------------------------------

## Everything wrong with a generated rocket (empty = solvable and fair). ctx: {n, crew, simple, launched}.
static func check(rk: Dictionary, ctx: Dictionary) -> Array:
	var bad: Array = []
	var n := int(ctx.n)
	var simple := bool(ctx.simple)
	var crew := int(ctx.get("crew", 1))
	var mods: Array = rk.get("modules", [])
	var rname := String(rk.get("name", ""))
	if not P.ROCKET_NAMES.has(rname):
		bad.append("unknown rocket name %s" % rname)
	var types := {}
	var vr := 0
	var jobs := 0
	for m in mods:
		var t := String(m.type)
		if types.has(t):
			bad.append("two %s modules" % t)
		types[t] = true
		if bool(m.done):
			bad.append("%s starts solved" % t)
		if P.is_job(t):
			jobs += 1
		else:
			vr += 1
		for why in check_module(m, simple, rname):
			bad.append("%s: %s" % [t, why])
	if simple:
		var want := 1 if n == 1 else (3 if P.simple_level(n) >= 3 and n > P.SIMPLE_ORDER.size() else 2)
		if mods.size() != want:
			bad.append("simple rocket %d has %d puzzles (want %d)" % [n, mods.size(), want])
		if jobs > 0:
			bad.append("simple rocket has crew jobs")
		if n <= P.SIMPLE_ORDER.size() and (mods.is_empty() or String(mods[0].type) != P.SIMPLE_ORDER[n - 1]):
			bad.append("the new control (%s) is not first" % P.SIMPLE_ORDER[n - 1])
		for t in types:
			if not P.SIMPLE_ORDER.has(t):
				bad.append("simple rocket has %s" % t)
	else:
		if vr < 2:
			bad.append("only %d desk puzzles" % vr)
		var secs := float(rk.get("time", 0.0))
		if secs < 20.0 + 30.0 * vr + 25.0 * jobs:
			bad.append("not enough time (%.0f s for %d desk + %d jobs)" % [secs, vr, jobs])
		if crew >= 1 and jobs > crew + 1:
			bad.append("%d jobs for a crew of %d" % [jobs, crew])
	if int(rk.get("level", 0)) != level(n, simple):
		bad.append("level")
	var lk: Array = rk.get("look", [])
	if lk.size() != 6:
		bad.append("look has %d parts" % lk.size())
	else:
		var daily := bool(rk.get("daily", false))
		if int(lk[L_BODY]) < 0 or int(lk[L_BODY]) >= BODY_COLORS.size() or int(lk[L_TRIM]) < 0 or int(lk[L_TRIM]) >= TRIM_COLORS.size():
			bad.append("look colour out of range %s" % str(lk))
		if int(lk[L_FINS]) >= FINS.size() or int(lk[L_NOSE]) >= NOSES.size() or int(lk[L_EXTRA]) >= EXTRAS.size():
			bad.append("look part out of range %s" % str(lk))
		if daily != (int(lk[L_TRIM]) == GOLD) or daily != (int(lk[L_GOLD]) == 1):
			bad.append("gold trim is only for TODAY'S ROCKET %s" % str(lk))
		if not daily:
			var u := unlocked(int(ctx.get("launched", 0)))
			for pair in [["body", L_BODY], ["trim", L_TRIM], ["fins", L_FINS], ["nose", L_NOSE], ["extra", L_EXTRA]]:
				if not (u[pair[0]] as Array).has(int(lk[pair[1]])):
					bad.append("%s %d is not unlocked yet" % [pair[0], int(lk[pair[1]])])
	return bad


## Can the pilot do it with the desk, and can the crew find the answer on the boards?
static func check_module(m: Dictionary, simple: bool, rname: String) -> Array:
	var bad: Array = []
	match String(m.type):
		"fuel":
			var a: Array = m.answer
			if a.is_empty() or a.size() > 4:
				bad.append("answer size %d" % a.size())
			for c in a:
				if int(c) < 0 or int(c) >= P.COLORS.size():
					bad.append("colour %d" % int(c))
			var s := a.duplicate()
			s.sort()
			if s != a:
				bad.append("answer not sorted")
			if simple:
				var seen := {}
				for c in a:
					seen[int(c)] = true
				if seen.size() != a.size():
					bad.append("a simple fuel button twice")  # (a second press of a lit button does nothing)
			bad.append_array(_check_rows(m, rname))
		"wires":
			var order: Array = m.order
			var used := {}
			var plugs := 0
			for c in order:
				if int(c) < 0:
					continue
				plugs += 1
				if int(c) >= 4 or used.has(int(c)):
					bad.append("bad plug colour %d" % int(c))
				used[int(c)] = true
			if order.size() > 4 or plugs < 2 or (not simple and plugs < 3):
				bad.append("%d plugs in %d sockets" % [plugs, order.size()])
			if (m.placed as Array).size() != 4:
				bad.append("placed size")
		"symbols":
			var layout: Array = m.layout
			var order: Array = m.order
			var used := {}
			for s in layout:
				if int(s) < 0 or int(s) >= P.SHAPE_NAMES.size() or used.has(int(s)):
					bad.append("layout %s" % str(layout))
				used[int(s)] = true
			if layout.size() != 4:
				bad.append("layout size %d" % layout.size())
			var seen := {}
			for s in order:
				if not layout.has(s) or seen.has(int(s)):
					bad.append("shape %d not pressable once" % int(s))
				seen[int(s)] = true
			if order.size() < 2 or order.size() > 4:
				bad.append("order size %d" % order.size())
		"gauge":
			if int(m.answer) < 2 or int(m.answer) > 9:
				bad.append("dial %d off the dial (2..9: never the start 1)" % int(m.answer))
			bad.append_array(_check_rows(m, rname))
		"switches":
			var a: Array = m.answer
			var on := 0
			for b in a:
				on += int(bool(b))
			if a.size() != P.SWITCH_COUNT or on < 1 or on > 4:
				bad.append("switch pattern %s" % str(a))
			if m.state == m.answer:
				bad.append("already solved")
			bad.append_array(_check_rows(m, rname))
		"alien":
			var cast: Array = m.cast
			var pick := int(m.pick)
			if pick < 0 or pick >= cast.size():
				bad.append("pick %d" % pick)
			else:
				var me: Array = cast[pick]
				if int(m.answer) != int(me[3]):
					bad.append("answer is not the picked alien's word")
				for i in cast.size():
					var o: Array = cast[i]
					if i != pick and int(o[0]) == int(me[0]) and int(o[1]) == int(me[1]) and int(o[2]) == int(me[2]):
						bad.append("two aliens look the same")
		"crank":
			if int(m.answer) < 2 or int(m.answer) > 6:
				bad.append("crank %d" % int(m.answer))
			bad.append_array(_check_rows(m, rname))
		"canister":
			if int(m.spot) < 0 or int(m.spot) >= P.CAN_SPOTS.size():
				bad.append("spot")
		"pipe":
			if int(m.spot) < 0 or int(m.spot) >= P.PIPE_SPOTS.size():
				bad.append("spot")
		"bolts":
			var spots: Array = m.spots
			var seen := {}
			for s in spots:
				if int(s) < 0 or int(s) >= P.BOLT_SPOTS.size() or seen.has(int(s)):
					bad.append("bolt spot %d" % int(s))
				seen[int(s)] = true
			if spots.size() != 3:
				bad.append("%d bolts" % spots.size())
		"paint":
			if int(m.answer) < 0 or int(m.answer) >= P.COLORS.size():
				bad.append("paint %d" % int(m.answer))
		_:
			bad.append("unknown module")
	return bad


## Blueprint rows: the crew must be able to tell which row is this rocket's (names unique, the
## rocket's own row there, answers all different so a wrong row is really wrong).
static func _check_rows(m: Dictionary, rname: String) -> Array:
	var bad: Array = []
	var rows: Array = m.get("rows", [])
	if rows.is_empty():
		return ["no blueprint rows"]
	var names := {}
	var answers := {}
	var mine: Variant = null
	for row in rows:
		var rn := String(row[0])
		if names.has(rn):
			bad.append("two rows called '%s'" % rn)
		names[rn] = true
		var key := var_to_str(row[1])
		if answers.has(key):
			bad.append("two rows with the same answer")
		answers[key] = true
		if rn == "" or rn == rname:
			mine = row[1]
	if rows.size() > 1 and not names.has(rname):
		bad.append("this rocket's row is missing")
	if mine == null or var_to_str(mine) != var_to_str(m.answer):
		bad.append("the blueprint row doesn't match the answer")
	return bad
