extends SceneTree
## SHEEP ROUND-UP field generator: proves the seeded fields are fair over many seeds (no game, no window).
##   godot-test --headless --path . -s res://tests/sheep_round_up_gen_test.gd      (SEEDS=300 for more)
## For every level (the plain first field .. a late field with a stream, hedges and one gate) and player
## count: games/sheep_round_up/fieldgen.gd check() (every sheep has a herding path to an open gate, no
## pockets a sheep can't be herded out of, gate doorsteps clear, dogs reach everywhere, nothing tall
## near the cameras), the same seed gives the same field, generate() rarely needs its plain fallback,
## fields get harder as levels rise, breeds appear when they should, TODAY'S FIELD is the same all day,
## the geometry the game uses (fence gates, the stream, hedges) behaves, the farm's story rules, and
## generation stays fast (Decks are slow: < 100 ms there). Prints "SCRIPT ERROR: ..." for each failure.

const FieldGen := preload("res://games/sheep_round_up/fieldgen.gd")
const Farm := preload("res://games/sheep_round_up/farm.gd")
const Seeded := preload("res://core/seeded.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 40
	var total := 0
	var gens := 0
	var plain := 0
	var attempts := 0
	var t0 := Time.get_ticks_usec()
	var stats := {}  # level -> [hedges, bushes, streams, gates open, breeds seen]
	for lv in [0, 1, 2, 3, 4, 5, 6, 8, 11]:
		for players in [1, 3, 6]:
			var sp := FieldGen.spec(lv, players, 120.0)
			var r := Seeded.validate(func(s: int) -> Dictionary: return FieldGen.generate(s, sp),
				func(f: Dictionary) -> Array: return FieldGen.check(f),
				seeds if players == 3 else seeds / 3, 17 + lv, [0, 1, 999999], "SHEEP L%d p%d" % [lv, players])
			total += int(r.checked)
			gens += int(r.checked) * 2
			fails += (r.failures as Array).size()
			if players == 3:
				var st := [0, 0, 0, 0, {}]
				for s in 20:
					var f := FieldGen.generate(300 + s, sp)
					attempts += int(f.attempt)
					if int(f.attempt) == 99:
						plain += 1
					st[0] += (f.hedges as Array).size()
					st[1] += (f.bushes as Array).size()
					st[2] += 0 if (f.stream as Dictionary).is_empty() else 1
					for side in 4:
						st[3] += 1 if FieldGen.gate_open(int(f.gates), side) else 0
					for sh in f.sheep:
						st[4][int(sh[2])] = int(st[4].get(int(sh[2]), 0)) + 1
				stats[lv] = st
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens)
	print("sheep gen: %.2f ms per field (%d fields), %d plain fallbacks of 180, %d extra attempts" % [per_ms, gens, plain, attempts])
	for lv in stats:
		print("  level %d: hedges %d bushes %d streams %d gates %d breeds %s (20 fields)" % [lv, stats[lv][0], stats[lv][1], stats[lv][2], stats[lv][3], str(stats[lv][4])])
	_expect(per_ms < 25.0, "a field generates in under 25 ms here (%.2f ms; Decks are ~3x slower, aim < 100)" % per_ms)
	_expect(plain <= 4, "generate() rarely falls back to the plain field (%d of 180)" % plain)
	# Rising challenge.
	_expect(stats[0][0] == 0 and stats[0][1] == 0 and stats[0][2] == 0 and stats[0][3] == 80, "the first field is plain with every gate open")
	_expect(stats[3][2] >= 18, "field 4 (level 3) brings the stream (%d of 20)" % stats[3][2])
	_expect(stats[8][3] < stats[0][3] and stats[8][0] > stats[2][0], "later fields have fewer open gates and more hedges")
	_expect(FieldGen.spec(8, 2).n > FieldGen.spec(0, 2).n, "later fields have more sheep")
	_expect((stats[0][4] as Dictionary).keys() == [FieldGen.WHITE], "the first field has only woolly sheep (%s)" % str(stats[0][4]))
	for b in FieldGen.BREEDS.size():
		_expect(int(stats[11][4].get(b, 0)) > 0 or (b == FieldGen.GOLDEN and int(stats[5][4].get(b, 0)) > 0), "breed %s shows up later (%s)" % [FieldGen.BREEDS[b].id, str(stats[11][4])])
		var from := int(FieldGen.BREEDS[b].from)
		if from > 0:
			_expect(not stats[from - 1][4].has(b) and (from - 1 < 1 or true), "breed %s never comes before level %d" % [FieldGen.BREEDS[b].id, from])
	# TODAY'S FIELD: fair, the same all day, different day to day.
	var days := {}
	for d in 40:
		var date := Time.get_date_string_from_unix_time(1790000000 + d * 86400)
		var f := FieldGen.generate(FieldGen.daily_seed(date), FieldGen.daily_spec(3, 120.0, date))
		for w in FieldGen.check(f):
			_fail("daily %s: %s" % [date, w])
		_expect(var_to_str(f) == var_to_str(FieldGen.generate(FieldGen.daily_seed(date), FieldGen.daily_spec(3, 120.0, date))), "daily %s is the same all day" % date)
		_expect(bool(f.daily), "the daily field knows it's the daily")
		days[var_to_str(f.sheep)] = true
		total += 1
	_expect(days.size() >= 39, "daily fields differ day to day (%d unique of 40)" % days.size())
	# The validator catches broken fields.
	var good := FieldGen.generate(5, FieldGen.spec(6, 3))
	var walled := good.duplicate(true)
	walled.hedges = []
	for side in 4:
		var a := FieldGen._rot(side, Vector2(-1.2, FieldGen.PEN + 0.5))
		var b := FieldGen._rot(side, Vector2(1.2, FieldGen.PEN + 0.5))
		walled.hedges.append([a.x, a.y, b.x, b.y])
	_expect(not FieldGen.check(walled).is_empty(), "hedges across every gate are caught")
	var ring := good.duplicate(true)
	ring.hedges = []
	ring.stream = {}
	ring.bushes = []
	var sp0: Array = ring.sheep[0]
	var c := Vector2(sp0[0], sp0[1])
	for k in 8:
		var a := c + Vector2.from_angle(k * TAU / 8.0) * 0.9
		var b := c + Vector2.from_angle((k + 1) * TAU / 8.0) * 0.9
		ring.hedges.append([a.x, a.y, b.x, b.y])
	_expect(not FieldGen.check(ring).is_empty(), "a sheep fenced in by a ring of hedge is caught")
	var tall := good.duplicate(true)
	tall.trees.append([0.0, FieldGen.ARENA + 3.0, 1.2])
	_expect(not FieldGen.check(tall).is_empty(), "a tree where a follow camera can be is caught")
	var big := good.duplicate(true)
	big.bushes.append([0.0, 6.0, 1.0])
	_expect(not FieldGen.check(big).is_empty(), "a bush tall enough to hide a dog is caught")
	var shut := good.duplicate(true)
	shut.gates = 0
	_expect(not FieldGen.check(shut).is_empty(), "a pen with every gate shut is caught")
	var dry := FieldGen.generate(9, FieldGen.spec(5, 3))
	if not (dry.stream as Dictionary).is_empty():
		var nb := dry.duplicate(true)
		nb.stream.bridges = []
		_expect(not FieldGen.check(nb).is_empty(), "a stream with no bridge is caught")
	# Geometry the game uses.
	var g2 := {"gates": 1, "stream": {}, "hedges": [], "bushes": []}  # only the south gate open
	_expect(FieldGen.in_pen(FieldGen.fence_block(Vector3(0.0, 0.0, 1.7), Vector3(0.0, 0.0, 1.5), 1)), "a sheep walks in through an open gate")
	_expect(not FieldGen.in_pen(FieldGen.fence_block(Vector3(0.0, 0.0, -1.7), Vector3(0.0, 0.0, -1.5), 1)), "a shut gate keeps a sheep out")
	_expect(not FieldGen.in_pen(FieldGen.fence_block(Vector3(1.7, 0.0, 0.0), Vector3(1.5, 0.0, 0.0), 1)), "a shut side gate keeps a sheep out")
	_expect(FieldGen.move_sheep(g2, Vector3.ZERO, Vector3(0.1, 0.0, 0.0)).x > 0.05, "nothing in the way: a sheep just walks")
	var hf := {"stream": {}, "hedges": [[-1.0, 4.0, 1.0, 4.0]], "bushes": [[3.0, 3.0, 0.5]]}
	var hp := FieldGen.move_sheep(hf, Vector3(0.0, 0.0, 3.5), Vector3(0.0, 0.0, 3.95))
	_expect(hp.z < 4.0 - FieldGen.HEDGE_R - FieldGen.SHEEP_R + 0.01, "a hedge stops a sheep (%.2f)" % hp.z)
	_expect(FieldGen.move_dog(hf, Vector3(3.0, 0.0, 3.1)).distance_to(Vector3(3.0, 0.0, 3.0)) >= 0.79, "a bush pushes a dog out")
	# tangent t = -x nz + z nx: the bridge at t = 2 is at x = -2
	var sf := {"stream": {"n": [0.0, 1.0], "d": 5.0, "w": 0.55, "bridges": [2.0]}, "hedges": [], "bushes": []}
	_expect(FieldGen.water_at(sf, 0.0, 5.0) and not FieldGen.water_at(sf, -2.0, 5.0) and not FieldGen.water_at(sf, 0.0, 6.0), "the stream is wet except on its bridge")
	var bank := FieldGen.move_sheep(sf, Vector3(0.0, 0.0, 4.4), Vector3(0.0, 0.0, 4.6))
	_expect(not FieldGen.water_at(sf, bank.x, bank.z), "a sheep never walks into the stream")
	_expect(FieldGen.move_sheep(sf, Vector3(-2.0, 0.0, 4.4), Vector3(-2.0, 0.0, 4.6)).z > 4.55, "a sheep walks onto a bridge")
	var out := FieldGen.move_sheep(sf, Vector3(0.0, 0.0, 5.1), Vector3(0.0, 0.0, 5.1))
	_expect(not FieldGen.water_at(sf, out.x, out.z), "a sheep thrown in the stream scrambles out")
	# The farm's story rules.
	_expect(Farm.new_milestones(9, 12).size() == 1 and Farm.new_milestones(12, 20).is_empty(), "the barn comes at 10 sheep, once")
	_expect(Farm.built_for(30) == ["barn", "hay"], "built things are kept (%s)" % str(Farm.built_for(30)))
	_expect(Farm.stars(true, 60.0, 120.0) == 3 and Farm.stars(true, 5.0, 120.0) == 1 and Farm.stars(false, 60.0, 120.0) == 0, "stars by time left")
	var d0 := Farm.save_defaults()
	d0.world = 1234
	_expect(var_to_str(Farm.next_field(d0, 2, 120.0)) == var_to_str(Farm.next_field(d0, 2, 120.0)), "the next field is the same for the same farm")
	d0.rounds = 1
	_expect(int(Farm.next_field(d0, 2, 120.0).seed) != int(Farm.next_field(d0.merged({"rounds": 0}, true), 2, 120.0).seed), "a retry is a fresh layout")
	for m in Farm.MILESTONES:
		_expect(String(m[3]).length() <= 26, "milestone line '%s' is short" % m[3])
	for b in FieldGen.BREEDS:
		_expect(String(b.line).length() <= 26, "breed line '%s' is short" % b.line)
	for c2 in Farm.CHEERS:
		_expect(c2.length() <= 26, "cheer '%s' is short" % c2)
	print("sheep gen: %d fields checked, %d failures" % [total, fails])
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: sheep gen: " + what)
