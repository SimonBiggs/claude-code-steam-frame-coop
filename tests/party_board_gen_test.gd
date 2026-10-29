extends SceneTree
## PARTY BOARD party generator: proves the seeded parties are fair over many seeds (no game, no window).
##   godot-test --headless --path . -s res://tests/party_board_gen_test.gd      (SEEDS=500 for more)
## For every festival level and party length: games/party_board/partygen.gd check() (START stays, reds
## never on a junction / right after START / two in a row, the right number of reds, the STAR on blue
## non-junction spaces, its first spot a short walk from START and every flight far away, a minigame per
## round with no repeats in a row and every simple one coming), the same seed gives the same party,
## levels raise the reds, parties differ, the festival rules, and generation stays fast (Decks are slow).
## Prints "SCRIPT ERROR: ..." for each failure.

const BD := preload("res://games/party_board/board_data.gd")
const PartyGen := preload("res://games/party_board/partygen.gd")
const Festival := preload("res://games/party_board/festival.gd")
const Seeded := preload("res://core/seeded.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 60
	var data := BD.new()
	data.make_simple()
	var total := 0
	var t0 := Time.get_ticks_usec()
	var gens := 0
	var reds := {}
	var seen := {}
	for level in [0, 2, 5, 8, 20]:
		for rounds in [1, 3, 4, 8]:
			var sp := {"level": level, "rounds": rounds}
			var r := Seeded.validate(func(s: int) -> Dictionary: return PartyGen.generate(data, s, sp),
				func(p: Dictionary) -> Array: return PartyGen.check(data, p), seeds, 5 + level, [0, 1, 999999], "PARTY l%d r%d" % [level, rounds])
			total += int(r.checked)
			gens += int(r.checked) * 2
			fails += (r.failures as Array).size()
			if rounds == 4:
				for s in 20:
					var p := PartyGen.generate(data, 300 + s, sp)
					reds[level] = int(reds.get(level, 0)) + int(p.reds)
					seen[var_to_str(p.types) + var_to_str(p.route)] = true
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens)
	print("party gen: %.3f ms per party (%d parties)" % [per_ms, gens])
	_expect(per_ms < 30.0, "a party generates in under 30 ms here (%.2f ms; Decks are slower, aim < 100)" % per_ms)
	_expect(int(reds[8]) > int(reds[0]), "more reds as the festival grows (%s)" % str(reds))
	_expect(seen.size() >= 78, "parties differ (%d unique of 100; levels 8 and 20 both have the most reds)" % seen.size())
	# The board the party plays on is the board data with the party's types.
	var p0 := PartyGen.generate(data, 42, {"level": 3, "rounds": 4})
	var d2 := BD.new()
	d2.make_simple()
	d2.set_types(p0.types)
	_expect(d2.type_of(int(p0.route[0])) == "blue", "the STAR starts on blue on the applied board")
	var nred := 0
	for i in d2.count():
		nred += 1 if d2.type_of(i) == "red" else 0
	_expect(nred == int(p0.reds), "set_types applies the reds (%d / %d)" % [nred, int(p0.reds)])
	_expect(d2.star_spots().has(int(p0.route[1])), "the route's spots are the board's star spots")
	# Hand checks: the validator catches broken parties.
	var bad := p0.duplicate(true)
	var t: Array = bad.types
	var jn := -1
	for i in data.count():
		if data.is_junction(i):
			jn = i
	t[jn] = "red"
	_expect(not PartyGen.check(data, bad).is_empty(), "a red junction is caught")
	var bad2 := p0.duplicate(true)
	bad2.route[3] = bad2.route[2]
	_expect(not PartyGen.check(data, bad2).is_empty(), "a STAR that doesn't fly is caught")
	var bad3 := p0.duplicate(true)
	bad3.minigames = ["coin_catch", "coin_catch", "kart_dash", "balloon_pop"]
	_expect(not PartyGen.check(data, bad3).is_empty(), "the same minigame twice in a row is caught")
	# The festival.
	_expect(Festival.offers([]).size() == 2, "two festival pieces to pick from at first")
	var all: Array = []
	for d in Festival.DECOS:
		all.append(d.id)
		_expect(String(d.word).length() <= 10 and String(d.line).length() <= 22, "%s words are short" % d.id)
	_expect(Festival.offers(all).is_empty(), "nothing to pick when the festival is complete")
	_expect(Festival.offers(all.slice(0, 7)).size() == 1, "the last piece comes alone")
	for id in Festival.SPOTS:
		var p: Vector3 = Festival.spot(String(id))
		for i in data.count():
			var q: Vector3 = data.pos(i)
			if Vector2(p.x - q.x, p.z - q.z).length() < 2.0:
				_fail("festival piece %s stands on space %d" % [id, i])
	print("party gen: %d parties checked, %d failures" % [total, fails])
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: party gen: " + what)
