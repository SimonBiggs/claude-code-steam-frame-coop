extends Node
## Hot reload in the running arcade (gdev bridge reload_selftest, core/dev/gdev_main.gd): a brand-new class_name
## script and code using it go live without a relaunch; a changed generator makes the node that built its data from
## it in _ready rebuild it (_on_hot_reload, static caches emptied); the class cache file learns the new class; no
## live node builds things from a generator without an _on_hot_reload; every live _on_hot_reload runs cleanly.
## The arcade menu is on screen (its _on_hot_reload runs too). SafeApply would hold the edits back mid-game, so it
## applies at once here. Prints GDEV RELOAD TEST: PASS / FAIL (dev.land runs it with the repo guards).

var f := 0
var arcade: Node


func _ready() -> void:
	arcade = load("res://arcade.tscn").instantiate()
	add_child(arcade)


func _process(_d: float) -> void:
	f += 1
	if f == 60:
		_run()


func _run() -> void:
	var sa := get_tree().root.find_child("SafeApply", true, false)
	if sa != null:
		sa.set("mode", "now")
	var bridge := get_node_or_null("/root/GDev")
	var impl: Node = bridge.get("impl") if bridge != null else null
	var r: Dictionary = {"pass": false, "fails": ["no gdev bridge logic running (/root/GDev.impl)"]}
	if impl != null and impl.has_method("reload_selftest"):
		r = await impl.reload_selftest()
	for x in r.fails:
		print("GDEV RELOAD TEST FAIL: " + str(x))
	print("GDEV RELOAD TEST: " + (("SKIPPED: " + str(r.skipped)) if r.has("skipped") else "PASS" if r.pass else "FAIL"))
	preload("res://tests/bot_end.gd").quit_quietly(get_tree(), r.fails.size())
