extends SceneTree
## HIDE AND SEEK houses: proves the seeded houses are fair over many seeds (no game, no window).
##   godot-test --headless --path . -s res://tests/hide_and_seek_gen_test.gd      (SEEDS=300 for more)
## For small (3 rooms across) and big (4 across) houses: games/hide_and_seek/housegen.gd check() (every
## room, doorway, spawn, star spot and the jail bell walkable for a hider and the seeker; every hiding
## spot reachable by a hider AND touchable by the seeker, so every hider can be found; no walled-off
## pockets; enough hiding spots, stars and decoys), the same seed gives the same house, houses differ,
## hiding spots move between houses, bigger houses later, TODAY'S HOUSE is the same all day, the story
## rules (themes unlock with Pip's toys), and a house generates fast. Prints "SCRIPT ERROR: ..." per failure.

const HouseGen := preload("res://games/hide_and_seek/housegen.gd")
const Story := preload("res://games/hide_and_seek/story.gd")
const Seeded := preload("res://core/seeded.gd")

var fails := 0


func _gen(s: int, sp: Dictionary) -> Dictionary:
	HouseGen.clear_cache()
	return HouseGen.generate(s, sp)


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 40
	var total := 0
	var t0 := Time.get_ticks_usec()
	var gens := 0
	var stat := {"attempts": 0, "spots_min": 999, "stars_min": 999}  # (lambdas can't change plain locals)
	for level in [0, 2, 5, 12]:
		var sp := {"level": level, "theme": level % Story.THEMES.size()}
		var r := Seeded.validate(func(s: int) -> Dictionary: return _gen(s, sp),
			func(g: Dictionary) -> Array:
				stat.attempts += int(g.attempt) + 1
				stat.spots_min = mini(int(stat.spots_min), (g.hide_spots as Array).size())
				stat.stars_min = mini(int(stat.stars_min), (g.star_spots as Array).size())
				var w := HouseGen.check(g)
				if not bool(g.ok):
					w.append("no try passed")
				return w, seeds, 11 + level, [0, 1, 999999], "HOUSE l%d" % level)
		total += int(r.checked)
		gens += int(r.checked) * 2
		fails += (r.failures as Array).size()
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens)
	var tries := float(stat.attempts) / maxf(1.0, total)
	print("house gen: %.1f ms per house (%d houses, %.2f tries each, at least %d hiding spots, %d star spots)" % [per_ms, gens, tries, stat.spots_min, stat.stars_min])
	_expect(per_ms < 60.0, "a house generates in under 60 ms here (%.1f ms; the Deck is about 1.5x slower)" % per_ms)
	_expect(tries < 3.0, "most houses pass on an early try (%.2f tries)" % tries)
	# Houses differ; hiding spots move; bigger later.
	var looks := {}
	for s in 20:
		var g := _gen(100 + s, {"level": 1})
		looks[var_to_str(g.hide_spots)] = true
	_expect(looks.size() >= 19, "houses differ (%d of 20)" % looks.size())
	var small := _gen(5, {"level": 0})
	var big := _gen(5, {"level": 6})
	_expect(int(big.cols) > int(small.cols), "later houses are bigger (%d -> %d rooms across)" % [small.cols, big.cols])
	_expect((big.decoys as Array).size() > (small.decoys as Array).size(), "later houses have more decoys")
	_expect(var_to_str(_gen(77, {"level": 3})) == var_to_str(_gen(77, {"level": 3})), "same seed, same house")
	# Every room type turns up, the hall has the jail, the garden has the shed and Pip's kennel.
	var kinds := {}
	for s in 30:
		var g := _gen(300 + s, {"level": 5})
		for pc in g.pieces:
			kinds[pc.k] = true
	for k in ["sofa", "table", "wardrobe", "fort", "ballpit", "bathtub", "bunk", "desk", "shed", "hedge", "kennel"]:
		_expect(kinds.has(k), "a %s turns up in some houses" % k)
	# TODAY'S HOUSE.
	var days := {}
	for d in 20:
		var date := Time.get_date_string_from_unix_time(1790000000 + d * 86400)
		var dl := Story.daily(date)
		_expect(var_to_str(dl) == var_to_str(Story.daily(date)), "daily %s is the same all day" % date)
		var g := _gen(int(dl.seed), dl)
		for w in HouseGen.check(g):
			_fail("daily %s: %s" % [date, w])
		days[int(dl.seed)] = true
	_expect(days.size() >= 19, "daily houses differ (%d of 20)" % days.size())
	# The validator catches broken houses.
	var g0 := _gen(42, {"level": 0})
	var bad := g0.duplicate(true)
	var d0: Vector3 = bad.doors[0][1]
	(bad.solids as Array).append([d0 + Vector3(0, 1.0, 0), Vector3(1.8, 2.0, 1.8)])
	_expect(not HouseGen.check(bad).is_empty(), "a doorway blocked by a box is caught")
	var bad2 := g0.duplicate(true)
	var s0: Vector3 = bad2.hide_spots[0]
	(bad2.solids as Array).append([s0 + Vector3(0, 1.0, 0), Vector3(2.6, 2.0, 0.1)])
	(bad2.solids as Array).append([s0 + Vector3(0, 1.0, 0), Vector3(0.1, 2.0, 2.6)])
	_expect(not HouseGen.check(bad2).is_empty(), "a hiding spot walled in is caught")
	var bad3 := g0.duplicate(true)
	(bad3.hide_spots as Array)[0] = bad3.jail
	_expect(not HouseGen.check(bad3).is_empty(), "a hiding spot inside the jail is caught")
	# Story.
	_expect(Story.unlocked(0) == [0], "only the cosy house at first")
	_expect(Story.unlocked(9).size() == Story.THEMES.size(), "every look with 9 toys")
	_expect(Story.new_theme(2, 3) == 1 and Story.new_theme(3, 4) == -1, "the seaside look comes with the third toy")
	var hs := Story.house_spec(1234, 7, 0)
	_expect(int(hs.theme) == 0 and int(hs.level) == 7, "a house spec keeps to unlocked looks (%s)" % str(hs))
	_expect(Story.house_spec(1234, 7, 0).seed == hs.seed and Story.house_spec(1234, 8, 0).seed != hs.seed, "house seeds: same n same seed")
	print("house gen: %d houses checked, %d failures" % [total, fails])
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: house gen: " + what)
