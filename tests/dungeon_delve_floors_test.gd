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
## And the run as a whole (fast logic checks, timed: they must stay well under 100 ms on a Deck):
##  - every floor of a run can be reached: start -> stairs (or the boss) on every floor of every biome;
##  - every boss room is fair (FloorGen.boss_room_problem: open arena, one boss of the biome, starting away
##    from the door) and every boss attack winds up for at least Foes.MIN_TELL seconds, even in phase 3;
##  - the biome hazards (crystal shards, lava vents) glow for long enough, sit on walkable floor away from
##    doors, and never in the start, boss or camp rooms;
##  - every relic altar offer is valid (Relics.check_offer) for every hoard level and party (solo hero,
##    solo VR knight, a full party with relics already taken);
##  - difficulty rises smoothly with depth: monster strength climbs every floor, never by more than 25 %,
##    and the monsters on a floor (cost x strength, averaged over seeds) climb floor by floor.
## Prints "SCRIPT ERROR: FLOORS ..." for each failure (the bot runner greps for SCRIPT ERROR).

const FloorGen := preload("res://games/dungeon_delve/floorgen.gd")
const FloorView := preload("res://games/dungeon_delve/floor_view.gd")
const Foes := preload("res://games/dungeon_delve/foes.gd")
const Relics := preload("res://games/dungeon_delve/relics.gd")
const Classes := preload("res://games/dungeon_delve/classes.gd")
const Deep := preload("res://games/dungeon_delve/deep.gd")

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
				for s2 in [930279, 542184, 666233, 42, 71, 33]:  # seeds the family / bots played
					_check(s2, zone, fl, heroic)
	# Endless depths: the zones go round again with twists.
	for zone2 in range(FloorGen.ZONE_COUNT, FloorGen.ZONE_COUNT + 4):
		for fl2 in FloorGen.FLOORS_PER_ZONE:
			for s3 in maxi(4, seeds / 6):
				_check(5000 + s3 * 131, zone2, fl2, s3 % 2 == 0)
	if FloorGen.modifier(1, 0, 0) != "" or FloorGen.modifier(1, FloorGen.ZONE_COUNT, 0) == "":
		_fail("twists only in the endless depths")
	for path in ["res://games/dungeon_delve/deep.gd", "res://games/dungeon_delve/deep_hud.gd", "res://games/dungeon_delve/floor_view.gd", "res://games/dungeon_delve/foes.gd"]:
		var src := FileAccess.get_file_as_string(path)
		if RegEx.create_from_string("ZONES\\[(zone|z)\\]").search(src) != null:
			_fail("%s indexes ZONES with a raw zone (use FloorGen.zone_data: endless zones go past 3)" % path)
	if FloorGen.room_door_bits(FloorGen.generate(3, 0, 0, false), 99) != 0:
		_fail("room_door_bits with a stale room index from another floor must be 0")
	_check_shop()
	_check_view()
	var t1 := Time.get_ticks_usec()
	_check_run_logic()
	_check_bosses()
	_check_relics()
	_check_difficulty()
	print("FLOORS: run logic checks %.1f ms" % ((Time.get_ticks_usec() - t1) / 1000.0))
	for path2 in ["res://games/dungeon_delve/deep.gd", "res://games/dungeon_delve/foes.gd", "res://games/dungeon_delve/floor_view.gd", "res://games/dungeon_delve/deep_hud.gd"]:
		var src2 := FileAccess.get_file_as_string(path2)
		if RegEx.create_from_string("\\b(zone|z) [!=]= [0-9]").search(src2) != null:
			_fail("%s picks looks by a zone number (use the biome id: FloorGen.zone_data(zone)[\"id\"])" % path2)
	print("FLOORS: %d floors checked, %d failures (%d ms)" % [checks, fails, Time.get_ticks_msec() - t0])
	quit(1 if fails > 0 else 0)


func _fail(msg: String) -> void:
	fails += 1
	if fails < 40:
		print("SCRIPT ERROR: FLOORS %s" % msg)


## The floor view survives an empty floor (deep.stop() used to build one: crash on the TV, 25 Oct),
## a real floor, and clear().
func _check_view() -> void:
	var v := FloorView.new()
	root.add_child(v)
	v.build({"seed": 0, "zone": 0, "floor": 0, "kind": "none", "rooms": [], "doors": [], "switches": [], "traps": []})
	v.build(FloorGen.generate(930279, 0, 0, true))
	v.clear()
	v.animate(0.016, 0)
	if not v.f.is_empty():
		_fail("FloorView.clear leaves a floor")
	v.queue_free()


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


## Every floor of a run (seeded like a real run: shop camps in between), every biome and two endless laps.
func _check_run_logic() -> void:
	for heroic in [false, true]:
		for sd in 12:
			var seed_value := 77 + sd * 1013
			for z in FloorGen.ZONE_COUNT + 2:
				for fl in FloorGen.FLOORS_PER_ZONE:
					var f := FloorGen.generate(seed_value, z, fl, heroic)
					var tag := "run seed %d %d-%d" % [seed_value, z + 1, fl + 1]
					var reach := FloorGen.solve(f)
					if reach.size() != (f["rooms"] as Array).size():
						_fail("%s: a room can't be reached" % tag)
					if FloorGen.is_boss_floor(fl):
						var why := FloorGen.boss_room_problem(f)
						if why != "":
							_fail("%s: unfair boss room: %s" % [tag, why])
					elif not reach.has(int(f["exit"])):
						_fail("%s: the stairs can't be reached" % tag)
					_check_features(f, tag)
					var shop := FloorGen.generate(seed_value, z, fl, heroic, "shop")
					if not ((shop["rooms"] as Array)[0] as Dictionary).has("stairs"):
						_fail("%s: the camp has no stairs" % tag)


func _check_features(f: Dictionary, tag: String) -> void:
	var rooms: Array = f["rooms"]
	var zd: Dictionary = FloorGen.zone_data(int(f["zone"]))
	var rects := FloorGen.walk_rects(f, (1 << (f["doors"] as Array).size()) - 1)
	var obst := FloorGen.obstacle_rects(f)
	var any := false
	for i in rooms.size():
		var r: Dictionary = rooms[i]
		for fe in (r.get("features", []) as Array):
			var fd: Dictionary = fe
			any = true
			var fk := String(fd["kind"])
			if fk != String(zd["feature"]):
				_fail("%s: %s in the %s" % [tag, fk, String(zd["name"])])
			if String(r["role"]) in ["start", "boss", "secret", "treasure", "shop"]:
				_fail("%s: %s in a %s room" % [tag, fk, String(r["role"])])
			if float(FloorGen.FEATURE[fk]["warn"]) < FloorGen.MIN_WARN:
				_fail("%s glows for too short a time" % fk)
			var p2: Vector2 = fd["p"]
			for d in (r["doors"] as Dictionary):
				if FloorGen.door_local(int(d)).distance_to(p2) < (2.0 if fk == "vents" else 1.6):
					_fail("%s: %s right by a door in room %d" % [tag, fk, i])
			if fk == "vents" and not FloorGen.walkable(rects, obst, FloorGen.to_world(f, i, p2), 0.3):
				_fail("%s: a lava vent in a wall / pillar in room %d" % [tag, i])
			if fk == "vents" and (r.has("stairs") and (r["stairs"] as Vector2).distance_to(p2) < 1.8 or r.has("key_at") and (r["key_at"] as Vector2).distance_to(p2) < 1.5):
				_fail("%s: a lava vent on the stairs / key in room %d" % [tag, i])
	if String(zd["feature"]) != "" and not any and FloorGen.global_floor(int(f["zone"]), int(f["floor"])) > 0 and not FloorGen.is_boss_floor(int(f["floor"])):
		_fail("%s: no %s anywhere in the %s" % [tag, String(zd["feature"]), String(zd["name"])])


## Every biome has a boss with readable tells (at every phase), and boss health stays sane for one player.
func _check_bosses() -> void:
	var seen := {}
	for z in FloorGen.ZONE_COUNT:
		var b := int(FloorGen.ZONES[z]["boss"])
		if seen.has(b):
			_fail("two biomes share a boss")
		seen[b] = true
		if not Foes.BOSSES.has(b) or not Foes.BOSS_NAMES.has(b) or not Foes.TELLS.has(b) or not Foes.BASE_HP.has(b) or not Foes.GOLD.has(b):
			_fail("boss %d is missing its name / tells / health / gold" % b)
			continue
		for atk in Foes.TELLS[b]:
			for ph in [1, 2, 3]:
				if Foes.tell(b, String(atk), ph) < Foes.MIN_TELL:
					_fail("%s's %s winds up in %.2f s at phase %d (< %.2f)" % [Foes.BOSS_NAMES[b], atk, Foes.tell(b, String(atk), ph), ph, Foes.MIN_TELL])
		for heroic in [false, true]:
			var d: Dictionary = Deep.DIFF["heroic" if heroic else "brave"]
			var sc := FloorGen.scaling(float(d["hp"]), float(d["spd"]), heroic, z, 3, 1)
			var hp := float(Foes.BASE_HP[b]) * float(sc["boss_hp"])
			if hp > 260.0 or hp < 40.0:
				_fail("%s has %d health alone on %s" % [Foes.BOSS_NAMES[b], int(hp), "heroic" if heroic else "brave"])
			if z > 0:
				var pb := int(FloorGen.ZONES[z - 1]["boss"])
				var sp := FloorGen.scaling(float(d["hp"]), float(d["spd"]), heroic, z - 1, 3, 1)
				if hp <= float(Foes.BASE_HP[pb]) * float(sp["boss_hp"]):
					_fail("%s isn't tougher than %s" % [Foes.BOSS_NAMES[b], Foes.BOSS_NAMES[pb]])


## Every altar offer is valid, for every hoard level and many parties.
func _check_relics() -> void:
	var ids := {}
	for r in Relics.LIST:
		if ids.has(r["id"]):
			_fail("relic %s twice" % r["id"])
		ids[r["id"]] = true
	if Relics.count() < 8 or Relics.count() > 12:
		_fail("%d relics (8-12 wanted)" % Relics.count())
	if Relics.unlocked(0).size() < Relics.OFFER * 2:
		_fail("too few relics at the start")
	if not Classes.unlocked(0).has("knight") or Classes.unlocked(1 << 20).size() != Classes.ORDER.size():
		_fail("hero unlocks")
	var hoards: Array = [0, 59, 60, 199, 200, 500, 1000, 5000]
	for r2 in Relics.LIST:
		hoards.append(int(r2["hoard"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var all_ids: Array = ids.keys()
	var offers := 0
	for h in hoards:
		var un := Relics.unlocked(int(h))
		for t in 40:
			var party: Array = []
			match t % 4:
				0:
					party = [{"knight": false, "relics": []}]
				1:
					party = [{"knight": true, "relics": []}]
				2:
					party = [{"knight": true, "relics": []}, {"knight": false, "relics": []}]
				_:
					for k in rng.randi_range(2, 6):
						party.append({"knight": k == 0 and rng.randf() < 0.5, "relics": []})
			# Relics already taken (up to every one).
			for m in party:
				for k2 in rng.randi_range(0, all_ids.size()):
					var id: String = all_ids[rng.randi_range(0, all_ids.size() - 1)]
					if not (m["relics"] as Array).has(id):
						(m["relics"] as Array).append(id)
			for z in FloorGen.ZONE_COUNT + 1:
				for fl in FloorGen.FLOORS_PER_ZONE:
					if not Relics.altar_after(fl):
						continue
					var o := Relics.offer(1000 + t, z, fl, un, party)
					offers += 1
					var why := Relics.check_offer(o, un, party)
					if why != "":
						_fail("relic offer (hoard %d, party %s): %s" % [int(h), str(party), why])
					if o != Relics.offer(1000 + t, z, fl, un, party):
						_fail("relic offers aren't seeded")
	# A fresh solo hero always gets a full altar.
	if Relics.offer(1, 0, 1, Relics.unlocked(0), [{"knight": false, "relics": []}]).size() != Relics.OFFER:
		_fail("a fresh hero doesn't get %d relics to choose from" % Relics.OFFER)
	if Relics.offer(1, 0, 1, Relics.unlocked(0), [{"knight": true, "relics": []}]).size() < Relics.MIN_OFFER:
		_fail("the VR knight alone gets fewer than %d relics" % Relics.MIN_OFFER)
	for fl2 in FloorGen.FLOORS_PER_ZONE:
		if Relics.altar_after(fl2) != (fl2 == 1 or FloorGen.is_boss_floor(fl2)):
			_fail("altars: after the 2nd floor and after the boss")


## Difficulty rises smoothly with depth (BRAVE and HEROIC, 1-4 players).
func _check_difficulty() -> void:
	for heroic in [false, true]:
		var d: Dictionary = Deep.DIFF["heroic" if heroic else "brave"]
		for n in [1, 2, 4]:
			var prev := -1.0
			for g in (FloorGen.ZONE_COUNT + 2) * FloorGen.FLOORS_PER_ZONE:
				var sc := FloorGen.scaling(float(d["hp"]), float(d["spd"]), heroic, g / FloorGen.FLOORS_PER_ZONE, g % FloorGen.FLOORS_PER_ZONE, n)
				var st := FloorGen.strength(sc)
				if prev > 0.0 and (st <= prev or st > prev * 1.25):
					_fail("%s %dp: monster strength %.2f -> %.2f at depth %d (must climb, by 25 %% at most)" % ["heroic" if heroic else "brave", n, prev, st, g + 1])
				prev = st
		# A typical fight (monster cost per fight room x strength, 30 seeds): every fight floor at least as hard as the last.
		var last := -1.0
		var last_g := 0
		for z in FloorGen.ZONE_COUNT:
			for fl in FloorGen.FLOORS_PER_ZONE - 1:
				var tot := 0.0
				var fights := 0
				for sd in 30:
					var f := FloorGen.generate(400 + sd * 37, z, fl, heroic)
					for r in f["rooms"]:
						if ((r as Dictionary)["foes"] as Array).is_empty():
							continue
						fights += 1
						for fo in (r as Dictionary)["foes"]:
							var fk := int((fo as Array)[0])
							tot += float(FloorGen.FOE_COST.get(fk, 1.0)) / (3.0 if fk == FloorGen.F_SWARM else 1.0)
				var sc2 := FloorGen.scaling(float(d["hp"]), float(d["spd"]), heroic, z, fl, 1)
				var threat := tot / maxf(1.0, fights) * FloorGen.strength(sc2)  # a typical fight on this floor
				var g := FloorGen.global_floor(z, fl)
				if last > 0.0 and (threat < last * 0.97 or threat > last * pow(1.45, g - last_g)):  # (boss floors skipped: two steps)
					_fail("%s: floor %d-%d threat %.1f after %.1f (not a smooth climb)" % ["heroic" if heroic else "brave", z + 1, fl + 1, threat, last])
				last = threat
				last_g = g
