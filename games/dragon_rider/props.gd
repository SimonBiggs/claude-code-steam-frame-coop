extends Node3D
## Simple mode: everything the rider can reach does something when touched (Simon's rule).
##  - The dragon's fluffy mane (on its neck, in front of the saddle): pat it and the dragon purrs,
##    squints happily and puffs a little smoke ring.
##  - The two saddle horns: little gold knobs that honk and wobble.
##  - A lantern hanging on the right of the saddle: it swings, chimes and glows brighter.
##  - A flag on the left of the saddle: it spins round and flutters.
##  - Visitors: little clouds drift past at arm's reach (touch = poof!) and birds fly alongside for a
##    while (touch = they flutter away, tweeting).
## A child of the dragon, so everything is in dragon-local space (the steady, level saddle frame).
## The host reads the rider's hands (touch()) and tells main, which plays the sound and sends the
## reaction to the TV as an event; react() / spawn_visitor() run on both machines. ~30 small meshes,
## no shadows.

const MANE := [Vector3(0, 0.03, -0.62), Vector3(0, -0.02, -0.86), Vector3(0, -0.08, -1.1)]
const HORN_TIPS := [Vector3(-0.42, 0.36, -0.86), Vector3(0.42, 0.36, -0.86)]
const LANTERN_HOOK := Vector3(0.62, 0.42, 0.02)
const FLAG_POLE := Vector3(-0.62, -0.1, 0.12)
const FLAG_H := 0.95
const VISITOR_LIFE := 7.0

var main
var touched := {}            # name -> times touched (tests)
var lantern: Node3D
var lantern_glow: StandardMaterial3D
var lantern_swing := 0.0
var lantern_vel := 0.0
var lantern_bright := 0.0
var flag: Node3D
var flag_spin := 0.0
var flag_t := 0.0
var horns: Array[Node3D] = []
var horn_wobble: Array[float] = [0.0, 0.0]
var mane: Array[Node3D] = []
var mane_wobble := 0.0
var visitors := {}           # id -> {kind, node, t, side, gone, wings}
var next_visitor := 0
var spawn_t := 5.0
var last_hand := {}          # 0/1 -> dragon-local hand position last frame
var cool := {}               # name -> seconds until it can be touched again
var inside := {}             # keys the hands touched last frame (a touch counts when a hand arrives)
var now_in := {}
var t := 0.0
var cloud_mat: StandardMaterial3D
var bird_mats: Array[StandardMaterial3D] = []


func _ready() -> void:
	var gold: StandardMaterial3D = main.color_mat(Color(1.0, 0.8, 0.35), 0.5)
	var wood: StandardMaterial3D = main.color_mat(Color(0.55, 0.36, 0.22), 0.0)
	# Mane: three fluffy tufts running up the neck from the front of the saddle.
	var fur: StandardMaterial3D = main.color_mat(Color(1.0, 0.62, 0.45), 0.15)
	for i in MANE.size():
		var tuft := Node3D.new()
		add_child(tuft)
		tuft.position = MANE[i]
		var m := _mesh(tuft, main.sphere_mesh(0.13 - i * 0.015), fur)
		m.scale = Vector3(1.0, 0.75, 1.3)
		mane.append(tuft)
	# Gold knobs on the saddle horns.
	for p in HORN_TIPS:
		var h := Node3D.new()
		add_child(h)
		h.position = p
		_mesh(h, main.sphere_mesh(0.065), gold)
		horns.append(h)
	# Lantern on a little hook arm (right of the saddle).
	_mesh(self, main.box_mesh(Vector3(0.2, 0.03, 0.03)), wood).position = LANTERN_HOOK + Vector3(-0.1, 0, 0)
	var post := _mesh(self, main.box_mesh(Vector3(0.03, 0.55, 0.03)), wood)
	post.position = LANTERN_HOOK + Vector3(-0.2, -0.27, 0)
	lantern = Node3D.new()
	add_child(lantern)
	lantern.position = LANTERN_HOOK
	_mesh(lantern, main.cyl_mesh(0.005, 0.005, 0.14, 4), wood).position = Vector3(0, -0.07, 0)
	_mesh(lantern, main.cyl_mesh(0.05, 0.07, 0.04, 8), gold).position = Vector3(0, -0.15, 0)
	lantern_glow = main.make_material(Color(1.0, 0.75, 0.35), 2.5)
	var glass := _mesh(lantern, main.sphere_mesh(0.08), lantern_glow)
	glass.position = Vector3(0, -0.24, 0)
	glass.scale = Vector3(1.0, 1.25, 1.0)
	_mesh(lantern, main.cyl_mesh(0.07, 0.05, 0.03, 8), gold).position = Vector3(0, -0.34, 0)
	# Flag on a pole (left of the saddle).
	var pole := _mesh(self, main.cyl_mesh(0.015, 0.02, FLAG_H, 6), wood)
	pole.position = FLAG_POLE + Vector3(0, FLAG_H * 0.5, 0)
	_mesh(self, main.sphere_mesh(0.035), gold).position = FLAG_POLE + Vector3(0, FLAG_H + 0.02, 0)
	flag = Node3D.new()
	add_child(flag)
	flag.position = FLAG_POLE + Vector3(0, FLAG_H - 0.12, 0)
	var cloth_mat: StandardMaterial3D = main.color_mat(Color(0.95, 0.35, 0.45), 0.3)
	cloth_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cloth := _mesh(flag, main.prism_mesh(Vector3(0.2, 0.32, 0.01)), cloth_mat)
	cloth.rotation = Vector3(0, PI / 2.0, PI / 2.0)  # a pennant pointing backwards (+Z)
	cloth.position = Vector3(0, 0, 0.16)
	cloud_mat = main.color_mat(Color(1.0, 1.0, 1.0), 0.35)
	for c in [Color(0.35, 0.65, 1.0), Color(1.0, 0.85, 0.3), Color(1.0, 0.5, 0.55)]:
		bird_mats.append(main.color_mat(c, 0.2))


func _mesh(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


# --- Touch (host, VR rider) ------------------------------------------------------

## hands: the rider's hands in world space. Returns nothing; touches go to main.prop_touched().
func touch(hands: Array, delta: float) -> void:
	for k in cool.keys():
		cool[k] = float(cool[k]) - delta
	inside = now_in
	now_in = {}
	for i in hands.size():
		var p: Vector3 = to_local(hands[i])
		var v := Vector3.ZERO
		if last_hand.has(i) and delta > 0.0:
			v = (p - (last_hand[i] as Vector3)) / delta
		last_hand[i] = p
		# Pat the mane: a hand on the dragon's neck in front of the saddle, moving down a little.
		if p.z < -0.42 and p.z > -1.35 and absf(p.x) < 0.3 and p.y < 0.2 and p.y > -0.3 and v.y < -0.15:
			_hit("pat")
		for h in HORN_TIPS.size():
			if p.distance_to(HORN_TIPS[h]) < 0.13:
				_hit("horn", h)
		if p.distance_to(lantern.position + Vector3(0, -0.24, 0)) < 0.16:
			_hit("lantern", 0, signf(v.z if absf(v.z) > absf(v.x) else v.x))
		if p.distance_to(FLAG_POLE + Vector3(0, FLAG_H - 0.15, 0.1)) < 0.2:
			_hit("flag")
		for id in visitors.keys():
			var vi: Dictionary = visitors[id]
			if vi.gone:
				continue
			var n: Node3D = vi.node
			var r := 0.45 if vi.kind == "cloud" else 0.28
			if p.distance_to(n.position) < r:
				_hit(vi.kind, int(id))


func _hit(what: String, id: int = 0, dir: float = 1.0) -> void:
	var key := "%s%d" % [what, id]
	now_in[key] = true
	if inside.has(key) and what != "pat":
		return  # still touching it: wait until the hand leaves and comes back
	if float(cool.get(key, 0.0)) > 0.0:
		return
	cool[key] = 0.6 if what != "pat" else 1.0
	touched[what] = int(touched.get(what, 0)) + 1
	main.prop_touched(what, id, dir)


## Both machines: the visual reaction to a touch.
func react(what: String, id: int, dir: float) -> void:
	match what:
		"pat":
			mane_wobble = 1.0
		"horn":
			if id >= 0 and id < horn_wobble.size():
				horn_wobble[id] = 1.0
		"lantern":
			lantern_vel += 4.0 * (dir if dir != 0.0 else 1.0)
			lantern_bright = 1.0
		"flag":
			flag_spin = 1.0
		"cloud", "bird":
			if visitors.has(id):
				var vi: Dictionary = visitors[id]
				vi.gone = true
				vi.t = 0.0


# --- Visitors (clouds and birds) ---------------------------------------------------

## Host: time for a new visitor? Returns [kind, side] or [] (main spawns it on both machines).
func want_visitor(delta: float) -> Array:
	spawn_t -= delta
	if spawn_t > 0.0 or visitors.size() >= 2:
		return []
	spawn_t = randf_range(6.0, 10.0)
	return ["cloud" if randi() % 2 == 0 else "bird", -1.0 if randf() < 0.5 else 1.0]


func spawn_visitor(kind: String, id: int, side: float) -> void:
	var n := Node3D.new()
	add_child(n)
	var wings: Array[Node3D] = []
	if kind == "cloud":
		for k in 4:
			var m := _mesh(n, main.sphere_mesh(0.22), cloud_mat)
			m.position = Vector3((k - 1.5) * 0.17, sin(k * 1.7) * 0.05 + (0.06 if k == 1 or k == 2 else 0.0), cos(k * 2.3) * 0.06)
			m.scale = Vector3.ONE * (1.0 if k == 1 or k == 2 else 0.75)
		n.position = Vector3(0.95 * side, 0.6, -14.0)
	else:
		var mat: StandardMaterial3D = bird_mats[id % bird_mats.size()]
		var b := _mesh(n, main.sphere_mesh(0.07), mat)
		b.scale = Vector3(1.0, 0.9, 1.4)
		_mesh(n, main.sphere_mesh(0.05), mat).position = Vector3(0, 0.05, -0.08)
		var beak := _mesh(n, main.prism_mesh(Vector3(0.03, 0.05, 0.03)), main.color_mat(Color(1.0, 0.65, 0.2), 0.2))
		beak.position = Vector3(0, 0.05, -0.14)
		beak.rotation.x = -PI / 2.0
		for s in [-1.0, 1.0]:
			var w := Node3D.new()
			n.add_child(w)
			w.position = Vector3(0.05 * s, 0.02, 0)
			var wm := _mesh(w, main.box_mesh(Vector3(0.13, 0.01, 0.07)), mat)
			wm.position = Vector3(0.065 * s, 0, 0)
			wings.append(w)
		n.position = Vector3(3.5 * side, 2.0, -6.0)
	visitors[id] = {"kind": kind, "node": n, "t": 0.0, "side": side, "gone": false, "wings": wings}


# --- Per frame (both machines) -----------------------------------------------------

func animate(delta: float) -> void:
	t += delta
	# Mane: a happy wiggle after a pat.
	mane_wobble = maxf(0.0, mane_wobble - delta * 1.2)
	for i in mane.size():
		var s := 1.0 + sin(t * 14.0 + i) * 0.12 * mane_wobble
		mane[i].scale = Vector3(s, 2.0 - s, s)
	for h in horns.size():
		horn_wobble[h] = maxf(0.0, horn_wobble[h] - delta * 2.0)
		horns[h].scale = Vector3.ONE * (1.0 + sin(t * 30.0) * 0.25 * horn_wobble[h] + horn_wobble[h] * 0.2)
	# Lantern: a little pendulum.
	lantern_vel += (-lantern_swing * 18.0 - lantern_vel * 1.2) * delta
	lantern_swing += lantern_vel * delta
	lantern.rotation = Vector3(lantern_swing * 0.6, 0.0, lantern_swing)
	lantern_bright = maxf(0.0, lantern_bright - delta * 0.6)
	lantern_glow.emission_energy_multiplier = 2.5 + lantern_bright * 5.0
	# Flag: always waving, spins round when touched.
	flag_spin = maxf(0.0, flag_spin - delta * 0.7)
	flag_t += delta * (1.0 + flag_spin * 3.0)
	flag.rotation.y = sin(flag_t * 5.0) * 0.25 + flag_spin * flag_spin * TAU * 2.0
	for id in visitors.keys():
		var vi: Dictionary = visitors[id]
		vi.t = float(vi.t) + delta
		var n: Node3D = vi.node
		var side: float = vi.side
		var vt: float = vi.t
		if vi.gone:
			# Touched: clouds poof away (shrink), birds flutter up and away.
			if vi.kind == "cloud":
				n.scale = Vector3.ONE * maxf(0.01, 1.0 - vt * 3.0)
			else:
				n.position += Vector3(side * 1.5, 3.0, -2.0) * delta
				_flap(vi, 40.0)
			if vt > 1.2:
				n.queue_free()
				visitors.erase(id)
			continue
		if vi.kind == "cloud":
			n.position.z += 2.6 * delta
			n.position.y = 0.6 + sin(vt * 1.3) * 0.05
			if n.position.z > 6.0:
				n.queue_free()
				visitors.erase(id)
		else:
			var perch := Vector3(0.85 * side, 0.78 + sin(vt * 2.2) * 0.06, -0.55 + sin(vt * 0.9) * 0.12)
			if vt < 2.0:
				n.position = n.position.lerp(perch, 1.0 - exp(-2.0 * delta))
			elif vt < VISITOR_LIFE:
				n.position = n.position.lerp(perch, 1.0 - exp(-4.0 * delta))
			else:
				n.position += Vector3(side * 1.0, 1.2, -3.0) * delta
				if vt > VISITOR_LIFE + 4.0:
					n.queue_free()
					visitors.erase(id)
			n.rotation.y = sin(vt * 1.5) * 0.4
			_flap(vi, 22.0)


func _flap(vi: Dictionary, speed: float) -> void:
	var wings: Array = vi.wings
	var a := sin(float(vi.t) * speed) * 0.7
	for k in wings.size():
		(wings[k] as Node3D).rotation.z = a if k == 0 else -a


## Where a visitor is (world), for bursts.
func visitor_pos(id: int) -> Vector3:
	if visitors.has(id):
		return (visitors[id].node as Node3D).global_position
	return global_position
