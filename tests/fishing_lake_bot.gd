extends Node
## Headless bot for Fishing Lake. The angler casts at the nearest fish, hooks on a bite, reels while
## the tension is safe, eases off while the fish surges and yanks when it's tired. Boats row to
## floating treasure and net it, or row to fish and call them to the bobber.
## BOT_PLAYERS=N: boats to have (local split screen: up to 5; TV machine: up to 6).
## BOT_ROUND=s: day length in seconds (default 30, so a whole day fits in the test).
## BOT_VR=1 (local / host): fake VR - the angler's real VR code is driven by moving fake hands:
## flick casts, yanks on the bite, and winding the left hand around the reel.
## BOT_GREEDY=1: the angler never eases off (exercises line snaps).
## Local mode also joins one boat by pressing A on a fake controller, and checks Start does NOT join.

const FAKE_PAD := 40

var main
var t := 0.0
var joined := false
var report_t := 0.0
var cont_t := 0.0
var join_time := 0.0
var last_day := 1
var days_done := 0
var frame := 0
var max_score := 0
# fake VR
var vr_phase := "idle"
var vr_t := 0.0
var pitch := 0.3
var aim := 0.0
var crank_a := 0.0
var flicks := 0
var max_crank := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps running if the Start check opened the pause menu
	main = load("res://games/fishing_lake/main.tscn").instantiate()
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
	frame += 1
	if main == null or not main.ready_to_play:
		return
	var mode: String = main.net.mode
	if not joined and t > (3.0 if mode == "client" else 1.0):
		joined = true
		join_time = t
		_join_players(mode)
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
	if mode != "client" and not has_meta("short_day"):
		set_meta("short_day", true)
		var rt := float(OS.get_environment("BOT_ROUND")) if OS.has_environment("BOT_ROUND") else 30.0
		main.round_time = rt
		main.time_left = minf(main.time_left, rt)
		print("BOT: day length set to %.0f s" % rt)
	if main.day > last_day:
		days_done += main.day - last_day
		print("BOT: day %d complete (%d so far)" % [last_day, days_done])
	last_day = main.day
	max_score = maxi(max_score, main.score)
	for p in main.players:
		if p.index > 0 and p.active and p.is_local():
			_drive_boat(p)
	var a = main.players[0]
	if a.is_local():
		if a.fake_vr:
			_drive_fake_vr(a, delta)
		elif not a.vr:
			_drive_angler(a)
	if main.state == "over" and main.state_t > 2.0:
		cont_t -= delta
		if cont_t <= 0.0:
			cont_t = 1.0
			main.debug_continue()
	report_t -= delta
	if report_t <= 0.0:
		report_t = 4.0
		_report(mode)


func _join_players(mode: String) -> void:
	if mode == "host":
		return
	var want := int(OS.get_environment("BOT_PLAYERS")) if OS.has_environment("BOT_PLAYERS") else (2 if mode == "local" else 1)
	var cap := 5 if mode == "local" else 6
	var extra := clampi(want, 1, cap) - 1
	print("BOT: %s mode, joining %d extra boats" % [mode, extra])
	if mode == "local":
		_pad_press(FAKE_PAD + 1, JOY_BUTTON_START)  # Start must open the menu, not join
		if extra > 0:
			set_meta("pad_join", true)  # A on the fake controller once the menu is closed again
			extra -= 1
	for i in extra:
		var p = main.debug_join()
		print("BOT: debug_join -> %s" % ("P%d" % (p.index + 1) if p != null else "none"))


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _target_fish(from: Vector3):
	var best = null
	var best_d := 18.0
	for f in main.fish:
		if f.kind < 0 or f.is_junk() or not f.free_to_bite():
			continue
		var d := _flat(f.position - from).length()
		if f.called_t > 0.0:
			d -= 8.0
		if d < best_d and d > 4.0:
			best_d = d
			best = f
	return best


func _drive_angler(a) -> void:
	a.bot = true
	a.bot_reel = 0.0
	match str(a.line_state):
		"ready":
			if a.cast_cool <= 0.0 and main.state == "play":
				var tip: Vector3 = a.tip_pos()
				var f = _target_fish(tip)
				var to := Vector3(0, 0, -10)
				if f != null:
					to = _flat(f.position - tip)
				a.bot_cast_dir = to.normalized()
				a.bot_cast_dist = clampf(to.length(), 5.0, 18.0)
		"waiting":
			a.bot_reel = 0.35 if fmod(t, 6.0) < 0.3 else 0.0  # a little twitch now and then
		"bite":
			a.bot_reel = 1.0
		"fight":
			if OS.has_environment("BOT_GREEDY"):
				a.bot_reel = 1.0  # always reel flat out: big fish snap the line
			elif a.surge:
				a.bot_reel = 0.0 if a.tension > 0.45 else 0.3
			else:
				a.bot_reel = 1.0 if a.tension < 0.8 else 0.0
				if a.yank_cool <= 0.0 and frame % 50 == 0:
					a.bot_yank = true


## Fake VR: move the fake right hand (rod) and left hand like a player would.
func _drive_fake_vr(a, delta: float) -> void:
	vr_t += delta
	var hr: Node3D = a.hand_r
	var hl: Node3D = a.hand_l
	var rest_l := Vector3(-0.3, 1.0, -0.15)
	var want_crank := false
	a.fake_trigger = 0.0
	match str(a.line_state):
		"ready":
			if main.state != "play" or a.cast_cool > 0.0:
				vr_phase = "idle"
			elif vr_phase == "idle":
				var f = _target_fish(a.tip_pos())
				if f != null:
					var to := _flat(f.position - hr.global_position)
					aim = atan2(-to.x, -to.z)
				else:
					aim = 0.0
				vr_phase = "raise"
				vr_t = 0.0
			if vr_phase == "raise":
				pitch = lerpf(pitch, 1.1, 1.0 - exp(-6.0 * delta))
				if vr_t > 0.6:
					vr_phase = "flick"
					vr_t = 0.0
					flicks += 1
			elif vr_phase == "flick":
				pitch = lerpf(1.1, -0.3, clampf(vr_t / 0.2, 0.0, 1.0))
				if vr_t > 0.5:
					vr_phase = "idle"
		"flying", "waiting":
			vr_phase = "idle"
			pitch = lerpf(pitch, 0.3, 1.0 - exp(-1.2 * delta))
		"bite":
			if vr_phase != "yank":
				vr_phase = "yank"
				vr_t = 0.0
			pitch = lerpf(0.3, 1.2, clampf(vr_t / 0.12, 0.0, 1.0))
		"fight":
			if vr_phase == "yank" and vr_t > 0.3:
				vr_phase = "fight"
			if vr_phase == "yank":
				pitch = lerpf(pitch, 1.2, 0.5)
			else:
				vr_phase = "fight"
				pitch = lerpf(pitch, 0.6, 1.0 - exp(-2.0 * delta))
				if a.surge:
					want_crank = a.tension < 0.4
				else:
					want_crank = a.tension < 0.8
					if a.yank_cool <= 0.0 and frame % 70 == 0:
						vr_phase = "yank"
						vr_t = 0.0
						pitch = 0.4
			if vr_phase == "yank":
				pitch = lerpf(0.4, 1.1, clampf(vr_t / 0.12, 0.0, 1.0))
		_:
			pitch = lerpf(pitch, 0.5, 1.0 - exp(-3.0 * delta))
	hr.position = Vector3(0.25, 1.15, -0.35)
	hr.rotation = Vector3(pitch, aim, 0.0)
	if want_crank:
		crank_a += delta * 10.0
		var rb: Basis = a.rod_root.global_basis
		var off: Vector3 = rb.y.normalized() * cos(crank_a) * 0.07 + rb.z.normalized() * sin(crank_a) * 0.07
		hl.global_position = a.reel_world() + off + rb.x.normalized() * -0.04
	else:
		hl.position = hl.position.lerp(rest_l, 1.0 - exp(-10.0 * delta))
	max_crank = maxf(max_crank, a.crank)


func _drive_boat(p) -> void:
	p.bot = true
	var tgt := Vector3.ZERO
	var has_tgt := false
	var want_net := false
	var want_call := false
	var best_d := 1e9
	for tr in main.treasures:
		if tr.kind < 0:
			continue
		var d := _flat(tr.position - p.position).length()
		if d < best_d:
			best_d = d
			tgt = tr.position
			has_tgt = true
	if has_tgt:
		var np: Vector3 = p.net_point()
		if _flat(tgt - np).length() < 1.3:
			want_net = true
		# Aim the bow at the treasure, so the net reaches it.
		tgt = tgt - _flat(tgt - p.position).normalized() * 0.2
	elif main.lure_in_water():
		var lure: Vector3 = main.lure_position()
		var f = _target_fish(lure)
		if f != null:
			tgt = f.position + _flat(f.position - lure).normalized() * 2.5  # get behind it, push it to the bobber
			has_tgt = true
			if _flat(f.position - p.position).length() < 9.0:
				want_call = true
	if not has_tgt:
		var a: float = t * 0.2 + p.index
		tgt = Vector3(sin(a) * 9.0, 0.0, -10.0 + cos(a) * 9.0)
	var to := _flat(tgt - p.position)
	p.bot_dir = to.normalized() * clampf(to.length() / 2.0, 0.3, 1.0) if to.length() > 0.3 else Vector3.ZERO
	p.bot_net = want_net and frame % 4 < 2
	p.bot_call = want_call and frame % 30 == 0


func _report(mode: String) -> void:
	var a = main.players[0]
	var boats: Array[String] = []
	var scooped := 0
	var calls := 0
	var synced := 0
	for p in main.players:
		if p.index > 0 and p.active:
			boats.append("P%d@%.0f,%.0f" % [p.index + 1, p.position.x, p.position.z])
			scooped += p.scooped
			calls += p.calls
			if p.remote and p.net_started:
				synced += 1
	var views := 0
	for p in main.players:
		if p.has_meta("view") and p.get_meta("view").visible:
			views += 1
	var tr := 0
	for x in main.treasures:
		if x.kind >= 0:
			tr += 1
	print("BOT %s t=%.0f day=%d state=%s time=%.0f score=%d/%d line=%s tension=%.2f casts=%d catches=%d(%d) snaps=%d fish=%d treasure=%d scooped=%d calls=%d views=%d remote_synced=%d%s [%s]" % [
		mode, t, main.day, main.state, main.time_left, main.score, main.target, a.line_state, a.tension, a.casts,
		a.catches, main.catches.size(), a.snaps, main.fish_count(), tr, scooped, calls, views, synced,
		(" flicks=%d max_crank=%.2f" % [flicks, max_crank]) if a.fake_vr else "", ", ".join(boats)])


func _exit_tree() -> void:
	if main == null:
		return
	var a = main.players[0] if main.players.size() > 0 else null
	if a == null:
		return
	print("BOT SUMMARY: mode=%s days_completed=%d max_score=%d casts=%d catches=%d snaps=%d" % [
		main.net.mode, days_done, max_score, a.casts, a.catches, a.snaps])
