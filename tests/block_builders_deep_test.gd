extends SceneTree
## BLOCK BUILDERS second pass validator (no game, no window): games/block_builders/deep.gd.
##   godot-test --headless --path . -s res://tests/block_builders_deep_test.gd      (SEEDS=200 for more; GEN_QUICK=1 samples)
## Proves, over many sky courses (many adventures, every mode, every season):
##   - GENTLE <= BRAVE <= HARD: the mode table (deep.gd ordered()) AND what the courses really get (challenges a course,
##     spare planks in the tray, surprise warning seconds, wind, wobble sizes, dizzy seconds), and every moded course
##     passes CourseGen.check;
##   - the surprises are fair (deep.gd problems() for every spot on every course in every mode: bare island ground only -
##     never over a block, the start or the flag, never on the start island - told long enough for a small kid in its
##     middle to walk out onto safe ground), the same every time and unchanged over the network (pack);
##   - TODAY'S SKY over 400+ dates: the course fair (CourseGen.check), dressed in its date's season, its surprises fair
##     in every mode;
##   - Puff's gifts never break the proof: BIG BRICKS' free planks never land on a block the course needs, the start,
##     the flag, the friend or inside an island; the BLOCK BOX and the modes only ever add to the tray; STICKY BRICKS stop
##     every push; three different unlocked gifts are offered, the newest among them, not the last again when there
##     are others; every picture drawn; short names;
##   - the seasons: a picture, a short line, real themes, both surprises; every date has a season;
##   - Puff's town only grows, a building for every course, spots apart and away from the course; the season rocks too;
##   - the pick rows: the start orbs over the start island a runner can stand under (every course), apart, above heads,
##     names clear of nameplates; the flat orbs apart; the VR orbs an arm's reach in front of the builder, small, apart;
##   - the validator catches unfair surprises; constants match the game's; every key colour stands out (palette.gd);
##   - fast: a course's surprise spots are made and checked well under 100 ms.
## Prints "SCRIPT ERROR: ..." for each failure and "BLOCKS DEEP: PASS" / "FAIL".

const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/block_builders/deep.gd")
const CourseGen := preload("res://games/block_builders/coursegen.gd")
const Story := preload("res://games/block_builders/story.gd")
const Themes := preload("res://games/block_builders/themes.gd")
const Season := preload("res://games/block_builders/season.gd")
const Runner := preload("res://games/block_builders/runner.gd")
const Builder := preload("res://games/block_builders/builder.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const Seeded := preload("res://core/seeded.gd")
const TestTime := preload("res://tests/test_time.gd")

const ADVS: Array[int] = [0, 1, 2, 3, 5, 8, 12, 40]

var fails := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	for w in Deep.ordered():
		_fail("modes: " + str(w))
	for w in Contrast.check_game("block_builders"):
		_fail("contrast: " + str(w))
	_expect(Deep.RUN_SPEED < Runner.SPEED, "a small kid runs slower than runner.gd SPEED")
	_expect(is_equal_approx(Deep.S, Builder.S), "deep.gd's world scale matches builder.gd")
	_expect(Deep.MAX_ADV == Story.ADVENTURES - 1, "deep.gd MAX_ADV matches story.gd")
	var worst_ms := [0.0]
	var sums := {}
	for m in PickOrbs.MODE_IDS:
		sums[m] = {"challenges": 0, "spare": 0, "spots": 0, "warn": 0.0, "wind": 0.0, "wobble": 0.0, "dizzy": 0.0, "n": 0}
	var seasons: Array = Deep.SEASONS.keys()
	var res := Seeded.validate(func(s: int) -> Array:
			var all: Array = []
			for adv in ADVS:
				for m in PickOrbs.MODE_IDS:
					var lv := CourseGen.generate(Seeded.derive(s, "sky%d" % adv), Deep.mode_adv(adv, m), "SKY %d" % (adv + 1))
					lv["theme"] = Deep.season_theme(int(lv.get("seed", 0)), String(seasons[(s + adv) % 4]))
					all.append([m, lv])
			return all,
		func(all: Array) -> Array:
			var why: Array = []
			for item in all:
				var m: String = item[0]
				var lv: Dictionary = item[1]
				why.append_array(_course_problems(lv, m, worst_ms, sums))
			return why, Seeded.test_count(60), 3, [0, 1, 999999], "BB DEEP")
	fails += (res.failures as Array).size()
	# What the courses really get: GENTLE <= BRAVE <= HARD.
	var g: Dictionary = sums.gentle
	var b: Dictionary = sums.brave
	var h: Dictionary = sums.hard
	print("blocks deep: per mode %s" % str(sums))
	_expect(g.challenges <= b.challenges and b.challenges <= h.challenges, "courses grow gentle -> brave -> hard (%d %d %d)" % [g.challenges, b.challenges, h.challenges])
	_expect(g.challenges < h.challenges, "hard courses really are bigger than gentle ones")
	_expect(g.spare >= b.spare and b.spare >= h.spare and g.spare > h.spare, "spare planks most on gentle (%d %d %d)" % [g.spare, b.spare, h.spare])
	for k in ["wind", "wobble", "dizzy"]:
		_expect(float(g[k]) <= float(b[k]) and float(b[k]) <= float(h[k]), "%s gentle <= brave <= hard" % k)
	_expect(float(g.warn) / maxf(1, g.spots) >= float(h.warn) / maxf(1, h.spots), "gentle surprises are told longest")
	_expect(int(b.spots) > 0, "brave courses have surprise spots (%d)" % int(b.spots))
	# TODAY'S SKY: every date, every mode.
	var rs := Seeded.validate_days(func(date: String) -> Dictionary: return Story.daily_course(date),
		func(lv: Dictionary) -> Array:
			var why: Array = CourseGen.check(lv)
			if lv.has("fallback"):
				why.append("fell back to the small safe course")
			for m in PickOrbs.MODE_IDS:
				for e in Deep.spots(lv, m):
					for w in Deep.problems(lv, e, m):
						why.append("%s: %s" % [m, w])
			return why, 400, "TODAY'S SKY DEEP", ["2026-11-12", "2026-12-25", "2027-02-29"])
	fails += (rs.failures as Array).size()
	for d in ["2026-04-02", "2026-07-02", "2026-10-02", "2027-01-02"]:
		var lv := Story.daily_course(d)
		_expect((Deep.season_data(Seeded.season(d)).themes as Array).has(String(lv.theme)), "today's sky on %s wears its season (%s)" % [d, lv.theme])
	# The validator catches unfair surprises.
	var lv0 := _a_course_with_spots()
	var e0: Dictionary = Deep.spots(lv0, "brave")[0]
	var short := e0.duplicate()
	short.warn = 0.5
	_expect(not Deep.problems(lv0, short, "brave").is_empty(), "a surprise told too briefly is caught")
	var sol0: Array = lv0.solution
	var c0: Vector3i = sol0[sol0.size() - 1][1]
	var over := e0.duplicate()
	over.x = c0.x + 0.5
	over.y = float(c0.y) + 1.0
	_expect(not Deep.problems(lv0, over, "brave").is_empty(), "a surprise over a block is caught")
	var start_e := e0.duplicate()
	start_e.x = (lv0.start as Vector3).x
	start_e.y = (lv0.start as Vector3).y
	_expect(not Deep.problems(lv0, start_e, "brave").is_empty(), "a surprise on the start is caught")
	var big := e0.duplicate()
	big.w = 2.6
	big.kind = "wobble"
	_expect(not Deep.problems(lv0, big, "hard").is_empty(), "a wobble too big to walk out of is caught")
	# Gifts.
	for gd in Deep.GIFTS:
		_expect(StoryCard.has_picture(String(gd.pic)), "gift %s has a picture" % gd.id)
		_expect(String(gd.name).length() <= 14, "gift %s has a short name" % gd.id)
		_expect(String(gd.line).length() <= 22, "gift %s has a short line" % gd.id)
	for n in [0, 1, 2, 3, 4, 9]:
		for last in ["", "sticky", "box", "boots"]:
			for s in 20:
				var ch := Deep.gift_choices(n, last, s)
				var un := Deep.unlocked(n)
				_expect(ch.size() == 3, "three gifts")
				var seen := {}
				for id in ch:
					_expect(un.has(id) and not seen.has(id), "gift %s is unlocked and different (town %d)" % [id, n])
					seen[id] = true
				_expect(ch.has(un[un.size() - 1]) or un[un.size() - 1] == last, "the newest gift is offered (town %d)" % n)
				if un.size() > 3 and last != "":
					_expect(not ch.has(last), "not the last gift again (town %d, %s)" % [n, last])
				_expect(var_to_str(ch) == var_to_str(Deep.gift_choices(n, last, s)), "gift choices are the same every time")
	_expect(Deep.unlocked(99).size() == Deep.GIFTS.size(), "every gift opens")
	_expect(Deep.jump_scale("boots") > 1.0 and Deep.jump_scale("") == 1.0, "jumpy boots jump higher")
	_expect(Deep.sticky("sticky") and not Deep.sticky("big"), "sticky bricks stop pushes")
	# Seasons.
	for s in Deep.SEASONS:
		var sd: Dictionary = Deep.SEASONS[s]
		_expect(StoryCard.has_picture(String(sd.pic)), "season %s has a picture" % s)
		_expect(String(sd.line).length() <= 22 and String(sd.name).length() <= 14, "season %s has a short line and name" % s)
		for th in sd.themes:
			_expect(Themes.THEMES.has(th), "season %s theme %s exists" % [s, th])
		_expect(float(sd.weights[0]) > 0.0 and float(sd.weights[1]) > 0.0, "season %s has both surprises" % s)
	for mth in 12:
		_expect(Deep.SEASONS.has(Seeded.season("2026-%02d-15" % (mth + 1))), "month %d has a season" % (mth + 1))
	for k in Deep.KINDS:
		_expect(StoryCard.has_picture(String(Deep.KIND_PICS[k])) and String(Deep.KIND_NAMES[k]).length() <= 10, "surprise %s has a picture and a short name" % k)
	_expect(Contrast.score(Deep.WIND_COLOR, Deep.WOBBLE_COLOR) > 0.2, "wind and wobble tells have distinct colours")
	# Puff's town.
	var kinds := {}
	for n in 40:
		var kd := Deep.town_kind(n)
		_expect(Deep.TOWN_KINDS.has(kd), "building %d is a known kind (%s)" % [n, kd])
		kinds[kd] = true
	for kd in Deep.TOWN_KINDS:
		_expect(kinds.has(kd), "every kind of building comes (%s)" % kd)
		_expect(StoryCard.has_picture(kd), "building %s has a picture" % kd)
	_expect(Deep.town_kind(9) == "castle", "a castle every tenth")
	for i in Deep.TOWN_SHOWN:
		var p := Deep.town_spot(i)
		_expect(p.y < -9.0 and absf(p.x) < 13.0, "building %d stands behind the course (%s)" % [i, str(p)])
		for j in range(i + 1, Deep.TOWN_SHOWN):
			_expect(p.distance_to(Deep.town_spot(j)) >= Deep.TOWN_GAP - 0.01, "buildings %d and %d have room" % [i, j])
	for i in Season.SPOTS.size():
		var sp: Vector3 = Season.SPOTS[i]
		_expect(sp.z < -8.5, "season rock %d floats behind the course and the friend's island" % i)
		_expect(sp.z > Deep.town_spot(0).y + 2.0, "season rock %d floats in front of the town" % i)
	# The pick rows.
	for s in Seeded.test_count(120, 40):
		var lv := CourseGen.generate(s * 31 + 7, s % 14)
		var row := Deep.row_spots(lv)
		var isl: Array = Deep.main_islands(lv)[0]
		for i in row.size():
			var sp: Vector3 = row[i]
			_expect(sp.x - Deep.TV_R > float(isl[0]) and sp.x + Deep.TV_R < float(isl[1]) and sp.z - Deep.TV_R > float(isl[2])
				and sp.z + Deep.TV_R < float(isl[3]), "start orb %d floats over the start island (seed %d)" % [i, s])
			_expect(Deep.under(row, Vector3(sp.x, 0.0, sp.z)) == i, "a runner can stand under start orb %d" % i)
			for k in 6:  # (runner.gd start_spot: where runners stand when the orbs pop up)
				var st: Vector3 = lv.start + Vector3((k % 3 - 1) * 0.7, 0.0, (k / 3) * 0.7 - 0.35)
				_expect(Deep.under(row, st) < 0, "runner %d doesn't start under an orb" % (k + 1))
			_expect(sp.y - PickOrbs.BALL_R * Deep.ORB_SCALE - (lv.start as Vector3).y > 1.6, "start orb %d floats above heads and nameplates" % i)
			for j in range(i + 1, row.size()):
				var q: Vector3 = row[j]
				_expect(Vector2(sp.x, sp.z).distance_to(Vector2(q.x, q.z)) > Deep.TV_R * 2.0 + 0.2, "start orbs %d and %d are apart" % [i, j])
	var fl := Deep.flat_spots()
	for i in fl.size():
		for j in range(i + 1, fl.size()):
			_expect((fl[i] as Vector3).distance_to(fl[j]) > Deep.TV_R * 2.0 + 0.5, "flat orbs %d and %d are apart" % [i, j])
	var head := Transform3D(Basis(), Vector3(0.0, 6.2, 6.8))
	var vr := Deep.vr_spots(head)
	var orb_m := PickOrbs.BALL_R * Deep.VR_SCALE
	for i in vr.size():
		var d: float = (vr[i] as Vector3).distance_to(head.origin) / Deep.S
		_expect(d > 0.3 and d < 0.62, "VR orb %d is an arm's reach away (%.2f m)" % [i, d])
		_expect((vr[i] as Vector3).z < head.origin.z, "VR orb %d is in front of the builder" % i)
		for j in range(i + 1, vr.size()):
			_expect((vr[i] as Vector3).distance_to(vr[j]) / Deep.S > 2.0 * (orb_m + Deep.HAND_R), "VR orbs %d and %d are apart" % [i, j])
	_expect((vr[0] as Vector3).x < (vr[2] as Vector3).x, "GENTLE is on the VR builder's left")
	_expect(orb_m > 0.05 and orb_m < 0.12, "VR orbs are a modest size (%.2f m)" % orb_m)
	_expect(Deep.DWELL >= 0.3 and Deep.TV_DWELL >= 0.8, "picks need a deliberate touch")
	_expect(worst_ms[0] < 100.0, "a course's surprise spots are made and checked fast (%.1f ms)" % worst_ms[0])
	for why in StoryCard.check():
		_fail(why)
	print("blocks deep: worst %.2f ms, %d ms in all" % [worst_ms[0], Time.get_ticks_msec() - t0])
	print("BLOCKS DEEP: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)


## Everything about one moded course: fair, its surprise spots fair, BIG BRICKS safe; adds to the per-mode sums.
func _course_problems(lv: Dictionary, m: String, worst_ms: Array, sums: Dictionary) -> Array:
	var why: Array = []
	for w in CourseGen.check(lv):
		why.append("%s %s: %s" % [m, lv.get("name", "?"), w])
	var t1 := Time.get_ticks_usec()
	var list := Deep.spots(lv, m)
	for e in list:
		for w in Deep.problems(lv, e, m):
			why.append("%s %s: %s" % [m, lv.get("name", "?"), w])
	worst_ms[0] = TestTime.worst(worst_ms[0], (Time.get_ticks_usec() - t1) / 1000.0, func() -> Variant:
		var l2 := Deep.spots(lv, m)
		for e in l2:
			Deep.problems(lv, e, m)
		return l2)
	if var_to_str(list) != var_to_str(Deep.spots(lv, m)):
		why.append("%s: surprise spots not deterministic" % m)
	for e in list:
		if var_to_str(Deep.unpack(Deep.pack(e))) != var_to_str(e):
			why.append("a surprise changes over the network: %s" % str(e))
	# BIG BRICKS: the free plank never takes a cell the course needs, the start, the flag or the friend.
	var cells := {}
	for s in lv.solution:
		cells[s[1]] = true
	for s in lv.solution:
		var x := Deep.big_extra(lv, String(s[0]), s[1])
		if x != Deep.NO_CELL and cells.has(x):
			why.append("a big brick lands on a needed block %s" % str(x))
	# The tray only ever grows with the mode and the gifts.
	for gid in ["", "box", "big", "sticky", "robot", "boots"]:
		var tr := Deep.tray(lv.budget, m, gid)
		for k in lv.budget:
			if int(tr.get(k, 0)) < int(lv.budget[k]):
				why.append("the tray shrinks (%s, %s)" % [m, gid])
	var md := Deep.mode_data(m)
	var sm: Dictionary = sums[m]
	sm.challenges = int(sm.challenges) + (lv.get("challenges", []) as Array).size()
	sm.spare = int(sm.spare) + int(Deep.tray(lv.budget, m, "").get("plank", 0)) - int(lv.budget.get("plank", 0))
	sm.spots = int(sm.spots) + list.size()
	for e in list:
		sm.warn = float(sm.warn) + float(e.warn)
	sm.wind = float(md.wind)
	sm.wobble = float(md.wobble_r)
	sm.dizzy = float(md.dizzy)
	sm.n = int(sm.n) + 1
	if not (Deep.SEASONS.values().any(func(sd: Dictionary) -> bool: return (sd.themes as Array).has(String(lv.theme)))):
		why.append("theme %s is in no season" % lv.theme)
	return why


func _a_course_with_spots() -> Dictionary:
	for s in 200:
		var lv := CourseGen.generate(s, 4)
		if not Deep.spots(lv, "brave").is_empty():
			return lv
	_fail("no course with surprise spots")
	return CourseGen.generate(1, 4)


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: %s" % what)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)
