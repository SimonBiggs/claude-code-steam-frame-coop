extends Node3D
## Simple mode: teach by doing, not by text.
##  PRACTICE (before wave 1): a glowing training goblin drops onto the table near the Giant and a
##  glowing ring lies on the table. Grab the goblin and throw it into the ring (throwing it off the
##  table, squashing or smacking it all count too; knights' bonks just make it giggle): confetti, a chime, and
##  the next one. After STEPS of them (or MAX_TIME seconds) wave 1 starts.
##  A bouncing arrow points at the goblin (at the ring while you hold it), and a see-through ghost
##  hand shows the move: reach down, squeeze, swing over to the ring, let go.
##  RAIN: the same ghost hand, open, hovers over the campfire (an umbrella) until the Giant's hand
##  is there.
## Host runs the logic; the TV draws the ring and arrow from the snapshot (active, ring_pos).

const W := preload("res://games/giants_table/world.gd")
const GoblinScript := preload("res://games/giants_table/goblin.gd")
const GOBLIN_SPOTS := [Vector3(1.2, 0.0, 8.8), Vector3(-1.4, 0.0, 9.2)]
const RING_SPOTS := [Vector3(-4.6, 0.0, 7.4), Vector3(4.0, 0.0, 6.8)]
const STEPS := 2
const MAX_TIME := 50.0
const RING_R := 2.0
const DEMO_LOOP := 3.6

var main
var active := true
var step := 0
var t := 0.0
var gap := 1.0
var goblin = null
var ring_pos := Vector3.ZERO
var ring: MeshInstance3D
var ring_mat: StandardMaterial3D
var arrow: MeshInstance3D
var hand: Node3D
var hand_mat: StandardMaterial3D
var fingers: Array = []
var thumb: Node3D
var demo_t := 0.0
var idle_t := 0.0
var anim_t := 0.0


func _ready() -> void:
	ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = RING_R - 0.3
	tm.outer_radius = RING_R
	tm.rings = 28
	tm.ring_segments = 6
	ring.mesh = tm
	ring_mat = W.mat(Color(1.0, 0.85, 0.3), 3.0)
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1.0, 0.4, 1.0)
	ring.visible = false
	add_child(ring)
	arrow = MeshInstance3D.new()
	arrow.mesh = W.cyl(0.5, 0.0, 0.9, 8)  # wide end up: points down at the thing to grab
	var am := W.mat(Color(1.0, 0.9, 0.35), 3.0)
	am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow.material_override = am
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arrow.visible = false
	add_child(arrow)
	_build_hand()


## A see-through glowing copy of the giant's hand (fingers point -Z, palm down).
func _build_hand() -> void:
	hand = Node3D.new()
	hand.visible = false
	add_child(hand)
	hand_mat = StandardMaterial3D.new()
	hand_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hand_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hand_mat.albedo_color = Color(0.75, 0.95, 1.0, 0.5)
	var palm := MeshInstance3D.new()
	palm.mesh = W.box(Vector3(1.45, 0.45, 1.5))
	palm.position = Vector3(0.0, 0.0, 0.25)
	hand.add_child(palm)
	for i in 4:
		var f := Node3D.new()
		f.position = Vector3(-0.54 + i * 0.36, 0.0, -0.45)
		hand.add_child(f)
		var fm := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.16
		cap.height = 0.95
		cap.radial_segments = 8
		cap.rings = 2
		fm.mesh = cap
		fm.rotation.x = PI / 2.0
		fm.position.z = -0.4
		f.add_child(fm)
		fingers.append(f)
	thumb = Node3D.new()
	thumb.position = Vector3(-0.75, -0.05, 0.25)
	thumb.rotation.y = -0.7
	hand.add_child(thumb)
	var tmi := MeshInstance3D.new()
	var tcap := CapsuleMesh.new()
	tcap.radius = 0.17
	tcap.height = 0.8
	tcap.radial_segments = 8
	tcap.rings = 2
	tmi.mesh = tcap
	tmi.rotation.x = PI / 2.0
	tmi.position.z = -0.3
	thumb.add_child(tmi)
	_style(hand)


func _style(n: Node) -> void:
	if n is MeshInstance3D:
		n.material_override = hand_mat
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_style(c)


# --- Host logic ----------------------------------------------------------------------

func tick(delta: float) -> void:
	if not active:
		return
	t += delta
	if t > MAX_TIME:
		print("Practice: time's up, on to wave 1")
		_finish()
		return
	if goblin != null and (not is_instance_valid(goblin) or goblin.is_queued_for_deletion()):
		goblin = null
	if goblin == null:
		gap -= delta
		if gap <= 0.0:
			_spawn()


func _spawn() -> void:
	var g := GoblinScript.new()
	g.setup("goblin", main)
	g.practice = true
	g.net_id = main.next_net_id()
	var s: Vector3 = GOBLIN_SPOTS[step % GOBLIN_SPOTS.size()]
	g.position = Vector3(s.x, W.height(s.x, s.z) + 7.0, s.z)
	g.flying = true
	g.hop = true  # drops in gently (no squash on this landing)
	main.add_child(g)
	goblin = g
	var r: Vector3 = RING_SPOTS[step % RING_SPOTS.size()]
	ring_pos = Vector3(r.x, maxf(W.height(r.x, r.z), 0.0), r.z)
	main.sound("pickup", -4.0, 1.5)
	print("Practice: training goblin %d" % (step + 1))


## Did the training goblin land in the ring?
func in_ring(p: Vector3) -> bool:
	return active and Vector2(p.x - ring_pos.x, p.z - ring_pos.z).length() < RING_R + 0.3


## The training goblin was beaten (main.goblin_defeated): confetti and the next one.
func on_hit(g) -> void:
	var p: Vector3 = g.grab_center()
	for i in 4:
		main.burst(p + Vector3.UP * 0.5, Color.from_hsv(randf(), 0.7, 1.0), 12, 0.12)
	main.sound("chime", 0.0, 1.0 + 0.15 * step)
	main.sound("cheer", -8.0)
	step += 1
	goblin = null
	gap = 0.9
	print("Practice: %d / %d" % [step, STEPS])
	if step >= STEPS:
		_finish()


func _finish() -> void:
	active = false
	if goblin != null and is_instance_valid(goblin):
		goblin.queue_free()
	goblin = null
	main.practice_finished()


# --- Visuals (every machine) -------------------------------------------------------------

func _process(delta: float) -> void:
	anim_t += delta
	var g = _training_goblin()
	ring.visible = active and g != null
	arrow.visible = false
	if ring.visible:
		var pulse := 1.0 + 0.06 * sin(anim_t * 5.0)
		ring.position = ring_pos + Vector3.UP * 0.1
		ring.scale = Vector3(pulse, 0.4, pulse)
		ring_mat.emission_energy_multiplier = 2.0 + 1.5 * (0.5 + 0.5 * sin(anim_t * 5.0))
		var over: Vector3 = ring_pos + Vector3.UP * 0.6 if g.held else g.grab_center()
		arrow.visible = not g.flying or g.hop
		arrow.position = over + Vector3.UP * (2.0 + 0.35 * absf(sin(anim_t * 4.0)))
	_update_hand(delta, g)


func _training_goblin():
	if not active:
		return null
	if goblin != null and is_instance_valid(goblin):
		return goblin
	for g in get_tree().get_nodes_in_group("goblins"):
		if g.practice and not g.is_queued_for_deletion():
			return g
	return null


func _update_hand(delta: float, g) -> void:
	var giant = main.giant
	var mine: bool = giant != null and (giant.vr or giant.flat)  # only the Giant's own view
	if mine and main.rain_t > 0.0 and not main.shield and not main.game_over:
		# Umbrella: an open hand, palm down, bobbing over the campfire.
		hand.visible = true
		hand.position = Vector3(0.0, 5.0 + 0.4 * sin(anim_t * 3.0), 0.0)
		hand.basis = _face_basis(Vector3.ZERO)
		_grip(0.0)
		hand_mat.albedo_color.a = 0.3 + 0.2 * (0.5 + 0.5 * sin(anim_t * 4.0))
		return
	var holding := false
	if giant != null:
		for h in giant.hands:
			if h.held != null:
				holding = true
	if not mine or g == null or g.held or holding or (g.flying and not g.hop):
		hand.visible = false
		idle_t = 0.0
		demo_t = 0.0
		return
	idle_t += delta
	if idle_t < 1.2:
		hand.visible = false
		return
	demo_t = fmod(demo_t + delta, DEMO_LOOP)
	var gc: Vector3 = g.grab_center()
	var above := gc + Vector3.UP * 4.0
	var low := gc + Vector3.UP * 0.5
	var ring_top := ring_pos + Vector3.UP * 3.0
	var p := above
	var grip := 0.0
	var alpha := 0.5
	var d := demo_t
	if d < 0.9:
		var k := ease(d / 0.9, -1.8)
		p = above.lerp(low, k)
		alpha = 0.5 * minf(1.0, d / 0.3)
	elif d < 1.2:
		p = low
		grip = (d - 0.9) / 0.3
	elif d < 2.2:
		var k2 := ease((d - 1.2) / 1.0, -1.8)
		p = low.lerp(ring_top, k2) + Vector3.UP * sin(k2 * PI) * 2.0
		grip = 1.0
	elif d < 2.5:
		p = ring_top
		grip = 1.0 - (d - 2.2) / 0.3
	else:
		p = ring_top
		alpha = 0.5 * maxf(0.0, 1.0 - (d - 2.5) / 0.6)
	hand.visible = alpha > 0.01
	hand.position = p + Vector3.UP * 0.35
	hand.basis = _face_basis(p)
	_grip(grip)
	hand_mat.albedo_color.a = alpha


## Fingers pointing away from the Giant's eyes, towards p.
func _face_basis(p: Vector3) -> Basis:
	var eye: Vector3 = main.giant.head_transform().origin if main.giant != null else Vector3(0, 20, 20)
	var d := p - eye
	if Vector2(d.x, d.z).length() < 0.1:
		return Basis()
	return Basis(Vector3.UP, atan2(-d.x, -d.z))


func _grip(g: float) -> void:
	for f in fingers:
		f.rotation.x = -g * 1.25
	thumb.rotation.x = -g * 0.6
