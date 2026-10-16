extends Node3D
## ELEMENTAL BENDER: the MASTER BENDER, the VR player (slot 0, host / local with a headset or BOT_VR).
## This node is also the VR player's body for the fight: it stands under the head (group eb_player,
## hit_radius / hit_height, hp, take_hit) so raiders chase and hit it like any bender.
## Bending with the hands (all measured against the head, generous dead zones, no rest pose):
##  - ELEMENT: four glowing orbs float round the waist, in front and to the sides (never near the face,
##    never at the left wrist's MENU); touch one with either glove to pick that element.
##  - ATTACK: hold the RIGHT trigger and punch / throw: the element flies the way the fist moves
##    (aim-assisted towards the nearest raider in that direction). EARTH: lift the fist with the
##    trigger held and a boulder rises out of the ground and floats in front of you; push to send it.
##  - LEFT fist: a weaker jab of the same element (no trigger needed: the Frame's left trigger
##    doesn't reach the game).
##  - SPECIAL: raise BOTH hands above your head, then bring them down hard (or press A).
##  - SPIRIT STATE: press A when the team's spirit meter on the right wrist glows full.
## Health, chi and the team's spirit meter are three little bars on the back of the right wrist.

const E := preload("res://games/elemental_bender/elem.gd")
const Looks := preload("res://games/elemental_bender/looks.gd")
const World := preload("res://games/elemental_bender/world.gd")
const VrRig := preload("res://core/vr_rig.gd")
const MeshKit := preload("res://core/mesh_kit.gd")

const ORB_R := 0.075
const ORB_TOUCH := 0.13
const ORB_ANGLES: Array[float] = [-75.0, -35.0, 35.0, 75.0]  ## degrees right of the body's facing
const ORB_DIST := 0.42
const ORB_DROP := 0.62  ## below the eyes (about the waist when standing)
const PUNCH_SPEED := 1.2  ## m/s of the fist that counts as a punch (right hand, trigger held)
const JAB_SPEED := 2.0  ## left hand (no trigger: needs a clearer jab)
const REARM_SPEED := 0.7
const LIFT_SPEED := 0.9
const RAISE := 0.0  ## both hands this far above the eyes = arms raised
const SLAM := -0.45  ## ...then both below this, moving down = slam
const MAX_HP := 100.0
const MAX_CHI := 100.0

var main  ## games/elemental_bender/main.gd (untyped: it calls back into the game)
var rig: VrRig
var slot := 0
var element := E.AIR
var hp := MAX_HP
var max_hp := MAX_HP
var chi := MAX_CHI
var spirit_t := 0.0
var dead := false
var down_t := 0.0
var invuln_t := 0.0
var hit_radius := 0.45
var hit_height := 0.9
var can_act := true
## Bots / stats.
var punches := 0
var jabs := 0
var slams := 0
var rocks_lifted := 0
var orb_touches := 0

var _orbs: Array[MeshInstance3D] = []
var _orb_pos: Array[Vector3] = []
var _body_yaw := 0.0
var _body_ok := false
var _armed := [true, true]
var _cd := [0.0, 0.0]
var _touch_on := [-1, -1]
var _raised_t := 0.0
var _rock: MeshInstance3D
var _rock_t := 0.0
var _glow: Array[MeshInstance3D] = []
var _bars: Array[MeshInstance3D] = []
var _spirit_ready_was := false
var _t := 0.0


func setup(m: Node, r: VrRig) -> void:
	main = m
	rig = r
	add_to_group("eb_player")
	for i in 4:
		var o := MeshKit.instance(Looks.orb(ORB_R, 12), false)
		o.material_override = E.mat(E.COLORS[i], 3.0)
		main.add_child(o)
		_orbs.append(o)
		_orb_pos.append(Vector3.ZERO)
	for h in 2:
		var g := MeshKit.instance(Looks.orb(0.07, 10), false)
		g.position = Vector3(0, 0.0, -0.06)
		rig.hand(h).add_child(g)
		_glow.append(g)
	_build_wrist()
	_set_element(E.AIR)


## Three bars on the back of the right wrist: health, chi, the team's spirit meter.
func _build_wrist() -> void:
	var holder := Node3D.new()
	holder.position = Vector3(0.0, 0.045, 0.09)
	holder.rotation = Vector3(-1.1, 0.0, 0.0)
	rig.hand_r.add_child(holder)
	var back := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.11, 0.004, 0.07)
	back.mesh = bm
	back.material_override = E.mat(Color(0.05, 0.05, 0.08))
	holder.add_child(back)
	var cols: Array[Color] = [Color(1.0, 0.3, 0.3), Color(0.35, 0.65, 1.0), Color(1.0, 0.85, 0.3)]
	for i in 3:
		var bar := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.1, 0.006, 0.014)
		bar.mesh = b
		bar.material_override = E.mat(cols[i], 2.0)
		bar.position = Vector3(0.0, 0.004, -0.022 + i * 0.022)
		holder.add_child(bar)
		_bars.append(bar)


func _set_element(e: int) -> void:
	element = e
	for h in 2:
		_glow[h].material_override = E.mat(E.COLORS[e], 3.0 if h == VrRig.RIGHT else 1.5)
	for i in 4:
		_orbs[i].scale = Vector3.ONE * (1.45 if i == e else 1.0)


## Host / local, every frame.
func step(delta: float) -> void:
	_t += delta
	var head := rig.head_position()
	var feet_y := rig.floor_height
	global_position = Vector3(head.x, feet_y, head.z)
	for i in 2:
		_cd[i] = maxf(0.0, float(_cd[i]) - delta)
	invuln_t -= delta
	if spirit_t > 0.0:
		spirit_t -= delta
		chi = MAX_CHI
		if randf() < 0.5:
			var hp_r := rig.hand_point(randi() % 2)
			main.fx.puff(hp_r, E.COLORS[randi() % 4], 0.05, 0.4, Vector3.UP * 0.6)
		if spirit_t <= 0.0:
			main.on_spirit_faded(slot)
	else:
		chi = minf(MAX_CHI, chi + 15.0 * delta)
	if dead:
		down_t -= delta
		if down_t <= 0.0:
			dead = false
			hp = max_hp
			invuln_t = 2.0
			main.on_revived(slot)
	_place_orbs(head, delta)
	_update_wrist()
	if not can_act or dead:
		_drop_rock(false)
		return
	_touch_orbs()
	_hands(head, delta)
	_special_gesture(head, delta)
	if rig.a_pressed():
		if main.team_spirit_full() and spirit_t <= 0.0:
			main.bender_spirit(slot)
		else:
			_try_special()


## The orbs float round the waist and turn with the body: the body yaw follows the head lazily
## (only when the head turns well away), so looking around doesn't swing the orbs about.
func _place_orbs(head: Vector3, delta: float) -> void:
	var hy := rig.head_yaw()
	if not _body_ok:
		_body_yaw = hy
		_body_ok = true
	var diff := wrapf(hy - _body_yaw, -PI, PI)
	if absf(diff) > deg_to_rad(40.0):
		_body_yaw += diff * (1.0 - exp(-3.0 * delta))
	for i in 4:
		var a := _body_yaw - deg_to_rad(ORB_ANGLES[i])
		var dir := Vector3(-sin(a), 0.0, -cos(a))
		var p := head + dir * ORB_DIST + Vector3(0.0, -ORB_DROP + sin(_t * 2.0 + i) * 0.015, 0.0)
		_orb_pos[i] = p
		_orbs[i].global_position = p
		var k := 1.45 if i == element else 1.0
		if dead:
			k *= 0.6
		_orbs[i].scale = _orbs[i].scale.lerp(Vector3.ONE * k * (1.0 + 0.08 * sin(_t * 5.0 + i)), 1.0 - exp(-10.0 * delta))


func orb_position(i: int) -> Vector3:
	return _orb_pos[i]


func _touch_orbs() -> void:
	for h in 2:
		var hp := rig.hand_point(h)
		var now := -1
		for i in 4:
			if hp.distance_to(_orb_pos[i]) < ORB_TOUCH:
				now = i
		if now >= 0 and now != int(_touch_on[h]) and not (h == VrRig.RIGHT and rig.in_wrist_zone(_orb_pos[now])):
			orb_touches += 1
			rig.pulse(h, 0.5, 0.06)
			if now != element:
				_set_element(now)
				main.sound_at("ui_tick", _orb_pos[now], -2.0, 1.3)
				main.sound_at(E.SOUNDS[now], _orb_pos[now], -10.0, 1.4)
				main.fx.burst(_orb_pos[now], E.COLORS[now], 10, 1.2, 0.04, 0.4)
				main.vr_element_changed(now)
		_touch_on[h] = now


func _hands(head: Vector3, _delta: float) -> void:
	var fwd := rig.head_forward()
	for h in 2:
		var v := rig.hand_velocity(h)
		var speed := v.length()
		if speed < REARM_SPEED:
			_armed[h] = true
		var hp := rig.hand_point(h)
		var out := Vector3(hp.x - head.x, 0.0, hp.z - head.z)
		var vdir := v / maxf(speed, 0.001)
		var outward := vdir.dot(out.normalized()) > 0.2 if out.length() > 0.05 else false
		var forwardish := vdir.dot(fwd) > 0.3 or outward
		if h == VrRig.RIGHT:
			var held := rig.trigger_down()
			if element == E.EARTH and held and _rock == null and bool(_armed[h]) and v.y > LIFT_SPEED and v.y > Vector2(v.x, v.z).length():
				_lift_rock(head, fwd)
				_armed[h] = false
				continue
			if _rock != null:
				_hold_rock(hp, fwd)
				if (held or rig.trigger_released()) and speed > PUNCH_SPEED and forwardish and v.y < speed * 0.7:
					_throw_rock(vdir, fwd)
					_armed[h] = false
				elif not held and not rig.trigger_released():
					_drop_rock(true)
				continue
			if held and bool(_armed[h]) and float(_cd[h]) <= 0.0 and speed > PUNCH_SPEED and forwardish:
				_armed[h] = false
				_punch(h, hp, vdir, fwd, 1.0)
				punches += 1
		else:
			if bool(_armed[h]) and float(_cd[h]) <= 0.0 and speed > JAB_SPEED and forwardish and absf(vdir.y) < 0.7:
				_armed[h] = false
				_punch(h, hp, vdir, fwd, 0.6)
				jabs += 1


## Fire the element from the fist the way it moved (blended with where the hand points), aim-assisted.
func _punch(h: int, hp: Vector3, vdir: Vector3, fwd: Vector3, power: float) -> void:
	var point := -rig.hand(h).global_basis.z
	var dir := (vdir * 0.65 + point * 0.35).normalized()
	if dir.y < -0.3:
		dir.y = -0.3
		dir = dir.normalized()
	var aim: Vector3 = main.aim_assist(hp, dir, 0.9)
	var flat := Vector3(aim.x, 0.0, aim.z).normalized() if Vector2(aim.x, aim.z).length() > 0.05 else fwd
	var shots: Array
	if spirit_t > 0.0:
		_cd[h] = 0.22
		shots = E.spirit_shots(hp + aim * 0.15, aim, global_position, flat)
		main.sound_at("magic", hp, -6.0, 1.6)
	else:
		_cd[h] = float(E.ATTACK_CD[element]) * (1.0 if h == VrRig.RIGHT else 1.6)
		shots = E.primary_shots(element, hp + aim * 0.15, aim, global_position, flat, power)
		main.sound_at(E.SOUNDS[element], hp, -4.0, 1.0)
	rig.pulse(h, 0.6 * power, 0.07)
	main.bender_fire(slot, shots)


func _lift_rock(head: Vector3, fwd: Vector3) -> void:
	rocks_lifted += 1
	_rock = MeshKit.instance(Looks.shot(E.EARTH, 0.6, false), false)
	main.add_child(_rock)
	var ground := Vector3(head.x, rig.floor_height - 0.5, head.z) + fwd * 1.3
	_rock.global_position = ground
	_rock_t = 0.0
	main.sound_at("crash", ground, -2.0, 0.8)
	main.fx.burst(ground + Vector3.UP * 0.5, Color(0.6, 0.5, 0.35), 14, 3.0, 0.25, 0.5)
	main.vr_shake(0.3)
	rig.pulse(VrRig.RIGHT, 0.8, 0.12)


func _hold_rock(hp: Vector3, fwd: Vector3) -> void:
	_rock_t += get_process_delta_time()
	var want := hp + fwd * 0.75 + Vector3(0.0, -0.1, 0.0)
	var k := minf(_rock_t / 0.25, 1.0)
	_rock.global_position = _rock.global_position.lerp(want, 0.15 + 0.5 * k)
	_rock.rotate_y(0.04)
	if _rock_t > 6.0:
		_drop_rock(true)


func _throw_rock(vdir: Vector3, fwd: Vector3) -> void:
	var from := _rock.global_position
	var aim: Vector3 = main.aim_assist(from, (vdir * 0.7 + fwd * 0.3).normalized(), 0.88)
	var p := {"element": E.EARTH, "team": 0, "pos": from, "vel": aim * 22.0, "damage": 30.0, "knockback": 14.0,
		"radius": 0.6, "life": 1.6, "effect": "stun"}
	_rock.queue_free()
	_rock = null
	_cd[VrRig.RIGHT] = E.ATTACK_CD[E.EARTH]
	punches += 1
	main.sound_at("crash", from, -2.0, 1.2)
	rig.pulse(VrRig.RIGHT, 0.9, 0.1)
	main.bender_fire(slot, [p])


func _drop_rock(crumble: bool) -> void:
	if _rock == null:
		return
	if crumble:
		main.fx.burst(_rock.global_position, E.ROCK, 12, 3.0, 0.2, 0.5)
	_rock.queue_free()
	_rock = null


## Both hands up above the head, then down hard: the element's special.
func _special_gesture(head: Vector3, delta: float) -> void:
	var yl := rig.hand_point(VrRig.LEFT).y - head.y
	var yr := rig.hand_point(VrRig.RIGHT).y - head.y
	if yl > RAISE and yr > RAISE:
		_raised_t = 1.2
	elif _raised_t > 0.0:
		_raised_t -= delta
		var vl := rig.hand_velocity(VrRig.LEFT).y
		var vr := rig.hand_velocity(VrRig.RIGHT).y
		if yl < SLAM and yr < SLAM and (vl < -0.8 or vr < -0.8):
			_raised_t = 0.0
			slams += 1
			_try_special()


func _try_special() -> void:
	var cost: float = E.SPECIAL_COST[element]
	if chi < cost and spirit_t <= 0.0:
		main.sound_at("ui_error", rig.head_position() + rig.head_forward(), -4.0, 1.0)
		rig.pulse(VrRig.RIGHT, 0.2, 0.2)
		main.vr_note("NEED CHI")
		return
	if spirit_t <= 0.0:
		chi -= cost
	rig.pulse(VrRig.LEFT, 0.9, 0.25)
	rig.pulse(VrRig.RIGHT, 0.9, 0.25)
	main.vr_shake(0.6 if element == E.EARTH else 0.3)
	main.bender_special(slot, element, global_position)


func _update_wrist() -> void:
	var fr: Array[float] = [hp / max_hp, chi / MAX_CHI, float(main.team_spirit()) / 100.0]
	if spirit_t > 0.0:
		fr[2] = spirit_t / E.SPIRIT_TIME
	for i in 3:
		var f := clampf(fr[i], 0.0, 1.0)
		_bars[i].scale = Vector3(maxf(f, 0.02), 1.0, 1.0)
		_bars[i].position.x = -0.05 * (1.0 - f)
	var ready: bool = main.team_spirit_full() and spirit_t <= 0.0
	_bars[2].scale.y = 1.0 + (0.8 + 0.8 * sin(_t * 10.0) if ready else 0.0)
	if ready and not _spirit_ready_was:
		rig.pulse(VrRig.RIGHT, 0.5, 0.3)
	_spirit_ready_was = ready


## Host / local: something hurt the master. Returns the damage taken.
func take_hit(dmg: float, _push: Vector3) -> float:
	if dead or invuln_t > 0.0:
		return 0.0
	if spirit_t > 0.0:
		dmg *= 0.3
	hp -= dmg
	invuln_t = 0.5
	rig.pulse(VrRig.LEFT, 0.7, 0.15)
	rig.pulse(VrRig.RIGHT, 0.7, 0.15)
	if hp <= 0.0:
		hp = 0.0
		dead = true
		down_t = 6.0
		spirit_t = 0.0
		_drop_rock(true)
	return dmg


func visual_yaw() -> float:
	return rig.head_yaw()


func cleanup() -> void:
	for o in _orbs:
		if is_instance_valid(o):
			o.queue_free()
	_drop_rock(false)
