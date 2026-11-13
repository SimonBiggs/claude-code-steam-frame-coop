extends Node3D
## SNOWBALL BLITZ: Bobo's friends and the skating pond (third pass). Every siege a friend of Bobo's comes to watch
## (seeded from the siege, from the season's friends: a duckling in spring, a hedgehog in autumn ...). They wait at
## the edge of the frozen pond beside the square, and when the family holds the fort for STAY_WAVES waves (or wins)
## they stay and SKATE: the pond (world.gd "Pond") grows a little with every friend, and all of them glide round it,
## every game, on every machine (saved: save.data.rink, the newest SHOW shown). The visitor is told on a story card.
##   Rink.pick(seed, season) -> friend id      Rink.find(id) -> {id, name, pic, body, belly, ears, beak, seasons}
##   rink.show_friends(ids)   rink.set_visitor(id)   (every machine: main.gd sends "rink" [ids, visitor])

const MeshKit := preload("res://core/mesh_kit.gd")
const Seeded := preload("res://core/seeded.gd")

const FRIENDS: Array[Dictionary] = [
	{"id": "pip", "name": "PIP", "pic": "penguin", "body": Color(0.16, 0.2, 0.34), "belly": Color(0.97, 0.97, 1.0), "ears": "", "beak": true,
		"seasons": ["spring", "summer", "autumn", "winter"]},
	{"id": "rusty", "name": "RUSTY", "pic": "fox", "body": Color(0.92, 0.45, 0.12), "belly": Color(1.0, 0.92, 0.8), "ears": "point", "beak": false,
		"seasons": ["spring", "autumn", "winter"]},
	{"id": "hoot", "name": "HOOT", "pic": "owl", "body": Color(0.5, 0.35, 0.22), "belly": Color(0.9, 0.8, 0.6), "ears": "tuft", "beak": true,
		"seasons": ["autumn", "winter"]},
	{"id": "ollie", "name": "OLLIE", "pic": "otter", "body": Color(0.42, 0.28, 0.18), "belly": Color(0.85, 0.72, 0.55), "ears": "round", "beak": false,
		"seasons": ["spring", "summer", "autumn", "winter"]},
	{"id": "bun", "name": "BUN", "pic": "bunny", "body": Color(0.72, 0.62, 0.55), "belly": Color(1.0, 0.95, 0.9), "ears": "long", "beak": false,
		"seasons": ["spring", "winter"]},
	{"id": "prickles", "name": "PRICKLES", "pic": "hedgehog", "body": Color(0.45, 0.36, 0.3), "belly": Color(0.95, 0.85, 0.7), "ears": "round", "beak": false,
		"seasons": ["summer", "autumn"]},
	{"id": "nutkin", "name": "NUTKIN", "pic": "squirrel", "body": Color(0.75, 0.32, 0.15), "belly": Color(1.0, 0.88, 0.75), "ears": "point", "beak": false,
		"seasons": ["spring", "summer", "autumn"]},
	{"id": "dot", "name": "DOT", "pic": "duckling", "body": Color(1.0, 0.85, 0.2), "belly": Color(1.0, 0.95, 0.6), "ears": "", "beak": true,
		"seasons": ["spring", "summer"]},
]
const STAY_WAVES := 3  # waves held before the visitor stays to skate (a win always does)
const SHOW := 16  # skaters shown (the newest)
const KEEP := 40  # friends kept in the save
const POND_R := 3.2  # == world.gd's pond
const GROW := 0.12  # the pond's radius grows this much per friend...
const POND_MAX := 4.6  # ...up to this (it grows outward: its near edge stays by the fence)
const SKATER := 0.75  # a skater's size (metres tall-ish)

var pond: Node3D
var pond_home := Vector3.ZERO
var skaters: Array = []  # [{node, r, a, speed}]
var visitor: Node3D
var visitor_id := ""
var friend_ids: Array = []
var _t := 0.0


static func find(id: String) -> Dictionary:
	for f in FRIENDS:
		if f.id == id:
			return f
	return {}


## The siege's visitor: a friend from the season's friends, from the seed (the same on every machine, all day for
## TODAY'S BLIZZARD).
static func pick(seed_value: int, season: String) -> String:
	var pool: Array = FRIENDS.filter(func(f: Dictionary) -> bool: return (f.seasons as Array).has(season))
	if pool.is_empty():
		pool = FRIENDS
	var r := Seeded.rng(seed_value, "friend")
	return String(pool[r.randi_range(0, pool.size() - 1)].id)


static func pond_radius(n: int) -> float:
	return minf(POND_MAX, POND_R + GROW * float(n))


## Attach to world.gd's pond (call once it exists).
func attach(p: Node3D) -> void:
	pond = p
	pond_home = p.position


## Every machine: the friends who stayed (oldest first) skate round the pond; it grows with them.
func show_friends(ids: Array) -> void:
	if friend_ids == ids and skaters.size() == mini(ids.size(), SHOW):
		return
	var grew := ids.size() > friend_ids.size() and not friend_ids.is_empty()
	friend_ids = ids.duplicate()
	for s in skaters:
		(s.node as Node3D).queue_free()
	skaters.clear()
	var r := pond_radius(ids.size())
	if pond != null and is_instance_valid(pond):
		pond.scale = Vector3(r / POND_R, 1.0, r / POND_R)
		pond.position = pond_home + Vector3(r - POND_R, 0.0, 0.0)  # (outward: away from the square)
	var shown := ids.slice(maxi(0, ids.size() - SHOW))
	for i in shown.size():
		var f := find(String(shown[i]))
		if f.is_empty():
			continue
		var n := critter(f, SKATER)
		add_child(n)
		var lane := 0.9 + fmod(float(i) * 0.61, maxf(0.3, r - 1.6))
		skaters.append({"node": n, "r": lane, "a": float(i) * 2.39, "speed": (0.55 + fmod(float(i) * 0.37, 0.5)) * (1.0 if i % 3 != 2 else -1.0)})
		if grew and i == shown.size() - 1:
			n.scale = Vector3.ONE * 0.05
			n.create_tween().tween_property(n, "scale", Vector3.ONE, 1.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_place(0.0)


## Every machine: this siege's visitor waits on the snow at the pond's near edge, waving ("" = none).
func set_visitor(id: String) -> void:
	if id == visitor_id:
		return
	visitor_id = id
	if visitor != null and is_instance_valid(visitor):
		visitor.queue_free()
	visitor = null
	var f := find(id)
	if f.is_empty():
		return
	visitor = critter(f, SKATER * 1.25)
	visitor.name = "Visitor"
	add_child(visitor)
	_place(0.0)


func centre() -> Vector3:
	return pond.position if pond != null and is_instance_valid(pond) else pond_home


func _process(delta: float) -> void:
	_t += delta
	_place(delta)


func _place(delta: float) -> void:
	var c := centre()
	for s in skaters:
		s.a = float(s.a) + float(s.speed) * delta / maxf(0.5, float(s.r)) * 1.6
		var a: float = s.a
		var n: Node3D = s.node
		n.position = c + Vector3(cos(a) * float(s.r), 0.04, sin(a) * float(s.r))
		var fwd := Vector3(-sin(a), 0.0, cos(a)) * signf(float(s.speed))
		n.rotation = Vector3(0.0, atan2(fwd.x, fwd.z), sin(_t * 3.0 + a) * 0.12)
	if visitor != null and is_instance_valid(visitor):
		var near := c + (Vector3.ZERO - c).normalized() * (pond_radius(friend_ids.size()) + 0.6)
		near.y = absf(sin(_t * 5.0)) * 0.12  # hopping with excitement
		visitor.position = near
		visitor.rotation = Vector3(0.0, atan2(-near.x, -near.z), 0.0)  # facing the fort


## One little animal (looks down +Z): a round body in its colour with a pale belly, a head, ears / a beak, a scarf.
static func critter(f: Dictionary, size: float) -> Node3D:
	var b := MeshKit.Builder.new()
	var body: Color = f.body
	var belly: Color = f.belly
	var k := size
	b.sphere(0.32 * k, MeshKit.at(Vector3(0, 0.36 * k, 0), Vector3(1.0, 1.15, 0.95)), body, 12)
	b.sphere(0.22 * k, MeshKit.at(Vector3(0, 0.33 * k, 0.14 * k), Vector3(1.0, 1.2, 0.6)), belly, 10)
	b.sphere(0.22 * k, MeshKit.at(Vector3(0, 0.82 * k, 0.02 * k)), body, 12)
	b.sphere(0.04 * k, MeshKit.at(Vector3(-0.08 * k, 0.86 * k, 0.2 * k)), Color(0.08, 0.08, 0.1), 6)
	b.sphere(0.04 * k, MeshKit.at(Vector3(0.08 * k, 0.86 * k, 0.2 * k)), Color(0.08, 0.08, 0.1), 6)
	if bool(f.beak):
		b.cone(0.06 * k, 0.12 * k, MeshKit.at(Vector3(0, 0.78 * k, 0.24 * k), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.55, 0.1), 6)
	else:
		b.sphere(0.045 * k, MeshKit.at(Vector3(0, 0.78 * k, 0.23 * k)), Color(0.15, 0.1, 0.1), 6)
	for side in [-1.0, 1.0]:
		match String(f.ears):
			"point", "tuft":
				b.cone(0.07 * k, 0.16 * k, MeshKit.at(Vector3(side * 0.12 * k, 1.02 * k, 0), Vector3.ONE, Vector3(0, 0, -side * 0.3)), body, 6)
			"round":
				b.sphere(0.07 * k, MeshKit.at(Vector3(side * 0.15 * k, 0.99 * k, 0)), body, 8)
			"long":
				b.sphere(0.06 * k, MeshKit.at(Vector3(side * 0.08 * k, 1.18 * k, 0), Vector3(0.8, 2.6, 0.6), Vector3(0, 0, -side * 0.15)), body, 8)
	# a scarf in Bobo's red, and little skates
	b.cylinder(0.2 * k, 0.22 * k, 0.07 * k, MeshKit.at(Vector3(0, 0.63 * k, 0.01 * k)), Color(0.9, 0.2, 0.25), 12)
	for side in [-1.0, 1.0]:
		b.box(Vector3(0.08, 0.05, 0.26) * k, MeshKit.at(Vector3(side * 0.12 * k, 0.03 * k, 0.02 * k)), Color(0.75, 0.8, 0.9))
	var root := Node3D.new()
	root.add_child(MeshKit.instance(b.build(), false))
	root.set_meta("friend", String(f.id))
	return root