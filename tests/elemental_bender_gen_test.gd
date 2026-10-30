extends SceneTree
## ELEMENTAL BENDER wave generator: proves every seeded wave is fair for small kids (no game, no window).
##   godot-test --headless --path . -s res://tests/elemental_bender_gen_test.gd      (SEEDS=500 for more)
## For waves 1..WaveGen.MAX_WAVE of many temples and every party size (1..7 fighters): games/elemental_bender/
## wavegen.gd check() (portals: one in front for waves 1-2, two from wave 3, two or three from wave 6, spread apart
## on open grass, far enough out; one element in waves 1-2 (two different ones), then 2, 3, 4; no far throwers before
## wave 3; the General only every 5th wave, first, swapping to a new element each time; the first raider from the
## front portal; a slow kid team never faces more than kid_cap() at once; spawning done in time), the same seed
## gives the same waves, seeds differ, TODAY'S RAIDERS is the same all day and differs between days, the validator
## really catches unfair waves, the Spirit Tree / fruit / lanterns fit beside the temple, Kiko's pictures exist, the
## constants match the game's, and generation + checks stay fast. Prints "SCRIPT ERROR: ..." per failure.

const G := preload("res://games/elemental_bender/wavegen.gd")
const W := preload("res://games/elemental_bender/world.gd")
const Main := preload("res://games/elemental_bender/main.gd")
const Pics := preload("res://games/elemental_bender/story_pictures.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 60
	W.layout()  # (built once per game; don't time it)
	var t0 := Time.get_ticks_usec()
	var res := Seeded.validate(func(s: int) -> Array:
			var all: Array = []
			for players in range(1, G.MAX_PLAYERS + 1):
				for n in range(1, G.MAX_WAVE + 1):
					all.append(G.plan(s, n, players))
			return all,
		func(all: Array) -> Array:
			var why: Array = []
			for p in all:
				why.append_array(G.check(p))
			return why,
		seeds, 1, [0, 999999, G.daily_seed("2026-10-30")], "TEMPLE")
	fails += (res.failures as Array).size()
	var plans := seeds * G.MAX_PLAYERS * G.MAX_WAVE
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, plans)
	var longest := 0.0
	var busiest := 0
	for i in seeds:
		var s: int = 1 + i * 7919
		for n in range(1, G.MAX_WAVE + 1):
			var sim := G.kid_sim(G.plan(s, n, 1))
			longest = maxf(longest, float(sim.end))
			busiest = maxi(busiest, int(sim.most))
	print("temple gen: %.3f ms per wave plan incl. checks (%d plans); the slow solo kid's longest wave %.0f s, most at once %d" % [
		per_ms, plans, longest, busiest])
	_expect(per_ms < 20.0, "a wave plan generates + checks in under 20 ms here (%.2f ms; Decks are ~3x slower, aim < 100)" % per_ms)
	# Variety and determinism.
	_expect(var_to_str(G.plan(4242, 5, 2)) == var_to_str(G.plan(4242, 5, 2)), "the same seed gives the same waves")
	var differ := 0
	for s in 20:
		if var_to_str(G.gates(s * 13 + 1, 4)) != var_to_str(G.gates(s * 13 + 2, 4)):
			differ += 1
	_expect(differ >= 18, "seeds give different portals (%d of 20)" % differ)
	var spots := {}
	for s in 40:
		var g: Vector3 = G.gates(s + 100, 3)[1]
		spots[snappedf(atan2(g.z, g.x), 0.3)] = true
	_expect(spots.size() >= 12, "the second portal really moves round the island (%d places)" % spots.size())
	var firsts := {}
	for s in 40:
		firsts[int(G.plan(s + 7, 1, 1).palette[0])] = true
	_expect(firsts.size() == 4, "wave 1 can bring any element (%d kinds)" % firsts.size())
	for players in range(1, G.MAX_PLAYERS + 1):
		_expect(var_to_str(G.plan(77, 6, players).gates) == var_to_str(G.gates(77, 6)), "every party size sees the same portals (%d)" % players)
	_expect(G.daily_seed("2026-10-30") == G.daily_seed("2026-10-30"), "TODAY'S RAIDERS is the same all day")
	_expect(G.daily_seed("2026-10-30") != G.daily_seed("2026-10-31"), "TODAY'S RAIDERS changes the next day")
	_expect(G.daily_seed() == Seeded.daily_seed("elemental_bender"), "TODAY'S RAIDERS uses the shared daily seed")
	# The story rules.
	for s in 30:
		_expect(G.plan(s, 1, 1).palette != G.plan(s, 2, 1).palette, "waves 1 and 2 bring different elements (seed %d)" % s)
	var generals := 0
	for n in range(1, G.MAX_WAVE + 1):
		var p := G.plan(5, n, 1)
		if p.boss:
			generals += 1
			_expect(n % 5 == 0, "the General comes on wave 5, 10, 15 (wave %d)" % n)
	_expect(generals == 3, "the General comes three times in 15 waves (%d)" % generals)
	# The validator really catches unfair waves.
	var base := G.plan(9, 4, 1)
	_expect(G.check(base).is_empty(), "seed 9 wave 4 is fair (%s)" % str(G.check(base)))
	var bad := base.duplicate(true)
	for sp in bad.spawns:
		sp[3] = 0.3
	_expect(not G.check(bad).is_empty(), "raiders all at once (too busy for small kids) is caught")
	bad = base.duplicate(true)
	var g0: Vector3 = bad.gates[0]
	bad.gates[1] = g0.rotated(Vector3.UP, 0.3)
	_expect(not G.check(bad).is_empty(), "two portals side by side is caught")
	bad = G.plan(9, 1, 1)
	bad.gates[0] = -(bad.gates[0] as Vector3)
	_expect(not G.check(bad).is_empty(), "the wave 1 portal behind the temple is caught")
	bad = G.plan(9, 1, 1)
	bad.gates[0] = Vector3(0, 0, -12.0)
	_expect(not G.check(bad).is_empty(), "a portal right next to the temple is caught")
	bad = G.plan(9, 2, 1)
	bad.spawns[1][0] = (int(bad.palette[0]) + 1) % 4
	_expect(not G.check(bad).is_empty(), "a second element in wave 2 is caught")
	bad = G.plan(9, 2, 1)
	bad.spawns[1][2] = true
	_expect(not G.check(bad).is_empty(), "a far thrower in wave 2 is caught")
	bad = G.plan(9, 5, 1)
	bad.boss_order[1] = bad.boss_order[0]
	_expect(not G.check(bad).is_empty(), "the General swapping to the same element is caught")
	var on_prop := 0
	for pr in W.layout().props:
		var q: Vector3 = pr.p
		if Vector2(q.x, q.z).length() > G.GATE_R.x and Vector2(q.x, q.z).length() < G.GATE_R.y and not G._gate_ok(q, []).is_empty():
			on_prop += 1
	_expect(on_prop >= 1, "a portal on a tree or rock is caught (%d)" % on_prop)
	_expect(not G._gate_ok(Vector3(0, 0, -22.5), []).is_empty(), "a portal on a training platform is caught")
	_expect(W.blocked(Vector3(0, 0, -19.0), 0.5) != "", "the training platform is not open grass")
	# Keepsakes fit beside the temple.
	_expect(W.blocked(G.TREE_AT, G.TREE_CLEAR) == "", "the Spirit Tree stands on open grass (%s)" % W.blocked(G.TREE_AT, G.TREE_CLEAR))
	for n in range(1, 4):
		for g in G.gates(n, 1):
			_expect((g as Vector3).distance_to(G.TREE_AT) > 6.0, "the Spirit Tree isn't on a portal")
	for i in G.LANTERNS_MAX:
		var p := G.lantern_slot(i)
		var r := Vector2(p.x, p.z).length()
		_expect(r > 8.5 and r < 11.0, "lantern %d sits round the temple steps" % i)
		_expect(p.distance_to(G.TREE_AT) > 2.5, "lantern %d isn't in the tree" % i)
		for pr in W.layout().props:
			_expect((pr.p as Vector3).distance_to(p) > float(pr.r) + 0.3, "lantern %d isn't in a tree or rock" % i)
	_expect(G.lantern_slot(G.LANTERNS_MAX) == Vector3.INF, "no lantern slots past the end")
	_expect(G.lanterns(400) == G.LANTERNS_MAX and G.lanterns(3) == 3, "one lantern per play-day, up to the most")
	_expect(G.tree_stage(0) == 0 and G.tree_stage(1000) == G.TREE_STAGES.size() - 1, "the tree grows from a seed to the great tree")
	for st in range(1, G.TREE_STAGES.size()):
		for i in G.FRUIT_MAX:
			var f := G.fruit_slot(i, st)
			_expect(f.y > 0.2 and Vector2(f.x, f.z).length() <= G.crown_r(st) * 1.0 + 0.01, "fruit %d hangs in the crown (stage %d)" % [i, st])
	# Pictures.
	for pic in ["kiko", "portal", "general", "spirittree", "lightfruit", "lantern", "crown"]:
		_expect(StoryCard.has_picture(pic), "the %s picture exists" % pic)
	for pic in Pics.ELEMENT_PICS:
		_expect(StoryCard.has_picture(pic), "element picture %s exists" % pic)
	_expect(StoryCard.check().is_empty(), "story pictures are fine (%s)" % str(StoryCard.check()))
	# The constants match the game's.
	_expect(G.MAX_ALIVE == Main.MAX_ALIVE, "MAX_ALIVE matches main.gd")
	_expect(G.GAME_ID == Main.GAME_ID, "the game id matches main.gd")
	print("ELEMENTAL BENDER GEN TEST: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: ELEMENTAL BENDER GEN: " + what)
