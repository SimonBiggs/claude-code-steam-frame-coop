extends Node3D
## A cheeky raccoon that sneaks in through the back door and steals ingredients from the pass.
## Bump into it (walk close) to scare it off. Host simulates; the client mirrors [on, pos, yaw, carry].

const L := preload("res://games/kitchen_rush/layout.gd")
const ItemScript := preload("res://games/kitchen_rush/item.gd")

var main
var ghost := false
var state := "off"  # off, sneak, escape, flee
var target := Vector3.ZERO
var slot := 0
var carry_kind := ""
var net_target := Vector3.ZERO
var yaw := 0.0
var walk_t := 0.0
var carry_vis: Node3D
var shown_carry := ""
var body_root: Node3D


func _ready() -> void:
	body_root = Node3D.new()
	add_child(body_root)
	var grey := Color(0.55, 0.55, 0.6)
	var dark := Color(0.15, 0.15, 0.18)
	var body := _mesh(_sphere(0.28, 0.4), grey, Vector3(0, 0.3, 0))
	body.scale = Vector3(0.9, 1.0, 1.4)
	var head := _mesh(_sphere(0.17, 0.3), grey.lightened(0.15), Vector3(0, 0.45, -0.38))
	var mask := _mesh(_sphere(0.13, 0.12), dark, Vector3(0, 0.48, -0.47))
	mask.scale = Vector3(1.5, 1.0, 0.6)
	for side in [-1.0, 1.0]:
		_mesh(_sphere(0.04, 0.08), Color.WHITE, Vector3(side * 0.07, 0.5, -0.53))
		_mesh(_sphere(0.06, 0.12), dark, Vector3(side * 0.11, 0.62, -0.36))
	_mesh(_sphere(0.03, 0.06), dark, Vector3(0, 0.42, -0.56))
	# Stripy tail.
	for i in 4:
		var seg := _mesh(_sphere(0.09, 0.18), dark if i % 2 == 0 else grey.lightened(0.3), Vector3(0, 0.3 + i * 0.06, 0.38 + i * 0.1))
		seg.scale = Vector3.ONE * (1.0 - i * 0.08)
	visible = false


func _sphere(r: float, h: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = h
	s.radial_segments = 12
	s.rings = 6
	return s


func _mesh(m: Mesh, c: Color, p: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = main.mat(c)
	mi.position = p
	body_root.add_child(mi)
	return mi


## Host: start a raid on a pass slot.
func start() -> void:
	state = "sneak"
	global_position = L.RACCOON_DOOR
	carry_kind = ""
	slot = randi() % L.PASS_SLOTS.size()
	for i in L.PASS_SLOTS.size():  # prefer a slot that has something on it
		if main.item_at(L.PASS_SLOTS[i], 0.15) != null:
			slot = i
			break
	var s: Vector3 = L.PASS_SLOTS[slot]
	target = Vector3(s.x, 0.0, -0.62)
	visible = true


func active() -> bool:
	return state != "off"


func _process(delta: float) -> void:
	walk_t += delta
	if ghost:
		global_position = global_position.lerp(net_target, 1.0 - exp(-12.0 * delta))
	elif state != "off":
		_simulate(delta)
	body_root.rotation.y = yaw
	body_root.position.y = absf(sin(walk_t * 14.0)) * 0.06
	if carry_kind != shown_carry:
		shown_carry = carry_kind
		if carry_vis:
			carry_vis.queue_free()
			carry_vis = null
		if carry_kind != "":
			var it := ItemScript.new()
			it.main = main
			it.kind = carry_kind
			it.ghost = true
			it.remove_from_group("kr_items")
			carry_vis = Node3D.new()
			body_root.add_child(carry_vis)
			carry_vis.position = Vector3(0, 0.55, -0.6)
			carry_vis.add_child(it)
			it.set_process(false)
			it.remove_from_group("kr_items")


func _simulate(delta: float) -> void:
	var speed := 2.0 if state == "sneak" else (4.5 if state == "flee" else 2.8)
	var dest := target
	if state != "sneak":
		dest = L.RACCOON_EXIT
	# Go through the back door rather than the wall.
	var p := global_position
	var inside := p.z > -6.0
	var dest_inside := dest.z > -6.0
	if inside != dest_inside and absf(p.z + 6.0) > 0.4:
		dest = Vector3(0.0, 0.0, -6.0)
	var to := dest - p
	to.y = 0.0
	if to.length() > 0.05:
		yaw = atan2(-to.x, -to.z)
	global_position = p.move_toward(Vector3(dest.x, 0.0, dest.z), speed * delta)
	# Scared by any runner that gets close.
	if state != "flee":
		for i in range(1, main.players.size()):
			var r = main.players[i]
			if r.active and r.global_position.distance_to(global_position) < 1.25:
				_scare(i)
				return
	if state == "sneak" and global_position.distance_to(target) < 0.1:
		var it = main.item_at(L.PASS_SLOTS[slot], 0.15)
		if it != null:
			carry_kind = it.kind
			main.remove_item(it)
			main.sound("spit", -2.0, 1.4)
			main.popup(global_position + Vector3.UP * 1.0, "SNATCH!", Color(0.8, 0.8, 0.9))
		state = "escape"
	elif state != "sneak" and global_position.distance_to(L.RACCOON_EXIT) < 0.2:
		if carry_kind != "" and state == "escape":
			main.banner("The raccoon got away with the %s!" % ItemScript.display_name(carry_kind), 2.0)
		state = "off"
		carry_kind = ""
		visible = false


func _scare(runner_index: int) -> void:
	main.sound("dash", 0.0, 1.6)
	main.popup(global_position + Vector3.UP * 1.0, "SHOO!", Color(1.0, 0.9, 0.4))
	main.burst(global_position + Vector3.UP * 0.4, Color(0.7, 0.7, 0.75), 14, 0.06)
	if carry_kind != "":
		main.return_stolen(carry_kind)
		carry_kind = ""
	main.on_raccoon_scared(runner_index)
	state = "flee"


func net_state() -> Array:
	return [state != "off", global_position, yaw, carry_kind]


func apply_net(st: Array) -> void:
	var on: bool = st[0]
	if on and not visible:
		global_position = st[1]
	visible = on
	net_target = st[1]
	yaw = st[2]
	carry_kind = st[3]
