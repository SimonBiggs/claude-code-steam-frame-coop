extends RefCounted
## CRYSTAL SAGA journeys: every journey north is generated from a seed and a tier (how many journeys the
## family has done), so the road changes every time while the story (the village, the shrine) stays:
##  - names: the forest, the cave and the giant ("MOSSY HOLLOW", "GLOW GROTTO", "MOSS GIANT!");
##  - looks: leaf colour of the forest, gem colour of the cave, the giant's colours;
##  - props: the touchable things along the edges of the forest, cave and glade (trees, mushrooms,
##    flowers, crystals, chests with shards, signposts) and ROCKS in the way (logs, crystal clusters,
##    standing stones) that the party walks round;
##  - encounters: the monster waves of the forest and cave (positions and kinds), how many show up for
##    1..7 heroes (count = base + team, between lo and the wave's size), and the giant's toughness;
##    higher tiers bring more waves, bigger waves, quicker monsters, a tougher giant who stomps sooner.
## check(plan) is the validator (tests/crystal_saga_gen_test.gd runs it over many seeds and tiers):
## every zone walkable from its entrance to its barrier, every touchable thing in reach, the level-up
## stones and the giant free, monsters spawning on open ground away from the entrance, and every
## encounter fair for a team of 1 to 7 (enough to do, never swamped, done in reasonable time).
## The host sends [seed, tier, daily]; every machine rebuilds the same plan (generate() is deterministic).

const Seeded := preload("res://core/seeded.gd")
const World := preload("res://games/crystal_saga/world.gd")
const Monsters := preload("res://games/crystal_saga/monsters.gd")

const TIERS := 6
const MAX_TEAM := 7  ## the VR hero + six TV heroes
const CELL := 0.33  ## validator walk grid
const REACH := 1.0  ## a hero standing this far from a thing's edge can touch it (TV poke 0.7 + slack, VR arm)

const FORESTS: Array[String] = ["WHISPER WOOD", "MOSSY HOLLOW", "BRAMBLE GLEN", "FERN FOREST", "OWL WOOD",
	"BLUEBELL WOOD", "PINE PATH", "FOXGLOVE DELL", "HONEY WOOD", "MAPLE MAZE"]
const CAVES: Array[String] = ["CRYSTAL CAVE", "GLITTER CAVE", "ECHO CAVE", "GLOW GROTTO", "GEM TUNNEL",
	"STAR CAVERN", "RAINBOW CAVE", "DRIP DROP CAVE"]
const LEAVES: Array[Color] = [Color(0.8, 1.0, 0.8), Color(1.0, 0.85, 0.6), Color(0.75, 0.9, 1.0), Color(1.0, 0.8, 0.85),
	Color(0.9, 1.0, 0.65), Color(1.0, 1.0, 1.0)]
const GEMS: Array[Color] = [Color(0.5, 0.85, 1.0), Color(0.85, 0.55, 1.0), Color(0.5, 1.0, 0.75), Color(1.0, 0.75, 0.45),
	Color(1.0, 0.55, 0.7)]
## The level-up stones (main.gd) stand here in a zone: x, z from the zone centre.
const CHOICE_AT: Array[Vector2] = World.CHOICE_SPOTS
## The cave's orb and the glade's giant / friend (fixed spots, kept clear).
const ORB_AT := Vector2(0.0, -1.0)
const GIANT_AT := Vector2(0.0, -3.5)
const FRIEND_AT := Vector2(3.6, -5.2)


## The plan for one journey (pure data: arrays, numbers, colours, strings).
static func generate(seed_value: int, tier: int) -> Dictionary:
	tier = clampi(tier, 0, TIERS - 1)
	var nr := Seeded.rng(seed_value, "names")
	var g := nr.randi() % World.SAGA_GIANTS.size()
	var names: Array = ["WILLOWBROOK", FORESTS[nr.randi() % FORESTS.size()], CAVES[nr.randi() % CAVES.size()],
		"%s GIANT!" % World.SAGA_GIANTS[g][0], "THE CRYSTAL!"]
	var lr := Seeded.rng(seed_value, "look")
	var props: Array = []
	_edge_props(Seeded.rng(seed_value, "forest"), 1, props)
	_edge_props(Seeded.rng(seed_value, "cave"), 2, props)
	_edge_props(Seeded.rng(seed_value, "glade"), 3, props)
	_rocks(Seeded.rng(seed_value, "rocks"), tier, props)
	var waves: Array = [[], _forest_waves(Seeded.rng(seed_value, "w1"), tier, props), _cave_waves(Seeded.rng(seed_value, "w2"), tier, props), [], []]
	return {"seed": seed_value, "tier": tier, "names": names, "leaf": LEAVES[lr.randi() % LEAVES.size()],
		"gem": GEMS[lr.randi() % GEMS.size()], "giant": g, "props": props, "waves": waves,
		"giant_hits": [12 + 2 * tier, 2, 14, 26 + 2 * tier], "speed": 1.0 + 0.07 * tier,
		"stomp": [4.5 - 0.3 * tier, 6.5 - 0.4 * tier]}


## The tree trunks and touchable things along both edges of a zone: [kind, x, z, r] (world coordinates).
static func _edge_props(r: RandomNumberGenerator, zone: int, props: Array) -> void:
	var c := World.center(zone).z
	var bag: Array = []
	match zone:
		1:
			bag = [World.CHEST]
			for i in 2 + r.randi() % 3:
				bag.append(World.MUSHROOM)
			for i in 1 + r.randi() % 3:
				bag.append(World.FLOWER)
		2:
			bag = [World.CHEST]
			for i in 3 + r.randi() % 3:
				bag.append(World.CRYSTAL)
		3:
			for i in 2 + r.randi() % 2:
				bag.append(World.FLOWER)
			if r.randf() < 0.6:
				bag.append(World.CHEST)
			if r.randf() < 0.5:
				bag.append(World.MUSHROOM)
	bag = Seeded.shuffled(r, bag)
	# Slots down both sides, staggered, away from the entrance's spawn row and the far corners.
	var slots: Array = []
	for side in [-1.0, 1.0]:
		var z := c + 5.2 - r.randf() * 0.8
		while z > c - 6.6:
			var x: float = side * r.randf_range(4.2, 4.6)
			if not (zone == 3 and side > 0.0 and z < c - 2.8):  # the giant's friend waves from there
				slots.append([x, z])
			z -= r.randf_range(1.7, 2.6)
	slots = Seeded.shuffled(r, slots)
	for i in mini(bag.size(), slots.size()):
		var k: int = bag[i]
		props.append([k, snappedf(float(slots[i][0]), 0.01), snappedf(float(slots[i][1]), 0.01), _radius(k)])
	if zone == 1:
		var trees := 2 + r.randi() % 3
		for i in trees:
			var side2 := -1.0 if (i + r.randi() % 2) % 2 == 0 else 1.0
			props.append([World.TREE, side2 * 5.6, snappedf(c + 5.0 - (12.0 * (i + r.randf() * 0.6)) / trees, 0.01), _radius(World.TREE)])
	var sx := -1.0 if r.randf() < 0.5 else 1.0
	if zone < 3:
		props.append([World.SIGN, sx * 2.6, c + 6.2, _radius(World.SIGN)])


static func _radius(kind: int) -> float:
	match kind:
		World.TREE: return 0.8
		World.MUSHROOM: return 0.7
		World.CHEST, World.CHOICE: return 0.55
		World.CRYSTAL: return 0.6
	return 0.5


## Rocks in the way (logs and boulders in the forest, crystal clusters in the cave, standing stones in the
## glade): [ROCK, x, z, r]. They stay off the entrance, the exit, the level-up stones, the orb and the giant.
static func _rocks(r: RandomNumberGenerator, tier: int, props: Array) -> void:
	for zone in [1, 2, 3]:
		var c := World.center(zone).z
		var want: int = [0, 1 + r.randi() % 2 + mini(tier, 2) / 2, r.randi() % 3, r.randi() % 3][zone]
		var placed := 0
		for attempt in 30:
			if placed >= want:
				break
			var rad := snappedf(r.randf_range(0.45, 0.72), 0.01)
			var p := Vector2(r.randf_range(-3.2, 3.2), r.randf_range(c - 3.2, c + 3.0))
			if zone == 3:
				p.x = (-1.0 if r.randf() < 0.5 else 1.0) * r.randf_range(3.3, 4.0)
				p.y = r.randf_range(c - 1.8, c + 3.5)
			if not _rock_ok(p, rad, zone, props):
				continue
			props.append([World.ROCK, snappedf(p.x, 0.01), snappedf(p.y, 0.01), rad])
			placed += 1


static func _rock_ok(p: Vector2, rad: float, zone: int, props: Array) -> bool:
	var c := World.center(zone).z
	var keep: Array = [[CHOICE_AT[0] + Vector2(0.0, c), 1.4], [CHOICE_AT[1] + Vector2(0.0, c), 1.4]]
	if zone == 2:
		keep.append([ORB_AT + Vector2(0.0, c), 2.0])
	if zone == 3:
		keep.append([GIANT_AT + Vector2(0.0, c), 2.6])
	for k in keep:
		if p.distance_to(k[0]) < float(k[1]) + rad:
			return false
	for q in props:
		if World.zone_of(Vector3(float(q[1]), 0.0, float(q[2]))) != zone:
			continue
		# Leave a hero-wide gap to everything (so no pocket closes up).
		if p.distance_to(Vector2(float(q[1]), float(q[2]))) < rad + float(q[3]) + 1.2:
			return false
	return true


## Forest waves: slimes and mushies. Each wave: [base, lo, [[kind, x, y, z], ...]]: count(n) = clamp(base + n, lo, size).
static func _forest_waves(r: RandomNumberGenerator, tier: int, props: Array) -> Array:
	var n_waves := 2 + (1 if tier >= 2 else 0) + (1 if tier >= 5 else 0)
	var out: Array = []
	var c := World.center(1).z
	for w in n_waves:
		var size := clampi(4 + tier, 4, 9)
		var mons: Array = []
		for i in size:
			var kind := Monsters.MUSHY if r.randf() < 0.3 + 0.05 * tier else Monsters.SLIME
			var p := _spawn_spot(r, c - 5.5, c + (1.0 if w == 0 else 3.0), 3.8, props, mons)
			mons.append([kind, snappedf(p.x, 0.01), 0.0, snappedf(p.y, 0.01)])
		out.append([1 + tier / 2, 2, mons])
	return out


## Cave waves: bats up high (always first) and slimes on the floor.
static func _cave_waves(r: RandomNumberGenerator, tier: int, props: Array) -> Array:
	var n_waves := 2 + (1 if tier >= 3 else 0)
	var out: Array = []
	var c := World.center(2).z
	for w in n_waves:
		var size := clampi(4 + tier / 2 + w, 4, 8)
		var mons: Array = []
		for i in size:
			if i % 3 == 1:
				var p := _spawn_spot(r, c - 4.5 + w * 1.5, c + 2.0, 3.0, props, mons)
				mons.append([Monsters.SLIME, snappedf(p.x, 0.01), 0.0, snappedf(p.y, 0.01)])
			else:
				var p2 := Vector2(r.randf_range(-2.5, 2.5), r.randf_range(c - 3.0, c + 2.0))
				mons.append([Monsters.BAT, snappedf(p2.x, 0.01), snappedf(r.randf_range(1.75, 2.05), 0.01), snappedf(p2.y, 0.01)])
		out.append([1 + tier / 3, 2, mons])
	return out


## A free ground spot (off rocks and other monsters of the wave); deterministic.
static func _spawn_spot(r: RandomNumberGenerator, z0: float, z1: float, half_x: float, props: Array, mons: Array) -> Vector2:
	var p := Vector2.ZERO
	for attempt in 24:
		p = Vector2(r.randf_range(-half_x, half_x), r.randf_range(z0, z1))
		var ok := true
		for q in props:
			if int(q[0]) == World.ROCK and p.distance_to(Vector2(float(q[1]), float(q[2]))) < float(q[3]) + 0.5:
				ok = false
		for m in mons:
			if p.distance_to(Vector2(float(m[1]), float(m[3]))) < 0.8:
				ok = false
		if int(World.zone_of(Vector3(0.0, 0.0, z0))) == 2 and p.distance_to(ORB_AT + Vector2(0.0, World.center(2).z)) < 0.9:
			ok = false
		if ok:
			return p
	return p


## How many monsters of wave `w` come out for a team of n (the VR hero counts as one).
static func wave_count(wave: Array, n: int) -> int:
	return clampi(int(wave[0]) + n, int(wave[1]), (wave[2] as Array).size())


## The giant's toughness (hits to clear his mist) for a team of n.
static func giant_hits(plan: Dictionary, n: int) -> int:
	var g: Array = plan.giant_hits
	return clampi(int(g[0]) + int(g[1]) * n, int(g[2]), int(g[3]))


## Rough seconds for a team of n to clear a zone's waves (a hit every ~3 s each; four aim at once at most).
static func fight_secs(waves: Array, n: int) -> float:
	var s := 0.0
	for wave in waves:
		s += wave_count(wave, n) * 3.0 / minf(n, 3.0) + 4.0
	return s


## Blockers (round, [Vector2, r]) of one zone: rocks, plus the fixed ones (the cave's orb).
static func blockers(plan: Dictionary, zone: int) -> Array:
	var out: Array = []
	for q in plan.props:
		if int(q[0]) == World.ROCK and World.zone_of(Vector3(float(q[1]), 0.0, float(q[2]))) == zone:
			out.append([Vector2(float(q[1]), float(q[2])), float(q[3])])
	if zone == 2:
		out.append([ORB_AT + Vector2(0.0, World.center(2).z), 0.45])
	return out


# --- The validator ------------------------------------------------------------------------------------

## Everything wrong with a plan (empty = fine).
static func check(plan: Dictionary) -> Array:
	var why: Array = []
	for i in (plan.names as Array).size():
		if String(plan.names[i]).length() > 14 or String(plan.names[i]) == "":
			why.append("name %s is too long" % plan.names[i])
	var props: Array = plan.props
	if props.size() > 34:
		why.append("too many props (%d): used bits run out" % props.size())
	for zone in [1, 2, 3]:
		why.append_array(_check_zone(plan, zone))
	var chests := 0
	for q in props:
		chests += 1 if int(q[0]) == World.CHEST else 0
	if chests < 2:
		why.append("only %d chests (shards to find)" % chests)
	# Encounters: fair for every team size.
	for zone in [1, 2]:
		var waves: Array = plan.waves[zone]
		if waves.size() < 2:
			why.append("zone %d has %d waves" % [zone, waves.size()])
		for n in range(1, MAX_TEAM + 1):
			for wi in waves.size():
				var cnt := wave_count(waves[wi], n)
				if cnt < mini(n, 4) and cnt < (waves[wi][2] as Array).size():
					why.append("zone %d wave %d: only %d monsters for %d heroes" % [zone, wi, cnt, n])
				if cnt < 2:
					why.append("zone %d wave %d: %d monsters" % [zone, wi, cnt])
				if cnt > 3 + 1.5 * n:
					why.append("zone %d wave %d: %d monsters swamp %d heroes" % [zone, wi, cnt, n])
				if zone == 2:
					var slimes := 0
					var bats := 0
					for i in cnt:
						if int(waves[wi][2][i][0]) == Monsters.BAT:
							bats += 1
						else:
							slimes += 1
					if bats == 0 or slimes == 0:
						why.append("cave wave %d for %d heroes: bats %d slimes %d" % [wi, n, bats, slimes])
			var secs := fight_secs(waves, n)
			if secs > 80.0:
				why.append("zone %d takes %.0f s for %d heroes" % [zone, secs, n])
		for wi2 in waves.size():
			for m in waves[wi2][2]:
				why.append_array(_check_spawn(plan, zone, m))
	for n2 in range(1, MAX_TEAM + 1):
		var h := giant_hits(plan, n2)
		if h < 12 or h * 0.8 / minf(n2, 3.0) > 40.0:
			why.append("the giant needs %d hits from %d heroes" % [h, n2])
	if float(plan.stomp[0]) < 2.5 or float(plan.stomp[1]) <= float(plan.stomp[0]):
		why.append("the giant stomps too often %s" % str(plan.stomp))
	if float(plan.speed) > 1.5:
		why.append("monsters too quick (%.2f)" % float(plan.speed))
	return why


## A walk grid over one zone: cells a hero (radius 0.32) can stand on, flood-filled from the entrance.
## Checks the barrier is reachable, every touchable thing is in reach, the special spots are clear.
static func _check_zone(plan: Dictionary, zone: int) -> Array:
	var why: Array = []
	var c := World.center(zone).z
	var bl := blockers(plan, zone)
	var r := 0.32
	var nx := int(ceil((World.HALF_W - r) * 2.0 / CELL)) + 1
	var z_lo := c - World.HALF_L + r + 0.25
	var z_hi := c + World.HALF_L - r
	var nz := int(ceil((z_hi - z_lo) / CELL)) + 1
	var free := PackedByteArray()
	free.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var p := Vector2(-World.HALF_W + r + ix * CELL, z_lo + iz * CELL)
			var ok := 1
			for b in bl:
				if p.distance_to(b[0]) < float(b[1]) + r:
					ok = 0
					break
			free[iz * nx + ix] = ok
	# Flood from the entrance.
	var start := Vector2(0.0, World.entrance(zone).z)
	var si := clampi(int(round((start.x + World.HALF_W - r) / CELL)), 0, nx - 1)
	var sj := clampi(int(round((start.y - z_lo) / CELL)), 0, nz - 1)
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	if free[sj * nx + si] == 0:
		return ["zone %d: the entrance is blocked" % zone]
	var todo: Array[int] = [sj * nx + si]
	seen[sj * nx + si] = 1
	var reach_pts: Array[Vector2] = []
	while not todo.is_empty():
		var k: int = todo.pop_back()
		var ix2 := k % nx
		var iz2 := k / nx
		reach_pts.append(Vector2(-World.HALF_W + r + ix2 * CELL, z_lo + iz2 * CELL))
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var jx: int = ix2 + int(d[0])
			var jz: int = iz2 + int(d[1])
			if jx < 0 or jz < 0 or jx >= nx or jz >= nz:
				continue
			var j := jz * nx + jx
			if seen[j] == 0 and free[j] == 1:
				seen[j] = 1
				todo.append(j)
	var exit_ok := false
	for q in reach_pts:
		if q.y < World.wall_z(zone) + 1.2 and absf(q.x) < 1.5:
			exit_ok = true
			break
	if not exit_ok:
		why.append("zone %d: the barrier can't be reached" % zone)
	# Touchable things, the level-up stones, the orb, the giant's friend: someone can stand next to each.
	var things: Array = []
	for q2 in plan.props:
		var at := Vector2(float(q2[1]), float(q2[2]))
		if World.zone_of(Vector3(at.x, 0.0, at.y)) != zone:
			continue
		var kind := int(q2[0])
		var ctr := at + (Vector2(signf(-at.x) * 0.3, 0.0) if kind == World.TREE else Vector2.ZERO)
		things.append([World.KIND_NAMES[kind], ctr, float(q2[3])])
		if absf(at.x) > World.HALF_W + 1.0 or at.y > c + World.HALF_L or at.y < c - World.HALF_L:
			why.append("zone %d: a %s is off the map" % [zone, World.KIND_NAMES[kind]])
		if kind != World.ROCK:
			for b2 in bl:
				if at.distance_to(b2[0]) < float(b2[1]) + float(q2[3]) - 0.1:
					why.append("zone %d: a %s is inside a rock" % [zone, World.KIND_NAMES[kind]])
	for ci in CHOICE_AT.size():
		things.append(["level-up stone %d" % ci, CHOICE_AT[ci] + Vector2(0.0, c), 0.55])
		for b3 in bl:
			if (CHOICE_AT[ci] + Vector2(0.0, c)).distance_to(b3[0]) < float(b3[1]) + 0.8:
				why.append("zone %d: a rock sits on level-up stone %d" % [zone, ci])
	if zone == 2:
		things.append(["orb", ORB_AT + Vector2(0.0, c), 0.5])
	if zone == 3:
		things.append(["friend", FRIEND_AT + Vector2(-0.6, c), 1.2])
		for b4 in bl:
			if (GIANT_AT + Vector2(0.0, c)).distance_to(b4[0]) < float(b4[1]) + 2.0:
				why.append("zone 3: a rock is in the giant's way")
	for t in things:
		var ctr2: Vector2 = t[1]
		var ok2 := false
		for q3 in reach_pts:
			if q3.distance_to(ctr2) < float(t[2]) + REACH:
				ok2 = true
				break
		if not ok2:
			why.append("zone %d: the %s can't be reached" % [zone, t[0]])
	return why


static func _check_spawn(plan: Dictionary, zone: int, m: Array) -> Array:
	var why: Array = []
	var p := Vector2(float(m[1]), float(m[3]))
	var c := World.center(zone).z
	if absf(p.x) > World.HALF_W - 0.4 or p.y > c + World.HALF_L - 0.9 or p.y < c - World.HALF_L + 0.9:
		why.append("zone %d: a monster spawns off the path at %s" % [zone, str(p)])
	if p.distance_to(Vector2(0.0, World.entrance(zone).z)) < 3.0:
		why.append("zone %d: a monster spawns on the entrance" % zone)
	if int(m[0]) == Monsters.BAT:
		if float(m[2]) < 1.6 or float(m[2]) > 2.3:
			why.append("zone %d: a bat flies out of reach (%.2f)" % [zone, float(m[2])])
	else:
		for b in blockers(plan, zone):
			if p.distance_to(b[0]) < float(b[1]) + 0.3:
				why.append("zone %d: a monster spawns inside a rock" % zone)
	return why
