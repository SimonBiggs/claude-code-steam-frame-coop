extends RefCounted
## HoleSpec: one hole described as plain data in hole-local metres. The tee sits near the origin,
## play goes towards -Z, +X is to the right and the green's surface is y = 0 unless raised.
## The course files (course_pirate.gd, course_space.gd) fill one in with the helpers below and
## hole_builder.gd turns it into meshes, colliders and gimmicks. No randomness: the host and the
## TV machine build exactly the same hole.

const Defs := preload("res://games/mini_golf_party/defs.gd")

var index := 0
var theme := "pirate"
var title := ""
var par := 3
## How the gimmick works (shown when the hole starts) and the skill shot (a tip).
var hint := ""
var skill := ""
var tee := Vector3.ZERO
var cup := Vector3(0.0, 0.0, -6.0)
## {"pts": PackedVector3Array (convex outline of the top surface, any winding), "kind": "felt" | "plank" | "metal" | "sand"}
var floors: Array = []
## {"a": Vector3, "b": Vector3 (on the floor surface), "h": float, "kind": "rail" | "obst"}
var walls: Array = []
## Round posts: {"at": Vector3 (base), "r": float, "h": float, "bumper": bool, "look": String}
var posts: Array = []
## Box obstacles: {"at": Vector3 (centre of the base), "size": Vector3, "yaw": float, "look": String}
var blocks: Array = []
## Areas with an effect: {"type": "water" | "lowgrav" | "conveyor" | "sand" | "funnel", "at": Vector3,
## "size": Vector2 (x, z extents), "yaw": float, plus per type: "dir" (Vector2) + "speed" (conveyor),
## "g" (lowgrav), "radius" + "accel" (funnel), "decel" (sand)}
var zones: Array = []
## Moving / scripted pieces: windmill, cannon, ship, mover, orbit, spinner, loop, portal (see hole_builder.gd).
var gimmicks: Array = []
## Bot / auto-putt waypoints, tee to cup: {"p": Vector3, "v": exact speed or 0, "k": speed factor,
## "jump": true (may fly over gaps), "from": Vector3 + "from_r": only aim here from near that spot,
## "gate": gimmick index to wait for (windmill blades, the ship), "end": arrive with this speed}
var route: Array = []
## Party-mode power-up boxes (floor positions).
var powerups: Array = []
## Scenery around the hole: {"prop": MeshKit prop name or a custom look, "at": Vector3, "yaw": float, "scale": float}
var decor: Array = []
## Which side of the cup the critter audience sits (+1 right, -1 left).
var crowd_side := 1.0
## Where the audience stands (hole-local, set by the course file or computed from the bounds).
var crowd_at := Vector3.INF


# --- Floors and walls -------------------------------------------------------------------------

## A corridor along a polyline (Vector2 = flat at height y, or Vector3 with its own heights), w
## metres wide, with mitred floor pieces and rails. caps: "both", "start", "end" or "none" (open
## ends to join other areas). sides: "both", "left", "right" or "none".
func lane(points: Array, w: float, y: float = 0.0, caps: String = "both", sides: String = "both", kind: String = "felt") -> void:
	var pts: Array[Vector3] = _v3(points, y)
	if pts.size() < 2:
		return
	var hw := w * 0.5
	var edge_l := _offset(pts, hw)
	var edge_r := _offset(pts, -hw)
	for i in pts.size() - 1:
		floors.append({"pts": PackedVector3Array([edge_l[i], edge_l[i + 1], edge_r[i + 1], edge_r[i]]), "kind": kind})
	var wo := hw + Defs.WALL_T * 0.5
	var wl := _offset(pts, wo)
	var wr := _offset(pts, -wo)
	if sides == "both" or sides == "left":
		for i in pts.size() - 1:
			_wall(wl[i], wl[i + 1], Defs.WALL_H, "rail")
	if sides == "both" or sides == "right":
		for i in pts.size() - 1:
			_wall(wr[i], wr[i + 1], Defs.WALL_H, "rail")
	var d0 := (pts[1] - pts[0])
	d0.y = 0.0
	d0 = d0.normalized() * Defs.WALL_T * 0.5
	var n := pts.size() - 1
	var d1 := (pts[n] - pts[n - 1])
	d1.y = 0.0
	d1 = d1.normalized() * Defs.WALL_T * 0.5
	if caps == "both" or caps == "start":
		_wall(wr[0] - d0, wl[0] - d0, Defs.WALL_H, "rail")
	if caps == "both" or caps == "end":
		_wall(wl[n] + d1, wr[n] + d1, Defs.WALL_H, "rail")


## A flat rectangular floor (no rails): centre, size (x, z), height, yaw (degrees).
func area(center: Vector2, size: Vector2, y: float = 0.0, yaw_deg: float = 0.0, kind: String = "felt") -> void:
	var h := size * 0.5
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var c := Vector3(center.x, y, center.y)
	var pts := PackedVector3Array()
	for corner in [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]:
		var cc: Vector2 = corner
		pts.append(c + b * Vector3(cc.x, 0.0, cc.y))
	floors.append({"pts": pts, "kind": kind})


## A flat convex floor polygon (Vector2 points) at height y.
func poly(points: Array, y: float = 0.0, kind: String = "felt") -> void:
	floors.append({"pts": PackedVector3Array(_v3(points, y)), "kind": kind})


## A regular-polygon floor (round islands, dish rooms): centre, radius, sides.
func disc(center: Vector2, radius: float, y: float = 0.0, sides: int = 12, kind: String = "felt") -> void:
	var pts: Array = []
	for i in sides:
		var a := TAU * float(i) / sides + PI / sides
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	poly(pts, y, kind)


## Rails along a polyline (Vector2 at height y, or Vector3). closed: back to the first point.
## Rails are centred on the line. kind "rail" (outer, never ghosted) or "obst" (ghost balls pass).
func rail(points: Array, y: float = 0.0, closed: bool = false, h: float = Defs.WALL_H, kind: String = "rail") -> void:
	var pts: Array[Vector3] = _v3(points, y)
	for i in pts.size() - 1:
		_wall(pts[i], pts[i + 1], h, kind)
	if closed and pts.size() > 2:
		_wall(pts[pts.size() - 1], pts[0], h, kind)


## Rails round a regular polygon (matches disc()). gaps: side indices left open.
func ring_rail(center: Vector2, radius: float, y: float = 0.0, sides: int = 12, gaps: Array = [], kind: String = "rail") -> void:
	var r := radius + Defs.WALL_T * 0.5 / cos(PI / sides)
	for i in sides:
		if gaps.has(i):
			continue
		var a0 := TAU * float(i) / sides + PI / sides
		var a1 := TAU * float(i + 1) / sides + PI / sides
		_wall(Vector3(center.x + cos(a0) * r, y, center.y + sin(a0) * r), Vector3(center.x + cos(a1) * r, y, center.y + sin(a1) * r), Defs.WALL_H, kind)


## A round post (barrels, coins, pillars). bumper: springy "boing" bounce.
func post(at: Vector2, r: float = 0.1, y: float = 0.0, bumper: bool = false, look: String = "", h: float = 0.22) -> void:
	posts.append({"at": Vector3(at.x, y, at.y), "r": r, "h": h, "bumper": bumper, "look": look})


## A box obstacle standing on the floor (rocks, crates, consoles).
func block(center: Vector2, size: Vector2, yaw_deg: float = 0.0, y: float = 0.0, h: float = 0.25, look: String = "") -> void:
	blocks.append({"at": Vector3(center.x, y, center.y), "size": Vector3(size.x, h, size.y), "yaw": deg_to_rad(yaw_deg), "look": look})


# --- Zones, gimmicks, route ---------------------------------------------------------------------

func water(center: Vector2, size: Vector2, yaw_deg: float = 0.0) -> void:
	zones.append({"type": "water", "at": Vector3(center.x, 0.0, center.y), "size": size, "yaw": deg_to_rad(yaw_deg)})


func zone(type: String, center: Vector2, size: Vector2, opts: Dictionary = {}, y: float = 0.0) -> void:
	var z := {"type": type, "at": Vector3(center.x, y, center.y), "size": size, "yaw": deg_to_rad(float(opts.get("yaw", 0.0)))}
	for k in opts:
		if String(k) != "yaw":
			z[k] = opts[k]
	zones.append(z)


## Add a gimmick ({"type": ...}); returns its index (for route gates).
func gimmick(g: Dictionary) -> int:
	gimmicks.append(g)
	return gimmicks.size() - 1


## A bot waypoint (Vector2 = on the green at y).
func waypoint(p: Variant, opts: Dictionary = {}, y: float = 0.0) -> void:
	var w := {"p": Vector3(p.x, y, p.y) if p is Vector2 else p}
	for k in opts:
		w[k] = opts[k]
	route.append(w)


func powerup(at: Vector2, y: float = 0.0) -> void:
	powerups.append(Vector3(at.x, y, at.y))


func prop(prop_name: String, at: Vector2, yaw_deg: float = 0.0, s: float = 1.0, y: float = -0.12) -> void:
	decor.append({"prop": prop_name, "at": Vector3(at.x, y, at.y), "yaw": deg_to_rad(yaw_deg), "scale": s})


# --- Queries ------------------------------------------------------------------------------------

## The playing area's XZ bounding rectangle (hole-local).
func bounds() -> Rect2:
	var r := Rect2(Vector2(tee.x, tee.z), Vector2.ZERO)
	for f in floors:
		var pts: PackedVector3Array = f.pts
		for p in pts:
			r = r.expand(Vector2(p.x, p.z))
	return r


## Floor height under a hole-local XZ point (the highest floor piece containing it), or NAN.
func floor_height(x: float, z: float) -> float:
	var best := NAN
	for f in floors:
		var pts: PackedVector3Array = f.pts
		if _inside(pts, x, z):
			var h := _height_in(pts, x, z)
			if is_nan(best) or h > best:
				best = h
	return best


# --- Helpers -------------------------------------------------------------------------------------

func _wall(a: Vector3, b: Vector3, h: float, kind: String) -> void:
	if a.distance_to(b) < 0.01:
		return
	walls.append({"a": a, "b": b, "h": h, "kind": kind})


static func _v3(points: Array, y: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in points:
		if p is Vector3:
			out.append(p)
		else:
			var q: Vector2 = p
			out.append(Vector3(q.x, y, q.y))
	return out


## Mitred offset of a polyline (positive = to the left of the walking direction).
static func _offset(pts: Array[Vector3], dist: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n := pts.size()
	for i in n:
		var p := pts[i]
		var nl := Vector2.ZERO
		if i == 0:
			nl = _left(pts[0], pts[1])
		elif i == n - 1:
			nl = _left(pts[n - 2], pts[n - 1])
		else:
			var a := _left(pts[i - 1], pts[i])
			var b := _left(pts[i], pts[i + 1])
			var m := (a + b)
			if m.length() < 0.001:
				m = a
			m = m.normalized()
			nl = m / maxf(m.dot(a), 0.35)
		out.append(p + Vector3(nl.x, 0.0, nl.y) * dist)
	return out


## Unit vector to the left of walking a -> b (in XZ, as Vector2(x, z)).
static func _left(a: Vector3, b: Vector3) -> Vector2:
	var d := Vector2(b.x - a.x, b.z - a.z).normalized()
	return Vector2(d.y, -d.x)


static func _inside(pts: PackedVector3Array, x: float, z: float) -> bool:
	var n := pts.size()
	var sign_seen := 0
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var cr := (b.x - a.x) * (z - a.z) - (b.z - a.z) * (x - a.x)
		var s := 1 if cr > 0.0005 else (-1 if cr < -0.0005 else 0)
		if s != 0:
			if sign_seen == 0:
				sign_seen = s
			elif s != sign_seen:
				return false
	return true


## Height of the plane through the polygon's first three points at (x, z).
static func _height_in(pts: PackedVector3Array, x: float, z: float) -> float:
	var a := pts[0]
	var nrm := (pts[1] - a).cross(pts[2] - a)
	if absf(nrm.y) < 0.00001:
		return a.y
	return a.y - (nrm.x * (x - a.x) + nrm.z * (z - a.z)) / nrm.y
