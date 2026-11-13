extends SceneTree
## TOWER STACK third pass: Rolo's rolling balls (games/tower_stack/rollers.gd) are fair for every job, Wren's
## neighbours and village green (green.gd) grow as they should, and the seasons dress the park (season.gd).
##   godot-test --headless --path . -s res://tests/tower_stack_rollers_test.gd      (SEEDS=2000 for more)
## Rolls: for every mode, level, with and without TS_TRY=rollers (eager), over many seeds and 400+ days of TODAY'S
## TOWER, Rollers.check(): every lane stays in the park, misses the tower stage and the pad, is told WARN seconds
## first, never during a gust / quake, never two at once, never in gentle's first levels, slow enough to step out of;
## the same seed gives the same rolls; rolls do happen (brave level 2+, hard, eager). Green: the i-th neighbour is
## always the same, names and kinds vary, every neighbour / piece picture exists, pieces open in order and stand
## inside the green, the green stands clear of the park's walk edge, the town rows and the districts. Seasons: each
## season dresses, ARCADE_SEASON wins, every ground exists, every ball picture exists. Fast (Decks are slow).

const G := preload("res://games/tower_stack/towergen.gd")
const Rollers := preload("res://games/tower_stack/rollers.gd")
const Green := preload("res://games/tower_stack/green.gd")
const Season := preload("res://games/tower_stack/season.gd")
const Districts := preload("res://games/tower_stack/districts.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")
const SeasonKit := preload("res://core/season_kit.gd")
const TestTime := preload("res://tests/test_time.gd")

var fails := 0


func _initialize() -> void:
	var n := Seeded.test_count(300)
	var total := 0
	var happened := {}
	for md in G.MODE_IDS:
		for lv in range(1, int(G.tune(md).max) + 1):
			for eager in [false, true]:
				var res := Seeded.validate(func(sd: int) -> Dictionary:
						var st := G.site(sd, lv, false, md, G.OPEN_ALL)
						return {"site": st, "rolls": Rollers.plan(sd, lv, md, st.events, eager)},
					func(x: Dictionary) -> Array:
						return Rollers.check(x.rolls, x.site.events, lv, md, eager),
					n, 7 + lv, [0, 999999], "ROLLS %s level %d%s" % [md, lv, " eager" if eager else ""])
				total += int(res.checked)
				fails += (res.failures as Array).size()
				for sd in 20:
					var st2 := G.site(sd, lv, false, md, G.OPEN_ALL)
					var r := Rollers.plan(sd, lv, md, st2.events, eager)
					happened["%s:%d:%s" % [md, lv, eager]] = int(happened.get("%s:%d:%s" % [md, lv, eager], 0)) + r.size()
					_expect(r == Rollers.plan(sd, lv, md, st2.events, eager), "the same seed gives the same rolls")
	_expect(int(happened.get("brave:2:false", 0)) > 10, "brave level 2 jobs have rolls (%d)" % int(happened.get("brave:2:false", 0)))
	_expect(int(happened.get("hard:3:false", 0)) > int(happened.get("brave:3:false", 0)), "hard has more rolls than brave")
	_expect(int(happened.get("gentle:1:false", 0)) == 0 and int(happened.get("gentle:2:false", 0)) == 0, "gentle starts calm")
	_expect(int(happened.get("brave:1:true", 0)) >= 20, "TS_TRY=rollers rolls a ball in every job")
	# TODAY'S TOWER (job DAILY_N, every mode) over 400+ days.
	for md in G.MODE_IDS:
		var dres := Seeded.validate_days(func(day: String) -> Dictionary:
				var sd := G.daily_seed(day)
				var st := G.site(sd, G.DAILY_LEVEL, true, md, G.OPEN_ALL)
				return {"site": st, "rolls": Rollers.plan(sd, G.DAILY_LEVEL, md, st.events)},
			func(x: Dictionary) -> Array:
				return Rollers.check(x.rolls, x.site.events, G.DAILY_LEVEL, md),
			400, "DAILY ROLLS %s" % md)
		fails += (dres.failures as Array).size()
	# A bad lane is caught.
	_expect(not Rollers.check([[20.0, -8.0, 0.0, 8.0, 0.0, 3.8]], [], 3, "brave").is_empty(), "a lane over the stage fails check()")
	_expect(not Rollers.check([[20.0, -2.0, 8.0, 8.0, 3.0, 3.8], [21.0, 0.0, 8.6, 0.0, -8.6, 3.8]], [], 3, "brave").is_empty(), "rolls on top of each other fail check()")
	_expect(not Rollers.check([[20.0, -8.0, 4.0, 8.0, 4.0, 3.8]], [[22.0, "gust", 0.5]], 3, "brave").is_empty(), "a roll during a gust fails check()")
	# Rolls are quick to make (Decks are slow).
	var worst_ms := 0.0
	for sd in 200:
		var t1 := Time.get_ticks_usec()
		Rollers.plan(sd, 6, "hard", [[20.0, "gust", 0.5], [45.0, "quake", 0.02]])
		worst_ms = TestTime.worst(worst_ms, (Time.get_ticks_usec() - t1) / 1000.0, func() -> Variant: return Rollers.plan(sd, 6, "hard", [[20.0, "gust", 0.5], [45.0, "quake", 0.02]]))
	_expect(worst_ms < 5.0, "one job's rolls in < 5 ms (worst %.2f ms)" % worst_ms)
	_green()
	_seasons()
	for s in Rollers.BALLS:
		_expect(StoryCard.has_picture(String(Rollers.BALLS[s][0])), "%s ball picture exists" % s)
	_expect(StoryCard.has_picture("hedgehog"), "Rolo's picture exists")
	print("tower stack rollers: %d jobs checked" % total)
	print("TOWER STACK ROLLERS TEST: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func _green() -> void:
	var kinds := {}
	var names := {}
	for i in 200:
		var d := Green.neighbour(i)
		_expect(d == Green.neighbour(i), "neighbour %d is always the same" % i)
		kinds[d.kind] = true
		names[d.name] = true
		_expect(StoryCard.has_picture(String(d.pic)), "neighbour picture %s exists" % d.pic)
		if i > 0 and Green.neighbour(i - 1).kind == d.kind and Green.neighbour(i - 1).name == d.name:
			_expect(false, "two same neighbours in a row (%d)" % i)
	_expect(kinds.size() >= 7 and names.size() >= 15, "neighbours vary (%d kinds, %d names)" % [kinds.size(), names.size()])
	var prev := -1
	for g in Green.GROWS:
		_expect(int(g.at) > prev, "green pieces open in order")
		prev = int(g.at)
		_expect(StoryCard.has_picture(String(g.pic)), "green piece picture %s exists" % g.pic)
	_expect(Green.grown(0) == 0 and Green.grown(1000) == Green.GROWS.size(), "the green grows from nothing to everything")
	for k in Green.GROWS.size():
		_expect(Green.piece_spot(k).length() < Green.RADIUS - 0.4, "green piece %d stands on the green" % k)
		for j in k:
			_expect(Green.piece_spot(k).distance_to(Green.piece_spot(j)) > 0.9, "green pieces %d and %d stand apart" % [j, k])
	for k in Green.SHOW:
		for j in Green.GROWS.size():
			_expect(Green.folk_spot(k).distance_to(Green.piece_spot(j)) > 0.5, "neighbour %d stands clear of piece %d" % [k, j])
	var c := Green.CENTER
	_expect(Vector2(c.x, c.z) == Rollers.GREEN, "rollers.gd GREEN == green.gd CENTER")
	_expect(Vector2(c.x, c.z).length() + Green.RADIUS < G.ARENA + 1.0, "the green is in the park where everyone sees it")
	_expect(Vector2(c.x, c.z).length() - Green.RADIUS > G.BASE_R + 3.0, "the green leaves room round the stage")
	_expect(Vector2(c.x - Rollers.PAD.x, c.z - Rollers.PAD.y).length() > Green.RADIUS + 3.0, "the green is far from the pad")
	for k in Season.SPOTS.size():
		var sp := Vector3(cos(Season.SPOTS[k]), 0.0, sin(Season.SPOTS[k])) * Season.SPOT_R
		_expect(sp.distance_to(c) > Green.RADIUS + 1.0, "season prop %d is clear of the green" % k)
	for i in G.town_size():
		var p := G.town_slot(i)
		_expect(Vector2(p.x - c.x, p.z - c.z).length() > Green.RADIUS + 0.8, "the green is clear of town spot %d" % i)
	for k in Districts.LIST.size():
		var p2 := Districts.spot(k)
		_expect(Vector2(p2.x - c.x, p2.z - c.z).length() > Green.RADIUS + 1.3, "the green is clear of district %d" % k)


func _seasons() -> void:
	for s in SeasonKit.SEASONS:
		_expect(Rollers.BALLS.has(s) and Season.DRIFT.has(s) and StoryCard.has_picture(String(Season.PICS[s])), "%s is dressed" % s)
		for gr in G.GROUNDS:
			_expect(G.GROUND_COLORS.has(Season.ground(s, gr)), "%s ground for %s exists" % [s, gr])
	_expect(Season.ground("winter", "beach") == "snow", "winter is snowy")
	OS.set_environment("ARCADE_SEASON", "autumn")
	_expect(Season.pick() == "autumn", "ARCADE_SEASON wins")
	OS.unset_environment("ARCADE_SEASON")
	_expect(Season.pick() == Seeded.season(), "the date's season otherwise")


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: tower stack rollers: %s" % what)
