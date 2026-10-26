extends SceneTree
## MARBLE MAZE generator: proves the seeded mazes are fair over many seeds (no game, no window).
##   godot-test --headless --path . -s res://tests/marble_maze_gen_test.gd      (SEEDS=500 for more)
## For every story place (and 3 bonus laps) and the daily maze: games/marble_maze/mazegen.gd check()
## (the start reaches the goal with zoom arrows one-way and teleporters as links; team pads are
## reachable with the gate shut and the goal is not; no trap cells; the shiny is reachable; holes
## never cluster or sit by the start / goal / bumpers / arrow landings), the same seed gives the same
## maze, the generator never falls back to the plain maze, every place's own feature shows up, and the
## story rules (where / places lit / shinies / save defaults).
## Prints "SCRIPT ERROR: ..." for each failure.

const MazeGen := preload("res://games/marble_maze/mazegen.gd")
const Story := preload("res://games/marble_maze/story.gd")
const Seeded := preload("res://core/seeded.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 40
	var t0 := Time.get_ticks_msec()
	var total := 0
	var fallbacks := 0
	var feats := {}
	var path_len := {}
	for lap in 4:
		for pl in Story.PLACES.size():
			for step in Story.MAZES_PER_PLACE:
				var i := (lap * Story.PLACES.size() + pl) * Story.MAZES_PER_PLACE + step
				var sp := Story.spec(i)
				var r := Seeded.validate(func(s: int) -> Dictionary: return MazeGen.generate(s, sp),
					func(lv: Dictionary) -> Array:
						var why := MazeGen.check(lv)
						if lv.has("fallback"):
							why.append("fell back to the plain maze")
						return why,
					seeds if step == 0 else seeds / 3, 3 + i, [0, 1, 999999], "MAZE %s" % sp.name)
				total += int(r.checked)
				fails += (r.failures as Array).size()
				for s in 12:
					var lv := MazeGen.generate(100 + s, sp)
					if lv.has("fallback"):
						fallbacks += 1
					var f := MazeGen.features(lv)
					var key := "%d" % pl
					if not feats.has(key):
						feats[key] = {}
					for k in f:
						feats[key][k] = int(feats[key].get(k, 0)) + 1
					path_len[lap] = int(path_len.get(lap, 0)) + MazeGen._path(_grid(lv)).size()
	# Every place's own thing shows up in its mazes.
	for pl in Story.PLACES.size():
		var tile: String = Story.PLACES[pl].tile
		var got: Dictionary = feats.get("%d" % pl, {})
		if tile != "" and int(got.get(tile, 0)) < 12:
			_fail("place %s rarely has its tile '%s' (%s)" % [Story.PLACES[pl].name, tile, str(got)])
		if int(got.get("*", 0)) < 12 * Story.MAZES_PER_PLACE * 4 * 9 / 10:
			_fail("place %s rarely hides a shiny (%s)" % [Story.PLACES[pl].name, str(got)])
	_expect(fallbacks == 0, "no plain fallback mazes (%d)" % fallbacks)
	# The daily maze: fair for a year of days, the same all day, different on different days.
	var days := {}
	for d in 120:
		var date := Time.get_date_string_from_unix_time(1790000000 + d * 86400)
		var lv := Story.daily(date)
		var why := MazeGen.check(lv)
		if lv.has("fallback"):
			why.append("fell back")
		for w in why:
			_fail("daily %s: %s" % [date, w])
		_expect(var_to_str(lv) == var_to_str(Story.daily(date)), "daily %s is the same all day" % date)
		days["\n".join(PackedStringArray(lv.map))] = true
		total += 1
	_expect(days.size() > 100, "daily mazes differ day to day (%d unique of 120)" % days.size())
	# A hand check: a gate with its pads behind it must fail; a trap after an arrow must fail.
	_expect(not MazeGen.check({"map": ["############", "#S.........#", "#..........#", "#######D####", "#.P......P.#",
		"#..........#", "#..........#", "#..........#", "#.........G#", "############"]}).is_empty(), "pads behind the gate are caught")
	_expect(not MazeGen.check({"map": ["############", "#S.........#", "#.######...#", "#.#....#...#", "#.#.##.#...#",
		"#.#.##v#...#", "#...##.#...#", "#.#######..#", "#.........G#", "############"]}).is_empty(), "an arrow into a dead end is caught")
	_expect(MazeGen.check({"map": ["############", "#S.........#", "#..........#", "#######....#", "#..........#",
		"#..........#", "#....#######", "#..........#", "#.........G#", "############"]}).is_empty(), "the first lesson passes")
	_story_checks()
	for lap in path_len:
		print("MAZE: lap %d average way %.1f cells" % [lap, float(path_len[lap]) / (Story.PLACES.size() * Story.MAZES_PER_PLACE * 12)])
	print("MAZE: %d mazes checked, %d failures (%d ms)" % [total, fails, Time.get_ticks_msec() - t0])
	_show(Story.maze(4242, 0))
	_show(Story.maze(4242, 14))
	_show(Story.maze(4242, 18))
	quit(1 if fails > 0 else 0)


func _grid(lv: Dictionary) -> Array:
	var g: Array = []
	for row in lv.map:
		var a: Array = []
		for k in str(row):
			a.append(k)
		g.append(a)
	return g


func _show(lv: Dictionary) -> void:
	print("MAZE %s (seed %d):" % [lv.name, int(lv.seed)])
	for row in lv.map:
		print("   " + str(row))


func _story_checks() -> void:
	_expect(Story.where(0) == [0, 0, 0] and Story.where(5) == [1, 2, 0], "where() walks places 3 mazes each")
	_expect(Story.where(21) == [0, 0, 1], "after 7 places the bonus lap starts")
	_expect(Story.places_lit(0) == 0 and Story.places_lit(3) == 1 and Story.places_lit(99) == 7, "places light up per 3 mazes")
	_expect(Story.spec(0).new == "O" and Story.spec(1).new == "" and Story.spec(21).new == "", "a place's new tile sparkles once")
	_expect(int(Story.spec(21).holes) > int(Story.spec(0).holes), "bonus laps have more holes")
	_expect(Story.shiny_of(-1)[0] == "GOLDEN" and Story.shiny_of(17)[0] == Story.SHINIES[1][0], "shinies cycle, daily is golden")
	_expect(Story.shiny_total({"SUNNY": 2, "OCEAN": 1}) == 3, "shiny total")
	var d := Story.save_defaults()
	for k in ["lessons_done", "story_i", "world", "shinies", "places", "daily"]:
		_expect(d.has(k), "save default %s" % k)
	_expect(var_to_str(Story.maze(7, 4)) == var_to_str(Story.maze(7, 4)), "a world's maze is always the same")
	_expect(var_to_str(Story.maze(7, 4)) != var_to_str(Story.maze(8, 4)), "different worlds differ")


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	if fails <= 40:
		print("SCRIPT ERROR: MAZE %s" % what)
