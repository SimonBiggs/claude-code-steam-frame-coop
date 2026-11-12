extends SceneTree
## TINY TOWN TYCOON second pass validator (no game, no window): games/tiny_town_tycoon/deep.gd.
##   godot-test --headless --path . -s res://tests/tiny_town_tycoon_deep_test.gd      (SEEDS=200 for more; GEN_QUICK=1 samples)
## Proves, over many seeded islands (every mode, every season, every gift):
##   - GENTLE <= BRAVE <= HARD: the mode table (deep.gd ordered()) AND what the days really get (weathers a day, warning
##     seconds, sizes, seconds a vehicle loses);
##   - Benny's weather is fair (deep.gd problems(): never early in a day, never two at once, over before the day ends,
##     told long enough for the slowest vehicle in its middle to drive out over land round the water and rocks, never
##     over the sea or most of the island, hit by every weather a vehicle still drives most of the day) with every gift
##     (a gift only helps), the same every time and unchanged over the network (pack); the bots' quick weather too;
##   - TODAY'S ISLAND over 400+ dates, every mode: its weather fair;
##   - the builder gifts: three different unlocked ones, the newest among them, not the last again when there are
##     others, every picture drawn, short names; every gift helps; the twin house and the happy park find a spot;
##   - the seasons: each has a picture, a line and both weathers; the season props stand outside the VR mayor's
##     walking square;
##   - the islets only grow, all come, sit on the sea between the island and the table's edge, apart, away from the
##     mayor's side and the windmill toy;
##   - the pick rows: the island orbs over road cells by the town hall a vehicle can drive under (every island), apart;
##     the VR orbs an arm's reach in front of the mayor (standing and seated), small, apart, under the eyes;
##   - the validator catches unfair weather; constants match vehicle.gd; every key colour stands out (palette.gd);
##   - fast: a day's weather is made and checked well under 100 ms.
## Prints "SCRIPT ERROR: ..." for each failure and "TINY TOWN DEEP: PASS" / "FAIL".

const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/tiny_town_tycoon/deep.gd")
const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const IslandGen := preload("res://games/tiny_town_tycoon/islandgen.gd")
const Wishes := preload("res://games/tiny_town_tycoon/wishes.gd")
const Town := preload("res://games/tiny_town_tycoon/town.gd")
const Season := preload("res://games/tiny_town_tycoon/season.gd")
const Props := preload("res://games/tiny_town_tycoon/props.gd")
const Vehicle := preload("res://games/tiny_town_tycoon/vehicle.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const Seeded := preload("res://core/seeded.gd")
const TestTime := preload("res://tests/test_time.gd")

var fails := 0


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	for w in Deep.ordered():
		_fail("modes: " + str(w))
	for w in Contrast.check_game("tiny_town_tycoon"):
		_fail("contrast: " + str(w))
	_expect(is_equal_approx(Deep.MAX_SPEED, Vehicle.MAX_SPEED), "deep.gd MAX_SPEED matches vehicle.gd")
	var probe := Town.new()
	probe.apply_island(IslandGen.generate(5))
	var slow := 9.0
	for z in Defs.GRID:
		for x in Defs.GRID:
			slow = minf(slow, probe.speed_at(Defs.cell_center(x, z)))
	_expect(Deep.SLOWEST <= Vehicle.MAX_SPEED * slow + 0.0001, "deep.gd SLOWEST is the slowest a vehicle drives (%.3f)" % slow)
	_weather()
	_daily()
	_gifts()
	_seasons()
	_islets()
	_rows()
	_broken()
	print("tiny town deep: %d ms" % (Time.get_ticks_msec() - t0))
	print("TINY TOWN DEEP: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


# --- Weather over many islands -----------------------------------------------------------------------------------

func _weather() -> void:
	var worst_ms := [0.0]
	var sums := {}
	for m in PickOrbs.MODE_IDS:
		sums[m] = {"n": 0, "count": 0, "warn": 0.0, "size": 0.0, "lost": 0.0}
	var seasons: Array = Deep.SEASONS.keys()
	var gifts: Array = [""]
	for g in Deep.GIFTS:
		gifts.append(String(g.id))
	var res := Seeded.validate(func(s: int) -> Dictionary: return IslandGen.generate(s),
		func(isl: Dictionary) -> Array:
			var why: Array = []
			var season: String = seasons[absi(int(isl.seed)) % 4]
			for m in PickOrbs.MODE_IDS:
				for spec in [{"seed": int(isl.seed) + 1, "mode": m, "season": season, "day": 0, "len": 400.0},
						{"seed": int(isl.seed) + 2, "mode": m, "season": season, "day": 3, "len": 420.0},
						{"seed": int(isl.seed) + 3, "mode": m, "season": season, "day": 1, "len": 130.0},
						{"seed": int(isl.seed) + 4, "mode": m, "season": season, "day": 0, "len": 90.0, "first": Deep.SHORT_FIRST, "gap": Deep.SHORT_GAP}]:
					var t1 := Time.get_ticks_usec()
					var list := Deep.weather(isl, spec)
					var probs := Deep.problems(isl, list, spec)
					worst_ms[0] = TestTime.worst(worst_ms[0], (Time.get_ticks_usec() - t1) / 1000.0, func() -> Variant:
						return Deep.problems(isl, Deep.weather(isl, spec), spec))
					for w in probs:
						why.append("%s (%s): %s" % [m, str(spec), w])
					for g in gifts:
						var gs: Dictionary = spec.duplicate()
						gs["gift"] = g
						for w in Deep.problems(isl, list, gs):
							why.append("%s with %s: %s" % [m, g, w])
					if var_to_str(list) != var_to_str(Deep.weather(isl, spec)):
						why.append("%s: weather not deterministic" % m)
					for e in list:
						if var_to_str(Deep.unpack(Deep.pack(e))) != var_to_str(e):
							why.append("weather changes over the network: %s" % str(e))
					if float(spec.len) >= 420.0:
						var sm: Dictionary = sums[m]
						sm.n += 1
						sm.count += list.size()
						var fx := Deep.effect(m, "")
						for e in list:
							sm.warn += float(e.warn)
							sm.size += float(e.w)
							sm.lost += float(fx.stall) if String(e.kind) == "gust" else float(e.after) * (1.0 - float(fx.slow))
			return why,
		Seeded.test_count(60), 1, [], "TOWN WEATHER")
	if not bool(res.ok):
		fails += 1
	var avg := func(m: String, k: String) -> float:
		return float((sums[m] as Dictionary)[k]) / maxf(1.0, float((sums[m] as Dictionary).n))
	var per := func(m: String, k: String) -> float:
		return float((sums[m] as Dictionary)[k]) / maxf(1.0, float((sums[m] as Dictionary).count))
	for k in ["count", "lost"]:
		_expect(avg.call("gentle", k) <= avg.call("brave", k) + 0.001 and avg.call("brave", k) <= avg.call("hard", k) + 0.001,
			"days: %s gentle %.2f <= brave %.2f <= hard %.2f" % [k, avg.call("gentle", k), avg.call("brave", k), avg.call("hard", k)])
	_expect(per.call("gentle", "warn") >= per.call("brave", "warn") and per.call("brave", "warn") >= per.call("hard", "warn"), "weather is told longest on gentle")
	_expect(per.call("gentle", "size") <= per.call("hard", "size"), "hard weather is bigger than gentle")
	_expect(avg.call("gentle", "count") >= 1.0, "even gentle days have weather (%.1f)" % avg.call("gentle", "count"))
	_expect(avg.call("gentle", "count") < avg.call("hard", "count"), "hard has more weather than gentle")
	_expect(worst_ms[0] < 100.0, "a day's weather is made and checked fast (%.1f ms)" % worst_ms[0])
	print("weather: gentle %.1f / brave %.1f / hard %.1f a day, worst %.1f ms" % [avg.call("gentle", "count"), avg.call("brave", "count"),
		avg.call("hard", "count"), worst_ms[0]])


## TODAY'S ISLAND over 400+ dates: its weather in every mode, that date's season, a first day and a later one.
func _daily() -> void:
	var days := Seeded.validate_days(func(date: String) -> Dictionary:
			var isl := IslandGen.generate(Wishes.today_seed(date))
			var lists := {}
			for m in PickOrbs.MODE_IDS:
				for d in [0, 2]:
					var spec := {"seed": Seeded.derive(int(isl.seed), "day %d" % d), "mode": m, "season": Seeded.season(date), "day": d, "len": 420.0}
					lists["%s %d" % [m, d]] = [spec, Deep.weather(isl, spec)]
			return {"isl": isl, "lists": lists},
		func(day: Dictionary) -> Array:
			var why: Array = []
			for k in day.lists:
				var sl: Array = day.lists[k]
				for w in Deep.problems(day.isl, sl[1], sl[0]):
					why.append("%s: %s" % [k, w])
			return why, 400, "TODAY'S ISLAND WEATHER", ["2026-11-12", "2026-11-13"])
	if not bool(days.ok):
		fails += 1
	print("TODAY'S ISLAND weather: %d dates" % int(days.checked))


# --- Gifts --------------------------------------------------------------------------------------------------------

func _gifts() -> void:
	var ids := {}
	for g in Deep.GIFTS:
		ids[String(g.id)] = true
		_expect(StoryCard.has_picture(String(g.pic)), "gift %s has a picture (%s)" % [g.id, g.pic])
		_expect(String(g.name).length() <= 14 and String(g.name).split(" ").size() <= 2, "gift name %s is short" % g.name)
		_expect(String(g.line).length() <= 16, "gift line %s is short" % g.line)
		for m in PickOrbs.MODE_IDS:
			var fx := Deep.effect(m, String(g.id))
			var md := Deep.mode_data(m)
			_expect(float(fx.stall) <= float(md.stall) and float(fx.slow) >= float(md.fog_slow), "%s never makes %s weather worse" % [g.id, m])
		_expect(Deep.gift_speed(String(g.id)) >= 1.0, "%s never slows a vehicle" % g.id)
	_expect(ids.size() == Deep.GIFTS.size(), "gift ids are different")
	_expect(Deep.unlocked(0).size() >= 3, "three gifts from the start")
	_expect(Deep.unlocked(Deep.ISLETS.size()).size() == Deep.GIFTS.size(), "every gift opens as the archipelago grows")
	_expect(Deep.CRANE_BUILD < 2.5 and Deep.CRANE_CARRY > 1, "SPEEDY CRANE helps (sim.gd builds in 2.5 s, one brick a load)")
	_expect(Deep.PARK_MOVE > 1.0 and Deep.ZOOMY > 1.0, "HAPPY PARK and ZOOMY WHEELS help")
	_expect(Deep.effect("hard", "sunny").stall == Deep.MODES.gentle.stall, "SUNNY DAY makes the weather gentle")
	for n in Deep.ISLETS.size() + 1:
		var un := Deep.unlocked(n)
		for last in [""] + un:
			for s in 12:
				var ch := Deep.gift_choices(n, String(last), 1000 + s * 77)
				var seen := {}
				for c in ch:
					seen[String(c)] = true
					_expect(un.has(c), "offered gift %s is unlocked at %d islets" % [c, n])
				_expect(ch.size() == 3 and seen.size() == 3, "three different gifts (%s)" % str(ch))
				if un.size() > 3:
					_expect(not ch.has(last), "not %s again when there are others" % last)
				if String(last) != String(un[un.size() - 1]):
					_expect(ch.has(un[un.size() - 1]), "the newest gift %s is offered" % un[un.size() - 1])
	# The twin house and the happy park find spots on a fresh town (the starter street).
	for s in Seeded.test_count(40):
		var town := Town.new()
		town.apply_island(IslandGen.generate(500 + s * 13))
		town.starter_town()
		var p := Deep.park_spot(town)
		_expect(p.x >= 0 and town.can_place("park", p.x, p.y) == "" and town.on_road({"kind": "park", "x": p.x, "z": p.y}),
			"island %d: HAPPY PARK finds a spot by the hall" % s)
		var hs := Deep.park_spot(town)  # a house where the park would go, then its twin
		var tw := Deep.twin_spot(town, hs.x, hs.y)
		if hs.x >= 0:
			town.add_building("house", hs.x, hs.y, 0, 0)
			tw = Deep.twin_spot(town, hs.x, hs.y)
			_expect(tw.x >= 0 and town.can_place("house", tw.x, tw.y) == "", "island %d: DOUBLE HOUSES finds a twin spot" % s)


# --- Seasons, islets ----------------------------------------------------------------------------------------------

func _seasons() -> void:
	for s in Deep.SEASONS:
		var sd := Deep.season_data(String(s))
		_expect(StoryCard.has_picture(String(sd.pic)), "season %s has a picture" % s)
		_expect(String(sd.line).length() <= 16 and (sd.weights as Array).size() == Deep.KINDS.size(), "season %s: a short line, every weather" % s)
		for w in sd.weights:
			_expect(float(w) > 0.0, "season %s has every weather" % s)
	for k in Deep.KINDS:
		_expect(StoryCard.has_picture(String(Deep.KIND_PICS[k])), "weather %s has a picture" % k)
	for date in Seeded.dates(30):
		_expect(Deep.SEASONS.has(Seeded.season(String(date))), "every date has a season (%s)" % date)
	for p in Season.spots():
		var v: Vector3 = p
		_expect(maxf(absf(v.x), absf(v.z)) >= 2.05, "a season prop stands outside the VR mayor's walking square (%s)" % str(v))


func _islets() -> void:
	var last := 0
	for n in 60:
		var k := Deep.islets(n)
		_expect(k >= last, "islets only grow")
		last = k
	_expect(last == Deep.ISLETS.size(), "every islet comes (%d)" % last)
	_expect(Deep.ISLET_ANGLES.size() >= Deep.ISLETS.size(), "every islet has a place")
	for i in Deep.ISLETS.size():
		var il: Dictionary = Deep.ISLETS[i]
		_expect(StoryCard.has_picture(String(il.pic)), "islet %s has a picture" % il.id)
		var p := Deep.islet_spot(i)
		var r := Deep.ISLET_R
		_expect(maxf(absf(p.x), absf(p.z)) - r >= Defs.HALF + 0.01, "islet %s is off the island's edge" % il.id)
		_expect(Vector2(p.x, p.z).length() + r <= 0.89, "islet %s is on the table's cloth" % il.id)
		_expect(absf(p.x) + r <= 0.86 and absf(p.z) + r <= 0.86, "islet %s is on the sea" % il.id)
		_expect(p.z < 0.3, "islet %s is away from the mayor's side" % il.id)
		_expect(Vector2(p.x - Props.WINDMILL_AT.x, p.z - Props.WINDMILL_AT.z).length() > r + 0.08, "islet %s is clear of the windmill toy" % il.id)
		for j in i:
			_expect(Deep.islet_spot(j).distance_to(p) > 2.0 * r + 0.02, "islets %d and %d are apart" % [i, j])


# --- Pick rows ----------------------------------------------------------------------------------------------------

func _rows() -> void:
	for s in Seeded.test_count(60):
		var town := Town.new()
		town.apply_island(IslandGen.generate(900 + s * 31))
		town.starter_town()
		var cells := Deep.row_cells(town)
		_expect(cells.size() == 3, "island %d: three orb spots" % s)
		for i in cells.size():
			var c: Vector2i = cells[i]
			_expect(town._drivable(c.x, c.y) and town.has_road(c.x, c.y), "island %d: an orb over a road a vehicle drives on" % s)
			for j in i:
				var o: Vector2i = cells[j]
				_expect(absi(o.x - c.x) + absi(o.y - c.y) >= Deep.ROW_GAP, "island %d: orbs apart" % s)
		var spots := Deep.row_spots(town)
		for i in spots.size():
			_expect(Deep.under(spots, Vector3(spots[i].x, Defs.GROUND_Y, spots[i].z)) == i, "a vehicle right under orb %d picks it" % i)
	var r := PickOrbs.BALL_R * Deep.ORB_SCALE
	_expect(r > Defs.CELL * 0.3 and r < Defs.CELL, "island orbs: bigger than a toy vehicle, smaller than a house (%.3f m)" % r)
	_expect(Deep.ORB_Y - r > 0.03, "island orbs float over the toy vehicles and houses")
	for eye in [1.6, 1.15]:
		var head := Transform3D(Basis(), Vector3(0.0, eye, 1.05))
		var vs := Deep.vr_spots(head)
		for i in vs.size():
			var p: Vector3 = vs[i]
			var d := p.distance_to(head.origin)
			_expect(d > 0.35 and d < 0.65, "VR orb %d is an arm's reach away (%.2f m, eye %.2f)" % [i, d, eye])
			_expect(p.y < eye and p.y > Defs.GROUND_Y + 0.12, "VR orb %d is under the eyes, over the town (eye %.2f)" % [i, eye])
			for j in i:
				_expect(p.distance_to(vs[j]) > 2.0 * PickOrbs.BALL_R * Deep.VR_SCALE + 0.05, "VR orbs apart")
		_expect(vs[0].x < vs[2].x, "VR orbs left to right (GENTLE on the left)")
	_expect(PickOrbs.BALL_R * Deep.VR_SCALE < 0.08, "VR orbs are modest")


# --- The validator catches unfair weather ---------------------------------------------------------------------------

func _broken() -> void:
	var isl := IslandGen.generate(42)
	var spec := {"seed": 7, "mode": "brave", "season": "spring", "day": 2, "len": 420.0}
	var good := Deep.weather(isl, spec)
	_expect(not good.is_empty() and Deep.problems(isl, good, spec).is_empty(), "a fair day passes")
	if good.is_empty():
		return
	var e: Dictionary = (good[0] as Dictionary).duplicate()
	var short := e.duplicate()
	short.warn = 1.0
	_expect(not Deep.problems(isl, [short], spec).is_empty(), "weather told for 1 s is caught")
	var early := e.duplicate()
	early.t = 2.0
	_expect(not Deep.problems(isl, [early], spec).is_empty(), "weather at a day's start is caught")
	var e2 := e.duplicate()
	e2.t = float(e.t) + 5.0
	_expect(not Deep.problems(isl, [e, e2], spec).is_empty(), "two weathers at once are caught")
	var sea := {"t": 60.0, "kind": "fog", "x": Defs.HALF - 0.01, "z": Defs.HALF - 0.01, "w": 0.04, "warn": 4.4, "after": 10.0}
	_expect(not Deep.problems(isl, [sea], spec).is_empty(), "fog out at sea is caught")
	var huge := {"t": 60.0, "kind": "fog", "x": 0.0, "z": 0.0, "w": 0.4, "warn": 4.4, "after": 10.0}
	_expect(not Deep.problems(isl, [huge], spec).is_empty(), "fog over the whole island is caught")
	var late := e.duplicate()
	late.t = 418.0
	_expect(not Deep.problems(isl, [late], spec).is_empty(), "weather past the day's end is caught")


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: TINY TOWN DEEP: %s" % what)
