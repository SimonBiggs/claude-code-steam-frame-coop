extends SceneTree
## DUNGEON DELVE: CINDER'S LOST FRIENDS + RUMBLY FLOORS + trap tells validator (games/dungeon_delve/friends.gd,
## rumble.gd, floorgen.gd TRAP_WARN), no game, no window.
##   godot-test --headless --path . -s res://tests/dungeon_delve_friends_test.gd   (GEN_QUICK=1 = the landing sample)
## Over many seeds (Seeded.validate) x every biome (and two endless depths) x every floor x BRAVE/HEROIC, plus camps:
##  - a caged friend is fair (Friends.problem): in a fight / treasure room you can reach from the start (FloorGen.solve,
##    keys before locked doors), on walkable floor clear of pillars, walls, doors, chests, pots, keys, switches, stairs,
##    lava vents and crystal shard lanes; the biome's own friend; never on a boss floor or in the camp; every biome's
##    2nd floor has one; the same cage on every machine;
##  - a rumbly floor is fair (Rumble.problem): never depth 1, a boss floor, the camp or the boss room; it has a room to
##    rumble in; its falls are told for at least FloorGen.MIN_WARN seconds;
##  - every trap is told for at least FloorGen.MIN_WARN seconds (TRAP_WARN) and the spikes stay down long enough to cross;
##  - every friend turns up somewhere, rumbles turn up in every biome, floor names are two words;
##  - TODAY'S DUNGEON over 400+ days (Seeded.validate_days): its friends and rumbles are fair on every floor;
##  - fast: picking a cage for a floor stays well under a few ms (TestTime.worst; it runs on a Deck at every floor).
## Prints "FRIENDS: PASS" / "SCRIPT ERROR: FRIENDS ..." (the bot runner greps for SCRIPT ERROR).

const FloorGen := preload("res://games/dungeon_delve/floorgen.gd")
const Friends := preload("res://games/dungeon_delve/friends.gd")
const Rumble := preload("res://games/dungeon_delve/rumble.gd")
const Deep := preload("res://games/dungeon_delve/deep.gd")
const Seeded := preload("res://core/seeded.gd")
const TestTime := preload("res://tests/test_time.gd")

var fails := 0
var seen := {}
var rumbles := {}
var worst_ms := 0.0


func _fail(msg: String) -> void:
	fails += 1
	if fails <= 30:
		print("SCRIPT ERROR: FRIENDS " + msg)


## Every floor of a run with this seed (both difficulties, every biome + 2 endless zones, camps): reasons.
func _run_problems(seed_v: int, heroic_too: bool) -> Array:
	var out: Array = []
	for heroic in ([false, true] if heroic_too else [false]):
		for z in FloorGen.ZONE_COUNT + 2:
			var zone_friends := 0
			for fl in FloorGen.FLOORS_PER_ZONE:
				for k in ["floor", "shop"]:
					var f := FloorGen.generate(seed_v, z, fl, heroic, k)
					var c := Friends.pick(f)
					var where := "zone %d floor %d %s%s" % [z, fl, k, " heroic" if heroic else ""]
					var p := Friends.problem(f, c)
					if p != "":
						out.append("%s: %s (%s)" % [where, p, str(c)])
					var rp := Rumble.problem(f)
					if rp != "":
						out.append("%s: %s" % [where, rp])
					if not c.is_empty():
						zone_friends += 1
						seen[String(c["id"])] = true
					if Rumble.on(f):
						rumbles[String(FloorGen.zone_data(z)["id"])] = true
					if k == "floor" and FloorGen.floor_name(seed_v, z, fl).split(" ").size() != 2:
						out.append("%s: floor name %s" % [where, FloorGen.floor_name(seed_v, z, fl)])
			if zone_friends == 0:
				out.append("zone %d: no lost friend in the whole biome" % z)
	return out


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	for k in FloorGen.TRAP_WARN:
		if float(FloorGen.TRAP_WARN[k]) < FloorGen.MIN_WARN:
			_fail("the %s trap is told for only %.1f s" % [k, float(FloorGen.TRAP_WARN[k])])
	if 4.0 - FloorGen.SPIKES_UP - float(FloorGen.TRAP_WARN["spikes"]) < 1.5:
		_fail("the spikes are down for under 1.5 s (no time to cross)")
	if Rumble.WARN < FloorGen.MIN_WARN:
		_fail("falls are told for only %.1f s" % Rumble.WARN)
	if Rumble.RADIUS * 2.0 > FloorGen.HALF:
		_fail("falls are too big to step out of")
	# Seeds (both difficulties).
	var rs := Seeded.validate(func(s: int) -> Dictionary: return {"seed": s},
		func(l: Dictionary) -> Array: return _run_problems(int(l.seed), true), 60, 1000, [930279, 542184, 666233, 42, 71, 33], "FRIENDS")
	fails += (rs.failures as Array).size()
	# TODAY'S DUNGEON (BRAVE rules, Deep.daily_seed).
	var rd := Seeded.validate_days(func(date: String) -> Dictionary: return {"seed": Deep.daily_seed(date)},
		func(l: Dictionary) -> Array: return _run_problems(int(l.seed), false), 400, "FRIENDS TODAY'S DUNGEON", ["2026-11-12"])
	fails += (rd.failures as Array).size()
	if not Seeded.quick():
		for fr in Friends.all():
			if not seen.has(String((fr as Dictionary)["id"])):
				_fail("%s is never lost anywhere" % String((fr as Dictionary)["id"]))
		for z in FloorGen.ZONES:
			if not rumbles.has(String((z as Dictionary)["id"])):
				_fail("the %s never rumbles" % String((z as Dictionary)["id"]))
	if Friends.all().size() != 12 or Friends.CAMP_SPOTS.size() < Friends.all().size():
		_fail("every friend needs a seat at the camp")
	# Speed: every floor's cage pick (it runs at every floor on a Deck), the worst one.
	for z in FloorGen.ZONE_COUNT:
		for fl in FloorGen.FLOORS_PER_ZONE:
			var f := FloorGen.generate(4242 + z, z, fl, true)
			var t1 := Time.get_ticks_usec()
			Friends.pick(f)
			worst_ms = TestTime.worst(worst_ms, (Time.get_ticks_usec() - t1) / 1000.0, func() -> Variant: return Friends.pick(f))
	if worst_ms > 5.0:
		_fail("picking a cage takes %.2f ms" % worst_ms)
	print("FRIENDS: %s - %d seeds, %d days, friends seen %d, rumbly biomes %s, cage pick %.2f ms (%d ms)" % ["PASS" if fails == 0 else "FAIL",
		int(rs.checked), int(rd.checked), seen.size(), str(rumbles.keys()), worst_ms, Time.get_ticks_msec() - t0])
	quit(1 if fails > 0 else 0)
