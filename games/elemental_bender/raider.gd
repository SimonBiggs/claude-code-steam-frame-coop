extends CharacterBody3D
## ELEMENTAL BENDER: a Shadow Raider, a masked bender whose glowing head orb shows its element.
## Host / local: simulated (chases the nearest bender, melee or ranged shots, knockback, slow /
## stun / freeze, falls off the island = "Ring out!"). Bosses are twice the size: the Shadow General swaps
## element every 5 seconds; the island bosses (bosses.gd: Frost Giant, Lava Drake, Storm Hawk) TELL every attack
## (they stop, glow and a ring shows on the ground: main.boss_warn) and then STOMP / breathe a FAN / DIVE; at half
## health they power up (main.on_boss_phase2). `gentle`: the kind numbers (longer tells, softer hits).
## TV machine: `ghost = true`, a visual copy driven by the host's snapshots (apply_remote).
## Numbers are the source game's.

const E := preload("res://games/elemental_bender/elem.gd")
const Looks := preload("res://games/elemental_bender/looks.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const Bosses := preload("res://games/elemental_bender/bosses.gd")

var game: Node
var ghost := false
var id := 0
var element := E.FIRE
var hp := 30.0
var max_hp := 30.0
var speed := 3.4
var ranged := false
var boss := false
var damage := 10.0
var hit_radius := 0.6
var hit_height := 1.0
var dead := false
var frozen := false
var flash_t := 0.0
var last_hit_slot := -1
## The General's seeded element order (wavegen.gd boss_order; [] = random swaps).
var swap_order: Array = []
var _swap_i := 0
## Island bosses (bosses.gd).
var boss_kind := "general"
var gentle := false
var phase2 := false
var telling := 0.0  ## seconds of warning glow left before the attack
var _atk_t := 0.8  # (a boss shows its first warning glow soon after it arrives)
var _dive_t := 0.0
var _dive_dir := Vector3.ZERO
var _dive_hit := {}
var _dives_left := 0
var _tell_at := Vector3.ZERO

var _knock := Vector3.ZERO
var _slow_t := 0.0
var _stun_t := 0.0
var _attack_cd := 1.5
var _swap_t := 5.0
var _strafe := 1.0
var _visual: Node3D
var _body: MeshInstance3D
var _orb: MeshInstance3D
var _ice: MeshInstance3D
var _bar: HudKit.Bar3D
var _stuck_t := 0.0
var _side_t := 0.0
var _side := Vector3.ZERO
var _target: Node3D
var _retarget_t := 0.0
var _t := 0.0
var _goal := Vector3.ZERO
var _goal_yaw := 0.0
var _shown_element := -1


func _ready() -> void:
	add_to_group("eb_enemy")
	var s := 2.0 if boss else 1.0
	hit_radius *= s
	hit_height *= s
	if not ghost:
		collision_layer = 4
		collision_mask = 1 | 4
		var col := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.4 * s
		cap.height = 1.8 * s
		col.shape = cap
		col.position.y = 0.9 * s
		add_child(col)
	else:
		collision_layer = 0
		collision_mask = 0
	_visual = Node3D.new()
	_visual.scale = Vector3.ONE * s
	add_child(_visual)
	_body = MeshKit.instance(Looks.boss(boss_kind) if special_boss() else Looks.raider(element, boss), false)
	_visual.add_child(_body)
	_orb = MeshKit.instance(Looks.orb(0.13), false)
	_orb.position = Vector3(0, 2.15, 0)
	_visual.add_child(_orb)
	_bar = HudKit.bar3d(self, {"max": 1.0, "hide_full": true, "width": 1.6 if boss else 0.9,
		"offset": Vector3(0, 2.6 * s, 0), "name": String(Bosses.info(boss_kind).name) if boss else ""})
	_attack_cd = randf_range(1.0, 2.5)
	_strafe = 1.0 if randf() < 0.5 else -1.0
	_goal = position
	_set_element(element)


func _set_element(e: int) -> void:
	element = e
	if _shown_element == e:
		return
	_shown_element = e
	if not special_boss():
		_body.mesh = Looks.raider(e, boss)
	_orb.material_override = E.mat(E.COLORS[e], 5.0)


## An island boss (not the classic General): tells, stomps, fans, dives.
func special_boss() -> bool:
	return boss and boss_kind != "general"


func _process(delta: float) -> void:
	_t += delta
	flash_t -= delta
	var glow := telling > 0.0 and fmod(_t, 0.24) < 0.12
	_body.material_overlay = Looks.flash_material() if flash_t > 0.0 or glow else null
	if special_boss():
		var lift := 0.0
		if boss_kind == "hawk":
			lift = 0.5 + sin(_t * 2.5) * 0.15 + (0.8 if telling > 0.0 else 0.0)
		_visual.position.y = lerpf(_visual.position.y, lift, 1.0 - exp(-6.0 * delta))
		if telling > 0.0 and boss_kind == "giant":
			_visual.scale = Vector3.ONE * 2.0 * (1.0 + 0.06 * absf(sin(_t * 9.0)))
		elif phase2:
			_visual.scale = Vector3.ONE * 2.15
		else:
			_visual.scale = Vector3.ONE * 2.0
		if ghost:
			telling = maxf(0.0, telling - delta)
	_orb.position.y = 2.15 + sin(_t * 4.0) * 0.08
	if ghost:
		global_position = global_position.lerp(_goal, 1.0 - exp(-14.0 * delta))
		_visual.rotation.y = lerp_angle(_visual.rotation.y, _goal_yaw, 10.0 * delta)


## TV machine: the host's latest state for this raider.
func apply_remote(pos: Vector3, yaw: float, e: int, flags: int, hp_frac: float) -> void:
	_goal = pos
	_goal_yaw = yaw
	if e != element:
		_set_element(e)
	if flags & 4 != 0:
		flash_t = 0.1
	if flags & 8 != 0:
		telling = maxf(telling, 0.2)
	phase2 = flags & 16 != 0
	_set_frozen(flags & 2 != 0)
	_bar.set_value(hp_frac)


func pack_flags() -> int:
	return (1 if boss else 0) | (2 if frozen else 0) | (4 if flash_t > 0.0 else 0) | (8 if telling > 0.0 else 0) \
		| (16 if phase2 else 0) | (Bosses.index_of(boss_kind) << 5 if boss else 0)


## A ghost's boss kind from the snapshot flags (bits 5-6).
static func kind_from_flags(flags: int) -> String:
	return Bosses.KINDS[clampi((flags >> 5) & 3, 0, Bosses.KINDS.size() - 1)]


func visual_yaw() -> float:
	return _visual.rotation.y


func _set_frozen(on: bool) -> void:
	if on == frozen:
		return
	frozen = on
	if on:
		_ice = MeshKit.instance(Looks.ice(), false)
		_visual.add_child(_ice)
	elif _ice != null:
		_ice.queue_free()
		_ice = null


func _physics_process(delta: float) -> void:
	if ghost or dead:
		return
	_slow_t -= delta
	_stun_t -= delta
	if frozen and _stun_t <= 0.0:
		_set_frozen(false)
	if special_boss():
		_boss_step(delta)
	elif boss:
		_swap_t -= delta
		if _swap_t <= 0.0:
			_swap_t = 5.0
			_swap_i += 1
			if not swap_order.is_empty():
				var nx := int(swap_order[_swap_i % swap_order.size()])
				_set_element(nx if nx != element else (element + 1) % 4)  # (wrapping round the list)
			else:
				_set_element((element + 1 + randi() % 3) % 4)
			game.call("on_boss_swap", self)
	_retarget_t -= delta
	if _retarget_t <= 0.0 or _target == null or not is_instance_valid(_target) or bool(_target.get("dead")):
		_retarget_t = 0.5
		_target = game.call("nearest_fighter", global_position)
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	var want := Vector3.ZERO
	var dir := Vector3.FORWARD
	var dist := 99.0
	if _target != null:
		var to_p: Vector3 = _target.global_position - global_position
		to_p.y = 0.0
		dist = to_p.length()
		dir = to_p / maxf(dist, 0.01)
	var busy := telling > 0.0 or _dive_t > 0.0
	if _stun_t <= 0.0 and _target != null and not busy:
		if ranged and not special_boss():
			if dist > 13.0:
				want = dir
			elif dist < 7.0:
				want = -dir
			else:
				want = dir.cross(Vector3.UP) * _strafe * 0.6
		elif dist > 1.5:
			want = dir
		_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(-dir.x, -dir.z), 8.0 * delta)
		_attack_cd -= delta
		if _attack_cd <= 0.0:
			if ranged and dist < 22.0:
				_shoot()
				_attack_cd = randf_range(1.8, 3.0) * (0.6 if boss else 1.0)
				if randf() < 0.3:
					_strafe = -_strafe
			elif dist < 2.0 + (1.0 if boss else 0.0):
				game.call("raider_melee", self, _target, damage, dir * 9.0)
				_attack_cd = 1.3 if not boss else 1.0
				_visual.position = dir * 0.4
				create_tween().tween_property(_visual, "position", Vector3.ZERO, 0.25)
	var spd := speed * (0.4 if _slow_t > 0.0 else 1.0)
	if _dive_t > 0.0:
		want = _dive_dir
		spd = 22.0
	_side_t -= delta
	if _side_t > 0.0 and want.length() > 0.1:
		want = (want + _side * 1.3).normalized()
	var before := global_position
	velocity.x = want.x * spd + _knock.x
	velocity.z = want.z * spd + _knock.z
	if _knock.y > 0.0:
		velocity.y = _knock.y
		_knock.y = 0.0
	_knock = _knock.lerp(Vector3.ZERO, 1.0 - exp(-4.0 * delta))
	move_and_slide()
	# Blocked by a tree or a step: hop and sidestep around it.
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if want.length() > 0.1 and moved < spd * delta * 0.3:
		_stuck_t += delta
		if _stuck_t > 0.3:
			_stuck_t = 0.0
			if is_on_floor():
				velocity.y = 8.0
			_side = want.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
			_side_t = 0.9
	else:
		_stuck_t = 0.0
	if global_position.y < -4.0:
		die(true)


## Host / local: an island boss's attack clock: tell (stop, glow, a warning ring), then the attack.
func _boss_step(delta: float) -> void:
	var nums := Bosses.numbers(boss_kind, gentle, phase2)
	if not phase2 and hp < max_hp * Bosses.PHASE2_AT:
		phase2 = true
		game.call("on_boss_phase2", self)
	if _dive_t > 0.0:
		_dive_t -= delta
		for f in game.call("fighters", true):
			var n: Node3D = f
			if not _dive_hit.has(n) and n.global_position.distance_to(global_position) < float(nums.radius) + 0.6:
				_dive_hit[n] = true
				game.call("boss_hit", self, n, float(nums.damage), _dive_dir * 10.0 + Vector3.UP * 4.0)
		if _dive_t <= 0.0 and _dives_left > 0:
			_dives_left -= 1
			_begin_tell(nums)
		return
	if telling > 0.0:
		telling -= delta
		if telling <= 0.0:
			_attack(nums)
		return
	if _stun_t > 0.0 or _target == null:
		return
	_atk_t -= delta
	if _atk_t <= 0.0:
		_atk_t = float(nums.every)
		_dives_left = int(nums.dives_now) - 1
		_begin_tell(nums)


func _begin_tell(nums: Dictionary) -> void:
	telling = float(nums.tell)
	var col: Color = nums.color
	match boss_kind:
		"giant":
			_tell_at = global_position
			game.call("boss_warn", self, _tell_at, float(nums.radius), col, telling)
		"drake":
			_tell_at = _target.global_position if _target != null and is_instance_valid(_target) else global_position
			game.call("boss_warn", self, global_position, 2.5, col, telling)
		"hawk":
			var to: Vector3 = (_target.global_position if _target != null and is_instance_valid(_target) else Vector3.ZERO) - global_position
			to.y = 0.0
			_dive_dir = to.normalized() if to.length() > 0.5 else -global_position.normalized()
			var len := float(nums.get("dive_len", 16.0))
			for k in 4:
				var p := global_position + _dive_dir * (len * (k + 1) / 4.0)
				game.call("boss_warn", self, Vector3(p.x, 0.0, p.z), float(nums.radius), col, telling)
	_visual.rotation.y = atan2(-(_tell_at - global_position).x, -(_tell_at - global_position).z) if boss_kind == "drake" else _visual.rotation.y


func _attack(nums: Dictionary) -> void:
	match boss_kind:
		"giant":
			game.call("boss_stomp", self, global_position, float(nums.radius), float(nums.damage))
			if int(nums.shards_now) > 0 and _target != null and is_instance_valid(_target):
				_fan(int(nums.shards_now), 0.3, float(nums.damage) * 0.5, _target.global_position)
		"drake":
			_fan(int(nums.shots_now), 0.22, float(nums.damage), _tell_at)
		"hawk":
			_dive_hit = {}
			_dive_t = float(nums.get("dive_len", 16.0)) / 22.0
			_visual.rotation.y = atan2(-_dive_dir.x, -_dive_dir.z)
			game.call("sound_all", "whoosh", global_position, 0.0, 0.7)


func _fan(count: int, spread: float, dmg: float, at: Vector3) -> void:
	var from := global_position + Vector3.UP * hit_height * 1.2
	var target := at + Vector3.UP * 1.0
	var out: Array = []
	for i in count:
		var d := (target - from).normalized().rotated(Vector3.UP, (i - (count - 1) / 2.0) * spread)
		out.append({"element": element, "team": 1, "pos": from, "vel": d * 13.0,
			"damage": dmg, "knockback": 6.0, "radius": 0.6, "life": 2.6})
	game.call("fire_shots", out, -1)


func _shoot() -> void:
	var from := global_position + Vector3.UP * hit_height * 1.3
	var target: Vector3 = _target.global_position + Vector3.UP * float(_target.get("hit_height"))
	var shots := 3 if boss else 1
	var out: Array = []
	for i in shots:
		var d := (target - from).normalized().rotated(Vector3.UP, (i - (shots - 1) / 2.0) * 0.25)
		out.append({"element": element, "team": 1, "pos": from, "vel": d * 15.0,
			"damage": damage * 0.8, "knockback": 5.0, "radius": 0.45 * (1.5 if boss else 1.0), "life": 2.5})
	game.call("fire_shots", out, -1)


## Host / local: a bending hit. Returns the damage dealt (after the element multiplier).
func take_hit(dmg: float, elem: int, push: Vector3, effect: String, slot: int) -> float:
	if dead:
		return 0.0
	var mult: float = E.multiplier(elem, element)
	var amount := dmg * mult
	hp -= amount
	flash_t = 0.1
	last_hit_slot = slot
	var weight := 0.25 if boss else 1.0
	_knock += push * weight
	_knock.y = push.length() * 0.35 * weight
	_bar.set_value(maxf(hp / max_hp, 0.0))
	match effect:
		"slow":
			_slow_t = 2.0
		"stun":
			_stun_t = maxf(_stun_t, 0.6 if not boss else 0.2)
		"freeze":
			_stun_t = 2.5 if not boss else 0.8
			_set_frozen(true)
	game.call("on_raider_hit", self, amount, mult, slot)
	if hp <= 0.0:
		die(false)
	return amount


func die(ring_out: bool) -> void:
	if dead:
		return
	dead = true
	game.call("on_raider_died", self, ring_out)
	queue_free()
