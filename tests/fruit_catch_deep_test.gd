extends SceneTree
## FRUIT CATCH second pass validator (no game, no window): games/fruit_catch/deep.gd.
##   godot-test --headless --path . -s res://tests/fruit_catch_deep_test.gd      (SEEDS=200 for more; GEN_QUICK=1 samples)
## Proves, for every mode and season over many harvests (rounds 2-4, short bot rounds, TODAY'S HARVEST over 400+ days):
##   - the surprises are fair (deep.gd problems(): none on a session's first round or a round's first seconds, never
##     two at once, never into the fruit storm, told long enough for a small child standing in the middle to walk out,
##     never over the bowl, the trunk, Nutmeg, the sign or the giant's spot, a windfall never lands where a good fruit
##     is falling, and a small child keeping clear of every surprise still finishes Nutmeg's first dish, with and
##     without a giant), the same every time and unchanged over the network;
##   - GENTLE <= BRAVE <= HARD: the mode table (deep.gd ordered()) AND what the rounds really get (surprises a round,
##     warning seconds, windfall size and apples, wasp band width, harvest level);
##   - Nutmeg's gifts: three different unlocked ones, the newest among them, not the last again when there are others,
##     every picture drawn, short names; every gift opens within a few days of play; SLOW FALL lands every fruit where
##     it would have fallen; BIG BASKET really catches further; GOLDEN DISH really doubles;
##   - the seasons: each has drifting things, a picture, a line and both surprises; every date has an orchard;
##   - the pick row: an arm's reach from the giant, one basket never under two orbs, every orb reachable by a TV player
##     (round the bowl, the trunk and Nutmeg's stump), clear of the sign and the bowl;
##   - Nutmeg's pantry only grows, finishes, and stands outside the park clear of the orchard and the season props;
##   - every key colour stands out (core/contrast.gd, games/fruit_catch/palette.gd);
##   - fast: a round's surprises are planned and checked well under 100 ms (a Deck plans one between rounds).
## Prints "SCRIPT ERROR: ..." for each failure and "FRUIT DEEP: PASS" / "FAIL".

const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/fruit_catch/deep.gd")
const G := preload("res://games/fruit_catch/harvestgen.gd")
const Art := preload("res://games/fruit_catch/art.gd")
const Main := preload("res://games/fruit_catch/main.gd")
const SeasonScript := preload("res://games/fruit_catch/season.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const Seeded := preload("res://core/seeded.gd")
const TestTime := preload("res://tests/test_time.gd")

var fails := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var seeds := Seeded.test_count(40, 10)
	for w in Deep.ordered():
		_fail("modes: " + str(w))
	for w in Contrast.check_game("fruit_catch"):
		_fail("contrast: " + str(w))
	_expect(Deep.NUTMEG_POS == Main.NUTMEG_POS and Deep.SIGN_POS == Main.SIGN_POS and Deep.VR_START == Main.VR_START
		and is_equal_approx(Deep.STUMP_R, Art.STUMP_R), "deep.gd's places match main.gd / art.gd")
	var per := {}
	var checked := 0
	var worst_ms := 0.0
	for mode in PickOrbs.MODE_IDS:
		var sum := {"rounds": 0, "hz": 0, "wf": 0, "wasp": 0, "level": 0.0, "wf_r": 0.0, "wf_n": 0.0, "wasp_w": 0.0, "warn": 0.0}
		var by_season := {}
		for season in Deep.SEASONS:
			var kinds := {"windfall": 0, "wasp": 0}
			for s in seeds:
				for round_n in [2, 3, 4]:
					var lv := Deep.level(round_n, 0, mode)
					var h := G.harvest(G.round_seed(4100 + s * 7919, round_n), lv, false, G.ROUND_SECS)
					var spec := {"mode": mode, "season": season, "round": round_n}
					var t1 := Time.get_ticks_usec()
					var list := Deep.hazards(h, spec)
					var why := Deep.problems(h, list, spec)
					worst_ms = TestTime.worst(worst_ms, (Time.get_ticks_usec() - t1) / 1000.0, func() -> Variant:
						return Deep.problems(h, Deep.hazards(h, spec), spec))
					checked += 1
					var tag := "%s %s seed %d round %d" % [mode, season, s, round_n]
					for x in why:
						_fail("%s: %s" % [tag, x])
					if s % 4 == 0 and str(Deep.hazards(h, spec)) != str(list):
						_fail("%s: surprises differ for the same harvest" % tag)
					for e in list:
						if str(Deep.unpack(Deep.pack(e))) != str(_rounded(e)):
							_fail("%s: a surprise changes over the network" % tag)
						kinds[String(e.kind)] += 1
						sum.hz += 1
						sum.warn += float(e.warn)
						if String(e.kind) == "windfall":
							sum.wf += 1
							sum.wf_r += float(e.r)
							sum.wf_n += float(e.n)
						else:
							sum.wasp += 1
							sum.wasp_w += float(e.r)
					sum.rounds += 1
					sum.level += lv
				# Bots: short rounds with surprises from 3 s on round 1: still fair.
				var hb := G.harvest(5000 + s * 31, Deep.level(1, 0, mode), false, 16.0)
				var bspec := {"mode": mode, "season": season, "round": Deep.FIRST_ROUND, "first": Deep.SHORT_FIRST}
				var bl := Deep.hazards(hb, bspec)
				for x in Deep.problems(hb, bl, bspec):
					_fail("%s %s seed %d (bot round): %s" % [mode, season, s, x])
				if s < 4 and bl.is_empty():
					_fail("%s %s seed %d: a bot round has no surprise to test" % [mode, season, s])
			by_season[season] = kinds
		var r := maxf(1.0, sum.rounds)
		per[mode] = {"hz": sum.hz / r, "warn": sum.warn / maxf(1.0, sum.hz), "wf_r": sum.wf_r / maxf(1.0, sum.wf),
			"wf_n": sum.wf_n / maxf(1.0, sum.wf), "wasp_w": sum.wasp_w / maxf(1.0, sum.wasp), "level": sum.level / r}
		print("FRUIT DEEP %s: %.1f surprises a round, told %.1f s, windfalls r %.1f with %.0f apples, wasp bands %.1f m, level %.1f (%d windfalls, %d wasps)" % [
			mode, per[mode].hz, per[mode].warn, per[mode].wf_r, per[mode].wf_n, per[mode].wasp_w * 2.0, per[mode].level, sum.wf, sum.wasp])
		if sum.wf == 0 or sum.wasp == 0:
			_fail("%s: never a windfall or never a wasp" % mode)
		_expect(int(by_season.summer.wasp) > int(by_season.autumn.wasp) and int(by_season.autumn.windfall) > int(by_season.summer.windfall),
			"%s: summer has more wasps, autumn more windfalls (%s)" % [mode, str(by_season)])
		for season in by_season:
			_expect(int(by_season[season].windfall) > 0 and int(by_season[season].wasp) > 0, "%s %s: both surprises happen" % [mode, season])
	var g: Dictionary = per.gentle
	var b: Dictionary = per.brave
	var h2: Dictionary = per.hard
	for k in ["hz", "wf_r", "wf_n", "wasp_w", "level"]:
		if not (float(g[k]) <= float(b[k]) + 0.001 and float(b[k]) <= float(h2[k]) + 0.001):
			_fail("real rounds: %s not gentle <= brave <= hard (%.2f %.2f %.2f)" % [k, g[k], b[k], h2[k]])
	if not (float(g.warn) >= float(b.warn) and float(b.warn) >= float(h2.warn)):
		_fail("real rounds: warnings not longest on gentle")
	_expect(float(g.hz) >= 1.5, "gentle rounds still have surprises (%.1f)" % float(g.hz))
	_expect(Deep.hazards(G.harvest(77, 1), {"mode": "hard", "round": 1}).is_empty(), "no surprises on a session's first round")
	_daily()
	_gifts()
	_seasons()
	_row()
	_pantry()
	print("FRUIT DEEP: %d rounds checked, %.1f ms worst, %d ms total" % [checked, worst_ms, Time.get_ticks_msec() - t0])
	if worst_ms > 100.0:
		_fail("a round's surprises took %.0f ms to plan and check (a Deck must stay well under 100 ms)" % worst_ms)
	print("FRUIT DEEP: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


## pack() keeps every number (floats as they are): compare with the same dictionary.
func _rounded(e: Dictionary) -> Dictionary:
	return {"kind": String(e.kind), "x": float(e.x), "z": float(e.z), "dx": float(e.dx),
		"dz": float(e.dz), "warn": float(e.warn), "r": float(e.r), "n": int(e.n), "t": float(e.t)}


## TODAY'S HARVEST over 400+ days: if the day's harvest ever has surprises (a later round in a mode), they are fair.
func _daily() -> void:
	var rs := Seeded.validate_days(func(date: String) -> Dictionary:
			var h := G.harvest(G.daily_seed(date), G.DAILY_LEVEL, true, G.ROUND_SECS)
			var lists := {}
			for mode in PickOrbs.MODE_IDS:
				lists[mode] = Deep.hazards(h, {"mode": mode, "season": Seeded.season(date), "round": Deep.FIRST_ROUND})
			return {"h": h, "lists": lists, "season": Seeded.season(date)},
		func(d: Dictionary) -> Array:
			var why: Array = []
			for mode in d.lists:
				for x in Deep.problems(d.h, d.lists[mode], {"mode": mode, "season": d.season, "round": Deep.FIRST_ROUND}):
					why.append("%s: %s" % [mode, x])
			if not Deep.SEASONS.has(String(d.season)):
				why.append("no orchard for %s" % d.season)
			return why, 400, "TODAY'S HARVEST SURPRISES", ["2026-11-12", "2026-12-25"])
	fails += (rs.failures as Array).size()
	print("FRUIT DEEP: %d days of TODAY'S HARVEST checked" % int(rs.checked))


func _gifts() -> void:
	var ids: Array = []
	for gd in Deep.GIFTS:
		ids.append(String(gd.id))
		if not StoryCard.has_picture(String(gd.pic)):
			_fail("gift %s: no picture %s" % [gd.id, gd.pic])
		if String(gd.name).length() > 12 or String(gd.line).length() > 20:
			_fail("gift %s: name or line too long" % gd.id)
		if int(gd.unlock) > Deep.PANTRY.size():
			_fail("gift %s never opens" % gd.id)
		if int(gd.unlock) * Deep.PANTRY_EVERY > 15:  # dishes: two or three a round, a few rounds a day
			_fail("gift %s takes too long to open" % gd.id)
	_expect(Deep.catch_r("big") > Deep.catch_r("") * 1.4, "BIG BASKET catches clearly further")
	_expect(Deep.dish_bonus("golden") == Deep.dish_bonus("") * 2, "GOLDEN DISH doubles a dish")
	# SLOW FALL: a fruit falls slower but lands where it would have (main.gd's step: v.y -= g * share; wind * sqrt(share)).
	for w in [Vector2(0.8, 0.0), Vector2(-0.3, 0.6)]:
		var plain := _fall(w, "")
		var slow := _fall(w, "slow")
		_expect(slow[0].distance_to(plain[0]) < 0.08, "SLOW FALL lands where a plain fall does (%s vs %s)" % [slow[0], plain[0]])
		_expect(float(slow[1]) > float(plain[1]) * 1.2, "SLOW FALL really is slower (%.2f vs %.2f s)" % [slow[1], plain[1]])
	for pieces in range(0, Deep.PANTRY.size() + 1):
		var un := Deep.unlocked(pieces)
		for last in [""] + ids:
			for s in 6:
				var ch := Deep.gift_choices(pieces, String(last), 300 + s * 7)
				var tag := "gifts (pantry %d, last %s, seed %d)" % [pieces, last, s]
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


## Where a fruit dropped from DROP_HEIGHT reaches basket height, and how long it takes ([Vector2, secs]).
func _fall(w: Vector2, gift_id: String) -> Array:
	var p := Vector3(0.0, G.DROP_HEIGHT, 0.0)
	var v := Vector3.ZERO
	var t := 0.0
	var dt := 1.0 / 120.0
	while p.y > G.CATCH_Y and t < 10.0:
		v.y = maxf(v.y - G.FALL_G * Deep.fall_share(gift_id) * dt, -5.0)
		var ww := w * Deep.wind_share(gift_id)
		p += (v + Vector3(ww.x, 0.0, ww.y)) * dt
		t += dt
	return [Vector2(p.x, p.z), t]


func _seasons() -> void:
	for s in ["spring", "summer", "autumn", "winter"]:
		if not Deep.SEASONS.has(s):
			_fail("no %s" % s)
			continue
		var sd: Dictionary = Deep.SEASONS[s]
		for k in ["drift", "pic", "line", "weights"]:
			if not sd.has(k):
				_fail("season %s has no %s" % [s, k])
		if not StoryCard.has_picture(String(sd.pic)):
			_fail("season %s: no picture %s" % [s, sd.pic])
		if String(sd.line).length() > 20:
			_fail("season %s: line too long" % s)
	for date in ["2026-01-10", "2026-04-10", "2026-07-10", "2026-10-10"]:
		if not Deep.SEASONS.has(Seeded.season(date)):
			_fail("no orchard for %s" % Seeded.season(date))
	for k in Deep.KIND_PICS:
		if not StoryCard.has_picture(String(Deep.KIND_PICS[k])):
			_fail("surprise %s: no picture" % k)
	for p in ["squirrel", "gift", "pantry", "snowglobe"]:
		if not StoryCard.has_picture(p):
			_fail("no picture %s" % p)
	for p in SeasonScript.SPOTS:
		var q: Vector3 = p
		if Vector2(q.x, q.z).length() < G.ARENA + 0.6:
			_fail("a season prop stands in the park (%s)" % q)
		for i in G.ORCHARD_SLOTS:
			if q.distance_to(G.orchard_slot(i)) < 1.4:
				_fail("a season prop stands on orchard tree %d (%s)" % [i, q])


func _row() -> void:
	var spots := Deep.row_spots()
	var head := Deep.VR_START + Vector3(0.0, 1.4, 0.0)  # a standing or sitting giant's shoulders
	var orb := Deep.orb_r()
	for i in spots.size():
		var p: Vector3 = spots[i]
		var reach := p.distance_to(head)
		if reach > 1.25 or reach < 0.55:
			_fail("pick row: orb %d is %.2f m from the giant (an arm's reach, never in the face)" % [i, reach])
		for j in i:
			var q: Vector3 = spots[j]
			if p.distance_to(q) < orb * 2.0 + 0.15:
				_fail("pick row: orbs %d and %d touch" % [i, j])
			if Vector2(p.x - q.x, p.z - q.z).length() < Deep.TV_R * 2.0:
				_fail("pick row: one basket can be under orbs %d and %d" % [i, j])
		if Vector2(p.x - Deep.SIGN_POS.x, p.z - Deep.SIGN_POS.z).length() < orb + 0.3:
			_fail("pick row: orb %d in the sign" % i)
		if p.y - orb < Main.BOWL_TOP + 0.2:
			_fail("pick row: orb %d sits in the bowl's height" % i)
		# A TV player's basket gets under it (walking round the bowl, the trunk and the stump: main.gd _push_out).
		var ok := false
		for k in 64:
			var a := float(k) * TAU / 64.0
			for rr in [0.0, Deep.TV_R * 0.5, Deep.TV_R * 0.9]:
				var c: Vector2 = Vector2(p.x, p.z) + Vector2(cos(a), sin(a)) * rr
				if c.length() >= G.TRUNK_R + 0.35 and c.distance_to(Vector2(G.BOWL_POS.x, G.BOWL_POS.z)) >= G.BOWL_R + 0.35 \
						and c.distance_to(Vector2(Deep.NUTMEG_POS.x, Deep.NUTMEG_POS.z)) >= Deep.STUMP_R + 0.35:
					ok = true
		if not ok:
			_fail("pick row: no TV player can get under orb %d" % i)
	for st in ["mode", "gift"]:
		if Deep.wait_for(st, false) < 14.0 or Deep.wait_for(st, true) < 5.0:
			_fail("pick row: too little time to pick (%s)" % st)
	if Deep.DWELL < 0.15 or Deep.DWELL > 0.6:
		_fail("pick row: a glove must stay a moment, not long")
	if Deep.ORB_SCALE > 0.4:
		_fail("pick row: the orbs are too big to sit at an arm's reach")


func _pantry() -> void:
	var prev := 0
	for dishes in 60:
		var c := Deep.pantry(dishes)
		if c < prev:
			_fail("the pantry shrinks at %d dishes" % dishes)
		prev = c
	if Deep.pantry(Deep.PANTRY_EVERY * Deep.PANTRY.size()) != Deep.PANTRY.size():
		_fail("the pantry never finishes")
	for k in Deep.PANTRY_PICS:
		if not StoryCard.has_picture(String(Deep.PANTRY_PICS[k])):
			_fail("pantry %s: no picture" % k)
	_expect(Deep.PANTRY_PICS.size() == Deep.PANTRY.size(), "every pantry piece has a picture")
	for i in Deep.PANTRY.size():
		var p := Deep.pantry_spot(i)
		if Vector2(p.x, p.z).length() < G.ARENA + 0.8:
			_fail("pantry piece %d stands in the park" % i)
		for k in G.ORCHARD_SLOTS:
			if p.distance_to(G.orchard_slot(k)) < 1.6:
				_fail("pantry piece %d stands on orchard tree %d" % [i, k])
		for q in SeasonScript.SPOTS:
			if p.distance_to(q) < 1.5:
				_fail("pantry piece %d stands on a season prop" % i)
		for j in i:
			if p.distance_to(Deep.pantry_spot(j)) < 1.3:
				_fail("pantry pieces %d and %d overlap" % [i, j])


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_fail(msg)


func _fail(msg: String) -> void:
	fails += 1
	printerr("SCRIPT ERROR: " + msg)
