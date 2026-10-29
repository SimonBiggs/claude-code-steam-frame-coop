extends SceneTree
## SOFT DODGEBALL generator: proves every seeded round is fair and gentle for small kids (no game, no window).
##   godot-test --headless --path . -s res://tests/dodge_ball_gen_test.gd      (SEEDS=500 for more)
## For every level and TODAY'S PARK: games/dodge_ball/courtgen.gd check() (cushions inside the court with
## room to run between them and off the spawn spots, the court in one piece, some but not too much cover,
## gold star windows inside the round, sane pace / flight / wobble / blink, and the FAIR AND GENTLE model:
## with 1..6 small runners who never dodge, nobody is out more than MAX_OUT_SHARE of the round, gets more
## than MAX_PER_10S throws in 10 s, is thrown at twice within MIN_GAP, or gets an unfair share), the same seed
## gives the same round, rounds get gently harder, TODAY'S PARK is the same all day and new each day, the
## code round-trips, the fair picker and the gentle bubble work, the park has room, TumTum's pictures exist,
## the constants match the game's, and generation stays fast. Prints "SCRIPT ERROR: ..." per failure.

const G := preload("res://games/dodge_ball/courtgen.gd")
const Main := preload("res://games/dodge_ball/main.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 60
	var t0 := Time.get_ticks_usec()
	var gens := 0
	var avg := {}
	var seen := {}
	for lv in range(1, G.MAX_LEVEL + 1):
		var res := Seeded.validate(func(s: int) -> Dictionary: return G.build(G.code_of(s, lv, false)),
			func(d: Dictionary) -> Array: return G.check(d), seeds, 3 + lv, [0, 999999], "ROUND L%d" % lv)
		gens += int(res.checked)
		fails += (res.failures as Array).size()
		var a := {"pace": 0.0, "flight": 0.0, "cushions": 0.0, "stars": 0.0, "wobble": 0.0}
		for k in 30:
			var d := G.build(G.code_of(k * 37 + 1, lv, false))
			a.pace += float(d.pace) / 30.0
			a.flight += float(d.flight) / 30.0
			a.wobble += float(d.wobble) / 30.0
			a.cushions += float((d.cushions as Array).size()) / 30.0
			a.stars += float((d.stars as Array).size()) / 30.0
			seen[str(d.name).split(" ")[0]] = true
		avg[lv] = a
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens * 2.0)
	print("round gen: %.2f ms per round incl. check (%d rounds)" % [per_ms, gens * 2])
	_expect(per_ms < 25.0, "a round generates + checks fast (%.2f ms here; Decks ~3x slower, aim < 100)" % per_ms)
	for lv in range(1, G.MAX_LEVEL + 1):
		print("level %d: %s" % [lv, str(avg[lv])])
	for lv in range(2, G.MAX_LEVEL + 1):
		_expect(float(avg[lv].pace) <= float(avg[lv - 1].pace) + 0.05, "the giant never slows down going on (L%d)" % lv)
		_expect(float(avg[lv].cushions) >= float(avg[lv - 1].cushions) - 0.3, "cover doesn't vanish going on (L%d)" % lv)
	_expect(float(avg[1].pace) > float(avg[G.MAX_LEVEL].pace) + 0.6, "the warm-up is clearly gentler than the top")
	_expect(float(avg[1].flight) > float(avg[G.MAX_LEVEL].flight) + 0.15, "warm-up lobs fly slower")
	_expect(seen.size() >= G.ADJ.size() / 2, "round names use many words (%d)" % seen.size())
	# Codes round-trip; session order: TODAY'S PARK first when due, then levels climb.
	for s in [0, 1, 4242, 999999]:
		for lv in range(1, G.MAX_LEVEL + 1):
			for dy in [false, true]:
				var c := G.code_of(s, lv, dy)
				_expect(G.seed_of(c) == s and G.level_of(c) == lv and G.daily_of(c) == dy, "code round-trips (%d, %d, %s)" % [s, lv, dy])
	_expect(G.daily_of(G.code_at(5, 1, true)) and not G.daily_of(G.code_at(5, 2, true)), "TODAY'S PARK is the first round when due")
	_expect(not G.daily_of(G.code_at(5, 1, false)), "no TODAY'S PARK once it's done")
	_expect(G.level_of(G.code_at(5, 1, false)) == 1 and G.level_of(G.code_at(5, 2, true)) == 1, "the session starts at level 1")
	_expect(G.level_of(G.code_at(5, 30, false)) == G.MAX_LEVEL, "levels stop at the top")
	for date in ["2026-10-29", "2026-12-25", "2027-01-01"]:
		var dc := G.code_at(77, 1, true, date)
		_expect(dc == G.code_at(123456, 1, true, date), "TODAY'S PARK is the same for every session all day")
		_expect(G.level_of(dc) == G.DAILY_LEVEL, "TODAY'S PARK is at its level")
		var dd := G.build(dc)
		_expect(dd.color == G.GOLD, "TODAY'S PARK is golden")
		for why in G.check(dd):
			_expect(false, "TODAY'S PARK %s: %s" % [date, why])
	_expect(G.daily_seed("2026-10-29") != G.daily_seed("2026-10-30"), "a new TODAY'S PARK each day")
	# The fair picker and the gentle bubble.
	var d1 := G.build(G.code_of(11, 3, false))
	_expect(G.pick_target(d1, {0: 2, 1: 1, 2: 2}, [0, 1, 2], 0) == 1, "the giant aims at whoever had the fewest throws")
	_expect(G.pick_target(d1, {}, [], 0) == -1, "nobody to aim at")
	_expect(G.pick_target(d1, {0: 3, 1: 1}, [0], 0, [1]) == -1, "TumTum waits for a runner who is out instead of piling on")
	_expect(G.pick_target(d1, {0: 2, 1: 1}, [0], 0, [1]) == 0, "... but not when the shares are close")
	var firsts := {}
	for k in 8:
		firsts[G.pick_target(d1, {}, [0, 1, 2, 3], k)] = true
	_expect(firsts.size() >= 3, "ties don't always go to the same runner")
	_expect(is_equal_approx(G.safe_time(d1, [], 20.0), float(d1.safe)), "a first hit: the normal blink")
	_expect(G.safe_time(d1, [10.0], 20.0) > float(d1.safe) + 1.0, "hit again soon: a longer bubble")
	_expect(is_equal_approx(G.safe_time(d1, [1.0], 40.0), float(d1.safe)), "an old hit doesn't count")
	# The checker really catches unkind rounds.
	var mean := d1.duplicate(true)
	mean.pace = 0.3
	mean.jitter = 0.0
	mean.safe = 0.5
	_expect(not G.check(mean).is_empty(), "a giant throwing non-stop is caught")
	var walled := d1.duplicate(true)
	walled.cushions = [[0.0, 0.0, 0.8], [1.2, 0.0, 0.8]]
	_expect(not G.check(walled).is_empty(), "cushions with no room between are caught")
	var lane := d1.duplicate(true)
	lane.cushions = [[-3.0, 3.0, 0.7]]
	_expect(not G.check(lane).is_empty(), "a cushion on a spawn spot is caught")
	var p := G.push_out(d1, Vector3((d1.cushions[0] as Array)[0], 0.0, (d1.cushions[0] as Array)[1]))
	_expect(Vector2(p.x, p.z).distance_to(Vector2(d1.cushions[0][0], d1.cushions[0][1])) >= float(d1.cushions[0][2]) + G.RUNNER_R - 0.01, "runners are pushed out of cushions")
	# The park: room for everything, out of the court, inside the bushes, every kind comes, grows a stage a day.
	var spots: Array = []
	for i in G.PARK_SLOTS:
		var at := G.park_slot(i)
		_expect(absf(at.x) > Main.WALL_X + 0.6 or at.z > Main.WALL_Z.y + 0.6, "park spot %d is outside the court (%s)" % [i, str(at)])
		_expect(Vector2(at.x, at.z + 1.0).length() < 11.2, "park spot %d is inside the bushes (%s)" % [i, str(at)])
		for o in spots:
			_expect((o as Vector3).distance_to(at) > 1.0, "park spot %d has room" % i)
		spots.append(at)
	_expect(G.park_slot(G.PARK_SLOTS) == Vector3.INF, "no park spot past the end")
	_expect(G.park_stage(3, 3) == 0 and G.park_stage(3, 4) == 1 and G.park_stage(3, 30) == G.PARK_STAGES - 1, "park things grow a stage a day")
	var kinds := {}
	for n in 80:
		kinds[G.park_kind(G.code_of(n * 13, 1, false), n)] = true
	_expect(kinds.size() == G.PARK_KINDS.size(), "every kind of park thing comes")
	# The game uses the same numbers.
	_expect(is_equal_approx(G.OUT_TIME, Main.OUT_TIME), "OUT_TIME matches main.gd")
	_expect(is_equal_approx(G.COURT_X, Main.COURT_X) and G.COURT_Z == Main.COURT_Z, "the court matches main.gd")
	_expect(G.GIANT_POS == Vector2(Main.GIANT_FEET.x, Main.GIANT_FEET.z), "the giant's spot matches main.gd")
	for i in 7:
		_expect(G.SPAWNS.has(Main.spawn_spot(i)), "runner %d spawns on a spot the cushions keep clear" % i)
	var m: Node = Main.new()
	_expect(is_equal_approx(G.ROUND_TIME, float(m.get("round_time"))), "the round time matches main.gd")
	m.free()
	var pics: Array = ["tumtum", "squishball", "goldball", "cushion", "tree"]
	pics.append_array(G.PARK_KINDS)
	for pic in pics:
		_expect(StoryCard.has_picture(pic), "story picture %s exists" % pic)
	for why in StoryCard.check():
		_expect(false, why)
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: %s" % what)
