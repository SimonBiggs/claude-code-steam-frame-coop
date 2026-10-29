extends SceneTree
## FRUIT CATCH generator: proves every seeded harvest is catchable and fair (no game, no window).
##   godot-test --headless --path . -s res://tests/fruit_catch_gen_test.gd      (SEEDS=500 for more)
## For every level 1-6, TODAY'S HARVEST and short bot rounds: games/fruit_catch/harvestgen.gd check()
## (every fruit lands in the park clear of the trunk and bowl, no rotten apple lands by a good fruit at
## the same moment, recipes have plenty of their fruit, a small child alone finishes the first dish early
## with or without a giant, a quick player alone finishes all three), the same seed gives the same
## harvest, the challenge rises level by level, every dish / fruit shows up, TODAY'S HARVEST is the same
## all day and differs between days, the orchard has room and stands clear of the park, Nutmeg's pictures
## exist, the constants match the game's, and generation stays fast. Prints "SCRIPT ERROR: ..." per failure.

const G := preload("res://games/fruit_catch/harvestgen.gd")
const Main := preload("res://games/fruit_catch/main.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 120
	var t0 := Time.get_ticks_usec()
	var gens := 0
	var seen := {}
	var avg_need := {}
	var avg_rot := {}
	var avg_wind := {}
	var avg_kid := {}
	for lv in range(1, G.MAX_LEVEL + 1):
		for secs in [G.ROUND_SECS, 16.0]:
			var res := Seeded.validate(func(s: int) -> Dictionary: return G.harvest(s, lv, false, secs),
				func(h: Dictionary) -> Array: return G.check(h), seeds if secs == G.ROUND_SECS else seeds / 3,
				17 + lv, [0, 999999], "HARVEST level %d (%ds)" % [lv, int(secs)])
			gens += int(res.checked) * 2
			fails += (res.failures as Array).size()
		for s in 60:
			var h := G.harvest(s * 13 + 1, lv)
			var n := 0
			for dd in h.dishes:
				seen["d:%d" % int(dd[0])] = true
				for k in G.GOOD:
					n += int((dd[1] as Array)[k])
					if int((dd[1] as Array)[k]) > 0:
						seen["k:%d" % k] = true
			avg_need[lv] = float(avg_need.get(lv, 0.0)) + n / 60.0
			avg_rot[lv] = float(avg_rot.get(lv, 0.0)) + float(h.rotten) / 60.0
			avg_wind[lv] = float(avg_wind.get(lv, 0.0)) + (h.wind as Vector2).length() / 60.0
			var kid := G.solo(h, G.KID_SHARE, false)
			avg_kid[lv] = float(avg_kid.get(lv, 0.0)) + kid.size() / 60.0
			if (h.wind as Vector2).length() > 0.0:
				seen["wind"] = true
			for d in h.drops:
				seen["drop:%d" % int(d[2])] = true
				seen["branch:%d" % int(d[1])] = true
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens)
	print("harvest gen: %.3f ms per harvest incl. check (%d harvests)" % [per_ms, gens])
	_expect(per_ms < 5.0, "a harvest generates + checks in under 5 ms here (%.2f ms; Decks are slower, aim < 100)" % per_ms)
	print("average fruit needed per level: %s" % str(avg_need))
	print("average rotten share per level: %s" % str(avg_rot))
	print("average wind per level: %s" % str(avg_wind))
	print("dishes a small child finishes alone per level: %s" % str(avg_kid))
	for lv in range(2, G.MAX_LEVEL + 1):
		_expect(float(avg_need[lv]) >= float(avg_need[lv - 1]) - 0.01, "recipes never get smaller (%d)" % lv)
		_expect(float(avg_rot[lv]) >= float(avg_rot[lv - 1]), "rotten apples never get rarer (%d)" % lv)
		_expect(float(avg_wind[lv]) >= float(avg_wind[lv - 1]) - 0.001, "the breeze never calms going up (%d)" % lv)
	_expect(float(avg_need[G.MAX_LEVEL]) > float(avg_need[1]) * 1.6, "top harvests need clearly more fruit than warm-ups")
	for d in G.DISHES.size():
		_expect(seen.has("d:%d" % d), "dish %s shows up" % G.DISH_NAMES[d])
	for k in G.GOOD:
		_expect(seen.has("k:%d" % k), "fruit %s is in recipes" % G.KIND_NAMES[k])
	for k in G.ROTTEN + 1:
		_expect(seen.has("drop:%d" % k), "fruit kind %d falls" % k)
	for b in G.BRANCHES:
		_expect(seen.has("branch:%d" % b), "branch %d drops fruit" % b)
	_expect(seen.has("wind"), "breezy harvests happen")
	for n in range(1, 10):
		for trees in [0, 5, 20, 200]:
			_expect(G.level(n + 1, trees) >= G.level(n, trees), "levels never drop within a session")
			_expect(G.level(n, trees) >= 1 and G.level(n, trees) <= G.MAX_LEVEL, "level in range")
	_expect(G.level(1, 0) == 1, "the very first harvest is the easiest")
	# The validator really catches unfair harvests (it isn't just saying yes).
	var bad := G.harvest(5, 3)
	var trunk := bad.duplicate(true)
	(trunk.drops as Array)[3] = [(trunk.drops as Array)[3][0], 0, 0, 0.3, 0.2]
	_expect(not G.check(trunk).is_empty(), "fruit in the trunk is caught")
	var mean := bad.duplicate(true)
	var d0: Array = (mean.drops as Array)[4]
	(mean.drops as Array).insert(5, [float(d0[0]) + 0.3, d0[1], G.ROTTEN, d0[3], d0[4]])
	if int(d0[2]) != G.ROTTEN:
		_expect(not G.check(mean).is_empty(), "a rotten apple right by a good fruit is caught")
	var greedy := bad.duplicate(true)
	(greedy.dishes as Array)[0] = [0, [14, 0, 0, 0]]
	_expect(not G.check(greedy).is_empty(), "a recipe too big for a small child is caught")
	var away := bad.duplicate(true)
	away.wind = Vector2(3.0, 0.0)
	_expect(not G.check(away).is_empty(), "a gale is caught")
	# Shaking: the giant's branches mostly drop what the dish needs.
	var r := Seeded.rng(1, "shake")
	var hits := 0
	for i in 400:
		if G.shake_kind(r, [0, 3, 0, 0], 0.2) == G.ORANGE:
			hits += 1
	_expect(hits > 220, "shaking mostly drops the fruit the dish needs (%d / 400)" % hits)
	# TODAY'S HARVEST: valid, the same all day, different between days.
	for date in ["2026-10-29", "2026-12-25", "2027-01-01"]:
		var ds := G.daily_seed(date)
		var h := G.harvest(ds, G.DAILY_LEVEL, true)
		for why in G.check(h):
			_expect(false, "TODAY'S HARVEST %s: %s" % [date, why])
		_expect(var_to_str(h) == var_to_str(G.harvest(G.daily_seed(date), G.DAILY_LEVEL, true)), "TODAY'S HARVEST is the same all day")
		_expect(int((h.dishes as Array)[2][0]) == G.SALAD and int((h.dishes as Array)[G.DISH_COUNT - 1][0]) == G.SALAD, "TODAY'S HARVEST ends with a fruit salad feast")
	_expect(G.daily_seed("2026-10-29") != G.daily_seed("2026-10-30"), "a new TODAY'S HARVEST each day")
	# The orchard: room for plenty, each tree its own spot, outside the park, behind the big tree.
	var spots: Array = []
	for i in G.ORCHARD_SLOTS:
		var at := G.orchard_slot(i)
		var rr := Vector2(at.x, at.z).length()
		_expect(rr > G.ARENA + 1.0, "orchard spot %d stands outside the park (%.1f)" % [i, rr])
		_expect(at.z < 0.0, "orchard spot %d is behind the big tree (%s)" % [i, str(at)])
		for o in spots:
			_expect((o as Vector3).distance_to(at) > 1.2, "orchard spot %d has room" % i)
		spots.append(at)
	_expect(G.orchard_slot(G.ORCHARD_SLOTS) == Vector3.INF, "no spot past the end")
	_expect(G.ORCHARD_KEEP >= G.ORCHARD_SLOTS, "the save keeps a full orchard")
	_expect(absf(G.orchard_slot(0).x) < 0.5, "the first tree stands right behind the big tree")
	_expect(G.tree_stage(3, 3) == 1 and G.tree_stage(3, 4) == 2 and G.tree_stage(3, 9) == 3, "trees grow a stage a day")
	# The game uses the same numbers.
	_expect(is_equal_approx(G.ARENA, Main.ARENA) and is_equal_approx(G.SPEED, Main.SPEED), "park size + speed match main.gd")
	_expect(is_equal_approx(G.TRUNK_R, Main.TRUNK_R) and G.BRANCHES == Main.BRANCHES, "trunk + branches match main.gd")
	_expect(is_equal_approx(G.DROP_HEIGHT, Main.DROP_HEIGHT) and is_equal_approx(G.FALL_G, Main.FALL_G) and is_equal_approx(G.HANG_TIME, Main.HANG_TIME), "fall matches main.gd")
	_expect(G.BOWL_POS.is_equal_approx(Main.BOWL_POS) and is_equal_approx(G.BOWL_R, Main.BOWL_R), "bowl matches main.gd")
	var pics: Array = ["squirrel", "acorn"]
	pics.append_array(G.KIND_PICS)
	pics.append_array(G.DISH_PICS)
	for pic in pics:  # every picture Nutmeg shows
		_expect(StoryCard.has_picture(pic), "story picture %s exists" % pic)
	for why in StoryCard.check():
		_expect(false, why)
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: %s" % what)
