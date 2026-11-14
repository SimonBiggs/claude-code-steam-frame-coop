extends Node3D
## SKY BOTS: CRANKY CRAB, Crab Cove's little boss on its round arena. Grumpy, never scary: it scuttles towards a
## robot, then TELLS its stomp (a ring of warn rings round it, core/warn_rings.gd, sent to every machine), STOMPS (a
## bump for robots inside the ring), and is DIZZY for a while (stars spin round its head): punch it, hop on it, or the
## VR giant gives it a poke. Enough bonks and it flops over, sorry, and the SPARK drops on the arena.
## The host runs it; the TV machine draws it from pack().

const MeshKit := preload("res://core/mesh_kit.gd")
const Contrast := preload("res://core/contrast.gd")

const COLOR := Color(1.0, 0.42, 0.28)
const RING_COLOR := Color(1.0, 0.3, 0.45)
const STATES: Array[String] = ["sleep", "walk", "tell", "stomp", "dizzy", "dead"]
const TELL := {"gentle": 1.7, "brave": 1.35, "hard": 1.05}
const DIZZY := {"gentle": 4.5, "brave": 3.6, "hard": 3.0}
const SPEED := {"gentle": 1.6, "brave": 2.2, "hard": 2.9}

var main: Node
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
	arena = bd.c
	arena_r = float(bd.r) + 1.2
	hp = int(bd.hp)
	hp_max = hp
	position = arena + Vector3(arena_r * 0.35, 0, -1.0)
	_target = position
	body = Node3D.new()
	add_child(body)
	var mi := MeshKit.instance(crab_mesh(), false)
	Contrast.outline(mi, Contrast.OUTLINE)
	body.add_child(mi)
	for s in [-1.0, 1.0]:
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
	stars.position = Vector3(0, 1.9, 0)
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
			if st_t > 2.6 or (tgt != null and bd < 2.2 and st_t > 1.0):
				_go("tell")
				main.boss_tell(position, stomp_r, float(TELL[mode]))
		"tell":
			if st_t >= float(TELL[mode]):
				_go("stomp")
				stomps += 1
				main.boss_stomp(position, stomp_r)
		"stomp":
			if st_t > 0.35:
				_go("dizzy")
		"dizzy":
			if st_t > float(DIZZY[mode]):
				_go("walk")
	_target = position
	_target_yaw = rotation.y


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
