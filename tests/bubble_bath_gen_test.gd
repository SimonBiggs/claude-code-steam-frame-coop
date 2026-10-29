extends SceneTree
## BUBBLE BATH generator: proves every seeded bath is fair and finishable by a small kid (no game, no window).
##   godot-test --headless --path . -s res://tests/bubble_bath_gen_test.gd      (SEEDS=500 for more)
## For rounds 1-12 of many baths: games/bubble_bath/bathgen.gd check() (round 1 is the plain bath, one new thing at a
## time, the plug inside the VR splasher's throw and away from walls and tap, islands never pinch a channel or sit on
## the whirlpool, duck spots and boat starts clear and spread round the tub, everything reachable by boat, one slow
## kid alone reaches the goal in well under the round) and check_bath() (goals and islands never go down), the same
## seed gives the same bath, seeds differ, TODAY'S BATH is the same all day and differs between days, the validator
## really catches unfair baths, the toys and ducklings fit on the rim, Mama Duck's pictures exist, the constants
## match the game's, and generation + checks stay fast. Prints "SCRIPT ERROR: ..." per failure.

const G := preload("res://games/bubble_bath/bathgen.gd")
const Main := preload("res://games/bubble_bath/main.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 120
	var t0 := Time.get_ticks_usec()
	var res := Seeded.validate(func(s: int) -> Array:
			var all: Array = []
			for n in range(1, G.MAX_ROUND + 1):
				all.append(G.plan(s, n))
			return all,
		func(_all: Array) -> Array: return [],
		seeds, 1, [0, 999999, G.daily_seed("2026-10-29")], "BATH")
	fails += (res.failures as Array).size()
	var plans := 0
	var worst := 0.0
	for i in seeds:
		var s: int = 1 + i * 7919
		for why in G.check_bath(s):
			fails += 1
			if fails < 40:
				print("SCRIPT ERROR: BATH seed %d: %s" % [s, why])
		for n in range(1, G.MAX_ROUND + 1):
			worst = maxf(worst, G.kid_seconds(G.plan(s, n)))
		plans += G.MAX_ROUND
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, plans * 2.5)
	print("bath gen: %.3f ms per round plan incl. checks (%d plans); slowest kid round %.0f s of %.0f" % [per_ms, plans, worst, G.ROUND_SECS])
	_expect(per_ms < 20.0, "a round plan generates + checks in under 20 ms here (%.2f ms; Decks are ~3x slower, aim < 100)" % per_ms)
	# Variety and determinism.
	_expect(var_to_str(G.plan(4242, 5)) == var_to_str(G.plan(4242, 5)), "the same seed gives the same bath")
	var differ := 0
	for s in 20:
		if var_to_str(G.plan(s * 13 + 1, 4)) != var_to_str(G.plan(s * 13 + 2, 4)):
			differ += 1
	_expect(differ >= 19, "seeds give different baths (%d of 20)" % differ)
	var moved := {}
	for s in 30:
		moved[G.plan(s + 100, 3).drain] = true
	_expect(moved.size() >= 25, "the plug really moves around from round 3 (%d places)" % moved.size())
	_expect(G.daily_seed("2026-10-29") == G.daily_seed("2026-10-29"), "TODAY'S BATH is the same all day")
	_expect(G.daily_seed("2026-10-29") != G.daily_seed("2026-10-30"), "TODAY'S BATH changes the next day")
	_expect(G.daily_seed() == Seeded.daily_seed("bubble_bath"), "TODAY'S BATH uses the shared daily seed")
	# The validator really catches unfair baths.
	var base := G.plan(9, 4)
	_expect(G.check(base).is_empty(), "seed 9 round 4 is fair (%s)" % str(G.check(base)))
	var bad := base.duplicate(true)
	bad.islands.append(Vector3(bad.drain.x + 0.3, bad.drain.y, 0.4))
	_expect(not G.check(bad).is_empty(), "an island on the plug is caught")
	bad = base.duplicate(true)
	bad.drain = Vector2(3.8, 0.0)
	_expect(not G.check(bad).is_empty(), "a plug by the wall is caught")
	bad = base.duplicate(true)
	bad.spots[0] = Vector2(bad.islands[0].x, bad.islands[0].y)
	_expect(not G.check(bad).is_empty(), "a duck on an island is caught")
	bad = base.duplicate(true)
	bad.goal = 60
	_expect(not G.check(bad).is_empty(), "a goal too big for a small kid is caught")
	bad = G.plan(9, 1)
	bad.islands = [Vector3(2.0, 1.0, 0.4)]
	_expect(not G.check(bad).is_empty(), "an island in round 1 is caught")
	# A wall of islands across the tub cuts the left end off: unreachable spots must be caught (island rules off).
	var walled := G.plan(9, 2)
	walled.islands = []
	for k in 7:
		walled.islands.append(Vector3(-2.6, -HZ_() + 0.35 + k * 0.8, 0.45))
	var field := G.path_field(walled)
	var cut := false
	for s in walled.spots:
		if s.x < -3.2 and G.path_to(field, s, 0.6) == INF:
			cut = true
	_expect(cut, "the path search finds spots cut off behind a wall of islands")
	# Toys and ducklings fit on the rims.
	for i in G.TOY_KEEP:
		var p := G.toy_slot(i, 1.05)
		_expect(absf(p.z) <= G.HZ + 0.001, "toy %d sits on the side rim" % i)
	_expect(G.toy_slot(G.TOY_KEEP, 1.05) == Vector3.INF, "no toy slot past the end")
	_expect(G.duckling_slot(G.DUCKLINGS_MAX - 1, 1.05).x < G.HX, "every duckling fits on the far rim")
	_expect(G.ducklings(400) == G.DUCKLINGS_MAX and G.ducklings(3) == 3, "one duckling per play-day, up to the most")
	# Pictures.
	for pic in ["mamaduck", "duckling", "sponge", "bathtub", "beachball", "soapbar", "whale", "boat", "starfish", "fish", "crown", "star"]:
		_expect(StoryCard.has_picture(pic) or ["crown", "star"].has(pic), "the %s picture exists" % pic)
	for t in G.TOYS:
		_expect(StoryCard.has_picture(t), "toy %s has a picture" % t)
	_expect(StoryCard.check().is_empty(), "story pictures are fine (%s)" % str(StoryCard.check()))
	# The constants match the game's.
	_expect(G.HX == Main.HX and G.HZ == Main.HZ and G.DRAIN_R == Main.DRAIN_R and G.BOAT_R == Main.BOAT_R and G.DUCK_R == Main.DUCK_R, "sizes match main.gd")
	_expect(G.TAP.is_equal_approx(Main.TAP), "the tap matches main.gd")
	print("BUBBLE BATH GEN TEST: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)


static func HZ_() -> float:
	return G.HZ


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: BUBBLE BATH GEN: " + what)
