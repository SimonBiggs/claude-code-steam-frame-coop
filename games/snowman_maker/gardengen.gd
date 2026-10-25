extends RefCounted
## SNOWMAN MAKER garden generator: a seeded snow day = where the boxes stand (a carrot box + one box
## per hat of the chapter), pine trees in the garden (chapter 2+), icy patches where snowballs slide
## (3+), deep drifts where they grow fast (4+), where new snowballs pop up, where the visitors stand,
## and the list of visitors' wishes. The same seed and chapter always give the same garden, so every
## machine builds it itself from {seed, chapter}.
## check() is the validator (tests/snowman_maker_garden_test.gd runs it over many seeds): everything is
## inside the garden, nothing overlaps, every box / spawn / visitor spot / the build circle can be
## walked to from every player start, every spawn's snowball can be rolled (at full size) to the build
## circle, the VR builder can reach every box from where they stand, wishes only ask for hats in boxes.

const Seeded := preload("res://core/seeded.gd")
const Story := preload("res://games/snowman_maker/story.gd")

const ARENA := 9.0
const YARD := Vector3.ZERO
const YARD_R := 1.8
const VR_START := Vector3(0.0, 0.0, 2.3)
const SIGN_POS := Vector3(2.9, 0.0, -1.2)
const BALL_MAX := 0.42
const BODY_R := 0.32
const TREE_R := 0.5  ## a garden pine's bump radius (trunk + lowest branches)
const BOX_R := 0.4  ## a box's footprint radius
const VR_REACH := 2.1  ## boxes this close to where the VR builder stands (arm + a step)
const SPAWNS := 12
const WISHES := 16
const MAX_SLOTS := 8
const CELL := 0.25


static func features(chapter: int) -> Dictionary:
	return {"trees": chapter >= 1, "ice": chapter >= 2, "drifts": chapter >= 3}


## Where player `slot` starts (the old ring, kept so every machine agrees without the garden).
static func player_start(slot: int) -> Vector3:
	var ang := slot * 1.1
	return Vector3(sin(ang), 0.0, -cos(ang)) * 4.0


## A whole garden: {seed, chapter, boxes: [{pos, kind}], trees: [Vector3], ice: [[Vector3, r]],
## drifts: [[Vector3, r]], spawns: [Vector3], visitor: Vector3, wishes: [[hat, visitor index]]}.
static func garden(seed_value: int, chapter: int) -> Dictionary:
	var r := Seeded.rng(seed_value, "garden%d" % chapter)
	var feats := features(chapter)
	var hats: Array = Story.chapter(chapter).hats
	var g := {"seed": seed_value, "chapter": chapter, "boxes": [], "trees": [], "ice": [], "drifts": [],
		"spawns": [], "visitor": Vector3(-2.7, 0.0, -0.9), "wishes": []}
	# Boxes: in front of the VR builder, round the near side of the build circle.
	var kinds: Array = [Story.CARROT]
	kinds.append_array(hats)
	kinds = [kinds[0]] + Seeded.shuffled(r, kinds.slice(1))
	var boxes: Array = []
	for layout in 30:  # a whole layout at a time (four boxes don't always fit one by one)
		boxes = []
		for k in kinds:
			for attempt in 40:
				var p := Vector3(r.randf_range(-2.4, 2.4), 0.0, r.randf_range(0.9, 3.4))
				if _box_ok(p, boxes):
					boxes.append({"pos": p, "kind": int(k)})
					break
		if boxes.size() == kinds.size():
			break
	if boxes.size() != kinds.size():  # the fallback layout (always fine: the validator proves it)
		boxes = []
		var fb: Array = [Vector3(-1.0, 0.0, 1.5), Vector3(1.0, 0.0, 1.5), Vector3(-1.8, 0.0, 2.6), Vector3(1.8, 0.0, 2.6)]
		for i in kinds.size():
			boxes.append({"pos": fb[i], "kind": int(kinds[i])})
	g.boxes = boxes
	# Visitors stand on the far side of the circle, where the VR builder and the TV cameras see them.
	for attempt in 40:
		var a := r.randf_range(-PI * 0.85, -PI * 0.15)
		var p := Vector3(cos(a), 0.0, sin(a)) * r.randf_range(2.6, 3.2)
		if p.distance_to(SIGN_POS) > 1.4:
			g.visitor = p
			break
	# Trees.
	var trees: Array = []
	if feats.trees:
		var want := 3 + r.randi() % 3 + (1 if chapter >= 3 else 0)
		for attempt in 200:
			if trees.size() >= want:
				break
			var a := r.randf() * TAU
			var p := Vector3(cos(a), 0.0, sin(a)) * r.randf_range(3.7, ARENA - 1.6)
			if _tree_ok(p, g, trees):
				trees.append(p)
	g.trees = trees
	# Icy patches, then deep drifts (never on the circle, a box, a tree, the visitor, each other).
	var patches: Array = []
	for kind in ["ice", "drifts"]:
		if not feats[kind]:
			continue
		var want := 2 + (r.randi() % 2 if kind == "ice" else 0)
		var made: Array = []
		for attempt in 120:
			if made.size() >= want:
				break
			var rad := r.randf_range(1.1, 1.7) if kind == "ice" else r.randf_range(1.0, 1.4)
			var a := r.randf() * TAU
			var p := Vector3(cos(a), 0.0, sin(a)) * r.randf_range(YARD_R + rad + 0.5, ARENA - rad - 0.4)
			if _patch_ok(p, rad, g, trees, patches):
				made.append([p, rad])
				patches.append([p, rad])
		g[kind] = made
	# Where new snowballs pop up.
	var spawns: Array = []
	for attempt in 300:
		if spawns.size() >= SPAWNS:
			break
		var a := r.randf() * TAU
		var p := Vector3(cos(a), 0.0, sin(a)) * r.randf_range(3.2, ARENA - 1.0)
		if _spawn_ok(p, g, trees, spawns):
			spawns.append(p)
	g.spawns = spawns
	# Wishes: hats of this chapter, never the same visitor twice in a row.
	var wishes: Array = []
	var last := -1
	for i in WISHES:
		var v := r.randi() % Story.VISITORS.size()
		if v == last:
			v = (v + 1) % Story.VISITORS.size()
		last = v
		wishes.append([int(Seeded.pick(r, hats)), v])
	g.wishes = wishes
	return g


static func _box_ok(p: Vector3, boxes: Array) -> bool:
	if _flat(p - VR_START) < 1.0 or _flat(p - VR_START) > VR_REACH:
		return false
	if _flat(p - YARD) < YARD_R - 0.1:
		return false
	for b in boxes:
		if _flat(p - (b.pos as Vector3)) < 1.15:
			return false
	return true


static func _tree_ok(p: Vector3, g: Dictionary, trees: Array) -> bool:
	if _flat(p - VR_START) < 2.2 or _flat(p - SIGN_POS) < 1.6 or _flat(p - (g.visitor as Vector3)) < 1.6:
		return false
	for b in g.boxes:
		if _flat(p - (b.pos as Vector3)) < 1.7:
			return false
	for s in MAX_SLOTS:
		if _flat(p - player_start(s)) < 1.3:
			return false
	for t in trees:
		if _flat(p - (t as Vector3)) < 2.4:
			return false
	return true


static func _patch_ok(p: Vector3, rad: float, g: Dictionary, trees: Array, patches: Array) -> bool:
	if _flat(p - YARD) < YARD_R + rad + 0.3 or _flat(p - VR_START) < rad + 1.0 or _flat(p - (g.visitor as Vector3)) < rad + 0.8:
		return false
	for b in g.boxes:
		if _flat(p - (b.pos as Vector3)) < rad + 0.9:
			return false
	for t in trees:
		if _flat(p - (t as Vector3)) < rad + TREE_R + 0.3:
			return false
	for q in patches:
		if _flat(p - (q[0] as Vector3)) < rad + float(q[1]) + 0.4:
			return false
	return true


static func _spawn_ok(p: Vector3, g: Dictionary, trees: Array, spawns: Array) -> bool:
	if _flat(p - VR_START) < 1.6 or _flat(p - (g.visitor as Vector3)) < 1.0:
		return false
	for b in g.boxes:
		if _flat(p - (b.pos as Vector3)) < 1.1:
			return false
	for t in trees:
		if _flat(p - (t as Vector3)) < TREE_R + BALL_MAX + 0.45:
			return false
	for q in spawns:
		if _flat(p - (q as Vector3)) < 1.2:
			return false
	return true


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


## True when a body of radius `clear` at p touches no tree and stays in the garden.
static func free_at(g: Dictionary, p: Vector3, clear: float) -> bool:
	if _flat(p) > ARENA - clear:
		return false
	for t in g.trees:
		if _flat(p - (t as Vector3)) < TREE_R + clear:
			return false
	return true


## Which patch kind is under p: "ice", "drifts" or "".
static func ground_at(g: Dictionary, p: Vector3) -> String:
	for kind in ["ice", "drifts"]:
		for q in g.get(kind, []):
			if _flat(p - (q[0] as Vector3)) < float(q[1]):
				return kind
	return ""


## Cells reachable (flood fill on a CELL grid) from `from` for a body of radius `clear`.
static func reach_map(g: Dictionary, from: Vector3, clear: float) -> Dictionary:
	var n := int(ceil(ARENA / CELL))
	var seen := {}
	var start := Vector2i(roundi(from.x / CELL), roundi(from.z / CELL))
	if not free_at(g, from, clear):
		# Start just off a blocked point: the nearest free cell.
		var best := Vector2i(999, 999)
		for dx in range(-4, 5):
			for dz in range(-4, 5):
				var c := start + Vector2i(dx, dz)
				if free_at(g, Vector3(c.x * CELL, 0.0, c.y * CELL), clear) and (best.x == 999 or Vector2(dx, dz).length() < Vector2(best - start).length()):
					best = c
		if best.x == 999:
			return seen
		start = best
	var queue: Array[Vector2i] = [start]
	seen[start] = true
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = c + d
			if absi(nb.x) > n or absi(nb.y) > n or seen.has(nb):
				continue
			if free_at(g, Vector3(nb.x * CELL, 0.0, nb.y * CELL), clear):
				seen[nb] = true
				queue.append(nb)
	return seen


static func _reached(map: Dictionary, p: Vector3) -> bool:
	var c := Vector2i(roundi(p.x / CELL), roundi(p.z / CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if map.has(c + Vector2i(dx, dz)):
				return true
	return false


## The validator: an Array of reasons (empty when the garden is fine).
static func check(g: Dictionary) -> Array:
	var out: Array = []
	var chap := int(g.get("chapter", 0))
	var feats := features(chap)
	var hats: Array = Story.chapter(chap).hats
	var boxes: Array = g.get("boxes", [])
	# Boxes: one carrot box and one per hat, all where the VR builder reaches them, apart, off the circle.
	var kinds := {}
	for b in boxes:
		var p: Vector3 = b.pos
		kinds[int(b.kind)] = true
		if _flat(p - VR_START) > VR_REACH + 0.01:
			out.append("box %d too far from the VR builder" % int(b.kind))
		if _flat(p - VR_START) < 0.99:
			out.append("box %d on the VR builder's feet" % int(b.kind))
		if _flat(p) < YARD_R - 0.11:
			out.append("box %d inside the build circle" % int(b.kind))
		for o in boxes:
			if o != b and _flat(p - (o.pos as Vector3)) < 1.0:
				out.append("boxes %d and %d overlap" % [int(b.kind), int(o.kind)])
	if not kinds.has(Story.CARROT):
		out.append("no carrot box")
	for h in hats:
		if not kinds.has(int(h)):
			out.append("no box for hat %d" % int(h))
	if boxes.size() != hats.size() + 1:
		out.append("%d boxes for %d hats" % [boxes.size(), hats.size()])
	# Features only in their chapters.
	for kind in ["trees", "ice", "drifts"]:
		if not feats[kind] and not (g.get(kind, []) as Array).is_empty():
			out.append("%s before their chapter" % kind)
		if feats[kind] and (g.get(kind, []) as Array).is_empty():
			out.append("no %s in a chapter that has them" % kind)
	# Patches never cover the circle, a box, a tree or each other.
	var patches: Array = (g.get("ice", []) as Array) + (g.get("drifts", []) as Array)
	for i in patches.size():
		var q: Array = patches[i]
		var p: Vector3 = q[0]
		var rad := float(q[1])
		if _flat(p) < YARD_R + rad:
			out.append("a patch covers the build circle")
		if _flat(p) + rad > ARENA:
			out.append("a patch leaves the garden")
		for b in boxes:
			if _flat(p - (b.pos as Vector3)) < rad + BOX_R:
				out.append("a patch covers a box")
		for t in g.trees:
			if _flat(p - (t as Vector3)) < rad + TREE_R:
				out.append("a patch covers a tree")
		for j in range(i + 1, patches.size()):
			if _flat(p - (patches[j][0] as Vector3)) < rad + float(patches[j][1]):
				out.append("patches overlap")
	# Trees: off the circle, the boxes, the VR builder, the sign, the visitor, the player starts.
	for t in g.trees:
		var p: Vector3 = t
		if _flat(p) < YARD_R + TREE_R + 0.5 or _flat(p) > ARENA - TREE_R:
			out.append("a tree in the circle or out of the garden")
		if _flat(p - VR_START) < 1.5 or _flat(p - SIGN_POS) < 1.0 or _flat(p - (g.visitor as Vector3)) < 1.0:
			out.append("a tree on the VR builder, sign or visitor")
		for b in boxes:
			if _flat(p - (b.pos as Vector3)) < TREE_R + BOX_R + 0.3:
				out.append("a tree on a box")
	for s in MAX_SLOTS:
		if not free_at(g, player_start(s), BODY_R):
			out.append("player %d starts in a tree" % s)
	# Spawns: enough, apart, free of trees.
	var spawns: Array = g.get("spawns", [])
	if spawns.size() < 6:
		out.append("only %d snowball spawns" % spawns.size())
	for p in spawns:
		if not free_at(g, p, BALL_MAX + 0.05):
			out.append("a snowball spawns in a tree")
	# Reachability: players walk to everything from every start; big snowballs roll to the circle.
	var walk := reach_map(g, player_start(0), BODY_R)
	for s in MAX_SLOTS:
		if not _reached(walk, player_start(s)):
			out.append("player %d can't reach the others" % s)
	for b in boxes:
		if not _reached(walk, b.pos):
			out.append("box %d can't be walked to" % int(b.kind))
	if not _reached(walk, YARD) or not _reached(walk, g.visitor):
		out.append("the circle or the visitor can't be walked to")
	var roll := reach_map(g, YARD, BALL_MAX + 0.08)
	for p in spawns:
		if not _reached(roll, p):
			out.append("a snowball at (%.1f, %.1f) can't be rolled to the circle" % [p.x, p.z])
		if not _reached(walk, p):
			out.append("a spawn can't be walked to")
	# Wishes: only hats that are in the boxes.
	var wishes: Array = g.get("wishes", [])
	if wishes.size() < 4:
		out.append("too few wishes")
	for w in wishes:
		if not hats.has(int(w[0])):
			out.append("a wish for a hat not in the boxes")
		if int(w[1]) < 0 or int(w[1]) >= Story.VISITORS.size():
			out.append("a wish from nobody")
	return out
