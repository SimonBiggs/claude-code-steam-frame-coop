extends Node3D
## A sea monster tentacle. It rises beside the hull, sways while winding up, then slams the deck
## (punching a leak) and does it again until it's shot away by a cannon or the deckhands' muskets.

const World := preload("res://games/cannon_cove/world.gd")

const SEGMENTS := 8
const RISE := 1.6
const WINDUP := 4.0
const SLAM := 0.45
const HOLD := 1.2
const RETREAT := 1.0

var main
var net_id := 0
var ghost := false
var hp := 5.0
var max_hp := 5.0
var side := 1.0  # +1: starboard (+X), -1: port
var state := "rise"
var state_t := 0.0
var rise := 0.0  # 0..1 out of the water
var slam_k := 0.0  # 0 upright, 1 slammed onto the deck
var sway := 0.0
var dying := 0.0
var deck_target := Vector3.ZERO
var segs: Array[MeshInstance3D] = []
var skin: StandardMaterial3D
var flash := 0.0
var warn: Label3D


func _ready() -> void:
	add_to_group("tentacles")
	skin = World.mat(Color(0.55, 0.25, 0.75), 0.0, 0.5)
	skin.emission_enabled = true
	skin.emission = Color(1.0, 0.6, 1.0)
	skin.emission_energy_multiplier = 0.0
	var sucker := World.mat(Color(1.0, 0.7, 0.8))
	for i in SEGMENTS:
		var r := lerpf(0.6, 0.18, float(i) / (SEGMENTS - 1))
		var s := World.sphere(self, r, Vector3.ZERO, skin, 12)
		s.top_level = true
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		segs.append(s)
		if i % 2 == 1:
			var su := World.sphere(s, r * 0.35, Vector3(-side * r * 0.85, 0, 0), sucker, 6)
			su.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Two googly eyes on the base, to keep it friendly.
	for ez in [-0.25, 0.25]:
		var eye := World.sphere(segs[0], 0.18, Vector3(-side * 0.45, 0.25, ez), World.mat(Color.WHITE), 8)
		World.sphere(eye, 0.09, Vector3(-side * 0.12, 0, 0), World.mat(Color.BLACK), 6)
	warn = Label3D.new()
	warn.text = "!"
	warn.font_size = 160
	warn.outline_size = 30
	warn.pixel_size = 0.01
	warn.modulate = Color(1.0, 0.3, 0.3)
	warn.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	warn.no_depth_test = false
	warn.top_level = true
	add_child(warn)
	if deck_target == Vector3.ZERO:
		_pick_target()
	_update_pose()


func _pick_target() -> void:
	deck_target = Vector3(side * randf_range(1.4, 2.6), 0.0, clampf(position.z + randf_range(-1.5, 1.5), -9.5, 8.5))


func _physics_process(delta: float) -> void:
	flash = maxf(0.0, flash - delta * 4.0)
	skin.emission_energy_multiplier = flash * 1.5
	if not ghost:
		_think(delta)
	_update_pose()


func _think(delta: float) -> void:
	state_t += delta
	if dying > 0.0:
		dying += delta
		if dying > 1.6:
			queue_free()
		return
	match state:
		"rise":
			rise = minf(1.0, state_t / RISE)
			slam_k = 0.0
			if state_t >= RISE:
				_set_state("windup")
		"windup":
			sway = minf(state_t, WINDUP - 0.001)
			if state_t >= WINDUP:
				_set_state("slam")
				sway = WINDUP
				main.sound("tentacle", -2.0, 1.2)
		"slam":
			slam_k = minf(1.0, state_t / SLAM)
			if state_t >= SLAM:
				_set_state("hold")
				main.on_tentacle_slam(self, deck_target)
		"hold":
			slam_k = 1.0
			if state_t >= HOLD:
				_set_state("retreat")
		"retreat":
			slam_k = maxf(0.0, 1.0 - state_t / RETREAT)
			if state_t >= RETREAT:
				_pick_target()
				_set_state("windup")


func _set_state(s: String) -> void:
	state = s
	state_t = 0.0


## Bezier from the base in the sea to the tip: upright and swaying, or slammed onto the deck.
func _update_pose() -> void:
	var sea: float = main.sea_level
	var base := Vector3(position.x, sea - 0.4, position.z)
	var sink := 0.0
	if dying > 0.0:
		sink = dying * 4.0
	var h := 6.5 * rise - sink
	var sw := sin(sway * (2.0 + sway * 0.35)) * 0.9 * minf(1.0, sway)
	var up_tip := base + Vector3(-side * 1.2 + sw * 0.3, h, sw)
	var up_ctrl := base + Vector3(side * 0.4, h * 0.55, -sw * 0.5)
	var slam_tip := deck_target + Vector3(0, 0.35, 0)
	var slam_ctrl := Vector3(side * (World.HULL_HALF_W + 0.3), 4.5, (base.z + deck_target.z) * 0.5)
	var e := slam_k * slam_k * (3.0 - 2.0 * slam_k)
	var tip := up_tip.lerp(slam_tip, e)
	var ctrl := up_ctrl.lerp(slam_ctrl, e)
	for i in SEGMENTS:
		var t := float(i) / (SEGMENTS - 1)
		var a := base.lerp(ctrl, t)
		var b := ctrl.lerp(tip, t)
		segs[i].global_position = a.lerp(b, t)
		segs[i].visible = rise > 0.02
	var warning := rise >= 1.0 and slam_k < 0.05 and sway > WINDUP - 1.6 and sway < WINDUP and dying <= 0.0
	warn.visible = warning
	warn.global_position = segs[SEGMENTS - 1].global_position + Vector3.UP * 1.2


## Host: closest distance from p to the tentacle (for cannonballs and musket shots).
func distance_to_point(p: Vector3) -> float:
	var best := INF
	for s in segs:
		best = minf(best, s.global_position.distance_to(p))
	return best


func ray_hit(from: Vector3, dir: Vector3, max_d: float) -> float:
	var best := INF
	for i in SEGMENTS:
		var c: Vector3 = segs[i].global_position
		var t := (c - from).dot(dir)
		if t < 0.0 or t > max_d:
			continue
		var r := lerpf(0.6, 0.18, float(i) / (SEGMENTS - 1)) + 0.35
		if (from + dir * t).distance_to(c) < r:
			best = minf(best, t)
	return best


func hit(damage: float) -> void:
	if dying > 0.0:
		return
	hp -= damage
	flash = 1.0
	if hp <= 0.0:
		dying = 0.01
		main.on_tentacle_killed(self)


func alive() -> bool:
	return dying <= 0.0


## Snapshot: [id, pos, rise, slam_k, sway, dying, side, deck_target, hp]
func net_state() -> Array:
	return [net_id, position, rise, slam_k, sway, dying, side, deck_target, hp]


func apply_net(item: Array) -> void:
	position = item[1]
	rise = item[2]
	slam_k = lerpf(slam_k, item[3], 0.7)
	sway = item[4]
	var d: float = item[5]
	if d > 0.0 and dying <= 0.0:
		flash = 1.0
	dying = d
	deck_target = item[7]
	var new_hp: float = item[8]
	if new_hp < hp:
		flash = 1.0
	hp = new_hp
