extends Node
## Deploys while playing (core/safe_apply.gd): new code reaches every machine at once but switches on only at a safe
## point, every lobby machine together. Run with its own project copy per machine (it CHANGES files to fake deploys):
##   tools/multibot.ts --copies -n 2 --seconds 150 res://tests/safe_apply_bot.tscn
## A deploy reaches machine k a little after machine k-1 (like duo-deploy's rsync to the TV, then each Deck).
## It changes a probe script (core/zz_safe_apply_probe.gd: v() = the deploy number) and arcade/arcade.gd.
## Timeline (seconds after the shared T0):
##   A  in the lobby menu: deploy 2 reaches the machines one after another. Nobody switches before the LAST machine
##      has it; then all switch within a moment of each other. The menu keeps its tab, highlighted game and lobby
##      connection, is on screen every frame (no blank flash) and the new arcade code runs.
##   C  deploy 3 reaches the host, then machine 1 asks to start a game BEFORE the others have it: the start waits
##      until everyone has it, and every machine starts the game on deploy 3 (BOT AGREE start_ver=3).
##   B  mid-game, deploy 4 arrives (core + arcade): the game keeps running deploy 3 (the core change waits) with a small
##      "update ready" note; leaving for the menu switches it on (BOT AGREE end_ver=4), the menu comes back on the
##      same tab and game and the lobby forms again.

const PROBE := "res://core/zz_safe_apply_probe.gd"
const ARCADE_GD := "res://arcade/arcade.gd"
const SafeApply := preload("res://core/safe_apply.gd")

var me := int(OS.get_environment("BOT_MACHINE")) if OS.has_environment("BOT_MACHINE") else 0
var count := int(OS.get_environment("BOT_MACHINES")) if OS.has_environment("BOT_MACHINES") else 1
var t0_ms := int(OS.get_environment("BOT_GROUP_T0")) if OS.has_environment("BOT_GROUP_T0") else 0
var game_id: String = OS.get_environment("BOT_GAME") if OS.has_environment("BOT_GAME") else "balloon_pop"
var arcade: Node
var probe: GDScript
var failures := 0
var phase := "wait"
var done := {}
var before := {}  # menu state before deploy 2
var switched_at := {}  # deploy number -> seconds when this machine's probe changed to it
var blank_frames := 0
var arcade_orig := ""
var t_a_last := 0.0
var t_c := 0.0
var t_b := 0.0
var t_r := 0.0
var game_started_at := -1.0
var menu_state_left := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_environment("BOT_OWN_COPY") != "1":
		print("BOT ASSERT FAILED: this bot changes game files: run it with tools/multibot.ts --copies")
		get_tree().quit(1)
		return
	_write(PROBE, _probe_src(1))
	probe = load(PROBE)
	arcade_orig = FileAccess.get_file_as_string(ARCADE_GD)
	t_a_last = 3.0 + 1.5 * (count - 1)
	t_c = t_a_last + 5.0
	t_b = t_c + 2.0 * (count - 1) + 7.0
	t_r = t_b + 5.0
	arcade = load("res://arcade.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arcade)
	(func() -> void: get_tree().current_scene = arcade).call_deferred()
	print("SAFE APPLY BOT: machine %d of %d" % [me, count])


func _probe_src(v: int) -> String:
	return "extends RefCounted\n## Test file made by tests/safe_apply_bot.gd in a throwaway project copy.\nconst V := %d\n\nstatic func v() -> int:\n\treturn V\n" % v


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## A "deploy": the probe says n, and arcade.gd gets a new function answering n (a real script change to apply).
func _deploy(n: int) -> void:
	_write(PROBE, _probe_src(n))
	_write(ARCADE_GD, arcade_orig + "\n\nfunc _safe_apply_bot_marker() -> int:\n\treturn %d\n" % n)
	print("SAFE APPLY BOT: machine %d got deploy %d at %.2f" % [me, n, _now()])


func _now() -> float:
	return (Time.get_unix_time_from_system() * 1000.0 - t0_ms) / 1000.0


func _fail(msg: String) -> void:
	failures += 1
	print("BOT ASSERT FAILED: machine %d: %s" % [me, msg])


func _once(key: String, at: float) -> bool:
	if done.has(key) or _now() < at:
		return false
	done[key] = true
	return true


func _in_menu() -> bool:
	var s := get_tree().current_scene
	return s != null and is_instance_valid(s) and s.scene_file_path == "res://arcade.tscn"


func _menu_visible() -> bool:
	for c in arcade.get_children():
		if c is CanvasLayer and str(c.name).begins_with("TvMenu") and c.visible and not c.is_queued_for_deletion():
			return true
	return false


func _lobby_ok() -> bool:
	if count < 2:
		return true
	if me == 0:
		return arcade.mode == "host" and arcade.machines.size() == count - 1
	return arcade.mode == "client" and arcade.join_deadline == 0 \
		and multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _game_index() -> int:
	var games: Array = preload("res://arcade/arcade.gd").GAMES
	for i in games.size():
		if games[i].id == game_id:
			return i
	return 0


func _process(_delta: float) -> void:
	if phase == "quit":
		return
	var now := _now()
	var v := int(probe.v())
	if not switched_at.has(v):
		switched_at[v] = now
		print("SAFE APPLY BOT: machine %d runs deploy %d from %.2f" % [me, v, now])
	if _in_menu() and arcade == get_tree().current_scene and phase != "game" and now > 0.0 and not _menu_visible():
		blank_frames += 1
		if blank_frames == 1:
			print("SAFE APPLY BOT: menu missing at %.2f; arcade children: %s" % [now, ", ".join(arcade.get_children().map(func(c): return "%s(%s,%s)" % [c.name, c.get_class(), c.get("visible")]))])
	match phase:
		"wait":
			if now >= 0.0:
				if not _lobby_ok():
					_fail("lobby not formed at T0 (mode %s)" % arcade.mode)
				phase = "a"
		"a":
			if me == 0 and _once("tab", 0.5):
				arcade._show_category(1, true)  # a different tab + game than the first, chosen on the host
			if _once("before", 2.0):
				before = {"cat": arcade.cat, "selected": arcade.selected, "mode": arcade.mode}
			if _once("deploy2", 3.0 + 1.5 * me):
				_deploy(2)
			if me == 0 and count > 1 and _once("note_menu", t_a_last - 0.4):
				var note := _note()
				if SafeApply.held_count() == 0 or note == null or not note.visible:
					_fail("deploy 2 arrived but nothing waits / no note while the other machines don't have it yet")
			if _once("check_a", t_a_last + 3.5):
				_check_a()
				phase = "c"
		"c":
			if _once("deploy3", t_c + 2.0 * me):
				_deploy(3)
			if me == mini(1, count - 1) and _once("start", t_c + 1.0):
				print("SAFE APPLY BOT: machine %d asks to start %s at %.2f" % [me, game_id, now])
				arcade._start_everywhere(_game_index())
			var s := get_tree().current_scene
			if s != null and s != arcade and is_instance_valid(s) and s.scene_file_path.begins_with("res://games/"):
				game_started_at = now
				print("SAFE APPLY BOT: machine %d started %s at %.2f on deploy %d" % [me, s.scene_file_path, now, v])
				print("BOT AGREE start_ver=%d" % v)
				print("BOT AGREE started=%s" % s.scene_file_path)
				menu_state_left = get_tree().root.get_meta("arcade_menu_state", {})
				if now < t_c + 2.0 * (count - 1):
					_fail("the game started at %.2f, before the last machine got deploy 3 (%.2f)" % [now, t_c + 2.0 * (count - 1)])
				phase = "game"
			elif _once("start_timeout", t_c + 2.0 * (count - 1) + 15.0):
				_fail("no game started")
				phase = "game"
		"game":
			if _once("deploy4", t_b + 0.7 * me):
				_deploy(4)
			if _once("check_b", t_b + 0.7 * (count - 1) + 3.0):
				if v != 3:
					_fail("deploy 4 switched on mid-game (probe %d)" % v)
				var note := _note()
				if SafeApply.held_count() == 0 or note == null or not note.visible or not note.text.contains("update"):
					_fail("no 'update ready' note mid-game (held %d)" % SafeApply.held_count())
				if not _in_game():
					_fail("not in the game any more at %.2f" % now)
			if _once("leave", t_r):
				SafeApply.change_scene("res://arcade.tscn")
				phase = "back"
		"back":
			if _in_menu():
				if get_tree().current_scene != arcade:
					arcade = get_tree().current_scene
					print("SAFE APPLY BOT: machine %d back in the menu at %.2f on deploy %d" % [me, now, v])
					if v != 4:
						_fail("back in the menu but deploy 4 isn't on (probe %d): it must switch on as the game is left" % v)
			if _once("check_end", t_r + 7.0):
				_check_end(v)
				print("BOT AGREE end_ver=%d" % v)
				_finish()


func _in_game() -> bool:
	var s := get_tree().current_scene
	return s != null and is_instance_valid(s) and s.scene_file_path.begins_with("res://games/")


func _note() -> Label:
	var n := SafeApply.node()
	return n.get("_note") as Label if n != null else null


func _check_a() -> void:
	var at := float(switched_at.get(2, -1.0))
	print("SAFE APPLY BOT: machine %d switched to deploy 2 at %.2f (last machine got it at %.2f)" % [me, at, t_a_last])
	if at < 0.0:
		_fail("deploy 2 never switched on in the menu")
	elif at < t_a_last - 0.05:
		_fail("switched to deploy 2 at %.2f, before the last machine had it (%.2f): machines ran different code" % [at, t_a_last])
	elif at > t_a_last + 2.5:
		_fail("switched to deploy 2 only at %.2f (the last machine had it at %.2f)" % [at, t_a_last])
	if not arcade.has_method("_safe_apply_bot_marker") or int(arcade.call("_safe_apply_bot_marker")) != 2:
		_fail("the arcade isn't running the new arcade.gd")
	if arcade.cat != before.cat or arcade.selected != before.selected:
		_fail("menu state lost across the switch: tab %d -> %d, game %d -> %d" % [before.cat, arcade.cat, before.selected, arcade.selected])
	var f := get_viewport().gui_get_focus_owner()
	if not arcade.cards.has(arcade.selected) or f != arcade.cards[arcade.selected]:
		_fail("the highlighted card isn't the selected game after the switch")
	if not _lobby_ok():
		_fail("lobby connection lost across the switch (mode %s)" % arcade.mode)
	if blank_frames > 0:
		_fail("the menu was missing for %d frame(s) (a blank flash)" % blank_frames)
	print("BOT AGREE menu_after_switch=%d/%d" % [arcade.cat, arcade.selected])


func _check_end(v: int) -> void:
	if v != 4:
		_fail("ended on deploy %d, not 4" % v)
	if int(arcade.call("_safe_apply_bot_marker")) != 4 if arcade.has_method("_safe_apply_bot_marker") else true:
		_fail("the menu isn't running deploy 4's arcade.gd")
	if menu_state_left is Dictionary and menu_state_left.has("selected"):
		if arcade.selected != int(menu_state_left.selected):
			_fail("back from the game on game %d, but %d was highlighted when it started" % [arcade.selected, menu_state_left.selected])
	if not _lobby_ok():
		_fail("the lobby didn't form again after the game (mode %s)" % arcade.mode)
	if SafeApply.held_count() != 0:
		_fail("%d file(s) still waiting in the menu" % SafeApply.held_count())
	if blank_frames > 0:
		_fail("the menu was missing for %d frame(s)" % blank_frames)


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROBE))
	print("BOT RESULT: %s (machine %d)" % ["PASS" if failures == 0 else "FAIL", me])
	phase = "quit"
	get_tree().quit(0 if failures == 0 else 1)
