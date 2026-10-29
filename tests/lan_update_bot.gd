extends Node
## LAN update test driver (run by tools/lan-update-test as a joining machine's main scene): it stays alive at the
## root, opens the real arcade, and when the updater has downloaded + verified an update it starts a "game" at once.
## The update must NOT be applied during the game, only after returning to the arcade menu.

const ARCADE := "res://arcade.tscn"
var t := 0.0
var phase := "wait"
var before := ""


func _ready() -> void:
	if not has_meta("driver"):
		var d: Node = (get_script() as GDScript).new()
		d.set_meta("driver", true)
		d.name = "LanUpdateBot"
		get_tree().root.add_child.call_deferred(d)
		get_tree().change_scene_to_file.call_deferred(ARCADE)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	before = FileAccess.get_file_as_string("res://.update/manifest.json")


func _process(delta: float) -> void:
	if not has_meta("driver"):
		return
	t += delta
	if t > 120.0:
		print("BOT RESULT: FAIL (timed out in phase %s)" % phase)
		preload("res://tests/bot_end.gd").quit_quietly(get_tree(), 1)
		return
	var u := get_node_or_null("/root/LanUpdate")
	if u == null:
		return
	match phase:
		"wait":
			if not (u.get("waiting") as Dictionary).is_empty():
				print("BOT: update verified, starting a game before the menu can apply it")
				var game := Node3D.new()
				game.name = "Main"
				var ps := PackedScene.new()
				ps.pack(game)
				game.free()
				get_tree().change_scene_to_packed(ps)
				phase = "game"
				t = 100.0 - 6.0  # 6 s in the game
		"game":
			if t >= 100.0:
				var now := FileAccess.get_file_as_string("res://.update/manifest.json")
				if now != before:
					print("BOT ASSERT FAILED: the update was applied during a game")
				elif (u.get("waiting") as Dictionary).is_empty():
					print("BOT ASSERT FAILED: the verified update was dropped during the game")
				else:
					print("BOT: still the old version after 6 s in a game (deferred)")
				u.applied.connect(func(v: String) -> void:
					print("BOT: applied %s after returning to the arcade" % v)
					print("BOT RESULT: PASS")
					preload("res://tests/bot_end.gd").quit_quietly(get_tree(), 0))
				get_tree().change_scene_to_file(ARCADE)
				phase = "back"
				t = 60.0
