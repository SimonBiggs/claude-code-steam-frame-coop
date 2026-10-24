extends Node3D
## Simple mode: everything the gardener can reach does something (Simon's rule). World units (x4).
##  - FLOWERS: touch one and it bobs and lets go of a few petals.
##  - a GARDEN GNOME on the ledge: touch him, he rocks and giggles.
##  - a SNAIL creeping along the ledge: touch it, it hides in its shell, then peeks out again.
##  - a little hand RAKE at the right end of the ledge: pick it up (trigger) and scratch the soil.
##  - a BIRD BATH beside the bed (left): touch the water - SPLASH! the little bird hops up and back.
##  - a WIND CHIME on a post (right): brush it - it swings and tinkles. Bees can ring it too.
##  - BUTTERFLIES resting on the rims: reach for one (or a bee buzzes by) and it flutters off and lands
##    somewhere else.
## The host (or local game) checks the hands; the TV gets sounds / bursts as events and the props'
## state in the snapshot. Cheap: about 40 small meshes, no shadows, no physics engine.

const W := preload("res://games/bee_garden/world.gd")

const GNOME := Vector3(-1.35, 0.0, 2.35)
const SNAIL_Z := 2.6
const SNAIL_X := Vector2(0.65, 1.95)
const RAKE_HOME := Vector3(3.85, 0.03, 2.25)
const BATH := Vector3(-5.0, 0.0, 2.9)          # the bowl's water surface (top)
const CHIME := Vector3(4.6, 1.55, 2.9)         # middle of the hanging tubes
const PERCHES: Array[Vector3] = [Vector3(-2.0, 0.19, -1.95), Vector3(2.2, 0.19, -1.95), Vector3(-4.15, 0.19, 0.6),
	Vector3(4.15, 0.19, -0.6), Vector3(-0.6, 0.03, 2.62), Vector3(0.0, 0.19, -1.95)]
const FLY_COLS: Array[Color] = [Color(1.0, 0.55, 0.15), Color(0.45, 0.7, 1.0), Color(1.0, 0.5, 0.8)]

var main
var gnome: Node3D
var gnome_ang := 0.0
var gnome_vel := 0.0
var snail: Node3D
var snail_body: Node3D
var snail_x := 1.3
var snail_dir := 1.0
var snail_hide := 0.0
var rake: Node3D
var rake_xf := Transform3D(Basis(), RAKE_HOME)
var rake_held := false
var bird: Node3D
var bird_hop := 0.0
var chime: Node3D
var chime_ang := 0.0
var chime_vel := 0.0
var flies: Array = []  # {node, wings, perch, pos, from, to, t, state ("rest"/"fly")}
var plant_cd := {}
var cool := {}
var touched := {}  # kind -> count (the bot reads it)
var t := 0.0


func _ready() -> void:
	name = "Props"
	_build_gnome()
	_build_snail()
	_build_rake()
	_build_bath()
	_build_chime()
	for i in 3:
		_build_fly(i)


func _build_gnome() -> void:
	gnome = Node3D.new()
	gnome.position = GNOME
	add_child(gnome)
	var st := _st()
	W.vcyl(st, Vector3(0, 0.03, 0), 0.2, 0.2, 0.06, Color(0.4, 0.3, 0.2), 10)
	W.vcyl(st, Vector3(0, 0.2, 0), 0.11, 0.15, 0.3, Color(0.3, 0.45, 0.85), 10)
	W.vsphere(st, Vector3(0, 0.43, 0), Vector3(0.11, 0.11, 0.11), Color(1.0, 0.82, 0.68), 10, 6)
	W.vsphere(st, Vector3(0, 0.37, 0.08), Vector3(0.1, 0.1, 0.05), Color(0.98, 0.98, 0.98), 8, 4)  # beard (faces +Z)
	W.vsphere(st, Vector3(0, 0.44, 0.11), Vector3(0.03, 0.03, 0.03), Color(1.0, 0.55, 0.5), 6, 4)  # nose
	for s in [-1.0, 1.0]:
		W.vsphere(st, Vector3(s * 0.04, 0.48, 0.095), Vector3(0.015, 0.018, 0.01), Color(0.1, 0.08, 0.05), 6, 4)
	W.vcyl(st, Vector3(0, 0.66, 0), 0.0, 0.12, 0.32, Color(0.9, 0.2, 0.25), 10)
	gnome.add_child(_mesh(st))


func _build_snail() -> void:
	snail = Node3D.new()
	add_child(snail)
	var st := _st()
	W.vsphere(st, Vector3(0, 0.12, 0), Vector3(0.11, 0.11, 0.07), Color(0.85, 0.55, 0.3), 10, 6)  # shell
	W.vsphere(st, Vector3(0, 0.12, 0.05), Vector3(0.06, 0.06, 0.03), Color(0.95, 0.75, 0.45), 8, 4)
	snail.add_child(_mesh(st))
	snail_body = Node3D.new()
	snail.add_child(snail_body)
	var bt := _st()
	W.vsphere(bt, Vector3(0.02, 0.03, 0), Vector3(0.17, 0.035, 0.05), Color(0.75, 0.8, 0.6), 8, 4)
	W.vsphere(bt, Vector3(0.16, 0.08, 0), Vector3(0.045, 0.05, 0.045), Color(0.75, 0.8, 0.6), 8, 4)
	for s in [-1.0, 1.0]:
		W.vcyl(bt, Vector3(0.18, 0.15, s * 0.02), 0.008, 0.01, 0.08, Color(0.75, 0.8, 0.6), 4)
		W.vsphere(bt, Vector3(0.18, 0.2, s * 0.02), Vector3(0.016, 0.016, 0.016), Color(0.15, 0.12, 0.1), 6, 4)
	snail_body.add_child(_mesh(bt))


func _build_rake() -> void:
	rake = Node3D.new()
	add_child(rake)
	var handle := W.mesh_node(rake, W.cyl(0.03, 0.03, 0.7, 6), W.cmat(Color(0.7, 0.45, 0.25)), Vector3(0, 0, -0.35))
	handle.rotation.x = PI / 2.0  # the handle lies along -Z
	var st := _st()
	W.vbox(st, Vector3(0, 0, -0.72), Vector3(0.36, 0.04, 0.05), Color(0.6, 0.62, 0.66))
	for k in 4:
		W.vbox(st, Vector3(-0.15 + k * 0.1, -0.06, -0.74), Vector3(0.025, 0.12, 0.025), Color(0.6, 0.62, 0.66))
	rake.add_child(_mesh(st))
	rake.global_transform = rake_xf


func _build_bath() -> void:
	var st := _st()
	var base := Vector3(BATH.x, W.LAWN_Y, BATH.z)
	var h := BATH.y - W.LAWN_Y
	W.vcyl(st, base + Vector3(0, h * 0.45, 0), 0.12, 0.22, h * 0.9, Color(0.85, 0.85, 0.82), 10)
	W.vcyl(st, Vector3(BATH.x, BATH.y - 0.06, BATH.z), 0.55, 0.3, 0.16, Color(0.88, 0.88, 0.85), 14)
	W.vcyl(st, Vector3(BATH.x, BATH.y + 0.01, BATH.z), 0.47, 0.47, 0.02, Color(0.5, 0.78, 1.0), 14)
	add_child(_mesh(st))
	bird = Node3D.new()
	bird.position = BATH + Vector3(0.45, 0.06, 0.0)
	add_child(bird)
	var bt := _st()
	W.vsphere(bt, Vector3(0, 0.1, 0), Vector3(0.1, 0.09, 0.13), Color(0.3, 0.55, 1.0), 8, 4)
	W.vsphere(bt, Vector3(0, 0.19, 0.1), Vector3(0.07, 0.07, 0.07), Color(0.3, 0.55, 1.0), 8, 4)
	W.vsphere(bt, Vector3(0, 0.15, 0.06), Vector3(0.06, 0.05, 0.04), Color(1.0, 0.5, 0.35), 6, 4)
	W.vbox(bt, Vector3(0, 0.19, 0.19), Vector3(0.03, 0.025, 0.06), Color(1.0, 0.75, 0.2))
	bird.add_child(_mesh(bt))
	bird.rotation.y = -PI * 0.5


func _build_chime() -> void:
	var st := _st()
	var top := 2.1
	W.vbox(st, Vector3(CHIME.x + 0.35, (W.LAWN_Y + top) * 0.5, CHIME.z), Vector3(0.1, top - W.LAWN_Y, 0.1), Color(0.55, 0.37, 0.22))
	W.vbox(st, Vector3(CHIME.x + 0.15, top, CHIME.z), Vector3(0.5, 0.06, 0.06), Color(0.55, 0.37, 0.22))
	add_child(_mesh(st))
	chime = Node3D.new()
	chime.position = Vector3(CHIME.x, top - 0.03, CHIME.z)
	add_child(chime)
	var ct := _st()
	W.vcyl(ct, Vector3(0, -0.1, 0), 0.16, 0.16, 0.03, Color(0.65, 0.45, 0.3), 10)
	for k in 5:
		var a := TAU * k / 5.0
		var ln := 0.35 + k * 0.06
		W.vcyl(ct, Vector3(cos(a) * 0.12, -0.15 - ln * 0.5, sin(a) * 0.12), 0.025, 0.025, ln, Color(0.75, 0.85, 0.95), 6)
	W.vsphere(ct, Vector3(0, -0.5, 0), Vector3(0.05, 0.05, 0.05), Color(0.95, 0.75, 0.3), 6, 4)
	chime.add_child(_mesh(ct, 0.2))


func _build_fly(i: int) -> void:
	var n := Node3D.new()
	add_child(n)
	var wings: Array[MeshInstance3D] = []
	var m := W.cmat(FLY_COLS[i], 0.3)
	for s in [-1.0, 1.0]:
		var piv := MeshInstance3D.new()
		piv.mesh = W.sphere(0.11, 6)
		piv.material_override = m
		piv.scale = Vector3(1.0, 0.12, 0.8)
		piv.position = Vector3(s * 0.1, 0.0, 0.0)
		piv.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piv.set_meta("side", s)
		n.add_child(piv)
		wings.append(piv)
	W.mesh_node(n, W.sphere(0.025, 6), W.cmat(Color(0.2, 0.15, 0.1)), Vector3.ZERO, Vector3(1.0, 1.0, 4.0))
	var perch := i * 2
	var p: Vector3 = PERCHES[perch]
	flies.append({"node": n, "wings": wings, "perch": perch, "pos": p, "from": p, "to": p, "t": 0.0, "state": "rest"})
	n.position = p


func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _mesh(st: SurfaceTool, glow: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = W.vmesh(st, glow)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _count(kind: String) -> void:
	touched[kind] = int(touched.get(kind, 0)) + 1


func _ready_cool(key: String, secs: float) -> bool:
	if float(cool.get(key, 0.0)) > 0.0:
		return false
	cool[key] = secs
	return true


# --- Rake (the gardener's script calls these) -----------------------------------

func rake_tip() -> Vector3:
	return rake.global_transform * Vector3(0.0, -0.12, -0.74)


func try_grab_rake(pos: Vector3, reach: float) -> bool:
	if rake_held:
		return false
	var d := minf(rake.global_position.distance_to(pos), (rake.global_transform * Vector3(0, 0, -0.4)).distance_to(pos))
	if d > reach:
		return false
	rake_held = true
	main.sound("pick", -6.0, 1.2)
	_count("rake")
	return true


func release_rake() -> void:
	rake_held = false


## Where a held rake is drawn (both machines): in the gardener's hand, the handle along the fingers.
func hold_rake(hand_xf: Transform3D) -> void:
	rake_xf = hand_xf * Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0.0, -0.05, 0.05))
	rake.global_transform = rake_xf


# --- Update -------------------------------------------------------------------------

func _process(delta: float) -> void:
	t += delta
	for k in cool.keys():
		cool[k] = float(cool[k]) - delta
	for k in plant_cd.keys():
		plant_cd[k] = float(plant_cd[k]) - delta
	var host: bool = main.net == null or main.net.mode != "client"
	if host:
		_simulate(delta)
	# Looks (both machines).
	gnome.rotation = Vector3(gnome_ang * 0.6, 0.0, gnome_ang)
	snail.position = Vector3(snail_x, 0.0, SNAIL_Z)
	snail.rotation.y = 0.0 if snail_dir > 0.0 else PI
	snail_body.scale = Vector3.ONE * clampf(1.0 - snail_hide * 2.0, 0.05, 1.0)
	snail_body.visible = snail_hide < 0.45
	bird.position = BATH + Vector3(0.45, 0.06 + sin(clampf(bird_hop, 0.0, 1.0) * PI) * 0.6, 0.0)
	chime.rotation = Vector3(chime_ang * 0.5, 0.0, chime_ang)
	var holder = _rake_hand()
	if holder != null:
		hold_rake(holder.xf)
	elif not rake_held:
		rake_xf = rake_xf.interpolate_with(Transform3D(Basis(), RAKE_HOME), 1.0 - exp(-8.0 * delta))
		rake.global_transform = rake_xf
	for f in flies:
		var n: Node3D = f["node"]
		n.global_position = f["pos"]
		var flying: bool = f["state"] == "fly"
		var flap := 0.9 * absf(sin(t * (22.0 if flying else 2.0) + float(f["perch"])))
		for w in f["wings"]:
			var wm: MeshInstance3D = w
			var side: float = wm.get_meta("side")
			wm.rotation.z = side * (0.15 + flap)
		if flying:
			var to: Vector3 = f["to"] - (f["from"] as Vector3)
			if Vector2(to.x, to.z).length() > 0.01:
				n.rotation.y = atan2(-to.x, -to.z)


func _rake_hand():
	var g = main.gardener
	if g == null:
		return null
	for h in g.hands:
		if h.held == "rake":
			return h
	return null


func _simulate(delta: float) -> void:
	gnome_vel += (-gnome_ang * 60.0 - gnome_vel * 3.0) * delta
	gnome_ang = clampf(gnome_ang + gnome_vel * delta, -0.5, 0.5)
	chime_vel += (-chime_ang * 25.0 - chime_vel * 1.2) * delta
	chime_ang = clampf(chime_ang + chime_vel * delta, -0.7, 0.7)
	if absf(chime_vel) > 1.2 and _ready_cool("chime_ring", 0.22):
		main.sound("chime", -12.0, [1.0, 1.125, 1.25, 1.5, 1.667][randi() % 5])
	bird_hop = maxf(0.0, bird_hop - delta * 0.8)
	snail_hide = maxf(0.0, snail_hide - delta * 0.25)
	if snail_hide <= 0.0:
		snail_x += snail_dir * 0.06 * delta
		if snail_x > SNAIL_X.y or snail_x < SNAIL_X.x:
			snail_dir = -snail_dir
			snail_x = clampf(snail_x, SNAIL_X.x, SNAIL_X.y)
	for f in flies:
		if f["state"] == "fly":
			f["t"] = float(f["t"]) + delta
			var k := clampf(float(f["t"]) / 3.5, 0.0, 1.0)
			var a: Vector3 = f["from"]
			var b: Vector3 = f["to"]
			var p := a.lerp(b, ease(k, -1.6)) + Vector3.UP * sin(k * PI) * 1.4
			p += Vector3(sin(float(f["t"]) * 5.0), 0.0, cos(float(f["t"]) * 4.0)) * 0.25 * sin(k * PI)
			f["pos"] = p
			if k >= 1.0:
				f["state"] = "rest"
				f["pos"] = b
	var g = main.gardener
	if g == null:
		return
	var pts: Array = []  # [position, velocity, hand or null]
	for h in g.hands:
		if g.ghost:
			break
		pts.append([h.pos, h.vel, h])
		if h.held == "rake":
			pts.append([rake_tip(), h.vel, h])
			_rake_soil(h)
	for p in pts:
		_touch(p[0], p[1], p[2])
	# Bees ring the chime and startle the butterflies too.
	for bee in main.bees():
		if bee.active:
			_touch_bee(bee.global_position, bee.vel)


func _touch(p: Vector3, v: Vector3, h) -> void:
	var g = main.gardener
	# Flowers: bob and let go of petals.
	for i in main.spots.size():
		var s: Dictionary = main.spots[i]
		if int(s.kind) < 0 or float(s.growth) < 0.3:
			continue
		var hp: Vector3 = main.head_pos(i)
		if p.distance_to(hp) < 0.32 and float(plant_cd.get(i, 0.0)) <= 0.0:
			plant_cd[i] = 0.9
			main.poke_plant(i, v)
			var kd: Dictionary = W.KINDS[int(s.kind)]
			if s.bloom:
				main.burst(hp + Vector3.UP * 0.05, kd.petal, 7, 0.05)
			main.sound("petal", -10.0, randf_range(0.9, 1.2))
			_buzz(g, h, 0.2)
			_count("flower")
	# The gnome giggles.
	if p.distance_to(GNOME + Vector3(0, 0.35, 0)) < 0.35 and _ready_cool("gnome", 1.0):
		gnome_vel += (2.5 if v.x >= 0.0 else -2.5) + v.x * 0.5
		main.sound("giggle", -4.0, 1.0)
		get_tree().create_timer(0.16).timeout.connect(func() -> void: main.sound("giggle", -5.0, 1.2))
		get_tree().create_timer(0.32).timeout.connect(func() -> void: main.sound("giggle", -6.0, 1.45))
		_buzz(g, h, 0.3)
		_count("gnome")
	# The snail hides.
	var sp := Vector3(snail_x, 0.12, SNAIL_Z)
	if snail_hide <= 0.0 and p.distance_to(sp) < 0.28:
		snail_hide = 1.0
		main.sound("pop", -6.0, 1.0)
		_buzz(g, h, 0.2)
		_count("snail")
	# Bird bath: splash!
	if Vector2(p.x - BATH.x, p.z - BATH.z).length() < 0.5 and absf(p.y - BATH.y) < 0.3 and _ready_cool("bath", 0.5):
		main.burst(Vector3(p.x, BATH.y + 0.05, p.z), Color(0.6, 0.85, 1.0), 14, 0.05)
		main.sound("water", -2.0, 1.3)
		bird_hop = 1.0
		_buzz(g, h, 0.3)
		_count("bath")
	if bird_hop <= 0.0 and p.distance_to(bird.global_position + Vector3.UP * 0.12) < 0.25:
		bird_hop = 1.0
		main.sound("tweet", -6.0, 1.0)
		_count("bird")
	# Wind chime.
	if p.distance_to(CHIME) < 0.4 and _ready_cool("chime", 0.4):
		chime_vel += clampf(v.length() * 0.6, 1.5, 4.0) * (1.0 if v.x >= 0.0 else -1.0)
		main.sound("chime", -6.0, 1.0)
		_buzz(g, h, 0.2)
		_count("chime")
	_startle(p, 0.55)


func _touch_bee(p: Vector3, v: Vector3) -> void:
	if p.distance_to(CHIME) < 0.45 and _ready_cool("chime", 0.6):
		chime_vel += 2.0 * (1.0 if v.x >= 0.0 else -1.0)
		main.sound("chime", -6.0, 1.25)
		_count("chime_bee")
	_startle(p, 0.6)


func _startle(p: Vector3, r: float) -> void:
	for f in flies:
		if f["state"] != "rest" or p.distance_to(f["pos"]) > r:
			continue
		var taken := {}
		for o in flies:
			taken[int(o["perch"])] = true
		var opts: Array[int] = []
		for k in PERCHES.size():
			if not taken.has(k):
				opts.append(k)
		var to := int(opts[randi() % opts.size()]) if not opts.is_empty() else int(f["perch"])
		f["perch"] = to
		f["from"] = f["pos"]
		f["to"] = PERCHES[to]
		f["t"] = 0.0
		f["state"] = "fly"
		main.sound("flutter", -10.0, randf_range(0.9, 1.2))
		_count("butterfly")


## A held rake scratching the soil leaves little puffs of earth.
func _rake_soil(h) -> void:
	var tip := rake_tip()
	if tip.y > 0.1 or not W.in_soil(tip.x, tip.z) or Vector2(h.vel.x, h.vel.z).length() < 0.8:
		return
	if _ready_cool("rake_soil", 0.18):
		main.burst(Vector3(tip.x, 0.05, tip.z), Color(0.45, 0.3, 0.18), 5, 0.04)
		main.sound("rake", -10.0, randf_range(0.9, 1.15))
		_buzz(main.gardener, h, 0.15)
		_count("rake_soil")


func _buzz(g, h, amp: float) -> void:
	if h == null or g == null:
		return
	g.haptic(h, amp, 0.05)


## Snapshot entry (the rake follows the gardener's hand on its own, from the hand snapshots).
func net_state() -> PackedFloat32Array:
	var a := PackedFloat32Array([gnome_ang, snail_x, snail_dir, snail_hide, bird_hop, chime_ang, 1.0 if rake_held else 0.0])
	for f in flies:
		var p: Vector3 = f["pos"]
		var to: Vector3 = f["to"]
		a.append_array([p.x, p.y, p.z, 1.0 if f["state"] == "fly" else 0.0, to.x, to.z])
	return a


func apply_net(st: PackedFloat32Array) -> void:
	if st.size() < 7 + flies.size() * 6:
		return
	gnome_ang = st[0]
	snail_x = st[1]
	snail_dir = st[2]
	snail_hide = st[3]
	bird_hop = st[4]
	chime_ang = st[5]
	rake_held = st[6] > 0.5
	for i in flies.size():
		var o := 7 + i * 6
		var f: Dictionary = flies[i]
		f["pos"] = Vector3(st[o], st[o + 1], st[o + 2])
		f["state"] = "fly" if st[o + 3] > 0.5 else "rest"
		f["from"] = f["pos"]
		f["to"] = Vector3(st[o + 4], 0.0, st[o + 5])
