extends RefCounted
## TREASURE DIG islands from a seed: where the palms and rocks stand, where every treasure of the round
## is buried and in what order (the DECK: coins, gems, silly boots and the three MAP PIECES), and where
## the RELIC waits under the big X. The island kind (story.gd ISLANDS) sets the mix; the level (islands
## done) adds boots and pushes the map pieces deeper into the deck. Same (seed, spec) -> same island on
## every machine (the host sends {seed, kind, level}). check() is the validator
## (tests/treasure_dig_gen_test.gd). Positions are beach-local (main.gd: sand radius ISLAND, walkable R).

const Seeded := preload("res://core/seeded.gd")
const Story := preload("res://games/treasure_dig/story.gd")

const ISLAND := 7.0
const R := 6.2
const CHEST_CLEAR := 2.3  ## nothing buried this close to the chest (diggers bank there)
const SPOT_GAP := 1.8
const DECK := 40  ## treasures in a round's pile (more than any round digs)
const SPOTS := 24  ## distinct burial spots (reused in turn: a spot is free again once dug)
const HIDDEN := 6  ## main.gd buries this many at a time


## spec: {kind: island id, level: islands done}. Returns {seed, kind, level, palms: [Vector3],
## rocks: [[Vector3, radius]], spots: [Vector3], deck: [kinds], relic: Vector3, map_at: [deck indices]}.
static func generate(seed_value: int, spec: Dictionary) -> Dictionary:
	var r := Seeded.rng(seed_value, "island")
	var isl: Dictionary = Story.island(Story.island_index(String(spec.get("kind", "sunny"))))
	var level := maxi(0, int(spec.get("level", 0)))
	var palms: Array = []
	var n_palms := int(isl.palms)
	var a0 := r.randf() * TAU
	for k in n_palms:
		var a := a0 + k * TAU / n_palms + r.randf_range(-0.2, 0.2)
		palms.append(Vector3(cos(a), 0.0, sin(a)) * r.randf_range(R + 0.15, ISLAND - 0.3))
	var rocks: Array = []
	for k in r.randi_range(2, 4):
		var a := r.randf() * TAU
		rocks.append([Vector3(cos(a), 0.0, sin(a)) * r.randf_range(3.0, R - 0.6), r.randf_range(0.35, 0.6)])
	# Burial spots: on the sand, away from the chest, the rocks and each other.
	var spots: Array = []
	var tries := 0
	while spots.size() < SPOTS and tries < 2000:
		tries += 1
		var a := r.randf() * TAU
		var p := Vector3(cos(a), 0.0, sin(a)) * sqrt(r.randf_range(CHEST_CLEAR * CHEST_CLEAR, (R - 0.4) * (R - 0.4)))
		if _free(p, spots, rocks, SPOT_GAP):
			spots.append(p)
	# The relic: its own spot, far from the chest.
	var relic := Vector3.ZERO
	for t in 400:
		var a := r.randf() * TAU
		var p := Vector3(cos(a), 0.0, sin(a)) * r.randf_range(3.5, R - 0.6)
		if _free(p, [], rocks, 0.0):
			relic = p
			break
	# The deck: the island's mix, more boots with every island, three map pieces (deeper on later islands).
	var dr := Seeded.rng(seed_value, "deck")
	var mix: Array = isl.mix
	var boots := minf(0.35, float(mix[2]) + 0.015 * level)
	var deck: Array = []  # exact counts, shuffled (no unlucky all-boots rounds)
	var n_boot := roundi(boots * DECK)
	var n_gem := roundi(float(mix[1]) / (float(mix[0]) + float(mix[1])) * (DECK - n_boot))
	for k in DECK:
		deck.append(Story.KIND_BOOT if k < n_boot else (Story.KIND_GEM if k < n_boot + n_gem else Story.KIND_COIN))
	deck = Seeded.shuffled(dr, deck)
	var map_at: Array = []
	var spread := 4 + mini(level, 4)  # later islands: the pieces further apart (more digging between them)
	var at := mini(level, 6) + dr.randi_range(0, 2)  # later islands: the first piece deeper in the pile
	for k in Story.MAP_PIECES:
		map_at.append(at)
		deck[at] = Story.KIND_MAP
		at += dr.randi_range(2, spread)
	return {"seed": seed_value, "kind": String(isl.id), "level": level, "palms": palms, "rocks": rocks, "spots": spots,
		"deck": deck, "relic": relic, "map_at": map_at}


static func _free(p: Vector3, spots: Array, rocks: Array, gap: float) -> bool:
	for s in spots:
		if (s as Vector3).distance_to(p) < gap:
			return false
	for rk in rocks:
		if (rk[0] as Vector3).distance_to(p) < float(rk[1]) + 0.8:
			return false
	return true


## The validator: reasons this island is unfair or broken (empty when fine).
static func check(g: Dictionary) -> Array:
	var why: Array = []
	var spots: Array = g.get("spots", [])
	if spots.size() < HIDDEN * 2:
		why.append("only %d burial spots" % spots.size())
	for i in spots.size():
		var p: Vector3 = spots[i]
		var d := Vector2(p.x, p.z).length()
		if d < CHEST_CLEAR - 0.01 or d > R - 0.3:
			why.append("spot %d at %.2f from the middle" % [i, d])
		for j in range(i + 1, spots.size()):
			if p.distance_to(spots[j]) < SPOT_GAP - 0.01:
				why.append("spots %d and %d too close" % [i, j])
		for rk in g.get("rocks", []):
			if (rk[0] as Vector3).distance_to(p) < float(rk[1]) + 0.5:
				why.append("spot %d under a rock" % i)
	var relic: Vector3 = g.get("relic", Vector3.ZERO)
	var rd := Vector2(relic.x, relic.z).length()
	if rd < 3.0 or rd > R - 0.3:
		why.append("the relic at %.2f from the middle" % rd)
	for rk in g.get("rocks", []):
		if (rk[0] as Vector3).distance_to(relic) < float(rk[1]) + 0.5:
			why.append("the relic is under a rock")
	var deck: Array = g.get("deck", [])
	var maps := 0
	var boots := 0
	for k in deck:
		maps += 1 if int(k) == Story.KIND_MAP else 0
		boots += 1 if int(k) == Story.KIND_BOOT else 0
		if int(k) < 0 or int(k) > Story.KIND_MAP:
			why.append("a %d in the deck" % int(k))
	if maps != Story.MAP_PIECES:
		why.append("%d map pieces" % maps)
	var map_at: Array = g.get("map_at", [])
	if map_at.is_empty() or int(map_at[-1]) > 26:
		why.append("the last map piece is too deep (%s)" % str(map_at))
	if boots * 100 > deck.size() * 45:
		why.append("too many boots (%d of %d)" % [boots, deck.size()])
	for p in g.get("palms", []):
		var d := Vector2((p as Vector3).x, (p as Vector3).z).length()
		if d < R or d > ISLAND:
			why.append("a palm at %.2f (in the diggers' way or in the sea)" % d)
	return why
