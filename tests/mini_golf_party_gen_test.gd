extends SceneTree
## MINI GOLF PARTY generator: proves every seeded hole can be sunk (no game, no window).
##   godot-test --headless --path . -s res://tests/mini_golf_party_gen_test.gd      (SEEDS=300 for more)
## For every level 1-4 and every hole of a course: games/mini_golf_party/holegen.gd check() (fits the camera and
## the lawn, walls don't cross, tee spots for 7 balls, cup clear of walls and bumpers, the aim path from the tee to
## the cup is in sight point to point, the gimmick sits on a straight with room before and after, the VR toys, flag
## board and Gus's molehill are off the green) AND sim(): an aiming putter with the game's own ball physics and
## windmill sinks it within the game's putt limit. Also: the same seed gives the same hole, TV machines rebuild the
## host's hole from [seed, hole, level, try], the classic fallbacks pass, TODAY'S COURSE is the same all day and
## differs between days, levels add shapes, Gus's pictures exist, and generating a hole stays fast.
## Prints "SCRIPT ERROR: ..." per failure.

const G := preload("res://games/mini_golf_party/holegen.gd")
const Main := preload("res://games/mini_golf_party/main.gd")
const Garden := preload("res://games/mini_golf_party/garden.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 60
	var t0 := Time.get_ticks_usec()
	var gens := 0
	var acc := [0, 0, 0]  # sims, sim microseconds, extra tries (lambdas capture ints by value: use an Array)
	var putts := {}  # gimmick -> [total putts, holes, worst]
	var shapes := {}  # level -> {shape: n}
	for lv in range(1, G.MAX_LEVEL + 1):
		for i in G.HOLES:
			var res := Seeded.validate(func(s: int) -> Dictionary: return G.hole(s, i, lv),
				func(d: Dictionary) -> Array:
					var why := G.check(d)
					if int(d["try"]) < 0:
						why.append("needed the classic fallback")
					var t1 := Time.get_ticks_usec()
					var r := G.sim(d)
					acc[1] += Time.get_ticks_usec() - t1
					acc[0] += 1
					if not bool(r["sunk"]):
						why.append("the aiming putter didn't sink %s/%s in %d putts" % [d["gimmick"], d["shape"], G.MAX_PUTTS])
					elif int(r["putts"]) > int(d["par"]) + 2:
						why.append("%s/%s took %d putts (par %d)" % [d["gimmick"], d["shape"], int(r["putts"]), int(d["par"])])
					var g := String(d["gimmick"])
					var pt: Array = putts.get(g, [0, 0, 0])
					putts[g] = [int(pt[0]) + int(r["putts"]), int(pt[1]) + 1, maxi(int(pt[2]), int(r["putts"]))]
					var sh: Dictionary = shapes.get(lv, {})
					sh[d["shape"]] = int(sh.get(d["shape"], 0)) + 1
					shapes[lv] = sh
					acc[2] += int(d["try"])
					# TV machines rebuild it from the compact description.
					if var_to_str(G.hole_try(int(d["course_seed"]), i, lv, int(d["try"]))) != var_to_str(d):
						why.append("the rebuilt hole differs")
					if int(d["index"]) != i:
						why.append("wrong hole index")
					return why, seeds, 3 + lv * 11 + i, [0, 999999], "HOLE level %d hole %d" % [lv, i + 1])
			gens += int(res.checked)
			fails += (res.failures as Array).size()
	var per_ms := float(Time.get_ticks_usec() - t0 - int(acc[1])) / 1000.0 / maxf(1.0, gens * 2)
	print("hole gen: %.3f ms per hole incl. check + proof sim (%d holes); sim %.2f ms per hole (%d)" % [per_ms, gens, int(acc[1]) / 1000.0 / maxf(1, int(acc[0])), int(acc[0])])
	print("tries: %.2f extra per hole" % (float(acc[2]) / maxf(1, int(acc[0]))))
	for g in putts:
		var pt: Array = putts[g]
		print("putts %s: avg %.2f worst %d (%d holes)" % [g if g != "" else "practice", float(pt[0]) / pt[1], pt[2], pt[1]])
	print("shapes per level: %s" % str(shapes))
	_expect(per_ms < 20.0, "a hole generates + checks + proves in under 20 ms here (%.2f ms; Decks are slower, aim < 100)" % per_ms)
	# Every gimmick's classic fallback passes too.
	for g in ["", "bumper", "windmill", "hill", "loop", "pinball"]:
		for lv in range(1, G.MAX_LEVEL + 1):
			for s in 40:
				var i := G.plan(s, lv).find(g)
				if i < 0:
					continue
				var d := G.hole_try(s, i, lv, -1)
				var why := G.check(d)
				_expect(why.is_empty(), "the classic %s hole passes (%s)" % [g, str(why)])
				_expect(bool(G.sim(d)["sunk"]), "the classic %s hole can be sunk" % g)
				break
	# Plans: hole 1 is the practice putt, then four different gimmicks; pinball from level 2.
	for s in 50:
		var p1 := G.plan(s, 1)
		_expect(p1[0] == "" and not p1.has("pinball"), "level 1 plan %s" % str(p1))
		var uniq := {}
		for g in p1:
			uniq[g] = true
		_expect(uniq.size() == G.HOLES, "every hole has its own gimmick")
	var any_pin := false
	for s in 50:
		any_pin = any_pin or G.plan(s, 2).has("pinball")
	_expect(any_pin, "the pinball hole comes at level 2")
	_expect(not (shapes[1] as Dictionary).has("dogleg"), "no doglegs at level 1")
	_expect((shapes[2] as Dictionary).has("dogleg"), "doglegs at level 2")
	_expect(G.level_for(0) == 1 and G.level_for(2) == 2 and G.level_for(40) == G.MAX_LEVEL, "levels grow with play-days")
	# Determinism, the daily seed.
	var one := G.hole(4242, 2, 3)
	_expect(var_to_str(one) == var_to_str(G.hole(4242, 2, 3)), "the same seed gives the same hole")
	_expect(var_to_str(one) != var_to_str(G.hole(4243, 2, 3)), "another seed gives another hole")
	_expect(G.daily_seed("2026-10-29") == G.daily_seed("2026-10-29"), "TODAY'S COURSE is the same all day")
	_expect(G.daily_seed("2026-10-29") != G.daily_seed("2026-10-30"), "TODAY'S COURSE changes each day")
	_expect(G.daily_seed() > 0, "the daily seed is a real seed")
	# The validator really catches broken holes.
	var bad := G.hole(9, 1, 2)
	bad["cup"] = (bad["tee"] as Vector2) + Vector2(0.0, -0.5)
	_expect(not G.check(bad).is_empty(), "check() catches a cup next to the tee")
	var bad2 := G.hole(9, 0, 1)
	bad2["outline"] = (bad2["outline"] as Array).duplicate()
	(bad2["outline"] as Array)[1] = Vector2(9.0, 9.0)
	_expect(not G.check(bad2).is_empty(), "check() catches a broken wall")
	_expect(Main.MAX_STROKES == G.MAX_PUTTS, "the game's putt limit matches the proof")
	# Gus's garden: spots off the green, one ornament per play-day.
	for s in 20:
		var d := G.hole(s * 13 + 1, s % G.HOLES, 1 + s % G.MAX_LEVEL)
		var spots := Garden.spots(d, Garden.MAX_PIECES)
		_expect(spots.size() >= 8, "room for the garden (%d spots)" % spots.size())
		for p in spots:
			_expect(not Geometry2D.is_point_in_polygon(p, PackedVector2Array(d["outline"])), "a garden spot is off the green")
	for kind in Garden.KINDS:
		var pc := Garden.piece(kind)
		_expect(pc != null, "garden piece %s builds" % kind)
		if pc != null:
			pc.free()
	for pic in ["gopher", "golfball", "golfflag", "trophy", "gnome"]:
		_expect(StoryCard.has_picture(pic), "story picture %s exists" % pic)
	_expect(StoryCard.check().is_empty(), "story pictures are all fine %s" % str(StoryCard.check()))
	print("MINI GOLF GEN: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: MINI GOLF GEN: " + what)
