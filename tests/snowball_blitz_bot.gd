extends Node
## Headless bot for Snowball Blitz. The first local player snipes the nearest snowman with charged
## lobs; the second local player packs the most damaged fort wall (and throws when the fort is fine).
## On the client it also wakes player 3 by "pressing" throw.
## Local / host also exercise the new content: bunny, balloon and shield snowmen, every fort upgrade, a
## MEGA SNOWBALL throw and the weather (blizzard, sunshine, cocoa party); the game-over screen prints the
## awards. BOT_WAVE=N jumps to wave N (12 = the YETI finale), BOT_GOD=1 keeps everyone warm and the fort
## standing, BOT_VR=1 (local) makes P1 the real VR thrower with fake hands (squeeze, swing, release).
## SIMPLE_MODE (main.simple): no packing / weather / upgrades; the bot checks target practice ends, the
## waves bring one new kind at a time, and (BOT_VR) touches every prop and throws a snapped-off icicle.

var main
var t := 0.0
var next_report := 0.0
var cycle := {}  # player index -> seconds into the current charge/throw cycle
## BOT_PLAYERS=N: N TV players join programmatically (main.debug_join), like N controllers pressing A.
var bot_players: int = int(OS.get_environment("BOT_PLAYERS")) if OS.has_environment("BOT_PLAYERS") else 0
var join_t := 1.0
var script_step := 0
var vr_t := 0.0
var vr_throws := 0


func _ready() -> void:
	if Engine.has_meta("sb_bot_restarts"):
		print("Bot: game restarted")
		var up := InputEventKey.new()
		up.physical_keycode = KEY_ENTER
		up.pressed = false
		Input.parse_input_event(up)
	main = load("res://games/snowball_blitz/main.tscn").instantiate()
	add_child(main)


func _physics_process(delta: float) -> void:
	t += delta
	if not main.ready_to_play:
		return
	if bot_players > 0 and t >= join_t:
		join_t = t + 1.0
		var n := 0
		for p in main.players:
			if p.ghost or p.remote or p.vr:
				continue
			n += 1
			if n <= bot_players and not p.active:
				print("Bot: P%d joins" % (p.index + 1))
				main.debug_join(p.index)
	for p in main.players:
		if p.ghost or p.remote:
			continue
		if p.vr:
			_drive_vr(p, delta)
			continue
		if not p.active:
			p.bot_throw = bot_players == 0 and t > 4.0 and fmod(t, 2.0) < 0.3
			continue
		if p.index == 1 and not main.simple and _repair_role(p):
			continue
		_throw_role(p, delta)
	if main.net.mode != "client":
		_content_script()
		if OS.has_environment("BOT_GOD"):
			for p in main.players:
				p.invuln_t = 1.0
				p.hp = maxf(p.hp, 60.0)
			for i in main.segments:
				main.seg_hp[i] = maxf(main.seg_hp[i], 40.0)
	if main.game_over and not has_meta("over_print"):
		set_meta("over_print", true)
		print("Bot: end screen:\n%s" % main.center_label.text)
	_pad_test()
	_check_restart()
	if t >= next_report:
		next_report += 5.0
		_report()


## New snowmen, upgrades, a mega throw and the weather, once each.
func _content_script() -> void:
	if main.simple:
		_simple_script()
		return
	var steps := [
		[1.5, func() -> void:
			if OS.has_environment("BOT_WAVE"):
				main.debug_skip_to_wave(int(OS.get_environment("BOT_WAVE")))
				print("Bot: skip to wave %s" % OS.get_environment("BOT_WAVE"))],
		[4.0, func() -> void:
			for k in ["bunny", "balloon", "shield"]:
				main.debug_spawn(k)
			print("Bot: spawned bunny, balloon, shield")],
		[8.0, func() -> void: main.debug_event("blizzard")],
		[12.0, func() -> void:
			main.debug_upgrades()
			main.players[0].mega = true
			print("Bot: every fort upgrade + a mega snowball for P1")],
		[24.0, func() -> void: main.debug_event("sunshine")],
		[36.0, func() -> void: main.debug_event("cocoa")],
		[float(OS.get_environment("BOT_END")) if OS.has_environment("BOT_END") else 56.0, func() -> void:
			if not main.game_over:
				print("Bot: forcing game over to show the awards")
				main._on_game_over("TIME FOR COCOA!")],
	]
	while script_step < steps.size() and t >= float(steps[script_step][0]):
		var f: Callable = steps[script_step][1]
		f.call()
		script_step += 1


var practice_seen := false
var kinds_seen := {}
## Simple mode: skip ahead if asked, note when practice ends and which kinds each wave brings,
## a MEGA SNOWBALL for P1, then the game-over screen (which restarts by itself).
func _simple_script() -> void:
	if script_step == 0 and t >= 1.5:
		script_step = 1
		if OS.has_environment("BOT_WAVE"):
			main.debug_skip_to_wave(int(OS.get_environment("BOT_WAVE")))
			print("Bot: skip to wave %s" % OS.get_environment("BOT_WAVE"))
	if main.practice:
		practice_seen = true
	elif practice_seen and not has_meta("practice_done"):
		set_meta("practice_done", true)
		print("Bot: practice over at t=%.1f (VR hits %d)" % [t, main.vr_hits])
	for s in get_tree().get_nodes_in_group("snowmen"):
		var key := "%s" % s.kind
		if not kinds_seen.has(key):
			kinds_seen[key] = main.wave
			print("Bot: first %s in wave %d" % [s.kind, main.wave])
	if script_step == 1 and t >= 20.0:
		script_step = 2
		main.players[0].mega = true
		print("Bot: a mega snowball for P1")
	var end_t: float = float(OS.get_environment("BOT_END")) if OS.has_environment("BOT_END") else 56.0
	if script_step == 2 and t >= end_t:
		script_step = 3
		if not main.game_over:
			print("Bot: forcing game over")
			main._on_game_over("TIME FOR COCOA!")


## BOT_VR + simple mode: the left hand touches every prop in turn; the right hand snaps off an icicle.
func _touch_props(p) -> bool:
	if main.props == null or t < 2.0 or t > 9.5:
		return false
	var pr = main.props
	var spots := [pr.bell_pivot.global_position + Vector3(0, -0.13, 0), pr.icicles[0].node.global_position,
		pr.tree.global_position + Vector3(0, 0.9, 0), pr.sled_pos + Vector3(0, 0.1, 0), pr.piles[0].node.global_position,
		main.seg_center(0) + Vector3(0, 0.8, 0)]
	var i := int((t - 2.0) / 1.0)
	if i < spots.size():
		p.hand_l.global_position = spots[i]
		return false
	p.hand_l.position = Vector3(-0.25, 1.1, -0.3)
	# 8.0-9.5 s: the right hand goes to an icicle, squeezes, and the normal throw loop takes over.
	var ic: Vector3 = pr.icicles[2].node.global_position
	if t < 8.2:
		p.bot_squeeze = 0.0
		p.hand_r.global_position = ic
		return true
	if t < 8.5:
		p.bot_squeeze = 1.0
		p.hand_r.global_position = ic
		if p.held_icicle and not has_meta("icicle"):
			set_meta("icicle", true)
			print("Bot VR: snapped off an icicle")
		return true
	return false


## BOT_VR: squeeze the fake trigger, swing the hand towards the nearest snowman, let go.
func _drive_vr(p, delta: float) -> void:
	if main.simple and _touch_props(p):
		return
	if main.simple and main.practice and t < 4.5:
		p.bot_squeeze = 0.0  # stand still for a moment: the ghost hand shows how to throw
		if main.ghost_hand != null and main.ghost_hand.visible and not has_meta("ghost_seen"):
			set_meta("ghost_seen", true)
			print("Bot VR: the ghost hand is showing scoop-and-throw")
		return
	vr_t += delta
	var best = null
	var best_d := INF
	for s in get_tree().get_nodes_in_group("snowmen"):
		var dd: float = s.global_position.distance_to(p.global_position)
		if dd < best_d:
			best_d = dd
			best = s
	if best == null:
		p.bot_squeeze = 0.0
		return
	var to: Vector3 = best.global_position - p.global_position
	to.y = 0.0
	if to.length() > 0.1:
		p.xr_origin.global_basis = Basis(Vector3.UP, atan2(-to.x, -to.z))
	var c := fmod(vr_t, 1.2)
	if c < 0.5:
		p.bot_squeeze = 1.0
		p.hand_r.position = Vector3(0.3, 1.3, 0.25)  # wind up behind the shoulder
	elif c < 0.62:
		p.bot_squeeze = 1.0
		var k := (c - 0.5) / 0.12
		p.hand_r.position = Vector3(0.3, 1.3 + k * 0.3, 0.25 - k * 0.9)  # swing forward
	else:
		if p.bot_squeeze > 0.0:
			vr_throws += 1
			if vr_throws % 5 == 1:
				print("Bot VR: throw %d" % vr_throws)
		p.bot_squeeze = 0.0


func _report() -> void:
	var ps: Array[String] = []
	for p in main.players:
		ps.append("P%d%s hp=%d%s%s" % [p.index + 1, "" if p.active else "(idle)", int(p.hp), " DOWN" if p.is_down else "",
			" repairing" if p.repairing else ""])
	if main.view_grid:
		print("Bot: views grid columns=%d shown=%d" % [main.view_grid.columns, main.view_grid.get_children().filter(func(c): return c.visible).size()])
	var kinds := {}
	for s in get_tree().get_nodes_in_group("snowmen"):
		kinds[s.kind] = int(kinds.get(s.kind, 0)) + 1
	var d = main.director()
	if main.simple:
		print("Bot:   simple practice=%s vr_hits=%d props=%s ghost_hand=%s" % [main.practice, main.vr_hits,
			main.props.touched if main.props else {}, main.ghost_hand != null and main.ghost_hand.visible])
	print("Bot:   kinds=%s event=%s upgrades=%s won=%s night=%.2f boss=%s" % [kinds, d.event_name, d.upgrades, d.won, d.night, main.boss_text()])
	print("t=%.0f mode=%s playing=%d wave=%d score=%d fort=%d%% snowmen=%d cocoa=%d balls=%d over=%s | %s" % [t, main.net.mode, main.party_size(), main.wave, main.score,
		int(main.fort_fraction() * 100.0), get_tree().get_nodes_in_group("snowmen").size(), get_tree().get_nodes_in_group("cocoa").size(),
		main.get_children().filter(func(c): return c.get("spin") != null).size(), main.game_over, ", ".join(ps)])


## Walk to the most damaged wall and pack it. Returns false when nothing needs packing.
func _repair_role(p) -> bool:
	var worst := -1
	var worst_hp := 75.0
	for i in main.segments:
		if main.seg_hp[i] < worst_hp:
			worst_hp = main.seg_hp[i]
			worst = i
	if worst < 0 and not p.repairing:
		p.bot_repair = false
		p.bot_move = Vector3.ZERO
		return false
	if worst < 0:
		worst = p.repair_seg
	var spot: Vector3 = main.seg_center(worst) * ((main.fort_r - 1.1) / main.fort_r)
	var to: Vector3 = spot - p.global_position
	to.y = 0.0
	p.bot_throw = false
	if to.length() > 0.5:
		p.bot_move = to.normalized()
		p.bot_repair = false
	else:
		p.bot_move = Vector3.ZERO
		p.bot_repair = main.seg_hp[worst] < main.seg_max
		p.yaw = atan2(-(main.seg_center(worst) - p.global_position).x, -(main.seg_center(worst) - p.global_position).z)
	return true


func _throw_role(p, delta: float) -> void:
	p.bot_repair = false
	p.bot_move = Vector3.ZERO
	var best = null
	var best_d := INF
	for s in get_tree().get_nodes_in_group("snowmen"):
		if s.kind == "target" and not s.has_meta("tv") and main.net.mode != "client":
			continue  # the VR player's practice target
		var dd: float = s.global_position.distance_to(p.global_position)
		if dd < best_d:
			best_d = dd
			best = s
	var c: float = cycle.get(p.index, 0.0) + delta
	cycle[p.index] = c
	if best == null:
		p.bot_throw = false
		return
	var target: Vector3 = best.global_position + Vector3.UP * best.height * 0.45
	var eye: Vector3 = p.global_position + Vector3.UP * 1.5
	var flat := Vector2(target.x - eye.x, target.z - eye.z)
	p.yaw = atan2(-flat.x, -flat.y)
	p.pitch = _solve_pitch(flat.length(), target.y - eye.y, 17.7 if main.simple else 24.0)
	# Hold for a full charge, then release.
	p.bot_throw = c < 1.0
	if c > 1.15:
		cycle[p.index] = 0.0


## Pitch that lands a full-charge throw at horizontal distance dist and height dy (numeric search).
func _solve_pitch(dist: float, dy: float, speed: float) -> float:
	var best := 0.0
	var best_err := INF
	for k in 40:
		var pitch := -0.4 + k * 0.03
		var v := Vector2(cos(pitch) * speed, sin(pitch) * speed + 1.5)
		var x := 0.5 * cos(pitch)
		var y := 0.5 * sin(pitch)
		var err := INF
		for i in 200:
			v.y -= main.gravity * 0.02
			x += v.x * 0.02
			y += v.y * 0.02
			if x >= dist:
				err = absf(y - dy)
				break
			if y < -2.0:
				break
		if err < best_err:
			best_err = err
			best = pitch
	return best


var over_t := 0.0
## After a game over, press Enter (once per run) to check that restarting works.
func _check_restart() -> void:
	if not main.game_over:
		over_t = 0.0
		return
	over_t += get_physics_process_delta_time()
	var restarts: int = Engine.get_meta("sb_bot_restarts", 0)
	if restarts >= 1 or over_t < 3.0:
		return
	Engine.set_meta("sb_bot_restarts", restarts + 1)
	print("Bot: pressing Enter to restart")
	if true:
		var e := InputEventKey.new()
		e.physical_keycode = KEY_ENTER
		e.pressed = true
		Input.parse_input_event(e)


## BOT_PAD_TEST=1: a new controller (device 7) presses A to join, unplugs (leaves), plugs back in (rejoins).
var pad_step := 0
func _pad_test() -> void:
	if not OS.has_environment("BOT_PAD_TEST") or main.net.mode == "host":
		return
	if pad_step == 0 and t > 6.0:
		pad_step = 1
		var e := InputEventJoypadButton.new()
		e.device = 7
		e.button_index = JOY_BUTTON_A
		e.pressed = true
		Input.parse_input_event(e)
		print("Bot: controller 7 pressed A")
	elif pad_step == 1 and t > 9.0:
		pad_step = 2
		print("Bot: controller 7 unplugged")
		main._on_joy_changed(7, false)
	elif pad_step == 2 and t > 12.0:
		pad_step = 3
		print("Bot: controller 7 plugged back in")
		main._on_joy_changed(7, true)
	elif pad_step == 3 and t > 14.0:
		pad_step = 4
		var owner = main._player_with_pad(7)
		print("Bot: pad test done, controller 7 -> P%d active=%s, playing=%d" % [owner.index + 1 if owner else 0, owner.active if owner else false, main.party_size()])
