extends SceneTree
## PENALTY SHOOTOUT second pass validator (no game, no window): games/penalty_shootout/deep.gd.
##   godot-test --headless --path . -s res://tests/penalty_shootout_deep_test.gd      (SEEDS=40 for more)
## Proves, for every mode, season and match over many cup seeds:
##   - the weather is fair (deep.gd problems(): none on match 1 or a match's first kicks, never two kicks in a row, a
##     gust never blows a star kick out of the goal, no kick too slow, a lone keeper still reaches enough of the
##     computer striker's kicks), the same every time and unchanged over the network;
##   - GENTLE <= BRAVE <= HARD: the mode table (deep.gd ordered()) AND what the matches really get (weather kicks,
##     warning seconds, gust drift, kick speeds, how big Leo's star is);
##   - Leo's gifts: three different unlocked ones, the newest among them, not the last again when there are others,
##     every picture drawn, short names; every gift opens within a few weeks of play; every gift's speed still flies;
##   - the seasons: each has drifting things, a picture and a line;
##   - the pick row: orbs inside the goal mouth (a kick aimed at one goes in), far enough apart that one ball never
##     takes two, within a keeper's reach of the goal line, and long enough to kick at;
##   - Leo's trophy corner only grows and stands clear of Leo, his prizes, his cubs, the goal and every kick;
##   - every key colour stands out (core/contrast.gd, games/penalty_shootout/palette.gd);
##   - fast: well under 100 ms a match (a Deck builds one between matches).
## Prints "SCRIPT ERROR: ..." for each failure and "PENALTY DEEP: PASS" / "FAIL".

const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/penalty_shootout/deep.gd")
const MatchGen := preload("res://games/penalty_shootout/matchgen.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const Seeded := preload("res://core/seeded.gd")
const Keeper := preload("res://games/penalty_shootout/keeper.gd")

var fails := 0


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 12
	for w in Deep.ordered():
		_fail("modes: " + str(w))
	for w in Contrast.check_game("penalty_shootout"):
		_fail("contrast: " + str(w))
	var per := {}
	var checked := 0
	var worst_ms := 0.0
	for mode in PickOrbs.MODE_IDS:
		var sum := {"weather": 0, "kicks": 0, "gusts": 0, "muds": 0, "drift": 0.0, "speed": 0.0}
		for season in Deep.SEASONS:
			for s in seeds:
				var cup := 5100 + s * 7919
				for n in range(1, MatchGen.MAX_MATCH + 1):
					var t1 := Time.get_ticks_usec()
					var spec := {"mode": mode, "season": season}
					var list := Deep.hazards(cup, n, spec)
					worst_ms = maxf(worst_ms, (Time.get_ticks_usec() - t1) / 1000.0)
					checked += 1
					var tag := "%s %s cup %d match %d" % [mode, season, cup, n]
					for x in Deep.problems(cup, n, list, spec):
						_fail("%s: %s" % [tag, x])
					if s == 0 and str(Deep.hazards(cup, n, spec)) != str(list):
						_fail("%s: weather differs for the same seed" % tag)
					for e in list:
						if str(Deep.unpack(Deep.pack(e))) != str(e):
							_fail("%s: weather changes over the network" % tag)
					# Bots turn weather on from match 1, kick 1: still fair.
					var bot_spec := {"mode": mode, "season": season, "from": 1, "first": 1}
					for x in Deep.problems(cup, n, Deep.hazards(cup, n, bot_spec), bot_spec):
						_fail("%s (bot spec): %s" % [tag, x])
					if n >= Deep.FIRST_MATCH:
						var plan := MatchGen.plan(cup, n)
						var turns := MatchGen.turns_for(2)
						for k in turns:
							sum.kicks += 1
							var e: Dictionary = list[k]
							sum.speed += Deep.top_speed(MatchGen.speed_at(plan, k), mode, "", e)
							if e.is_empty():
								continue
							sum.weather += 1
							if String(e.kind) == "gust":
								sum.gusts += 1
								sum.drift += float(e.drift)
							else:
								sum.muds += 1
		var kicks := maxf(1.0, sum.kicks)
		per[mode] = {"weather": sum.weather / kicks, "drift": sum.drift / maxf(1.0, sum.gusts), "speed": sum.speed / kicks,
			"warn": float(Deep.mode_data(mode).warn), "star": Deep.star_r(mode, ""), "gusts": sum.gusts, "muds": sum.muds}
		print("PENALTY DEEP %s: weather on %.0f%% of kicks, told %.1f s, gusts blow %.1f m, top speed %.1f m/s, star r %.2f m (%d gusts, %d muds)" % [
			mode, per[mode].weather * 100.0, per[mode].warn, per[mode].drift, per[mode].speed, per[mode].star, sum.gusts, sum.muds])
	var g: Dictionary = per.gentle
	var b: Dictionary = per.brave
	var h: Dictionary = per.hard
	for k in ["weather", "drift", "speed"]:
		if not (float(g[k]) <= float(b[k]) + 0.001 and float(b[k]) <= float(h[k]) + 0.001):
			_fail("real matches: %s not gentle <= brave <= hard (%.2f %.2f %.2f)" % [k, g[k], b[k], h[k]])
	for k in ["warn", "star"]:
		if not (float(g[k]) >= float(b[k]) and float(b[k]) >= float(h[k])):
			_fail("real matches: %s not most on gentle" % k)
	for m in per:
		if float(per[m].weather) < 0.08:
			_fail("%s: hardly any weather (%.2f a kick)" % [m, per[m].weather])
		if int(per[m].gusts) == 0 or int(per[m].muds) == 0:
			_fail("%s: never a gust or never mud" % m)
	if not Deep.hazards(5100, 1, {"mode": "hard"}).all(func(e): return (e as Dictionary).is_empty()):
		_fail("weather on the first match")
	_gifts()
	_seasons()
	_row()
	_corner()
	print("PENALTY DEEP: %d matches checked, %.1f ms worst, %d ms total" % [checked, worst_ms, Time.get_ticks_msec() - t0])
	if worst_ms > 100.0:
		_fail("a match took %.0f ms to make (a Deck must stay well under 100 ms)" % worst_ms)
	print("PENALTY DEEP: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func _gifts() -> void:
	var ids: Array = []
	for gd in Deep.GIFTS:
		ids.append(String(gd.id))
		if not StoryCard.has_picture(String(gd.pic)):
			_fail("gift %s: no picture %s" % [gd.id, gd.pic])
		if String(gd.name).length() > 12 or String(gd.line).length() > 20:
			_fail("gift %s: name or line too long" % gd.id)
		if int(gd.unlock) > Deep.CORNER.size():
			_fail("gift %s never opens" % gd.id)
		if int(gd.unlock) * Deep.CORNER_EVERY > 14:  # star goals: about one a match, a few matches a day
			_fail("gift %s takes too long to open" % gd.id)
		for mode in PickOrbs.MODE_IDS:
			if Deep.top_speed(MatchGen.SPEED_FIRST, mode, String(gd.id), {"kind": "mud"}) < Deep.MIN_SPEED:
				_fail("gift %s: kicks too slow on %s in mud" % [gd.id, mode])
	if Keeper.BIG_GLOVES < 1.3:
		_fail("BIG GLOVES barely grow")
	if Deep.star_r("hard", "") < MatchGen.STAR_R * 0.7:
		_fail("hard: Leo's star too small to hit")
	for pieces in range(0, Deep.CORNER.size() + 1):
		var un := Deep.unlocked(pieces)
		for last in [""] + ids:
			for s in 6:
				var ch := Deep.gift_choices(pieces, String(last), 300 + s * 7)
				var tag := "gifts (corner %d, last %s, seed %d)" % [pieces, last, s]
				if ch.size() != mini(3, un.size()):
					_fail("%s: %d choices" % [tag, ch.size()])
				var seen := {}
				for id in ch:
					if seen.has(id):
						_fail("%s: %s twice" % [tag, id])
					seen[id] = true
					if not un.has(id):
						_fail("%s: %s is still locked" % [tag, id])
				if not ch.has(un[un.size() - 1]) and un[un.size() - 1] != last:
					_fail("%s: the newest gift is missing" % tag)
				if un.size() > 3 and ch.has(last):
					_fail("%s: the last gift again" % tag)
				if str(ch) != str(Deep.gift_choices(pieces, String(last), 300 + s * 7)):
					_fail("%s: choices differ for the same seed" % tag)


func _seasons() -> void:
	for s in ["spring", "summer", "autumn", "winter"]:
		if not Deep.SEASONS.has(s):
			_fail("no %s" % s)
			continue
		var sd: Dictionary = Deep.SEASONS[s]
		for k in ["drift", "pic", "line", "weights"]:
			if not sd.has(k):
				_fail("season %s has no %s" % [s, k])
		if not StoryCard.has_picture(String(sd.pic)):
			_fail("season %s: no picture %s" % [s, sd.pic])
		if String(sd.line).length() > 20:
			_fail("season %s: line too long" % s)
	for date in ["2026-01-10", "2026-04-10", "2026-07-10", "2026-10-10"]:
		if not Deep.SEASONS.has(Seeded.season(date)):
			_fail("no pitch for %s" % Seeded.season(date))
	for p in ["airswirl", "mudpatch", "gift", "lion", "star"]:
		if not StoryCard.has_picture(p):
			_fail("no picture %s" % p)
	for k in Deep.CORNER_PICS:
		if not StoryCard.has_picture(String(Deep.CORNER_PICS[k])):
			_fail("corner %s: no picture" % k)


func _row() -> void:
	var spots := Deep.row_spots()
	var catch := Deep.catch_r()
	for i in spots.size():
		var p: Vector3 = spots[i]
		# A kick aimed at the orb's middle goes into the goal (inside the posts, under the bar).
		if absf(p.x) + 0.3 > MatchGen.GOAL_HALF - 0.5 or p.y > MatchGen.GOAL_H - 0.4 or p.y < 0.6:
			_fail("pick row: orb %d isn't comfortably inside the goal mouth" % i)
		if p.z < Keeper.KEEPER_Z + 0.3 or p.z > Keeper.KEEPER_Z + 1.0:
			_fail("pick row: orb %d out of the keeper's reach from the goal line (z %.1f)" % [i, p.z])
		if absf(p.x) > 2.6:
			_fail("pick row: orb %d too far for a keeper to step to" % i)
		for j in i:
			if p.distance_to(spots[j]) < catch * 2.0 + 0.2:
				_fail("pick row: orbs %d and %d too close (one ball takes both)" % [i, j])
		if absf(p.x) < Deep.FLAT_R and i != 1:
			_fail("pick row: a side orb under a flat keeper standing in the middle")
	for st in ["mode", "gift"]:
		if Deep.wait_for(st, false) < 15.0 or Deep.wait_for(st, true) < 10.0:
			_fail("pick row: too little time to pick (%s)" % st)
	if Deep.DWELL < 0.15 or Deep.DWELL > 0.6:
		_fail("pick row: a glove must stay a moment, not long")


func _corner() -> void:
	var prev := 0
	for goals in 40:
		var c := Deep.corner(goals)
		if c < prev:
			_fail("the corner shrinks at %d star goals" % goals)
		prev = c
	if Deep.corner(Deep.CORNER_EVERY * Deep.CORNER.size()) != Deep.CORNER.size():
		_fail("the corner never finishes")
	for i in Deep.CORNER.size():
		var p := Deep.corner_spot(i)
		if absf(p.x) < MatchGen.GOAL_HALF + 4.5:
			_fail("corner piece %d stands by the goal" % i)
		if p.distance_to(MatchGen.LEO) < 2.5:
			_fail("corner piece %d stands on Leo" % i)
		for k in MatchGen.PRIZE_KEEP:
			if p.distance_to(MatchGen.prize_slot(k)) < 1.0:
				_fail("corner piece %d stands on prize %d" % [i, k])
		for k in MatchGen.CUBS_MAX:
			if p.distance_to(MatchGen.cub_slot(k)) < 1.0:
				_fail("corner piece %d stands on cub %d" % [i, k])
		for j in i:
			if p.distance_to(Deep.corner_spot(j)) < 1.4:
				_fail("corner pieces %d and %d overlap" % [i, j])


func _fail(msg: String) -> void:
	fails += 1
	printerr("SCRIPT ERROR: " + msg)