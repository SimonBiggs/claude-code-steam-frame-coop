extends SceneTree
## BALLOON POP second pass validator (no game, no window): games/balloon_pop/skies.gd.
##   godot-test --headless --path . -s res://tests/balloon_pop_deep_test.gd      (SEEDS=40 for more)
## Proves, for every mode over many rides, fair sizes, player counts and today's skies:
##   - every round is fair in every mode (wavegen.gd check(): every balloon reachable by the VR player and a TV
##     player, grumpies clear, no overlaps, no long gaps, sets whole, a fair star goal);
##   - its wind gusts are fair (skies.gd gust_problems(): told >= 2 s early, never blowing a balloon out of reach or
##     out of the park, never two at once) and the same every time (every machine makes the same list);
##   - GENTLE <= BRAVE <= HARD: the mode table (skies.gd ordered()) AND what the rounds really get (balloons a minute,
##     how fast they rise, grumpies, gusts);
##   - every balloon colour stands out on every sky and every grass (the snow-sheep lesson);
##   - Poppy's gifts: three different unlocked gifts, the newest unlock among them, not the last gift again;
##   - the sky theme: every time of day and season has one, no snow outside winter, the same all hour;
##   - the pick orbs: in the park, within a VR player's step from their spot, clear of each other;
##   - the parade only grows, and fast enough to unlock every gift within a few weeks of play.
## Prints "SCRIPT ERROR: ..." for each failure and "BALLOON DEEP: PASS" / "FAIL".

const WaveGen := preload("res://games/balloon_pop/wavegen.gd")
const Story := preload("res://games/balloon_pop/story.gd")
const Skies := preload("res://games/balloon_pop/skies.gd")
const Balloon := preload("res://games/balloon_pop/balloon.gd")
const Picks := preload("res://games/balloon_pop/picks.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")

var fails := 0


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 4
	for w in Skies.ordered():
		_fail("modes: " + str(w))
	# Every balloon colour on every sky.
	var cols: Array = []
	for i in Balloon.COLORS.size():
		cols.append([Balloon.COLOR_NAMES[i], Balloon.COLORS[i]])
	cols.append(["gold", Balloon.GOLD_COLOR])
	cols.append(["grumpy", Balloon.GRUMPY_COLOR])
	cols.append(["rocket", Balloon.ROCKET_COLOR])
	cols.append(["ice", Balloon.ICE_COLOR])
	cols.append(["ride choice", Balloon.CHOICE_COLOR])
	for k in Story.KIND_COLORS:
		cols.append(["%s card" % WaveGen.KIND_NAMES[int(k)], Story.KIND_COLORS[k]])
	for w in Skies.contrast_problems(cols):
		_fail("contrast: " + str(w))
	_expect(Skies.contrast_problems([["sky blue", Color(0.3, 0.55, 0.93)]]).size() > 0, "the contrast check catches a sky-blue balloon")
	# Rounds x modes.
	var per := {}
	var checked := 0
	var gust_ms := 0.0
	for mode in PickOrbs.MODE_IDS:
		var sum := {"balloons": 0.0, "rise": 0.0, "n": 0, "grumpy": 0, "gusts": 0, "rounds": 0}
		var ri := 0
		for r in Story.RIDES:
			for built in [0, 4, 12]:
				for players in [1, 4]:
					for time in [14.0, 120.0]:
						ri += 1
						for s in (seeds if time > 60.0 else 2):
							var met := {WaveGen.GRUMPY: true, WaveGen.ICE: true, WaveGen.GIANT: true} if built >= 3 else {}
							var sp := Skies.apply(Story.spec(r.id, built, met, players, time), mode)
							var seed_v := 7000 + ri * 31 + s
							var rd := WaveGen.generate(seed_v, sp)
							for x in WaveGen.check(rd, Story.allowed(sp)):
								_fail("%s / %s b%d p%d %ds seed %d: %s" % [mode, r.id, built, players, int(time), seed_v, x])
							var g0 := Time.get_ticks_usec()
							var gl := Skies.gusts(rd, mode)
							gust_ms = maxf(gust_ms, (Time.get_ticks_usec() - g0) / 1000.0)
							for x in Skies.gust_problems(rd, gl, mode):
								_fail("%s / %s b%d %ds seed %d: gusts: %s" % [mode, r.id, built, int(time), seed_v, x])
							if var_to_str(gl) != var_to_str(Skies.gusts(rd.duplicate(true), mode)):
								_fail("%s / %s: gusts differ between two makes" % [mode, r.id])
							if time > 60.0:
								sum.balloons += (rd.spawns as Array).size() * 60.0 / time
								for b in rd.spawns:
									sum.rise += float(b[5])
									sum.n += 1
									if int(b[1]) == WaveGen.GRUMPY:
										sum.grumpy += 1
								sum.gusts += gl.size()
								sum.rounds += 1
							checked += 1
		# Today's sky rounds.
		for d in seeds:
			var date := Time.get_date_string_from_unix_time(1790000000 + d * 86400 * 11)
			var sp2 := Skies.apply(Story.daily_spec(3, 120.0, date), mode)
			var rd2 := WaveGen.generate(Story.daily_seed(date), sp2)
			for x in WaveGen.check(rd2, Story.allowed(sp2)):
				_fail("%s daily %s: %s" % [mode, date, x])
			for x in Skies.gust_problems(rd2, Skies.gusts(rd2, mode), mode):
				_fail("%s daily %s: gusts: %s" % [mode, date, x])
			checked += 1
		per[mode] = {"balloons_min": snappedf(sum.balloons / maxf(1.0, sum.rounds), 0.1), "rise": snappedf(sum.rise / maxf(1.0, sum.n), 0.001),
			"grumpy": sum.grumpy, "gusts": sum.gusts}
	print("BALLOON DEEP: per mode %s" % str(per))
	var g: Dictionary = per.gentle
	var b: Dictionary = per.brave
	var h: Dictionary = per.hard
	for k in ["balloons_min", "rise", "grumpy", "gusts"]:
		_expect(float(g[k]) <= float(b[k]) and float(b[k]) <= float(h[k]), "%s gentle %s <= brave %s <= hard %s" % [k, str(g[k]), str(b[k]), str(h[k])])
	_expect(float(g.balloons_min) < float(h.balloons_min) * 0.85, "hard is clearly busier than gentle (%s vs %s)" % [str(h.balloons_min), str(g.balloons_min)])
	_expect(int(h.gusts) > int(g.gusts), "hard brings more gusts (%d vs %d)" % [int(h.gusts), int(g.gusts)])
	_expect(gust_ms < 20.0, "gusts made fast (worst %.1f ms)" % gust_ms)
	# A gust that would blow a balloon out of reach is caught.
	var edge := {"time": 30.0, "spawns": [[9.0, WaveGen.NORMAL, 6.2, 0.0, WaveGen.SPAWN_Y, 0.2, 0, -1]]}
	_expect(not Skies.gust_problems(edge, [[10.0, 1.0, 0.0]], "hard").is_empty(), "a gust blowing a balloon out of the park is caught")
	# Gifts.
	for parade in [0, 4, 5, 11, 12, 40]:
		var un := Skies.unlocked(parade)
		for last in ["", "dart", "pump", "slow", "magnet", "poppop"]:
			if last != "" and not un.has(last):
				continue
			for s in 20:
				var ch := Skies.gift_choices(parade, last, s)
				_expect(ch.size() == 3, "three gifts (parade %d last %s: %s)" % [parade, last, str(ch)])
				var seen := {}
				for id in ch:
					_expect(un.has(id), "gift %s unlocked at parade %d" % [id, parade])
					_expect(not seen.has(id), "gifts differ (%s)" % str(ch))
					seen[id] = true
				_expect(ch.has(un[un.size() - 1]) or un[un.size() - 1] == last, "the newest unlock offered (parade %d: %s)" % [parade, str(ch)])
				if un.size() > 3:
					_expect(not ch.has(last), "not the last gift again when there are others (%s, last %s)" % [str(ch), last])
	for gd in Skies.GIFTS:
		_expect(StoryCard.has_picture(String(gd.pic)), "gift %s has a picture %s" % [gd.id, gd.pic])
		_expect(String(gd.line).length() <= 26, "gift %s line is short" % gd.id)
	# The parade: grows with stars, unlocks the last gift in about two weeks of a few rounds a day.
	_expect(Skies.parade_gain(0, false) == 0 and Skies.parade_gain(1, false) == 1 and Skies.parade_gain(3, true) == 3, "parade gains")
	var last_unlock := 0
	for gd in Skies.GIFTS:
		last_unlock = maxi(last_unlock, int(gd.unlock))
	_expect(last_unlock <= 14 * 2, "every gift unlocks within ~2 weeks of 2 starry rounds a day (%d)" % last_unlock)
	# Sky themes.
	for season in Skies.SEASONS:
		for hour in 24:
			var th := Skies.theme(Skies.time_of(hour), season)
			_expect(StoryCard.has_picture(String(th.pic)), "theme %s has a picture" % th.id)
			_expect(String(Skies.theme_by_id(String(th.id)).id) == String(th.id), "theme %s survives the net" % th.id)
			if season != "winter":
				_expect(String(th.preset) != "snowy", "no snow sky in %s" % season)
	_expect(Skies.season_of("2026-12-25") == "winter" and Skies.season_of("2026-07-01") == "summer", "seasons")
	_expect(Skies.time_of(7) == "dawn" and Skies.time_of(12) == "day" and Skies.time_of(18) == "sunset" and Skies.time_of(22) == "night", "times of day")
	# The pick orbs: in the park, a step from the VR player's spot, clear of each other.
	for i in 3:
		var p := PickOrbs.spot(i, 3, Picks.ROW, Picks.GAP, Picks.Y)
		var flat := Vector2(p.x, p.z)
		_expect(flat.length() < WaveGen.ARENA - 1.0, "pick orb %d in the park" % i)
		_expect(flat.distance_to(WaveGen.VR_HOME) < 2.2, "pick orb %d a step from the VR player (%.2f m)" % [i, flat.distance_to(WaveGen.VR_HOME)])
		_expect(p.y > 0.8 and p.y < 1.5, "pick orb %d at a hand's height for VR and a TV player's body" % i)
	_expect(Picks.GAP > Picks.TV_R * 2.0, "a TV player touches one orb at a time")
	print("BALLOON DEEP: %d rounds + gusts checked in %d ms" % [checked, Time.get_ticks_msec() - t0])
	print("BALLOON DEEP: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	if fails < 40:
		print("SCRIPT ERROR: BALLOON DEEP: " + what)
