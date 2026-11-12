extends SceneTree
## Background work never outlives the code it runs. A WorkerThreadPool task (or Thread) still running GDScript when
## Godot quits, or one locking a STATIC Mutex that Godot already freed while unloading scripts, crashes the quit
## (Sprout Hop 2026-11-12: SIGSEGV in pthread_mutex_lock, then abort). Static scan of core/, games/, arcade/, addons/:
##   - a script that starts WorkerThreadPool tasks waits for them in _exit_tree (wait_for_task_completion);
##   - a script that starts Threads joins them in _exit_tree (wait_to_finish);
##   - a game that prefetches with core/bg_gen.gd calls BgGen.wait_all() in its _exit_tree;
##   - a static Mutex is only allowed in STATIC_MUTEX, with how every thread that locks it is collected before quit.
##   godot-test --headless --path . -s res://tests/thread_quit_test.gd   -> THREAD QUIT: PASS / FAIL

## script -> why its static Mutex is safe at quit.
const STATIC_MUTEX := {
	"res://core/bg_gen.gd": "its tasks are the only threads that lock it; every user calls BgGen.wait_all() in _exit_tree (checked here)",
	"res://games/hide_and_seek/housegen.gd": "locked from BgGen house jobs only, which hide_and_seek/main.gd collects with BgGen.wait_all() in _exit_tree",
}
## Scripts that manage task ids themselves in another way (path -> why).
const OWN_LIFETIME := {
	"res://core/bg_gen.gd": "static helper: its callers collect its tasks (BgGen.wait_all, checked here)",
}

var fails: Array[String] = []


func _initialize() -> void:
	var files: Array[String] = []
	for d in ["res://core", "res://games", "res://arcade", "res://addons"]:
		_collect(d, files)
	var mutex_re := RegEx.create_from_string("(?m)^static var \\w+\\s*:?=\\s*Mutex\\.new\\(\\)")
	var seen_mutex := {}
	for path in files:
		var src := FileAccess.get_file_as_string(path)
		var exit := _exit_body(src)
		if src.contains("WorkerThreadPool.add_task(") and not OWN_LIFETIME.has(path) and not exit.contains("wait_for_task_completion"):
			fails.append("%s starts WorkerThreadPool tasks but its _exit_tree doesn't wait for them (wait_for_task_completion)" % path)
		if src.contains("Thread.new()") and not exit.contains("wait_to_finish"):
			fails.append("%s starts a Thread but its _exit_tree doesn't join it (wait_to_finish)" % path)
		if src.contains("BgGen.prefetch(") and not OWN_LIFETIME.has(path) and not exit.contains("BgGen.wait_all()"):
			fails.append("%s prefetches with BgGen but its _exit_tree doesn't call BgGen.wait_all()" % path)
		if mutex_re.search(src) != null:
			seen_mutex[path] = true
			if not STATIC_MUTEX.has(path):
				fails.append("%s has a static Mutex: avoid it (a per-node Mutex, or no sharing), or list it in STATIC_MUTEX with how its threads are collected before quit" % path)
	for p in STATIC_MUTEX:
		if not seen_mutex.has(p):
			fails.append("STATIC_MUTEX lists %s, which has no static Mutex any more" % p)
	for f in fails:
		print("  FAIL ", f)
	print("THREAD QUIT: %s (%d scripts)" % ["PASS" if fails.is_empty() else "FAIL (%d)" % fails.size(), files.size()])
	quit(0 if fails.is_empty() else 1)


func _collect(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_collect(dir + "/" + d, out)


## The body of `func _exit_tree` ("" when there is none).
func _exit_body(src: String) -> String:
	var lines := src.split("\n")
	var out := ""
	var inside := false
	for l in lines:
		if l.begins_with("func _exit_tree("):
			inside = true
			continue
		if inside:
			if l != "" and not l.begins_with("\t") and not l.begins_with(" ") and not l.begins_with("#"):
				break
			out += l + "\n"
	return out