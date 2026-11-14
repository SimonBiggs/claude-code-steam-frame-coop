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
##   godot-test --headless --path . -s res://tests/vr_watch_test.gd   -> VR WATCH: PASS / FAIL

const VrWatch := preload("res://core/vr_watch.gd")

var fails: Array[String] = []


func _initialize() -> void:
	_log_reading()
	_specs()
	_processes()
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
	w.free()


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
	for need in ["CRASH_SIGNALS", "GDEV_RESTART_FILE", "GDEV_SUPERVISED", "restart.json", "\"now\""]:
		_check(gdev.contains(need), "tools/gdev lost its RESTART support (%s missing)" % need)
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