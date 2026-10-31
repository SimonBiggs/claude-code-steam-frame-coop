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
const Cups := preload("res://games/kart_race/cups.gd")
const Items := preload("res://games/kart_race/items.gd")
const StoryCard := preload("res://core/story_card.gd")

var fails := 0
## core/ui_kit.gd icon kinds the cups / items use as pictures (StoryCard.picture draws them too).
const UI_ICONS: Array[String] = ["star", "flag", "fire", "clock", "crown", "trophy", "shield"]


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
	# Bolt's cups: every cup race at every speed, over many worlds - hazards placed, alone, a clear lane, CPU lines
	# clear of bumpers, corners makeable at speed, ? boxes reachable (TrackGen.check does all of it).
	var hz_seen := {}
	for c in Cups.CUPS.size():
		for race in Cups.RACES:
			for m in ["gentle", "zoom"]:
				var sp := Cups.spec(c, race, m)
				var cr := Seeded.validate(func(s: int) -> Dictionary: return TrackGen.generate(s, sp),
					func(info: Dictionary) -> Array:
						var why := TrackGen.check(info)
						if info.has("fallback"):
							why.append("fell back to a hand-made track")
						var hz: Array = info.get("hazards", [])
						var want := int(sp.patches) + int(sp.bumpers)
						if hz.size() < want:
							why.append("%d of %d hazards" % [hz.size(), want])
						if String(info.get("hz", "")) != String(Cups.cup(c).hz):
							why.append("wrong hazard kind")
						if (info.get("splits", []) as Array).size() < int(sp.splits):
							why.append("missing split lanes")
						for h in hz:
							hz_seen["%s/%s" % [info.get("hz", ""), h[2]]] = true
						return why,
					maxi(4, seeds / 2), 701 + c * 37 + race * 5 + (1 if m == "zoom" else 0), [3, 77], "KART CUP %s race %d %s" % [Cups.cup(c).id, race, m])
				total += int(cr.checked)
				fails += (cr.failures as Array).size()
				var ts := Time.get_ticks_msec()
				var info := TrackGen.generate(9000 + c * 13 + race, sp)
				slowest = maxi(slowest, Time.get_ticks_msec() - ts)
				attempts[int(info.get("attempt", -1))] = int(attempts.get(int(info.get("attempt", -1)), 0)) + 1
	for c in Cups.CUPS:
		for kind in ["patch", "bump"]:
			_expect(hz_seen.has("%s/%s" % [c.hz, kind]), "%s cup has %s hazards" % [c.id, kind])
	# Cups, karts, parts, speeds and the item set are fair (cups.gd / items.gd check()).
	var pic_ok := func(n: String) -> bool: return StoryCard.has_picture(n) or UI_ICONS.has(n)
	for w in Cups.check(pic_ok):
		_fail("CUPS: " + w)
	for w in Items.check(pic_ok):
		_fail("ITEMS: " + w)
	_expect(Cups.desc(5, 1, 2, "zoom") == Cups.desc(5, 1, 2, "zoom") and Cups.desc(5, 1, 2, "zoom") != Cups.desc(6, 1, 2, "zoom"), "cup descriptions per world")
	_expect(Story.key_for(Cups.desc(5, 2, 1, "gentle")) == Story.track_for(Cups.desc(5, 2, 1, "gentle"))[1], "cup key_for matches track_for")
	_expect(Story.key_for(Cups.desc(5, 2, 1, "gentle")) != Story.key_for(Cups.desc(5, 2, 1, "zoom")), "zoom cup tracks have more hazards")
	_expect(Cups.medal_for(1, "zoom") == 3 and Cups.medal_for(4, "zoom") == 0 and Cups.medal_for(6, "gentle") == 1 and Cups.medal_for(1, "trial") == 0, "medal_for()")
	_expect(Cups.parts_unlocked({}).is_empty() and Cups.parts_unlocked({"candy:gentle": 1, "ice:zoom": 0, "x": 3}).size() == 2, "parts_unlocked()")
	_expect(Cups.next_part("", {"candy:gentle": 1}) == "spoiler" and Cups.next_part("spoiler", {"candy:gentle": 1}) == "", "next_part()")
	_expect(Cups.next_cup({"candy:gentle": 2}, "gentle") == 1 and Cups.next_cup({"candy:gentle": 2}, "zoom") == 0, "next_cup()")
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
