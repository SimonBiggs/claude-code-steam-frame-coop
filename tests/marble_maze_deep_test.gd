extends SceneTree
## MARBLE MAZE second pass validator (no game, no window): games/marble_maze/worlds.gd.
##   godot-test --headless --path . -s res://tests/marble_maze_deep_test.gd      (SEEDS=40 for more)
## Proves, for every mode x today's world over many story mazes and daily dates:
##   - the maze is fair (mazegen.gd check(), never the plain fallback) with the mode's holes and the world's extras;
##   - its told events are fair (worlds.gd event_problems(): told >= 2 s early, a quake always weaker than a marble's
##     own push, gates only on a safe doorway along the way, never up long, never two events at once) and the same
##     every time (every machine makes the same list);
##   - GENTLE <= BRAVE <= HARD: the mode table (worlds.gd ordered()) AND what the mazes really get (holes, events,
##     push, gate time, how early it's told);
##   - every marble colour stands out on every floor (worlds never recolour the floor: the snow-sheep lesson);
##   - Bobo's gift picks: three different unlocked marbles, the newest unlock among them, not the last gift again;
##   - today's world: the same all day, every world turns up, no snow in summer, no flower day in winter;
##   - the pick board: open, every orb reachable from the start, under an orb is plain floor.
## Prints "SCRIPT ERROR: ..." for each failure and "MARBLE DEEP: PASS" / "FAIL".

const MazeGen := preload("res://games/marble_maze/mazegen.gd")
const Story := preload("res://games/marble_maze/story.gd")
const Worlds := preload("res://games/marble_maze/worlds.gd")
const Levels := preload("res://games/marble_maze/levels.gd")
const Picks := preload("res://games/marble_maze/picks.gd")
const Main := preload("res://games/marble_maze/main.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const Contrast := preload("res://core/contrast.gd")
const TestTime := preload("res://tests/test_time.gd")

var fails := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 8
	for w in Worlds.ordered():
		_fail("modes: " + str(w))
	for w in Contrast.check_game("marble_maze"):  # marbles on every floor (games/marble_maze/palette.gd)
		_fail("contrast: " + str(w))
	# Mazes x modes x worlds.
	var per_mode := {}
	var checked := 0
	var ev_ms := 0.0
	for mode in PickOrbs.MODE_IDS:
		var sum := {"holes": 0, "events": 0, "gates": 0, "mazes": 0}
		for wd in Worlds.WORLDS:
			for s in seeds:
				var i := (s * 5 + Worlds.WORLDS.find(wd) * 3) % 30
				var def := Story.maze(1000 + s, i, mode, str(wd.id))
				var why := MazeGen.check(def)
				if def.has("fallback"):
					why.append("fell back to the plain maze")
				for x in why:
					_fail("%s / %s / story %d seed %d: %s" % [mode, wd.id, i, 1000 + s, x])
				var e0 := Time.get_ticks_usec()
				var ev := Worlds.events(def, mode)
				ev_ms = TestTime.worst(ev_ms, (Time.get_ticks_usec() - e0) / 1000.0, func() -> Variant: return Worlds.events(def, mode))
				for x in Worlds.event_problems(def, ev, mode):
					_fail("%s / %s / story %d: events: %s" % [mode, wd.id, i, x])
				if var_to_str(ev) != var_to_str(Worlds.events(Story.maze(1000 + s, i, mode, str(wd.id)), mode)):
					_fail("%s / %s / story %d: events differ between two makes" % [mode, wd.id, i])
				sum.holes += int(MazeGen.features(def).get("O", 0))
				sum.events += ev.size()
				for e in ev:
					if str(e[1]) == "gate":
						sum.gates += 1
				sum.mazes += 1
				checked += 1
		# Daily mazes in this mode.
		for d in seeds:
			var date := Time.get_date_string_from_unix_time(1790000000 + d * 86400 * 9)
			var wd2 := str(Worlds.world_of(date).id)
			var dd := Story.daily(date, mode, wd2)
			var why2 := MazeGen.check(dd)
			if dd.has("fallback"):
				why2.append("fell back")
			for x in why2:
				_fail("%s daily %s: %s" % [mode, date, x])
			for x in Worlds.event_problems(dd, Worlds.events(dd, mode), mode):
				_fail("%s daily %s: events: %s" % [mode, date, x])
			checked += 1
		per_mode[mode] = sum
	print("MARBLE DEEP: per mode %s" % str(per_mode))
	var g: Dictionary = per_mode.gentle
	var b: Dictionary = per_mode.brave
	var h: Dictionary = per_mode.hard
	_expect(g.holes <= b.holes and b.holes <= h.holes, "holes gentle %d <= brave %d <= hard %d" % [g.holes, b.holes, h.holes])
	_expect(g.events <= b.events and b.events <= h.events, "events gentle %d <= brave %d <= hard %d" % [g.events, b.events, h.events])
	_expect(h.gates > 0, "closing gates turn up (%d in hard)" % h.gates)
	_expect(ev_ms < 100.0, "events made fast (worst %.1f ms)" % ev_ms)
	# Gift picks.
	for rack in [0, 3, 6, 10, 15, 40]:
		for last in ["", "heavy", "bouncy", "magnet", "sticky", "zoomy"]:
			if last != "" and not Worlds.unlocked(rack).has(last):
				continue
			for s in 20:
				var ch := Worlds.gift_choices(rack, last, s)
				var un := Worlds.unlocked(rack)
				_expect(ch.size() == 3, "three gifts (rack %d last %s: %s)" % [rack, last, str(ch)])
				var seen := {}
				for id in ch:
					_expect(un.has(id), "gift %s unlocked at rack %d" % [id, rack])
					_expect(not seen.has(id), "gifts differ (%s)" % str(ch))
					seen[id] = true
				_expect(ch.has(un[un.size() - 1]) or un[un.size() - 1] == last, "the newest unlock offered (rack %d: %s)" % [rack, str(ch)])
				if un.size() > 3:
					_expect(not ch.has(last), "not the last gift again when there are others (%s, last %s)" % [str(ch), last])
	# Today's world.
	var seen_w := {}
	for d in 366:
		var date := Time.get_date_string_from_unix_time(1790000000 + d * 86400)
		var w := Worlds.world_of(date)
		seen_w[w.id] = true
		_expect(var_to_str(w) == var_to_str(Worlds.world_of(date)), "world of %s the same all day" % date)
		var season := Worlds.season_of(date)
		if season == "summer":
			_expect(w.id != "snow", "no snow day in summer (%s)" % date)
		if season == "winter":
			_expect(w.id != "bloom", "no flower day in winter (%s)" % date)
	_expect(seen_w.size() == Worlds.WORLDS.size(), "every world turns up in a year (%s)" % str(seen_w.keys()))
	# The pick board.
	var pm: Array = Main.PICK_MAP
	_expect(pm.size() == MazeGen.H, "pick board rows")
	var gg: Array = []
	for row in pm:
		var a: Array = []
		for k in str(row):
			a.append(k)
		gg.append(a)
	var reach := MazeGen._walk(gg, MazeGen._find(gg, "S"), true)
	for i in 3:
		var x := Picks.ROW.x + (i - 1) * Picks.GAP
		var c := Vector2i(int(floorf(x / 0.1 + MazeGen.W * 0.5)), int(floorf(Picks.ROW.z / 0.1 + MazeGen.H * 0.5)))
		_expect(reach.has(c) and str(gg[c.y][c.x]) == ".", "pick orb %d over plain reachable floor %s" % [i, str(c)])
	_expect(Picks.Y - 0.6 * Picks.SCALE > 0.028 * 2.0, "a marble rolls under a pick orb")
	# every story maze but a place's last tells how close the place is to lighting up (one more maze)
	for i in Story.PLACES.size() * Story.MAZES_PER_PLACE * 2:
		var line := Story.progress_line(i)
		var last := int(Story.where(i)[1]) == Story.MAZES_PER_PLACE - 1
		_expect((line == "") == last, "progress line after story maze %d: \"%s\"" % [i, line])
		_expect(line.length() <= 40, "progress line short enough for a story card (%s)" % line)
	checked += _hot_streak()
	print("MARBLE DEEP: %d mazes + events checked in %d ms" % [checked, Time.get_ticks_msec() - t0])
	print("MARBLE DEEP: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


## HOT STREAK (story.gd heat_after / heat_spec): every heat a mode allows makes fair mazes in every place (story lap
## and the first bonus lap, every board type), with fair told events; heat only ever adds holes; heat 0 is the very
## maze from before; the streak rules. Returns the mazes checked.
func _hot_streak() -> int:
	var n := 0
	var per := 2 if OS.has_environment("GEN_QUICK") else 4
	for mode in PickOrbs.MODE_IDS:
		var cap := Story.heat_cap(mode)
		_expect(cap >= 1 and cap <= 3, "heat cap %s = %d" % [mode, cap])
		for heat in range(1, cap + 1):
			for lap in 2:
				for pl in Story.PLACES.size():
					for step in Story.MAZES_PER_PLACE:
						var i := (lap * Story.PLACES.size() + pl) * Story.MAZES_PER_PLACE + step
						for s in per:
							var wd := str(Worlds.WORLDS[(s + pl) % Worlds.WORLDS.size()].id)
							var w := 5000 + s * 37 + heat
							var def := Story.maze(w, i, mode, wd, heat)
							var why := MazeGen.check(def)
							if def.has("fallback"):
								why.append("fell back to the plain maze")
							for x in Worlds.event_problems(def, Worlds.events(def, mode), mode):
								why.append("events: " + str(x))
							for x in why:
								_fail("heat %d %s / %s / story %d (%s) world %d: %s" % [heat, mode, wd, i, def.get("name", ""), w, x])
							n += 1
		var base := Worlds.apply(Story.spec(4), mode, "sunny")
		for heat in range(1, cap + 1):
			var hs := Story.heat_spec(base, heat)
			_expect(int(hs.holes) == int(base.holes) + heat, "heat %d adds %d holes (%s)" % [heat, heat, mode])
			_expect(float(hs.door) <= float(base.door) and int(hs.get("loops", 2)) <= int(base.get("loops", 2)), "heat never opens a maze up")
	_expect(var_to_str(Story.maze(7, 4, "brave", "snow", 0)) == var_to_str(Story.maze(7, 4, "brave", "snow")), "heat 0 = the maze from before")
	# The streak: clean, clean -> up; a fall ends it; lots of falls -> down; never past the cap or below 0.
	var r := Story.heat_after(0, 0, 0, 2, "brave")
	_expect(var_to_str(r) == var_to_str([0, 1, 0]), "one clean maze: streak 1 (%s)" % str(r))
	r = Story.heat_after(int(r[0]), int(r[1]), 0, 2, "brave")
	_expect(var_to_str(r) == var_to_str([1, 2, 1]), "two clean mazes: heat up (%s)" % str(r))
	r = Story.heat_after(1, 2, 1, 2, "brave")
	_expect(var_to_str(r) == var_to_str([1, 0, 0]), "one fall ends the streak, keeps the heat (%s)" % str(r))
	r = Story.heat_after(1, 0, 3, 2, "brave")
	_expect(var_to_str(r) == var_to_str([0, 0, -1]), "lots of falls cool down (%s)" % str(r))
	r = Story.heat_after(0, 0, 9, 2, "brave")
	_expect(int(r[0]) == 0 and int(r[2]) == 0, "never below 0 (%s)" % str(r))
	r = Story.heat_after(1, 1, 0, 2, "gentle")
	_expect(int(r[0]) == 1 and int(r[2]) == 0, "gentle stays at its cap (%s)" % str(r))
	r = Story.heat_after(3, 0, 0, 2, "gentle")
	_expect(int(r[0]) == 1, "a hard family's heat drops to gentle's cap (%s)" % str(r))
	r = Story.heat_after(1, 3, 1, 6, "hard")
	_expect(int(r[0]) == 1 and int(r[1]) == 0, "one fall among six marbles doesn't cool (%s)" % str(r))
	_expect(Story.heat_line(12).length() <= 40, "heat line short enough for a story card")
	for x in Story.HotStreak.problems():
		_fail("hot streak: " + str(x))
	return n


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	if fails < 40:
		print("SCRIPT ERROR: MARBLE DEEP: " + what)
