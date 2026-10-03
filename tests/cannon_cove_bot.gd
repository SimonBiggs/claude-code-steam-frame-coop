extends Node
## Headless bot test for Cannon Cove. The gunner aims (solving the ballistic arc) and fires at the
## nearest ship or tentacle; deckhands patch leaks, shoot boarders and carry cannonballs.
## Same scene on host and client, so node paths match.
## BOT_PLAYERS=N (1..6) brings N deckhands aboard (players 2..N+1) through main.debug_join(); on the
## TV client the default is 2 (player 3 joins after a few seconds, as before).

const World := preload("res://games/cannon_cove/world.gd")

var main
var t := 0.0
var report_t := 0.0
var toggle := false
var joined_upto := 1


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
		if p.gunner:
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
	for p in main.players:
		carrying.append(p.carrying)
	var best: int = Engine.get_meta("cc_best_wave", 0)
	best = maxi(best, main.wave)
	Engine.set_meta("cc_best_wave", best)
	var active := 0
	for p in main.players:
		if p.active:
			active += 1
	print("t=%.0f mode=%s players=%d views=%d wave=%d (best %d) gold=%d water=%.0f ships=%d tentacles=%d boarders=%d leaks=%d ammo=%s carrying=%s over=%s" % [
		t, main.net.mode, active, main.view_count, main.wave, best, main.gold, main.water,
		get_tree().get_nodes_in_group("ships").size(), get_tree().get_nodes_in_group("tentacles").size(),
		get_tree().get_nodes_in_group("boarders").size(), get_tree().get_nodes_in_group("leaks").size(),
		ammo, carrying, main.game_over])


func _drive_gunner(p) -> void:
	if main.game_over:
		p.bot_fire = t > 1.0 and toggle and main.game_over_time > 2.0
		return
	var target = null
	var best_d := INF
	for s in get_tree().get_nodes_in_group("ships"):
		if s.sinking:
			continue
		var d: float = s.global_position.length()
		if d < best_d:
			best_d = d
			target = s
	for tn in get_tree().get_nodes_in_group("tentacles"):
		if tn.alive() and tn.rise >= 1.0:
			target = tn
			break
	p.bot_fire = false
	if target == null:
		p.bot_aim_on = false
		return
	var tp: Vector3
	if target.is_in_group("tentacles"):
		tp = target.segs[3].global_position
	else:
		tp = target.global_position + Vector3.UP * 0.5
		var flight := tp.length() / 27.0
		tp += target.forward() * target.speed * flight
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
	var close_enough: bool = target.is_in_group("tentacles") or tp.length() < (float(OS.get_environment("CC_BOT_RANGE")) if OS.has_environment("CC_BOT_RANGE") else 55.0)
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
			if pos.distance_to(World.HOLD_POS) < 2.3:
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


func _exit_tree() -> void:
	if main != null:
		var active := 0
		for p in main.players:
			if p.active:
				active += 1
		print("FINAL players=%d mode=%s wave=%d gold=%d water=%.0f game_over=%s best_wave=%d" % [active, main.net.mode, main.wave, main.gold, main.water, main.game_over, maxi(main.wave, Engine.get_meta("cc_best_wave", 0))])
