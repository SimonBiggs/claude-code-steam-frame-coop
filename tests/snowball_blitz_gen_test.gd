extends SceneTree
## SNOWBALL BLITZ generator: proves every seeded siege is fair for small kids (no game, no window).
##   godot-test --headless --path . -s res://tests/snowball_blitz_gen_test.gd      (SEEDS=500 for more)
## For every level and TODAY'S BLIZZARD: games/snowball_blitz/siegegen.gd check() (gates spread out and in
## front at first, one new kind per wave and nothing unmet, no too-short gaps, no wall swamped, a small
## child alone holds the first waves, a VR player + a child hold waves 3-4), the same
## seed gives the same siege, the challenge rises level by level and wave by wave, every new kind arrives
## in every slot over the seeds, endless waves are made on demand, TODAY'S BLIZZARD is the same all day and
## differs between days, the village has room outside the square and clear of the big tree, Bobo's
## pictures exist, the constants match the game's, and generation stays fast. Prints "SCRIPT ERROR: ..."
## per failure.

const G := preload("res://games/snowball_blitz/siegegen.gd")
const Main := preload("res://games/snowball_blitz/main.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 120
	var t0 := Time.get_ticks_usec()
	var gens := 0
	var seen := {}
	var avg_count := {}
	var avg_kid := {}
	for lv in range(1, G.MAX_LEVEL + 1):
		var res := Seeded.validate(func(s: int) -> Dictionary: return G.siege(s, lv),
			func(s: Dictionary) -> Array: return G.check(s), seeds, 31 + lv, [0, 999999], "SIEGE level %d" % lv)
		gens += int(res.checked)
		fails += (res.failures as Array).size()
		for k in 40:
			var s := G.siege(k * 17 + 3, lv)
			if int(s.gentle) > 0:
				seen["gentle"] = int(seen.get("gentle", 0)) + 1
			for n in (s.new as Dictionary):
				seen["%s@%d" % [s.new[n], int(n)]] = true
			seen["want:%d" % int(s.want)] = true
			var c := 0
			for w in s.waves:
				c += (w.spawns as Array).size()
				for g in w.gates:
					seen["side:%d" % (int(roundf(wrapf(float(g), 0.0, TAU) / (TAU / 4.0))) % 4)] = true
			avg_count[lv] = float(avg_count.get(lv, 0.0)) + c / 40.0
			avg_kid[lv] = float(avg_kid.get(lv, 0.0)) + G.hold(G.wave_plan(s, 3), G.KID_RATE, G.KID_SPOT) / 40.0
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens)
	print("siege gen: %.3f ms per siege incl. check (%d sieges)" % [per_ms, gens])
	_expect(per_ms < 5.0, "a siege generates + checks in under 5 ms here (%.2f ms; Decks are slower, aim < 100)" % per_ms)
	print("snowmen per siege by level: %s" % str(avg_count))
	print("wall left after wave 3 with a small child alone, by level: %s" % str(avg_kid))
	print("sieges that needed a gentler try: %d of %d" % [int(seen.get("gentle", 0)), 40 * G.MAX_LEVEL])
	for lv in range(2, G.MAX_LEVEL + 1):
		_expect(float(avg_count[lv]) > float(avg_count[lv - 1]), "higher levels send more snowmen (%d)" % lv)
	# Wave by wave: more snowmen, quicker gaps, more gates (one seed, every level).
	for lv in range(1, G.MAX_LEVEL + 1):
		var s := G.siege(777, lv)
		for n in range(2, G.FINALE + 1):
			var a: Dictionary = G.wave_plan(s, n - 1)
			var b: Dictionary = G.wave_plan(s, n)
			if a.boss == "" and b.boss == "":
				_expect((b.spawns as Array).size() >= (a.spawns as Array).size(), "wave %d sends no fewer than wave %d (level %d)" % [n, n - 1, lv])
			_expect((b.gates as Array).size() >= mini(2, (a.gates as Array).size()), "gates never drop below two once there are two")
	for k in G.NEW_KINDS:
		for wv in G.NEW_WAVES:
			_expect(seen.has("%s@%d" % [k, wv]), "%s can be the new kind in wave %d" % [k, wv])
	_expect(seen.has("giant@%d" % G.GIANT_WAVE), "the giants come in wave %d" % G.GIANT_WAVE)
	for i in G.WANTS.size():
		_expect(seen.has("want:%d" % i), "the snowmen sometimes want the %s" % G.WANT_NAMES[i])
	for q in 4:
		_expect(seen.has("side:%d" % q), "snowmen come from every side of the square (%d)" % q)
	# Determinism, endless waves, levels.
	var one := G.siege(4242, 2)
	_expect(var_to_str(one) == var_to_str(G.siege(4242, 2)), "the same seed gives the same siege")
	_expect(var_to_str(one) != var_to_str(G.siege(4243, 2)), "another seed gives another siege")
	for n in [11, 14, 18, 30]:
		var w := G.wave_plan(one, n)
		_expect(int(w.n) == n and not (w.spawns as Array).is_empty(), "endless wave %d is made" % n)
		_expect(var_to_str(w) == var_to_str(G.wave_plan(one, n)), "endless wave %d is the same every time" % n)
		_expect(String(w.boss) == G.boss_for(n), "endless wave %d boss" % n)
	_expect(G.level(0) == 1, "a new village starts at level 1")
	for i in 40:
		_expect(G.level(i + 1) >= G.level(i) and G.level(i) <= G.MAX_LEVEL, "levels rise with the village and stop at the top")
	# The validator really catches unfair sieges (it isn't just saying yes).
	var bad := G.siege(5, 2)
	var behind := bad.duplicate(true)
	(behind.waves as Array)[0].gates = [PI / 2.0]
	_expect(not G.check(behind).is_empty(), "wave 1 from behind is caught")
	var rush := bad.duplicate(true)
	for sp in (rush.waves as Array)[0].spawns:
		sp[0] = 0.5
	_expect(not G.check(rush).is_empty(), "a rushed wave 1 is caught")
	var early := bad.duplicate(true)
	((early.waves as Array)[1].spawns as Array)[1][1] = "giant"
	_expect(not G.check(early).is_empty(), "a giant in wave 2 is caught")
	var swamp := bad.duplicate(true)
	var w4: Dictionary = (swamp.waves as Array)[3]
	for sp in w4.spawns:
		sp[0] = G.MIN_GAP
		sp[2] = 0
		sp[3] = 0.0
		sp[1] = "snowman"
	_expect(not G.check(swamp).is_empty(), "a wave piled onto one wall is caught")
	var close := bad.duplicate(true)
	(close.waves as Array)[5].gates = [0.0, 0.2, 2.0]
	_expect(not G.check(close).is_empty(), "two gates side by side are caught")
	var no_new := bad.duplicate(true)
	for sp in (no_new.waves as Array)[2].spawns:
		sp[1] = "snowman"
	_expect(not G.check(no_new).is_empty(), "a wave without its new kind is caught")
	# TODAY'S BLIZZARD: valid, the same all day, different between days.
	for date in ["2026-10-29", "2026-12-25", "2027-01-01"]:
		var ds := G.daily_seed(date)
		var s := G.siege(ds, G.DAILY_LEVEL, true)
		for why in G.check(s):
			_expect(false, "TODAY'S BLIZZARD %s: %s" % [date, why])
		_expect(var_to_str(s) == var_to_str(G.siege(G.daily_seed(date), G.DAILY_LEVEL, true)), "TODAY'S BLIZZARD is the same all day")
	_expect(G.daily_seed("2026-10-29") != G.daily_seed("2026-10-30"), "a new TODAY'S BLIZZARD each day")
	# The village: room for plenty, each igloo its own spot, outside the square, clear of the big tree + pond.
	var spots: Array = []
	var tree := Vector3(0.0, 0.0, -(G.ARENA_RADIUS + 6.0))
	var pond := Vector3(G.ARENA_RADIUS + 6.5, 0.0, G.ARENA_RADIUS * 0.25)
	for i in G.VILLAGE_SLOTS:
		var at := G.village_slot(i)
		var rr := Vector2(at.x, at.z).length()
		_expect(rr > G.ARENA_RADIUS + 4.0, "igloo spot %d stands outside the fence (%.1f)" % [i, rr])
		_expect(at.z < 0.0, "igloo spot %d is in front of the fort (%s)" % [i, str(at)])
		_expect(at.distance_to(tree) > 3.6, "igloo spot %d is clear of the big tree" % i)
		_expect(at.distance_to(pond) > 8.0, "igloo spot %d is clear of the pond" % i)
		for o in spots:
			_expect((o as Vector3).distance_to(at) > 2.6, "igloo spot %d has room (%.1f)" % [i, (o as Vector3).distance_to(at)])
		spots.append(at)
	_expect(G.village_slot(G.VILLAGE_SLOTS) == Vector3.INF, "no spot past the end")
	_expect(G.VILLAGE_KEEP >= G.VILLAGE_SLOTS, "the save keeps a full village")
	_expect(G.igloo_stage(3, 3) == 1 and G.igloo_stage(3, 4) == 2 and G.igloo_stage(3, 9) == 3, "igloos grow a stage a day")
	# The game uses the same numbers.
	_expect(is_equal_approx(G.ARENA_RADIUS, Main.ARENA_RADIUS) and is_equal_approx(G.FORT_RADIUS, Main.FORT_RADIUS), "square + fort match main.gd")
	_expect(G.SEGMENTS == Main.SEGMENTS and is_equal_approx(G.SEG_MAX, Main.SEG_MAX), "walls match main.gd")
	_expect(G.FINALE == Main.SIMPLE_FINALE and G.KING_WAVE == Main.SIMPLE_KING, "boss waves match main.gd")
	var pics: Array = ["polarbear", "igloo", "sledman", "snowking", "yeti", "bunny", "balloon", "snowman"]
	pics.append_array(G.WANTS)
	for pic in pics:  # every picture Bobo shows
		_expect(StoryCard.has_picture(pic), "story picture %s exists" % pic)
	for why in StoryCard.check():
		_expect(false, why)
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: %s" % what)
