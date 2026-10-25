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
static func today() -> String:
	return Time.get_date_string_from_system()


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


## The validator loop every generator test uses: generate `count` levels (seeds from `first`, plus any
## `extra` seeds, e.g. ones the family played), run `check` on each (returns an Array of failure
## reasons, empty when fine) and check determinism (the same seed must give the same level, compared
## with var_to_str). Prints "SCRIPT ERROR: <tag> seed N: reason" for failures (bot runners grep it).
static func validate(gen: Callable, check: Callable, count: int = 200, first: int = 1, extra: Array = [], tag: String = "GEN") -> Dictionary:
	var failures: Array = []
	var seeds: Array = []
	for i in count:
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
