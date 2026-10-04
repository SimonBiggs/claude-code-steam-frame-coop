extends Node
## Headless bot for Penalty Shootout. Every local striker picks a random corner, steers the reticle there
## with its (fake) stick, holds A until the meter reaches its chosen power (sometimes with curve) and lets
## go. The keeper (local / DUO_HOST) predicts where the ball will cross the line and, on most shots,
## shuffles and dives there. PS_FAKE_VR=1 (local): the keeper runs its VR code with bot-moved hands and
## the left stick, saving by touching the ball with a glove.
## BOT_PLAYERS=N: strikers to have (local split screen: up to 5 plus the keeper; TV machine: up to 6).
## Local mode shortens the group stage to 1 round (host: 2) and the cup final to 1 shot each, skips the intro, plays
## again at full time, joins one striker by pressing A on a fake controller and checks that Start does
## NOT join. Strikers mix normal shots, CHIPs (X) and their FIREBALL (Y); the keeper takes power-up
## bubbles (flat: automatic, fake VR: touches them with a glove).
## Real controllers are attached to this machine: their presses are swallowed (they must not pause
## or join the test), and if anything else pauses the game the bot resumes it.

const FAKE_PAD := 40

var main
var t := 0.0
var joined := false
var join_time := 0.0
var report_t := 0.0
var cont_t := 0.0
var plan_key := ""
var plan_aim := Vector2.ZERO
var plan_power := 0.5
var plan_curve := 0.0
var keep_key := ""
var keeper_try := true
var last_state := ""
var result_wait := -1.0
var results := {}
var last_round := 0
var rounds_done := 0
var matches_done := 0
var shots_fired := 0
var my_pause := false
var paused_t := 0.0
var shot_kinds := {}
var powers_seen := {}
var replays := 0
var finals := 0
var cups := []


class RealPadFilter extends Node:
	## Sits after the bot in the tree, so it sees input first: real controllers (device < 40) are ignored.
	func _input(event: InputEvent) -> void:
		var jb := event as InputEventJoypadButton
		var jm := event as InputEventJoypadMotion
		if (jb != null and jb.device < FAKE_PAD) or (jm != null and jm.device < FAKE_PAD):
			get_viewport().set_input_as_handled()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps running if the Start check opened the pause menu
	main = load("res://games/penalty_shootout/main.tscn").instantiate()
	add_child(main)
	var filt := RealPadFilter.new()
	filt.name = "RealPadFilter"
	filt.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child.call_deferred(filt)


## Something paused the game that wasn't us (a real controller's Start, a stray key): resume it.
func _unstick(delta: float) -> void:
	if not get_tree().paused or my_pause:
		paused_t = 0.0
		return
	paused_t += delta
	if paused_t < 1.0:
		return
	paused_t = 0.0
	print("BOT: the game was paused by something else (a real controller?) - resuming")
	for n in main.get_children():
		if n is CanvasLayer and n.get("panel") != null and n.has_method("_resume"):
			if n.panel.visible:
				n._resume()
	if get_tree().paused:
		get_tree().paused = false
		if main.net.mode == "client":
			main.net.send_action("pause", [false])
		else:
			main._set_pause_banner(false, "")


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
	_unstick(delta)
	if not joined and t > (3.0 if mode == "client" else 1.0):
		joined = true
		join_time = t
		_join_players(mode)
	if mode == "local" and joined and t > join_time + 0.3 and not has_meta("start_checked"):
		set_meta("start_checked", true)
		print("BOT: Start on a new controller: joined=%s, menu opened=%s" % [main.joy_owner.has(FAKE_PAD + 1), get_tree().paused])
		if get_tree().paused:
			_pad_press(FAKE_PAD + 1, JOY_BUTTON_START)  # close the menu again
		my_pause = false
	if get_tree().paused:
		return
	if has_meta("pad_join") and t > join_time + 0.5:
		remove_meta("pad_join")
		_pad_press(FAKE_PAD, JOY_BUTTON_A)
	if mode == "local" and joined and t > join_time + 0.8 and not has_meta("pad_checked"):
		set_meta("pad_checked", true)
		print("BOT: fake controller %d drives P%d, paused=%s" % [FAKE_PAD, int(main.joy_owner.get(FAKE_PAD, -1)) + 1, get_tree().paused])
	var st: String = main.state
	if mode == "local" and st == "intro" and main.rounds_total > 1:
		main.rounds_total = 1  # keep the headless match short
		main.final_shots = 1
	if mode == "host" and st == "intro" and main.rounds_total > 2:
		main.rounds_total = 2
		main.final_shots = 1
	if mode != "client" and st == "trophy" and main.state_t > 3.0 and main.state_t < 5.0:
		main.state_t = 99.0  # short runs: a quicker trophy ceremony
	if (st == "intro" and main.state_t > 2.0 and joined and t > join_time + 1.5) or (st == "over" and main.state_t > 2.5):
		cont_t -= delta
		if cont_t <= 0.0:
			cont_t = 1.0
			main.debug_continue()
	if main.replay_on and not has_meta("replay_%d" % main.shots_total):
		set_meta("replay_%d" % main.shots_total, true)
		replays += 1
		print("BOT %s: REPLAY of '%s'" % [mode, main.last_result])
	if main.keeper.power != "" and not powers_seen.has("%d/%s" % [main.turn_count, main.keeper.power]):
		powers_seen["%d/%s" % [main.turn_count, main.keeper.power]] = true
		print("BOT %s: keeper power-up %s" % [mode, main.keeper.power])
	if st != last_state:
		if st == "final_intro":
			finals += 1
			print("BOT %s: THE FINAL P%d vs P%d" % [mode, main.finalists[0] + 1, main.finalists[1] + 1])
		if st == "trophy":
			cups.append(main.champion)
			print("BOT %s: CUP WINNER %s" % [mode, "keeper" if main.champion == 0 else "P%d" % (main.champion + 1)])
		if st == "result":
			result_wait = 0.25
		if st == "over":
			matches_done += 1
			print("BOT %s: MATCH OVER (saves %d, goals %d, shots %d) awards: %s" % [mode, main.saves, main.goals_total, main.shots_total,
				str(main.get_meta("awards", "")).replace("\n", " | ")])
		if st == "flight":
			shots_fired += 1
			shot_kinds[main.last_shot] = int(shot_kinds.get(main.last_shot, 0)) + 1
		last_state = st
	if result_wait >= 0.0:
		result_wait -= delta
		if result_wait < 0.0:
			var r: String = main.last_result
			results[r] = int(results.get(r, 0)) + 1
			print("BOT %s: result #%d %s" % [mode, _count(), r])
	if main.round_i > last_round:
		rounds_done += main.round_i - last_round
		print("BOT %s: ROUND %d COMPLETE" % [mode, last_round + 1])
	last_round = main.round_i
	for i in range(1, main.players.size()):
		var p = main.players[i]
		if p.active and p.is_local():
			p.bot = true
			_drive_striker(p)
	if mode != "client":
		var k = main.keeper
		if k.vr:
			_drive_vr_keeper(k, delta)
		else:
			_drive_flat_keeper(k)
	report_t -= delta
	if report_t <= 0.0:
		report_t = 4.0
		_report(mode)


func _count() -> int:
	var n := 0
	for k in results:
		n += int(results[k])
	return n


func _join_players(mode: String) -> void:
	if mode == "host":
		return
	var want := int(OS.get_environment("BOT_PLAYERS")) if OS.has_environment("BOT_PLAYERS") else (2 if mode == "local" else 1)
	var cap := 5 if mode == "local" else 6
	var extra := clampi(want, 1, cap) - 1
	print("BOT: %s mode, joining %d extra strikers" % [mode, extra])
	if mode == "local":
		my_pause = true
		_pad_press(FAKE_PAD + 1, JOY_BUTTON_START)  # Start must open the menu, not join
		if extra > 0:
			set_meta("pad_join", true)  # A on the fake controller once the menu is closed again
			extra -= 1
	for i in extra:
		var p = main.debug_join()
		print("BOT: debug_join -> %s" % ("P%d" % (p.index + 1) if p != null else "none"))


func _drive_striker(p) -> void:
	if not main.is_turn_of(p):
		p.bot_hold = false
		p.bot_stick = Vector2.ZERO
		return
	var key := "%d/%d/%d" % [main.round_i, main.shooter, main.shots_total]
	if key != plan_key:
		plan_key = key
		plan_aim = Vector2(randf_range(-3.3, 3.3), randf_range(0.3, 2.2))
		plan_power = randf_range(0.45, 0.95)
		plan_curve = randf_range(-1.0, 1.0) if randf() < 0.4 else 0.0
		var r := randf()
		p.bot_shot = "fire" if (r < 0.3 and p.fire_left > 0) else ("chip" if r < 0.55 else "normal")
	var aim: Vector2 = p.aim
	var to := plan_aim - aim
	p.bot_stick = (to * 3.0).limit_length(1.0) if to.length() > 0.05 else Vector2.ZERO
	p.bot_curve = plan_curve
	if to.length() < 0.12 and main.can_shoot():
		if not p.charging:
			p.bot_hold = not p.bot_hold  # release for a frame, then press (a fresh press starts charging)
		elif p.power >= plan_power:
			p.bot_hold = false  # let go: shoot
		else:
			p.bot_hold = true
	else:
		p.bot_hold = false


## Where (and when) the ball will cross the plane z = plane_z, or [] if it isn't coming.
func _predict(plane_z: float) -> Array:
	var b = main.ball
	if main.state != "flight" or not b.live:
		return []
	var pos: Vector3 = b.position
	var v: Vector3 = b.vel
	if v.z > -0.5:
		return []
	var th := (pos.z - plane_z) / -v.z
	var a: Vector3 = b.acc if b.curve_on else Vector3.ZERO
	var p := pos + v * th + 0.5 * (Vector3(0, -9.8, 0) + a) * th * th
	return [p, th]


func _drive_flat_keeper(k) -> void:
	k.bot = true
	var key := "%d/%d" % [main.round_i, main.shots_total]
	if key != keep_key:
		keep_key = key
		keeper_try = randf() < 0.6
	var pr := _predict(0.6)
	if pr.is_empty() or not keeper_try:
		var kx: float = k.kx
		k.bot_move = -signf(kx) if absf(kx) > 0.2 else 0.0
		return
	var p: Vector3 = pr[0]
	var th: float = pr[1]
	var dx: float = p.x - float(k.kx)
	k.bot_move = signf(dx) if absf(dx) > 0.3 else 0.0
	if th < 0.38 and not k.is_diving():
		var d := Vector3(dx, p.y - 1.6, 0.0)
		if d.length() > 0.5:
			k.bot_dive = d.normalized()


func _drive_vr_keeper(k, delta: float) -> void:
	k.bot = true
	var key := "%d/%d" % [main.round_i, main.shots_total]
	if key != keep_key:
		keep_key = key
		keeper_try = randf() < 0.7
	var head: Vector3 = k.xr_camera.global_position
	var hr: Node3D = k.hand_r
	var hl: Node3D = k.hand_l
	if main.state == "aim" and k.bubble != "" and main.state_t > 0.6:
		# Touch the power-up bubble with the left glove.
		hl.global_position = hl.global_position.move_toward(k.bubble_pos, 3.0 * delta)
		return
	var pr := _predict(head.z + 0.35)
	if pr.is_empty() or not keeper_try:
		k.bot_stick = Vector2(signf(head.x), 0.0) if absf(head.x) > 0.3 else Vector2.ZERO  # facing +z: right is -x
		hr.global_position = hr.global_position.move_toward(head + Vector3(-0.3, -0.45, 0.3), 3.0 * delta)
		hl.global_position = hl.global_position.move_toward(head + Vector3(0.3, -0.45, 0.3), 3.0 * delta)
		return
	var p: Vector3 = pr[0]
	var th: float = pr[1]
	var dx := p.x - head.x
	k.bot_stick = Vector2(-signf(dx), 0.0) if absf(dx) > 0.6 else Vector2.ZERO
	if th < 0.8:
		var reach := head + (p - head).limit_length(0.85 * float(k.ws()))
		var hand: Node3D = hr if dx < 0.0 else hl
		hand.global_position = hand.global_position.move_toward(reach, 7.0 * delta)


func _report(mode: String) -> void:
	var act: Array[String] = []
	for p in main.players:
		if p.index > 0 and p.active:
			act.append("P%d:%dg/%ds" % [p.index + 1, p.goals, p.shots])
	var views := 0
	for p in main.players:
		if p.has_meta("view") and p.get_meta("view").visible:
			views += 1
	var kinfo := ""
	if main.keeper.vr:
		kinfo = " vr_scale=%.2f head=%s" % [main.keeper.ws(), str(main.keeper.head_pos.snapped(Vector3(0.01, 0.01, 0.01)))]
	print("BOT %s t=%.0f state=%s stage=%s round=%d/%d shooter=P%d saves=%d goals=%d shots=%d fired=%d kinds=%s replays=%d finals=%d cups=%s rounds_done=%d matches=%d views=%d results=%s [%s]%s" % [
		mode, t, main.state, main.cup_stage, main.round_i + 1, main.rounds_total, main.shooter + 1, main.saves, main.goals_total,
		main.shots_total, shots_fired, str(shot_kinds), replays, finals, str(cups), rounds_done, matches_done, views, str(results), ", ".join(act), kinfo])
