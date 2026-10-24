extends Node3D
## SIMPLE_MODE touchables (Simon's rule: if you can reach it, it does something) and the glowing practice
## rings. Every machine has this node; what runs where:
## - Cockpit toys (the VR pilot's machine only, local, VR-only layer): two little button panels by the
##   hips whose big buttons beep and light up (one of them starts the windscreen WIPERS), a HORN that
##   honks and squashes, a BOBBLEHEAD that wobbles, FUZZY DICE hanging from the roof that swing, and
##   the wipers also sweep when a hand reaches out towards the window.
## - Outside (host decides, everyone sees it through combat.emit_fx "tree" / "wobble" events):
##   buildings WOBBLE when the Titan punches them (no damage); TREES can be picked up by reaching a
##   giant fist down to one (VR) or pressing B (TV pilot), and thrown with a punch (or B): a thrown
##   tree bonks a kaiju dizzy-ish and gets replanted where it lands.
## - Practice rings (net store "rings": key -> Vector3): one glowing ring per TV player to fly / drive
##   through the first time they get a vehicle, and the DASH ring for the pilot when the dash unlocks.
##   TV players' rings are on the TV-only layer.
## Cheap for the Frame: a dozen tiny meshes in the cockpit, one mesh per held / flying tree.

const Data := preload("res://games/mech_titans/data.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")
const Kaiju := preload("res://games/mech_titans/kaiju.gd")
const Support := preload("res://games/mech_titans/support.gd")

const TOUCH := 0.085
const BTN_R := 0.035
## Two small button panels (cockpit space), angled up towards the pilot, within easy reach of the hips.
const PANELS: Array[Vector3] = [Vector3(-0.5, 0.95, -0.32), Vector3(0.5, 0.95, -0.32)]
const BTN_COLORS: Array[Color] = [Color(1.0, 0.3, 0.3), Color(0.35, 1.0, 0.45), Color(1.0, 0.85, 0.25),
	Color(0.4, 0.7, 1.0), Color(1.0, 0.5, 0.9), Color(0.5, 0.95, 1.0)]
const HORN := Vector3(0.5, 1.0, -0.52)
const BOBBLE := Vector3(-0.5, 0.99, -0.52)
const DICE_TOP := Vector3(0.32, 2.5, -0.62)
const DICE_LEN := 0.72
const WIPER_BTN := 5  ## the light-blue button on the right panel
const TREE_GRAB := 3.6  ## metres from a giant fist to a tree trunk
const TREE_LOW := 4.2  ## the fist must be this low (world y) to pick a tree up
const RING_R := 3.4

var main: Node
var vr := false
var touched := {}  ## kind -> true once (bots)
var _touching := {}
var _t := 0.0
# Cockpit
var _root: Node3D
var _buttons: Array[MeshInstance3D] = []
var _btn_pos: Array[Vector3] = []
var _btn_mats: Array[StandardMaterial3D] = []
var _btn_t: Array[float] = []
var _horn: MeshInstance3D
var _horn_t := 0.0
var _bob_head: Node3D
var _bob := Vector2.ZERO
var _bob_v := Vector2.ZERO
var _dice: Node3D
var _dice_a := Vector2.ZERO
var _dice_v := Vector2.ZERO
var _wipers: Array[Node3D] = []
var _wipe_t := 0.0
# Trees
var held: Array[int] = [-1, -1]
var _held_nodes: Array[MeshInstance3D] = [null, null]
var _flying := {}  ## tree index -> {node, vel}
var trees_grabbed := 0  ## bots
var trees_thrown := 0
var wobbles_seen := 0
# Buildings
var _wobble := {}  ## block -> seconds left
# Rings
var _rings := {}  ## key -> MeshInstance3D
var ring_t := {}  ## host: key -> seconds up
var rings_done := {}  ## host: key -> true once passed
var rings_popped := 0


func setup(p_main: Node) -> void:
	main = p_main
	vr = main.vr_rig != null
	if vr:
		_build_cockpit(main.mech.cockpit.console)


func _host() -> bool:
	return main.net.mode != "client"


# --- Cockpit toys (VR) ------------------------------------------------------------------------------------

func _glow_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.25)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.15
	m.roughness = 0.5
	return m


func _mi(mesh: Mesh, mat: Material, parent: Node3D, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.layers = Data.LAYER_VR_ONLY
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _sphere(r: float, seg: int = 12) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = seg / 2
	return s


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 8
	c.rings = 1
	return c


## A post from the side console up to a panel / toy.
func _post(from: Vector3, to: Vector3) -> void:
	var d := to - from
	var mi := _mi(_cyl(0.018, d.length()), MeshKit.material(Color(0.55, 0.58, 0.65)), _root, (from + to) * 0.5)
	var up := d.normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	mi.basis = Basis(side, up, side.cross(up))


func _build_cockpit(parent: Node3D) -> void:
	_root = Node3D.new()
	_root.name = "Toys"
	parent.add_child(_root)
	var dark := MeshKit.material(Color(0.2, 0.22, 0.28))
	# Two button panels on posts from the side consoles.
	for p in 2:
		var c := PANELS[p]
		var sx := -1.0 if p == 0 else 1.0
		_post(Vector3(sx * 0.85, 0.78, c.z), c + Vector3(sx * 0.12, -0.05, 0))
		var panel := _mi(_box(Vector3(0.32, 0.03, 0.22)), dark, _root, c)
		panel.rotation.x = 0.35
		for b in 3:
			var bp := c + Vector3((b - 1) * 0.095, 0.035, 0.0)
			var m := _glow_mat(BTN_COLORS[p * 3 + b])
			var btn := _mi(_cyl(BTN_R, 0.03), m, _root, bp)
			btn.rotation.x = 0.35
			_buttons.append(btn)
			_btn_pos.append(bp)
			_btn_mats.append(m)
			_btn_t.append(0.0)
	# Horn: a big squishy red dome on the right.
	_post(Vector3(0.85, 0.78, HORN.z), HORN + Vector3(0.06, -0.06, 0))
	_mi(_cyl(0.075, 0.04), dark, _root, HORN + Vector3(0, -0.03, 0))
	var hs := _sphere(0.065)
	hs.height = 0.07
	hs.is_hemisphere = true
	_horn = _mi(hs, MeshKit.material(Color(1.0, 0.25, 0.25), 0.3), _root, HORN)
	# Bobblehead on the left: a little Titan with a big wobbly head.
	_post(Vector3(-0.85, 0.78, BOBBLE.z), BOBBLE + Vector3(-0.06, -0.06, 0))
	_mi(_cyl(0.05, 0.025), dark, _root, BOBBLE + Vector3(0, -0.02, 0))
	_mi(_box(Vector3(0.05, 0.07, 0.035)), MeshKit.material(Color(0.3, 0.55, 0.95)), _root, BOBBLE + Vector3(0, 0.03, 0))
	_bob_head = Node3D.new()
	_bob_head.position = BOBBLE + Vector3(0, 0.07, 0)
	_root.add_child(_bob_head)
	_mi(_sphere(0.05), MeshKit.material(Color(0.35, 0.6, 1.0)), _bob_head, Vector3(0, 0.05, 0))
	_mi(_box(Vector3(0.07, 0.018, 0.02)), MeshKit.material(Color(0.4, 0.95, 1.0), 1.5), _bob_head, Vector3(0, 0.058, 0.042))
	# Fuzzy dice hanging from the roof.
	_dice = Node3D.new()
	_dice.position = DICE_TOP
	_root.add_child(_dice)
	_mi(_cyl(0.004, DICE_LEN), MeshKit.material(Color(0.95, 0.95, 0.95)), _dice, Vector3(0, -DICE_LEN * 0.5, 0))
	var pink := MeshKit.material(Color(1.0, 0.55, 0.8))
	var d1 := _mi(_box(Vector3(0.07, 0.07, 0.07)), pink, _dice, Vector3(-0.03, -DICE_LEN - 0.03, 0))
	d1.rotation = Vector3(0.3, 0.5, 0.2)
	var d2 := _mi(_box(Vector3(0.07, 0.07, 0.07)), pink, _dice, Vector3(0.04, -DICE_LEN + 0.02, 0.01))
	d2.rotation = Vector3(-0.2, 0.9, 0.4)
	# Windscreen wipers on the canopy's bottom bar (resting flat).
	for sx2 in [-1.0, 1.0]:
		var piv := Node3D.new()
		piv.position = Vector3(sx2 * 0.55 - 0.25, 1.22, -1.5)
		_root.add_child(piv)
		_mi(_box(Vector3(0.025, 0.8, 0.02)), MeshKit.material(Color(0.12, 0.12, 0.14)), piv, Vector3(0, 0.4, 0))
		piv.rotation.z = -1.45
		_wipers.append(piv)


func _hands_local() -> Array:
	var rig: VrRig = main.vr_rig
	var ck: Node3D = main.mech.cockpit
	var out: Array = []
	for h in 2:
		var p: Vector3 = ck.to_local(rig.hand_point(h))
		var v: Vector3 = ck.global_basis.inverse() * rig.hand_velocity(h)
		out.append([p, v])
	return out


## One reaction per touch: true the first frame hand h comes within r of p (it must leave to re-arm).
func _poke(key: String, h: int, hp: Vector3, p: Vector3, r: float) -> bool:
	var k := "%s%d" % [key, h]
	var d := hp.distance_to(p)
	if d < r:
		if not _touching.has(k):
			_touching[k] = true
			touched[key.rstrip("0123456789")] = true
			return true
	elif d > r * 1.6:
		_touching.erase(k)
	return false


func _tick_cockpit(delta: float) -> void:
	var hands := _hands_local()
	for h in 2:
		var hp: Vector3 = hands[h][0]
		var hv: Vector3 = hands[h][1]
		for b in _buttons.size():
			if _poke("button%d" % b, h, hp, _btn_pos[b], TOUCH):
				_btn_t[b] = 0.6
				main.sfx.play("beep", -6.0, 0.8 + b * 0.12)
				main.pulse(h, 0.3, 0.05)
				if b == WIPER_BTN:
					_wipe()
		if _poke("horn", h, hp, HORN, TOUCH + 0.02):
			_horn_t = 0.35
			main.sfx.play("honk", -2.0, 0.8)
			main.pulse(h, 0.5, 0.1)
		if _poke("bobble", h, hp, _bob_head.position + Vector3(0, 0.05, 0), TOUCH + 0.01):
			_bob_v += Vector2(hv.x, hv.z) * 6.0 + Vector2(randf_range(-4, 4), 3.0)
			main.sfx.play("boing", -6.0, 1.5)
			main.pulse(h, 0.3, 0.06)
		var dpos := _dice.position + _dice.basis * Vector3(0, -DICE_LEN, 0)
		if _poke("dice", h, hp, dpos, TOUCH + 0.03):
			_dice_v += Vector2(-hv.z, hv.x) * 3.0 + Vector2(randf_range(-2, 2), randf_range(-2, 2))
			main.sfx.play("dice", -6.0, 1.2)
			main.pulse(h, 0.25, 0.05)
		# Reaching out to the window works the wipers too.
		if _poke("wiper", h, hp, Vector3(clampf(hp.x, -0.9, 0.9), 1.5, -0.95), 0.3):
			_wipe()
	for b in _buttons.size():
		_btn_t[b] = maxf(0.0, _btn_t[b] - delta)
		var on := _btn_t[b] > 0.0
		_btn_mats[b].emission_energy_multiplier = 3.0 if on else 0.15
		_buttons[b].scale = Vector3(1.0, 0.4 if _btn_t[b] > 0.45 else 1.0, 1.0)
	_horn_t = maxf(0.0, _horn_t - delta)
	_horn.scale = Vector3(1.15, 0.45, 1.15) if _horn_t > 0.2 else Vector3.ONE.lerp(Vector3(1.15, 0.45, 1.15), _horn_t / 0.2)
	# Springs: the bobblehead and the dice.
	_bob_v += (-_bob * 90.0 - _bob_v * 2.2) * delta
	_bob += _bob_v * delta
	_bob = _bob.limit_length(0.7)
	_bob_head.rotation = Vector3(_bob.y, 0, -_bob.x)
	_dice_v += (-_dice_a * 14.0 - _dice_v * 0.9) * delta
	_dice_a += _dice_v * delta
	_dice_a = _dice_a.limit_length(1.1)
	_dice.rotation = Vector3(_dice_a.x, 0, _dice_a.y)
	if _wipe_t > 0.0:
		_wipe_t = maxf(0.0, _wipe_t - delta)
		var a := sin((2.4 - _wipe_t) / 2.4 * TAU * 2.0 - PI * 0.5) * 0.5 + 0.5  # two sweeps
		for i in _wipers.size():
			_wipers[i].rotation.z = lerpf(-1.45, 0.25, a)


func _wipe() -> void:
	if _wipe_t > 0.6:
		return
	_wipe_t = 2.4
	main.sfx.play("swish", -6.0, 0.7)


## Bots: cockpit-space points of each toy.
func bot_targets() -> Dictionary:
	return {"button": _btn_pos[0], "horn": HORN, "bobble": _bob_head.position + Vector3(0, 0.05, 0),
		"dice": DICE_TOP + Vector3(0, -DICE_LEN, 0), "wiper": Vector3(0.0, 1.5, -0.95)}


# --- Trees (host decides) ------------------------------------------------------------------------------------

## New city: forget held / flying trees.
func reset_world() -> void:
	for h in 2:
		held[h] = -1
		if _held_nodes[h] != null and is_instance_valid(_held_nodes[h]):
			_held_nodes[h].queue_free()
		_held_nodes[h] = null
	for i in _flying:
		var n: Node = _flying[i]["node"]
		if is_instance_valid(n):
			n.queue_free()
	_flying.clear()
	_wobble.clear()


func _tree_near(p: Vector3, r: float) -> int:
	var city: Node = main.city
	if city == null or city.trees_mm == null:
		return -1
	var best := -1
	var bd := r
	for i in city.tree_xf.size():
		if city.tree_down[i] == 2:
			continue  # already in a fist (flattened trees can be picked up and replanted)
		var o: Vector3 = (city.tree_xf[i] as Transform3D).origin
		var d := Vector2(o.x - p.x, o.z - p.z).length()
		if d < bd:
			bd = d
			best = i
	return best


func _tick_trees_host() -> void:
	var mech: Node3D = main.mech
	if mech.rebooting > 0.0:
		return
	var pilot = main.pilot
	if pilot.mode == "vr":
		for h in 2:
			if held[h] >= 0:
				continue
			var f: Vector3 = mech.call("fist_world", h)
			if f.y > TREE_LOW:
				continue
			var i := _tree_near(f, TREE_GRAB)
			if i >= 0:
				main.combat.emit_fx("tree", ["grab", i, h])
	elif pilot.mode == "pad" and main.party.is_local(0) and not main.slot_busy(0) and main.party.just_pressed(0, "b"):
		if held[1] >= 0:
			throw_tree(1, mech.call("forward") * 28.0 + Vector3(0, 9.0, 0))
		else:
			var i2 := _tree_near(mech.global_position + mech.call("forward") * 4.0, 11.0)
			if i2 >= 0:
				main.combat.emit_fx("tree", ["grab", i2, 1])
	# Flying trees: bonk kaiju, land and get replanted.
	for i in _flying.keys():
		var rec: Dictionary = _flying[i]
		var n: Node3D = rec["node"]
		var p := n.global_position
		var landed := p.y <= 0.3 or float(rec["t"]) > 6.0
		for id in main.combat.kaiju:
			var k: Kaiju = main.combat.kaiju[id]
			if not k.is_active() or k.state == "practice":
				continue
			if k.surface_distance(p) < 1.6:
				main.combat.damage_kaiju(k, 30.0, -1, 0, "tree")
				k.stun = minf(100.0, k.stun + 45.0)
				main.combat.emit_fx("burst", ["stars", p, 2.0])
				main.combat.emit_fx("sfx", ["boing", p, 6.0, 0.6])
				main.combat.emit_fx("pop", [p + Vector3.UP * 2.0, "BONK!", Color(0.6, 1.0, 0.5), 3.0])
				landed = true
				break
		if landed:
			var at: Vector3 = main.city.push_out(Vector3(p.x, 0, p.z), 1.5)
			at.x = clampf(at.x, -Data.MAP, Data.MAP)
			at.z = clampf(at.z, -Data.MAP, Data.MAP)
			main.combat.emit_fx("tree", ["land", i, at])


## Host: a punch with a tree in that fist throws it instead.
func throw_tree(h: int, vel: Vector3) -> void:
	if held[h] < 0:
		return
	var from: Vector3 = main.mech.call("fist_world", h)
	main.combat.emit_fx("tree", ["throw", held[h], h, from, vel])


func _tree_mesh() -> Mesh:
	return main.city.trees_mm.mesh


func _tree_basis(i: int) -> Basis:
	return (main.city.tree_xf[i] as Transform3D).basis


## Every machine (combat.play_fx "tree").
func on_tree(a: Array) -> void:
	var city: Node = main.city
	if city == null or city.trees_mm == null:
		return
	var what := String(a[0])
	var i := int(a[1])
	if i < 0 or i >= city.tree_xf.size():
		return
	match what:
		"grab":
			var h := int(a[2])
			if held[h] >= 0:
				return
			held[h] = i
			city.tree_down[i] = 2
			city.trees_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0, -50, 0)))
			var mi := MeshInstance3D.new()
			mi.mesh = _tree_mesh()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			main.world_root.add_child(mi)
			_held_nodes[h] = mi
			trees_grabbed += 1
			main.sfx.play_at("pickup", (city.tree_xf[i] as Transform3D).origin, 2.0, 0.6)
			main.fx.burst("dust", (city.tree_xf[i] as Transform3D).origin, 1.5)
			if h < 2:
				main.pulse(h, 0.5, 0.12)
		"throw":
			var h2 := int(a[2])
			if held[h2] == i:
				held[h2] = -1
				if _held_nodes[h2] != null and is_instance_valid(_held_nodes[h2]):
					_held_nodes[h2].queue_free()
				_held_nodes[h2] = null
			var fly := MeshInstance3D.new()
			fly.mesh = _tree_mesh()
			fly.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			main.world_root.add_child(fly)
			fly.global_transform = Transform3D(_tree_basis(i), a[3])
			_flying[i] = {"node": fly, "vel": a[4], "t": 0.0}
			trees_thrown += 1
			main.sfx.play_at("whoosh", a[3], 4.0, 0.5)
		"land":
			if _flying.has(i):
				var n: Node = _flying[i]["node"]
				if is_instance_valid(n):
					n.queue_free()
				_flying.erase(i)
			for h3 in 2:
				if held[h3] == i:
					held[h3] = -1
					if _held_nodes[h3] != null and is_instance_valid(_held_nodes[h3]):
						_held_nodes[h3].queue_free()
					_held_nodes[h3] = null
			var at: Vector3 = a[2]
			var xf := Transform3D(_tree_basis(i), at)
			city.tree_xf[i] = xf
			city.tree_down[i] = 0
			city.trees_mm.set_instance_transform(i, xf)
			main.fx.burst("dust", at, 2.0)
			main.sfx.play_at("land", at, 0.0, 0.9)


func _tick_trees_visual(delta: float) -> void:
	var mech: Node3D = main.mech
	for h in 2:
		var n := _held_nodes[h]
		if n == null or not is_instance_valid(n) or held[h] < 0:
			continue
		var f: Vector3 = mech.call("fist_world", h)
		var b := _tree_basis(held[h])
		n.global_transform = Transform3D(Basis(Vector3(0, 0, 1), sin(_t * 3.0 + h) * 0.12) * b, f + Vector3(0, -1.4, 0))
	for i in _flying:
		var rec: Dictionary = _flying[i]
		var n2: Node3D = rec["node"]
		var v: Vector3 = rec["vel"]
		v.y -= 22.0 * delta
		rec["vel"] = v
		rec["t"] = float(rec["t"]) + delta
		n2.global_position += v * delta
		n2.rotate(Vector3(v.z, 0, -v.x).normalized() if Vector2(v.x, v.z).length() > 0.1 else Vector3.RIGHT, 7.0 * delta)


# --- Buildings wobble ---------------------------------------------------------------------------------------

## Every machine (combat.play_fx "wobble"): a city block jiggles.
func wobble(block: int) -> void:
	if main.city == null or block < 0 or block >= main.city.blocks.size():
		return
	_wobble[block] = 0.8
	wobbles_seen += 1


func _tick_wobble(delta: float) -> void:
	for b in _wobble.keys():
		var t: float = _wobble[b] - delta
		var mi: Node3D = main.city.blocks[b]
		if t <= 0.0:
			_wobble.erase(b)
			mi.position = Vector3.ZERO
			continue
		_wobble[b] = t
		mi.position = Vector3(sin(t * 38.0) * 0.3 * t, 0.0, cos(t * 31.0) * 0.25 * t)


# --- Practice rings -----------------------------------------------------------------------------------------

## Host: put a glowing ring up for `key` ("1".."n" = TV seats, "dash" = the pilot).
func add_ring(key: String, pos: Vector3) -> void:
	var r: Dictionary = (main.net.state_get("rings", {}) as Dictionary).duplicate()
	r[key] = pos
	ring_t[key] = 0.0
	main.net.state_set("rings", r)


func remove_ring(key: String, passed: bool) -> void:
	var r: Dictionary = (main.net.state_get("rings", {}) as Dictionary).duplicate()
	if not r.has(key):
		return
	var p: Vector3 = r[key]
	r.erase(key)
	ring_t.erase(key)
	rings_done[key] = true
	main.net.state_set("rings", r)
	if passed:
		rings_popped += 1
		main.combat.emit_fx("burst", ["stars", p, 2.5])
		main.combat.emit_fx("sfx", ["sparkle", p, 6.0, 1.0])


func has_ring(key: String) -> bool:
	return (main.net.state_get("rings", {}) as Dictionary).has(key)


## Every machine: build / remove the ring meshes to match the store.
func sync_rings(r: Dictionary) -> void:
	for key in _rings.keys():
		if not r.has(key):
			(_rings[key] as Node).queue_free()
			_rings.erase(key)
	for key in r:
		if not _rings.has(key):
			var tm := TorusMesh.new()
			var big := String(key) == "dash"
			tm.inner_radius = (5.2 if big else RING_R - 0.45)
			tm.outer_radius = (6.0 if big else RING_R)
			tm.rings = 24
			tm.ring_segments = 8
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(1.0, 0.9, 0.35) if big else Color(0.45, 1.0, 0.7)
			var mi := MeshInstance3D.new()
			mi.mesh = tm
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.layers = 1 if big else Data.LAYER_TV_ONLY
			add_child(mi)
			_rings[key] = mi
		var n: MeshInstance3D = _rings[key]
		n.global_position = r[key]


## Host: TV players get one ring each the first time they have a vehicle; check who flew through.
func _tick_rings_host(delta: float) -> void:
	var r: Dictionary = main.net.state_get("rings", {})
	for id in main.support.vehicles:
		var slot := int(id)
		if slot >= Support.AI_BASE:
			continue
		var key := str(slot)
		if rings_done.has(key) or r.has(key):
			continue
		var v: Node3D = main.support.vehicles[id]
		var f := Vector3(-sin(v.get("aim_yaw")), 0, -cos(v.get("aim_yaw")))
		var p: Vector3 = v.global_position + f * 22.0
		p.x = clampf(p.x, -Data.MAP + 6.0, Data.MAP - 6.0)
		p.z = clampf(p.z, -Data.MAP + 6.0, Data.MAP - 6.0)
		if not bool(v.call("flyer")):
			p = main.city.push_out(Vector3(p.x, 0, p.z), 4.0)
			p.y = 2.6
		else:
			p.y = v.global_position.y
		add_ring(key, p)
	for key in r.keys():
		ring_t[key] = float(ring_t.get(key, 0.0)) + delta
		var rp: Vector3 = r[key]
		var near := false
		if String(key) == "dash":
			var mp: Vector3 = main.mech.global_position
			near = Vector2(mp.x - rp.x, mp.z - rp.z).length() < 7.0
		else:
			var v2: Node3D = main.support.vehicles.get(int(key), null)
			near = v2 != null and v2.global_position.distance_to(rp) < RING_R + 2.0
		if near:
			remove_ring(key, true)
		elif float(ring_t[key]) > 40.0 and String(key) != "dash":
			remove_ring(key, false)


func _tick_rings_visual() -> void:
	for key in _rings:
		var n: MeshInstance3D = _rings[key]
		n.rotation = Vector3(PI * 0.5, _t * 0.8, 0)
		var s := 1.0 + sin(_t * 5.0) * 0.08
		n.scale = Vector3(s, s, s)


# --- Per frame -------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if main == null or not main.ready_to_play or main.city == null:
		return
	_t += delta
	if vr and _root != null:
		_tick_cockpit(delta)
	if _host():
		_tick_trees_host()
		if String(main.net.state_get("phase", "")) == "play":
			_tick_rings_host(delta)
	_tick_trees_visual(delta)
	_tick_wobble(delta)
	_tick_rings_visual()
