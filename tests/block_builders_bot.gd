extends Node
## Headless bot for Block Builders. Drives whichever players are local on this machine:
## the builder (flat cursor, or the VR hand with BB_FAKE_VR=1) places each level's known solution,
## and the runners wait for the path, then follow the level's bot_path to the flag. Banners are
## confirmed with jump / the builder's click. Prints progress every 5 s.
## BOT_PLAYERS=n (2..6): n TV runners join (via main.debug_join; the last one drops in through a fake
## controller pressing A, then gets unplugged at 22 s and plugged back in at 28 s).
## BB_START_LEVEL=n: jump straight to level n (1-based) on the host / local game.
## New features: "jump" / "leap" path modes (crates, speed pads), stars on the bot paths, a gift balloon
## called early on level 2 that the builder grabs and carries to a runner, and high fives at the flag.
## SIMPLE_MODE (main.simple): no balloon / stars / timer. The fake VR hand first pokes the toys (a cloud,
## a balloon, a bird) and grabs and throws a toy block, then builds; runners boop at the flag. Every 5 s
## it prints the simple checks: ghost hand shown, practice ring, toys touched, buddy runner (solo VR),
## and it shouts "Bot: FAIL" if a level ever fails (there's no timer any more).
## BOT_VR=1: the same as BB_FAKE_VR=1 (the builder runs the real VR code with a fake right hand).
## Visual teaching (simple mode): records the picture cues each view shows (cue_run, cue_jump,
## cue_place, cue_plug), the ones learned (cue_learned_*), the glowing arrows (place_arrow, goal_arrow,
## tray_arrow), the ghost hand, the join cue and the bolt (plug_cue); checks the pause banner is just
## PAUSED, that no runner's camera sees its own name tag, and prints "BOT: ERROR instruction text" if a
## headline (TV or VR) is anything but BLOCK BUILDERS, a level name or a short word, or a tip spot (a
## view's HUD / hint line, the controls line, the status line) shows words.

const Levels := preload("res://games/block_builders/levels.gd")
const Story := preload("res://games/block_builders/story.gd")

var main
var t := 0.0
var last_print := -100.0
var bot_players := clampi(int(OS.get_environment("BOT_PLAYERS")), 0, 6) if OS.has_environment("BOT_PLAYERS") else 0
var joined := 1
var fake_pad := 13
var pad_phase := 0
var build_t := 0.0
var cleared_seen := 0
var last_state := ""
var started_level := false
# Fake VR hand
var vr_phase := "idle"
var vr_item: Array = []
var vr_wait := 0.0
var gift_called_seq := -1
var gifts_seen := 0
var props_phase := 0
var props_t := 0.0
var cues := {}  # simple mode: picture cues seen / learned
const WORDS := ["", "BLOCK BUILDERS", "HOORAY!", "YOU DID IT!", "PAUSED", "Connecting to the Builder…"]
const HUD_WORDS := ["", "YOU MADE IT!", "Syncing with the Builder…"]


func _ready() -> void:
	preload("res://tests/bot_end.gd").arm(self)  # end by itself in networked runs
	if OS.get_environment("BOT_VR") == "1" and not OS.has_environment("DUO_JOIN"):
		OS.set_environment("BB_FAKE_VR", "1")
	main = load("res://games/block_builders/main.tscn").instantiate()
	main.set("fresh_save", true)  # a brand-new sky story every run (story.gd)
	add_child(main)


func _physics_process(delta: float) -> void:
	t += delta
	if not main.ready_to_play:
		return
	_party()
	if main.simple:
		_note_cues()
	var host_side: bool = main.net.mode != "client"
	if host_side and OS.has_environment("BB_START_LEVEL") and not started_level and main.state == "intro" and t > 2.0 \
			and (main.net.mode != "host" or main.net.connected):
		started_level = true
		main._start_level(int(OS.get_environment("BB_START_LEVEL")) - 1)
	if host_side and not main.simple and main.state == "play" and main.level == 1 and gift_called_seq != main.level_seq and main.level_time > 0.5:
		gift_called_seq = main.level_seq
		main.spawn_balloon()
	if host_side and main.builder != null:
		if main.builder.flat:
			_drive_flat_builder(delta)
		elif main.builder.vr:
			_drive_vr_builder(delta)
	for r in main.runners():
		if not r.remote and not r.buddy:
			_drive_runner(r)
	if main.balloon_state == 0 and int(get_meta("balloon_was", 0)) != 0:
		gifts_seen += 1
		print("Bot: gift balloon gone (%d), budget=%s" % [gifts_seen, str(main.budget)])
	set_meta("balloon_was", main.balloon_state)
	if main.state != last_state:
		print("t=%.1f state %s -> %s (level %d)" % [t, last_state, main.state, main.level + 1])
		if main.state == "clear" or main.state == "won":
			cleared_seen += 1
			print("Bot: LEVEL %d CLEARED (%d so far) score=%d stars=%d" % [main.level + 1, cleared_seen, main.score, main.stars_taken])
			if main.simple and main.net.mode != "client" and Story.is_adventure(main.level):
				# The bot path detours to the lost cloud friend (coursegen.gd), so it must be home now.
				if main.friend_state == 2 and (main.save.data.friends as Array).size() > 0:
					print("Bot: FRIEND rescued on %s (%d home)" % [str(main.level_data().name), (main.save.data.friends as Array).size()])
				else:
					printerr("SCRIPT ERROR: Bot: the lost friend on %s wasn't rescued (state %d) %s friend %s ground %s path %s" % [str(main.level_data().name), main.friend_state, str(main.level_data().get("challenges")), str(main.level_data().get("friend")), str(main.level_data().ground), str(main.level_data().bot_path)])
				if int(main.save.data.adventure) < Story.adventure_of(main.level) + 1 and not Story.is_daily(main.level):
					printerr("SCRIPT ERROR: Bot: the adventure wasn't saved (%d)" % int(main.save.data.adventure))
		if main.simple and main.state == "failed":
			print("Bot: FAIL - a level failed in SIMPLE_MODE")
		last_state = main.state
	if t - last_print >= 5.0:
		last_print = t
		var rs: Array[String] = []
		for r in main.runners():
			if r.active:
				rs.append("P%d%s %s" % [r.index + 1, " FLAG" if r.finished else "", r.global_position.snapped(Vector3.ONE * 0.1)])
		print("t=%.0f mode=%s state=%s level=%d time=%.0f score=%d blocks=%d budget=%s views=%d runners=%d [%s]" % [
			t, main.net.mode, main.state, main.level + 1, main.time_left, main.score, main.course.blocks.size(),
			str(main.budget), main.view_count, main.active_runner_count(), ", ".join(rs)])
		if main.simple:
			print("Bot: simple checks: ghost_hand=%s ring=%d toys_touched=%s solo_buddy=%s vr_text='%s'" % [
				main.ghost_hand.shown if main.ghost_hand != null else "n/a", main.ring_state,
				str(main.props.touched.keys()) if main.props != null else "[]", main.solo,
				main.vr_center.text.replace("\n", " | ") if main.vr_center != null and main.vr_center.visible else ""])


## BOT_PLAYERS: bring in extra TV runners one by one, and exercise unplug / replug.
func _party() -> void:
	if bot_players < 2 or main.net.mode == "host":
		return
	if main.net.mode == "client" and not main.synced:
		return
	if joined < bot_players and t >= 2.0 + joined * 1.0:
		joined += 1
		if joined == bot_players and joined >= 3:
			var ev := InputEventJoypadButton.new()
			ev.device = fake_pad
			ev.button_index = JOY_BUTTON_A
			ev.pressed = true
			Input.parse_input_event(ev)
			print("Bot: fake controller %d pressed A (expect P%d)" % [fake_pad, joined + 1])
		else:
			print("Bot: P%d joins" % (joined + 1))
			main.debug_join(joined)
	if joined == bot_players and bot_players >= 3:
		if pad_phase == 0 and t >= 22.0:
			pad_phase = 1
			print("Bot: unplugging controller %d (owner P%d)" % [fake_pad, main.pad_owner(fake_pad) + 1])
			main._on_joy_changed(fake_pad, false)
		elif pad_phase == 1 and t >= 28.0:
			pad_phase = 2
			print("Bot: plugging controller %d back in" % fake_pad)
			main._on_joy_changed(fake_pad, true)
			print("Bot: controller %d now owned by P%d" % [fake_pad, main.pad_owner(fake_pad) + 1])


func _solution() -> Array:
	return Levels.get_level(main.level).solution


## Next block of the solution that isn't in the course yet (or an empty array).
func _next_item() -> Array:
	for item in _solution():
		var c: Vector3i = item[1]
		if not main.course.has_block(c):
			return item
	return []


func _path_built() -> bool:
	return _next_item().is_empty()


## Where the builder's hand should go for the co-op extras (gift balloon, high fives), or null.
func _coop_target():
	if main.balloon_state == 1:
		return main.balloon_pos
	if main.balloon_state == 2:
		var r = main.players[1]
		return r.global_position + Vector3.UP * 0.5
	for r in main.runners():
		if r.active and r.finished and int(main.high_fived.get(r.index, -1)) != main.level_seq:
			return r.global_position + Vector3.UP * 0.6
	return null


func _drive_flat_builder(delta: float) -> void:
	var b = main.builder
	b.bot = true
	build_t -= delta
	var ct = _coop_target()
	if ct != null and main.state != "intro":
		var cp: Vector3 = ct
		b.bot_cell = Vector3i(floori(cp.x), floori(cp.y - 0.5), floori(cp.z))
		b.bot_kind = "plank"
		if main.state == "play":
			return
	if main.state != "play":
		# Confirm banners (start / next level / retry) now and then.
		if main.state_t > 3.5 and build_t <= 0.0:
			build_t = 1.0
			b.bot_place = true
		return
	if build_t > 0.0:
		return
	build_t = 0.3
	var item := _next_item()
	if item.is_empty():
		return
	b.bot_kind = item[0]
	b.bot_cell = item[1]
	b.held_rot = item[2]
	b.bot_place = true


## BB_FAKE_VR: move the right controller node by hand to the tray, squeeze, carry, let go.
func _drive_vr_builder(delta: float) -> void:
	var b = main.builder
	b.bot = true
	if b.xr_camera.position == Vector3.ZERO:
		b.xr_camera.position = Vector3(0.0, 1.5 * b.S, 0.0)
	var ctrl: XRController3D = b.hand_r
	var off: Vector3 = ctrl.global_basis * (b.GRAB_LOCAL * b.S)
	vr_wait -= delta
	if _poke_props(b, ctrl, off, delta):
		return
	var ct = _coop_target()
	if ct != null and (vr_phase == "idle" or vr_phase == "coop") and main.state != "intro":
		vr_phase = "coop"
		b.bot_trigger = false
		var want: Vector3 = ct
		ctrl.global_position = ctrl.global_position.move_toward(want - off, 30.0 * delta)
		return
	if vr_phase == "coop":
		vr_phase = "idle"
	if main.state != "play":
		b.bot_trigger = main.state_t > 3.5 and int(t * 2.0) % 2 == 0
		vr_phase = "idle"
		return
	match vr_phase:
		"idle":
			b.bot_trigger = false
			vr_item = _next_item()
			if not vr_item.is_empty() and vr_wait <= 0.0:
				vr_phase = "to_tray"
		"to_tray":
			var slot: int = b.Art.KINDS.find(vr_item[0])
			var want: Vector3 = b.slot_world(slot)
			ctrl.global_position = ctrl.global_position.move_toward(want - off, 40.0 * delta)
			if b.grab_point.distance_to(want) < 0.3:
				b.bot_trigger = true
				vr_phase = "carry"
				vr_wait = 0.25  # the builder reads the trigger in _process: give it a frame or two
		"carry":
			if b.held_kind == "" and vr_wait > 0.0:
				return
			if b.held_kind == "":
				vr_phase = "idle"
				vr_wait = 0.3
				return
			var c: Vector3i = vr_item[1]
			b.held_rot = vr_item[2]
			var want := Vector3(c.x + 0.5, c.y + 0.5, c.z + 0.5)
			ctrl.global_position = ctrl.global_position.move_toward(want - off, 40.0 * delta)
			if b.grab_point.distance_to(want) < 0.05 and b.target == c:
				b.bot_trigger = false
				vr_phase = "idle"
				vr_wait = 0.2
				print("Bot: VR builder placed a %s at %s (ok=%s)" % [vr_item[0], c, b.target_ok])


## SIMPLE_MODE, level 1: touch each kind of toy once (the toy block gets grabbed and thrown).
func _poke_props(b, ctrl: XRController3D, off: Vector3, delta: float) -> bool:
	if not main.simple or main.props == null or main.state != "play" or main.level != 0:
		return false
	var targets: Array = main.props.bot_targets()
	if props_phase >= targets.size():
		return false
	var kind: String = targets[props_phase][0]
	var want: Vector3 = targets[props_phase][1]
	props_t += delta
	if kind == "toy" and main.props.held >= 0:
		# Throw it: swing up and towards the course, then let go.
		ctrl.global_position = ctrl.global_position.move_toward(Vector3(0.0, 4.0, 1.0) - off, 30.0 * delta)
		if props_t > 0.35:
			b.bot_trigger = false
			print("Bot: threw a toy block")
			props_phase += 1
			props_t = 0.0
		return true
	ctrl.global_position = ctrl.global_position.move_toward(want - off, 25.0 * delta)
	if b.grab_point.distance_to(want) < 0.25:
		if kind == "toy":
			b.bot_trigger = true
			if main.props.held >= 0:
				props_t = 0.0
			return true
		if props_t > 0.3:
			print("Bot: poked the %s (touched %s)" % [kind, str(main.props.touched.keys())])
			props_phase += 1
			props_t = 0.0
	elif props_t > 6.0:
		print("Bot: couldn't reach the %s, skipping" % kind)
		b.bot_trigger = false
		props_phase += 1
		props_t = 0.0
	return true


func _drive_runner(r) -> void:
	if not r.active:
		r.bot_input = {"move": Vector3.ZERO, "jump": false}
		return
	if main.state != "play":
		# Jump now and then: confirms banners on the TV / split screen.
		r.bot_input = {"move": Vector3.ZERO, "jump": main.state_t > 2.0 and int(t * 2.0) % 2 == 0 and r.index == 1}
		return
	if r.finished or not _path_built():
		r.bot_input = {"move": Vector3.ZERO, "jump": false}
		return
	var path: Array = Levels.get_level(main.level).bot_path
	var seq: int = main.level_seq
	if int(r.get_meta("bot_seq", -1)) != seq:
		r.set_meta("bot_seq", seq)
		r.set_meta("bot_wp", 0)
	if r.respawn_t > 0.0:
		# Back at a safe spot: carry on from the first waypoint ahead of us.
		var k := 0
		while k < path.size() - 1:
			var wpk: Vector3 = path[k][0]
			if wpk.x > r.global_position.x - 0.3:
				break
			k += 1
		r.set_meta("bot_wp", k)
	var wi: int = clampi(int(r.get_meta("bot_wp", 0)), 0, path.size() - 1)
	var wp: Vector3 = path[wi][0]
	var mode: String = path[wi][1]
	var pos: Vector3 = r.global_position
	var to := Vector2(wp.x - pos.x, wp.z - pos.z)
	var move := Vector3.ZERO
	if to.length() > 0.12:
		move = Vector3(to.x, 0.0, to.y).normalized() * clampf(to.length() * 2.0, 0.3, 1.0)
	var reached := to.length() < 0.3
	var jump := false
	if mode == "rise":
		reached = reached and pos.y >= wp.y - 0.6
	elif mode == "jump":
		reached = reached and pos.y >= wp.y - 0.3
		jump = int(t * 4.0) % 2 == 0
	elif mode == "leap":
		reached = to.length() < 0.5
		# Jump right at the edge (no ground just ahead).
		var dir := Vector3(to.x, 0.0, to.y).normalized()
		var ahead: float = main.course.surface_below(pos.x + dir.x * 0.45, pos.z + dir.z * 0.45, pos.y + 0.1, 0.05)
		jump = r.on_ground and ahead < pos.y - 0.5
	if reached and wi < path.size() - 1:
		r.set_meta("bot_wp", wi + 1)
	r.bot_input = {"move": move, "jump": jump}


# --- Visual teaching checks (simple mode) ------------------------------------------

## Picture cues instead of words; any instruction text in a tip spot is an error.
func _note_cues() -> void:
	var gh = main.ghost_hand
	if gh != null and gh.visible:
		cues["ghost_hand"] = true
	for k in ["place_arrow", "goal_arrow"]:
		var n = main.get(k)
		if n != null and n.is_visible_in_tree():
			if not cues.has(k):
				print("BOT: %s glows (t=%.0f)" % [k, t])
			cues[k] = true
	var b = main.builder
	if b != null and b.arrow != null and b.arrow.is_visible_in_tree():
		cues["tray_arrow"] = true
	if main.join_cue != null and main.join_cue.visible:
		cues["join_cue"] = true
	if main.plug_cue != null and main.plug_cue.visible:
		if not cues.has("plug_cue"):
			print("BOT: bolt shows (t=%.0f)" % t)
		cues["plug_cue"] = true
	if not has_meta("pause_check") and t >= 25.0 and main.net.mode != "client" and not get_tree().paused:
		set_meta("pause_check", true)  # the pause banner is just PAUSED (no sentence)
		main._set_pause_banner(true, "A runner opened the menu")
		var pt: String = main.center_label.text
		print("BOT: pause banner %s" % ("PAUSED" if pt == "PAUSED" else "ERROR: " + pt.replace("\n", " / ")))
		main._set_pause_banner(false, "")
	if main.center_label.modulate.a > 0.05:
		_check_headline("TV headline", main.center_label.text)
	if main.vr_center != null and main.vr_center.visible and main.vr_center.modulate.a > 0.05:
		_check_headline("VR headline", main.vr_center.text)
	if main.vr_info != null and main.vr_info.visible and main.vr_info.text != "":
		_tip_error("VR status line", main.vr_info.text)
	if main.help_label.visible and main.help_label.modulate.a > 0.05 and main.help_label.text.strip_edges() != "":
		_tip_error("controls line", main.help_label.text)
	if not HUD_WORDS.has(main.info_label.text.strip_edges()):
		_tip_error("status line", main.info_label.text)
	for p in main.players:
		if not p.active or not p.has_meta("view"):
			continue
		for l in [p.hud_label, p.hint_label]:
			if l != null and l.is_visible_in_tree() and not HUD_WORDS.has(l.text.strip_edges()):
				_tip_error("P%d HUD line" % (p.index + 1), l.text)
		if p.index > 0 and p.camera != null and p.tag != null and (p.camera.cull_mask & p.tag.layers) != 0:
			if not cues.has("own_tag"):
				print("BOT: ERROR P%d sees its own name tag" % (p.index + 1))
			cues["own_tag"] = true
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
		set_meta("cues_shown", cues.size())  # networked runs end on a timeout: print the cues as they come
		var ks: Array = cues.keys()
		ks.sort()
		print("BOT CUES so far: mode=%s %s" % [main.net.mode, ",".join(PackedStringArray(ks))])


func _check_headline(who: String, text: String) -> void:
	var tx := text.strip_edges()
	if WORDS.has(tx):
		return
	if tx == str(main.level_data().name) or Story.is_course_name(tx):
		return  # (the sky adventures' names: coursegen.gd; a TV machine may show the next one before its snapshot)
	for n in Levels.levels().size():
		if tx == str(Levels.levels()[n].name):
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
