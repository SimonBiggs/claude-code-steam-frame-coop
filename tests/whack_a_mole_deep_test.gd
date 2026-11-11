extends SceneTree
## WHACK-A-MOLE second pass validator (no game, no window): games/whack_a_mole/deep.gd.
##   godot-test --headless --path . -s res://tests/whack_a_mole_deep_test.gd      (SEEDS=40 for more)
## Proves, for every mode over every crop, garden size, player count, round length, season and hammer gift:
##   - every round is fair in every mode (roundgen.gd check(): holes never overlap, never too many moles up, no long
##     empty gaps, only the crop's kinds, a fair star goal) and the same on every machine;
##   - its warned tricks are fair (deep.gd problems(): told >= 1.5 s early, spaced out, inside the round, never on the
##     KING, never two golden moles at once, a band you can step out of while it is told) and the same every time;
##   - GENTLE <= BRAVE <= HARD: the mode table (deep.gd ordered()) AND what the rounds really get (moles a minute,
##     how long a mole stays up, tricks a minute, points a minute for three stars; warnings longest on GENTLE);
##   - every key colour stands out (core/contrast.gd, games/whack_a_mole/palette.gd) in every season;
##   - Fig's hammer gifts: three different unlocked ones, the newest unlock among them, not the last again when there
##     are others, every picture drawn, short names; every gift unlocks within a few weeks of play;
##   - the seasons: every one has a lawn, a sky, a picture and a dress;
##   - the pick orbs: over the table, apart enough that a hammer-kid touches one at a time, in the giant's reach;
##   - the holiday garden: deckchairs clear of Fig's beds, each other and the giant's spot, on the lawn; only grows.
## Prints "SCRIPT ERROR: ..." for each failure and "WHACK DEEP: PASS" / "FAIL".

const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/whack_a_mole/deep.gd")
const RoundGen := preload("res://games/whack_a_mole/roundgen.gd")
const Story := preload("res://games/whack_a_mole/story.gd")
const Props := preload("res://games/whack_a_mole/props.gd")
const Picks := preload("res://games/whack_a_mole/picks.gd")
const Garden := preload("res://games/whack_a_mole/garden.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const SkyKit := preload("res://core/sky_kit.gd")
const TestTime := preload("res://tests/test_time.gd")

const GIANT_AT := Vector3(0.0, 0.0, 1.7)  # main.gd: the VR player stands at Props.HALF.y + 0.5 in front of the table
const GIANT_REACH := 1.25  # an arm (~0.6 m) + the mallet (Props.HEAD_OFFSET 0.62 m), measured across the floor

var fails := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 3
	for w in Deep.ordered():
		_fail("modes: " + str(w))
	for w in Contrast.check_game("whack_a_mole"):
		_fail("contrast: " + str(w))
	var per := {}
	var checked := 0
	var worst_ms := 0.0
	var gen_us := 0
	for mode in PickOrbs.MODE_IDS:
		var sum := {"moles": 0.0, "mins": 0.0, "stay": 0.0, "n": 0, "tricks": 0.0, "goal3": 0.0, "rounds": 0}
		for c in Story.CROPS:
			for beds in [0, 12]:
				for players in [1, 4]:
					for time in [14.0, 120.0]:
						for si in Deep.SEASONS.size():
							var season: String = Deep.SEASONS.keys()[si]
							var gift: String = String(Deep.GIFTS[(si + beds) % Deep.GIFTS.size()].id)
							var met := {RoundGen.HELMET: true, RoundGen.SPEEDY: true, RoundGen.BUNNY: true} if beds >= 4 else {}
							var sp := Deep.round_spec(Story.spec(String(c.id), beds, met, players, time), mode, gift)
							var ok := Story.allowed(sp)
							for s in (seeds if time > 60.0 else maxi(1, seeds / 2)):
								var seed_v: int = 7700 + s * 131 + beds * 17 + players
								var t1 := Time.get_ticks_usec()
								var rd := RoundGen.generate(seed_v, sp)
								var tspec := {"mode": mode, "time": time, "season": season, "extra_gold": 1 if gift == "gold" else 0}
								var tl := Deep.tricks(seed_v, tspec, rd)
								worst_ms = TestTime.worst(worst_ms, (Time.get_ticks_usec() - t1) / 1000.0, func() -> Variant: return Deep.tricks(seed_v, tspec, RoundGen.generate(seed_v, sp)))
								gen_us += Time.get_ticks_usec() - t1
								checked += 1
								var tag := "%s %s b%d p%d %ds %s %s seed %d" % [mode, c.id, beds, players, int(time), season, gift, seed_v]
								for x in RoundGen.check(rd, ok):
									_fail("%s: round: %s" % [tag, x])
								for x in Deep.problems(tl, tspec, rd):
									_fail("%s: tricks: %s" % [tag, x])
								if s == 0 and str(Deep.tricks(seed_v, tspec, RoundGen.generate(seed_v, sp))) != str(tl):
									_fail("%s: tricks differ for the same seed" % tag)
								if time == 120.0 and gift != "sleepy":
									var spawns: Array = rd.spawns
									sum.moles += spawns.size()
									sum.mins += time / 60.0
									for sw in spawns:
										sum.stay += float(sw[3])
									sum.n += spawns.size()
									sum.tricks += tl.size()
									sum.goal3 += float((rd.goal as Array)[2]) / (time / 60.0)
									sum.rounds += 1
		per[mode] = {"moles_min": sum.moles / sum.mins, "stay": sum.stay / maxf(1.0, sum.n), "tricks_min": sum.tricks / sum.mins,
			"goal3_min": sum.goal3 / maxf(1.0, sum.rounds), "warn": float(Deep.mode_data(mode).warn)}
	print("WHACK DEEP modes: %s" % str(per))
	for k in ["moles_min", "tricks_min", "goal3_min"]:
		if not (float(per.gentle[k]) <= float(per.brave[k]) and float(per.brave[k]) <= float(per.hard[k])):
			_fail("%s not gentle <= brave <= hard: %.2f %.2f %.2f" % [k, per.gentle[k], per.brave[k], per.hard[k]])
	for k in ["stay", "warn"]:
		if not (float(per.gentle[k]) >= float(per.brave[k]) and float(per.brave[k]) >= float(per.hard[k])):
			_fail("%s not longest on gentle: %.2f %.2f %.2f" % [k, per.gentle[k], per.brave[k], per.hard[k]])
	if float(per.hard.tricks_min) <= 0.0:
		_fail("no tricks ever happen")
	# TODAY'S PATCH in every mode.
	for mode in PickOrbs.MODE_IDS:
		for d in ["2026-01-05", "2026-07-19", "2026-11-11"]:
			var sp2 := Deep.round_spec(Story.daily_spec(3, 120.0, d), mode, "")
			var rd2 := RoundGen.generate(Story.daily_seed(d), sp2)
			for x in RoundGen.check(rd2, Story.allowed(sp2)):
				_fail("%s daily %s: %s" % [mode, d, x])
	# The kinds of trick both really happen.
	var kinds := {}
	for s in 40:
		var rd3 := RoundGen.generate(s, Story.spec("MELONS", 6, {}, 2, 120.0))
		for e in Deep.tricks(s, {"mode": "brave", "time": 120.0, "season": "summer"}, rd3):
			kinds[String(e[1])] = true
	for k in Deep.KINDS:
		if not kinds.has(k):
			_fail("the %s trick never happens" % k)
	_gifts()
	_seasons()
	_orbs()
	_holiday()
	var ms := Time.get_ticks_msec() - t0
	var avg_ms := gen_us / 1000.0 / maxf(1.0, checked)
	print("WHACK DEEP: %d rounds checked in %d ms (a round + its tricks: %.2f ms on average, worst %.2f ms at idle priority)" % [checked, ms, avg_ms, worst_ms])
	if avg_ms > 10.0:
		_fail("a round + its tricks take %.1f ms (a Deck is ~4x slower: keep it well under 100 ms)" % avg_ms)
	print("WHACK DEEP: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func _gifts() -> void:
	for g in Deep.GIFTS:
		if not StoryCard.has_picture(String(g.pic)):
			_fail("gift %s has no picture %s" % [g.id, g.pic])
		if String(g.name).length() > 13 or String(g.line).length() > 18:
			_fail("gift %s: name / line too long for kids" % g.id)
	var last_unlock := int(Deep.GIFTS[Deep.GIFTS.size() - 1].unlock)
	# ~60 moles a round, ~6 rounds an evening: every gift within a few weeks.
	if last_unlock * Deep.HOLIDAY_EVERY > 60 * 6 * 14:
		_fail("the last gift takes too long to unlock")
	for hol in range(0, Deep.MAX_HOLIDAY + 1):
		var un := Deep.unlocked(hol)
		for last in [""] + Deep.unlocked(hol):
			for sd in 4:
				var ch := Deep.gift_choices(hol, String(last), sd * 97 + hol)
				var tag := "gifts hol %d last %s" % [hol, last]
				if ch.size() != 3:
					_fail("%s: %d choices" % [tag, ch.size()])
				var seen := {}
				for id in ch:
					if seen.has(id):
						_fail("%s: %s twice" % [tag, id])
					seen[id] = true
					if not un.has(id):
						_fail("%s: %s not unlocked" % [tag, id])
				if un.size() > 3 and ch.has(last):
					_fail("%s: the last gift again" % tag)
				if String(un[un.size() - 1]) != String(last) and not ch.has(un[un.size() - 1]):
					_fail("%s: the newest gift missing" % tag)
	for m in PickOrbs.MODE_IDS:
		if String(PickOrbs.mode(m).get("pic", "")) == "":
			_fail("mode %s has no picture" % m)


func _seasons() -> void:
	for s in Deep.SEASONS:
		var d: Dictionary = Deep.SEASONS[s]
		if not StoryCard.has_picture(String(d.pic)):
			_fail("season %s has no picture" % s)
		if not Props.LAWNS.has(s):
			_fail("season %s has no lawn" % s)
		if SkyKit.resolve(String(d.sky)) != String(d.sky):
			_fail("season %s: no sky %s" % [s, d.sky])
		if (d.weights as Array).size() != Deep.KINDS.size():
			_fail("season %s: weights" % s)
		var m := Props.season_deco(s)
		if m == null or m.get_surface_count() == 0:
			_fail("season %s has no dress" % s)


func _orbs() -> void:
	for n in [2, 3]:
		for i in n:
			var p := Picks.spot_of(i, n)
			if absf(p.x) > Props.HALF.x - 0.1 or absf(p.z) > Props.HALF.y - 0.1:
				_fail("pick orb %d of %d is off the table (%s)" % [i, n, p])
			if Vector2(p.x - GIANT_AT.x, p.z - GIANT_AT.z).length() > GIANT_REACH:
				_fail("pick orb %d of %d out of the giant's reach (%s)" % [i, n, p])
			if p.y < Props.TABLE_Y + 0.15 or p.y > Props.TABLE_Y + 0.6:
				_fail("pick orb %d of %d at a bad height" % [i, n])
	if Picks.GAP < Picks.TV_R * 2.0 + 0.1:
		_fail("pick orbs so close a hammer-kid touches two")
	# A kid seated on the table never starts on an orb (main.gd _ensure_avatar spots).
	for slot in 10:
		var kid := Vector3(-1.2 + 0.6 * float(slot % 5), 0.0, -0.36 + 0.72 * float((slot / 5) % 2))
		for i in 3:
			var o := Picks.spot_of(i, 3)
			if Vector2(kid.x - o.x, kid.z - o.z).length() < Picks.TV_R + 0.1:
				_fail("a hammer-kid starts on pick orb %d" % i)


func _holiday() -> void:
	var prev := 0
	for total in range(0, Deep.HOLIDAY_EVERY * (Deep.MAX_HOLIDAY + 5), 7):
		var h := Deep.holiday(total)
		if h < prev:
			_fail("the holiday garden shrank at %d" % total)
		prev = h
	if Deep.holiday(Deep.HOLIDAY_EVERY * 1000) != Deep.MAX_HOLIDAY:
		_fail("the holiday garden is not capped")
	var spots: Array = []
	for i in Deep.MAX_HOLIDAY:
		var p: Vector3 = Deep.holiday_spot(i).origin
		for b in Story.CROPS.size():
			if p.distance_to(Garden.spot(b).origin) < 1.25:
				_fail("holiday mole %d sits on Fig's bed %d" % [i, b])
		for q in spots:
			if p.distance_to(q) < 0.7:
				_fail("holiday mole %d sits on another" % i)
		if p.distance_to(GIANT_AT) < 3.0:
			_fail("holiday mole %d sits where the giant stands" % i)
		if p.length() > 20.0:
			_fail("holiday mole %d is off the lawn" % i)
		var f := Deep.holiday_spot(i).basis.z
		if f.dot(-p.normalized()) < 0.9:
			_fail("holiday mole %d doesn't face the table" % i)
		spots.append(p)


func _fail(msg: String) -> void:
	fails += 1
	printerr("SCRIPT ERROR: WHACK DEEP: " + msg)
	print("SCRIPT ERROR: WHACK DEEP: " + msg)