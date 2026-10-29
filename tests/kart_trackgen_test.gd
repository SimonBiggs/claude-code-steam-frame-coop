extends SceneTree
## KART RACE track generator: proves the seeded tracks are fair over many seeds (no game, no window).
##   godot-test --headless --path . -s res://tests/kart_trackgen_test.gd      (SEEDS=40 for more)
## For every Grand Tour race spec (6 places x 3 races, the story and a bonus tour) and 60 days of TODAY'S
## TRACK: games/kart_race/trackgen.gd check() (closed loop, never near itself, drivable bends, gentle
## hills, a straight flat start for the grid, fair jumps at every kart speed, things on the road and off
## the island, no prop spots inside the walls), the same seed gives the same track, no hand-made fallback,
## the features each spec asks for are there, and the story rules (where / hats / descriptions / save).
## Prints "SCRIPT ERROR: ..." for each failure and "KART TRACKGEN: PASS" or "FAIL" (exit code 1).

const TrackGen := preload("res://games/kart_race/trackgen.gd")
const Story := preload("res://games/kart_race/story.gd")
const Seeded := preload("res://core/seeded.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 12
	var t0 := Time.get_ticks_msec()
	var total := 0
	var attempts := {}
	var lens: Array[float] = []
	var slowest := 0
	for tour in 2:
		for pl in Story.PLACES.size():
			for step in Story.RACES_PER_PLACE:
				var i := (tour * Story.PLACES.size() + pl) * Story.RACES_PER_PLACE + step
				var sp := Story.spec(i)
				var r := Seeded.validate(func(s: int) -> Dictionary: return TrackGen.generate(s, sp),
					func(info: Dictionary) -> Array:
						var why := TrackGen.check(info)
						if info.has("fallback"):
							why.append("fell back to a hand-made track")
						if (info.get("splits", []) as Array).size() < int(sp.splits):
							why.append("missing split lanes")
						if (info.get("ramps", []) as Array).size() < 1:
							why.append("no ramp")
						if (info.get("items", []) as Array).size() < 2:
							why.append("too few ? box rows")
						return why,
					seeds, 11 + i * 3, [0, 1, 999999], "KART TRACK race %d" % i)
				total += int(r.checked)
				fails += (r.failures as Array).size()
				for s in 4:
					var ts := Time.get_ticks_msec()
					var info := TrackGen.generate(500 + s * 31 + i, sp)
					slowest = maxi(slowest, Time.get_ticks_msec() - ts)
					attempts[int(info.get("attempt", -1))] = int(attempts.get(int(info.get("attempt", -1)), 0)) + 1
					var tr := TrackGen.Track.new()
					tr.prepare(info)
					lens.append(tr.length)
					tr.free()
	# Today's track: fair for 60 days, the same all day, different on different days.
	var day_seeds := {}
	for d in 60:
		var date := Time.get_date_string_from_unix_time(1790000000 + d * 86400)
		var desc := Story.daily_desc(date)
		var a: Array = Story.track_for(desc)
		var info: Dictionary = a[0]
		var why := TrackGen.check(info)
		if info.has("fallback"):
			why.append("fell back")
		if var_to_str(Story.track_for(desc)[0]) != var_to_str(info):
			why.append("not the same all day")
		for w in why:
			_fail("TODAY'S TRACK %s: %s" % [date, w])
		day_seeds[int(desc[1])] = true
		total += 1
	_expect(day_seeds.size() >= 55, "today's tracks differ day to day (%d of 60)" % day_seeds.size())
	# Story rules.
	_expect(Story.where(0) == [0, 0, 0] and Story.where(5) == [1, 2, 0] and Story.where(18) == [0, 0, 1], "where()")
	_expect(Story.hats_after(1) == 0 and Story.hats_after(2) == 1 and Story.hats_after(17) == 6 and Story.hats_after(40) == 6, "hats_after()")
	_expect(Story.hat_for(0, 0) == -1 and Story.hat_for(0, 3) == 2 and Story.hat_for(1, 3) == 1 and Story.hat_for(5, 3) == 0, "hat_for()")
	_expect(Story.HATS.size() == Story.PLACES.size(), "one hat per place")
	_expect(Story.key_for(Story.story_desc(5, 3)) == Story.track_for(Story.story_desc(5, 3))[1], "key_for matches track_for")
	_expect(Story.story_desc(7, 2) == Story.story_desc(7, 2) and Story.story_desc(7, 2) != Story.story_desc(8, 2), "story descriptions per world")
	var d := Story.save_defaults()
	for k in ["world", "story_i", "hats", "champs", "golds", "races", "tours", "daily"]:
		_expect(d.has(k), "save default %s" % k)
	lens.sort()
	print("KART TRACKGEN: %d tracks checked in %d ms; lengths %.0f..%.0f m (median %.0f); attempts %s; slowest %d ms" % [
		total, Time.get_ticks_msec() - t0, lens[0], lens[-1], lens[lens.size() / 2], str(attempts), slowest])
	_expect(not attempts.has(-1), "no fallbacks")
	_expect(slowest < 1500, "a track generates in under 1.5 s (%d ms)" % slowest)
	print("KART TRACKGEN: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	if fails <= 40:
		print("SCRIPT ERROR: KART TRACKGEN: " + what)
