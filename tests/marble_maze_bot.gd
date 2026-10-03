extends Node
## Headless bot for Marble Maze. Every marble follows a breadth-first path to the goal (avoiding holes,
## air and bumpers); the tilt bot (local / non-VR host) tilts the board the way the marbles want to go.
## BOT_PLAYERS=N: marbles to have (local split screen: up to 5, plus P1 tilting; TV machine: up to 6).
## BOT_LEVEL=n (local): start at level n.
## BOT_CHAOS=1: random tilting and steering instead (exercises falls, bumpers, respawns and time-up).
## Local mode also joins one marble by pressing A on a fake controller, and checks Start does NOT join.

const FAKE_PAD := 40

var main
var t := 0.0
var joined := false
var report_t := 0.0
var cont_t := 0.0
var dist := {}
var dist_level := -1
var cleared := 0
var last_level := 1
var max_home := 0
var join_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps running if the Start check opened the pause menu
	main = load("res://games/marble_maze/main.tscn").instantiate()
	add_child(main)


func _pad_press(device: int, button: JoyButton) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = device
		e.button_index = button
		e.pressed = down
		Input.parse_input_event(e)


func _physics_process(delta: float) -> void:
	t += delta
	if main == null or not main.ready_to_play:
		return
	var mode: String = main.net.mode
	if not joined and t > (3.0 if mode == "client" else 1.0):
		joined = true
		join_time = t
		_join_players(mode)
	if OS.has_environment("BOT_LEVEL") and mode == "local" and not has_meta("level_set"):
		set_meta("level_set", true)
		main._start_level(int(OS.get_environment("BOT_LEVEL")))
		last_level = main.level
	if mode == "local" and joined and t > join_time + 0.3 and not has_meta("start_checked"):
		set_meta("start_checked", true)
		print("BOT: Start on a new controller: joined=%s, menu opened=%s" % [main.joy_owner.has(FAKE_PAD + 1), get_tree().paused])
		if get_tree().paused:
			_pad_press(FAKE_PAD + 1, JOY_BUTTON_START)  # close the menu again
	if get_tree().paused:
		return
	if has_meta("pad_join") and t > join_time + 0.5:
		remove_meta("pad_join")
		_pad_press(FAKE_PAD, JOY_BUTTON_A)
	if mode == "local" and joined and t > join_time + 0.8 and not has_meta("pad_checked"):
		set_meta("pad_checked", true)
		print("BOT: fake controller %d drives P%d, paused=%s" % [FAKE_PAD, int(main.joy_owner.get(FAKE_PAD, -1)) + 1, get_tree().paused])
	var board = main.board
	if board.level_n != dist_level and board.rows.size() > 0:
		_bfs()
	if main.level > last_level:
		cleared += main.level - last_level
		print("BOT: level %d cleared (%d so far)" % [last_level, cleared])
	last_level = main.level
	max_home = maxi(max_home, main.home_count())
	var want := Vector2.ZERO
	var n := 0
	for p in main.players:
		if p.index == 0 or not p.active:
			continue
		var d := _desired(p)
		if p.is_local():
			p.bot = true
			p.bot_steer = d
		if not p.home and not p.falling:
			want += d
			n += 1
	if OS.has_environment("BOT_CHAOS"):
		_chaos(delta)
	var tl = main.players[0]
	if tl.is_local() and not tl.vr:
		tl.bot = true
		tl.bot_tilt = (want / n * 0.6) if n > 0 else Vector2.ZERO
		if OS.has_environment("BOT_CHAOS"):
			tl.bot_tilt = Vector2(sin(t * 0.9), cos(t * 0.6))
	if (main.state == "clear" or main.state == "over") and main.state_t > 2.0:
		cont_t -= delta
		if cont_t <= 0.0:
			cont_t = 1.0
			main.debug_continue()
	report_t -= delta
	if report_t <= 0.0:
		report_t = 4.0
		_report(mode)


func _chaos(_delta: float) -> void:
	for p in main.players:
		if p.index > 0 and p.is_local():
			p.bot_steer = Vector2(sin(t * 1.3 + p.index), cos(t * 0.7 + p.index * 2.0))
	if main.state == "play" and main.level == 1 and not has_meta("rushed") and main.net.mode != "client":
		set_meta("rushed", true)
		main.time_left = 25.0  # reach the time-up screen quickly


func _join_players(mode: String) -> void:
	if mode == "host":
		return
	var want := int(OS.get_environment("BOT_PLAYERS")) if OS.has_environment("BOT_PLAYERS") else (2 if mode == "local" else 1)
	var cap := 5 if mode == "local" else 6
	var target := clampi(want, 1, cap)
	var extra := target - 1
	print("BOT: %s mode, joining %d extra marbles" % [mode, extra])
	if mode == "local":
		_pad_press(FAKE_PAD + 1, JOY_BUTTON_START)  # Start must open the menu, not join
		if extra > 0:
			set_meta("pad_join", true)  # A on the fake controller once the menu is closed again
			extra -= 1
	for i in extra:
		var p = main.debug_join()
		print("BOT: debug_join -> %s" % ("P%d" % (p.index + 1) if p != null else "none"))


func _passable(k: String) -> bool:
	return k != "#" and k != "O" and k != "_" and k != "B"


func _step_ok(board, a: Vector2i, b: Vector2i) -> bool:
	if not _passable(board.ch(b.x, b.y)):
		return false
	var ka: String = board.ch(a.x, a.y)
	var kb: String = board.ch(b.x, b.y)
	if a.y == b.y and (ka == "|" or kb == "|"):
		return false
	if a.x == b.x and (ka == "-" or kb == "-"):
		return false
	return true


## Distance (in cells) from every cell to the goal.
func _bfs() -> void:
	var board = main.board
	dist_level = board.level_n
	dist.clear()
	var g: Vector2i = board.cell_of(board.goal)
	dist[g] = 0
	var q: Array[Vector2i] = [g]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = c + d
			if dist.has(nb) or not _step_ok(board, nb, c) or not _passable(board.ch(nb.x, nb.y)):
				continue
			dist[nb] = int(dist[c]) + 1
			q.append(nb)


func _desired(p) -> Vector2:
	var board = main.board
	var pos := Vector2(p.lp.x, p.lp.z)
	var c: Vector2i = board.cell_of(pos)
	var best := c
	var bd: int = dist.get(c, 9999)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nb: Vector2i = c + d
		var nd: int = dist.get(nb, 9999)
		if nd < bd and _step_ok(board, c, nb):
			bd = nd
			best = nb
	var target: Vector2 = board.center(best.x, best.y)
	if bd == 9999:
		target = board.center(c.x, c.y)
	var to := target - pos
	var desired_v := to.normalized() * minf(0.22, to.length() * 3.0) if to.length() > 0.001 else Vector2.ZERO
	var vel: Vector2 = p.est_v
	return ((desired_v - vel) * 5.0).limit_length(1.0)


func _report(mode: String) -> void:
	var act: Array[String] = []
	var falls := 0
	for p in main.players:
		if p.index > 0 and p.active:
			var cc: Vector2i = main.board.cell_of(Vector2(p.lp.x, p.lp.z))
			act.append("P%d%s@%d,%d" % [p.index + 1, "(home)" if p.home else "", cc.x, cc.y])
			falls += p.falls
	var views := 0
	for p in main.players:
		if p.has_meta("view") and p.get_meta("view").visible:
			views += 1
	var synced := 0
	for p in main.players:
		if p.index > 0 and p.remote and p.active and p.net_started:
			synced += 1
	print("BOT %s t=%.0f level=%d state=%s time=%.0f score=%d home=%d/%d gems=%d falls=%d cleared=%d views=%d remote_synced=%d tilt=%s [%s]" % [
		mode, t, main.level, main.state, main.time_left, main.score, main.home_count(), main.active_marbles().size(),
		main.board.gem_taken.count(true), falls, cleared, views, synced, main.board.tilt.snapped(Vector2(0.01, 0.01)), ", ".join(act)])
