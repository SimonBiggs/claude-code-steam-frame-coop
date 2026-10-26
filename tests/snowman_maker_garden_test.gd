extends SceneTree
## SNOWMAN MAKER gardens: checks the seeded garden generator over many seeds (no game, no window).
##   godot-test --headless --path . -s res://tests/snowman_maker_garden_test.gd      (SEEDS=500 for more)
## For every chapter (and the mixed bonus / daily chapter): gardengen.gd check() (boxes reachable by
## the VR builder and every player, every spawn's snowball rollable to the circle at full size, no
## overlaps, features only in their chapter, wishes only for hats in the boxes) and determinism;
## plus the story rules (goals, stars, advance, village pieces, unlocks, next round, save defaults).
## Prints "SCRIPT ERROR: ..." for each failure.

const GardenGen := preload("res://games/snowman_maker/gardengen.gd")
const Story := preload("res://games/snowman_maker/story.gd")
const Seeded := preload("res://core/seeded.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 200
	var t0 := Time.get_ticks_msec()
	var total := 0
	for chap in Story.CHAPTERS.size():
		var r := Seeded.validate(func(s: int) -> Dictionary: return GardenGen.garden(s, chap),
			GardenGen.check, seeds, 17 + chap, [Seeded.daily_seed("snowman_maker", "2026-10-25"), 0, 1, 999999],
			"GARDEN ch%d" % chap)
		total += int(r.checked)
		fails += (r.failures as Array).size()
	# Variety: different seeds give different gardens.
	var a := GardenGen.garden(5, 3)
	var b := GardenGen.garden(6, 3)
	_expect(var_to_str(a.trees) != var_to_str(b.trees), "different seeds give different trees")
	_story_checks()
	print("GARDEN: %d gardens checked, %d failures (%d ms)" % [total, fails, Time.get_ticks_msec() - t0])
	quit(1 if fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: GARDEN %s" % what)


func _story_checks() -> void:
	var g1: Array = Story.goals(1, 0, 0, 0, 150.0)
	var g4: Array = Story.goals(4, 0, 0, 0, 150.0)
	_expect(int(g4[0]) > int(g1[0]), "goals grow with builders")
	_expect(int(g1[0]) < int(g1[1]) and int(g1[1]) < int(g1[2]), "1-2-3 star goals rise")
	var gm: Array = Story.goals(1, 0, 9, 0, 150.0)
	_expect(int(gm[0]) <= int(g1[0]) and int(gm[0]) >= 1, "misses lower the goal, never to zero")
	_expect(Story.stars_for(0, g1) == 0 and Story.stars_for(int(g1[2]), g1) == 3, "stars_for")
	_expect(Story.points(3, 2) == 5, "points: snowmen + wishes")
	# Walk the whole story: 15 days with a star each reach the bonus days.
	var c := 0
	var d := 0
	var laps := 0
	var stars := {}
	for i in Story.MIXED * Story.DAYS_PER_CHAPTER:
		stars["%d-%d" % [c, d]] = 1
		var adv := Story.advance(c, d, laps, 0, 1)
		c = int(adv.chapter)
		d = int(adv.day)
		laps = int(adv.laps)
	_expect(c == Story.MIXED and d == 0, "15 good days reach the bonus days (got ch%d day%d)" % [c, d])
	_expect(Story.village(stars) == [3, 3, 3, 3, 3], "every place fully built")
	var miss := Story.advance(2, 1, 0, 0, 0)
	_expect(int(miss.chapter) == 2 and int(miss.day) == 1 and int(miss.misses) == 1, "a day with no star stays")
	_expect(Story.unlocked(0).is_empty() and Story.unlocked(999).size() == Story.UNLOCKS.size(), "unlocks")
	_expect(Story.newly_unlocked(2, 3) == ["SCARVES"], "newly unlocked")
	var fresh := Story.save_defaults()
	_expect(Story.next_round(fresh, "daily:2026-10-25") == ["story", 0, 0], "a new builder starts in the cosy garden")
	fresh["chapter"] = 2
	_expect(String(Story.next_round(fresh, "daily:2026-10-25")[0]) == "daily", "the first game of the day is the daily garden")
	fresh["daily"] = {"daily:2026-10-25": 3}
	_expect(Story.next_round(fresh, "daily:2026-10-25") == ["story", 2, 0], "then the story goes on")
	for ch in Story.CHAPTERS:
		_expect(String(ch.intro).length() <= 60 and String(ch.done).length() <= 60, "short story lines (%s)" % ch.name)
