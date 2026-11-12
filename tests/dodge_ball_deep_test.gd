extends SceneTree
## SOFT DODGEBALL second pass validator (no game, no window): games/dodge_ball/deep.gd.
##   godot-test --headless --path . -s res://tests/dodge_ball_deep_test.gd      (SEEDS=200 for more; GEN_QUICK=1 samples)
## Proves, over many parks (every level, every mode, every season):
##   - GENTLE <= BRAVE <= HARD: the mode table (deep.gd ordered()) AND what the rounds really get (the park's level,
##     tricks a round, warning seconds, trick sizes, seconds out), and every moded park passes CourtGen.check;
##   - TumTum's tricks are fair (deep.gd problems(): none in round 1 or a round's first seconds, never two at once, over
##     before the round ends, told long enough for a small kid standing in the middle to run out round the cushions,
##     showers on the court, a stomp never fills it, hit by every trick a runner still plays most of the round), the
##     same every time and unchanged over the network (pack); the bots' short rounds too;
##   - TODAY'S PARK in every mode over 400+ dates: the park fair (CourtGen.check) and its tricks fair;
##   - TumTum's gifts: three different unlocked ones, the newest among them, not the last again when there are others,
##     every picture drawn, short names; every gift helps;
##   - the seasons: each has a picture, a short line and both tricks; every date has a season;
##   - the toys only grow, all come, stand on the lawn clear of the court, the park's things, each other and the
##     trees; the season props too;
##   - the pick rows: the court orbs over open court a runner can stand under (on every park), apart, above the
##     runners' heads; the VR orbs an arm's reach in front of the giant, small, apart;
##   - the validator catches unfair tricks; constants match main.gd; every key colour stands out (palette.gd);
##   - fast: a round's tricks are made and checked well under 100 ms.
## Prints "SCRIPT ERROR: ..." for each failure and "DODGE DEEP: PASS" / "FAIL".

const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/dodge_ball/deep.gd")
const G := preload("res://games/dodge_ball/courtgen.gd")
const Season := preload("res://games/dodge_ball/season.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const Seeded := preload("res://core/seeded.gd")
const TestTime := preload("res://tests/test_time.gd")

var fails := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	for w in Deep.ordered():
		_fail("modes: " + str(w))
	for w in Contrast.check_game("dodge_ball"):
		_fail("contrast: " + str(w))
	var Main: GDScript = load("res://games/dodge_ball/main.gd")
	_expect(Deep.RUN_SPEED < float(Main.SPEED), "a small kid runs slower than main.gd SPEED")
	_expect(is_equal_approx(Deep.COURT_X, Main.COURT_X) and Deep.COURT_Z == Main.COURT_Z, "deep.gd's court matches main.gd")
	_expect(is_equal_approx(Deep.BELLY_R, 0.42), "the belly target matches main.gd's old size")
	# Parks and tricks over many seeds (Seeded.validate: today's sample in a quick run).
	var worst_ms := [0.0]
	var sums := {}
	for m in PickOrbs.MODE_IDS:
		sums[m] = {"level": 0, "tricks": 0, "warn": 0.0, "size": 0.0, "out": 0.0, "n": 0}
	var seasons: Array = Deep.SEASONS.keys()
	var res := Seeded.validate(func(s: int) -> Array:
			var all: Array = []
			for lv in range(1, G.MAX_LEVEL + 1):
				all.append(G.code_of(s, lv, false))
			return all,
		func(all: Array) -> Array:
			var why: Array = []
			for code in all:
				for m in PickOrbs.MODE_IDS:
					var mc := Deep.mode_code(int(code), m)
					var rd := G.build(mc)
					for w in G.check(rd):
						why.append("%s park %d: %s" % [m, mc, w])
					var season: String = seasons[absi(int(code)) % 4]
					for spec in [{"mode": m, "season": season, "round": 2, "len": G.ROUND_TIME},
							{"mode": m, "season": season, "round": 5, "len": G.ROUND_TIME},
							{"mode": m, "season": season, "round": 1, "len": 18.0, "first": Deep.SHORT_FIRST}]:
						var t1 := Time.get_ticks_usec()
						var list := Deep.tricks(rd, spec)
						var probs := Deep.problems(rd, list, spec)
						worst_ms[0] = TestTime.worst(worst_ms[0], (Time.get_ticks_usec() - t1) / 1000.0, func() -> Variant:
							return Deep.problems(rd, Deep.tricks(rd, spec), spec))
						for w in probs:
							why.append("%s park %d (%s): %s" % [m, mc, str(spec), w])
						if var_to_str(list) != var_to_str(Deep.tricks(rd, spec)):
							why.append("%s park %d: tricks not deterministic" % [m, mc])
						for e in list:
							if var_to_str(Deep.unpack(Deep.pack(e))) != var_to_str(e):
								why.append("a trick changes over the network: %s" % str(e))
						if float(spec.len) >= G.ROUND_TIME:
							var sm: Dictionary = sums[m]
							sm.n += 1
							sm.level += int(rd.level)
							sm.tricks += list.size()
							for e in list:
								sm.warn += float(e.warn)
								sm.size += float(e.w)
								sm.out += Deep.trick_out(m)
					if not Deep.tricks(rd, {"mode": m, "season": season, "round": 1, "len": G.ROUND_TIME}).is_empty():
						why.append("tricks in round 1")
			return why,
		Seeded.test_count(60), 1, [], "DODGE DEEP")
	if not bool(res.ok):
		fails += 1
	# What the rounds really get: GENTLE <= BRAVE <= HARD.
	var avg := func(m: String, k: String) -> float:
		var sm: Dictionary = sums[m]
		return float(sm[k]) / maxf(1.0, float(sm.n))
	for k in ["level", "tricks", "out"]:
		_expect(avg.call("gentle", k) <= avg.call("brave", k) + 0.001 and avg.call("brave", k) <= avg.call("hard", k) + 0.001,
			"rounds: %s gentle %.2f <= brave %.2f <= hard %.2f" % [k, avg.call("gentle", k), avg.call("brave", k), avg.call("hard", k)])
	var per := func(m: String, k: String) -> float:
		return float((sums[m] as Dictionary)[k]) / maxf(1.0, float((sums[m] as Dictionary).tricks))
	_expect(per.call("gentle", "warn") >= per.call("brave", "warn") and per.call("brave", "warn") >= per.call("hard", "warn"), "tricks are told longest on gentle")
	_expect(avg.call("gentle", "tricks") < avg.call("hard", "tricks"), "hard has more tricks than gentle")
	_expect(avg.call("gentle", "tricks") >= 2.0, "even gentle rounds have tricks (%.1f)" % avg.call("gentle", "tricks"))
	_expect(worst_ms[0] < 100.0, "a round's tricks are made and checked fast (%.1f ms)" % worst_ms[0])
	# TODAY'S PARK over 400+ dates, every mode.
	var days := Seeded.validate_days(func(date: String) -> Dictionary:
			return G.build(G.code_at(1, 1, true, date)),
		func(rd: Dictionary) -> Array:
			var why: Array = G.check(rd)
			if not bool(rd.daily):
				why.append("not the daily park")
			for m in PickOrbs.MODE_IDS:
				if Deep.mode_code(int(rd.code), m) != int(rd.code):
					why.append("a mode changes TODAY'S PARK")
				for rn in [1, 2]:
					var spec := {"mode": m, "season": "winter", "round": rn, "len": G.ROUND_TIME}
					for w in Deep.problems(rd, Deep.tricks(rd, spec), spec):
						why.append("%s: %s" % [m, w])
			return why,
		400, "DODGE DAILY")
	if not bool(days.ok):
		fails += 1
	# The validator catches unfair tricks.
	var rd0 := G.build(G.code_of(7, 3, false))
	var spec0 := {"mode": "brave", "season": "spring", "round": 2, "len": G.ROUND_TIME}
	var quick := {"t": 20.0, "kind": "shower", "x": 0.0, "z": 1.0, "w": 1.8, "warn": 0.6}
	_expect(not Deep.problems(rd0, [quick], spec0).is_empty(), "a trick told too briefly is caught")
	var off := {"t": 20.0, "kind": "shower", "x": 6.0, "z": 1.0, "w": 1.8, "warn": 2.8}
	_expect(not Deep.problems(rd0, [off], spec0).is_empty(), "a shower off the court is caught")
	var early := {"t": 2.0, "kind": "stomp", "x": 0.0, "z": 1.0, "w": 1.25, "warn": 2.8}
	_expect(not Deep.problems(rd0, [early], spec0).is_empty(), "a trick in a round's first seconds is caught")
	var twin := {"t": 24.0, "kind": "stomp", "x": 0.0, "z": 4.0, "w": 1.25, "warn": 2.8}
	_expect(not Deep.problems(rd0, [{"t": 20.0, "kind": "stomp", "x": 0.0, "z": 0.0, "w": 1.25, "warn": 2.8}, twin], spec0).is_empty(), "two tricks at once are caught")
	var deep_band := {"t": 20.0, "kind": "stomp", "x": 0.0, "z": 1.2, "w": 4.5, "warn": 2.8}
	_expect(not Deep.problems(rd0, [deep_band], spec0).is_empty(), "a stomp filling the court is caught")
	var many: Array = []
	for i in 12:
		many.append({"t": 14.0 + 8.0 * i, "kind": "stomp", "x": 0.0, "z": -1.0 if i % 2 == 0 else 3.0, "w": 1.0, "warn": 3.4})
	_expect(not Deep.problems(rd0, many, {"mode": "hard", "round": 2, "len": G.ROUND_TIME}).is_empty(), "too many tricks are caught")
	_expect(Deep.inside({"kind": "shower", "x": 0.0, "z": 0.0, "w": 1.5}, Vector2(1.6, 0.0)) and not Deep.inside({"kind": "shower", "x": 0.0, "z": 0.0, "w": 1.5}, Vector2(2.0, 0.0)), "a runner's body counts at a shower's edge")
	# Gifts.
	for g in Deep.GIFTS:
		_expect(StoryCard.has_picture(String(g.pic)), "gift %s has a picture" % g.id)
		_expect(String(g.name).length() <= 14, "gift %s has a short name" % g.id)
		_expect(String(g.line).length() <= 28, "gift %s has a short line" % g.id)
	for toys_n in Deep.TOYS.size() + 1:
		var un := Deep.unlocked(toys_n)
		for last in [""] + un:
			for s in 12:
				var ch := Deep.gift_choices(toys_n, String(last), s * 977)
				_expect(ch.size() == 3, "three gifts offered (%d toys)" % toys_n)
				var seen := {}
				for id in ch:
					seen[id] = true
					_expect(un.has(id), "only unlocked gifts are offered")
				_expect(seen.size() == ch.size(), "three different gifts")
				if String(last) != un[un.size() - 1] or un.size() <= 3:
					_expect(ch.has(un[un.size() - 1]), "the newest gift is offered")
				if un.size() > 3:
					_expect(not ch.has(last) or String(last) == "", "not the last gift again")
	_expect(Deep.unlocked(0).size() == 3 and Deep.unlocked(Deep.TOYS.size()).size() == Deep.GIFTS.size(), "three gifts at first, all of them later")
	_expect(Deep.run_speed("shoes") > 1.0 and Deep.run_speed("") == 1.0, "SPEEDY SHOES run faster")
	_expect(Deep.pickup_r("magnet") > Deep.pickup_r(""), "the BALL MAGNET grabs from further")
	_expect(Deep.belly_r("curve", true) > Deep.belly_r("", true) and Deep.belly_r("curve", false) == Deep.belly_r("", false), "the CURVE BALL helps only the runners' throws")
	_expect(Deep.belly_bonus("squishy") > 0 and Deep.ball_scale("squishy") > 1.0, "SQUISHY BALL helps")
	# Seasons.
	for s in ["spring", "summer", "autumn", "winter"]:
		_expect(Deep.SEASONS.has(s), "season %s has a park" % s)
		var sd := Deep.season_data(s)
		_expect(StoryCard.has_picture(String(sd.pic)), "season %s has a picture" % s)
		_expect(String(sd.line).length() <= 28 and String(sd.name).length() <= 16, "season %s has a short line and name" % s)
		_expect((sd.weights as Array).size() == 2 and float(sd.weights[0]) > 0.0 and float(sd.weights[1]) > 0.0, "season %s has both tricks" % s)
	for date in Seeded.dates(370):
		_expect(Deep.SEASONS.has(Seeded.season(String(date))), "every date has a season (%s)" % date)
	for k in Deep.KINDS:
		_expect(StoryCard.has_picture(String(Deep.KIND_PICS[k])), "trick %s has a picture" % k)
		_expect(String(Deep.KIND_NAMES[k]).length() <= 14, "trick %s has a short banner" % k)
	# Toys and season props: on the lawn, clear of the court, the park's things, each other and the trees.
	var prev := 0
	var placed: Array = []
	for r in 60:
		_expect(Deep.toys(r) >= prev, "toys only grow")
		prev = Deep.toys(r)
	_expect(Deep.toys(Deep.TOY_EVERY * Deep.TOYS.size()) == Deep.TOYS.size(), "every toy comes")
	_expect(Deep.TOY_SPOTS.size() >= Deep.TOYS.size(), "a spot for every toy")
	for i in Deep.TOYS.size():
		_expect(StoryCard.has_picture(String(Deep.TOYS[i].pic)), "toy %s has a picture" % Deep.TOYS[i].id)
		var p: Vector2 = Deep.TOY_SPOTS[i]
		_expect(absf(p.x) - Deep.TOY_HALF > Main.WALL_X + 0.4, "toy %d stands off the court" % i)
		_expect(p.distance_to(Vector2(0.0, -1.0)) + Deep.TOY_HALF < 11.4, "toy %d stands inside the trees" % i)
		for q in placed:
			_expect(p.distance_to(q) > Deep.TOY_HALF * 2.0 + 0.3, "toy %d has room" % i)
		for k in G.PARK_SLOTS:
			var ps := G.park_slot(k)
			_expect(Vector2(ps.x, ps.z).distance_to(p) > Deep.TOY_HALF + 0.5, "toy %d is clear of the park's thing %d" % [i, k])
		placed.append(p)
	for i in Season.SPOTS.size():
		var p: Vector2 = Season.SPOTS[i]
		_expect(p.y < -9.2 - 0.6 or absf(p.x) > 4.0 + 0.8, "season prop %d is off the stage" % i)
		_expect(p.distance_to(Vector2(0.0, -1.0)) + 0.8 < 11.4, "season prop %d is inside the trees" % i)
		for q in placed:
			_expect(p.distance_to(q) > 1.6, "season prop %d has room" % i)
		placed.append(p)
	# The court pick row: over open court on every park, apart, above heads.
	var row := Deep.row_spots()
	for i in row.size():
		var sp: Vector3 = row[i]
		_expect(absf(sp.x) < Deep.COURT_X - 0.3 and sp.z > Deep.COURT_Z.x and sp.z < Deep.COURT_Z.y, "court orb %d floats over the court" % i)
		_expect(sp.y - Deep.orb_r(false) > 1.6, "court orb %d floats above the runners' heads" % i)
		for j in range(i + 1, row.size()):
			_expect(Vector2(sp.x, sp.z).distance_to(Vector2((row[j] as Vector3).x, (row[j] as Vector3).z)) > Deep.TV_R * 2.0 + 0.4, "court orbs %d and %d are apart" % [i, j])
	for s in 300:
		var rd := G.build(G.code_of(s * 31 + 5, 1 + s % G.MAX_LEVEL, s % 7 == 0))
		for i in row.size():
			var sp: Vector3 = row[i]
			_expect(Deep.standable(rd, Vector2(sp.x, sp.z)) and Deep.under(row, Vector3(sp.x, 0.0, sp.z)) == i, "a runner can stand under court orb %d (park %d)" % [i, int(rd.code)])
	# The VR pick row: an arm's reach, small, apart.
	var head := Vector3(0.0, 2.5, -6.4)
	var vr := Deep.vr_spots(head)
	for i in vr.size():
		var d: float = (vr[i] as Vector3).distance_to(head)
		_expect(d > 0.3 and d < 0.62, "VR orb %d is an arm's reach away (%.2f m)" % [i, d])
		for j in range(i + 1, vr.size()):
			_expect((vr[i] as Vector3).distance_to(vr[j]) > 2.0 * (Deep.orb_r(true) + Deep.HAND_R), "VR orbs %d and %d are apart" % [i, j])
	_expect(Deep.orb_r(true) > 0.05 and Deep.orb_r(true) < 0.12, "VR orbs are a modest size (%.2f m)" % Deep.orb_r(true))
	_expect(Deep.DWELL >= 0.3 and Deep.TV_DWELL >= 0.8, "picks need a deliberate touch")
	for why in StoryCard.check():
		_fail(why)
	print("dodge deep: %d ms" % (Time.get_ticks_msec() - t0))
	print("DODGE DEEP: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: %s" % what)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)
