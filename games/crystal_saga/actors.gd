extends Node3D
## CRYSTAL SAGA party avatars on every machine: the Hero (member 0) and the companions (TV seats 1-6,
## or the AI friends 7-8 when nobody sits on the TV). Chibi humanoids from core/creatures.gd scaled
## to grown-up size (the VR player walks among them at full scale), each with a player-coloured ring
## and name tag.
## Who moves whom: a TV seat moves its own companion on the machine it sits at (instant; the TV
## machine reports positions with net.send_state); idle companions trot after the hero in formation;
## the AI friends are simulated by the host; the hero follows the VR head (or the slot-0 pad in local
## play without a headset, or the first companion when nobody controls the hero).
## In battles and cutscenes the host places everyone and the TV machine just mirrors snapshots.

const Creatures := preload("res://core/creatures.gd")
const HudKit := preload("res://core/hud_kit.gd")
const UiKit := preload("res://core/ui_kit.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")
const Data := preload("res://games/crystal_saga/data.gd")

const SCALE := 1.42  # chibis at grown-up height for the VR player
const WALK := 4.4
const HERO_WALK := 4.6
const LEASH := 12.0
const FOLLOW_GAP := 2.2

var main: Node
var avatars := {}  # member id -> Node3D
var looks := {}  # member id -> look key (rebuild when the class / VR state changes)
var last_pos := {}
var idle_t := {}  # member id -> seconds since its stick moved
var send_t := 0.0
var hero_yaw := 0.0
var tv_sword: Node3D  # TV view of the VR hero's sword (follows the right hand pose)
var tv_shield: Node3D
var pose := PackedFloat32Array()  # client: latest VR pose from the host
var pushes := {}  # member id -> Vector3 wind push this frame (sky bridge)


## Make / remove avatars so they match the roster (member ids).
func sync_roster(roster: Array) -> void:
	var want := {}
	for r in roster:
		want[int(r)] = true
	for id in avatars.keys():
		if not want.has(int(id)):
			var a: Node3D = avatars[id]
			if is_instance_valid(a):
				main.fx.poof(a.global_position + Vector3.UP * 0.8, Color(1, 1, 1))
				a.queue_free()
			avatars.erase(id)
			looks.erase(id)
			last_pos.erase(id)
	for id in want:
		_ensure(int(id))


## The avatar of member `id` (null if not in the party).
func avatar(id: int) -> Node3D:
	var a: Node3D = avatars.get(id, null)
	return a if a != null and is_instance_valid(a) else null


func hero() -> Node3D:
	return avatar(0)


func _look_key(id: int) -> String:
	var m: Dictionary = main.member(id)
	return "%s|%s|%s" % [String(m.get("cls", "")), str(main.hero_has_vr()), String(m.get("weapon", ""))]


func _ensure(id: int) -> void:
	var key := _look_key(id)
	var old := avatar(id)
	if old != null and String(looks.get(id, "")) == key:
		return
	var pos := old.position if old != null else _spawn_point(id)
	var yaw := old.rotation.y if old != null else PI
	if old != null:
		old.queue_free()
	var a := _make(id)
	add_child(a)
	a.position = pos
	a.rotation.y = yaw
	avatars[id] = a
	looks[id] = key
	last_pos[id] = pos
	if old == null and main.phase() == "explore":
		main.fx.poof(pos + Vector3.UP * 0.8, color_of(id))


func _spawn_point(id: int) -> Vector3:
	var h := hero()
	if h != null and id != 0:
		return main.world.nav_nearest(h.position + Vector3(randf_range(-1.5, 1.5), 0, randf_range(1.0, 2.0)))
	var sp: Array = main.net.state_get("spawn", [Vector3.ZERO, 0.0])
	return sp[0]


func color_of(id: int) -> Color:
	if id >= 7:
		return Color(0.85, 0.85, 0.9)
	return UiKit.player_color(id)


func _make(id: int) -> Node3D:
	var m: Dictionary = main.member(id)
	var cls := String(m.get("cls", "knight"))
	var c: Dictionary = Data.CLASSES.get(cls, Data.CLASSES["knight"])
	var look: Dictionary = (c["look"] as Dictionary).duplicate()
	look["scale"] = SCALE
	look["lod"] = "auto"
	look["lod_distance"] = 18.0
	if id == 0 and main.hero_has_vr():
		look["weapon"] = "none"  # the TV sees the VR player's real sword instead
		look["offhand"] = "none"
	var a := Creatures.humanoid(look)
	a.name = "Member%d" % id
	var col := color_of(id)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.52
	tm.rings = 18
	tm.ring_segments = 4
	ring.mesh = tm
	ring.material_override = MeshKit.material(col, 1.2)
	ring.position.y = 0.03
	ring.scale = Vector3(1.0, 0.15, 1.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	a.add_child(ring)
	var label := String(m.get("name", "P%d" % (id + 1)))
	if id >= 1 and id <= 6:
		label = "%s %s" % [main.party.name_of(id), String(c["name"])]
	elif id == 0:
		label = "HERO" if not main.hero_has_vr() else "HERO (VR)"
	HudKit.nameplate(a, label, col, Creatures.height_of(a) + 0.25, 0.2)
	if id == 0:
		_set_layers(a, VrRig.AVATAR_LAYER)  # never drawn for the VR player's own eyes / mirror
	return a


func _set_layers(n: Node, layers: int) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = layers
	for ch in n.get_children():
		_set_layers(ch, layers)


## Put the whole party around `pos` facing `yaw` (creature yaw; PI = facing north).
func place_all(pos: Vector3, yaw: float) -> void:
	hero_yaw = yaw
	var k := 0
	for id in avatars:
		var a: Node3D = avatars[id]
		if int(id) == 0:
			a.position = pos
		else:
			a.position = main.world.nav_nearest(formation_point(k, pos, yaw))
			k += 1
		a.rotation.y = yaw
		last_pos[id] = a.position
		idle_t[id] = 99.0


## Where the k-th companion trots behind the hero.
func formation_point(k: int, hero_pos: Vector3, yaw: float) -> Vector3:
	var fwd := Vector3(sin(yaw), 0, cos(yaw))  # creature front
	var right := Vector3(-fwd.z, 0, fwd.x)
	var row := k / 2
	var side := -1.0 if k % 2 == 0 else 1.0
	return hero_pos - fwd * (FOLLOW_GAP + row * 1.1) + right * side * (1.2 + row * 0.35)


# --- Per frame --------------------------------------------------------------------------------------

func update(delta: float) -> void:
	var ph: String = main.phase()
	var free_move := ph == "explore"
	_update_hero(delta, free_move)
	var k := 0
	var h := hero()
	for idv in avatars:
		var id := int(idv)
		if id == 0:
			continue
		var a: Node3D = avatars[id]
		if free_move and id <= 6 and main.party.is_local(id):
			_move_local(id, a, delta, k)
		elif free_move and id >= 7 and main.net.mode != "client" and h != null:
			_follow(id, a, delta, formation_point(k, h.position, hero_yaw), 1.0)
		k += 1
	_animate(delta)
	if main.net.mode == "client":
		_send(delta)
	pushes.clear()


func _update_hero(delta: float, free_move: bool) -> void:
	var h := hero()
	if h == null:
		return
	if main.vr_rig != null:
		var head: Vector3 = main.vr_rig.head_position()
		h.position = Vector3(head.x, main.vr_rig.floor_height, head.z)
		hero_yaw = main.vr_rig.head_yaw() + PI
		h.rotation.y = hero_yaw
		return
	if main.net.mode == "client":
		hero_yaw = h.rotation.y
		return
	if main.party.is_local(0):
		if free_move and not main.menu_busy(0):
			var mv: Vector2 = main.party.stick(0, "move")
			var push: Vector3 = pushes.get(0, Vector3.ZERO)
			if mv != Vector2.ZERO or push != Vector3.ZERO:
				var dir := _cam_dir(0, mv)
				var to := h.position + dir * HERO_WALK * main.world.speed_scale(h.position) * delta + push * delta
				h.position = main.world.slide(h.position, to)
				if dir.length() > 0.1:
					Creatures.anim(h).face(dir)
		hero_yaw = h.rotation.y
		return
	# Nobody controls the hero (a headset host without a headset): trot after the first companion.
	if free_move:
		for idv in avatars:
			if int(idv) != 0:
				var lead: Node3D = avatars[idv]
				_follow(0, h, delta, lead.position + Vector3(0, 0, 1.5), 1.0)
				break
	hero_yaw = h.rotation.y


func _cam_dir(slot: int, mv: Vector2) -> Vector3:
	var cam: Camera3D = main.tv_camera(slot)
	if cam == null:
		return Vector3(mv.x, 0, mv.y)
	var f := -cam.global_basis.z
	f.y = 0.0
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	var r := Vector3(-f.z, 0.0, f.x)
	return r * mv.x - f * mv.y


func _move_local(id: int, a: Node3D, delta: float, k: int) -> void:
	var mv: Vector2 = main.party.stick(id, "move") if not main.menu_busy(id) else Vector2.ZERO
	var h := hero()
	var push: Vector3 = pushes.get(id, Vector3.ZERO)
	if mv != Vector2.ZERO:
		idle_t[id] = 0.0
		var dir := _cam_dir(id, mv)
		var to := a.position + dir * WALK * main.world.speed_scale(a.position) * delta + push * delta
		if h != null and Vector2(to.x - h.position.x, to.z - h.position.z).length() > LEASH:
			var back := (h.position - a.position)
			back.y = 0.0
			to = a.position + back.normalized() * WALK * 0.4 * delta  # gently tugged back to the hero
		a.position = main.world.slide(a.position, to)
		Creatures.anim(a).face(dir)
	else:
		idle_t[id] = float(idle_t.get(id, 99.0)) + delta
		if push != Vector3.ZERO:
			a.position = main.world.slide(a.position, a.position + push * delta)
		if h != null and float(idle_t[id]) > 1.2:
			_follow(id, a, delta, formation_point(k, h.position, hero_yaw), 1.0)


## Trot towards `target` (formation spot); far away = a sparkly hop next to the hero.
func _follow(id: int, a: Node3D, delta: float, target: Vector3, speed_mul: float) -> void:
	var to := target - a.position
	to.y = 0.0
	var d := to.length()
	if d > 16.0:
		var spot: Vector3 = main.world.nav_nearest(target)
		a.position = spot
		last_pos[id] = spot
		main.fx.poof(spot + Vector3.UP * 0.8, color_of(id))
		return
	if d < 0.6:
		return
	var sp := clampf(d * 1.6, 1.2, 5.2) * speed_mul * main.world.speed_scale(a.position)
	var step := to.normalized() * minf(d, sp * delta)
	a.position = main.world.slide(a.position, a.position + step)
	Creatures.anim(a).face(to)


func _animate(delta: float) -> void:
	for id in avatars:
		var a: Node3D = avatars[id]
		var prev: Vector3 = last_pos.get(id, a.position)
		var v := Vector2(a.position.x - prev.x, a.position.z - prev.z).length() / maxf(delta, 0.001)
		Creatures.anim(a).walk(v if v > 0.25 else 0.0)
		last_pos[id] = a.position
	_update_tv_sword()


func _send(delta: float) -> void:
	send_t -= delta
	if send_t > 0.0:
		return
	send_t = 1.0 / 30.0
	if main.phase() != "explore":
		return
	for slot in main.party.local_slots():
		var a := avatar(slot)
		if a != null:
			main.net.send_state(a.position, a.rotation.y, 0.0, slot)


## Host: a TV seat moved on the TV machine.
func remote_state(slot: int, pos: Vector3, yaw: float) -> void:
	var a := avatar(slot)
	if a == null or main.phase() != "explore":
		return
	a.position = pos
	a.rotation.y = yaw


# --- The VR hero's sword and shield as seen on the TV -----------------------------------------------

func _update_tv_sword() -> void:
	var have_pose := main.vr_rig != null or pose.size() >= 21
	var h := hero()
	if not have_pose or h == null or not main.hero_has_vr():
		if tv_sword != null:
			tv_sword.visible = false
			tv_shield.visible = false
		return
	if tv_sword == null:
		tv_sword = Node3D.new()
		var sm := MeshKit.instance(main.fx.sword_mesh(false))
		sm.layers = VrRig.AVATAR_LAYER
		tv_sword.add_child(sm)
		add_child(tv_sword)
		tv_shield = Node3D.new()
		var shm := MeshKit.instance(main.fx.shield_mesh())
		shm.layers = VrRig.AVATAR_LAYER
		tv_shield.add_child(shm)
		add_child(tv_shield)
	tv_sword.visible = true
	tv_shield.visible = true
	if main.vr_rig != null:
		tv_sword.global_transform = main.vr_rig.hand_r.global_transform.orthonormalized()
		tv_shield.global_transform = main.vr_rig.hand_l.global_transform.orthonormalized()
	else:
		tv_sword.global_transform = tv_sword.global_transform.interpolate_with(_pose_xf(1), 0.5)
		tv_shield.global_transform = tv_shield.global_transform.interpolate_with(_pose_xf(2), 0.5)


func _pose_xf(i: int) -> Transform3D:
	var o := i * 7
	return Transform3D(Basis(Quaternion(pose[o + 3], pose[o + 4], pose[o + 5], pose[o + 6]).normalized()),
		Vector3(pose[o], pose[o + 1], pose[o + 2]))


# --- Snapshots ---------------------------------------------------------------------------------------

## Host: [id, x, z, yaw] for every avatar.
func pack() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for id in avatars:
		var a: Node3D = avatars[id]
		out.append_array([float(id), snappedf(a.position.x, 0.01), snappedf(a.position.z, 0.01), snappedf(a.rotation.y, 0.01)])
	return out


## TV machine: apply positions (not to its own seats while they walk freely).
func unpack(p: PackedFloat32Array) -> void:
	var free_move: bool = main.phase() == "explore"
	var i := 0
	while i + 3 < p.size():
		var id := int(p[i])
		var a := avatar(id)
		if a != null and not (free_move and id >= 1 and id <= 6 and main.party.is_local(id)):
			var target := Vector3(p[i + 1], 0.0, p[i + 2])
			if a.position.distance_to(target) > 6.0:
				a.position = target
			else:
				a.position = a.position.lerp(target, 0.5)
			a.rotation.y = lerp_angle(a.rotation.y, p[i + 3], 0.5)
		i += 4
