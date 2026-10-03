extends Node
## Headless bot for Ghost Lantern. Same scene on host and client (so node paths match).
## Local/host: player 1 points the lantern at the ghost nearest player 2 (and rings the bell now and then).
## Local/client: vacuum players walk up to the nearest ghost, aim at it and hold fire. On the client,
## player 3 joins after a few seconds by holding Space.
var main
var t := 0.0
var last_print := -100.0
var bell_t := 7.0


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
	if mode == "client" and t > 8.0 and not has_meta("p3"):
		set_meta("p3", true)
		_press(KEY_SPACE, true)  # player 3 joins, then vacuums
	var p1 = main.players[0]
	# Exercise courage, cheering up, game over and restart (host side decides).
	var down_at := 30.0 if mode == "local" else 18.0
	var over_at := 50.0 if mode == "local" else 26.0
	if mode != "client" and t > down_at and not has_meta("spooked"):
		set_meta("spooked", true)
		print("BOT: spooking player 2 until they're down")
		for i in 3:
			main.players[1].invuln_t = 0.0
			main.spook_player(main.players[1], p1)
	if mode == "local" and has_meta("spooked") and main.players[1].is_down and t < down_at + 6.0:
		p1.global_position = main.players[1].global_position + Vector3(1.0, 0.0, 0.0)  # cheer them up
		return
	if mode != "client" and t > over_at and not main.game_over:
		print("BOT: spooking everyone to test game over + restart")
		for p in main.players:
			for i in 4:
				p.invuln_t = 0.0
				p.spook(40.0, p.global_position)
	if not p1.ghost and not p1.remote and not p1.is_down:
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
		print("BOT t=%.0f mode=%s night=%d score=%d caught=%d saved=%d photos=%d/%d ghosts=%d courage=%s over=%s" % [
			t, mode, main.night, main.score, main.caught, main.saved, main.photos_left(), main.photos.size(),
			get_tree().get_nodes_in_group("ghosts").size(), courage, main.game_over])
