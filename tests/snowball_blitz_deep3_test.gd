extends SceneTree
## SNOWBALL BLITZ third pass (no game, no window):
##   godot-test --headless --path . -s res://tests/snowball_blitz_deep3_test.gd      (SEEDS=500 for more)
## WARNED SURPRISES (games/snowball_blitz/tricks.gd): every siege's plan passes Tricks.check in every mode and level
## (1-3 surprises, never waves 1-2 or a boss wave, told long enough - longer in gentle -, the snow slide outside the
## fort and starting off the square, icicle circles on real walls, no told shape over anyone's start spot), TODAY'S
## BLIZZARD's surprises over 400+ days, both kinds and every plain wave turn up, the validator catches bad plans, the
## start spots match main.gd. SEASONS (seasons.gd): every season has its card picture, hat and props clear of the
## square, the igloos and the pond. BOBO'S FRIENDS (rink.gd): every season has visitors, every friend visits, the
## same seed brings the same friend, pictures exist, the pond grows and stops. Fast (< 100 ms a siege on a Deck).

const G := preload("res://games/snowball_blitz/siegegen.gd")
const Tricks := preload("res://games/snowball_blitz/tricks.gd")
const Seasons := preload("res://games/snowball_blitz/seasons.gd")
const Rink := preload("res://games/snowball_blitz/rink.gd")
const Main := preload("res://games/snowball_blitz/main.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")
const TestTime := preload("res://tests/test_time.gd")

var fails := 0


func _initialize() -> void:
	var seeds := Seeded.test_count(200)
	var tm := {"worst": 0.0, "n": 0}  # (a lambda captures locals by value: keep the worst in a dictionary)
	var seen := {}
	for mode in G.MODES:
		for lv in [1, G.MAX_LEVEL]:
			var res := Seeded.validate(func(s: int) -> Dictionary: return G.siege(s, lv, false, mode),
				func(s: Dictionary) -> Array:
					var t1 := Time.get_ticks_usec()
					var p := Tricks.plan(s)
					var why := Tricks.check(p, mode)
					tm.n = int(tm.n) + 1
					tm.worst = TestTime.worst(float(tm.worst), (Time.get_ticks_usec() - t1) / 1000.0,
						func() -> Variant: return Tricks.check(Tricks.plan(s), mode))
					seen["count:%d" % p.size()] = true
					for n in p:
						seen["%s@%d" % [p[n].kind, int(n)]] = true
						seen[p[n].kind] = true
						seen["wave:%d" % int(n)] = true
					return why, seeds, 101 + lv, [0, 999999], "SURPRISES %s level %d" % [mode, lv])
			fails += (res.failures as Array).size()
	print("surprise plan + check worst %.3f ms over %d sieges" % [float(tm.worst), int(tm.n)])
	_expect(float(tm.worst) < 20.0, "surprises plan + check fast (%.2f ms; a Deck must stay under 100)" % float(tm.worst))
	_expect(int(tm.n) > 10, "surprises were checked (%d)" % int(tm.n))
	for k in Tricks.KINDS:
		_expect(seen.has(k), "a %s turns up" % k)
	for c in [1, 2, 3]:
		_expect(seen.has("count:%d" % c), "sieges with %d surprises" % c)
	for n in range(Tricks.FIRST_WAVE, Tricks.LAST_WAVE + 1):
		if not Tricks.BOSS_WAVES.has(n):
			_expect(seen.has("wave:%d" % n), "a surprise can come in wave %d" % n)
	# TODAY'S BLIZZARD's surprises, every mode, 400+ days.
	var rd := Seeded.validate_days(func(date: String) -> Array:
			var out: Array = []
			for mode in G.MODES:
				out.append(Tricks.plan(G.siege(G.daily_seed(date), G.DAILY_LEVEL, true, mode)))
			return out,
		func(day: Array) -> Array:
			var why: Array = []
			for i in day.size():
				for w in Tricks.check(day[i], G.MODES[i]):
					why.append("%s: %s" % [G.MODES[i], w])
			return why, 400, "TODAY'S BLIZZARD SURPRISES", ["2026-11-13", "2026-12-25"])
	fails += (rd.failures as Array).size()
	# Same seed, same surprises (every machine); modes only change the tell.
	var s := G.siege(4242, 2, false, "brave")
	_expect(var_to_str(Tricks.plan(s)) == var_to_str(Tricks.plan(G.siege(4242, 2, false, "brave"))), "the same seed gives the same surprises")
	var pg := Tricks.plan(G.siege(4242, 2, false, "gentle"))
	var pb := Tricks.plan(s)
	_expect(pg.keys() == pb.keys(), "gentle has the same surprises as brave")
	for n in pg:
		_expect(float(pg[n].tell) > float(pb[n].tell), "gentle tells longer (wave %d)" % int(n))
	# The validator catches bad plans.
	var bad := pb.duplicate(true)
	var k0: int = bad.keys()[0]
	bad[1] = bad[k0].duplicate(true)
	_expect(not Tricks.check(bad).is_empty(), "a surprise in wave 1 is caught")
	bad = pb.duplicate(true)
	bad[7] = pb[k0].duplicate(true)
	_expect(not Tricks.check(bad).is_empty(), "a surprise in the Snow King's wave is caught")
	bad = pb.duplicate(true)
	bad[k0].tell = 1.0
	_expect(not Tricks.check(bad).is_empty(), "a too-short tell is caught")
	var thru := {5: {"kind": "slide", "at": 8.0, "tell": 3.0, "from": Vector3(-23, 0, 0.5), "dir": Vector3.RIGHT, "len": 46.0}}
	_expect(not Tricks.check(thru).is_empty(), "a snow slide through the fort is caught")
	var short := {5: {"kind": "slide", "at": 8.0, "tell": 3.0, "from": Vector3(-5, 0, 10), "dir": Vector3.RIGHT, "len": 10.0}}
	_expect(not Tricks.check(short).is_empty(), "a snow slide starting inside the square is caught")
	var near := {5: {"kind": "icicles", "at": 8.0, "tell": 3.0, "segs": [0, 0]}}
	_expect(not Tricks.check(near).is_empty(), "icicles twice on one wall are caught")
	var over := Tricks.zones({"kind": "slide", "from": Vector3(-23, 0, 2.6), "dir": Vector3.RIGHT, "len": 46.0})
	_expect(WarnRings_inside(over[0], Vector3(2.2, 0, 2.6)), "the start-spot test sees a line over a spot")
	# Start spots match the game's.
	var mn: Node = Main.new()
	for i in 7:
		for mode in ["host", "local"]:
			var sp: Vector3 = mn._spawn_spot(i, mode)
			_expect(Tricks.START_SPOTS.any(func(q: Vector3) -> bool: return q.is_equal_approx(sp)), "start spot %s %d is known to tricks.gd (%s)" % [mode, i, str(sp)])
	for i in Main.SEGMENTS:
		_expect(Tricks.seg_center(i).is_equal_approx(mn.seg_center(i)), "wall %d matches main.gd" % i)
	mn.free()
	_expect(is_equal_approx(Tricks.ARENA_RADIUS, Main.ARENA_RADIUS) and is_equal_approx(Tricks.FORT_RADIUS, Main.FORT_RADIUS) and Tricks.SEGMENTS == Main.SEGMENTS, "square matches main.gd")
	_expect(Tricks.BOSS_WAVES == [G.KING_WAVE, G.FINALE], "boss waves match siegegen.gd")
	_expect(Tricks.ICICLE_KEEP > 0.0, "icicles never take the last of a wall")
	# Seasons.
	var pond := Vector3(G.ARENA_RADIUS + 6.5, 0.0, G.ARENA_RADIUS * 0.25)
	for se in Seasons.SEASONS:
		_expect(StoryCard.has_picture(String(Seasons.PICS[se])), "%s has a card picture" % se)
		_expect(Seasons.HATS.has(se) and Seasons.LINES.has(se) and Seasons.CARD_COLORS.has(se), "%s has a hat, a line and a colour" % se)
		_expect(se == "winter" or Seasons.DRIFT.has(se), "%s drifts" % se)
		_expect(String(Seasons.LINES[se]).length() <= 16, "%s card line is short" % se)
	for p in Seasons.spots():
		var r := Vector2(p.x, p.z).length()
		_expect(r > G.ARENA_RADIUS + 1.5, "season prop %s stands outside the square" % str(p))
		_expect(p.distance_to(Vector3(0, 0, -(G.ARENA_RADIUS + 6.0))) > 4.0, "season prop clear of the big tree")
		_expect(p.distance_to(pond) > Rink.POND_R + 1.0, "season prop clear of the pond")
		for i in G.VILLAGE_SLOTS:
			_expect(p.distance_to(G.village_slot(i)) > 2.2, "season prop clear of igloo %d" % i)
	# Bobo's friends.
	var met := {}
	for se in Seasons.SEASONS:
		var pool := Rink.FRIENDS.filter(func(f: Dictionary) -> bool: return (f.seasons as Array).has(se))
		_expect(pool.size() >= 3, "%s has 3+ friends who visit (%d)" % [se, pool.size()])
		for sd in 200:
			var id := Rink.pick(sd * 31 + 7, se)
			met[id] = true
			_expect((Rink.find(id).seasons as Array).has(se), "%s visits in %s" % [id, se])
	for f in Rink.FRIENDS:
		_expect(met.has(f.id), "%s visits sometimes" % f.id)
		_expect(StoryCard.has_picture(String(f.pic)), "%s has a picture (%s)" % [f.id, f.pic])
		_expect(("%s stays to skate!" % f.name).length() <= 24, "%s's card line is short" % f.id)
	_expect(Rink.pick(99, "winter") == Rink.pick(99, "winter"), "the same seed brings the same friend")
	_expect(Rink.pond_radius(0) == Rink.POND_R and Rink.pond_radius(5) > Rink.pond_radius(4) and Rink.pond_radius(999) == Rink.POND_MAX, "the pond grows with friends and stops")
	for k in Tricks.KINDS:
		_expect(StoryCard.has_picture(String(Tricks.PICS[k])), "%s has a picture" % k)
	print("SNOWBALL BLITZ DEEP3: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)


func WarnRings_inside(z: Dictionary, p: Vector3) -> bool:
	return preload("res://core/warn_rings.gd").inside(String(z.kind), z.pos, z.dir, z.size, p, 0.0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: %s" % what)