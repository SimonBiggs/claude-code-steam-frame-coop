extends SceneTree
## COLOUR CONTRAST: every arcade game's games/<game>/palette.gd (core/contrast.gd) - each key gameplay colour
## (players, balls, pickups, hazards) stands out on every floor / ground / sky the game can show. Fails a game in
## arcade GAMES without a palette.gd. Also proves the check itself: the known bad cases fail and their fixes pass.
##   godot-test --headless --path . -s res://tests/contrast_test.gd     Prints CONTRAST: PASS / FAIL.

const Contrast := preload("res://core/contrast.gd")

## History (why MIN is what it is): [fg, bg, should pass, what]. These are the colours as they WERE, kept here on
## purpose (not read from the games, which have moved on).
const SAMPLES := [
	[Color(0.97, 0.96, 0.92), Color(0.86, 0.9, 0.95), false, "Sheep Round-Up: white sheep on the old snowy winter grass"],
	[Color(1.0, 0.99, 0.97), Color(0.86, 0.9, 0.95), false, "Sheep Round-Up: a lamb on the old snowy winter grass"],
	[Color(0.97, 0.96, 0.92), Color(0.6, 0.76, 0.7), true, "Sheep Round-Up: white sheep on frosty-green winter grass"],
	[Color(0.25, 0.6, 1.0), Color(0.3, 0.55, 0.93), false, "Balloon Pop: the old blue balloon on the day sky"],
	[Color(0.3, 0.9, 0.4), Color(0.45, 0.78, 0.36), false, "Balloon Pop: the old green balloon on spring grass"],
	[Color(0.72, 0.9, 1.0), Color(0.86, 0.9, 0.96), false, "Balloon Pop: the old ice balloon on snow"],
	[Color(0.15, 0.3, 0.95), Color(0.3, 0.55, 0.93), true, "Balloon Pop: the new blue balloon on the day sky"],
	[Color(0.55, 1.0, 0.15), Color(0.45, 0.78, 0.36), true, "Balloon Pop: the new green balloon on spring grass"],
	[Color(0.35, 1.0, 0.9), Color(0.86, 0.9, 0.96), true, "Balloon Pop: the new ice balloon on snow"],
	[Color(0.25, 0.6, 1.0), Color(0.82, 0.92, 0.99), true, "Marble Maze: a blue marble on the ice floor"],
]

var fails := 0


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("CONTRAST: FAIL ", what)


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	# The check itself.
	for s in SAMPLES:
		var sc := Contrast.score(s[0], s[1])
		_expect(Contrast.distinct(s[0], s[1]) == bool(s[2]), "%s should %s (score %.3f, MIN %.2f)" % [s[3],
			"pass" if s[2] else "fail", sc, Contrast.MIN])
	_expect(Contrast.problems({"sheep": Color(0.97, 0.96, 0.92)}, {"snow": Color(0.86, 0.9, 0.95)}).size() == 1,
		"problems() reports a white sheep on snow")
	_expect(Contrast.problems({"sheep": {"color": Color(0.97, 0.96, 0.92), "rim": Color(0.2, 0.2, 0.25)}},
		{"snow": Color(0.86, 0.9, 0.95)}).is_empty(), "a dark rim makes a white sheep stand out on snow")
	_expect(not Contrast.distinct(Color(0.2, 0.4, 1.0, 0.05), Color(0.86, 0.9, 0.96)), "a nearly clear stripe doesn't show")
	_expect(Contrast.check_game("no_such_game")[0].contains("add games/no_such_game/palette.gd"),
		"a game without palette.gd is told to add one")
	# Every game in the arcade (Quiz Show / Mystery Manor are hidden there, so not in GAMES).
	var games: Array = load("res://arcade/arcade.gd").GAMES
	var pairs := 0
	var bad_games := 0
	for g in games:
		var id := String(g.id)
		var probs := Contrast.check_game(id)
		pairs += Contrast.pair_count(id)
		if not probs.is_empty():
			bad_games += 1
		for p in probs:
			_expect(false, p)
	var ms := Time.get_ticks_msec() - t0
	print("CONTRAST: %d games, %d colour pairs, %d games with problems, %d ms" % [games.size(), pairs, bad_games, ms])
	_expect(ms < 2000, "the contrast test took %d ms (keep it < 2 s: palette.gd should preload small data scripts)" % ms)
	print("CONTRAST: PASS" if fails == 0 else "CONTRAST: FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)
