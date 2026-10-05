extends Node3D
## OBSTACLE RUSH: the four short courses, a candy-coloured toy course standing on the giant's table.
## They run along +X (start at the left, the finish arch at the right, as the VR giant sees it).
## ONE new thing per course:
##   0 HOP HOP   two little gaps to jump (the practice: a glowing ring over the first gap for the TV
##               runners, a glowing target on the floor for the giant's first ball)
##   1 SPINNER   a spinning bar on a round platform: jump it! (the giant can hold it still or spin it)
##   2 BOING     mushroom bounce pads up two big steps (the giant can poke them)
##   3 DOORS     two walls of doors: some are pretend and go BOING (the giant can lift any door)
##               ... and the golden crown waits at the finish.
## Static pieces are ONE merged vertex-coloured mesh and one StaticBody3D. Only the current course
## exists; build() clears the old one. Both machines build the same course from (index, seed).
## The host runs the moving parts (step()); the TV machine copies them from the snapshot.

const MeshKit := preload("res://core/mesh_kit.gd")

const COUNT := 4
const NAMES: Array[String] = ["HOP HOP", "SPINNER", "BOING", "DOORS"]
const START_X := -11.0
const FINISH_X := 9.3
const SPIN_SPEED := 1.1
const BAR_R := 4.2
const DOOR_W := 2.0
const TRIM := Color(0.98, 0.97, 0.94)
const CANDY: Array[Color] = [Color(1.0, 0.6, 0.75), Color(0.55, 0.8, 1.0), Color(1.0, 0.85, 0.45), Color(0.6, 0.9, 0.62)]

var index := 0
var half_w := 2.0
var low_y := 0.0  ## lowest floor (falling well below it pops you back)
var finish_y := 0.0
var checkpoints: Array[Vector3] = []
var route: Array = []  ## CPU runners: [Vector3 point, String what] ("", "jump", "door")
var ring_pos := Vector3.INF  ## TV practice ring (course 0)
var target_pos := Vector3.INF  ## VR practice target (course 0)
var spin_angle := 0.0
var spin_vel := SPIN_SPEED
var spin_held := 0.0  ## seconds the giant's hand keeps it still
var spinner: Node3D
var pads: Array[Vector3] = []
var pad_nodes: Array[Node3D] = []
var pad_kick: Array[float] = []
var doors: Array[Dictionary] = []  ## {node, hinge, x, z, fake, body, open (0..1), lift (s)}
var flag: Node3D
var flag_wave := 0.0
var ring: Node3D
var target: Node3D
var _t := 0.0
var _body: StaticBody3D
var _b: MeshKit.Builder


func build(i: int, seed_value: int) -> void:
	for c in get_children():
		c.queue_free()
	index = clampi(i, 0, COUNT - 1)
	half_w = 3.0 if index == 3 else 2.0
	checkpoints.clear()
	route.clear()
	pads.clear()
	pad_nodes.clear()
	pad_kick.clear()
	doors.clear()
	ring_pos = Vector3.INF
	target_pos = Vector3.INF
	spinner = null
	ring = null
	target = null
	spin_angle = 0.0
	spin_vel = SPIN_SPEED
	spin_held = 0.0
	low_y = 0.0
	finish_y = 0.0
	_b = MeshKit.Builder.new()
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	add_child(_body)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	match index:
		0:
			_hop_hop()
		1:
			_spinner()
		2:
			_boing()
		_:
			_doors(rng)
	_finish_arch()
	var mi := MeshKit.instance(_b.build())
	mi.name = "Static"
	add_child(mi)
	_b = null


# --- The four courses ---------------------------------------------------------------------------

func _hop_hop() -> void:
	_floor(-13.0, -4.0, 0.0, 0)
	_floor(-1.5, 3.5, 0.0, 1)
	_floor(6.0, 13.0, 0.0, 2)
	checkpoints = [Vector3(START_X, 0, 0), Vector3(-0.5, 0, 0), Vector3(7.0, 0, 0)]
	route = [[Vector3(-4.4, 0, 0), "jump"], [Vector3(-0.5, 0, 0), ""], [Vector3(3.1, 0, 0), "jump"], [Vector3(11.5, 0, 0), ""]]
	ring_pos = Vector3(-2.75, 1.25, 0.0)
	ring = _glow_ring(ring_pos)
	target_pos = Vector3(1.0, 0.03, 0.0)
	target = _target_disc(target_pos)


func _spinner() -> void:
	_floor(-13.0, -4.2, 0.0, 0)
	_floor(4.2, 13.0, 0.0, 2)
	_disc(Vector3.ZERO, 4.6, 1)
	_shape_cyl(Vector3(0.0, 0.8, 0.0), 0.45, 1.6)
	checkpoints = [Vector3(START_X, 0, 0), Vector3(6.0, 0, 0)]
	route = [[Vector3(-4.6, 0, 0), ""], [Vector3(-2.6, 0, 1.7), "spin"], [Vector3(2.6, 0, 1.7), "spin"],
		[Vector3(4.8, 0, 0), ""], [Vector3(11.5, 0, 0), ""]]
	spinner = Node3D.new()
	add_child(spinner)
	var b := MeshKit.Builder.new()
	b.cylinder(0.45, 0.55, 1.6, MeshKit.at(Vector3(0, 0.8, 0)), Color(1.0, 0.45, 0.55), 16)
	b.box(Vector3(BAR_R * 2.0, 0.34, 0.34), MeshKit.at(Vector3(0, 0.45, 0)), Color(1.0, 0.92, 0.35))
	for s in [-1.0, 1.0]:
		b.sphere(0.32, MeshKit.at(Vector3(s * BAR_R, 0.45, 0)), Color(1.0, 0.45, 0.55), 12)
		for k in 4:
			b.box(Vector3(0.2, 0.36, 0.36), MeshKit.at(Vector3(s * (0.9 + k * 0.9), 0.45, 0)), Color(1.0, 0.45, 0.55))
	b.sphere(0.5, MeshKit.at(Vector3(0, 1.85, 0)), Color(1.0, 0.85, 0.3), 14, true)  # the knob the giant grabs
	spinner.add_child(MeshKit.instance(b.build()))


func _boing() -> void:
	_floor(-13.0, -1.0, 0.0, 0)
	_floor(-1.0, 4.0, 3.0, 1)
	_floor(4.0, 13.0, 6.0, 2)
	_block(-1.0, 4.0, 2.4, 1)
	_block(4.0, 13.0, 5.4, 2)
	finish_y = 6.0
	checkpoints = [Vector3(START_X, 0, 0), Vector3(0.0, 3, 0), Vector3(6.0, 6, 0)]
	route = [[Vector3(-3.0, 0, 0), "pad"], [Vector3(0.5, 3, 0), ""], [Vector3(2.0, 3, 0), "pad"], [Vector3(11.5, 6, 0), ""]]
	for p in [Vector3(-3.0, 0, 0), Vector3(2.0, 3.0, 0)]:
		_pad(p)


func _doors(rng: RandomNumberGenerator) -> void:
	_floor(-13.0, 13.0, 0.0, 0)
	checkpoints = [Vector3(START_X, 0, 0), Vector3(0.5, 0, 0), Vector3(7.0, 0, 0)]
	var walls: Array[float] = [-3.0, 4.0]
	var fakes: Array[int] = [1, 2]
	for w in 2:
		var x := walls[w]
		var order: Array[int] = [0, 1, 2]
		for k in 3:  # shuffle (same on both machines: the seed is shared)
			var j := rng.randi_range(k, 2)
			var tmp := order[k]
			order[k] = order[j]
			order[j] = tmp
		for k in 3:
			_door(x, -2.0 + k * 2.0, order.find(k) < fakes[w], w)
		# The wall above and beside the doors (can't be jumped).
		_b.box(Vector3(0.4, 0.8, half_w * 2.0), MeshKit.at(Vector3(x, 2.6, 0)), CANDY[w + 1])
		_b.box(Vector3(0.45, 0.2, half_w * 2.0 + 0.1), MeshKit.at(Vector3(x, 3.05, 0)), TRIM)
		_shape_box(Vector3(x, 2.6, 0), Vector3(0.4, 0.8, half_w * 2.0))
		for k in 4:
			var z := -3.0 + k * 2.0
			_b.box(Vector3(0.45, 2.2, 0.16), MeshKit.at(Vector3(x, 1.1, z)), TRIM)
	route = [[Vector3(-2.4, 0, 0), "door"], [Vector3(-0.5, 0, 0), ""], [Vector3(4.6, 0, 0), "door"], [Vector3(11.5, 0, 0), ""]]
	# The golden crown on a cake stand by the finish.
	var b := _b
	b.cylinder(0.7, 0.9, 0.6, MeshKit.at(Vector3(11.8, 0.3, 0)), Color(1.0, 0.95, 0.85), 18)
	b.cylinder(0.45, 0.45, 0.25, MeshKit.at(Vector3(11.8, 0.72, 0)), Color(1.0, 0.82, 0.25), 14, true)
	for k in 6:
		var a := TAU * k / 6.0
		b.cone(0.12, 0.35, MeshKit.at(Vector3(11.8 + cos(a) * 0.38, 1.0, sin(a) * 0.38)), Color(1.0, 0.82, 0.25), 6, true)


# --- Pieces -------------------------------------------------------------------------------------

## A floor slab from x0 to x1 with its top at y, on a candy pillar down to the table.
func _floor(x0: float, x1: float, y: float, colour: int) -> void:
	var len := x1 - x0
	var cx := (x0 + x1) * 0.5
	var col := CANDY[colour % CANDY.size()]
	_b.box(Vector3(len, 0.6, half_w * 2.0), MeshKit.at(Vector3(cx, y - 0.3, 0)), col)
	_b.box(Vector3(len, 0.12, 0.2), MeshKit.at(Vector3(cx, y - 0.02, half_w - 0.1)), TRIM)
	_b.box(Vector3(len, 0.12, 0.2), MeshKit.at(Vector3(cx, y - 0.02, -half_w + 0.1)), TRIM)
	for k in int(len / 2.0):
		var x := x0 + 1.0 + k * 2.0
		_b.box(Vector3(1.0, 0.02, half_w * 2.0 - 0.6), MeshKit.at(Vector3(x, y + 0.005, 0)), col.lightened(0.25))
	var pillar_h := y + 3.5
	_b.cylinder(0.5, 0.7, pillar_h, MeshKit.at(Vector3(cx, y - 0.6 - pillar_h * 0.5 + 0.3, 0)), col.darkened(0.15), 12)
	_shape_box(Vector3(cx, y - 0.3, 0), Vector3(len, 0.6, half_w * 2.0))


## A solid candy block under a raised floor (from the lowest floor up to `top`), so steps are walls.
func _block(x0: float, x1: float, top: float, colour: int) -> void:
	var c := Vector3((x0 + x1) * 0.5, (top - 0.6) * 0.5, 0)
	var size := Vector3(x1 - x0, top + 0.6, half_w * 2.0)
	_b.box(size, MeshKit.at(c), CANDY[colour % CANDY.size()].darkened(0.1))
	_shape_box(c, size)


func _disc(c: Vector3, r: float, colour: int) -> void:
	var col := CANDY[colour % CANDY.size()]
	_b.cylinder(r, r, 0.6, MeshKit.at(c + Vector3(0, -0.3, 0)), col, 32)
	_b.torus(r - 0.1, 0.1, MeshKit.at(c + Vector3(0, -0.02, 0)), TRIM, 32, 6)
	_b.cylinder(0.6, 0.8, 3.2, MeshKit.at(c + Vector3(0, -2.2, 0)), col.darkened(0.15), 12)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = 0.6
	cs.shape = cyl
	cs.position = c + Vector3(0, -0.3, 0)
	_body.add_child(cs)


func _shape_box(c: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = c
	_body.add_child(cs)


func _shape_cyl(c: Vector3, r: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = h
	cs.shape = cyl
	cs.position = c
	_body.add_child(cs)


func _pad(p: Vector3) -> void:
	var n := Node3D.new()
	n.position = p
	add_child(n)
	var b := MeshKit.Builder.new()
	b.cylinder(0.25, 0.3, 0.3, MeshKit.at(Vector3(0, 0.15, 0)), TRIM, 10)
	b.dome(0.85, MeshKit.at(Vector3(0, 0.25, 0), Vector3(1.0, 0.45, 1.0)), Color(1.0, 0.35, 0.45), 18)
	for k in 5:
		var a := TAU * k / 5.0
		b.sphere(0.12, MeshKit.at(Vector3(cos(a) * 0.5, 0.52, sin(a) * 0.5), Vector3(1.0, 0.5, 1.0)), TRIM, 8)
	n.add_child(MeshKit.instance(b.build()))
	pads.append(p)
	pad_nodes.append(n)
	pad_kick.append(0.0)


func _door(x: float, z: float, fake: bool, wall: int) -> void:
	var hinge := Node3D.new()
	hinge.position = Vector3(x, 0.0, z - DOOR_W * 0.5 + 0.1)
	add_child(hinge)
	var b := MeshKit.Builder.new()
	var col := CANDY[(wall * 2 + int(z + 4.0)) % CANDY.size()]
	b.box(Vector3(0.2, 2.1, DOOR_W - 0.2), MeshKit.at(Vector3(0, 1.05, DOOR_W * 0.5 - 0.1)), col)
	b.sphere(0.12, MeshKit.at(Vector3(-0.15, 1.0, DOOR_W - 0.45)), Color(1.0, 0.85, 0.3), 8)
	b.sphere(0.12, MeshKit.at(Vector3(0.15, 1.0, DOOR_W - 0.45)), Color(1.0, 0.85, 0.3), 8)
	b.star(5, 0.35, 0.16, 0.06, MeshKit.at(Vector3(-0.12, 1.5, DOOR_W * 0.5 - 0.1), Vector3.ONE, Vector3(0, -PI * 0.5, 0)), TRIM)
	hinge.add_child(MeshKit.instance(b.build()))
	var body: StaticBody3D = null
	if fake:
		body = StaticBody3D.new()
		body.collision_layer = 1
		body.set_meta("fake_door", doors.size())
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.3, 2.2, DOOR_W)
		cs.shape = bs
		body.add_child(cs)
		body.position = Vector3(x, 1.1, z)
		add_child(body)
	doors.append({"hinge": hinge, "x": x, "z": z, "fake": fake, "body": body, "open": 0.0, "lift": 0.0, "wobble": 0.0})


func _finish_arch() -> void:
	var y := finish_y
	var x := FINISH_X
	for s in [-1.0, 1.0]:
		_b.cylinder(0.22, 0.25, 3.4, MeshKit.at(Vector3(x, y + 1.7, s * (half_w + 0.1))), TRIM, 10)
		_b.sphere(0.35, MeshKit.at(Vector3(x, y + 3.5, s * (half_w + 0.1))), Color(1.0, 0.85, 0.3), 10)
	for k in 8:
		var z := -half_w + (k + 0.5) * half_w * 2.0 / 8.0
		for row in 2:
			var dark := (k + row) % 2 == 0
			_b.box(Vector3(0.1, 0.3, half_w * 2.0 / 8.0), MeshKit.at(Vector3(x, y + 3.05 + row * 0.3, z)),
				Color(0.15, 0.15, 0.2) if dark else TRIM)
	# The finish flag on a pole (it waves; the giant can flick it).
	flag = Node3D.new()
	flag.position = Vector3(12.4, y, -half_w + 0.4)
	add_child(flag)
	var b := MeshKit.Builder.new()
	b.cylinder(0.07, 0.07, 3.0, MeshKit.at(Vector3(0, 1.5, 0)), TRIM, 6)
	b.box(Vector3(1.2, 0.75, 0.05), MeshKit.at(Vector3(0.62, 2.6, 0)), Color(1.0, 0.35, 0.45))
	b.star(5, 0.22, 0.1, 0.07, MeshKit.at(Vector3(0.62, 2.6, 0.03)), Color(1.0, 0.9, 0.35))
	flag.add_child(MeshKit.instance(b.build()))


func _glow_ring(p: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = p
	add_child(n)
	var b := MeshKit.Builder.new()
	b.torus(0.95, 0.09, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(1.0, 0.95, 0.4), 24, 6, true)
	var mi := MeshKit.instance(b.build(), false)
	n.add_child(mi)
	return n


func _target_disc(p: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = p
	add_child(n)
	var b := MeshKit.Builder.new()
	var cols: Array[Color] = [Color(1.0, 0.35, 0.4), TRIM, Color(1.0, 0.35, 0.4), Color(1.0, 0.9, 0.35)]
	for k in 4:
		b.cylinder(1.3 - k * 0.3, 1.3 - k * 0.3, 0.04 + k * 0.01, MeshKit.at(Vector3(0, k * 0.01, 0)), cols[k], 24, true)
	n.add_child(MeshKit.instance(b.build(), false))
	return n


# --- Rules (every machine asks; the host runs step()) ---------------------------------------------

## Velocity for a runner standing on a bounce pad, or ZERO.
func pad_launch(p: Vector3) -> Vector3:
	for k in pads.size():
		var c := pads[k]
		if absf(p.y - (c.y + 0.35)) < 0.5 and Vector2(p.x - c.x, p.z - c.z).length() < 0.85:
			pad_kick[k] = 1.0
			return Vector3(4.2, 15.0, -p.z * 0.6)
	return Vector3.ZERO


## The spinner bar hits a runner standing at p: the push direction, or ZERO.
func hazard_hit(p: Vector3) -> Vector3:
	if spinner == null or p.y > 0.75 or p.y < -0.5:
		return Vector3.ZERO
	var d := Vector3(cos(spin_angle), 0.0, -sin(spin_angle))
	var rel := Vector3(p.x, 0.0, p.z)
	var along := rel.dot(d)
	var off := absf(rel.x * d.z - rel.z * d.x)
	if absf(along) > BAR_R + 0.3 or off > 0.55 or absf(spin_vel) < 0.2:
		return Vector3.ZERO
	var tangent := Vector3(spin_vel * rel.z, 0.0, -spin_vel * rel.x)
	return (tangent.normalized() + rel.normalized() * 0.3).normalized()


## Index of the furthest checkpoint the runner at p has reached (never goes back).
func checkpoint_for(p: Vector3, current: int) -> int:
	var best := current
	for k in range(current + 1, checkpoints.size()):
		var c := checkpoints[k]
		if p.x >= c.x - 0.5 and absf(p.y - c.y) < 1.2:
			best = k
	return best


## Where to pop back to (spread out a little so runners don't stack).
func checkpoint_spot(k: int, rid: int) -> Vector3:
	if checkpoints.is_empty():
		return Vector3(START_X, 1.0, 0.0)
	var c := checkpoints[clampi(k, 0, checkpoints.size() - 1)]
	var off := float((rid * 7) % 5) - 2.0
	return c + Vector3(0.0, 0.6, clampf(off * 0.6, -half_w + 0.6, half_w - 0.6))


func start_spot(n: int, count: int) -> Vector3:
	var row := n % 4
	var col := n / 4
	var spread := (float(row) - float(mini(count, 4) - 1) * 0.5) * 0.95
	return Vector3(START_X - col * 1.2, 0.3, clampf(spread, -half_w + 0.5, half_w - 0.5))


func finished(p: Vector3) -> bool:
	return p.x > FINISH_X + 0.3 and p.y > finish_y - 0.6


## Host: the giant's hand touched something at p (moving at vel). Returns what it was ("" = nothing).
func touch(p: Vector3, vel: Vector3) -> String:
	if spinner != null and p.y > -0.3 and p.y < 2.6:
		var d := Vector3(cos(spin_angle), 0.0, -sin(spin_angle))
		var rel := Vector3(p.x, 0.0, p.z)
		if Vector2(p.x, p.z).length() < 0.9 or (absf(rel.dot(d)) < BAR_R + 0.4 and absf(rel.x * d.z - rel.z * d.x) < 0.7 and p.y < 1.2):
			var push := Vector3(0, 1, 0).cross(rel).normalized().dot(vel) if rel.length() > 0.3 else 0.0
			if absf(push) > 6.0:
				spin_vel = clampf(push * 0.25, -4.0, 4.0)  # a swipe spins it fast
				spin_held = 0.0
				return "spin"
			spin_held = 0.25  # a still hand holds it
			return "hold"
	for k in pads.size():
		if p.distance_to(pads[k] + Vector3(0, 0.4, 0)) < 1.0:
			pad_kick[k] = 1.0
			return "pad"
	for d in doors:
		var dc := Vector3(float(d["x"]), 1.1, float(d["z"]))
		if absf(p.x - dc.x) < 0.7 and absf(p.z - dc.z) < 1.0 and p.y > -0.2 and p.y < 2.6:
			var was: float = d["lift"]
			d["lift"] = 4.0
			return "door" if was <= 0.0 else "hold"
	if flag != null and p.distance_to(flag.position + Vector3(0.6, 2.4, 0)) < 1.2:
		flag_wave = 1.5
		return "flag"
	return ""


## Host: move the moving parts. runners: Array of runner nodes (to swing real doors open).
func step(delta: float, runners: Array) -> void:
	_t += delta
	if spinner != null:
		if spin_held > 0.0:
			spin_held -= delta
			spin_vel = move_toward(spin_vel, 0.0, 12.0 * delta)
		else:
			spin_vel = move_toward(spin_vel, SPIN_SPEED, 0.6 * delta)
		spin_angle = wrapf(spin_angle + spin_vel * delta, -PI, PI)
	for d in doors:
		d["lift"] = maxf(0.0, float(d["lift"]) - delta)
	animate(delta, runners)


## Every machine: door swings, pad squash, flag, ring and target glow.
func animate(delta: float, runners: Array) -> void:
	if spinner != null:
		spinner.rotation.y = spin_angle
	for k in pad_nodes.size():
		pad_kick[k] = maxf(0.0, pad_kick[k] - delta * 2.5)
		var s := sin(pad_kick[k] * PI * 2.0) * 0.3 * pad_kick[k]
		pad_nodes[k].scale = Vector3(1.0 + s * 0.5, 1.0 - s, 1.0 + s * 0.5)
	for d in doors:
		var want := 0.0
		if float(d["lift"]) > 0.0:
			want = 1.0
		elif not bool(d["fake"]):
			for r in runners:
				var rp: Vector3 = (r as Node3D).position
				if absf(rp.x - float(d["x"])) < 1.6 and absf(rp.z - float(d["z"])) < 1.2:
					want = 1.0
		d["open"] = move_toward(float(d["open"]), want, delta * 4.0)
		d["wobble"] = maxf(0.0, float(d["wobble"]) - delta * 2.0)
		var h: Node3D = d["hinge"]
		h.rotation.y = -float(d["open"]) * 1.45 + sin(float(d["wobble"]) * 20.0) * 0.12 * float(d["wobble"])
		var body: StaticBody3D = d["body"]
		if body != null:
			var off := float(d["open"]) > 0.5
			if body.process_mode != (Node.PROCESS_MODE_DISABLED if off else Node.PROCESS_MODE_INHERIT):
				body.process_mode = Node.PROCESS_MODE_DISABLED if off else Node.PROCESS_MODE_INHERIT
	flag_wave = maxf(0.0, flag_wave - delta)
	if flag != null:
		flag.rotation.y = sin(_t * 3.0) * 0.08 + sin(_t * 18.0) * 0.35 * minf(1.0, flag_wave)
	if ring != null:
		ring.rotation.x = _t * 0.8
		ring.scale = Vector3.ONE * (1.0 + sin(_t * 4.0) * 0.06)
	if target != null:
		target.scale = Vector3.ONE * (1.0 + sin(_t * 3.0) * 0.05)


## A fake door gets bonked into: it wobbles.
func wobble_door(k: int) -> void:
	if k >= 0 and k < doors.size():
		doors[k]["wobble"] = 1.0


## Snapshot of the moving parts: [spin angle, door lift bits, pad kicks bits].
func pack() -> Array:
	var bits := 0
	for k in doors.size():
		if float(doors[k]["lift"]) > 0.0:
			bits |= 1 << k
	var pk := 0
	for k in pad_kick.size():
		if pad_kick[k] > 0.9:
			pk |= 1 << k
	return [spin_angle, bits, pk, flag_wave, spin_vel]


func unpack(a: Array, delta: float, runners: Array) -> void:
	if a.size() < 5:
		return
	spin_angle = float(a[0])
	spin_vel = float(a[4])
	var bits := int(a[1])
	for k in doors.size():
		doors[k]["lift"] = 1.0 if bits & (1 << k) else 0.0
	var pk := int(a[2])
	for k in pad_kick.size():
		if pk & (1 << k) and pad_kick[k] < 0.5:
			pad_kick[k] = 1.0
	flag_wave = maxf(flag_wave, float(a[3]))
	_t += delta
