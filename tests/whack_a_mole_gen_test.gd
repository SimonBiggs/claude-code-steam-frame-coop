extends SceneTree
## WHACK-A-MOLE round generator: proves the seeded rounds are fair over many seeds (no game, no window).
##   godot-test --headless --path . -s res://tests/whack_a_mole_gen_test.gd      (SEEDS=500 for more)
## For every crop, garden size (bed 0 .. a giant lap), player count and round length (the bots' 14 s, a
## minute, the real two minutes): games/whack_a_mole/roundgen.gd check() (holes never overlap, never too
## many moles up, no long empty gaps, only the crop's kinds, a fair star goal, a king only when there's
## time), the same seed gives the same round, rounds get busier as the garden grows, each crop's
## visitors really show up, TODAY'S PATCH is the same all day, the story rules (offers, bed sizes), and
## generation stays fast (Decks are slow). Prints "SCRIPT ERROR: ..." for each failure.

const RoundGen := preload("res://games/whack_a_mole/roundgen.gd")
const Story := preload("res://games/whack_a_mole/story.gd")
const Seeded := preload("res://core/seeded.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 30
	var total := 0
	var t0 := Time.get_ticks_usec()
	var gens := 0
	var seen := {}  # crop -> {kind: n}
	var busy := {}  # level -> moles per minute
	for c in Story.CROPS:
		for beds in [0, 3, 8, 15]:
			for players in [1, 3, 6]:
				for time in [14.0, 60.0, 120.0]:
					var met := {RoundGen.HELMET: true, RoundGen.SPEEDY: true} if beds >= 3 else {}
					var sp := Story.spec(c.id, beds, met, players, time)
					var ok := Story.allowed(sp)
					var r := Seeded.validate(func(s: int) -> Dictionary: return RoundGen.generate(s, sp),
						func(rd: Dictionary) -> Array: return RoundGen.check(rd, ok),
						seeds if time > 60.0 else seeds / 3, 11 + beds, [0, 1, 999999], "MOLES %s b%d p%d %ds" % [c.id, beds, players, int(time)])
					total += int(r.checked)
					gens += int(r.checked) * 2
					fails += (r.failures as Array).size()
					if time == 120.0 and players == 3:
						for s in 10:
							var rd := RoundGen.generate(500 + s, sp)
							if not seen.has(c.id):
								seen[c.id] = {}
							for m in rd.spawns:
								seen[c.id][int(m[2])] = int(seen[c.id].get(int(m[2]), 0)) + 1
							busy[beds] = float(busy.get(beds, 0.0)) + rd.spawns.size() / 2.0 / 10.0 / Story.CROPS.size()
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens)
	print("whack gen: %.3f ms per round (%d rounds)" % [per_ms, gens])
	_expect(per_ms < 20.0, "a round generates in under 20 ms here (%.2f ms; Decks are slower, aim < 100)" % per_ms)
	# Every crop's own visitors show up; a crop without them doesn't get them (bed 0 = nothing met yet).
	for c in Story.CROPS:
		var got: Dictionary = seen.get(c.id, {})
		for k in c.kinds:
			_expect(int(got.get(int(k), 0)) >= 10, "%s brings its %s moles (%s)" % [c.id, RoundGen.KIND_NAMES[int(k)], str(got)])
		_expect(int(got.get(RoundGen.GOLD, 0)) >= 3, "%s has golden moles (%s)" % [c.id, str(got)])
		if bool(c.get("king", false)):
			_expect(int(got.get(RoundGen.KING, 0)) >= 30, "%s brings the king in every round (%s)" % [c.id, str(got)])
	_expect(float(busy[15]) > float(busy[0]) * 1.1, "rounds get busier as the garden grows (%s moles a minute)" % str(busy))
	# The plain first bed only has plain and golden moles.
	var first := RoundGen.generate(42, Story.spec(Story.FIRST_CROP, 0, {}, 2, 120.0))
	for m in first.spawns:
		if int(m[2]) > RoundGen.GOLD:
			_fail("the first bed has a %s mole" % RoundGen.KIND_NAMES[int(m[2])])
			break
	_expect((first.waves as Array).filter(func(w: Array) -> bool: return w[1] != "scatter").is_empty(), "the first bed is plain scatter")
	var later := RoundGen.generate(42, Story.spec("CORN", 6, {}, 2, 120.0))
	var shapes := {}
	for w in later.waves:
		shapes[w[1]] = true
	_expect(shapes.size() >= 4, "later rounds mix wave shapes (%s)" % str(shapes.keys()))
	# TODAY'S PATCH: fair for many days, the same all day, different day to day.
	var days := {}
	for d in 60:
		var date := Time.get_date_string_from_unix_time(1790000000 + d * 86400)
		var sp := Story.daily_spec(3, 120.0, date)
		var rd := RoundGen.generate(Story.daily_seed(date), sp)
		for w in RoundGen.check(rd, Story.allowed(sp)):
			_fail("daily %s: %s" % [date, w])
		_expect(var_to_str(rd) == var_to_str(RoundGen.generate(Story.daily_seed(date), Story.daily_spec(3, 120.0, date))), "daily %s is the same all day" % date)
		days[var_to_str(rd.spawns)] = true
		total += 1
	_expect(days.size() >= 58, "daily rounds differ day to day (%d unique of 60)" % days.size())
	# Hand checks: the validator catches broken rounds.
	var bad := {"time": 20.0, "cap": 5, "max": 3, "goal": [1, 2, 3], "spawns": [[1.0, 3, 0, 1.0], [1.5, 3, 0, 1.0], [2.0, 4, 0, 1.0]]}
	_expect(not RoundGen.check(bad).is_empty(), "a hole used twice at once is caught")
	var gap := {"time": 20.0, "cap": 5, "max": 3, "goal": [1, 2, 3], "spawns": [[1.0, 3, 0, 1.0], [9.0, 4, 0, 1.0], [10.0, 5, 0, 1.0]]}
	_expect(not RoundGen.check(gap).is_empty(), "a long empty gap is caught")
	var crowd: Array = []
	for h in 7:
		crowd.append([2.0 + h * 0.01, h, 0, 2.0])
	_expect(not RoundGen.check({"time": 10.0, "cap": 5, "max": 7, "goal": [1, 2, 3], "spawns": crowd}).is_empty(), "too many moles up is caught")
	_expect(not RoundGen.check(first, [RoundGen.NORMAL]).is_empty() or not (first.kinds as Array).has(RoundGen.GOLD), "a kind that isn't allowed is caught")
	# Story rules.
	_expect(Story.offers(7, {}, "").size() == 1 or Story.offers(7, {}, "")[0] == Story.FIRST_CROP, "nothing grown: only lettuce is open")
	var o := Story.offers(7, {"LETTUCE": 1}, "LETTUCE")
	_expect(o.size() == 2 and not o.has("LETTUCE"), "after the lettuce: two new crops (%s)" % str(o))
	_expect(var_to_str(o) == var_to_str(Story.offers(7, {"LETTUCE": 1}, "LETTUCE")), "offers are the same for the same world")
	var all := {}
	for c in Story.CROPS:
		all[c.id] = 1
	var o2 := Story.offers(9, all.merged({"APPLES": 2}), "APPLES")
	_expect(o2.size() == 2 and not o2.has("APPLES"), "the giant lap offers crops not yet giant (%s)" % str(o2))
	_expect(Story.bed_need(0) < Story.bed_need(5), "later beds need more veg")
	_expect(Story.save_defaults().cur == Story.FIRST_CROP, "a new garden starts with lettuce")
	for c in Story.CROPS:
		_expect(String(c.intro).length() <= 26 and String(c.done).length() <= 26, "%s lines are short" % c.id)
	print("whack gen: %d rounds checked, %d failures" % [total, fails])
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: whack gen: " + what)
