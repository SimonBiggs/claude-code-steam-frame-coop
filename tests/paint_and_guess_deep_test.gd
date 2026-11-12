extends SceneTree
## PAINT AND GUESS second pass validator (no game, no window): games/paint_and_guess/deep.gd + paintgen.gd modes.
##   godot-test --headless --path . -s res://tests/paint_and_guess_deep_test.gd      (SEEDS=200 for more; GEN_QUICK=1 samples)
## Proves:
##   - GENTLE <= BRAVE <= HARD: the mode table (deep.gd ordered()) AND what the games really get (how hard the pictures
##     are, how alike the answers look, round seconds), every moded game passes paintgen.gd check(), codes carry the
##     mode (older codes read as BRAVE);
##   - TODAY'S GALLERY over 400+ dates in every mode: fair (check()), the starting themes, winnable by a lone painter
##     (Smudge guesses in time in every round);
##   - the surprises are fair on many paintings (deep.gd problems(): bare canvas only - never over paint - on the
##     canvas, told long enough, the mode's size), the same every time, unchanged over the network (pack), and the
##     painting around them never reaches inside while they show (blocks()), so they never spoil anyone's picture;
##   - Smudge's gifts never break the proof: the PEEK GLASS never crosses out the right answer (every seat of every
##     round), the SLOW CLOCK only adds time, BIG BRUSH paint stays within the surprises' padding, STAMPS stay on the
##     canvas; three different unlocked gifts are offered, the newest among them, not the last again when there are
##     others; every picture drawn; short names;
##   - SMUDGE GUESSES in time in every round type, mode and gift for a small kid's painting speed;
##   - the seasons: a picture, a short line; every date has a season;
##   - Smudge's museum: a treasure for every game, every kind comes, a cat statue every tenth, spots apart on the floor
##     by the side walls, under the window and the shelves, clear of the season props;
##   - the pick rows: canvas orbs in front of the canvas with their spots on it, apart, rings start under none; VR orbs
##     an arm's reach in front of the artist, small, apart, GENTLE on the left; picks need a deliberate touch;
##   - constants match the game's; every key colour stands out (palette.gd); fast: a surprise spot is found and
##     checked well under 100 ms.
## Prints "SCRIPT ERROR: ..." for each failure and "PAINT DEEP: PASS" / "FAIL".

const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/paint_and_guess/deep.gd")
const G := preload("res://games/paint_and_guess/paintgen.gd")
const Canvas := preload("res://games/paint_and_guess/canvas.gd")
const Artist := preload("res://games/paint_and_guess/artist.gd")
const Main := preload("res://games/paint_and_guess/main.gd")
const Season := preload("res://games/paint_and_guess/season.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const Seeded := preload("res://core/seeded.gd")
const TestTime := preload("res://tests/test_time.gd")

var fails := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	for w in Deep.ordered():
		_fail("modes: " + str(w))
	for w in Contrast.check_game("paint_and_guess"):
		_fail("contrast: " + str(w))
	_check_modes()
	_check_daily()
	_check_surprises()
	_check_gifts()
	_check_smudge()
	_check_seasons_museum()
	_check_rows()
	# Constants match the game's.
	_expect(Deep.MAX_HALF_W >= Artist.SPARKLE_W * Deep.BIG * 0.5 and Deep.MAX_HALF_W >= Artist.BRUSH_W * Deep.BIG * 0.5
		and Deep.MAX_HALF_W >= Main.TEAM_BRUSH_W * Deep.BIG * 0.5, "the widest paint (BIG BRUSH) fits the surprises' padding")
	_expect(is_equal_approx(Deep.round_time("paint", "brave", ""), G.ROUND_TIMES["paint"]), "brave rounds are the old rounds")
	for why in StoryCard.check():
		_fail(why)
	print("paint deep: %d ms in all" % (Time.get_ticks_msec() - t0))
	print("PAINT DEEP: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)


## Every mode's games are fair; GENTLE <= BRAVE <= HARD in what they really ask.
func _check_modes() -> void:
	var tiers := {}
	var alike := {}
	for m in PickOrbs.MODE_IDS:
		tiers[m] = 0.0
		alike[m] = 0
		var res := Seeded.validate(func(s: int) -> Array:
				var out: Array = []
				for tn in [G.BASE_THEMES, G.THEMES.size()]:
					out.append(G.build(G.code_of(s, tn, false, m)))
				return out,
			func(ds: Array) -> Array:
				var why: Array = []
				for d in ds:
					why.append_array(G.check(d))
					if String(d.mode) != m:
						why.append("the game forgot its mode")
					for ri in G.ROUNDS:
						var rd: Dictionary = d.rounds[ri]
						tiers[m] = float(tiers[m]) + G.tier(String(rd.target))
						for a in rd.opts[1]:
							if String(a) != String(rd.target) and G.shape(String(a)) == G.shape(String(rd.target)):
								alike[m] = int(alike[m]) + 1
						if float(rd.time) < G.round_time(String(rd.type), m) - 0.01:
							why.append("round %d is shorter than its mode's" % (ri + 1))
				return why, Seeded.test_count(80), 3, [0, 999999], "PAINT MODE %s" % m)
		fails += (res.failures as Array).size()
	print("paint deep: picture tiers %s, look-alike shapes %s" % [str(tiers), str(alike)])
	_expect(float(tiers.gentle) <= float(tiers.brave) and float(tiers.brave) <= float(tiers.hard) and float(tiers.gentle) < float(tiers.hard),
		"pictures get trickier gentle -> brave -> hard")
	_expect(int(alike.gentle) <= int(alike.brave) and int(alike.brave) <= int(alike.hard) and int(alike.gentle) == 0,
		"answers look most different on gentle (never alike)")
	for t in G.ROUND_TIMES:
		_expect(G.round_time(t, "gentle") > G.round_time(t, "hard"), "%s rounds are longer on gentle" % t)
	for s in [0, 1, 4242, 999999]:
		for m in PickOrbs.MODE_IDS:
			for tn in range(G.BASE_THEMES, G.THEMES.size() + 1):
				for dy in [false, true]:
					var c := G.code_of(s, tn, dy, m)
					_expect(G.seed_of(c) == s and G.themes_of(c) == tn and G.daily_of(c) == dy and G.mode_of(c) == m,
						"code round-trips (%d, %d, %s, %s)" % [s, tn, dy, m])
	_expect(G.mode_of(77 * 100 + 7 * 2 + 1) == "brave", "an older code is a BRAVE game")
	_expect(G.code_of(5, 6, false) == 5 * 100 + 6 * 2, "a BRAVE game's code is the old code (the same game as before)")
	# A NEW ONE keeps the mode's rules.
	for m in PickOrbs.MODE_IDS:
		var d := G.build(G.code_of(31, G.THEMES.size(), false, m))
		var used: Array = []
		for ri in G.ROUNDS:
			used.append(String(d.rounds[ri].target))
			var nd := d.duplicate(true)
			nd.rounds[ri] = G.round_of(d, ri, used, 1)
			for why in G.check(nd):
				_fail("%s NEW ONE round %d: %s" % [m, ri + 1, why])


## TODAY'S GALLERY in every mode over 400+ dates: fair, and a lone painter finishes every round (Smudge guesses).
func _check_daily() -> void:
	var rd := Seeded.validate_days(func(date: String) -> Array:
			var out: Array = []
			for m in PickOrbs.MODE_IDS:
				out.append(G.build(G.code_at(77, 1, true, G.THEMES.size(), date, m)))
			return out,
		func(ds: Array) -> Array:
			var why: Array = []
			for d in ds:
				why.append_array(G.check(d))
				if not bool(d.daily) or int(d.themes) != G.BASE_THEMES:
					why.append("not a TODAY'S GALLERY with the starting themes")
				for r in d.rounds:
					var type := "paint" if String(r.type) == "team" else String(r.type)  # (alone, TEAM PAINT is painted)
					if Deep.smudge_right_at(type, String(d.mode), "") < 0.0:
						why.append("a lone painter can't finish a %s round in %s" % [type, d.mode])
			return why, 400, "TODAY'S GALLERY DEEP", ["2026-11-12", "2026-12-25", "2027-02-29"])
	fails += (rd.failures as Array).size()


## A painting a kid might make (canvas.gd export_strokes format): blobs and lines covering about `cover` of the canvas.
func _painting(seed_value: int, cover: float) -> Array:
	var r := Seeded.rng(seed_value, "painting")
	var strokes: Array = []
	var n := int(cover * 30.0)
	for k in n:
		var pts := PackedVector2Array()
		var c := Vector2(r.randf_range(-0.6, 0.6), r.randf_range(-0.42, 0.42))
		var dir := Vector2.RIGHT.rotated(r.randf() * TAU)
		var steps := r.randi_range(4, 70)
		for i in steps:
			dir = dir.rotated(r.randf_range(-0.5, 0.5))
			c = Vector2(clampf(c.x + dir.x * 0.012, -0.64, 0.64), clampf(c.y + dir.y * 0.012, -0.44, 0.44))
			pts.append(c)
		var col := r.randi_range(0, Canvas.COLORS.size() - 1)
		var w := (Artist.SPARKLE_W if col == Canvas.SPARKLE else Artist.BRUSH_W) * (Deep.BIG if k % 3 == 0 else 1.0)
		strokes.append([k + 1, col, w, pts, 0])
	return strokes


func _check_surprises() -> void:
	var worst := [0.0]
	var found := {"drip": 0, "wind": 0}
	var tried := [0]
	var res := Seeded.validate(func(s: int) -> Array:
			var out: Array = []
			for cover in [0.0, 0.3, 0.7, 1.4]:
				out.append(_painting(s, cover))
			return out,
		func(paintings: Array) -> Array:
			var why: Array = []
			for strokes in paintings:
				for m in PickOrbs.MODE_IDS:
					for kind in Deep.KINDS:
						for k in 2:
							tried[0] += 1
							var t1 := Time.get_ticks_usec()
							var e := Deep.spot(strokes, kind, m, 1000 + k, k, [Vector2(0.0, 0.0)])
							var ms := (Time.get_ticks_usec() - t1) / 1000.0
							worst[0] = TestTime.worst(worst[0], ms, func() -> Variant: return Deep.spot(strokes, kind, m, 1000 + k, k, [Vector2.ZERO]))
							if e.is_empty():
								continue
							found[kind] = int(found[kind]) + 1
							for w in Deep.problems(e, strokes, m):
								why.append("%s: %s" % [m, w])
							if Deep.inside(e, Vector2.ZERO, Deep.CURSOR_AWAY):
								why.append("a surprise right where a brush is")
							if var_to_str(e) != var_to_str(Deep.spot(strokes, kind, m, 1000 + k, k, [Vector2(0.0, 0.0)])):
								why.append("surprise spots not the same every time")
							if var_to_str(Deep.unpack(Deep.pack(e))) != var_to_str(e):
								why.append("a surprise changes over the network")
							# Somebody paints all over while it shows: the brush lifts at it, so it stays bare.
							var more: Array = (strokes as Array).duplicate()
							var pts := PackedVector2Array()
							var last := Vector2(-0.64, -0.44)
							var y := -0.44
							while y <= 0.44:
								var x := -0.64
								while x <= 0.64:
									var q := Vector2(x, y)
									var hw := Artist.SPARKLE_W * Deep.BIG * 0.5
									if not Deep.blocks(e, last if not pts.is_empty() else q, q, hw):
										pts.append(q)
										last = q
									elif pts.size() > 0:
										more.append([999, 1, hw * 2.0, pts, 0])
										pts = PackedVector2Array()
									x += 0.02
								y += 0.03
							if pts.size() > 0:
								more.append([998, 1, Artist.SPARKLE_W * Deep.BIG, pts, 0])
							if not Deep.bare(e, more):
								why.append("%s %s: paint got into a told surprise" % [m, kind])
			return why, Seeded.test_count(60), 3, [0, 1, 999999], "PAINT SURPRISES")
	fails += (res.failures as Array).size()
	print("paint deep: surprise spots found %s of %d tries, worst %.2f ms" % [str(found), tried[0], worst[0]])
	_expect(int(found.drip) > tried[0] / 6 and int(found.wind) > tried[0] / 6, "surprises find bare canvas on most paintings")
	_expect(worst[0] < 100.0, "a surprise spot is found and checked fast (%.1f ms)" % worst[0])
	# The validator catches unfair surprises.
	var blank: Array = []
	var e0 := Deep.spot(blank, "drip", "brave", 1, 0)
	_expect(not e0.is_empty() and Deep.problems(e0, blank, "brave").is_empty(), "a blank canvas has a fair drip")
	var over := [[1, 1, 0.022, PackedVector2Array([Vector2(float(e0.x), float(e0.y)), Vector2(float(e0.x) + 0.01, float(e0.y))]), 0]]
	_expect(not Deep.problems(e0, over, "brave").is_empty(), "a surprise over paint is caught")
	var short := e0.duplicate()
	short.warn = 0.5
	_expect(not Deep.problems(short, blank, "brave").is_empty(), "a surprise told too briefly is caught")
	var off := e0.duplicate()
	off.x = 0.64
	_expect(not Deep.problems(off, blank, "brave").is_empty(), "a surprise off the canvas is caught")
	var big := e0.duplicate()
	big.w = 0.3
	_expect(not Deep.problems(big, blank, "hard").is_empty(), "a surprise too big for its mode is caught")
	var full := _painting(7, 6.0)
	for kind in Deep.KINDS:
		var ef := Deep.spot(full, kind, "brave", 3, 0)
		_expect(ef.is_empty() or Deep.problems(ef, full, "brave").is_empty(), "a full canvas gets no unfair surprise")
	for k in Deep.KINDS:
		_expect(StoryCard.has_picture(String(Deep.KIND_PICS[k])) and String(Deep.KIND_NAMES[k]).length() <= 10, "surprise %s has a picture and a short name" % k)
	_expect(Contrast.score(Deep.DRIP_COLOR, Deep.WIND_COLOR) > 0.2, "drip and wind tells have distinct colours")


func _check_gifts() -> void:
	for gd in Deep.GIFTS:
		_expect(StoryCard.has_picture(String(gd.pic)), "gift %s has a picture" % gd.id)
		_expect(String(gd.name).length() <= 14, "gift %s has a short name" % gd.id)
		_expect(String(gd.line).length() <= 22, "gift %s has a short line" % gd.id)
	for n in [0, 1, 2, 3, 4, 9]:
		for last in ["", "bigbrush", "clock", "peek"]:
			for s in 20:
				var ch := Deep.gift_choices(n, last, s)
				var un := Deep.unlocked(n)
				_expect(ch.size() == 3, "three gifts")
				var seen := {}
				for id in ch:
					_expect(un.has(id) and not seen.has(id), "gift %s is unlocked and different (museum %d)" % [id, n])
					seen[id] = true
				_expect(ch.has(un[un.size() - 1]) or un[un.size() - 1] == last, "the newest gift is offered (museum %d)" % n)
				if un.size() > 3 and last != "":
					_expect(not ch.has(last), "not the last gift again (museum %d, %s)" % [n, last])
				_expect(var_to_str(ch) == var_to_str(Deep.gift_choices(n, last, s)), "gift choices are the same every time")
	_expect(Deep.unlocked(99).size() == Deep.GIFTS.size(), "every gift opens")
	_expect(Deep.brush_scale("bigbrush") > 1.0 and Deep.brush_scale("") == 1.0, "the big brush paints wider")
	# SLOW CLOCK only adds time; PEEK GLASS never crosses out the right answer.
	for m in PickOrbs.MODE_IDS:
		for t in G.ROUND_TIMES:
			for gid in ["", "bigbrush", "rainbow", "stamps", "clock", "peek"]:
				_expect(Deep.round_time(t, m, gid) >= G.round_time(t, m), "gift %s never shortens a round" % gid)
			_expect(Deep.round_time(t, m, "clock") > G.round_time(t, m), "the slow clock adds time")
	for s in Seeded.test_count(60, 20):
		var d := G.build(G.code_of(s * 7 + 1, G.THEMES.size(), false, PickOrbs.MODE_IDS[s % 3]))
		for ri in G.ROUNDS:
			var rd: Dictionary = d.rounds[ri]
			for seat in G.MAX_PLAYERS:
				var o: Array = rd.opts[seat]
				for mask in [0, 1, 2, 4, 8, 3, 5, 6, 9, 10, 12]:
					var i := Deep.peek_pick(o, String(rd.target), mask, s + seat)
					if i >= 0:
						_expect(String(o[i]) != String(rd.target), "the peek glass never crosses out the right answer")
						_expect((mask >> i) & 1 == 0, "the peek glass crosses out a new one")
	# STAMPS stay on the canvas.
	for k in 200:
		var p := Vector2(randf_range(-0.8, 0.8), randf_range(-0.6, 0.6))
		for q in Deep.stamp_points(p):
			_expect(absf(q.x) <= Canvas.W * 0.5 - 0.005 and absf(q.y) <= Canvas.H * 0.5 - 0.005, "a stamp stays on the canvas")


func _check_smudge() -> void:
	for m in PickOrbs.MODE_IDS:
		for t in G.ROUND_TIMES:
			if t == "team":
				continue
			for gid in ["", "peek", "clock"]:
				_expect(Deep.smudge_right_at(t, m, gid) >= 0.0, "Smudge guesses a %s round in time (%s, %s)" % [t, m, gid])
	_expect(Deep.smudge_right_at("speed", "gentle", "") <= Deep.smudge_right_at("speed", "hard", ""), "Smudge guesses soonest on gentle")
	_expect(Deep.smudge_right_at("paint", "brave", "peek") < Deep.smudge_right_at("paint", "brave", ""), "the peek glass helps Smudge")


func _check_seasons_museum() -> void:
	for s in Deep.SEASONS:
		var sd: Dictionary = Deep.SEASONS[s]
		_expect(StoryCard.has_picture(String(sd.pic)), "season %s has a picture" % s)
		_expect(String(sd.line).length() <= 22 and String(sd.name).length() <= 16, "season %s has a short line and name" % s)
	for mth in 12:
		_expect(Deep.SEASONS.has(Seeded.season("2026-%02d-15" % (mth + 1))), "month %d has a season" % (mth + 1))
	var kinds := {}
	for n in 40:
		var kd := Deep.treasure_kind(n)
		_expect(Deep.TREASURES.has(kd), "treasure %d is a known kind (%s)" % [n, kd])
		kinds[kd] = true
	for kd in Deep.TREASURES:
		_expect(kinds.has(kd), "every kind of treasure comes (%s)" % kd)
		_expect(StoryCard.has_picture(kd), "treasure %s has a picture" % kd)
		_expect(Deep.TREASURE_NAMES.has(kd), "treasure %s has a name" % kd)
	_expect(Deep.treasure_kind(9) == "catstatue", "a cat statue every tenth")
	_expect(Deep.PLINTH_H + Deep.TREASURE_H < 1.15, "treasures stay under the window and the shelves")
	for i in Deep.MUSEUM_SHOWN:
		var p := Deep.museum_spot(i)
		_expect(absf(p.x) > 3.4 and absf(p.x) < 3.9 and p.z > -2.2 and p.z < 4.2, "treasure %d stands by a side wall (%s)" % [i, str(p)])
		for j in range(i + 1, Deep.MUSEUM_SHOWN):
			_expect(p.distance_to(Deep.museum_spot(j)) > 0.5, "treasures %d and %d have room" % [i, j])
		for sp in Season.SPOTS:
			_expect(Vector2(p.x, p.z).distance_to(Vector2((sp as Vector3).x, (sp as Vector3).z)) > 0.8, "treasure %d is clear of the season props" % i)


func _check_rows() -> void:
	var cs := Deep.canvas_spots()
	for i in cs.size():
		var c: Vector3 = cs[i]
		_expect(c.z > 0.1 and absf(c.x) + PickOrbs.BALL_R * Deep.CANVAS_SCALE < Canvas.W * 0.5, "canvas orb %d floats in front of the canvas" % i)
		var u := Vector2(c.x, Deep.UNDER_Y)
		_expect(absf(u.x) + Deep.TV_R < Canvas.W * 0.5 + 0.01 and absf(u.y) + Deep.TV_R < Canvas.H * 0.5, "the spot under orb %d is on the canvas" % i)
		_expect(Deep.under(cs, u) == i, "a ring can rest under orb %d" % i)
		_expect(Deep.under(cs, Vector2(c.x, Deep.REST_Y)) < 0, "rings start under no orb (%d)" % i)
		_expect(c.y - PickOrbs.BALL_R * Deep.CANVAS_SCALE > u.y + 0.1, "orb %d floats above its spot" % i)
		for j in range(i + 1, cs.size()):
			_expect(absf((cs[j] as Vector3).x - c.x) > Deep.TV_R * 2.0 + 0.1, "canvas orbs %d and %d are apart" % [i, j])
	var head := Transform3D(Basis(), Vector3(0.0, 1.6, 1.5))
	var vr := Deep.vr_spots(head)
	var orb_m := PickOrbs.BALL_R * Deep.VR_SCALE
	for i in vr.size():
		var d: float = (vr[i] as Vector3).distance_to(head.origin)
		_expect(d > 0.3 and d < 0.62, "VR orb %d is an arm's reach away (%.2f m)" % [i, d])
		_expect((vr[i] as Vector3).z < head.origin.z, "VR orb %d is in front of the artist" % i)
		for j in range(i + 1, vr.size()):
			_expect((vr[i] as Vector3).distance_to(vr[j]) > 2.0 * (orb_m + Deep.HAND_R), "VR orbs %d and %d are apart" % [i, j])
	_expect((vr[0] as Vector3).x < (vr[2] as Vector3).x, "GENTLE is on the VR artist's left")
	_expect(orb_m > 0.05 and orb_m < 0.12, "VR orbs are a modest size (%.2f m)" % orb_m)
	_expect(Deep.DWELL >= 0.3 and Deep.TV_DWELL >= 0.8, "picks need a deliberate touch")


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: %s" % what)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)
