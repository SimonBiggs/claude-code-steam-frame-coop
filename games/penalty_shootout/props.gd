extends Node3D
## Simple mode: everything the keeper can reach does something (Simon's rule).
##  - GOAL POSTS and CROSSBAR: touch them - CLANG, a spark, a buzz in the hand.
##  - the NET: push a glove into it - it ripples and swishes.
##  - three SPARE BALLS on a crate by the right post: tap them with a glove to bat them away, or squeeze
##    the right trigger near one to pick it up and throw it (back to the strikers gets a cheer). They
##    pop back onto the crate a little later.
##  - a WATER BOTTLE on the kit bag by the left post: touch it - it wobbles and squirts; pick it up
##    (right trigger) and lift it to your mouth - GLUG GLUG. Let go: it floats back to the bag.
##  - a CORNER FLAG beside the crate: touch it - it swings and flaps.
##  - LEO the lion mascot by the left post: touch him for a high five - he dances and the crowd cheers.
## The host (or local game) checks the keeper's gloves; the TV gets each touch as a "prop" event and the
## loose balls / bottle in the snapshot. Cheap: one merged mesh per prop, no physics engine.

const MeshKit := preload("res://games/penalty_shootout/mesh_kit.gd")
const R := 0.11
const G := Vector3(0, -9.8, 0)
const CRATE := Vector3(4.45, 0.0, 1.1)
const BAG := Vector3(-4.45, 0.0, 1.0)
const FLAG := Vector3(4.75, 0.0, 2.1)
const MASCOT := Vector3(-5.0, 0.0, 1.9)
const BALL_HOME: Array[Vector3] = [Vector3(4.33, 0.81, 0.95), Vector3(4.57, 0.81, 1.05), Vector3(4.42, 0.81, 1.28)]
const BOTTLE_HOME := Vector3(-4.4, 0.83, 0.9)
const TOUCH_R := 0.13
const GRAB_R := 0.2

var main
var balls: Array = []  # Dictionaries: node, pos, vel, home, away_t, rest_t, cheered
var bottle: Node3D
var bottle_pos := BOTTLE_HOME
var bottle_wob := Vector2.ZERO
var bottle_wob_v := Vector2.ZERO
var bottle_back := false
var flag: Node3D
var flag_cloth: Node3D
var flag_ang := Vector2.ZERO
var flag_vel := Vector2.ZERO
var held := -1  # 0-2 a ball, 3 the bottle (in the right glove)
var grab_was := false
var prev_tips: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var tip_vel: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var hand_vel := Vector3.ZERO
var cool := {}  # touch key -> seconds until it can fire again
var drink_cd := 0.0
var touched := {}  # kind -> count (the bot reads it)
var bot_grab := false  # bot: squeeze the right trigger
var t := 0.0


func build() -> void:
	var vm: StandardMaterial3D = MeshKit.vertex_material(main.mats)
	# Ball crate and kit bag (static, one mesh).
	var stat := MeshInstance3D.new()
	stat.mesh = MeshKit.merge([
		[MeshKit.box(Vector3(0.6, 0.7, 0.7)), MeshKit.at(CRATE + Vector3(0, 0.35, 0)), Color(0.55, 0.35, 0.18)],
		[MeshKit.box(Vector3(0.62, 0.06, 0.72)), MeshKit.at(CRATE + Vector3(0, 0.55, 0)), Color(0.4, 0.24, 0.1)],
		[MeshKit.box(Vector3(0.5, 0.7, 0.55)), MeshKit.at(BAG + Vector3(0, 0.35, 0)), Color(0.15, 0.3, 0.85)],
		[MeshKit.box(Vector3(0.52, 0.08, 0.57)), MeshKit.at(BAG + Vector3(0, 0.5, 0)), Color(1, 1, 1)],
	])
	stat.material_override = vm
	add_child(stat)
	var ball_mesh := MeshKit.merge([
		[MeshKit.sphere(R, 12), MeshKit.at(Vector3.ZERO), Color(1, 1, 1)],
		[MeshKit.sphere(0.04, 6), MeshKit.at(Vector3(0, 0, R * 0.9), Vector3(1, 1, 0.4)), Color(0.1, 0.1, 0.12)],
		[MeshKit.sphere(0.035, 6), MeshKit.at(Vector3(R * 0.85, 0.03, 0), Vector3(0.4, 1, 1)), Color(0.1, 0.1, 0.12)],
		[MeshKit.sphere(0.035, 6), MeshKit.at(Vector3(-0.03, R * 0.85, -0.02), Vector3(1, 0.4, 1)), Color(0.1, 0.1, 0.12)],
	])
	for h in BALL_HOME:
		var n := MeshInstance3D.new()
		n.mesh = ball_mesh
		n.material_override = vm
		add_child(n)
		n.position = h
		balls.append({"node": n, "pos": h, "vel": Vector3.ZERO, "home": h, "away_t": 0.0, "rest_t": 0.0, "cheered": false})
	bottle = Node3D.new()
	add_child(bottle)
	var bm := MeshInstance3D.new()
	bm.mesh = MeshKit.merge([
		[MeshKit.cyl(0.038, 0.038, 0.2, 10), MeshKit.at(Vector3(0, 0.1, 0)), Color(0.3, 0.75, 1.0)],
		[MeshKit.cyl(0.039, 0.039, 0.06, 10), MeshKit.at(Vector3(0, 0.1, 0)), Color(1, 1, 1)],
		[MeshKit.cyl(0.018, 0.03, 0.04, 8), MeshKit.at(Vector3(0, 0.22, 0)), Color(0.95, 0.3, 0.3)],
	])
	bm.material_override = vm
	bottle.add_child(bm)
	bottle.position = BOTTLE_HOME
	flag = Node3D.new()
	add_child(flag)
	flag.position = FLAG
	var pole := MeshInstance3D.new()
	pole.mesh = MeshKit.merge([
		[MeshKit.cyl(0.025, 0.025, 1.5, 6), MeshKit.at(Vector3(0, 0.75, 0)), Color(1.0, 0.95, 0.3)],
		[MeshKit.sphere(0.045, 6), MeshKit.at(Vector3(0, 1.52, 0)), Color(1, 1, 1)],
	])
	pole.material_override = vm
	flag.add_child(pole)
	flag_cloth = Node3D.new()
	flag_cloth.position = Vector3(0, 1.35, 0)
	flag.add_child(flag_cloth)
	var cloth := MeshInstance3D.new()
	cloth.mesh = MeshKit.merge([
		[MeshKit.box(Vector3(0.012, 0.3, 0.42)), MeshKit.at(Vector3(0, 0, 0.22)), Color(1.0, 0.25, 0.2)],
		[MeshKit.box(Vector3(0.014, 0.15, 0.21)), MeshKit.at(Vector3(0, 0.075, 0.115)), Color(1.0, 0.85, 0.2)],
	])
	cloth.material_override = vm
	flag_cloth.add_child(cloth)
	if main.world.mascot != null:
		main.world.mascot.position = MASCOT  # in reach of the keeper, just outside the left post
		main.world.mascot_home_yaw = 0.9


func _hit(key: String, cd: float = 0.35) -> bool:
	if float(cool.get(key, 0.0)) > 0.0:
		cool[key] = cd
		return false
	cool[key] = cd
	return true


## Host / local: the keeper's gloves touch things. tips: [left glove, right glove] (world).
func _process(delta: float) -> void:
	t += delta
	for k in cool.keys():
		cool[k] = float(cool[k]) - delta
	drink_cd = maxf(0.0, drink_cd - delta)
	var host: bool = main.is_host_side() and main.keeper != null and main.keeper.is_local()
	if host:
		_touch_all(delta)
		_sim_balls(delta)
	_animate(delta)


func _touch_all(delta: float) -> void:
	var k = main.keeper
	var w: float = k.ws()
	var tips: Array[Vector3] = [k.glove_l, k.glove_r]
	for i in 2:
		if prev_tips[i] != Vector3.ZERO:
			tip_vel[i] = tip_vel[i].lerp((tips[i] - prev_tips[i]) / maxf(delta, 0.001), 0.5)
		prev_tips[i] = tips[i]
	hand_vel = tip_vel[1]
	var reach := TOUCH_R * w
	for i in 2:
		var p: Vector3 = tips[i]
		var tag := "h%d" % i
		# Posts and crossbar.
		for px in [-3.72, 3.72]:
			if p.y < 2.55 and Vector2(p.x - px, p.z).length() < 0.06 + reach:
				if _hit("post" + tag):
					_touch("post", Vector3(px, p.y, 0.0), i)
		if absf(p.x) < 3.72 and Vector2(p.y - 2.5, p.z).length() < 0.06 + reach:
			if _hit("bar" + tag):
				_touch("post", Vector3(p.x, 2.5, 0.0), i)
		# The net (back and sides).
		if p.z < -0.15 and p.z > -2.3 and p.y < 2.5 and absf(p.x) < 3.85:
			if p.z < -1.85 or absf(absf(p.x) - 3.72) < reach or p.y > 2.3:
				if _hit("net" + tag, 0.6):
					_touch("net", p, i)
		# Spare balls: bat them with either glove (not the one being held).
		for b in balls.size():
			if b == held:
				continue
			var bd: Dictionary = balls[b]
			if p.distance_to(bd.pos) < R + reach:
				if _hit("ball%d%s" % [b, tag], 0.4):
					var v: Vector3 = tip_vel[i]
					var push: Vector3 = v * 1.4 if v.length() > 0.4 else (bd.pos - p).normalized() * 1.2
					bd.vel = push + Vector3(0, 1.0, 0)
					bd.rest_t = 0.0
					_touch("ball", bd.pos, i)
		if held != 3 and p.distance_to(bottle_pos + Vector3(0, 0.12, 0)) < 0.06 + reach:
			if _hit("bottle" + tag, 0.6):
				_touch("bottle", bottle_pos + Vector3(0, 0.2, 0), i)
				bottle_wob_v += Vector2(tip_vel[i].x, tip_vel[i].z).limit_length(3.0) * 2.0 + Vector2(1.5, 0)
		var fp := flag.global_position
		if p.y < 1.65 and Vector2(p.x - fp.x, p.z - fp.z).length() < 0.06 + reach + (0.25 if p.y > 1.1 else 0.0):
			if _hit("flag" + tag, 0.5):
				_touch("flag", p, i)
				flag_vel += Vector2(tip_vel[i].x, tip_vel[i].z).limit_length(4.0) * 0.6 + Vector2(1.2, 0.0)
		var mp: Vector3 = main.world.mascot.global_position if main.world.mascot != null else MASCOT
		if p.y > 0.6 and p.y < 2.1 and Vector2(p.x - mp.x, p.z - mp.z).length() < 0.42 + reach:
			if _hit("mascot" + tag, 1.5):
				_touch("mascot", p, i)
	# Grab with the right trigger (VR keeper; the bot squeezes too).
	var grab: bool = (k.vr and k.vr_trigger()) or bot_grab
	if grab and not grab_was and held < 0:
		var best := -1
		var bd2 := GRAB_R * w
		for b in balls.size():
			var d := tips[1].distance_to(balls[b].pos)
			if d < bd2:
				bd2 = d
				best = b
		if tips[1].distance_to(bottle_pos + Vector3(0, 0.1, 0)) < bd2:
			best = 3
		if best >= 0:
			held = best
			bottle_back = false
			_bump(1, 0.3)
			main.sound("bounce", -6.0, 1.4)
			touched["grab"] = int(touched.get("grab", 0)) + 1
	elif not grab and held >= 0:
		if held == 3:
			bottle_back = true
		else:
			var bd3: Dictionary = balls[held]
			bd3.vel = hand_vel.limit_length(18.0) * 1.3
			bd3.rest_t = 0.0
			bd3.cheered = false
			touched["throw"] = int(touched.get("throw", 0)) + 1
			print("Spare ball thrown at %.1f m/s" % bd3.vel.length())
		held = -1
	grab_was = grab
	if held >= 0 and held < 3:
		var bd4: Dictionary = balls[held]
		bd4.pos = tips[1] + Vector3(0, 0, 0.05) * w
		bd4.vel = Vector3.ZERO
		bd4.away_t = 0.0
	elif held == 3:
		bottle_pos = tips[1] + Vector3(0, -0.06, 0.02) * w
		if bottle_pos.distance_to(k.head_pos + Vector3(0, -0.1, 0.05) * w) < 0.2 * w and drink_cd <= 0.0:
			drink_cd = 1.2
			_touch("drink", bottle_pos, 1)
	if bottle_back and held != 3:
		bottle_pos = bottle_pos.move_toward(BOTTLE_HOME, 1.5 * delta)
		if bottle_pos.distance_to(BOTTLE_HOME) < 0.01:
			bottle_back = false


func _sim_balls(delta: float) -> void:
	for b in balls.size():
		if b == held:
			continue
		var bd: Dictionary = balls[b]
		var home: Vector3 = bd.home
		var at_home: bool = bd.pos.distance_to(home) < 0.02 and bd.vel.length() < 0.05
		if at_home:
			bd.away_t = 0.0
			continue
		bd.away_t += delta
		bd.vel += G * delta
		bd.pos += bd.vel * delta
		if bd.pos.y < R:
			bd.pos.y = R
			if bd.vel.y < 0.0:
				bd.vel.y = -bd.vel.y * 0.45
			bd.vel.x *= 0.9
			bd.vel.z *= 0.9
		if not bd.cheered and bd.pos.z > 7.0:
			bd.cheered = true
			main.sound("cheer", -8.0, 1.2, true)
			main.excite = 1.0
			touched["back"] = int(touched.get("back", 0)) + 1
		if bd.vel.length() < 0.3 and bd.pos.y < R + 0.02:
			bd.rest_t += delta
		if bd.rest_t > 2.0 or bd.away_t > 7.0:
			bd.pos = home  # pop back onto the crate
			bd.vel = Vector3.ZERO
			bd.rest_t = 0.0
			main.burst(home + Vector3(0, 0.1, 0), Color(1, 1, 1), 6)


## One touch on the host: react here, tell the TV, buzz the hand.
func _touch(kind: String, pos: Vector3, hand: int) -> void:
	touched[kind] = int(touched.get(kind, 0)) + 1
	react(kind, pos)
	if main.net != null:
		main.net.event("prop", [kind, pos])
	_bump(hand, 0.5 if kind == "post" or kind == "mascot" else 0.3)


func _bump(hand: int, amp: float) -> void:
	var k = main.keeper
	if k.vr:
		var h: XRController3D = k.hand_l if hand == 0 else k.hand_r
		h.trigger_haptic_pulse("haptic", 0.0, amp, 0.1, 0.0)


## Everyone: the reaction (sound, sparks, wobble).
func react(kind: String, pos: Vector3) -> void:
	match kind:
		"post":
			main.sound("post", -5.0, randf_range(0.85, 1.15))
			main.burst(pos, Color(1.0, 1.0, 0.8), 8, false)
		"net":
			main.sound("net", -10.0, 1.3)
			main.world.poke_net()
		"ball":
			main.sound("kick", -6.0, 1.3)
		"bottle":
			main.sound("glug", -4.0, 1.4)
			main.burst(pos, Color(0.4, 0.8, 1.0), 10, false)
			if not main.is_host_side():
				bottle_wob_v += Vector2(2.5, 0.0)
		"drink":
			main.sound("glug", -2.0, 0.9)
			main.burst(pos + Vector3(0, 0.1, 0), Color(0.4, 0.8, 1.0), 6, false)
		"flag":
			main.sound("dive", -12.0, 0.7)
			if not main.is_host_side():
				flag_vel += Vector2(1.5, 0.0)
		"mascot":
			main.sound("cheer", -6.0, 1.15)
			main.sound("save", -6.0, 1.6)
			main.world.mascot_cheer("save")
			main.excite = maxf(main.excite, 0.7)
			main.burst(pos, Color(1.0, 0.8, 0.25), 14, false)


func _animate(delta: float) -> void:
	for b in balls.size():
		var bd: Dictionary = balls[b]
		var n: Node3D = bd.node
		var d: Vector3 = bd.pos - n.position
		n.position = bd.pos if d.length() > 1.5 or main.is_host_side() else n.position.lerp(bd.pos, 1.0 - exp(-15.0 * delta))
		var sp := Vector3(d.x, 0.0, d.z)
		if sp.length() > 0.001:
			n.rotate(Vector3(sp.z, 0.0, -sp.x).normalized(), sp.length() / R)
	# Bottle wobble (a spring) and position.
	bottle_wob_v += (-bottle_wob * 60.0 - bottle_wob_v * 4.0) * delta
	bottle_wob += bottle_wob_v * delta
	bottle_wob = bottle_wob.limit_length(0.8)
	bottle.position = bottle.position.lerp(bottle_pos, 1.0 - exp(-20.0 * delta)) if not main.is_host_side() else bottle_pos
	bottle.rotation = Vector3(bottle_wob.y * 0.5, 0.0, -bottle_wob.x * 0.5) if held != 3 else Vector3(-0.4, 0.0, 0.0)
	# Flag: swings on its base, the cloth flaps faster.
	flag_vel += (-flag_ang * 30.0 - flag_vel * 2.5) * delta
	flag_ang += flag_vel * delta
	flag_ang = flag_ang.limit_length(0.6)
	flag.rotation = Vector3(flag_ang.y * 0.5, 0.0, -flag_ang.x * 0.5)
	flag_cloth.rotation.y = sin(t * 3.0) * 0.15 + sin(t * 11.0) * flag_vel.length() * 0.15


## Snapshot: the loose balls and the bottle (only where they are; reactions come as events).
func net_state() -> Array:
	return [balls[0].pos, balls[1].pos, balls[2].pos, bottle_pos, held]


func apply_net(s: Array) -> void:
	if s.size() < 5:
		return
	for b in 3:
		balls[b].pos = s[b]
	bottle_pos = s[3]
	held = int(s[4])
