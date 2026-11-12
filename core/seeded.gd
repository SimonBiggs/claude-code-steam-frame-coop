extends RefCounted
## Seeded: shared helpers for procedural generation, so every game makes "same seed -> same level"
## the same way, has the same daily seed, and proves its generator with the same validator loop.
##   const Seeded := preload("res://core/seeded.gd")
##   var rng := Seeded.rng(seed, "hoops")            # one independent stream per purpose (salt)
##   var s := Seeded.daily_seed("paper_planes")      # the same number on every machine all day
##   var key := Seeded.daily_key()                   # "daily:2026-10-25" (for best-of-day saves)
##   var s2 := Seeded.fresh_seed()                   # a new random seed (0..999999) for a new session
##   var r := Seeded.validate(func(s): return gen(s), func(level): return [] if ok else ["why"], 500)
##   # r = {"ok": bool, "checked": n, "failures": [[seed, reason], ...]} (prints SCRIPT ERROR lines)
## Seeds are plain ints below 1,000,000 so they're easy to read in logs and type into tests.

const SEED_MAX := 1000000


## A RandomNumberGenerator for `seed_value`, with an optional salt so separate parts of a level
## (layout, colours, events) each get their own stream and changing one never shifts the others.
static func rng(seed_value: int, salt: String = "") -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%d:%s" % [seed_value, salt]) if salt != "" else seed_value
	return r


## A sub-seed derived from a seed and a salt (e.g. flight 3 of a chapter).
static func derive(seed_value: int, salt: Variant) -> int:
	return absi(hash("%d/%s" % [seed_value, str(salt)])) % SEED_MAX


## Today's date as "YYYY-MM-DD" (local time, so the daily level changes at the family's midnight).
## Test runs only (env SAVE_TEST, which godot-test sets): DUO_TODAY=YYYY-MM-DD pretends it is that day, so a bot can
## replay any day's daily level (2026-11-12: Hide and Seek's TODAY'S STREET broke the bot on one date only).
static func today() -> String:
	if OS.has_environment("SAVE_TEST") and OS.get_environment("DUO_TODAY").length() == 10:
		return OS.get_environment("DUO_TODAY")
	return Time.get_date_string_from_system()


## The season on a date ("YYYY-MM-DD", "" = today): winter (Dec-Feb), spring, summer, autumn. One place for every
## game's seasonal look (Balloon Pop skies, Marble Maze worlds, Sheep Round-Up weather, Treasure Dig, Whack-a-Mole).
static func season(date: String = "") -> String:
	var parts := (date if date != "" else today()).split("-")
	var month := int(parts[1]) if parts.size() >= 2 else 6
	if month == 12 or month <= 2:
		return "winter"
	if month <= 5:
		return "spring"
	if month <= 8:
		return "summer"
	return "autumn"


## "daily:YYYY-MM-DD": a save key for best-of-the-day records.
static func daily_key(date: String = "") -> String:
	return "daily:" + (date if date != "" else today())


## The same seed on every machine all day, different for each game (pass the game id).
static func daily_seed(game_id: String = "", date: String = "") -> int:
	return absi(hash((date if date != "" else today()) + "/" + game_id)) % SEED_MAX


## A brand-new seed for a new session.
static func fresh_seed() -> int:
	return randi() % SEED_MAX


## Pick one item of `items` with rng (null when empty).
static func pick(r: RandomNumberGenerator, items: Array) -> Variant:
	return null if items.is_empty() else items[r.randi() % items.size()]


## Pick an index by weights ([3, 1, 1] -> 0 is three times as likely).
static func weighted(r: RandomNumberGenerator, weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	var x := r.randf() * total
	for i in weights.size():
		x -= float(weights[i])
		if x < 0.0:
			return i
	return weights.size() - 1


## Shuffle a copy of `items` with rng (Array.shuffle() uses the global generator: not reproducible).
static func shuffled(r: RandomNumberGenerator, items: Array) -> Array:
	var a := items.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := r.randi() % (i + 1)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t
	return a


## Dates a daily-level validator checks: `count` days from `first`, then the 60 days from whenever the test runs
## (so the family's real "today" and the coming weeks are always covered), plus `extra` dates. "YYYY-MM-DD" each.
static func dates(count: int = 400, first: String = "2026-10-01", extra: Array = []) -> Array:
	var out: Array = []
	var t0 := Time.get_unix_time_from_datetime_string(first + "T12:00:00")
	for d in count:
		out.append(Time.get_date_string_from_unix_time(t0 + d * 86400))
	var now := Time.get_unix_time_from_datetime_string(Time.get_date_string_from_system() + "T12:00:00")
	for d in 60:
		var s := Time.get_date_string_from_unix_time(now + d * 86400)
		if not out.has(s):
			out.append(s)
	for e in extra:
		if not out.has(str(e)):
			out.append(str(e))
	return out


## QUICK test runs (2026-11-12): a landing (dev.land sets GEN_QUICK=1) checks a representative SAMPLE so no test
## holds a landing up for minutes (kart_trackgen_test took ~220 s, dungeon_delve_floors_test ~130 s); the nightly
## full sweep (tools/duo-nightly-tests, duo-nightly-tests.timer) runs every seed and date. The sample turns with the
## day (offset = days since 2026-10-01), so over a few landings every seed/date is checked in quick runs too, and a
## landing is reproducible all day. Seeds/dates a test lists as `extra` (family-played seeds, fixed dates) are
## ALWAYS checked, and so are the next QUICK_AHEAD days (the family's real coming dailies).
const QUICK_STRIDE := 4  ## validate(): every 4th seed
const QUICK_DAY_STRIDE := 10  ## validate_days(): every 10th date of the 400
const QUICK_AHEAD := 14


static func quick() -> bool:
	return OS.get_environment("GEN_QUICK") == "1"


## A test's loop count: SEEDS env when set, else `full`, or in a quick run `quick_n` (default about a quarter, >= 2).
##   var seeds := Seeded.test_count(60)      # 60 nightly, 15 in a landing
##   var seeds := Seeded.test_count(60, 6)   # 60 nightly, 6 in a landing
static func test_count(full: int, quick_n: int = -1) -> int:
	if OS.has_environment("SEEDS"):
		return int(OS.get_environment("SEEDS"))
	if not quick():
		return full
	return mini(full, quick_n) if quick_n >= 0 else maxi(mini(2, full), full / QUICK_STRIDE)


## True when item `i` of a loop is in today's quick sample (always true in a full run): for loops a test can't
## shorten with test_count() (fixed lists of places / cups / dates).  if not Seeded.sampled(i): continue
static func sampled(i: int, stride: int = QUICK_STRIDE) -> bool:
	return not quick() or posmod(i - _day_offset(), stride) == 0


static func _day_offset() -> int:
	var now := Time.get_unix_time_from_datetime_string(Time.get_date_string_from_system() + "T12:00:00")
	return int((now - Time.get_unix_time_from_datetime_string("2026-10-01T12:00:00")) / 86400)


## The validator loop for a game's TODAY'S level (every game with a daily): make the daily level for each of
## dates(count) with gen(date) and run check(level) on it (an Array of reasons, empty when fine); the same date must
## make the same level all day. A daily nobody can win is a whole day lost for the family, so every gen test with a
## daily runs this over a year+ of dates. Returns {"ok", "checked", "failures": [[date, reason], ...]} and prints
## "SCRIPT ERROR: <tag> <date>: reason" per failure (first 30), like validate().
static func validate_days(gen: Callable, check: Callable, count: int = 400, tag: String = "DAILY", extra: Array = []) -> Dictionary:
	var failures: Array = []
	var days := dates(count, "2026-10-01", extra)
	if quick():
		var keep := {}
		for e in extra:
			keep[str(e)] = true
		var now := Time.get_unix_time_from_datetime_string(Time.get_date_string_from_system() + "T12:00:00")
		for d in QUICK_AHEAD:
			keep[Time.get_date_string_from_unix_time(now + d * 86400)] = true
		var sample: Array = []
		for i in days.size():
			if keep.has(days[i]) or sampled(i, QUICK_DAY_STRIDE):
				sample.append(days[i])
		days = sample
	for date in days:
		var level: Variant = gen.call(date)
		var reasons: Array = check.call(level)
		if var_to_str(gen.call(date)) != var_to_str(level):
			reasons.append("not the same all day")
		for why in reasons:
			failures.append([date, str(why)])
			if failures.size() <= 30:
				print("SCRIPT ERROR: %s %s: %s" % [tag, date, str(why)])
	return {"ok": failures.is_empty(), "checked": days.size(), "failures": failures}


## The validator loop every generator test uses: generate `count` levels (seeds from `first`, plus any
## `extra` seeds, e.g. ones the family played), run `check` on each (returns an Array of failure
## reasons, empty when fine) and check determinism (the same seed must give the same level, compared
## with var_to_str). Prints "SCRIPT ERROR: <tag> seed N: reason" for failures (bot runners grep it).
static func validate(gen: Callable, check: Callable, count: int = 200, first: int = 1, extra: Array = [], tag: String = "GEN") -> Dictionary:
	var failures: Array = []
	var seeds: Array = []
	for i in count:
		if count <= 3 or sampled(i):  # quick runs: today's quarter of the seeds (see quick())
			seeds.append(first + i * 7919)
	seeds.append_array(extra)
	for s in seeds:
		var level: Variant = gen.call(int(s))
		var reasons: Array = check.call(level)
		if var_to_str(gen.call(int(s))) != var_to_str(level):
			reasons.append("not deterministic")
		for why in reasons:
			failures.append([int(s), str(why)])
			if failures.size() <= 30:
				print("SCRIPT ERROR: %s seed %d: %s" % [tag, int(s), str(why)])
	return {"ok": failures.is_empty(), "checked": seeds.size(), "failures": failures}
