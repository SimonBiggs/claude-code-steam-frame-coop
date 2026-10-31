extends SceneTree
## CRYSTAL SAGA seeded journeys: proves every generated road is completable and fair (no game, no window).
##   godot-test --headless --path . -s res://tests/crystal_saga_gen_test.gd      (SEEDS=500 for more)
## For every tier: games/crystal_saga/sagagen.gd check() (each zone walkable from entrance to barrier,
## every touchable thing, level-up stone, the orb and the giant's friend in reach, rocks off the special
## spots, monsters spawning on open ground away from the entrance, waves fair for teams of 1 to 7, the
## giant's toughness fair) and determinism; higher tiers are harder; hand-broken plans are caught;
## TODAY'S QUEST is the same all day and passes; the story rules (saga.gd); every picture exists;
## and it all stays fast (< 100 ms a road on a Deck: we allow 30 ms here, the Steam Machine is quicker).
## saga-deep: every biome of the realm in every tier, gentle and brave (each region's quest can be done: enough
## things hidden in reach before the guardian; each crystal guardian is fair: tells long enough to step out of,
## time to hit back, rain that leaves the glade mostly safe, few helpers); the family realms (realm.gd check():
## every region can be reached by clearing open ones, roads only between neighbouring rows, difficulty never
## jumps along any order of play); difficulty rises smoothly tier by tier for every team size; heroes (classes.gd).
## Prints "SCRIPT ERROR: ..." for each failure.

const SagaGen := preload("res://games/crystal_saga/sagagen.gd")
const Saga := preload("res://games/crystal_saga/saga.gd")
const World := preload("res://games/crystal_saga/world.gd")
const Monsters := preload("res://games/crystal_saga/monsters.gd")
const Seeded := preload("res://core/seeded.gd")
const Realm := preload("res://games/crystal_saga/realm.gd")
const Classes := preload("res://games/crystal_saga/classes.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 60
	var total := 0
	var t0 := Time.get_ticks_usec()
	var gens := 0
	var hard := {}
	for tier in SagaGen.TIERS:
		for biome in Realm.BIOMES.size():
			for brave in [false, true]:
				var n_seeds := maxi(4, seeds / Realm.BIOMES.size())
				var r := Seeded.validate(func(s: int) -> Dictionary: return SagaGen.generate(s, tier, biome, "", brave),
					func(p: Dictionary) -> Array: return SagaGen.check(p), n_seeds, 11 + tier * 31 + biome, [0, 1, 999999],
					"SAGA T%d %s%s" % [tier, Realm.BIOMES[biome].id, " BRAVE" if brave else ""])
				total += int(r.checked)
				gens += int(r.checked)
				fails += (r.failures as Array).size()
		var r0 := Seeded.validate(func(s: int) -> Dictionary: return SagaGen.generate(s, tier),
			func(p: Dictionary) -> Array: return SagaGen.check(p), seeds / 4, 11 + tier, [0, 1, 999999], "SAGA T%d" % tier)
		total += int(r0.checked)
		gens += int(r0.checked) * 2
		var r := r0
		fails += (r.failures as Array).size()
		var mons := 0.0
		for s in 20:
			var p := SagaGen.generate(300 + s * 13, tier)
			for z in [1, 2]:
				for w in p.waves[z]:
					mons += SagaGen.wave_count(w, 3)
			mons += SagaGen.giant_hits(p, 3) * 0.25
		hard[tier] = mons
	# Difficulty rises smoothly by tier for every team size, gentle and brave: never easier, never a big jump.
	for n in range(1, SagaGen.MAX_TEAM + 1):
		var prev := 0.0
		for tier2 in SagaGen.TIERS:
			var d := 0.0
			for s2 in 12:
				for biome2 in Realm.BIOMES.size():
					d += SagaGen.difficulty(SagaGen.generate(500 + s2 * 7, tier2, biome2), n)
			if tier2 > 0:
				_expect(d >= prev, "tier %d is easier than tier %d for %d heroes (%.0f < %.0f)" % [tier2, tier2 - 1, n, d, prev])
				_expect(d <= prev * 1.45, "tier %d jumps too far above tier %d for %d heroes (%.0f vs %.0f)" % [tier2, tier2 - 1, n, d, prev])
			prev = d
	# The family realms: every region reachable, roads between neighbouring rows, smooth climbs.
	var rr := Seeded.validate(func(s: int) -> Dictionary: return Realm.generate(s), func(p: Dictionary) -> Array: return Realm.check(p),
		seeds * 2, 3, [0, 1, 999999], "REALM")
	total += int(rr.checked)
	fails += (rr.failures as Array).size()
	var shapes := {}
	for s3 in 40:
		shapes[var_to_str(Realm.generate(s3 * 17 + 3).regions)] = true
	_expect(shapes.size() >= 36, "realms differ (%d of 40)" % shapes.size())
	var rb := Realm.generate(42)
	var rb1 := rb.duplicate(true)
	for g in rb1.regions:
		if int(g.depth) == 3:
			g.links = []
	for g2 in rb1.regions:
		g2.links = (g2.links as Array).filter(func(j: Variant) -> bool: return int(rb1.regions[int(j)].depth) != 3 or false)
	_expect(not Realm.check(rb1).is_empty(), "a row cut off from the map is caught")
	var rb2 := rb.duplicate(true)
	var far := -1
	for i in Realm.SIZE:
		if int(rb2.regions[i].depth) == 4:
			far = i
	(rb2.regions[far].links as Array).append(0)
	(rb2.regions[0].links as Array).append(far)
	_expect(not Realm.check(rb2).is_empty(), "a road jumping from row 1 to row 4 is caught")
	var rb3 := rb.duplicate(true)
	rb3.regions[0].biome = 3
	_expect(not Realm.check(rb3).is_empty(), "a realm that doesn't start in the meadow is caught")
	# Every realm slot plays: its plan at its tier passes, in both modes.
	for wseed in [5, 1234, 777777]:
		var rl := Realm.generate(wseed)
		var order := Realm.clear_order(rl)
		for k in order.size():
			var cl: Array = order.slice(0, k)
			for hard2 in [false, true]:
				var jn := Saga.journey(k, wseed, false, "", int(order[k]), cl, hard2)
				_expect(int(jn.region) == int(order[k]), "world %d: region %d is open after %s" % [wseed, int(order[k]), str(cl)])
				for w5 in SagaGen.check(Saga.plan_for(jn, wseed, hard2)):
					_fail("world %d region %d: %s" % [wseed, int(order[k]), w5])
				total += 1
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens)
	print("saga gen: %.2f ms per road + check (%d roads)" % [per_ms, gens])
	_expect(per_ms < 30.0, "a road generates and checks in under 30 ms here (%.2f ms)" % per_ms)
	for tier in range(1, SagaGen.TIERS):
		_expect(float(hard[tier]) > float(hard[tier - 1]), "tier %d is harder than tier %d (%s)" % [tier, tier - 1, str(hard)])
	# Roads differ: names, rocks, props.
	var looks := {}
	var names := {}
	var rocks := 0
	for s in 40:
		var p2 := SagaGen.generate(s * 101 + 5, 2, s % Realm.BIOMES.size())
		looks[var_to_str(p2.props)] = true
		names[str(p2.names)] = true
		for q in p2.props:
			rocks += 1 if int(q[0]) == World.ROCK else 0
	_expect(looks.size() >= 38, "roads differ (%d of 40)" % looks.size())
	_expect(names.size() >= 16, "road names differ (%d of 40)" % names.size())
	_expect(rocks >= 40, "rocks get in the way sometimes (%d in 40 roads)" % rocks)
	# Journeys and TODAY'S QUEST.
	for world in [5, 1234, 777777]:
		for j in [0, 1, 2, 5, 12]:
			var jn := Saga.journey(j, world, j == 2, "2026-11-0%d" % (j % 9 + 1))
			for w2 in SagaGen.check(SagaGen.generate(int(jn.seed), int(jn.tier))):
				_fail("world %d journey %d: %s" % [world, j, w2])
			total += 1
	var days := {}
	for d in 40:
		var date := Time.get_date_string_from_unix_time(1790000000 + d * 86400)
		var dq := Saga.journey(3, 42, true, date)
		var p3 := SagaGen.generate(int(dq.seed), int(dq.tier))
		for w3 in SagaGen.check(p3):
			_fail("daily %s: %s" % [date, w3])
		_expect(int(Saga.journey(3, 999, true, date).seed) == int(dq.seed), "TODAY'S QUEST %s is the same road for every family" % date)
		days[var_to_str(p3.props)] = true
		total += 1
	_expect(days.size() >= 30, "daily quests differ (%d unique of 40)" % days.size())
	# Hand checks: the validator catches broken roads.
	var p0 := SagaGen.generate(42, 3)
	var b1 := p0.duplicate(true)
	var c1 := World.center(1).z
	for x in [-4.0, -2.4, -0.8, 0.8, 2.4, 4.0]:
		b1.props.append([World.ROCK, x, c1, 0.75])
	_expect(not SagaGen.check(b1).is_empty(), "a wall of rocks across the forest is caught")
	var b2 := p0.duplicate(true)
	b2.props.append([World.ROCK, World.CHOICE_SPOTS[0].x, World.center(3).z + World.CHOICE_SPOTS[0].y, 0.6])
	_expect(not SagaGen.check(b2).is_empty(), "a rock on a level-up stone is caught")
	var b3 := p0.duplicate(true)
	b3.waves[1][0][2][0][3] = World.entrance(1).z
	b3.waves[1][0][2][0][1] = 0.0
	_expect(not SagaGen.check(b3).is_empty(), "a monster on the entrance is caught")
	var b4 := p0.duplicate(true)
	b4.waves[1][0][0] = 20
	_expect(not SagaGen.check(b4).is_empty(), "a wave that swamps one hero is caught")
	var b5 := p0.duplicate(true)
	b5.giant_hits = [60, 4, 40, 90]
	_expect(not SagaGen.check(b5).is_empty(), "a giant too tough for one hero is caught")
	var b6 := p0.duplicate(true)
	for q2 in b6.props:
		if int(q2[0]) == World.CHEST:
			q2[1] = 9.0
	_expect(not SagaGen.check(b6).is_empty(), "a chest off the map is caught")
	var b7 := p0.duplicate(true)
	for wv in b7.waves[2]:
		for m in wv[2]:
			m[0] = Monsters.BAT
	_expect(not SagaGen.check(b7).is_empty(), "a cave wave without slimes is caught")
	var b9 := p0.duplicate(true)
	b9.props = b9.props.filter(func(q: Array) -> bool: return int(q[0]) != World.QUEST)
	_expect(not SagaGen.check(b9).is_empty(), "a quest with nothing to find is caught")
	var b10 := p0.duplicate(true)
	for q3 in b10.props:
		if int(q3[0]) == World.QUEST:
			b10.props.append([World.ROCK, float(q3[1]) + 0.2, float(q3[2]), 0.7])
			break
	_expect(not SagaGen.check(b10).is_empty(), "a quest thing inside a rock is caught")
	var b11 := p0.duplicate(true)
	for q4 in b11.props:
		if int(q4[0]) == World.QUEST:
			q4[2] = World.center(3).z - 6.0
	_expect(not SagaGen.check(b11).is_empty(), "quest things past the guardian's gate are caught")
	var b12 := p0.duplicate(true)
	b12.guardian.warn["stomp"] = 0.6
	_expect(not SagaGen.check(b12).is_empty(), "a stomp tell too quick to step out of is caught")
	var b13 := p0.duplicate(true)
	b13.guardian.gap = [2.0, 3.0]
	_expect(not SagaGen.check(b13).is_empty(), "a guardian with no pause to hit back is caught")
	var b14 := p0.duplicate(true)
	b14.guardian.attacks = ["call"]
	b14.guardian.call_n = 6
	_expect(not SagaGen.check(b14).is_empty(), "a guardian calling a crowd is caught")
	var b15 := p0.duplicate(true)
	b15.guardian.attacks = ["rain"]
	b15.guardian.rain_n = 14
	_expect(not SagaGen.check(b15).is_empty(), "crystal rain over the whole glade is caught")
	var b8 := p0.duplicate(true)
	b8.props.append([World.ROCK, -4.0, World.center(2).z - 6.6, 0.6])
	b8.props.append([World.CRYSTAL, -4.5, World.center(2).z - 6.6, 0.6])
	_expect(not SagaGen.check(b8).is_empty(), "a crystal inside a rock is caught")
	# Pictures: every story card picture has a drawing (all games); every picture the saga uses exists.
	var StoryCard := load("res://core/story_card.gd")
	for e in StoryCard.check():  # (tests/story_pictures_test.gd checks the pictures in depth)
		_expect(false, e)
	var icons := ["star", "crown", "music", "trophy", "flag", "heart", "sun"]
	var used: Array = ["lumi", "shard", "sun", "star", "guardian", "house", "rainbow"]
	for id in Saga.SKILLS:
		used.append(String(Saga.SKILLS[id].pic))
	for b in Realm.BIOMES:
		used.append(String(b.pic))
		used.append(String(b.quest[1]))
		used.append(String(b.quest[4]))
	for cid in Classes.ORDER:
		used.append(String(Classes.INFO[cid].pic))
	icons.append_array(["fire", "check", "dot", "arrow_down"])
	for pl in Saga.PLACES:
		used.append(String(pl.pic))
	for pic2 in used:
		_expect(StoryCard.has_picture(pic2) or icons.has(pic2), "picture %s exists" % pic2)
	_expect(Saga.PLACES.size() == World.PLACE_AT.size(), "every Willowbrook place has a spot (%d places, %d spots)" % [Saga.PLACES.size(), World.PLACE_AT.size()])
	# Story.
	for w4 in Saga.self_check():
		_fail("story: " + w4)
	for w6 in Classes.self_check():
		_fail("heroes: " + w6)
	print("saga gen: %d roads checked, %d failures" % [total, fails])
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: saga gen: " + what)
