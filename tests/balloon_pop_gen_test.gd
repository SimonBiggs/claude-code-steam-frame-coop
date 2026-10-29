extends SceneTree
## BALLOON POP wave generator: proves the seeded rounds are fair over many seeds (no game, no window).
##   godot-test --headless --path . -s res://tests/balloon_pop_gen_test.gd      (SEEDS=500 for more)
## For every ride, fair size (first ride .. a lit-up lap), player count and round length (the bots' 14 s, a
## minute, the real two minutes): games/balloon_pop/wavegen.gd check() (every balloon reachable in time
## by the VR player walking from their spot AND a TV player running from the middle, grumpies never too
## close to a good balloon, no overlaps, never too many up, no long gaps, only the ride's kinds, sets
## whole, a fair star goal), the same seed gives the same round, rounds get busier as the fair grows,
## each ride's special balloons really show up, TODAY'S SKY is the same all day, the story rules
## (offers, ride sizes), and generation stays fast (Decks are slow). Prints "SCRIPT ERROR: ..." per failure.

const WaveGen := preload("res://games/balloon_pop/wavegen.gd")
const Story := preload("res://games/balloon_pop/story.gd")
const Seeded := preload("res://core/seeded.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 10
	var total := 0
	var t0 := Time.get_ticks_usec()
	var gens := 0
	var seen := {}  # ride -> {kind: n}
	var busy := {}  # built -> balloons per minute
	var sets := {}  # shape -> n
	for r in Story.RIDES:
		for built in [0, 3, 8, 15]:
			for players in [1, 3, 6]:
				for time in [14.0, 60.0, 120.0]:
					var met := {WaveGen.GRUMPY: true, WaveGen.ICE: true, WaveGen.GIANT: true} if built >= 3 else {}
					var sp := Story.spec(r.id, built, met, players, time)
					var ok := Story.allowed(sp)
					var res := Seeded.validate(func(s: int) -> Dictionary: return WaveGen.generate(s, sp),
						func(rd: Dictionary) -> Array: return WaveGen.check(rd, ok),
						seeds if time > 60.0 else seeds / 3, 11 + built, [0, 1, 999999], "BALLOONS %s b%d p%d %ds" % [r.id, built, players, int(time)])
					total += int(res.checked)
					gens += int(res.checked) * 2
					fails += (res.failures as Array).size()
					if time == 120.0 and players == 3:
						for s in 10:
							var rd := WaveGen.generate(500 + s, sp)
							if not seen.has(r.id):
								seen[r.id] = {}
							for b in rd.spawns:
								seen[r.id][int(b[1])] = int(seen[r.id].get(int(b[1]), 0)) + 1
							for st in rd.sets:
								sets[st[1]] = int(sets.get(st[1], 0)) + 1
							busy[built] = float(busy.get(built, 0.0)) + rd.spawns.size() / 2.0 / 10.0 / Story.RIDES.size()
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens)
	print("balloon gen: %.3f ms per round incl. check (%d rounds)" % [per_ms, gens])
	_expect(per_ms < 25.0, "a round generates + checks in under 25 ms here (%.2f ms; Decks are slower, aim < 100)" % per_ms)
	# Every ride's own specials show up.
	for r in Story.RIDES:
		var got: Dictionary = seen.get(r.id, {})
		for k in r.kinds:
			_expect(int(got.get(int(k), 0)) >= 10, "%s brings its %s balloons (%s)" % [r.id, WaveGen.KIND_NAMES[int(k)], str(got)])
		_expect(int(got.get(WaveGen.GOLD, 0)) >= 5, "%s has gold balloons (%s)" % [r.id, str(got)])
		if float(r.get("grumpy", 0.0)) > 0.0:
			_expect(int(got.get(WaveGen.GRUMPY, 0)) >= 20, "%s brings grumpy balloons (%s)" % [r.id, str(got)])
		if int(r.get("giants", 0)) > 0:
			_expect(int(got.get(WaveGen.GIANT, 0)) >= 10 * int(r.giants) * 4 / 5, "%s brings its giants (%s)" % [r.id, str(got)])
	for shape in WaveGen.SETS:
		_expect(int(sets.get(shape, 0)) >= 10, "%s sets happen (%s)" % [shape, str(sets)])
	_expect(float(busy[15]) > float(busy[0]) * 1.15, "rounds get busier as the fair grows (%s balloons a minute)" % str(busy))
	# The first ride: only plain and gold balloons, no sets yet, no grumpies.
	var first := WaveGen.generate(42, Story.spec(Story.FIRST_RIDE, 0, {}, 2, 120.0))
	for b in first.spawns:
		if int(b[1]) > WaveGen.GOLD:
			_fail("the first ride has a %s balloon" % WaveGen.KIND_NAMES[int(b[1])])
			break
	_expect((first.sets as Array).is_empty(), "the first ride has no sets yet")
	var later := WaveGen.generate(42, Story.spec("FERRIS", 6, {}, 2, 120.0))
	var shapes := {}
	for w in later.waves:
		shapes[w[1]] = true
	_expect(shapes.size() >= 5, "later rounds mix wave shapes (%s)" % str(shapes.keys()))
	# TODAY'S SKY: fair for many days, the same all day, different day to day.
	var days := {}
	var skies := {}
	for d in 60:
		var date := Time.get_date_string_from_unix_time(1790000000 + d * 86400)
		var sp := Story.daily_spec(3, 120.0, date)
		var rd := WaveGen.generate(Story.daily_seed(date), sp)
		for w in WaveGen.check(rd, Story.allowed(sp)):
			_fail("daily %s: %s" % [date, w])
		_expect(var_to_str(rd) == var_to_str(WaveGen.generate(Story.daily_seed(date), Story.daily_spec(3, 120.0, date))), "daily %s is the same all day" % date)
		days[var_to_str(rd.spawns)] = true
		skies[sp.sky] = true
		total += 1
	_expect(days.size() >= 58, "daily rounds differ day to day (%d unique of 60)" % days.size())
	_expect(skies.size() >= 3, "TODAY'S SKY changes (%s)" % str(skies.keys()))
	# Hand checks: the validator catches broken rounds.
	var g := [1, 2, 3]
	var far := {"time": 20.0, "max": 9, "goal": g, "spawns": [[1.0, 0, 0.0, -6.3, 0.35, 0.5, 0, -1], [2.0, 0, 0.0, 0.0, 0.35, 0.3, 1, -1]]}
	_expect(_has(WaveGen.check(far), "can't reach"), "a far-away fast balloon is caught")
	var grump := {"time": 20.0, "max": 9, "goal": g, "spawns": [[1.0, 0, 1.0, 1.0, 0.35, 0.3, 0, -1], [1.0, 2, 1.0, 1.9, 0.35, 0.3, 1, -1]]}
	_expect(_has(WaveGen.check(grump), "crowded"), "a grumpy hugging a good balloon is caught")
	var gap := {"time": 20.0, "max": 9, "goal": g, "spawns": [[1.0, 0, 0.0, 0.0, 0.35, 0.3, 0, -1], [9.0, 0, 2.0, 0.0, 0.35, 0.3, 1, -1]]}
	_expect(_has(WaveGen.check(gap), "gap"), "a long empty gap is caught")
	var crowd: Array = []
	for k in 16:
		crowd.append([2.0 + k * 0.01, 0, -4.0 + (k % 8) * 1.0, -1.0 + (k / 8) * 1.5, 0.35, 0.3, 0, -1])
	_expect(_has(WaveGen.check({"time": 10.0, "max": 16, "goal": g, "spawns": crowd}), "crowded"), "too many balloons up is caught")
	var notok := {"time": 20.0, "max": 9, "goal": g, "spawns": [[1.0, WaveGen.ROCKET, 0.0, 0.0, 0.35, 0.3, 0, -1]]}
	_expect(_has(WaveGen.check(notok, [WaveGen.NORMAL]), "not allowed"), "a kind that isn't allowed is caught")
	# Story rules.
	_expect(Story.offers(7, {}, "").size() == 1 and Story.offers(7, {}, "")[0] == Story.FIRST_RIDE, "nothing built: only bunting is open")
	var o := Story.offers(7, {"BUNTING": 1}, "BUNTING")
	_expect(o.size() == 2 and not o.has("BUNTING"), "after the bunting: two new rides (%s)" % str(o))
	_expect(var_to_str(o) == var_to_str(Story.offers(7, {"BUNTING": 1}, "BUNTING")), "offers are the same for the same world")
	var all := {}
	for r in Story.RIDES:
		all[r.id] = 1
	var o2 := Story.offers(9, all.merged({"FIREWORKS": 2}, true), "FIREWORKS")
	_expect(o2.size() == 2 and not o2.has("FIREWORKS"), "the lit-up lap offers rides not yet lit (%s)" % str(o2))
	_expect(Story.ride_need(0) < Story.ride_need(5), "later rides need more tickets")
	_expect(Story.save_defaults().cur == Story.FIRST_RIDE, "a new fair starts with the bunting")
	for r in Story.RIDES:
		_expect(String(r.intro).length() <= 26 and String(r.done).length() <= 26, "%s lines are short" % r.id)
	for k in Story.KIND_LINES:
		_expect(String(Story.KIND_LINES[k]).length() <= 26, "the %s line is short" % WaveGen.KIND_NAMES[int(k)])
	print("balloon gen: %d rounds checked, %d failures" % [total, fails])
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)


func _has(why: Array, word: String) -> bool:
	for w in why:
		if String(w).contains(word):
			return true
	return false


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: balloon gen: " + what)
