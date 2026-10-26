extends Node
# Headless test for Kitchen Rush: an autopilot button-chef (host/local) and autopilot runners (client/local).
# The chef uses the real button-chef actions (cursor + grab + chop); runners walk with bot_move and press_use().
# BOT_PLAYERS=N (1..6): N TV runners join (local split screen, or on the TV machine when networked). The last
# one joins through a fake controller pressing Start (the real drop-in path); with N >= 3 that controller is
# later "unplugged" (the runner should leave after 15 s) and plugged back in (it should rejoin).
# SIMPLE_MODE (main.gd): checks the practice order, the ghost hand, the glowing spots / crates / pass,
# one new dish per round, no game over, and (fake VR) pokes every prop: pans, clock, grinder, bell, a
# thrown veggie and the spoon. DUO_HOST=1 alone = solo VR: the kitchen helpers must keep it going.
# KR_FAKE_VR=1 (or BOT_VR=1): the real VR chef code runs; the bot moves the fake hands like a person, following the
# chef's on-screen "next step" guidance (chop with a knife swing, grab with the right trigger, drop on the plate).
# Ends by itself after BOT_SECONDS (default 110 s host, 100 s client, 600 s local: local runs use --quit-after)
# with "BOT RESULT: PASS (n checks)" or "SCRIPT ERROR: BOT RESULT: FAIL" (also printed on exit).
# KR_START_SHIFT=N starts at shift N (3 = the first dinner, with the rush). KR_TAUGHT=1: the save already
# has gifts and two visits from robots, aliens and knights (MELT, WRAP, SANDWICH on the menus from round 5).
# Gran's café (simple mode): checks the party rounds (parties.gd): story cards (a short title + one short
# line), the invitations (a runner taps one, the chef grabs one when no runner does, else the first comes),
# star guests, Gran's cookie, the gift shelf growing, one RUN telemetry line per round.
# Visual teaching (simple mode): records the picture cues each view shows (cue_take, cue_drop, cue_serve,
# cue_chop, cue_grab, cue_move, cue_plug), the ones learned (cue_learned_*), the glowing arrows (fetch_arrow,
# pass_arrow, plate_arrow, serve_arrow, chef_arrow), the ghost hand and that no view draws its own name tag,
# checks the pause banner is just PAUSED, and prints "BOT: ERROR instruction text" if a headline (TV or VR)
# is anything but a short title word, or a tip spot (a view's hint line, job panel, carry / order lists,
# the help panel, the VR hint, the wrist, the top line) shows any words.
const L := preload("res://games/kitchen_rush/layout.gd")
const M := preload("res://games/kitchen_rush/main.gd")

var main
var t := 0.0
var bot_errors := 0  # "BOT: ERROR" lines printed
var finished := false
## Run length before the bot checks and quits by itself (BOT_SECONDS; see _ready). The result also prints
## on exit (--quit-after).
var end_at := 140.0
var chef_t := 0.0
var use_t := {}
var last_pos := {}
var stuck_t := {}
var max_shift := 0
var joined := false
var log_t := 0.0
var want_players := 1
var next_join := 2
var join_at := 3.0
const FAKE_PAD := 60
var unplug_stage := 0
var max_active := 0
var seen := {}
var vr_state := "idle"
var vr_t := 0.0
var vr_target = null
var vr_from := Vector3.ZERO
var vr_chops := 0
var vr_drops := 0
var play_at := 25.0
var play_step := 0
var playing := false
var grumpy_seen := false
var cues := {}  # simple mode: picture cues seen / learned
const HEADLINES := "^(KITCHEN RUSH!|Connecting to the chef…|P\\d!|LET'S COOK!|NEW DISH!|OPEN!|HOORAY!|RACCOON!|ORDER UP!|PAUSED)$"
var headline_re := RegEx.create_from_string(HEADLINES)


func _ready() -> void:
	main = load("res://games/kitchen_rush/main.tscn").instantiate()
	add_child(main)
	if main.save != null and not OS.has_environment("KR_KEEP_SAVE"):
		main.save.data = main.save.defaults.duplicate(true)  # every bot run starts a new café (KR_KEEP_SAVE=1 keeps it)
		main._show_gifts([], false)
	var default_players := 2 if OS.has_environment("DUO_JOIN") else 1
	want_players = clampi(int(OS.get_environment("BOT_PLAYERS")) if OS.has_environment("BOT_PLAYERS") else default_players, 1, 6)
	print("BOT: %d TV runner(s) requested" % want_players)
	# Networked runs are real time with no --quit-after (tools/multibot.ts); local runs pass --quit-after
	# (the result prints on exit), so their own end is only a safety net.
	end_at = 100.0 if OS.has_environment("DUO_JOIN") else (110.0 if OS.has_environment("DUO_HOST") else 600.0)  # inside multibot's 120 s
	if OS.has_environment("BOT_SECONDS"):
		end_at = float(OS.get_environment("BOT_SECONDS"))


func _physics_process(delta: float) -> void:
	t += delta
	if t >= end_at and not finished:
		_finish()
		get_tree().quit(0 if _result() else 1)
		return
	if not main.ready_to_play:
		return
	var mode: String = main.net.mode
	if OS.has_environment("KR_START_SHIFT") and mode != "client" and not has_meta("skipped"):
		set_meta("skipped", true)
		if OS.has_environment("KR_TAUGHT") and main.save != null:
			main.save.data["visits"] = {"robot": 2, "alien": 2, "knight": 2}
			var g: Array = []
			for i in 8:
				g.append(["teapot", false, "granny"])
			main.save.data["gifts"] = g
			main.practice = false
			main.served_total = maxi(main.served_total, 1)
			print("BOT: save has 8 gifts, taught %s" % [main.Parties.taught(main._progress())])
		main.shift = int(OS.get_environment("KR_START_SHIFT")) - 1
		print("BOT: starting at shift %d" % (main.shift + 1))
	_note_features()
	if main.simple:
		_note_cues()
		if not has_meta("pause_check") and t >= 30.0 and mode != "client":
			set_meta("pause_check", true)  # the pause banner is just PAUSED (no sentence)
			main._set_pause_banner(true, "A TV player opened the menu")
			var pt: String = main.center_label.text
			print("Bot: pause banner %s" % ("PAUSED" if pt == "PAUSED" else "ERROR: " + pt.replace("\n", " / ")))
			main._set_pause_banner(false, "")
	if OS.has_environment("KR_LAZY") and mode != "client":
		# Game-over test: nobody cooks and customers run out of patience fast; then press Enter to restart.
		for c in main._waiting_customers():
			c.patience = minf(c.patience, 0.5)
		if main.simple:
			# Simple mode has no game over: grumpy customers just leave and new ones keep coming.
			if main.angry >= 6 and not grumpy_seen:
				grumpy_seen = true
				print("BOT: %d grumpy customers left, kitchen still open (game_over=%s)" % [main.angry, main.game_over])
			main.practice = false
			return
		if main.game_over and main.game_over_t > 2.5 and not Engine.has_meta("kr_restarted"):
			Engine.set_meta("kr_restarted", true)
			print("BOT: game over seen, pressing Enter to restart")
			var e := InputEventKey.new()
			e.physical_keycode = KEY_ENTER
			e.pressed = true
			Input.parse_input_event(e)
		if Engine.has_meta("kr_restarted") and not main.game_over and t < 1.0 and not has_meta("said"):
			set_meta("said", true)
			print("BOT: restarted into a fresh kitchen")
		return
	if mode != "client":
		if main.players[0].fake_vr:
			_chef_vr(delta)
		else:
			_chef(delta)
	if mode != "host":
		for i in range(1, main.players.size()):
			var p = main.players[i]
			if p.active:
				_runner(p, delta)
		_join_players(mode)
	if main.shift > max_shift:
		max_shift = main.shift
		print("BOT: reached shift %d (%s)" % [max_shift, mode])
	log_t -= delta
	if log_t <= 0.0:
		log_t = 5.0
		var carry := []
		for i in range(1, main.players.size()):
			carry.append(main.players[i].carry_kind)
		var act := []
		for i in range(1, main.players.size()):
			if main.players[i].active:
				act.append("P%d" % (i + 1))
		max_active = maxi(max_active, act.size())
		print("BOT t=%.0f runners=%s views=%d mode=%s shift=%d coins=%d served=%d/%d total=%d angry=%d items=%d customers=%d fire=%s raccoon=%s carry=%s" % [
			t, act, _views(), mode, main.shift, main.coins, main.served_shift, main.shift_target(), main.served_total, main.angry,
			main.all_items().size(), main._waiting_customers().size(), main.fire_on, main.raccoon.visible, carry])
		if mode == "host":
			print("   snapshot bytes: %d" % var_to_bytes(main.make_snapshot()).size())
		if mode != "host":
			print("   runner1 at %s next=%s need=%s" % [main.players[1].global_position.snapped(Vector3.ONE * 0.1), _next_ingredient(1), _needed_recipes()])


func _views() -> int:
	var n := 0
	for p in main.players:
		if p.has_meta("view") and p.get_meta("view").visible:
			n += 1
	return n


## Bring in the extra TV players one at a time, then exercise unplug / replug of the last one.
func _join_players(mode: String) -> void:
	if t < join_at or (mode == "client" and not main.synced):
		return
	if next_join <= want_players:
		join_at = t + 0.7
		if next_join == want_players and next_join >= 3:
			# Pretend P2 (and the split-screen chef) already own controllers, so the new one is a new player.
			if main.players[1].joy < 0:
				main.players[1].joy = FAKE_PAD + 1
			if mode == "local" and main.players[0].joy < 0:
				main.players[0].joy = FAKE_PAD + 2
			print("BOT: fake controller %d presses Start to join" % FAKE_PAD)
			var e := InputEventJoypadButton.new()
			e.device = FAKE_PAD
			e.button_index = JOY_BUTTON_START
			e.pressed = true
			Input.parse_input_event(e)
			var e2 := e.duplicate() as InputEventJoypadButton
			e2.pressed = false
			Input.parse_input_event(e2)
		else:
			print("BOT: debug_join(%d)" % next_join)
			main.debug_join(next_join)
		next_join += 1
		return
	if want_players < 3:
		return
	var p = main.players[want_players]
	if unplug_stage == 0 and t > 12.0:
		unplug_stage = 1
		print("BOT: P%d joy=%d paused=%s, unplugging controller %d" % [want_players + 1, p.joy, get_tree().paused, FAKE_PAD])
		main._on_joy_changed(FAKE_PAD, false)
	elif unplug_stage == 1 and not p.active:
		unplug_stage = 2
		print("BOT: P%d left after unplug (t=%.1f)" % [want_players + 1, t])
		main._on_joy_changed(FAKE_PAD, true)
	elif unplug_stage == 2 and p.active:
		unplug_stage = 3
		print("BOT: P%d rejoined after replug (t=%.1f) joy=%d" % [want_players + 1, t, p.joy])


## Prints each new feature the first time it shows up.
func _note_features() -> void:
	var types := {}
	for c in get_tree().get_nodes_in_group("kr_customers"):
		types[c.ctype] = true
	var guide := false
	for p in main.players:
		if p.has_meta("guide") and p.get_meta("guide").visible:
			guide = true
	var checks := {
		"chef guidance": str(main.chef_task.get("text", "")) != "",
		"runner job": main.players.size() > 1 and str(main.runner_job(main.players[1]).get("text", "")) != "",
		"guide arrow": guide,
		"stars": not main.stars.is_empty(),
		"dinner rush": main.rush_t > 0.0,
		"critic": types.has("critic"),
		"fire": main.fire_on,
		"raccoon": main.raccoon.visible,
		"stats": main.stats_text != "",
		"practice": main.practice and main.served_total == 0 and main.net.mode != "client",
		"practice done": not main.practice and main.served_total >= 1,
		"ghost hand": main.ghost_hand != null and main.ghost_hand.visible,
		"ghost chop": main.ghost_hand != null and main.ghost_hand.visible and main.ghost_hand.mode == "chop",
		"ghost stack": main.ghost_hand != null and main.ghost_hand.visible and main.ghost_hand.mode == "stack",
		"chef spot": main.chef_spot != null and main.chef_spot.visible,
		"crate glow": _any_glow(),
		"pass glow": main.pass_glow != null and main.pass_glow.visible,
		"new dish SALAD": main.unlocked_recipes().has("SALAD"),
		"new dish BURGER": main.unlocked_recipes().has("BURGER"),
		"new dish PIZZA": main.unlocked_recipes().has("PIZZA"),
		"props moving": main.props != null and (absf(float(main.props.pans[0]["ang"])) > 0.05 or main.props.bird_out > 0.0),
		"story card": main.story_count > 0,
		"invitations": _invites().size() == 2,
		"party chosen": main.round_info.has("picked") and str(main.round_info["picked"]) != "",
		"star guest": _star_guest(),
		"gift shelf": not main.gifts_shown.is_empty(),
		"golden gift": main.gifts_shown.any(func(g) -> bool: return bool(g[1])),
		"party dish": main.unlocked_recipes().has("MELT") or main.unlocked_recipes().has("WRAP") or main.unlocked_recipes().has("SANDWICH"),
	}
	for k in checks:
		if checks[k] and not seen.has(k):
			seen[k] = true
			var extra := ""
			if k == "chef guidance":
				extra = ": " + str(main.chef_task.get("text", ""))
			elif k == "runner job":
				extra = ": " + str(main.runner_job(main.players[1]).get("text", ""))
			elif k == "stars":
				extra = ": %s" % [main.stars]
			elif k == "party chosen":
				extra = ": %s by %s" % [main.round_info["party"], main.round_info["picked"]]
			elif k == "party dish":
				extra = ": %s" % [main.unlocked_recipes()]
			print("BOT: seen %s (t=%.0f, shift %d)%s" % [k, t, main.shift, extra])
	if main.props != null:
		for kind in main.props.touched:
			if not seen.has("prop:" + kind):
				seen["prop:" + kind] = true
				print("BOT: prop %s (t=%.0f)" % [kind, t])
	if main.story_count != int(get_meta("stories", 0)):
		set_meta("stories", main.story_count)
		var b: Dictionary = main.last_story
		print("BOT: story card %s / %s (%s)" % [b.get("who", ""), b.get("line", ""), b.get("pic", "")])
		if not RegEx.create_from_string("^[A-Z][A-Z' !]{1,15}$").search(str(b.get("who", ""))) or str(b.get("line", "")).length() > 28:
			bot_errors += 1
			print("BOT: ERROR story card text too long: %s / %s" % [b.get("who", ""), b.get("line", "")])
	for ty in types:
		if not seen.has("type:" + ty):
			seen["type:" + ty] = true
			print("BOT: customer type %s" % ty)


func _invites() -> Array:
	return main.all_items().filter(func(it) -> bool: return it.kind == "invite")


func _star_guest() -> bool:
	for c in get_tree().get_nodes_in_group("kr_customers"):
		if c.star:
			return true
	return false


func _any_glow() -> bool:
	for k in main.crate_glows:
		if main.crate_glows[k].visible:
			return true
	return false


## Fake VR chef: plays with the props now and then (pans, clock, grinder, a thrown veggie, the spoon).
## Returns true while busy.
func _play_props(delta: float) -> bool:
	var chef = main.players[0]
	var props = main.props
	if props == null or main.practice or t < play_at or chef.held[0] != null or chef.held[1] != null:
		return false
	if not playing:
		playing = true
		vr_t = 0.0
	var hl: Node3D = chef.hand_l
	var hr: Node3D = chef.hand_r
	# The hand point is 6 cm in front of and 2 cm below the controller.
	var off := Vector3(0, 0.02, 0.06)
	match play_step:
		0, 2:  # swing the left hand through a pan from the chef's side
			var c: Vector3 = props.pan_centre(0 if play_step == 0 else 1)
			var start := c + Vector3(0.25, 0.0, 0.0) + off
			var end := c + Vector3(-0.1, 0.0, 0.0) + off
			if vr_t < 0.6:
				hl.global_position = hl.global_position.move_toward(start, delta * 3.0)
			else:
				hl.global_position = hl.global_position.move_toward(end, delta * 2.0)
				if hl.global_position.distance_to(end) < 0.01:
					play_step += 1
					vr_t = 0.0
		1:  # touch the cuckoo clock and the pepper grinder
			var want: Vector3 = (props.CLOCK if vr_t < 0.8 else props.grinder.global_position + Vector3.UP * 0.18) + off
			hr.global_position = hr.global_position.move_toward(want, delta * 2.5)
			if vr_t > 1.8:
				play_step += 1
				vr_t = 0.0
		3:  # grab a veggie and throw it towards the runners
			var vg: Dictionary = props.veg[0]
			if props.held[1] == "":
				var want: Vector3 = vg["pos"] + Vector3(0, 0.05, 0.06)
				hr.global_position = hr.global_position.move_toward(want, delta * 2.0)
				chef.fake_trigger[1] = 1.0 if hr.global_position.distance_to(want) < 0.01 and chef.fake_trigger[1] == 0.0 else 0.0
				vr_t = minf(vr_t, 0.99)
				if t > play_at + 30.0:
					play_step = 99
			elif vr_t < 1.3:
				hr.global_position += Vector3(0.0, 1.5, -3.0) * delta
			else:
				chef.fake_trigger[1] = 0.0
				play_step += 1
				vr_t = 0.0
		4:  # pick up the spoon and bang it on the counter, then on the bell
			var bell: Node3D = main.parts.get("bell")
			if props.held[1] == "":
				var want2: Vector3 = props.spoon.global_position + Vector3(0, 0.03, 0.06)
				hr.global_position = hr.global_position.move_toward(want2, delta * 2.0)
				chef.fake_trigger[1] = 1.0 if hr.global_position.distance_to(want2) < 0.01 and chef.fake_trigger[1] == 0.0 else 0.0
				vr_t = minf(vr_t, 0.99)
				if t > play_at + 30.0:
					play_step = 99
			elif vr_t < 1.6:
				hr.global_position = hr.global_position.move_toward(Vector3(0.7, 1.2, 0.3), delta * 2.0)
			elif vr_t < 1.9:
				hr.global_position += Vector3(0.0, -2.5, 0.0) * delta
			elif vr_t < 2.6:
				var head: Vector3 = props.spoon_head()
				hr.global_position += (bell.global_position + Vector3.UP * 0.06 - head).limit_length(delta * 1.5)
			else:
				chef.fake_trigger[1] = 0.0
				play_step += 1
				vr_t = 0.0
		_:
			play_step = 0
			playing = false
			play_at = t + 40.0
			print("BOT VR: played with the props: %s" % [props.touched])
			return false
	return true


## Fake VR chef: moves the hands like a person would, following the chef's guidance.
func _chef_vr(delta: float) -> void:
	var chef = main.players[0]
	var hl: Node3D = chef.hand_l
	var hr: Node3D = chef.hand_r
	var head: Vector3 = chef.xr_camera.global_position
	var rest_r := head + Vector3(0.3, -0.55, -0.35)
	var rest_l := head + Vector3(-0.3, -0.55, -0.35)
	vr_t += delta
	if vr_state == "idle" and _play_props(delta):
		return
	var inv := _invites()
	if vr_state == "idle" and not inv.is_empty() and main.invite_t < main.INVITE_WAIT - 4.0 and main.invite_t > 1.0 and chef.held[1] == null:
		var head_pos: Vector3 = inv[1].global_position + Vector3(0, main.ItemScript.INVITE_LIFT, 0.06)
		hr.global_position = hr.global_position.move_toward(head_pos, delta * 1.5)
		if hr.global_position.distance_to(head_pos) < 0.03:
			chef.fake_trigger[1] = 1.0
			print("BOT VR: reached for an invitation")
		return
	var task: Dictionary = main.chef_task
	var it = task.get("item")
	var plate = task.get("plate")
	var held = chef.held[1]
	match vr_state:
		"idle":
			chef.fake_trigger[1] = 0.0
			hr.global_position = hr.global_position.lerp(rest_r, 0.2)
			hl.global_position = hl.global_position.lerp(rest_l, 0.2)
			if vr_t < (2.5 if main.practice else 0.4) or main.game_over:  # in practice: hesitate, watch the ghost hand
				return
			if held != null and is_instance_valid(held):
				vr_state = "carry"
			elif it != null and is_instance_valid(it) and it.holder == -1:
				vr_target = it
				vr_state = "chop_up" if it.needs_chop() and not main.fire_on else ("reach" if not it.needs_chop() else "idle")
			elif main.free_pass_slot(Vector3.ZERO) < 0:
				for i in 4:
					var junk = main.item_at(L.PASS_SLOTS[i], 0.15)
					if junk != null:
						vr_target = junk
						vr_state = "reach"
						break
			vr_t = 0.0
		"chop_up":
			if vr_target == null or not is_instance_valid(vr_target) or not vr_target.needs_chop():
				vr_state = "idle"
				return
			var above: Vector3 = vr_target.global_position + Vector3(0, 0.3, 0.18)
			hl.global_position = hl.global_position.move_toward(above, delta * 1.5)
			if hl.global_position.distance_to(above) < 0.02:
				vr_state = "chop_down"
				vr_t = 0.0
		"chop_down":
			if vr_target == null or not is_instance_valid(vr_target):
				vr_state = "idle"
				return
			var below: Vector3 = vr_target.global_position + Vector3(0, -0.02, 0.18)
			hl.global_position = hl.global_position.move_toward(below, delta * 2.6)
			if hl.global_position.distance_to(below) < 0.02 or vr_t > 0.6:
				vr_chops += 1
				if vr_chops <= 3:
					print("BOT VR: knife swing %d at the %s (chops %d)" % [vr_chops, vr_target.kind, vr_target.chops])
				vr_state = "chop_up" if vr_target.needs_chop() else "idle"
				vr_t = 0.0
		"reach":
			if vr_target == null or not is_instance_valid(vr_target) or vr_target.holder != -1:
				vr_state = "idle"
				return
			# hand_point is 6 cm in front of and 2 cm below the controller.
			var want: Vector3 = vr_target.global_position + Vector3(0, 0.06, 0.06)
			hr.global_position = hr.global_position.move_toward(want, delta * 1.5)
			if hr.global_position.distance_to(want) < 0.02:
				chef.fake_trigger[1] = 1.0
				vr_state = "carry"
				vr_t = 0.0
		"carry":
			held = chef.held[1]
			if held == null or not is_instance_valid(held):
				if vr_t > 0.3:
					vr_state = "idle"
					chef.fake_trigger[1] = 0.0
				return
			var dest: Vector3
			if plate != null and is_instance_valid(plate) and held.is_ready():
				dest = plate.global_position + Vector3(0, 0.14, 0.06)
			elif held.needs_chop():
				dest = L.BOARD + Vector3(0, 0.14, 0.06)
			else:
				dest = L.TRASH + Vector3(0, 0.14, 0.06)
			hr.global_position = hr.global_position.move_toward(dest, delta * 1.5)
			if hr.global_position.distance_to(dest) < 0.02:
				chef.fake_trigger[1] = 0.0
				vr_drops += 1
				if vr_drops <= 3:
					print("BOT VR: dropped the %s (task: %s)" % [held.kind, main.chef_task.get("text", "")])
				vr_state = "idle"
				vr_t = 0.0


# --- Chef ---------------------------------------------------------------------

func _needed_recipes() -> Array:
	var cs: Array = main._waiting_customers()
	cs.sort_custom(func(a, b) -> bool: return a.frac < b.frac)
	var need := []
	for c in cs:
		need.append(c.recipe)
	for it in main.all_items():
		if it.is_plate() and it.recipe != "":
			need.erase(it.recipe)
	for i in range(1, main.players.size()):
		var ck: String = main.players[i].carry_kind
		if ck.begins_with("plate:"):
			need.erase(ck.substr(6))
	return need


func _subset(a: Array, b: Array) -> bool:
	for k in a:
		if not b.has(k):
			return false
	return true


func _plan() -> Dictionary:
	var need := _needed_recipes()
	var plan := {}
	for h in 2:
		var p = main._home_plate(h)
		if p == null or p.recipe != "":
			continue
		var r := ""
		for cand in need:
			if _subset(p.contents, M.RECIPES[cand]):
				r = cand
				break
		if r != "":
			need.erase(r)
		plan[h] = r
	return plan


func _spot_of(it) -> int:
	var best := 0
	var best_d := INF
	for i in L.spot_count():
		var d: float = main.flat_dist(it.global_position, L.spot_pos(i))
		if d < best_d:
			best_d = d
			best = i
	return best


func _chef(delta: float) -> void:
	chef_t -= delta
	if chef_t > 0.0 or main.game_over:
		return
	chef_t = 0.15
	var chef = main.players[0]
	var inv := _invites()
	if not inv.is_empty() and chef.held[0] == null and main.invite_t < main.INVITE_WAIT - 4.0 and main.invite_t > 2.0:
		chef.cursor = _spot_of(inv[0])
		chef.do_grab()
		print("BOT: the chef grabbed an invitation")
		return
	var plan := _plan()
	var held = chef.held[0]
	if held != null:
		if held.is_plate():
			chef.cursor = 4
			chef.do_grab()
			return
		for h in plan:
			var p = main._home_plate(h)
			if plan[h] != "" and held.is_ready() and M.RECIPES[plan[h]].has(held.kind) and not p.contents.has(held.kind):
				chef.cursor = 5 if h == 0 else 7
				chef.do_grab()
				return
		var slot: int = main.free_pass_slot(Vector3.ZERO)
		if not _wanted(held.kind, plan) or slot < 0:
			chef.cursor = 4
		else:
			chef.cursor = slot
		chef.do_grab()
		return
	for h in plan:
		var p = main._home_plate(h)
		if plan[h] == "":
			if p.contents.size() > 0:
				chef.cursor = 5 if h == 0 else 7
				chef.do_grab()
				return
			continue
		for k in M.RECIPES[plan[h]]:
			if p.contents.has(k):
				continue
			var it = _counter_item(k)
			if it == null:
				continue
			chef.cursor = _spot_of(it)
			if it.needs_chop():
				if not main.fire_on:
					chef.do_chop()
					return
				continue
			chef.do_grab()
			return
	# Pass clogged with things nobody needs: bin one.
	if main.free_pass_slot(Vector3.ZERO) < 0:
		for i in 4:
			var it2 = main.item_at(L.PASS_SLOTS[i], 0.15)
			if it2 != null and not _wanted(it2.kind, plan):
				chef.cursor = i
				chef.do_grab()
				return


func _wanted(kind: String, plan: Dictionary) -> bool:
	for h in plan:
		if plan[h] != "" and M.RECIPES[plan[h]].has(kind):
			return true
	return false


func _counter_item(kind: String):
	for it in main.all_items():
		if it.holder == -1 and not it.is_plate() and it.kind == kind:
			return it
	return null


# --- Runners ------------------------------------------------------------------

func _next_ingredient(index: int) -> String:
	var need := _needed_recipes().slice(0, 2)
	var missing := []
	for r in need:
		for k in M.RECIPES[r]:
			missing.append(k)
	for h in 2:
		var p = main._home_plate(h)
		if p != null and p.recipe == "":
			for k in p.contents:
				missing.erase(k)
	for it in main.all_items():
		if not it.is_plate() and it.holder == -1:
			missing.erase(it.kind)
		elif not it.is_plate() and it.holder == 0:
			missing.erase(it.kind)
	for i in range(1, main.players.size()):
		missing.erase(main.players[i].carry_kind)
	if missing.is_empty():
		return ""
	return missing[(index - 1) % missing.size()]


func _runner(p, delta: float) -> void:
	var cd: float = use_t.get(p.index, 0.0) - delta
	use_t[p.index] = cd
	var c: String = p.carry_kind
	var idle := Vector3(-1.5 + float((p.index - 1) % 4), 0.0, -1.6 - 0.6 * floorf(p.index / 4.0))
	var goal := idle
	if c == "":
		var plate = null
		var need := _needed_recipes_with_plates()
		for it in main.all_items():
			if it.is_plate() and it.recipe != "" and it.holder == -1 and need.has(it.recipe):
				plate = it
		var inv := _invites()
		if not inv.is_empty() and p.index == 1:
			goal = Vector3(inv[0].global_position.x, 0.0, -0.8)
		elif main.fire_on and main.ext_holder == -1 and p.index == want_players:
			goal = L.EXT_POS + Vector3(0, 0, 1.0)
		elif plate != null:
			goal = Vector3(plate.global_position.x, 0.0, -0.8)
		else:
			var kind := _next_ingredient(p.index)
			if kind != "":
				goal = L.source_stand(kind)
	elif c == "extinguisher":
		goal = L.STOVE + Vector3(0, 0, 1.4) if main.fire_on else L.EXT_POS + Vector3(0, 0, 1.0)
	elif c.begins_with("plate:"):
		for cu in main._waiting_customers():
			if cu.recipe == c.substr(6):
				goal = cu.serve_point()
	else:
		var slot: int = main.free_pass_slot(p.global_position)
		if slot >= 0:
			goal = Vector3(L.PASS_SLOTS[slot].x, 0.0, -0.8)
	_walk(p, goal, delta)
	if main.flat_dist(p.global_position, goal) < 0.7 and cd <= 0.0:
		var r: Dictionary = main.resolve(p)
		if r.has("act") and r["act"] != "return" and r["act"] != "put_ext":
			p.press_use()
			use_t[p.index] = 0.45


## Plates that some waiting customer still wants (counting plates already being carried).
func _needed_recipes_with_plates() -> Array:
	var need := []
	for c in main._waiting_customers():
		need.append(c.recipe)
	for i in range(1, main.players.size()):
		var ck: String = main.players[i].carry_kind
		if ck.begins_with("plate:"):
			need.erase(ck.substr(6))
	return need


func _walk(p, goal: Vector3, delta: float) -> void:
	var pos: Vector3 = p.global_position
	var wp := goal
	var inside := pos.z > -6.0
	var goal_inside := goal.z > -6.0
	if inside != goal_inside:
		if inside:
			wp = Vector3(0, 0, -6.9) if absf(pos.x) < 0.5 and pos.z < -4.75 else Vector3(0, 0, -5.0)
		else:
			wp = Vector3(0, 0, -5.0) if absf(pos.x) < 0.5 and pos.z > -7.15 else Vector3(0, 0, -6.9)
	elif inside:
		# Go round the counter on the garden side.
		var crossing := (pos.z > -0.7 or goal.z > -0.7) and signf(pos.x) != signf(goal.x) and absf(pos.x - goal.x) > 0.5
		if (absf(goal.x) > 1.8 and absf(pos.x) < 1.8 and goal.z > -0.7) or (absf(pos.x) > 1.8 and absf(goal.x) < 1.8 and pos.z > -0.7) or crossing:
			var side := signf(goal.x if absf(goal.x) > 1.8 else pos.x)
			var corner := Vector3(side * 1.95, 0, -0.95)
			if main.flat_dist(pos, corner) > 0.3 and pos.z > -0.85:
				wp = corner
			elif pos.z > -0.85 and absf(pos.x) < 1.8:
				wp = Vector3(pos.x, 0, -1.0)
	var to: Vector3 = wp - pos
	to.y = 0.0
	if to.length() < 0.15:
		p.bot_move = Vector3.ZERO
		return
	p.bot_move = to.normalized() * minf(1.0, to.length() * 2.0)
	p.yaw = atan2(-to.x, -to.z)
	# Unstick: if we haven't moved for a while, sidestep.
	var lp: Vector3 = last_pos.get(p.index, pos)
	if pos.distance_to(lp) < 0.01:
		stuck_t[p.index] = stuck_t.get(p.index, 0.0) + delta
	else:
		stuck_t[p.index] = 0.0
	last_pos[p.index] = pos
	if stuck_t.get(p.index, 0.0) > 0.6:
		p.bot_move = Basis(Vector3.UP, PI / 2.0) * p.bot_move + Vector3(0, 0, -0.5)


func _count_visuals(n: Node) -> int:
	var c := 0
	if (n is MeshInstance3D or n is MultiMeshInstance3D or n is CPUParticles3D or n is Label3D) and n.is_visible_in_tree():
		c += 1
	for ch in n.get_children():
		c += _count_visuals(ch)
	return c


## Visual teaching: picture cues instead of words; any instruction text in a tip spot is an error.
func _note_cues() -> void:
	if main.ghost_hand != null and main.ghost_hand.visible:
		cues["ghost_hand"] = true
	if main.help_panel != null and main.help_panel.visible:
		_tip_error("help panel", main.help_label.text)
	if main.center_label.modulate.a > 0.05:
		_check_headline("TV headline", main.center_label.text)
	if main.vr_center != null and main.vr_center.modulate.a > 0.05:
		_check_headline("VR headline", main.vr_center.text)
	if main.vr_hint != null and main.vr_hint.visible and main.vr_hint.text.strip_edges() != "":
		_tip_error("VR hint", main.vr_hint.text)
	if Engine.get_physics_frames() % 30 == 0:
		_check_cards(main)
		for item in main.all_items():
			if item.label != null and item.label.is_visible_in_tree() and item.label.text != "":
				_tip_error("a plate's word", item.label.text)
	var it: String = main.info_label.text
	if it != "" and it != "Syncing…":
		_tip_error("top line", it)
	for p in main.players:
		if not p.active or p.ghost or p.remote:
			continue
		if p.has_meta("guide") and p.get_meta("guide").visible:
			if p.index == 0:
				cues["chef_arrow"] = true
			else:
				var c: String = p.carry_kind
				if c.begins_with("plate:"):
					cues["serve_arrow"] = true
				elif c != "" and c != "extinguisher":
					cues["pass_arrow"] = true
				elif main.runner_job(p).has("kind"):
					cues["fetch_arrow"] = true
				elif str(main.runner_job(p).get("text", "")).contains("READY"):
					cues["plate_arrow"] = true
		if p.index == 0 and p.vr:
			if p.wrist_label != null and p.wrist_label.text != "" and not RegEx.create_from_string("^ROUND \\d+$").search(p.wrist_label.text):
				_tip_error("VR wrist", p.wrist_label.text)
			continue
		if p.hud == null:
			continue
		var h = p.hud
		if h.hint_label.visible and h.hint_label.text.strip_edges() != "":
			_tip_error("P%d hint line" % (p.index + 1), h.hint_label.text)
		for l in [h.carry_label, h.orders_label]:
			if l.visible and l.text.strip_edges() != "":
				_tip_error("P%d list" % (p.index + 1), l.text)
		if h.job_panel.visible:
			_tip_error("P%d job panel" % (p.index + 1), h.job_label.text)
		if p.camera != null:
			if int(p.camera.cull_mask) & int(p.body_layer()):
				if not cues.has("own_tag_shown"):
					bot_errors += 1
					print("BOT: ERROR P%d's view shows its own name tag" % (p.index + 1))
				cues["own_tag_shown"] = true
			else:
				cues["own_tag_hidden"] = true
		var key := str(p.get_meta("cue", ""))
		var box = p.get_meta("cue_box") if p.has_meta("cue_box") else null
		if key != "" and box != null and box.visible:
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


## The empty split-screen cells: a pulsing A + person, no "press A to join" words.
func _check_cards(n: Node) -> void:
	for c in n.get_children():
		if c.has_meta("filler"):
			if c.visible and c.get_node_or_null("JoinCue") != null:
				cues["join_card_cue"] = true
			for l in c.get_children():
				if l is Label and l.visible and l.text != "":
					_tip_error("join card", l.text)
		elif c is Control or c is CanvasLayer or c == main or c is SubViewportContainer:
			_check_cards(c)


func _check_headline(who: String, text: String) -> void:
	var tx := text.strip_edges()
	if tx == "" or headline_re.search(tx) != null:
		return
	_tip_error(who, tx)


func _tip_error(who: String, text: String) -> void:
	if not cues.has("tip_text"):
		bot_errors += 1
		print("BOT: ERROR instruction text on %s: %s" % [who, text.replace("\n", " / ")])
	cues["tip_text"] = true


## The checks behind "BOT RESULT": [label, ok] pairs.
func _checks() -> Array:
	var out: Array = []
	var mode: String = main.net.mode
	out.append(["no BOT: ERROR lines", bot_errors == 0])
	out.append(["the kitchen started", main.ready_to_play])
	if OS.has_environment("KR_LAZY"):
		out.append(["grumpy customers seen" if main.simple else "game over and restart", grumpy_seen if main.simple else Engine.has_meta("kr_restarted")])
		return out
	if mode == "client":
		out.append(["synced with the host", main.synced])
		out.append(["a round started", main.shift >= 1])
		if main.simple:
			out.append(["a story card arrived", main.story_count > 0])
		return out
	out.append(["customers were served", main.served_total >= 1])
	out.append(["got past the first round", max_shift >= 2 or OS.has_environment("KR_START_SHIFT")])
	if main.simple:
		out.append(["story cards shown", main.story_count > 0])
		out.append(["a party round was made", not main.round_info.is_empty()])
		out.append(["a gift went on the shelf", not main.gifts_shown.is_empty()])
	return out


func _result() -> bool:
	for c in _checks():
		if not c[1]:
			return false
	return true


func _finish() -> void:
	if finished or main == null or not is_instance_valid(main) or main.net == null:
		return
	finished = true
	var cs := _checks()
	var bad := 0
	for c in cs:
		if not c[1]:
			bad += 1
			print("SCRIPT ERROR: BOT ASSERT FAILED: %s: %s" % [main.net.mode, c[0]])
	if bad == 0:
		print("[%6.1fs] BOT RESULT: PASS (%d checks)" % [t, cs.size()])
	else:
		print("SCRIPT ERROR: BOT RESULT: FAIL (%d of %d checks failed)" % [bad, cs.size()])


func _exit_tree() -> void:
	_finish()
	if main != null and is_instance_valid(main) and main.simple:
		var ks: Array = cues.keys()
		ks.sort()
		print("BOT CUES: mode=%s %s" % [main.net.mode, ",".join(PackedStringArray(ks))])
		for p in main.players:
			if p.has_meta("cue_done"):
				print("BOT CUES: P%d done=%s" % [p.index + 1, p.get_meta("cue_done")])
	if main != null:
		print("FINAL mode=%s shift=%d coins=%d served=%d angry=%d stars=%s seen=%s" % [main.net.mode, main.shift, main.coins, main.served_total, main.angry, main.stars, seen.keys()])
		print("Visual instances in the scene: %d" % _count_visuals(main))
		if OS.has_environment("KR_BREAKDOWN"):
			var by := {}
			for ch in main.get_children():
				var key: String = ch.get_script().resource_path.get_file() if ch.get_script() else ch.get_class()
				by[key] = by.get(key, 0) + _count_visuals(ch)
			print("Breakdown: %s" % by)
