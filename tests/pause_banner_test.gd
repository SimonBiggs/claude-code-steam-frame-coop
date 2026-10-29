extends SceneTree
## The game's own TV pause banner ("PAUSED / P2 - Start", main.tv_banner, made by main.on_pause_changed) must never
## show under this machine's open pause menu, which already says PAUSED - not even for the one frame between
## on_pause_changed showing it and core/pause_menu.gd's _process hiding it (treasure_dig_bot's "Start pauses" check
## caught that frame ~1 run in 21 under load, 2026-10-29). core/pause_menu.gd hide_game_banner() runs right after
## every on_pause_changed (pause_menu _tell_main, core/net.gd). Checks every game whose main shows a tv_banner.
##   godot-test --headless --path . -s res://tests/pause_banner_test.gd

var fails := 0
var checked := 0


func _initialize() -> void:
	Engine.set_meta("save_test_mode", true)  # (tests/bot_kit.gd SAVE_TEST_META: no real saves touched)
	_run.call_deferred()


func _run() -> void:
	for id in DirAccess.get_directories_at("res://games"):
		var path := "res://games/%s/main.gd" % id
		if not FileAccess.file_exists(path) or not "tv_banner.visible = paused" in FileAccess.get_file_as_string(path):
			continue
		await _check(id)
	if fails == 0 and checked > 0:
		print("PAUSE BANNER: PASS (%d games)" % checked)
	else:
		printerr("SCRIPT ERROR: PAUSE BANNER: FAIL (%d of %d games, or none checked)" % [fails, checked])
	quit(1 if fails > 0 or checked == 0 else 0)


func _check(id: String) -> void:
	var main: Node = load("res://games/%s/main.tscn" % id).instantiate()
	root.add_child(main)
	var t := 0
	while not bool(main.get("ready_to_play")) and t < 300:
		await process_frame
		t += 1
	for k in 3:
		await process_frame
	var menu: Node = null
	for m in get_nodes_in_group("pause_menu"):
		if main.is_ancestor_of(m):
			menu = m
	if menu == null or main.get("split") == null:
		print("  %s: skipped (no pause menu / no TV view here)" % id)
	else:
		checked += 1
		menu.call("_open", -2)  # Esc / Start: the menu opens, the game hears on_pause_changed in the same call
		var b: Variant = main.get("tv_banner")
		var shown: bool = b is CanvasItem and (b as CanvasItem).visible
		if shown or not paused:
			fails += 1
			printerr("SCRIPT ERROR: %s: the game's PAUSED banner shows under the open pause menu (paused %s)" % [id, str(paused)])
		else:
			print("  %s: ok" % id)
		menu.call("_resume")
	paused = false
	main.queue_free()
	await process_frame
	await process_frame
