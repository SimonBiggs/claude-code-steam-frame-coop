extends SceneTree
## TINY TOWN TYCOON seeded islands: proves every island is a good place for a town (no game, no window).
##   godot-test --headless --path . -s res://tests/tiny_town_tycoon_gen_test.gd      (SEEDS=500 for more)
## games/tiny_town_tycoon/islandgen.gd check() over many seeds (the hall and street fit in the middle,
## room for the practice road and for houses, every district reachable with room and a landmark that
## fits and can be reached, every resource has a reachable spot for its building); same seed -> same
## island; islands differ (biomes, rivers, hills); old towns get districts and resources without anything
## landing on their buildings; TODAY'S ISLAND is the same all day and passes too. Then THE WISHES: a
## greedy little mayor plays many seeded towns through wishes.gd, granting every wish the way the game
## does (a building at the wished spot, a road to it), opening every district: no wish may ever be
## impossible. Hand-broken islands are caught. Prints "SCRIPT ERROR: ..." for each failure.

const IslandGen := preload("res://games/tiny_town_tycoon/islandgen.gd")
const Wishes := preload("res://games/tiny_town_tycoon/wishes.gd")
const Town := preload("res://games/tiny_town_tycoon/town.gd")
const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const Seeded := preload("res://core/seeded.gd")

var fails := 0


func _init() -> void:
	var seeds := int(OS.get_environment("SEEDS")) if OS.has_environment("SEEDS") else 120
	var t0 := Time.get_ticks_usec()
	var r := Seeded.validate(func(s: int) -> Dictionary: return IslandGen.generate(s),
		func(isl: Dictionary) -> Array: return IslandGen.check(isl), seeds, 1, [0, 1, 999999], "ISLAND")
	fails += (r.failures as Array).size()
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, float(r.checked) * 2.0)
	print("island gen: %.2f ms per island + check (%d islands)" % [per_ms, int(r.checked)])
	_expect(per_ms < 60.0, "an island generates and checks in under 60 ms here (%.2f ms)" % per_ms)
	# Variety.
	var biomes := {}
	var rivers := 0
	var shapes := {}
	var looks := {}
	for s in 60:
		var isl := IslandGen.generate(1000 + s * 31)
		biomes[int(isl.biome)] = true
		rivers += 1 if bool(isl.river) else 0
		shapes[var_to_str(isl.ter)] = true
		for k in range(1, IslandGen.DISTRICTS + 1):
			looks[IslandGen.district_look(isl, k)] = true
	_expect(biomes.size() == 3, "all three biomes turn up (%s)" % str(biomes.keys()))
	_expect(rivers > 20 and rivers < 60, "most islands have a river, not all (%d of 60)" % rivers)
	_expect(shapes.size() == 60, "every island is a new shape (%d of 60)" % shapes.size())
	_expect(looks.size() >= 3, "districts look different (%s)" % str(looks.keys()))
	# TODAY'S ISLAND: the same all day, different each day, always good.
	var days := {}
	for d in 30:
		var date := Time.get_date_string_from_unix_time(1790000000 + d * 86400)
		var s1 := Wishes.today_seed(date)
		_expect(s1 == Wishes.today_seed(date), "today's island is the same all day")
		days[s1] = true
		for w in IslandGen.check(IslandGen.generate(s1)):
			_fail("today %s: %s" % [date, w])
	_expect(days.size() >= 28, "today's island changes every day (%d of 30)" % days.size())
	# Old towns (made before seeded islands): features() leaves their buildings and roads alone.
	var old := Town.new()
	old.generate(0)
	old.starter_town()
	old.add_building("house", 3, 11, 0, 1)
	old.set_layer(4, 11, Defs.L_ROAD)
	var oi := {"seed": 77, "ter": old.ter, "trees": old.trees.duplicate()}
	IslandGen.features(oi, old.owner_id, old.lay)
	var res: PackedByteArray = oi.res
	for i in Defs.GRID * Defs.GRID:
		if res[i] != 0 and (old.owner_id[i] > 0 or old.lay[i] != 0):
			_fail("old town: a resource landed on a building or road at %d" % i)
	var dist: PackedByteArray = oi.dist
	_expect((int(oi.open) >> int(dist[11 * Defs.GRID + 3])) & 1 == 1, "old town: a district with a house in it starts open")
	for l in oi.lm:
		if not (l as Array).is_empty():
			for c in old.footprint(String(l[0]), int(l[1]), int(l[2])):
				_expect(old.owner_id[c.y * Defs.GRID + c.x] == 0 and old.lay[c.y * Defs.GRID + c.x] == 0, "old town: a landmark spot is free")
	# THE WISHES: a greedy mayor grants every wish on many towns; none may be impossible.
	var t1 := Time.get_ticks_usec()
	var granted_total := 0
	var land_wishes := 0
	var kinds_seen := {}
	var towns := int(OS.get_environment("TOWNS")) if OS.has_environment("TOWNS") else 14
	for s in towns:
		var out := Wishes.self_play(IslandGen.generate(5000 + s * 101), 36, 4242 + s)
		for w in out.problems:
			_fail("wishes seed %d: %s" % [5000 + s * 101, w])
		granted_total += int(out.granted)
		land_wishes += int(out.land)
		for k in out.kinds:
			kinds_seen[k] = true
		_expect(int(out.open) == 15, "seed %d: every district opened by wishes (open %d after %d wishes)" % [5000 + s * 101, int(out.open), int(out.granted)])
	print("wishes: %d granted over %d towns (%d land wishes), %.1f ms per town" % [granted_total, towns, land_wishes,
		float(Time.get_ticks_usec() - t1) / 1000.0 / towns])
	_expect(land_wishes > towns, "wishes ask for resource spots too (%d)" % land_wishes)
	_expect(kinds_seen.size() >= 6, "wishes ask for many kinds of building (%s)" % str(kinds_seen.keys()))
	# Hand checks: the validator catches broken islands.
	var b1 := IslandGen.generate(42)
	var t1b: PackedByteArray = b1.ter
	t1b.fill(Defs.T_WATER)
	b1.ter = t1b
	_expect(not IslandGen.check(b1).is_empty(), "an island of sea is caught")
	var b2 := IslandGen.generate(42)
	var t2b: PackedByteArray = b2.ter
	for i in Defs.GRID * Defs.GRID:
		if Vector2(i % Defs.GRID + 0.5, i / Defs.GRID + 0.5).distance_to(IslandGen.CENTRE) < 3.0:
			t2b[i] = Defs.T_ROCK
	b2.ter = t2b
	_expect(not IslandGen.check(b2).is_empty(), "rocks under the town hall are caught")
	var b3 := IslandGen.generate(42)
	b3.lm = [[], [], [], []]
	_expect(not IslandGen.check(b3).is_empty(), "missing landmarks are caught")
	var b4 := IslandGen.generate(42)
	var t4b: PackedByteArray = b4.ter
	for i in Defs.GRID * Defs.GRID:
		var dc := Vector2(i % Defs.GRID + 0.5, i / Defs.GRID + 0.5).distance_to(IslandGen.CENTRE)
		if dc > IslandGen.CENTRE_R - 0.5 and dc < IslandGen.CENTRE_R + 1.0:
			t4b[i] = Defs.T_WATER  # a moat round the middle
	b4.ter = t4b
	_expect(not IslandGen.check(b4).is_empty(), "districts cut off by a moat are caught")
	var b5 := IslandGen.generate(43)
	var r5b: PackedByteArray = b5.res
	r5b.fill(0)
	b5.res = r5b
	_expect(not IslandGen.check(b5).is_empty(), "an island without resources is caught")
	# Pictures: every story card picture has a drawing, and the ones the town uses exist.
	var StoryCard := load("res://core/story_card.gd")
	var src := FileAccess.get_file_as_string("res://core/story_card.gd")
	for pic in StoryCard.PICTURES:
		var re := RegEx.create_from_string("\\n\\t+(\"[a-z]+\", )*\"%s\"(, \"[a-z]+\")*:" % pic)
		_expect(re.search(src) != null, "story card picture %s has a drawing" % pic)
	for pic in Wishes.PICTURES_USED:
		_expect(StoryCard.PICTURES.has(pic) or ["star", "heart", "crown", "music", "trophy", "flag"].has(pic), "picture %s exists" % pic)
	for w in Wishes.self_check():
		_fail("wishes: " + w)
	print("island gen: %d failures" % fails)
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(what: String) -> void:
	fails += 1
	print("SCRIPT ERROR: island gen: " + what)
