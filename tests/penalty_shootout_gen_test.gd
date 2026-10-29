extends SceneTree
## PENALTY SHOOTOUT generator: proves every seeded match is fair and winnable by small kids (no game, no window).
##   godot-test --headless --path . -s res://tests/penalty_shootout_gen_test.gd      (SEEDS=500 for more)
## For matches 1-8 of many cups: games/penalty_shootout/matchgen.gd check() (match 1 starts plain, one new thing at a
## time, Leo's stars well inside the goal, off the keeper's middle and side to side, kick speeds start slow and rise
## in small steps under the cap, a slow kid keeper alone can reach the first computer kicks, every star kick and most
## of the rest, practice rings inside the goal, Leo's star goal easy for a small kid with 1-6 strikers or the
## computer) and check_cup() (never slower, never fewer stars), the same seed gives the same match, seeds differ,
## TODAY'S MATCH is the same all day and differs between days, the validator really catches unfair matches, the
## cubs and prizes fit beside Leo, the pictures exist, the constants match the game's, and generation stays fast.
## Prints "SCRIPT ERROR: ..." per failure.

const G := preload("res://games/penalty_shootout/matchgen.gd")
const Main := preload("res://games/penalty_shootout/main.gd")
const Ball := preload("res://games/penalty_shootout/ball.gd")
const Striker := preload("res://games/penalty_shootout/striker.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 150
	var t0 := Time.get_ticks_usec()
	var res := Seeded.validate(func(s: int) -> Array:
			var all: Array = []
			for n in range(1, G.MAX_MATCH + 1):
				all.append(G.plan(s, n))
			return all,
		func(_all: Array) -> Array: return [],
		seeds, 1, [0, 999999, G.daily_seed("2026-10-29")], "MATCH")
	fails += (res.failures as Array).size()
	var plans := 0
	var hardest := 99
	for i in seeds:
		var s: int = 1 + i * 7919
		for why in G.check_cup(s):
			fails += 1
			if fails < 40:
				print("SCRIPT ERROR: MATCH seed %d: %s" % [s, why])
		for n in range(1, G.MAX_MATCH + 1):
			var p := G.plan(s, n)
			var ok := 0
			for k in G.CPU_TURNS:
				var c: Vector3 = p.cpu[k]
				if absf(c.x) <= G.kid_reach(G.kick_speed(G.speed_at(p, k), c.z)):
					ok += 1
			hardest = mini(hardest, ok)
		plans += G.MAX_MATCH
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, plans * 3.0)
	print("match gen: %.3f ms per match plan incl. checks (%d plans); hardest solo match: %d of %d computer kicks reachable" % [
		per_ms, plans, hardest, G.CPU_TURNS])
	_expect(per_ms < 20.0, "a match plan generates + checks in under 20 ms here (%.2f ms; Decks are ~3x slower, aim < 100)" % per_ms)
	# Variety and determinism.
	_expect(var_to_str(G.plan(4242, 3)) == var_to_str(G.plan(4242, 3)), "the same seed gives the same match")
	var differ := 0
	for s in 20:
		if var_to_str(G.plan(s * 13 + 1, 2)) != var_to_str(G.plan(s * 13 + 2, 2)):
			differ += 1
	_expect(differ >= 19, "seeds give different matches (%d of 20)" % differ)
	var spots := {}
	for s in 30:
		spots[G.plan(s + 100, 1).stars[2]] = true
	_expect(spots.size() >= 25, "Leo's first star really moves around (%d places)" % spots.size())
	_expect(G.daily_seed("2026-10-29") == G.daily_seed("2026-10-29"), "TODAY'S MATCH is the same all day")
	_expect(G.daily_seed("2026-10-29") != G.daily_seed("2026-10-30"), "TODAY'S MATCH changes the next day")
	_expect(G.daily_seed() == Seeded.daily_seed("penalty_shootout"), "TODAY'S MATCH uses the shared daily seed")
	# One new thing at a time.
	var m1 := G.plan(9, 1)
	_expect(m1.stars[0] == Vector2.INF and m1.stars[1] == Vector2.INF and m1.stars[2] != Vector2.INF, "match 1: no star for the first two kicks")
	_expect(G.star_turns(G.plan(9, 3), 10) > G.star_turns(m1, 10), "later matches have more stars")
	# The validator really catches unfair matches.
	var base := G.plan(9, 3)
	_expect(G.check(base).is_empty(), "seed 9 match 3 is fair (%s)" % str(G.check(base)))
	var bad := base.duplicate(true)
	bad.stars[3] = Vector2(3.4, 1.0)
	_expect(not G.check(bad).is_empty(), "a star by the post is caught")
	bad = base.duplicate(true)
	bad.stars[3] = Vector2(0.1, 1.0)
	_expect(not G.check(bad).is_empty(), "a star in the keeper's middle is caught")
	bad = base.duplicate(true)
	bad.stars[3] = Vector2(1.5, 2.3)
	_expect(not G.check(bad).is_empty(), "a star under the bar is caught")
	bad = base.duplicate(true)
	bad.speeds[0] = 14.0
	_expect(not G.check(bad).is_empty(), "a fast first kick is caught")
	bad = base.duplicate(true)
	bad.speeds[10] = float(bad.speeds[9]) + 3.0
	_expect(not G.check(bad).is_empty(), "a sudden jump in speed is caught")
	bad = base.duplicate(true)
	bad.cpu[0] = Vector3(3.2, 1.0, 0.9)
	_expect(not G.check(bad).is_empty(), "an unreachable first computer kick is caught")
	bad = base.duplicate(true)
	for k in G.CPU_TURNS:
		if not bool(bad.cpu_star[k]):
			bad.cpu[k] = Vector3(3.2, 1.0, 0.9)
	_expect(not G.check(bad).is_empty(), "a computer striker a small keeper can't stop is caught")
	bad = base.duplicate(true)
	bad.rings[2] = Vector2(3.4, 1.0)
	_expect(not G.check(bad).is_empty(), "a practice ring poking out of the goal is caught")
	bad = G.plan(9, 1)
	bad.stars[0] = Vector2(1.5, 1.0)
	_expect(not G.check(bad).is_empty(), "a star on the very first kick of match 1 is caught")
	# Leo's goal for every team size.
	for strikers in range(0, 7):
		var turns := G.turns_for(strikers)
		_expect(G.star_goal(m1, turns) >= 1, "Leo always asks for at least one star (%d strikers)" % strikers)
	_expect(G.turns_for(1) == 5 and G.turns_for(6) == 18 and G.turns_for(0) == G.CPU_TURNS, "kicks per match match main.gd")
	_expect(G.takes_star(m1, 2, m1.stars[2]) and not G.takes_star(m1, 2, Vector2(-m1.stars[2].x, 1.0)), "an aim at the star takes it")
	# Cubs and prizes fit beside Leo, off the pitch's goal mouth.
	for i in G.CUBS_MAX:
		var c := G.cub_slot(i)
		_expect(c.x < -G.GOAL_HALF - 2.0, "cub %d sits clear of the goal" % i)
		for j in i:
			_expect(c.distance_to(G.cub_slot(j)) > 0.45, "cubs %d and %d don't overlap" % [i, j])
	for i in G.PRIZE_KEEP:
		var p := G.prize_slot(i)
		_expect(p.x < -G.GOAL_HALF - 2.0, "prize %d sits clear of the goal" % i)
		for j in G.CUBS_MAX:
			_expect(Vector2(p.x, p.z).distance_to(Vector2(G.cub_slot(j).x, G.cub_slot(j).z)) > 0.4, "prize %d doesn't stand on cub %d" % [i, j])
	_expect(G.prize_slot(G.PRIZE_KEEP) == Vector3.INF, "no prize slot past the end")
	_expect(G.cubs(400) == G.CUBS_MAX and G.cubs(3) == 3, "one cub per play-day, up to the most")
	# Pictures.
	for pic in ["lion", "lioncub", "football", "crown"]:
		_expect(StoryCard.has_picture(pic), "the %s picture exists" % pic)
	for pr in G.PRIZES:
		_expect(StoryCard.has_picture(pr), "prize %s has a picture" % pr)
	_expect(StoryCard.check().is_empty(), "story pictures are fine (%s)" % str(StoryCard.check()))
	# The constants match the game's.
	_expect(G.GOAL_HALF == Ball.GOAL_HALF and G.GOAL_H == Ball.GOAL_H, "goal size matches ball.gd")
	_expect(G.SPD_MIN == Main.SPD_MIN and G.AIM_X == Striker.AIM_X and G.AIM_Y_MAX == Striker.AIM_Y_MAX, "kick and aim limits match the game")
	_expect(G.CPU_TURNS == Main.CPU_ROUNDS, "the computer striker's kicks match main.gd")
	print("PENALTY SHOOTOUT GEN TEST: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: PENALTY SHOOTOUT GEN: " + what)
