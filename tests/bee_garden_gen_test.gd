extends SceneTree
## BEE GARDEN garden generator: proves the seeded gardens and rounds are fair over many seeds (no game).
##   godot-test --headless --path . -s res://tests/bee_garden_gen_test.gd      (SEEDS=500 for more)
## games/bee_garden/gardengen.gd check(): 12 spots in the soil within the gardener's reach, clear of the
## pond / stones / rocks / toadstools, far enough apart that a tossed seed lands in the right one; every
## flower kind's head reachable by a bee flying straight from the hive (nothing in the way); the practice
## ring near the gardener and empty; the bees' first flower a blooming daisy. check_day(): weather, aphids
## and the golden flower spaced out, a calm first round, Queen Bea's favourite growable, and the honey goal
## filled in good time by 1..6 bees and by the two helper bees (a flight simulation), even if the gardener
## never plants. Plus: same seed -> same garden, all plans and features show up, TODAY'S GARDEN is the same
## all day and differs day to day, the story rules, the world constants match the game, every picture
## exists, and it's fast. Prints "SCRIPT ERROR: ..." per failure and "BOT RESULT: PASS/FAIL".

const Gen := preload("res://games/bee_garden/gardengen.gd")
const Story := preload("res://games/bee_garden/story.gd")
const W := preload("res://games/bee_garden/world.gd")
const Bee := preload("res://games/bee_garden/bee.gd")
const Helpers := preload("res://games/bee_garden/helpers.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 60
	var t0 := Time.get_ticks_usec()
	var total := 0
	var plans := {}
	var feats := {}
	var weathers := {}
	var fallback := 0
	for kinds in [1, 2, 3]:
		for level in [0, 4, 12]:
			var sp := {"kinds": kinds, "level": level}
			var res := Seeded.validate(func(s: int) -> Dictionary: return Gen.generate(s, sp),
				func(g: Dictionary) -> Array: return Gen.check(g), seeds, 3 + kinds * 31 + level, [0, 1, 999999],
				"GARDEN k%d l%d" % [kinds, level])
			total += int(res.checked)
			fails += (res.failures as Array).size()
	# Rounds: every garden's first rounds with 0 (helpers), 1, 3 and 6 bees.
	var day_t0 := Time.get_ticks_usec()
	var days := 0
	for s in seeds / 2:
		var g := Gen.generate(1000 + s * 37, {"kinds": 1 + s % 3, "level": [0, 5, 15][s % 3]})
		plans[g.plan] = int(plans.get(g.plan, 0)) + 1
		for f in g.features:
			feats[f[0]] = int(feats.get(f[0], 0)) + 1
		for rn in [1, 2, 3, 5, 8]:
			for bees in [0, 1, 3, 6]:
				var d := Gen.day_plan(g, rn, {"bees": bees})
				weathers[d.weather] = int(weathers.get(d.weather, 0)) + 1
				days += 1
				for why in Gen.check_day(g, d):
					_fail("seed %d round %d bees %d: %s" % [int(g.seed), rn, bees, why])
				_expect(var_to_str(d) == var_to_str(Gen.day_plan(g, rn, {"bees": bees})), "round plans are deterministic")
	var per_day := float(Time.get_ticks_usec() - day_t0) / 1000.0 / maxf(1.0, days)
	var per_ms := float(day_t0 - t0) / 1000.0 / maxf(1.0, total * 2)
	print("bee gen: %.2f ms per garden incl. check, %.2f ms per round check (fill sims)" % [per_ms, per_day])
	_expect(per_ms < 20.0, "a garden generates + checks in under 20 ms here (%.2f; Decks are slower, aim < 100)" % per_ms)
	_expect(per_day < 25.0, "a round plan checks in under 25 ms here (%.2f)" % per_day)
	for p in Gen.PLANS:
		_expect(int(plans.get(p, 0)) >= 1, "the %s plan happens (%s)" % [p, str(plans)])
	for f in Gen.FEATURE_KINDS:
		_expect(int(feats.get(f, 0)) >= (1 if f == "pond" else 3), "%ss show up (%s)" % [f, str(feats)])
	for w in Gen.WEATHERS:
		_expect(int(weathers.get(w, 0)) >= 3, "%s weather happens (%s)" % [w, str(weathers)])
	for s in 200:
		if Gen.generate(s * 101, {}).plan == "rows" and Gen.generate(s * 101, {}).features.is_empty():
			fallback += 1
	_expect(fallback < 20, "the plain fallback bed is rare (%d of 200)" % fallback)
	# Gardens differ, and the bed only depends on the seed (TV and host build the same one).
	var looks := {}
	for s in 40:
		looks[var_to_str(Gen.generate(s, {"kinds": 2}).spots)] = true
	_expect(looks.size() >= 38, "gardens differ (%d unique of 40)" % looks.size())
	_expect(var_to_str(Gen.generate(77, {"kinds": 1}).spots) == var_to_str(Gen.generate(77, {"kinds": 3, "level": 9}).spots),
		"the bed's layout depends only on the seed")
	# Harder rounds ask for more honey; more bees a little more.
	var g0 := Gen.generate(5, {"kinds": 2, "level": 5})
	_expect(int(Gen.day_plan(g0, 4, {"bees": 1}).target) > int(Gen.day_plan(g0, 1, {"bees": 1}).target), "later rounds want more honey")
	_expect(int(Gen.day_plan(g0, 3, {"bees": 6}).target) > int(Gen.day_plan(g0, 3, {"bees": 1}).target), "more bees, more honey")
	# The validator catches broken gardens.
	var bad := Gen.generate(3, {}).duplicate(true)
	bad.spots[1] = [bad.spots[0][0] + 0.3, bad.spots[0][1]]
	_expect(_has(Gen.check(bad), "too close"), "spots too close are caught")
	bad = Gen.generate(3, {}).duplicate(true)
	bad.spots[2] = [3.9, 0.0]
	_expect(_has(Gen.check(bad), "reach"), "a spot out of reach is caught")
	bad = Gen.generate(3, {}).duplicate(true)
	bad.features.append(["pond", bad.spots[4][0], bad.spots[4][1], 0.4])
	_expect(_has(Gen.check(bad), "on a pond"), "a spot in the pond is caught")
	var tall := {"features": [["rock", -3.65, -0.5, 0.3]]}
	var FH: Dictionary = Gen.FEATURE_H
	_expect(Gen._blocked(Gen.HIVE_ENTRY + Vector3(0.6, -0.2, 0.0), Vector3(-2.7, 0.3, -0.5), tall.features) != "", "a rock in the bees' way is caught")
	_expect(Gen._blocked(Gen.HIVE_ENTRY + Vector3(0.6, 0.3, 0.0), Vector3(0.0, 0.6, -2.0), []) != "", "the jars in the bees' way are caught")
	bad = Gen.generate(3, {}).duplicate(true)
	bad.blooms.append([bad.practice, 0])
	_expect(_has(Gen.check(bad), "practice"), "a flower in the practice ring is caught")
	var d0 := Gen.day_plan(g0, 3, {"bees": 1})
	d0.target = 48
	d0.expect = 1
	d0.fav = 1
	_expect(_has(Gen.check_day(g0, d0), "takes"), "a honey goal too big for the flowers is caught")
	d0 = Gen.day_plan(g0, 1, {"bees": 1})
	d0.weather = "drizzle"
	_expect(_has(Gen.check_day(g0, d0), "calm"), "a stormy practice round is caught")
	_expect(FH.has("rock"), "feature heights listed")
	# TODAY'S GARDEN: the same all day, different day to day; the next gardens come from the world seed.
	var daily := {}
	for dd in 30:
		var date := Time.get_date_string_from_unix_time(1790000000 + dd * 86400)
		var gs: Array = Story.garden_seed({"daily": "", "world": 5}, date)
		_expect(bool(gs[1]) and int(gs[0]) == Story.daily_seed(date), "the first garden of %s is today's" % date)
		_expect(int(Story.garden_seed({"daily": "", "world": 9}, date)[0]) == int(gs[0]), "today's garden is the same for every family")
		daily[var_to_str(Gen.generate(int(gs[0]), {}).spots)] = true
		for why in Gen.check(Gen.generate(int(gs[0]), {})):
			_fail("today %s: %s" % [date, why])
	_expect(daily.size() >= 29, "today's garden changes day to day (%d of 30)" % daily.size())
	var later: Array = Story.garden_seed({"daily": "2026-10-29", "world": 5, "gardens": 3}, "2026-10-29")
	_expect(not bool(later[1]) and int(later[0]) == Seeded.derive(5, 3), "later gardens today come from the world seed")
	# Story rules.
	_expect(Story.kinds_for(0) == 1 and Story.kinds_for(4) == 2 and Story.kinds_for(20) == 3 and Story.kinds_for(999) == 3, "seed kinds arrive with the jars")
	_expect(Story.shelf(5) == [5, 0] and Story.shelf(Story.SHELF_SLOTS + 3) == [Story.SHELF_SLOTS - 3, 3], "the shelf fills, then jars turn gold")
	_expect(int(Story.save_defaults().decor) == 2 and int(Story.save_defaults().world) < 0, "a new garden starts with the gnome and the bird bath")
	for k in Story.LINES:
		_expect(String(Story.LINES[k]).length() <= 26, "the %s line is short" % k)
	# The generator's copies of game numbers match the game.
	for k in 3:
		_expect(is_equal_approx(Gen.KIND_H[k], float(W.KINDS[k].h)) and Gen.KIND_HONEY[k] == int(W.KINDS[k].honey), "kind %d facts match world.gd" % k)
	_expect(Gen.HIVE_ENTRY == W.HIVE_ENTRY, "the hive entry matches world.gd")
	_expect(is_equal_approx(Gen.BEE_SPEED, Bee.SPEED * 0.55) and Gen.BEE_LOAD == Bee.MAX_POLLEN and is_equal_approx(Gen.HELPER_SPEED, Helpers.SPEED), "bee facts match bee.gd / helpers.gd")
	_expect(Gen.SPOTS == W.SPOTS and absf(Gen.X_MAX) < W.BED_X - 0.5 and -Gen.Z_MIN < W.BED_Z, "the bed fits world.gd")
	_expect(Story.DECOR_MAX == W.DECOR.size(), "decor count matches world.gd")
	# Every picture Queen Bea shows exists (story_card.gd).
	var pics: Array = ["queenbee", "hive", "honeyjar", "cloud", "sun"]
	pics.append_array(Story.KIND_PICS)
	for pic in pics:
		_expect(StoryCard.PICTURES.has(pic), "the %s picture exists" % pic)
	print("bee gen: %d gardens checked, %d round plans, plans %s, features %s, weather %s, %d failures" % [total, days, str(plans), str(feats), str(weathers), fails])
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)


func _has(why: Array, word: String) -> bool:
	for w in why:
		if String(w).contains(word):
			return true
	return false


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	if fails <= 60:
		print("SCRIPT ERROR: bee gen: " + what)
