extends Node3D
## SIMPLE_MODE practice for the VR builder: SHOWS how to build instead of text. A see-through glowing
## hand comes down onto the tray, curls its fingers round a block, carries it over to the glowing gap
## (the see-through hint block) and lets go: the ghost block drops into place. It loops on the first
## level until the builder puts down their first block, and comes back on any level if they haven't
## built anything for a while. Only made on the VR host (nobody else needs it).

const Art := preload("res://games/block_builders/art.gd")
const CYCLE := 4.2
const S := 8.0

var main
var hand: Node3D
var fingers: Array[Node3D] = []
var mat: StandardMaterial3D
var block: MeshInstance3D
var block_mat: StandardMaterial3D
var t := 0.0
var idle_t := 0.0
var shown := false  # bots: the demo has been on screen


func _ready() -> void:
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 1.0, 0.95, 0.5)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	hand = Node3D.new()
	add_child(hand)
	var s := S
	_part(hand, Vector3(0, 0.03 * s, 0.01 * s), Vector3(0.05, 0.022, 0.06) * s)  # palm
	for i in 4:
		var f := Node3D.new()
		f.position = Vector3((-0.033 + i * 0.022) * s, 0.025 * s, -0.045 * s)
		hand.add_child(f)
		fingers.append(f)
		_part(f, Vector3(0, 0, -0.025 * s), Vector3(0.009, 0.009, 0.03) * s)
	var thumb := Node3D.new()
	thumb.position = Vector3(0.05 * s, 0.025 * s, 0.0)
	thumb.rotation.y = -0.7
	hand.add_child(thumb)
	fingers.append(thumb)
	_part(thumb, Vector3(0, 0, -0.02 * s), Vector3(0.01, 0.01, 0.025) * s)
	block_mat = mat.duplicate()
	block_mat.albedo_color = Color(1.0, 0.95, 0.5, 0.55)
	block = MeshInstance3D.new()
	block.material_override = block_mat
	block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(block)
	visible = false


func _part(parent: Node3D, pos: Vector3, radii: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Art.sphere(1.0, 10)
	mi.material_override = mat
	mi.position = pos
	mi.scale = radii
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _want() -> bool:
	var b = main.builder
	if b == null or not b.vr or main.state != "play" or main.hint.size() < 3 or b.held_kind != "":
		return false
	if main.level == 0 and main.placed_level == 0:
		return true
	return main.build_idle() > 20.0


func update_demo(delta: float) -> void:
	if not _want():
		visible = false
		idle_t = 0.0
		t = 0.0
		return
	idle_t += delta
	if idle_t < 1.2:  # a moment to look around first
		visible = false
		return
	var b = main.builder
	var kind: String = Art.KINDS[clampi(int(main.hint[0]), 0, Art.KINDS.size() - 1)]
	var slot := Art.KINDS.find(kind)
	if slot < 0 or not b.slot_on[slot]:
		visible = false
		return
	visible = true
	shown = true
	t = fmod(t + delta, CYCLE)
	var hc: Vector3 = main.hint[1]
	var cell := Vector3(hc.x + 0.5, hc.y + 0.5, hc.z + 0.5)
	var tray_p: Vector3 = b.slot_world(slot)
	var over := cell + Vector3(0, 1.2, 0)
	var grab_y := 0.46  # the block hangs under the grab point (like the real held block)
	var p: Vector3
	var grip := 0.0
	var carry := false
	var drop := 0.0
	if t < 0.7:  # come down onto the tray
		p = tray_p + Vector3(0, 1.4 * (1.0 - ease(t / 0.7, 0.4)), 0)
	elif t < 1.1:  # grab
		p = tray_p
		grip = (t - 0.7) / 0.4
		carry = t > 0.95
	elif t < 2.9:  # carry it over in an arc
		var k := ease((t - 1.1) / 1.8, -1.8)
		p = tray_p.lerp(over, k) + Vector3(0, sin(k * PI) * 1.5, 0)
		grip = 1.0
		carry = true
	elif t < 3.3:  # let go: it drops into the gap
		p = over
		grip = 1.0 - (t - 2.9) / 0.4
		drop = clampf((t - 2.9) / 0.3, 0.0, 1.0)
	else:  # fade away
		p = over + Vector3(0, (t - 3.3) * 0.8, 0)
		drop = 1.0
	var a := 0.55 * minf(1.0, t / 0.3)
	if t > CYCLE - 0.6:
		a *= maxf(0.0, (CYCLE - t) / 0.6)
	mat.albedo_color.a = a
	# Face the hand along the way from the tray to the gap (fingers forward).
	var dir := over - tray_p
	dir.y = 0.0
	var yaw := atan2(-dir.x, -dir.z) if dir.length() > 0.01 else 0.0
	hand.global_transform = Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, -0.02 * S, 0))
	for f in fingers:
		f.rotation.x = -1.4 * grip
	var m := Art.block_mesh(kind)
	if block.mesh != m:
		block.mesh = m
	block.visible = carry or drop > 0.0
	var rot := int(main.hint[2])
	var bp := p - Vector3(0, grab_y, 0)
	if drop > 0.0:
		bp = (over - Vector3(0, grab_y, 0)).lerp(Vector3(cell.x, hc.y, cell.z), ease(drop, 2.0))
	block.global_transform = Transform3D(Basis(Vector3.UP, -rot * PI * 0.5).scaled(Vector3.ONE * 0.92), bp)
	block_mat.albedo_color.a = 0.6 * minf(1.0, t / 0.3) * (1.0 if t < CYCLE - 0.6 else maxf(0.0, (CYCLE - t) / 0.6))
