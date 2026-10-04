extends Node3D
## COASTER CREW: the tabletop theme park (park-local coordinates; the host turns this node to rotate the
## table for the VR builder). Everything here reacts to a touch (Simon's rule): trees sway, the station
## bell rings, the ice cream stand pops a scoop, balloons float off, the carousel and the big wheel spin
## faster, the fountain splashes, the flags flap, guests jump and giggle (and can be picked up: main.gd).
## A new decoration appears after every ride (decor count in the state store), the same on every machine.
## Cheap: a few merged meshes per prop, no physics bodies, springs in one _process.

const MeshKit := preload("res://core/mesh_kit.gd")
const Creatures := preload("res://core/creatures.gd")
const Track := preload("res://games/roller_coaster/track.gd")

const TREE_SPOTS: Array[Vector3] = [Vector3(-10.1, 0, 4.5), Vector3(-10.8, 0, -3.2), Vector3(-8.3, 0, -8.0), Vector3(-3.2, 0, -10.9),
	Vector3(3.5, 0, -10.7), Vector3(9.3, 0, -4.8), Vector3(10.5, 0, 1.6), Vector3(9.1, 0, 6.9), Vector3(-8.5, 0, 8.3)]
const ICE_CREAM := Vector3(-1.9, 0, 9.7)
const BELL := Vector3(0.3, 0, 7.2)
## Decorations, in the order they arrive (one per ride).
const DECOR: Array = [["balloons", Vector3(7.2, 0, 3.5)], ["carousel", Vector3(-6.1, 0, -4.8)],
	["wheel", Vector3(5.6, 0, -7.2)], ["fountain", Vector3(0.0, 0, -8.8)], ["flags", Vector3(-9.9, 0, 0.0)]]
const GUEST_COUNT := 6
const GUEST_SCALE := 0.8

var trees: Array[Node3D] = []
var props := {}  # kind -> Node3D (bell, ice, decorations)
var springs := {}  # key -> [angle Vector2, velocity Vector2, node, k]
var spin := {}  # kind -> [node, speed, base speed]
var balloons: Array[Node3D] = []
var balloon_t: Array[float] = []
var scoop: Node3D
var scoop_t := 0.0
var fountain_fx: CPUParticles3D
var guests: Array[Node3D] = []
var decor_count := 0
var _t := 0.0


func _ready() -> void:
	_build_table()
	_build_station()
	for i in TREE_SPOTS.size():
		var tr := Node3D.new()
		tr.position = TREE_SPOTS[i]
		add_child(tr)
		var mi := MeshKit.instance(MeshKit.prop("tree", i % 3), false)
		mi.scale = Vector3.ONE * (0.9 + 0.12 * (i % 3))
		tr.add_child(mi)
		trees.append(tr)
		springs["tree%d" % i] = [Vector2.ZERO, Vector2.ZERO, tr, 30.0]
	_build_ice_cream()
	for i in GUEST_COUNT:
		var g := Creatures.humanoid({"class": "villager", "seed": 40 + i, "scale": GUEST_SCALE})
		g.name = "Guest%d" % i
		add_child(g)
		var a := TAU * i / GUEST_COUNT
		g.position = Vector3(cos(a) * 4.0, 0.0, sin(a) * 4.0 - 1.5)
		guests.append(g)


func _build_table() -> void:
	var b := MeshKit.builder()
	b.cylinder(Track.TABLE_R, Track.TABLE_R, 0.4, Transform3D(Basis(), Vector3(0, -0.2, 0)), Color(0.48, 0.76, 0.38), 40)
	b.cylinder(Track.TABLE_R + 0.35, Track.TABLE_R + 0.35, 0.5, Transform3D(Basis(), Vector3(0, -0.45, 0)), Color(0.62, 0.42, 0.25), 40)
	# Paths and a little pond of colour so the park doesn't look empty before any building.
	b.cylinder(1.8, 1.8, 0.03, Transform3D(Basis(), Vector3(-2.0, 0.01, -2.5)), Color(0.9, 0.82, 0.62), 18)
	b.box(Vector3(10.0, 0.03, 1.2), Transform3D(Basis(), Vector3(-2.5, 0.01, 8.3)), Color(0.9, 0.82, 0.62))
	for k in 44:
		var a := k * 2.4
		var r := 2.0 + fmod(k * 1.7, 9.0)
		var c := [Color(1.0, 0.5, 0.6), Color(1.0, 0.9, 0.4), Color(0.7, 0.6, 1.0)][k % 3] as Color
		b.sphere(0.12, Transform3D(Basis(), Vector3(cos(a) * r, 0.1, sin(a) * r)), c, 6)
	var mi := MeshKit.instance(b.build(), false)
	mi.name = "Table"
	add_child(mi)


func _build_station() -> void:
	var b := MeshKit.builder()
	var s := Track.station_start()
	var e := Track.station_end()
	var mid := (s + e) * 0.5
	b.box(Vector3(Track.STATION_LEN + 0.6, 0.7, 1.4), Transform3D(Basis(), Vector3(mid.x, 0.35, mid.z + 1.2)), Track.STATION_COL)
	for x in [-1.0, 1.0]:
		for z in [-0.6, 1.8]:
			b.cylinder(0.08, 0.08, 2.6, Transform3D(Basis(), Vector3(mid.x + x * (Track.STATION_LEN * 0.5), 1.3, mid.z + z)), Color.WHITE, 6)
	b.box(Vector3(Track.STATION_LEN + 1.0, 0.18, 3.0), Transform3D(Basis(), Vector3(mid.x, 2.65, mid.z + 0.6)), Color(0.95, 0.35, 0.4))
	for k in 6:
		b.box(Vector3(0.5, 0.2, 3.05), Transform3D(Basis(), Vector3(mid.x - 2.5 + k, 2.8, mid.z + 0.6)), Color.WHITE if k % 2 == 0 else Color(0.95, 0.35, 0.4))
	var mi := MeshKit.instance(b.build(), false)
	mi.name = "Station"
	add_child(mi)
	# The station bell on its own post (touch it: DING).
	var post := MeshKit.builder()
	post.cylinder(0.06, 0.06, 2.2, Transform3D(Basis(), Vector3(0, 1.1, 0)), Color(0.5, 0.35, 0.2), 6)
	post.box(Vector3(0.5, 0.08, 0.08), Transform3D(Basis(), Vector3(0.2, 2.15, 0)), Color(0.5, 0.35, 0.2))
	var pm := MeshKit.instance(post.build(), false)
	pm.position = BELL
	add_child(pm)
	var pivot := Node3D.new()
	pivot.position = BELL + Vector3(0.4, 2.1, 0)
	add_child(pivot)
	var bb := MeshKit.builder()
	bb.cylinder(0.14, 0.3, 0.42, Transform3D(Basis(), Vector3(0, -0.3, 0)), Color(1.0, 0.8, 0.25), 12)
	bb.sphere(0.07, Transform3D(Basis(), Vector3(0, -0.55, 0)), Color(0.5, 0.4, 0.2), 8)
	pivot.add_child(MeshKit.instance(bb.build(), false))
	props["bell"] = pivot
	springs["bell"] = [Vector2.ZERO, Vector2.ZERO, pivot, 40.0]


func _build_ice_cream() -> void:
	var n := Node3D.new()
	n.position = ICE_CREAM
	add_child(n)
	var b := MeshKit.builder()
	b.box(Vector3(1.4, 0.9, 0.8), Transform3D(Basis(), Vector3(0, 0.45, 0)), Color(0.98, 0.95, 0.9))
	b.box(Vector3(1.42, 0.2, 0.82), Transform3D(Basis(), Vector3(0, 0.75, 0)), Color(1.0, 0.55, 0.7))
	b.cylinder(0.04, 0.04, 1.4, Transform3D(Basis(), Vector3(0, 1.4, 0)), Color.WHITE, 6)
	b.cone(1.0, 0.5, Transform3D(Basis(), Vector3(0, 2.1, 0)), Color(0.5, 0.85, 1.0), 12)
	b.cone(0.25, 0.7, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0.45, 1.25, 0)), Color(0.95, 0.75, 0.45), 10)
	b.sphere(0.27, Transform3D(Basis(), Vector3(0.45, 1.65, 0)), Color(1.0, 0.7, 0.8), 10)
	n.add_child(MeshKit.instance(b.build(), false))
	props["ice"] = n
	springs["ice"] = [Vector2.ZERO, Vector2.ZERO, n, 60.0]
	scoop = MeshKit.instance(_ball_mesh(Color(0.75, 1.0, 0.75)), false)
	scoop.visible = false
	n.add_child(scoop)


func _ball_mesh(c: Color) -> ArrayMesh:
	var b := MeshKit.builder()
	b.sphere(0.27, Transform3D(), c, 10)
	return b.build()


## Show the first `count` decorations (a new one pops in with confetti).
func set_decor(count: int, animate: bool) -> void:
	count = clampi(count, 0, DECOR.size())
	while decor_count < count:
		var d: Array = DECOR[decor_count]
		var n := _make_decor(String(d[0]))
		n.position = d[1]
		add_child(n)
		props[String(d[0])] = n
		springs[String(d[0])] = [Vector2.ZERO, Vector2.ZERO, n, 50.0]
		if animate:
			n.scale = Vector3.ONE * 0.05
			create_tween().tween_property(n, "scale", Vector3.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		decor_count += 1


func _make_decor(kind: String) -> Node3D:
	var n := Node3D.new()
	n.name = kind.capitalize()
	var b := MeshKit.builder()
	match kind:
		"balloons":
			b.box(Vector3(1.2, 0.6, 0.7), Transform3D(Basis(), Vector3(0, 0.3, 0)), Color(0.95, 0.45, 0.35))
			n.add_child(MeshKit.instance(b.build(), false))
			var cols := [Color(1, 0.3, 0.35), Color(1, 0.85, 0.2), Color(0.35, 0.7, 1), Color(0.5, 0.9, 0.4), Color(0.9, 0.5, 1)]
			for i in 5:
				var bl := Node3D.new()
				var bm := MeshKit.builder()
				bm.ellipsoid(Vector3(0.28, 0.34, 0.28), Transform3D(Basis(), Vector3(0, 0.0, 0)), cols[i], 10)
				bm.cylinder(0.01, 0.01, 1.2, Transform3D(Basis(), Vector3(0, -0.8, 0)), Color.WHITE, 3)
				bl.add_child(MeshKit.instance(bm.build(), false))
				bl.position = Vector3(-0.4 + i * 0.2, 2.0 + (i % 2) * 0.35, (i % 3 - 1) * 0.2)
				bl.set_meta("home", bl.position)
				n.add_child(bl)
				balloons.append(bl)
				balloon_t.append(0.0)
		"carousel":
			b.cylinder(1.6, 1.6, 0.25, Transform3D(Basis(), Vector3(0, 0.12, 0)), Color(0.95, 0.85, 0.6), 18)
			b.cylinder(0.15, 0.15, 2.2, Transform3D(Basis(), Vector3(0, 1.3, 0)), Color(1.0, 0.8, 0.3), 8)
			b.cone(1.9, 0.9, Transform3D(Basis(), Vector3(0, 2.7, 0)), Color(0.95, 0.4, 0.55), 16)
			var base := MeshKit.instance(b.build(), false)
			n.add_child(base)
			var top := Node3D.new()
			var tb := MeshKit.builder()
			for i in 6:
				var a := TAU * i / 6.0
				var p := Vector3(cos(a), 0, sin(a)) * 1.15
				tb.cylinder(0.03, 0.03, 2.1, Transform3D(Basis(), p + Vector3(0, 1.3, 0)), Color(1, 0.85, 0.4), 4)
				tb.box(Vector3(0.22, 0.32, 0.6), Transform3D(Basis(Vector3.UP, -a), p + Vector3(0, 0.9, 0)),
					[Color.WHITE, Color(1, 0.7, 0.8), Color(0.7, 0.85, 1)][i % 3], false)
			top.add_child(MeshKit.instance(tb.build(), false))
			n.add_child(top)
			spin["carousel"] = [top, 0.6, 0.6]
		"wheel":
			b.box(Vector3(0.2, 3.4, 0.2), Transform3D(Basis(Vector3.BACK, 0.35), Vector3(-0.55, 1.6, 0)), Color(0.9, 0.9, 0.95))
			b.box(Vector3(0.2, 3.4, 0.2), Transform3D(Basis(Vector3.BACK, -0.35), Vector3(0.55, 1.6, 0)), Color(0.9, 0.9, 0.95))
			n.add_child(MeshKit.instance(b.build(), false))
			var w := Node3D.new()
			w.position = Vector3(0, 3.1, 0)
			var wb := MeshKit.builder()
			wb.torus(1.7, 0.06, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), Color(1.0, 0.45, 0.5), 24, 4)
			for i in 8:
				var a := TAU * i / 8.0
				var p := Vector3(cos(a), sin(a), 0) * 1.7
				wb.tube(Vector3.ZERO, p, 0.03, 0.03, Color.WHITE, 4, false, false)
				wb.box(Vector3(0.4, 0.35, 0.4), Transform3D(Basis(), p - Vector3(0, 0.25, 0)),
					[Color(1, 0.85, 0.2), Color(0.4, 0.75, 1), Color(0.5, 0.9, 0.45)][i % 3])
			w.add_child(MeshKit.instance(wb.build(), false))
			n.add_child(w)
			spin["wheel"] = [w, 0.35, 0.35]
		"fountain":
			b.cylinder(1.3, 1.4, 0.4, Transform3D(Basis(), Vector3(0, 0.2, 0)), Color(0.85, 0.85, 0.9), 18)
			b.cylinder(1.15, 1.15, 0.05, Transform3D(Basis(), Vector3(0, 0.38, 0)), Color(0.35, 0.65, 1.0), 18)
			b.cylinder(0.15, 0.2, 1.0, Transform3D(Basis(), Vector3(0, 0.8, 0)), Color(0.85, 0.85, 0.9), 8)
			n.add_child(MeshKit.instance(b.build(), false))
			fountain_fx = _water_fx(n, Vector3(0, 1.3, 0), 24, 2.5)
			fountain_fx.emitting = true
		"flags":
			b.cylinder(0.06, 0.06, 4.0, Transform3D(Basis(), Vector3(0, 2.0, 0)), Color.WHITE, 6)
			b.sphere(0.12, Transform3D(Basis(), Vector3(0, 4.05, 0)), Color(1, 0.85, 0.3), 8)
			n.add_child(MeshKit.instance(b.build(), false))
			var f := Node3D.new()
			f.position = Vector3(0, 3.7, 0)
			var fb := MeshKit.builder()
			fb.box(Vector3(1.2, 0.7, 0.03), Transform3D(Basis(), Vector3(0.62, 0, 0)), Color(0.35, 0.6, 1.0))
			fb.box(Vector3(0.4, 0.3, 0.04), Transform3D(Basis(), Vector3(0.62, 0, 0)), Color(1, 0.9, 0.3))
			f.add_child(MeshKit.instance(fb.build(), false))
			n.add_child(f)
			spin["flags"] = [f, 0.0, 0.0]
	return n


func _water_fx(parent: Node3D, pos: Vector3, amount: int, speed: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.9
	p.direction = Vector3.UP
	p.spread = 25.0
	p.gravity = Vector3(0, -9.0, 0)
	p.initial_velocity_min = speed * 0.7
	p.initial_velocity_max = speed
	var m := SphereMesh.new()
	m.radius = 0.06
	m.height = 0.12
	m.radial_segments = 6
	m.rings = 3
	m.material = MeshKit.material(Color(0.6, 0.85, 1.0, 0.85))
	p.mesh = m
	p.position = pos
	p.emitting = false
	parent.add_child(p)
	return p


## Things a hand can touch: [[local pos, radius, kind, index], ...] (the host tests the VR hands).
func touch_points() -> Array:
	var out: Array = []
	for i in trees.size():
		out.append([trees[i].position + Vector3(0, 2.0, 0), 1.3, "tree", i])
	out.append([BELL + Vector3(0.4, 1.8, 0), 0.6, "bell", 0])
	out.append([ICE_CREAM + Vector3(0, 1.2, 0), 1.0, "ice", 0])
	for k in ["balloons", "carousel", "wheel", "fountain", "flags"]:
		if props.has(k):
			var n: Node3D = props[k]
			var h := {"balloons": 2.1, "carousel": 1.4, "wheel": 3.0, "fountain": 0.8, "flags": 3.4}[k] as float
			var r := {"balloons": 0.9, "carousel": 1.8, "wheel": 1.9, "fountain": 1.4, "flags": 0.9}[k] as float
			out.append([n.position + Vector3(0, h, 0), r, k, 0])
	return out


## A touch reaction (every machine). dir: the hand's push direction (park-local, flat).
func poke(kind: String, idx: int, dir: Vector3, sfx: Node) -> void:
	var at := Vector3.ZERO
	var push := Vector2(dir.z, -dir.x).limit_length(1.0) * 2.5
	match kind:
		"tree":
			if idx < trees.size():
				_kick("tree%d" % idx, push)
				at = trees[idx].position
				_sound(sfx, "swish", at, -4.0, 0.7)
		"bell":
			_kick("bell", push * 1.6 + Vector2(1.5, 0))
			at = BELL
			_sound(sfx, "bell", at, -2.0, 1.2)
		"ice":
			_kick("ice", push * 0.4)
			at = ICE_CREAM
			scoop.visible = true
			scoop_t = 0.0
			(scoop as MeshInstance3D).mesh = _ball_mesh([Color(0.75, 1.0, 0.75), Color(1.0, 0.75, 0.85), Color(0.8, 0.6, 0.4)][randi() % 3])
			_sound(sfx, "pop", at, 0.0, 0.9)
		"balloons":
			at = props["balloons"].position
			for i in balloons.size():
				if balloon_t[i] <= 0.0:
					balloon_t[i] = 0.01
					break
			_sound(sfx, "boing", at, -3.0, 1.4)
		"carousel", "wheel":
			at = (props[kind] as Node3D).position
			var sp: Array = spin[kind]
			sp[1] = float(sp[2]) * 6.0
			_sound(sfx, "sparkle" if kind == "carousel" else "whoosh", at, -2.0, 1.0)
		"fountain":
			at = props["fountain"].position
			if fountain_fx != null:
				fountain_fx.initial_velocity_max = 7.0
				fountain_fx.amount = 24
			_sound(sfx, "splash", at, -2.0, 1.1)
		"flags":
			at = props["flags"].position
			var sp: Array = spin["flags"]
			sp[1] = 9.0
			_sound(sfx, "swish", at, -3.0, 1.3)
		"guest":
			if idx < guests.size():
				Creatures.anim(guests[idx]).play("jump")
				at = guests[idx].position
				_sound(sfx, "boing", at, -4.0, 1.6)


func _sound(sfx: Node, n: String, at: Vector3, db: float, pitch: float) -> void:
	if sfx != null:
		sfx.play_at(n, to_global(at), db, pitch)


func _kick(key: String, v: Vector2) -> void:
	if springs.has(key):
		var s: Array = springs[key]
		s[1] = (s[1] as Vector2) + v


func _process(delta: float) -> void:
	_t += delta
	for key in springs:
		var s: Array = springs[key]
		var ang: Vector2 = s[0]
		var vel: Vector2 = s[1]
		var k: float = s[3]
		vel += (-ang * k - vel * 3.0) * delta
		ang += vel * delta
		s[0] = ang
		s[1] = vel
		var n: Node3D = s[2]
		n.rotation = Vector3(ang.x * 0.25, n.rotation.y, ang.y * 0.25)
	for kind in spin:
		var sp: Array = spin[kind]
		var node: Node3D = sp[0]
		sp[1] = move_toward(float(sp[1]), float(sp[2]), delta * 0.8)
		if kind == "wheel":
			node.rotation.z += float(sp[1]) * delta
		elif kind == "flags":
			node.rotation.y = sin(_t * 3.0) * 0.25 * (0.3 + float(sp[1]) * 0.15)
			sp[1] = move_toward(float(sp[1]), 0.0, delta * 3.0)
		else:
			node.rotation.y += float(sp[1]) * delta
	if scoop.visible:
		scoop_t += delta
		scoop.position = Vector3(0.45, 1.9 + scoop_t * 2.5 - scoop_t * scoop_t * 3.0, 0)
		if scoop_t > 1.2:
			scoop.visible = false
	for i in balloons.size():
		if balloon_t[i] > 0.0:
			balloon_t[i] += delta
			var home: Vector3 = balloons[i].get_meta("home")
			balloons[i].position = home + Vector3(sin(balloon_t[i] * 2.0) * 0.3, balloon_t[i] * 1.6, 0)
			balloons[i].visible = balloon_t[i] < 4.0
			if balloon_t[i] > 6.0:
				balloon_t[i] = 0.0
				balloons[i].position = home
				balloons[i].visible = true
		else:
			balloons[i].rotation.z = sin(_t * 1.5 + i) * 0.08
	if fountain_fx != null:
		fountain_fx.initial_velocity_max = move_toward(fountain_fx.initial_velocity_max, 2.5, delta * 3.0)
