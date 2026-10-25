extends SceneTree
## DUNGEON DELVE deep floors: checks the generator over many seeds (no game, no window).
##   godot-test --headless --path . -s res://tests/dungeon_delve_floors_test.gd
## For every zone x floor x difficulty and SEEDS seeds:
##  - logic: every room can be reached from the start (keys found before their locked doors, puzzle
##    switches on the near side, the secret room behind its wall), the key is never behind its own door;
##  - geometry: with every door open, a body the size of a hero can walk (0.25 m grid flood fill)
##    from the start to every doorway, switch, key, chest, stairs and monster spawn, and nothing spawns
##    inside a pillar; boss floors have exactly one boss room with the boss in it;
##  - determinism: the same seed builds the same floor.
## Prints "SCRIPT ERROR: FLOORS ..." for each failure (the bot runner greps for SCRIPT ERROR).

const FloorGen := preload("res://games/dungeon_delve/floorgen.gd")

var fails := 0
var checks := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 60
	var t0 := Time.get_ticks_msec()
	for heroic in [false, true]:
		for zone in FloorGen.ZONE_COUNT:
			for fl in FloorGen.FLOORS_PER_ZONE:
				for s in seeds:
					_check(1000 + s * 7919, zone, fl, heroic)
	_check_shop()
	print("FLOORS: %d floors checked, %d failures (%d ms)" % [checks, fails, Time.get_ticks_msec() - t0])
	quit(1 if fails > 0 else 0)


func _fail(msg: String) -> void:
	fails += 1
	if fails < 40:
		print("SCRIPT ERROR: FLOORS %s" % msg)


func _check_shop() -> void:
	var f := FloorGen.generate(5, 1, 2, false, "shop")
	if (f["rooms"] as Array).size() != 1 or not ((f["rooms"] as Array)[0] as Dictionary).has("stairs"):
		_fail("the shop is one room with stairs")


func _check(seed_value: int, zone: int, fl: int, heroic: bool) -> void:
	checks += 1
	var tag := "seed %d zone %d floor %d %s" % [seed_value, zone, fl, "heroic" if heroic else "brave"]
	var f := FloorGen.generate(seed_value, zone, fl, heroic)
	var again := FloorGen.generate(seed_value, zone, fl, heroic)
	if var_to_str(f) != var_to_str(again):
		_fail("%s: not deterministic" % tag)
	var rooms: Array = f["rooms"]
	var doors: Array = f["doors"]
	if rooms.size() < 4:
		_fail("%s: only %d rooms" % [tag, rooms.size()])
	# Logic.
	var reach := FloorGen.solve(f)
	if reach.size() != rooms.size():
		_fail("%s: %d of %d rooms reachable" % [tag, reach.size(), rooms.size()])
	var bosses := 0
	for i in rooms.size():
		var r: Dictionary = rooms[i]
		if String(r["role"]) == "boss":
			bosses += 1
			if (r["foes"] as Array).size() != 1:
				_fail("%s: the boss room has %d monsters" % [tag, (r["foes"] as Array).size()])
	if FloorGen.is_boss_floor(fl) != (bosses == 1) or bosses > 1:
		_fail("%s: %d boss rooms" % [tag, bosses])
	if not FloorGen.is_boss_floor(fl) and not ((rooms[int(f["exit"])] as Dictionary).has("stairs")):
		_fail("%s: the exit has no stairs" % tag)
	var locked := 0
	for d in doors:
		if int((d as Dictionary)["type"]) in [FloorGen.LOCKED, FloorGen.BOSS]:
			locked += 1
	if locked != 1:
		_fail("%s: %d locked doors" % [tag, locked])
	# Geometry: flood fill with everything open.
	var all_open := (1 << doors.size()) - 1
	var rects := FloorGen.walk_rects(f, all_open)
	var obst := FloorGen.obstacle_rects(f)
	var rad := 0.32
	var start := FloorGen.room_center(f, 0) + Vector3(0.0, 0.0, 2.0)
	if not FloorGen.walkable(rects, obst, start, rad):
		start = FloorGen.room_center(f, 0) + Vector3(0.0, 0.0, 3.5)
	var step := 0.25
	var seen := {}
	var q: Array[Vector2i] = []
	var org := Vector2(start.x, start.z)
	var k0 := Vector2i.ZERO
	seen[k0] = true
	q.append(k0)
	var guard := 0
	while not q.is_empty() and guard < 400000:
		guard += 1
		var c: Vector2i = q.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n):
				continue
			var p := Vector3(org.x + n.x * step, 0.0, org.y + n.y * step)
			if FloorGen.walkable(rects, obst, p, rad):
				seen[n] = true
				q.append(n)
	var can := func(p: Vector3, what: String, r: float) -> void:
		var best := false
		var cx := int(round((p.x - org.x) / step))
		var cz := int(round((p.z - org.y) / step))
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				var key := Vector2i(cx + dx, cz + dz)
				if seen.has(key) and Vector2(org.x + key.x * step, org.y + key.y * step).distance_to(Vector2(p.x, p.z)) <= r:
					best = true
		if not best:
			_fail("%s: can't walk to %s at %s" % [tag, what, str(p)])
	for di in doors.size():
		var dd: Dictionary = doors[di]
		can.call(FloorGen.door_world(f, di), "door %d" % di, 0.5)
	for sw in f["switches"]:
		var s: Dictionary = sw
		var wp := FloorGen.to_world(f, int(s["room"]), s["p"])
		can.call(wp, "%s switch" % String(s["kind"]), 0.9 if String(s["kind"]) == "lever" else 0.5)
	for i in rooms.size():
		var r: Dictionary = rooms[i]
		for fo in r["foes"]:
			var fp := FloorGen.to_world(f, i, (fo as Array)[1])
			if int((fo as Array)[0]) < FloorGen.B_SLIME:
				if not FloorGen.walkable(rects, obst, fp, 0.25):
					_fail("%s: a monster spawns in a wall/pillar in room %d" % [tag, i])
		for ch in r["chests"]:
			can.call(FloorGen.to_world(f, i, (ch as Array)[0]), "chest in room %d" % i, 0.9)
		if r.has("key_at"):
			can.call(FloorGen.to_world(f, i, r["key_at"]), "key in room %d" % i, 0.5)
		if r.has("stairs"):
			can.call(FloorGen.to_world(f, i, r["stairs"]), "stairs", 0.6)
		for p in r["pots"]:
			can.call(FloorGen.to_world(f, i, p), "pot in room %d" % i, 0.7)
