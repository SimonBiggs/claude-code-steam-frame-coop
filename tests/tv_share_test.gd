extends SceneTree
## A VR launch never takes the TV off another game (core/tv_share.gd, 2026-11-14: a Frame launch covered Stick Fight).
## Checks:
##   - finding other Steam games: reaper SteamLaunch AppId=N lines, our own launch (an ancestor) and SteamVR skipped;
##   - our ancestry is read from /proc (this process is its own first ancestor);
##   - the fake process list (TV_SHARE_FAKE) parses;
##   - pads_off() follows the meta, and the shared input layers honour it (core/party.gd, core/ui_input.gd);
##   - guards: TvShare is a service; no other code unmaps / hides the arcade window (one place decides).
##   godot-test --headless --path . -s res://tests/tv_share_test.gd   -> TV SHARE: PASS / FAIL

const TvShare := preload("res://core/tv_share.gd")

var fails: Array[String] = []


func _initialize() -> void:
	_finding()
	_fake()
	_pads()
	_guards()
	for f in fails:
		print("  FAIL ", f)
	print("TV SHARE: %s (%d problems)" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
	quit(0 if fails.is_empty() else 1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)


func _finding() -> void:
	var procs := [
		{"pid": 100, "cmd": "/home/deck/.local/share/Steam/ubuntu12_32/reaper SteamLaunch AppId=3125609988 -- /home/deck/GodotProjects/duo-arena/launch.sh"},
		{"pid": 200, "cmd": "/home/deck/.local/share/Steam/ubuntu12_32/reaper SteamLaunch AppId=674940 -- /x/StickFight.x86_64"},
		{"pid": 300, "cmd": "/home/deck/.local/share/Steam/ubuntu12_32/reaper SteamLaunch AppId=250820 -- vrstartup.sh"},
		{"pid": 400, "cmd": "/home/deck/.local/share/Steam/ubuntu12_32/reaper SteamLaunch AppId=674940 -- child"},
		{"pid": 500, "cmd": "reaper something else"},
	]
	var mine := [999, 100, 1]
	var got := TvShare.other_games(procs, mine)
	_check(got == ["674940"], "other games: Stick Fight once, not us, not SteamVR (got %s)" % [got])
	_check(TvShare.other_games(procs.slice(0, 1), mine).is_empty(), "only our own launch: no other game")
	_check(TvShare.other_games([procs[2]], mine).is_empty(), "SteamVR alone is not a game on the TV")
	var anc := TvShare.ancestors(OS.get_process_id())
	_check(anc.size() >= 2 and int(anc[0]) == OS.get_process_id(), "ancestors start with this process (%s)" % [anc])
	var t0 := Time.get_ticks_usec()
	var real := TvShare.read_procs()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_check(real is Array, "reading /proc works")
	print("tv share: /proc scan %.1f ms (in a worker thread in the game), %d reapers" % [ms, real.size()])


func _fake() -> void:
	var path := OS.get_cache_dir().path_join("tv_share_test_%d.txt" % OS.get_process_id())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("42 /x/reaper SteamLaunch AppId=674940 -- game\nnot a line\n")
	f.close()
	var r := TvShare.read_fake(path)
	_check(r.size() == 1 and int(r[0].pid) == 42, "fake list parses (%s)" % [r])
	_check(TvShare.other_games(r, []) == ["674940"], "fake list finds the game")
	DirAccess.remove_absolute(path)


func _pads() -> void:
	Engine.set_meta(TvShare.META, true)
	_check(TvShare.pads_off(), "pads_off while the TV is another game's")
	Engine.set_meta(TvShare.META, false)
	_check(not TvShare.pads_off(), "pads back when the TV is ours")
	for p in ["res://core/party.gd", "res://core/ui_input.gd"]:
		_check(FileAccess.get_file_as_string(p).contains("tv_share.gd\").pads_off()"), "%s honours TvShare.pads_off()" % p)


func _guards() -> void:
	_check(FileAccess.get_file_as_string("res://core/services.gd").contains("res://core/tv_share.gd"), "TvShare is a service")
	var re := RegEx.create_from_string("windowunmap|WINDOW_MODE_MINIMIZED")
	for dir in ["res://core", "res://arcade", "res://games"]:
		_scan(dir, re)


func _scan(dir: String, re: RegEx) -> void:
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d), re)
	for f in DirAccess.get_files_at(dir):
		var p := dir.path_join(f)
		if f.ends_with(".gd") and p != "res://core/tv_share.gd" and re.search(FileAccess.get_file_as_string(p)) != null:
			fails.append("%s hides the window itself: only core/tv_share.gd decides" % p)