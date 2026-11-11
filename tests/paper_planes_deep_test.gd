extends SceneTree
## PAPER PLANES second pass validator (no game, no window): games/paper_planes/deep.gd.
##   godot-test --headless --path . -s res://tests/paper_planes_deep_test.gd      (SEEDS=40 for more)
## Proves, for every mode, season and flight length over many seeds:
##   - every sky event is fair (deep.gd problems(): gusts and geese inside the sky the planes fly in, never at the VR
##     deck, never at the start of a flight or still going at its end, never two at once, always time to fly out
##     while told, a gust never pushes a plane out of the sky) and the same every time, and unchanged over the network;
##   - GENTLE <= BRAVE <= HARD: the mode table (deep.gd ordered()) AND what the flights really get (events a flight,
##     warning seconds, how far a gust pushes, star goals);
##   - Pip's folds: three different unlocked ones, the newest among them, not the last again when there are others,
##     every picture drawn, short names, every breeze underneath real; every fold opens as the hangar grows;
##   - the seasons: each has drifting things, a picture and a line;
##   - the pick row: every orb inside the sky the TV planes fly in and in the VR thrower's reach, far enough apart that
##     one plane never takes two, and the wait is long enough to fly there;
##   - Pip's hangar: only grows, every piece out of the sky the planes fly in, clear of the valley's places and of
##     each other;
##   - every key colour stands out (core/contrast.gd, games/paper_planes/palette.gd);
##   - fast: well under 100 ms a flight (a Deck builds one when a flight starts).
## Prints "SCRIPT ERROR: ..." for each failure and "PLANES DEEP: PASS" / "FAIL".

const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/paper_planes/deep.gd")
const SkyGen := preload("res://games/paper_planes/skygen.gd")
const Story := preload("res://games/paper_planes/story.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const Seeded := preload("res://core/seeded.gd")
const TestTime := preload("res://tests/test_time.gd")

## main.gd PLACES (the valley's places; main.gd is never loaded by a test).
const PLACES := [Vector3(-16.0, 0.0, -3.0), Vector3(16.0, 0.0, -6.0), Vector3(-14.5, 0.0, -17.0), Vector3(14.5, 0.0, -18.0),
	Vector3(-9.0, 10.5, -26.0)]

var fails := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 30
	for w in Deep.ordered():
		_fail("modes: " + str(w))
	for w in Contrast.check_game("paper_planes"):
		_fail("contrast: " + str(w))
	var per := {}
	var checked := 0
	var worst_ms := 0.0
	for mode in PickOrbs.MODE_IDS:
		var sum := {"events": 0, "flights": 0, "warn": 0.0, "drift": 0.0, "gusts": 0, "geese": 0}
		for season in Deep.SEASONS:
			for secs in [100.0, 120.0, 28.0]:
				for s in seeds:
					var fseed := 7100 + s * 6007
					var spec := {"mode": mode, "season": season, "secs": secs}
					var t1 := Time.get_ticks_usec()
					var es := Seeded.derive(fseed, "events")
					var list := Deep.events(es, spec)
					worst_ms = TestTime.worst(worst_ms, (Time.get_ticks_usec() - t1) / 1000.0, func() -> Variant: return Deep.events(Seeded.derive(fseed, "events"), spec))
					checked += 1
					var tag := "%s %s %ds seed %d" % [mode, season, int(secs), fseed]
					for x in Deep.problems(list, spec):
						_fail("%s: %s" % [tag, x])
					if s == 0 and str(Deep.events(es, spec)) != str(list):
						_fail("%s: events differ for the same seed" % tag)
					for e in list:
						if str(Deep.unpack(Deep.pack(e))) != str(e):
							_fail("%s: an event changes over the network" % tag)
						if String(e.kind) == "gust":
							sum.gusts += 1
							sum.drift += float(Deep.MODES[mode].push) * float(Deep.MODES[mode].gust)
						else:
							sum.geese += 1
					if secs == 100.0:
						sum.events += list.size()
						sum.flights += 1
						if list.is_empty():
							_fail("%s: a full flight with no events" % tag)
					sum.warn += float(Deep.MODES[mode].warn)
					# Bots ask for more and earlier events: still fair.
					if s < 3:
						var bspec := {"mode": mode, "season": season, "secs": secs, "scale": 2.0, "first": 3.0}
						for x in Deep.problems(Deep.events(es, bspec), bspec):
							_fail("%s (bot spec): %s" % [tag, x])
		per[mode] = sum
	# GENTLE <= BRAVE <= HARD in what the flights really get.
	var ev := func(m: String) -> float: return float(per[m].events) / maxf(1.0, float(per[m].flights))
	var dr := func(m: String) -> float: return float(per[m].drift) / maxf(1.0, float(per[m].gusts))
	if not (ev.call("gentle") <= ev.call("brave") and ev.call("brave") <= ev.call("hard")):
		_fail("events a flight not gentle <= brave <= hard: %.2f %.2f %.2f" % [ev.call("gentle"), ev.call("brave"), ev.call("hard")])
	if not (dr.call("gentle") <= dr.call("brave") and dr.call("brave") <= dr.call("hard")):
		_fail("gust pushes not gentle <= brave <= hard")
	for m in PickOrbs.MODE_IDS:
		if int(per[m].gusts) == 0 or int(per[m].geese) == 0:
			_fail("%s: gusts %d, geese %d over every flight (both should come)" % [m, per[m].gusts, per[m].geese])
	var g1 := func(m: String) -> int: return int(round(float(Story.goals(2, 1, 0, 0, 100.0)[0]) * float(Deep.MODES[m].goals)))
	if not (g1.call("gentle") <= g1.call("brave") and g1.call("brave") <= g1.call("hard")):
		_fail("star goals not gentle <= brave <= hard")
	if float(Deep.MODES.gentle.warn) <= float(Deep.MODES.hard.warn):
		_fail("gentle doesn't warn longer than hard")
	_check_folds()
	_check_seasons()
	_check_row()
	_check_hangar()
	if worst_ms > 30.0:
		_fail("a flight's events took %.1f ms (Decks build them when a flight starts)" % worst_ms)
	print("PLANES DEEP: %d flights checked in %d ms (worst %.2f ms); events/flight gentle %.1f brave %.1f hard %.1f" % [checked,
		Time.get_ticks_msec() - t0, worst_ms, ev.call("gentle"), ev.call("brave"), ev.call("hard")])
	print("PLANES DEEP: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func _check_folds() -> void:
	var ids := {}
	for f in Deep.FOLDS:
		var id := String(f.id)
		if ids.has(id):
			_fail("fold %s twice" % id)
		ids[id] = true
		if not StoryCard.has_picture(String(f.pic)):
			_fail("fold %s: no picture %s" % [id, f.pic])
		if String(f.name).length() > 12:
			_fail("fold %s: name too long for an orb" % id)
		if String(f.line).length() > 28:
			_fail("fold %s: line too long" % id)
		if not Story.BREEZES.has(String(f.breeze)):
			_fail("fold %s: no breeze %s" % [id, f.breeze])
		if float(f.speed) < Deep.SLOWEST - 0.001:
			_fail("fold %s flies slower than deep.gd SLOWEST (the events' fairness assumes it)" % id)
		if int(f.unlock) > Deep.HANGAR.size():
			_fail("fold %s never opens (needs %d hangar pieces)" % [id, f.unlock])
	if not StoryCard.has_picture(String(Deep.DAILY_ENTRY.pic)):
		_fail("TODAY'S SKY has no picture")
	for pieces in range(0, Deep.HANGAR.size() + 1):
		var un := Deep.unlocked(pieces)
		if un.size() < 3:
			_fail("only %d folds at %d hangar pieces" % [un.size(), pieces])
			continue
		for last in [""] + un:
			for s in 8:
				var ch := Deep.fold_choices(pieces, String(last), 300 + s)
				if ch.size() != 3:
					_fail("fold choices: %d, not 3" % ch.size())
				var seen := {}
				for id in ch:
					if seen.has(id) or not un.has(id):
						_fail("fold choices %s: twice or locked (%d pieces)" % [str(ch), pieces])
					seen[id] = true
				var newest: String = un[un.size() - 1]
				if newest != last and not ch.has(newest):
					_fail("the newest fold %s isn't offered (%d pieces)" % [newest, pieces])
				if un.size() > 3 and String(last) != "" and ch.has(last):
					_fail("the last fold %s offered again (%d pieces)" % [last, pieces])
				if str(ch) != str(Deep.fold_choices(pieces, String(last), 300 + s)):
					_fail("fold choices differ for the same seed")


func _check_seasons() -> void:
	for s in ["spring", "summer", "autumn", "winter"]:
		if not Deep.SEASONS.has(s):
			_fail("no season %s" % s)
			continue
		var sd: Dictionary = Deep.SEASONS[s]
		for k in ["weights", "drift", "pic", "line"]:
			if not sd.has(k):
				_fail("season %s has no %s" % [s, k])
		if not StoryCard.has_picture(String(sd.pic)):
			_fail("season %s: no picture %s" % [s, sd.pic])
		if String(sd.line).length() > 32:
			_fail("season %s: line too long" % s)
		if (sd.weights as Array).size() != Deep.KINDS.size():
			_fail("season %s: weights for every kind" % s)


func _check_row() -> void:
	for n in [3, 4]:
		var spots := Deep.row_spots(n)
		var r := Deep.catch_r()
		for i in spots.size():
			var p: Vector3 = spots[i]
			for ax in 3:
				if p[ax] - r * 0.5 < SkyGen.FLY_MIN[ax] or p[ax] + r * 0.5 > SkyGen.FLY_MAX[ax]:
					_fail("pick orb %d of %d outside the sky the planes fly in (%s)" % [i, n, str(p)])
					break
			if p.y < 2.0:
				_fail("pick orb %d of %d too low (planes skim the grass)" % [i, n])
			if p.distance_to(SkyGen.VR_HEAD) > SkyGen.VR_REACH - 2.0:
				_fail("pick orb %d of %d out of the VR thrower's reach" % [i, n])
			if p.distance_to(SkyGen.VR_HEAD) < 6.0:
				_fail("pick orb %d of %d in the VR thrower's face" % [i, n])
			for j in range(i + 1, spots.size()):
				if p.distance_to(spots[j]) < 2.0 * r + 0.5:
					_fail("pick orbs %d and %d of %d too close (one plane takes two)" % [i, j, n])
		# A plane from anywhere in the sky reaches the furthest orb well inside the wait (turning included).
		var far := 0.0
		for p in spots:
			for c in [SkyGen.FLY_MIN, SkyGen.FLY_MAX, Vector3(SkyGen.FLY_MIN.x, SkyGen.FLY_MAX.y, SkyGen.FLY_MAX.z)]:
				far = maxf(far, (p as Vector3).distance_to(c))
		var secs := (far + PI * SkyGen.TURN_R) / (Deep.FLY_SPEED * Deep.SLOWEST)
		if secs > Deep.ROW_WAIT * 0.6:
			_fail("the pick wait is too short to fly to an orb (%.1f s)" % secs)


func _check_hangar() -> void:
	var last := 0
	for st in range(0, 80):
		var n := Deep.hangar(st)
		if n < last:
			_fail("the hangar shrank at %d stamps" % st)
		last = n
	if Deep.hangar(9999) != Deep.HANGAR.size():
		_fail("the hangar never finishes")
	var ground: Array = []
	for i in Deep.HANGAR.size():
		var p := Deep.hangar_spot(i)
		var kind := Deep.HANGAR[i]
		if kind == "trail":
			if p.y < SkyGen.FLY_MAX.y + 2.0:
				_fail("sky trail plane %d in the sky the planes fly in (y %.1f)" % [i, p.y])
			continue
		if p.y > 0.01:
			_fail("hangar piece %d floats" % i)
		var tall := 5.5 if kind == "shed" else 4.2
		var half := 3.2 if kind == "shed" else 0.8
		if p.z + half > SkyGen.FLY_MIN.z and tall > SkyGen.FLY_MIN.y and kind != "plane":
			_fail("hangar piece %d (%s) pokes into the sky the planes fly in" % [i, kind])
		if kind == "plane" and p.z > SkyGen.FLY_MIN.z + 1.5:
			_fail("parked plane %d out in the valley (z %.1f)" % [i, p.z])
		for pl in PLACES:
			if Vector2(p.x, p.z).distance_to(Vector2((pl as Vector3).x, (pl as Vector3).z)) < half + 5.0:
				_fail("hangar piece %d (%s) on top of a valley place" % [i, kind])
		for g in ground:
			var d := Vector2(p.x, p.z).distance_to(Vector2((g[0] as Vector3).x, (g[0] as Vector3).z))
			if d < half + float(g[1]) + 0.3:
				_fail("hangar pieces %d and %d overlap (%.1f m)" % [i, int(g[2]), d])
		ground.append([p, half, i])


func _fail(msg: String) -> void:
	fails += 1
	print("SCRIPT ERROR: PLANES DEEP: " + msg)
