extends SceneTree
## PARTY BOARD party generator: proves the seeded parties are fair over many seeds (no game, no window).
##   godot-test --headless --path . -s res://tests/party_board_gen_test.gd      (SEEDS=500 for more)
## For every board, festival level and party length: games/party_board/partygen.gd check() - the BOARD is fully
## connected (START reaches every space and every space leads back to START), every space can be reached, no
## dead ends, no overlapping tiles, nothing up the volcano or out at sea; START stays; reds, presents and the
## board's special spaces never on a junction / right after START / next to each other; the right numbers of
## each; warp pads far apart; cannons land on the board; the STAR on blue non-junction spaces, its first spot a
## short walk from START and every flight far away; a minigame per round with no repeats in a row and every
## simple one coming; the board event in a real round. Also: the same seed gives the same party, layouts and
## parties differ, levels raise the reds, boards unlock in order, trophies give hats, the festival rules, every
## word is short and UPPERCASE, and generation stays fast (Decks are slow).
## Prints "SCRIPT ERROR: ..." for each failure.

const BD := preload("res://games/party_board/board_data.gd")
const PartyGen := preload("res://games/party_board/partygen.gd")
const Festival := preload("res://games/party_board/festival.gd")
const Boards := preload("res://games/party_board/boards.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 40
	var data := BD.new()
	data.make_simple()
	var total := 0
	var t0 := Time.get_ticks_usec()
	var gens := 0
	var reds := {}
	var seen := {}
	var layouts := {}
	var shortcuts := {}
	for bid in Boards.ids():
		for level in [0, 3, 8, 20]:
			for rounds in [1, 3, 4, 8]:
				var sp := {"level": level, "rounds": rounds, "board": bid}
				var r := Seeded.validate(func(s: int) -> Dictionary: return PartyGen.generate(data, s, sp),
					func(p: Dictionary) -> Array:
						# check against the party's own layout (generate() rebuilt `data` with it)
						var d2 := BD.new()
						d2.build_layout(p.layout)
						d2.make_simple()
						return PartyGen.check(d2, p), seeds, 5 + level, [0, 1, 999999], "PARTY %s l%d r%d" % [bid, level, rounds])
				total += int(r.checked)
				gens += int(r.checked) * 2
				fails += (r.failures as Array).size()
				if rounds == 4 and (level == 0 or level == 8):
					for s in 20:
						var p := PartyGen.generate(data, 300 + s, sp)
						reds[level] = int(reds.get(level, 0)) + int(p.reds)
						seen[var_to_str(p.types) + var_to_str(p.route)] = true
	for s in 200:
		var lay := PartyGen.layout(1000 + s)
		layouts[var_to_str(lay)] = true
		var key := ("T" if not (lay.trail as Array).is_empty() else "") + ("P" if not (lay.pier as Array).is_empty() else "")
		shortcuts[key] = int(shortcuts.get(key, 0)) + 1
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens)
	print("party gen: %.3f ms per party (%d parties)" % [per_ms, gens])
	_expect(per_ms < 30.0, "a party generates in under 30 ms here (%.2f ms; Decks are slower, aim < 100)" % per_ms)
	_expect(int(reds[8]) > int(reds[0]), "more reds as the festival grows (%s)" % str(reds))
	_expect(seen.size() >= 150, "parties differ (%d unique of 200)" % seen.size())
	_expect(layouts.size() >= 190, "board layouts differ (%d unique of 200)" % layouts.size())
	for k in shortcuts:
		_expect(int(shortcuts[k]) >= 25, "each shortcut mix is common enough %s" % str(shortcuts))
	_expect(shortcuts.size() == 3, "trail only, pier only and both shortcuts all happen %s" % str(shortcuts))
	print("party gen: shortcuts %s, %d layouts" % [str(shortcuts), layouts.size()])
	# The classic island is still a valid board.
	var classic := BD.new()
	_expect(PartyGen.check_board(classic).is_empty(), "the classic island board is sound %s" % str(PartyGen.check_board(classic)))
	# The board the party plays on is the board data with the party's types.
	var p0 := PartyGen.generate(data, 42, {"level": 3, "rounds": 4, "board": "space"})
	data.set_types(p0.types)
	_expect(data.type_of(int(p0.route[0])) == "blue", "the STAR starts on blue on the applied board")
	var nred := 0
	for i in data.count():
		nred += 1 if data.type_of(i) == "red" else 0
	_expect(nred == int(p0.reds), "set_types applies the reds (%d / %d)" % [nred, int(p0.reds)])
	_expect(data.star_spots().has(int(p0.route[1])), "the route's spots are the board's star spots")
	_expect((p0.warps as Array).size() >= 2, "the space station has warp pads %s" % str(p0.warps))
	var again := PartyGen.generate(BD.new(), 42, {"level": 3, "rounds": 4, "board": "space"})
	_expect(var_to_str(again) == var_to_str(p0), "the same seed builds the same party on another machine")
	# Hand checks: the validator catches broken boards and parties.
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
	var bad4 := p0.duplicate(true)
	bad4.warps = [int(bad4.warps[0])]
	_expect(not PartyGen.check(data, bad4).is_empty(), "a lonely warp pad is caught")
	var bad5 := p0.duplicate(true)
	(bad5.types as Array)[int(bad5.route[5])] = "cannon"
	_expect(not PartyGen.check(data, bad5).is_empty(), "another board's special space is caught")
	var cut := BD.new()
	cut.build_layout(p0.layout)
	(cut.spaces[3]["next"] as Array).clear()
	_expect(not PartyGen.check_board(cut).is_empty(), "a dead end (a board that isn't connected) is caught")
	var island := BD.new()
	island.build_layout(p0.layout)
	(island.spaces[island.ring - 1]["next"] as Array).clear()
	(island.spaces[island.ring - 1]["next"] as Array).append(island.ring - 2)
	_expect(not PartyGen.check_board(island).is_empty(), "spaces cut off from START are caught")
	var squash := BD.new()
	squash.build_layout(p0.layout)
	squash.spaces[5]["pos"] = squash.spaces[6]["pos"]
	_expect(not PartyGen.check_board(squash).is_empty(), "overlapping tiles are caught")
	# Boards, items, trophies and hats.
	_expect(Boards.unlocked(0, []) == ["island"], "a new family starts on PARTY ISLAND")
	_expect(Boards.unlocked(0, ["haunted"]).has("haunted"), "TODAY'S PARTY unlocks the board it visits")
	_expect(Boards.unlocked(99, []).size() == Boards.BOARDS.size(), "every board unlocks in the end")
	var last := -1
	for b in Boards.BOARDS:
		_expect(int(b.unlock) >= last, "boards unlock in order (%s)" % b.id)
		last = int(b.unlock)
		_expect(Boards.SPECIAL_IDS.has(String(b.special)), "%s has a special space" % b.id)
		_expect(StoryCard.has_picture(String(b.pic)) and StoryCard.has_picture(String(b.event_pic)), "%s has its pictures" % b.id)
		_short(String(b.name), 14)
		_short(String(b.event_word), 12)
	for it in Boards.ITEMS:
		_short(String(it.word), 8)
	var tro := {}
	for tr in Boards.TROPHIES:
		_short(String(tr.line), 14)
		_expect(StoryCard.has_picture(String(tr.pic)) or ["star", "heart", "crown", "trophy"].has(String(tr.pic)),
			"trophy %s has a picture (a story picture or a ui_kit icon)" % tr.id)
		tro[tr.id] = "2026-10-31"
	_expect(Boards.hats({}).is_empty(), "no hats before any trophy")
	_expect(Boards.hats(tro).size() >= 8, "trophies give hats %s" % str(Boards.hats(tro)))
	var sh := Boards.seat_hats(Boards.hats(tro), 3)
	_expect(sh.size() == 7 and String(sh[0]) != "" and String(sh[0]) != String(sh[1]), "seats wear different hats %s" % str(sh))
	for b in Boards.BOARDS:
		_expect(tro.has("win_" + String(b.id)), "every board has its cup (%s)" % b.id)
	# The festival.
	_expect(Festival.offers([]).size() == 2, "two festival pieces to pick from at first")
	var all: Array = []
	for d in Festival.DECOS:
		all.append(d.id)
		_expect(String(d.word).length() <= 10 and String(d.line).length() <= 22, "%s words are short" % d.id)
	_expect(Festival.offers(all).is_empty(), "nothing to pick when the festival is complete")
	_expect(Festival.offers(all.slice(0, 7)).size() == 1, "the last piece comes alone")
	# Festival pieces and the trophy wall never stand on a space, on any layout.
	for s in 30:
		var lay := PartyGen.layout(s * 7 + 1)
		var d3 := BD.new()
		d3.build_layout(lay)
		var spots: Array = []
		for id in Festival.SPOTS:
			spots.append([String(id), Festival.spot(String(id))])
		spots.append(["trophy wall", Festival.wall_spot()])
		for sp2 in spots:
			var q0: Vector3 = sp2[1]
			for i in d3.count():
				var q: Vector3 = d3.pos(i)
				if Vector2(q0.x - q.x, q0.z - q.z).length() < 2.0:
					_fail("%s stands on space %d (layout %d)" % [sp2[0], i, s])
	print("party gen: %d parties checked, %d failures" % [total, fails])
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)


func _short(w: String, n: int) -> void:
	_expect(w == w.to_upper() and w.length() <= n and w.split(" ", false).size() <= 2, "\"%s\" is short and UPPERCASE" % w)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: party gen: " + what)
