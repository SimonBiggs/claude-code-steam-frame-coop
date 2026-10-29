extends SceneTree
## OBSTACLE RUSH seeded courses: proves every course is runnable, finishable and fair (no game, no window).
##   godot-test --headless --path . -s res://tests/obstacle_rush_gen_test.gd      (SEEDS=500 for more)
## For every tier and TODAY'S COURSE: games/obstacle_rush/coursegen.gd check() (floors on the table and
## apart, a real door in every wall, every checkpoint safe and right after its obstacle so a ball bonk or a
## fall never costs more than one obstacle, the start line and finish solid, the CPU route stands on
## the course, every star reachable, the giant can reach and hit every bit of the course, and the
## simulated jelly bean runs it to the flag at CPU and full speed, jumping early and late, never falling),
## the same seed gives the same course, a compact description {k, s, tier, a} rebuilds it exactly, every
## piece shows up, higher tiers are harder, the four lessons pass too, the story rules (story.gd), and it
## all stays fast. The real proof is the bot playing generated shows (OR_GEN=1).
## Prints "SCRIPT ERROR: ..." for each failure.

const CourseGen := preload("res://games/obstacle_rush/coursegen.gd")
const Story := preload("res://games/obstacle_rush/story.gd")
const Seeded := preload("res://core/seeded.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 60
	var total := 0
	var t0 := Time.get_ticks_usec()
	var gens := 0
	var kinds := {}
	var pieces := {}
	var gaps := {}
	var stars := {}
	for tier in CourseGen.tier_count():
		var r := Seeded.validate(func(s: int) -> Dictionary: return CourseGen.generate(s, tier),
			func(c: Dictionary) -> Array: return CourseGen.check(c), seeds, 5 + tier, [0, 1, 999999], "COURSE T%d" % tier)
		total += int(r.checked)
		gens += int(r.checked) * 2
		fails += (r.failures as Array).size()
		var wide := 0.0
		for s in 20:
			var c := CourseGen.generate(900 + s * 13, tier)
			for k in c.pieces:
				kinds[k] = int(kinds.get(k, 0)) + 1
			pieces[tier] = int(pieces.get(tier, 0)) + (c.pieces as Array).size()
			stars[tier] = int(stars.get(tier, 0)) + (c.stars as Array).size()
			for o in c.obstacles:
				if String(o[2]) == "gap":
					wide = maxf(wide, float(o[1]) - float(o[0]))
			# Every machine rebuilds the same course from the host's compact description.
			var d := CourseGen.describe("gen", 900 + s * 13, tier)
			_expect(var_to_str(CourseGen.make(d).floors) == var_to_str(c.floors) and var_to_str(CourseGen.make(d).stars) == var_to_str(c.stars),
				"tier %d seed %d: the compact description rebuilds the course" % [tier, 900 + s * 13])
		gaps[tier] = wide
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens)
	print("course gen: %.2f ms per course + check (%d courses)" % [per_ms, gens])
	_expect(per_ms < 40.0, "a course generates and checks in under 40 ms here (%.2f ms)" % per_ms)
	for k in CourseGen.KINDS:
		_expect(int(kinds.get(k, 0)) >= 5, "piece %s shows up (%s)" % [k, str(kinds)])
	var last := CourseGen.tier_count() - 1
	_expect(int(pieces[last]) > int(pieces[0]), "higher tiers have more pieces (%s)" % str(pieces))
	_expect(float(gaps[last]) > float(gaps[0]), "higher tiers have wider gaps (%s)" % str(gaps))
	_expect(int(stars[last]) > int(stars[0]), "higher tiers have more stars (%s)" % str(stars))
	# The lessons pass the same validator.
	for i in CourseGen.LESSONS.size():
		for s in [1, 77, 4242]:
			for w in CourseGen.check(CourseGen.lesson(i, s)):
				_fail("lesson %d seed %d: %s" % [i, s, w])
			total += 1
	# TODAY'S COURSE: fair, the same all day, different day to day.
	var days := {}
	for d in 40:
		var date := Time.get_date_string_from_unix_time(1790000000 + d * 86400)
		var desc := Story.daily_desc(date)
		var c := CourseGen.make(desc)
		for w in CourseGen.check(c):
			_fail("daily %s: %s" % [date, w])
		_expect(String(c.name) == "TODAY'S COURSE", "the daily course is called TODAY'S COURSE")
		_expect(var_to_str(c) == var_to_str(CourseGen.make(Story.daily_desc(date))), "daily %s is the same all day" % date)
		days[var_to_str(c.floors)] = true
		total += 1
	_expect(days.size() >= 30, "daily courses differ (%d unique of 40)" % days.size())
	# Hand checks: the validator catches broken courses.
	var c0 := CourseGen.generate(42, 3)
	var b1 := c0.duplicate(true)
	for o in b1.obstacles:
		if String(o[2]) == "gap":
			for f in b1.floors:
				if absf(float(f[0]) - float(o[1])) < 0.01:
					f[0] = float(f[0]) + 3.0  # a gap far too wide to jump
			break
	if (c0.pieces as Array).has("gap"):
		_expect(not CourseGen.check(b1).is_empty(), "a gap too wide to jump is caught")
	var b2 := c0.duplicate(true)
	(b2.stars as Array).append(Vector3(0.0, 9.0, 0.0))
	_expect(not CourseGen.check(b2).is_empty(), "a star in the sky is caught")
	var b3 := c0.duplicate(true)
	(b3.checkpoints as Array).remove_at(1)
	_expect(not CourseGen.check(b3).is_empty(), "a missing checkpoint is caught")
	for s in 60:
		var cd := CourseGen.generate(s, 2)
		if not (cd.walls as Array).is_empty():
			var b4 := cd.duplicate(true)
			b4.walls[0].fakes = [true, true, true]
			_expect(not CourseGen.check(b4).is_empty(), "a wall of pretend doors is caught")
			break
	# Story.
	for w in Story.self_check():
		_fail("story: " + w)
	print("course gen: %d courses checked, %d failures" % [total, fails])
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: course gen: " + what)
