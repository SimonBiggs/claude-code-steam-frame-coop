extends SceneTree
## GHOST LANTERN houses: proves the seeded haunted houses are fair over many seeds (no game, no window).
##   godot-test --headless --path . -s res://tests/ghost_lantern_gen_test.gd      (SEEDS=500 for more)
## For every level: games/ghost_lantern/housegen.gd check() (every hiding place inside its room, off the
## furniture / doorways / start corner, every floor cell still reachable from the start, every hiding
## place reachable on foot and in the lantern's sight from somewhere reachable, every night plan fair for
## crews of 1..7: each hiding ghost in its own hiding place, everyone comes out by themselves in time,
## everyone catchable alone and with vacuums, more hunters never fewer ghosts, a gentle night 1), the
## same seed gives the same house, TODAY'S HOUSE is the same all day, Granny Boo's jar shelf fills,
## and the check catches broken houses. Fast: a Deck checks a house in well under 100 ms.

const HouseGen := preload("res://games/ghost_lantern/housegen.gd")
const Museum := preload("res://games/ghost_lantern/museum.gd")
const Seeded := preload("res://core/seeded.gd")

var fails := 0


func _initialize() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 40
	var total := 0
	var t0 := Time.get_ticks_usec()
	var gens := 0
	for level in 4:
		var r := Seeded.validate(func(s: int) -> Dictionary: return HouseGen.generate(s, {"level": level}),
			HouseGen.check, seeds / 4 + 2, 17 + level, [0, 999999], "HOUSE l%d" % level)
		total += int(r.checked)
		gens += int(r.checked)
		fails += (r.failures as Array).size()
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, gens)
	print("house gen: %.2f ms per house generated twice + checked (%d houses)" % [per_ms, gens])
	_expect(per_ms < 20.0, "a house generates and checks in under 20 ms here (%.2f ms)" % per_ms)
	# Quick: generating one house (what the game does at the start) is fast.
	var t1 := Time.get_ticks_usec()
	for s in 20:
		HouseGen.generate(500 + s, {"level": 3})
	var gen_ms := float(Time.get_ticks_usec() - t1) / 1000.0 / 20.0
	print("house gen: %.2f ms to generate a house" % gen_ms)
	_expect(gen_ms < 8.0, "a house generates in under 8 ms (%.2f)" % gen_ms)
	# Variety: every hiding place kind and every room turns up, houses differ.
	var kinds := {}
	var shapes := {}
	for s in 60:
		var h := HouseGen.generate(1000 + s, {"level": 1 + s % 5})
		var key := []
		for sp in h.spots:
			kinds[sp.kind] = true
			key.append([sp.kind, sp.pos])
		shapes[var_to_str(key)] = true
	_expect(kinds.size() == HouseGen.KINDS.size(), "every hiding place turns up (%s)" % str(kinds.keys()))
	_expect(shapes.size() >= 58, "houses differ (%d of 60)" % shapes.size())
	_expect((HouseGen.generate(3, {"level": 0}).spots as Array).size() - HouseGen.FIXED_SPOTS.size() == 3, "the first house has 3 hiding places")
	_expect((HouseGen.generate(3, {"level": 5}).spots as Array).size() - HouseGen.FIXED_SPOTS.size() == 6, "a later house has 6")
	# TODAY'S HOUSE: the same all day whatever the family's level, and different from day to day.
	var days := {}
	for d in 30:
		var date := Time.get_date_string_from_unix_time(1790000000 + d * 86400)
		var sd := Seeded.daily_seed("ghost_lantern", date)
		var a := HouseGen.generate(sd, {"level": 0, "daily": true})
		var b := HouseGen.generate(sd, {"level": 7, "daily": true})
		_expect(var_to_str(a) == var_to_str(b), "daily %s: the same house for everyone" % date)
		for w in HouseGen.check(a):
			_fail("daily %s: %s" % [date, w])
		days[var_to_str(a.spots)] = true
	_expect(days.size() >= 29, "daily houses differ (%d of 30)" % days.size())
	# Night plans: one new thing each night, the king on 5 and 10, crews.
	var h0 := HouseGen.generate(42, {"level": 2})
	var n1 := HouseGen.night_plan(h0, 1, 2)
	_expect(n1.size() == 3 and n1.filter(func(g: Dictionary) -> bool: return g.kind == "snoozy").size() == 1, "night 1: two plain ghosts and one snoozy")
	_expect(HouseGen.night_plan(h0, 2, 2).any(func(g: Dictionary) -> bool: return g.kind == "sprite"), "night 2 brings Zip")
	_expect(HouseGen.night_plan(h0, 3, 2).any(func(g: Dictionary) -> bool: return g.kind == "spooker"), "night 3 brings Peekaboo")
	_expect(HouseGen.night_plan(h0, 4, 2).any(func(g: Dictionary) -> bool: return g.kind == "golden"), "night 4 brings Goldie")
	_expect(HouseGen.king_night(5) and HouseGen.king_night(10) and not HouseGen.king_night(6), "the king visits on night 5 and 10")
	_expect(HouseGen.night_plan(h0, 6, 7).size() > HouseGen.night_plan(h0, 6, 2).size(), "a big crew gets more ghosts")
	var hidden1 := HouseGen.night_plan(h0, 1, 2).filter(func(g: Dictionary) -> bool: return g.hide >= 0)
	_expect(not hidden1.is_empty() and String(h0.spots[hidden1[0].hide].room) == "hall", "night 1's sleepy ghost hides in the hall, near the start")
	# Granny Boo's jars: a family playing night after night fills the shelf and lights the house up.
	var jars := {}
	var kept := 0
	for n in range(1, 11):
		for g in HouseGen.night_plan(h0, n, 2):
			jars[g.kind] = int(jars.get(g.kind, 0)) + 1
			kept += 1
		if HouseGen.king_night(n):
			jars["king"] = int(jars.get("king", 0)) + 1
			kept += 1
	for k in HouseGen.GHOSTS:
		_expect(int(jars.get(k, 0)) > 0, "a %s jar turns up within ten nights" % k)
	_expect(Museum.cosy_level(kept) >= 5, "ten nights light most of the house up (%d of %d, %d kept)" % [Museum.cosy_level(kept), Museum.STEPS.size(), kept])
	_expect(Museum.cosy_level(0) == 0 and Museum.cosy_level(Museum.STEPS[0]) == 1, "the first cosy step comes after %d ghosts" % Museum.STEPS[0])
	_expect(Museum.jars_shown(0) == 0 and Museum.jars_shown(1) == 1 and Museum.jars_shown(100) == 3, "jars on the shelf: 0, 1 .. 3")
	# SECOND PASS: wings, modes, the new ghosts and a smooth climb.
	_expect(HouseGen.generate(5, {"level": 0}).wing.is_empty(), "the very first house has no wing")
	_expect(String(HouseGen.generate(5, {"level": 1}).wing.id) == "attic", "the attic opens on the second house")
	_expect(String(HouseGen.generate(5, {"level": 2}).wing.id) == "cellar", "then the cellar")
	_expect(String(HouseGen.generate(5, {"level": 3}).wing.id) == "greenhouse", "then the greenhouse")
	var wings_seen := {}
	var wing_rooms := {}
	for s in 40:
		var hw := HouseGen.generate(3000 + s, {"level": 4 + s % 3})
		wings_seen[hw.wing.id] = true
		wing_rooms[hw.wing.room] = true
		var n_wing := (hw.spots as Array).filter(func(o: Dictionary) -> bool: return String(o.kind) == String(hw.wing.kind)).size()
		_expect(n_wing >= 1, "house %d: the %s has a %s to hide in" % [3000 + s, hw.wing.id, hw.wing.kind])
	_expect(wings_seen.size() == 3 and wing_rooms.size() == 2, "later houses get every wing in both side rooms (%s, %s)" % [wings_seen.keys(), wing_rooms.keys()])
	var hm := HouseGen.generate(4242, {"level": 5})
	for m in HouseGen.MODE_IDS:
		_expect(var_to_str(HouseGen.night_plan(hm, 1, 2, m)) == var_to_str(HouseGen.night_plan(hm, 1, 2)), "%s: night 1 is the gentle night" % m)
		var first_boing := 99
		var first_puff := 99
		for n in range(1, 11):
			var kinds_n := HouseGen.night_plan(hm, n, 2, m).map(func(g: Dictionary) -> String: return String(g.kind))
			if kinds_n.has("boing"):
				first_boing = mini(first_boing, n)
			if kinds_n.has("puff"):
				first_puff = mini(first_puff, n)
		_expect(first_boing <= 6 and first_puff <= 8, "%s: Boing (night %d) and Puff (night %d) come within a visit" % [m, first_boing, first_puff])
		_expect(first_boing >= 3 and first_puff >= 3, "%s: the new ghosts never come on the first two nights" % m)
	var earlier := 0
	for s in 30:
		var hb := HouseGen.generate(5000 + s, {"level": 4})
		var plain_b := 99
		var wing_b := 99
		for n in range(1, 9):
			var k_n := HouseGen.night_plan(hb, n, 2, "gentle").map(func(g: Dictionary) -> String: return String(g.kind))
			if k_n.has(String(hb.wing.ghost)):
				wing_b = mini(wing_b, n)
		if String(hb.wing.ghost) != "snoozy" and wing_b < int(HouseGen.MODE_NEW.gentle[hb.wing.ghost]):
			earlier += 1
	_expect(earlier > 0, "a wing calls its own ghost a night early (%d houses)" % earlier)
	for m in HouseGen.MODE_IDS:
		for crew in [1, 3, 6]:
			var loads := []
			for n in range(1, 11):
				loads.append(snappedf(HouseGen.night_load(hm, n, crew, m), 0.1))
			print("curve %s crew %d: %s" % [m, crew, str(loads)])
			_expect(HouseGen.curve_problems(hm, m, crew).is_empty(), "%s crew %d: a smooth climb %s" % [m, crew, str(HouseGen.curve_problems(hm, m, crew))])
	_expect(HouseGen.night_load(hm, 6, 3, "hard") > HouseGen.night_load(hm, 6, 3, "gentle") * 1.15, "hard is clearly harder than gentle by night 6")
	_expect(HouseGen.catch_time("puff", false) < 4.0 and HouseGen.catch_time("boing", true) < 6.0, "Boing and the pufflings are quick to catch")
	_expect(HouseGen.LAND_DIZZY.gentle >= HouseGen.LAND_DIZZY.hard and HouseGen.HOP_TIME >= 1.0, "a hop is told for a second, gentle lands dizzy longest")
	# The checker catches a wing hiding place outside its wing.
	var badw := HouseGen.generate(4242, {"level": 5})
	var other := "library" if String(badw.wing.room) == "ballroom" else "ballroom"
	for o in badw.spots:
		if String(o.kind) == String(badw.wing.kind):
			o.room = other
	_expect(HouseGen.check(badw).any(func(w: String) -> bool: return w.contains("outside its wing")), "a wing's hiding place outside the wing is caught")
	# Hand checks: the checker catches broken houses.
	var good := HouseGen.generate(77, {"level": 3})
	_expect(HouseGen.check(good).is_empty(), "house 77 is fine")
	var bad := good.duplicate(true)
	var sp: Dictionary = bad.spots[HouseGen.FIXED_SPOTS.size()]
	sp.pos = Vector3(-14.0, 0.0, -2.0)  # on the reading table
	sp.peek = HouseGen._peek_point(sp)
	_expect(not HouseGen.check(bad).is_empty(), "a hiding place on the reading table is caught")
	var bad2 := good.duplicate(true)
	var sp2: Dictionary = bad2.spots[HouseGen.FIXED_SPOTS.size()]
	sp2.kind = "wardrobe"
	sp2.room = "hall"
	sp2.pos = Vector3(-7.0 + 0.5, 0.0, 0.0)  # in the doorway
	sp2.yaw = 0.0
	sp2.peek = HouseGen._peek_point(sp2)
	_expect(not HouseGen.check(bad2).is_empty(), "a wardrobe in the doorway is caught")
	var bad3 := good.duplicate(true)
	# Wall the library off with wardrobes across the doorway side: the far room is shut in.
	for z in [-7.0, -5.7, -4.4, -3.1, -1.8, -0.5, 0.8, 2.1, 3.4, 4.7, 6.0, 7.3]:
		var w := {"kind": "wardrobe", "room": "library", "pos": Vector3(-10.0, 0.0, z), "yaw": PI / 2.0}
		w.peek = HouseGen._peek_point(w)
		(bad3.spots as Array).append(w)
	_expect(HouseGen.check(bad3).any(func(w: String) -> bool: return w.contains("shut in")), "a shut-in room is caught")
	var bad4 := good.duplicate(true)
	bad4.rooms = ["library", "hall", "ballroom"]
	_expect(not HouseGen.check(bad4).is_empty(), "night 1 away from the hall is caught")
	var plan := HouseGen.night_plan(good, 3, 2)
	var dup := plan.duplicate(true)
	var hides := dup.filter(func(g: Dictionary) -> bool: return g.hide >= 0)
	if hides.size() >= 2:
		hides[1].hide = hides[0].hide
	_expect(not HouseGen.plan_problems(good, 3, 2, dup).is_empty(), "two ghosts in one hiding place is caught")
	print("house gen: %d houses checked, %d failures" % [total, fails])
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: house gen: " + what)
