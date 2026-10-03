extends Node3D
## A cheeky pirate who swings aboard on a rope. He pinches cannonballs from the cannons or chops
## holes in the deck until a deckhand's musket knocks him overboard (splash!).

const World := preload("res://games/cannon_cove/world.gd")

const SPEED := 2.3
const STEAL_EVERY := 2.6
const HACK_TIME := 3.5

var main
var net_id := 0
var ghost := false
var hp := 2.0
var state := "swing"  # swing, walk, steal, hack, fall
var state_t := 0.0
var yaw := 0.0
var swing_from := Vector3.ZERO
var swing_to := Vector3.ZERO
var target_cannon = null
var target_pos := Vector3.ZERO
var act_t := 0.0
var walk_t := 0.0
var flash := 0.0
var fall_dir := Vector3.ZERO
var body: Node3D
var shirt: StandardMaterial3D
var sword: Node3D
var legs: Array[Node3D] = []
var eye: MeshInstance3D
var blink_t := 1.0
var look := 0
var net_target := Vector3.ZERO
var net_started := false


func _ready() -> void:
	add_to_group("boarders")
	body = Node3D.new()
	add_child(body)
	shirt = World.mat(Color(0.9, 0.15, 0.15))
	shirt.emission_enabled = true
	shirt.emission = Color.WHITE
	shirt.emission_energy_multiplier = 0.0
	var skin := World.mat(Color(1.0, 0.78, 0.6))
	var white := World.mat(Color(0.97, 0.97, 0.97))
	var dark := World.mat(Color(0.15, 0.12, 0.2))
	var torso := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.1
	cap.radial_segments = 10
	cap.rings = 3
	torso.mesh = cap
	torso.material_override = shirt
	torso.position.y = 0.75
	body.add_child(torso)
	World.box(body, Vector3(0.62, 0.1, 0.62), Vector3(0, 0.95, 0), white)
	World.box(body, Vector3(0.62, 0.1, 0.62), Vector3(0, 0.7, 0), white)
	World.box(body, Vector3(0.5, 0.2, 0.4), Vector3(0, 0.42, 0), dark)
	# Legs that stride (one is a wooden peg leg, of course).
	for sx in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(sx * 0.13, 0.42, 0)
		body.add_child(leg)
		if sx < 0.0:
			World.box(leg, Vector3(0.15, 0.4, 0.16), Vector3(0, -0.2, 0), dark)
			World.box(leg, Vector3(0.17, 0.09, 0.24), Vector3(0, -0.38, -0.04), World.mat(Color(0.1, 0.08, 0.06)))
		else:
			World.cyl(leg, 0.05, 0.035, 0.42, Vector3(0, -0.21, 0), World.mat(Color(0.6, 0.42, 0.22)), 6)
		legs.append(leg)
	World.sphere(body, 0.25, Vector3(0, 1.5, 0), skin, 10)
	look = randi() % 3
	match look:
		0:
			var bandana := World.sphere(body, 0.26, Vector3(0, 1.58, 0), World.mat(Color(0.2, 0.3, 0.9)), 10)
			bandana.scale = Vector3(1.0, 0.6, 1.0)
		1:
			var hat_mat := World.mat(Color(0.1, 0.08, 0.1))
			World.cyl(body, 0.36, 0.36, 0.05, Vector3(0, 1.68, 0), hat_mat, 3)
			World.cyl(body, 0.15, 0.2, 0.2, Vector3(0, 1.8, 0), hat_mat, 8)
			World.sphere(body, 0.06, Vector3(0, 1.82, -0.18), white, 6)  # a little skull badge
		_:
			World.sphere(body, 0.05, Vector3(0.24, 1.45, 0), World.mat(Color(1.0, 0.8, 0.2), 0.8), 6)  # gold earring
			var beard := World.sphere(body, 0.2, Vector3(0, 1.36, -0.12), World.mat(Color(0.3, 0.15, 0.08)), 8)
			beard.scale = Vector3(1.0, 0.8, 0.7)
	eye = World.sphere(body, 0.05, Vector3(0.1, 1.53, -0.22), dark, 6)
	World.box(body, Vector3(0.14, 0.12, 0.04), Vector3(-0.1, 1.53, -0.23), dark)  # eye patch
	World.box(body, Vector3(0.02, 0.02, 0.5), Vector3(-0.1, 1.6, 0.0), dark, Vector3(0.0, 0.0, 0.5))  # patch strap
	World.sphere(body, 0.035, Vector3(0, 1.45, -0.25), World.mat(Color(1.0, 0.55, 0.5)), 6)
	sword = Node3D.new()
	sword.position = Vector3(0.38, 0.95, -0.1)
	body.add_child(sword)
	World.box(sword, Vector3(0.06, 0.06, 0.7), Vector3(0, 0, -0.35), World.mat(Color(0.85, 0.88, 0.95), 0.2, 0.2))
	World.box(sword, Vector3(0.2, 0.06, 0.06), Vector3(0, 0, 0), World.mat(Color(1.0, 0.78, 0.2)))
	for c in body.get_children():
		if c is GeometryInstance3D:
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not ghost:
		position = swing_from


func _physics_process(delta: float) -> void:
	flash = maxf(0.0, flash - delta * 5.0)
	shirt.emission_energy_multiplier = flash * 2.0
	if ghost:
		if not net_started:
			net_started = true
			position = net_target
		position = position.lerp(net_target, 1.0 - exp(-14.0 * delta))
		_animate(delta)
		return
	state_t += delta
	match state:
		"swing":
			var k := minf(1.0, state_t / 1.1)
			position = swing_from.lerp(swing_to, k) + Vector3.UP * sin(k * PI) * 2.0
			if k >= 1.0:
				_retarget()
		"walk":
			var to := target_pos - position
			to.y = 0.0
			if to.length() < 0.35:
				state = "steal" if target_cannon != null else "hack"
				state_t = 0.0
				act_t = 0.0
			else:
				var step := to.normalized() * SPEED * delta
				yaw = atan2(-to.x, -to.z)
				position = World.constrain(position + step, 0.35, main.cannon_obstacles())
				if state_t > 9.0:
					_retarget()  # stuck: try something else
		"steal":
			act_t += delta
			if target_cannon == null or not is_instance_valid(target_cannon) or target_cannon.ammo <= 0:
				_retarget()
			elif act_t >= STEAL_EVERY:
				act_t = 0.0
				main.boarder_stole(self, target_cannon)
		"hack":
			act_t += delta
			if act_t >= HACK_TIME:
				main.boarder_hacked(self, position + Basis(Vector3.UP, yaw) * Vector3(0, 0, -0.6))
				_retarget()
		"fall":
			position += fall_dir * 4.0 * delta + Vector3.UP * (3.0 - state_t * 9.0) * delta
			if state_t > 1.4:
				queue_free()
	_animate(delta)


func _animate(delta: float) -> void:
	walk_t += delta
	body.rotation.y = lerp_angle(body.rotation.y, yaw, 1.0 - exp(-10.0 * delta))
	blink_t -= delta
	if blink_t < -0.12:
		blink_t = randf_range(1.5, 3.5)
	eye.scale = Vector3(1.0, 0.2 if blink_t < 0.0 else 1.0, 1.0)
	var stride := sin(walk_t * 9.0) * 0.6 if state == "walk" else 0.0
	if legs.size() == 2:
		legs[0].rotation.x = stride
		legs[1].rotation.x = -stride
	match state:
		"walk", "swing":
			body.position.y = absf(sin(walk_t * 9.0)) * 0.08
			sword.rotation.x = sin(walk_t * 9.0) * 0.3
			body.rotation.x = 0.0
		"steal", "hack":
			body.position.y = 0.0
			sword.rotation.x = -absf(sin(walk_t * 7.0)) * 1.4
		"fall":
			body.rotation.x += delta * 10.0


## Pick the nearest cannon that still has balls to pinch; if none, chop a hole somewhere.
func _retarget() -> void:
	walk_t = 0.0
	state = "walk"
	state_t = 0.0
	target_cannon = null
	var best := INF
	for c in main.cannons:
		if c.ammo <= 0:
			continue
		var p: Vector3 = c.global_position - c.outboard * 1.1
		var d := position.distance_to(Vector3(p.x, 0, p.z))
		if d < best:
			best = d
			target_cannon = c
	if target_cannon != null and randf() < 0.75:
		var p: Vector3 = target_cannon.global_position - target_cannon.outboard * 1.15
		target_pos = Vector3(p.x, 0.0, p.z)
	else:
		target_cannon = null
		target_pos = World.random_deck_point()


func ray_hit(from: Vector3, dir: Vector3, max_d: float) -> float:
	if state == "fall":
		return INF
	var c := global_position + Vector3.UP * 1.0
	var t := (c - from).dot(dir)
	if t < 0.0 or t > max_d:
		return INF
	return t if (from + dir * t).distance_to(c) < 0.75 else INF


func alive() -> bool:
	return state != "fall"


func hit(damage: float) -> bool:
	if state == "fall":
		return false
	hp -= damage
	flash = 1.0
	if hp <= 0.0:
		state = "fall"
		state_t = 0.0
		var out := Vector3(signf(position.x) if absf(position.x) > 0.1 else 1.0, 0.0, 0.0)
		fall_dir = out
		yaw = atan2(out.x, out.z)
		return true
	return false


## Snapshot: [id, pos, yaw, state]
func net_state() -> Array:
	return [net_id, global_position, yaw, state]


func apply_net(item: Array) -> void:
	net_target = item[1]
	yaw = item[2]
	var s: String = item[3]
	if s != state and s == "fall":
		flash = 1.0
	state = s
