extends RefCounted
## Where you can walk in an area: a union of walkable capsules / circles / rectangles minus round and
## rectangular blockers (houses, trees, pillars), all on the XZ ground plane. No physics needed:
## the VR rig's move_filter, the TV companions, AI friends and map monsters all slide with slide().
## Walking for real in the play space is never blocked (that's the player's room); the stick only.

var caps: Array = []  # [Vector2 a, Vector2 b, float radius] (a == b: a circle)
var rects: Array = []  # [Rect2]
var blocks: Array = []  # [Vector2 centre, float radius]
var block_rects: Array = []  # [Rect2]
var bounds := Rect2()  # for the mini-map
## Closable blockers (sealed doors, crystal barriers): id -> Rect2 while closed.
var gates := {}


## A walkable circle.
func circle(c: Vector3, r: float) -> void:
	capsule(c, c, r)


## A walkable capsule (a path from a to b, `r` wide each side).
func capsule(a: Vector3, b: Vector3, r: float) -> void:
	caps.append([Vector2(a.x, a.z), Vector2(b.x, b.z), r])
	_grow(Rect2(Vector2(minf(a.x, b.x) - r, minf(a.z, b.z) - r), Vector2(absf(a.x - b.x) + 2.0 * r, absf(a.z - b.z) + 2.0 * r)))


## A chain of capsules through the points.
func path(points: Array, r: float) -> void:
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		capsule(a, b, r)


## A walkable rectangle (x, z from `from` to `to`).
func rect(from: Vector3, to: Vector3) -> void:
	var r := Rect2(Vector2(minf(from.x, to.x), minf(from.z, to.z)), Vector2(absf(to.x - from.x), absf(to.z - from.z)))
	rects.append(r)
	_grow(r)


## A round obstacle.
func block(c: Vector3, r: float) -> void:
	blocks.append([Vector2(c.x, c.z), r])


## A rectangular obstacle centred at c with size (x, z).
func block_box(c: Vector3, size: Vector2) -> void:
	block_rects.append(Rect2(Vector2(c.x, c.z) - size * 0.5, size))


func _grow(r: Rect2) -> void:
	bounds = r if bounds.size == Vector2.ZERO else bounds.merge(r)


## How far `p` is outside the walkable shapes (<= 0 inside; blockers ignored).
func outside(p: Vector2) -> float:
	var best := INF
	for c in caps:
		var a: Vector2 = c[0]
		var b: Vector2 = c[1]
		var r: float = c[2]
		best = minf(best, _seg_dist(p, a, b) - r)
	for rr in rects:
		var q: Rect2 = rr
		var dx := maxf(q.position.x - p.x, p.x - q.end.x)
		var dz := maxf(q.position.y - p.y, p.y - q.end.y)
		var d := maxf(dx, dz) if dx <= 0.0 and dz <= 0.0 else Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length()
		best = minf(best, d)
	return best


## True if a body of radius `margin` fits at p (inside the walkable area, clear of blockers).
func walkable(p: Vector2, margin: float = 0.25) -> bool:
	if outside(p) > -margin:
		return false
	return not blocked(p, margin)


## True if p is inside a blocker (grown by margin).
func blocked(p: Vector2, margin: float = 0.25) -> bool:
	for bb in blocks:
		var c: Vector2 = bb[0]
		var r: float = bb[1]
		if p.distance_to(c) < r + margin:
			return true
	for br in block_rects:
		var q: Rect2 = br
		if q.grow(margin).has_point(p):
			return true
	for g in gates:
		var gr: Rect2 = gates[g]
		if gr.grow(margin).has_point(p):
			return true
	return false


## Close (block) or open a gate: a rectangle centred at c with size (x, z).
func set_gate(id: String, closed: bool, c: Vector3 = Vector3.ZERO, size: Vector2 = Vector2.ONE) -> void:
	if closed:
		gates[id] = Rect2(Vector2(c.x, c.z) - size * 0.5, size)
	else:
		gates.erase(id)


## Move from -> to, sliding along edges. Someone already outside may only move back inwards.
func slide(from: Vector3, to: Vector3, margin: float = 0.25) -> Vector3:
	var f := Vector2(from.x, from.z)
	var t := Vector2(to.x, to.z)
	if walkable(t, margin):
		return to
	if not walkable(f, margin):
		# Outside (walked there for real, or spawned badly): allow moves that get closer to the inside.
		if outside(t) <= outside(f) + 0.0001 and not blocked(t, margin * 0.5):
			return to
		if blocked(f, margin) and not blocked(t, margin):
			return to
		var o0 := outside(f)
		var o1 := outside(t)
		if o1 < o0:
			return to
		return from
	var tx := Vector2(t.x, f.y)
	if walkable(tx, margin):
		return Vector3(tx.x, to.y, tx.y)
	var tz := Vector2(f.x, t.y)
	if walkable(tz, margin):
		return Vector3(tz.x, to.y, tz.y)
	return from


## The nearest walkable point to p (searching outwards); p itself if it is fine.
func nearest(p: Vector3, margin: float = 0.3) -> Vector3:
	var v := Vector2(p.x, p.z)
	if walkable(v, margin):
		return p
	for ring in range(1, 30):
		var rad := ring * 0.35
		for k in 16:
			var a := k * TAU / 16.0
			var q := v + Vector2(cos(a), sin(a)) * rad
			if walkable(q, margin):
				return Vector3(q.x, p.y, q.y)
	return p


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
