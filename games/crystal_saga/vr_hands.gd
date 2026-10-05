extends Node
## CRYSTAL SAGA: the VR hero's hands (host with a headset only).
##  - RIGHT hand: the hero's sword. Swing it through a monster and it poofs (the Stone Giant's dark
##    mist shrinks). Touching anything with it pokes it.
##  - LEFT hand: a little fire glows on the glove. RAISE the hand above your head and a fireball flies
##    at the nearest monster in front of you (or the practice target). Lower it to get the next one.
##  - THUNDER (after the cave's golden orb): the sword glows yellow; RAISE THE SWORD above your head and
##    lightning strikes every monster near you.
## Both gestures are measured against the head (no rest pose), with big margins. Either glove touching
## a thing pokes it. Hits go to main (hit_monster / prop_poke / cast_fire / cast_thunder).

const VrRig := preload("res://core/vr_rig.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const World := preload("res://games/crystal_saga/world.gd")

const BLADE := 0.95  ## from the hand to the tip
const SWING_SPEED := 1.2  ## tip speed (m/s) that counts as a swing
const RAISE := -0.02  ## a hand this far above the eyes counts as "raised"
const LOWER := -0.3  ## ...and below this it is "down" again (re-arms the spell)
const FIRE_CD := 0.7
const THUNDER_CD := 2.5

var main: Node
var rig: VrRig
var sword: MeshInstance3D
var sword_glow: MeshInstance3D
var flame: MeshInstance3D
var idle_t := 0.0  ## seconds since the sword last hit a monster (the ghost hand comes back)
var swings := 0  ## bots: sword hits on monsters
var fires := 0  ## bots: fireballs cast
var thunders := 0  ## bots: thunder cast
var fire_cd := 0.0
var thunder_cd := 0.0
var _armed := [true, true]
var _tip_prev := Vector3.INF
var _blade_on := {}
var _touch_on: Array[Dictionary] = [{}, {}]
var _t := 0.0


static func sword_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var down := Vector3(-PI * 0.5, 0.0, 0.0)  # +Y of a primitive -> -Z (forward from the hand)
	b.cylinder(0.025, 0.028, 0.16, MeshKit.at(Vector3(0, 0, 0.02), Vector3.ONE, down), Color(0.3, 0.25, 0.5), 8)
	b.sphere(0.035, MeshKit.at(Vector3(0, 0, 0.11)), Color(0.5, 0.85, 1.0), 8, true)
	b.rounded_box(Vector3(0.28, 0.04, 0.05), 0.015, MeshKit.at(Vector3(0, 0, -0.07)), Color(1.0, 0.8, 0.3))
	b.rounded_box(Vector3(0.075, 0.025, 0.8), 0.012, MeshKit.at(Vector3(0, 0, -0.5)), Color(0.85, 0.92, 1.0))
	b.cone(0.04, 0.09, MeshKit.at(Vector3(0, 0, -0.94), Vector3(1.0, 1.0, 0.35), down), Color(0.85, 0.92, 1.0), 4)
	b.box(Vector3(0.02, 0.028, 0.7), MeshKit.at(Vector3(0, 0, -0.48)), Color(0.5, 0.85, 1.0), true)
	return b.build()


static func flame_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.sphere(0.055, MeshKit.at(Vector3.ZERO), Color(1.0, 0.55, 0.15), 10, true)
	b.cone(0.045, 0.12, MeshKit.at(Vector3(0.0, 0.07, 0.0)), Color(1.0, 0.85, 0.3), 8, true)
	return b.build()


static func glow_blade_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.rounded_box(Vector3(0.1, 0.04, 0.84), 0.02, MeshKit.at(Vector3(0, 0, -0.52)), Color(1.0, 0.95, 0.35), true)
	return b.build()


func setup(m: Node, r: VrRig) -> void:
	main = m
	rig = r
	sword = MeshKit.instance(sword_mesh(), false)
	rig.hand_r.add_child(sword)
	sword_glow = MeshKit.instance(glow_blade_mesh(), false)
	sword_glow.visible = false
	rig.hand_r.add_child(sword_glow)
	flame = MeshKit.instance(flame_mesh(), false)
	flame.position = Vector3(0.0, 0.07, 0.02)
	rig.hand_l.add_child(flame)


func blade() -> Array:
	var hp := rig.hand_point(VrRig.RIGHT)
	var fwd := -rig.hand_r.global_basis.z
	return [hp + fwd * 0.08, hp + fwd * BLADE]


static func seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func update(delta: float, thunder_on: bool) -> void:
	_t += delta
	idle_t += delta
	fire_cd = maxf(0.0, fire_cd - delta)
	thunder_cd = maxf(0.0, thunder_cd - delta)
	var head := rig.head_position()
	_spells(head, thunder_on)
	# The glow on the hand says "ready".
	var ready_k := 1.0 if fire_cd <= 0.0 else 0.35
	flame.scale = Vector3.ONE * ready_k * (1.0 + 0.12 * sin(_t * 9.0))
	sword_glow.visible = thunder_on and thunder_cd <= 0.0
	if sword_glow.visible:
		sword_glow.scale = Vector3(1.0 + 0.2 * sin(_t * 7.0), 1.0, 1.0)
	var bl := blade()
	var base: Vector3 = bl[0]
	var tip: Vector3 = bl[1]
	var speed := 0.0
	if _tip_prev != Vector3.INF:
		speed = (tip - _tip_prev).length() / maxf(delta, 0.0001)
		if speed > 25.0:  # teleported
			speed = 0.0
	_tip_prev = tip
	var swinging := speed > SWING_SPEED
	if swinging:
		for id in main.monsters.mons.keys():
			var c: Vector3 = main.monsters.center_of(id)
			if seg_dist(c, base, tip) < main.monsters.radius_of(id) + 0.1:
				if main.hit_monster(int(id), 0, c):
					swings += 1
					idle_t = 0.0
					rig.pulse(VrRig.RIGHT, 0.7, 0.08)
	# Props: the blade and both gloves.
	var w: World = main.world
	var my_zone := World.zone_of(head)
	var blade_now := {}
	var touch_now: Array[Dictionary] = [{}, {}]
	for id in w.props.size():
		var p: Dictionary = w.props[id]
		var kind: int = p["kind"]
		if absi(int(p["zone"]) - my_zone) > 1 or kind in World.SPELL_ONLY or not (p["node"] as Node3D).visible:
			continue
		var c2 := w.prop_center(id)
		var r: float = p["r"]
		if seg_dist(c2, base, tip) < r:
			blade_now[id] = true
			if not _blade_on.has(id) and main.prop_poke(id, 0):
				rig.pulse(VrRig.RIGHT, 0.5, 0.06)
		for h in 2:
			if rig.hand_point(h).distance_to(c2) < r + 0.05:
				touch_now[h][id] = true
				if not _touch_on[h].has(id) and main.prop_poke(id, 0):
					rig.pulse(h, 0.4, 0.05)
	_blade_on = blade_now
	_touch_on = touch_now


func _spells(head: Vector3, thunder_on: bool) -> void:
	for h in 2:
		var y := rig.hand_point(h).y - head.y
		if y < LOWER:
			_armed[h] = true
		elif y > RAISE and bool(_armed[h]):
			if h == VrRig.LEFT and fire_cd <= 0.0:
				_armed[h] = false
				fire_cd = FIRE_CD
				fires += 1
				main.cast_fire(rig.hand_point(VrRig.LEFT) + Vector3(0.0, 0.1, 0.0))
				rig.pulse(VrRig.LEFT, 0.6, 0.1)
			elif h == VrRig.RIGHT and thunder_on and thunder_cd <= 0.0:
				_armed[h] = false
				thunder_cd = THUNDER_CD
				thunders += 1
				main.cast_thunder(blade()[1])
				rig.pulse(VrRig.RIGHT, 0.9, 0.2)


## A new journey: forget swings in progress.
func reset() -> void:
	_tip_prev = Vector3.INF
	fire_cd = 0.0
	thunder_cd = 0.0
	_armed = [true, true]
