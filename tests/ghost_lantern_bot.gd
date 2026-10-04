extends Node
## Headless bot for Ghost Lantern. Same scene on host and client (so node paths match).
## Local/host: player 1 points the lantern at the ghost nearest player 2 (and rings the bell now and then).
## Local/client: vacuum players walk up to the nearest ghost, aim at it and hold fire. On the client,
## player 3 joins after a few seconds by holding Space.
## BOT_PLAYERS=N (2..6): N TV players (P2..P{N+1}) join programmatically via main.debug_join(); in local mode
## the bot also fakes a controller unplug/replug and a player leaving and rejoining.
## Local / host also exercise the new content: shy, snuffer and golden ghosts, a thunderstorm, the LAST
## CHANCE (every photo lost -> the Ghost King has them), a ghost party and treat time; the game-over
## screen prints the awards. BOT_NIGHT=N jumps to night N first (6 = the last night -> sunrise);
## BOT_GOD=1 nobody gets spooked (and skips the scripted spook tests).
## BOT_VR=1 (local): the lantern-bearer runs the real VR code with fake hands (aims, shakes the bell).
var main
var t := 0.0
var last_print := -100.0
var bell_t := 7.0
var bot_players := int(OS.get_environment("BOT_PLAYERS")) if OS.has_environment("BOT_PLAYERS") else 0
var script_step := 0
var god := OS.has_environment("BOT_GOD")


func _ready() -> void:
	main = load("res://games/ghost_lantern/main.tscn").instantiate()
	add_child(main)
	_press(KEY_ENTER, true)  # P2 vacuum (and restart after game over)
	if not OS.has_environment("DUO_JOIN"):
		_press(KEY_SPACE, true)  # P1 focuses the lantern


func _press(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _nearest_ghost(pos: Vector3):
	var best = null
	var best_d := INF
	for g in get_tree().get_nodes_in_group("ghosts"):
		var d: float = g.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = g
	return best


func _aim(p, target: Vector3) -> void:
	var d: Vector3 = target - (p.global_position + Vector3.UP * 1.5)
	var flat := Vector2(d.x, d.z).length()
	if flat > 0.1:
		p.yaw = atan2(-d.x, -d.z)
		p.pitch = atan2(d.y, flat)


func _walk_to(p, target: Vector3, keep: float, delta: float) -> void:
	var to: Vector3 = target - p.global_position
	to.y = 0.0
	if to.length() > keep:
		var step: Vector3 = to.normalized() * 3.5 * delta
		p.global_position = Vector3(clampf(p.global_position.x + step.x, -20.0, 20.0), 0.0, clampf(p.global_position.z + step.z, -7.3, 7.3))


func _physics_process(delta: float) -> void:
	t += delta
	if main == null or main.players.size() < 2:
		return
	var mode: String = main.net.mode
	if bot_players <= 1 and mode == "client" and t > 8.0 and not has_meta("p3"):
		set_meta("p3", true)
		_press(KEY_SPACE, true)  # player 3 joins, then vacuums
	if bot_players >= 2 and mode != "host" and t > (8.0 if mode == "client" else 3.0) and not has_meta("joined"):
		set_meta("joined", true)
		for i in range(2, mini(bot_players, 6) + 1):
			print("BOT: P%d joins" % (i + 1))
			main.debug_join(i)
	if mode == "local" and bot_players >= 4:
		_test_pads()
	for p in main.players:
		if p.index >= 2 and not p.remote:
			p.bot_fire = p.active
	var p1 = main.players[0]
	if mode != "client":
		_content_script()
		if god:
			for p in main.players:
				p.invuln_t = 1.0
	if main.game_over and not has_meta("over_print"):
		set_meta("over_print", true)
		print("BOT: end screen:\n%s" % main.center_label.text)
	# Exercise courage, cheering up, game over and restart (host side decides).
	var down_at := 30.0 if mode == "local" else 18.0
	var over_at := 50.0 if mode == "local" else 26.0
	if mode != "client" and t > down_at and not has_meta("spooked") and not god:
		set_meta("spooked", true)
		print("BOT: spooking player 2 until they're down")
		for i in 3:
			main.players[1].invuln_t = 0.0
			main.spook_player(main.players[1], p1)
	if mode == "local" and has_meta("spooked") and main.players[1].is_down and t < down_at + 6.0:
		p1.global_position = main.players[1].global_position + Vector3(1.0, 0.0, 0.0)  # cheer them up
		return
	if mode != "client" and t > over_at and not main.game_over and not god:
		print("BOT: spooking everyone to test game over + restart")
		for p in main.players:
			for i in 4:
				p.invuln_t = 0.0
				p.spook(40.0, p.global_position)
	if p1.vr and not p1.is_down:
		# BOT_VR: point the lantern hand at the ghost nearest P2, walk the play space there, and shake
		# the left hand now and then to ring the bell.
		var vg = _nearest_ghost(main.players[1].global_position)
		if vg:
			p1.hand_r.global_basis = Basis.looking_at((vg.global_position - p1.hand_r.global_position).normalized(), Vector3.UP)
			var to: Vector3 = vg.global_position - p1.global_position
			to.y = 0.0
			if to.length() > 5.0:
				p1.xr_origin.global_position += to.normalized() * 3.0 * delta
		var shaking := fmod(t, 9.0) < 1.0
		p1.hand_l.position = Vector3(-0.25 + (sin(t * 30.0) * 0.12 if shaking else 0.0), 1.1, -0.3)
	elif not p1.ghost and not p1.remote and not p1.is_down:
		var g = _nearest_ghost(main.players[1].global_position)
		if g:
			_aim(p1, g.global_position)
			_walk_to(p1, g.global_position, 6.0, delta)
		bell_t -= delta
		if bell_t <= 0.0:
			bell_t = 9.0
			p1.try_ring_bell()
	for p in main.players:
		if p.role != "vacuum" or p.remote or p.ghost or not p.active or p.is_down:
			continue
		var g = _nearest_ghost(p.global_position)
		if g:
			_walk_to(p, g.global_position, 3.5, delta)
			_aim(p, g.global_position)
	if t - last_print >= 5.0:
		last_print = t
		var courage := []
		for p in main.players:
			courage.append("%d%s" % [int(p.courage), "(down)" if p.is_down else ""])
		var act := []
		for p in main.players:
			if p.active:
				act.append(p.index + 1)
		print("BOT t=%.0f active=%s views=%d bonus=%d" % [t, act, main.view_count, main.crowd_bonus()])
		print("BOT t=%.0f mode=%s night=%d score=%d caught=%d saved=%d photos=%d/%d ghosts=%d courage=%s over=%s" % [
			t, mode, main.night, main.score, main.caught, main.saved, main.photos_left(), main.photos.size(),
			get_tree().get_nodes_in_group("ghosts").size(), courage, main.game_over])
		var kinds := {}
		for g in get_tree().get_nodes_in_group("ghosts"):
			kinds[g.kind] = int(kinds.get(g.kind, 0)) + 1
		var d = main.director()
		print("BOT   kinds=%s event=%s last_chance=%.0f treats=%d won=%s dawn=%.2f snuff=%.1f" % [kinds, d.event_name,
			d.last_chance_t, d.treats.size(), d.won, d.dawn, main.players[0].snuff_t])


## New ghosts and events, once each.
func _content_script() -> void:
	var steps := [
		[1.5, func() -> void:
			if OS.has_environment("BOT_NIGHT"):
				main.debug_skip_to_night(int(OS.get_environment("BOT_NIGHT")))
				print("BOT: skip to night %s" % OS.get_environment("BOT_NIGHT"))],
		[4.0, func() -> void:
			for k in ["shy", "snuffer", "golden"]:
				main.debug_spawn(k)
			print("BOT: spawned shy, snuffer, golden")],
		[8.0, func() -> void: main.debug_event("storm")],
		[16.0, func() -> void:
			if not OS.has_environment("BOT_NIGHT"):
				main.debug_lose_photos()
				print("BOT: every photo lost -> last chance?")],
		[22.0, func() -> void: main.debug_event("party")],
		[36.0, func() -> void: main.debug_event("treats")],
	]
	while script_step < steps.size() and t >= float(steps[script_step][0]):
		var f: Callable = steps[script_step][1]
		f.call()
		script_step += 1


## Local only: fake a controller for P4, unplug and replug it; then P5 times out, leaves and rejoins.
func _test_pads() -> void:
	var p4 = main.players[3]
	var p5 = main.players[4]
	if t > 12.0 and not has_meta("unplug"):
		set_meta("unplug", true)
		p4.joy = 97
		main._on_joy_changed(97, false)
		print("BOT: unplugged P4's pad -> waiting=%s joy=%d" % [main.pad_wait.has(3), p4.joy])
	if t > 14.0 and not has_meta("replug"):
		set_meta("replug", true)
		main._on_joy_changed(97, true)
		print("BOT: replugged -> P4 joy=%d waiting=%s" % [p4.joy, main.pad_wait.has(3)])
		p4.joy = -1
	if t > 16.0 and not has_meta("leave"):
		set_meta("leave", true)
		p5.joy = 98
		main._on_joy_changed(98, false)
		main.pad_wait[4] = 0.3
	if t > 17.0 and not has_meta("left"):
		set_meta("left", true)
		print("BOT: P5 active after pad timeout = %s" % p5.active)
	if t > 19.0 and not has_meta("rejoin"):
		set_meta("rejoin", true)
		main.debug_join(4)
		print("BOT: P5 rejoined = %s" % p5.active)
