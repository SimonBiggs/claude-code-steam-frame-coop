extends SceneTree
## The arcade survives SteamVR crashing (core/vr_watch.gd + tools/gdev RESTART). 2026-11-13: vrserver aborted when the
## Frame's stream stalled and SteamVR's vrclient.so then abort()ed the arcade from inside (can't be caught in GDScript).
## Checks:
##   - the vrlink log reading (headset connected after we started, still connected) and its timestamps;
##   - the restart specs: VR lost -> flat (--xr-mode off, DUO_VR_LOST, BOT_VR / ARCADE_GAME unset), the game kept;
##   - finding processes by name (/proc), own process found;
##   - guards (the pattern "a VR session not under the restart supervisor"): VrWatch is a service, launch.sh starts
##     the game with `gdev run`, tools/gdev restarts on crash signals / "now" from GDEV_RESTART_FILE; no other code
##     restarts or quits the game on OpenXR session loss (one place decides).
##   - launched while SteamVR wasn't running (2026-11-19: vrclient, loaded by the failed start, aborted the flat arcade
##     when SteamVR came up): the run waits for the headset quietly and its crash restart is a plain relaunch (VR if
##     the runtime is up, no --xr-mode off) in the same game; VR live turns the window's V-Sync off (the TV's 60 Hz
##     capped the 90 Hz headset) and puts it back after; one place does that (no game sets V-Sync itself);
##   - VR wanted (arcade-vr / launch-vr.sh, 2026-11-20): each step's TV words + .dev/vr_status, SteamVR asked for once,
##     the headset steps (waiting / asleep / ready), the wish done when VR is live and given up after WANT_TTL; the
##     flat-first restart spec; the headset's standby read from vrserver's log and an asleep loss's flat card;
##   godot-test --headless --path . -s res://tests/vr_watch_test.gd   -> VR WATCH: PASS / FAIL

const VrWatch := preload("res://core/vr_watch.gd")

var fails: Array[String] = []


func _initialize() -> void:
	_log_reading()
	_specs()
	_processes()
	_standby()
	_wanted()
	_guards()
	for f in fails:
		print("  FAIL ", f)
	print("VR WATCH: %s (%d problems)" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
	quit(0 if fails.is_empty() else 1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)


func _stamp(unix: float) -> String:
	# The vrlink log's local-time format: "Fri Nov 13 2026 18:18:31.835389"
	var bias := float(Time.get_time_zone_from_system().get("bias", 0)) * 60.0
	var d := Time.get_datetime_dict_from_unix_time(int(unix + bias))
	var mon: String = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][int(d.month) - 1]
	return "Fri %s %02d %d %02d:%02d:%02d.500000" % [mon, d.day, d.year, d.hour, d.minute, d.second]


func _log_reading() -> void:
	var now := Time.get_unix_time_from_system()
	var t := VrWatch.log_time(_stamp(now) + " [Info] - x")
	_check(absf(t - (floor(now) + 0.5)) < 1.01, "log_time: %s -> %f, wanted ~%f" % [_stamp(now), t, now])
	_check(VrWatch.log_time("garbage") == 0.0, "log_time of garbage should be 0")
	var start := now - 60.0
	var up_new := "%s [Info] - ReceivedHMDStaticProps. Model Number: Deckard MP\n" % _stamp(now - 5.0)
	var up_old := "%s [Info] - ReceivedHMDStaticProps. Model Number: Deckard MP\n" % _stamp(now - 600.0)
	var boot := "%s [Info] - vrserver 2.18.4 startup with PID=1, config=x\n" % _stamp(now - 8.0)
	var inactive := "%s [Info] - Connection inactive at 28.17\n" % _stamp(now - 2.0)
	_check(VrWatch.link_up_since(boot + up_new, start), "headset connected after we started: should count as back")
	_check(not VrWatch.link_up_since(up_old, start), "a connect from before we started must not count (restart loop)")
	_check(not VrWatch.link_up_since(boot + up_new + inactive, start), "connected then 'Connection inactive': not back")
	_check(not VrWatch.link_up_since(up_new + boot, start), "a vrserver start after the connect: not back yet")
	_check(not VrWatch.link_up_since("", start), "empty log: not back")
	# The real 2026-11-13 log: the last connect was before the crash, then the link went inactive.
	var real := "Fri Nov 13 2026 18:18:31.909258 [Info] - ReceivedHMDStaticProps. Model Number: Deckard MP\n" \
		+ "Fri Nov 13 2026 18:18:55.152840 [Info] - Connection inactive at 28.172165\n" \
		+ "Fri Nov 13 2026 18:19:09.935667 [Info] - vrserver 2.18.4 startup with PID=1294951, config=x\n"
	_check(not VrWatch.link_up_since(real, 0.0), "the 2026-11-13 crash log must read as 'headset not connected'")


func _specs() -> void:
	var w: Node = VrWatch.new()
	root.add_child(w)
	var spec: Dictionary = w.call("_flat_spec", "test", true)
	var args: Array = spec.get("args", [])
	_check(args.size() >= 2 and args[args.find("--xr-mode") + 1] == "off", "VR-lost restart must pass --xr-mode off: %s" % [args])
	_check(dict(spec.get("env", {})).has("DUO_VR_LOST"), "VR-lost restart must set DUO_VR_LOST")
	for k in ["BOT_VR", "ARCADE_GAME", "DUO_VR_REJOIN"]:
		_check(Array(spec.get("unset", [])).has(k), "VR-lost restart must unset %s" % k)
	_check(bool(spec.get("now", false)), "a loss asks for the restart now")
	_check(not bool(w.call("_flat_spec", "x", false).get("now", true)), "the armed spec is not 'now'")
	_check(not VrWatch.supervised() or OS.has_environment("GDEV_RESTART_FILE"), "supervised() needs the restart file")
	_check(not w.call("session_live"), "no headset in a test: session_live() must be false")
	# A clean exit nobody asked for (2026-11-19 19:44: headset standby, SteamVR down, Godot quit by itself, exit 0).
	_check((w.call("unasked_quit_spec") as Dictionary).is_empty(), "plain flat play: a quit is just a quit (no restart)")
	w.set("live", true)
	var uq: Dictionary = w.call("unasked_quit_spec")
	_check(bool(uq.get("now", false)) and Array(uq.get("args", [])).has("--xr-mode") and dict(uq.get("env", {})).has("DUO_VR_LOST"),
		"closing by itself while VR is live must restart flat now (--xr-mode off, DUO_VR_LOST): %s" % [uq])
	w.set("live", false)
	w.set("launch_flat", true)
	uq = w.call("unasked_quit_spec")
	_check(bool(uq.get("now", false)) and not Array(uq.get("args", [])).has("--xr-mode"),
		"closing by itself while flat waiting for VR must relaunch now, VR allowed: %s" % [uq])
	w.set("launch_flat", false)
	w.free()
	# Launched flat because SteamVR wasn't running.
	var ls: Dictionary = VrWatch.launch_flat_spec("kart_race")
	_check(not Array(ls.get("args", [])).has("--xr-mode"), "launch-flat crash restart must try VR again (no --xr-mode off): %s" % [ls])
	_check(dict(ls.get("env", {})).get("DUO_RESUME_GAME", "") == "kart_race", "launch-flat crash restart keeps the game")
	_check(not bool(ls.get("now", true)), "launch-flat restart is armed for a crash only (not 'now')")
	for k in ["DUO_VR_LOST", "DUO_VR_REJOIN"]:
		_check(Array(ls.get("unset", [])).has(k), "launch-flat restart must unset %s" % k)
	OS.set_environment("VR_WATCH_FAKE", "1")
	OS.set_environment("VR_WATCH_FAKE_FAILED", "1")
	var lf: Node = VrWatch.new()
	root.add_child(lf)
	if not lf.is_node_ready():
		lf.call("_ready")  # (-s scripts: the tree isn't running yet in _initialize)
	_check(bool(lf.get("launch_flat")) and float(lf.get("lost_at")) > 0.0, "a run whose OpenXR failed at launch must wait for the headset (launch_flat)")
	lf.set("_t", 0.0)
	lf.call("_process", 0.016)
	_check(String(lf.call("ui_text")) == "", "launch_flat with no headset: nothing on the TV (was '%s')" % lf.call("ui_text"))
	_check(lf.get("state") == "lost", "launch_flat waits in state lost (was %s)" % lf.get("state"))
	lf.free()
	OS.unset_environment("VR_WATCH_FAKE_FAILED")
	var nf: Node = VrWatch.new()
	root.add_child(nf)
	if not nf.is_node_ready():
		nf.call("_ready")
	_check(not bool(nf.get("launch_flat")), "a run without the failed-XR sign must not count as launch_flat")
	nf.free()
	OS.unset_environment("VR_WATCH_FAKE")
	var src := FileAccess.get_file_as_string("res://core/vr_watch.gd")
	_check(src.contains("window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)") and src.contains("_pace_for_vr(now_live)"),
		"core/vr_watch.gd must turn V-Sync off while VR is live (Frame 90 Hz vs TV 60 Hz)")


func _standby() -> void:
	var now := Time.get_unix_time_from_system()
	var boot := "%s [Info] - vrserver 2.18.4 startup with PID=1, config=x\n" % _stamp(now - 600.0)
	var sleep := "%s [Info] - 0 - entering standby\n" % _stamp(now - 60.0)
	var ctrl := "%s [Info] - 1 - entering standby\n" % _stamp(now - 50.0)
	var wake := "%s [Info] - 0 - leaving standby\n" % _stamp(now - 5.0)
	_check(absf(VrWatch.standby_since(boot + sleep) - (floor(now - 60.0) + 0.5)) < 1.01, "headset standby time read from vrserver's log")
	_check(VrWatch.standby_since(boot + sleep + ctrl) > 0.0, "a CONTROLLER's standby (device 1) doesn't wake the headset")
	_check(VrWatch.standby_since(boot + ctrl) == 0.0, "only device 0 (the headset) counts as the headset asleep")
	_check(VrWatch.standby_since(boot + sleep + wake) == 0.0, "left standby: awake")
	_check(VrWatch.standby_since(sleep + boot) == 0.0, "vrserver restarted after the standby: not asleep")
	_check(VrWatch.woke_since(boot + sleep + wake, now - 30.0), "woke after 'since': counts as back")
	_check(not VrWatch.woke_since(boot + sleep + wake, now - 1.0), "woke before 'since': not back")
	_check(not VrWatch.woke_since(boot + wake + sleep, 0.0), "asleep again after waking: not back")
	# The real 2026-11-19 log: standby 19:37, controllers 19:42 (the battery ran low), no wake before SteamVR went.
	var real := "Thu Nov 19 2026 19:37:37.218291 [Info] - 0 - entering standby\n" \
		+ "Thu Nov 19 2026 19:42:37.359642 [Info] - 1 - entering standby\n"
	_check(VrWatch.standby_since(real) > 0.0, "the 2026-11-19 log must read as 'headset asleep'")
	# A loss while asleep: the flat run's card says so (charge it), the restart carries DUO_VR_ASLEEP.
	var w: Node = VrWatch.new()
	root.add_child(w)
	w.set("asleep_since", now - 200.0)
	_check(dict(w.call("_flat_spec", "headset asleep", true).get("env", {})).has("DUO_VR_ASLEEP"),
		"a loss while the headset sleeps must restart flat with DUO_VR_ASLEEP (the 'headset asleep' card)")
	w.set("asleep_since", 0.0)
	_check(not dict(w.call("_flat_spec", "x", true).get("env", {})).has("DUO_VR_ASLEEP"), "awake loss: no DUO_VR_ASLEEP")
	w.set("asleep_flat", true)
	w.set("lost_at", now)
	OS.set_environment("VR_WATCH_SERVER", VrWatch.proc_comm(OS.get_process_id()))  # "SteamVR" = this process: running
	OS.set_environment("VR_WATCH_SERVER_LOG", "/nonexistent/vrserver.txt")
	w.call("_show_ui")
	var t := String(w.call("ui_text"))
	_check(t.contains("asleep") and t.contains("charge"), "asleep flat card must say asleep + charge it (was '%s')" % t)
	_check(String(w.call("_stopped_line")).begins_with("Headset asleep"), "asleep banner: %s" % w.call("_stopped_line"))
	OS.set_environment("VR_WATCH_SERVER", "no-such-vrserver-xyz")
	w.set("asleep_flat", false)
	_check(String(w.call("_stopped_line")).contains("ask Claude"), "SteamVR gone entirely: the banner says to ask for VR again (was '%s')" % w.call("_stopped_line"))
	w.free()
	OS.unset_environment("VR_WATCH_SERVER")
	OS.unset_environment("VR_WATCH_SERVER_LOG")


func _wanted() -> void:
	var dir := OS.get_cache_dir().path_join("vr_watch_test_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	var want := ProjectSettings.globalize_path("res://" + VrWatch.WANT_FILE)
	var status := ProjectSettings.globalize_path("res://" + VrWatch.STATUS_FILE)
	var had_want := FileAccess.file_exists(want)
	DirAccess.remove_absolute(want)
	var asked := dir.path_join("asked")
	OS.set_environment("VR_WATCH_FAKE", "1")  # (no BOT_VR: not live)
	OS.set_environment("VR_WATCH_SERVER", "no-such-vrserver-xyz")
	OS.set_environment("VR_WATCH_SERVER_LOG", dir.path_join("vrserver.txt"))
	OS.set_environment("VR_WATCH_LINK_LOG", dir.path_join("vrlink.txt"))
	OS.set_environment("VR_WATCH_STEAMVR_CMD", "echo asked >> '%s'" % asked)
	var w: Node = VrWatch.new()
	root.add_child(w)
	if not w.is_node_ready():
		w.call("_ready")
	w.call("_want_check", false)
	_check(w.get("want_stage") == "", "no wish: no steps (was '%s')" % w.get("want_stage"))
	w.call("want_vr", "test")
	_check(float(w.call("want_time")) > 0.0, "want_vr leaves a wish in %s" % want)
	w.call("_want_check", false)
	_check(w.get("want_stage") == "starting" and String(w.call("want_text")).contains("Starting VR"),
		"SteamVR not running: 'Starting VR...' on the TV (was %s / '%s')" % [w.get("want_stage"), w.call("want_text")])
	_check(FileAccess.get_file_as_string(status).contains("\tstarting\t"), "the step is in %s for arcade-vr" % status)
	w.call("_want_check", false)
	OS.delay_msec(300)  # (the fake "steam" is a shell)
	var asks := FileAccess.get_file_as_string(asked).count("asked")
	_check(asks == 1, "SteamVR asked for exactly once per STEAMVR_RETRY (was %d)" % asks)
	# SteamVR up ("vrserver" = this process), no headset yet.
	OS.set_environment("VR_WATCH_SERVER", VrWatch.proc_comm(OS.get_process_id()))
	w.call("_want_check", false)
	_check(w.get("want_stage") == "headset" and String(w.call("want_text")).contains("Steam Machine"),
		"SteamVR up, no headset: 'Put the Frame on ... choose Steam Machine' (was %s / '%s')" % [w.get("want_stage"), w.call("want_text")])
	var now := Time.get_unix_time_from_system()
	_write(dir.path_join("vrserver.txt"), "%s [Info] - 0 - entering standby\n" % _stamp(now - 40.0))
	w.call("_want_check", false)
	_check(w.get("want_stage") == "asleep" and String(w.call("want_text")).contains("charge"),
		"headset in standby: 'asleep ... charge' (was %s / '%s')" % [w.get("want_stage"), w.call("want_text")])
	_write(dir.path_join("vrserver.txt"), "")
	_write(dir.path_join("vrlink.txt"), "%s [Info] - ReceivedHMDStaticProps. Model Number: Deckard MP\n" % _stamp(now - 2.0))
	w.call("_want_check", false)
	_check(String(w.get("want_stage")).begins_with("ready"), "headset connected: ready (was %s)" % w.get("want_stage"))
	# VR live: the wish is done and goes away.
	w.set("_rejoin_t", -1.0)
	w.call("_want_check", true)
	_check(not FileAccess.file_exists(want) and w.get("want_stage") == "" and String(w.call("want_text")) == "",
		"VR live: wish removed, steps gone")
	_check(FileAccess.get_file_as_string(status).contains("\tlive\t"), "status says live")
	# An old wish gives up visibly.
	_write(want, str(now - VrWatch.WANT_TTL - 5.0))
	w.call("_want_check", false)
	_check(w.get("want_stage") == "gave_up" and String(w.call("want_text")).contains("didn't start") and not FileAccess.file_exists(want),
		"an expired wish gives up on the TV and is removed (was %s)" % w.get("want_stage"))
	w.free()
	# The flat-first restart (OpenXR already failed in this process): no OpenXR, now, same game, wish kept (not in env).
	var fs: Dictionary = VrWatch.want_flat_spec("kart_race")
	var a: Array = fs.get("args", [])
	_check(a.has("--xr-mode") and a[a.find("--xr-mode") + 1] == "off" and bool(fs.get("now", false)),
		"VR wanted after a failed OpenXR: restart flat --xr-mode off now (%s)" % [fs])
	_check(dict(fs.get("env", {})).get("DUO_RESUME_GAME", "") == "kart_race" and Array(fs.get("unset", [])).has("DUO_VR_WANT"),
		"flat-first restart keeps the game, drops the env wish (the file holds it)")
	# The env wish becomes the file wish and leaves the env.
	DirAccess.remove_absolute(want)
	OS.set_environment("DUO_VR_WANT", "1")
	var e: Node = VrWatch.new()
	root.add_child(e)
	if not e.is_node_ready():
		e.call("_ready")
	_check(FileAccess.file_exists(want) and not OS.has_environment("DUO_VR_WANT"), "DUO_VR_WANT=1 becomes .dev/vr_want and leaves the env")
	e.free()
	DirAccess.remove_absolute(want)
	DirAccess.remove_absolute(status)
	if had_want:
		_write(want, str(Time.get_unix_time_from_system()))
	for k in ["VR_WATCH_FAKE", "VR_WATCH_SERVER", "VR_WATCH_SERVER_LOG", "VR_WATCH_LINK_LOG", "VR_WATCH_STEAMVR_CMD"]:
		OS.unset_environment(k)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	# One step from the shell and from Steam: arcade-vr writes the same wish; launch-vr.sh only adds DUO_VR_WANT=1.
	var tool := FileAccess.get_file_as_string("res://tools/arcade-vr")
	_check(tool.contains(".dev/vr_want") and tool.contains(".dev/vr_status"), "tools/arcade-vr must write .dev/vr_want and follow .dev/vr_status")
	var lv := FileAccess.get_file_as_string("res://launch-vr.sh")
	_check(lv.contains("DUO_VR_WANT=1") and lv.contains("launch.sh") and not lv.contains("steam://"),
		"launch-vr.sh: DUO_VR_WANT=1 + exec launch.sh, nothing else (decisions live in core/vr_watch.gd)")


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


func _processes() -> void:
	var me := OS.get_process_id()
	var comm := VrWatch.proc_comm(me)
	_check(comm != "" and VrWatch.find_processes(comm).has(me), "find_processes(%s) should find this process %d" % [comm, me])
	_check(VrWatch.find_processes("no-such-process-xyz").is_empty(), "find_processes of a made-up name must be empty")


func _guards() -> void:
	var services := FileAccess.get_file_as_string("res://core/services.gd")
	_check(services.contains("\"res://core/vr_watch.gd\""), "core/services.gd must start VrWatch (res://core/vr_watch.gd)")
	var launch := FileAccess.get_file_as_string("res://launch.sh")
	_check(RegEx.create_from_string("(?m)^exec gdev run ").search(launch) != null,
		"launch.sh must start the game with `exec gdev run` (the restart supervisor): a VR session not under it dies with SteamVR")
	var gdev := FileAccess.get_file_as_string("res://tools/gdev")
	for need in ["CRASH_SIGNALS", "GDEV_RESTART_FILE", "GDEV_SUPERVISED", "restart.json", "\"now\"", "stop_marker(proj).write_text"]:
		_check(gdev.contains(need), "tools/gdev lost its RESTART support (%s missing)" % need)
	# One place sets the window's V-Sync / max_fps for VR (core/vr_watch.gd): a game doing it too fights it.
	var vs := RegEx.create_from_string("window_set_vsync_mode|Engine\\.max_fps\\s*=")
	var all: Array[String] = []
	_collect("res://games", all)
	_collect("res://arcade", all)
	for path in all:
		if vs.search(FileAccess.get_file_as_string(path)) != null:
			fails.append("%s sets V-Sync / max_fps: leave it to core/vr_watch.gd (VR pacing)" % path)
	# Quits somebody chose go through VrWatch.quit_on_purpose(): any other quit counts as "nobody asked" and comes
	# back (2026-11-19 19:44: SteamVR went down, Godot quit cleanly, the arcade was gone).
	var bare := RegEx.create_from_string("(?m)^[^#\\n]*\\bquit\\(")
	var qfiles: Array[String] = []
	_collect("res://games", qfiles)
	_collect("res://core", qfiles)
	_collect("res://arcade", qfiles)
	for path in qfiles:
		if path == "res://core/vr_watch.gd":
			continue
		for m in bare.search_all(FileAccess.get_file_as_string(path)):
			var line := m.get_string()
			if not line.contains("quit_on_purpose") and not line.contains("func "):
				fails.append("%s quits with a bare quit(): use VrWatch.quit_on_purpose(get_tree()) (else the arcade restarts itself): %s" % [path, line.strip_edges()])
	# Engine options (--xr-mode, --quit-after, --fixed-fps...) are NOT in OS.get_cmdline_args(): read them with
	# QuitAfter.engine_arg (2026-11-20: VrWatch looked for --xr-mode off there and its flat-first restart looped).
	var opt := RegEx.create_from_string("\"--(xr-mode|quit-after|fixed-fps|headless|audio-driver|rendering-method)\"")
	var ofiles: Array[String] = []
	_collect("res://games", ofiles)
	_collect("res://core", ofiles)
	_collect("res://arcade", ofiles)
	_collect("res://tests", ofiles)
	for path in ofiles:
		var code := []  # (comments may name it)
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if not line.strip_edges().begins_with("#"):
				code.append(line)
		var txt := "\n".join(code)
		if path != "res://tests/vr_watch_test.gd" and txt.contains("get_cmdline_args()") and opt.search(txt) != null:
			fails.append("%s looks for an engine option in OS.get_cmdline_args() (never there): use preload(\"res://core/quit_after.gd\").engine_arg(flag)" % path)
	# One place decides what happens when OpenXR goes away: no game / core script hooks the loss signals itself.
	var re := RegEx.create_from_string("session_loss_pending|instance_exiting")
	var files: Array[String] = []
	_collect("res://games", files)
	_collect("res://core", files)
	_collect("res://arcade", files)
	for path in files:
		if path == "res://core/vr_watch.gd":
			continue
		if re.search(FileAccess.get_file_as_string(path)) != null:
			fails.append("%s handles OpenXR session loss itself: leave it to core/vr_watch.gd (restart flat + rejoin)" % path)


func _collect(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_collect(dir + "/" + d, out)