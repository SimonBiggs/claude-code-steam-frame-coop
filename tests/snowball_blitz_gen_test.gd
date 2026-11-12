extends SceneTree
## SNOWBALL BLITZ generator: proves every seeded siege is fair for small kids (no game, no window).
##   godot-test --headless --path . -s res://tests/snowball_blitz_gen_test.gd      (SEEDS=500 for more)
## For every level and TODAY'S BLIZZARD: games/snowball_blitz/siegegen.gd check() (gates spread out and in
## front at first, one new kind per wave and nothing unmet, no too-short gaps, no wall swamped, a small
## child alone holds the first waves, a VR player + a child hold waves 3-4), the same
## seed gives the same siege, the challenge rises level by level and wave by wave, every new kind arrives
## in every slot over the seeds, endless waves are made on demand, TODAY'S BLIZZARD is the same all day and
## differs between days, the village has room outside the square and clear of the big tree, Bobo's
## pictures exist, the constants match the game's, and generation stays fast. MODES: every mode fair, gentle <= brave
## <= hard wave by wave, each mode's average curve rises smoothly (no cliff). BOSSES (bosses.gd check: every big attack
## told long enough, longer in gentle, soft gentle hits, a breather). BOBO'S GIFTS (gifts.gd: names, pictures, caps,
## offers at every village size). Prints "SCRIPT ERROR: ..."
## per failure.

const G := preload("res://games/snowball_blitz/siegegen.gd")
const Main := preload("res://games/snowball_blitz/main.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")
const Bosses := preload("res://games/snowball_blitz/bosses.gd")
const Gifts := preload("res://games/snowball_blitz/gifts.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")

var fails := 0


func _initialize() -> void:
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
			if a.boss == "" and b.boss == "" and n != G.GIANT_WAVE:  # (the giants' wave: fewer, bigger)
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
	# TODAY'S BLIZZARD over 400+ days (and the 60 from whenever this runs), the way _new_siege builds it: the
	# DAILY_LEVEL siege from daily_seed(date) in every mode (check()), gentle <= brave <= hard (check_modes).
	var rd := Seeded.validate_days(func(date: String) -> Array:
			var out: Array = [G.daily_seed(date)]
			for mode in G.MODES:
				out.append(G.siege(G.daily_seed(date), G.DAILY_LEVEL, true, mode))
			return out,
		func(day: Array) -> Array:
			var why: Array = []
			for k in range(1, day.size()):
				for w in G.check(day[k]):
					why.append("%s: %s" % [G.MODES[k - 1], w])
			for w in G.check_modes(int(day[0]), G.DAILY_LEVEL, true):
				why.append("modes: " + w)
			return why, 400, "TODAY'S BLIZZARD", ["2026-11-11", "2026-11-12"])
	gens += int(rd.checked) * G.MODES.size()
	fails += (rd.failures as Array).size()
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
	# MODES (gentle / brave / hard): every mode's sieges are fair, gentle <= brave <= hard wave by wave, and each mode's
	# average curve rises smoothly (no cliff).
	for mode in G.MODES:
		for lv in [1, G.MAX_LEVEL]:
			var mres := Seeded.validate(func(s: int) -> Dictionary: return G.siege(s, lv, false, mode),
				func(s: Dictionary) -> Array: return G.check(s), seeds / 2, 77 + lv, [0], "SIEGE %s level %d" % [mode, lv])
			gens += int(mres.checked)
			fails += (mres.failures as Array).size()
	var mode_bad := 0
	for lv in range(1, G.MAX_LEVEL + 1):
		for k in seeds / 3:
			for why in G.check_modes(k * 131 + lv, lv):
				mode_bad += 1
				if mode_bad <= 5:
					_expect(false, "modes (seed %d level %d): %s" % [k * 131 + lv, lv, why])
	_expect(mode_bad == 0, "gentle <= brave <= hard in every wave (%d problems)" % mode_bad)
	for lv in range(1, G.MAX_LEVEL + 1):
		var curves := {}
		for mode in G.MODES:
			curves[mode] = G.curve(mode, lv, 40)
			for why in G.check_curve(curves[mode]):
				_expect(false, "%s level %d curve: %s" % [mode, lv, why])
		for n in G.FINALE:
			_expect(float(curves.gentle[n]) <= float(curves.brave[n]) and float(curves.brave[n]) <= float(curves.hard[n]),
				"level %d wave %d: gentle <= brave <= hard on average" % [lv, n + 1])
		if lv == 1:
			print("average threat by wave (level 1): gentle %s / brave %s / hard %s" % [curves.gentle.map(func(x): return snappedf(x, 0.01)),
				curves.brave.map(func(x): return snappedf(x, 0.01)), curves.hard.map(func(x): return snappedf(x, 0.01))])
	_expect(G.wave_count(1, 1, "", "gentle") <= G.wave_count(1, 1, "", "brave") and G.speed_of("snowman", 3, "gentle") < G.speed_of("snowman", 3, "hard"),
		"gentle sends fewer, slower snowmen than hard")
	var cliffy := G.siege(5, 2).duplicate(true)
	var w6: Array = (cliffy.waves as Array)[5].spawns
	for i in 3:
		w6.append_array(w6.duplicate(true))
	for sp in w6:
		sp[0] = G.MIN_GAP
	_expect((G.check(cliffy) as Array).any(func(w: String) -> bool: return w.contains("cliff")), "the validator catches a cliff wave")
	var flat: Array[float] = [1.0, 2.0, 2.2, 6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0]
	_expect(not G.check_curve(flat).is_empty(), "the curve check catches a jump")
	# BOSSES: every big attack is told (long enough, longer in gentle), gentle hits are soft, a breather between attacks.
	for k in Bosses.KINDS:
		for why in Bosses.check(k):
			_expect(false, "boss: " + why)
		_expect(StoryCard.has_picture(String(Bosses.info(k).pic)), "%s has a picture" % k)
		_expect(float(Bosses.numbers(k, "gentle", false).tell) > float(Bosses.numbers(k, "brave", false).tell), "%s tells longer in gentle" % k)
		_expect(float(Bosses.numbers(k, "hard", true).every) >= float(Bosses.numbers(k, "hard", true).tell) + Bosses.REST, "%s hard angry still breathes" % k)
		_expect(G.boss_for(G.KING_WAVE) == "king" and G.boss_for(G.FINALE) == "yeti", "the king and the yeti come")
	_expect(not Bosses.check("dragon").is_empty(), "the boss check catches an unknown boss")
	# BOBO'S GIFTS: names fit the orbs, pictures exist, capped, a full offer at every village size, the same offer everywhere.
	var ui_src := FileAccess.get_file_as_string("res://core/ui_kit.gd")
	var has_pic := func(n: String) -> bool: return StoryCard.has_picture(n) or ui_src.contains('"%s":' % n)
	for why in Gifts.check_lists(has_pic):
		_expect(false, "gifts: " + why)
	for d in PickOrbs.MODES:
		_expect(bool(has_pic.call(String(d.pic))), "mode %s has a picture" % d.id)
	for igloos in [0, 2, 4, 8, 99]:
		var open := Gifts.unlocked(igloos)
		for sd in 30:
			for n in [1, 4, 9, 15]:
				var ids := Gifts.offer(sd * 977 + 1, n, open)
				for why in Gifts.check_offer(ids, open):
					_expect(false, "gift offer (igloos %d seed %d wave %d): %s" % [igloos, sd, n, why])
	_expect(var_to_str(Gifts.offer(42, 3, Gifts.unlocked(9))) == var_to_str(Gifts.offer(42, 3, Gifts.unlocked(9))), "the same gift orbs on every machine")
	_expect(Gifts.unlocked(99).size() > Gifts.unlocked(0).size(), "Bobo's village unlocks more gifts")
	_expect(not Gifts.check_offer(["big", "big", "nope"], Gifts.unlocked(0)).is_empty(), "the offer check catches a bad offer")
	_expect(Gifts.default_pick(["a", "b", "c"]) == "b", "the middle orb is taken for whoever doesn't choose")
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
