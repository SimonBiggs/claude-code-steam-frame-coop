extends SceneTree
## ELEMENTAL BENDER wave generator: proves every seeded wave is fair for small kids (no game, no window).
##   godot-test --headless --path . -s res://tests/elemental_bender_gen_test.gd      (SEEDS=500 for more)
## For waves 1..WaveGen.MAX_WAVE of many temples and every party size (1..7 fighters): games/elemental_bender/
## wavegen.gd check() (portals: one in front for waves 1-2, two from wave 3, two or three from wave 6, spread apart
## on open grass, far enough out; one element in waves 1-2 (two different ones), then 2, 3, 4; no far throwers before
## wave 3; the General only every 5th wave, first, swapping to a new element each time; the first raider from the
## front portal; a slow kid team never faces more than kid_cap() at once; spawning done in time), the same seed
## gives the same waves, seeds differ, TODAY'S RAIDERS is the same all day and differs between days, the validator
## really catches unfair waves, the Spirit Tree / fruit / lanterns fit beside the temple, Kiko's pictures exist, the
## constants match the game's, and generation + checks stay fast. Prints "SCRIPT ERROR: ..." per failure.

const G := preload("res://games/elemental_bender/wavegen.gd")
const W := preload("res://games/elemental_bender/world.gd")
const Main := preload("res://games/elemental_bender/main.gd")
const Pics := preload("res://games/elemental_bender/story_pictures.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")
const Arenas := preload("res://games/elemental_bender/arenas.gd")
const Bosses := preload("res://games/elemental_bender/bosses.gd")
const Boons := preload("res://games/elemental_bender/boons.gd")

var fails := 0
const E_FIRE := 3


func _initialize() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 60
	W.layout()  # (built once per game; don't time it)
	var t0 := Time.get_ticks_usec()
	var res := Seeded.validate(func(s: int) -> Array:
			var all: Array = []
			for players in range(1, G.MAX_PLAYERS + 1):
				for n in range(1, G.MAX_WAVE + 1):
					all.append(G.plan(s, n, players))
			# The other islands (only ever from wave 6 on): a few party sizes.
			for a in Arenas.ids():
				if a == "temple":
					continue
				all.append({"island": a, "seed": Arenas.layout_seed(s, a)})
				for players in [1, 3, G.MAX_PLAYERS]:
					for n in range(Arenas.SEGMENT + 1, G.MAX_WAVE + 1):
						all.append(G.plan(s, n, players, false, a))
			# The altar's gifts at every unlock level.
			for lv in [[0, 0], [6, 0], [12, 1], [40, 4]]:
				var open := Boons.unlocked_boons(lv[0], lv[1])
				for n in range(1, G.MAX_WAVE + 1):
					all.append({"offer": Boons.offer(s, n, open), "open": open})
			return all,
		func(all: Array) -> Array:
			var why: Array = []
			for p in all:
				if p.has("island"):
					why.append_array(Arenas.check(String(p.island), int(p.seed)))
				elif p.has("offer"):
					why.append_array(Boons.check_offer(p.offer, p.open))
				else:
					why.append_array(G.check(p))
			return why,
		seeds, 1, [0, 999999, G.daily_seed("2026-10-30")], "TEMPLE")
	fails += (res.failures as Array).size()
	var plans := seeds * (G.MAX_PLAYERS * G.MAX_WAVE + 3 * 3 * (G.MAX_WAVE - Arenas.SEGMENT))
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, plans)
	var longest := 0.0
	var busiest := 0
	for i in seeds:
		var s: int = 1 + i * 7919
		for n in range(1, G.MAX_WAVE + 1):
			var sim := G.kid_sim(G.plan(s, n, 1))
			longest = maxf(longest, float(sim.end))
			busiest = maxi(busiest, int(sim.most))
	print("temple gen: %.3f ms per wave plan incl. checks (%d plans); the slow solo kid's longest wave %.0f s, most at once %d" % [
		per_ms, plans, longest, busiest])
	_expect(per_ms < 20.0, "a wave plan generates + checks in under 20 ms here (%.2f ms; Decks are ~3x slower, aim < 100)" % per_ms)
	# Variety and determinism.
	_expect(var_to_str(G.plan(4242, 5, 2)) == var_to_str(G.plan(4242, 5, 2)), "the same seed gives the same waves")
	var differ := 0
	for s in 20:
		if var_to_str(G.gates(s * 13 + 1, 4)) != var_to_str(G.gates(s * 13 + 2, 4)):
			differ += 1
	_expect(differ >= 18, "seeds give different portals (%d of 20)" % differ)
	var spots := {}
	for s in 40:
		var g: Vector3 = G.gates(s + 100, 3)[1]
		spots[snappedf(atan2(g.z, g.x), 0.3)] = true
	_expect(spots.size() >= 12, "the second portal really moves round the island (%d places)" % spots.size())
	var firsts := {}
	for s in 40:
		firsts[int(G.plan(s + 7, 1, 1).palette[0])] = true
	_expect(firsts.size() == 4, "wave 1 can bring any element (%d kinds)" % firsts.size())
	for players in range(1, G.MAX_PLAYERS + 1):
		_expect(var_to_str(G.plan(77, 6, players).gates) == var_to_str(G.gates(77, 6)), "every party size sees the same portals (%d)" % players)
	_expect(G.daily_seed("2026-10-30") == G.daily_seed("2026-10-30"), "TODAY'S RAIDERS is the same all day")
	_expect(G.daily_seed("2026-10-30") != G.daily_seed("2026-10-31"), "TODAY'S RAIDERS changes the next day")
	_expect(G.daily_seed() == Seeded.daily_seed("elemental_bender"), "TODAY'S RAIDERS uses the shared daily seed")
	# TODAY'S RAIDERS over 400+ days (Seeded.validate_days, the shared daily validator), as main.gd plays it: for a new
	# family and one grown family (by the date; unlocks [waves, generals]) the islands the day's run travels to
	# (_enter_arena: arena_for(seed, segment, open, last island)) and their layouts (Arenas.check; TEMPLE ISLAND is the
	# fixed classic layout, checked above), every wave's plan there (check(); one party size a wave, 1-7 benders turn
	# by turn: a plan for every size of both families was +46 s) and the altar's gifts (check_offer), the same all day.
	var rs := Seeded.validate_days(func(date: String) -> Array:
			var ds := G.daily_seed(date)
			var all: Array = []
			var grown := [[6, 0], [12, 1], [20, 2], [40, 4]]
			for lv in [[0, 0], grown[absi(hash(date)) % grown.size()]]:
				var open := Arenas.unlocked(int(lv[1]), int(lv[0]))
				var boons := Boons.unlocked_boons(int(lv[0]), int(lv[1]))
				var island := ""
				for n in range(1, G.MAX_WAVE + 1):
					var seg := Arenas.segment_of(n)
					if (n - 1) % Arenas.SEGMENT == 0:
						island = Arenas.arena_for(ds, seg, open, island if seg > 0 else "")
						if island != "temple":
							all.append({"island": island, "seed": Arenas.layout_seed(ds, island)})
					all.append(G.plan(ds, n, 1 + (absi(hash(date)) + n) % G.MAX_PLAYERS, false, island))
					all.append({"offer": Boons.offer(ds, n, boons), "open": boons})
			return all,
		func(all: Array) -> Array:
			var why: Array = []
			for p in all:
				if p.has("island"):
					why.append_array(Arenas.check(String(p.island), int(p.seed)))
				elif p.has("offer"):
					why.append_array(Boons.check_offer(p.offer, p.open))
				else:
					why.append_array(G.check(p))
			return why, 400, "TODAY'S RAIDERS", ["2026-11-11", "2026-11-12"])
	fails += (rs.failures as Array).size()
	# The story rules.
	for s in 30:
		_expect(G.plan(s, 1, 1).palette != G.plan(s, 2, 1).palette, "waves 1 and 2 bring different elements (seed %d)" % s)
	var generals := 0
	for n in range(1, G.MAX_WAVE + 1):
		var p := G.plan(5, n, 1)
		if p.boss:
			generals += 1
			_expect(n % 5 == 0, "the General comes on wave 5, 10, 15 (wave %d)" % n)
	_expect(generals == 3, "the General comes three times in 15 waves (%d)" % generals)
	# The validator really catches unfair waves.
	var base := G.plan(9, 4, 1)
	_expect(G.check(base).is_empty(), "seed 9 wave 4 is fair (%s)" % str(G.check(base)))
	var bad := base.duplicate(true)
	for sp in bad.spawns:
		sp[3] = 0.3
	_expect(not G.check(bad).is_empty(), "raiders all at once (too busy for small kids) is caught")
	bad = base.duplicate(true)
	var g0: Vector3 = bad.gates[0]
	bad.gates[1] = g0.rotated(Vector3.UP, 0.3)
	_expect(not G.check(bad).is_empty(), "two portals side by side is caught")
	bad = G.plan(9, 1, 1)
	bad.gates[0] = -(bad.gates[0] as Vector3)
	_expect(not G.check(bad).is_empty(), "the wave 1 portal behind the temple is caught")
	bad = G.plan(9, 1, 1)
	bad.gates[0] = Vector3(0, 0, -12.0)
	_expect(not G.check(bad).is_empty(), "a portal right next to the temple is caught")
	bad = G.plan(9, 2, 1)
	bad.spawns[1][0] = (int(bad.palette[0]) + 1) % 4
	_expect(not G.check(bad).is_empty(), "a second element in wave 2 is caught")
	bad = G.plan(9, 2, 1)
	bad.spawns[1][2] = true
	_expect(not G.check(bad).is_empty(), "a far thrower in wave 2 is caught")
	bad = G.plan(9, 5, 1)
	bad.boss_order[1] = bad.boss_order[0]
	_expect(not G.check(bad).is_empty(), "the General swapping to the same element is caught")
	var on_prop := 0
	for pr in W.layout().props:
		var q: Vector3 = pr.p
		if Vector2(q.x, q.z).length() > G.GATE_R.x and Vector2(q.x, q.z).length() < G.GATE_R.y and not G._gate_ok(q, []).is_empty():
			on_prop += 1
	_expect(on_prop >= 1, "a portal on a tree or rock is caught (%d)" % on_prop)
	_expect(not G._gate_ok(Vector3(0, 0, -22.5), []).is_empty(), "a portal on a training platform is caught")
	_expect(W.blocked(Vector3(0, 0, -19.0), 0.5) != "", "the training platform is not open grass")
	# Keepsakes fit beside the temple.
	_expect(W.blocked(G.TREE_AT, G.TREE_CLEAR) == "", "the Spirit Tree stands on open grass (%s)" % W.blocked(G.TREE_AT, G.TREE_CLEAR))
	for n in range(1, 4):
		for g in G.gates(n, 1):
			_expect((g as Vector3).distance_to(G.TREE_AT) > 6.0, "the Spirit Tree isn't on a portal")
	for i in G.LANTERNS_MAX:
		var p := G.lantern_slot(i)
		var r := Vector2(p.x, p.z).length()
		_expect(r > 8.5 and r < 11.0, "lantern %d sits round the temple steps" % i)
		_expect(p.distance_to(G.TREE_AT) > 2.5, "lantern %d isn't in the tree" % i)
		for pr in W.layout().props:
			_expect((pr.p as Vector3).distance_to(p) > float(pr.r) + 0.3, "lantern %d isn't in a tree or rock" % i)
	_expect(G.lantern_slot(G.LANTERNS_MAX) == Vector3.INF, "no lantern slots past the end")
	_expect(G.lanterns(400) == G.LANTERNS_MAX and G.lanterns(3) == 3, "one lantern per play-day, up to the most")
	_expect(G.fruit_cap(G.TREE_STAGES.size() - 1) == G.FRUIT_MAX, "the great tree holds every fruit kept")
	_expect(G.tree_stage(0) == 0 and G.tree_stage(1000) == G.TREE_STAGES.size() - 1, "the tree grows from a seed to the great tree")
	for st in range(1, G.TREE_STAGES.size()):
		for i in G.fruit_cap(st):
			var f := G.fruit_slot(i, st)
			var out := f.distance_to(Vector3(0.0, G.tree_height(st), 0.0))
			_expect(f.y > 0.2 and out > G.crown_r(st) * 0.98 and out < G.crown_r(st) * 1.1, "fruit %d hangs on the outside of the crown (stage %d)" % [i, st])
			for j in i:
				_expect(f.distance_to(G.fruit_slot(j, st)) > 0.25, "fruits %d and %d don't overlap (stage %d)" % [i, j, st])
	# Pictures.
	for pic in ["kiko", "portal", "general", "spirittree", "lightfruit", "lantern", "crown"]:
		_expect(StoryCard.has_picture(pic), "the %s picture exists" % pic)
	for pic in Pics.ELEMENT_PICS:
		_expect(StoryCard.has_picture(pic), "element picture %s exists" % pic)
	_expect(StoryCard.check().is_empty(), "story pictures are fine (%s)" % str(StoryCard.check()))
	# Islands, bosses, gifts and masters.
	_expect(Arenas.check("temple", Arenas.CLASSIC_SEED).is_empty(), "TEMPLE ISLAND is fair (%s)" % str(Arenas.check("temple", Arenas.CLASSIC_SEED)))
	_expect(var_to_str(Arenas.layout("temple", Arenas.CLASSIC_SEED).props) == var_to_str(W.layout().props), "TEMPLE ISLAND keeps its classic trees and rocks")
	_expect(Arenas.layout("temple", Arenas.CLASSIC_SEED).props.size() == 33, "the classic island has its 33 trees and rocks (one moved off the altar)")
	_expect(Arenas.arena_for(5, 0, Arenas.ids()) == "temple", "every run starts at home on TEMPLE ISLAND")
	_expect(Arenas.arena_for(5, 1, ["temple"]) == "temple", "with no island unlocked the run stays home")
	_expect(Arenas.arena_for(5, 1, ["temple", "ice"]) == "ice", "the first unlocked island comes after the first boss")
	var visits := {}
	for s in 30:
		for k in range(1, 4):
			visits[Arenas.arena_for(s, k, Arenas.ids())] = true
	_expect(visits.size() == 3 and not visits.has("temple"), "with every island open the run visits the other three (%s)" % str(visits.keys()))
	_expect(Arenas.arena_for(5, 4, Arenas.ids()) == "temple", "the round trip comes home again")
	_expect(Arenas.arena_for(5, 1, ["temple", "ice"], "ice") == "temple", "never the same island twice in a row")
	_expect(Arenas.unlocked(0, 0) == ["temple"], "a new family has only TEMPLE ISLAND")
	_expect(Arenas.unlocked(1, 0).has("ice") and Arenas.unlocked(3, 0).size() == 4, "Generals beaten open the islands")
	_expect(Arenas.unlocked(0, 40).size() == 4, "a big Spirit Tree opens every island too")
	for a in Arenas.ids():
		var info := Arenas.info(a)
		_expect(StoryCard.has_picture(String(info.pic)), "%s has a picture" % a)
		_expect(String(info.name).length() <= 14, "%s's name is short" % a)
		_expect(Bosses.LIST.has(String(info.boss)), "%s has a boss" % a)
		_expect(info.hazard == "" or Arenas.HAZARDS.has(String(info.hazard)), "%s's hazard exists" % a)
		_expect(a == "temple" or Arenas.layout(a, 11) != Arenas.layout(a, 12), "%s changes with the temple seed" % a)
	for k in Bosses.KINDS:
		_expect(Bosses.check(k).is_empty(), "the %s is kid-fair (%s)" % [k, str(Bosses.check(k))])
		_expect(StoryCard.has_picture(String(Bosses.info(k).pic)), "the %s has a picture" % k)
	var ice := Arenas.layout("ice", 4242).duplicate(true)
	_expect(Arenas.check("ice", 4242).is_empty(), "ice 4242 is fair (%s)" % str(Arenas.check("ice", 4242)))
	_expect(not Arenas._vent_problems({"p": Vector3(0, 0, -9.0), "r": 2.2, "period": 8.0}, [], ice).is_empty(), "a vent on the temple steps is caught")
	_expect(not Arenas._vent_problems({"p": Vector3(0, 0, -14.0), "r": 2.2, "period": 8.0}, [], ice).is_empty(), "a vent on the altar is caught")
	_expect(not Arenas._vent_problems({"p": Vector3(14, 0, 0), "r": 2.2, "period": 3.0}, [], ice).is_empty(), "a vent bursting too often is caught")
	var walled := {"id": "walltest", "seed": 1, "props": [], "mountains": [], "vents": []}
	for i in 80:
		var a := i * TAU / 80.0
		walled.props.append({"kind": "rock", "p": Vector3(cos(a) * 25.0, 0, sin(a) * 25.0), "r": 1.6})
	_expect(not Arenas.reachable(Vector3(5, 0, -29.0), walled), "a portal walled off by rocks is caught (unreachable)")
	_expect(Arenas.reachable(Vector3(5, 0, -13.0), walled), "inside the wall is still reachable")
	var bad_boss := G.plan(9, 10, 1, false, "ice")
	bad_boss.boss_order = [E_FIRE]
	_expect(not G.check(bad_boss).is_empty(), "a Frost Giant of the wrong element is caught")
	_expect(not Boons.check_offer(["big", "big", "power"], Boons.unlocked_boons(0, 0)).is_empty(), "the same gift twice is caught")
	_expect(not Boons.check_offer(["big", "power", "leaf"], Boons.unlocked_boons(0, 0)).is_empty(), "a locked gift on the altar is caught")
	_expect(Boons.unlocked_masters(0, 0).size() == 2, "a new family starts with two masters")
	_expect(Boons.unlocked_masters(5, 0).size() == 4 and Boons.unlocked_masters(5, 3).size() == 5, "masters unlock as the tree grows and Generals fall")
	_expect(Boons.unlocked_boons(0, 0).size() >= 6 and Boons.unlocked_boons(999, 9).size() == Boons.BOONS.size(), "gifts unlock up to all of them")
	for m in Boons.MASTERS:
		_expect(String(m.name).length() <= 8, "master %s's name is short" % m.id)
	var big := Boons.mods({"m": "fire", "b": ["big", "power", "power", "power", "power", "power", "power"]})
	_expect(float(big.dmg) <= 3.0, "stacked gifts are capped")
	_expect(Boons.shape_shots(Boons.mods({"b": ["triple"]}), [{"damage": 10.0, "vel": Vector3.FORWARD}]).size() == 3, "TRIPLE SHOT fires three")
	_expect(float(Boons.mods({"m": "earth", "b": ["shield", "shield", "shield", "shield"]}).taken) >= 0.35, "rock skin never makes anyone unhurtable")
	# The constants match the game's.
	_expect(G.MAX_ALIVE == Main.MAX_ALIVE, "MAX_ALIVE matches main.gd")
	_expect(G.GAME_ID == Main.GAME_ID, "the game id matches main.gd")
	print("ELEMENTAL BENDER GEN TEST: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: ELEMENTAL BENDER GEN: " + what)
