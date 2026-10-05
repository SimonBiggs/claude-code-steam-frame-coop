extends Node3D
## DUNGEON DELVE: the dungeon itself. Five small rooms in a straight line along -Z, joined by
## doorways with gates (portcullis bars that rise when a room is cleared):
##   0 practice, 1 slimes, 2 bats, 3 the Slime King, 4 the treasure room.
## Everything in a room can be poked (sword, hand, or a TV hero's bonk) and does something:
##   pots (on little stools) break into confetti, and the VR player's LEFT hand picks them up by
##   touching them (flick the hand to throw); torches flare up; chests pop open and spill coins;
##   a friendly skeleton rattles and waves; the practice dummy wobbles; the big treasure chest opens.
## Every machine builds the same dungeon; the host decides what happens (main.gd) and the visuals
## follow the replicated state ("used" bits, "open" gates) and events.
## Cheap for the Frame: the floors, walls, stools and brackets are ONE merged mesh; props are a few
## small meshes each; only one OmniLight (it follows the current room).

const MeshKit := preload("res://core/mesh_kit.gd")
const Creatures := preload("res://core/creatures.gd")

const ROOMS := 5
const ROOM := 9.0  ## room size (square)
const HALF := 4.5
const DOOR := 1.1  ## half-width of a doorway
const WALL_H := 2.6

enum { POT, TORCH, CHEST, SKEL, DUMMY, BIG }

## id -> {"kind", "room", "home": Vector3, "node": Node3D, "r": touch radius, "c": centre offset,
##        "prac": bool, "flame"/"lid"/"anim": extra nodes}
var props: Array[Dictionary] = []
var gates: Array[Node3D] = []
var open_count := 0
var used_bits := 0
var light: OmniLight3D
var prac_ring: MeshInstance3D  ## glowing ring under the practice pot
var dummy_ring: MeshInstance3D  ## glowing ring under the practice dummy
var dummy_id := -1
var big_id := -1
var _flare: Dictionary = {}  ## prop id -> seconds left
var _wobble: Dictionary = {}  ## prop id -> seconds left
var _t := 0.0
var _pot_mesh: ArrayMesh
var _lid_mesh: ArrayMesh


static func center(room: int) -> Vector3:
	return Vector3(0.0, 0.0, -room * ROOM)


## z of the wall (and gate) between room k and room k + 1.
static func wall_z(k: int) -> float:
	return -k * ROOM - HALF


static func room_of(p: Vector3) -> int:
	return clampi(int(floor((-p.z + HALF) / ROOM)), 0, ROOMS - 1)


## Where players come into a room (just past its doorway).
static func entrance(room: int) -> Vector3:
	if room == 0:
		return Vector3(0.0, 0.0, 3.2)
	return center(room) + Vector3(0.0, 0.0, HALF - 1.2)


# --- Building ------------------------------------------------------------------------------------

func build() -> void:
	var b := MeshKit.Builder.new()
	var stone := Color(0.42, 0.4, 0.5)
	var z_end := -(ROOMS - 1) * ROOM - HALF
	for r in ROOMS:
		var c := center(r)
		# Checker floor tiles (1.5 m).
		for ix in 6:
			for iz in 6:
				var dark := (ix + iz) % 2 == 0
				var col := Color(0.36, 0.33, 0.42) if dark else Color(0.46, 0.42, 0.52)
				if r == ROOMS - 1:
					col = Color(0.55, 0.42, 0.25) if dark else Color(0.68, 0.53, 0.3)
				b.box(Vector3(1.48, 0.1, 1.48), MeshKit.at(c + Vector3(-HALF + 0.75 + ix * 1.5, -0.05, -HALF + 0.75 + iz * 1.5)), col)
		# Side walls.
		for sx in [-1.0, 1.0]:
			var x: float = sx * (HALF + 0.2)
			b.box(Vector3(0.4, WALL_H, ROOM + 0.4), MeshKit.at(c + Vector3(x, WALL_H * 0.5, 0.0)), stone)
			# A row of rounded stones along the top, and corner pillars.
			for k in 5:
				b.rounded_box(Vector3(0.5, 0.25, 1.6), 0.08, MeshKit.at(c + Vector3(x, WALL_H + 0.1, -3.6 + k * 1.8)), stone.lightened(0.12))
			for sz in [-1.0, 1.0]:
				b.cylinder(0.32, 0.36, WALL_H + 0.3, MeshKit.at(c + Vector3(sx * (HALF - 0.05), (WALL_H + 0.3) * 0.5, sz * (HALF - 0.05))), stone.darkened(0.1), 10)
		# Torch brackets (the flames are separate, they flare up when poked).
		for t in _torch_spots(r):
			var tp: Vector3 = t
			b.box(Vector3(0.12, 0.08, 0.08), MeshKit.at(tp + Vector3(signf(-tp.x) * -0.08, -0.25, 0.0)), Color(0.25, 0.25, 0.3))
			b.cylinder(0.05, 0.035, 0.35, MeshKit.at(tp + Vector3(0.0, -0.12, 0.0), Vector3.ONE, Vector3(0, 0, signf(tp.x) * 0.35)), Color(0.45, 0.3, 0.18), 6)
		# Stools for the pots.
		for p in _pot_spots(r):
			var pp: Vector3 = p
			if pp.y > 0.1:
				b.cylinder(0.24, 0.24, 0.08, MeshKit.at(Vector3(pp.x, pp.y - 0.04, pp.z)), Color(0.55, 0.38, 0.22), 10)
				b.cylinder(0.05, 0.07, pp.y, MeshKit.at(Vector3(pp.x, pp.y * 0.5, pp.z)), Color(0.45, 0.3, 0.18), 6)
	# Walls across: the start wall, the doorway walls between rooms (with an arch) and the end wall.
	b.box(Vector3(ROOM + 0.8, WALL_H, 0.4), MeshKit.at(Vector3(0.0, WALL_H * 0.5, HALF + 0.2)), stone)
	b.box(Vector3(ROOM + 0.8, WALL_H, 0.4), MeshKit.at(Vector3(0.0, WALL_H * 0.5, z_end - 0.2)), stone)
	for k in ROOMS - 1:
		var wz := wall_z(k)
		var seg := HALF - DOOR
		for sx in [-1.0, 1.0]:
			b.box(Vector3(seg + 0.4, WALL_H, 0.4), MeshKit.at(Vector3(sx * (DOOR + seg * 0.5 + 0.2) - sx * 0.2, WALL_H * 0.5, wz)), stone)
			b.cylinder(0.25, 0.3, WALL_H + 0.5, MeshKit.at(Vector3(sx * (DOOR + 0.15), (WALL_H + 0.5) * 0.5, wz)), stone.lightened(0.15), 10)
		b.box(Vector3(DOOR * 2.0, 0.45, 0.45), MeshKit.at(Vector3(0.0, WALL_H + 0.05, wz)), stone.lightened(0.15))
		b.sphere(0.13, MeshKit.at(Vector3(0.0, WALL_H + 0.05, wz + 0.25)), Color(1.0, 0.8, 0.3), 10, true)
	add_child(MeshKit.instance(b.build(), false))
	# Gates.
	for k in ROOMS - 1:
		var g := Node3D.new()
		g.position = Vector3(0.0, 0.0, wall_z(k))
		var gb := MeshKit.Builder.new()
		for i in 6:
			gb.cylinder(0.04, 0.04, 2.3, MeshKit.at(Vector3(-DOOR + 0.18 + i * (DOOR * 2.0 - 0.36) / 5.0, 1.15, 0.0)), Color(0.3, 0.3, 0.36), 6)
		for y in [0.5, 1.4]:
			gb.box(Vector3(DOOR * 2.0, 0.07, 0.07), MeshKit.at(Vector3(0.0, y, 0.0)), Color(0.3, 0.3, 0.36))
		gb.rounded_box(Vector3(0.3, 0.36, 0.12), 0.04, MeshKit.at(Vector3(0.0, 0.95, 0.06)), Color(1.0, 0.8, 0.3))  # the lock
		g.add_child(MeshKit.instance(gb.build(), false))
		add_child(g)
		gates.append(g)
	_build_props()
	light = OmniLight3D.new()
	light.omni_range = 11.0
	light.light_energy = 1.6
	light.light_color = Color(1.0, 0.8, 0.55)
	light.shadow_enabled = false
	light.position = Vector3(0.0, 3.6, 0.0)
	add_child(light)


func _torch_spots(r: int) -> Array:
	var c := center(r)
	return [c + Vector3(-HALF + 0.15, 1.55, -1.6), c + Vector3(HALF - 0.15, 1.55, 1.6)]


## Pots: y > 0 means it sits on a stool at that height.
func _pot_spots(r: int) -> Array:
	var c := center(r)
	if r == 0:
		return [c + Vector3(-2.8, 0.0, 0.4), c + Vector3(3.4, 0.6, -3.4), c + Vector3(-3.4, 0.6, -3.4)]
	return [c + Vector3(-3.5, 0.6, -3.5), c + Vector3(3.5, 0.6, 3.3), c + Vector3(-3.5, 0.6, 2.4), c + Vector3(2.0, 0.6, -3.6)]


func _add(kind: int, room: int, home: Vector3, node: Node3D, r: float, c: Vector3) -> int:
	add_child(node)
	node.position = home
	props.append({"kind": kind, "room": room, "home": home, "node": node, "r": r, "c": c, "prac": false})
	return props.size() - 1


func _build_props() -> void:
	_pot_mesh = _make_pot()
	var chest_base := _make_chest_base()
	_lid_mesh = _make_lid()
	var flame := _make_flame()
	for r in ROOMS:
		var c := center(r)
		for p in _pot_spots(r):
			var pot := MeshKit.instance(_pot_mesh, false)
			var id := _add(POT, r, p, pot, 0.22, Vector3(0, 0.18, 0))
			props[id]["spin"] = randf() * TAU
			pot.rotation.y = float(props[id]["spin"])
		for t in _torch_spots(r):
			var f := MeshKit.instance(flame, false)
			var tid := _add(TORCH, r, t, f, 0.2, Vector3.ZERO)
			props[tid]["flame"] = f
		if r < ROOMS - 1:
			var ch := Node3D.new()
			ch.add_child(MeshKit.instance(chest_base, false))
			var lid := Node3D.new()
			lid.position = Vector3(0.0, 0.42, -0.26)
			var lm := MeshKit.instance(_lid_mesh, false)
			lm.position = Vector3(0.0, 0.0, 0.26)
			lid.add_child(lm)
			ch.add_child(lid)
			var at := c + (Vector3(1.6, 0.0, 1.0) if r == 0 else Vector3(3.2, 0.0, -1.2))
			var cid := _add(CHEST, r, at, ch, 0.42, Vector3(0, 0.35, 0))
			ch.rotation.y = -PI * 0.5 if r > 0 else -0.4
			props[cid]["lid"] = lid
			var sk := Creatures.monster("skeleton", {"weapon": "none", "eye_color": Color(0.4, 0.9, 1.0), "seed": 7 + r})
			var sat := c + (Vector3(-3.4, 0.0, -1.0) if r > 0 else Vector3(-3.4, 0.0, -0.4))
			var sid := _add(SKEL, r, sat, sk, 0.5, Vector3(0, 0.8, 0))
			sk.rotation.y = PI * 0.5
			props[sid]["anim"] = Creatures.anim(sk)
	# The practice pot (for the TV heroes) and the practice dummy (for the VR knight).
	props[0]["prac"] = true
	prac_ring = _ring(Color(0.4, 1.0, 0.8))
	prac_ring.position = Vector3(-2.8, 0.03, 0.4)
	var dummy := _make_dummy()
	var did := _add(DUMMY, 0, Vector3(0.35, 0.0, 1.45), dummy, 0.36, Vector3(0, 0.95, 0))
	props[did]["prac"] = true
	dummy_id = did
	dummy_ring = _ring(Color(1.0, 0.85, 0.3))
	dummy_ring.position = Vector3(0.35, 0.03, 1.45)
	# The big treasure chest.
	var big := Node3D.new()
	big.add_child(MeshKit.instance(chest_base, false))
	var blid := Node3D.new()
	blid.position = Vector3(0.0, 0.42, -0.26)
	var blm := MeshKit.instance(_lid_mesh, false)
	blm.position = Vector3(0.0, 0.0, 0.26)
	blid.add_child(blm)
	big.add_child(blid)
	big.scale = Vector3.ONE * 2.0
	var bid := _add(BIG, ROOMS - 1, center(ROOMS - 1) + Vector3(0.0, 0.0, -1.2), big, 1.0, Vector3(0, 0.6, 0.3))
	props[bid]["lid"] = blid
	big_id = bid


func _ring(col: Color) -> MeshInstance3D:
	var b := MeshKit.Builder.new()
	b.torus(0.5, 0.05, Transform3D.IDENTITY, col, 24, 4, true)
	var mi := MeshKit.instance(b.build(), false)
	add_child(mi)
	return mi


func _make_pot() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var clay := Color(0.85, 0.5, 0.32)
	b.sphere(0.17, MeshKit.at(Vector3(0, 0.17, 0), Vector3(1.0, 1.05, 1.0)), clay, 12)
	b.cylinder(0.08, 0.1, 0.1, MeshKit.at(Vector3(0, 0.36, 0)), clay.darkened(0.1), 10)
	b.torus(0.085, 0.025, MeshKit.at(Vector3(0, 0.41, 0)), clay.lightened(0.15), 10, 4)
	b.torus(0.17, 0.018, MeshKit.at(Vector3(0, 0.2, 0)), Color(0.4, 0.75, 0.9), 14, 4)
	return b.build()


func _make_chest_base() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var wood := Color(0.6, 0.36, 0.2)
	var gold := Color(1.0, 0.8, 0.3)
	b.rounded_box(Vector3(0.8, 0.42, 0.52), 0.04, MeshKit.at(Vector3(0, 0.21, 0)), wood)
	for x in [-0.28, 0.28]:
		b.box(Vector3(0.07, 0.43, 0.54), MeshKit.at(Vector3(float(x), 0.215, 0)), gold)
	b.box(Vector3(0.7, 0.03, 0.42), MeshKit.at(Vector3(0, 0.41, 0)), Color(1.0, 0.85, 0.35), true)  # gold inside
	return b.build()


func _make_lid() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var wood := Color(0.66, 0.4, 0.22)
	var gold := Color(1.0, 0.8, 0.3)
	b.cylinder(0.26, 0.26, 0.8, MeshKit.at(Vector3(0, 0.0, 0), Vector3(0.7, 1, 1), Vector3(0, 0, PI * 0.5)), wood, 12)
	for x in [-0.28, 0.28]:
		b.torus(0.26, 0.03, MeshKit.at(Vector3(float(x), 0.0, 0), Vector3(0.7, 1, 1), Vector3(0, 0, PI * 0.5)), gold, 12, 4)
	b.box(Vector3(0.14, 0.16, 0.05), MeshKit.at(Vector3(0, -0.02, 0.27)), gold)
	return b.build()


func _make_flame() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.sphere(0.09, MeshKit.at(Vector3(0, 0.0, 0), Vector3(1, 1.2, 1)), Color(1.0, 0.55, 0.15), 8, true)
	b.cone(0.07, 0.22, MeshKit.at(Vector3(0, 0.14, 0)), Color(1.0, 0.85, 0.3), 8, true)
	return b.build()


func _make_dummy() -> Node3D:
	var n := Node3D.new()
	var b := MeshKit.Builder.new()
	b.cylinder(0.05, 0.05, 0.7, MeshKit.at(Vector3(0, 0.35, 0)), Color(0.5, 0.33, 0.2), 8)
	b.cylinder(0.3, 0.32, 0.06, MeshKit.at(Vector3(0, 0.03, 0)), Color(0.5, 0.33, 0.2), 12)
	var body := Node3D.new()
	body.position = Vector3(0, 0.7, 0)
	var bb := MeshKit.Builder.new()
	bb.ellipsoid(Vector3(0.3, 0.28, 0.24), MeshKit.at(Vector3(0, 0.25, 0)), Color(0.95, 0.8, 0.45), 14)
	for i in 3:
		bb.torus(0.1 + i * 0.07, 0.02, MeshKit.at(Vector3(0, 0.25, 0.22 - i * 0.02), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.95, 0.3, 0.3) if i % 2 == 0 else Color.WHITE, 16, 4)
	bb.sphere(0.04, MeshKit.at(Vector3(-0.09, 0.36, 0.2)), Color(0.15, 0.1, 0.1), 6)
	bb.sphere(0.04, MeshKit.at(Vector3(0.09, 0.36, 0.2)), Color(0.15, 0.1, 0.1), 6)
	body.add_child(MeshKit.instance(bb.build(), false))
	n.add_child(MeshKit.instance(b.build(), false))
	n.add_child(body)
	n.set_meta("body", body)
	return n


func pot_mesh() -> ArrayMesh:
	return _pot_mesh


# --- Queries -------------------------------------------------------------------------------------

func prop_center(id: int) -> Vector3:
	var p: Dictionary = props[id]
	return (p["node"] as Node3D).global_position + (p["c"] as Vector3) * ((p["node"] as Node3D).scale.x)


func is_used(id: int) -> bool:
	return used_bits & (1 << id) != 0


## Keep a body of radius r inside the dungeon: walls, closed gates and doorways.
func walk_clamp(from: Vector3, to: Vector3, r: float) -> Vector3:
	var z_end := -(ROOMS - 1) * ROOM - HALF
	to.x = clampf(to.x, -HALF + r, HALF - r)
	to.z = clampf(to.z, z_end + r, HALF - r)
	for k in ROOMS - 1:
		var wz := wall_z(k)
		var band := r + 0.2
		if absf(to.z - wz) >= band and signf(to.z - wz) == signf(from.z - wz):
			continue
		var open := k < open_count
		if not open:
			to.z = wz + band if from.z >= wz else wz - band
			continue
		if absf(to.x) > DOOR - r:
			if absf(from.z - wz) >= band - 0.01:
				to.z = wz + band if from.z >= wz else wz - band
			else:
				to.x = clampf(to.x, -(DOOR - r), DOOR - r)
	return to


## Keep a monster in its room.
static func room_clamp(p: Vector3, room: int, r: float) -> Vector3:
	var c := center(room)
	p.x = clampf(p.x, -HALF + r, HALF - r)
	p.z = clampf(p.z, c.z - HALF + r, c.z + HALF - r)
	return p


# --- State from the host ------------------------------------------------------------------------

func set_open(n: int) -> void:
	open_count = n


func set_used(bits: int) -> void:
	var was := used_bits
	used_bits = bits
	for id in props.size():
		var p: Dictionary = props[id]
		var on := bits & (1 << id) != 0
		match int(p["kind"]):
			POT:
				(p["node"] as Node3D).visible = not on
				if not on and was & (1 << id) != 0:
					(p["node"] as Node3D).position = p["home"]
			CHEST, BIG:
				if not on:
					(p["lid"] as Node3D).rotation.x = 0.0
	if prac_ring != null:
		prac_ring.visible = not is_used(0)
	if dummy_ring != null:
		dummy_ring.visible = not is_used(dummy_id)


## Every machine: a prop was poked (the look only; sounds come from the host).
func react(id: int) -> void:
	if id < 0 or id >= props.size():
		return
	var p: Dictionary = props[id]
	match int(p["kind"]):
		TORCH:
			_flare[id] = 1.2
		CHEST, BIG:
			var lid: Node3D = p["lid"]
			var tw := lid.create_tween()
			tw.tween_property(lid, "rotation:x", -1.9, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		SKEL:
			_wobble[id] = 1.0
			var a: Variant = p.get("anim")
			if a != null:
				a.play("wave", 1.0)
		DUMMY:
			_wobble[id] = 1.2


func animate(delta: float, focus_room: int) -> void:
	_t += delta
	var target := center(focus_room) + Vector3(0.0, 3.6, 0.0)
	light.position = light.position.lerp(target, 1.0 - exp(-2.0 * delta))
	for k in gates.size():
		var g := gates[k]
		var want := 2.4 if k < open_count else 0.0
		g.position.y = move_toward(g.position.y, want, delta * 1.6)
	for id in props.size():
		var p: Dictionary = props[id]
		match int(p["kind"]):
			TORCH:
				var f: Node3D = p["flame"]
				var fl := float(_flare.get(id, 0.0))
				if fl > 0.0:
					fl -= delta
					_flare[id] = fl
				var s := 1.0 + 0.08 * sin(_t * 9.0 + id) + maxf(0.0, fl) * 1.6
				f.scale = Vector3(s, s * (1.0 + 0.1 * sin(_t * 13.0 + id * 2.0)), s)
			SKEL, DUMMY:
				var w := float(_wobble.get(id, 0.0))
				if w > 0.0:
					w = maxf(0.0, w - delta)
					_wobble[id] = w
					var n: Node3D = p["node"]
					if int(p["kind"]) == DUMMY:
						var body: Node3D = n.get_meta("body")
						body.rotation = Vector3(sin(_t * 18.0) * 0.5 * w, 0.0, sin(_t * 23.0) * 0.4 * w)
					else:
						n.rotation.z = sin(_t * 40.0) * 0.08 * w
	if prac_ring != null and prac_ring.visible:
		prac_ring.scale = Vector3.ONE * (1.0 + 0.12 * sin(_t * 5.0))
	if dummy_ring != null and dummy_ring.visible:
		dummy_ring.scale = Vector3.ONE * (1.0 + 0.12 * sin(_t * 5.0))
