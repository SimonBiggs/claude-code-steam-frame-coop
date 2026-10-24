extends Node
## Headless test of the shared presentation engine (core/ui_kit, ui_input, ui_menu, vr_menu, dialogue,
## hud_kit, hints, awards, mesh_kit, creatures, sky_kit, sfx, music). Each area is a part script in
## tests/engine_ui/ (extending part_base.gd); this runner awaits them one by one and quits with the
## number of failed checks as the exit code.
##   godot --headless --path . --fixed-fps 60 res://tests/engine_ui_test.tscn
##   ENGINE_PARTS=ui,world godot --headless ...   # only some parts

const PARTS := {
	"ui": "res://tests/engine_ui/ui_test.gd",
	"world": "res://tests/engine_ui/world_test.gd",
	"audio": "res://tests/engine_ui/audio_test.gd",
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var only := OS.get_environment("ENGINE_PARTS")
	var failures := 0
	var checks := 0
	var t0 := Time.get_ticks_msec()
	for key in PARTS:
		if only != "" and not only.split(",").has(key):
			continue
		var path: String = PARTS[key]
		if not ResourceLoader.exists(path):
			print("[runner] FAIL: missing part %s" % path)
			failures += 1
			continue
		var script: GDScript = load(path)
		var part: Node = script.new()
		part.name = "Part_" + key
		add_child(part)
		print("[runner] --- %s ---" % key)
		var pt := Time.get_ticks_msec()
		await part.call("run")
		var f: int = int(part.get("failures"))
		var c: int = int(part.get("checks"))
		failures += f
		checks += c
		print("[runner] %s: %d checks, %d failed (%.1f s)" % [key, c, f, (Time.get_ticks_msec() - pt) / 1000.0])
		part.queue_free()
		await get_tree().process_frame
	# let the last sounds finish (in REAL time: --fixed-fps runs faster than the audio clock), so
	# nothing is mid-playback at exit (Godot reports playing streams as leaked instances)
	var settle_until := Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < settle_until:
		await get_tree().process_frame
	print("[runner] ENGINE TEST DONE: %d checks, %d failed, %.1f s" % [checks, failures, (Time.get_ticks_msec() - t0) / 1000.0])
	print("ENGINE_TEST_RESULT %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(mini(failures, 100))
