extends SceneTree
## ROCKET WORKSHOP second pass validator (no game, no window): games/rocket_workshop/deep.gd (+ rocketgen.gd opts).
##   godot-test --headless --path . -s res://tests/rocket_workshop_deep_test.gd      (SEEDS=60 for more)
## Proves, for every mode, season, gift and rocket number over many seeds:
##   - every meteor is fair (deep.gd problems(): on the workshop floor, never at the pilot's desk or where the crew
##     arrive, never in a rocket's first seconds, never two at once, always time to walk out while told, room to walk
##     between a shower's rings), the same every time and unchanged over the network; the bots' busier spec too;
##   - GENTLE <= BRAVE <= HARD: the mode table (ordered()) AND what the rockets really get (meteors a rocket, warning
##     seconds, ring size, desk puzzles a rocket, how soon Sprocket helps);
##   - every rocket with every mode and gift is solvable (rocketgen.gd check() with the opts): BOOSTERS never takes the
##     new control away, HARD's extra puzzle is one the family has met; FINS really means fewer meteors;
##   - Sprocket's gifts: three different unlocked ones, the newest among them, not the last again when there are others,
##     every picture drawn, short names and lines; every gift opens as the family launches rockets;
##   - the seasons: a picture, a short line, a yard ground;
##   - the pick row over the desk: every orb in the VR pilot's reach, far enough apart that one hand never touches two,
##     and a crew member standing at the desk's far side under one takes that one only;
##   - every key colour stands out (core/contrast.gd, games/rocket_workshop/palette.gd);
##   - fast: well under 100 ms a rocket (a Deck plans one when it rolls out).
## Prints "SCRIPT ERROR: ..." for each failure and "ROCKET DEEP: PASS" / "FAIL".

const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/rocket_workshop/deep.gd")
const G := preload("res://games/rocket_workshop/rocketgen.gd")
const P := preload("res://games/rocket_workshop/puzzles.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const Seeded := preload("res://core/seeded.gd")
const TestTime := preload("res://tests/test_time.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 25
	for w in Deep.ordered():
		_fail("modes: " + str(w))
	for w in Contrast.check_game("rocket_workshop"):
		_fail("contrast: " + str(w))
	var gifts: Array = [""]
	for g in Deep.GIFTS:
		gifts.append(String(g.id))
	var per := {}
	var worst_ms := 0.0
	for mode in PickOrbs.MODE_IDS:
		var sum := {"events": 0, "rockets": 0, "warn": 0.0, "size": 0.0, "rings": 0, "puzzles": 0, "help": 0.0}
		for season in Deep.SEASONS:
			for gid in gifts:
				for n in [1, 2, 3, 4, 6, 9, 12]:
					for s in seeds:
						var rseed: int = 4100 + s * 7919 + int(n)
						var spec := {"mode": mode, "season": season, "gift": gid, "n": n}
						var t1 := Time.get_ticks_usec()
						var ms := Seeded.derive(rseed, "meteors")
						var list := Deep.events(ms, spec)
						var opts := Deep.puzzle_opts(mode, gid, n)
						var rk := G.rocket(rseed, n, 2, true, 40, false, opts)
						worst_ms = TestTime.worst(worst_ms, (Time.get_ticks_usec() - t1) / 1000.0, func() -> Variant: return [Deep.events(Seeded.derive(rseed, "meteors"), spec), G.rocket(rseed, n, 2, true, 40, false, Deep.puzzle_opts(mode, gid, n))])
						var tag := "%s %s %s rocket %d seed %d" % [mode, season, gid if gid != "" else "no gift", n, rseed]
						for x in Deep.problems(list, spec):
							_fail("%s: %s" % [tag, x])
						if s == 0 and str(Deep.events(ms, spec)) != str(list):
							_fail("%s: meteors differ for the same seed" % tag)
						for e in list:
							if str(Deep.unpack(Deep.pack(e))) != str(e):
								_fail("%s: a meteor changes over the network" % tag)
							sum.size += float(e.r) if String(e.kind) == "meteor" else 0.0
							sum.rings += 1 if String(e.kind) == "meteor" else 0
						if n >= Deep.FIRST_N and Deep.want_of(spec) > 0 and list.is_empty():
							_fail("%s: no meteors" % tag)
						if n < Deep.FIRST_N and not list.is_empty():
							_fail("%s: meteors on the practice / TODAY'S rocket" % tag)
						for why in G.check(rk, {"n": n, "crew": 2, "simple": true, "launched": 40, "opts": opts}):
							_fail("%s: rocket: %s" % [tag, why])
						if gid == "":
							sum.events += list.size()
							sum.rockets += 1
							sum.warn += Deep.warn_of(spec)
							sum.puzzles += (rk.modules as Array).size()
							var h := Deep.help_after(mode, gid, n)
							sum.help += 30.0 if h == INF else h
						if s < 3:  # the bots' busier spec: still fair
							var bspec := spec.duplicate()
							bspec["scale"] = 3.0
							bspec["first"] = 3.0
							for x in Deep.problems(Deep.events(ms, bspec), bspec):
								_fail("%s (bot spec): %s" % [tag, x])
					# Gifts really change the rocket.
					var base: int = G.simple_want(n, Deep.puzzle_opts(mode, "", n))
					if gid == "boosters" and n > 1 and G.simple_want(n, Deep.puzzle_opts(mode, gid, n)) >= base and base > 1:
						_fail("%s rocket %d: BOOSTERS keeps every puzzle" % [mode, n])
					if gid == "fins" and n >= Deep.FIRST_N and Deep.want_of({"mode": mode, "season": season, "gift": gid, "n": n}) \
							>= Deep.want_of({"mode": mode, "season": season, "n": n}) and Deep.want_of({"mode": mode, "season": season, "n": n}) > 0:
						_fail("%s %s rocket %d: FINS brings as many meteors" % [mode, season, n])
		per[mode] = sum
	var avg := func(m: String, k: String, by: String) -> float: return float(per[m][k]) / maxf(1.0, float(per[m][by]))
	for pair in [["events", "rockets", 1], ["puzzles", "rockets", 1], ["size", "rings", 1], ["help", "rockets", 1], ["warn", "rockets", -1]]:
		var a: float = avg.call("gentle", pair[0], pair[1])
		var b: float = avg.call("brave", pair[0], pair[1])
		var c: float = avg.call("hard", pair[0], pair[1])
		var ok := (a <= b and b <= c) if int(pair[2]) > 0 else (a >= b and b >= c)
		if not ok:
			_fail("%s not gentle %s brave %s hard: %.2f %.2f %.2f" % [pair[0], "<=" if int(pair[2]) > 0 else ">=",
				"<=" if int(pair[2]) > 0 else ">=", a, b, c])
		print("  %s: gentle %.2f  brave %.2f  hard %.2f" % [pair[0], a, b, c])
	_check_gifts()
	_check_seasons()
	_check_row()
	if worst_ms > 100.0:
		_fail("planning a rocket took %.1f ms" % worst_ms)
	print("ROCKET DEEP: %s (worst %.2f ms a rocket)" % ["PASS" if fails == 0 else "FAIL (%d)" % fails, worst_ms])
	quit(1 if fails > 0 else 0)


func _check_gifts() -> void:
	for g in Deep.GIFTS:
		if not StoryCard.has_picture(String(g.pic)):
			_fail("gift %s: no picture %s" % [g.id, g.pic])
		if String(g.name).length() > 10 or String(g.line).length() > 28:
			_fail("gift %s: name or line too long" % g.id)
		if int(g.unlock) > 30:
			_fail("gift %s opens too late" % g.id)
		var lk := Deep.gift_look([0, 0, 0, 0, 0, 0], String(g.id))
		if lk.size() != 6 or int(lk[G.L_FINS]) >= G.FINS.size() or int(lk[G.L_EXTRA]) >= G.EXTRAS.size():
			_fail("gift %s: a part off the rocket %s" % [g.id, str(lk)])
	for total in [0, 3, 8, 20, 60]:
		var un := Deep.unlocked(total)
		for last in [""] + un:
			for s in 20:
				var ch := Deep.gift_choices(total, String(last), 900 + s)
				var seen := {}
				for id in ch:
					if not un.has(id) or seen.has(id):
						_fail("gift choices %s (total %d)" % [str(ch), total])
					seen[id] = true
				if ch.size() != mini(3, un.size()):
					_fail("%d gift choices (total %d)" % [ch.size(), total])
				if not ch.has(un[un.size() - 1]) and String(last) != String(un[un.size() - 1]):
					_fail("the newest gift is missing (total %d)" % total)
				if un.size() > 3 and ch.has(last):
					_fail("the last gift again (total %d)" % total)
	if Deep.unlocked(1000).size() != Deep.GIFTS.size():
		_fail("a gift never opens")


func _check_seasons() -> void:
	for s in Deep.SEASONS:
		var sd: Dictionary = Deep.SEASONS[s]
		if not StoryCard.has_picture(String(sd.pic)):
			_fail("season %s: no picture %s" % [s, sd.pic])
		if String(sd.line).length() > 28:
			_fail("season %s: line too long" % s)
		if (sd.weights as Array).size() != Deep.KINDS.size():
			_fail("season %s: weights" % s)
	for p in ["meteor"]:
		if not StoryCard.has_picture(p):
			_fail("no picture %s" % p)


func _check_row() -> void:
	var hit := PickOrbs.HIT_R * Deep.ORB_SCALE
	for top in [0.75, 0.9, 1.1]:
		for n in [2, 3]:
			var row := Deep.row_spots(n, top)
			for i in row.size():
				var o: Vector3 = row[i]
				if o.distance_to(Deep.PILOT_AT + Vector3(0.0, top - 0.9, 0.0)) > Deep.REACH:
					_fail("orb %d out of the VR pilot's reach (top %.2f)" % [i, top])
				var stand := Deep.crew_spot(o)
				if Deep.desk_dist(stand) > 0.12 or (stand.z > Deep.DESK_LO.y):
					_fail("orb %d: the crew can't stand under it %s" % [i, str(stand)])
				for j in row.size():
					var q: Vector3 = row[j]
					var flat := Vector2(stand.x - q.x, stand.z - q.z).length()
					if i == j and flat >= Deep.crew_r():
						_fail("orb %d: standing under it doesn't take it (%.2f m)" % [i, flat])
					if i != j and flat < Deep.crew_r():
						_fail("orb %d: standing under it takes orb %d too" % [i, j])
					if i < j and o.distance_to(q) < 2.0 * (hit + Deep.HAND_R):
						_fail("orbs %d and %d: one hand touches both" % [i, j])


func _fail(msg: String) -> void:
	fails += 1
	if fails <= 40:
		printerr("SCRIPT ERROR: " + msg)
