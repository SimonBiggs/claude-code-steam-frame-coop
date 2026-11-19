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
const Worlds := preload("res://games/marble_maze/worlds.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const Seeded := preload("res://core/seeded.gd")

var fails := 0
## The old 2026-10-29 daily maze: the shiny (and the rooms round it) only reachable by leaving the zoom
## arrows at (2,3) / (3,3) sideways, which BOOST never lets a marble do.
const OLD_2026_10_29 := ["############", "#S..#T.....#", "#..##..##.##", "#T>>...O#.G#", "##..#..#####",
	"#....O..O..#", "#..######.##", "#O..*B.B#II#", "#...#....II#", "############"]


func _initialize() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 40
	var t0 := Time.get_ticks_msec()
	var total := 0
	var fallbacks := 0
	var feats := {}
	var path_len := {}
	var laps := 2 if OS.has_environment("GEN_QUICK") else 4  # (a landing: the story and its first bonus lap; nightly: 4)
	for lap in laps:
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
		var twin := {"H": "V", "-": "|"}  # moving walls slide either way, planks lie either way
		var n_tile := int(got.get(tile, 0)) + int(got.get(twin.get(tile, "?"), 0))
		if tile != "" and n_tile < 12:
			_fail("place %s rarely has its tile '%s' (%s)" % [Story.PLACES[pl].name, tile, str(got)])
		if int(got.get("*", 0)) < 12 * Story.MAZES_PER_PLACE * laps * 9 / 10:
			_fail("place %s rarely hides a shiny (%s)" % [Story.PLACES[pl].name, str(got)])
	_expect(fallbacks == 0, "no plain fallback mazes (%d)" % fallbacks)
	# The daily maze: fair for a year of days, the same all day, different on different days.
	# Over 400+ days from 2026-10-01 (Seeded.validate_days, the shared daily validator: includes 2026-10-29, the shiny
	# below a zoom arrow where the bot looped for 230 s, and the 60 days from whenever the test runs), as main.gd
	# _gen_job() makes it (Story.daily(date, mode, Worlds.world_of(date))) in one mode a day (GENTLE / BRAVE / HARD by the
	# date: a maze is ~10 ms, all three a day was +26 s), fair (never the
	# plain fallback: MazeGen.generate() only returns a maze that passed check(), so it isn't run twice), with fair
	# world events (Worlds.event_problems), the same all day.
	var days := {}
	var race_styles := {}
	var rs := Seeded.validate_days(func(date: String) -> Dictionary:
			var wd := str(Worlds.world_of(date).id)
			var out := {}
			for mode in [PickOrbs.MODE_IDS[absi(hash(date)) % PickOrbs.MODE_IDS.size()]]:
				for leg in Story.RACE_LEGS:  # TODAY'S RACE: every leg, as main.gd _gen_job makes it
					var lv := Story.daily(date, mode, wd, leg)
					out["%s%d" % [mode, leg]] = {"lv": lv, "ev": Worlds.events(lv, mode), "mode": mode}
			return out,
		func(out: Dictionary) -> Array:
			var why: Array = []
			var styles := {}
			for key in out:
				var lv: Dictionary = out[key].lv
				var mode: String = out[key].mode
				if lv.has("fallback"):
					why.append("%s: fell back" % key)
				why.append_array(MazeGen.check(lv).map(func(w: String) -> String: return "%s: %s" % [key, w]))
				for w in Worlds.event_problems(lv, out[key].ev, mode):
					why.append("%s: events: %s" % [key, w])
				styles[str(lv.get("style", ""))] = true
				race_styles[str(lv.get("style", ""))] = true
				if int(lv.get("steps", 0)) < MazeGen.MIN_GOAL_STEPS:
					why.append("%s: no race steps" % key)
			if styles.size() < Story.RACE_LEGS:
				why.append("the race's mazes are not all different board types (%s)" % str(styles.keys()))
			for key in out:
				if str(key).ends_with("0"):
					days["\n".join(PackedStringArray(out[key].lv.map))] = true
			return why, 400, "TODAY'S RACE", ["2026-11-11", "2026-11-12"])
	_expect(race_styles.size() == MazeGen.STYLES.size(), "the race uses every board type (%s)" % str(race_styles.keys()))
	total += int(rs.checked)
	fails += (rs.failures as Array).size()
	_expect(days.size() > int(rs.checked) * 4 / 5, "daily mazes differ day to day (%d unique of %d)" % [days.size(), int(rs.checked)])
	_expect(Story.daily("2026-10-29").map != OLD_2026_10_29, "2026-10-29's daily maze is no longer the unfair one")
	_expect(not MazeGen.check({"map": OLD_2026_10_29}).is_empty(), "a shiny only reachable by rolling sideways off a zoom arrow is caught")
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
	print("MAZE: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
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
	var lap := Story.PLACES.size() * Story.MAZES_PER_PLACE
	_expect(Story.where(0) == [0, 0, 0] and Story.where(5) == [1, 2, 0], "where() walks places 3 mazes each")
	_expect(Story.where(lap) == [0, 0, 1], "after every place the bonus lap starts")
	_expect(Story.places_lit(0) == 0 and Story.places_lit(3) == 1 and Story.places_lit(999) == Story.PLACES.size(), "places light up per 3 mazes")
	_expect(Story.spec(0).new == "O" and Story.spec(1).new == "" and Story.spec(lap).new == "", "a place's new tile sparkles once")
	_expect(int(Story.spec(lap).holes) > int(Story.spec(0).holes), "bonus laps have more holes")
	# Third pass: every board type in the story, the race's cups and clock, old saves moved onto the twelve places.
	var styles := {}
	for i in lap:
		styles[str(Story.spec(i).style)] = true
	_expect(styles.size() == MazeGen.STYLES.size(), "every board type is in the story (%s)" % str(styles.keys()))
	_expect(str(Story.spec(2).style) != "rooms", "the very first place already has a different board type")
	_expect(Story.medal(10.0, 30, 1) == "gold" and Story.medal(30.0, 30, 1) == "silver" and Story.medal(99.0, 30, 1) == "bronze", "race cups")
	_expect(Story.medal(25.0, 30, 4) == "gold", "more marbles get a little more time for gold")
	_expect(Story.clock(65.4) == "1:05" and Story.clock(9.9) == "0:09", "the race clock")
	_expect(Story.migrate_story_i(1) == 1 and Story.migrate_story_i(3) == 3 and Story.migrate_story_i(6) == 9, "old saves keep their place")
	_expect(Story.migrate_story_i(20) == Story.OLD_PLACES[6] * 3 + 2 and Story.migrate_story_i(21) == lap, "old saves keep their lap")
	for j in Story.OLD_PLACES.size():
		_expect(Story.PLACES[Story.OLD_PLACES[j]].name == ["FLOWER PARK", "SEASIDE", "CANDY SHOP", "ICE CAVE", "CASTLE", "STAR PARK", "RAINBOW HILL"][j],
			"old place %d moved to %d" % [j, Story.OLD_PLACES[j]])
	_expect(MazeGen.MARBLE_STEER == preload("res://games/marble_maze/marble.gd").STEER, "the magnet check uses the marble's real push")
	# Hand checks for the new tiles: a magnet by a hole, a warp exit by the air, a moving wall along a corridor, a plank
	# entered from the side, air by the start: each caught.
	_expect(not MazeGen.check({"map": ["############", "#S.........#", "#..........#", "#...NO.....#", "#..........#",
		"#..........#", "#..........#", "#..........#", "#.........G#", "############"]}).is_empty(), "a magnet by a hole is caught")
	_expect(not MazeGen.check({"map": ["############", "#S.........#", "#.W........#", "#..........#", "#..........#",
		"#......w_..#", "#..........#", "#..........#", "#.........G#", "############"]}).is_empty(), "a warp exit by the air is caught")
	_expect(not MazeGen.check({"map": ["############", "#S.........#", "#.#########", "#.#H.......#", "#.#.###....#",
		"#...#......#", "#.#........#", "#..........#", "#.........G#", "############"]}).is_empty(), "a moving wall sliding along a corridor is caught")
	_expect(MazeGen.check({"map": ["############", "#S..#......#", "#...#......#", "#..._......#", "#...-......#",
		"#..._......#", "#...#......#", "#...#......#", "#...#.....G#", "############"]}).is_empty() == true, "a plank across a wall column is crossed left/right")
	_expect(MazeGen.check({"map": ["############", "#S..#......#", "#...#......#", "#..._......#", "#...|......#",
		"#..._......#", "#...#......#", "#...#......#", "#...#.....G#", "############"]}).is_empty() == false, "a plank lying the wrong way leads nowhere (caught)")
	_expect(MazeGen.check({"map": ["############", "#S..#......#", "#...#......#", "#..._......#", "#..._......#",
		"#...-......#", "#..._......#", "#...#......#", "#...#.....G#", "############"]}).is_empty(), "a plank across the gap passes")
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
