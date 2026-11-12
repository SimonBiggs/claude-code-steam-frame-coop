extends SceneTree
## STARSHIP CREW second pass validator (no game, no window): games/starship_crew/deep.gd.
##   godot-test --headless --path . -s res://tests/starship_crew_deep_test.gd      (SEEDS=200 for more; GEN_QUICK=1 samples)
## Proves, for every mode, season, mission kind and tier over many mission laps (and bot laps with early surprises, and
## TODAY'S MISSION over 400+ days):
##   - the surprises are fair (deep.gd problems(): none on the lessons trip or a lap's first seconds, never two at once,
##     never past the lap, told long enough for the ship to slide out from the worst spot inside (its middle, a
##     stream's ends at space's edges) from a standing start, always a way out inside space, never over a ring arriving
##     while it is told or going off, and a pilot hit by every surprise still fills the dashboard from the rings alone),
##     the same every time and unchanged over the network;
##   - GENTLE <= BRAVE <= HARD: the mode table (deep.gd ordered()) AND what the laps really get (surprises a lap,
##     warning seconds, stream width, flare size, mission tier, stars a hit costs); GENTLE hits cost nothing;
##   - the missions in every mode still pass missiongen.gd check();
##   - the ship modules: three different unlocked ones, the newest among them, not the last again when there are others,
##     every picture drawn, short names; every module opens within a few trips; TURBO / TRACTOR / MEGA really help and
##     the BUBBLE SHIELD really stops a hit costing stars;
##   - the seasons: each sector has a name, dust, a picture, a short line and both surprises (summer more flares, autumn
##     more rock streams); every date has a sector; the sector islands float far outside space;
##   - the pick row: the orbs sit inside space (the ship can line up with each), never two at once, not lined up with a
##     ship on its usual line, and on a Deck-wide screen wherever the ship is;
##   - the crew friends: only grow, finish, pictures drawn, pods clear of the ship and wing turrets, on a Deck-wide
##     screen and out of the pilot's view straight ahead;
##   - every key colour stands out (core/contrast.gd, games/starship_crew/palette.gd);
##   - fast: a lap's surprises are planned and checked well under 100 ms (a Deck plans one between laps).
## Prints "SCRIPT ERROR: ..." for each failure and "STARSHIP DEEP: PASS" / "FAIL".

const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/starship_crew/deep.gd")
const MissionGen := preload("res://games/starship_crew/missiongen.gd")
const Space := preload("res://games/starship_crew/space.gd")
const Story := preload("res://games/starship_crew/story.gd")
const Art := preload("res://games/starship_crew/art.gd")
const SeasonScript := preload("res://games/starship_crew/season.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const Seeded := preload("res://core/seeded.gd")
const TestTime := preload("res://tests/test_time.gd")

const DECK_ASPECT := 1.6  # a Deck is 16:10 (narrower than the TV's 16:9: same height, less width)

var fails := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var seeds := Seeded.test_count(24, 6)
	for w in Deep.ordered():
		_fail("modes: " + str(w))
	for w in Contrast.check_game("starship_crew"):
		_fail("contrast: " + str(w))
	_expect(is_equal_approx(Deep.STEER, 5.0) and Deep.STEER == MissionGen.STEER, "deep.gd steers like main.gd")
	var per := {}
	var per_season := {}  # season -> [streams, flares] over every mode
	var checked := 0
	var worst_ms := 0.0
	for mode in PickOrbs.MODE_IDS:
		var sum := {"laps": 0, "hz": 0, "stream": 0, "flare": 0, "tier": 0.0, "sw": 0.0, "fr": 0.0, "warn": 0.0, "lose": 0.0}
		var by_season := {}
		for season in Deep.SEASONS:
			var kinds := {"stream": 0, "flare": 0}
			for s in seeds:
				for kind in Story.POOL + ["home"]:
					var base := 1 + (s % (MissionGen.TIERS - 1))
					var tier := Deep.tier(base, mode)
					for lap in [0, 1]:
						var plan := MissionGen.generate(9100 + s * 7919, String(kind), tier, lap)
						var spec := {"mode": mode, "season": season, "trip": base}
						var t1 := Time.get_ticks_usec()
						var list := Deep.hazards(plan, spec)
						var why := Deep.problems(plan, list, spec)
						worst_ms = TestTime.worst(worst_ms, (Time.get_ticks_usec() - t1) / 1000.0, func() -> Variant:
							return Deep.problems(plan, Deep.hazards(plan, spec), spec))
						checked += 1
						var tag := "%s %s %s tier %d seed %d lap %d" % [mode, season, kind, tier, s, lap]
						for x in why:
							_fail("%s: %s" % [tag, x])
						if lap == 0 and season == "spring":
							for x in MissionGen.check(plan):
								_fail("%s: mission: %s" % [tag, x])
						if s % 4 == 0 and str(Deep.hazards(plan, spec)) != str(list):
							_fail("%s: surprises differ for the same lap" % tag)
						for e in list:
							if str(Deep.unpack(Deep.pack(e))) != str(_rounded(e)):
								_fail("%s: a surprise changes over the network" % tag)
							kinds[String(e.kind)] += 1
							sum.hz += 1
							sum.warn += float(e.warn)
							if String(e.kind) == "stream":
								sum.stream += 1
								sum.sw += float(e.w)
							else:
								sum.flare += 1
								sum.fr += float(e.w)
						sum.laps += 1
						sum.tier += tier
						sum.lose += Deep.lose(mode, "")
				# Bots (SC_SURPRISES_NOW): the first lap's surprises from 3 s on: still fair, and there are some.
				var bplan := MissionGen.generate(5000 + s * 31, "mixed", Deep.tier(1, mode), 0)
				var bspec := {"mode": mode, "season": season, "trip": 1, "first": Deep.SHORT_FIRST}
				var bl := Deep.hazards(bplan, bspec)
				for x in Deep.problems(bplan, bl, bspec):
					_fail("%s %s seed %d (bot lap): %s" % [mode, season, s, x])
				if s < 3 and bl.is_empty():
					_fail("%s %s seed %d: a bot lap has no surprise to test" % [mode, season, s])
			by_season[season] = kinds
		var r := maxf(1.0, sum.laps)
		per[mode] = {"hz": sum.hz / r, "warn": sum.warn / maxf(1.0, sum.hz), "sw": sum.sw / maxf(1.0, sum.stream),
			"fr": sum.fr / maxf(1.0, sum.flare), "tier": sum.tier / r, "lose": sum.lose / r}
		print("STARSHIP DEEP %s: %.2f surprises a lap, told %.1f s, streams %.1f m wide, flares r %.1f, tier %.1f, a hit costs %.0f (%d streams, %d flares)" % [
			mode, per[mode].hz, per[mode].warn, per[mode].sw * 2.0, per[mode].fr, per[mode].tier, per[mode].lose, sum.stream, sum.flare])
		if sum.stream == 0 or sum.flare == 0:
			_fail("%s: never a rock stream or never a flare" % mode)
		_expect(int(by_season.summer.flare) > int(by_season.autumn.flare) and int(by_season.autumn.stream) > int(by_season.summer.stream),
			"%s: summer has more flares, autumn more rock streams (%s)" % [mode, str(by_season)])
		for season in by_season:
			var all_s := 0
			var all_f := 0
			all_s += int(by_season[season].stream)
			all_f += int(by_season[season].flare)
			per_season[season] = [int(per_season.get(season, [0, 0])[0]) + all_s, int(per_season.get(season, [0, 0])[1]) + all_f]
	for season in per_season:
		_expect(int(per_season[season][0]) > 0 and int(per_season[season][1]) > 0, "%s: both surprises happen (%s)" % [season, str(per_season[season])])
	var g: Dictionary = per.gentle
	var b: Dictionary = per.brave
	var h2: Dictionary = per.hard
	for k in ["hz", "sw", "fr", "tier", "lose"]:
		if not (float(g[k]) <= float(b[k]) + 0.001 and float(b[k]) <= float(h2[k]) + 0.001):
			_fail("real laps: %s not gentle <= brave <= hard (%.2f %.2f %.2f)" % [k, g[k], b[k], h2[k]])
	if not (float(g.warn) >= float(b.warn) and float(b.warn) >= float(h2.warn)):
		_fail("real laps: warnings not longest on gentle")
	_expect(float(g.hz) >= 0.6, "gentle laps still have surprises (%.2f)" % float(g.hz))
	_expect(Deep.hazards(MissionGen.generate(77, "mixed", 0, 0), {"mode": "hard", "trip": 0}).is_empty(), "no surprises on the lessons trip")
	_escape()
	_daily()
	_gifts()
	_seasons()
	_row()
	_crew()
	print("STARSHIP DEEP: %d laps checked, %.1f ms worst, %d ms total" % [checked, worst_ms, Time.get_ticks_msec() - t0])
	if worst_ms > 100.0:
		_fail("a lap's surprises took %.0f ms to plan and check (a Deck must stay well under 100 ms)" % worst_ms)
	print("STARSHIP DEEP: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func _rounded(e: Dictionary) -> Dictionary:
	return {"kind": String(e.kind), "x": float(e.x), "y": float(e.y), "w": float(e.w), "vert": int(e.vert), "warn": float(e.warn), "t": float(e.t)}


## The escape really works: from anywhere inside a surprise, the escape point is outside the hit zone, inside space,
## and a ship flying there (main.gd's steering: accelerate to STEER) gets out before it goes off.
func _escape() -> void:
	for mode in PickOrbs.MODE_IDS:
		var md := Deep.mode_data(mode)
		for kind in Deep.KINDS:
			for i in 40:
				var r := Seeded.rng(600 + i, "escape %s %s" % [mode, kind])
				var e := Deep._make(r, kind, 20.0, md)
				for k in 12:
					var p := Vector2(r.randf_range(-Space.LIMIT.x, Space.LIMIT.x), r.randf_range(-Space.LIMIT.y, Space.LIMIT.y))
					if not Deep.inside(e, p):
						continue
					var q := Deep.escape(e, p)
					if q == Vector2.INF:
						continue  # (problems() refuses a surprise with no way out from its worst spots)
					if Deep.inside(e, q):
						_fail("%s %s: the escape %s is still inside" % [mode, kind, q])
					if absf(q.x) > Space.LIMIT.x or absf(q.y) > Space.LIMIT.y:
						_fail("%s %s: the escape %s is outside space" % [mode, kind, q])
					# fly it like main.gd: react, then accelerate towards it
					var pos := p
					var vel := Vector2.ZERO
					var t := 0.0
					while t < float(e.warn) and Deep.inside(e, pos):
						if t >= Deep.REACT:
							vel = vel.move_toward((q - pos).limit_length(1.0) * Deep.STEER * minf(1.0, (q - pos).length() / 0.4), Deep.ACCEL * 0.02)
						pos += vel * 0.02
						t += 0.02
					if Deep.inside(e, pos) and Deep.escape_time(e, p) <= float(e.warn):
						_fail("%s %s: a ship at %s can't really get out in %.1f s" % [mode, kind, p, float(e.warn)])


## TODAY'S MISSION over 400+ days: its laps and surprises are fair in every mode (it keeps its own tier).
func _daily() -> void:
	var rs := Seeded.validate_days(func(date: String) -> Dictionary:
			var m := Story.daily_mission(date)
			var laps := {}
			for mode in PickOrbs.MODE_IDS:
				for lap in [0, 1]:
					var plan := MissionGen.generate(int(m.s), String(m.k), Deep.tier(int(m.tier), mode, true), lap)
					laps["%s/%d" % [mode, lap]] = [plan, Deep.hazards(plan, {"mode": mode, "season": Seeded.season(date), "trip": 1})]
			return {"m": m, "laps": laps, "season": Seeded.season(date)},
		func(d: Dictionary) -> Array:
			var why: Array = []
			for key in d.laps:
				var plan: Dictionary = d.laps[key][0]
				var mode := String(key).get_slice("/", 0)
				for x in MissionGen.check(plan):
					why.append("%s: mission: %s" % [key, x])
				for x in Deep.problems(plan, d.laps[key][1], {"mode": mode, "season": d.season, "trip": 1}):
					why.append("%s: %s" % [key, x])
				if int(plan.tier) != int(d.m.tier):
					why.append("%s: TODAY'S MISSION changed tier with the mode" % key)
			if not Deep.SEASONS.has(String(d.season)):
				why.append("no star sector for %s" % d.season)
			return why, 400, "TODAY'S MISSION SURPRISES", ["2026-11-12", "2026-12-25"])
	fails += (rs.failures as Array).size()
	print("STARSHIP DEEP: %d days of TODAY'S MISSION checked" % int(rs.checked))


func _gifts() -> void:
	var ids: Array = []
	for gd in Deep.GIFTS:
		ids.append(String(gd.id))
		if not StoryCard.has_picture(String(gd.pic)):
			_fail("module %s: no picture %s" % [gd.id, gd.pic])
		if String(gd.name).length() > 14 or String(gd.line).length() > 20:
			_fail("module %s: name or line too long" % gd.id)
		if int(gd.unlock) > Story.PARTS.size() or int(gd.unlock) > 5:  # station parts: one a trip home
			_fail("module %s takes too long to open" % gd.id)
	_expect(Deep.unlocked(0).size() >= 3, "three modules from the start")
	_expect(Deep.steer_speed("turbo") > Deep.steer_speed("") * 1.3 and Deep.accel("turbo") > Deep.accel(""), "TURBO steers clearly faster")
	_expect(Deep.pull_r("tractor") > Deep.pull_r("") * 1.4 and Deep.pull("tractor") > Deep.pull("") and Deep.pull_z("tractor") < Deep.pull_z(""), "the TRACTOR BEAM pulls from further")
	_expect(Deep.zap_tol("mega") > Deep.zap_tol("") * 1.5, "the MEGA LASER zaps much more easily")
	_expect(Deep.extra_star("boost") == 1 and Deep.extra_star("") == 0, "STAR BOOST adds a star")
	for mode in PickOrbs.MODE_IDS:
		_expect(Deep.lose(mode, "shield") == 0 and Deep.dizzy(mode, "shield") == 0.0, "%s: the BUBBLE SHIELD stops a hit" % mode)
	for parts in range(0, Story.PARTS.size() + 1):
		var un := Deep.unlocked(parts)
		for last in [""] + ids:
			for s in 6:
				var ch := Deep.gift_choices(parts, String(last), 300 + s * 7)
				var tag := "modules (parts %d, last %s, seed %d)" % [parts, last, s]
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
					_fail("%s: the newest module is missing" % tag)
				if un.size() > 3 and ch.has(last):
					_fail("%s: the last module again" % tag)
				if str(ch) != str(Deep.gift_choices(parts, String(last), 300 + s * 7)):
					_fail("%s: choices differ for the same seed" % tag)


func _seasons() -> void:
	for s in Deep.SEASONS:
		var sd: Dictionary = Deep.SEASONS[s]
		_expect(String(sd.name).length() <= 14 and String(sd.line).length() <= 24, "%s: short sector name and line" % s)
		_expect(StoryCard.has_picture(String(sd.pic)), "%s: picture %s is drawn" % [s, sd.pic])
		_expect((sd.weights as Array).size() == Deep.KINDS.size(), "%s: a weight for each surprise" % s)
	for m in 12:
		var date := "2026-%02d-15" % (m + 1)
		_expect(Deep.SEASONS.has(Seeded.season(date)), "a star sector for %s" % date)
	for p in SeasonScript.ISLANDS:
		_expect(absf(p.x) > Space.LIMIT.x + Deep.ORB_SCALE * PickOrbs.HIT_R + 8.0, "a sector island floats far outside space (%s)" % p)
	for k in Deep.KIND_PICS:
		_expect(StoryCard.has_picture(String(Deep.KIND_PICS[k])), "surprise %s has a picture" % k)
	_expect(Deep.STREAM_COLOR != Deep.FLARE_COLOR, "the surprises have their own colours")


## Where a world point shows on a Deck-wide screen (TV camera, 16:10): uv, |x| and |y| < 1 = on screen.
func _deck_uv(w: Vector3) -> Vector2:
	var uv := MissionGen.project(w)
	return Vector2(uv.x * MissionGen.ASPECT / DECK_ASPECT, uv.y)


func _row() -> void:
	var spots := Deep.row_spots(3)
	for i in spots.size():
		var p: Vector2 = spots[i]
		_expect(absf(p.x) <= Space.LIMIT.x - 0.5 and absf(p.y) <= Space.LIMIT.y - 0.5, "orb %d sits inside space (the ship can line up with it)" % i)
		for j in range(i + 1, spots.size()):
			_expect(p.distance_to(spots[j]) > Deep.LINE_R * 2.0 + 0.5, "orbs %d and %d are never lined up at once" % [i, j])
		_expect(Deep.lined_up(spots, Vector2(p.x, 0.0)) < 0, "a ship on its usual line isn't resting on orb %d" % i)
		_expect(Deep.lined_up(spots, p) == i, "a ship at orb %d is lined up with it" % i)
		for off in [Vector2.ZERO, Space.LIMIT, -Space.LIMIT, Vector2(Space.LIMIT.x, -Space.LIMIT.y), Vector2(-Space.LIMIT.x, Space.LIMIT.y)] + spots:
			var o: Vector2 = off
			var w := Vector3(p.x - o.x, p.y - o.y + Space.SHIP_Y, Deep.ROW_Z)
			var uv := _deck_uv(w)
			var rad := Deep.orb_r() / 12.0
			_expect(absf(uv.x) < 0.95 - rad and absf(uv.y) < 0.9 - rad, "orb %d is on a Deck screen with the ship at %s (%s)" % [i, o, uv])
	_expect(Deep.wait_for("mode", true) < Deep.wait_for("mode", false), "nobody to pick: the middle comes sooner")


func _crew() -> void:
	var last := -1
	for m in 60:
		var n := Deep.crew(m)
		_expect(n >= last and n <= Deep.CREW.size(), "the crew only grows (%d missions)" % m)
		last = n
	_expect(Deep.crew(Deep.CREW.size() * Deep.CREW_EVERY) == Deep.CREW.size(), "every crew friend joins")
	_expect(Deep.CREW_SPOTS.size() >= Deep.CREW.size(), "a pod spot for every friend")
	for i in Deep.CREW.size():
		var f: Dictionary = Deep.CREW[i]
		_expect(StoryCard.has_picture(String(f.pic)), "crew %s: picture %s" % [f.id, f.pic])
		_expect(("%s joins the crew!" % String(f.name)).length() <= 24, "crew %s: a short line" % f.id)
		var p: Vector3 = Deep.CREW_SPOTS[i]
		_expect(absf(p.x) > 3.6 + 0.24 + 0.9, "crew pod %d clear of the ship's wing turrets" % i)
		var uv := _deck_uv(p)
		_expect(absf(uv.x) < 0.9 and absf(uv.y) < 0.88, "crew pod %d is on a Deck screen (%s)" % [i, uv])
		var eye := Vector3(0.0, 1.2, 0.12)
		var ang := rad_to_deg((p - eye).angle_to(Vector3.FORWARD))
		_expect(ang > 22.0, "crew pod %d stays out of the pilot's view straight ahead (%.0f deg)" % [i, ang])
		for j in range(i + 1, Deep.CREW.size()):
			_expect(p.distance_to(Deep.CREW_SPOTS[j]) > 1.8, "crew pods %d and %d don't bump" % [i, j])


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(msg: String) -> void:
	fails += 1
	if fails <= 60:
		print("SCRIPT ERROR: %s" % msg)