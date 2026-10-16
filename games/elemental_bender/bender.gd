extends CharacterBody3D
## ELEMENTAL BENDER: a TV bender (slots 1..6, and slot 0 in local play without a headset).
## Exactly the source game's bender: switch between the four elements, primary attack (RT), special
## (LT / Y, costs chi), dash (B), jump (A; air benders double-jump and glide), Spirit State (click a
## stick when the team's spirit meter is full).
## Roles on each machine:
##  - `owned`: driven by a local controller here (physics, input, chase camera, chi). On the TV
##    machine it reports its position to the host 30x a second and asks the host for every attack.
##  - `auth`: the host / local copy that owns health, Spirit State and being knocked down. On the
##    host a TV machine's bender is auth but not owned: a puppet that glides to the reported spot.
## Everything that hurts or scores goes through main (host-authoritative).

const E := preload("res://games/elemental_bender/elem.gd")
const Looks := preload("res://games/elemental_bender/looks.gd")
const World := preload("res://games/elemental_bender/world.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const CameraRig := preload("res://core/camera_rig.gd")
const UiMenu := preload("res://core/ui_menu.gd")

const MAX_HP := 100.0
const MAX_CHI := 100.0
const DOWN_TIME := 6.0

var game: Node
var party: Node
var slot := 1
var owned := true
var auth := true
var band := Color.WHITE
var element := E.AIR
var hp := MAX_HP
var max_hp := MAX_HP
var chi := MAX_CHI
var spirit_t := 0.0
var dead := false
var down_t := 0.0
var hit_radius := 0.5
var hit_height := 1.0
var invuln_t := 0.0
var cam: CameraRig
var can_act := true  ## main turns this off on the results screen
var show_name := true  ## a name tag above the head (not in a real headset: no Label3D billboards in VR)
## Bots / stats.
var attacks := 0
var specials := 0

var _cd := 0.0
var _dash_t := 0.0
var _dash_dir := Vector3.ZERO
var _air_jumps := 0
var _aim_face_t := 0.0
var _hand := 0
var _hurt_flash := 0.0
var _aura_t := 0.0
var _visual: Node3D
var _mesh: MeshInstance3D
var _shown := -1
var _goal := Vector3.ZERO
var _goal_yaw := 0.0
var _was_dead := false
var _walk_t := 0.0
var _last_pos := Vector3.ZERO


func _ready() -> void:
	add_to_group("eb_player")
	collision_layer = 2
	collision_mask = 1 | 4
	floor_snap_length = 0.4
	if not owned:
		collision_layer = 0
		collision_mask = 0
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	_visual = Node3D.new()
	add_child(_visual)
	_mesh = MeshKit.instance(Looks.bender(element, band), false)
	_visual.add_child(_mesh)
	if show_name:
		HudKit.nameplate(self, String(party.call("name_of", slot)), slot, 2.25, 0.16)
	_goal = position
	_last_pos = position
	_apply_look()


func _apply_look() -> void:
	if _shown == element:
		return
	_shown = element
	_mesh.mesh = Looks.bender(element, band)


## Host: a TV machine's bender moved there.
func set_remote(pos: Vector3, yaw: float) -> void:
	_goal = pos
	_goal_yaw = yaw


func forward() -> Vector3:
	if cam != null and cam.camera != null:
		var f := -cam.camera.global_basis.z
		f.y = 0.0
		if f.length() > 0.01:
			return f.normalized()
	return Basis(Vector3.UP, _visual.rotation.y) * Vector3.FORWARD


func visual_yaw() -> float:
	return _visual.rotation.y


func _process(delta: float) -> void:
	_apply_look()
	if spirit_t > 0.0:
		_aura_t -= delta
		if _aura_t <= 0.0:
			_aura_t = 0.05
			var c: Color = E.COLORS[randi() % 4]
			var off := Vector3(randf_range(-0.6, 0.6), randf_range(0, 1.8), randf_range(-0.6, 0.6))
			game.get("fx").call("puff", global_position + off, c, 0.15, 0.5, Vector3.UP * 2.0)
	_hurt_flash -= delta
	_visual.visible = not (_hurt_flash > 0.0 and int(Time.get_ticks_msec() / 60) % 2 == 0)
	if dead:
		_visual.rotation.x = lerpf(_visual.rotation.x, -PI / 2.0, 8.0 * delta)
		_visual.position.y = lerpf(_visual.position.y, 0.3, 8.0 * delta)
	else:
		_visual.rotation.x = lerpf(_visual.rotation.x, 0.0, 10.0 * delta)
		# A little walk bob from how far we moved.
		var moved := Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length() / maxf(delta, 0.001)
		if moved > 0.5 and is_on_floor_or_puppet():
			_walk_t += delta * 12.0
		_visual.position.y = absf(sin(_walk_t)) * 0.06 if moved > 0.5 else lerpf(_visual.position.y, 0.0, 10.0 * delta)
	_last_pos = global_position
	if not owned:
		global_position = global_position.lerp(_goal, 1.0 - exp(-14.0 * delta))
		_visual.rotation.y = lerp_angle(_visual.rotation.y, _goal_yaw, 12.0 * delta)


func is_on_floor_or_puppet() -> bool:
	return not owned or is_on_floor()


## Host / local: tick the knocked-down timer (puppets included).
func auth_step(delta: float) -> void:
	invuln_t -= delta
	if spirit_t > 0.0:
		spirit_t -= delta
		if spirit_t <= 0.0:
			game.call("on_spirit_faded", slot)
	if dead:
		down_t -= delta
		if down_t <= 0.0:
			dead = false
			hp = max_hp
			invuln_t = 2.0
			game.call("on_revived", slot)


func _physics_process(delta: float) -> void:
	if not owned:
		return
	# Back on our feet (host decided): pop up at the temple.
	if _was_dead and not dead:
		global_position = World.temple_spot(slot)
		velocity = Vector3.ZERO
		_visual.position = Vector3.ZERO
	_was_dead = dead
	_cd -= delta
	_aim_face_t -= delta
	if not auth:
		invuln_t -= delta
	var in_spirit := spirit_t > 0.0
	if in_spirit:
		chi = MAX_CHI
	else:
		chi = minf(MAX_CHI, chi + 15.0 * delta)
	var acting := can_act and not dead and not UiMenu.slot_busy(slot)
	if acting:
		if party.call("just_pressed", slot, "rb"):
			_switch((element + 1) % 4)
		if party.call("just_pressed", slot, "lb"):
			_switch((element + 3) % 4)
		var pads: Array[String] = ["up", "left", "down", "right"]
		for i in 4:
			if party.call("just_pressed", slot, pads[i]):
				_switch(i)
	# Movement relative to the camera.
	var mv: Vector2 = party.call("stick", slot, "move") if acting else Vector2.ZERO
	var f := forward()
	var r := Vector3(-f.z, 0.0, f.x)
	var dir := r * mv.x - f * mv.y
	var spd := 7.0
	if element == E.AIR:
		spd = 8.5
	if in_spirit:
		spd = 9.5
	var hv := Vector3(velocity.x, 0, velocity.z)
	var fx: Node = game.get("fx")
	if _dash_t > 0.0:
		_dash_t -= delta
		hv = _dash_dir * 24.0
		fx.call("puff", global_position + Vector3.UP, E.COLORS[element], 0.3, 0.3, Vector3.ZERO)
	else:
		var accel := 60.0 if is_on_floor() else 25.0
		hv = hv.move_toward(dir * spd, accel * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	var jump_now: bool = acting and _jump_pressed()
	var jump_held: bool = acting and bool(party.call("pressed", slot, "accept"))
	var grav := 24.0
	# Air benders (and the Spirit State) glide while holding jump.
	if (element == E.AIR or in_spirit) and velocity.y < 0.0 and jump_held:
		grav = 5.0
		velocity.y = maxf(velocity.y, -2.5)
		if randf() < 0.3:
			fx.call("puff", global_position, Color(1, 1, 1), 0.25, 0.3, Vector3.DOWN)
	if is_on_floor():
		_air_jumps = 1 if (element == E.AIR or in_spirit) else 0
		if jump_now:
			velocity.y = 9.5
	else:
		velocity.y -= grav * delta
		if jump_now and _air_jumps > 0:
			_air_jumps -= 1
			velocity.y = 9.0
			for i in 8:
				var v := Vector3(cos(i * TAU / 8), -0.5, sin(i * TAU / 8)) * 4.0
				fx.call("puff", global_position, Color(1, 1, 1), 0.3, 0.35, v)
			game.call("sound_at", "whoosh", global_position, -4.0, 1.4)
	if acting and party.call("just_pressed", slot, "b") and chi >= 15.0 and _dash_t <= 0.0:
		chi -= 15.0
		_dash_t = 0.18
		invuln_t = 0.3
		_dash_dir = dir.normalized() if dir.length() > 0.1 else f
		game.call("sound_at", "dash", global_position, -2.0, 1.0)
		game.call("bender_dash", slot)
	if acting and _attack_held() and _cd <= 0.0:
		_primary(in_spirit)
	if acting and (party.call("just_pressed", slot, "lt") or party.call("just_pressed", slot, "y")):
		var cost: float = E.SPECIAL_COST[element]
		if chi >= cost or in_spirit:
			if not in_spirit:
				chi -= cost
			_special()
		else:
			game.call("tv_note", slot, "Not enough chi!")
			game.call("sound_at", "ui_error", global_position, -6.0, 1.0)
	if acting and (party.call("just_pressed", slot, "l3") or party.call("just_pressed", slot, "r3")):
		game.call("bender_spirit", slot)
	move_and_slide()
	var face_dir := dir
	if _aim_face_t > 0.0:
		face_dir = f
	if face_dir.length() > 0.1 and not dead:
		_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(-face_dir.x, -face_dir.z), 12.0 * delta)
	if global_position.y < -6.0:
		global_position = World.temple_spot(slot)
		velocity = Vector3.ZERO
		game.call("bender_splash", slot)


func _jump_pressed() -> bool:
	if not bool(party.call("just_pressed", slot, "accept")):
		return false
	# Keyboard + mouse: left click is the attack, not a jump.
	return int(party.call("device_of", slot)) != -2 or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _attack_held() -> bool:
	if float(party.call("trigger", slot, "rt")) > 0.5 or bool(party.call("pressed", slot, "x")):
		return true
	return int(party.call("device_of", slot)) == -2 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _switch(e: int) -> void:
	if e == element:
		return
	element = e
	_apply_look()
	game.get("fx").call("burst", global_position + Vector3.UP, E.COLORS[e], 10, 2.0, 0.2, 0.4)
	game.call("sound_at", "ui_tick", global_position, -4.0, 1.2)
	game.call("bender_elem", slot, e)


## Aim at the raider closest to the centre of the view, so gamepad players hit things.
func _aim(from: Vector3) -> Vector3:
	var fwd := forward()
	var best: Node3D = null
	var best_score := 0.0
	for t in game.call("targets_for", 0):
		var en: Node3D = t
		var to: Vector3 = en.global_position + Vector3.UP * float(en.get("hit_height")) - from
		var d := to.length()
		if d > 35.0:
			continue
		var flat := Vector3(to.x, 0, to.z).normalized()
		var dot := flat.dot(fwd)
		if dot < 0.88:
			continue
		var score := dot * 2.0 - d / 35.0
		if best == null or score > best_score:
			best = en
			best_score = score
	if best != null:
		return (best.global_position + Vector3.UP * float(best.get("hit_height")) - from).normalized()
	var pitch := cam.pitch if cam != null else -0.25
	var up := clampf((pitch + 0.25) * 0.8, -0.2, 0.6)
	return (fwd + Vector3.UP * up).normalized()


func _primary(in_spirit: bool) -> void:
	_aim_face_t = 0.5
	attacks += 1
	_hand = 1 - _hand
	var f := forward()
	var side := Vector3(-f.z, 0.0, f.x) * ((_hand - 0.5) * 0.7)
	var from := global_position + Vector3.UP * 1.2 + f * 0.6 + side
	var aim := _aim(from)
	var shots: Array
	if in_spirit:
		_cd = 0.22
		shots = E.spirit_shots(from, aim, global_position, f)
		game.call("sound_at", "magic", from, -6.0, 1.6)
	else:
		_cd = E.ATTACK_CD[element]
		shots = E.primary_shots(element, from, aim, global_position, f)
		game.call("sound_at", E.SOUNDS[element], from, -4.0, 1.0)
		if element == E.EARTH and cam != null:
			cam.shake(0.25)
	party.call("rumble", slot, 0.15, 0.0, 0.05)
	game.call("bender_fire", slot, shots)


func _special() -> void:
	_aim_face_t = 0.4
	specials += 1
	match element:
		E.AIR:
			velocity.y = 13.0
			_air_jumps = 1
		E.EARTH:
			if cam != null:
				cam.shake(0.8)
	party.call("rumble", slot, 0.4, 0.4, 0.2)
	game.call("bender_special", slot, element, global_position)


## Host / local: something hurt this bender. Returns the damage taken.
func take_hit(dmg: float, push: Vector3) -> float:
	if dead or invuln_t > 0.0:
		return 0.0
	if spirit_t > 0.0:
		dmg *= 0.3
	if element == E.EARTH:
		push *= 0.4
	hp -= dmg
	invuln_t = 0.5
	if hp <= 0.0:
		hp = 0.0
		dead = true
		down_t = DOWN_TIME
		spirit_t = 0.0
	if owned:
		feel_hit(push)
	return dmg


## The owning machine: knockback, blink and rumble (the host sends "hurt" to the TV machine).
func feel_hit(push: Vector3) -> void:
	velocity += push
	velocity.y = maxf(velocity.y, 3.0)
	_hurt_flash = 0.5
	if not auth:
		invuln_t = 0.5
	if cam != null:
		cam.shake(0.35)
	party.call("rumble", slot, 0.5, 0.5, 0.2)
