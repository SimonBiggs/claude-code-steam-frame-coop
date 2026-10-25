extends SceneTree
## PAPER PLANES skies: checks the seeded flight generator over many seeds (no game, no window).
##   godot-test --headless --path . -s res://tests/paper_planes_sky_test.gd      (SEEDS=500 for more)
## For every chapter (and the mixed bonus/daily chapter), with and without the RAINBOWS breeze:
##  - every hoop is inside the sky the TV planes fly in and the VR player can throw to, never edge-on
##    to the thrower, never overlapping another hoop (drift included);
##  - chains are numbered in order and each next hoop can be reached from the last one's facing;
##  - grumpy clouds never sit on a hoop, never block the VR throw line, always leave one way in;
##    Gust's golden hoop path stays in the sky and clear of clouds;
##  - features only arrive in their chapter; the same seed gives the same flight (determinism);
## plus the story rules (goals, stars, chapter advance, village pieces, unlocks, saves).
## Prints "SCRIPT ERROR: ..." for each failure.

const SkyGen := preload("res://games/paper_planes/skygen.gd")
const Story := preload("res://games/paper_planes/story.gd")
const Seeded := preload("res://core/seeded.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 200
	var t0 := Time.get_ticks_msec()
	var total := 0
	var shapes := {}
	for chap in Story.CHAPTERS.size():
		for lucky in [false, true]:
			var r := Seeded.validate(func(s: int) -> Dictionary: return SkyGen.flight(s, chap, {"lucky": lucky}),
				SkyGen.check, seeds, 11 + chap, [Seeded.daily_seed("paper_planes", "2026-10-25"), 0, 1, 999999],
				"SKY ch%d%s" % [chap, " lucky" if lucky else ""])
			total += int(r.checked)
			fails += (r.failures as Array).size()
		for s in 20:
			for f in SkyGen.flight(100 + s, chap).formations:
				shapes[f.shape] = int(shapes.get(f.shape, 0)) + 1
	_expect(shapes.size() == SkyGen.SHAPES.size(), "every formation shape appears (%s)" % str(shapes))
	_story_checks()
	print("SKY: %d flights checked, %d failures (%d ms)" % [total, fails, Time.get_ticks_msec() - t0])
	quit(1 if fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: SKY %s" % what)


func _story_checks() -> void:
	# Goals: more players -> more points needed; misses make it kinder (never below half); stars count up.
	var g1: Array = Story.goals(1, 0, 0, 0, 100.0)
	var g4: Array = Story.goals(4, 0, 0, 0, 100.0)
	_expect(int(g4[0]) > int(g1[0]), "goals grow with players")
	_expect(int(g1[0]) < int(g1[1]) and int(g1[1]) < int(g1[2]), "1-2-3 star goals rise")
	var gm: Array = Story.goals(1, 0, 9, 0, 100.0)
	_expect(int(gm[0]) < int(g1[0]) and int(gm[0]) >= int(g1[0]) / 2 - 1, "misses lower the goal, not below half")
	_expect(Story.stars_for(0, g1) == 0 and Story.stars_for(int(g1[2]), g1) == 3, "stars_for")
	# Advance through the whole story: 15 flights with a star each reach the bonus skies.
	var c := 0
	var f := 0
	var laps := 0
	var done := false
	for i in 15:
		var r := Story.advance(c, f, laps, 0, 1)
		c = int(r.chapter)
		f = int(r.flight)
		laps = int(r.laps)
		done = done or bool(r.story_done)
	_expect(c == Story.MIXED and f == 0 and done, "15 good flights finish the story (chapter %d flight %d)" % [c, f])
	var miss := Story.advance(2, 1, 0, 1, 0)
	_expect(int(miss.chapter) == 2 and int(miss.flight) == 1 and int(miss.misses) == 2, "a flight with no star is tried again")
	var bonus := Story.advance(Story.MIXED, 2, 0, 0, 2)
	_expect(int(bonus.laps) == 1 and int(bonus.chapter) == Story.MIXED, "bonus skies count laps")
	var v := Story.village({"0-0": 2, "0-1": 1, "1-0": 3, "4-2": 1})
	_expect(v == [2, 1, 0, 0, 1], "village pieces from stars (%s)" % str(v))
	_expect(Story.newly_unlocked(2, 3) == ["RAINBOW TRAILS"], "3 stamps unlock rainbow trails")
	# Gates: two different breezes plus DAILY, deterministic per seed.
	for s in 50:
		var a: Array = Story.gate_choices(Seeded.rng(s, "gates"))
		_expect(a.size() == 3 and a[0] != a[1] and a[2] == Story.DAILY_GATE, "gate choices %s" % str(a))
		_expect(a == Story.gate_choices(Seeded.rng(s, "gates")), "gate choices are seeded")
	_expect(Seeded.daily_seed("paper_planes", "2026-10-25") == Seeded.daily_seed("paper_planes", "2026-10-25")
		and Seeded.daily_seed("paper_planes", "2026-10-25") != Seeded.daily_seed("paper_planes", "2026-10-26"), "daily seed changes by day")
	# Saves: old saves (only "best") gain every new key.
	var Save := preload("res://core/save.gd")
	Engine.set_meta(Save.TEST_META, true)
	Save.store("paper_planes_test_old", {"best": 41})
	var d := Save.load_data("paper_planes_test_old", Story.save_defaults())
	for k in Story.save_defaults():
		_expect(d.has(k), "an old save gets '%s'" % k)
	_expect(int(d.best) == 41, "an old save keeps its best")
	Save.erase("paper_planes_test_old")
