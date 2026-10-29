extends SceneTree
## COASTER CREW generator: proves Buttons' seeded coaster plans are always buildable and fair (no game, no window).
##   godot-test --headless --path . -s res://tests/roller_coaster_gen_test.gd      (SEEDS=500 for more)
## Checks, over many seeds: whole coasters built plan after plan from the practice track (every section passes
## games/roller_coaster/coastergen.gd check(): pieces fit on the table in order, no bumping into itself or the
## station roof, a fast drop, a short lap), the same seed gives the same plan, plans grow gently, TODAY'S COASTER
## is the same all day and differs between days, plans on messy hand-built tracks are fine or marked full (never
## broken), the stars are spread out and grabbable, the validator really catches bad plans, the numbers match
## main.gd / train.gd, Buttons' pictures exist, and generation stays fast. Prints "SCRIPT ERROR: ..." per failure.

const G := preload("res://games/roller_coaster/coastergen.gd")
const Track := preload("res://games/roller_coaster/track.gd")
const Main := preload("res://games/roller_coaster/main.gd")
const Train := preload("res://games/roller_coaster/train.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 60
	var t0 := Time.get_ticks_usec()
	var gens := 0
	# 1) Whole coasters: section after section from the practice track until the table is full.
	var sections_per_coaster := 0.0
	var sizes := {}
	var loops := 0
	var splashes := 0
	var res := Seeded.validate(func(s: int) -> Dictionary: return _coaster(s),
		func(c: Dictionary) -> Array: return c.problems, seeds, 3, [G.daily_seed("2026-10-29"), G.daily_seed("2026-12-25")], "COASTER")
	fails += (res.failures as Array).size()
	for k in seeds:
		var c := _coaster(k * 131 + 7)
		gens += int(c.sections) + 1  # (+ the last try that found the table full)
		sections_per_coaster += float(c.sections) / seeds
		for sz in c.sizes:
			sizes[sz] = int(sizes.get(sz, 0)) + 1
		loops += int(c.loops)
		splashes += int(c.splashes)
	print("sections per coaster: %.1f, plan sizes: %s, loops %d, splashes %d" % [sections_per_coaster, str(sizes), loops, splashes])
	_expect(sections_per_coaster >= 2.0, "a coaster has room for at least 2 plans (%.1f)" % sections_per_coaster)
	_expect(loops > seeds / 3 and splashes > seeds / 4, "loops and splashes turn up (%d, %d)" % [loops, splashes])
	# 2) Plans on messy hand-built tracks: fine, or marked full - never broken.
	var full := 0
	for k in seeds:
		var r := Seeded.rng(k, "messy")
		var base: Array = []
		for i in r.randi_range(0, 16):
			var e := Track.end_of(base)
			var t: String = Seeded.pick(r, Track.TYPES)
			if Track.fits(t, 0.0, e[0], e[1]):
				base.append([t, r.randf_range(-1.0, 2.0) if r.randf() < 0.3 else 0.0])
		var plan := G.section(k * 17 + 1, base, r.randi_range(1, 5))
		gens += 1
		if bool(plan.full):
			full += 1
			_expect((plan.pieces as Array).is_empty(), "a full plan has no pieces")
		for why in G.check(plan):
			_expect(false, "messy track %d: %s" % [k, why])
	print("plans on messy tracks marked full: %d of %d" % [full, seeds])
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens)
	print("plan gen: %.2f ms per section incl. check (%d sections)" % [per_ms, gens])
	_expect(per_ms < 40.0, "a section generates in under 40 ms here, busy machine (%.2f ms; once per ride, at the cheer)" % per_ms)
	# 3) Determinism and growth.
	var pb := G.practice_base()
	var one := G.section(4242, pb, 1)
	_expect(var_to_str(one) == var_to_str(G.section(4242, pb, 1)), "the same seed gives the same plan")
	var differ := 0
	for k in 10:
		if var_to_str(G.section(1000 + k, pb, 1).pieces) != var_to_str(one.pieces):
			differ += 1
	_expect(differ >= 8, "other seeds give other plans (%d of 10)" % differ)
	_expect(G.size_for(1) < G.size_for(3) and G.size_for(99) <= 7, "plans grow gently (%d, %d, %d)" % [G.size_for(1), G.size_for(3), G.size_for(99)])
	# 4) TODAY'S COASTER.
	_expect(G.daily_seed("2026-10-29") == G.daily_seed("2026-10-29"), "TODAY'S COASTER is the same all day")
	_expect(G.daily_seed("2026-10-29") != G.daily_seed("2026-10-30"), "a new TODAY'S COASTER each day")
	for date in ["2026-10-29", "2026-11-05", "2026-12-25", "2027-01-01"]:
		var d := G.section(G.daily_seed(date), pb, 1)
		_expect(not bool(d.full) and (d.pieces as Array).size() == G.size_for(1), "TODAY'S COASTER %s has a full plan" % date)
		for why in G.check(d):
			_expect(false, "TODAY'S COASTER %s: %s" % [date, why])
	# 5) Stars.
	for k in seeds:
		var c := _coaster(k * 7 + 3)
		var tr := Track.build(c.pieces)
		for ride in [1, 2, 5, 9]:
			var list := G.stars(k, ride, tr, false)
			for why in G.check_stars(list, tr, false):
				_expect(false, "stars seed %d ride %d: %s" % [k, ride, why])
		_expect(G.stars(k, 9, tr, false).size() >= G.stars(k, 1, tr, false).size(), "later rides have more stars")
	var ptr := Track.build(G.practice_base())
	for why in G.check_stars(G.stars(1, 1, ptr, true), ptr, true):
		_expect(false, "practice stars: %s" % why)
	_expect(var_to_str(G.stars(5, 3, ptr, false)) == var_to_str(G.stars(5, 3, ptr, false)), "the same seed gives the same stars")
	# 6) The validator really catches bad plans.
	var bad := one.duplicate(true)
	(bad.pieces as Array).append(["warp", 0.0])
	_expect(not G.check(bad).is_empty(), "an unknown piece is caught")
	var off := G.section(9, pb, 1).duplicate(true)
	for i in 12:
		(off.pieces as Array).append(["straight", 0.0])
	_expect(not G.check(off).is_empty(), "a plan running off the table is caught")
	var curl := {"seed": 1, "section": 1, "base": [], "pieces": [["left", 0.0], ["left", 0.0], ["left", 0.0], ["left", 0.0], ["straight", 0.0]], "wish": "left", "full": false}
	_expect(not G.check(curl).is_empty(), "a track curling into itself is caught")
	var flat := {"seed": 1, "section": 1, "base": [], "pieces": [["straight", 0.0], ["straight", 0.0]], "wish": "straight", "full": false}
	_expect(not G.check(flat).is_empty(), "a coaster without a drop is caught")
	var nowish := one.duplicate(true)
	nowish.wish = "splash" if not (nowish.pieces as Array).any(func(p: Array) -> bool: return p[0] == "splash") else "warp"
	_expect(not G.check(nowish).is_empty(), "a wish that isn't in the plan is caught")
	var empty := one.duplicate(true)
	empty.pieces = []
	_expect(not G.check(empty).is_empty(), "an empty plan not marked full is caught")
	var close := [[Track.STATION_LEN + 3.0, "star"], [Track.STATION_LEN + 3.5, "star"], [Track.STATION_LEN + 9.0, "star"]]
	_expect(not G.check_stars(close, Track.build(one.pieces), false).is_empty(), "stars too close together are caught")
	# 7) The pieces really are in the built track (a cast-append bug once dropped every piece, leaving only the way home).
	var built := Track.build([["straight", 0.0], ["loop", 0.0], ["up", 0.0]])
	var ps: Array = built.piece_s
	_expect(ps.size() == 3 and float(ps[0]) > Track.STATION_LEN and float(ps[1]) > float(ps[0]) + 5.0 and float(ps[2]) > float(ps[1]), "piece distances grow along the track (%s)" % str(ps))
	_expect(float(built.open_s) == float(ps[2]) and (built.loops as Array).size() == 1 and float(built.loops[0][1]) > float(built.loops[0][0]), "the loop is in the track")
	var top := 0.0
	for q in (built.pts as PackedVector3Array):
		top = maxf(top, q.y)
	_expect(top > Track.STATION_Y + Track.LOOP_R * 1.5, "the loop goes up high (%.1f)" % top)
	for t in Track.TYPES:
		_expect(Track.piece_mesh(t, 0.0, Color.WHITE) != null and Track.piece_mesh(t, 0.0, Color.WHITE).get_surface_count() > 0, "the %s tray piece has a mesh" % t)
	# 7) The game uses the same numbers.
	_expect(G.PRACTICE == Main.PRACTICE and G.MAX_PIECES == Main.MAX_PIECES, "practice + piece limit match main.gd")
	_expect(is_equal_approx(G.G, Main.G) and is_equal_approx(G.VMIN, Main.VMIN) and is_equal_approx(G.VMAX, Main.VMAX) and is_equal_approx(G.LIFT_V, Main.LIFT_V), "ride physics match main.gd")
	_expect(is_equal_approx(G.FRICTION, Main.FRICTION) and is_equal_approx(G.GAP, Train.GAP), "friction + car gap match")
	for pic in ["bear", "blueprint", "ticket", "coastercar", "loopdeloop", "splashpool", "bunting", "carousel", "ferris", "fountain", "balloon"]:
		_expect(StoryCard.has_picture(pic), "story picture %s exists" % pic)
	for why in StoryCard.check():
		_expect(false, why)
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)


## A whole coaster built by following every plan from the practice track: {pieces, problems, sections, ...}.
func _coaster(seed_value: int) -> Dictionary:
	var pieces := G.practice_base()
	var problems: Array = []
	var sizes: Array = []
	var k := 1
	var lp := 0
	var sp := 0
	while k < 12:
		var plan := G.section(Seeded.derive(seed_value, k), pieces, k)
		if bool(plan.full):
			break
		for why in G.check(plan):
			problems.append("section %d: %s" % [k, why])
		sizes.append((plan.pieces as Array).size())
		for p in plan.pieces:
			lp += 1 if p[0] == "loop" else 0
			sp += 1 if p[0] == "splash" else 0
		pieces.append_array(plan.pieces)
		k += 1
	if k == 1:
		problems.append("no plan at all after the practice")
	if k >= 12:
		problems.append("plans never fill the table")
	return {"pieces": pieces, "problems": problems, "sections": k - 1, "sizes": sizes, "loops": lp, "splashes": sp}


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: %s" % what)
