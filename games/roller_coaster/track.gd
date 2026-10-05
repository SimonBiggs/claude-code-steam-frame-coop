extends RefCounted
## COASTER CREW track maths (park-local coordinates, 1 unit = 1 m for the riders; the table top is y = 0).
## The track is a list of pieces [type, extra_height] that start at the station end. build() turns it
## into a polyline (points + up vectors + distances; the same data a Curve3D would bake) that always
## closes back into the station, so a ride never fails. Every machine builds the same polyline from the
## same piece list, so the TV only needs the list (state store) and the train's distance (snapshot).

const MeshKit := preload("res://core/mesh_kit.gd")

const TYPES: Array[String] = ["straight", "up", "down", "left", "right", "loop", "splash"]
const STATION_Y := 1.0
const STATION_LEN := 5.0
const STATION_X := -3.5
const STATION_Z := 5.6  # the station runs along +X, on the builder's side of the table
const MIN_Y := 0.6
const MAX_Y := 7.0
const WATER_Y := 0.15
const TABLE_R := 12.0
const FIT_R := 11.3
const FLOOR_Y := -13.5  # the living-room floor (builder.gd: TABLE_H * WS)  # piece ends must stay on the table
const STEP := 0.35  # polyline spacing
const GAUGE := 0.42  # half the distance between the rails
const TURN_R := 1.9
const LOOP_R := 1.5

const RAIL_COL := Color(0.92, 0.22, 0.25)
const TIE_COL := Color(0.38, 0.3, 0.26)
const POST_COL := Color(0.95, 0.95, 0.92)
const STATION_COL := Color(0.98, 0.78, 0.3)


static func fwd(yaw: float) -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


## The station's first point (where the closing track arrives) and its end (where pieces start).
static func station_start() -> Vector3:
	return Vector3(STATION_X - STATION_LEN * 0.5, STATION_Y, STATION_Z)


static func station_end() -> Vector3:
	return Vector3(STATION_X + STATION_LEN * 0.5, STATION_Y, STATION_Z)


## Length a piece adds along the ground (for the ghost and the fit test).
static func piece_len(t: String) -> float:
	match t:
		"up", "down":
			return 2.8
		"left", "right":
			return TURN_R * PI * 0.5
		"loop":
			return 2.8
		"splash":
			return 3.4
	return 2.0


## Where a piece ends: [pos, yaw] from a start [pos, yaw].
static func piece_end(t: String, h: float, pos: Vector3, yaw: float) -> Array:
	var r := _piece(t, h, pos, yaw, null)
	return r


## The end of a whole piece list: [pos, yaw].
static func end_of(pieces: Array) -> Array:
	var pos := station_end()
	var yaw := 0.0
	for p in pieces:
		var a: Array = p
		var r := piece_end(String(a[0]), float(a[1]), pos, yaw)
		pos = r[0]
		yaw = r[1]
	return [pos, yaw]


## True when a piece added at [pos, yaw] stays on the table.
static func fits(t: String, h: float, pos: Vector3, yaw: float) -> bool:
	var r := piece_end(t, h, pos, yaw)
	var e: Vector3 = r[0]
	if t == "left" or t == "right":
		return Vector2(e.x, e.z).length() < TABLE_R + 1.5  # turns may hang over the edge: never stuck
	var mid := (pos + e) * 0.5
	return Vector2(e.x, e.z).length() < FIT_R and Vector2(mid.x, mid.z).length() < FIT_R + 0.3


## Walk one piece. If `out` (a Dictionary with pts/ups arrays) is given, append its samples (the start
## point excluded). Returns [end_pos, end_yaw].
static func _piece(t: String, h: float, pos: Vector3, yaw: float, out) -> Array:
	var y0 := pos.y
	var y1 := y0
	match t:
		"up":
			y1 = y0 + 2.2
		"down":
			y1 = y0 - 2.2
		"splash":
			y1 = MIN_Y
	y1 = clampf(y1 + h, MIN_Y, MAX_Y)
	if t == "splash":
		y1 = MIN_Y
	var length := piece_len(t)
	var turn := 0.0
	if t == "left":
		turn = PI * 0.5
	elif t == "right":
		turn = -PI * 0.5
	var n := maxi(2, int(ceil(length / STEP)))
	if t == "loop":
		n = 40
	var p := pos
	var cur_yaw := yaw
	var base := pos
	for i in range(1, n + 1):
		var k := float(i) / n
		var up := Vector3.UP
		if t == "loop":
			# A vertical loop drifting sideways a little so the exit misses the entry.
			var a := k * TAU
			var f := fwd(yaw)
			var side := f.cross(Vector3.UP)
			var along := length * k + LOOP_R * sin(a) * 0.95
			p = base + f * along + Vector3.UP * (LOOP_R * (1.0 - cos(a))) + side * (0.9 * (k - sin(a) / TAU))
			p.y += lerpf(y0, y1, smoothstep(0.0, 1.0, k)) - y0
			up = (Vector3.UP * cos(a) - f * sin(a)).normalized()
		else:
			var ds := length / n
			var mid_yaw := cur_yaw + turn / n * 0.5
			cur_yaw += turn / n
			p = Vector3(p.x, 0.0, p.z) + fwd(mid_yaw) * ds
			var hk := k
			if t == "splash":
				hk = minf(1.0, k * 1.7)
			p.y = lerpf(y0, y1, smoothstep(0.0, 1.0, hk))
			if turn != 0.0:
				var inward := fwd(cur_yaw + signf(turn) * PI * 0.5)
				up = (Vector3.UP + inward * 0.35 * sin(k * PI)).normalized()
		if out != null:
			(out["pts"] as PackedVector3Array).append(p)
			(out["ups"] as PackedVector3Array).append(up)
	return [Vector3(p.x, y1, p.z), yaw + turn]


## The full ride: a Dictionary with pts, ups, dist (cumulative), length, open_s (where the automatic
## closing track starts), loops [[s0, s1], ...], splashes [[s0, s1], ...], piece_s (end distance of
## each piece).
static func build(pieces: Array) -> Dictionary:
	var out := {"pts": PackedVector3Array(), "ups": PackedVector3Array(), "loops": [], "splashes": [], "piece_s": []}
	var pts: PackedVector3Array = out["pts"]
	# Station straight.
	var a := station_start()
	var b := station_end()
	var ns := int(ceil(STATION_LEN / STEP))
	for i in ns + 1:
		(out["pts"] as PackedVector3Array).append(a.lerp(b, float(i) / ns))
		(out["ups"] as PackedVector3Array).append(Vector3.UP)
	var pos := b
	var yaw := 0.0
	for pc in pieces:
		var arr: Array = pc
		var t := String(arr[0])
		var s0 := _len_of(out["pts"])
		var r := _piece(t, float(arr[1]), pos, yaw, out)
		pos = r[0]
		yaw = r[1]
		var s1 := _len_of(out["pts"])
		(out["piece_s"] as Array).append(s1)
		if t == "loop":
			(out["loops"] as Array).append([s0, s1])
		elif t == "splash":
			(out["splashes"] as Array).append([s0 + (s1 - s0) * 0.55, s1])
	out["open_s"] = _len_of(out["pts"])
	out["end"] = [pos, yaw]
	_close(out, pos, yaw)
	pts = out["pts"]
	var dist := PackedFloat32Array()
	dist.resize(pts.size())
	var acc := 0.0
	for i in pts.size():
		if i > 0:
			acc += pts[i].distance_to(pts[i - 1])
		dist[i] = acc
	out["dist"] = dist
	out["length"] = acc + pts[pts.size() - 1].distance_to(pts[0])
	return out


static func _len_of(pts: PackedVector3Array) -> float:
	var acc := 0.0
	for i in range(1, pts.size()):
		acc += pts[i].distance_to(pts[i - 1])
	return acc


## The automatic track home: a smooth curve from the end back to a short run-in before the station.
static func _close(out: Dictionary, pos: Vector3, yaw: float) -> void:
	var target := station_start() - Vector3(1.8, 0.0, 0.0)
	var d := pos.distance_to(target)
	if d < 0.5:
		return
	var hl := clampf(d * 0.45, 1.5, 7.0)
	var c1 := _on_table(pos + fwd(yaw) * hl)
	var c2 := _on_table(target - Vector3(hl, 0.0, 0.0))
	var n := maxi(6, int(ceil((d + hl) / STEP)))
	var pts: PackedVector3Array = out["pts"]
	var ups: PackedVector3Array = out["ups"]
	for i in range(1, n + 1):
		var k := float(i) / n
		var p := pos.bezier_interpolate(c1, c2, target, k)
		p.y = lerpf(pos.y, STATION_Y, smoothstep(0.0, 1.0, k))
		pts.append(p)
		ups.append(Vector3.UP)
	var m := int(ceil(1.8 / STEP))
	for i in range(1, m):
		pts.append(target.lerp(station_start(), float(i) / m))
		ups.append(Vector3.UP)
	out["pts"] = pts
	out["ups"] = ups


static func _on_table(p: Vector3) -> Vector3:
	var flat := Vector2(p.x, p.z)
	if flat.length() > FIT_R:
		flat = flat.normalized() * FIT_R
	return Vector3(flat.x, p.y, flat.y)


## Position, forward and up at distance s (wraps around the loop).
static func sample(tr: Dictionary, s: float) -> Transform3D:
	var pts: PackedVector3Array = tr["pts"]
	var ups: PackedVector3Array = tr["ups"]
	var dist: PackedFloat32Array = tr["dist"]
	var length: float = tr["length"]
	var n := pts.size()
	if n < 2:
		return Transform3D()
	s = fposmod(s, length)
	var i := dist.bsearch(s, true) - 1
	i = clampi(i, 0, n - 1)
	var j := (i + 1) % n
	var seg := (length - dist[i]) if j == 0 else (dist[j] - dist[i])
	var k := clampf((s - dist[i]) / maxf(seg, 0.0001), 0.0, 1.0)
	var p := pts[i].lerp(pts[j], k)
	var f := (pts[j] - pts[i]).normalized()
	if f.length() < 0.5:
		f = Vector3.RIGHT
	var u := ups[i].lerp(ups[j], k)
	var right := f.cross(u).normalized()
	if right.length() < 0.5:
		right = f.cross(Vector3.UP).normalized()
	u = right.cross(f).normalized()
	# Basis: -Z forward, +Y up (like a Godot node facing its travel direction).
	return Transform3D(Basis(right, u, -f), p)


## True when s is inside one of the ranges ([[s0, s1], ...]).
static func in_ranges(ranges: Array, s: float) -> bool:
	for r in ranges:
		var a: Array = r
		if s >= float(a[0]) and s <= float(a[1]):
			return true
	return false


## The whole track as one vertex-coloured mesh (one draw call): rails, ties, posts and the splash pools.
## The closing part (after open_s) uses ghost colours when `closed` is false.
static func bake(tr: Dictionary, closed: bool) -> Array:
	var solid := MeshKit.builder()
	var ghost := MeshKit.builder()
	var pts: PackedVector3Array = tr["pts"]
	var dist: PackedFloat32Array = tr["dist"]
	var open_s: float = tr["open_s"]
	var n := pts.size()
	var tie_acc := 0.0
	var post_acc := 1.2
	for i in n:
		var j := (i + 1) % n
		var s := dist[i]
		var a := pts[i]
		var bpt := pts[j]
		var seg := a.distance_to(bpt)
		if seg < 0.001:
			continue
		var xa := sample(tr, s + 0.001)
		var xb := sample(tr, s + seg - 0.001)
		var is_ghost := s >= open_s and not closed
		var bld: MeshKit.Builder = ghost if is_ghost else solid
		var rc := RAIL_COL if not is_ghost else Color(1.0, 1.0, 1.0, 0.35)
		for side in [-1.0, 1.0]:
			var ra: Vector3 = xa.origin + xa.basis.x * GAUGE * side
			var rb: Vector3 = xb.origin + xb.basis.x * GAUGE * side
			_beam(bld, ra, rb, xa.basis.y.lerp(xb.basis.y, 0.5), Vector2(0.11, 0.11), rc)
		tie_acc += seg
		if tie_acc > 0.55:
			tie_acc = 0.0
			var tb := Basis(xa.basis.x * (GAUGE * 2.0 + 0.2), xa.basis.y * 0.07, xa.basis.z * 0.16)
			bld.box(Vector3.ONE, Transform3D(tb, xa.origin - xa.basis.y * 0.08), TIE_COL if not is_ghost else Color(1, 1, 1, 0.25))
		post_acc += seg
		if post_acc > 2.2 and not is_ghost and xa.basis.y.y > 0.6:
			post_acc = 0.0
			var top := xa.origin - xa.basis.y * 0.1
			var foot := 0.0 if Vector2(top.x, top.z).length() < TABLE_R + 0.3 else FLOOR_Y  # over the edge: down to the floor
			if top.y - foot > 0.25:
				bld.cylinder(0.07, 0.09, top.y - foot, Transform3D(Basis(), Vector3(top.x, (top.y + foot) * 0.5, top.z)), POST_COL, 6, false, false)
	for r in tr["splashes"]:
		var ra: Array = r
		var mid := sample(tr, (float(ra[0]) + float(ra[1])) * 0.5)
		solid.cylinder(1.6, 1.6, 0.12, Transform3D(Basis(), Vector3(mid.origin.x, WATER_Y, mid.origin.z)), Color(0.3, 0.65, 1.0), 14)
	return [solid.build() if not solid.is_empty() else null, ghost.build(MeshKit.vertex_material(true, true)) if not ghost.is_empty() else null]


## A box from a to b with its "up" side along `up` (size: width, height).
static func _beam(b: MeshKit.Builder, a: Vector3, c: Vector3, up: Vector3, size: Vector2, col: Color) -> void:
	var d := c - a
	var l := d.length() + 0.04
	if l < 0.001:
		return
	var z := d.normalized()
	var x := up.cross(z).normalized()
	if x.length() < 0.5:
		x = Vector3.RIGHT
	var y := z.cross(x).normalized()
	b.box(Vector3.ONE, Transform3D(Basis(x * size.x, y * size.y, z * l), (a + c) * 0.5), col)


## A small mesh of a single piece (the tray models and the glowing ghost), starting at the origin
## heading +X at height 1.
static func piece_mesh(t: String, h: float, col: Color) -> ArrayMesh:
	var out := {"pts": PackedVector3Array([Vector3(0, 1, 0)]), "ups": PackedVector3Array([Vector3.UP])}
	_piece(t, h, Vector3(0, 1, 0), 0.0, out)
	var pts: PackedVector3Array = out["pts"]
	var ups: PackedVector3Array = out["ups"]
	var b := MeshKit.builder()
	for i in range(pts.size() - 1):
		var f := (pts[i + 1] - pts[i]).normalized()
		var right := f.cross(ups[i]).normalized()
		for side in [-1.0, 1.0]:
			_beam(b, pts[i] + right * GAUGE * side, pts[i + 1] + right * GAUGE * side, ups[i], Vector2(0.14, 0.14), col)
		if i % 2 == 0:
			var u := right.cross(f)
			b.box(Vector3.ONE, Transform3D(Basis(right * (GAUGE * 2.0 + 0.2), u * 0.08, f * 0.18), pts[i] - u * 0.08), col.darkened(0.3))
	return b.build()
