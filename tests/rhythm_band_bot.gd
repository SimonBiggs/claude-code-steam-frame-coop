extends Node
## Headless bot for Rhythm Band. Every local guitarist presses its lanes on time (with a little human
## wobble and the odd skipped note, to exercise misses); the drummer either taps A S D F (local) or,
## in "fake VR" mode, swings two virtual stick tips down into the drums so the same hand-speed +
## proximity detection as the headset runs (BOT_FAKE_VR=1, and always on a DUO_HOST host).
## BOT_PLAYERS=N: guitarists (local split screen: up to 5; TV machine: up to 6).
## Songs are shortened to 5 bars of notes unless BOT_FULL=1; intros are skipped after a moment and the
## tour jumps from song 1 to the last song, so a short run sees the tour results, awards and a new menu.
## Local mode also joins one guitarist by pressing A on a fake controller, and checks Start does NOT join.
## SETLIST menu: the guitarists pick different levels (EASY / ROCK / NORMAL...) - the fake controller
## with real D-pad / A presses - and get ready; the drummer picks a level (flat: the tom = ROCK, fake VR:
## the hi-hat = EASY) and starts the show with the crash (the second tour starts when everyone is ready). In song 2 the star meter is
## filled so a TV player's Y (or the drummer's crash) sets off STAR POWER.
## Real controllers are attached to this machine: their presses are swallowed (they must not pause
## or join the test), and if anything else pauses the game the bot resumes it.
## SIMPLE_MODE (main.gd): no menu, no star power. The bot plays the PRACTICE (guitarists press the
## lane of the note waiting on their ring, the drummer hits the glowing drum - fake VR swings, flat taps
## the key); in fake VR it first touches every stage toy (props.gd), picks up a maraca and shakes it.
## Songs 1, 2, 3 play in a row (song 1 must use only the outer lanes, song 2 adds the middle one, song
## 3 has NORMAL drums, no gold notes anywhere); the bot prints "BOT CHECK ..." lines and quits after
## song 3 (BOT_VR=1 is the same as BOT_FAKE_VR=1).

const FAKE_PAD := 40

var main
var t := 0.0
var joined := false
var join_time := 0.0
var report_t := 0.0
var cont_t := 0.0
var songs_done := 0
var was_results := false
var fake_vr := false
var drum_pressed := {}
var lane_keys: Array[Key] = [KEY_A, KEY_S, KEY_D, KEY_F]
var my_pause := false
var paused_t := 0.0
var menus_seen := 0
var menu_steps := {}
var star_forced := -1
var stars_used := 0
var simple := false
var prop_k := 0
var prop_t := 0.0
var props_done := false
var prac_tapped := -1
var checks := {}
var quit_t := -1.0


class RealPadFilter extends Node:
	## Sits after the bot in the tree, so it sees input first: real controllers (device < 40) are ignored.
	func _input(event: InputEvent) -> void:
		var jb := event as InputEventJoypadButton
		var jm := event as InputEventJoypadMotion
		if (jb != null and jb.device < FAKE_PAD) or (jm != null and jm.device < FAKE_PAD):
			get_viewport().set_input_as_handled()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps running if the Start check opened the pause menu
	main = load("res://games/rhythm_band/main.tscn").instantiate()
	if not OS.has_environment("BOT_FULL"):
		main.song_bars = 5
	add_child(main)
	simple = main.SIMPLE_MODE
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


func _key_press(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.keycode = k
		e.pressed = down
		Input.parse_input_event(e)


## Same wobble for a note every time (-1..1), so runs are repeatable.
func _wob(i: int, salt: int) -> float:
	var x := sin(float(i) * 12.9898 + float(salt) * 78.233) * 43758.5453
	return (x - floorf(x)) * 2.0 - 1.0


func _process(delta: float) -> void:
	t += delta
	if main == null or not main.ready_to_play:
		return
	var mode: String = main.net.mode
	_unstick(delta)
	if not joined and t > (3.0 if mode == "client" else 1.0):
		joined = true
		join_time = t
		_join_players(mode)
		fake_vr = OS.has_environment("BOT_FAKE_VR") or OS.has_environment("BOT_VR") or mode == "host"
		if fake_vr and not main.players[0].ghost and not main.players[0].vr:
			main.players[0].fake_vr = true
			print("BOT: driving the drummer's hands (fake VR)")
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
		print("BOT: fake controller %d drives P%d" % [FAKE_PAD, int(main.joy_owner.get(FAKE_PAD, -1)) + 1])
	if main.state == "practice":
		_practice(mode, delta)
	if main.state == "menu":
		_drive_menu(mode)
	else:
		menu_steps.clear()
	if mode != "client" and main.state == "intro" and main.state_t > 1.5 and main.state_t < 3.0:
		main.state_t = 99.0  # short runs: skip the intro text
	if main.state == "play" and main.song != null:
		_check_song()
		if not simple:
			_force_star(mode)
		_play_guitars()
		if mode != "client":
			if main.players[0].fake_vr:
				_swing_drums()
			else:
				_tap_drums()
	var res: bool = main.state == "results"
	if res and not was_results:
		songs_done += 1
		print("BOT %s: SONG %d COMPLETE ('%s') - %d stars, score %d, crowd %d%%, sync %d" % [mode, int(main.tour_pos) + 1, str(main.song.title),
			int(main.last_stars), int(main.score), int(main.crowd * 100.0), int(main.sync_count)])
		if simple and songs_done >= 3 and quit_t < 0.0:
			quit_t = t + 2.0
			_final_checks(mode)
		if mode != "client" and int(main.tour_pos) == 0 and not OS.has_environment("BOT_FULL") and not simple:
			main.tour_pos = 1  # jump to the last song of the tour
	if main.state == "tour" and not has_meta("tour_seen%d" % menus_seen):
		set_meta("tour_seen%d" % menus_seen, true)
		print("BOT %s: TOUR COMPLETE - awards: %s" % [mode, str(main.get_meta("awards", "")).replace("\n", " | ")])
	was_results = res
	if (main.state == "results" or main.state == "tour") and main.state_t > 2.0:
		cont_t -= delta
		if cont_t <= 0.0:
			cont_t = 1.0
			main.debug_continue()
	if quit_t > 0.0 and t > quit_t:
		print("BOT %s: done" % mode)
		get_tree().quit()
		quit_t = 1e9
	report_t -= delta
	if report_t <= 0.0:
		report_t = 4.0
		_report(mode)


## SIMPLE_MODE PRACTICE: (fake VR) touch every toy first, then everyone does their practice notes.
func _practice(mode: String, delta: float) -> void:
	var d = main.players[0]
	if not checks.has("practice_seen"):
		checks["practice_seen"] = true
		print("BOT %s: PRACTICE started" % mode)
	# Guitarists: press the lane of the waiting note once it has arrived.
	for p in main.players:
		if p.index == 0 or not p.active or not p.is_local():
			continue
		if int(p.prac_step) < main.PRACTICE_LANES.size() and float(p.prac_t) > 1.7:
			var lane: int = main.PRACTICE_LANES[int(p.prac_step)]
			if p.joy >= FAKE_PAD:
				var buttons: Array[JoyButton] = [JOY_BUTTON_X, JOY_BUTTON_A, JOY_BUTTON_B]
				_pad_press(p.joy, buttons[lane])
			else:
				p.press(lane)
	if mode == "client" or d.ghost:
		return
	if d.fake_vr and d.props != null and not props_done:
		_touch_props(d, delta)
		return
	var k: int = main.prac_d
	if k >= main.PRACTICE_PADS.size():
		if d.fake_vr:
			d.fake_tips[0] = d.pads[1].global_position + Vector3(0, 0.3, 0)
			d.fake_tips[1] = d.pads[2].global_position + Vector3(0, 0.3, 0)
		return
	var pad: int = main.PRACTICE_PADS[k]
	if d.fake_vr:
		# Hover over the glowing drum while the ball floats in, then swing down onto it.
		var h := 0 if pad <= 1 else 1
		var c: Vector3 = d.pads[pad].global_position
		var down := clampf((float(main.prac_t) - 1.9) / 0.15, 0.0, 1.0)
		d.fake_tips[h] = c + Vector3(0, 0.3 * (1.0 - down), 0)
		d.fake_tips[1 - h] = d.pads[2 if h == 0 else 1].global_position + Vector3(0, 0.3, 0)
	elif not d.vr and float(main.prac_t) > 1.9 and prac_tapped != k:
		prac_tapped = k
		_key_press(lane_keys[pad])


## Fake VR: swing each hand through every stage toy, then pick up a maraca, shake it and put it back.
func _touch_props(d, delta: float) -> void:
	var props = d.props
	prop_t += delta
	var n: int = props.items.size()
	var rest_l: Vector3 = d.pads[1].global_position + Vector3(0, 0.3, 0)
	var rest_r: Vector3 = d.pads[2].global_position + Vector3(0, 0.3, 0)
	if prop_k < n:
		var tp: Vector3 = props._touch_point(prop_k)
		var h := 0 if float(props.items[prop_k].base.x) < 0.0 else 1
		# Come in from 25 cm above, through the toy, and away again.
		var ph := clampf(prop_t / 0.5, 0.0, 1.0)
		var tip := tp + Vector3(0, 0.25 - 0.5 * ph, 0)
		d.fake_tips[h] = tip
		d.fake_tips[1 - h] = rest_l if h == 1 else rest_r
		if prop_t > 0.6:
			prop_t = 0.0
			prop_k += 1
		return
	# The maraca: hold it in the right hand and shake it up and down for a second.
	if prop_k == n:
		props.force_grab = true
		d.fake_tips[0] = rest_l
		d.fake_tips[1] = rest_r + Vector3(0.1, 0.0, 0.2) + Vector3(0, 0.08 * sin(prop_t * 30.0), 0)
		if prop_t > 1.2:
			props.force_grab = false
			prop_k += 1
			prop_t = 0.0
		return
	d.fake_tips[1] = rest_r
	if prop_t > 0.5:
		props_done = true
		var kinds: Dictionary = props.touched
		print("BOT CHECK props: touched %s, shakes %d, held %d -> %s" % [str(kinds), int(props.shakes), int(props.held),
			"PASS" if kinds.size() >= 6 and int(props.shakes) >= 3 and int(props.held) < 0 else "FAIL"])


## Simple mode: what each song should look like (checked once per song).
func _check_song() -> void:
	if not simple or checks.has("song%d" % int(main.song_serial)):
		return
	checks["song%d" % int(main.song_serial)] = true
	var g = main.song
	var lanes := {}
	for l in g.g_lane:
		lanes[int(l)] = true
	var gold := 0
	for v in g.g_star:
		gold += int(v)
	for v in g.d_star:
		gold += int(v)
	var pos := int(main.tour_pos)
	var want_lanes := 2 if pos == 0 else 3
	var ok: bool = lanes.size() == want_lanes and gold == 0 and int(main.drum_level) == (0 if pos < 2 else 1)
	if pos == 0:
		ok = ok and not lanes.has(1)
	print("BOT CHECK song %d '%s' %d BPM: lanes %s, gold notes %d, drum level %d, guitar notes %d, drum notes %d -> %s" % [pos + 1,
		str(g.title), int(g.bpm), str(lanes.keys()), gold, int(main.drum_level), g.g_t.size(), g.d_t.size(), "PASS" if ok else "FAIL"])


func _final_checks(mode: String) -> void:
	var d = main.players[0]
	var gs := ""
	for p in main.players:
		if p.index > 0 and p.active and p.is_local():
			gs += " P%d %d/%d" % [p.index + 1, int(p.hits), int(p.hits) + int(p.misses)]
	print("BOT CHECK %s: practice seen %s, songs %d, menus %d, star power %d -> %s" % [mode, checks.has("practice_seen"), songs_done,
		menus_seen, stars_used, "PASS" if checks.has("practice_seen") and menus_seen == 0 and stars_used == 0 else "FAIL"])
	print("BOT %s: last song drums %d/%d%s" % [mode, int(d.hits), int(d.hits) + int(d.misses), gs])


func _join_players(mode: String) -> void:
	if mode == "host":
		return
	var want := int(OS.get_environment("BOT_PLAYERS")) if OS.has_environment("BOT_PLAYERS") else (2 if mode == "local" else 1)
	var cap := 5 if mode == "local" else 6
	var extra := clampi(want, 1, cap) - 1
	print("BOT: %s mode, joining %d extra guitarists" % [mode, extra])
	if mode == "local":
		my_pause = true
		_pad_press(FAKE_PAD + 1, JOY_BUTTON_START)  # Start must open the menu, not join
		if extra > 0:
			set_meta("pad_join", true)
			extra -= 1
	for i in extra:
		var p = main.debug_join()
		print("BOT: debug_join -> %s" % ("P%d" % (p.index + 1) if p != null else "none"))


## The SETLIST menu: guitarists pick levels and get ready, the drummer picks NORMAL and starts.
func _drive_menu(mode: String) -> void:
	var st: float = main.state_t
	if not menu_steps.has("seen"):
		menu_steps["seen"] = true
		menus_seen += 1
		print("BOT %s: SETLIST menu #%d %s" % [mode, menus_seen, str(main.setlist)])
	var lv := [0, 2, 1, 0, 2, 1]
	if st > 1.6 and not menu_steps.has("levels"):
		menu_steps["levels"] = true
		for p in main.players:
			if p.index == 0 or not p.active or not p.is_local():
				continue
			var want: int = lv[(p.index - 1 + menus_seen - 1) % lv.size()]
			if p.joy >= FAKE_PAD:
				# The fake controller: real D-pad presses to the level.
				for k in absi(want - int(p.level)):
					_pad_press(p.joy, JOY_BUTTON_DPAD_RIGHT if want > int(p.level) else JOY_BUTTON_DPAD_LEFT)
			else:
				p.set_level(want)
		print("BOT %s: guitarists picked their levels" % mode)
	if st > (3.5 if menus_seen == 1 else 1.6) and not menu_steps.has("ready"):
		menu_steps["ready"] = true
		for p in main.players:
			if p.index == 0 or not p.active or not p.is_local():
				continue
			if p.joy >= FAKE_PAD:
				_pad_press(p.joy, JOY_BUTTON_A)  # A = READY
			else:
				p.set_ready(true)
	if mode == "client" or menus_seen > 1:
		return
	var d = main.players[0]
	if d.fake_vr:
		# Swing into the hi-hat (EASY), then the crash (START).
		var pad := 0 if st < 2.4 else 3
		var c: Vector3 = d.pads[pad].global_position
		var phase := fmod(st, 1.1)
		d.fake_tips[0 if pad == 0 else 1] = c + Vector3(0, 0.3 * clampf(1.0 - phase * 3.0, 0.0, 1.0) if st > 1.0 else 0.3, 0)
		d.fake_tips[1 if pad == 0 else 0] = d.pads[1 if pad == 3 else 2].global_position + Vector3(0, 0.3, 0)
	elif not d.vr:
		if st > 1.0 and not menu_steps.has("tom"):
			menu_steps["tom"] = true
			_key_press(KEY_D)  # the tom: ROCK
		if st > 2.2 and not menu_steps.has("crash"):
			menu_steps["crash"] = true
			_key_press(KEY_F)


## Song 2: fill the star meter, then a TV player presses Y (or the drummer's crash sets it off).
func _force_star(mode: String) -> void:
	if mode == "client" or songs_done != 1 or star_forced == int(main.song_serial):
		if main.star_active() and not has_meta("star_seen%d" % int(main.song_serial)):
			set_meta("star_seen%d" % int(main.song_serial), true)
			stars_used += 1
			print("BOT %s: STAR POWER is on (song_t %.1f)" % [mode, float(main.song_t)])
		return
	if float(main.song_t) > 5.0:
		star_forced = int(main.song_serial)
		main.star_meter = 1.0
		print("BOT %s: star meter filled" % mode)
		for p in main.players:
			if p.index > 0 and p.active and p.is_local():
				if p.joy >= FAKE_PAD:
					_pad_press(p.joy, JOY_BUTTON_Y)
				else:
					main.request_star(p)
				break


func _play_guitars() -> void:
	var g = main.song
	var st: float = main.song_t
	var n: int = g.g_t.size()
	for p in main.players:
		if p.index == 0 or not p.active or not p.is_local():
			continue
		if p.judged.size() != n:
			continue
		var i: int = maxi(0, int(p.next_idx) - 2)
		while i < n:
			var tn: float = g.g_t[i]
			if tn > st + 0.1:
				break
			if p.judged[i] == 0 and _wob(i, p.index * 3) > -0.88:  # ~6% skipped
				if st >= tn + _wob(i, p.index) * 0.06:
					var lane: int = g.g_lane[i]
					if p.joy >= FAKE_PAD:
						var buttons: Array[JoyButton] = [JOY_BUTTON_X, JOY_BUTTON_A, JOY_BUTTON_B]
						_pad_press(p.joy, buttons[lane])
					else:
						p.press(lane)
					break
			i += 1


func _tap_drums() -> void:
	var g = main.song
	if int(get_meta("drum_serial", -1)) != int(main.song_serial):
		set_meta("drum_serial", int(main.song_serial))
		drum_pressed.clear()
	var st: float = main.song_t
	var n: int = g.d_t.size()
	var i: int = maxi(0, int(main.d_next) - 2)
	while i < n:
		var tn: float = g.d_t[i]
		if tn > st + 0.1:
			break
		if main.d_judged[i] == 0 and not drum_pressed.has(i) and _wob(i, 99) > -0.9:
			if st >= tn + _wob(i, 98) * 0.05:
				drum_pressed[i] = true
				_key_press(lane_keys[int(g.d_pad[i])])
		i += 1


## Fake VR: each hand hovers 30 cm over the drum its next ball goes to, and swings down onto it.
func _swing_drums() -> void:
	var d = main.players[0]
	var g = main.song
	var st: float = main.song_t
	var n: int = g.d_t.size()
	for h in 2:
		var target := -1
		var tdt := 0.0
		var i: int = maxi(0, int(main.d_next) - 2)
		while i < n:
			var pad: int = g.d_pad[i]
			var mine := (pad <= 1) == (h == 0)
			var tn: float = g.d_t[i]
			if mine and main.d_judged[i] == 0 and tn > st - 0.05:
				target = i
				tdt = tn - st + _wob(i, 7) * 0.03
				break
			i += 1
		var rest_pad := 1 if h == 0 else 2
		var tip: Vector3 = d.pads[rest_pad].global_position + Vector3(0, 0.3, 0)
		if target >= 0:
			var pad: int = g.d_pad[target]
			var c: Vector3 = d.pads[pad].global_position
			var skip := _wob(target, 55) < -0.9
			if tdt > 0.1 or skip:
				tip = c + Vector3(0, 0.3, 0)
			else:
				tip = c + Vector3(0, 0.3 * maxf(tdt, 0.0) / 0.1, 0)
		d.fake_tips[h] = tip


func _report(mode: String) -> void:
	var parts: Array[String] = []
	var d = main.players[0]
	parts.append("drums(%s) %d/%d" % [main.LEVEL_NAMES[int(main.drum_level)], int(d.hits), int(d.hits) + int(d.misses)])
	for p in main.players:
		if p.index > 0 and p.active:
			parts.append("P%d(%s%s) %d/%d" % [p.index + 1, main.LEVEL_NAMES[int(p.level)], " ready" if p.menu_ready and main.state == "menu" else "",
				int(p.hits), int(p.hits) + int(p.misses)])
	var views := 0
	for p in main.players:
		if p.has_meta("view") and p.get_meta("view").visible:
			views += 1
	var title: String = main.song.title if main.song != null else "-"
	if simple:
		print("BOT %s t=%.0f state=%s song=%d '%s' song_t=%.1f crowd=%d%% combo=%d prac_d=%d views=%d audio=%s [%s]" % [mode, t, main.state,
			int(main.tour_pos) + 1, title, float(main.song_t), int(main.crowd * 100.0), int(main.combo), int(main.prac_d), views,
			main.backing.stream != null, ", ".join(parts)])
		return
	print("BOT %s t=%.0f state=%s song=%d/%d '%s' song_t=%.1f crowd=%d%% combo=%d score=%d star=%.2f%s sync=%d songs_done=%d menus=%d stars_used=%d views=%d audio=%s [%s]" % [
		mode, t, main.state, int(main.tour_pos) + 1, int(main.SONGS_PER_TOUR), title, float(main.song_t), int(main.crowd * 100.0), int(main.combo),
		int(main.score), float(main.star_meter_value()), " ON" if main.star_active() else "", int(main.tour_sync), songs_done, menus_seen, stars_used,
		views, main.backing.stream != null, ", ".join(parts)])
