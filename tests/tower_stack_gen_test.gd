extends SceneTree
## TOWER STACK generator: proves every seeded tower job is buildable and fair (no game, no window).
##   godot-test --headless --path . -s res://tests/tower_stack_gen_test.gd      (SEEDS=500 for more)
## For every level 1-6 and TODAY'S TOWER: games/tower_stack/towergen.gd check() (physics-aware: every
## block rests on something, every block and every cut through the tower keeps its centre of mass over
## its support even leaning by the worst gust + the jelly stage's sway, nothing slides; the plan fits
## the stage and the giant's reach; the set has every block in order plus spares; crews of 0-6 can
## build it well inside a round), the same seed gives the same job, the challenge grows level by level,
## every building / block kind / ground shows up, TODAY'S TOWER is the same all day and differs between
## days, the town has room and stands clear of the park and the trees, Wren's pictures exist, the
## constants match the game's, and generation stays fast (Decks are slow). Prints "SCRIPT ERROR: ..."
## per failure.

const G := preload("res://games/tower_stack/towergen.gd")
const Looks := preload("res://games/tower_stack/looks.gd")
const Main := preload("res://games/tower_stack/main.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 150
	var t0 := Time.get_ticks_usec()
	var gens := 0
	var seen := {}
	var avg_top := {}
	var avg_blocks := {}
	var windy := {}
	for lv in range(1, G.MAX_LEVEL + 1):
		var res := Seeded.validate(func(s: int) -> Dictionary: return G.site(s, lv),
			func(st: Dictionary) -> Array: return G.check(st), seeds, 11 + lv, [0, 999999], "TOWER level %d" % lv)
		gens += int(res.checked) * 2
		fails += (res.failures as Array).size()
		for s in 60:
			var st := G.site(s * 13 + 1, lv)
			avg_top[lv] = float(avg_top.get(lv, 0.0)) + float(st.top) / 60.0
			avg_blocks[lv] = float(avg_blocks.get(lv, 0.0)) + (st.plan as Array).size() / 60.0
			windy[lv] = float(windy.get(lv, 0.0)) + (float(st.wind) / G.GRAVITY + tan(float(st.sway))) / 60.0
			seen["b:" + String(st.building)] = true
			seen["g:" + String(st.ground)] = true
			for b in st.plan:
				seen["k:%d" % int(b[0])] = true
			if float(st.wind) > 0.0:
				seen["wind"] = true
			if float(st.sway) > 0.0:
				seen["sway"] = true
			for c in st.palette:
				seen["c:%d" % int(c)] = true
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens)
	print("tower gen: %.3f ms per job incl. check (%d jobs)" % [per_ms, gens])
	_expect(per_ms < 5.0, "a job generates + checks in under 5 ms here (%.2f ms; Decks are slower, aim < 100)" % per_ms)
	print("average top per level: %s" % str(avg_top))
	print("average blocks per level: %s" % str(avg_blocks))
	print("average lean (wind + sway) per level: %s" % str(windy))
	for lv in range(2, G.MAX_LEVEL + 1):
		_expect(float(avg_blocks[lv]) >= float(avg_blocks[lv - 1]) - 0.01, "levels never get smaller (%d)" % lv)
		_expect(float(windy[lv]) >= float(windy[lv - 1]) - 0.001, "weather never gets calmer going up (%d)" % lv)
	_expect(float(avg_top[G.MAX_LEVEL]) > float(avg_top[1]) + 0.6, "top towers are clearly taller than warm-ups")
	for b in G.BUILDINGS:
		_expect(seen.has("b:" + b), "building %s shows up" % b)
	for g in G.GROUNDS:
		_expect(seen.has("g:" + g), "ground %s shows up" % g)
	for k in G.KINDS.size():
		_expect(seen.has("k:%d" % k), "block kind %s is used" % G.KINDS[k])
	for c in Looks.COLORS.size():
		_expect(seen.has("c:%d" % c), "colour %d is used" % c)
	_expect(seen.has("wind") and seen.has("sway"), "windy and wobbly sites happen")
	for n in range(1, 12):
		for built in [0, 5, 20, 200]:
			_expect(G.level(n + 1, built) >= G.level(n, built), "levels never drop within a round")
			_expect(G.level(n, built) >= 1 and G.level(n, built) <= G.MAX_LEVEL, "level in range")
	_expect(G.level(1, 0) == 1, "the very first tower is the easiest")
	# The validator really catches broken towers (it isn't just saying yes).
	var bad := G.site(5, 3)
	var tipsy: Array = (bad.plan as Array).duplicate(true)
	tipsy[tipsy.size() - 1][1] = float(tipsy[tipsy.size() - 1][1]) + G.B * 0.8
	_expect(not G.stability(tipsy, 0.0).is_empty(), "a top block hanging off the edge is caught")
	var floating: Array = (bad.plan as Array).duplicate(true)
	floating[floating.size() - 1][2] = float(floating[floating.size() - 1][2]) + 0.5
	_expect(not G.stability(floating, 0.0).is_empty(), "a floating block is caught")
	_expect(not G.stability(bad.plan, 0.9).is_empty(), "a hurricane knocks any tower over")
	var short := bad.duplicate(true)
	(short.set as Array).resize((bad.plan as Array).size() - 1)
	_expect(not G.check(short).is_empty(), "a set missing blocks is caught")
	var col := [[0, 0.0, 0.5, 0.0, 0], [0, 0.0, 1.1, 0.0, 0], [0, 0.0, 1.7, 0.0, 0], [0, 0.0, 2.3, 0.0, 0], [0, 0.0, 2.9, 0.0, 0]]
	var lim := G.safe_tan(col)
	_expect(lim > 0.05 and lim < 0.3, "five cubes in a column tip at a sensible lean (%.3f)" % lim)
	# TODAY'S TOWER: valid, the same all day, different between days.
	for date in ["2026-10-29", "2026-12-25", "2027-01-01"]:
		var ds := G.daily_seed(date)
		var st := G.site(ds, G.DAILY_LEVEL, true)
		for why in G.check(st):
			_expect(false, "TODAY'S TOWER %s: %s" % [date, why])
		_expect(var_to_str(st) == var_to_str(G.site(G.daily_seed(date), G.DAILY_LEVEL, true)), "TODAY'S TOWER is the same all day")
		_expect(var_to_str(G.from_job(G.job_of(st))) == var_to_str(st), "the job description rebuilds the same tower on the TV")
	_expect(G.daily_seed("2026-10-29") != G.daily_seed("2026-10-30"), "a new TODAY'S TOWER each day")
	# The town: room for plenty, each tower its own spot, clear of the park edge and the tree ring.
	var slots := G.town_size()
	_expect(slots >= 25, "the town holds at least 25 towers (%d)" % slots)
	_expect(G.town_slot(slots) == Vector3.INF, "no slot past the end")
	_expect(G.TOWN_KEEP >= slots, "the save keeps at least a full town")
	var spots: Array = []
	for i in slots:
		var at := G.town_slot(i)
		var r := Vector2(at.x, at.z).length()
		_expect(r > G.ARENA + 1.0, "town slot %d stands outside the park (%.1f)" % [i, r])
		_expect(r < G.ARENA + 3.5, "town slot %d stands before the trees (%.1f)" % [i, r])
		_expect(at.z < -2.0, "town slot %d is behind the stage, in view (%s)" % [i, str(at)])
		for o in spots:
			_expect((o as Vector3).distance_to(at) > G.TOWN_STEP * 0.9, "town slot %d has room" % i)
		spots.append(at)
	_expect(G.town_slot(0).distance_to(Vector3(0, 0, -G.TOWN_R[0])) < 0.01, "the first tower stands right behind the stage")
	# The game uses the same numbers.
	_expect(is_equal_approx(G.B, Looks.BLOCK), "block size matches looks.gd")
	_expect(is_equal_approx(G.BASE_R, Main.BASE_R) and is_equal_approx(G.BASE_H, Main.BASE_H), "stage size matches main.gd")
	_expect(is_equal_approx(G.ARENA, Main.ARENA), "park size matches main.gd")
	_expect(is_equal_approx(G.VR_SPOT.y, Main.VR_SPOT.z), "the giant's spot matches main.gd")
	for pic in ["wren", "tower"]:
		_expect(StoryCard.PICTURES.has(pic), "story picture %s exists" % pic)
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: %s" % what)
