extends Node3D
## SKY BOTS: CRANKY CRAB, Crab Cove's little boss on its round arena. Grumpy, never scary: it scuttles towards a
## robot, then TELLS its stomp (a ring of warn rings round it, core/warn_rings.gd, sent to every machine), STOMPS (a
## bump for robots inside the ring), and is DIZZY for a while (stars spin round its head): punch it, hop on it, or the
## VR giant gives it a poke. Enough bonks and it flops over, sorry, and the SPARK drops on the arena.
## KING KEYWIND (kind "king", Clockwork Keep): a huffy wind-up tin king. He doesn't stomp: he picks a robot, TELLS his
## charge with a warn line across the arena (core/warn_rings.gd line, sent to every machine), DASHES along it, bonks
## into the arena's rim and is DIZZY with his big key spinning: punch him, hop on him, pound him, or the giant pokes.
## The host runs it; the TV machine draws it from pack().

const MeshKit := preload("res://core/mesh_kit.gd")
const Contrast := preload("res://core/contrast.gd")

const COLOR := Color(1.0, 0.42, 0.28)
const RING_COLOR := Color(1.0, 0.3, 0.45)
const KING_COLOR := Color(0.55, 0.4, 0.9)
const STATES: Array[String] = ["sleep", "walk", "tell", "stomp", "dizzy", "dead", "dash"]
const KING_TELL := {"gentle": 2.0, "brave": 1.6, "hard": 1.25}  ## the king's charge line shows this long first
const KING_DASH := {"gentle": 6.0, "brave": 8.0, "hard": 10.0}
const TELL := {"gentle": 1.7, "brave": 1.35, "hard": 1.05}
const DIZZY := {"gentle": 4.5, "brave": 3.6, "hard": 3.0}
const SPEED := {"gentle": 1.6, "brave": 2.2, "hard": 2.9}

var main: Node
var kind := "crab"  ## "crab" (Cranky Crab) or "king" (King Keywind)
var charge_dir := Vector3.RIGHT  ## the king's charge (host; bots read it)
var charge_to := Vector3.ZERO
var key: Node3D
var host := true
var arena := Vector3.ZERO
var arena_r := 6.0
var stomp_r := 2.8
var hp := 4
var hp_max := 4
var mode := "brave"
var state := "sleep"
var st_t := 0.0
var hit_cool := {}  ## who -> seconds
var hits := 0
var stomps := 0
var body: Node3D
var claws: Array[Node3D] = []
var stars: Node3D
var _target := Vector3.ZERO
var _target_yaw := 0.0


func setup(m: Node, bd: Dictionary, the_mode: String, is_host: bool) -> void:
	main = m
	host = is_host
	mode = the_mode
	kind = String(bd.get("kind", "crab"))
	arena = bd.c
	arena_r = float(bd.r) + 1.2
	hp = int(bd.hp)
	hp_max = hp
	position = arena + Vector3(arena_r * 0.35, 0, -1.0)
	_target = position
	body = Node3D.new()
	add_child(body)
	var mi := MeshKit.instance(crab_mesh() if kind == "crab" else king_mesh(), false)
	Contrast.outline(mi, Contrast.OUTLINE)
	body.add_child(mi)
	if kind == "king":
		key = Node3D.new()
		key.position = Vector3(0, 1.1, -0.75)
		body.add_child(key)
		var kb := MeshKit.Builder.new()
		kb.cylinder(0.07, 0.07, 0.5, MeshKit.at(Vector3(0, 0, -0.25), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.85, 0.85, 0.9), 8)
		for e in [-1.0, 1.0]:
			kb.torus(0.22, 0.07, MeshKit.at(Vector3(e * 0.26, 0, -0.55), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(1.0, 0.82, 0.3), 14, 6)
		var km := MeshKit.instance(kb.build(), false)
		Contrast.outline(km, Contrast.OUTLINE)
		key.add_child(km)
	for s in ([-1.0, 1.0] if kind == "crab" else []):
		var c := Node3D.new()
		c.position = Vector3(s * 1.15, 0.75, 0.55)
		body.add_child(c)
		var cb := MeshKit.Builder.new()
		cb.ellipsoid(Vector3(0.42, 0.3, 0.36), MeshKit.at(Vector3(0, 0, 0.3)), COLOR.lightened(0.1), 12)
		cb.wedge(Vector3(0.5, 0.18, 0.4), MeshKit.at(Vector3(0, 0.12, 0.62)), COLOR.lightened(0.2))
		var cm := MeshKit.instance(cb.build(), false)
		Contrast.outline(cm, Contrast.OUTLINE)
		c.add_child(cm)
		claws.append(c)
	stars = Node3D.new()
	stars.position = Vector3(0, 1.9 if kind == "crab" else 2.6, 0)
	body.add_child(stars)
	var sb := MeshKit.Builder.new()
	for k in 4:
		var a := TAU * k / 4.0
		sb.star(5, 0.18, 0.08, 0.05, MeshKit.at(Vector3(cos(a) * 0.6, 0, sin(a) * 0.6)), Color(1.0, 0.92, 0.3), true)
	stars.add_child(MeshKit.instance(sb.build(), false))
	stars.visible = false


## Cranky Crab: a round orange shell, eyes on stalks with cross brows, little legs.
static func crab_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.ellipsoid(Vector3(1.0, 0.55, 0.8), MeshKit.at(Vector3(0, 0.75, 0)), COLOR, 18)
	b.ellipsoid(Vector3(0.8, 0.25, 0.65), MeshKit.at(Vector3(0, 0.5, 0)), Color(1.0, 0.82, 0.6), 14)
	for s in [-1.0, 1.0]:
		b.cylinder(0.06, 0.06, 0.5, MeshKit.at(Vector3(s * 0.32, 1.35, 0.35)), COLOR, 6)
		b.sphere(0.2, MeshKit.at(Vector3(s * 0.32, 1.65, 0.38)), Color(1, 1, 1), 10)
		b.sphere(0.09, MeshKit.at(Vector3(s * 0.32, 1.66, 0.55)), Color(0.08, 0.08, 0.1), 8)
		b.box(Vector3(0.3, 0.06, 0.05), MeshKit.at(Vector3(s * 0.32, 1.88, 0.45), Vector3.ONE, Vector3(0, 0, -s * 0.45)), Color(0.25, 0.1, 0.08))
		for k in 3:
			var z := -0.35 + k * 0.35
			b.capsule(0.07, 0.7, MeshKit.at(Vector3(s * 1.0, 0.35, z), Vector3.ONE, Vector3(0, 0, s * 0.9)), COLOR.darkened(0.15), 6)
	b.box(Vector3(0.4, 0.05, 0.05), MeshKit.at(Vector3(0, 0.82, 0.8), Vector3.ONE, Vector3(0, 0, PI)), Color(0.25, 0.1, 0.08))
	return b.build()


## King Keywind: a round purple tin king on little wheels, a gold crown, a white moustache and cross brows.
static func king_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.cylinder(0.8, 0.9, 1.1, MeshKit.at(Vector3(0, 0.75, 0)), KING_COLOR, 18)
	b.sphere(0.8, MeshKit.at(Vector3(0, 1.3, 0), Vector3(1, 0.6, 1)), KING_COLOR, 18)
	b.cylinder(0.92, 0.92, 0.12, MeshKit.at(Vector3(0, 0.55, 0)), Color(1.0, 0.82, 0.3), 18)
	b.rounded_box(Vector3(0.9, 0.42, 0.08), 0.1, MeshKit.at(Vector3(0, 1.35, 0.72)), Color(0.12, 0.12, 0.2))
	for s in [-1.0, 1.0]:
		b.sphere(0.11, MeshKit.at(Vector3(s * 0.2, 1.4, 0.77)), Color(1.0, 0.95, 0.5), 8, true)
		b.box(Vector3(0.26, 0.06, 0.05), MeshKit.at(Vector3(s * 0.2, 1.58, 0.78), Vector3.ONE, Vector3(0, 0, -s * 0.4)), Color(0.12, 0.1, 0.1))
		b.ellipsoid(Vector3(0.2, 0.07, 0.06), MeshKit.at(Vector3(s * 0.14, 1.2, 0.8), Vector3.ONE, Vector3(0, 0, s * 0.3)), Color(0.97, 0.97, 0.97), 8)
		b.cylinder(0.2, 0.2, 0.14, MeshKit.at(Vector3(s * 0.62, 0.2, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.25, 0.25, 0.3), 12)
	b.cylinder(0.5, 0.55, 0.3, MeshKit.at(Vector3(0, 1.85, 0)), Color(1.0, 0.82, 0.3), 14)
	for k in 6:
		var a := TAU * k / 6.0
		b.cone(0.1, 0.26, MeshKit.at(Vector3(cos(a) * 0.48, 2.1, sin(a) * 0.48)), Color(1.0, 0.82, 0.3), 6)
	b.sphere(0.09, MeshKit.at(Vector3(0, 1.88, 0.52)), Color(0.95, 0.25, 0.4), 8, true)
	return b.build()


func alive() -> bool:
	return state != "dead"


func code() -> int:
	return STATES.find(state)


func _go(st: String) -> void:
	state = st
	st_t = 0.0


## Host: the crab's turn. robots: the robots (Node3D) in play.
func host_step(delta: float, robots: Array) -> void:
	st_t += delta
	for k in hit_cool.keys():
		hit_cool[k] = float(hit_cool[k]) - delta
		if float(hit_cool[k]) <= 0.0:
			hit_cool.erase(k)
	var on_arena: Array = []
	for r in robots:
		var p: Vector3 = (r as Node3D).position
		if Vector2(p.x - arena.x, p.z - arena.z).length() < arena_r and absf(p.y - arena.y) < 2.0:
			on_arena.append(r)
	match state:
		"sleep":
			if not on_arena.is_empty():
				_go("walk")
				main.boss_woke()
		"walk":
			var tgt: Node3D = null
			var bd := INF
			for r in on_arena:
				var d := (r as Node3D).position.distance_to(position)
				if d < bd:
					bd = d
					tgt = r
			if tgt != null and bd > 1.6:
				var dir := tgt.position - position
				dir.y = 0.0
				var np := position + dir.normalized() * float(SPEED[mode]) * delta
				var off := Vector3(np.x - arena.x, 0, np.z - arena.z)
				if off.length() > arena_r - 1.4:
					np = arena + off.normalized() * (arena_r - 1.4)
				np.y = arena.y
				position = np
				rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-6.0 * delta))
			if kind == "king" and (st_t > 2.2 or (tgt != null and st_t > 1.0)):
				_king_aim(tgt)
			elif kind == "crab" and (st_t > 2.6 or (tgt != null and bd < 2.2 and st_t > 1.0)):
				_go("tell")
				main.boss_tell(position, stomp_r, float(TELL[mode]))
		"tell":
			if kind == "king":
				if st_t >= float(KING_TELL[mode]):
					_go("dash")
			elif st_t >= float(TELL[mode]):
				_go("stomp")
				stomps += 1
				main.boss_stomp(position, stomp_r)
		"dash":
			position = position.move_toward(charge_to, float(KING_DASH[mode]) * delta)
			if position.distance_to(charge_to) < 0.02:
				_go("stomp")
				stomps += 1
				main.boss_bonk(position)
		"stomp":
			if st_t > 0.35:
				_go("dizzy")
		"dizzy":
			if st_t > float(DIZZY[mode]):
				_go("walk")
	_target = position
	_target_yaw = rotation.y


## Host, the king: aim a charge at robot tgt (or across the arena) to the rim, and tell it with a warn line.
func _king_aim(tgt: Node3D) -> void:
	var dir := Vector3(arena.x - position.x, 0, arena.z - position.z)
	if tgt != null:
		dir = Vector3(tgt.position.x - position.x, 0, tgt.position.z - position.z)
	if dir.length() < 0.3:
		dir = Vector3(-signf(position.x - arena.x + 0.01), 0, 0)
	dir = dir.normalized()
	# How far to the rim (arena_r - 1.4 from the middle) along dir.
	var o := Vector3(position.x - arena.x, 0, position.z - arena.z)
	var lim := arena_r - 1.4
	var bq := o.dot(dir)
	var run_len := -bq + sqrt(maxf(0.0, bq * bq - (o.length_squared() - lim * lim)))
	if run_len < 2.0:  # (already at the rim: turn round)
		dir = -o.normalized() if o.length() > 0.1 else Vector3.LEFT
		bq = o.dot(dir)
		run_len = -bq + sqrt(maxf(0.0, bq * bq - (o.length_squared() - lim * lim)))
	charge_dir = dir
	charge_to = position + dir * run_len
	charge_to.y = arena.y
	rotation.y = atan2(dir.x, dir.z)
	_go("tell")
	main.boss_line(position, dir, run_len, float(KING_TELL[mode]))


## Host: a punch / hop / poke from `who` (a robot id, or "giant"). True if it counted.
func hit(who: String) -> bool:
	if state != "dizzy" or hit_cool.has(who):
		return false
	hit_cool[who] = 0.45
	hp -= 1
	hits += 1
	if hp <= 0:
		_go("dead")
	return true


## Every machine: claws snap, legs scuttle, stars spin while dizzy, flop over when beaten.
func animate(delta: float) -> void:
	if not host:
		position = position.lerp(_target, 1.0 - exp(-12.0 * delta))
		rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-10.0 * delta))
	var now := Time.get_ticks_msec() * 0.001
	stars.visible = state == "dizzy"
	stars.rotation.y = now * 4.0
	if key != null:
		key.rotation.z += delta * (14.0 if state == "dizzy" else (6.0 if state == "dash" else 1.5))
	if kind == "king":
		match state:
			"tell":
				body.position.y = absf(sin(now * 14.0)) * 0.12
				body.rotation.z = sin(now * 30.0) * 0.05
			"dash":
				body.position.y = 0.0
				body.rotation.x = 0.25
			"dizzy":
				body.rotation.x = 0.0
				body.rotation.z = sin(now * 3.0) * 0.15
			"dead":
				body.rotation.x = lerpf(body.rotation.x, -1.2, 1.0 - exp(-4.0 * delta))
			_:
				body.rotation = Vector3(0, 0, sin(now * 4.0) * 0.04)
				body.position.y = absf(sin(now * 8.0)) * 0.04
		return
	match state:
		"tell":
			body.position.y = absf(sin(now * 18.0)) * 0.25
			for c in claws:
				c.rotation.x = -1.0 + sin(now * 20.0) * 0.3
		"stomp":
			body.position.y = 0.0
		"dizzy":
			body.rotation.z = sin(now * 3.0) * 0.18
			for c in claws:
				c.rotation.x = 0.6
		"dead":
			body.rotation.z = lerpf(body.rotation.z, PI, 1.0 - exp(-4.0 * delta))
			body.position.y = lerpf(body.position.y, 0.9, 1.0 - exp(-4.0 * delta))
		_:
			body.position.y = absf(sin(now * 9.0)) * 0.06
			body.rotation.z = 0.0
			for i in claws.size():
				claws[i].rotation.x = sin(now * 5.0 + i) * 0.4


func pack() -> PackedFloat32Array:
	return PackedFloat32Array([position.x, position.y, position.z, rotation.y, float(code()), float(hp)])


func unpack(a: PackedFloat32Array) -> void:
	if a.size() < 6:
		return
	_target = Vector3(a[0], a[1], a[2])
	_target_yaw = a[3]
	state = STATES[clampi(int(a[4]), 0, STATES.size() - 1)]
	hp = int(a[5])
