extends SceneTree
## COASTER CREW second pass validator (no game, no window): games/roller_coaster/deep.gd.
##   godot-test --headless --path . -s res://tests/roller_coaster_deep_test.gd      (SEEDS=60 for more)
## Proves, over many coasters grown plan by plan from the practice track (coastergen.gd), with Buttons' track gifts on
## them, for every mode, season and ride:
##   - the warned weather is fair (deep.gd problems(): never in the station, a loop, a splash or on a track gift, never two
##     touching, a sleepy stop only on a flat bit), told long enough before the train really gets there (a ride
##     simulated like main.gd _ride, boosters included), never on the practice ride, the same every time;
##   - GENTLE <= BRAVE <= HARD: the mode table (deep.gd mode_order_problems) AND what the rides really get (weather
##     stretches, gust metres, nap seconds), and a nap always ends by itself (nobody is ever stuck);
##   - Buttons' gifts: up to three different ones that fit this track, track gifts on the right pieces and never more
##     than MAX_EXTRAS, every picture drawn, short names, BIG STARS only once the toy fair has grown;
##   - the pick row: orbs far enough apart that a hand is never in two at once, within a small builder's arm's reach;
##   - the toy fair: every ride has a picture, stands on the floor clear of the table, the builder and the other rides;
##   - the seasons: a picture, a line, drifting things; every key colour stands out (core/contrast.gd, palette.gd);
##   - fast: a ride's weather in well under 100 ms (a Deck works it out when the lever is pulled).
## Prints "SCRIPT ERROR: ..." for each failure and "COASTER DEEP: PASS" / "FAIL".

const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/roller_coaster/deep.gd")
const G := preload("res://games/roller_coaster/coastergen.gd")
const Track := preload("res://games/roller_coaster/track.gd")
const Fair := preload("res://games/roller_coaster/fair.gd")
const Builder := preload("res://games/roller_coaster/builder.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const Seeded := preload("res://core/seeded.gd")
const TestTime := preload("res://tests/test_time.gd")

var fails := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 16
	for w in Deep.mode_order_problems():
		_fail("modes: " + str(w))
	for w in Contrast.check_game("roller_coaster"):
		_fail("contrast: " + str(w))
	var worst_ms := 0.0
	var per := {}
	for m in PickOrbs.MODE_IDS:
		per[m] = {"stretches": 0, "gust_m": 0.0, "nap": 0.0, "rides": 0, "sleepy": 0}
	var checked := 0
	var gifts_given := {}
	for k in seeds:
		var seed_value := 9100 + k * 7919
		for tr_info in _coasters(seed_value):
			var pieces: Array = tr_info[0]
			var tr: Dictionary = Track.build(pieces)
			var extras := _gifts(seed_value, pieces, gifts_given)
			var avoid := Deep.gift_ranges(tr, extras)
			for rg in avoid:
				if float(rg[0]) < Track.STATION_LEN - 0.01 or float(rg[1]) > float(tr.length) + 0.01 or float(rg[1]) <= float(rg[0]):
					_fail("a track gift outside the lap: %s (%.1f)" % [str(rg), float(tr.length)])
			for mode in PickOrbs.MODE_IDS:
				for season in Deep.SEASONS:
					for ride in range(1, 9):
						var t1 := Time.get_ticks_usec()
						var list := Deep.weather(seed_value, ride, tr, mode, season, avoid)
						var ms := (Time.get_ticks_usec() - t1) / 1000.0
						worst_ms = TestTime.worst(worst_ms, ms, func() -> void: Deep.weather(seed_value, ride, tr, mode, season, avoid))
						checked += 1
						if ride == 1 and not list.is_empty():
							_fail("weather on the practice ride")
						if str(list) != str(Deep.weather(seed_value, ride, tr, mode, season, avoid)):
							_fail("weather differs for the same seed")
						for why in Deep.problems(list, tr, mode, avoid):
							_fail("%s %s ride %d seed %d (%d pieces): %s" % [mode, season, ride, seed_value, pieces.size(), why])
						var lead := _lead_secs(tr, list, avoid)
						if lead < Deep.MIN_WARN:
							_fail("weather told only %.2f s before the train is there (%s ride %d seed %d)" % [lead, mode, ride, seed_value])
						var p: Dictionary = per[mode]
						p.rides += 1
						p.stretches += list.size()
						for e in list:
							if String(e.kind) == "gust":
								p.gust_m += float(e.s1) - float(e.s0)
							else:
								p.sleepy += 1
								p.nap += float(Deep.mode_of(mode).nap)
	print("weather per mode: %s" % str(per))
	print("gifts given: %s, checked %d rides" % [str(gifts_given), checked])
	var order := ["gentle", "brave", "hard"]
	for i in 2:
		var a: Dictionary = per[order[i]]
		var b: Dictionary = per[order[i + 1]]
		if a.stretches > b.stretches or a.gust_m > b.gust_m or a.nap > b.nap:
			_fail("the rides got harder in the wrong order: %s %s vs %s %s" % [order[i], str(a), order[i + 1], str(b)])
	for mode in order:
		_expect(int(per[mode].stretches) > 0, "%s rides get some weather" % mode)
		_expect(float(Deep.mode_of(mode).nap) <= 5.0, "a %s nap ends by itself soon (%.1f s)" % [mode, float(Deep.mode_of(mode).nap)])
	_expect(int(per.brave.sleepy) > 0 and int(per.hard.sleepy) > 0, "sleepy carts turn up in brave and hard")
	_expect(int(per.gentle.sleepy) == 0, "gentle has no sleepy carts")
	for g in ["booster", "corkscrew", "splash"]:
		_expect(int(gifts_given.get(g, 0)) > 0, "the %s gift found a spot on some coasters" % g)
	_expect(worst_ms < 40.0, "a ride's weather in well under 100 ms (worst %.2f ms)" % worst_ms)
	_gift_checks()
	_row_checks()
	_fair_checks()
	_season_checks()
	for n in ["corkscrew", "sleepycart", "teacup", "helter", "droptower", "airswirl", "gift", "bear"]:
		_expect(StoryCard.has_picture(n), "picture %s exists" % n)
	print("checked in %d ms" % (Time.get_ticks_msec() - t0))
	print("COASTER DEEP: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


## A few coasters (piece lists) grown plan by plan from the practice track, like the game does.
func _coasters(seed_value: int) -> Array:
	var out: Array = []
	var base := G.practice_base()
	for k in range(1, 8):
		var plan := G.section(Seeded.derive(seed_value, "p%d" % k), base, k)
		if bool(plan.full):
			break
		base = base + (plan.pieces as Array)
		if k == 1 or k == 3 or k >= 5:
			out.append([base.duplicate(true)])
	return out


## Buttons' gifts as the game gives them, ride after ride: the offer, the middle one taken.
func _gifts(seed_value: int, pieces: Array, given: Dictionary) -> Array:
	var extras: Array = []
	for ride in range(Deep.FIRST_GIFT_RIDE, 12):
		var fair := Deep.fair_count(ride)
		var opts := Deep.offer(seed_value, ride, pieces, extras, fair)
		if opts.size() > 3:
			_fail("more than three gifts offered")
		var seen := {}
		for id in opts:
			if seen.has(id):
				_fail("a gift offered twice: %s" % str(opts))
			seen[id] = true
			var g := Deep.gift(String(id))
			if g.is_empty() or int(g.unlock) > fair:
				_fail("gift %s offered before the fair opened it" % id)
		if opts.is_empty():
			continue
		var kind := String(opts[opts.size() / 2])
		if bool(Deep.gift(kind).piece):
			var at := Deep.gift_spot(pieces, extras, kind)
			if at < 3 or at >= pieces.size():
				_fail("track gift %s offered with no spot (%d)" % [kind, at])
				continue
			if not (Deep.GIFT_ON[kind] as Array).has(String((pieces[at] as Array)[0])):
				_fail("track gift %s on a %s" % [kind, String((pieces[at] as Array)[0])])
			extras.append([at, kind])
		given[kind] = int(given.get(kind, 0)) + 1
	if extras.size() > Deep.MAX_EXTRAS:
		_fail("too many track gifts (%d)" % extras.size())
	return extras


## Seconds from the lever until the train's front reaches the first weather stretch (main.gd _ride physics).
func _lead_secs(tr: Dictionary, list: Array, gifts: Array) -> float:
	if list.is_empty():
		return INF
	var first := INF
	for e in list:
		first = minf(first, float(e.s0))
	var s := Track.STATION_LEN - 0.4
	var v := 5.0
	var energy := 0.5 * v * v + G.G * Track.STATION_Y
	var t := 0.0
	var dt := 1.0 / 30.0
	while s < first and t < 60.0:
		var xf := Track.sample(tr, s - G.GAP)
		var y := xf.origin.y
		v = sqrt(maxf(0.0, 2.0 * (energy - G.G * y)))
		if -xf.basis.z.y > 0.08 and v < G.LIFT_V:
			v = G.LIFT_V
		v = clampf(v, G.VMIN, G.VMAX)
		for rg in gifts:
			if String(rg[2]) == "booster" and s >= float(rg[0]) and s <= float(rg[1]):
				v = maxf(v, Deep.BOOST_V)
		energy = 0.5 * v * v + G.G * y - G.FRICTION * dt
		s += v * dt
		t += dt
	return t


func _gift_checks() -> void:
	for g in Deep.GIFTS:
		_expect(StoryCard.has_picture(String(g.pic)), "gift %s has a picture (%s)" % [g.id, g.pic])
		_expect(String(g.name).length() <= 10, "gift name %s is short" % g.name)
		_expect(String(g.line).length() <= 16, "gift line %s is short" % g.line)
		if bool(g.piece):
			_expect(Deep.GIFT_ON.has(String(g.id)), "track gift %s says which pieces it goes on" % g.id)
	_expect(Deep.BOOST_V <= G.VMAX and Deep.BOOST_V > 8.0, "the booster is fast but within the coaster's top speed")
	_expect(Deep.BIG_REACH > 1.1, "big stars reach further than plain ones")


## The pick row: a hand never in two orbs at once; every orb within a small builder's reach.
func _row_checks() -> void:
	var row := Deep.row(3)
	var hit := PickOrbs.HIT_R * Deep.ORB_SCALE + Deep.HAND_R
	for i in 2:
		var d := (row[i] as Vector3).distance_to(row[i + 1])
		_expect(d > 2.0 * hit, "pick orbs %d and %d far enough apart for one hand (%.2f > %.2f)" % [i, i + 1, d, 2.0 * hit])
	var feet := Vector3(0.0, -Builder.TABLE_H * Builder.WS, Track.TABLE_R + 0.15 * Builder.WS)
	var head := feet + Vector3(0.0, 1.15 * Builder.WS, 0.0)  # a small builder (eyes 1.15 m up)
	for p in row:
		var d := (p as Vector3).distance_to(head) / Builder.WS
		_expect(d <= 0.62, "pick orb within a small builder's reach (%.2f m)" % d)
		_expect((p as Vector3).y > Track.MAX_Y * 0.5, "pick orb floats above the track (y %.1f)" % (p as Vector3).y)
	_expect(Deep.ORB_SCALE / Builder.WS <= 0.16, "pick orbs are modest (%.2f m)" % (Deep.ORB_SCALE / Builder.WS))


func _fair_checks() -> void:
	var feet := Vector3(0.0, 0.0, Track.TABLE_R + 0.15 * Builder.WS)
	for i in Deep.FAIR.size():
		var kind: String = Deep.FAIR[i]
		_expect(StoryCard.has_picture(String(Deep.FAIR_PICS.get(kind, ""))), "fair ride %s has a picture" % kind)
		var p := Fair.spot(i)
		var flat := Vector2(p.x, p.z)
		_expect(flat.length() > Track.TABLE_R + 5.0, "fair ride %s stands clear of the table" % kind)
		_expect(flat.distance_to(Vector2(feet.x, feet.z)) > 9.0, "fair ride %s clear of the builder's feet" % kind)
		for j in i:
			var q := Fair.spot(j)
			_expect(flat.distance_to(Vector2(q.x, q.z)) > 9.0, "fair rides %d and %d apart" % [i, j])
	_expect(Deep.fair_count(0) == 0 and Deep.fair_count(Deep.FAIR_EVERY) == 1 and Deep.fair_count(9999) == Deep.FAIR.size(), "the fair grows ride by ride and stops when full")


func _season_checks() -> void:
	for s in ["spring", "summer", "autumn", "winter"]:
		var d := Deep.season_data(s)
		_expect(Deep.SEASONS.has(s), "season %s" % s)
		_expect(StoryCard.has_picture(String(d.pic)), "season %s picture" % s)
		_expect(String(d.line).length() <= 16, "season %s line short" % s)
		_expect(d.has("drift") and d.has("grass"), "season %s drifts and tints the grass" % s)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: " + what)
