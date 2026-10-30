extends SceneTree
## PAINT AND GUESS generator: proves every seeded game is fair and playable by small kids who can't read yet
## (no game, no window).   godot-test --headless --path . -s res://tests/paint_and_guess_gen_test.gd   (SEEDS=500 for more)
## For every number of unlocked themes and TODAY'S GALLERY: games/paint_and_guess/paintgen.gd check() (every
## answer is a picture, the right one is there exactly once for every seat and everyone has the same four, no
## look-alikes, all from the round's theme, easy rounds ask for easy things with differently shaped wrong
## answers, the right answer's place moves about, nothing is asked twice, there's time to find it after three
## wrong picks), the packs themselves (check_packs), the same seed gives the same game, rounds get harder,
## TODAY'S GALLERY is the same all day and new each day, codes round-trip, themes unlock as the gallery grows,
## paintings pack small and come back, the family gallery has room on the walls, the story pictures exist, the
## constants match the game's, and generation stays fast. Prints "SCRIPT ERROR: ..." per failure.

const G := preload("res://games/paint_and_guess/paintgen.gd")
const Main := preload("res://games/paint_and_guess/main.gd")
const Canvas := preload("res://games/paint_and_guess/canvas.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 120
	for why in G.check_packs():
		_expect(false, "packs: %s" % why)
	var t0 := Time.get_ticks_usec()
	var gens := 0
	var tiers: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	var tier_n := 0
	var targets_seen := {}
	var themes_seen := {}
	for tn in range(G.BASE_THEMES, G.THEMES.size() + 1):
		var res := Seeded.validate(func(s: int) -> Dictionary: return G.build(G.code_of(s, tn, false)),
			func(d: Dictionary) -> Array: return G.check(d), seeds, 5 + tn, [0, 999999], "GAME T%d" % tn)
		gens += int(res.checked)
		fails += (res.failures as Array).size()
		for k in 40:
			var d := G.build(G.code_of(k * 131 + 7, tn, false))
			tier_n += 1
			for ri in G.ROUNDS:
				var rd: Dictionary = d.rounds[ri]
				tiers[ri] += float(G.tier(str(rd.target)))
				targets_seen[str(rd.target)] = true
				themes_seen[int(rd.theme)] = true
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens * 2.0)
	print("game gen: %.2f ms per game incl. check (%d games)" % [per_ms, gens * 2])
	_expect(per_ms < 25.0, "a game generates + checks fast (%.2f ms here; Decks ~3x slower, aim < 100)" % per_ms)
	for ri in G.ROUNDS:
		tiers[ri] /= float(tier_n)
	print("average tier per round: %s" % str(tiers))
	_expect(tiers[0] <= 1.01, "round 1 always asks for an easy thing")
	_expect(tiers[2] <= 1.01, "TEAM PAINT always asks for an easy thing")
	_expect(tiers[4] > tiers[0] + 1.0, "the golden final is clearly trickier than round 1")
	_expect(tiers[3] > tiers[0], "the speed round is trickier than round 1")
	_expect(themes_seen.size() == G.THEMES.size(), "every theme comes up (%d)" % themes_seen.size())
	_expect(targets_seen.size() >= 40, "lots of different things to paint (%d)" % targets_seen.size())
	# Base games only use the starting themes; unlocked themes come up.
	for k in 30:
		var d := G.build(G.code_of(k * 17 + 3, G.BASE_THEMES, false))
		for rd in d.rounds:
			_expect(int(rd.theme) < G.BASE_THEMES, "a new family only meets the starting themes")
	var newest := 0
	for k in 30:
		var d := G.build(G.code_of(k * 17 + 3, G.BASE_THEMES + 1, false))
		for rd in d.rounds:
			if int(rd.theme) == G.BASE_THEMES:
				newest += 1
	_expect(newest >= 20, "a newly unlocked theme comes up often (%d of 30 games)" % newest)
	# Codes round-trip; session order: TODAY'S GALLERY first when due.
	for s in [0, 1, 4242, 999999]:
		for tn in range(G.BASE_THEMES, G.THEMES.size() + 1):
			for dy in [false, true]:
				var c := G.code_of(s, tn, dy)
				_expect(G.seed_of(c) == s and G.themes_of(c) == tn and G.daily_of(c) == dy, "code round-trips (%d, %d, %s)" % [s, tn, dy])
	_expect(G.daily_of(G.code_at(5, 1, true, 7)) and not G.daily_of(G.code_at(5, 2, true, 7)), "TODAY'S GALLERY is the first game when due")
	_expect(not G.daily_of(G.code_at(5, 1, false, 7)), "no TODAY'S GALLERY once it's done")
	_expect(G.themes_of(G.code_at(5, 2, true, 7)) == 7, "later games use the family's unlocked themes")
	_expect(G.code_at(5, 2, false, 6) != G.code_at(5, 3, false, 6), "each game of a session is new")
	for date in ["2026-10-30", "2026-12-25", "2027-01-01"]:
		var dc := G.code_at(77, 1, true, 5, date)
		_expect(dc == G.code_at(123456, 1, true, 7, date), "TODAY'S GALLERY is the same for every session and family all day")
		_expect(G.themes_of(dc) == G.BASE_THEMES, "TODAY'S GALLERY uses the starting themes (same on every machine)")
		var dd := G.build(dc)
		_expect(str(dd.name) == "TODAY'S GALLERY", "TODAY'S GALLERY is called that")
		for why in G.check(dd):
			_expect(false, "TODAY'S GALLERY %s: %s" % [date, why])
	_expect(G.daily_seed("2026-10-30") != G.daily_seed("2026-10-31"), "a new TODAY'S GALLERY each day")
	# Unlocks.
	_expect(G.themes_unlocked(0) == G.BASE_THEMES, "a new family starts with the starting themes")
	_expect(G.themes_unlocked(G.UNLOCK_EVERY) == G.BASE_THEMES + 1, "a theme unlocks after UNLOCK_EVERY paintings")
	_expect(G.themes_unlocked(9999) == G.THEMES.size(), "unlocks stop at the last theme")
	_expect(G.paintings_to_unlock(0) == G.UNLOCK_EVERY and G.paintings_to_unlock(G.UNLOCK_EVERY - 1) == 1, "paintings to the next theme")
	_expect(G.paintings_to_unlock(9999) == 0, "nothing left to unlock")
	# The checker really catches unfair games.
	var d1 := G.build(G.code_of(11, G.BASE_THEMES, false))
	var bad := d1.duplicate(true)
	(bad.rounds[0].opts[2] as Array)[0] = "dragon"
	(bad.rounds[0].opts[2] as Array)[1] = "dragon"
	_expect(not G.check(bad).is_empty(), "a seat with a duplicate / missing answer is caught")
	var hard := d1.duplicate(true)
	hard.rounds[0].target = "lion"
	_expect(not G.check(hard).is_empty(), "a tricky thing in round 1 is caught")
	var same := d1.duplicate(true)
	for seat in G.MAX_PLAYERS:
		var o: Array = same.rounds[1].opts[seat]
		var tg := str(same.rounds[1].target)
		o.erase(tg)
		o.push_front(tg)
	_expect(not G.check(same).is_empty(), "the right answer in the same place for everyone is caught")
	var look := d1.duplicate(true)
	look.rounds[1].theme = 1
	look.rounds[1].target = "apple"
	for seat in G.MAX_PLAYERS:
		look.rounds[1].opts[seat] = ["apple", "orange", "carrot", "pie"]
	_expect(not G.check(look).is_empty(), "look-alike answers (apple and orange) are caught")
	var twice := d1.duplicate(true)
	twice.rounds[3].target = twice.rounds[1].target
	_expect(not G.check(twice).is_empty(), "the same thing twice in a game is caught")
	# Paintings pack small and come back.
	var strokes: Array = []
	var pts := PackedVector2Array()
	for i in 900:
		pts.append(Vector2(sin(float(i) * 0.05) * 0.5, cos(float(i) * 0.03) * 0.35))
	strokes.append([1, 3, 0.03, pts, 0])
	strokes.append([2, Canvas.RAINBOW, 0.05, PackedVector2Array([Vector2(-0.6, -0.4), Vector2(0.6, 0.4)]), 0])
	var packed := G.pack_strokes(strokes, Canvas.W, Canvas.H)
	_expect(G.packed_size(packed) < 1200, "a painting packs small (%d bytes)" % G.packed_size(packed))
	var back := G.unpack_strokes(packed, Canvas.W, Canvas.H)
	_expect(back.size() == 2 and int(back[1][1]) == Canvas.RAINBOW, "strokes and colours come back")
	_expect(absf(float(back[0][2]) - 0.03) < 0.001, "brush widths come back")
	var bp: PackedVector2Array = back[1][3]
	_expect(bp.size() == 2 and bp[0].distance_to(Vector2(-0.6, -0.4)) < 0.01 and bp[1].distance_to(Vector2(0.6, 0.4)) < 0.01, "points come back close")
	var bp0: PackedVector2Array = back[0][3]
	_expect(bp0.size() <= G.PACK_POINTS + 2 and bp0.size() >= G.PACK_POINTS / 3, "long paintings are thinned (%d points)" % bp0.size())
	_expect(G.unpack_strokes([[1, 2]], 1.0, 1.0).is_empty() and G.unpack_strokes([], 1.0, 1.0).is_empty(), "broken saves unpack to nothing")
	_expect(G.packed_size(packed) * G.GALLERY_MAX < 60000, "the whole family gallery stays small")
	# The family gallery has room on the side walls, clear of the window and the shelves.
	var spots: Array = []
	for i in G.GALLERY_MAX:
		var at := G.family_slot(i)
		_expect(absf(at.x) > 4.0 and absf(at.x) < 4.2, "family frame %d is on a side wall (%s)" % [i, str(at)])
		_expect(at.z > 0.4 and at.z < 4.4 and at.y > 1.2 and at.y < 3.0, "family frame %d is clear of the window and shelves (%s)" % [i, str(at)])
		for o in spots:
			_expect((o as Vector3).distance_to(at) > 0.65, "family frame %d has room" % i)
		spots.append(at)
	_expect(G.family_slot(G.GALLERY_MAX) == Vector3.INF, "no family frame past the end")
	# The game uses the same numbers.
	_expect(G.ROUNDS == Main.ROUNDS and G.ROUND_PLAN == Main.ROUND_PLAN, "the round plan matches main.gd")
	_expect(is_equal_approx(G.LOCKOUT, Main.LOCKOUT), "LOCKOUT matches main.gd")
	_expect(G.MAX_PLAYERS == Main.MAX_PLAYERS, "seats match main.gd")
	var m: Node = Main.new()
	for type in G.ROUND_TIMES:
		m.set("round_type", type)
		_expect(is_equal_approx(float(G.ROUND_TIMES[type]), float(m.call("round_time"))), "%s round time matches main.gd" % type)
	m.free()
	for pic in ["smudge", "paintpot", "goldframe"]:
		_expect(StoryCard.has_picture(pic), "story picture %s exists" % pic)
	for why in StoryCard.check():
		_expect(false, why)
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: %s" % what)
