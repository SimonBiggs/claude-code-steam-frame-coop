extends SceneTree
## BLOCK BUILDERS sky adventures: proves the seeded courses are fair over many seeds (no game, no window).
##   godot-test --headless --path . -s res://tests/block_builders_gen_test.gd      (SEEDS=500 for more)
## For adventures 0..12 and TODAY'S SKY: games/block_builders/coursegen.gd check() (islands in bounds and
## apart, every solution block in the build area, outside the islands and off the start / flag, the
## budget covers the solution, every bot waypoint stands on something and plain walks never cross a hole,
## the path ends at the flag and visits the lost friend), the same seed gives the same course, every
## challenge kind shows up, later adventures have more challenges, the story rules (story.gd), and
## generation stays fast. The real proof is the bot playing generated courses (BB_START_LEVEL=9+).
## Prints "SCRIPT ERROR: ..." for each failure.

const CourseGen := preload("res://games/block_builders/coursegen.gd")
const Story := preload("res://games/block_builders/story.gd")
const Seeded := preload("res://core/seeded.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 80
	var total := 0
	var t0 := Time.get_ticks_usec()
	var gens := 0
	var kinds := {}
	var nch := {}
	for adv in 13:
		var r := Seeded.validate(func(s: int) -> Dictionary: return CourseGen.generate(s, adv),
			func(lv: Dictionary) -> Array: return CourseGen.check(lv), seeds, 3 + adv, [0, 1, 999999], "SKY %d" % adv)
		total += int(r.checked)
		gens += int(r.checked) * 2
		fails += (r.failures as Array).size()
		for s in 20:
			var lv := CourseGen.generate(700 + s, adv)
			for k in lv.challenges:
				kinds[k] = int(kinds.get(k, 0)) + 1
			nch[adv] = int(nch.get(adv, 0)) + (lv.challenges as Array).size()
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens)
	print("sky gen: %.3f ms per course (%d courses)" % [per_ms, gens])
	_expect(per_ms < 20.0, "a course generates in under 20 ms here (%.2f ms)" % per_ms)
	for k in CourseGen.KINDS:
		_expect(int(kinds.get(k, 0)) >= 10, "challenge %s shows up (%s)" % [k, str(kinds)])
	_expect(int(nch[10]) > int(nch[0]), "later adventures have more challenges (%s)" % str(nch))
	# TODAY'S SKY: fair, the same all day, different day to day.
	var days := {}
	for d in 40:
		var date := Time.get_date_string_from_unix_time(1790000000 + d * 86400)
		var lv := Story.daily_course(date)
		for w in CourseGen.check(lv):
			_fail("daily %s: %s" % [date, w])
		_expect(var_to_str(lv) == var_to_str(Story.daily_course(date)), "daily %s is the same all day" % date)
		days[var_to_str(lv.ground)] = true
		total += 1
	_expect(days.size() >= 30, "daily courses differ (%d unique of 40)" % days.size())
	# Hand checks: the validator catches broken courses.
	var lv0 := CourseGen.generate(42, 4)
	var bad := lv0.duplicate(true)
	(bad.solution as Array).remove_at(0)
	var b2 := lv0.duplicate(true)
	b2.budget = {}
	_expect(not CourseGen.check(b2).is_empty(), "a short budget is caught")
	var b3 := lv0.duplicate(true)
	(b3.bot_path as Array).append([Vector3(0.5, 9.0, 0.5), ""])
	_expect(not CourseGen.check(b3).is_empty(), "a waypoint in the air is caught")
	var gap := CourseGen.generate(7, 0)
	var had_gap := false
	for s in 40:
		var g := CourseGen.generate(s, 1)
		if (g.challenges as Array).has("gap"):
			var b4 := g.duplicate(true)
			var sol: Array = b4.solution
			for i in sol.size():
				if String(sol[i][0]) == "plank" and (sol[i][1] as Vector3i).z == 0:
					sol.remove_at(i)
					break
			_expect(not CourseGen.check(b4).is_empty(), "a missing bridge plank is caught (seed %d)" % s)
			had_gap = true
			break
	_expect(had_gap, "found a course with a gap")
	# Story.
	_expect(Story.FRIENDS.size() >= 12, "plenty of cloud friends to find")
	_expect(Story.level_index(0) == Story.LESSONS, "adventure 0 comes right after the lessons")
	_expect(Story.adventure_of(Story.level_index(5)) == 5, "level index <-> adventure")
	_expect(Story.is_daily(Story.DAILY_INDEX), "the daily level has its own index")
	print("sky gen: %d courses checked, %d failures" % [total, fails])
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: sky gen: " + what)
