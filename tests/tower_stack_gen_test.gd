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
## Second pass: every level in every MODE (gentle / brave / hard) with no special blocks and with all of them open;
## special blocks keep towers standing (the validator weighs balloons light, bouncy blocks slippery, honey glued -
## and really catches a balloon blown off, a bouncy block sliding, an overhang only honey holds); weather events are
## announced in time and stay inside the tipping limit; DIFFICULTY rises smoothly job by job in every mode and over
## the days (districts open more special blocks), gentle <= brave <= hard; the builder pick always has 3 buildings;
## the districts open every special block, in order, standing clear of the town; old 3-long town entries rebuild.

const G := preload("res://games/tower_stack/towergen.gd")
const Looks := preload("res://games/tower_stack/looks.gd")
const Main := preload("res://games/tower_stack/main.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")
const Districts := preload("res://games/tower_stack/districts.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const MAX_STEP := 4.5  # difficulty never jumps more than this from one job to the next

var fails := 0


func _initialize() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 120
	var t0 := Time.get_ticks_usec()
	var gens := 0
	var seen := {}
	var avg_top := {}
	var avg_blocks := {}
	var windy := {}
	for md in G.MODE_IDS:
		for open in [0, G.OPEN_ALL]:
			for lv2 in range(1, int(G.tune(md).max) + 1):
				var res := Seeded.validate(func(s: int) -> Dictionary: return G.site(s, lv2, false, md, open),
					func(st: Dictionary) -> Array: return G.check(st), seeds / 2, 11 + lv2, [0, 999999], "TOWER %s open %d level %d" % [md, open, lv2])
				gens += int(res.checked) * 2
				fails += (res.failures as Array).size()
				for s in 40:
					var st := G.site(s * 7 + 3, lv2, false, md, open)
					for b in st.plan:
						seen["k:%d" % int(b[0])] = true
					for e in st.events:
						seen["e:" + String(e[1])] = true
					if md == "gentle":
						_expect(G.worst_lean(st) == 0.0 and (st.events as Array).is_empty(), "gentle jobs are calm")
	for lv in range(1, G.MAX_LEVEL + 1):
		for s in 60:
			var st := G.site(s * 13 + 1, lv)
			avg_top[lv] = float(avg_top.get(lv, 0.0)) + float(st.top) / 60.0
			avg_blocks[lv] = float(avg_blocks.get(lv, 0.0)) + (st.plan as Array).size() / 60.0
			windy[lv] = float(windy.get(lv, 0.0)) + G.difficulty(st) / 60.0
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
	print("average difficulty per level: %s" % str(windy))
	for lv in range(2, G.MAX_LEVEL + 1):
		_expect(float(avg_blocks[lv]) >= float(avg_blocks[lv - 1]) - 0.01, "levels never get smaller (%d)" % lv)
		_expect(float(windy[lv]) >= float(windy[lv - 1]) - 0.001, "levels never get easier going up (%d)" % lv)
	_expect(seen.has("e:gust") and seen.has("e:quake"), "gusts and quakes both happen")
	_difficulty_curve()
	_specials()
	_districts_and_picks()
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
	for n in range(1, 12):
		for built in [0, 8, 20]:
			_expect(G.level(n, built, "gentle") <= G.level(n, built) and G.level(n, built) <= G.level(n, built, "hard"), "gentle <= brave <= hard levels")
			_expect(G.level(n + 1, built, "hard") >= G.level(n, built, "hard"), "hard levels never drop")
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
		for md in G.MODE_IDS:
			var st2 := G.site(ds, G.DAILY_LEVEL, true, md, G.OPEN_ALL)
			_expect(var_to_str(G.from_job(G.job_of(st2))) == var_to_str(st2), "a %s job with special blocks rebuilds on the TV" % md)
			for why in G.check(st2):
				_expect(false, "TODAY'S TOWER %s %s: %s" % [date, md, why])
	# Old saves: 3-long town entries rebuild as the brave job with nothing open (the first pass's jobs).
	for sd in [1, 77, 4242]:
		_expect(var_to_str(G.from_job([sd, 4, 0])) == var_to_str(G.site(sd, 4)), "an old town entry rebuilds the same tower")
		_expect(int(G.site(sd, 4).specials) == 0, "no special blocks before a district opens them")
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
	_expect(G.MODE_IDS == PickOrbs.MODE_IDS, "the modes are the shared pick's modes")
	_expect(Looks.SIZES.size() == G.KINDS.size() and G.SIZE.size() == G.KINDS.size() and G.MASS.size() == G.KINDS.size()
		and G.HEAVY.size() == G.KINDS.size() and G.FRIC.size() == G.KINDS.size() and G.BOUNCE.size() == G.KINDS.size()
		and G.TRIP.size() == G.KINDS.size(), "every block kind has a size, weight, grip, bounce and trip time")
	for pic in ["wren", "tower", "cloud", "wave", "house", "bouncyblock", "honeyblock", "balloonblock", "lighthouse",
			"castle", "clocktower", "windmill", "birdnest", "gust", "quake"]:  # every picture Wren shows
		_expect(StoryCard.has_picture(pic), "story picture %s exists" % pic)
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)


## Difficulty: the average job n of a round, for every mode and as the town grows (more special blocks open), rises
## smoothly (never easier, never a big jump), and gentle <= brave <= hard.
func _difficulty_curve() -> void:
	for built in [0, 8, 16, 40]:
		var rows := {}
		for md in G.MODE_IDS:
			var row: Array = []
			for n in range(1, 8):
				var sum := 0.0
				for k in 50:
					sum += G.difficulty(G.site(Seeded.derive(k, "curve"), G.level(n, built, md), false, md, Districts.open_mask(built)))
				row.append(snappedf(sum / 50.0, 0.01))
			rows[md] = row
			for n in range(1, row.size()):
				_expect(float(row[n]) >= float(row[n - 1]) - 0.05, "%s (built %d): job %d is never easier than job %d (%s)" % [md, built, n + 1, n, str(row)])
				_expect(float(row[n]) - float(row[n - 1]) <= MAX_STEP, "%s (built %d): no big jump at job %d (%s)" % [md, built, n + 1, str(row)])
		for n in 7:
			_expect(float(rows.gentle[n]) <= float(rows.brave[n]) + 0.01 and float(rows.brave[n]) <= float(rows.hard[n]) + 0.01,
				"built %d job %d: gentle <= brave <= hard (%s / %s / %s)" % [built, n + 1, rows.gentle[n], rows.brave[n], rows.hard[n]])
		print("difficulty, built %d: %s" % [built, str(rows)])


## Special blocks keep towers standing: every generated job with them checks out (above); here the validator is
## shown to really weigh them, and every special block shows up.
func _specials() -> void:
	for k in G.SPECIALS:
		_expect(seen_kind(k), "special block %s shows up when open" % G.KINDS[k])
	var col := [[0, 0.0, 0.5, 0.0, 0], [0, 0.0, 1.1, 0.0, 0], [0, 0.0, 1.7, 0.0, 0]]
	var cubes := G.safe_tan(col)
	var balloon := col.duplicate(true)
	balloon[2][0] = G.K_BALLOON
	_expect(G.safe_tan(balloon) < cubes - 0.02, "a balloon on top tips at a smaller lean (%.3f < %.3f)" % [G.safe_tan(balloon), cubes])
	var bouncy := col.duplicate(true)
	bouncy[1][0] = G.K_BOUNCY
	_expect(not G.stability(bouncy, 0.62).filter(func(w: String) -> bool: return w.contains("slides")).is_empty(), "blocks slide on a slippery bouncy block")
	# An overhang only honey holds: a cube hanging most of the way off its support.
	var hang := [[0, 0.0, 0.5, 0.0, 0], [0, 0.4, 1.1, 0.0, 0]]
	_expect(not G.stability(hang, 0.0).is_empty(), "a cube hanging off the edge tips")
	var honey := hang.duplicate(true)
	honey[0][0] = G.K_STICKY
	_expect(G.stability(honey, 0.0).is_empty(), "honey under it holds the overhang")
	# Every special job's specials sit where the plan had a cube (same shape), and none appear unopened.
	for sd in 200:
		var st := G.site(sd, 5, false, "hard", G.OPEN_ALL)
		var plain := G.site(sd, 5, false, "hard", 0)
		for i in (st.plan as Array).size():
			var a: Array = st.plan[i]
			var b: Array = plain.plan[i]
			_expect(int(a[0]) == int(b[0]) or (G.is_special(int(a[0])) and int(b[0]) == G.K_CUBE), "special blocks only replace cubes")
			_expect(Vector3(a[1], a[2], a[3]) == Vector3(b[1], b[2], b[3]), "special blocks keep the plan's shape")


func seen_kind(k: int) -> bool:
	for sd in 300:
		for b in G.site(sd, 4, false, "brave", G.OPEN_ALL).plan:
			if int(b[0]) == k:
				return true
	return false


## The districts open every special block in order and stand clear of the town; the builder pick has 3 buildings.
func _districts_and_picks() -> void:
	_expect(Districts.reached(0) == 1 and Districts.open_mask(0) == 0, "a new town has one district and no special blocks")
	var last := 0
	for built in 80:
		var m := Districts.open_mask(built)
		_expect(m & last == last and Districts.reached(built) >= Districts.reached(maxi(0, built - 1)), "districts never close")
		last = m
	_expect(last == G.OPEN_ALL, "the districts open every special block")
	for i in Districts.LIST.size():
		var d: Dictionary = Districts.LIST[i]
		_expect(StoryCard.has_picture(String(d.pic)), "district %s has a picture" % d.id)
		_expect(String(d.name).length() <= 14, "district %s has a short name" % d.id)
		if i > 0:
			_expect(int(d.at) > int(Districts.LIST[i - 1].at), "districts open one after another")
		var at := Districts.spot(i)
		_expect(at.z < -4.0, "district %d stands behind the park (%s)" % [i, str(at)])
		_expect(Vector2(at.x, at.z).length() > G.TOWN_R[G.TOWN_R.size() - 1] + 0.8, "district %d stands behind the town rows" % i)
		for j in i:
			_expect(Districts.spot(j).distance_to(at) > 2.4, "districts %d and %d have room" % [j, i])
	for sd in 300:
		var offer := G.choices(sd, 1 + sd % 3, 3, 3, G.MODE_IDS[sd % 3], sd % 8)
		_expect(offer.size() == G.CHOICES, "the builder pick finds three buildings (session %d)" % sd)
		for st in offer:
			_expect(G.check(st).is_empty(), "every building on the pick is buildable")


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: %s" % what)
