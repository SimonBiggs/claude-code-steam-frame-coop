extends SceneTree
## TREASURE DIG islands: proves the seeded islands are fair over many seeds (no game, no window).
##   godot-test --headless --path . -s res://tests/treasure_dig_gen_test.gd      (SEEDS=500 for more)
## For every island kind and level: games/treasure_dig/islandgen.gd check() (burial spots on the sand,
## clear of the chest, the rocks and each other; the relic reachable; exactly three map pieces, not too
## deep; not too many boots; palms out of the diggers' way), the same seed gives the same island, boots
## and depth rise with the level, each kind keeps its own mix, TODAY'S ISLAND is the same all day, the
## story rules, and generation stays fast. Prints "SCRIPT ERROR: ..." for each failure.

const IslandGen := preload("res://games/treasure_dig/islandgen.gd")
const Story := preload("res://games/treasure_dig/story.gd")
const Seeded := preload("res://core/seeded.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 100
	var total := 0
	var t0 := Time.get_ticks_usec()
	var gens := 0
	var boots := {}
	var gems := {}
	for isl in Story.ISLANDS:
		for level in [0, 3, 8, 30]:
			var sp := {"kind": isl.id, "level": level}
			var r := Seeded.validate(func(s: int) -> Dictionary: return IslandGen.generate(s, sp),
				func(g: Dictionary) -> Array: return IslandGen.check(g), seeds, 9 + level, [0, 1, 999999], "ISLAND %s l%d" % [isl.id, level])
			total += int(r.checked)
			gens += int(r.checked) * 2
			fails += (r.failures as Array).size()
			for s in 30:
				var g := IslandGen.generate(500 + s, sp)
				for k in g.deck:
					var key := "%s:%d" % [isl.id, level]
					if int(k) == Story.KIND_BOOT:
						boots[key] = int(boots.get(key, 0)) + 1
					if int(k) == Story.KIND_GEM:
						gems[isl.id] = int(gems.get(isl.id, 0)) + 1
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens)
	print("island gen: %.3f ms per island (%d islands)" % [per_ms, gens])
	_expect(per_ms < 20.0, "an island generates in under 20 ms here (%.2f ms)" % per_ms)
	_expect(int(boots["sunny:8"]) > int(boots["sunny:0"]), "more boots on later islands (%s)" % str(boots))
	_expect(int(gems["jungle"]) > int(gems["sunny"]), "the jungle has more gems than the sunny isle (%s)" % str(gems))
	var g0 := IslandGen.generate(42, {"kind": "sunny", "level": 0})
	var g9 := IslandGen.generate(42, {"kind": "sunny", "level": 9})
	_expect(int(g9.map_at[0]) > int(g0.map_at[0]) or int(g9.map_at[-1]) > int(g0.map_at[-1]), "map pieces lie deeper on later islands")
	# TODAY'S ISLAND.
	var days := {}
	for d in 40:
		var date := Time.get_date_string_from_unix_time(1790000000 + d * 86400)
		var dl := Story.daily(date)
		var g := IslandGen.generate(int(dl[0]), {"kind": dl[1], "level": 3})
		for w in IslandGen.check(g):
			_fail("daily %s: %s" % [date, w])
		_expect(var_to_str(dl) == var_to_str(Story.daily(date)), "daily %s is the same all day" % date)
		days[var_to_str(g.spots)] = true
	_expect(days.size() >= 38, "daily islands differ (%d of 40)" % days.size())
	# Hand checks.
	var bad := g0.duplicate(true)
	(bad.spots as Array)[1] = (bad.spots as Array)[0]
	_expect(not IslandGen.check(bad).is_empty(), "two treasures in one spot is caught")
	var bad2 := g0.duplicate(true)
	bad2.relic = Vector3.ZERO
	_expect(not IslandGen.check(bad2).is_empty(), "a relic under the chest is caught")
	var bad3 := g0.duplicate(true)
	(bad3.deck as Array)[int(bad3.map_at[0])] = Story.KIND_COIN
	_expect(not IslandGen.check(bad3).is_empty(), "a missing map piece is caught")
	# Story.
	var o := Story.offers(7, 3, {})
	_expect(o.size() == 2 and o[0] != o[1], "two different islands to pick (%s)" % str(o))
	_expect(not Story.offers(7, 3, {"sunny": 5, "jungle": 5}).has("sunny"), "the least-visited islands come first")
	_expect(Story.next_relic([0, 1]) == 2, "relics come in order")
	_expect(Story.save_defaults().relics.is_empty(), "a new collection is empty")
	print("island gen: %d islands checked, %d failures" % [total, fails])
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: island gen: " + what)
