extends SceneTree
## ROCKET WORKSHOP generator: proves every seeded rocket is solvable and fair (no game, no window).
##   godot-test --headless --path . -s res://tests/rocket_workshop_gen_test.gd      (SEEDS=500 for more)
## For simple and full mode, rocket numbers 1-16, crews of 0-6 and parts unlocked from none to all:
## games/rocket_workshop/rocketgen.gd check() (every answer is something the desk can do, the crew can
## find this rocket's row on the boards, the new control comes first, no doubled modules, time for the
## jobs, no more jobs than the crew can carry, only unlocked parts, gold only on TODAY'S ROCKET), the
## same seed gives the same rocket, the challenge grows in readable steps, every part shows up, every
## unlock is reachable and announced, TODAY'S ROCKET is the same all day and differs between days,
## Rocket Row has room and stands clear of the pad, the walk area and the trees, Sprocket's pictures
## exist, and generation stays fast (Decks are slow). Prints "SCRIPT ERROR: ..." per failure.

const G := preload("res://games/rocket_workshop/rocketgen.gd")
const P := preload("res://games/rocket_workshop/puzzles.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 40
	var t0 := Time.get_ticks_usec()
	var gens := 0
	var parts_seen := {}
	var sizes := {}  # level -> total blueprint pictures (simple)
	for simple in [true, false]:
		for n in range(1, 17):
			for crew in ([0, 1, 3, 6] if simple else [1, 2, 3, 5, 6]):
				for launched in [0, 3, 12, 40]:
					var ctx := {"n": n, "crew": crew, "simple": simple, "launched": launched}
					var res := Seeded.validate(func(s: int) -> Dictionary: return G.rocket(s, n, crew, simple, launched),
						func(rk: Dictionary) -> Array: return G.check(rk, ctx),
						seeds, 3 + n, [0, 999999], "ROCKET %s n%d crew%d parts%d" % ["simple" if simple else "full", n, crew, launched])
					gens += int(res.checked) * 2
					fails += (res.failures as Array).size()
					if simple and crew == 1 and launched == 0:
						var lv := P.simple_level(n)
						for s in 20:
							sizes[lv] = float(sizes.get(lv, 0.0)) + _pictures(G.rocket(s, n, crew, true, 0)) / 20.0 / _count_n(lv)
	for s in 400:  # (a look depends on the seed and the parts, not the rocket number)
		var lk: Array = G.rocket(s * 31 + 5, 3, 1, true, 40).look
		for k in [G.L_FINS, G.L_NOSE, G.L_EXTRA, G.L_BODY, G.L_TRIM]:
			parts_seen["%d:%d" % [k, int(lk[k])]] = true
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens)
	print("rocket gen: %.3f ms per rocket incl. check (%d rockets)" % [per_ms, gens])
	_expect(per_ms < 5.0, "a rocket generates + checks in under 5 ms here (%.2f ms; Decks are slower, aim < 100)" % per_ms)
	# TODAY'S ROCKET: gold, valid, the same all day, different between days.
	for date in ["2026-10-29", "2026-12-25", "2027-01-01"]:
		var ds := G.daily_seed(date)
		_expect(ds == G.daily_seed(date), "the daily seed is stable for %s" % date)
		for simple in [true, false]:
			var rk := G.rocket(ds, G.DAILY_N, 1, simple, 0, true)
			for why in G.check(rk, {"n": G.DAILY_N, "crew": 1, "simple": simple, "launched": 0}):
				_expect(false, "TODAY'S ROCKET %s: %s" % [date, why])
			_expect(var_to_str(rk) == var_to_str(G.rocket(ds, G.DAILY_N, 1, simple, 0, true)), "TODAY'S ROCKET is the same all day")
	_expect(G.daily_seed("2026-10-29") != G.daily_seed("2026-10-30"), "a new TODAY'S ROCKET each day")
	# Readable rising challenge: more to read on the boards at each level, never fewer.
	print("simple blueprint pictures per level: %s" % str(sizes))
	_expect(float(sizes.get(2, 0.0)) > float(sizes.get(1, 0.0)) and float(sizes.get(3, 0.0)) > float(sizes.get(2, 0.0)),
		"simple rockets get bigger blueprints level by level %s" % str(sizes))
	for n in range(1, 30):
		_expect(P.simple_level(n + 1) >= P.simple_level(n), "levels never drop (rocket %d)" % n)
	# Every part shows up once unlocked; every unlock is reachable, in order, and has a line.
	for k in G.FINS.size():
		_expect(parts_seen.has("%d:%d" % [G.L_FINS, k]), "fins %s are used" % G.FINS[k])
	for k in G.NOSES.size():
		_expect(parts_seen.has("%d:%d" % [G.L_NOSE, k]), "nose %s is used" % G.NOSES[k])
	for k in G.EXTRAS.size():
		_expect(parts_seen.has("%d:%d" % [G.L_EXTRA, k]), "extra %s is used" % G.EXTRAS[k])
	for k in G.BODY_COLORS.size():
		_expect(parts_seen.has("%d:%d" % [G.L_BODY, k]), "body colour %d is used" % k)
	var last := 0
	for u in G.UNLOCKS:
		_expect(int(u.at) > last, "unlocks come in order (%d)" % int(u.at))
		_expect(String(u.line) != "" and String(u.line).length() <= 18, "unlock line is a few words: %s" % u.line)
		_expect(G.new_unlocks(int(u.at) - 1, int(u.at)).size() == 1, "unlock at %d is announced once" % int(u.at))
		var lk := G.look(Seeded.rng(7), int(u.at), false)
		var shown := true
		match String(u.kind):
			"fins":
				shown = int(lk[G.L_FINS]) == int(u.v)
			"nose":
				shown = int(lk[G.L_NOSE]) == int(u.v)
			"extra":
				shown = int(lk[G.L_EXTRA]) == int(u.v)
			"colour":
				shown = int(lk[G.L_BODY]) == int(u.v)
		_expect(shown, "the rocket after unlock %s wears it (%s)" % [u.line, str(lk)])
		last = int(u.at)
	var all := G.unlocked(1000)
	_expect((all.fins as Array).size() == G.FINS.size() and (all.nose as Array).size() == G.NOSES.size()
		and (all.extra as Array).size() == G.EXTRAS.size() and (all.body as Array).size() == G.BODY_COLORS.size(), "everything unlocks in the end")
	_expect(not (all.trim as Array).has(G.GOLD), "gold trim stays special")
	# Rocket Row: room for plenty, every slot in a free spot (clear of the pad, the walk area, the trees).
	var slots := G.museum_size()
	_expect(slots >= 30, "Rocket Row holds at least 30 rockets (%d)" % slots)
	_expect(G.museum_slot(slots) == Vector3.INF, "no slot past the end")
	var trees: Array[Vector3] = [Vector3(-12.5, 0, -11), Vector3(-12, 0, -16), Vector3(8, 0, -14), Vector3(12, 0, -10),
		Vector3(-15, 0, -8), Vector3(15, 0, -17), Vector3(3.5, 0, -26), Vector3(-6.5, 0, -25.5)]
	var seen_spots := {}
	for i in slots:
		var at := G.museum_slot(i)
		_expect(at.z < -17.6, "slot %d stands past the crew's walk area (%s)" % [i, str(at)])
		_expect(Vector2(at.x, at.z + 11.0).length() > 6.0, "slot %d is clear of the launch pad" % i)
		for tr in trees:
			_expect(Vector2(at.x - tr.x, at.z - tr.z).length() > 1.8, "slot %d is clear of the tree at %s" % [i, str(tr)])
		var key := "%.1f,%.1f" % [at.x, at.z]
		_expect(not seen_spots.has(key), "slot %d has its own spot" % i)
		seen_spots[key] = true
	_expect(G.MUSEUM_KEEP >= slots, "the save keeps at least a full row")
	# Pictures Sprocket shows.
	for pic in ["engineer", "toyrocket"]:
		_expect(StoryCard.has_picture(pic), "story picture %s exists" % pic)
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)


func _count_n(lv: int) -> float:
	var c := 0
	for n in range(1, 17):
		if P.simple_level(n) == lv:
			c += 1
	return float(c)


## How many things the crew read off the boards for a rocket (buttons, plugs, shapes, switches up, dial).
func _pictures(rk: Dictionary) -> float:
	var total := 0.0
	for m in rk.modules:
		match String(m.type):
			"fuel":
				total += (m.answer as Array).size()
			"wires":
				for c in m.order:
					total += 1.0 if int(c) >= 0 else 0.0
			"symbols":
				total += (m.order as Array).size()
			"switches":
				for b in m.answer:
					total += 1.0 if bool(b) else 0.0
			"gauge":
				total += 1.0
	return total


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: %s" % what)
