extends Node3D
## Dice, driven by the replicated "dice" state {id, pid, n, mode, values}:
##  - "tv" / "cpu": spinning dice BLOCKS above the token (Mario-Party style); a TV player stops one
##    with A (net.request "dice_hit"), the host picks the number. Every machine shows them.
##  - "vr": real, physical dice for the VR player (host): they float beside the right hand; grab one
##    with the trigger, let go to THROW it onto the island; when it stops, the face pointing up is the
##    roll. Fell off the table or got stuck? It comes back. The TV machine sees the giant dice fly
##    (positions in the snapshot).

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const UiKit := preload("res://core/ui_kit.gd")
const BD := preload("res://games/party_board/board_data.gd")

## World size of the VR die (metres).
const DIE_M := 0.085
## Face values by local axis: +Y 1, -Y 6, +Z 2, -Z 5, +X 3, -X 4 (opposite faces add up to 7).
const FACES := [[Vector3.UP, 1], [Vector3.DOWN, 6], [Vector3.BACK, 2], [Vector3.FORWARD, 5], [Vector3.RIGHT, 3], [Vector3.LEFT, 4]]

var main: Node
var state: Dictionary = {}
var blocks: Array[Node3D] = []
var vr_dice: Array[RigidBody3D] = []  # host VR: the physical dice
var mirrors: Array[Node3D] = []  # TV machine: the VR dice as seen from the TV
var table_body: StaticBody3D
var _held := -1
var _hold_xf := Transform3D()
var _released_t: Array[float] = []
var _still_t: Array[float] = []
var _settled: Array[int] = []
var _cycle_t := 0.0
var _t := 0.0
var _hint_t := 0.0
var _reported := false


func _ready() -> void:
	if main.vr_rig != null:
		_build_table_collision()


# --- State --------------------------------------------------------------------------------------------

func on_state(key: String, value: Variant) -> void:
	if key != "dice":
		return
	var d: Dictionary = value if value is Dictionary else {}
	var new_roll := int(d.get("id", -1)) != int(state.get("id", -2))
	state = d
	if d.is_empty():
		_clear_blocks(true)
		_clear_vr()
		return
	if new_roll:
		_clear_blocks(false)
		_clear_vr()
		var n := int(d.get("n", 1))
		for i in n:
			_make_block(i, n)
		if String(d.get("mode", "")) == "vr" and main.vr_rig != null and main.net.mode != "client":
			_spawn_vr(n)
	_refresh_blocks()


func _make_block(i: int, n: int) -> void:
	var b := Node3D.new()
	b.name = "DiceBlock%d" % i
	var mi := MeshKit.instance(ResCache.get_or_make("pb_block_v1", _block_mesh), false)
	mi.name = "Cube"
	b.add_child(mi)
	for f in 5:
		var l := UiKit.label3d("?", 0.5, Color(0.15, 0.2, 0.45), true)
		l.outline_size = 6
		l.outline_modulate = Color(1, 1, 1, 0.9)
		l.no_depth_test = false
		l.double_sided = false
		var basis := Basis()
		var off := Vector3.ZERO
		match f:
			0:
				off = Vector3(0, 0, 0.56)
			1:
				basis = Basis(Vector3.UP, PI)
				off = Vector3(0, 0, -0.56)
			2:
				basis = Basis(Vector3.UP, PI * 0.5)
				off = Vector3(0.56, 0, 0)
			3:
				basis = Basis(Vector3.UP, -PI * 0.5)
				off = Vector3(-0.56, 0, 0)
			4:
				basis = Basis(Vector3.RIGHT, -PI * 0.5)
				off = Vector3(0, 0.56, 0)
		l.transform = Transform3D(basis, off)
		l.name = "Face%d" % f
		mi.add_child(l)
	b.set_meta("slot", i)
	b.set_meta("n", n)
	b.set_meta("value", 0)
	b.scale = Vector3.ONE * 0.01
	main.stage.add_child(b)
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	blocks.append(b)


func _block_mesh() -> Resource:
	var b := MeshKit.Builder.new()
	b.rounded_box(Vector3(1.1, 1.1, 1.1), 0.18, MeshKit.at(Vector3.ZERO), Color(1.0, 0.97, 0.9), 2)
	for k in 4:
		var a := k * PI * 0.5
		b.box(Vector3(1.16, 0.08, 0.08), MeshKit.at(Vector3(0, 0, 0.53).rotated(Vector3.UP, a) + Vector3(0, 0.53, 0), Vector3.ONE, Vector3(0, a, 0)), Color(1.0, 0.75, 0.25))
		b.box(Vector3(1.16, 0.08, 0.08), MeshKit.at(Vector3(0, 0, 0.53).rotated(Vector3.UP, a) + Vector3(0, -0.53, 0), Vector3.ONE, Vector3(0, a, 0)), Color(1.0, 0.75, 0.25))
	return b.build()


func _refresh_blocks() -> void:
	var values: Array = state.get("values", [])
	for b in blocks:
		if not is_instance_valid(b):
			continue
		var i := int(b.get_meta("slot"))
		if i < values.size() and int(b.get_meta("value")) == 0:
			var v := int(values[i])
			b.set_meta("value", v)
			_set_faces(b, str(v), Color(0.9, 0.25, 0.2))
			var tw := b.create_tween()
			b.scale = Vector3.ONE * 1.5
			tw.tween_property(b, "scale", Vector3.ONE * 1.15, 0.25).set_trans(Tween.TRANS_BACK)
			main.sfx.play("ding", -3.0, 0.9 + v * 0.06)
			main.burst(b.position, Color(1.0, 0.85, 0.3), 12)


func _set_faces(b: Node3D, text: String, col: Color) -> void:
	var mi := b.get_node("Cube")
	for f in 5:
		var l := mi.get_node("Face%d" % f) as Label3D
		l.text = text
		l.modulate = col


func _clear_blocks(animate: bool) -> void:
	for b in blocks:
		if not is_instance_valid(b):
			continue
		if animate:
			var tw := b.create_tween()
			tw.tween_property(b, "scale", Vector3.ONE * 0.01, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.tween_callback(b.queue_free)
		else:
			b.queue_free()
	blocks.clear()


func _process(delta: float) -> void:
	_t += delta
	_cycle_t -= delta
	var cycle := _cycle_t <= 0.0
	if cycle:
		_cycle_t = 0.075
	var pid := int(state.get("pid", -1))
	if pid >= 0 and main.tokens.has(pid):
		var tok: Node3D = main.tokens[pid]
		for b in blocks:
			if not is_instance_valid(b):
				continue
			var i := int(b.get_meta("slot"))
			var n := int(b.get_meta("n"))
			var side := (float(i) - (n - 1) * 0.5) * 1.5
			var want := tok.position + Vector3(side, 3.9 + 0.12 * sin(_t * 3.0 + i), 0)
			b.position = b.position.lerp(want, 1.0 - exp(-12.0 * delta)) if b.position.length() > 0.01 else want
			var mi := b.get_node("Cube") as Node3D
			if int(b.get_meta("value")) == 0:
				mi.rotation.y += delta * 7.0
				mi.rotation.x = 0.25 * sin(_t * 5.0 + i)
				if cycle and String(state.get("mode", "")) != "vr":
					_set_faces(b, str(randi_range(1, 6)), Color(0.15, 0.2, 0.45))
				elif String(state.get("mode", "")) == "vr":
					_set_faces(b, "?", Color(0.15, 0.2, 0.45))
			else:
				mi.rotation.y = lerp_angle(mi.rotation.y, PI if main.vr_rig == null else 0.0, 1.0 - exp(-10.0 * delta))
				mi.rotation.x = lerpf(mi.rotation.x, 0.0, 1.0 - exp(-10.0 * delta))
	if not vr_dice.is_empty():
		_vr_update(delta)


# --- VR physical dice (host) ------------------------------------------------------------------------------

func _build_table_collision() -> void:
	table_body = StaticBody3D.new()
	table_body.name = "DiceTable"
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.25
	pm.friction = 0.7
	table_body.physics_material_override = pm
	add_child(table_body)
	var top := float(main.TABLE_Y) + 0.62 * float(main.S)
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 0.2, 3.0)
	floor_shape.shape = box
	floor_shape.position = Vector3(0, top - 0.1, 0)
	table_body.add_child(floor_shape)
	var rad := 17.0 * float(main.S)
	for k in 10:
		var a := k * TAU / 10.0
		var w := CollisionShape3D.new()
		var wb := BoxShape3D.new()
		wb.size = Vector3(2.0 * rad * tan(PI / 10.0) + 0.05, 0.3, 0.06)
		w.shape = wb
		w.position = Vector3(sin(a) * rad, top, cos(a) * rad)
		w.rotation.y = a
		table_body.add_child(w)
	var cone := CollisionShape3D.new()
	var cs := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	var vc := Vector3(BD.VOLCANO.x, 0.4, BD.VOLCANO.y)
	for k in 12:
		var a2 := k * TAU / 12.0
		pts.append(Vector3(cos(a2) * BD.VOLCANO_R * 0.85, 0.4, sin(a2) * BD.VOLCANO_R * 0.85) * float(main.S))
		pts.append(Vector3(cos(a2) * 1.1, BD.VOLCANO_H - 0.6, sin(a2) * 1.1) * float(main.S))
	cs.points = pts
	cone.shape = cs
	cone.position = Vector3(vc.x * float(main.S), float(main.TABLE_Y), vc.z * float(main.S))
	table_body.add_child(cone)


## Where new VR dice wait: in front of the VR player's right hip, over the table edge.
func pedestal(i: int) -> Vector3:
	return Vector3(0.22 + i * 0.13, float(main.TABLE_Y) + 0.32, float(main.VR_FEET.z) - 0.42)


func _spawn_vr(n: int) -> void:
	_held = -1
	_reported = false
	_hint_t = 0.0
	for i in n:
		var body := RigidBody3D.new()
		body.name = "VrDie%d" % i
		body.mass = 0.05
		body.continuous_cd = true
		body.freeze = true
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		var pm := PhysicsMaterial.new()
		pm.bounce = 0.35
		pm.friction = 0.6
		body.physics_material_override = pm
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3.ONE * DIE_M
		cs.shape = bs
		body.add_child(cs)
		var mi := MeshKit.instance(ResCache.get_or_make("pb_die_v1", die_mesh), false)
		mi.scale = Vector3.ONE * DIE_M
		body.add_child(mi)
		add_child(body)
		body.global_position = pedestal(i)
		body.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		vr_dice.append(body)
		_released_t.append(-1.0)
		_still_t.append(0.0)
		_settled.append(0)
	main.vr_rig.guard_trigger()


func _clear_vr() -> void:
	for d in vr_dice:
		if is_instance_valid(d):
			d.queue_free()
	vr_dice.clear()
	_released_t.clear()
	_still_t.clear()
	_settled.clear()
	_held = -1


## A real-looking die (size 1): white rounded cube with dark pips.
static func die_mesh() -> Resource:
	var b := MeshKit.Builder.new()
	b.rounded_box(Vector3.ONE, 0.16, MeshKit.at(Vector3.ZERO), Color(0.98, 0.97, 0.94), 2)
	var pips := {1: [Vector2.ZERO], 2: [Vector2(-0.25, -0.25), Vector2(0.25, 0.25)],
		3: [Vector2(-0.25, -0.25), Vector2.ZERO, Vector2(0.25, 0.25)],
		4: [Vector2(-0.25, -0.25), Vector2(0.25, -0.25), Vector2(-0.25, 0.25), Vector2(0.25, 0.25)],
		5: [Vector2(-0.25, -0.25), Vector2(0.25, -0.25), Vector2.ZERO, Vector2(-0.25, 0.25), Vector2(0.25, 0.25)],
		6: [Vector2(-0.25, -0.27), Vector2(0.25, -0.27), Vector2(-0.25, 0.0), Vector2(0.25, 0.0), Vector2(-0.25, 0.27), Vector2(0.25, 0.27)]}
	for f in FACES:
		var fa: Array = f
		var n: Vector3 = fa[0]
		var v: int = int(fa[1])
		var u := Vector3(n.y, n.z, n.x)
		var w := n.cross(u)
		for p in pips[v]:
			var pv: Vector2 = p
			var c := Color(0.85, 0.15, 0.2) if v == 1 else Color(0.12, 0.12, 0.18)
			b.sphere(0.1 if v == 1 else 0.075, MeshKit.at(n * 0.49 + u * pv.x + w * pv.y, Vector3(1, 1, 1) - n.abs() * 0.6), c, 8)
	return b.build()


static func up_face(basis: Basis) -> int:
	var best := 1
	var bd := -2.0
	for f in FACES:
		var fa: Array = f
		var d := (basis * (fa[0] as Vector3)).normalized().dot(Vector3.UP)
		if d > bd:
			bd = d
			best = int(fa[1])
	return best


func _vr_update(delta: float) -> void:
	var rig: Node = main.vr_rig
	if rig == null or get_tree().paused:
		return
	_hint_t += delta
	for i in vr_dice.size():
		var d := vr_dice[i]
		if not is_instance_valid(d) or _settled[i] > 0:
			continue
		if i == _held:
			d.global_transform = rig.hand_r.global_transform * _hold_xf
			if rig.trigger_released() or not rig.trigger_down():
				_throw(i)
			continue
		if _released_t[i] < 0.0:
			# Waiting on its pedestal: bob and spin a little; grab it with the trigger.
			var base := pedestal(i)
			d.global_position = base + Vector3(0, 0.015 * sin(_t * 2.5 + i), 0)
			d.rotate_y(delta * 0.8)
			if _held < 0 and rig.trigger_pressed() and rig.touching(1, d.global_position, 0.12):
				_held = i
				_hold_xf = rig.hand_r.global_transform.affine_inverse() * d.global_transform
				rig.pulse(1, 0.5, 0.06)
				main.sfx.play("pickup", -6.0, 1.2)
			continue
		_released_t[i] += delta
		var off_table: bool = d.global_position.y < float(main.TABLE_Y) - 0.15 or Vector2(d.global_position.x, d.global_position.z).length() > 1.6
		if off_table:
			_reset_die(i)
			main.hud.toast("Oops! The dice fell off. Throw again!", 0, "question")
			continue
		if d.linear_velocity.length() < 0.04 and d.angular_velocity.length() < 0.4 and _released_t[i] > 0.4:
			_still_t[i] += delta
		else:
			_still_t[i] = 0.0
		if _still_t[i] > 0.3 or _released_t[i] > 6.0:
			_settled[i] = up_face(d.global_basis)
			main.sfx.play("ding", -2.0, 1.2)
			rig.pulse(1, 0.4, 0.05)
	var done := true
	for v in _settled:
		if v <= 0:
			done = false
	if done and not _reported and not _settled.is_empty():
		_reported = true
		var values: Array = []
		for v in _settled:
			values.append(v)
		if main.flow != null:
			main.flow.on_vr_dice(int(state.get("id", -1)), values)


func _throw(i: int) -> void:
	var rig: Node = main.vr_rig
	var d := vr_dice[i]
	_held = -1
	d.freeze = false
	var v: Vector3 = rig.hand_velocity(1) * 1.15
	if v.length() > 3.5:
		v = v.normalized() * 3.5
	if v.length() < 0.35:  # just let go: give it a friendly toss onto the island
		var to: Vector3 = main.to_world(Vector3(0, 0, 3)) - d.global_position
		to.y = 0.0
		v = to.normalized() * 0.9 + Vector3(0, 1.0, 0)
	v.y = maxf(v.y, 0.4)
	d.linear_velocity = v
	d.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(10.0, 16.0)
	_released_t[i] = 0.0
	_still_t[i] = 0.0
	rig.pulse(1, 0.7, 0.08)
	main.sfx.play("whoosh", -4.0, 1.3)
	main.sfx.play("dice", -2.0)


func _reset_die(i: int) -> void:
	var d := vr_dice[i]
	d.freeze = true
	d.linear_velocity = Vector3.ZERO
	d.angular_velocity = Vector3.ZERO
	d.global_position = pedestal(i)
	_released_t[i] = -1.0
	_still_t[i] = 0.0


## True while the VR player has dice waiting (bots / hints).
func vr_waiting() -> bool:
	for i in vr_dice.size():
		if _released_t[i] < 0.0 and i != _held:
			return true
	return false


func on_fx(_kind: String, _args: Variant) -> void:
	pass


# --- Snapshots: the VR dice for the TV machine ---------------------------------------------------------

func snapshot() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for d in vr_dice:
		if not is_instance_valid(d):
			continue
		var p: Vector3 = main.to_board(d.global_position)
		var q := d.global_basis.orthonormalized().get_rotation_quaternion()
		out.append_array([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(q.x, 0.01),
			snappedf(q.y, 0.01), snappedf(q.z, 0.01), snappedf(q.w, 0.01)])
	return out


func apply_snapshot(s: PackedFloat32Array) -> void:
	var n := s.size() / 7
	while mirrors.size() < n:
		var mi := MeshKit.instance(ResCache.get_or_make("pb_die_v1", die_mesh), false)
		var holder := Node3D.new()
		holder.add_child(mi)
		mi.scale = Vector3.ONE * DIE_M / float(main.S_VR)
		main.stage.add_child(holder)
		mirrors.append(holder)
	while mirrors.size() > n:
		var m: Node3D = mirrors.pop_back()
		m.queue_free()
	for i in n:
		var o := i * 7
		var m := mirrors[i]
		var target := Transform3D(Basis(Quaternion(s[o + 3], s[o + 4], s[o + 5], s[o + 6]).normalized()), Vector3(s[o], s[o + 1], s[o + 2]))
		m.transform = m.transform.interpolate_with(target, 0.6)
