extends Node
## Headless bot for Rhythm Band. Every local guitarist presses its lanes on time (with a little human
## wobble and the odd skipped note, to exercise misses); the drummer either taps A S D F (local) or,
## in "fake VR" mode, swings two virtual stick tips down into the drums so the same hand-speed +
## proximity detection as the headset runs (BOT_FAKE_VR=1, and always on a DUO_HOST host).
## BOT_PLAYERS=N: guitarists (local split screen: up to 5; TV machine: up to 6).
## Songs are shortened to 6 bars of notes unless BOT_FULL=1.
## Local mode also joins one guitarist by pressing A on a fake controller, and checks Start does NOT join.

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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps running if the Start check opened the pause menu
	main = load("res://games/rhythm_band/main.tscn").instantiate()
	if not OS.has_environment("BOT_FULL"):
		main.song_bars = 6
	add_child(main)


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
	if not joined and t > (3.0 if mode == "client" else 1.0):
		joined = true
		join_time = t
		_join_players(mode)
		fake_vr = OS.has_environment("BOT_FAKE_VR") or mode == "host"
		if fake_vr and not main.players[0].ghost and not main.players[0].vr:
			main.players[0].fake_vr = true
			print("BOT: driving the drummer's hands (fake VR)")
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
		print("BOT: fake controller %d drives P%d" % [FAKE_PAD, int(main.joy_owner.get(FAKE_PAD, -1)) + 1])
	if main.state == "play" and main.song != null:
		_play_guitars()
		if mode != "client":
			if main.players[0].fake_vr:
				_swing_drums()
			else:
				_tap_drums()
	var res: bool = main.state == "results"
	if res and not was_results:
		songs_done += 1
		print("BOT %s: SONG %d COMPLETE - %d stars, score %d, crowd %d%%" % [mode, int(main.song_idx) + 1, int(main.last_stars),
			int(main.score), int(main.crowd * 100.0)])
	was_results = res
	if (main.state == "results" or main.state == "tour") and main.state_t > 2.0:
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
	print("BOT: %s mode, joining %d extra guitarists" % [mode, extra])
	if mode == "local":
		_pad_press(FAKE_PAD + 1, JOY_BUTTON_START)  # Start must open the menu, not join
		if extra > 0:
			set_meta("pad_join", true)
			extra -= 1
	for i in extra:
		var p = main.debug_join()
		print("BOT: debug_join -> %s" % ("P%d" % (p.index + 1) if p != null else "none"))


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
					if p.joy >= 0:
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
	parts.append("drums %d/%d" % [int(d.hits), int(d.hits) + int(d.misses)])
	for p in main.players:
		if p.index > 0 and p.active:
			parts.append("P%d %d/%d" % [p.index + 1, int(p.hits), int(p.hits) + int(p.misses)])
	var views := 0
	for p in main.players:
		if p.has_meta("view") and p.get_meta("view").visible:
			views += 1
	var title: String = main.song.title if main.song != null else "-"
	print("BOT %s t=%.0f state=%s song=%d '%s' song_t=%.1f crowd=%d%% combo=%d score=%d songs_done=%d views=%d audio=%s [%s]" % [
		mode, t, main.state, int(main.song_idx) + 1, title, float(main.song_t), int(main.crowd * 100.0), int(main.combo),
		int(main.score), songs_done, views, main.backing.stream != null, ", ".join(parts)])
