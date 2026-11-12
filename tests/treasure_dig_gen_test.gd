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
const Deep := preload("res://games/treasure_dig/deep.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")

var fails := 0


func _initialize() -> void:
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
	# TODAY'S ISLAND over 400+ days (and the 60 from whenever this runs), the way _begin_island builds it: the
	# island Story.daily(date) picks at level 3 (Deep.island_spec per mode, IslandGen.check) and its warned events
	# (Deep.problems) for that date's season, the first round of a session, with and without the PARROT's gold.
	var days := {}
	var rd := Seeded.validate_days(func(date: String) -> Array:
			var dl := Story.daily(date)
			var season := Seeded.season(date) if Deep.SEASONS.has(Seeded.season(date)) else "spring"
			var out: Array = []
			for mode in PickOrbs.MODE_IDS:
				var desc := Deep.island_spec({"seed": int(dl[0]), "kind": String(dl[1]), "level": 3, "daily": true}, mode)
				var g := IslandGen.generate(int(dl[0]), desc)
				var evs: Array = []
				for gold in [0, Deep.PARROT_GOLD]:
					var spec := {"mode": mode, "time": 120.0, "season": season, "kind": String(dl[1]), "rocks": g.get("rocks", []), "extra_gold": gold}
					evs.append([spec, Deep.events(Seeded.derive(int(dl[0]), "ev1"), spec)])
				out.append([mode, g, evs])
			return out,
		func(day: Array) -> Array:
			var why: Array = []
			for me in day:
				for w in IslandGen.check(me[1]):
					why.append("%s island: %s" % [me[0], w])
				for se in me[2]:
					for x in Deep.problems(se[1], se[0]):
						why.append("%s events: %s" % [me[0], x])
			days[var_to_str(day[0][1].spots)] = true
			return why, 400, "TODAY'S ISLAND", ["2026-11-11", "2026-11-12"])
	total += int(rd.checked)
	fails += (rd.failures as Array).size()
	_expect(days.size() >= int(rd.checked) - 4, "daily islands differ (%d of %d)" % [days.size(), int(rd.checked)])
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
	_expect(o.size() == 3 and o[0] != o[1] and o[1] != o[2] and o[0] != o[2], "three different islands to pick (%s)" % str(o))
	_expect(not Story.offers(7, 3, {"sunny": 5, "jungle": 5}, 2).has("sunny"), "the least-visited islands come first")
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
