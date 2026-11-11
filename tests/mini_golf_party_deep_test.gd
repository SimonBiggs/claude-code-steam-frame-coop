extends SceneTree
## MINI GOLF PARTY second pass validator (no game, no window): games/mini_golf_party/deep.gd.
##   godot-test --headless --path . -s res://tests/mini_golf_party_deep_test.gd      (SEEDS=20 for more)
## Proves, for every level, hole, mode and season over many course seeds:
##   - every hole STAYS SINKABLE: the aiming putter (holegen.gd sim) sinks it within par + PAR_SLACK with every mode's
##     cup pull and every one of Gus's gifts (bouncy walls, magnet cup, giant cup ...);
##   - the surprises are fair (deep.gd problems(): told long enough, never two at once, none on the practice putt, a
##     gust never over the cup or the tee, the mole never on the aim line, the cup, a bumper or the windmill / loop,
##     never leaving a pocket by a wall, and the hole still sunk within par + PAR_SLACK with the gust blowing or the
##     mole up THE WHOLE TIME), the same every time and unchanged over the network;
##   - GENTLE <= BRAVE <= HARD: the mode table (deep.gd ordered()) AND what the holes really get (surprises per hole,
##     warning seconds, gust push, mole time, putts the aiming putter needs);
##   - Gus's gifts: three different unlocked ones, the newest among them, not the last again when there are others,
##     every picture drawn, short names; every gift opens within a few weeks of play; the giant cup never touches a wall;
##   - the pick green: passes holegen.gd check(), a putt aimed at each pad rolls onto it in one go (every mode), pads
##     and orbs apart, orbs at waist height, long enough to pick;
##   - the seasons and Gus's garden corner: pictures and lines, the corner only grows, and its pieces and the seasonal
##     things stand clear of every hole, the VR toys, the board, Gus and the garden's ornaments;
##   - every key colour stands out (core/contrast.gd, games/mini_golf_party/palette.gd);
##   - fast: making a hole's surprises (with their proofs) stays well under 100 ms.
## Prints "SCRIPT ERROR: ..." for each failure and "MINI GOLF DEEP: PASS" / "FAIL".

const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/mini_golf_party/deep.gd")
const HoleGen := preload("res://games/mini_golf_party/holegen.gd")
const Course := preload("res://games/mini_golf_party/course.gd")
const Garden := preload("res://games/mini_golf_party/garden.gd")
const Season := preload("res://games/mini_golf_party/season.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const Seeded := preload("res://core/seeded.gd")

var fails := 0


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 8
	for w in Deep.ordered():
		_fail("modes: " + str(w))
	for w in Contrast.check_game("mini_golf_party"):
		_fail("contrast: " + str(w))
	var seasons: Array = Deep.SEASONS.keys()
	var gifts: Array = [""]
	for g in Deep.GIFTS:
		gifts.append(String(g.id))
	var per := {}
	var worst_ms := 0.0
	var holes := 0
	for mode in PickOrbs.MODE_IDS:
		var sum := {"holes": 0, "events": 0, "gusts": 0, "moles": 0, "warn": 0.0, "acc": 0.0, "up": 0.0, "putts": 0}
		for lv in range(1, HoleGen.MAX_LEVEL + 1):
			for s in seeds:
				var cs := 7000 + s * 104729 + lv * 31
				for i in range(1, HoleGen.HOLES):
					var season: String = seasons[(s + i) % seasons.size()]
					var gift: String = gifts[(s + i + lv) % gifts.size()]
					var d := HoleGen.hole(cs, i, lv, func(h: Dictionary) -> bool: return Deep.sinkable(h, mode, gift))
					if int(d.try) < 0:
						_fail("%s lv%d seed %d hole %d needed the classic fallback with %s" % [mode, lv, cs, i + 1, gift])
					var spec := {"mode": mode, "season": season, "gift": gift}
					var tag := "%s lv%d seed %d hole %d (%s, %s, %s)" % [mode, lv, cs, i + 1, d.gimmick, season, gift if gift != "" else "no gift"]
					var t1 := Time.get_ticks_usec()
					var list := Deep.hazards(d, spec)
					var ms := (Time.get_ticks_usec() - t1) / 1000.0
					if ms > worst_ms:
						# a slow one: time it twice more and keep the fastest (a busy machine, not the generator,
						# made one take 42 ms during a landing; tests/gen_budget_test.gd does the same)
						for again in 2:
							var t2 := Time.get_ticks_usec()
							Deep.hazards(d, spec)
							ms = minf(ms, (Time.get_ticks_usec() - t2) / 1000.0)
					worst_ms = maxf(worst_ms, ms)
					holes += 1
					for x in Deep.problems(d, list, spec):
						_fail("%s: %s" % [tag, x])
					if s < 2 and str(Deep.hazards(d, spec)) != str(list):
						_fail("%s: surprises differ for the same hole" % tag)
					for ev in list:
						var back := Deep.unpack(Deep.pack(ev, "warn", 1.0))
						if back.is_empty() or back.p != ev.p or back.dir != ev.dir or String(back.kind) != String(ev.kind):
							_fail("%s: a surprise changes over the network" % tag)
						sum.events += 1
						sum.warn += float(ev.warn)
						if String(ev.kind) == "gust":
							sum.gusts += 1
							sum.acc += float(ev.acc)
						else:
							sum.moles += 1
							sum.up += float(ev.dur)
					# The bots' spec (from hole 2, soon after it starts) is fair too.
					var bot_spec := {"mode": mode, "season": season, "gift": gift, "from": 1, "first_t": 2.0}
					if s == 0:
						for x in Deep.problems(d, Deep.hazards(d, bot_spec), bot_spec):
							_fail("%s (bot spec): %s" % [tag, x])
					# Still sinkable with this mode and EVERY gift (the host picks a try proven for the course's gift).
					for g in (gifts if s == 0 else [gift]):
						var dg := d if String(g) == gift else HoleGen.hole(cs, i, lv, func(h: Dictionary) -> bool: return Deep.sinkable(h, mode, String(g)))
						var r := HoleGen.sim(dg, HoleGen.MAX_PUTTS, Deep.knobs(mode, String(g), dg))
						if not bool(r.sunk) or int(r.putts) > int(d.par) + Deep.PAR_SLACK:
							_fail("%s: with %s the putter needs %s putts (par %d)" % [tag, g if g != "" else "no gift",
								str(r.putts) if bool(r.sunk) else "too many", int(d.par)])
						if String(g) == gift:
							sum.putts += int(r.putts)
					sum.holes += 1
		var n := maxf(1.0, sum.holes)
		var ev_n := maxf(1.0, sum.events)
		per[mode] = {"events": sum.events / n, "warn": sum.warn / ev_n, "acc": sum.acc / maxf(1.0, sum.gusts),
			"up": sum.up / maxf(1.0, sum.moles), "putts": sum.putts / n, "gusts": sum.gusts, "moles": sum.moles,
			"assist": float(Deep.mode_data(mode).assist_r)}
		print("MINI GOLF DEEP %s: %.2f surprises a hole (%d gusts, %d moles), told %.1f s, gust %.2f m/s2, mole up %.1f s, %.2f putts a hole" % [
			mode, per[mode].events, sum.gusts, sum.moles, per[mode].warn, per[mode].acc, per[mode].up, per[mode].putts])
	var g0: Dictionary = per.gentle
	var b0: Dictionary = per.brave
	var h0: Dictionary = per.hard
	for k in ["events", "acc", "up"]:
		if not (float(g0[k]) <= float(b0[k]) + 0.001 and float(b0[k]) <= float(h0[k]) + 0.001):
			_fail("real holes: %s not gentle <= brave <= hard (%.2f %.2f %.2f)" % [k, g0[k], b0[k], h0[k]])
	for k in ["warn", "assist"]:
		if not (float(g0[k]) >= float(b0[k]) - 0.001 and float(b0[k]) >= float(h0[k]) - 0.001):
			_fail("real holes: %s not most on gentle" % k)
	if float(g0.putts) > float(h0.putts) + 0.05:
		_fail("gentle holes need more putts than hard ones (%.2f vs %.2f)" % [g0.putts, h0.putts])
	for m in per:
		if float(per[m].events) < 0.2:
			_fail("%s: hardly any surprises (%.2f a hole)" % [m, per[m].events])
	for m in ["brave", "hard"]:
		if int(per[m].gusts) == 0 or int(per[m].moles) == 0:
			_fail("%s: never a gust or never a mole" % m)
	_practice()
	_gifts()
	_pick_green()
	_seasons_and_corner(seeds)
	print("MINI GOLF DEEP: %d holes checked, surprises %.1f ms worst, %d ms total" % [holes, worst_ms, Time.get_ticks_msec() - t0])
	if worst_ms > 40.0:
		_fail("a hole's surprises took %.0f ms to make here (a Deck is ~3x slower and must stay under 100 ms)" % worst_ms)
	print("MINI GOLF DEEP: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


## No surprise on the practice putt or the pick green, ever.
func _practice() -> void:
	for mode in PickOrbs.MODE_IDS:
		for s in 20:
			var d := HoleGen.hole(9000 + s, 0, 1 + s % HoleGen.MAX_LEVEL)
			if not Deep.hazards(d, {"mode": mode}).is_empty() or not Deep.hazards(d, {"mode": mode, "from": 1, "first_t": 2.0}).is_empty():
				_fail("a surprise on the practice putt (%s)" % mode)
		if not Deep.hazards(Deep.pick_green(), {"mode": mode, "from": 0}).is_empty():
			_fail("a surprise on the pick green")


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
		if int(gd.unlock) * Deep.CORNER_EVERY > 40:  # gold stars: a few a course, a few courses a day
			_fail("gift %s takes too long to open" % gd.id)
	if Deep.MAGNET_R <= Course.ASSIST_R or Deep.BOUNCY_WALL <= Course.WALL_BOUNCE or Deep.GIANT <= 1.2 or Deep.LONG_REACH <= 1.0:
		_fail("a gift barely does anything")
	if Deep.stars_for("rainbow") != 2 or Deep.stars_for("") != 1:
		_fail("the rainbow ball's flowers")
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
	# The giant cup never reaches a wall or a bumper on any hole.
	for lv in range(1, HoleGen.MAX_LEVEL + 1):
		for s in 30:
			for i in HoleGen.HOLES:
				var d := HoleGen.hole(500 + s * 13, i, lv)
				var r := Deep.giant_r(d)
				if r < Course.CUP_R - 0.001:
					_fail("giant cup smaller than a cup")
				if HoleGen.wall_dist(d.outline, d.cup) < r + Deep.GIANT_ROOM - 0.001:
					_fail("giant cup touches a wall (seed %d hole %d)" % [500 + s * 13, i + 1])


func _pick_green() -> void:
	var d := Deep.pick_green()
	for w in HoleGen.check(d):
		_fail("pick green: %s" % w)
	var pads: Array = d.pads
	if pads.size() != 3:
		_fail("pick green: %d pads" % pads.size())
	for i in pads.size():
		for mode in PickOrbs.MODE_IDS:
			var n := Deep.putts_to_pad(d, i, Deep.knobs(mode, "", d))
			if n > 1:
				_fail("pick green: a putt aimed at pad %d (%s) needs %d goes" % [i, mode, n])
		var o := Deep.orb_spot(d, i)
		if o.y < 0.5 or o.y > 1.0:
			_fail("pick green: orb %d not at waist height" % i)
		if Deep.ORB_SCALE * PickOrbs.BALL_R > 0.25:
			_fail("pick green: orbs too big")
		for j in i:
			if (pads[i] as Vector2).distance_to(pads[j]) < Deep.PAD_R * 2.0 + 0.1:
				_fail("pick green: pads %d and %d touch" % [i, j])
			if o.distance_to(Deep.orb_spot(d, j)) < (Deep.ORB_SCALE * PickOrbs.HIT_R + Deep.HAND_R) * 2.0:
				_fail("pick green: one hand reaches two orbs")
		if Deep.pad_at(d, pads[i]) != i:
			_fail("pick green: pad %d isn't found" % i)
	if Deep.pad_at(d, d.tee) >= 0:
		_fail("pick green: the tee is on a pad")
	for st in ["mode", "gift"]:
		if Deep.wait_for(st, false) < 15.0 or Deep.wait_for(st, true) < 12.0:
			_fail("pick green: too little time to pick (%s)" % st)
	if Deep.DWELL < 0.15 or Deep.DWELL > 0.6:
		_fail("pick green: a glove must stay a moment, not long")


func _seasons_and_corner(seeds: int) -> void:
	for s in ["spring", "summer", "autumn", "winter"]:
		if not Deep.SEASONS.has(s):
			_fail("no %s" % s)
			continue
		var sd: Dictionary = Deep.SEASONS[s]
		for k in ["drift", "pic", "line", "weights", "lawn"]:
			if not sd.has(k):
				_fail("season %s has no %s" % [s, k])
		if not StoryCard.has_picture(String(sd.pic)):
			_fail("season %s: no picture %s" % [s, sd.pic])
		if String(sd.line).length() > 20:
			_fail("season %s: line too long" % s)
	for date in ["2026-01-10", "2026-04-10", "2026-07-10", "2026-10-10"]:
		if not Deep.SEASONS.has(Seeded.season(date)):
			_fail("no garden for %s" % Seeded.season(date))
	for p in ["gust", "mole", "gift", "gopher"]:
		if not StoryCard.has_picture(p):
			_fail("no picture %s" % p)
	for k in Deep.CORNER_PICS:
		if not StoryCard.has_picture(String(Deep.CORNER_PICS[k])):
			_fail("corner %s: no picture" % k)
	var prev := 0
	for stars in 120:
		var c := Deep.corner(stars)
		if c < prev:
			_fail("the corner shrinks at %d stars" % stars)
		prev = c
	if Deep.corner(Deep.CORNER_EVERY * Deep.CORNER.size()) != Deep.CORNER.size():
		_fail("the corner never finishes")
	var things: Array = []  # [what, spot, radius]
	for i in Deep.CORNER.size():
		things.append(["corner piece %d" % i, Deep.corner_spot(i), 0.7])
		for j in i:
			if Deep.corner_spot(i).distance_to(Deep.corner_spot(j)) < 1.2:
				_fail("corner pieces %d and %d overlap" % [i, j])
	for i in Season.SPOTS.size():
		things.append(["season thing %d" % i, Season.SPOTS[i], 0.6])
		if Season.SPOTS[i].length() > 7.0:
			_fail("season thing %d is off the lawn" % i)
	for i in things.size():
		for j in i:
			if (things[i][1] as Vector2).distance_to(things[j][1]) < float(things[i][2]) + float(things[j][2]):
				_fail("%s stands on %s" % [things[i][0], things[j][0]])
	var greens: Array = [Deep.pick_green()]
	for lv in range(1, HoleGen.MAX_LEVEL + 1):
		for s in seeds * 2:
			for i in HoleGen.HOLES:
				greens.append(HoleGen.hole(1300 + s * 17 + lv, i, lv))
	for d in greens:
		var poly := PackedVector2Array(d.outline)
		var near: Array = HoleGen.keep_clear(d)
		for sp in Garden.spots(d, Garden.MAX_PIECES):
			near.append([sp, 0.3])
		for th in things:
			var p: Vector2 = th[1]
			var r := float(th[2])
			if Geometry2D.is_point_in_polygon(p, poly) or HoleGen.wall_dist(d.outline, p) < r + 0.3:
				_fail("%s stands by %s hole %d" % [th[0], d.gimmick, int(d.index) + 1])
				continue
			for kc in near:
				if p.distance_to(kc[0]) < r + float(kc[1]):
					_fail("%s stands on something by the hole (%s)" % [th[0], str(kc[0])])
					break


func _fail(msg: String) -> void:
	fails += 1
	printerr("SCRIPT ERROR: " + msg)
