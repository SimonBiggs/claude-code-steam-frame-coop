extends Node
## Headless bot for Dragon Rider. The rider (local / DUO_HOST) flies an autopilot through the rings
## and flaps on the straights; every local gunner aims at the nearest storm sprite (or balloon) and
## holds fire. BOT_PLAYERS=N: total TV-side players (local: rider + gunners, up to 6; TV machine
## (DUO_JOIN): gunners, up to 6). Local mode also joins one gunner with a fake controller pressing A.
## DR_START_LEVEL=n: jump to level n (missions cycle: 1 ring run, 2 rescue, 3 race, 4 Storm King boss).
## The autopilot follows main.arrow_target() (rings, freed sky bunnies, the boss ring); gunners shoot
## sprites first, then cages, orbs, Goldie and balloons.
## SIMPLE_MODE (main.gd): checks the practice (3 rings left / right / up, one glowing balloon per
## gunner), stage 1 without sprites / stars, no game over, and prints a FINAL line with what was seen.
## BOT_VR=1 (or DR_FAKE_VR=1): the real VR rider code runs; the bot moves the fake hands like reins
## (measured from the head), hesitates in practice to watch the ghost hands, and after practice pats
## the dragon's mane, honks a horn, swings the lantern, spins the flag and touches clouds / birds.
## Visual teaching (simple mode): records the picture cues each TV view shows (cue_steer, cue_flap,
## cue_fire, cue_aim, cue_plug), the ones learned (cue_learned_*), the glowing edge arrows (edge_arrow),
## the ghost hands, the VR ghost flap hand (ghost_flap) and the big boss-ring arrow (boss_arrow). The
## rider waits a moment in practice and the gunners wait before firing, fire in presses, and the first
## gunner looks away from their practice balloon, so the cues show. Prints "BOT: ERROR instruction text"
## if a headline (TV or VR) or any word a TV view draws is anything but a short title, and checks the
## pause banner is just PAUSED.

const FAKE_PAD := 40

var main
var t := 0.0
var joined := false
var report_t := 0.0
var levels_done := 0
var was_done := false
var best_level := 0
var seen := {}
var touch_step := 0
var touch_t := 0.0
var touch_from := Vector3.ZERO
var practice_seen_t := 0.0
var cues := {}  # simple mode: picture cues seen / learned
const HEADLINES := "^(DRAGON RIDER!|STARS!|GOLDEN BALLOON!|SKY BUNNIES!|RACE GOLDIE!|STORM SPRITES!|STORM KING!|LET'S FLY!|TRIPLE BUBBLES!|HOORAY!|ALL ABOARD!|PAUSED|Connecting to the dragon rider…)$"
var headline_re := RegEx.create_from_string(HEADLINES)
var look_away_t := -1.0  # simple mode: the first gunner looks away from their practice balloon
var flap_seen_t := 0.0


func _ready() -> void:
	main = load("res://games/dragon_rider/main.tscn").instantiate()
	add_child(main)


func _pad_press(device: int, button: JoyButton) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = device
		e.button_index = button
		e.pressed = down
		Input.parse_input_event(e)


func _process(delta: float) -> void:
	t += delta
	if main == null or not main.ready_to_play:
		return
	var mode: String = main.net.mode
	if not joined and t > (3.0 if mode == "client" else 1.0):
		joined = true
		_join_players(mode)
	if mode != "client":
		if OS.has_environment("DR_START_LEVEL") and main.phase == "practice":
			main._end_practice()
		if OS.has_environment("DR_START_LEVEL") and not has_meta("jumped") and main.level == 1 and main.phase == "intro":
			set_meta("jumped", true)
			main._start_level(int(OS.get_environment("DR_START_LEVEL")))
		_autopilot(delta)
	_note(mode)
	if main.SIMPLE_MODE:
		_note_cues()
		_pause_check()
	for i in range(1, main.players.size()):
		var g = main.players[i]
		if g.active and not g.remote:
			_aim(g)
			if OS.has_environment("BOT_GAMEOVER"):
				g.force_fire = false  # let the sprites win, to test game over + play again
	if OS.has_environment("BOT_GAMEOVER") and main.phase == "over" and main.game_over_time > 2.0 and not has_meta("restarted"):
		set_meta("restarted", true)
		print("BOT: game over seen, pressing Enter to play again")
		var e := InputEventKey.new()
		e.physical_keycode = KEY_ENTER
		e.pressed = true
		Input.parse_input_event(e)
	var done: bool = main.phase == "done"
	if done and not was_done:
		levels_done += 1
		print("BOT %s: LEVEL %d (%s) COMPLETE (rings %d, score %d, rescued %d, power %.0f, cannon %d)" % [mode, main.level,
			main.mission, main.level_rings, main.score, main.course.rescued_count() if main.course != null else 0, main.power_t,
			main.cannon_level])
	was_done = done
	best_level = maxi(best_level, main.level)
	report_t -= delta
	if report_t <= 0.0:
		report_t = 4.0
		_report(mode)


func _join_players(mode: String) -> void:
	if mode == "host":
		return
	var want := int(OS.get_environment("BOT_PLAYERS")) if OS.has_environment("BOT_PLAYERS") else 2
	var have := 2 if mode == "local" else 1
	var target := clampi(want, have, 6)
	var extra := target - have
	print("BOT: %s mode, joining %d extra gunners" % [mode, extra])
	if mode == "local" and extra > 0:
		_pad_press(FAKE_PAD, JOY_BUTTON_A)  # a new controller presses A: joins (Start would pause)
		extra -= 1
		print("BOT: fake controller %d now drives P%d, paused=%s" % [FAKE_PAD, int(main.joy_owner.get(FAKE_PAD, -1)) + 1, get_tree().paused])
	for i in extra:
		var p = main.debug_join()
		print("BOT: debug_join -> %s" % ("P%d" % (p.index + 1) if p != null else "none"))


func _autopilot(delta: float) -> void:
	var r = main.players[0]
	r.bot_drive = not r.fake_vr
	var d: Node3D = main.dragon
	if main.SIMPLE_MODE and not r.fake_vr and main.phase == "practice":
		practice_seen_t += delta
		if practice_seen_t < 3.0:
			r.bot_input = Vector2.ZERO  # a moment first: the steer cue (button + arrow) shows
			r.bot_flap = false
			return
	var ring: Dictionary = main.arrow_target()
	if ring.is_empty():
		r.bot_input = Vector2.ZERO
		r.bot_flap = false
		if r.fake_vr:
			_fake_hands(r, Vector2.ZERO, delta)
		return
	var rp: Vector3 = ring.pos
	var rn: Vector3 = ring.get("normal", (rp - d.core_position()).normalized())
	var core: Vector3 = d.core_position()
	var dist := core.distance_to(rp)
	var aim_pt := rp - rn * clampf(dist * 0.35, 0.0, 22.0)
	var to := aim_pt - core
	var want := atan2(-to.x, -to.z)
	var err := wrapf(want - float(d.yaw), -PI, PI)
	r.bot_input = Vector2(clampf(-err * 3.0, -1.0, 1.0), clampf((rp.y - core.y) / 5.0, -1.0, 1.0))
	r.bot_flap = absf(err) < 0.12 and dist > 40.0
	if main.SIMPLE_MODE and not cues.has("cue_flap") and t < 45.0:
		r.bot_flap = false  # wait for the flap cue (button + forward arrow) first
	if r.fake_vr:
		_fake_hands(r, r.bot_input, delta)


## Fake VR: hold the reins like a kid would. Hands measured from the (fake) head: move both left /
## right to turn, lift them to the chin to climb, push them right down to dive. In practice the bot
## first waits a moment (watching the ghost hands), then copies the move.
func _fake_hands(r, want: Vector2, delta: float) -> void:
	r.fake_trigger = 0.0
	if main.flap_hand != null and main.flap_hand.visible:
		flap_seen_t += delta
		if flap_seen_t > 2.0:
			r.fake_trigger = 1.0 if fmod(flap_seen_t, 0.8) < 0.4 else 0.0  # copy the ghost finger
	elif flap_seen_t > 0.0:
		flap_seen_t += delta
		r.fake_trigger = 1.0 if fmod(flap_seen_t, 0.8) < 0.4 and flap_seen_t < 4.0 else 0.0
	if main.phase == "practice":
		practice_seen_t += delta
		if main.ghost_hands != null and main.ghost_hands.visible:
			seen["ghost hands"] = true
		if practice_seen_t < 2.5:
			want = Vector2.ZERO
		if main.practice_step >= 0 and main.practice_step < 3:
			var mv: String = main.PRACTICE_MOVES[main.practice_step]
			if practice_seen_t >= 2.5:
				want = Vector2(clampf(want.x * 2.0, -1.0, 1.0), clampf(want.y, -1.0, 1.0))
				if mv == "up" and want.y < 0.3:
					want.y = 0.6
	var cam: Node3D = r.xr_camera
	var head: Vector3 = cam.position
	var lift := 0.0
	if want.y > 0.15:
		lift = 0.12 + 0.18 * want.y
	elif want.y < -0.15:
		lift = -0.35
	var turn := want.x * 0.2
	r.hand_l.position = head + Vector3(-0.2 + turn, -0.45 + lift, -0.38)
	r.hand_r.position = head + Vector3(0.2 + turn, -0.45 + lift, -0.38)
	if main.phase == "fly" and main.level >= 1:
		_fake_touch(r, delta)


## Fake VR, after practice: touch every prop once (pat, horn, lantern, flag), then visitors.
func _fake_touch(r, delta: float) -> void:
	var props = main.props
	if props == null:
		return
	touch_t += delta
	var inv: Transform3D = r.fit_xf.affine_inverse()
	var spots := [props.MANE[0] + Vector3(0, 0.12, 0), props.HORN_TIPS[1], props.LANTERN_HOOK + Vector3(0, -0.24, 0),
		props.FLAG_POLE + Vector3(0, props.FLAG_H - 0.15, 0.1)]
	if touch_step < spots.size():
		var p: Vector3 = spots[touch_step]
		var k := clampf(touch_t / 0.6, 0.0, 1.0)
		if touch_step == 0:
			p += Vector3(0, -0.2 * clampf((touch_t - 0.6) / 0.4, 0.0, 1.0), 0)  # pat: down onto the mane
		var hand: XRController3D = r.hand_l if touch_step == 3 else r.hand_r
		hand.position = hand.position.lerp(inv * p, k)
		if touch_t > 1.3:
			touch_step += 1
			touch_t = 0.0
		return
	for id in props.visitors.keys():
		var vi: Dictionary = props.visitors[id]
		if vi.gone:
			continue
		var n: Node3D = vi.node
		if n.position.distance_to(Vector3(0.0, 0.6, -0.3)) < 1.3:
			var hand2: XRController3D = r.hand_l if n.position.x < 0.0 else r.hand_r
			hand2.position = inv * n.position
			return


func _aim(g) -> void:
	var eye: Vector3 = g.eye_position()
	var best: Node3D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("dr_targets"):
		var node := n as Node3D
		var dd := node.global_position.distance_to(eye)
		var kind: String = node.get_meta("kind", "")
		if kind == "sprite" and dd < 30.0:
			dd *= 0.3  # sprites close to the dragon first
		elif kind == "orb" or kind == "cage" or kind == "rival" or node.has_meta("golden"):
			dd *= 0.5  # then the mission targets
		if dd < best_d and node.global_position.distance_to(eye) < 65.0:
			best_d = dd
			best = node
	g.force_fire = best != null
	if main.SIMPLE_MODE:
		g.force_fire = best != null and fmod(t, 0.9) < 0.6 and (look_away_t == -2.0 or t > 14.0)  # presses, after a moment (fire cue)
		if _look_away(g):
			return
	if best == null:
		return
	var local: Vector3 = main.dragon.global_basis.inverse() * (best.global_position - eye)
	g.yaw = atan2(-local.x, -local.z)
	g.pitch = atan2(local.y, Vector2(local.x, local.z).length())


## Simple mode: the first local gunner turns away from their practice balloon once (after a few
## seconds) until the aim cue (button + arrow, and the glowing edge arrow) shows, then turns back.
func _look_away(g) -> bool:
	var first = null
	for i in range(1, main.players.size()):
		var q = main.players[i]
		if q.active and not q.remote:
			first = q
			break
	if g != first or look_away_t == -2.0 or not main.practice_balloons.has(g.index) or t < 3.5:
		return false
	if look_away_t < 0.0:
		look_away_t = t
		g.yaw = wrapf(g.yaw + PI, -PI, PI)  # facing straight away
	g.force_fire = false
	if str(g.get_meta("cue", "")) == "aim" or t - look_away_t > 6.0:
		print("Bot: P%d looked away until the aim cue showed (%s)" % [g.index + 1, g.get_meta("cue", "")])
		look_away_t = -2.0
		return false
	return true


## Visual teaching: picture cues instead of words; any instruction text is an error.
func _note_cues() -> void:
	if main.ghost_hands != null and main.ghost_hands.visible:
		cues["ghost_hands"] = true
	if main.flap_hand != null and main.flap_hand.visible:
		cues["ghost_flap"] = true
	if main.arrow.visible and main.arrow.get_meta("boss", false):
		cues["boss_arrow"] = true
	if main.center_alpha > 0.05:
		_check_headline("TV headline", main.center_text.get_slice("\n", 0))
	if main.vr_center != null and main.vr_center.visible:
		_check_headline("VR headline", main.vr_center.text)
	if main.vr_status != null and main.vr_status.visible:
		_tip_error("VR status panel", main.vr_status.text)
	if main.fallback_label.visible and main.fallback_label.modulate.a > 0.05:
		_check_headline("fallback label", main.fallback_label.text)
	for p in main.players:
		if not p.active or p.ghost or p.remote or p.vr or p.hud == null:
			continue
		for tx in p.hud.texts:
			_check_headline("P%d view" % (p.index + 1), tx)
		if p.hud.edge_arrow:
			cues["edge_arrow"] = true
		var key := str(p.get_meta("cue", ""))
		var box = p.get_meta("cue_box") if p.has_meta("cue_box") else null
		if key != "" and box != null and box.visible:
			if not cues.has("cue_" + key):
				print("BOT: P%d picture cue %s" % [p.index + 1, key])
			cues["cue_" + key] = true
	for p in main.players:
		var done: Dictionary = p.get_meta("cue_done", {})
		for k in done:
			if int(done[k]) >= 2:
				cues["cue_learned_" + str(k)] = true


func _check_headline(who: String, text: String) -> void:
	var tx := text.strip_edges()
	if tx == "" or headline_re.search(tx) != null:
		return
	_tip_error(who, tx)


func _tip_error(who: String, text: String) -> void:
	if not cues.has("tip_text"):
		print("BOT: ERROR instruction text on %s: %s" % [who, text.replace("\n", " / ")])
	cues["tip_text"] = true


## Simple mode: the pause banner is just PAUSED (no sentence), on every machine.
func _pause_check() -> void:
	if has_meta("pause_check") or t < 30.0:
		return
	set_meta("pause_check", true)
	main._set_pause_banner(true, "A gunner opened the menu")
	var pt: String = main.center_text
	print("Bot: pause banner %s" % ("PAUSED" if pt == "PAUSED" else "ERROR: " + pt.replace("\n", " / ")))
	main._set_pause_banner(false, "")


func _note(mode: String) -> void:
	if main.phase == "practice":
		seen["practice"] = true
		if main.practice_ring != null:
			seen["practice ring"] = true
		if not main.practice_balloons.is_empty():
			seen["practice balloon"] = true
	if main.practice_popped != 0:
		seen["practice balloon popped"] = true
	if main.practice_step >= 3 and main.level >= 1:
		seen["practice done"] = true
	if main.phase == "over":
		seen["GAME OVER (should not happen in simple mode)"] = true
	if main.level == 1 and main.phase == "fly":
		if not get_tree().get_nodes_in_group("dr_sprites").is_empty():
			seen["SPRITES IN STAGE 1 (should not happen)"] = true
		if main.course != null and not main.course.stars.is_empty():
			seen["STARS IN STAGE 1 (should not happen)"] = true
	if main.center_text.contains("\n") and main.phase != "wait":
		seen["multi-line banner: %s" % main.center_text.replace("\n", " / ")] = true
	if main.props != null:
		if not main.props.visitors.is_empty():
			seen["visitor"] = true
		for k in main.props.touched.keys():
			seen["touched " + str(k)] = true
	if main.level >= 2:
		seen["stage 2"] = true


func _exit_tree() -> void:
	if main == null:
		return
	var keys := seen.keys()
	keys.sort()
	print("FINAL mode=%s phase=%s level=%d levels_done=%d lanterns=%d balloons_gone=%d seen=%s" % [main.net.mode, main.phase,
		main.level, levels_done, main.dragon.lit_count(), main.course.gone.size() if main.course != null else 0, keys])
	if main.SIMPLE_MODE:
		var ks: Array = cues.keys()
		ks.sort()
		print("BOT CUES: mode=%s %s" % [main.net.mode, ",".join(PackedStringArray(ks))])
		for p in main.players:
			if p.has_meta("cue_done"):
				print("BOT CUES: P%d done=%s" % [p.index + 1, p.get_meta("cue_done")])


func _report(mode: String) -> void:
	if main.SIMPLE_MODE and cues.size() != int(get_meta("cues_shown", -1)):
		set_meta("cues_shown", cues.size())  # networked runs end on a timeout: print the cues as they come
		var ks: Array = cues.keys()
		ks.sort()
		print("BOT CUES so far: mode=%s %s" % [mode, ",".join(PackedStringArray(ks))])
	var act: Array[String] = []
	for p in main.players:
		if p.active:
			act.append("P%d" % (p.index + 1))
	var views := 0
	var cell := Vector2.ZERO
	for p in main.players:
		if p.has_meta("view") and p.get_meta("view").visible:
			views += 1
			cell = p.get_meta("view").size
	var synced := 0
	for i in range(1, main.players.size()):
		if main.players[i].remote and main.players[i].active and main.players[i].net_started:
			synced += 1
	if mode == "host":
		print("BOT host: %d active TV gunners are aiming over the network" % synced)
	var total: int = main.course.rings.size() if main.course != null else 0
	var extra := ""
	if main.rival != null and is_instance_valid(main.rival):
		extra = " goldie_ring=%d wrapped=%.1f" % [main.rival.ring_i, main.rival.bubbled_t]
	if main.boss != null and is_instance_valid(main.boss):
		extra = " boss_orbs=%d ring_open=%s dist=%.0f" % [main.boss.orbs_left(), main.boss.ring_open,
			main.boss.global_position.distance_to(main.dragon.global_position)]
	if main.course != null and not main.course.critters.is_empty():
		extra = " bunnies=%d/%d" % [main.course.rescued_count(), main.course.critters.size()]
	print("BOT %s t=%.0f phase=%s level=%d %s ring=%d/%d score=%d stars=%d lanterns=%d sprites=%d popped=%d alt=%.0f active=%s views=%d cell=%s levels_done=%d power=%.0f%s" % [
		mode, t, main.phase, main.level, main.mission, main.ring_i, total, main.score, main.stars_got, main.dragon.lit_count(),
		get_tree().get_nodes_in_group("dr_sprites").size(), main.sprites_popped, main.dragon.global_position.y,
		", ".join(act), views, cell, levels_done, main.power_t, extra])
