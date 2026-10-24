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
## SIMPLE_MODE (main.simple): instead of the content / spook scripts, the bot checks the practice (sleepy
## ghosts for the lantern, a glowing ghost per TV player, the VR ghost hand), touches every prop (VR:
## with the fake left hand), makes one ghost float away, and that nothing ever ends the game.
## Visual teaching (simple mode): records the picture cues each TV view shows (cue_vac, cue_turn,
## cue_shine, cue_plug), the ones learned (cue_learned_*), the glowing edge arrow, the practice arrow
## above the sleepy ghost, the VR ghost hand and the join cue; checks the pause banner is just PAUSED,
## and prints "BOT: ERROR instruction text" if a headline (TV or VR) is anything but a short title, or a
## tip spot (a view's hint line or corner, the controls line, the top line, the join line) shows words.
## P2 looks away now and then (to see the turn cue); local mode unplugs and replugs P2's (fake)
## controller to see the bolt.
var main
var t := 0.0
var last_print := -100.0
var bell_t := 7.0
var bot_players := int(OS.get_environment("BOT_PLAYERS")) if OS.has_environment("BOT_PLAYERS") else 0
var script_step := 0
var god := OS.has_environment("BOT_GOD")
var simple := false
var saw_hand := false
var saw_sleepy := false
var saw_glowy := false
var prop_i := 0
var prop_t := 0.0
var cues := {}  # simple mode: picture cues seen / learned
const HEADLINES := "^(GHOST LANTERN|NIGHT \\d+|HOORAY!|GOOD MORNING!|GHOST KING!|PLAYER \\d+!|HELLO!|PAUSED|Connecting to the lantern-bearer…)$"
var headline_re := RegEx.create_from_string(HEADLINES)
var plug_phase := 0


func _ready() -> void:
	main = load("res://games/ghost_lantern/main.tscn").instantiate()
	add_child(main)
	simple = main.simple
	_press(KEY_ENTER, true)  # P2 vacuum (and restart after game over)
	if not OS.has_environment("DUO_JOIN"):
		_press(KEY_SPACE, true)  # P1 focuses the lantern


func _press(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _nearest_ghost(pos: Vector3, kind: String = ""):
	var best = null
	var best_d := INF
	for g in get_tree().get_nodes_in_group("ghosts"):
		if kind != "" and g.kind != kind:
			continue
		if has_meta("float") and not has_meta("float_seen") and g == get_meta("float"):
			continue  # leave the ghost that should float away alone (or P2 vacuums it first)
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
	if simple:
		_simple_checks(delta)
	if mode != "client" and not simple:
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
	if mode != "client" and t > down_at and not has_meta("spooked") and not god and not simple:
		set_meta("spooked", true)
		print("BOT: spooking player 2 until they're down")
		for i in 3:
			main.players[1].invuln_t = 0.0
			main.spook_player(main.players[1], p1)
	if mode == "local" and has_meta("spooked") and main.players[1].is_down and t < down_at + 6.0:
		p1.global_position = main.players[1].global_position + Vector3(1.0, 0.0, 0.0)  # cheer them up
		return
	if mode != "client" and t > over_at and not main.game_over and not god and not simple:
		print("BOT: spooking everyone to test game over + restart")
		for p in main.players:
			for i in 4:
				p.invuln_t = 0.0
				p.spook(40.0, p.global_position)
	if p1.vr and not p1.is_down:
		# BOT_VR: point the lantern hand at the ghost nearest P2, walk the play space there, and shake
		# the left hand now and then to ring the bell.
		var vg = _nearest_ghost(p1.global_position, "sleepy")
		if vg == null:
			vg = _nearest_ghost(main.players[1].global_position)
		if vg and simple and vg.kind == "sleepy" and not saw_hand:
			vg = null  # simple: look away first so the practice ghost hand shows how
			p1.hand_r.global_basis = Basis(Vector3.UP, PI)
		if vg:
			p1.hand_r.global_basis = Basis.looking_at((vg.global_position - p1.hand_r.global_position).normalized(), Vector3.UP)
			var to: Vector3 = vg.global_position - p1.global_position
			to.y = 0.0
			if to.length() > 5.0:
				p1.xr_origin.global_position += to.normalized() * 3.0 * delta
		var shaking := fmod(t, 9.0) < 1.0
		if not (simple and prop_t > 0.0):
			p1.hand_l.position = Vector3(-0.25 + (sin(t * 30.0) * 0.12 if shaking else 0.0), 1.1, -0.3)
	elif not p1.ghost and not p1.remote and not p1.is_down:
		var g = _nearest_ghost(p1.global_position, "sleepy")
		if g == null:
			g = _nearest_ghost(main.players[1].global_position)
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
	if simple:
		_look_away()
		_note_cues()
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


## Simple mode: practice, props, a ghost floating away, no game over.
func _simple_checks(delta: float) -> void:
	var mode: String = main.net.mode
	for g in get_tree().get_nodes_in_group("ghosts"):
		if g.kind == "sleepy":
			saw_sleepy = true
		elif g.kind == "glowy":
			saw_glowy = true
	if main.ghost_hand != null and main.ghost_hand.visible:
		saw_hand = true
	if main.game_over:
		print("BOT: FAIL simple mode reached game over")
	if mode == "client":
		if t > 30.0 and not has_meta("client_report"):
			set_meta("client_report", true)
			print("BOT: client simple: practice=%s saw_glowy=%s tv_caught=%s night=%d caught=%d" % [main.practice, saw_glowy, main.tv_caught.keys(), main.night, main.caught])
		return
	var p1 = main.players[0]
	if OS.has_environment("BOT_NIGHT") and t > 1.5 and not has_meta("skipped"):
		set_meta("skipped", true)
		main.debug_skip_to_night(int(OS.get_environment("BOT_NIGHT")))
		print("BOT: skip to night %s" % OS.get_environment("BOT_NIGHT"))
	if t - last_print < 0.02 and fmod(t, 5.0) < 0.1:
		print("BOT   simple: dawn=%.2f won=%s kinds=%s" % [main.director().dawn, main.director().won, _kinds()])
	# Touch every prop once practice is over (VR: with the fake left hand; flat: P2 bumps the floor spots).
	if not main.practice and main.props != null and t > 20.0:
		var names: Array = main.props.TOUCH.keys()
		if prop_i < names.size():
			prop_t += delta
			var n: String = names[prop_i]
			var d: Array = main.props.TOUCH[n]
			if p1.vr:
				p1.hand_l.global_position = d[0]
			elif d[2] != null:
				main.players[1].global_position = d[2]
			elif not main.props.touched.has(n):
				main.props.touch(n)
			if prop_t > 0.5:
				prop_t = 0.0
				prop_i += 1
				if prop_i >= names.size():
					prop_t = 0.0
					print("BOT: props touched %s" % main.props.touched)
	if not main.practice and t > 40.0 and not has_meta("float"):
		for g in get_tree().get_nodes_in_group("ghosts"):
			if g.kind != "golden" and g.kind != "king":
				set_meta("float", g)
				g.life_t = 999.0
				print("BOT: ghost %d should giggle and float away" % g.net_id)
				break
	if has_meta("float") and not has_meta("float_seen"):
		var fg = get_meta("float")
		if is_instance_valid(fg) and not fg.leaving:
			fg.stun_t = 0.0  # (the lantern / a vacuum near it kept it dizzy, so it never set off)
			fg.capture = 0.0
		if is_instance_valid(fg) and fg.leaving:
			set_meta("float_seen", true)
			print("BOT: ghost %d is giggling off through the ceiling" % fg.net_id)
	if t > 55.0 and not has_meta("report"):
		set_meta("report", true)
		var practiced: bool = OS.has_environment("BOT_NIGHT") or (saw_sleepy and main.vr_woken >= main.VR_PRACTICE)
		var ok: bool = practiced and not main.practice and main.night >= 1 and has_meta("float_seen") \
			and main.caught > 0 and not main.game_over and main.props.touched.size() >= 5
		if (mode == "local" or main.net.connected) and not OS.has_environment("BOT_NIGHT"):
			ok = ok and saw_glowy
		if p1.vr and not OS.has_environment("BOT_NIGHT"):
			ok = ok and saw_hand and main.props.touched.size() >= main.props.TOUCH.size()
		print("BOT: SIMPLE %s practice_done=%s woken=%d saw_sleepy=%s saw_glowy=%s hand=%s tv_caught=%s night=%d caught=%d props=%s" % [
			"OK" if ok else "FAIL", not main.practice, main.vr_woken, saw_sleepy, saw_glowy, saw_hand, main.tv_caught.keys(),
			main.night, main.caught, main.props.touched])


func _kinds() -> Dictionary:
	var kinds := {}
	for g in get_tree().get_nodes_in_group("ghosts"):
		kinds[g.kind] = int(kinds.get(g.kind, 0)) + 1
	return kinds


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


# --- Visual teaching checks (simple mode) -----------------------------------------

## P2 turns its back on the ghosts for a moment now and then, so the turn cue (and edge arrow) shows.
func _look_away() -> void:
	if t < 22.0 or main.players.size() < 2:
		return
	var p2 = main.players[1]
	if p2.remote or p2.ghost or not p2.active:
		return
	if fmod(t - 22.0, 9.0) < 2.5:
		p2.yaw += PI


## Picture cues instead of words; any instruction text in a tip spot is an error.
func _note_cues() -> void:
	if main.ghost_hand != null and main.ghost_hand.visible:
		cues["ghost_hand"] = true
	if main.practice_arrow != null and main.practice_arrow.visible:
		cues["practice_arrow"] = true
	if main.join_cue != null and main.join_cue.visible:
		cues["join_cue"] = true
	if not has_meta("pause_check") and t >= 30.0 and main.net.mode != "client":
		set_meta("pause_check", true)  # the pause banner is just PAUSED (no sentence)
		main._pause_banner(true, "A TV player opened the menu")
		var pt: String = main.center_label.text
		print("Bot: pause banner %s" % ("PAUSED" if pt == "PAUSED" else "ERROR: " + pt.replace("\n", " / ")))
		main._pause_banner(false, "")
	if main.net.mode == "local" and main.players.size() > 1:
		var p2 = main.players[1]
		if plug_phase == 0 and t >= 34.0 and p2.active and p2.joy < 0:
			plug_phase = 1
			p2.joy = 14  # a fake controller for P2 (it keeps its keyboard when unplugged)
		elif plug_phase == 1 and t >= 35.0:
			plug_phase = 2
			print("Bot: unplugging P2's controller")
			main._on_joy_changed(14, false)
		elif plug_phase == 2 and t >= 40.0:
			plug_phase = 3
			print("Bot: plugging P2's controller back in")
			main._on_joy_changed(14, true)
			print("Bot: P2 joy=%d lost=%s" % [p2.joy, main.pad_lost(1)])
		elif plug_phase == 3 and t >= 41.0:
			plug_phase = 4
			p2.joy = -1
	if main.center_label.modulate.a > 0.05:
		_check_headline("TV headline", main.center_label.text)
	if main.vr_center != null and main.vr_center.modulate.a > 0.05:
		_check_headline("VR headline", main.vr_center.text)
	if main.help_label.visible and main.help_label.modulate.a > 0.05 and main.help_label.text.strip_edges() != "":
		_tip_error("controls line", main.help_label.text)
	if main.join_label != null and main.join_label.visible and main.join_label.text.strip_edges() != "":
		_tip_error("join line", main.join_label.text)
	var it: String = main.info_label.text
	if it != "" and it != "Syncing with the lantern-bearer…":
		_tip_error("top line", it)
	for p in main.players:
		var hud = p.hud
		if hud == null or not is_instance_valid(hud) or not p.active:
			continue
		if hud.hint_label.visible and hud.hint_label.text.strip_edges() != "":
			_tip_error("P%d hint line" % (p.index + 1), hud.hint_label.text)
		if hud.name_label.text != "" and hud.name_label.text != "P%d" % (p.index + 1):
			_tip_error("P%d corner" % (p.index + 1), hud.name_label.text)
		if hud.edge_on:
			cues["edge_arrow"] = true
		if hud.cue != null and hud.cue.visible and hud.cue_key != "":
			if not cues.has("cue_" + hud.cue_key):
				print("BOT: P%d picture cue %s (t=%.0f)" % [p.index + 1, hud.cue_key, t])
			cues["cue_" + hud.cue_key] = true
		if p.camera != null and int(p.camera.cull_mask) & p.body_layer():
			if not cues.has("own_tag_shown"):
				print("BOT: ERROR P%d's view shows its own name tag" % (p.index + 1))
			cues["own_tag_shown"] = true
	for p in main.players:
		var done: Dictionary = p.get_meta("cue_done", {})
		for k in done:
			if int(done[k]) >= 2 and not cues.has("cue_learned_" + str(k)):
				cues["cue_learned_" + str(k)] = true
				print("BOT: P%d learned %s (t=%.0f)" % [p.index + 1, k, t])
	if int(t) % 10 == 0 and cues.size() != int(get_meta("cues_shown", -1)):
		set_meta("cues_shown", cues.size())  # networked runs end on a timeout: print the cues as they come
		var ks: Array = cues.keys()
		ks.sort()
		print("BOT CUES so far: mode=%s %s" % [main.net.mode, ",".join(PackedStringArray(ks))])


func _check_headline(who: String, text: String) -> void:
	var tx := text.strip_edges()
	if tx == "" or headline_re.search(tx) != null:
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
		for p in main.players:
			if p.has_meta("cue_done"):
				print("BOT CUES: P%d done=%s" % [p.index + 1, p.get_meta("cue_done")])
