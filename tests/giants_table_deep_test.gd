extends SceneTree
## GIANT'S TABLE second pass validator (no game, no window): games/giants_table/deep.gd.
##   godot-test --headless --path . -s res://tests/giants_table_deep_test.gd      (SEEDS=200 for more; GEN_QUICK=1 samples)
## Proves, over many raids, every party (the Giant alone, with 1..6 knights) and every wave to RaidGen.MAX_WAVE:
##   - GENTLE <= BRAVE <= HARD: the mode table (deep.gd ordered()) AND what the waves really get (goblins a wave,
##     how quickly they come, tricks a wave, warning seconds, trick sizes), and every GENTLE / HARD plan passes the raid's
##     own fairness proof (RaidGen.check: the slow kid copes, ladders, kinds by wave ...), deterministic;
##   - the tricks are fair (deep.gd problems(): none in the first waves or a wave's first seconds, never two at once,
##     all while the goblins come, told long enough for a small knight standing in the middle to walk out, goo on open
##     ground off the fire, the river and the cottages, a barrel band clear of the fire and the cottages that rolls by
##     in time, never a bump that puts a knight down), the same every time and unchanged over the network (pack);
##   - TODAY'S RAID in every mode over 400+ dates: the night (waves 1..NIGHT_WAVES) fair for the slow kid with the
##     fire never low (the same ember sim as RaidGen.check_night) and its tricks fair;
##   - Sparky's gifts: three different unlocked ones, the newest among them, not the last again when there are others,
##     every picture drawn, short names; every gift helps (never a slower Giant or quicker goblins);
##   - the seasons: each has a picture, a line and both tricks; every date has a season;
##   - Sparky's table treasures only grow, finish, and sit on the rim clear of every lantern and gift;
##   - the pick row: in front of the Giant (an arm's reach for the VR Giant), over open walkable ground a knight can
##     stand on, orbs apart, a modest size, the flat Giant's and a knight's reach never covering two orbs;
##   - the validator catches unfair tricks; constants match knight.gd; every key colour stands out (palette.gd);
##   - fast: a wave's plan + tricks are made and checked well under 100 ms (the host plans one between waves).
## Prints "SCRIPT ERROR: ..." for each failure and "GIANTS DEEP: PASS" / "FAIL".

const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/giants_table/deep.gd")
const RaidGen := preload("res://games/giants_table/raidgen.gd")
const W := preload("res://games/giants_table/world.gd")
const Knight := preload("res://games/giants_table/knight.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const Seeded := preload("res://core/seeded.gd")
const TestTime := preload("res://tests/test_time.gd")
const PARTIES := [[0, true], [0, false], [1, false], [2, false], [4, false]]  # [extra knights, solo]

var fails := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	W.field(false, false)
	W.field(true, false)
	for w in Deep.ordered():
		_fail("modes: " + str(w))
	for w in Contrast.check_game("giants_table"):
		_fail("contrast: " + str(w))
	var k := Knight.new()
	_expect(is_equal_approx(Deep.KNIGHT_SPEED, Knight.SPEED) and is_equal_approx(Deep.KNIGHT_R, k.radius), "deep.gd's knight speed / size match knight.gd")
	k.free()
	# Plans and tricks over many raids (Seeded.validate: today's sample in a quick run).
	var worst_ms := [0.0]
	var sums := {}
	for m in PickOrbs.MODE_IDS:
		sums[m] = {"goblins": 0, "tricks": 0, "warn": 0.0, "goo_r": 0.0, "barrel_w": 0.0, "waves": 0}
	var res := Seeded.validate(func(s: int) -> Array:
			var all: Array = []
			for party in PARTIES:
				for n in range(1, RaidGen.MAX_WAVE + 1):
					all.append([s, n, party[0], party[1]])
			return all,
		func(all: Array) -> Array:
			var why: Array = []
			for job in all:
				var s: int = job[0]
				var n: int = job[1]
				var t1 := Time.get_ticks_usec()
				why.append_array(Deep.order_problems(s, n, job[2], job[3]))
				worst_ms[0] = TestTime.worst(worst_ms[0], (Time.get_ticks_usec() - t1) / 1000.0, func() -> Variant: return Deep.order_problems(s, n, job[2], job[3]))
				for m in PickOrbs.MODE_IDS:
					var p := Deep.plan(s, n, job[2], job[3], m)
					var season: String = Deep.SEASONS.keys()[(s + n) % 4]
					var spec := {"mode": m, "season": season, "send": Deep.send_secs(p)}
					var list := Deep.tricks(s, n, spec)
					for w in Deep.problems(list, n, spec):
						why.append("%s wave %d tricks: %s" % [m, n, w])
					if var_to_str(list) != var_to_str(Deep.tricks(s, n, spec)):
						why.append("%s wave %d: tricks not deterministic" % [m, n])
					for e in list:
						if var_to_str(Deep.unpack(Deep.pack(e))) != var_to_str(e):
							why.append("a trick changes over the network: %s" % str(e))
					var sm: Dictionary = sums[m]
					sm.goblins += (p.spawns as Array).size()
					sm.waves += 1
					sm.tricks += list.size()
					for e in list:
						sm.warn += float(e.warn)
						sm["goo_r" if String(e.kind) == "goo" else "barrel_w"] += float(e.r)
			return why,
		Seeded.test_count(24, 6), 1, [0, 999999, RaidGen.daily_seed("2026-11-12")], "GIANTS DEEP")
	fails += (res.failures as Array).size()
	var g: Dictionary = sums.gentle
	var b: Dictionary = sums.brave
	var h: Dictionary = sums.hard
	print("modes over %d waves each: goblins %d / %d / %d, tricks %d / %d / %d" % [b.waves, g.goblins, b.goblins, h.goblins, g.tricks, b.tricks, h.tricks])
	_expect(g.goblins < b.goblins and b.goblins < h.goblins, "GENTLE < BRAVE < HARD goblins (%d / %d / %d)" % [g.goblins, b.goblins, h.goblins])
	_expect(g.tricks < b.tricks and b.tricks < h.tricks, "GENTLE < BRAVE < HARD tricks (%d / %d / %d)" % [g.tricks, b.tricks, h.tricks])
	_expect(g.tricks > 0, "GENTLE still has a few tricks")
	_expect(worst_ms[0] < 100.0, "a wave's three plans are made and checked in under 100 ms (worst %.1f ms)" % worst_ms[0])
	# TODAY'S RAID in every mode (the night for the solo Giant and a party picked by the date).
	var rs := Seeded.validate_days(func(date: String) -> Dictionary:
			var ds := RaidGen.daily_seed(date)
			return {"seed": ds, "party": PARTIES[1 + absi(hash(date)) % (PARTIES.size() - 1)], "season": Seeded.season(date)},
		func(r: Dictionary) -> Array:
			var why: Array = []
			for m in PickOrbs.MODE_IDS:
				for party in [[0, true], r.party]:
					for w in night_problems(int(r.seed), party[0], party[1], m, String(r.season)):
						why.append("%s %s: %s" % [m, str(party), w])
			return why, 400, "TODAY'S RAID (modes)", ["2026-11-12", "2026-11-13"])
	fails += (rs.failures as Array).size()
	# The validator catches unfair tricks.
	var md := Deep.mode_data("brave")
	var good := {}
	for a in 72:  # a fair goo spot: open ground about 8 from the fire
		var at := Vector2(cos(a * TAU / 72.0), sin(a * TAU / 72.0)) * 8.0
		var e := {"t": 10.0, "kind": "goo", "warn": float(md.warn), "x": at.x, "z": at.y, "dx": 0.0, "dz": 1.0, "r": 2.0, "cx": at.x * 1.8, "cz": at.y * 1.8}
		if Deep._where_problem(e, []).is_empty():
			good = e
			break
	_expect(not good.is_empty(), "there is open ground for goo")
	var spec0 := {"mode": "brave", "send": 60.0}
	_expect(Deep.problems([good], 4, spec0).is_empty(), "a fair goo trick passes (%s)" % str(Deep.problems([good], 4, spec0)))
	_expect(not Deep.problems([good.merged({"x": 0.0, "z": 2.0}, true)], 4, spec0).is_empty(), "goo on the campfire is caught")
	_expect(not Deep.problems([good.merged({"warn": 1.0}, true)], 4, spec0).is_empty(), "a trick told too briefly is caught")
	_expect(not Deep.problems([good.merged({"t": 2.0}, true)], 4, spec0).is_empty(), "a trick in a wave's first seconds is caught")
	_expect(not Deep.problems([good], 1, spec0).is_empty(), "a trick in wave 1 is caught")
	_expect(not Deep.problems([good, good.merged({"t": 14.0}, true)], 4, spec0).is_empty(), "two tricks at once is caught")
	_expect(not Deep.problems([good.merged({"x": W.COTTAGES[0][0], "z": W.COTTAGES[0][1]}, true)], 4, spec0).is_empty(), "goo on a cottage is caught")
	_expect(not Deep.problems([good.merged({"r": 6.0}, true)], 4, spec0).is_empty(), "goo too big to walk out of is caught")
	var bar := {"t": 10.0, "kind": "barrel", "warn": float(md.warn), "x": 0.0, "z": 3.0, "dx": 1.0, "dz": 0.0, "r": 1.1, "cx": 0.0, "cz": 0.0}
	_expect(not Deep.problems([bar], 4, spec0).is_empty(), "a barrel through the village is caught")
	_expect(not Deep.problems([good.merged({"t": 70.0}, true)], 4, spec0).is_empty(), "a trick after the goblins have all come is caught")
	# Gifts.
	for treasures in range(0, Deep.TREASURES.size() + 1):
		for last in ["", "bigfire", "shield", "sleepy", "bighands"]:
			var ch := Deep.gift_choices(treasures, last, treasures * 31 + last.length())
			var un := Deep.unlocked(treasures)
			var distinct := {}
			for id in ch:
				distinct[id] = true
				_expect(un.has(id), "gift %s offered before it opens" % id)
			_expect(ch.size() == 3 and distinct.size() == 3, "three different gifts (%s)" % str(ch))
			_expect(ch.has(un[un.size() - 1]) or un[un.size() - 1] == last, "the newest gift is offered (%s)" % str(ch))
			if un.size() > 3:
				_expect(not ch.has(last) or last == "", "not the last gift again when there are others (%s after %s)" % [str(ch), last])
	_expect(Deep.unlocked(Deep.TREASURES.size()).size() == Deep.GIFTS.size(), "every gift opens")
	for gd in Deep.GIFTS:
		_expect(StoryCard.has_picture(String(gd.pic)), "gift %s has a picture" % gd.id)
		_expect(String(gd.name).length() <= 14 and String(gd.line).length() <= 28, "gift %s: short name and line" % gd.id)
		_expect(int(gd.unlock) <= 4, "gift %s opens within 12 waves" % gd.id)
	for id in Deep.unlocked(Deep.TREASURES.size()):
		_expect(Deep.goblin_speed(id) <= 1.0 and Deep.reach(id) >= 1.0 and Deep.flames(id) >= 1.0, "gift %s only helps" % id)
	_expect(Deep.goblin_speed("sleepy") < 1.0 and Deep.reach("bighands") > 1.0 and Deep.flames("bigfire") > 1.0, "the gifts really do something")
	for i in Deep.HELPERS:
		var hp := Deep.helper_spot(i)
		_expect(Vector2(hp.x, hp.z).length() > W.FIRE_R + 0.5 and W.push_out(hp, 0.3).distance_to(hp) < 0.001, "helper %d stands by the fire on open ground" % i)
	# Seasons.
	for s in Deep.SEASONS:
		var sd := Deep.season_data(s)
		_expect(StoryCard.has_picture(String(sd.pic)) and String(sd.line).length() <= 28, "season %s: picture and line" % s)
		_expect((sd.weights as Array).size() == Deep.KINDS.size() and float(sd.weights[0]) > 0.0 and float(sd.weights[1]) > 0.0, "season %s has both tricks" % s)
	for d in Seeded.dates(30):
		_expect(Deep.SEASONS.has(Seeded.season(d)), "%s has a season" % d)
	for kind in Deep.KINDS:
		_expect(StoryCard.has_picture(String(Deep.KIND_PICS[kind])) and Deep.KIND_NAMES.has(kind), "trick %s: picture and name" % kind)
	_expect(Contrast.score(Deep.GOO_COLOR, Deep.BARREL_COLOR) > 0.15, "goo and barrel tells look different")
	# Treasures.
	var prev := 0
	for c in 60:
		var n := Deep.treasures(c)
		_expect(n >= prev, "treasures only grow")
		prev = n
	_expect(Deep.treasures(999) == Deep.TREASURES.size(), "the treasures finish")
	for i in Deep.TREASURES.size():
		var p := Deep.treasure_slot(i)
		var r := Vector2(p.x, p.z).length()
		_expect(r > W.R and r < W.EDGE, "treasure %d sits on the rim" % i)
		_expect(StoryCard.has_picture(Deep.TREASURES[i]), "treasure %s has a picture" % Deep.TREASURES[i])
		for j in RaidGen.LANTERNS_MAX:
			_expect(p.distance_to(RaidGen.lantern_slot(j)) > 1.4, "treasure %d clear of lantern %d" % [i, j])
		for j in RaidGen.GIFT_KEEP:
			_expect(p.distance_to(RaidGen.gift_slot(j)) > 1.8, "treasure %d clear of gift %d" % [i, j])
		for j in i:
			_expect(p.distance_to(Deep.treasure_slot(j)) > 1.4, "treasures %d and %d apart" % [i, j])
	_expect(Deep.treasure_slot(Deep.TREASURES.size()) == Vector3.INF, "no treasure slot past the end")
	# The pick row.
	var eyes := Vector3(0.0, 0.45 * W.S, 0.95 * W.S)  # giant.gd HEAD_ABOVE_TABLE, SEAT_DIST
	var spots := Deep.row_spots(3)
	for i in spots.size():
		var sp: Vector3 = spots[i]
		var reach_m := sp.distance_to(eyes) / W.S
		_expect(reach_m > 0.3 and reach_m < 0.6, "orb %d is an arm's reach from the VR Giant's eyes (%.2f m)" % [i, reach_m])
		var ground := Vector3(sp.x, 0.0, sp.z)
		_expect(not W.in_water(sp.x, sp.z) and W.push_out(ground, Deep.KNIGHT_R + 0.3).distance_to(ground) < 0.001, "a knight can stand under orb %d" % i)
		_expect(sp.y - maxf(0.0, W.height(sp.x, sp.z)) > Deep.orb_r() + 1.0, "orb %d floats clear of the ground" % i)
		for j in i:
			var gap := Vector2(sp.x - spots[j].x, sp.z - spots[j].z).length()
			_expect(gap > 2.0 * Deep.orb_r() + 0.6, "orbs %d and %d apart" % [i, j])
			_expect(gap > 2.0 * maxf(Deep.FLAT_R, Deep.TV_R), "no hand or knight is under orbs %d and %d at once" % [i, j])
	var real_r := Deep.orb_r() / W.S
	_expect(real_r >= 0.04 and real_r <= 0.1, "orbs are a modest size in VR (%.0f cm)" % (real_r * 100.0))
	_expect(Deep.HAND_R / W.S < 0.03 and Deep.DWELL >= 0.3, "a VR hand has to reach in and stay")
	_expect(Deep.TV_DWELL > 2.0 * Deep.TV_R / Deep.KNIGHT_SPEED, "a knight running past under an orb never picks it")
	_expect(Deep.wait_for("mode", true) < Deep.wait_for("mode", false) and Deep.wait_for("gift", false) <= 20.0, "nobody to pick: the middle comes sooner")
	print("GIANTS DEEP: %s (%d fails, %d ms, worst wave %.1f ms)" % ["PASS" if fails == 0 else "FAIL", fails, Time.get_ticks_msec() - t0, worst_ms[0]])
	quit(1 if fails > 0 else 0)


## The night in a mode: every wave's plan passes RaidGen.check, its tricks are fair, and the slow kid's fire never
## runs low (RaidGen.check_night's ember sim).
static func night_problems(raid_seed: int, extra: int, solo: bool, mode: String, season: String) -> Array:
	var why: Array = []
	var e := RaidGen.MAX_EMBERS
	for n in range(1, RaidGen.NIGHT_WAVES + 1):
		var p := Deep.plan(raid_seed, n, extra, solo, mode)
		for w in RaidGen.check(p):
			why.append(w)
		var spec := {"mode": mode, "season": season, "send": Deep.send_secs(p)}
		for w in Deep.problems(Deep.tricks(raid_seed, n, spec), n, spec):
			why.append("wave %d tricks: %s" % [n, w])
		e -= int(RaidGen.kid_sim(p).lost)
		if e < RaidGen.NIGHT_MIN_EMBERS:
			why.append("the slow kid's fire is down to %d embers by wave %d" % [e, n])
		e = mini(e + 1, RaidGen.MAX_EMBERS)
	return why


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	if fails <= 40:
		print("SCRIPT ERROR: GIANTS DEEP: " + what)
