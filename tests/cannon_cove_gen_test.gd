extends SceneTree
## CANNON COVE generator: proves every seeded voyage is fair and reachable (no game, no window).
##   godot-test --headless --path . -s res://tests/cannon_cove_gen_test.gd      (SEEDS=500 for more)
## For every wave 1-16, simple and classic, crews of 1-6 deckhands: games/cannon_cove/voyagegen.gd check() (one new
## thing per wave, wave sizes in their bands, a ship to shoot first, wave 1 on the gunner's side, no long same-side
## runs early on, every ship inside the cannons' swing and range and outside our hull, no ships on top of each
## other, tentacles on the deck's length) and check_voyage() (waves 1-5 never calmer or smaller, bonus seas grow),
## the same seed gives the same voyage, seeds differ, TODAY'S VOYAGE is the same all day and differs between days,
## the validator really catches unfair plans, the treasure shelf and flags fit on the ship, Polly's pictures exist,
## the constants match the game's, and generation stays fast. Prints "SCRIPT ERROR: ..." per failure.

const G := preload("res://games/cannon_cove/voyagegen.gd")
const Main := preload("res://games/cannon_cove/main.gd")
const Cannon := preload("res://games/cannon_cove/cannon.gd")
const Ship := preload("res://games/cannon_cove/enemy_ship.gd")
const World := preload("res://games/cannon_cove/world.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 120
	var t0 := Time.get_ticks_usec()
	var gens := 0
	for simple in [true, false]:
		for extra in [0, 1, 2, 4]:
			var res := Seeded.validate(func(s: int) -> Array:
					var all: Array = []
					for w in range(1, G.MAX_WAVE + 1):
						all.append(G.wave_plan(s, w, simple, extra))
					return all,
				func(_all: Array) -> Array: return [],
				seeds, 3 + extra, [0, 999999], "VOYAGE simple=%s extra=%d" % [simple, extra])
			gens += int(res.checked) * G.MAX_WAVE
			fails += (res.failures as Array).size()
			for i in seeds:
				var s: int = 3 + extra + i * 7919
				for why in G.check_voyage(s, simple, extra):
					fails += 1
					if fails < 40:
						print("SCRIPT ERROR: VOYAGE simple=%s extra=%d seed %d: %s" % [simple, extra, s, why])
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens * 2)
	print("voyage gen: %.4f ms per wave plan incl. checks (%d plans)" % [per_ms, gens])
	_expect(per_ms < 1.0, "a wave plan generates + checks in under 1 ms here (%.3f ms; Decks are slower, aim < 100)" % per_ms)
	# Variety: seeds give different voyages, the same seed the same one.
	var a := var_to_str(G.wave_plan(4242, 3))
	_expect(a == var_to_str(G.wave_plan(4242, 3)), "the same seed gives the same wave")
	var differ := 0
	for s in 20:
		if var_to_str(G.wave_plan(s * 13 + 1, 2)) != var_to_str(G.wave_plan(s * 13 + 2, 2)):
			differ += 1
	_expect(differ >= 18, "seeds give different waves (%d of 20)" % differ)
	_expect(G.wave_seed(77, 3) == G.wave_seed(77, 3) and G.wave_seed(77, 3) != G.wave_seed(77, 4), "wave seeds are fixed per voyage and differ per wave")
	# The validator really catches unfair plans.
	var base := G.wave_plan(9, 4)
	var bad := base.duplicate(true)
	bad.insert(1, {"k": "fireship", "side": 1.0, "a": 0.0, "orbit": 0.0, "dir": 1.0, "fire": 3.0})
	_expect(not G.check(bad, 4).is_empty(), "a bomb boat in wave 4 is caught")
	var far := base.duplicate(true)
	far[0].orbit = 80.0
	_expect(not G.check(far, 4).is_empty(), "a ship circling out of range is caught")
	var wide := base.duplicate(true)
	wide[0].a = 1.4
	_expect(not G.check(wide, 4).is_empty(), "a ship outside the cannons' swing is caught")
	var first := base.duplicate(true)
	first.push_front({"k": "tentacle", "side": 1.0, "z": 0.0})
	_expect(not G.check(first, 5).is_empty(), "a wave opening with a tentacle is caught")
	var w1 := G.wave_plan(9, 1)
	w1[0].side = 1.0
	_expect(not G.check(w1, 1).is_empty(), "wave 1 off the gunner's side is caught")
	var run := [{"k": "raider", "side": 1.0, "a": -0.8, "orbit": 0.0, "dir": 1.0, "fire": 3.0},
		{"k": "raider", "side": 1.0, "a": 0.0, "orbit": 0.0, "dir": 1.0, "fire": 3.0},
		{"k": "raider", "side": 1.0, "a": 0.8, "orbit": 0.0, "dir": 1.0, "fire": 3.0}]
	_expect(not G.check(run, 2).is_empty(), "three ships in a row on one side is caught")
	var stack := [{"k": "raider", "side": 1.0, "a": 0.1, "orbit": 0.0, "dir": 1.0, "fire": 3.0},
		{"k": "raider", "side": 1.0, "a": 0.2, "orbit": 0.0, "dir": 1.0, "fire": 3.0}, {"k": "raider", "side": -1.0, "a": 0.2, "orbit": 0.0, "dir": 1.0, "fire": 3.0}]
	_expect(not G.check(stack, 2).is_empty(), "two ships on top of each other is caught")
	var boss := G.wave_plan(9, G.BOSS_WAVE)
	_expect(G.check(boss, G.BOSS_WAVE).is_empty() and boss[0].k == "kraken", "the Kraken opens wave 6")
	boss.push_front(boss.pop_back())
	_expect(not G.check(boss, G.BOSS_WAVE).is_empty(), "a Kraken wave without the Kraken first is caught")
	# Rising challenge, on average.
	var sizes := {}
	for w in range(1, 10):
		var tot := 0.0
		for s in 50:
			tot += G.threat(G.wave_plan(s + 1, w))
		sizes[w] = snappedf(tot / 50.0, 0.1)
	print("average threat per wave: %s" % str(sizes))
	_expect(float(sizes[5]) > float(sizes[1]) * 2.0, "wave 5 is clearly busier than wave 1")
	_expect(float(sizes[9]) > float(sizes[7]), "bonus seas grow")
	# TODAY'S VOYAGE.
	for date in ["2026-10-29", "2026-12-25", "2027-01-01"]:
		var ds := G.daily_seed(date)
		_expect(ds == G.daily_seed(date), "TODAY'S VOYAGE is the same all day")
		for why in G.check_voyage(ds):
			_expect(false, "TODAY'S VOYAGE %s: %s" % [date, why])
	_expect(G.daily_seed("2026-10-29") != G.daily_seed("2026-10-30"), "a new TODAY'S VOYAGE each day")
	# The treasure shelf (on top of the stern castle wall) and the flags (on the stay).
	var seen: Array = []
	for i in G.TREASURE_SLOTS:
		var at := G.treasure_slot(i)
		_expect(absf(at.x) < World.HULL_HALF_W - 0.1 and is_equal_approx(at.z, 10.0) and at.y > 2.2, "treasure %d sits on the shelf (%s)" % [i, str(at)])
		for o in seen:
			_expect((o as Vector3).distance_to(at) > 0.5, "treasure %d has room" % i)
		seen.append(at)
	_expect(G.treasure_slot(G.TREASURE_SLOTS) == Vector3.INF, "no treasure slot past the end")
	_expect(G.TREASURE_KEEP >= G.TREASURE_SLOTS, "the save keeps a full shelf")
	_expect(G.flags(0) == 0 and G.flags(3) == 3 and G.flags(999) == G.FLAGS_MAX, "a flag a day")
	for i in G.FLAGS_MAX:
		var f := G.flag_slot(i)
		_expect(f.y - 0.62 > 2.3, "flag %d hangs above heads (%.1f m)" % [i, f.y - 0.62])
		if i > 0:
			_expect(f.distance_to(G.flag_slot(i - 1)) > 0.5, "flag %d has room" % i)
	for w in range(1, 12):
		var tr := G.treasure_for(w)
		_expect(StoryCard.has_picture(tr), "wave %d's treasure %s has a picture" % [w, tr])
		_expect(Main.TREASURE_COLORS.has(tr) and Main.TREASURE_LINES.has(tr), "wave %d's treasure %s has a colour and a line" % [w, tr])
	# The game uses the same numbers.
	_expect(G.BOSS_WAVE == Main.BOSS_WAVE, "the Kraken's wave matches main.gd")
	_expect(is_equal_approx(G.YAW_LIMIT, Cannon.YAW_LIMIT) and is_equal_approx(G.MUZZLE_SPEED, Cannon.MUZZLE_SPEED) and is_equal_approx(G.PITCH_MAX, Cannon.PITCH_MAX), "cannon numbers match cannon.gd")
	_expect(is_equal_approx(G.GRAVITY, Main.GRAVITY), "gravity matches main.gd")
	for k in G.ORBIT:
		_expect(is_equal_approx(float(G.ORBIT[k]), float(Ship.KINDS[k][2])), "%s orbit matches enemy_ship.gd" % k)
	print("cannon range: %.0f m" % G.cannon_range())
	for pic in ["parrot", "doubloon", "pearl", "anchor", "starfish", "crown", "bunting", "treasuremap"]:
		_expect(StoryCard.has_picture(pic), "story picture %s exists" % pic)
	for why in StoryCard.check():
		_expect(false, why)
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: %s" % what)
