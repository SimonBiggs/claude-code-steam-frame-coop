extends Node3D
## Simple mode: everything the VR chef can reach does something (Simon's rule).
## Two little side tables flank the chef:
##  - LEFT: two PANS hanging from a rail: hit them (hand, knife, spoon or a thrown veggie) - CLANG! they
##    swing. A BOWL of veggies (a potato, an onion, a carrot): squeeze to pick one up, throw it, juggle,
##    catch it in the air. It bounces about and pops back into the bowl a bit later. BOING off a runner.
##  - RIGHT: a wooden SPOON: pick it up and bang the pans, the counter or the bell. A PEPPER GRINDER:
##    touch it - it spins and puffs pepper. A CUCKOO CLOCK: touch it - the bird pops out, CUCKOO!
## The service bell on the counter (chef.gd) rings too: "ORDER UP!".
## The host (or local game) checks the hands; the TV gets sounds / bursts as events and the pans, grinder,
## bird, spoon and veggies in the snapshot. Cheap: ~30 small meshes, no shadows, no physics engine.

const LEFT_TABLE := Vector3(-0.8, 0.0, 0.5)
const RIGHT_TABLE := Vector3(0.8, 0.0, 0.5)
const TABLE_TOP := 0.9
const TABLE_SIZE := Vector3(0.36, 0.04, 0.36)
const PAN_HOOK: Array[Vector3] = [Vector3(-0.66, 1.55, 0.48), Vector3(-0.9, 1.52, 0.48)]
const PAN_DROP := 0.24  # pan centre below its hook
const BOWL := Vector3(-0.78, TABLE_TOP, 0.52)
const SPOON_HOME := Vector3(0.84, TABLE_TOP + 0.015, 0.56)
const GRINDER := Vector3(0.7, TABLE_TOP, 0.42)
const CLOCK := Vector3(0.94, 1.5, 0.62)
const VEG := [["potato", Color(0.72, 0.52, 0.3)], ["onion", Color(0.78, 0.5, 0.78)], ["carrot", Color(1.0, 0.5, 0.12)]]
const GRAB_R := 0.13

var main
var pans: Array = []  # {pivot, ang, vel}
var veg: Array = []  # {node, home, pos, vel, state ("home", "held", "fly", "rest"), rest_t}
var spoon: Node3D
var spoon_pos := SPOON_HOME
var spoon_vel := Vector3.ZERO
var spoon_state := "home"
var spoon_rest := 0.0
var spoon_yaw := 0.0
var grinder: Node3D
var grinder_spin := 0.0
var grinder_rot := 0.0
var bird: Node3D
var bird_out := 0.0
var pendulum: Node3D
var held: Array = ["", ""]  # per hand: "" / "spoon" / "veg:i"
var prev_pt: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var hand_vel: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var cool := {}
var touched := {}  # kind -> count (the bot reads it)
var t := 0.0


func _ready() -> void:
	name = "Props"
	var wood: StandardMaterial3D = main.mat(Color(0.72, 0.48, 0.28))
	for tp in [LEFT_TABLE, RIGHT_TABLE]:
		_box(self, TABLE_SIZE, tp + Vector3(0, TABLE_TOP - 0.02, 0), wood)
		_box(self, Vector3(0.05, TABLE_TOP - 0.04, 0.05), tp + Vector3(0, (TABLE_TOP - 0.04) * 0.5, 0), wood)
	# Pan rail: a post at the back of the left table with an arm over it.
	_box(self, Vector3(0.04, 1.62 - TABLE_TOP, 0.04), Vector3(-0.96, (1.62 + TABLE_TOP) * 0.5, 0.48), wood)
	_box(self, Vector3(0.4, 0.03, 0.03), Vector3(-0.78, 1.6, 0.48), main.mat(Color(0.6, 0.6, 0.65)))
	for i in PAN_HOOK.size():
		var piv := Node3D.new()
		piv.position = PAN_HOOK[i]
		add_child(piv)
		_box(piv, Vector3(0.025, 0.14, 0.012), Vector3(0, -0.07, 0), main.mat(Color(0.25, 0.22, 0.2)))
		var pan := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.1 - i * 0.015
		cm.bottom_radius = 0.085 - i * 0.015
		cm.height = 0.035
		cm.radial_segments = 14
		cm.rings = 1
		pan.mesh = cm
		pan.material_override = main.mat(Color(0.35, 0.36, 0.4) if i == 0 else Color(0.85, 0.5, 0.25))
		pan.rotation.z = PI / 2.0  # the bottom faces the chef
		pan.position = Vector3(0, -PAN_DROP + 0.02 * i, 0)
		pan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piv.add_child(pan)
		pans.append({"pivot": piv, "ang": 0.0, "vel": 0.0})
	# Veggie bowl.
	var bowl := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.12
	bm.bottom_radius = 0.07
	bm.height = 0.06
	bm.radial_segments = 12
	bm.rings = 1
	bowl.mesh = bm
	bowl.material_override = main.mat(Color(0.3, 0.65, 0.85))
	bowl.position = BOWL + Vector3(0, 0.03, 0)
	bowl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bowl)
	for i in VEG.size():
		var n := Node3D.new()
		add_child(n)
		var c: Color = VEG[i][1]
		if VEG[i][0] == "carrot":
			var cone := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.028
			cyl.bottom_radius = 0.0
			cyl.height = 0.14
			cyl.radial_segments = 8
			cyl.rings = 1
			cone.mesh = cyl
			cone.material_override = main.mat(c)
			cone.rotation.x = PI / 2.0
			n.add_child(cone)
			_box(n, Vector3(0.03, 0.03, 0.04), Vector3(0, 0, 0.08), main.mat(Color(0.3, 0.75, 0.25)))
		else:
			var s := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.045
			sm.height = 0.09
			sm.radial_segments = 10
			sm.rings = 5
			s.mesh = sm
			s.material_override = main.mat(c)
			s.scale = Vector3(1.25, 0.85, 1.0) if VEG[i][0] == "potato" else Vector3.ONE
			n.add_child(s)
		var home := BOWL + Vector3((i - 1) * 0.06, 0.08, (i % 2) * 0.04 - 0.02)
		n.position = home
		veg.append({"node": n, "home": home, "pos": home, "vel": Vector3.ZERO, "state": "home", "rest_t": 0.0})
	# Wooden spoon (lies on the right table, pointing away from the chef like a knife in the hand).
	spoon = Node3D.new()
	add_child(spoon)
	_box(spoon, Vector3(0.022, 0.012, 0.2), Vector3(0, 0, -0.04), wood)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.035
	hm.height = 0.03
	hm.radial_segments = 10
	hm.rings = 4
	head.mesh = hm
	head.material_override = wood
	head.position = Vector3(0, 0, -0.16)
	spoon.add_child(head)
	# Pepper grinder.
	grinder = Node3D.new()
	grinder.position = GRINDER
	add_child(grinder)
	var gm := MeshInstance3D.new()
	var gc := CylinderMesh.new()
	gc.top_radius = 0.025
	gc.bottom_radius = 0.035
	gc.height = 0.18
	gc.radial_segments = 10
	gc.rings = 1
	gm.mesh = gc
	gm.material_override = main.mat(Color(0.35, 0.2, 0.12))
	gm.position.y = 0.09
	grinder.add_child(gm)
	var knob := _box(grinder, Vector3(0.05, 0.03, 0.02), Vector3(0, 0.2, 0), main.mat(Color(0.9, 0.75, 0.3)))
	knob.name = "Knob"
	# Cuckoo clock on a post at the back of the right table, facing the chef.
	_box(self, Vector3(0.04, CLOCK.y - TABLE_TOP, 0.04), Vector3(CLOCK.x + 0.04, (CLOCK.y + TABLE_TOP) * 0.5 - 0.1, CLOCK.z), wood)
	var clock := Node3D.new()
	clock.position = CLOCK
	clock.rotation.y = -PI / 2.0  # the face (+Z) turns to -X, towards the chef
	add_child(clock)
	_box(clock, Vector3(0.2, 0.2, 0.08), Vector3.ZERO, main.mat(Color(0.55, 0.32, 0.18)))
	_box(clock, Vector3(0.24, 0.03, 0.1), Vector3(0, 0.12, 0), main.mat(Color(0.8, 0.25, 0.2)))
	var face := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.06
	fm.bottom_radius = 0.06
	fm.height = 0.01
	fm.radial_segments = 14
	fm.rings = 1
	face.mesh = fm
	face.material_override = main.mat(Color(1.0, 0.97, 0.88))
	face.rotation.x = PI / 2.0
	face.position = Vector3(0, -0.02, 0.042)
	clock.add_child(face)
	_box(clock, Vector3(0.008, 0.045, 0.004), Vector3(0, 0.0, 0.05), main.mat(Color(0.1, 0.1, 0.1)))
	_box(clock, Vector3(0.05, 0.04, 0.01), Vector3(0, 0.075, 0.042), main.mat(Color(0.2, 0.12, 0.08)))  # the little door
	bird = Node3D.new()
	clock.add_child(bird)
	var bb := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.025
	bs.height = 0.05
	bs.radial_segments = 8
	bs.rings = 4
	bb.mesh = bs
	bb.material_override = main.mat(Color(1.0, 0.85, 0.2), 0.4)
	bird.add_child(bb)
	_box(bird, Vector3(0.012, 0.01, 0.025), Vector3(0, 0, 0.03), main.mat(Color(1.0, 0.5, 0.1)))
	pendulum = Node3D.new()
	pendulum.position = Vector3(0, -0.1, 0.02)
	clock.add_child(pendulum)
	_box(pendulum, Vector3(0.006, 0.14, 0.006), Vector3(0, -0.07, 0), main.mat(Color(0.85, 0.7, 0.3)))
	_box(pendulum, Vector3(0.035, 0.035, 0.01), Vector3(0, -0.15, 0), main.mat(Color(0.95, 0.8, 0.3), 0.3))
	_place_spoon(SPOON_HOME, 0.0)


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _place_spoon(pos: Vector3, yaw: float) -> void:
	spoon.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)


func pan_centre(i: int) -> Vector3:
	var piv: Node3D = pans[i]["pivot"]
	return piv.global_transform * Vector3(0, -PAN_DROP, 0)


func spoon_head() -> Vector3:
	return spoon.global_transform * Vector3(0, 0, -0.16)


func holding(h: int) -> bool:
	return held[h] != ""


## The chef squeezed with an empty hand that didn't find an ingredient: grab a veggie or the spoon.
func try_grab(h: int, point: Vector3) -> bool:
	var best := ""
	var best_d := GRAB_R
	for i in veg.size():
		if veg[i]["state"] == "held":
			continue
		var d: float = (veg[i]["pos"] as Vector3).distance_to(point)
		if d < best_d:
			best_d = d
			best = "veg:%d" % i
	if spoon_state != "held":
		var d2 := minf(spoon.global_position.distance_to(point), spoon_head().distance_to(point))
		if d2 < best_d:
			best = "spoon"
	if best == "":
		return false
	held[h] = best
	if best == "spoon":
		spoon_state = "held"
	else:
		veg[int(best.substr(4))]["state"] = "held"
	main.sfx_local("pickup", -12.0, 1.5)
	_count("grab")
	return true


## Let go: whatever the hand holds flies off with the hand's speed.
func release(h: int) -> void:
	var what: String = held[h]
	held[h] = ""
	var v: Vector3 = hand_vel[h].limit_length(7.0)
	if what == "spoon":
		spoon_state = "fly"
		spoon_vel = v
	elif what.begins_with("veg:"):
		var vg: Dictionary = veg[int(what.substr(4))]
		vg["state"] = "fly"
		vg["vel"] = v
		if v.length() > 1.5:
			_count("throw")


func _count(kind: String) -> void:
	touched[kind] = int(touched.get(kind, 0)) + 1


func _ready_cool(key: String, secs: float) -> bool:
	if float(cool.get(key, 0.0)) > 0.0:
		return false
	cool[key] = secs
	return true


func _process(delta: float) -> void:
	t += delta
	for k in cool.keys():
		cool[k] = float(cool[k]) - delta
	var host: bool = main.net == null or main.net.mode != "client"
	if host:
		_simulate(delta)
	# Looks (both machines).
	for p in pans:
		var piv: Node3D = p["pivot"]
		piv.rotation.z = float(p["ang"])
	grinder_rot += grinder_spin * delta
	var knob: Node3D = grinder.get_node("Knob")
	knob.rotation.y = grinder_rot
	bird.position = Vector3(0, 0.075, 0.03 + 0.07 * clampf(bird_out * 3.0, 0.0, 1.0))
	bird.visible = bird_out > 0.0
	bird.rotation.x = sin(t * 18.0) * 0.3 if bird_out > 0.0 else 0.0
	pendulum.rotation.z = sin(t * 3.0) * 0.35
	for vg in veg:
		var n: Node3D = vg["node"]
		n.global_position = vg["pos"]
		if vg["state"] == "fly":
			n.rotation += Vector3(6.0, 4.0, 0.0) * delta


func _simulate(delta: float) -> void:
	for p in pans:
		p["vel"] = float(p["vel"]) - float(p["ang"]) * 40.0 * delta
		p["vel"] = float(p["vel"]) * (1.0 - 1.8 * delta)
		p["ang"] = clampf(float(p["ang"]) + float(p["vel"]) * delta, -0.9, 0.9)
	grinder_spin = move_toward(grinder_spin, 0.0, delta * 10.0)
	bird_out = maxf(0.0, bird_out - delta)
	var chef = main.players[0] if not main.players.is_empty() else null
	var vr: bool = chef != null and chef.vr and chef.hand_l != null
	# Hands: where they are, how fast they move, what they hold.
	if vr:
		for h in 2:
			var pt: Vector3 = chef.hand_point(h)
			if prev_pt[h] != Vector3.ZERO:
				hand_vel[h] = hand_vel[h].lerp((pt - prev_pt[h]) / maxf(delta, 0.001), 0.5)
			prev_pt[h] = pt
			var hand: Node3D = chef.hand_l if h == 0 else chef.hand_r
			var what: String = held[h]
			if what == "spoon":
				spoon.global_transform = hand.global_transform.translated_local(Vector3(0, -0.012, -0.04))
				spoon_pos = spoon.global_position
			elif what.begins_with("veg:"):
				veg[int(what.substr(4))]["pos"] = pt + Vector3.DOWN * 0.03
	# Flying and resting things.
	for vg in veg:
		match vg["state"]:
			"fly":
				_fly(vg, delta)
			"rest":
				vg["rest_t"] = float(vg["rest_t"]) + delta
				if vg["rest_t"] > 3.0:
					_home_veg(vg)
	if spoon_state == "fly" or spoon_state == "rest":
		_fly_spoon(delta)
	if vr:
		_touches(chef)


## Ballistic flight with soft bounces on the counter, the side tables and the floor.
func _fly(vg: Dictionary, delta: float) -> void:
	var v: Vector3 = vg["vel"]
	var p: Vector3 = vg["pos"]
	v.y -= 9.8 * delta
	p += v * delta
	var g := _ground(p)
	if p.y < g + 0.03 and v.y < 0.0:
		p.y = g + 0.03
		if v.y < -1.2:
			main.sound("chop", -10.0, 0.5)
		v = Vector3(v.x * 0.55, -v.y * 0.35, v.z * 0.55)
		if absf(v.y) < 0.5:
			v = Vector3.ZERO
			vg["state"] = "rest"
			vg["rest_t"] = 0.0
	# Bonk a runner on the head.
	for i in range(1, main.players.size()):
		var r = main.players[i]
		if not r.active:
			continue
		var rp: Vector3 = r.global_position
		if main.flat_dist(rp, p) < 0.4 and p.y > 0.6 and p.y < 2.0 and _ready_cool("bonk%d" % i, 0.5):
			main.sound("boing", -2.0, randf_range(0.9, 1.2))
			main.burst(p, Color(1.0, 0.9, 0.4), 8, 0.04)
			v = Vector3((p - rp).x, 1.5, (p - rp).z).normalized() * 2.0
			_count("bonk")
	p.x = clampf(p.x, -L_ROOM.x, L_ROOM.x)
	p.z = clampf(p.z, -L_ROOM.y - 6.0, L_ROOM.y)
	vg["pos"] = p
	vg["vel"] = v


const L_ROOM := Vector2(6.8, 5.8)


func _ground(p: Vector3) -> float:
	if absf(p.x) < 1.25 and absf(p.z) < 0.3:
		return 0.95
	for tp in [LEFT_TABLE, RIGHT_TABLE]:
		if absf(p.x - tp.x) < TABLE_SIZE.x * 0.5 and absf(p.z - tp.z) < TABLE_SIZE.z * 0.5:
			return TABLE_TOP
	return 0.0


func _home_veg(vg: Dictionary) -> void:
	main.burst(vg["pos"], Color(1.0, 1.0, 1.0), 6, 0.03)
	vg["state"] = "home"
	vg["pos"] = vg["home"]
	vg["vel"] = Vector3.ZERO
	var n: Node3D = vg["node"]
	n.rotation = Vector3.ZERO
	main.sfx_local("pickup", -14.0, 1.8)


func _fly_spoon(delta: float) -> void:
	if spoon_state == "rest":
		spoon_rest += delta
		if spoon_rest > 3.0:
			main.burst(spoon_pos, Color(1.0, 1.0, 1.0), 6, 0.03)
			spoon_state = "home"
			spoon_pos = SPOON_HOME
			_place_spoon(SPOON_HOME, 0.0)
		return
	spoon_vel.y -= 9.8 * delta
	spoon_pos += spoon_vel * delta
	spoon_yaw += delta * 8.0
	var g := _ground(spoon_pos)
	if spoon_pos.y < g + 0.015:
		spoon_pos.y = g + 0.015
		if spoon_vel.y < -1.0:
			main.sound("chop", -10.0, 0.7)
		spoon_vel = Vector3.ZERO
		spoon_state = "rest"
		spoon_rest = 0.0
	spoon_pos.x = clampf(spoon_pos.x, -L_ROOM.x, L_ROOM.x)
	spoon_pos.z = clampf(spoon_pos.z, -L_ROOM.y, L_ROOM.y)
	_place_spoon(spoon_pos, spoon_yaw)


## Every touch point (hands, knife tips, the held spoon's head, flying veggies) against every prop.
func _touches(chef) -> void:
	var pts: Array = []  # [position, velocity, hand or -1]
	for h in 2:
		pts.append([chef.hand_point(h), hand_vel[h], h])
		var hand: Node3D = chef.hand_l if h == 0 else chef.hand_r
		var knife_out: bool = held[h] == "" and chef.held[h] == null
		if knife_out:
			pts.append([hand.global_transform * Vector3(0, -0.012, -0.24), hand_vel[h] * 1.3, h])
		if held[h] == "spoon":
			pts.append([spoon_head(), hand_vel[h] * 1.4, h])
	for vg in veg:
		if vg["state"] == "fly":
			pts.append([vg["pos"], vg["vel"], -1])
	for tp in pts:
		var p: Vector3 = tp[0]
		var v: Vector3 = tp[1]
		var h: int = tp[2]
		# Pans: CLANG!
		for i in pans.size():
			if p.distance_to(pan_centre(i)) < 0.11 and v.length() > 0.4 and _ready_cool("pan%d" % i, 0.18):
				var pan: Dictionary = pans[i]
				pan["vel"] = float(pan["vel"]) + (-1.0 if v.x <= 0.0 else 1.0) * clampf(v.length() * 2.5, 2.0, 7.0)
				main.sound("clang", -3.0, (1.0 if i == 0 else 1.3) * randf_range(0.95, 1.05))
				_buzz(chef, h, 0.6)
				_count("pan")
		# Grinder: twist it, pepper puffs out.
		if h >= 0 and p.distance_to(grinder.global_position + Vector3.UP * 0.18) < 0.08 and _ready_cool("grinder", 0.45):
			grinder_spin = 14.0
			main.sound("grind", -6.0, randf_range(0.9, 1.1))
			main.burst(grinder.global_position + Vector3(0, -0.01, -0.03), Color(0.15, 0.12, 0.1), 10, 0.012)
			_buzz(chef, h, 0.25)
			_count("grinder")
		# Cuckoo clock.
		if p.distance_to(CLOCK) < 0.14 and _ready_cool("clock", 2.2):
			cuckoo()
			_buzz(chef, h, 0.3)
			_count("clock")
		# The service bell (the spoon or a veggie can ring it too; bare hands ring it in chef.gd).
		var bell: Node3D = main.parts.get("bell")
		if bell and (h < 0 or held[h] == "spoon") and p.distance_to(bell.global_position + Vector3.UP * 0.06) < 0.08 and _ready_cool("bell", 0.6):
			main.chef_rang_bell()
			_count("bell")
	# Spoon banged on the counter or a table: THUNK.
	for h in 2:
		if held[h] == "spoon" and hand_vel[h].y < -1.0:
			var head := spoon_head()
			if head.y < _ground(head) + 0.03 and _ground(head) > 0.5 and _ready_cool("thunk", 0.2):
				main.sound("chop", -6.0, 0.55)
				main.burst(head, Color(0.95, 0.85, 0.6), 5, 0.025)
				_buzz(chef, h, 0.5)
				_count("thunk")


## The bird pops out: CUCKOO! CUCKOO! (also at the start of every round)
func cuckoo() -> void:
	bird_out = 1.4
	main.sound("cuckoo", -4.0, 1.0)
	get_tree().create_timer(0.45).timeout.connect(func() -> void: main.sound("cuckoo", -4.0, 0.8))


func _buzz(chef, h: int, amp: float) -> void:
	if h < 0 or chef.fake_vr:
		return
	var hand: XRController3D = chef.hand_l if h == 0 else chef.hand_r
	hand.trigger_haptic_pulse("haptic", 0.0, amp, 0.05, 0.0)


## Snapshot entry: pans, grinder, bird, spoon (x, y, z, yaw), veggies (x, y, z each).
func net_state() -> PackedFloat32Array:
	var a := PackedFloat32Array([float(pans[0]["ang"]), float(pans[1]["ang"]), grinder_spin, bird_out])
	var sp := spoon.global_position
	a.append_array([sp.x, sp.y, sp.z, spoon.global_rotation.y])
	for vg in veg:
		var p: Vector3 = vg["pos"]
		a.append_array([p.x, p.y, p.z])
	return a


func apply_net(st: PackedFloat32Array) -> void:
	if st.size() < 8 + veg.size() * 3:
		return
	pans[0]["ang"] = st[0]
	pans[1]["ang"] = st[1]
	grinder_spin = st[2]
	bird_out = st[3]
	_place_spoon(Vector3(st[4], st[5], st[6]), st[7])
	for i in veg.size():
		var np := Vector3(st[8 + i * 3], st[9 + i * 3], st[10 + i * 3])
		var old: Vector3 = veg[i]["pos"]
		veg[i]["state"] = "home" if np.distance_to(veg[i]["home"]) < 0.01 else ("fly" if np.distance_to(old) > 0.002 else "rest")
		veg[i]["pos"] = np
