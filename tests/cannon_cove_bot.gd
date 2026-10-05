extends Node
## Headless bot test for Cannon Cove. The gunner aims (solving the ballistic arc) and fires at the
## nearest ship or tentacle; deckhands patch leaks, shoot boarders and carry cannonballs.
## Same scene on host and client, so node paths match.
## BOT_PLAYERS=N (1..6) brings N deckhands aboard (players 2..N+1) through main.debug_join(); on the
## TV client the default is 2 (player 3 joins after a few seconds, as before).
## CC_START_WAVE=N skips ahead (e.g. 6 for the Kraken). CC_FAKE_VR=1 runs the real VR gunner code:
## the bot moves the fake hands to the glowing handle, squeezes the trigger, swings it and lets go
## (BOT_VR=1 does the same). In SIMPLE_MODE the fake VR gunner also rings the bell, pokes Polly and
## throws a spare cannonball overboard (props.gd) after the first shot.

const World := preload("res://games/cannon_cove/world.gd")

var main
var t := 0.0
var report_t := 0.0
var toggle := false
var joined_upto := 1
var vr_state := "rest"
var vr_t := 0.0
var vr_a_t := 0.0
var vr_shots := 0
var vr_misses := 0
var skipped := false
var prop_step := 0  # simple mode, fake VR: 0 not yet, 1 bell, 2 parrot, 3 reach ball, 4 throw, 5 done
var prop_t := 0.0
var seen := {}


func _wanted_deckhands() -> int:
	if OS.has_environment("BOT_PLAYERS"):
		return clampi(int(OS.get_environment("BOT_PLAYERS")), 1, 6)
	return 2 if main.net.mode == "client" else 1


func _ready() -> void:
	main = load("res://games/cannon_cove/main.tscn").instantiate()
	add_child(main)


func _physics_process(delta: float) -> void:
	t += delta
	toggle = not toggle
	if main == null or not main.ready_to_play:
		return
	if OS.has_environment("CC_START_WAVE") and not skipped and main.net.mode != "client":
		skipped = true
		main.wave = int(OS.get_environment("CC_START_WAVE")) - 1
		main.practice_hits = 99
		print("Bot: skipping ahead to wave %d" % (main.wave + 1))
	_note_features()
	if OS.has_environment("CC_SINK") and t > 30.0 and not main.game_over and main.net.mode != "client" and not has_meta("sunk"):
		set_meta("sunk", true)
		main.water = 100.0  # tests the game-over screen with stats and awards
		main._on_game_over()
		print("Bot: flooding the hold")
	# Drop-in: one more deckhand every second from t=4 s (host: nothing to do, the TV sends joins).
	if main.net.mode != "host" and t > 4.0 + joined_upto and joined_upto < _wanted_deckhands() and not main.game_over:
		joined_upto += 1
		main.debug_join(joined_upto)
		print("Bot: player %d joins" % (joined_upto + 1))
	_hotplug_test()
	for p in main.players:
		if p.ghost or p.remote:
			continue
		if not p.active:
			continue
		if p.gunner and p.fake_vr:
			_drive_fake_vr(p, delta)
		elif p.gunner:
			_drive_gunner(p)
		else:
			_drive_deckhand(p)
	report_t -= delta
	if report_t <= 0.0:
		report_t = 10.0
		_report()


## With 3+ deckhands: player 3's (pretend) controller unplugs at t=14 s and comes back at t=17 s.
var hotplug_step := 0


func _hotplug_test() -> void:
	if main.net.mode == "host" or _wanted_deckhands() < 3 or main.players.size() < 3:
		return
	var p = main.players[2]
	if hotplug_step == 0 and t > 14.0 and p.active:
		hotplug_step = 1
		p.joy = 42  # a fake device id
		main._on_joy_changed(42, false)
		print("Bot: unplugged player 3's controller")
	elif hotplug_step == 1 and t > 16.5:
		hotplug_step = 2
		print("Bot: player 3 active after unplug = %s" % p.active)
		main._on_joy_changed(42, true)
		print("Bot: plugged it back in")
	elif hotplug_step == 2 and t > 19.0:
		hotplug_step = 3
		print("Bot: player 3 active after replug = %s (joy %d)" % [p.active, p.joy])


func _report() -> void:
	var ammo := []
	for c in main.cannons:
		ammo.append(c.ammo)
	var carrying := []
	var where := []
	for p in main.players:
		carrying.append(p.carrying)
		if p.active and not p.gunner:
			where.append(Vector2(snappedf(p.global_position.x, 0.1), snappedf(p.global_position.z, 0.1)))
	var best: int = Engine.get_meta("cc_best_wave", 0)
	best = maxi(best, main.wave)
	Engine.set_meta("cc_best_wave", best)
	var active := 0
	for p in main.players:
		if p.active:
			active += 1
	print("t=%.0f mode=%s players=%d views=%d wave=%d (best %d) gold=%d water=%.0f ships=%d tentacles=%d boarders=%d leaks=%d ammo=%s carrying=%s deckhands at %s over=%s" % [
		t, main.net.mode, active, main.view_count, main.wave, best, main.gold, main.water,
		get_tree().get_nodes_in_group("ships").size(), get_tree().get_nodes_in_group("tentacles").size(),
		get_tree().get_nodes_in_group("boarders").size(), get_tree().get_nodes_in_group("leaks").size(),
		ammo, carrying, where, main.game_over])


## Prints each new feature the first time it shows up, so the log shows what got exercised.
func _note_features() -> void:
	var checks := {
		"practice target": not get_tree().get_nodes_in_group("targets").filter(func(x): return x.kind == "practice").is_empty(),
		"supply/chest": not get_tree().get_nodes_in_group("targets").filter(func(x): return x.kind != "practice").is_empty(),
		"fire ship": not get_tree().get_nodes_in_group("ships").filter(func(x): return x.kind == "fireship").is_empty(),
		"treasure ship": not get_tree().get_nodes_in_group("ships").filter(func(x): return x.kind == "treasure").is_empty(),
		"kraken": not get_tree().get_nodes_in_group("krakens").is_empty(),
		"kraken eyes open": not get_tree().get_nodes_in_group("krakens").filter(func(x): return x.state == "open").is_empty(),
		"golden ball on pile": main.golden_balls > 0,
		"golden ball loaded": main.cannons.any(func(c): return c.golden > 0),
		"victory": main.phase == "victory",
		"leak": not get_tree().get_nodes_in_group("leaks").is_empty(),
		"boarder": not get_tree().get_nodes_in_group("boarders").is_empty(),
		"tentacle": not get_tree().get_nodes_in_group("tentacles").is_empty(),
		"ghost hand": main.ghost_hand != null and main.ghost_hand.visible,
		"coach hint": main.coach_text != "",
		"guide arrow": main.players.any(func(pl): return pl.has_meta("guide") and pl.get_meta("guide").visible),
	}
	for k in checks:
		if checks[k] and not seen.has(k):
			seen[k] = true
			print("Bot: seen %s (t=%.0f, wave %d)%s" % [k, t, main.wave, (": " + main.coach_text.replace("\n", " / ")) if k == "coach hint" else ""])


## [aim point, node] of what the gunner should shoot, or [].
func _pick_target() -> Array:
	for k in get_tree().get_nodes_in_group("krakens"):
		if k.vulnerable():
			return [k.head_center(), k]
	var target = null
	var best_d := INF
	for s in get_tree().get_nodes_in_group("ships"):
		if s.sinking:
			continue
		var d: float = s.global_position.length() * (0.5 if s.is_fireship() else 1.0)
		if d < best_d:
			best_d = d
			target = s
	for tg in get_tree().get_nodes_in_group("targets"):
		var d: float = tg.global_position.length() * 0.6
		if d < best_d:
			best_d = d
			target = tg
	for tn in get_tree().get_nodes_in_group("tentacles"):
		if tn.alive() and tn.rise >= 1.0:
			target = tn
			break
	if target == null:
		return []
	var tp: Vector3
	if target.is_in_group("tentacles"):
		tp = target.segs[3].global_position
	elif target.is_in_group("targets"):
		tp = target.global_position + Vector3.UP * 0.6
	else:
		tp = target.global_position + Vector3.UP * 0.5
		var flight := tp.length() / 27.0
		tp += target.forward() * target.speed * flight
	return [tp, target]


## Yaw/pitch for cannon c to hit tp, or [] when out of range.
func _solve(c, tp: Vector3) -> Array:
	var d: Vector3 = c.global_basis.inverse() * (tp - c.global_position)
	var yaw := atan2(-d.x, -d.z)
	var r := Vector2(d.x, d.z).length()
	var v: float = c.MUZZLE_SPEED
	var g: float = main.GRAVITY
	var h := d.y
	var disc := v * v * v * v - g * (g * r * r + 2.0 * h * v * v)
	if disc < 0.0:
		return []
	return [yaw, atan((v * v - sqrt(disc)) / (g * r))]


## Fake VR gunner: reach for the handle, squeeze, swing, let go - like a person in the headset.
func _drive_fake_vr(p, delta: float) -> void:
	vr_t += delta
	vr_a_t -= delta
	p.fake_a = false
	var c = main.cannons[p.station]
	var handle: Vector3 = c.handle_world()
	var hr: Node3D = p.hand_r
	var rest: Vector3 = p.xr_camera.global_position + Vector3(0.2, -0.5, 0.0) - c.outboard * 0.1
	var pick := _pick_target()
	if main.game_over:
		p.fake_trigger["right_hand"] = 0.0
		return
	# Hop to the side the target is on (A).
	if not pick.is_empty() and p.grab_hand == null:
		var tp0: Vector3 = pick[0]
		var my_side := -1.0 if p.station < 2 else 1.0
		if signf(tp0.x) != my_side and absf(tp0.x) > 4.0 and vr_a_t <= 0.0:
			p.fake_a = true
			vr_a_t = 0.4
			vr_state = "rest"
			return
	if _fake_vr_props(p, delta):
		return
	match vr_state:
		"rest":
			hr.global_position = hr.global_position.lerp(rest, 0.2)
			p.fake_trigger["right_hand"] = 0.0
			if vr_t > 2.0 and vr_misses == 0:
				vr_state = "miss"  # first pull the trigger away from the handle (a lost newcomer)
				vr_t = 0.0
			elif vr_t > 0.6 and not pick.is_empty() and c.ammo > 0:
				vr_state = "reach"
				vr_t = 0.0
		"miss":
			p.fake_trigger["right_hand"] = 1.0 if vr_t < 0.3 else 0.0
			if vr_t > 0.8:
				vr_misses += 1
				print("Bot VR: pulled the trigger away from the handle, reach hint %.1f s, hint: %s" % [p.reach_miss_t, main.coach_text.replace("\n", " / ")])
				vr_state = "rest"
				vr_t = 0.0
		"reach":
			hr.global_position = hr.global_position.move_toward(handle, delta * 1.5)
			if hr.global_position.distance_to(handle) < 0.05:
				p.fake_trigger["right_hand"] = 1.0
				vr_state = "aim"
				vr_t = 0.0
		"aim":
			p.fake_trigger["right_hand"] = 1.0
			if p.grab_hand == null:
				if vr_t > 0.3:
					vr_state = "rest"
				return
			if pick.is_empty():
				return
			var sol := _solve(c, pick[0])
			if sol.is_empty():
				return
			var yaw: float = clampf(sol[0], -c.YAW_LIMIT, c.YAW_LIMIT)
			var pitch: float = clampf(sol[1], c.PITCH_MIN, c.PITCH_MAX)
			var flat := 0.95
			var d := Vector3(-sin(yaw) * flat, tan(pitch / 1.6) * flat, -cos(yaw) * flat)
			var want: Vector3 = c.global_position - c.global_basis * d - p.grab_offset
			hr.global_position = hr.global_position.lerp(want, 0.15)
			var settled: bool = absf(c.aim_yaw - yaw) < 0.04 and absf(c.aim_pitch - pitch) < 0.04
			var tp: Vector3 = pick[0]
			if settled and vr_t > 0.5 and absf(float(sol[0])) < c.YAW_LIMIT and tp.length() < 60.0:
				p.fake_trigger["right_hand"] = 0.0  # let go: BOOM
				vr_shots += 1
				vr_state = "rest"
				vr_t = 0.0
				if vr_shots <= 3:
					print("Bot VR: fired shot %d (ammo now %d)" % [vr_shots, c.ammo])


## Simple mode: touch the bell, poke Polly, then pick up a spare cannonball and throw it overboard.
func _fake_vr_props(p, delta: float) -> bool:
	if main.props == null or prop_step >= 5 or vr_shots < 1 or vr_state != "rest" or p.grab_hand != null:
		return false
	var hr: Node3D = p.hand_r
	var c = main.cannons[p.station]
	var mine := func(d: Dictionary) -> bool:
		var n: Node3D = d.node
		return Vector2(n.global_position.x - c.global_position.x, n.global_position.z - c.global_position.z).length() < 2.2
	prop_t += delta
	if prop_t > 8.0:
		print("Bot VR props: gave up at step %d" % prop_step)
		prop_step = 5
		return false
	match prop_step:
		0:
			prop_step = 1
			prop_t = 0.0
		1, 3:
			var kind := "bell" if prop_step == 1 else "ball"
			var goal = null
			for d in main.props.items:
				if d.kind == kind and d.state == "home" and mine.call(d):
					goal = main.props._touch_point(d) if kind == "bell" else (d.node as Node3D).global_position
					break
			if goal == null:
				return false
			var g: Vector3 = goal
			hr.global_position = hr.global_position.move_toward(g + (Vector3.ZERO if kind == "ball" else c.outboard * 0.15), delta * 1.6)
			p.fake_trigger["right_hand"] = 0.0
			if kind == "ball" and hr.global_position.distance_to(g) < 0.04:
				p.fake_trigger["right_hand"] = 1.0
				prop_step = 4
				prop_t = 0.0
			elif kind == "bell" and hr.global_position.distance_to(g + c.outboard * 0.15) < 0.03:
				prop_step = 2
				prop_t = 0.0
		2:
			var parrot = main.parrot
			var pp: Vector3 = parrot.global_position + Vector3.UP * 0.25
			hr.global_position = hr.global_position.move_toward(pp, delta * 1.2)
			if hr.global_position.distance_to(pp) < 0.05:
				prop_step = 3
				prop_t = 0.0
		4:
			p.fake_trigger["right_hand"] = 1.0
			hr.global_position += (c.outboard * 6.0 + Vector3.UP * 3.0) * delta  # fling it out to sea
			if prop_t > 0.25:
				p.fake_trigger["right_hand"] = 0.0
				print("Bot VR props: threw a cannonball (holding=%s)" % main.props.is_holding(hr))
				prop_step = 5
				vr_t = 0.0
	return true


func _drive_gunner(p) -> void:
	if main.game_over:
		p.bot_fire = t > 1.0 and toggle and main.game_over_time > 2.0
		return
	p.bot_fire = false
	var pick := _pick_target()
	if pick.is_empty():
		p.bot_aim_on = false
		return
	var target = pick[1]
	var tp: Vector3 = pick[0]
	# Pick a cannon on the side facing the target, preferring a loaded one.
	var first := 0 if tp.x < 0.0 else 2
	var station := first
	if main.cannons[first].ammo <= 0 and main.cannons[first + 1].ammo > 0:
		station = first + 1
	elif tp.z > 3.5 and main.cannons[first + 1].ammo > 0:
		station = first + 1
	p.bot_station = station
	var c = main.cannons[station]
	var d: Vector3 = c.global_basis.inverse() * (tp - c.global_position)
	var yaw := atan2(-d.x, -d.z)
	var r := Vector2(d.x, d.z).length()
	var v: float = c.MUZZLE_SPEED
	var g: float = main.GRAVITY
	var h := d.y
	var disc := v * v * v * v - g * (g * r * r + 2.0 * h * v * v)
	if disc < 0.0:
		p.bot_aim_on = false
		return
	var pitch := atan((v * v - sqrt(disc)) / (g * r))
	p.bot_aim_on = true
	p.bot_aim = Vector2(yaw, pitch)
	var settled: bool = absf(c.aim_yaw - clampf(yaw, -c.YAW_LIMIT, c.YAW_LIMIT)) < 0.03 and absf(c.aim_pitch - pitch) < 0.03
	var close_enough: bool = target.is_in_group("tentacles") or target.is_in_group("krakens") or tp.length() < (float(OS.get_environment("CC_BOT_RANGE")) if OS.has_environment("CC_BOT_RANGE") else 55.0)
	if settled and close_enough and absf(yaw) < c.YAW_LIMIT and c.ammo > 0 and c.reload_t <= 0.0 and p.station == station:
		p.bot_fire = toggle


func _drive_deckhand(p) -> void:
	p.bot_fire = false
	p.bot_use = false
	p.bot_move = Vector3.ZERO
	if main.game_over:
		return
	var pos: Vector3 = p.global_position
	var leaks := get_tree().get_nodes_in_group("leaks")
	var boarders := get_tree().get_nodes_in_group("boarders").filter(func(b): return b.alive())
	var goal = null
	# Odd players go for leaks first; even players go for boarders first.
	if not leaks.is_empty() and (p.index % 2 == 1 or boarders.is_empty() or leaks.size() > 1):
		var lk = leaks[0]
		for l in leaks:
			if l.global_position.distance_to(pos) < lk.global_position.distance_to(pos):
				lk = l
		if Vector2(pos.x - lk.global_position.x, pos.z - lk.global_position.z).length() < 1.3:
			p.bot_use = true
			return
		goal = lk.global_position
	elif not boarders.is_empty() and not p.carrying:
		var b = boarders[0]
		var to: Vector3 = b.global_position + Vector3.UP * 1.0 - (pos + Vector3.UP * 1.6)
		p.yaw = atan2(-to.x, -to.z)
		p.pitch = atan2(to.y, Vector2(to.x, to.z).length())
		p.bot_fire = true
		if to.length() > 9.0:
			goal = b.global_position
	elif not p.carrying and _musket_target(p) != null:
		var tp: Vector3 = _musket_target(p)
		var to: Vector3 = tp - (pos + Vector3.UP * 1.6)
		p.yaw = atan2(-to.x, -to.z)
		p.pitch = atan2(to.y, Vector2(to.x, to.z).length())
		p.bot_fire = true
	elif p.carrying:
		var best = main.cannons[0]
		for c in main.cannons:
			if c.ammo < best.ammo:
				best = c
		goal = best.global_position - best.outboard * 1.2
	else:
		var need := false
		for c in main.cannons:
			if c.ammo < c.MAX_AMMO:
				need = true
		if need:
			var spot := World.HOLD_POS + Vector3(-1.2 + 0.4 * p.index, 0.0, 1.9)
			if pos.distance_to(World.HOLD_POS) < 2.45:  # (the spot is 2.06 away; walking stops within 0.3 of it)
				p.bot_use = toggle
				return
			goal = spot
	if goal != null:
		var to: Vector3 = goal - pos
		to.y = 0.0
		if to.length() > 0.3:
			p.bot_move = to.normalized()
			if not p.bot_fire:
				p.yaw = lerp_angle(p.yaw, atan2(-to.x, -to.z), 0.2)
				p.pitch = 0.0


## Even-numbered deckhands snipe tentacles and bomb boats when there's nothing else to do.
func _musket_target(p):
	if p.index % 2 == 1:
		return null
	for tn in get_tree().get_nodes_in_group("tentacles"):
		if tn.alive() and tn.rise >= 1.0:
			return tn.segs[4].global_position
	for s in get_tree().get_nodes_in_group("ships"):
		if s.is_fireship() and not s.sinking and s.global_position.length() < 30.0:
			return s.global_position + Vector3.UP * 0.9
	return null


func _exit_tree() -> void:
	if main != null:
		var active := 0
		for p in main.players:
			if p.active:
				active += 1
		print("FINAL players=%d mode=%s wave=%d gold=%d water=%.0f game_over=%s best_wave=%d phase=%s practice_hits=%d seen=%s" % [active, main.net.mode, main.wave, main.gold, main.water, main.game_over, maxi(main.wave, Engine.get_meta("cc_best_wave", 0)), main.phase, main.practice_hits, seen.keys()])
		var n := _count_visuals(main)
		print("Visual instances in the scene: %d" % n)


func _count_visuals(n: Node) -> int:
	var c := 0
	if (n is MeshInstance3D or n is MultiMeshInstance3D or n is CPUParticles3D or n is Label3D) and n.is_visible_in_tree():
		c += 1
	for ch in n.get_children():
		c += _count_visuals(ch)
	return c
