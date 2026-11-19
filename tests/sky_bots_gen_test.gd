extends SceneTree
## SKY BOTS islands: proves every generated island can be finished (no game, no window).
##   godot-test --headless --path . -s res://tests/sky_bots_gen_test.gd      (SEEDS=500 for more; GEN_QUICK=1 samples)
## For every island (1 MEADOW HOP, 2 GEAR WORKS, 3 CRAB COVE, 4 SNOWY PEAKS, 5 JUNGLE JUMBLE, 6 CLOCKWORK KEEP) in every mode, and TODAY'S ISLAND over 400+ days:
## games/sky_bots/levelgen.gd check() (every hop on the main path from the robots' real jump numbers - movers at their
## nearest, lifts on at the bottom and off at the top - the secret island across, floors in the giant's walk, nothing
## overlapping or hanging over a floor, every bolt within a jump, the gold gear in its secret room behind the cracked
## wall, zap floors with a safe lane and a tell of 1 s+, grumbles on their floors, checkpoints close enough, the spark
## on the last floor, Cranky Crab's arena on Crab Cove), the same description gives the same island on every machine,
## every section shows up, harder modes have wider hops, and it all stays fast (< 100 ms on a Deck). The real proof is
## the bot playing islands (tests/sky_bots_bot.gd). Prints "SKY BOTS GEN: PASS" (or FAIL with SCRIPT ERROR lines).

const G := preload("res://games/sky_bots/levelgen.gd")
const Seeded := preload("res://core/seeded.gd")
const TestTime := preload("res://tests/test_time.gd")

var fails := 0


func _initialize() -> void:
	var n := Seeded.test_count(200)
	var worst_ms := 0.0
	var kinds := {}
	var widest := {}
	var total := 0
	for island in range(1, G.ISLANDS + 1):
		for m in G.MODES:
			var r := Seeded.validate(func(s: int) -> Dictionary: return G.generate({"i": island, "s": s, "m": m}),
				func(lv: Dictionary) -> Array: return G.check(lv), n, 1 + island * 1000, [0, 1, 999999], "ISLAND %d %s" % [island, m])
			total += int(r.checked)
			fails += (r.failures as Array).size()
			for s in 12:
				var t1 := Time.get_ticks_usec()
				var lv := G.generate({"i": island, "s": 500 + s * 7, "m": m})
				worst_ms = TestTime.worst(worst_ms, (Time.get_ticks_usec() - t1) / 1000.0,
					func() -> Variant: return G.generate({"i": island, "s": 500 + s * 7, "m": m}))
				for p in lv.plats:
					kinds[String(p.k)] = int(kinds.get(String(p.k), 0)) + 1
				kinds["grumble"] = int(kinds.get("grumble", 0)) + (lv.grumbles as Array).size()
				kinds["zap"] = int(kinds.get("zap", 0)) + (lv.zaps as Array).size()
				kinds["spring"] = int(kinds.get("spring", 0)) + (lv.springs as Array).size()
				kinds["fan"] = int(kinds.get("fan", 0)) + (lv.fans as Array).size()
				kinds["box"] = int(kinds.get("box", 0)) + (lv.boxes as Array).size()
				kinds[G.boss_of(island) + " boss"] = int(kinds.get(G.boss_of(island) + " boss", 0)) + (0 if (lv.boss as Dictionary).is_empty() else 1)
				for hop in lv.chain:
					if (hop as Array).size() > 2:
						continue  # (spring hops and fan floats aren't jumps)
					var a: Dictionary = lv.plats[int(hop[0])]
					var b: Dictionary = lv.plats[int(hop[1])]
					if not a.has("b") and not b.has("b"):
						var gap := absf(float((b.c as Vector3).x) - float((a.c as Vector3).x)) - float((a.s as Vector2).x) * 0.5 - float((b.s as Vector2).x) * 0.5
						widest[m] = maxf(float(widest.get(m, 0.0)), gap)
				# Every machine rebuilds the same island from the host's tiny description.
				var again := G.generate(lv.desc)
				_expect(var_to_str(again.plats) == var_to_str(lv.plats) and var_to_str(again.bolts) == var_to_str(lv.bolts),
					"island %d %s seed %d: the description rebuilds the island" % [island, m, 500 + s * 7])
				_expect((G.boss_of(island) == "") == (lv.boss as Dictionary).is_empty(), "island %d: a boss only on a boss island" % island)
				_expect((lv.boss as Dictionary).is_empty() or String(lv.boss.kind) == G.boss_of(island), "island %d has its own boss" % island)
	for k in ["solid", "mover", "lift", "side", "arena", "grumble", "zap", "belt", "spring", "fan", "box", "crab boss", "king boss"]:
		_expect(int(kinds.get(k, 0)) >= 5, "%s shows up (%s)" % [k, str(kinds)])
	_expect(float(widest.get("hard", 0.0)) > float(widest.get("gentle", 0.0)), "harder modes have wider hops (%s)" % str(widest))
	# TODAY'S ISLAND over 400+ days: the same all day, fair, called TODAY'S ISLAND.
	var rd := Seeded.validate_days(func(date: String) -> Dictionary: return G.generate(G.daily_desc("brave", date)),
		func(lv: Dictionary) -> Array:
			var why := G.check(lv)
			if G.island_name(lv.desc) != G.DAILY_NAME:
				why.append("not TODAY'S ISLAND")
			return why, 400, "DAILY")
	total += int(rd.checked)
	fails += (rd.failures as Array).size()
	_expect(var_to_str(G.daily_desc("gentle", "2026-12-01")) == var_to_str(G.daily_desc("gentle", "2026-12-01")), "TODAY'S ISLAND is the same all day")
	# TODAY'S ISLAND wears every theme some days (the new ones too).
	var themes := {}
	for date in Seeded.dates(60, "2026-12-01"):
		themes[G.theme_of(G.daily_desc("brave", String(date)))] = true
	_expect(themes.size() == G.THEMES.size(), "TODAY'S ISLAND wears every theme (%s)" % str(themes.keys()))
	_expect(G.daily_desc("brave", "2026-12-01").s != G.daily_desc("brave", "2026-12-02").s, "TODAY'S ISLAND changes every day")
	print("sky bots gen: %d islands checked, worst %.1f ms per island" % [total, worst_ms])
	_expect(worst_ms < 60.0, "an island generates + checks in under 60 ms here (%.1f ms)" % worst_ms)
	print("SKY BOTS GEN: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: %s" % what)
