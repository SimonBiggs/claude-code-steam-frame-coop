extends SceneTree
## SNOWMAN MAKER second pass validator (no game, no window): games/snowman_maker/deep.gd.
##   godot-test --headless --path . -s res://tests/snowman_maker_deep_test.gd      (SEEDS=200 for more; GEN_QUICK=1 samples)
## Proves, for every mode and season over many gardens of every chapter (days 2-4, short bot days, TODAY'S GARDEN over
## 400+ dates):
##   - the surprises are fair (deep.gd problems(): none on a session's first day or a day's first seconds, never two at
##     once, never in the day's last seconds, told long enough for a small child in the middle to get out, never on the
##     build circle, a box, the visitor, the sign or the VR builder, a sunbeam always leaves enough snowball spots in the
##     shade and never melts a whole snowball, a slide never through a pine, surprises going under half the day, and a
##     lone builder keeping clear of every surprise still earns the day's first star), the same every time and
##     unchanged over the network;
##   - GENTLE <= BRAVE <= HARD: the mode table (deep.gd ordered()) AND what the days really get (surprises a day,
##     warning seconds, sunbeam size, melt, slide width, the first star's goal);
##   - Tumble's gifts: three different unlocked ones, the newest among them, not the last again when there are others,
##     every picture drawn, short names; every gift opens within a few days of play; each really does its thing;
##   - the seasons: each has its weights, a picture, a line; winter is real snow and the rest a snow globe; summer has
##     the most sunbeams, winter the most slides; every date has a garden;
##   - the pick row: an arm's reach from the VR builder, apart, one roller never under two orbs; with no VR builder in
##     the build circle (always clear of pines, boxes and the visitor);
##   - Tumble's snow town only grows, finishes, and stands outside the garden, inside the globe, clear of the village
##     places and the season props;
##   - every key colour stands out (core/contrast.gd, games/snowman_maker/palette.gd);
##   - fast: a day's surprises are planned and checked well under 100 ms (a Deck plans one between days).
## Prints "SCRIPT ERROR: ..." for each failure and "SNOWMAN DEEP: PASS" / "FAIL".

const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/snowman_maker/deep.gd")
const G := preload("res://games/snowman_maker/gardengen.gd")
const Story := preload("res://games/snowman_maker/story.gd")
const Village := preload("res://games/snowman_maker/village.gd")
const Main := preload("res://games/snowman_maker/main.gd")
const SeasonScript := preload("res://games/snowman_maker/season.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const Seeded := preload("res://core/seeded.gd")
const TestTime := preload("res://tests/test_time.gd")

const SECS := 150.0  # a real snow day (main.gd round_time)

var fails := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var seeds := Seeded.test_count(24, 8)
	for w in Deep.ordered():
		_fail("modes: " + str(w))
	for w in Contrast.check_game("snowman_maker"):
		_fail("contrast: " + str(w))
	_expect(is_equal_approx(Deep.SPEED, Main.SPEED) and is_equal_approx(Deep.BALL_MIN, Main.BALL_MIN) and is_equal_approx(Deep.GROW, Main.GROW)
		and G.VR_START == Main.VR_START and G.SIGN_POS == Main.SIGN_POS and is_equal_approx(G.YARD_R, Main.YARD_R)
		and is_equal_approx(G.ARENA, Main.ARENA), "deep.gd / gardengen.gd numbers match main.gd")
	var per := {}
	var checked := 0
	var worst_ms := 0.0
	for mode in PickOrbs.MODE_IDS:
		var sum := {"days": 0, "hz": 0, "sun": 0, "slide": 0, "warn": 0.0, "sun_r": 0.0, "slide_w": 0.0, "goal": 0.0, "melt": 0.0}
		var by_season := {}
		for season in Deep.SEASONS:
			var kinds := {"sun": 0, "slide": 0}
			for s in seeds:
				var chap := s % Story.CHAPTERS.size()
				var g := G.garden(4100 + s * 7919, chap)
				for round_n in [2, 3, 4]:
					var goals := Deep.goals(1, chap, 0, 0, SECS, mode)
					var spec := {"mode": mode, "season": season, "round": round_n}
					var t1 := Time.get_ticks_usec()
					var list := Deep.hazards(g, SECS, spec)
					var why := Deep.problems(g, SECS, list, spec, goals)
					worst_ms = TestTime.worst(worst_ms, (Time.get_ticks_usec() - t1) / 1000.0, func() -> Variant:
						return Deep.problems(g, SECS, Deep.hazards(g, SECS, spec), spec, goals))
					checked += 1
					var tag := "%s %s seed %d ch%d day %d" % [mode, season, s, chap, round_n]
					for x in why:
						_fail("%s: %s" % [tag, x])
					if s % 4 == 0 and str(Deep.hazards(g, SECS, spec)) != str(list):
						_fail("%s: surprises differ for the same garden" % tag)
					for e in list:
						if str(Deep.unpack(Deep.pack(e))) != str(_rounded(e)):
							_fail("%s: a surprise changes over the network" % tag)
						kinds[String(e.kind)] += 1
						sum.hz += 1
						sum.warn += float(e.warn)
						if String(e.kind) == "sun":
							sum.sun += 1
							sum.sun_r += float(e.r)
						else:
							sum.slide += 1
							sum.slide_w += float(e.r)
					sum.days += 1
					sum.goal += float(goals[0])
					sum.melt += float(Deep.mode_data(mode).melt)
				# Bots: short days with surprises from 3 s on the first day: still fair.
				var bspec := {"mode": mode, "season": season, "round": Deep.FIRST_ROUND, "first": Deep.SHORT_FIRST}
				var bl := Deep.hazards(g, 26.0, bspec)
				for x in Deep.problems(g, 26.0, bl, bspec):  # (no star check: a 26 s bot day is too short for one)
					_fail("%s %s seed %d (bot day): %s" % [mode, season, s, x])
				if s < 4 and bl.is_empty():
					_fail("%s %s seed %d: a bot day has no surprise to test" % [mode, season, s])
			by_season[season] = kinds
		var r := maxf(1.0, sum.days)
		per[mode] = {"hz": sum.hz / r, "warn": sum.warn / maxf(1.0, sum.hz), "sun_r": sum.sun_r / maxf(1.0, sum.sun),
			"slide_w": sum.slide_w / maxf(1.0, sum.slide), "goal": sum.goal / r, "melt": sum.melt / r}
		print("SNOWMAN DEEP %s: %.1f surprises a day, told %.1f s, sunbeams r %.1f, slides %.1f m wide, first star %.1f (%d sunbeams, %d slides)" % [
			mode, per[mode].hz, per[mode].warn, per[mode].sun_r, per[mode].slide_w * 2.0, per[mode].goal, sum.sun, sum.slide])
		if sum.sun == 0 or sum.slide == 0:
			_fail("%s: never a sunbeam or never a slide" % mode)
		_expect(int(by_season.summer.sun) > int(by_season.winter.sun) and int(by_season.winter.slide) > int(by_season.summer.slide),
			"%s: summer has more sunbeams, winter more slides (%s)" % [mode, str(by_season)])
		for season in by_season:
			_expect(int(by_season[season].sun) > 0 and int(by_season[season].slide) > 0, "%s %s: both surprises happen" % [mode, season])
	var g0: Dictionary = per.gentle
	var b0: Dictionary = per.brave
	var h0: Dictionary = per.hard
	for k in ["hz", "sun_r", "slide_w", "goal", "melt"]:
		if not (float(g0[k]) <= float(b0[k]) + 0.001 and float(b0[k]) <= float(h0[k]) + 0.001):
			_fail("real days: %s not gentle <= brave <= hard (%.2f %.2f %.2f)" % [k, g0[k], b0[k], h0[k]])
	if not (float(g0.warn) >= float(b0.warn) and float(b0.warn) >= float(h0.warn)):
		_fail("real days: warnings not longest on gentle")
	_expect(float(g0.hz) >= 1.5, "gentle days still have surprises (%.1f)" % float(g0.hz))
	_expect(Deep.hazards(G.garden(77, 1), SECS, {"mode": "hard", "round": 1}).is_empty(), "no surprises on a session's first day")
	_goals()
	_daily()
	_gifts()
	_seasons()
	_row()
	_town()
	print("SNOWMAN DEEP: %d days checked, %.1f ms worst, %d ms total" % [checked, worst_ms, Time.get_ticks_msec() - t0])
	if worst_ms > 100.0:
		_fail("a day's surprises took %.0f ms to plan and check (a Deck must stay well under 100 ms)" % worst_ms)
	print("SNOWMAN DEEP: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func _rounded(e: Dictionary) -> Dictionary:
	return {"kind": String(e.kind), "x": float(e.x), "z": float(e.z), "dx": float(e.dx), "dz": float(e.dz),
		"warn": float(e.warn), "r": float(e.r), "t": float(e.t)}


## Mode goals: still 1 < 2 < 3 stars, never 0, gentle <= brave <= hard for every team and chapter.
func _goals() -> void:
	for b in range(1, 7):
		for chap in Story.CHAPTERS.size():
			for misses in [0, 3]:
				var gs := {}
				for mode in PickOrbs.MODE_IDS:
					var gl := Deep.goals(b, chap, misses, 0, SECS, mode)
					gs[mode] = gl
					if int(gl[0]) < 1 or not (int(gl[0]) < int(gl[1]) and int(gl[1]) < int(gl[2])):
						_fail("goals %s (%d builders, ch%d): %s" % [mode, b, chap, str(gl)])
					# A careful team with no surprises reaches the first star (bigger teams build faster).
					if Deep.can_make(b, SECS, [], mode) < float(gl[0]):
						_fail("goals %s: %d builders can't reach the first star in ch%d (%s)" % [mode, b, chap, str(gl)])
				for i in 3:
					if not (int(gs.gentle[i]) <= int(gs.brave[i]) and int(gs.brave[i]) <= int(gs.hard[i])):
						_fail("goals not gentle <= brave <= hard (%d builders, ch%d): %s" % [b, chap, str(gs)])


## TODAY'S GARDEN over 400+ dates: its surprises (in any mode, as a later day) are fair and the first star stays winnable
## for a lone builder and for a team.
func _daily() -> void:
	var rs := Seeded.validate_days(func(date: String) -> Dictionary:
			var nx := Story.next_round({"chapter": 2, "daily": {}}, Seeded.daily_key(date))
			var g := G.garden(Seeded.daily_seed("snowman_maker", date), int(nx[1]))
			var lists := {}
			for mode in PickOrbs.MODE_IDS:
				lists[mode] = Deep.hazards(g, SECS, {"mode": mode, "season": Seeded.season(date), "round": Deep.FIRST_ROUND})
			return {"g": g, "lists": lists, "season": Seeded.season(date), "chap": int(nx[1])},
		func(d: Dictionary) -> Array:
			var why: Array = []
			for mode in d.lists:
				var spec := {"mode": mode, "season": d.season, "round": Deep.FIRST_ROUND}
				for x in Deep.problems(d.g, SECS, d.lists[mode], spec, Deep.goals(1, int(d.chap), 0, 0, SECS, mode)):
					why.append("%s: %s" % [mode, x])
				for b in [2, 4, 6]:
					var gl := Deep.goals(b, int(d.chap), 0, 0, SECS, mode)
					if Deep.can_make(b, SECS, d.lists[mode], mode) < float(gl[0]):
						why.append("%s: %d builders can't reach the first star" % [mode, b])
			if not Deep.SEASONS.has(String(d.season)):
				why.append("no garden for %s" % d.season)
			return why, 400, "TODAY'S GARDEN SURPRISES", ["2026-11-12", "2026-12-25", "2027-07-01"])
	fails += (rs.failures as Array).size()
	print("SNOWMAN DEEP: %d days of TODAY'S GARDEN checked" % int(rs.checked))


func _gifts() -> void:
	var ids: Array = []
	for gd in Deep.GIFTS:
		ids.append(String(gd.id))
		if not StoryCard.has_picture(String(gd.pic)):
			_fail("gift %s: no picture %s" % [gd.id, gd.pic])
		if String(gd.name).length() > 16 or String(gd.line).length() > 22:
			_fail("gift %s: name or line too long" % gd.id)
		if int(gd.unlock) > Deep.TOWN.size():
			_fail("gift %s never opens" % gd.id)
		if int(gd.unlock) * Deep.TOWN_EVERY > 30:  # snowmen: a handful a day
			_fail("gift %s takes too long to open" % gd.id)
	_expect(Deep.grow_share("scarf") > 1.4 and Deep.grow_share("") == 1.0, "COSY SCARF grows snowballs faster")
	_expect(not Deep.melts("scarf") and Deep.melts(""), "COSY SCARF snowballs never melt")
	_expect(Deep.snowman_points(2, "buttons") == 4 and Deep.snowman_points(2, "") == 2, "SPARKLE BUTTONS doubles a snowman")
	_expect(Deep.speed_share("boots") > 1.2 and not Deep.bumps("boots") and Deep.bumps(""), "SNOW BOOTS run faster, no bumps")
	_expect(Deep.AUTO_SECS > 0.5 and Deep.AUTO_SECS < 3.0, "CARROT NOSE / MAGIC HAT pop on after a moment")
	for pieces in range(0, Deep.TOWN.size() + 1):
		var un := Deep.unlocked(pieces)
		for last in [""] + ids:
			for s in 6:
				var ch := Deep.gift_choices(pieces, String(last), 300 + s * 7)
				var tag := "gifts (town %d, last %s, seed %d)" % [pieces, last, s]
				if ch.size() != mini(3, un.size()):
					_fail("%s: %d choices" % [tag, ch.size()])
				var seen := {}
				for id in ch:
					if seen.has(id):
						_fail("%s: %s twice" % [tag, id])
					seen[id] = true
					if not un.has(id):
						_fail("%s: %s is still locked" % [tag, id])
				if not ch.has(un[un.size() - 1]) and un[un.size() - 1] != last:
					_fail("%s: the newest gift is missing" % tag)
				if un.size() > 3 and ch.has(last):
					_fail("%s: the last gift again" % tag)
				if str(ch) != str(Deep.gift_choices(pieces, String(last), 300 + s * 7)):
					_fail("%s: choices differ for the same seed" % tag)


func _seasons() -> void:
	for s in ["spring", "summer", "autumn", "winter"]:
		if not Deep.SEASONS.has(s):
			_fail("no %s" % s)
			continue
		var sd: Dictionary = Deep.SEASONS[s]
		for k in ["weights", "globe", "ground", "drift", "pic", "line"]:
			if not sd.has(k):
				_fail("season %s has no %s" % [s, k])
		if not StoryCard.has_picture(String(sd.pic)):
			_fail("season %s: no picture %s" % [s, sd.pic])
		if String(sd.line).length() > 22:
			_fail("season %s: line too long" % s)
		_expect(bool(sd.globe) == (s != "winter"), "%s: %s" % [s, "a snow globe out of season" if s != "winter" else "real snow in winter"])
	for date in ["2026-01-10", "2026-04-10", "2026-07-10", "2026-10-10"]:
		if not Deep.SEASONS.has(Seeded.season(date)):
			_fail("no garden for %s" % Seeded.season(date))
	for k in Deep.KIND_PICS:
		if not StoryCard.has_picture(String(Deep.KIND_PICS[k])):
			_fail("surprise %s: no picture" % k)
	for p in ["penguin", "gift", "snowglobe", "snowflake"]:
		if not StoryCard.has_picture(p):
			_fail("no picture %s" % p)
	# The globe holds the garden, the village and the town; its props stand outside it.
	_expect(SeasonScript.PROP_R > Deep.GLOBE_R + SeasonScript.STAND_W + 1.0, "the season props stand outside the globe's stand")
	_expect(Deep.GLOBE_R + SeasonScript.STAND_W >= G.ARENA + 16.0, "the globe's stand covers the garden snow's edge")
	for pl in Village.PLACES:
		var pp: Vector3 = pl[0]
		_expect(Vector2(pp.x, pp.z).length() < Deep.GLOBE_R - 2.5, "village place at %s inside the globe" % pp)


func _row() -> void:
	_row_for(true)
	_row_for(false)
	for st in ["mode", "gift"]:
		if Deep.wait_for(st, false) < 14.0 or Deep.wait_for(st, true) < 5.0:
			_fail("pick row: too little time to pick (%s)" % st)
	if Deep.DWELL < 0.15 or Deep.DWELL > 0.6:
		_fail("pick row: a glove must stay a moment, not long")
	if Deep.ORB_SCALE > 0.4:
		_fail("pick row: the orbs are too big to sit at an arm's reach")
	if Deep.FLAT_SCALE < 0.45:
		_fail("pick row: with no VR builder the orbs are too small to see on a Deck")


func _row_for(vr: bool) -> void:
	var orb := Deep.orb_r(vr)
	var tvr := Deep.tv_r(vr)
	var tag0 := "pick row (%s)" % ("VR builder" if vr else "no VR builder")
	var cases: Array = [[G.VR_START, Vector3.FORWARD]]
	if vr:  # wherever they stand, whichever way they look
		cases.append([Vector3(3.0, 0.0, -2.0), Vector3(1.0, 0.0, 0.3)])
		cases.append([Vector3(-5.0, 0.0, 4.0), Vector3(0.0, 0.0, 1.0)])
	for c in cases:
		var at: Vector3 = c[0]
		var spots := Deep.row_spots(3, vr, at, c[1])
		var head: Vector3 = at + Vector3(0.0, 1.4, 0.0)  # a standing or sitting builder's shoulders
		for i in spots.size():
			var p: Vector3 = spots[i]
			if vr:
				var reach := p.distance_to(head)
				if reach > 1.25 or reach < 0.55:
					_fail("%s: orb %d is %.2f m from the VR builder (an arm's reach, never in the face)" % [tag0, i, reach])
			else:
				if Vector2(p.x, p.z).length() + tvr > G.YARD_R:
					_fail("%s: orb %d is not inside the build circle" % [tag0, i])
				if p.y - orb < 1.0:
					_fail("%s: orb %d too low (a roller walks under it)" % [tag0, i])
			for j in i:
				var q: Vector3 = spots[j]
				if p.distance_to(q) < orb * 2.0 + 0.15:
					_fail("%s: orbs %d and %d touch" % [tag0, i, j])
				if Vector2(p.x - q.x, p.z - q.z).length() < tvr * 2.0:
					_fail("%s: one roller can be under orbs %d and %d" % [tag0, i, j])
	# The VR row from the start spot is clear of the sign and stays in the garden; rollers reach under it (the build
	# circle is always clear: gardengen.gd check()).
	for p in Deep.row_spots(3, true):
		if Vector2(p.x - G.SIGN_POS.x, p.z - G.SIGN_POS.z).length() < orb + 0.4:
			_fail("pick row: an orb in the sign")
		if Vector2(p.x, p.z).length() > G.YARD_R:
			_fail("pick row: an orb outside the build circle from the VR start (%s)" % p)


func _town() -> void:
	var prev := 0
	for made in 100:
		var c := Deep.town(made)
		if c < prev:
			_fail("the town shrinks at %d snowmen" % made)
		prev = c
	if Deep.town(Deep.TOWN_EVERY * Deep.TOWN.size()) != Deep.TOWN.size():
		_fail("the town never finishes")
	for k in Deep.TOWN_PICS:
		if not StoryCard.has_picture(String(Deep.TOWN_PICS[k])):
			_fail("town %s: no picture" % k)
	_expect(Deep.TOWN_PICS.size() == Deep.TOWN.size(), "every town piece has a picture")
	for i in Deep.TOWN.size():
		var p := Deep.town_spot(i)
		var fl := Vector2(p.x, p.z).length()
		if fl < G.ARENA + 2.0:
			_fail("town piece %d stands in the garden" % i)
		if fl > Deep.GLOBE_R - 2.5:
			_fail("town piece %d pokes out of the globe" % i)
		for pl in Village.PLACES:
			if p.distance_to(pl[0]) < 3.5:
				_fail("town piece %d stands on a village place" % i)
		for k in SeasonScript.PROPS:  # (winter's snowmen ring)
			var a := float(k) * TAU / SeasonScript.PROPS + 0.2
			if p.distance_to(Vector3(cos(a), 0.0, sin(a)) * SeasonScript.WINTER_R) < 2.0:
				_fail("town piece %d stands on a winter snowman" % i)
		for j in i:
			if p.distance_to(Deep.town_spot(j)) < 2.2:
				_fail("town pieces %d and %d overlap" % [i, j])


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_fail(msg)


func _fail(msg: String) -> void:
	fails += 1
	printerr("SCRIPT ERROR: " + msg)
