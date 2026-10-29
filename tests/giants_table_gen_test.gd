extends SceneTree
## GIANT'S TABLE raid generator: proves every seeded wave is fair and finishable by small kids (no game, no window).
##   godot-test --headless --path . -s res://tests/giants_table_gen_test.gd      (SEEDS=500 for more)
## For waves 1..RaidGen.MAX_WAVE of many raids and every party (the Giant alone, with one knight, two, ... six):
## games/giants_table/raidgen.gd check() (ladders: one on the Giant's side for waves 1-2, two from wave 3, two or three
## from wave 6, spread apart, never in the river or on a boulder, a walkable path to the fire for small and big
## goblins that takes long enough; new goblin kinds only from their wave; the first one up always a plain goblin;
## balloons land on dry open ground; a slow kid loses no ember in waves 1-2 and at most one a wave in the night) and
## check_night() (the slow kid's fire never runs low over a night), the same seed gives the same raid, seeds differ,
## TODAY'S RAID is the same all day (and the same for every party size) and differs between days, the validator
## really catches unfair waves, gifts and lanterns fit on the rim, Sparky's pictures exist, the constants match the
## game's, and generation + checks stay fast. Prints "SCRIPT ERROR: ..." per failure.

const G := preload("res://games/giants_table/raidgen.gd")
const W := preload("res://games/giants_table/world.gd")
const Main := preload("res://games/giants_table/main.gd")
const Goblin := preload("res://games/giants_table/goblin.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")
const PARTIES := [[0, true], [0, false], [1, false], [2, false], [3, false], [4, false]]  # [extra knights, solo]

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 60
	W.field(false, false)  # (the flow fields are built once per game; don't time them)
	W.field(true, false)
	var t0 := Time.get_ticks_usec()
	var res := Seeded.validate(func(s: int) -> Array:
			var all: Array = []
			for party in PARTIES:
				for n in range(1, G.MAX_WAVE + 1):
					all.append(G.plan(s, n, party[0], party[1]))
			return all,
		func(all: Array) -> Array:
			var why: Array = []
			for p in all:
				why.append_array(G.check(p))
			return why,
		seeds, 1, [0, 999999, G.daily_seed("2026-10-29")], "RAID")
	fails += (res.failures as Array).size()
	var plans := seeds * PARTIES.size() * G.MAX_WAVE
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, plans)
	var longest := 0.0
	for i in seeds:
		var s: int = 1 + i * 7919
		for party in PARTIES:
			for why in G.check_night(s, party[0], party[1]):
				fails += 1
				if fails < 40:
					print("SCRIPT ERROR: RAID seed %d party %s: %s" % [s, party, why])
		for n in range(1, G.MAX_WAVE + 1):
			longest = maxf(longest, float(G.kid_sim(G.plan(s, n, 0, true)).end))
	print("raid gen: %.3f ms per wave plan incl. checks (%d plans); the slow solo kid's longest wave %.0f s" % [per_ms, plans, longest])
	_expect(per_ms < 20.0, "a wave plan generates + checks in under 20 ms here (%.2f ms; Decks are ~3x slower, aim < 100)" % per_ms)
	# Variety and determinism.
	_expect(var_to_str(G.plan(4242, 5, 1, false)) == var_to_str(G.plan(4242, 5, 1, false)), "the same seed gives the same raid")
	var differ := 0
	for s in 20:
		if var_to_str(G.ladders(s * 13 + 1, 4)) != var_to_str(G.ladders(s * 13 + 2, 4)):
			differ += 1
	_expect(differ >= 18, "seeds give different ladders (%d of 20)" % differ)
	var spots := {}
	for s in 40:
		spots[snappedf(float(G.ladders(s + 100, 3)[1]), 0.2)] = true
	_expect(spots.size() >= 15, "the second ladder really moves round the table (%d places)" % spots.size())
	for party in PARTIES:
		_expect(var_to_str(G.plan(77, 6, party[0], party[1]).ladders) == var_to_str(G.ladders(77, 6)), "every party size sees the same ladders (%s)" % str(party))
	_expect(G.daily_seed("2026-10-29") == G.daily_seed("2026-10-29"), "TODAY'S RAID is the same all day")
	_expect(G.daily_seed("2026-10-29") != G.daily_seed("2026-10-30"), "TODAY'S RAID changes the next day")
	_expect(G.daily_seed() == Seeded.daily_seed("giants_table"), "TODAY'S RAID uses the shared daily seed")
	# The story rules.
	_expect(G.ladder_count(1) == 1 and G.ladder_count(2) == 1 and G.ladder_count(3) == 2, "one ladder, then two from wave 3")
	var kings := 0
	for n in range(1, G.MAX_WAVE + 1):
		for sp in G.plan(5, n, 0, true).spawns:
			if sp[0] == "king":
				kings += 1
				_expect(n % 3 == 0 and n >= 6, "the King comes on wave 6, 9, 12 (wave %d)" % n)
			_expect(sp[0] != "armored", "no spiky goblins for a Giant alone")
	_expect(kings == 3, "the King comes three times in 12 waves (%d)" % kings)
	_expect(G.NIGHT_WAVES == 6, "the night ends with the King's first wave")
	# The validator really catches unfair waves.
	var base := G.plan(9, 4, 0, true)
	_expect(G.check(base).is_empty(), "seed 9 wave 4 is fair (%s)" % str(G.check(base)))
	var bad := base.duplicate(true)
	for sp in bad.spawns:
		sp[2] = 0.5
	_expect(not G.check(bad).is_empty(), "goblins all at once (too quick for a small kid) is caught")
	bad = base.duplicate(true)
	bad.ladders[1] = fposmod(float(bad.ladders[0]) + 0.3, TAU)
	_expect(not G.check(bad).is_empty(), "two ladders side by side is caught")
	bad = base.duplicate(true)
	bad.ladders[0] = fposmod(G.GIANT_A + PI, TAU)
	_expect(not G.check(bad).is_empty(), "the first ladder behind the village (far from the Giant) is caught")
	bad = G.plan(9, 1, 0, true)
	bad.spawns.append(["ogre", bad.ladders[0], 5.0, 0.0])
	_expect(not G.check(bad).is_empty(), "an ogre in wave 1 is caught")
	bad = G.plan(9, 2, 0, true)
	bad.spawns[0][0] = "balloon"
	_expect(not G.check(bad).is_empty(), "a balloon goblin first in wave 2 is caught")
	var river_a := -1.0
	for k in 360:
		var a := TAU * k / 360.0
		if not G._ladder_ok(a, []).is_empty() and W.river_dist(cos(a) * 13.5, sin(a) * 13.5) < 1.0:
			river_a = a
			break
	_expect(river_a >= 0.0, "a ladder where the river leaves the table is caught")
	_expect(not G._balloon_ok(0.0, 0.5).is_empty(), "a balloon landing in the fire is caught")
	var houses := 0
	for c in W.obstacles():
		var q := Vector2(c[0], c[1])
		if q.length() >= G.BALLOON_R.x and q.length() <= G.BALLOON_R.y and not G._balloon_ok(q.angle(), q.length()).is_empty():
			houses += 1
	_expect(houses >= 1, "a balloon landing on a house or tree is caught (%d)" % houses)
	# Keepsakes fit on the rim and never cross.
	for i in G.GIFT_KEEP:
		var p := G.gift_slot(i)
		_expect(Vector2(p.x, p.z).length() > W.R and Vector2(p.x, p.z).length() < W.EDGE, "gift %d sits on the rim" % i)
		_expect(p.z < -W.R * 0.6, "gift %d is on the far side, facing the Giant" % i)
		for j in G.LANTERNS_MAX:
			_expect(p.distance_to(G.lantern_slot(j)) > 0.9, "gift %d and lantern %d don't overlap" % [i, j])
	_expect(G.gift_slot(G.GIFT_KEEP) == Vector3.INF and G.lantern_slot(G.LANTERNS_MAX) == Vector3.INF, "no slots past the end")
	for j in G.LANTERNS_MAX:
		var q := G.lantern_slot(j)
		_expect(Vector2(q.x, q.z).length() > W.R and Vector2(q.x, q.z).length() < W.EDGE, "lantern %d sits on the rim" % j)
	_expect(G.lanterns(400) == G.LANTERNS_MAX and G.lanterns(3) == 3, "one lantern per play-day, up to the most")
	_expect(G.gift_for(0) == "pie" and G.gift_for(G.GIFTS.size()) == "pie", "gifts go round in order")
	# Pictures.
	for pic in ["sparky", "ladder", "goblin", "lantern", "balloon"]:
		_expect(StoryCard.has_picture(pic), "the %s picture exists" % pic)
	for g in G.GIFTS:
		_expect(StoryCard.has_picture(g), "gift %s has a picture" % g)
		_expect(Main.GIFT_LINES.has(g), "gift %s has a line" % g)
	_expect(StoryCard.check().is_empty(), "story pictures are fine (%s)" % str(StoryCard.check()))
	# The constants match the game's.
	_expect(G.MAX_EMBERS == Main.MAX_EMBERS and G.BOULDERS == Main.BOULDER_COUNT, "embers and boulders match main.gd")
	_expect(G.BALLOON_FALL == Goblin.BALLOON_FALL, "the balloon fall speed matches goblin.gd")
	for k in G.SPEED:
		_expect(is_equal_approx(float(G.SPEED[k]), float(Goblin.KINDS[k].speed)), "%s speed matches goblin.gd" % k)
	print("GIANTS TABLE GEN TEST: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: GIANTS TABLE GEN: " + what)
