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

var fails := 0


func _init() -> void:
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
			var opts := {"level": level, "wish": w}
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
	var days_seen := {}
	for d in 40:
		var date := Time.get_date_string_from_unix_time(1790000000 + d * 86400)
		var sd := Seeded.daily_seed("fishing_lake", date)
		var a := LakeGen.generate(sd, {"level": 3, "daily": true, "wish": LakeGen.KOI})
		var b := LakeGen.generate(sd, {"level": 3, "daily": true, "wish": LakeGen.PIKE})
		_expect(var_to_str(a.spots) == var_to_str(b.spots) and a.weather == b.weather, "daily %s: the wish never changes TODAY'S LAKE" % date)
		for w in LakeGen.check(a):
			_fail("daily %s: %s" % [date, w])
		days_seen[var_to_str(a.spots)] = true
	_expect(days_seen.size() >= 38, "daily lakes differ (%d of 40)" % days_seen.size())
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
	# Story.
	_expect(Book.pick_wish({}, 0, 1) in [LakeGen.MINNOW, LakeGen.PERCH], "the first wish is an easy fish")
	var bk := {}
	_expect(Book.add(bk, LakeGen.TROUT, 1.2) and not Book.add(bk, LakeGen.TROUT, 2.0), "a new page once")
	_expect(is_equal_approx(float(bk["Rainbow Trout"][1]), 2.0), "the book keeps the best weight")
	_expect(Book.save_defaults().book.is_empty(), "a new book is empty")
	print("lake gen: %d lakes checked, %d failures" % [total, fails])
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)


func _check_wish(l: Dictionary, w: int) -> Array:
	var why := LakeGen.check(l)
	if w >= 0 and int(l.wish) != w:
		why.append("the wish %d was not kept" % w)
	return why


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: lake gen: " + what)
