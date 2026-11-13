extends SceneTree
## BUBBLE BATH second pass (games/bubble_bath/deep.gd): proves the warned surprises are fair and the gifts, pond and
## pick row make sense (no game, no window).
##   godot-test --headless --path . -s res://tests/bubble_bath_deep_test.gd      (SEEDS=200 for more; GEN_QUICK=1: today's sample)
## Surprises: for many baths, every round 1-12 in every mode (a season per seed): Deep.problems() is empty (none on a
## session's first round or a round's first seconds, never two at once, told long enough for a small kid sailing
## slowly to get the whole boat out, inside the tub, never over the plug-hole or inside a sponge island, and a slow
## kid still reaches Mama Duck's goal losing time to every surprise), the same seed gives the same list, short bot
## rounds are fair too, TODAY'S BATH's surprises over 400+ days (Seeded.validate_days). The validator really catches
## unfair surprises. The mode table gets harder GENTLE -> HARD. Gifts: three different unlocked ones, the newest always
## offered, every gift / surprise / pond piece / season has a picture; the pond's pieces sit in its water or on its
## bank, clear of each other and the tub. The pick row: an arm's reach in front of the splasher, clear of the tap,
## and every orb reachable by a boat. Prints "BUBBLE BATH DEEP: PASS".

const Deep := preload("res://games/bubble_bath/deep.gd")
const G := preload("res://games/bubble_bath/bathgen.gd")
const Main := preload("res://games/bubble_bath/main.gd")
const Seeded := preload("res://core/seeded.gd")
const StoryCard := preload("res://core/story_card.gd")
const TestTime := preload("res://tests/test_time.gd")

var fails := 0


func _initialize() -> void:
	_expect(Deep.ordered().is_empty(), "modes get harder gentle -> hard (%s)" % str(Deep.ordered()))
	var seeds := Seeded.test_count(int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 40)
	var modes: Array = Deep.MODES.keys()
	var seasons: Array = Deep.SEASONS.keys()
	var kinds := {}
	var counts := {}
	var worst_ms := 0.0
	var res := Seeded.validate(func(s: int) -> Array:
			var season: String = seasons[posmod(s, seasons.size())]
			var all: Array = []
			for n in range(1, G.MAX_ROUND + 1):
				var p := G.plan(s, n)
				for md in modes:
					var spec := _spec(s, n, String(md), season, p)
					all.append([n, md, spec, Deep.hazards(p, spec)])
			return all,
		func(all: Array) -> Array:
			var why: Array = []
			for e in all:
				var n: int = e[0]
				var p := G.plan(int(e[2].seed_bath), n)
				for w in Deep.problems(p, e[3], e[2]):
					why.append("round %d %s: %s" % [n, e[1], w])
				for h in e[3]:
					kinds[String(h.kind)] = true
				counts[String(e[1])] = int(counts.get(String(e[1]), 0)) + (e[3] as Array).size()
			return why,
		seeds, 1, [0, 999999], "BATH SURPRISES")
	fails += (res.failures as Array).size()
	_expect(kinds.has("whale") and kinds.has("spray"), "both surprises come (%s)" % str(kinds.keys()))
	_expect(int(counts.get("hard", 0)) > int(counts.get("gentle", 0)), "hard has more surprises than gentle (%s)" % str(counts))
	# The worst case on a Deck: one round's surprises (incl. the slow kid's path) well under 100 ms.
	var p9 := G.plan(9, 7)
	var t0 := Time.get_ticks_usec()
	var list9 := Deep.hazards(p9, _spec(9, 7, "hard", "summer", p9))
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	worst_ms = TestTime.worst(worst_ms, ms, func() -> float:
		var t1 := Time.get_ticks_usec()
		Deep.hazards(p9, _spec(9, 7, "hard", "summer", p9))
		return float(Time.get_ticks_usec() - t1) / 1000.0)
	_expect(worst_ms < 40.0, "a round's surprises generate in under 40 ms here (%.1f ms; Decks ~3x slower)" % worst_ms)
	_expect(var_to_str(list9) == var_to_str(Deep.hazards(p9, _spec(9, 7, "hard", "summer", p9))), "the same seed gives the same surprises")
	# Short bot rounds (BB_SURPRISES_NOW: 16 s rounds, from 3 s).
	for s in 30:
		var p := G.plan(s + 1, 3)
		var spec := {"seed": s, "mode": "hard", "season": "summer", "round": Deep.FIRST_ROUND, "secs": 16.0, "first": Deep.SHORT_FIRST}
		var list := Deep.hazards(p, spec)
		_expect(not list.is_empty(), "a short bot round has a surprise (seed %d)" % s)
		for w in Deep.problems(p, list, spec):
			_expect(false, "short round seed %d: %s" % [s, w])
	# None on the session's first round.
	_expect(Deep.hazards(G.plan(5, 4), _spec(5, 1, "hard", "spring", G.plan(5, 4))).is_empty(), "no surprises on a session's first round")
	# TODAY'S BATH's surprises (rounds 2-4, the family's last mode can be any) over 400+ days.
	var rs := Seeded.validate_days(func(date: String) -> Array:
			var ds := G.daily_seed(date)
			var all: Array = []
			for n in range(2, 5):
				var p := G.plan(ds, n)
				for md in modes:
					var spec := _spec(ds, n, String(md), Seeded.season(date), p)
					all.append([n, spec, Deep.hazards(p, spec)])
			return all,
		func(all: Array) -> Array:
			var why: Array = []
			for e in all:
				for w in Deep.problems(G.plan(int(e[1].seed_bath), int(e[0])), e[2], e[1]):
					why.append("round %d %s: %s" % [int(e[0]), e[1].mode, w])
			return why, 400, "TODAY'S BATH SURPRISES", ["2026-11-13", "2026-12-25"])
	fails += (rs.failures as Array).size()
	# The validator really catches unfair surprises.
	var p := G.plan(9, 4)
	var spec := _spec(9, 4, "brave", "spring", p)
	var d: Vector2 = p.drain
	var on_plug := [{"t": 30.0, "kind": "whale", "x": d.x, "z": d.y, "dx": 0.0, "dz": 1.0, "warn": 2.9, "r": 1.0, "push": 1.0}]
	_expect(not Deep.problems(p, on_plug, spec).is_empty(), "Wally over the plug-hole is caught")
	var through := [{"t": 30.0, "kind": "spray", "x": -G.HX, "z": d.y, "dx": 1.0, "dz": 0.0, "warn": 2.9, "r": 0.5, "push": 1.0}]
	_expect(not Deep.problems(p, through, spec).is_empty(), "a shower through the plug-hole is caught")
	var quick := [{"t": 30.0, "kind": "whale", "x": 3.0, "z": 1.5, "dx": 0.0, "dz": 1.0, "warn": 1.0, "r": 1.0, "push": 1.0}]
	_expect(not Deep.problems(p, quick, spec).is_empty(), "a surprise told too briefly is caught")
	var early := [{"t": 2.0, "kind": "whale", "x": 3.0, "z": 1.4, "dx": 0.0, "dz": 1.0, "warn": 2.9, "r": 1.0, "push": 1.0}]
	_expect(not Deep.problems(p, early, spec).is_empty(), "a surprise in a round's first seconds is caught")
	var out := [{"t": 30.0, "kind": "whale", "x": 4.0, "z": 0.0, "dx": 0.0, "dz": 1.0, "warn": 2.9, "r": 1.0, "push": 1.0}]
	_expect(not Deep.problems(p, out, spec).is_empty(), "Wally poking out of the tub is caught")
	var both := [{"t": 30.0, "kind": "whale", "x": 3.0, "z": 1.4, "dx": 0.0, "dz": 1.0, "warn": 2.9, "r": 1.0, "push": 1.0},
		{"t": 31.0, "kind": "whale", "x": -3.0, "z": -1.4, "dx": 0.0, "dz": 1.0, "warn": 2.9, "r": 1.0, "push": 1.0}]
	_expect(not Deep.problems(p, both, spec).is_empty(), "two surprises at once are caught")
	var first_spec := spec.duplicate()
	first_spec.round = 1
	_expect(not Deep.problems(p, [both[0]], first_spec).is_empty(), "a surprise on the first round is caught")
	var many: Array = []
	for k in 12:
		many.append({"t": 15.0 + k * 8.0, "kind": "whale", "x": 3.0, "z": 1.4, "dx": 0.0, "dz": 1.0, "warn": 2.9, "r": 1.0, "push": 1.0})
	_expect(not Deep.problems(p, many, spec).is_empty(), "too many surprises for a slow kid's goal are caught")
	_expect(Deep.unpack(Deep.pack(both[0])) == both[0], "a surprise packs and unpacks (the \"hz\" state)")
	# Gifts.
	for pieces in range(0, Deep.POND.size() + 1):
		var un := Deep.unlocked(pieces)
		for s in 10:
			var g := Deep.gift_choices(pieces, "zoomy", s)
			var dd := {}
			for id in g:
				dd[id] = true
				_expect(un.has(id), "gift %s is unlocked at %d pieces" % [id, pieces])
			_expect(g.size() == 3 and dd.size() == 3, "three different gifts (%s)" % str(g))
			_expect(g.has(un[un.size() - 1]), "the newest gift is offered")
	_expect(Deep.unlocked(0).size() == 4 and Deep.unlocked(Deep.POND.size()).size() == Deep.GIFTS.size(), "gifts open as the pond grows")
	_expect(Deep.train_max("train", Main.MAX_TRAIN) > Main.MAX_TRAIN and Deep.drain_r("plug") > Main.DRAIN_R, "BIG TRAIN and BIG PLUG are bigger")
	_expect(Deep.ZOOM_MAX > Main.BOAT_MAX and Deep.ZOOM_ACCEL > Main.BOAT_ACCEL, "ZOOMY BOATS are faster")
	# The big plug never reaches a sponge island or the walls (boats still fit round it).
	for s in 30:
		for n in range(3, 8):
			var pl := G.plan(s + 7, n)
			var dr: Vector2 = pl.drain
			_expect(absf(dr.x) + Deep.BIG_PLUG_R + Deep.BOAT_R * 2.0 < G.HX and absf(dr.y) + Deep.BIG_PLUG_R + Deep.BOAT_R * 2.0 < G.HZ, "the big plug fits in the tub")
			for o in pl.islands:
				_expect(dr.distance_to(Vector2(o.x, o.y)) > float(o.z) + Deep.BIG_PLUG_R + Deep.BOAT_R, "the big plug stays clear of the islands")
	# Pictures.
	for gd in Deep.GIFTS:
		_expect(StoryCard.has_picture(String(gd.pic)), "gift %s has a picture" % gd.id)
		_expect(String(gd.name).length() <= 14, "gift name %s is short" % gd.name)
	for k in Deep.KINDS:
		_expect(StoryCard.has_picture(String(Deep.KIND_PICS[k])) and Deep.KIND_NAMES.has(k) and Deep.KIND_LINES.has(k), "surprise %s has a picture, a name and a line" % k)
	_expect(StoryCard.has_picture("wally"), "Wally has a picture")
	for s in Deep.SEASONS:
		_expect(StoryCard.has_picture(String(Deep.SEASONS[s].pic)), "season %s has a picture" % s)
		_expect((Deep.SEASONS[s].weights as Array).size() == Deep.KINDS.size(), "season %s weighs every surprise" % s)
	# The pond.
	_expect(Deep.POND_SPOTS.size() == Deep.POND.size(), "every pond piece has a place")
	for i in Deep.POND.size():
		var kind: String = Deep.POND[i]
		_expect(StoryCard.has_picture(kind) and Deep.POND_LINES.has(kind), "pond piece %s has a picture and a line" % kind)
		var at := Deep.pond_spot(i)
		var q := Vector2(at.x - Deep.POND_AT.x, at.z - Deep.POND_AT.z)
		var in_water := Vector2(q.x / Deep.POND_HALF.x, q.y / Deep.POND_HALF.y).length()
		if Deep.POND_IN.has(kind):
			_expect(in_water < 0.85, "pond piece %s floats in the water (%.2f)" % [kind, in_water])
		elif kind != "rainbow":
			_expect(in_water > 1.05, "pond piece %s stands on the bank (%.2f)" % [kind, in_water])
		_expect(at.z < -G.HZ - 1.0, "pond piece %s is clear of the tub" % kind)
		for j in i:
			_expect(Deep.pond_spot(j).distance_to(at) > 0.55, "pond pieces %s and %s don't overlap" % [Deep.POND[j], kind])
	_expect(Deep.pond(0) == 0 and Deep.pond(Deep.POND_EVERY) == 1 and Deep.pond(999) == Deep.POND.size(), "a pond piece every %d goals" % Deep.POND_EVERY)
	_expect(Deep.pond_spot(Deep.POND.size()) == Vector3.INF, "no pond spot past the end")
	# The pick row.
	var head := Vector3(0.0, 1.6, G.HZ + 0.35)  # the splasher's eyes on the bath mat (main.gd vr_rig.place)
	for o in Deep.row_spots(3, true):
		_expect(head.distance_to(o) < 1.0, "a VR orb is an arm's reach from the splasher (%.2f m)" % head.distance_to(o))
		_expect(Vector2(o.x - G.TAP.x, o.z - G.TAP.z).length() > 0.5, "a VR orb is clear of the tap")
		_expect(o.y > Main.RIM_Y + 0.1, "a VR orb floats over the rim")
		_expect(absf(o.x) < G.HX - G.BOAT_R and o.z - (G.HZ - G.BOAT_R) < Deep.TV_R * 0.7, "a boat can sail under VR orb %s" % str(o))
	for o in Deep.row_spots(3, false):
		_expect(absf(o.x) < G.HX - G.BOAT_R and absf(o.z) < G.HZ - G.BOAT_R, "a flat orb floats over open water")
	print("BUBBLE BATH DEEP: %s (%d fails, %d seeds, worst %.1f ms)" % ["PASS" if fails == 0 else "FAIL", fails, seeds, worst_ms])
	quit(1 if fails > 0 else 0)


## The surprise spec main.gd uses for round n of bath seed s (the slow kid's seconds for the mode's goal included).
static func _spec(s: int, n: int, md: String, season: String, p: Dictionary) -> Dictionary:
	var full := p.duplicate()
	full.goal = Deep.goal_for(p, md)
	return {"seed": Seeded.derive(s, "hz%d" % n), "seed_bath": s, "mode": md, "season": season, "round": n, "secs": G.ROUND_SECS,
		"kid": G.kid_seconds(full)}


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: BUBBLE BATH DEEP: " + what)