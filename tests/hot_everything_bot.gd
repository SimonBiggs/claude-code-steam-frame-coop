extends Node
## Everything hot-reloads (Boot + core/services.gd, the gdev bridge loader + core/dev/gdev_main.gd), on ONE machine in
## its own project copy (it changes files):  tools/hot-everything-test
## In the arcade menu (a safe point), at game-time seconds:
##   3  a NEW service script + its line in core/services.gd -> /root/ZzTestService appears (no restart)
##   8  the service changes -> reloaded in place (v() = 2, same node)
##  12  the service gets a syntax error -> NOT reloaded: v() still 2 (the error is logged)
##  17  the bridge logic (core/dev/gdev_main.gd) changes -> a new copy runs (HOT_MARK = 2), state kept
##  21  the service is fixed (v() = 3) -> the NEW bridge logic reloads it
##  26  the bridge logic gets a syntax error -> refused, the running copy stays (HOT_MARK still 2)
##  29  the service changes (v() = 4) -> still reloads
##  34  core/services.gd gets a syntax error -> refused, every service keeps running
##  38  the service's line is removed -> /root/ZzTestService goes away
##  42  core/runtime_settings.gd: another stretch size -> applied live
## Deliberate syntax errors print parse errors: tools/hot-everything-test allows exactly those.

const SVC := "res://core/zz_test_service.gd"
const REG := "res://core/services.gd"
const IMPL := "res://core/dev/gdev_main.gd"
const RS := "res://core/runtime_settings.gd"

var t := 0.0
var done := {}
var failures := 0
var reg_orig := ""
var impl_orig := ""
var impl_node: Node
var svc_node: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_environment("BOT_OWN_COPY") != "1":
		print("BOT ASSERT FAILED: this bot changes game files: run it with tools/hot-everything-test")
		get_tree().quit(1)
		return
	reg_orig = FileAccess.get_file_as_string(REG)
	impl_orig = FileAccess.get_file_as_string(IMPL)
	var arcade: Node = load("res://arcade.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arcade)
	(func() -> void: get_tree().current_scene = arcade).call_deferred()


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("HOT BOT: %.1f wrote %s" % [t, path])


func _svc(v: int, broken := false) -> void:
	_write(SVC, "extends Node\n## Test service made by tests/hot_everything_bot.gd in a throwaway copy.\nconst V := %d\n\nfunc v() -> int:\n\treturn V%s\n" % [v, " +" if broken else ""])


func _fail(msg: String) -> void:
	failures += 1
	print("BOT ASSERT FAILED: %s" % msg)


func _at(key: String, when: float) -> bool:
	if done.has(key) or t < when:
		return false
	done[key] = true
	return true


func _impl() -> Node:
	var g := get_node_or_null("/root/GDev")
	return g.get("impl") if g != null else null


func _process(delta: float) -> void:
	t += delta
	var svc := get_node_or_null("/root/ZzTestService")
	if _at("add", 3.0):
		_svc(1)
		_write(REG, reg_orig.replace("const SERVICES := [\n", "const SERVICES := [\n\t{\"name\": \"ZzTestService\", \"path\": \"%s\"},\n" % SVC))
	if _at("c_add", 7.0):
		if svc == null or int(svc.call("v")) != 1:
			_fail("a new service + registry line didn't start a /root/ZzTestService (got %s)" % svc)
		svc_node = svc
	if _at("change", 8.0):
		_svc(2)
	if _at("c_change", 11.5):
		if svc == null or svc != svc_node or int(svc.call("v")) != 2:
			_fail("the service didn't reload in place (v %s)" % (svc.call("v") if svc else "none"))
	if _at("break", 12.0):
		_svc(9, true)
	if _at("c_break", 16.0):
		if svc == null or not svc.has_method("v") or int(svc.call("v")) != 2:
			_fail("a service with a syntax error broke the running one (it must keep v() = 2)")
	if _at("impl", 17.0):
		impl_node = _impl()
		_write(IMPL, impl_orig + "\n\nconst HOT_MARK := 2\n")
	if _at("c_impl", 20.0):
		var i := _impl()
		if i == null or i == impl_node or i.get("HOT_MARK") != 2:
			_fail("the bridge logic change didn't swap in live")
		elif (i.get("hashes") as Dictionary).size() < 10:
			_fail("the new bridge logic lost the old one's file table")
		impl_node = i
	if _at("fix", 21.0):
		_svc(3)
	if _at("c_fix", 25.0):
		if svc == null or not svc.has_method("v") or int(svc.call("v")) != 3:
			_fail("the new bridge logic didn't reload the fixed service (v %s)" % (svc.call("v") if svc and svc.has_method("v") else "?"))
	if _at("impl_break", 26.0):
		_write(IMPL, impl_orig + "\n\nconst HOT_MARK := 3 +\n")
	if _at("svc4", 29.0):
		_svc(4)
	if _at("c_impl_break", 33.0):
		var i := _impl()
		if i != impl_node or i.get("HOT_MARK") != 2:
			_fail("a broken bridge logic file replaced the running one")
		if svc == null or int(svc.call("v")) != 4:
			_fail("hot reload stopped after a broken bridge logic file (v %s)" % (svc.call("v") if svc else "none"))
	if _at("reg_break", 34.0):
		_write(REG, reg_orig.replace("const SERVICES := [\n", "const SERVICES := [\n\t{\"name\": \"ZzTestService\", \"path\": \"%s\"},,\n" % SVC))
	if _at("c_reg_break", 37.0):
		if svc == null or get_node_or_null("/root/SafeApply") == null:
			_fail("a broken core/services.gd stopped services")
	if _at("reg_remove", 38.0):
		_write(REG, reg_orig)
	if _at("c_reg_remove", 41.5):
		if svc != null and not svc.is_queued_for_deletion():
			_fail("removing the service's line didn't stop it")
	if _at("rs", 42.0):
		_write(RS, FileAccess.get_file_as_string(RS).replace("Vector2i(1920, 1080)", "Vector2i(1280, 720)"))
	if _at("c_rs", 46.0):
		if get_tree().root.content_scale_size != Vector2i(1280, 720):
			_fail("runtime settings didn't apply live (%s)" % get_tree().root.content_scale_size)
		for n in ["RuntimeSettings", "SafeApply", "VrTextGuard", "Boot", "GDev"]:
			if get_node_or_null("/root/" + n) == null:
				_fail("/root/%s missing" % n)
		var i := _impl()
		print("HOT BOT: bridge reload stats %s" % (i.get("reload_stats") if i else "?"))
		print("BOT RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
		get_tree().quit(0 if failures == 0 else 1)
