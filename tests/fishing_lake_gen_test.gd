extends SceneTree
## FISHING LAKE lakes: proves the seeded lakes are fair over many seeds (no game, no window).
##   godot-test --headless --path . -s res://tests/fishing_lake_gen_test.gd      (SEEDS=500 for more)
## For every level and wish: games/fishing_lake/lakegen.gd check() (every spot reachable by a cast from
## the jetty end and by the boats, spots apart, the wish catchable, every fish has its spot and its
## weather), the same seed gives the same lake, every fish in the book is catchable (each one on some
## lake, and a family fishing day after day fills the whole book in a few weeks), TODAY'S LAKE is the
## same all day, and generation stays fast (Deck: well under 100 ms for the whole quick check).

const LakeGen := preload("res://games/fishing_lake/lakegen.gd")
const Book := preload("res://games/fishing_lake/book.gd")
const Seeded := preload("res://core/seeded.gd")
const Tackle := preload("res://games/fishing_lake/tackle.gd")
const Seasons := preload("res://games/fishing_lake/seasons.gd")
const Lake := preload("res://games/fishing_lake/lake.gd")
const StoryCard := preload("res://core/story_card.gd")
const TestTime := preload("res://tests/test_time.gd")

var fails := 0


func _initialize() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 60
	var total := 0
	var gens := 0
	var t0 := Time.get_ticks_usec()
	var ever := {}
	for level in 4:
		var wishes: Array = [-1]
		for k in LakeGen.species():
			if LakeGen.unlocked(k, level):
				wishes.append(k)
		for w in wishes:
			var opts := {"level": level, "wish": w, "season": Seasons.SEASONS[(level + int(w) + 4) % 4]}
			var r := Seeded.validate(func(s: int) -> Dictionary: return LakeGen.generate(s, opts),
				func(l: Dictionary) -> Array: return _check_wish(l, int(w)), seeds / 4 + 3, 11 + level, [0, 999999], "LAKE l%d w%d" % [level, w])
			total += int(r.checked)
			gens += int(r.checked) * 2
			fails += (r.failures as Array).size()
		for s in seeds:
			for k in LakeGen.catchable(LakeGen.generate(300 + s, {"level": level})):
				ever[k] = true
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens)
	print("lake gen: %.3f ms per lake (%d lakes)" % [per_ms, gens])
	_expect(per_ms < 2.0, "a lake generates in under 2 ms here (%.3f ms)" % per_ms)
	for k in LakeGen.species():
		_expect(ever.has(k), "%s turns up on some lake by itself" % LakeGen.FishScript.TYPES[k].name)
	# The whole book: a family fishing one day after another (catching only Ollie's wish) fills it.
	var t1 := Time.get_ticks_usec()
	for world in 25:
		var book := {}
		var days := 0
		while Book.found(book).size() < LakeGen.species().size() and days < 40:
			var lvl := Book.level(days)
			var sd := Seeded.derive(world * 31 + 7, "day%d" % days)
			var lake: Dictionary
			if days % 5 == 2:  # some days are TODAY'S LAKE
				lake = LakeGen.generate(sd, {"level": lvl, "daily": true})
				lake.wish = Book.pick_daily_wish(book, lake)
			else:
				lake = LakeGen.generate(sd, {"level": lvl, "wish": Book.pick_wish(book, lvl, sd)})
			for w in LakeGen.check(lake):
				_fail("world %d day %d: %s" % [world, days, w])
			if int(lake.wish) >= 0:
				Book.add(book, int(lake.wish), 1.0)
			days += 1
		_expect(Book.found(book).size() == LakeGen.species().size(), "world %d: the book fills (%d pages in %d days)" % [world, Book.found(book).size(), days])
		_expect(days <= 18, "world %d: the book fills in %d days (want <= 18)" % [world, days])
	print("lake gen: 25 books filled in %.1f ms" % (float(Time.get_ticks_usec() - t1) / 1000.0))
	# A quick check fit for a Deck: 50 lakes with checks.
	var t2 := Time.get_ticks_usec()
	for s in 50:
		LakeGen.check(LakeGen.generate(s, {"level": 3}))
	var quick := float(Time.get_ticks_usec() - t2) / 1000.0
	print("lake gen: 50 lakes generated + checked in %.1f ms" % quick)
	_expect(quick < 50.0, "50 lakes in under 50 ms here (%.1f ms)" % quick)
	# TODAY'S LAKE.
	# Over 400+ days (Seeded.validate_days, the shared daily validator), as main.gd _new_lake() makes it: the day's
	# lake at every book level 0-3 with Ollie's daily wish for a new family (Book.pick_daily_wish), each fair with fair
	# lures (_check_wish: check() + Tackle.check_offer), the wish never changing the lake, the same all day.
	var days_seen := {}
	var rs := Seeded.validate_days(func(date: String) -> Dictionary:
			var sd := Seeded.daily_seed("fishing_lake", date)
			var out := {"lakes": []}
			for lvl in 4:
				var l := LakeGen.generate(sd, {"level": lvl, "daily": true, "season": Seeded.season(date)})
				l.wish = Book.pick_daily_wish({}, l)
				(out.lakes as Array).append(l)
			out["koi"] = LakeGen.generate(sd, {"level": 3, "daily": true, "wish": LakeGen.KOI, "season": Seeded.season(date)})
			out["pike"] = LakeGen.generate(sd, {"level": 3, "daily": true, "wish": LakeGen.PIKE, "season": Seeded.season(date)})
			return out,
		func(out: Dictionary) -> Array:
			var why: Array = []
			for i in (out.lakes as Array).size():
				for w in _check_wish(out.lakes[i], -1):
					why.append("level %d: %s" % [i, w])
			if var_to_str(out.koi.spots) != var_to_str(out.pike.spots) or out.koi.weather != out.pike.weather:
				why.append("the wish changes TODAY'S LAKE")
			days_seen[var_to_str(out.koi.spots)] = true
			return why, 400, "TODAY'S LAKE", ["2026-11-11", "2026-11-12"])
	total += int(rs.checked)
	fails += (rs.failures as Array).size()
	_expect(days_seen.size() >= int(rs.checked) - 10, "daily lakes differ (%d of %d)" % [days_seen.size(), int(rs.checked)])
	# Variety: all three weathers and all five spots turn up at level 3.
	var wx := {}
	var habs := {}
	for s in 60:
		var l := LakeGen.generate(s, {"level": 3})
		wx[l.weather] = true
		for sp in l.spots:
			habs[sp.hab] = true
	_expect(wx.size() == 3 and habs.size() == 5, "every weather and spot turns up (%s %s)" % [str(wx.keys()), str(habs.keys())])
	_expect(LakeGen.generate(5, {"level": 0}).weather == "sunny", "the first day is sunny")
	# THIRD PASS: seasons and flock visits. Every season's lakes are fair (check() includes the flocks), the
	# weather leans the season's way, flocks come from the second lake on and grow with the level, a mode's flocks
	# are the lake's first ones, and the shore garden's spots all stand on the bank.
	for sn in Seasons.SEASONS:
		var wxs := {}
		var nv := [0.0, 0.0, 0.0, 0.0]
		var n := 0
		for i in Seeded.test_count(80):
			n += 1
			for lvl in 4:
				var l := LakeGen.generate(i + 5000, {"level": lvl, "season": sn})
				for w in LakeGen.check(l):
					_fail("%s level %d seed %d: %s" % [sn, lvl, i, w])
				nv[lvl] += float((l.visits as Array).size()) / float(n)
		_expect(nv[0] == 0.0 and nv[1] >= 0.9 and nv[3] >= nv[1], "%s: flocks grow with the level (%s)" % [sn, str(nv)])
		var ww: Array = Seasons.WEATHER_W[sn]
		var lean_i := ww.find(ww.max())
		var lean: String = ["sunny", "rain", "evening"][lean_i]
		for i in 200:
			var lw := String(LakeGen.generate(20000 + i, {"level": 3, "season": sn}).weather)
			wxs[lw] = int(wxs.get(lw, 0)) + 1
		var share := float(wxs.get(lean, 0)) / 200.0
		_expect(share >= 0.7 * float(ww[lean_i]) / float(ww.reduce(func(a, b): return a + b, 0)), "%s leans %s (%s)" % [sn, lean, str(wxs)])
	var same_a := LakeGen.generate(77, {"level": 3, "season": "winter"})
	var same_b := LakeGen.generate(77, {"level": 3, "season": "winter"})
	_expect(var_to_str(same_a) == var_to_str(same_b), "the same seed and season give the same lake (flocks too)")
	var worst := 0.0
	for i in 40:
		var sd := 9000 + i
		var gen := func() -> void: LakeGen.check(LakeGen.generate(sd, {"level": 3, "season": "autumn"}))
		var t4 := Time.get_ticks_usec()
		gen.call()
		worst = TestTime.worst(worst, (Time.get_ticks_usec() - t4) / 1000.0, gen)
	_expect(worst < 20.0, "a seasonal lake + check in under 20 ms (worst %.2f ms)" % worst)
	var badv := LakeGen.generate(12, {"level": 3, "season": "spring"}).duplicate(true)
	if not (badv.visits as Array).is_empty():
		(badv.visits[0] as Dictionary).pos = LakeGen.JETTY_END + Vector3(0, 0, 1.0)
		_expect(not LakeGen.check(badv).is_empty(), "a flock on the jetty is caught")
	var badw := LakeGen.generate(13, {"level": 3, "season": "spring"}).duplicate(true)
	badw.visits = [{"at": 0.3, "pos": LakeGen.JETTY_END + Vector3(0, 0, -10), "r": Seasons.VISIT_R},
		{"at": 0.35, "pos": LakeGen.JETTY_END + Vector3(2, 0, -10), "r": Seasons.VISIT_R}]
	_expect(not LakeGen.check(badw).is_empty(), "two flocks at once are caught")
	_expect(not LakeGen.check(LakeGen.generate(14, {"level": 0, "season": "summer"}).merged({"visits": [{"at": 0.5, "pos": LakeGen.JETTY_END + Vector3(0, 0, -10), "r": 2.6}]}, true)).is_empty(), "flocks on a first lake are caught")
	for m in ["gentle", "brave", "hard"]:
		_expect(int(Tackle.num(m).visits) >= 1 and float(Tackle.num(m).visit_tell) >= 2.2, "%s: flocks told %.1f s ahead" % [m, float(Tackle.num(m).visit_tell)])
	var ks := Seasons.keepsake_spots()
	for w in Seasons.check_spots(ks):
		_fail("garden: " + w)
	_expect(ks.size() == Seasons.MAX_KEEPSAKES, "the shore garden has %d spots" % ks.size())
	_expect(not Seasons.check_spots([Lake.POND_C]).is_empty() and not Seasons.check_spots([Vector3(0, 0, 13), Vector3(0.5, 0, 13)]).is_empty(), "the garden check catches a keepsake in the pond or on the path")
	for sn in Seasons.SEASONS:
		_expect(Seasons.FLOCKS.has(sn) and Seasons.CARDS.has(sn) and Seasons.DRIFT.has(sn), "%s is dressed" % sn)
		_expect(StoryCard.has_picture(String(Seasons.CARDS[sn][1])) and StoryCard.has_picture(String(Seasons.FLOCKS[sn].pic)), "%s pictures exist" % sn)
	# Hand checks: the checker catches broken lakes.
	var g := LakeGen.generate(42, {"level": 3, "wish": LakeGen.KOI})
	var bad := g.duplicate(true)
	(bad.spots[0] as Dictionary).pos = Vector3(0, 0, 6.0)
	_expect(not LakeGen.check(bad).is_empty(), "a spot under the jetty is caught")
	var bad2 := g.duplicate(true)
	(bad2.spots[0] as Dictionary).pos = LakeGen.JETTY_END + Vector3(0, 0, -30.0)
	_expect(not LakeGen.check(bad2).is_empty(), "a spot out of casting reach is caught")
	var bad3 := g.duplicate(true)
	bad3.spots = (bad3.spots as Array).filter(func(s: Dictionary) -> bool: return s.hab != "lily")
	_expect(not LakeGen.check(bad3).is_empty(), "koi without lily pads is caught")
	var bad4 := g.duplicate(true)
	bad4.weather = "sunny"
	(bad4.mix as Dictionary)[LakeGen.MOONFISH] = 5
	_expect(not LakeGen.check(bad4).is_empty(), "moonfish in the sunshine is caught")
	# Tackle (second pass): modes rise in order with readable tells, Old Whiskers' pulls grow smoothly and no fight
	# drags on, every offered lure helps something, the lures change, and the curve over days has no cliffs.
	var t3 := Time.get_ticks_usec()
	for s in seeds:
		for w in Tackle.check_modes(s * 7 + 1):
			_fail("modes seed %d: %s" % [s, w])
	print("tackle: %d mode sets checked in %.1f ms (gentle %.0f s, brave %.0f s, hard %.0f s for Old Whiskers)" % [seeds,
		float(Time.get_ticks_usec() - t3) / 1000.0, Tackle.fight_secs(1, "gentle"), Tackle.fight_secs(1, "brave"), Tackle.fight_secs(1, "hard")])
	var offers := {}
	for s in 40:
		var l := LakeGen.generate(s, {"level": 3, "wish": LakeGen.EEL})
		offers[str(Tackle.offer(l))] = true
		_expect(Tackle.helps(String(Tackle.offer(l)[1]), LakeGen.EEL), "seed %d: the glow lure sits in the middle for an eel wish" % s)
	_expect(offers.size() >= 3, "the lure offers change (%d kinds)" % offers.size())
	var badm: Dictionary = LakeGen.generate(9, {"level": 0}).duplicate(true)
	_expect(not Tackle.check_offer(badm, ["worm", "glow", "goldfly"]).is_empty(), "lures before their level are caught")
	var badp := Tackle.boss_pulls(3, "brave")
	badp[4] = [0.5, 2.0, 1.0]
	_expect(not Tackle.check_pulls(badp, "brave").is_empty(), "an untold, jumpy pull is caught")
	_expect(Tackle.shiny_ok(LakeGen.TROUT) and not Tackle.shiny_ok(LakeGen.LEGEND) and not Tackle.shiny_ok(LakeGen.GOLDEN), "shiny fish: not the legend or the golden fish")
	_expect(Tackle.shiny_chance("goldfly") > Tackle.shiny_chance("worm"), "the gold fly finds more shiny fish")
	var prev_kinds := 0.0
	for level in 4:
		var kinds := 0.0
		for s in 40:
			kinds += float(LakeGen.catchable(LakeGen.generate(1000 + s, {"level": level})).size()) / 40.0
		_expect(kinds >= prev_kinds - 0.01 and (level == 0 or kinds - prev_kinds <= 3.0), "level %d: %.1f kinds of fish a day (was %.1f): a smooth rise" % [level, kinds, prev_kinds])
		prev_kinds = kinds
	var pl := 0
	for d in 20:
		var n := Book.pond_level(d)
		_expect(n >= pl and n - pl <= 1, "Ollie's pond grows one thing at a time (day %d)" % d)
		pl = n
	_expect(Book.pond_level(0) == 1 and Book.pond_level(30) == Book.POND.size(), "the pond starts with logs and grows it all")
	# Story.
	_expect(Book.pick_wish({}, 0, 1) in [LakeGen.MINNOW, LakeGen.PERCH, LakeGen.BLUEGILL], "the first wish is an easy fish")
	var wishes := {}
	for s in 30:
		wishes[Book.pick_wish({}, 3, s, LakeGen.MINNOW)] = true
	_expect(wishes.size() >= 2 and not wishes.has(LakeGen.MINNOW), "the wish changes from day to day (%s)" % str(wishes.keys()))
	var bk := {}
	_expect(Book.add(bk, LakeGen.TROUT, 1.2) and not Book.add(bk, LakeGen.TROUT, 2.0), "a new page once")
	_expect(is_equal_approx(float(bk["Rainbow Trout"][1]), 2.0), "the book keeps the best weight")
	_expect(Book.save_defaults().book.is_empty(), "a new book is empty")
	print("lake gen: %d lakes checked, %d failures" % [total, fails])
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	print("FISHING_LAKE_GEN: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)


func _check_wish(l: Dictionary, w: int) -> Array:
	var why := LakeGen.check(l)
	why.append_array(Tackle.check_offer(l, Tackle.offer(l)))  # today's lures: fair, unlocked, the wish's in the middle
	if w >= 0 and int(l.wish) != w:
		why.append("the wish %d was not kept" % w)
	return why


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: lake gen: " + what)
