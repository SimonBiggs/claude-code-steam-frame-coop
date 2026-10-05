extends Node
## DUNGEON DELVE: the VR knight's hands (host with a headset only).
##  - RIGHT hand: a big friendly toy sword. Swing it through a slime or a bat and it poofs. It also
##    smashes pots and pokes everything else (torches, chests, the skeleton, the dummy).
##  - LEFT hand (the Frame's left buttons don't reach the game, so it works by touch): touch a pot
##    and it sticks to the glove; flick the hand to throw it (it smashes, and bops a monster it hits).
##    Touching a torch, chest, the skeleton or the big treasure chest pokes it.
## Hits go to main (hit_monster / prop_poke / throw_pot), which decides and plays everything.

const VrRig := preload("res://core/vr_rig.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Dungeon := preload("res://games/dungeon_delve/dungeon.gd")

const BLADE := 0.95  ## from the hand to the tip
const SWING_SPEED := 1.2  ## tip speed (m/s) that counts as a swing

var main: Node
var rig: VrRig
var sword: MeshInstance3D
var held_pot := -1
var held_t := 0.0
var idle_t := 0.0  ## seconds since the sword last hit anything (the ghost hand comes back)
var swings := 0  ## bots: sword hits
var _tip_prev := Vector3.INF
var _blade_on := {}
var _touch_on: Array[Dictionary] = [{}, {}]


static func sword_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var down := Vector3(-PI * 0.5, 0.0, 0.0)  # +Y of a primitive -> -Z (forward from the hand)
	b.cylinder(0.025, 0.028, 0.16, MeshKit.at(Vector3(0, 0, 0.02), Vector3.ONE, down), Color(0.5, 0.3, 0.2), 8)
	b.sphere(0.035, MeshKit.at(Vector3(0, 0, 0.11)), Color(1.0, 0.8, 0.3), 8)
	b.rounded_box(Vector3(0.26, 0.04, 0.05), 0.015, MeshKit.at(Vector3(0, 0, -0.07)), Color(1.0, 0.8, 0.3))
	b.rounded_box(Vector3(0.075, 0.025, 0.8), 0.012, MeshKit.at(Vector3(0, 0, -0.5)), Color(0.75, 0.9, 1.0))
	b.cone(0.04, 0.09, MeshKit.at(Vector3(0, 0, -0.94), Vector3(1.0, 1.0, 0.35), down), Color(0.75, 0.9, 1.0), 4)
	b.box(Vector3(0.02, 0.028, 0.7), MeshKit.at(Vector3(0, 0, -0.48)), Color(0.55, 0.85, 1.0), true)
	return b.build()


func setup(m: Node, r: VrRig) -> void:
	main = m
	rig = r
	sword = MeshKit.instance(sword_mesh(), false)
	rig.hand_r.add_child(sword)


func blade() -> Array:
	var hp := rig.hand_point(VrRig.RIGHT)
	var fwd := -rig.hand_r.global_basis.z
	return [hp + fwd * 0.08, hp + fwd * BLADE]


static func seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func update(delta: float) -> void:
	idle_t += delta
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
	var dg: Dungeon = main.dungeon
	# Monsters.
	if swinging:
		for id in main.monsters.mons.keys():
			var c: Vector3 = main.monsters.center_of(id)
			if seg_dist(c, base, tip) < main.monsters.radius_of(id) + 0.1:
				if main.hit_monster(int(id), 0, c):
					swings += 1
					idle_t = 0.0
					rig.pulse(VrRig.RIGHT, 0.7, 0.08)
	# Props: the blade, and both hands.
	var my_room := Dungeon.room_of(rig.head_position())
	var blade_now := {}
	var touch_now: Array[Dictionary] = [{}, {}]
	for id in dg.props.size():
		var p: Dictionary = dg.props[id]
		var kind: int = p["kind"]
		if absi(int(p["room"]) - my_room) > 1 or (dg.is_used(id) and kind != Dungeon.BIG) or id == held_pot or main.pot_fly.has(id):
			continue
		var c2 := dg.prop_center(id)
		var r: float = p["r"]
		if seg_dist(c2, base, tip) < r:
			blade_now[id] = true
			if not _blade_on.has(id) and (swinging or kind != Dungeon.POT):
				if main.prop_poke(id, 0):
					idle_t = 0.0
					rig.pulse(VrRig.RIGHT, 0.5, 0.06)
		for h in 2:
			if rig.hand_point(h).distance_to(c2) < r + 0.04:
				touch_now[h][id] = true
				if _touch_on[h].has(id):
					continue
				if kind == Dungeon.POT and h == VrRig.LEFT and held_pot < 0:
					held_pot = id
					held_t = 0.0
					rig.pulse(h, 0.4, 0.06)
					main.sound_at("pickup", c2, -8.0, 1.2)
				elif kind != Dungeon.POT or h == VrRig.RIGHT:
					if main.prop_poke(id, 0):
						rig.pulse(h, 0.4, 0.05)
	_blade_on = blade_now
	_touch_on = touch_now
	# The pot in the left hand: follows the glove; a flick throws it.
	if held_pot >= 0:
		held_t += delta
		var pn: Node3D = dg.props[held_pot]["node"]
		pn.global_position = rig.hand_point(VrRig.LEFT) + Vector3(0.0, -0.2, 0.0)
		var v := rig.hand_velocity(VrRig.LEFT)
		if held_t > 0.3 and v.length() > 2.0:
			main.throw_pot(held_pot, pn.global_position, v * 1.5)
			rig.pulse(VrRig.LEFT, 0.5, 0.06)
			held_pot = -1


## A new round: let go of everything.
func reset() -> void:
	held_pot = -1
	_tip_prev = Vector3.INF
