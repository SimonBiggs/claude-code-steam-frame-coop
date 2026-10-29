extends RefCounted
## TINY TOWN TYCOON islands: every town is a new place. generate(seed) makes a whole island from one
## seed (the same on every machine): its shape, rocky HILLS, a RIVER winding to the sea (roads cross it
## on bridges), ponds, woods, RESOURCES (golden fields for farms, a spring for the water tower, breezy
## hilltops for windmills, deep woods for the sawmill), and DISTRICTS: the middle of the island is open
## from the start; three outer districts sleep under a soft MIST until the townsfolk's wishes come true
## (wishes.gd: OPEN_AT), each with its own LANDMARK (clock tower, big wheel, lighthouse) that appears
## as a blueprint when its mist lifts.
## features() adds districts, landmarks and resources to ANY terrain (old saved towns get them too, and
## a district with something already built in it starts open).
## check() is the validator (tests/tiny_town_tycoon_gen_test.gd runs it over many seeds): the town hall
## and the first street fit in the middle, the practice road has room, every district can be reached by
## road from the street, every landmark fits and can be reached, and every resource has a reachable spot
## for its building.
##   var isl := IslandGen.generate(seed)          # {seed, biome, ter, trees, res, dist, lm, ...}
##   town.apply_island(isl)                       # town.gd

const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const Seeded := preload("res://core/seeded.gd")

const N := Defs.GRID
const HALL := Vector2i(Defs.GRID / 2 - 1, Defs.GRID / 2 - 2)  ## the town hall's corner (town.starter_town)
const STREET_Z := Defs.GRID / 2  ## the first street's row
const STREET_X: Array[int] = [Defs.GRID / 2 - 4, Defs.GRID / 2 + 3]  ## its first and last cell
const CENTRE := Vector2(Defs.GRID * 0.5, Defs.GRID * 0.5)
const CENTRE_R := 6.0  ## district 0 (open from the start): cells this close to the middle
const CLEAR_R := 4.2  ## no hills, rivers, ponds or trees this close to the middle
const DISTRICTS := 3  ## outer districts (1..3), opened in order

## Resources (Town.res per cell) and the building that loves each one.
const R_NONE := 0
const R_FIELD := 1
const R_SPRING := 2
const R_BREEZE := 3
const R_WOOD := 4
const RES_KIND := {R_FIELD: "farm", R_SPRING: "water", R_BREEZE: "windmill", R_WOOD: "sawmill"}
const KIND_RES := {"farm": R_FIELD, "water": R_SPRING, "windmill": R_BREEZE, "sawmill": R_WOOD}

## Biomes: Defs.ISLANDS palettes (meadow, snowy, tropic), weighted.
const BIOMES: Array[int] = [0, 1, 2]
const BIOME_W: Array[int] = [3, 1, 2]
## Each district's look in the story ("the mist lifts over the WOODS").
const LANDMARKS: Array[String] = ["landmark", "ferris", "lighthouse"]


static func generate(seed_value: int) -> Dictionary:
	var r := Seeded.rng(seed_value, "shape")
	var biome: int = BIOMES[Seeded.weighted(Seeded.rng(seed_value, "biome"), BIOME_W)]
	var ter := PackedByteArray()
	ter.resize(N * N)
	ter.fill(Defs.T_WATER)
	var trees := PackedByteArray()
	trees.resize(N * N)
	trees.fill(0)
	# Shape: a wobbly round island, sometimes with a bulge (a headland).
	var r0 := r.randf_range(8.7, 10.0)
	var ph: Array[float] = [r.randf() * TAU, r.randf() * TAU, r.randf() * TAU]
	var amp: Array[float] = [r.randf_range(0.4, 0.9), r.randf_range(0.2, 0.55), r.randf_range(0.3, 0.7)]
	for z in N:
		for x in N:
			var p := Vector2(x + 0.5, z + 0.5) - CENTRE
			var a := atan2(p.y, p.x)
			var rr := r0 + sin(a * 3.0 + ph[0]) * amp[0] + sin(a * 5.0 + ph[1]) * amp[1] + sin(a * 2.0 + ph[2]) * amp[2]
			var dist := p.length()
			if dist < rr - 1.1:
				ter[z * N + x] = Defs.T_GRASS
			elif dist < rr:
				ter[z * N + x] = Defs.T_SAND
	# Rocky hills near the coast.
	var hills: Array[Vector2] = []
	var nh := 1 + r.randi() % 3
	for k in nh:
		var ang := r.randf() * TAU
		var hc := CENTRE + Vector2(cos(ang), sin(ang)) * r.randf_range(5.6, 7.4)
		var hr := r.randf_range(1.2, 2.0)
		hills.append(hc)
		for z in N:
			for x in N:
				var pc := Vector2(x + 0.5, z + 0.5)
				if ter[z * N + x] == Defs.T_GRASS and pc.distance_to(hc) < hr and pc.distance_to(CENTRE) > CLEAR_R + 0.6:
					ter[z * N + x] = Defs.T_ROCK
	# A river: from near a hill (or anywhere inland), winding outwards to the sea.
	var has_river := r.randf() < 0.75
	if has_river:
		var ang0: float = (hills[0] - CENTRE).angle() if not hills.is_empty() and r.randf() < 0.6 else r.randf() * TAU
		var src := CENTRE + Vector2(cos(ang0), sin(ang0)) * (CLEAR_R + 0.6)
		var cur := Vector2i(int(src.x), int(src.y))
		var out_dir := Vector2(cos(ang0), sin(ang0))
		var steps := 0
		while steps < 40:
			steps += 1
			if not _inside(cur.x, cur.y):
				break
			var i := cur.y * N + cur.x
			if ter[i] == Defs.T_WATER:
				break
			if Vector2(cur.x + 0.5, cur.y + 0.5).distance_to(CENTRE) > CLEAR_R + 0.3 and ter[i] != Defs.T_ROCK:
				ter[i] = Defs.T_RIVER
			# step: mostly outwards, sometimes sideways (4-neighbour, so the river never cuts corners)
			var side := Vector2(-out_dir.y, out_dir.x) * (1.0 if r.randf() < 0.5 else -1.0)
			var d := out_dir if r.randf() < 0.62 else side
			var stp := Vector2i(signi(roundi(d.x)), 0) if absf(d.x) >= absf(d.y) else Vector2i(0, signi(roundi(d.y)))
			if stp == Vector2i.ZERO:
				stp = Vector2i(1, 0)
			var nxt := cur + stp
			if Vector2(nxt.x + 0.5, nxt.y + 0.5).distance_to(CENTRE) < CLEAR_R + 0.3:
				nxt = cur + Vector2i(signi(roundi(out_dir.x)), 0) if absf(out_dir.x) >= absf(out_dir.y) else cur + Vector2i(0, signi(roundi(out_dir.y)))
			cur = nxt
		has_river = ter.count(Defs.T_RIVER) >= 3
		if not has_river:
			for i in ter.size():
				if ter[i] == Defs.T_RIVER:
					ter[i] = Defs.T_GRASS
	# A pond or two.
	for k in r.randi() % 2 + (0 if has_river else 1):
		var ang2 := r.randf() * TAU
		var lc := CENTRE + Vector2(cos(ang2), sin(ang2)) * r.randf_range(4.8, 6.4)
		for z in N:
			for x in N:
				var pc2 := Vector2(x + 0.5, z + 0.5)
				if ter[z * N + x] == Defs.T_GRASS and pc2.distance_to(lc) < 1.25 and pc2.distance_to(CENTRE) > CLEAR_R:
					ter[z * N + x] = Defs.T_WATER
	# Woods: clusters of trees on the grass, keeping the town centre clear.
	var woods: Array[Vector2] = []
	for k in 4 + r.randi() % 4:
		var ang3 := r.randf() * TAU
		woods.append(CENTRE + Vector2(cos(ang3), sin(ang3)) * r.randf_range(4.5, 8.0))
	for z in N:
		for x in N:
			if ter[z * N + x] != Defs.T_GRASS:
				continue
			var pc3 := Vector2(x + 0.5, z + 0.5)
			if pc3.distance_to(CENTRE) < CLEAR_R:
				continue
			var near := 99.0
			for cc in woods:
				near = minf(near, pc3.distance_to(cc))
			var chance := 0.75 if near < 1.6 else (0.25 if near < 2.6 else 0.05)
			if r.randf() < chance:
				trees[z * N + x] = 1 + r.randi() % 3
	# The middle is always green: the hall and the first street stand there.
	for z in N:
		for x in N:
			if Vector2(x + 0.5, z + 0.5).distance_to(CENTRE) < CLEAR_R - 0.6:
				ter[z * N + x] = Defs.T_GRASS
				trees[z * N + x] = 0
	var isl := {"seed": seed_value, "biome": biome, "ter": ter, "trees": trees, "river": has_river}
	features(isl, PackedInt32Array(), PackedByteArray())
	return isl


## Districts, landmarks and resources for an island's terrain (isl.ter, isl.trees, isl.seed). `owner`
## and `lay` (may be empty) are an existing town's buildings and roads: nothing new goes on them, and a
## district that already has something in it starts open. Sets isl.res, isl.dist, isl.lm (landmark per
## district: [kind, x, z] or [] when none fits) and isl.open (bit k = district k open).
static func features(isl: Dictionary, owner: PackedInt32Array, lay: PackedByteArray) -> void:
	var seed_value := int(isl["seed"])
	var ter: PackedByteArray = isl["ter"]
	var trees: PackedByteArray = isl["trees"]
	var r := Seeded.rng(seed_value, "features")
	var used := PackedByteArray()  # cells nothing new may go on
	used.resize(N * N)
	used.fill(0)
	for i in N * N:
		if (owner.size() == N * N and owner[i] > 0) or (lay.size() == N * N and lay[i] != Defs.L_NONE):
			used[i] = 1
	# Districts: the middle, then three slices of the outside.
	var dist := PackedByteArray()
	dist.resize(N * N)
	var a0 := r.randf() * TAU
	for z in N:
		for x in N:
			var p := Vector2(x + 0.5, z + 0.5) - CENTRE
			if p.length() < CENTRE_R:
				dist[z * N + x] = 0
			else:
				dist[z * N + x] = 1 + int(fposmod(atan2(p.y, p.x) - a0, TAU) / (TAU / DISTRICTS)) % DISTRICTS
	var open := 1
	for i in N * N:
		if used[i] == 1:
			open |= 1 << int(dist[i])
	# Landmarks: the sandiest district gets the lighthouse, the others the clock tower and the big wheel.
	var sand := [0, 0, 0, 0]
	for i in N * N:
		if ter[i] == Defs.T_SAND:
			sand[dist[i]] += 1
	var coast_d := 1
	for k in range(1, DISTRICTS + 1):
		if sand[k] > sand[coast_d]:
			coast_d = k
	var others: Array[String] = ["landmark", "ferris"]
	var sea0 := sea_mask(ter)
	var lm: Array = [[]]
	for k in range(1, DISTRICTS + 1):
		var kind: String = "lighthouse" if k == coast_d else String(others.pop_front())
		var spot := _landmark_spot(ter, dist, used, kind, k, r, sea0, _reach_all(ter, used, dist, (1 << (k + 1)) - 1))
		lm.append([kind, spot.x, spot.y] if spot.x >= 0 else [])
		if spot.x >= 0:
			var s := Defs.size_of(kind)
			for dz in s:
				for dx in s:
					used[(spot.y + dz) * N + spot.x + dx] = 1
	# Resources (only where a road from the first street could get to).
	var reach := _reach_all(ter, used)
	var sea := sea_mask(ter)
	var res := PackedByteArray()
	res.resize(N * N)
	res.fill(R_NONE)
	var free_grass := func(x: int, z: int) -> bool:
		return _inside(x, z) and ter[z * N + x] == Defs.T_GRASS and used[z * N + x] == 0 and res[z * N + x] == R_NONE and reach[z * N + x] == 1
	# golden fields: 2-3 patches of 2x2 .. 3x2 (no trees there)
	var fields := 0
	var tries := 0
	var want_fields := 2 + r.randi() % 2
	while fields < want_fields and tries < 80:
		tries += 1
		var ang := r.randf() * TAU
		var c := CENTRE + Vector2(cos(ang), sin(ang)) * r.randf_range(3.6 if fields == 0 else 4.5, 8.0)
		var fx := int(c.x) - 1
		var fz := int(c.y) - 1
		var w := 2 + r.randi() % 2
		var ok := true
		for dz in 2:
			for dx in w:
				ok = ok and free_grass.call(fx + dx, fz + dz) and Vector2(fx + dx + 0.5, fz + dz + 0.5).distance_to(CENTRE) > 3.4
		if not ok:
			continue
		for dz in 2:
			for dx in w:
				res[(fz + dz) * N + fx + dx] = R_FIELD
				trees[(fz + dz) * N + fx + dx] = 0
		fields += 1
	# springs: grass beside the river or a pond (else beside the sea)
	var wet: Array[Vector2i] = []
	var shore: Array[Vector2i] = []
	for z in N:
		for x in N:
			if not free_grass.call(x, z) or Vector2(x + 0.5, z + 0.5).distance_to(CENTRE) < 3.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, z) + d
				var t := ter[n.y * N + n.x] if _inside(n.x, n.y) else Defs.T_WATER
				if t == Defs.T_RIVER or (t == Defs.T_WATER and sea[n.y * N + n.x] == 0):
					wet.append(Vector2i(x, z))
					break
				if t == Defs.T_SAND:
					shore.append(Vector2i(x, z))
					break
	var springs: Array = Seeded.shuffled(r, wet if not wet.is_empty() else shore)
	for k in mini(1 + r.randi() % 2, springs.size()):
		var sp: Vector2i = springs[k]
		res[sp.y * N + sp.x] = R_SPRING
		trees[sp.y * N + sp.x] = 0
	# breezy hilltops: grass right beside the rocks
	var breezy: Array[Vector2i] = []
	for z in N:
		for x in N:
			if not free_grass.call(x, z):
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n2: Vector2i = Vector2i(x, z) + d
				if _inside(n2.x, n2.y) and ter[n2.y * N + n2.x] == Defs.T_ROCK:
					breezy.append(Vector2i(x, z))
					break
	var bl: Array = Seeded.shuffled(r, breezy)
	var nb := 0
	for c2 in bl:
		var cb: Vector2i = c2
		var far := true
		for z2 in range(cb.y - 3, cb.y + 4):
			for x2 in range(cb.x - 3, cb.x + 4):
				if _inside(x2, z2) and res[z2 * N + x2] == R_BREEZE:
					far = false
		if far:
			res[cb.y * N + cb.x] = R_BREEZE
			trees[cb.y * N + cb.x] = 0
			nb += 1
			if nb >= 2:
				break
	# the heart of the woods: a thick tree cell with trees all round
	var hearts: Array[Vector2i] = []
	for z in N:
		for x in N:
			var i := z * N + x
			if ter[i] != Defs.T_GRASS or trees[i] < 2 or used[i] == 1 or res[i] != R_NONE:
				continue
			var around := 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n3: Vector2i = Vector2i(x, z) + d
				if _inside(n3.x, n3.y) and trees[n3.y * N + n3.x] > 0:
					around += 1
			if around >= 3:
				hearts.append(Vector2i(x, z))
	var hl: Array = Seeded.shuffled(r, hearts)
	var nw := 0
	for c3 in hl:
		var cw: Vector2i = c3
		var far2 := true
		for z3 in range(cw.y - 4, cw.y + 5):
			for x3 in range(cw.x - 4, cw.x + 5):
				if _inside(x3, z3) and res[z3 * N + x3] == R_WOOD:
					far2 = false
		if far2:
			res[cw.y * N + cw.x] = R_WOOD
			nw += 1
			if nw >= 2:
				break
	if nw == 0:
		# no thick woods: plant a little wood (a cell with trees round it) somewhere out of town
		var spots: Array = []
		for z4 in N:
			for x4 in N:
				if free_grass.call(x4, z4) and Vector2(x4 + 0.5, z4 + 0.5).distance_to(CENTRE) > 4.8:
					spots.append(Vector2i(x4, z4))
		for c4 in Seeded.shuffled(r, spots):
			var cw2: Vector2i = c4
			res[cw2.y * N + cw2.x] = R_WOOD
			trees[cw2.y * N + cw2.x] = 3
			for d4 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n4: Vector2i = cw2 + d4
				if free_grass.call(n4.x, n4.y) and r.randf() < 0.7:
					trees[n4.y * N + n4.x] = 1 + r.randi() % 3
			break
	isl["res"] = res
	isl["dist"] = dist
	isl["lm"] = lm
	isl["open"] = open
	isl["trees"] = trees


## Cells a road could get to from the first street (all districts open), avoiding `used` cells
## (except roads, which are already roads).
static func _reach_all(ter: PackedByteArray, used: PackedByteArray, dist := PackedByteArray(), mask := 0xFF) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(N * N)
	out.fill(0)
	var q: Array[Vector2i] = []
	for x in range(STREET_X[0], STREET_X[1] + 1):
		out[STREET_Z * N + x] = 1
		q.append(Vector2i(x, STREET_Z))
	var head := 0
	while head < q.size():
		var c := q[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not _inside(n.x, n.y) or out[n.y * N + n.x] == 1:
				continue
			var i := n.y * N + n.x
			if _roadable_ter(ter[i]) and used[i] == 0 and (dist.is_empty() or (mask >> int(dist[i])) & 1 == 1):
				out[i] = 1
				q.append(n)
	return out


static func _inside(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < N and z < N


## 1 for the sea round the island (water joined to the edge of the board), 0 for land and ponds.
static func sea_mask(ter: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(N * N)
	out.fill(0)
	var q: Array[Vector2i] = []
	for i in N:
		for c in [Vector2i(i, 0), Vector2i(i, N - 1), Vector2i(0, i), Vector2i(N - 1, i)]:
			var cv: Vector2i = c
			if ter[cv.y * N + cv.x] == Defs.T_WATER and out[cv.y * N + cv.x] == 0:
				out[cv.y * N + cv.x] = 1
				q.append(cv)
	var head := 0
	while head < q.size():
		var cur := q[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if _inside(n.x, n.y) and out[n.y * N + n.x] == 0 and ter[n.y * N + n.x] == Defs.T_WATER:
				out[n.y * N + n.x] = 1
				q.append(n)
	return out


## A good landmark spot inside district k: fits on flat land, far out (but not on the beach edge for
## the big ones), the lighthouse right by the sea.
static func _landmark_spot(ter: PackedByteArray, dist: PackedByteArray, used: PackedByteArray, kind: String, k: int,
		r: RandomNumberGenerator, sea: PackedByteArray, reach: PackedByteArray) -> Vector2i:
	var s := Defs.size_of(kind)
	var best := Vector2i(-1, -1)
	var bs := -INF
	for z in N:
		for x in N:
			var ok := true
			var coast := false
			for dz in s:
				for dx in s:
					var cx := x + dx
					var cz := z + dz
					if not _inside(cx, cz):
						ok = false
						continue
					var i := cz * N + cx
					var t := ter[i]
					ok = ok and (t == Defs.T_GRASS or t == Defs.T_SAND) and int(dist[i]) == k and used[i] == 0
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var n: Vector2i = Vector2i(cx, cz) + d
						if not _inside(n.x, n.y) or sea[n.y * N + n.x] == 1:
							coast = true
			if not ok or (kind == "lighthouse" and not coast):
				continue
			# a drivable cell beside it (the crane must reach it)
			var side := false
			for c in _ring(x, z, s):
				if _inside(c.x, c.y) and reach[c.y * N + c.x] == 1:
					side = true
			if not side:
				continue
			var dc := Vector2(x + s * 0.5, z + s * 0.5).distance_to(CENTRE)
			var score := dc + r.randf() * 1.5
			if kind != "lighthouse":
				score = -absf(dc - 7.2) + r.randf() * 1.5
			if score > bs:
				bs = score
				best = Vector2i(x, z)
	return best


static func _ring(x: int, z: int, s: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k in s:
		out.append(Vector2i(x + k, z + s))
		out.append(Vector2i(x + s, z + k))
		out.append(Vector2i(x + k, z - 1))
		out.append(Vector2i(x - 1, z + k))
	return out


## Can a road go on this terrain (grass, sand, or a bridge over the river)?
static func _roadable_ter(t: int) -> bool:
	return t == Defs.T_GRASS or t == Defs.T_SAND or t == Defs.T_RIVER


## A short name for a district's look (story cards and telemetry): what most of it is.
static func district_look(isl: Dictionary, k: int) -> String:
	var ter: PackedByteArray = isl["ter"]
	var dist: PackedByteArray = isl["dist"]
	var trees: PackedByteArray = isl["trees"]
	var n := {"beach": 0, "woods": 0, "hills": 0, "river": 0}
	for i in N * N:
		if int(dist[i]) != k:
			continue
		match int(ter[i]):
			Defs.T_SAND: n["beach"] += 1
			Defs.T_ROCK: n["hills"] += 1
			Defs.T_RIVER: n["river"] += 1
		if trees[i] > 0:
			n["woods"] += 1
	if int(n["river"]) >= 3:
		return "river"
	if int(n["hills"]) >= 4:
		return "hills"
	if int(n["woods"]) >= 10:
		return "woods"
	return "beach"


# --- The validator --------------------------------------------------------------------------------------

## Problems with an island (empty = good). Uses town.gd's own rules (a scratch Town).
static func check(isl: Dictionary) -> Array:
	var TownScript: GDScript = load("res://games/tiny_town_tycoon/town.gd")
	var t = TownScript.new()
	t.apply_island(isl)
	t.starter_town()
	var why: Array = []
	var land := 0
	for i in N * N:
		land += 1 if t.is_land(i % N, i / N) else 0
	if land < 180:
		why.append("only %d land cells" % land)
	# the hall and the street stood up in the middle
	var halls: Array = t.of_kind("hall", true)
	if halls.size() != 1 or int(halls[0]["x"]) != HALL.x or int(halls[0]["z"]) != HALL.y:
		why.append("no town hall in the middle")
	for c in t.footprint("hall", HALL.x, HALL.y):
		if t.terrain(c.x, c.y) != Defs.T_GRASS:
			why.append("the hall stands on %d" % t.terrain(c.x, c.y))
	for x in range(STREET_X[0], STREET_X[1] + 1):
		if not t.has_road(x, STREET_Z):
			why.append("the first street is broken at %d" % x)
	# the practice road: three free cells on from a street end
	var practice := false
	for x in [STREET_X[0], STREET_X[1]]:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := 0
			for k in range(1, 4):
				var c: Vector2i = Vector2i(x, STREET_Z) + d * k
				if t.can_place("road", c.x, c.y) == "" and not t.has_road(c.x, c.y):
					n += 1
				else:
					break
			practice = practice or n == 3
	if not practice:
		why.append("no room for the practice road")
	# room for houses in the open middle
	var spots := 0
	for z in N:
		for x in N:
			if t.can_place("house", x, z) == "" and t.reach(Vector2i(x, z), 1):
				spots += 1
	if spots < 40:
		why.append("only %d house spots in the middle" % spots)
	# every district: reachable, has room, has its landmark; opening them all in turn
	var lm: Array = isl["lm"]
	for k in range(1, DISTRICTS + 1):
		t.open_mask |= 1 << k
		t.version += 1
		var room := 0
		var cells := 0
		for z in N:
			for x in N:
				if t.district(x, z) != k:
					continue
				if t.is_land(x, z):
					cells += 1
				if t.can_place("house", x, z) == "" and t.reach(Vector2i(x, z), 1):
					room += 1
		if cells < 12:
			why.append("district %d is tiny (%d cells)" % [k, cells])
		elif room < 8:
			why.append("district %d: only %d reachable house spots" % [k, room])
		var l: Array = lm[k] if k < lm.size() else []
		if l.is_empty():
			why.append("district %d has no landmark" % k)
			continue
		var kind := String(l[0])
		if t.can_place(kind, int(l[1]), int(l[2])) != "":
			why.append("district %d landmark %s doesn't fit: %s" % [k, kind, t.can_place(kind, int(l[1]), int(l[2]))])
		elif not t.reach(Vector2i(int(l[1]), int(l[2])), Defs.size_of(kind)):
			why.append("district %d landmark %s can't be reached" % [k, kind])
		if t.district(int(l[1]), int(l[2])) != k:
			why.append("district %d landmark is in district %d" % [k, t.district(int(l[1]), int(l[2]))])
	var seen := {}
	for l2 in lm:
		if not (l2 as Array).is_empty():
			seen[String(l2[0])] = true
	if seen.size() != DISTRICTS:
		why.append("landmarks repeat: %s" % str(seen.keys()))
	# every resource has a reachable spot for its building (with everything open)
	for rk in RES_KIND:
		var kind2 := String(RES_KIND[rk])
		var found := 0
		for i in N * N:
			if int(t.res[i]) == int(rk):
				found += 1
				if t.res_spot(kind2, Vector2i(i % N, i / N)).x < 0:
					why.append("%s at %d,%d has no reachable spot for a %s" % [_res_name(int(rk)), i % N, i / N, kind2])
		if found == 0 and (int(rk) != R_BREEZE or t.ter.count(Defs.T_ROCK) > 0):
			why.append("no %s on the island" % _res_name(int(rk)))
	if t.ter.count(Defs.T_RIVER) > 0 and not bool(isl.get("river", false)):
		why.append("river cells but no river")
	return why


static func _res_name(rk: int) -> String:
	return ["", "field", "spring", "breeze", "wood"][clampi(rk, 0, 4)]
