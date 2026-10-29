extends Node
## Headless bot for Marble Maze. Every marble follows a breadth-first path to the goal (avoiding holes,
## air and bumpers); the tilt bot (local / non-VR host) tilts the board the way the marbles want to go.
## BOT_PLAYERS=N: marbles to have (local split screen: up to 5, plus P1 tilting; TV machine: up to 6).
## BOT_LEVEL=n (local): start at level n.
## BOT_CHAOS=1: random tilting and steering instead (exercises falls, bumpers, respawns and time-up).
## Local mode also joins one marble by pressing A on a fake controller, and checks Start does NOT join.
## Teamwork: while a level's team gates are shut, marbles split up onto the pads (the BFS treats shut
## gates as walls and teleporters as links); marbles that are home steer their guide star to the
## marble furthest behind and tow it along its path. Unless BOT_LEVEL is set, local / host runs take a
## TOUR of the new levels (team gates, ice, zoom arrows, teleporters, mud + two gate groups, finale)
## and finally let the clock run out to check the awards.
## SIMPLE_MODE (main.simple): the tour is every level in order; the bot checks the practice (the ring,
## the ghost hands and ghost marble), that holes pop marbles back nearby, that no clock, score or game
## over exists, and touches every toy round the table (VR: with the fake hands).
## BOT_VR=1 (local or DUO_HOST): the giant runs the real VR code with fake hands: the right hand grabs a
## handle (after watching the ghost hands for a moment) and tilts the board the way the marbles need.
## DUO_HOST alone (no TV machine) in SIMPLE_MODE: the giant's own solo marble rolls home by tilt only.
## STORY (simple mode, games/marble_maze/story.gd): after the seven lessons come TODAY'S MAZE and Bobo's
## seeded story mazes. BOT_STORY=1 skips the lessons, BOT_STORY_I=n starts at story maze n (12 = CASTLE:
## team pads, 15 = STAR PARK: teleporters, 18 = RAINBOW HILL: everything), BOT_NO_DAILY=1 skips today's
## maze, BOT_NO_SHINY=1 stops P2's detour for the shiny marble. Zoom arrows are one-way in the bot's paths.
## Prints "BOT STORY: ..." (save progress, places lit, jar) at the end. Generator: marble_maze_gen_test.gd.
## Visual teaching (simple mode): records the picture cues each view shows (cue_roll, cue_turn,
## cue_tilt, cue_plug), the ones learned (cue_learned_*), the glowing edge arrow, the board arrows
## (tilt_arrow, goal_arrow, grab_arrow), the ghost hands / marble and the join cue; checks the pause
## banner is just PAUSED, and prints "BOT: ERROR instruction text" if a headline (TV or VR) is anything
## but a level name or a short word, or a tip spot (a view's HUD line, the controls line) shows words.
## P2 looks away from the goal now and then (turn cue); local mode unplugs P3's fake controller (bolt)
## and plugs it back in.

const FAKE_PAD := 40

const STUCK_SECS := 90.0
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
var pad_dist := {}  # pad index -> {cell: dist}
var gem_dist := {}  # story mazes: the way to the shiny marble (P2 detours for it)
var tour_i := 0
const TOUR := [1, 3, 5, 7, 9, 10, 12]
var forced_over := false
var simple := false
var saw_ring := false
var saw_hands := false
var saw_ghost_marble := false
var practice_done := false
var vr_grab_t := 0.0
var toy_i := 0
var toy_t := 0.0
var cues := {}  # simple mode: picture cues seen / learned
var plug_phase := 0
const WORDS := ["", "GO!", "HOORAY!", "PAUSED", "HELLO!", "Connecting to the VR player…"]
const HUD_WORDS := ["", "HOME!", "Syncing with the VR player…"]


func _ready() -> void:
	preload("res://tests/bot_end.gd").arm(self)  # end by itself in networked runs
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
	if OS.has_environment("BOT_COUNT"):
		if t > 8.0 and not has_meta("counted"):
			set_meta("counted", true)
			var c := {"mesh": 0, "multimesh": 0, "label": 0, "particles": 0}
			_count_node(main, c)
			print("COUNT ", c)
			get_tree().quit()
		return
	var mode: String = main.net.mode
	simple = main.simple
	if simple:
		_simple_checks(delta)
		_look_away()
		_note_cues()
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
	# The map itself is in the key: a story maze can replace the first lesson with the same level number.
	var key: int = hash([board.level_n, board.rows, board.gate_open[0], board.gate_open[1]])
	if key != dist_level and board.rows.size() > 0:
		dist_level = key
		dist = _bfs_from([board.cell_of(board.goal)])
		pad_dist.clear()
		for i in board.pads.size():
			var pd: Array = board.pads[i]
			pad_dist[i] = _bfs_from([board.cell_of(pd[0])])
		gem_dist = _bfs_from([board.cell_of(board.gems[0])]) if simple and not board.gems.is_empty() else {}
	if main.level > last_level:
		cleared += main.level - last_level
		print("BOT: level %d cleared (%d so far)" % [last_level, cleared])
	last_level = main.level
	max_home = maxi(max_home, main.home_count())
	var want := Vector2.ZERO
	var n := 0
	var k := 0
	for p in main.players:
		if p.index == 0 or not p.active:
			continue
		var d := (Vector2.ZERO if main.simple else _guide_dir(p)) if p.home else _desired(p, k)
		k += 1
		d = _unstick(p, d, delta)
		if p.is_local():
			p.bot = true
			p.bot_steer = d
		if not p.home and not p.falling:
			want += d
			n += 1
	if OS.has_environment("BOT_CHAOS"):
		_chaos(delta)
	var tl = main.players[0]
	if tl.vr and mode != "client":
		_vr_drive(tl, (want / n * 0.6) if n > 0 else Vector2.ZERO, delta)
	if tl.is_local() and not tl.vr:
		tl.bot = true
		tl.bot_tilt = (want / n * 0.6) if n > 0 else Vector2.ZERO
		if OS.has_environment("BOT_CHAOS"):
			tl.bot_tilt = Vector2(sin(t * 0.9), cos(t * 0.6))
	_tour()
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
	if main.state == "play" and main.level == 1 and not has_meta("rushed") and main.net.mode != "client" and not simple:
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


## Local / host without BOT_LEVEL: hop between the new levels on each clear, then run the clock out.
func _tour() -> void:
	if mode_is_client() or OS.has_environment("BOT_LEVEL") or OS.has_environment("BOT_CHAOS"):
		return
	if simple:
		# A maze nobody can finish (2026-10-29: the daily's shiny sat below a zoom arrow and P2 looped for
		# 230 s) must fail the run, not just "run to the end".
		if main.state == "play" and main.state_t > STUCK_SECS and not has_meta("stuck_%d" % main.level):
			set_meta("stuck_%d" % main.level, true)
			print("BOT ASSERT FAILED: level %d (%s) not cleared after %d s (home %d/%d)" % [main.level,
				main.board.level_name(main.level), int(STUCK_SECS), main.home_count(), main.active_marbles().size()])
		if main.state == "clear" and main.state_t > 1.6 and not has_meta("clear_%d" % main.level):
			set_meta("clear_%d" % main.level, true)
			print("BOT: simple level %d (%s) cleared, falls so far %d" % [main.level, main.board.level_name(main.level), _falls()])
		return
	if main.state == "clear" and main.state_t > 1.6 and tour_i + 1 < TOUR.size():
		tour_i += 1
		print("BOT: tour -> level %d" % TOUR[tour_i])
		last_level = TOUR[tour_i]
		main._start_level(TOUR[tour_i])
	var limit := 52.0 if not OS.has_environment("BOT_PLAYERS") else 34.0
	if not forced_over and main.net.mode == "local" and main.state == "play" and t > limit:
		forced_over = true
		print("BOT: letting the clock run out to check the awards")
		main.time_left = 0.2
	if main.state == "over" and not has_meta("over_said") and main.state_t > 0.5:
		set_meta("over_said", true)
		print("BOT: end screen says: %s" % main.center_label.text.replace("\n", " | "))


func _falls() -> int:
	var f := 0
	for p in main.players:
		if p.index > 0:
			f += p.falls
	return f


## SIMPLE_MODE checks (all machines): practice ring, ghost hands / marble, no clock, toys.
func _simple_checks(delta: float) -> void:
	if main.state == "practice":
		if main.ring_node != null and main.ring_node.visible and not saw_ring:
			saw_ring = true
			print("BOT: practice ring is glowing at %s" % main.board.practice_spot())
		var gh = main.ghost_hand
		if gh != null and gh.marble.visible and not saw_ghost_marble:
			saw_ghost_marble = true
			print("BOT: ghost marble rolls to the ring")
		if gh != null and gh.visible and gh.shown_hands and not saw_hands:
			saw_hands = true
			print("BOT: ghost hands show the grip and tilt")
	if main.state == "play" and saw_ring and not practice_done:
		practice_done = true
		print("BOT: practice done -> play (ring hits %s)" % str(main.ring_hit.keys()))
	if main.state == "over" and not has_meta("over_bad"):
		set_meta("over_bad", true)
		print("BOT: FAIL simple mode reached a game over")
	if main.props != null and not has_meta("props_said") and t > 50.0:
		set_meta("props_said", true)
		print("BOT: toys touched: %s (of 9)" % str(main.props.touched.keys()))
	if not has_meta("hud_said") and main.state == "play" and t > 20.0 and main.players.size() > 1:
		set_meta("hud_said", true)
		print("BOT: HUD line: '%s'  centre: '%s'" % [main.hud_text(main.players[1]), main.center_label.text.replace("\n", " | ")])
	# Non-VR toys: poke them straight (the VR run touches them with the fake left hand).
	if main.props != null and not main.players[0].vr and main.net.mode != "client":
		toy_t -= delta
		if toy_t <= 0.0 and toy_i < 8:
			toy_t = 2.0
			main.props.react(toy_i)
			toy_i += 1


## BOT_VR: the real tilter code with fake hands. The right hand waits a moment in practice (so the
## ghost hands show), then grabs the right handle and moves to tilt the board towards `want`.
## The left hand visits each toy in turn, then grabs and throws a spare marble.
func _vr_drive(tl, want: Vector2, delta: float) -> void:
	var board = main.board
	var waiting: bool = main.state == "practice" and not saw_hands
	if waiting or main.state != "play" and main.state != "practice":
		if tl.grabbing:
			tl.fake_trigger = 0.0
		else:
			tl.fake_trigger = 0.0
			tl.hand_r.global_position = tl.xr_camera.global_position + Vector3(0.25, -0.5, -0.3)
	else:
		if not tl.grabbing:
			tl.hand_r.global_position = board.handle_world(1)
			tl.fake_trigger = 0.0 if tl.fake_trigger > 0.5 else 1.0
			if tl.fake_trigger > 0.5:
				vr_grab_t = 0.0
		else:
			tl.fake_trigger = 1.0
			vr_grab_t += delta
			if not has_meta("vr_grab_said"):
				set_meta("vr_grab_said", true)
				print("BOT: VR right hand grabbed the board's handle")
			var g: Vector2 = tl.grab_tilt
			var d := want.limit_length(1.0) - g
			var gain: float = tl.HAND_GAIN
			tl.hand_r.global_position = tl.grab_r + Vector3(0.0, -d.x / gain, d.y / gain)
			if vr_grab_t > 6.0:  # let go now and then (re-grab at the current tilt)
				tl.fake_trigger = 0.0
	# Left hand: toys.
	var pr = main.props
	if pr == null:
		return
	toy_t -= delta
	if toy_t <= 0.0:
		toy_t = 1.5
		toy_i = (toy_i + 1) % 9
	var target: Vector3 = pr.touch_point(mini(toy_i, 8))
	var side := Vector3(0.0, 0.12 if toy_t > 0.8 else 0.0, 0.0)  # come down onto it
	tl.hand_l.global_position = target + side


func mode_is_client() -> bool:
	return main.net.mode == "client"


func _passable(k: String) -> bool:
	return k != "#" and k != "O" and k != "_" and k != "B"


func _open_here(board, c: Vector2i) -> bool:
	var k: String = board.ch(c.x, c.y)
	if k == "D":
		return board.gate_open[0]
	if k == "E":
		return board.gate_open[1]
	return _passable(k)


func _step_ok(board, a: Vector2i, b: Vector2i) -> bool:
	if not _open_here(board, b):
		return false
	var ka: String = board.ch(a.x, a.y)
	var kb: String = board.ch(b.x, b.y)
	if a.y == b.y and (ka == "|" or kb == "|"):
		return false
	if a.x == b.x and (ka == "-" or kb == "-"):
		return false
	# Zoom arrows are one-way: no rolling against one (leaving it or entering it).
	var arrows := {">": Vector2i(1, 0), "<": Vector2i(-1, 0), "^": Vector2i(0, -1), "v": Vector2i(0, 1)}
	if arrows.has(ka) and arrows[ka] == a - b:
		return false
	# ...and never sideways off one (BOOST carries you along it), unless it points into a wall (mazegen._moves).
	if arrows.has(ka) and arrows[ka] != b - a and _open_here(board, a + (arrows[ka] as Vector2i)):
		return false
	if arrows.has(kb) and arrows[kb] == a - b:
		return false
	return true


## Distance (in cells) from every cell to the nearest of `targets`. Rolling onto a teleporter puts
## you on its twin, so a teleporter's distance comes from its twin's neighbours, never from walking.
func _bfs_from(targets: Array) -> Dictionary:
	var board = main.board
	var out := {}
	var q: Array[Vector2i] = []
	for tc in targets:
		var c: Vector2i = tc
		out[c] = 0
		q.append(c)
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		var nbs: Array[Vector2i] = [c + Vector2i(1, 0), c + Vector2i(-1, 0), c + Vector2i(0, 1), c + Vector2i(0, -1)]
		for nb in nbs:
			if not _step_ok(board, nb, c) or not _open_here(board, nb):
				continue
			if board.tp_dest.has(nb):
				# Arriving on teleporter nb, you can roll on to c: so entering nb's twin is 2 steps from c.
				var twin: Vector2i = board.cell_of(board.tp_dest[nb])
				if not out.has(twin):
					out[twin] = int(out[c]) + 2
					q.append(twin)
				continue
			if out.has(nb):
				continue
			out[nb] = int(out[c]) + 1
			q.append(nb)
	return out


## Where this marble should head: the goal, or (while a team gate is shut) a team pad of its own.
func _target_map(p, k: int) -> Dictionary:
	var board = main.board
	var c: Vector2i = board.cell_of(Vector2(p.lp.x, p.lp.z))
	if k == 0 and main.state == "play" and not gem_dist.is_empty() and not board.gem_taken[0] and gem_dist.has(c) \
			and not OS.has_environment("BOT_NO_SHINY"):
		return gem_dist  # the first marble takes the detour for the shiny
	if dist.has(c) or board.pads.is_empty():
		return dist
	for g in 2:
		if board.gate_open[g] or not board.group_has_pads(g):
			continue
		var mine: Array = []
		for i in board.pads.size():
			var pd: Array = board.pads[i]
			if int(pd[1]) == g and pad_dist.has(i) and (pad_dist[i] as Dictionary).has(c):
				mine.append(i)
		if not mine.is_empty():
			return pad_dist[mine[k % mine.size()]]
	return dist


func _desired(p, k: int = 0) -> Vector2:
	var board = main.board
	var pos := Vector2(p.lp.x, p.lp.z)
	var c: Vector2i = board.cell_of(pos)
	var dm := _target_map(p, k)
	var best := c
	var bd: int = dm.get(c, 9999)
	if c == p.tp_lock:
		bd = 9999  # just popped out of a teleporter: roll off it first
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nb: Vector2i = c + d
		var nd: int = dm.get(nb, 9999)
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


## Two marbles nose to nose (e.g. one popping out of a teleporter the other wants to enter): after a
## couple of seconds of not moving, wiggle off in a random direction for a moment.
func _unstick(p, d: Vector2, delta: float) -> Vector2:
	if p.home or p.falling or main.state != "play":
		p.set_meta("stuck_t", 0.0)
		return d
	var wig: float = p.get_meta("wiggle_t", 0.0)
	if wig > 0.0:
		p.set_meta("wiggle_t", wig - delta)
		return p.get_meta("wiggle_dir", Vector2.ZERO)
	var vel: Vector2 = p.est_v
	var st: float = p.get_meta("stuck_t", 0.0)
	st = st + delta if vel.length() < 0.02 else 0.0
	p.set_meta("stuck_t", st)
	if st > 2.0:
		p.set_meta("stuck_t", 0.0)
		p.set_meta("wiggle_t", 0.7)
		p.set_meta("wiggle_dir", Vector2.from_angle(randf() * TAU))
	return d


## A home marble's guide star: go to the marble furthest from the goal, then lead it along its path.
func _guide_dir(p) -> Vector2:
	var board = main.board
	var worst = null
	var wd := -1
	for o in main.players:
		if o.index == 0 or not o.active or o.home or o.falling:
			continue
		var od: int = dist.get(board.cell_of(Vector2(o.lp.x, o.lp.z)), 999)
		if od > wd:
			wd = od
			worst = o
	if worst == null:
		return Vector2.ZERO
	var op := Vector2(worst.lp.x, worst.lp.z)
	var to: Vector2 = op - p.guide
	if to.length() > 0.04:
		if not has_meta("guide_said"):
			set_meta("guide_said", true)
			print("BOT: P%d's guide star heads for P%d" % [p.index + 1, worst.index + 1])
		return to.normalized()
	if not has_meta("tow_said"):
		set_meta("tow_said", true)
		print("BOT: P%d is towing P%d" % [p.index + 1, worst.index + 1])
	return _desired(worst) * 0.6 + to * 6.0


func _report(mode: String) -> void:
	if OS.has_environment("BOT_DEBUG"):
		for p in main.players:
			if p.index > 0 and p.active:
				var pos := Vector2(p.lp.x, p.lp.z)
				var c: Vector2i = main.board.cell_of(pos)
				print("DBG P%d pos=%s cell=%s off=%s lock=%s dist=%s steer=%s v=%s" % [p.index + 1, pos, c, pos - main.board.center(c.x, c.y), p.tp_lock, dist.get(c, -1), p.bot_steer, p.v])
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
	if simple:
		print("BOT %s t=%.0f level=%d (%s) state=%s home=%d/%d falls=%d views=%d remote_synced=%d tilt=%s solo=%s [%s]" % [
			mode, t, main.level, main.board.level_name(main.level), main.state, main.home_count(), main.active_marbles().size(), falls, views, synced,
			main.board.tilt.snapped(Vector2(0.01, 0.01)), main.solo, ", ".join(act)])
		return
	print("BOT %s t=%.0f level=%d state=%s time=%.0f score=%d stars=%d jar=%d home=%d/%d gems=%d falls=%d cleared=%d views=%d remote_synced=%d gates=%s tilt=%s [%s]" % [
		mode, t, main.level, main.state, main.time_left, main.score, main.stars, main.jar, main.home_count(), main.active_marbles().size(),
		main.board.gem_taken.count(true), falls, cleared, views, synced, str(main.board.gate_open), main.board.tilt.snapped(Vector2(0.01, 0.01)), ", ".join(act)])


## BOT_COUNT=1: what a camera would draw (performance check).
func _count_node(n: Node, c: Dictionary) -> void:
	if n is VisualInstance3D and (n as Node3D).is_visible_in_tree():
		if n is MeshInstance3D:
			c.mesh += 1
		elif n is MultiMeshInstance3D:
			c.multimesh += 1
		elif n is Label3D:
			c.label += 1
		elif n is CPUParticles3D:
			c.particles += 1
	for ch in n.get_children():
		_count_node(ch, c)


# --- Visual teaching checks (simple mode) ------------------------------------------

## P2 turns its camera away from the goal for a moment now and then, so the turn cue (and the edge
## arrow) shows; letting go, the camera swings back behind the rolling marble.
func _look_away() -> void:
	if t < 10.0 or main.players.size() < 2 or main.state != "play":
		return
	var p2 = main.players[1]
	if not p2.is_local() or not p2.active or p2.home or p2.camera == null:
		return
	if fmod(t - 10.0, 12.0) < 2.0:
		var d: Vector2 = main.board.goal - Vector2(p2.lp.x, p2.lp.z)
		p2.yaw = atan2(d.x, d.y)
		p2.cam_idle_t = 0.0


## Picture cues instead of words; any instruction text in a tip spot is an error.
func _note_cues() -> void:
	var gh = main.ghost_hand
	if gh != null and gh.visible and gh.shown_hands:
		cues["ghost_hands"] = true
	if gh != null and gh.marble.visible:
		cues["ghost_marble"] = true
	for k in ["tilt_arrow", "goal_arrow", "grab_arrow"]:
		var n = main.get(k)
		if n != null and n.is_visible_in_tree():
			if not cues.has(k):
				print("BOT: %s glows (t=%.0f)" % [k, t])
			cues[k] = true
	if main.join_cue != null and main.join_cue.visible:
		cues["join_cue"] = true
	if not has_meta("pause_check") and t >= 25.0 and main.net.mode != "client" and not get_tree().paused:
		set_meta("pause_check", true)  # the pause banner is just PAUSED (no sentence)
		main._set_pause_banner(true, "A TV player opened the menu")
		var pt: String = main.center_label.text
		print("BOT: pause banner %s" % ("PAUSED" if pt == "PAUSED" else "ERROR: " + pt.replace("\n", " / ")))
		main._set_pause_banner(false, "")
	_test_plug()
	if main.center_label.modulate.a > 0.05:
		_check_headline("TV headline", main.center_label.text)
	if main.vr_center != null and main.vr_center.modulate.a > 0.05:
		_check_headline("VR headline", main.vr_center.text)
	if main.help_label.visible and main.help_label.modulate.a > 0.05 and main.help_label.text.strip_edges() != "":
		_tip_error("controls line", main.help_label.text)
	if main.vr_board != null and main.vr_board.visible and main.vr_board.text != "":
		_tip_error("VR scoreboard", main.vr_board.text)
	for p in main.players:
		if not p.active or not p.has_meta("view"):
			continue
		if p.hud_label != null and p.hud_label.is_visible_in_tree() and not HUD_WORDS.has(p.hud_label.text.strip_edges()):
			_tip_error("P%d HUD line" % (p.index + 1), p.hud_label.text)
		var edge = p.get_meta("edge") if p.has_meta("edge") else null
		if edge != null and edge.on:
			cues["edge_arrow"] = true
		var cue = p.get_meta("cue") if p.has_meta("cue") else null
		var key: String = p.get_meta("cue_key", "")
		if cue != null and cue.visible and key != "":
			if not cues.has("cue_" + key):
				print("BOT: P%d picture cue %s (t=%.0f)" % [p.index + 1, key, t])
			cues["cue_" + key] = true
	for p in main.players:
		var done: Dictionary = p.get_meta("cue_done", {})
		for k in done:
			if int(done[k]) >= 2 and not cues.has("cue_learned_" + str(k)):
				cues["cue_learned_" + str(k)] = true
				print("BOT: P%d learned %s (t=%.0f)" % [p.index + 1, k, t])
	if int(t) % 10 == 0 and cues.size() != int(get_meta("cues_shown", -1)):
		set_meta("cues_shown", cues.size())  # networked runs can end on a timeout: print the cues as they come
		var ks: Array = cues.keys()
		ks.sort()
		print("BOT CUES so far: mode=%s %s" % [main.net.mode, ",".join(PackedStringArray(ks))])


## Local mode: P3 (on fake controller 40) has its controller unplugged (bolt), then plugged back in.
func _test_plug() -> void:
	if main.net.mode != "local" or main.players.size() < 3:
		return
	var p3 = main.players[2]
	if plug_phase == 0 and t > 34.0 and p3.active and p3.joy == FAKE_PAD:
		plug_phase = 1
		set_meta("plug_t", t)
		print("BOT: unplugging P3's controller")
		main._on_joy_changed(FAKE_PAD, false)
	elif plug_phase == 1 and t >= float(get_meta("plug_t")) + 3.0:
		plug_phase = 2
		print("BOT: plugging P3's controller back in")
		main._on_joy_changed(FAKE_PAD, true)
		print("BOT: P3 joy=%d lost=%.1f active=%s" % [p3.joy, p3.pad_lost_t, p3.active])


func _check_headline(who: String, text: String) -> void:
	var tx := text.strip_edges()
	if WORDS.has(tx):
		return
	for n in main.board.levels().size():
		if tx == main.board.level_name(n + 1):
			return
	if tx == main.board.level_name(main.level) or tx == str(main.board.cur.get("name", "")):
		return
	_tip_error(who, tx)


func _tip_error(who: String, text: String) -> void:
	if not cues.has("tip_text"):
		print("BOT: ERROR instruction text on %s: %s" % [who, text.replace("\n", " / ")])
	cues["tip_text"] = true


func _exit_tree() -> void:
	if main != null and is_instance_valid(main) and main.simple:
		var ks: Array = cues.keys()
		ks.sort()
		print("BOT CUES: mode=%s %s" % [main.net.mode, ",".join(PackedStringArray(ks))])
		if main.save != null:
			var d: Dictionary = main.save.data
			print("BOT STORY: mode=%s level=%d desc=%s story_i=%d places=%d jar=%d lessons_done=%s town_lit=%d" % [main.net.mode,
				main.level, str(main.level_desc), int(d.story_i), int(d.places), (d.jar as Array).size(), d.lessons_done,
				main.town.lit if main.town != null else -1])
		for p in main.players:
			if p.has_meta("cue_done"):
				print("BOT CUES: P%d done=%s" % [p.index + 1, p.get_meta("cue_done")])
