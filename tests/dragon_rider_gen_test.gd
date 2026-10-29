extends SceneTree
## DRAGON RIDER generator: proves every seeded sky route is flyable, comfy and fair (no game, no window).
##   godot-test --headless --path . -s res://tests/dragon_rider_gen_test.gd      (SEEDS=500 for more)
## For every stage 1-12 (its mission), from different start spots and headings: games/dragon_rider/routegen.gd
## check() (height band, gentle turns and climbs at the stage's cruise speed, long enough legs, islands off the
## flight path and away from the rings, balloons in the gunners' reach, bunnies close enough to scoop, the golden
## balloon once met), the same seed gives the same route, routes differ between seeds, stages grow gently,
## TODAY'S FLIGHT is the same all day and differs between days, the charm slots fit on the deck, Sunny's pictures
## exist, the constants match the game's, and generation stays fast. Prints "SCRIPT ERROR: ..." per failure.

const G := preload("res://games/dragon_rider/routegen.gd")
const Main := preload("res://games/dragon_rider/main.gd")
const Course := preload("res://games/dragon_rider/course.gd")
const Dragon := preload("res://games/dragon_rider/dragon.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 60
	var t0 := Time.get_ticks_usec()
	var gens := 0
	var gentle := 0
	var avg_rings := {}
	for lv in range(1, G.MAX_STAGE + 1):
		var mis: String = Main.mission_for(lv)
		var res := Seeded.validate(func(s: int) -> Dictionary:
				var r := Seeded.rng(s, "start")
				return G.route(s, Vector3(r.randf_range(-500, 500), r.randf_range(25, 80), r.randf_range(-500, 500)), r.randf_range(-PI, PI), lv, mis),
			func(r: Dictionary) -> Array: return G.check(r), seeds, 7 + lv, [0, 999999], "ROUTE stage %d (%s)" % [lv, mis])
		gens += int(res.checked)
		fails += (res.failures as Array).size()
		for k in 20:
			var r := G.route(k * 31 + 5, Vector3(0, 45, 0), 0.0, lv, mis)
			if int(r.seed) != k * 31 + 5:
				_expect(false, "the route keeps its seed")
			avg_rings[lv] = float(avg_rings.get(lv, 0.0)) + (r.rings as Array).size() / 20.0
			if G._make(k * 31 + 5, Vector3(0, 45, 0), 0.0, lv, mis, true, 0).hash() != r.hash():
				gentle += 1
			if mis == "rescue":
				_expect(not (r.critters as Array).is_empty(), "rescue stages have bunnies")
			if mis == "boss":
				_expect((r.rings as Array).is_empty(), "boss stages have no rings")
			_expect((r.golden != null) == (lv >= 3), "the golden balloon comes from stage 3 (stage %d)" % lv)
			_expect((r.stars as Array).is_empty() == (lv < 2), "stars come from stage 2 (stage %d)" % lv)
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens)
	print("route gen: %.3f ms per route incl. check (%d routes)" % [per_ms, gens])
	print("rings per stage: %s" % str(avg_rings))
	print("routes that needed a gentler try: %d of %d" % [gentle, 20 * G.MAX_STAGE])
	_expect(per_ms < 5.0, "a route generates + checks in under 5 ms here (%.2f ms; Decks are slower, aim < 100)" % per_ms)
	_expect(float(avg_rings[3]) > float(avg_rings[1]), "later stages have more rings")
	# Determinism.
	var one := G.route(4242, Vector3(10, 50, -20), 0.7, 4, Main.mission_for(4))
	_expect(var_to_str(one) == var_to_str(G.route(4242, Vector3(10, 50, -20), 0.7, 4, Main.mission_for(4))), "the same seed gives the same route")
	_expect(var_to_str(one) != var_to_str(G.route(4243, Vector3(10, 50, -20), 0.7, 4, Main.mission_for(4))), "another seed gives another route")
	_expect(G.stage_seed(77, 3) == G.stage_seed(77, 3) and G.stage_seed(77, 3) != G.stage_seed(77, 4), "stage seeds are fixed per flight and differ per stage")
	# The validator really catches unfair routes.
	var bad := G.route(9, Vector3(0, 45, 0), 0.0, 3, "rings")
	var low := bad.duplicate(true)
	(low.rings as Array)[1].pos.y = 5.0
	(low.points as Array)[2].y = 5.0
	_expect(not G.check(low).is_empty(), "a ring near the ground is caught")
	var sharp := bad.duplicate(true)
	var p1: Vector3 = (sharp.points as Array)[1]
	(sharp.points as Array)[2] = p1 + Vector3(60.0, 0.0, 30.0)  # a hairpin
	_expect(not G.check(sharp).is_empty(), "a hairpin turn is caught")
	var rock := bad.duplicate(true)
	(rock.islands as Array)[0][0] = ((rock.points as Array)[1] as Vector3).lerp((rock.points as Array)[2], 0.5)
	_expect(not G.check(rock).is_empty(), "an island on the flight path is caught")
	var far := bad.duplicate(true)
	(far.balloons as Array)[0][0] = (far.points as Array)[1] + Vector3(80.0, 0.0, 0.0)
	_expect(not G.check(far).is_empty(), "a balloon out of reach is caught")
	var nogold := bad.duplicate(true)
	nogold.golden = null
	_expect(not G.check(nogold).is_empty(), "a missing golden balloon is caught")
	var resc := G.route(11, Vector3(0, 45, 0), 0.0, 4, "rescue")
	(resc.critters as Array)[0] = (resc.critters as Array)[0] + Vector3(0.0, 40.0, 0.0)
	_expect(not G.check(resc).is_empty(), "a bunny out of scooping reach is caught")
	# TODAY'S FLIGHT.
	for date in ["2026-10-29", "2026-12-25", "2027-01-01"]:
		var ds := G.daily_seed(date)
		for lv in [1, 4, 7]:
			var r := G.route(G.stage_seed(ds, lv), Vector3(0, 45, 0), 0.0, lv, Main.mission_for(lv))
			for why in G.check(r):
				_expect(false, "TODAY'S FLIGHT %s stage %d: %s" % [date, lv, why])
	_expect(G.daily_seed("2026-10-29") != G.daily_seed("2026-10-30"), "a new TODAY'S FLIGHT each day")
	# Charms on the deck rail: every slot on the deck's length, each its own spot.
	var seen: Array = []
	for i in G.CHARM_SLOTS:
		var at := G.charm_slot(i)
		_expect(at.z > 0.7 and at.z < 5.4 and absf(at.x) > 1.1 and absf(at.x) < 1.4, "charm %d hangs on the rail (%s)" % [i, str(at)])
		for o in seen:
			_expect((o as Vector3).distance_to(at) > 0.3, "charm %d has room" % i)
		seen.append(at)
	_expect(G.charm_slot(G.CHARM_SLOTS) == Vector3.INF, "no charm slot past the end")
	_expect(G.CHARM_KEEP >= G.CHARM_SLOTS, "the save keeps a full rail")
	_expect(G.garland(0) == 0 and G.garland(3) == 3 and G.garland(999) == G.GARLAND_MAX, "a blossom a day")
	for m in ["rings", "rescue", "race", "boss"]:
		_expect(G.CHARMS.has(m), "%s stages earn a charm" % m)
	# The game uses the same numbers.
	_expect(is_equal_approx(G.SPACING, Course.SPACING) and is_equal_approx(G.FIRST, Course.FIRST), "spacing matches course.gd")
	_expect(is_equal_approx(G.RING_R, Course.RING_R) and is_equal_approx(G.RESCUE_R, Course.RESCUE_R), "ring sizes match course.gd")
	_expect(is_equal_approx(G.SCOOP, Course.RESCUE_R * 1.4), "scoop reach matches main.gd")
	_expect(is_equal_approx(G.MAX_YAW_RATE, Dragon.MAX_YAW_RATE) and is_equal_approx(G.CLIMB_SPEED, Dragon.CLIMB_SPEED), "flight matches dragon.gd")
	for n in range(1, 12):
		_expect(is_equal_approx(G.cruise(n), Main.simple_cruise(n)), "cruise speed matches main.gd (%d)" % n)
	for pic in ["dragon", "bell", "ribbon", "bunny", "crown", "flowerchain"]:
		_expect(StoryCard.has_picture(pic), "story picture %s exists" % pic)
	for why in StoryCard.check():
		_expect(false, why)
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: %s" % what)
