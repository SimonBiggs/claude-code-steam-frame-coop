extends SceneTree
## STARSHIP CREW seeded missions: proves every mission is flyable and fair (no game, no window).
##   godot-test --headless --path . -s res://tests/starship_crew_gen_test.gd      (SEEDS=500 for more)
## For every kind and tier (several laps each) and TODAY'S MISSION: games/starship_crew/missiongen.gd
## check() (rings in bounds and each one reachable from the last, laps join up, every rock and alien on
## the TV screen long enough to zap, no overlapping waves, never too many at once, plenty of stars,
## targets on both sides of the screen); same seed -> same mission; higher tiers are busier and faster;
## the lessons and every trip pass; hand-broken missions are caught; the story rules (story.gd);
## and it all stays fast. The real proof is the bot flying generated trips (SC_TRIPS=3).
## Prints "SCRIPT ERROR: ..." for each failure.

const MissionGen := preload("res://games/starship_crew/missiongen.gd")
const Story := preload("res://games/starship_crew/story.gd")
const Seeded := preload("res://core/seeded.gd")
const Space := preload("res://games/starship_crew/space.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 40
	var total := 0
	var t0 := Time.get_ticks_usec()
	var gens := 0
	var busy := {}
	for kind in MissionGen.KINDS:
		for tier in MissionGen.TIERS:
			for lap in [0, 1, 7]:
				var r := Seeded.validate(func(s: int) -> Dictionary: return MissionGen.generate(s, kind, tier, lap),
					func(m: Dictionary) -> Array: return MissionGen.check(m), seeds, 3 + tier + lap, [0, 1, 999999], "MISSION %s T%d L%d" % [kind, tier, lap])
				total += int(r.checked)
				gens += int(r.checked) * 2
				fails += (r.failures as Array).size()
			var b := 0.0
			for s in 20:
				b += MissionGen.busyness(MissionGen.generate(500 + s * 17, kind, tier))
			busy["%s%d" % [kind, tier]] = b
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens)
	print("mission gen: %.2f ms per mission + check (%d missions)" % [per_ms, gens])
	_expect(per_ms < 30.0, "a mission generates and checks in under 30 ms here (%.2f ms)" % per_ms)
	for kind in MissionGen.KINDS:
		_expect(float(busy["%s%d" % [kind, MissionGen.TIERS - 1]]) > float(busy["%s0" % kind]),
			"%s: higher tiers are busier (%s)" % [kind, str(busy)])
	_expect(MissionGen.speed_for(MissionGen.TIERS - 1) > MissionGen.speed_for(0), "higher tiers fly faster")
	# Every rock wave and alien wave shows up.
	var rocks := 0
	var ufos := 0
	var rings := 0
	for s in 30:
		for e in MissionGen.generate(s, "mixed", 2).events:
			match int(e[1]):
				Space.RING: rings += 1
				Space.ROCK: rocks += 1
				Space.UFO: ufos += 1
	_expect(rings > 0 and rocks > 0 and ufos > 0, "a star party has rings, rocks and aliens (%d %d %d)" % [rings, rocks, ufos])
	# Trips: the lessons, generated trips and TODAY'S MISSION all pass the validator.
	for world in [5, 1234, 777777]:
		for trips in [0, 1, 2, 5, 12]:
			var tp := Story.trip(trips, world, trips == 2, "2026-11-0%d" % (trips % 9 + 1))
			_expect(tp.size() == Story.MISSIONS, "a trip has %d missions" % Story.MISSIONS)
			for m in tp:
				for lap in 2:
					for w in MissionGen.check(MissionGen.generate(int(m.s), String(m.k), int(m.tier), lap)):
						_fail("world %d trip %d %s: %s" % [world, trips, String(m.k), w])
					total += 1
	var days := {}
	for d in 40:
		var date := Time.get_date_string_from_unix_time(1790000000 + d * 86400)
		var dm := Story.daily_mission(date)
		_expect(Story.mission_name(dm) == "TODAY'S MISSION!", "the daily mission is called TODAY'S MISSION!")
		var m := MissionGen.generate(int(dm.s), String(dm.k), int(dm.tier))
		for w in MissionGen.check(m):
			_fail("daily %s: %s" % [date, w])
		_expect(var_to_str(m) == var_to_str(MissionGen.generate(int(Story.daily_mission(date).s), String(dm.k), int(dm.tier))), "daily %s is the same all day" % date)
		days[var_to_str(m.events)] = true
		total += 1
	_expect(days.size() >= 30, "daily missions differ (%d unique of 40)" % days.size())
	# Hand checks: the validator catches broken missions.
	var m0 := MissionGen.generate(42, "rings", 3)
	var b1 := m0.duplicate(true)
	for e in b1.events:
		if int(e[1]) == Space.RING:
			e[2] = 7.0
			e[3] = -3.0
			break
	_expect(not MissionGen.check(b1).is_empty(), "a first ring far from the middle is caught")
	var b2 := m0.duplicate(true)
	var seen := 0
	for e in b2.events:
		if int(e[1]) == Space.RING:
			seen += 1
			if seen == 3:
				e[2] = -float(e[2]) - 6.5 * signf(float(e[2]) + 0.01)
				break
	_expect(not MissionGen.check(b2).is_empty(), "a ring too far to reach in time is caught")
	var b3 := MissionGen.generate(42, "rocks", 1).duplicate(true)
	for e in b3.events:
		if int(e[1]) == Space.ROCK:
			e[2] = 200.0
			break
	_expect(not MissionGen.check(b3).is_empty(), "a rock off the side of the TV screen is caught")
	var b4 := MissionGen.generate(42, "rocks", 1).duplicate(true)
	for e in b4.events:
		if int(e[1]) == Space.ROCK:
			var twin: Array = (e as Array).duplicate()
			(b4.events as Array).insert((b4.events as Array).find(e) + 1, twin)
			break
	_expect(not MissionGen.check(b4).is_empty(), "two rocks on top of each other are caught")
	var b5 := MissionGen.generate(42, "aliens", 1).duplicate(true)
	b5.events = (b5.events as Array).filter(func(e: Array) -> bool: return int(e[1]) == Space.RING)
	_expect(not MissionGen.check(b5).is_empty(), "a mission with nothing for the gunners is caught")
	var b6 := MissionGen.generate(42, "rocks", 1).duplicate(true)
	for e in b6.events:
		if int(e[1]) == Space.ROCK:
			e[2] = absf(float(e[2])) + 0.5
	_expect(not MissionGen.check(b6).is_empty(), "targets all on one side are caught")
	# Pictures: every story card picture has a drawing (all games), and every picture the captain uses exists.
	var StoryCard := load("res://core/story_card.gd")
	var src := FileAccess.get_file_as_string("res://core/story_card.gd")
	for pic in StoryCard.PICTURES:
		var re := RegEx.create_from_string("\\n\\t+(\"[a-z]+\", )*\"%s\"(, \"[a-z]+\")*:" % pic)
		_expect(re.search(src) != null, "story card picture %s has a drawing" % pic)
	_expect(RegEx.create_from_string("\\n\\t+(\"[a-z]+\", )*\"%s\"(, \"[a-z]+\")*:" % "nopicture").search(src) == null, "the picture check can fail")
	var icons := ["star", "crown", "music", "trophy", "flag", "heart"]
	for part in Story.PARTS:
		_expect(StoryCard.PICTURES.has(String(part.pic)) or icons.has(String(part.pic)), "station part picture %s exists" % part.pic)
	for pic in ["captain", "planet"]:
		_expect(StoryCard.PICTURES.has(pic), "picture %s exists" % pic)
	# Story.
	for w in Story.self_check():
		_fail("story: " + w)
	print("mission gen: %d missions checked, %d failures" % [total, fails])
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: mission gen: " + what)
