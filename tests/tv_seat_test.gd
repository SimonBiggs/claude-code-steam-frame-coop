extends SceneTree
## Pads at the TV join a streamed VR host through a local TV screen (core/tv_seat.gd, 2026-11-19: kids pressed A at the
## TV and nothing happened). Checks the decisions:
##   - streamed VR host detection (core/machine.gd: VR live on a non-arm64 machine; DUO_FAKE_STREAMED_VR overrides);
##   - the VR player's own controllers ("Steam Frame Controllers") are never a TV pad; bot pads only through the hook;
##   - TV prompt rules: nothing when not streamed / the TV is another game's / no pad; "join" with a pad; "starting"
##     until the TV screen joins; nothing once it has (it covers the mirror); "failed" for a while after a failure;
##   - starts: never two at once, one per MIN_GAP_MS, at most MAX_STARTS per WINDOW_MS, none while pads_off;
##   - the spawn command: flat, joins 127.0.0.1 on our port, its own user://, no LAN updates, VR/test/supervisor env
##     cleared, headless when we are, the pressing pad passed on, output to the log;
##   - the service's press(): one TV screen at most, rate limit, pads_off, a prompt that follows the pads (FAKE_PADS_META);
##   - room sound (core/room_audio.gd): off vrlink to HDMI, else another output, else "none" said;
##   - guards: TvSeat is a service; the shared input layers ignore the headset pad; party seats DUO_TV_CLIENT_PAD first.
##   godot-test --headless --path . -s res://tests/tv_seat_test.gd   -> TV SEAT: PASS / FAIL

const TvSeat := preload("res://core/tv_seat.gd")
const Machine := preload("res://core/machine.gd")
const RoomAudio := preload("res://core/room_audio.gd")
const TvShare := preload("res://core/tv_share.gd")

var fails: Array[String] = []


func _initialize() -> void:
	_streamed()
	_pads()
	_prompt()
	_starts()
	_command()
	_audio()
	_guards()
	_service.call_deferred()


func _finish() -> void:
	for f in fails:
		print("  FAIL ", f)
	print("TV SEAT: %s (%d problems)" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
	quit(0 if fails.is_empty() else 1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)


func _streamed() -> void:
	var had := OS.get_environment("DUO_FAKE_STREAMED_VR")
	OS.set_environment("DUO_FAKE_STREAMED_VR", "1")
	_check(Machine.streamed_vr_host(), "DUO_FAKE_STREAMED_VR=1 counts as a streamed VR host")
	OS.set_environment("DUO_FAKE_STREAMED_VR", "0")
	_check(not Machine.streamed_vr_host(), "DUO_FAKE_STREAMED_VR=0 does not")
	OS.unset_environment("DUO_FAKE_STREAMED_VR")
	_check(not Machine.streamed_vr_host(), "headless, no OpenXR: not a streamed VR host")
	var src := FileAccess.get_file_as_string("res://core/machine.gd")
	_check(src.contains("get_architecture_name().begins_with(\"arm\")"), "a native (arm64) Frame is never a streamed host")
	if had != "":
		OS.set_environment("DUO_FAKE_STREAMED_VR", had)


func _pads() -> void:
	_check(Machine.headset_pad_name("Steam Frame Controllers"), "the Frame's controllers are the VR player's hands")
	_check(not Machine.headset_pad_name("PS4 Controller"), "a PS4 pad is a TV pad")
	var pads := [{"id": 0, "name": "PS4 Controller"}, {"id": 2, "name": "Steam Frame Controllers"}, {"id": 40, "name": "bot pad"}]
	_check(TvSeat.real_pads(pads, false) == [0], "real pads: the PS4 only (%s)" % [TvSeat.real_pads(pads, false)])
	_check(TvSeat.real_pads(pads, true) == [0, 40], "with the bot hook: PS4 + bot pad")
	_check(TvSeat.real_pads([{"id": 2, "name": "Steam Frame Controllers"}], true).is_empty(), "the headset alone: no TV pad")


func _prompt() -> void:
	var long_ago := 1000000
	_check(TvSeat.prompt_state(false, 2, false, false, false, long_ago) == "", "not streamed: no prompt")
	_check(TvSeat.prompt_state(true, 0, false, false, false, long_ago) == "", "no pad: no prompt")
	_check(TvSeat.prompt_state(true, 1, false, false, false, long_ago) == "join", "a pad: Press A to join")
	_check(TvSeat.prompt_state(true, 1, true, false, false, long_ago) == "", "TV is another game's: no prompt")
	_check(TvSeat.prompt_state(true, 1, false, true, false, long_ago) == "starting", "running, not joined: starting")
	_check(TvSeat.prompt_state(true, 1, false, true, true, long_ago) == "", "joined: no prompt over the TV screen")
	_check(TvSeat.prompt_state(true, 1, false, false, false, 2000) == "failed", "just failed: says so")
	_check(TvSeat.prompt_state(true, 0, false, false, false, 2000) == "failed", "failure shows even if the pad went")
	_check(TvSeat.prompt_state(true, 1, false, false, false, TvSeat.FAIL_SHOW_MS + 1) == "join", "after the failure: join again")


func _starts() -> void:
	var now := 10000000
	_check(TvSeat.start_refusal(now, [], false, false) == "", "first start allowed")
	_check(TvSeat.start_refusal(now, [], true, false) != "", "never two TV screens")
	_check(TvSeat.start_refusal(now, [], false, true) != "", "no start while the TV is another game's")
	_check(TvSeat.start_refusal(now, [now - 1000], false, false) != "", "rate limit: one per MIN_GAP_MS")
	_check(TvSeat.start_refusal(now, [now - TvSeat.MIN_GAP_MS - 1], false, false) == "", "after MIN_GAP_MS: allowed")
	var many := []
	for i in TvSeat.MAX_STARTS:
		many.append(now - TvSeat.MIN_GAP_MS - 1 - i * 30000)
	_check(TvSeat.start_refusal(now, many, false, false).contains("too many"), "MAX_STARTS in WINDOW_MS: refused")
	_check(TvSeat.start_refusal(now + TvSeat.WINDOW_MS, many, false, false) == "", "old starts age out")


func _command() -> void:
	var spec := TvSeat.spawn_command({"exe": "/x/godot", "project": "/p/duo", "port": 23456, "pad": 3, "parent": 999,
		"headless": true, "log": "/p/duo/.dev/tv-seat.log", "data_home": "/u/tv_seat", "sdl_ignore": "0x1234/0x5678",
		"test_pad": false})
	var a: Array = spec.args
	var line := " ".join(a)
	_check(str(spec.path) == "/bin/sh" and a[0] == "-c" and str(a[1]).contains("exec \"$@\""), "through sh, exec'd (pid = the TV screen)")
	_check(a[3] == "/p/duo/.dev/tv-seat.log", "output to the log file")
	_check(a[4] == "/usr/bin/env", "env sets / clears its variables")
	for want in ["DUO_TV_CLIENT=1", "DUO_JOIN=127.0.0.1", "DUO_PORT=23456", "DUO_TV_CLIENT_PARENT=999", "DUO_TV_CLIENT_PAD=3",
			"DUO_UPDATE_RECEIVE=0", "XDG_DATA_HOME=/u/tv_seat", "SDL_GAMECONTROLLER_IGNORE_DEVICES=0x1234/0x5678"]:
		_check(a.has(want), "spawn env has %s" % want)
	for k in ["BOT_VR", "DUO_HOST", "ARCADE_GAME", "GDEV_SUPERVISED", "GDEV_RESTART_FILE", "VR_WATCH_FAKE", "DUO_FAKE_STREAMED_VR", "DUO_VR_LOST"]:
		var i := a.find(k)
		_check(i > 0 and a[i - 1] == "-u", "spawn clears %s" % k)
	var g := a.find("/x/godot")
	_check(g > 0 and a.slice(g) == ["/x/godot", "--path", "/p/duo", "--xr-mode", "off", "--headless"], "flat, our project, headless when we are (%s)" % [a.slice(g)])
	_check(not a.has("TV_SEAT_TEST_PAD=1"), "no test pad unless asked")
	var spec2 := TvSeat.spawn_command({"exe": "/x/godot", "project": "/p", "port": 7777, "pad": 0, "parent": 1,
		"headless": false, "log": "/l", "data_home": "/d", "sdl_ignore": "", "test_pad": true})
	_check(not (spec2.args as Array).has("--headless"), "a windowed host starts a windowed TV screen")
	_check(not " ".join(spec2.args).contains("SDL_GAMECONTROLLER_IGNORE_DEVICES"), "no SDL ignore when nothing to hide")
	_check((spec2.args as Array).has("TV_SEAT_TEST_PAD=1"), "test pad hook passed on")
	_check(not line.contains("DUO_JOIN=auto"), "the TV screen joins this machine, never 'auto'")


func _audio() -> void:
	var devs := ["Default", "vrlink-sink", "alsa_output.usb-headset", "alsa_output.pci-0000_04_00.1.hdmi-stereo"]
	var r := RoomAudio.choose(devs, "Default", "vrlink-sink")
	_check(bool(r.need) and str(r.pick).contains("hdmi"), "Default = vrlink: HDMI picked (%s)" % [r])
	r = RoomAudio.choose(devs, "vrlink-sink", "")
	_check(bool(r.need) and str(r.pick).contains("hdmi"), "vrlink chosen directly: HDMI picked")
	r = RoomAudio.choose(["Default", "vrlink-sink", "alsa_output.usb-speaker"], "Default", "vrlink-sink")
	_check(str(r.pick) == "alsa_output.usb-speaker", "no HDMI: any other output")
	r = RoomAudio.choose(["Default", "vrlink-sink"], "Default", "vrlink-sink")
	_check(bool(r.need) and str(r.pick) == "", "only the headset: none (said in the log)")
	r = RoomAudio.choose(devs, "Default", "alsa_output.pci-0000_04_00.1.hdmi-stereo")
	_check(not bool(r.need), "default already the TV: nothing to do")
	OS.set_environment("ROOM_AUDIO_FAKE_DEFAULT", "vrlink-sink")
	var got := RoomAudio.use_room_output("test")  # (headless: only "Default" exists, so: none, said)
	_check(got == "" and str(Engine.get_meta(RoomAudio.LAST_META, "")).contains("no other output"), "none found is said (%s)" % got)
	OS.unset_environment("ROOM_AUDIO_FAKE_DEFAULT")


func _guards() -> void:
	_check(FileAccess.get_file_as_string("res://core/services.gd").contains("res://core/tv_seat.gd"), "TvSeat is a service")
	_check(FileAccess.get_file_as_string("res://core/party.gd").contains("machine.gd\").headset_pad(device)"), "party ignores the headset pad")
	_check(FileAccess.get_file_as_string("res://core/party.gd").contains("DUO_TV_CLIENT_PAD"), "party seats the pressing pad first")
	_check(FileAccess.get_file_as_string("res://core/ui_input.gd").contains("Machine.headset_pad"), "ui_input ignores the headset pad")
	_check(FileAccess.get_file_as_string("res://core/dev/gdev_main.gd").contains("DUO_TV_CLIENT"), "gdev bridge leaves .dev to the VR host")
	# Only core/tv_seat.gd starts copies of the arcade (one place decides: never two TV screens).
	_scan("res://core")
	_scan("res://arcade")


func _scan(dir: String) -> void:
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		var p := dir.path_join(f)
		if f.ends_with(".gd") and p != "res://core/tv_seat.gd" and FileAccess.get_file_as_string(p).contains("DUO_TV_CLIENT=1"):
			fails.append("%s starts a TV screen itself: only core/tv_seat.gd does" % p)


## The service itself: prompt follows the pads, press() starts at most one, rate limit and pads_off refuse.
func _service() -> void:
	OS.set_environment("DUO_FAKE_STREAMED_VR", "1")
	var seat: Node = root.get_node_or_null("TvSeat")  # the service Boot started (core/services.gd)
	var own := seat == null
	if own:
		seat = TvSeat.new()
		root.add_child(seat)
	Engine.set_meta(TvSeat.FAKE_PADS_META, [{"id": 2, "name": "Steam Frame Controllers"}])
	await _frames(20)
	_check(seat.ui_text() == "", "headset pad only: no prompt (%s)" % seat.ui_text())
	Engine.set_meta(TvSeat.FAKE_PADS_META, [{"id": 0, "name": "PS4 Controller"}, {"id": 2, "name": "Steam Frame Controllers"}])
	await _frames(20)
	_check(seat.ui_text().begins_with(TvSeat.TEXT_JOIN), "a PS4 pad: '%s' (%s)" % [TvSeat.TEXT_JOIN, seat.ui_text()])
	Engine.set_meta(TvShare.META, true)
	await _frames(20)
	_check(seat.ui_text() == "", "TV is another game's: prompt gone")
	var n := (seat.starts as Array).size()
	seat.press(0)
	_check((seat.starts as Array).size() == n and seat.client_pid < 0, "pads_off: no start")
	Engine.set_meta(TvShare.META, false)
	# A start with a harmless stand-in for Godot (sleep), so no second game runs in this test.
	seat.client_pid = OS.create_process("/bin/sleep", ["1.5"])  # (exits by itself: Godot reaps a killed child itself)
	seat.client_started_ms = Time.get_ticks_msec()
	seat.starts.append(Time.get_ticks_msec())
	await _frames(20)
	_check(seat.ui_text().begins_with(TvSeat.TEXT_STARTING), "running, not joined: '%s' (%s)" % [TvSeat.TEXT_STARTING, seat.ui_text()])
	var pid: int = seat.client_pid
	seat.press(0)
	_check(seat.client_pid == pid and (seat.starts as Array).size() == n + 1, "never a second TV screen")
	seat.client_joined = true
	await _frames(20)
	_check(seat.ui_text() == "", "joined: no prompt over the TV screen")
	await _frames(80)
	_check(seat.client_pid < 0, "TV screen exit noticed")
	seat.press(0)
	_check(seat.client_pid < 0 and seat.fail_reason.contains("started"), "rate limit right after a start (%s)" % seat.fail_reason)
	await _frames(20)
	_check(seat.ui_text().begins_with(TvSeat.TEXT_FAILED), "refusal shown on the TV (%s)" % seat.ui_text())
	seat.client_joined = false
	seat.client_pid = OS.create_process("/bin/sleep", ["0.2"])
	await _frames(40)
	_check(seat.fail_reason == "it closed before joining", "a TV screen that dies before joining is a failure (%s)" % seat.fail_reason)
	OS.set_environment("DUO_FAKE_STREAMED_VR", "0")
	await _frames(20)
	_check(seat.ui_text() == "", "VR not streamed: no prompt")
	Engine.remove_meta(TvSeat.FAKE_PADS_META)
	OS.unset_environment("DUO_FAKE_STREAMED_VR")
	if own:
		seat.queue_free()
	await _frames(2)
	_finish()


## About n frames' worth of time (the service checks the prompt 4 times a second, whatever the frame rate).
func _frames(n: int) -> void:
	await create_timer(n * 0.02).timeout
	await process_frame
