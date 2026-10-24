extends Node3D
## MINI GOLF PARTY: one hole at a time. Holds the hole's shape for the ball physics (walls as 2D
## segments on the XZ plane, round bumpers, a height bump, the windmill gate, the loop) and builds
## what it looks like: the green, wooden rails, the cup and flag, and the hole's one gimmick, baked
## into a handful of merged meshes (cheap for the Frame). Built the same way on every machine from
## the hole number, so only the windmill angle needs to travel over the network.
## Coordinates: Vector2(x, z). Every hole starts near +Z (the tee) and ends near -Z (the cup).

const MeshKit := preload("res://core/mesh_kit.gd")

const BALL_R := 0.045
const CUP_R := 0.1
const RAIL_H := 0.1
const RAIL_T := 0.06
const GRASS := Color(0.36, 0.78, 0.36)
const GREEN := Color(0.3, 0.86, 0.45)
const GREEN2 := Color(0.26, 0.78, 0.4)
const WOOD := Color(0.95, 0.62, 0.32)
const WOOD2 := Color(1.0, 0.85, 0.45)
const HOLES := 5

## The holes. outline: the walls (closed polygon). rects: the green's floor [x0, z0, x1, z1].
## path: where to aim, in order (the last one is the cup). par: strokes for a star (kids' par).
static func hole_def(i: int) -> Dictionary:
	match i:
		0:  # PRACTICE: a short straight putt.
			return {"outline": [Vector2(-0.5, 1.7), Vector2(0.5, 1.7), Vector2(0.5, -1.6), Vector2(-0.5, -1.6)],
				"rects": [[-0.5, -1.6, 0.5, 1.7]], "tee": Vector2(0.0, 1.25), "cup": Vector2(0.0, -1.1), "par": 2,
				"path": [Vector2(0.0, -1.1)], "gimmick": ""}
		1:  # Round the corner, with a springy bumper in the bend.
			return {"outline": [Vector2(-0.55, 2.2), Vector2(0.55, 2.2), Vector2(0.55, -1.7), Vector2(-2.5, -1.7),
				Vector2(-2.5, -0.55), Vector2(-0.55, -0.55)],
				"rects": [[-0.55, -1.7, 0.55, 2.2], [-2.5, -1.7, -0.55, -0.55]], "tee": Vector2(0.0, 1.8),
				"cup": Vector2(-2.0, -1.12), "par": 3, "path": [Vector2(0.0, -1.0), Vector2(-2.0, -1.12)],
				"gimmick": "bumper", "bumpers": [[Vector2(0.28, -1.42), 0.2]]}
		2:  # The windmill: sneak through when the sails are up.
			return {"outline": [Vector2(-0.6, 2.7), Vector2(0.6, 2.7), Vector2(0.6, -2.6), Vector2(-0.6, -2.6)],
				"rects": [[-0.6, -2.6, 0.6, 2.7]], "tee": Vector2(0.0, 2.25), "cup": Vector2(0.0, -2.05), "par": 3,
				"path": [Vector2(0.0, 0.3), Vector2(0.0, -2.05)], "gimmick": "windmill", "mill_z": 0.0}
		3:  # Over the hill.
			return {"outline": [Vector2(-0.6, 2.9), Vector2(0.6, 2.9), Vector2(0.6, -2.8), Vector2(-0.6, -2.8)],
				"rects": [[-0.6, -2.8, 0.6, 2.9]], "tee": Vector2(0.0, 2.45), "cup": Vector2(0.0, -2.2), "par": 3,
				"path": [Vector2(0.0, -2.2)], "gimmick": "hill", "hill_z": 0.0, "hill_w": 0.75, "hill_h": 0.17}
		_:  # Loop-the-loop: give it a big whack!
			return {"outline": [Vector2(-0.6, 3.0), Vector2(0.6, 3.0), Vector2(0.6, -3.0), Vector2(-0.6, -3.0)],
				"rects": [[-0.6, -3.0, 0.6, 3.0]], "tee": Vector2(0.0, 2.55), "cup": Vector2(0.0, -2.4), "par": 3,
				"path": [Vector2(0.0, 0.4), Vector2(0.0, -2.4)], "gimmick": "loop", "loop_z": 0.0}


var index := 0
var def: Dictionary = {}
var walls: Array = []  # [a: Vector2, b: Vector2]
var bumpers: Array = []  # [center: Vector2, radius: float]
var outline := PackedVector2Array()
var tee := Vector2.ZERO
var cup := Vector2.ZERO
var par := 3
var path: Array = []
var gimmick := ""
## Windmill: sail angle (radians), spin speed (rad/s; a VR poke speeds it up for a while).
var mill_angle := 0.0
var mill_speed := 1.1
var mill_boost := 0.0
var mill_z := 0.0
var sails: Node3D
var hill_z := 0.0
var hill_w := 1.0
var hill_h := 0.0
var loop_z := 0.0
const LOOP_R := 0.38
const LOOP_GAP := 0.24
const MILL_GAP := 0.15
var flag: Node3D
var flag_wave := 0.0
var _t := 0.0


func build(i: int) -> void:
	for c in get_children():
		c.queue_free()
	index = clampi(i, 0, HOLES - 1)
	def = hole_def(index)
	tee = def["tee"]
	cup = def["cup"]
	par = int(def["par"])
	path = def["path"]
	gimmick = String(def["gimmick"])
	outline = PackedVector2Array()
	for p in def["outline"]:
		outline.append(p)
	walls.clear()
	bumpers.clear()
	for k in outline.size():
		walls.append([outline[k], outline[(k + 1) % outline.size()]])
	for b in def.get("bumpers", []):
		bumpers.append(b)
	mill_z = float(def.get("mill_z", 0.0))
	hill_z = float(def.get("hill_z", 0.0))
	hill_w = float(def.get("hill_w", 1.0))
	hill_h = float(def.get("hill_h", 0.0))
	loop_z = float(def.get("loop_z", 0.0))
	sails = null
	if gimmick == "windmill":
		# The windmill house: two front walls, a tunnel through it, two back walls.
		var g := MILL_GAP
		var back := mill_z - 0.36
		walls.append([Vector2(-0.6, mill_z), Vector2(-g, mill_z)])
		walls.append([Vector2(g, mill_z), Vector2(0.6, mill_z)])
		walls.append([Vector2(-g, mill_z), Vector2(-g, back)])
		walls.append([Vector2(g, mill_z), Vector2(g, back)])
		walls.append([Vector2(-0.6, back), Vector2(-g, back)])
		walls.append([Vector2(g, back), Vector2(0.6, back)])
	elif gimmick == "loop":
		walls.append([Vector2(-0.6, loop_z), Vector2(-LOOP_GAP, loop_z)])
		walls.append([Vector2(LOOP_GAP, loop_z), Vector2(0.6, loop_z)])
		walls.append([Vector2(-LOOP_GAP, loop_z), Vector2(-LOOP_GAP, loop_z - 0.05)])
		walls.append([Vector2(LOOP_GAP, loop_z), Vector2(LOOP_GAP, loop_z - 0.05)])
	_build_look()


# --- Physics shape ------------------------------------------------------------------------

## Ground height of the green at p (the hill hole has a bump).
func height(p: Vector2) -> float:
	if gimmick != "hill":
		return 0.0
	var d := absf(p.y - hill_z)
	if d >= hill_w:
		return 0.0
	return hill_h * (0.5 + 0.5 * cos(PI * d / hill_w))


## Slope (dh/dx, dh/dz).
func grad(p: Vector2) -> Vector2:
	if gimmick != "hill":
		return Vector2.ZERO
	var d := p.y - hill_z
	if absf(d) >= hill_w:
		return Vector2.ZERO
	return Vector2(0.0, -hill_h * 0.5 * PI / hill_w * sin(PI * d / hill_w))


func inside(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, outline)


## Wall segments the ball bounces off right now (the windmill sail closes its door when down).
func active_walls() -> Array:
	if gimmick == "windmill" and mill_blocking():
		var out := walls.duplicate()
		out.append([Vector2(-MILL_GAP, mill_z + 0.04), Vector2(MILL_GAP, mill_z + 0.04)])
		return out
	return walls


## A sail is pointing down across the door.
func mill_blocking() -> bool:
	for k in 4:
		var a := fposmod(mill_angle + k * PI * 0.5, TAU)
		if absf(a - PI) < 0.22:
			return true
	return false


## Is the straight line from a to b free of walls (aim helper)?
func clear_line(a: Vector2, b: Vector2) -> bool:
	for w in walls:
		if Geometry2D.segment_intersects_segment(a, b, w[0], w[1]) != null:
			return false
	for bm in bumpers:
		var c: Vector2 = bm[0]
		var q := Geometry2D.get_closest_point_to_segment(c, a, b)
		if q.distance_to(c) < float(bm[1]) + BALL_R:
			return false
	return true


## Where a ball at p should aim by default: the furthest path point it can see.
func aim_point(p: Vector2) -> Vector2:
	for k in range(path.size() - 1, -1, -1):
		var q: Vector2 = path[k]
		if clear_line(p, q):
			return q
	return path[0]


## World position of a ball resting at p.
func world(p: Vector2, lift: float = 0.0) -> Vector3:
	return Vector3(p.x, height(p) + BALL_R + lift, p.y)


func bounds() -> Rect2:
	var r := Rect2(outline[0], Vector2.ZERO)
	for p in outline:
		r = r.expand(p)
	return r


func _process(delta: float) -> void:
	_t += delta
	if gimmick == "windmill":
		mill_boost = maxf(0.0, mill_boost - delta)
		mill_angle = fmod(mill_angle + delta * mill_speed * (3.0 if mill_boost > 0.0 else 1.0), TAU)
		if sails != null:
			sails.rotation.z = mill_angle
	if flag != null:
		flag_wave = maxf(0.0, flag_wave - delta)
		flag.rotation.y = sin(_t * 2.0) * 0.15 + sin(_t * 14.0) * flag_wave * 0.5
		flag.rotation.z = sin(_t * 18.0) * flag_wave * 0.15


# --- Look ---------------------------------------------------------------------------------

func _build_look() -> void:
	var b := MeshKit.Builder.new()
	# The green: raised a touch above the lawn, with a darker stripe pattern.
	for r in def["rects"]:
		var x0: float = r[0]
		var z0: float = r[1]
		var x1: float = r[2]
		var z1: float = r[3]
		b.box(Vector3(x1 - x0, 0.06, z1 - z0), MeshKit.at(Vector3((x0 + x1) * 0.5, -0.03, (z0 + z1) * 0.5)), GREEN)
	# Rails: a box along each wall, just outside it.
	var k := 0
	for w in walls:
		var a: Vector2 = w[0]
		var c: Vector2 = w[1]
		var d := c - a
		var mid := (a + c) * 0.5
		var col := WOOD if k % 2 == 0 else WOOD2
		k += 1
		b.box(Vector3(RAIL_T, RAIL_H, d.length() + RAIL_T), Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)),
			Vector3(mid.x, RAIL_H * 0.5, mid.y)), col)
	for bm in bumpers:
		var c: Vector2 = bm[0]
		var rr: float = bm[1]
		b.cylinder(rr, rr, 0.16, MeshKit.at(Vector3(c.x, 0.08, c.y)), Color(1.0, 0.35, 0.55), 16)
		b.torus(rr, 0.035, MeshKit.at(Vector3(c.x, 0.1, c.y)), Color(1.0, 0.95, 0.95), 16, 6)
	# Tee mat and the cup (a dark hole with a white rim).
	b.box(Vector3(0.9, 0.01, 0.34), MeshKit.at(Vector3(tee.x, 0.003, tee.y)), Color(0.2, 0.62, 0.32))
	b.cylinder(CUP_R, CUP_R, 0.01, MeshKit.at(Vector3(cup.x, 0.003, cup.y)), Color(0.05, 0.08, 0.05), 16)
	b.torus(CUP_R + 0.01, 0.012, MeshKit.at(Vector3(cup.x, 0.004, cup.y)), Color.WHITE, 16, 4)
	b.cylinder(0.012, 0.012, 1.0, MeshKit.at(Vector3(cup.x + CUP_R * 0.6, 0.5, cup.y)), Color.WHITE, 6)
	if gimmick == "hill":
		_hill(b)
	elif gimmick == "windmill":
		_mill_house(b)
	elif gimmick == "loop":
		_loop(b)
	add_child(MeshKit.instance(b.build()))
	# The flag: its own little node so it can wave (and be flicked by the VR player).
	flag = Node3D.new()
	flag.position = Vector3(cup.x + CUP_R * 0.6, 0.98, cup.y)
	var fb := MeshKit.Builder.new()
	fb.box(Vector3(0.3, 0.2, 0.012), MeshKit.at(Vector3(0.15, -0.1, 0.0)), Color(1.0, 0.3, 0.3))
	fb.star(5, 0.06, 0.028, 0.02, MeshKit.at(Vector3(0.15, -0.1, 0.0)), Color(1.0, 0.92, 0.3), true)
	flag.add_child(MeshKit.instance(fb.build(), false))
	add_child(flag)
	if gimmick == "windmill":
		sails = Node3D.new()
		sails.position = Vector3(0.0, 0.55, mill_z + 0.08)
		var sb := MeshKit.Builder.new()
		for s in 4:
			var ang := s * PI * 0.5
			var dir := Vector3(sin(ang), -cos(ang), 0.0)
			sb.box(Vector3(0.12, 0.5, 0.02), Transform3D(Basis(Vector3.BACK, ang), dir * 0.3), Color(1.0, 0.97, 0.9) if s % 2 == 0 else Color(1.0, 0.45, 0.4))
		sb.sphere(0.06, MeshKit.at(Vector3.ZERO), Color(1.0, 0.85, 0.3), 10)
		sails.add_child(MeshKit.instance(sb.build(), false))
		add_child(sails)


func _hill(b: MeshKit.Builder) -> void:
	var n := 14
	for s in n:
		var z0 := hill_z - hill_w + 2.0 * hill_w * float(s) / n
		var z1 := hill_z - hill_w + 2.0 * hill_w * float(s + 1) / n
		var y0 := height(Vector2(0.0, z0))
		var y1 := height(Vector2(0.0, z1))
		var len := Vector2(z1 - z0, y1 - y0).length()
		var mid := Vector3(0.0, (y0 + y1) * 0.5 - 0.02, (z0 + z1) * 0.5)
		b.box(Vector3(1.2, 0.04, len + 0.01), Transform3D(Basis(Vector3.RIGHT, atan2(y1 - y0, -(z1 - z0))), mid),
			GREEN2 if s % 2 == 0 else GREEN)
		# Fill under it (so it looks solid from the side).
		b.box(Vector3(1.19, maxf(0.005, (y0 + y1) * 0.5), z1 - z0), MeshKit.at(Vector3(0.0, (y0 + y1) * 0.25, mid.z)), Color(0.5, 0.35, 0.22))


func _mill_house(b: MeshKit.Builder) -> void:
	var z := mill_z - 0.18
	for sx in [-1.0, 1.0]:
		var x: float = sx * (0.6 + MILL_GAP) * 0.5
		b.box(Vector3(0.6 - MILL_GAP, 0.5, 0.36), MeshKit.at(Vector3(x, 0.25, z)), Color(0.98, 0.9, 0.75))
	b.box(Vector3(1.2, 0.2, 0.36), MeshKit.at(Vector3(0.0, 0.6, z)), Color(0.98, 0.9, 0.75))
	b.cone(0.62, 0.45, MeshKit.at(Vector3(0.0, 0.92, z), Vector3(1.0, 1.0, 0.5)), Color(0.9, 0.3, 0.3), 4)
	b.box(Vector3(0.12, 0.08, 0.05), MeshKit.at(Vector3(-0.32, 0.3, mill_z + 0.01)), Color(0.4, 0.75, 1.0))
	b.box(Vector3(0.12, 0.08, 0.05), MeshKit.at(Vector3(0.32, 0.3, mill_z + 0.01)), Color(0.4, 0.75, 1.0))


func _loop(b: MeshKit.Builder) -> void:
	# A rainbow hoop standing over the door: the ball runs round it.
	var colors: Array[Color] = [Color(1.0, 0.35, 0.35), Color(1.0, 0.7, 0.25), Color(1.0, 0.95, 0.3), Color(0.4, 0.9, 0.4), Color(0.4, 0.65, 1.0)]
	var n := 20
	for s in n:
		var a0 := TAU * float(s) / n
		var a1 := TAU * float(s + 1) / n
		var p0 := _loop_point(a0)
		var p1 := _loop_point(a1)
		b.tube(p0, p1, 0.035, 0.035, colors[s % colors.size()], 6)
	b.box(Vector3(0.1, 0.06, 0.1), MeshKit.at(Vector3(-0.08, 0.03, loop_z)), Color(0.9, 0.9, 0.95))
	b.box(Vector3(0.1, 0.06, 0.1), MeshKit.at(Vector3(0.08, 0.03, loop_z)), Color(0.9, 0.9, 0.95))


## Ball centre on the loop at angle a (0 = the bottom going in, TAU = the bottom coming out).
func loop_ball(a: float, x: float) -> Vector3:
	return Vector3(x + 0.12 * a / TAU - 0.06, LOOP_R + BALL_R - (LOOP_R) * cos(a), loop_z - LOOP_R * sin(a))


func _loop_point(a: float) -> Vector3:
	var p := loop_ball(a, 0.0)
	# The track sits just outside the ball's path.
	var c := Vector3(p.x, LOOP_R + BALL_R, loop_z)
	return c + (p - c) * ((LOOP_R + BALL_R * 1.6) / LOOP_R)
