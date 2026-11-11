extends SceneTree
## DRAGON RIDER second pass validator (no game, no window): games/dragon_rider/deep.gd.
##   godot-test --headless --path . -s res://tests/dragon_rider_deep_test.gd      (SEEDS=40 for more)
## Proves, for every mode over every stage, mission, season and many seeds:
##   - every sky event is fair against its own route (deep.gd problems(): a storm cloud can be flown round while it is
##     told, clear of rings, stars, bunnies, balloons and the golden balloon; after a crosswind there is time to steer
##     back into the next ring; never two at once; none on a Storm King stage or stage 1) and the same every time;
##   - GENTLE <= BRAVE <= HARD: the mode table (deep.gd ordered()) AND what the stages really get (events a stage,
##     warning seconds, cloud size, how far a gust pushes);
##   - Sunny's gifts: three different unlocked ones, the newest among them, not the last again when there are others,
##     every picture drawn, short names; every gift hatches within a few weeks of play;
##   - the seasons: each has island colours, drifting things, a picture and a line;
##   - the pick row: flying straight passes under every orb (a pick is always deliberate), every orb can be reached at
##     every stage's cruise, orbs far enough apart that Sunny takes one at a time;
##   - the roost: baby dragons fly clear of the deck, the rail and each other; the flock only grows;
##   - every key colour stands out (core/contrast.gd, games/dragon_rider/palette.gd);
##   - fast: well under 100 ms a stage (a Deck builds one between stages).
## Prints "SCRIPT ERROR: ..." for each failure and "DRAGON DEEP: PASS" / "FAIL".

const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/dragon_rider/deep.gd")
const RouteGen := preload("res://games/dragon_rider/routegen.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const Seeded := preload("res://core/seeded.gd")

const MISSIONS: Array[String] = ["rings", "rescue", "race", "boss"]

var fails := 0


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 4
	for w in Deep.ordered():
		_fail("modes: " + str(w))
	for w in Contrast.check_game("dragon_rider"):
		_fail("contrast: " + str(w))
	var per := {}
	var checked := 0
	var worst_ms := 0.0
	var total_us := 0
	for mode in PickOrbs.MODE_IDS:
		var sum := {"events": 0, "stages": 0, "warn": 0.0, "cloud": 0.0, "clouds": 0, "drift": 0.0, "winds": 0}
		for season in Deep.SEASONS:
			for lv in range(1, RouteGen.MAX_STAGE + 1):
				for mission in MISSIONS:
					for s in seeds:
						var seed_v: int = RouteGen.stage_seed(9100 + s * 977, lv) + MISSIONS.find(mission)
						var origin := Vector3(s * 13.0, 45.0, -s * 7.0)
						var yaw := s * 0.7
						var t1 := Time.get_ticks_usec()
						var route := RouteGen.route(seed_v, origin, yaw, lv, mission, true)
						var spec := {"mode": mode, "season": season, "level": lv}
						var list := Deep.events(Seeded.derive(seed_v, "events"), route, spec)
						var us := Time.get_ticks_usec() - t1
						total_us += us
						worst_ms = maxf(worst_ms, us / 1000.0)
						checked += 1
						var tag := "%s %s stage %d %s seed %d" % [mode, season, lv, mission, seed_v]
						for x in Deep.problems(list, route, spec):
							_fail("%s: %s" % [tag, x])
						if s == 0 and str(Deep.events(Seeded.derive(seed_v, "events"), RouteGen.route(seed_v, origin, yaw, lv, mission, true), spec)) != str(list):
							_fail("%s: events differ for the same seed" % tag)
						if (lv < Deep.FIRST_STAGE or mission == "boss") and not list.is_empty():
							_fail("%s: events on a calm stage" % tag)
						for e in list:
							var back := Deep.unpack(Deep.pack(e))
							if str(back) != str(e):
								_fail("%s: an event changes over the network" % tag)
						if lv >= 3 and mission != "boss":
							sum.stages += 1
							sum.events += list.size()
							for e in list:
								sum.warn += float(Deep.mode_data(mode).warn)
								if String(e.kind) == "storm":
									sum.clouds += 1
									sum.cloud += float((e.size as Vector2).x)
								else:
									sum.winds += 1
									sum.drift += float(Deep.mode_data(mode).push) * float(Deep.mode_data(mode).gust)
		var stages := maxf(1.0, sum.stages)
		per[mode] = {"events": sum.events / stages, "warn": sum.warn / maxf(1.0, sum.events),
			"cloud": sum.cloud / maxf(1.0, sum.clouds), "drift": sum.drift / maxf(1.0, sum.winds),
			"storms": sum.clouds, "winds": sum.winds}
		print("DRAGON DEEP %s: %.2f events a stage, told %.1f s, clouds r %.1f m, gusts push %.1f m (%d storms, %d winds)" % [mode,
			per[mode].events, per[mode].warn, per[mode].cloud, per[mode].drift, sum.clouds, sum.winds])
	var g: Dictionary = per.gentle
	var b: Dictionary = per.brave
	var h: Dictionary = per.hard
	for k in ["events", "cloud", "drift"]:
		if not (float(g[k]) <= float(b[k]) + 0.001 and float(b[k]) <= float(h[k]) + 0.001):
			_fail("real stages: %s not gentle <= brave <= hard (%.2f %.2f %.2f)" % [k, g[k], b[k], h[k]])
	if not (float(g.warn) >= float(b.warn) and float(b.warn) >= float(h.warn)):
		_fail("real stages: warnings not longest on gentle")
	for m in per:
		if float(per[m].events) < 0.5:
			_fail("%s: hardly any sky events (%.2f a stage)" % [m, per[m].events])
		if int(per[m].storms) == 0 or int(per[m].winds) == 0:
			_fail("%s: never a storm or never a crosswind" % m)
	_gifts()
	_seasons()
	_row()
	_roost()
	var avg_ms := total_us / 1000.0 / maxf(1.0, checked)
	print("DRAGON DEEP: %d stages checked, %.2f ms avg, %.1f ms worst, %d ms total" % [checked, avg_ms, worst_ms, Time.get_ticks_msec() - t0])
	if worst_ms > 100.0:
		_fail("a stage took %.0f ms to make (a Deck must stay well under 100 ms)" % worst_ms)
	print("DRAGON DEEP: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func _gifts() -> void:
	var ids: Array = []
	for gd in Deep.GIFTS:
		ids.append(String(gd.id))
		if not StoryCard.has_picture(String(gd.pic)):
			_fail("gift %s: no picture %s" % [gd.id, gd.pic])
		if String(gd.name).length() > 14 or String(gd.line).length() > 20:
			_fail("gift %s: name or line too long" % gd.id)
		if int(gd.unlock) > Deep.MAX_BABIES:
			_fail("gift %s never hatches" % gd.id)
		# Stages to hatch it: a few weeks of play (about 6 stages a day).
		if int(gd.unlock) * Deep.HATCH_EVERY > 6 * 14:
			_fail("gift %s takes too long to unlock" % gd.id)
	for babies in range(0, Deep.MAX_BABIES + 1):
		var un := Deep.unlocked(babies)
		for last in [""] + ids:
			for s in 6:
				var ch := Deep.gift_choices(babies, String(last), 300 + s * 7)
				var tag := "gifts (babies %d, last %s, seed %d)" % [babies, last, s]
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
				if str(ch) != str(Deep.gift_choices(babies, String(last), 300 + s * 7)):
					_fail("%s: choices differ for the same seed" % tag)


func _seasons() -> void:
	for s in ["spring", "summer", "autumn", "winter"]:
		if not Deep.SEASONS.has(s):
			_fail("no %s" % s)
			continue
		var sd: Dictionary = Deep.SEASONS[s]
		for k in ["grass", "crown", "rock", "drift", "pic", "line", "weights"]:
			if not sd.has(k):
				_fail("season %s has no %s" % [s, k])
		if not StoryCard.has_picture(String(sd.pic)):
			_fail("season %s: no picture %s" % [s, sd.pic])
		if String(sd.line).length() > 20:
			_fail("season %s: line too long" % s)
	for date in ["2026-01-10", "2026-04-10", "2026-07-10", "2026-10-10"]:
		if not Deep.SEASONS.has(Seeded.season(date)):
			_fail("no lands for %s" % Seeded.season(date))


func _row() -> void:
	var catch := Deep.catch_r()
	# Sunny's middle is 1 m under her saddle (dragon.gd core_position): flying straight passes under every orb.
	if Deep.ROW_UP + 1.0 < catch + 1.0:
		_fail("pick row: flying straight would take the middle orb (%.1f m up, catch %.1f m)" % [Deep.ROW_UP, catch])
	if Deep.ROW_GAP < catch * 2.0 + 1.0:
		_fail("pick row: orbs too close (Sunny could take two)")
	for lv in range(1, RouteGen.MAX_STAGE + 1):
		var v := RouteGen.cruise(lv)
		var secs := Deep.ROW_SECS - Deep.REACT
		var side := Deep.lateral(secs, v)
		var up := Deep.climb(secs)
		if side < Deep.ROW_GAP - catch + 1.0 or up < Deep.ROW_UP + 1.0 - catch + 1.0:
			_fail("pick row at stage %d: an outer orb is out of reach (%.0f m across, %.0f m up)" % [lv, side, up])
	var spots := Deep.row_spots(Vector3(0, 40, 0), 0.4, 10.0)
	if spots.size() != 3 or absf((spots[0] as Vector3).y - (spots[2] as Vector3).y) > 0.01:
		_fail("pick row: orbs not level (pick_orbs keeps one height)")
	if Deep.ROW_WAIT < Deep.ROW_SECS + 2.0:
		_fail("pick row: the wait ends before Sunny gets there")


func _roost() -> void:
	var last := 0
	for n in 400:
		var b := Deep.babies(n)
		if b < last:
			_fail("the flock shrank at %d stages" % n)
		last = b
	if Deep.babies(9999) != Deep.MAX_BABIES:
		_fail("the flock never fills")
	for i in Deep.MAX_BABIES:
		var p := Deep.baby_spot(i)
		if absf(p.x) < 3.5:
			_fail("baby %d flies over the deck" % i)
		if p.distance_to(RouteGen.charm_slot(0)) < 2.0:
			_fail("baby %d in the charms" % i)
		for j in i:
			if p.distance_to(Deep.baby_spot(j)) < 1.8:
				_fail("babies %d and %d bump" % [i, j])


func _fail(what: String) -> void:
	fails += 1
	if fails <= 40:
		print("SCRIPT ERROR: DRAGON DEEP: " + what)
