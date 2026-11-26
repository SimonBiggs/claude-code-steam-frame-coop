extends Node
## gdev bridge logic (development only), HOT-RELOADABLE: run by the frozen loader addons/gdev/bridge.gd (the autoload
## the `gdev` CLI installs), which takes res://core/dev/gdev_main.gd if the project has one, else gdev's own copy
## res://addons/gdev/gdev_main.gd. Editing this file swaps it in live (state handed over via _handoff/_adopt); a copy
## that doesn't compile is refused and the running one keeps going. Keep the fields mtimes / hashes / poll_t and
## _scan_files(): core/safe_apply.gd uses them.
## - Hot-reloads edited .gd files in place (keeping state); restarts the scene when a .tscn changes. A changed script
##   that doesn't compile is NOT reloaded (an in-place reload that fails leaves the live script without its methods:
##   every node using it breaks); the old version keeps running until the file is fixed, or until a file it was waiting
##   for arrives (refused scripts are retried whenever new scripts or classes appear: a deploy copies in any order).
## - NEW class_name scripts work live too (Godot reads class names only at startup): see new_classes below.
## - After a reload, every node whose script uses the reloaded code (its own script, or one that refers to a reloaded
##   script by path or class name, directly or through others) gets _on_hot_reload() (or _on_hot_reload(paths: Array))
##   called, so data built once in _ready or once a day from that code is rebuilt ("on reload, re-run setup").
## - New asset files (png, wav, glb...) can't be loaded before an import: that is said loudly in the log, never silently.
## - GDEV_RELOAD_TEST=1: run reload_selftest() in the running game, print GDEV RELOAD TEST: PASS/FAIL and quit
##   (each game's tests/run.sh; duo-arena tests/gdev_reload_test.tscn).
## - Records a low-res frame every FRAME_INTERVAL seconds to res://.dev/frames/<unix_ms>.jpg.
## - Runs commands the CLI writes to res://.dev/cmd: restart, shot [width], pause, resume, record on|off, quit.

const DEV_DIR := "res://.dev"
const SELF_PATH := "res://addons/gdev/bridge.gd"
const SKIP_DIRS := ["res://addons/gdev/", "res://core/dev/"]  # gdev itself: the loader swaps these, never in place
const FRAME_INTERVAL := 0.5  # override with env GDEV_FRAME_INTERVAL
const FRAME_WIDTH := 960
const MAX_FRAMES := 2400  # about 20 minutes at 0.5 s

var dev_dir := ""
var frames_dir := ""
var hashes := {}
var mtimes := {}
var poll_t := 0.0
var frame_t := 0.0
var recording := true
var capture_busy := false
var frames: Array[String] = []
var tasks: Array[int] = []  # encoding tasks; each must be waited on or its memory is never freed
var rd: RenderingDevice
var frame_interval := FRAME_INTERVAL
var fps_t := 0.0

# Live MJPEG stream of the capture viewport (open http://<host>:8090/ in a browser).
const STREAM_PORT := 8090
const STREAM_FPS := 30.0
var stream_server: TCPServer
var stream_clients: Array[StreamPeerTCP] = []
var stream_t := 0.0
var stream_busy := false
var stream_busy_since := 0
var caption: Node  # "Claude:" captions (addons/gdev/caption.gd), created lazily
# Offscreen test run (godot.ts / gdev-offscreen): a control server instead of the cmd file, no recording,
# stream or captions, so it never touches the live game sharing this project folder.
var offscreen := OS.has_environment("GDEV_CONTROL_PORT")
# The TV screen core/tv_seat.gd starts next to a streamed VR host shares this project folder: it leaves .dev/cmd, the
# .dev/frames recording and the :8090 stream to the VR host (gdev commands and recordings mean the host).
var tv_screen := OS.get_environment("DUO_TV_CLIENT") == "1"
var adopted := false  # took over from an older copy of this script (no first scan, keep its servers)
var reload_stats := {"reloaded": 0, "refused": 0}
# New class_name scripts (2026-11-26: Sprout Hop's new journey.gd needed a relaunch on every running copy). Godot learns
# global class names only at startup (from res://.godot/global_script_class_cache.cfg), so code that uses a class added
# since then doesn't compile. Those classes are kept here, and a script using one is compiled with a constant of that
# name appended (const Journey = preload("res://journey.gd"), at the END so error line numbers stay right). The cache
# file is updated as well, so the next start (and a Deck copied from this folder) knows them for real.
var new_classes := {}  # class name -> script path: class_name scripts the running engine doesn't know
var registered := {}  # class name -> script path the engine knew at startup
var class_of := {}  # script path -> its class_name ("" if none)
var refused := {}  # path -> true: changed scripts that didn't compile yet (retried when new files arrive)
var hook_calls := {}  # node instance id -> times _on_hot_reload was called (reload_selftest reads it)
var asset_seen := {}  # asset path -> true (new ones that can't load without an import are reported once)
var _texts := {}  # path -> [md5, text] (dependency search)
var _assets: Array[String] = []
var _reloaded_now: Array[String] = []
var _retry_refused := false
var shadow_of := {}  # res://.godot/gdev_live/<pid>/x.gd -> res://x.gd (copies of new classes that use other new classes)
var _shadow_busy := {}
const SHADOW_DIR := "res://.godot/gdev_live/"
const CLASS_CACHE := "res://.godot/global_script_class_cache.cfg"
const ASSET_EXT := ["png", "jpg", "jpeg", "webp", "svg", "wav", "ogg", "mp3", "glb", "gltf", "obj", "ttf", "otf"]
const SELFTEST_DIR := "res://zz_gdev_reload_check_"


## The loader is swapping in a new copy of this script: give it everything worth keeping.
func _handoff() -> Dictionary:
	for t in tasks:
		WorkerThreadPool.wait_for_task_completion(t)  # (encode tasks run this copy's code: finish them first)
	tasks.clear()
	var keep := get_children()
	for c in keep:
		remove_child(c)  # (caption, offscreen control server: they move to the new copy, ports and all)
	var d := {"hashes": hashes, "mtimes": mtimes, "frames": frames, "recording": recording, "frame_interval": frame_interval,
		"stream_server": stream_server, "stream_clients": stream_clients, "children": keep, "reload_stats": reload_stats,
		"new_classes": new_classes, "registered": registered, "shadow_of": shadow_of, "class_of": class_of, "refused": refused, "hook_calls": hook_calls,
		"asset_seen": asset_seen}
	stream_server = null
	stream_clients = []
	return d


func _adopt(d: Dictionary) -> void:
	adopted = true
	hashes = d.get("hashes", {})
	mtimes = d.get("mtimes", {})
	frames.assign(d.get("frames", []))
	recording = d.get("recording", recording)
	frame_interval = d.get("frame_interval", frame_interval)
	stream_server = d.get("stream_server")
	stream_clients.assign(d.get("stream_clients", []))
	reload_stats = d.get("reload_stats", reload_stats)
	new_classes = d.get("new_classes", new_classes)
	shadow_of = d.get("shadow_of", shadow_of)
	registered = d.get("registered", {})
	class_of = d.get("class_of", class_of)
	refused = d.get("refused", refused)
	hook_calls = d.get("hook_calls", hook_calls)
	asset_seen = d.get("asset_seen", asset_seen)
	if registered.is_empty():
		_load_registered()  # (handed over by a copy older than new_classes)
	for c in d.get("children", []):
		add_child(c)
	for c in get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with("caption.gd"):
			caption = c


## Busy with an async screen readback or encode (the loader waits for this before swapping copies).
func busy() -> bool:
	return capture_busy or stream_busy or not tasks.is_empty()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if adopted:
		dev_dir = ProjectSettings.globalize_path(DEV_DIR)
		frames_dir = dev_dir + "/frames"
		rd = RenderingServer.get_rendering_device()
		_log("bridge logic swapped in live (pid %d)" % OS.get_process_id())
		_catch_up()
		return
	dev_dir = ProjectSettings.globalize_path(DEV_DIR)
	frames_dir = dev_dir + "/frames"
	DirAccess.make_dir_recursive_absolute(frames_dir)
	if not FileAccess.file_exists(dev_dir + "/.gdignore"):
		FileAccess.open(dev_dir + "/.gdignore", FileAccess.WRITE).close()
	for f in DirAccess.get_files_at(frames_dir):
		if f.ends_with(".jpg"):
			frames.append(frames_dir + "/" + f)
		elif f.ends_with(".tmp"):
			DirAccess.remove_absolute(frames_dir + "/" + f)
	frames.sort()
	_load_registered()
	_clean_shadows()
	_scan_files(true)
	if OS.get_environment("GDEV_RELOAD_TEST") == "1":
		_selftest_main.call_deferred()
	if offscreen and ResourceLoader.exists("res://addons/gdev/control.gd"):
		add_child((load("res://addons/gdev/control.gd") as GDScript).new())
	if DisplayServer.get_name() != "headless" and not offscreen and not tv_screen:
		stream_server = TCPServer.new()
		if stream_server.listen(STREAM_PORT) == OK:
			_log("live view: http://%s:%d/" % [OS.get_environment("HOSTNAME") if OS.has_environment("HOSTNAME") else "localhost", STREAM_PORT])
		else:
			stream_server = null
	rd = RenderingServer.get_rendering_device()
	if OS.has_environment("GDEV_FRAME_INTERVAL"):
		frame_interval = float(OS.get_environment("GDEV_FRAME_INTERVAL"))
	if DisplayServer.get_name() == "headless" or offscreen or tv_screen:
		recording = false  # nothing is rendered, so there is nothing to record
	_log("bridge ready (pid %d)%s" % [OS.get_process_id(), " as the TV screen: no commands, recording or stream (the VR host's)" if tv_screen else ""])


func _process(delta: float) -> void:
	if not offscreen and not is_instance_valid(caption) and ResourceLoader.exists("res://addons/gdev/caption.gd"):
		caption = (load("res://addons/gdev/caption.gd") as GDScript).new()
		add_child(caption)
	poll_t += delta
	if poll_t >= 0.25:
		poll_t = 0.0
		_scan_files(false)
		if not offscreen and not tv_screen:
			_poll_commands()
	_reap_tasks()
	_update_stream(delta)
	fps_t += delta
	if fps_t >= 10.0:
		fps_t = 0.0
		_log("fps %d" % Engine.get_frames_per_second())
	frame_t += delta
	if recording and frame_t >= frame_interval and not capture_busy and tasks.size() < 3:
		frame_t = 0.0
		_capture(frames_dir + "/%d.jpg" % _now_ms(), FRAME_WIDTH, true)


func _log(msg: String) -> void:
	print("[gdev %s] %s" % [Time.get_time_string_from_system(), msg])


func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


# --- Hot reload --------------------------------------------------------------

func _list_files(dir: String, out: Array[String]) -> void:
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			_list_files(dir.path_join(d), out)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") or f.ends_with(".tscn"):
			out.append(dir.path_join(f))
		elif f.get_extension().to_lower() in ASSET_EXT:
			_assets.append(dir.path_join(f))


func _scan_files(initial: bool) -> void:
	var paths: Array[String] = []
	_assets.clear()
	_list_files("res://", paths)
	var scene_changed := false
	var changed: Array[String] = []
	var added: Array[String] = []
	var classes_changed := false
	var cur := get_tree().current_scene
	# File times are whole seconds: a file written again in the same second as the scan that saw its first version kept
	# its time, and that edit was never noticed. Files changed in the last few seconds are always hashed.
	var recent := int(Time.get_unix_time_from_system()) - 3
	for path in paths:
		# md5 of every script 4x a second cost ~14 ms on the Frame's main thread (VR hitches):
		# only hash a file when its modified time changed.
		var mt := FileAccess.get_modified_time(path)
		if mtimes.get(path, -1) == mt and hashes.has(path) and mt < recent:
			continue
		mtimes[path] = mt
		var h := FileAccess.get_md5(path)
		if hashes.get(path, "") == h:
			continue
		var known := hashes.has(path)
		hashes[path] = h
		# Never hot-reload gdev's own files in place: replacing control.gd mid-command (a suspended _press) crashed
		# Godot. The loader swaps the bridge logic (core/dev/) as a whole.
		if path == SELF_PATH or _skipped(path):
			continue
		if path.ends_with(".gd") and _note_class(path, initial):
			classes_changed = true
		if initial:
			continue
		if not known:
			if path.ends_with(".gd"):
				added.append(path)
			continue  # a new script is read fresh when first used (new classes: see below)
		if path.ends_with(".gd"):
			changed.append(path)
		elif ResourceLoader.has_cached(path) or (cur != null and path == cur.scene_file_path):
			scene_changed = true  # only scenes in use restart the game (a new game's files don't)
	if not initial and hashes.size() > paths.size():
		classes_changed = _forget_deleted(paths) or classes_changed
	if classes_changed:
		_sync_class_cache()
	# Scripts refused earlier may have been waiting for a file or class that has just arrived: try them again.
	if classes_changed or not added.is_empty() or _retry_refused:
		_retry_refused = false
		for p in refused.keys():
			if not changed.has(p):
				changed.append(p)
	# New scripts that use a new class must get its constant too, before anything loads them plainly.
	for p in added:
		if _uses_new_class(p):
			_load_with_classes(p, {})
	# A script may need another changed script's new code to compile: retry the ones refused after the others.
	# Scripts the others use go first (a script calling another's new function only compiles once that one is new).
	if changed.size() > 1:
		var texts := {}
		for path in changed:
			texts[path] = FileAccess.get_file_as_string(path)
		var used := {}
		for path in changed:
			used[path] = changed.filter(func(o: String) -> bool: return o != path and str(texts[o]).contains(path)).size()
		changed.sort_custom(func(x: String, y: String) -> bool: return int(used[x]) > int(used[y]))
	_reloaded_now.clear()
	var again: Array[String] = []
	for path in changed:
		if not _reload_script(path, false):
			again.append(path)
	for path in again:
		_reload_script(path, true)
	for name in new_classes:  # an edited new class: refresh its copy (see _class_src_path)
		if new_classes[name] in changed:
			_class_src_path(name)
	if not _reloaded_now.is_empty():
		_call_hooks(_reloaded_now.duplicate())
	_check_assets(initial)
	if scene_changed:
		_log("scene file changed, restarting scene")
		_restart()


func _skipped(path: String) -> bool:
	for d in SKIP_DIRS:
		if path.begins_with(d):
			return true
	return false


## Does this source compile? Checked on a copy first, so a broken file never touches the live script.
## (A script that preloads itself can't be compiled as a copy: those go straight to the real reload.)
## keep_class: leave its class_name in (a class the engine doesn't know yet can't clash with itself).
static func compiles(path: String, text: String, keep_class := false) -> bool:
	if text.contains('preload("%s")' % path) or text.contains("load(\"%s\")" % path):
		return true
	var copy := GDScript.new()
	# The copy must not repeat the class_name: a second script claiming it fails with "Class X hides a global script
	# class", so every class_name script was refused and never hot-reloaded (2026-11-04, Sprout Hop).
	copy.source_code = text if keep_class else RegEx.create_from_string("(?m)^class_name\\s+\\w+").sub(text, "", true)
	return copy.reload() == OK


## False only when the new source doesn't compile (then nothing changed; with last_try the refusal is logged).
func _reload_script(path: String, last_try: bool = true) -> bool:
	if not ResourceLoader.has_cached(path):
		refused.erase(path)
		return true  # not loaded yet; it will be read fresh when first used
	var s := load(path) as GDScript
	if s == null:
		return true
	var text := with_classes(path, FileAccess.get_file_as_string(path))
	if not compiles(path, text, not registered.has(class_of.get(path, ""))):
		if last_try:
			reload_stats.refused += 1
			refused[path] = true
			_log("NOT RELOADED %s: it doesn't compile (see the error above); the old version keeps running. Fix it and save again (or it's retried when new files arrive)" % path)
		return false
	refused.erase(path)
	s.source_code = text
	var err := s.reload(true)
	if err != OK:
		_log("RELOAD FAILED %s: %s (fix it and save again)" % [path, error_string(err)])
		return true
	_apply_new_defaults(s)
	_reloaded_now.append(path)
	reload_stats.reloaded += 1
	_log("reloaded " + path)
	return true


# --- New classes -------------------------------------------------------------

## Swapped in for a copy older than new_classes (a deploy of this file reaching a running game): learn the classes
## now, and retry the loaded scripts that use a class the engine doesn't know (the old copy refused them).
func _catch_up() -> void:
	if not class_of.is_empty():
		return
	for p in hashes.keys():
		if str(p).ends_with(".gd") and not _skipped(str(p)):
			_note_class(str(p), true)
	if new_classes.is_empty():
		return
	_sync_class_cache()
	for p in hashes.keys():
		if str(p).ends_with(".gd") and ResourceLoader.has_cached(str(p)) and _uses_new_class(str(p)):
			refused[str(p)] = true
			_retry_refused = true


func _load_registered() -> void:
	registered = {}
	for e in ProjectSettings.get_global_class_list():
		registered[str(e.get("class", ""))] = str(e.get("path", ""))


static func mentions(text: String, word: String) -> bool:
	return RegEx.create_from_string("\\b%s\\b" % word).search(code_only(text)) != null


## A script's code without its strings and comments: a class name in a story line ("Herd them home!") or a comment
## is not a use of that class (2026-11-26: the reload lint blamed Sheepdog's story.gd for herd.gd that way).
static var _code_cache := {}
static var _strip_re: RegEx
static func code_only(text: String) -> String:
	var k := text.hash()
	if _code_cache.has(k):
		return _code_cache[k]
	if _strip_re == null:
		_strip_re = RegEx.create_from_string("\"\"\"[\\s\\S]*?\"\"\"|\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*'|#[^\\n]*")
	if _code_cache.size() > 4000:
		_code_cache.clear()
	var out := _strip_re.sub(text, "\"\"", true)
	_code_cache[k] = out
	return out


## Remember a script's class_name; true when the set of classes the engine doesn't know changed.
func _note_class(path: String, initial: bool) -> bool:
	var m := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)").search(FileAccess.get_file_as_string(path))
	var name := m.get_string(1) if m else ""
	var old: String = class_of.get(path, "")
	class_of[path] = name
	var changed := false
	if old != "" and old != name and new_classes.get(old, "") == path:
		new_classes.erase(old)
		changed = true
	if name != "" and registered.get(name, "") != path and new_classes.get(name, "") != path:
		new_classes[name] = path
		changed = true
		_log("new class %s (%s)%s" % [name, path, ": the class cache was behind" if initial else ": code using it gets it live"])
	return changed


## Files gone since the last scan: forget them. True when a new class went with them.
func _forget_deleted(paths: Array[String]) -> bool:
	var have := {}
	for p in paths:
		have[p] = true
	var changed := false
	for p in hashes.keys():
		if have.has(p) or _skipped(str(p)):
			continue
		hashes.erase(p)
		mtimes.erase(p)
		refused.erase(p)
		var c: String = class_of.get(p, "")
		class_of.erase(p)
		if c != "" and new_classes.get(c, "") == p:
			new_classes.erase(c)
			changed = true
			for sp in shadow_of.keys():
				if shadow_of[sp] == p:
					shadow_of.erase(sp)
					DirAccess.remove_absolute(ProjectSettings.globalize_path(sp))
		elif c != "" and registered.get(c, "") == p:
			changed = true  # (the cache file must drop it)
	return changed


## The source to compile for a script: plus a constant for every new class it uses (not its own). A script that
## extends a new class extends its file instead (same line, so line numbers stay right).
func with_classes(path: String, text: String) -> String:
	var tail := ""
	for name in new_classes:
		var p: String = new_classes[name]
		if p == path or not mentions(text, name):
			continue
		if RegEx.create_from_string("(?m)^\\s*(static\\s+)?(const|var|enum|class|signal|func)\\s+%s\\b" % name).search(text):
			continue  # the script has its own member of that name
		var target := _class_src_path(name)
		text = RegEx.create_from_string("(?m)^extends\\s+%s\\b" % name).sub(text, "extends \"%s\"" % target)
		tail += "\nconst %s = preload(\"%s\")" % [name, target]
	return text + tail if tail != "" else text


## Where code preloads a new class from: its own file, or, when that file itself uses other new classes, a copy with
## their constants added (Godot's parser reads a script it depends on straight from its FILE, so the constants added
## in memory are not seen there). The copies live in res://.godot/gdev_live/<pid>/ while this game runs.
func _class_src_path(name: String) -> String:
	var p: String = new_classes[name]
	if not _uses_new_class(p):
		return p
	var sp := _shadow_dir() + p.trim_prefix("res://").replace("/", "__")
	if _shadow_busy.has(sp):
		return sp  # (two new classes using each other)
	_shadow_busy[sp] = true
	var src := with_classes(p, FileAccess.get_file_as_string(p))
	_shadow_busy.erase(sp)
	shadow_of[sp] = p
	if not FileAccess.file_exists(sp) or FileAccess.get_file_as_string(sp) != src:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shadow_dir()))
		_put(sp, src)
		if ResourceLoader.has_cached(sp):  # an edit of that class: the copy in use gets it
			var s := load(sp) as GDScript
			s.source_code = src
			if s.reload(true) == OK:
				_apply_new_defaults(s)
	return sp


func _shadow_dir() -> String:
	return SHADOW_DIR + str(OS.get_process_id()) + "/"


## Copies left by games that are no longer running.
func _clean_shadows() -> void:
	var base := ProjectSettings.globalize_path(SHADOW_DIR)
	if not DirAccess.dir_exists_absolute(base):
		return
	for d in DirAccess.get_directories_at(base):
		if d != str(OS.get_process_id()) and not DirAccess.dir_exists_absolute("/proc/" + d):
			for f in DirAccess.get_files_at(base.path_join(d)):
				DirAccess.remove_absolute(base.path_join(d).path_join(f))
			DirAccess.remove_absolute(base.path_join(d))


func _uses_new_class(path: String) -> bool:
	var text := FileAccess.get_file_as_string(path)
	for name in new_classes:
		if new_classes[name] != path and mentions(text, name):
			return true
	return false


## Load a new script that uses new classes (and, first, the new classes it uses that use others) with their constants,
## so a plain load() or preload() of it later gets this compiled copy.
func _load_with_classes(path: String, visiting: Dictionary) -> void:
	if visiting.has(path) or ResourceLoader.has_cached(path):
		return
	visiting[path] = true
	var text := FileAccess.get_file_as_string(path)
	for name in new_classes:
		var p: String = new_classes[name]
		if p != path and mentions(text, name) and _uses_new_class(p):
			_load_with_classes(p, visiting)
	var src := with_classes(path, text)
	if src == text:
		return
	if not compiles(path, src, true):
		_log("NOT LOADED %s: it doesn't compile even with the new classes (see the error above)" % path)
		return
	var s := GDScript.new()
	s.source_code = src
	s.take_over_path(path)
	if s.reload() != OK:
		_log("LOAD FAILED %s" % path)


## Keep res://.godot/global_script_class_cache.cfg in step with the scripts: new classes added, classes whose file is
## gone (or renamed) dropped, so the next start knows exactly the classes there are.
func _sync_class_cache() -> void:
	var cf := ConfigFile.new()
	var old: Array = cf.get_value("", "list", []) if cf.load(CLASS_CACHE) == OK else []
	var out: Array = []
	var seen := {}
	for e in old:
		var p := str(e.get("path", ""))
		var c := str(e.get("class", ""))
		if seen.has(c) or not FileAccess.file_exists(p) or str(class_of.get(p, c)) != c:
			continue
		seen[c] = true
		out.append(e)
	for name in new_classes:
		if seen.has(name):
			continue
		var p: String = new_classes[name]
		var text := FileAccess.get_file_as_string(p)
		out.append({"base": StringName(_base_of(text, 0)), "class": StringName(name), "icon": "",
			"is_abstract": text.contains("@abstract"), "is_tool": text.contains("@tool"), "language": &"GDScript", "path": p})
	if out == old:
		return
	cf.set_value("", "list", out)
	# Written whole, then renamed over the old one: a half-written cache (two games in one folder, a crash) would leave
	# the next start without its classes.
	var tmp := CLASS_CACHE + ".%d.tmp" % OS.get_process_id()
	if cf.save(tmp) == OK and DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(CLASS_CACHE)) == OK:
		_log("class cache updated (%d classes): the next start knows the new ones" % out.size())
	else:
		_log("could not write %s: a restart won't know the new classes until the project is imported" % CLASS_CACHE)


func _base_of(text: String, depth: int) -> String:
	var m := RegEx.create_from_string("(?m)^extends\\s+(\"[^\"]+\"|[\\w.]+)").search(text)
	if m == null:
		return "RefCounted"
	var b := m.get_string(1)
	if not b.begins_with("\""):
		return b
	var p := b.trim_prefix("\"").trim_suffix("\"")
	var c: String = class_of.get(p, "")
	return c if c != "" or depth > 8 else _base_of(FileAccess.get_file_as_string(p), depth + 1)


# --- Re-run setup after a reload -----------------------------------------------

## Every live node with _on_hot_reload() whose script (or a base script) uses reloaded code gets it called once.
## "Uses" = the script itself was reloaded, or it refers to a reloaded script (its path or class name), directly or
## through other scripts: data built in _ready or once a day by a generator is rebuilt when the generator changes.
## First, static caches: a static var whose name contains "cache" (levelgen's _cache, _gen_cache, _lay_cache...) in a
## loaded script that uses reloaded code is emptied, since static vars survive a reload and would keep handing out
## what the OLD code made (2026-11-26).
func _call_hooks(reloaded: Array[String]) -> void:
	var hit := affected(reloaded)
	for sp in shadow_of:
		if hit.has(shadow_of[sp]):
			hit[sp] = true
	for p in hit:
		if ResourceLoader.has_cached(p):
			_clear_caches(p)
	var nodes: Array[Node] = []
	_find_hooked(get_tree().root, nodes)
	for n in nodes:
		var s: Script = n.get_script()
		while s != null and not hit.has(s.resource_path) and not hit.has(shadow_of.get(s.resource_path, "")):
			s = s.get_base_script()
		if s == null:
			continue
		var id := n.get_instance_id()
		hook_calls[id] = int(hook_calls.get(id, 0)) + 1
		if n.get_method_argument_count("_on_hot_reload") > 0:
			n.call_deferred("_on_hot_reload", reloaded.duplicate())
		else:
			n.call_deferred("_on_hot_reload")


func _clear_caches(path: String) -> void:
	var t := text_of(path) if hashes.has(path) else FileAccess.get_file_as_string(path)
	if not t.contains("static var"):
		return
	var s := load(path) as Script
	for m in RegEx.create_from_string("(?m)^static var (\\w*[Cc][Aa][Cc][Hh][Ee]\\w*)").search_all(t):
		var name := m.get_string(1)
		var v = s.get(name)
		if v is Dictionary or v is Array:
			v.clear()
		elif v != null:
			s.set(name, type_convert(null, typeof(v)))
		_log("emptied %s.%s (made by the old code)" % [path.get_file(), name])


func _find_hooked(node: Node, out: Array[Node]) -> void:
	if node.get_script() != null and node.has_method("_on_hot_reload"):
		out.append(node)
	for c in node.get_children():
		_find_hooked(c, out)


## The reloaded scripts plus every project script that refers to one of them, directly or through others.
func affected(reloaded: Array) -> Dictionary:
	var hit := {}
	var frontier: Array = []
	for p in reloaded:
		hit[p] = true
		frontier.append(p)
	var all: Array = hashes.keys().filter(func(p) -> bool: return str(p).ends_with(".gd") and not _skipped(str(p)))
	while not frontier.is_empty():
		var quoted: Array[String] = []
		var names: Array[String] = []
		for p in frontier:
			quoted.append("\"%s\"" % p)
			if str(class_of.get(p, "")) != "":
				names.append(class_of[p])
		var words := RegEx.create_from_string("\\b(%s)\\b" % "|".join(names)) if not names.is_empty() else null
		frontier = []
		for p in all:
			if hit.has(p):
				continue
			var t := text_of(p)
			var uses := words != null and words.search(t) != null
			for q in quoted:
				if uses:
					break
				uses = t.contains(q)
			if uses:
				hit[p] = true
				frontier.append(p)
	return hit


func text_of(path: String) -> String:
	var h: String = hashes.get(path, "")
	var c: Array = _texts.get(path, ["", ""])
	if c[0] != h or h == "":
		c = [h, FileAccess.get_file_as_string(path)]
		_texts[path] = c
	return c[1]


## New asset files only load after an import (Godot reads its imported copy in .godot/imported): say so loudly.
func _check_assets(initial: bool) -> void:
	for p in _assets:
		if asset_seen.has(p):
			continue
		asset_seen[p] = true
		if not initial and not ResourceLoader.exists(p):
			_log("NEEDS IMPORT %s: a new asset can't be loaded until the project is imported (godot --headless --import) and the game restarted" % p)


## Variables added by an edit start out null on live instances; give them their declared defaults.
func _apply_new_defaults(s: GDScript) -> void:
	var users: Array[Node] = []
	_find_users(get_tree().root, s, users)
	if users.is_empty() or not s.can_instantiate():
		return
	var probe = s.new()
	for prop in s.get_script_property_list():
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var def = probe.get(prop.name)
		if def == null:
			continue
		for n in users:
			if n.get(prop.name) == null:
				n.set(prop.name, def)
	if not probe is RefCounted:
		probe.free()


func _find_users(node: Node, s: Script, out: Array[Node]) -> void:
	if node.get_script() == s:
		out.append(node)
	for c in node.get_children():
		_find_users(c, s, out)


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


# --- Commands ----------------------------------------------------------------

func _poll_commands() -> void:
	var path := dev_dir + "/cmd"
	if not FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(path)
	DirAccess.remove_absolute(path)
	for line in text.split("\n", false):
		var parts := line.strip_edges().split(" ", false)
		if parts.is_empty():
			continue
		_log("command: " + line.strip_edges())
		match parts[0]:
			"restart":
				_restart()
			"shot":
				# shot [width] [group]: capture the viewport in that group instead of the default one.
				var w := int(parts[1]) if parts.size() > 1 else 1600
				var group := parts[2] if parts.size() > 2 else ""
				_capture(dev_dir + "/shot.jpg", w, false, group)
			"pause":
				get_tree().paused = true
			"resume":
				get_tree().paused = false
			"record":
				recording = parts.size() < 2 or parts[1] != "off"
			"quit":
				preload("res://core/vr_watch.gd").quit_on_purpose(get_tree())
			"run":
				# run PATH: compile a GDScript file (func run(tree: SceneTree) -> Variant) and call it live.
				_log(run_file(parts[1] if parts.size() > 1 else "", get_tree()))
			_:
				_log("unknown command: " + line)


## `run PATH` (live debugging: gdev send run /abs/path.gd): compile the file and call its run(tree). Returns the log line.
## tests/gdev_run_test.gd checks it.
static func run_file(path: String, tree: SceneTree) -> String:
	var src := FileAccess.get_file_as_string(path) if path != "" else ""
	var g := GDScript.new()
	g.source_code = src
	if src == "" or g.reload() != OK:
		return "run: can't compile " + path
	var o: Object = g.new()
	if not o.has_method("run"):
		return "run: %s has no func run(tree)" % path
	var out := "run result: " + str(o.call("run", tree))
	if not (o is RefCounted):
		o.free()
	return out


# --- Frame capture -----------------------------------------------------------

## Reads the screen back asynchronously when possible so the game never stalls.
func _capture(path: String, width: int, is_frame: bool, group: String = "gdev_capture") -> void:
	# A game can point recording at another viewport (e.g. a VR mirror) by adding it to group "gdev_capture".
	var vp: Viewport = get_viewport()
	var custom := get_tree().get_nodes_in_group(group if group != "" else "gdev_capture")
	if not custom.is_empty() and custom[0] is Viewport:
		vp = custom[0]
	var rd_tex := RenderingServer.texture_get_rd_texture(vp.get_texture().get_rid())
	if rd and rd_tex.is_valid():
		var fmt := rd.texture_get_format(rd_tex)
		if fmt.format == RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM or fmt.format == RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB:
			var w := fmt.width
			var h := fmt.height
			capture_busy = true
			var err := rd.texture_get_data_async(rd_tex, 0, func(data: PackedByteArray) -> void:
				capture_busy = false
				if data.size() == w * h * 4:
					tasks.append(WorkerThreadPool.add_task(_encode_raw.bind(data, w, h, path, width, is_frame))))
			if err == OK:
				return
			capture_busy = false
	# Fallback: synchronous readback (can cause a small hitch).
	var img := _grab(vp)
	if img == null:
		return
	tasks.append(WorkerThreadPool.add_task(_encode_image.bind(img, path, width, is_frame)))


func _update_stream(delta: float) -> void:
	if stream_server == null:
		return
	while stream_server.is_connection_available():
		var c := stream_server.take_connection()
		c.set_no_delay(true)
		var header := "HTTP/1.0 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=gdevframe\r\n" \
			+ "Cache-Control: no-cache\r\nConnection: close\r\n\r\n"
		c.put_data(header.to_utf8_buffer())
		stream_clients.append(c)
	stream_clients = stream_clients.filter(func(c: StreamPeerTCP) -> bool:
		c.poll()
		return c.get_status() == StreamPeerTCP.STATUS_CONNECTED)
	stream_t += delta
	if stream_busy and Time.get_ticks_msec() - stream_busy_since > 2000:
		stream_busy = false  # a lost frame (e.g. its viewport freed on a scene change) must not freeze the stream
	if stream_clients.is_empty() or stream_busy or stream_t < 1.0 / STREAM_FPS:
		return
	stream_t = 0.0
	stream_busy = true
	stream_busy_since = Time.get_ticks_msec()
	# Read back asynchronously like _capture: a synchronous get_image() 25 times a second stalls the
	# headset (missed VR frames show as black flashes).
	var vp := _capture_viewport()
	var rd_tex := RenderingServer.texture_get_rd_texture(vp.get_texture().get_rid())
	if rd and rd_tex.is_valid():
		var fmt := rd.texture_get_format(rd_tex)
		if fmt.format == RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM or fmt.format == RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB:
			var w := fmt.width
			var h := fmt.height
			var err := rd.texture_get_data_async(rd_tex, 0, func(data: PackedByteArray) -> void:
				if data.size() != w * h * 4:
					stream_busy = false
					return
				tasks.append(WorkerThreadPool.add_task(func() -> void:
					var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
					_stream_encode(img))))
			if err == OK:
				return
	var img := _grab(vp)  # fallback (can hitch)
	if img == null:
		stream_busy = false
		return
	tasks.append(WorkerThreadPool.add_task(_stream_encode.bind(img)))


func _stream_encode(img: Image) -> void:
	while img.get_width() >= 960:
		img.shrink_x2()
	img.convert(Image.FORMAT_RGB8)
	_send_stream_frame.call_deferred(img.save_jpg_to_buffer(0.8))


func _send_stream_frame(jpeg: PackedByteArray) -> void:
	stream_busy = false
	var part := ("--gdevframe\r\nContent-Type: image/jpeg\r\nContent-Length: %d\r\n\r\n" % jpeg.size()).to_utf8_buffer()
	part.append_array(jpeg)
	part.append_array("\r\n".to_utf8_buffer())
	# NEVER block the main thread on a viewer: a background browser tab that stops reading filled the
	# socket and put_data() froze the whole game. Send what fits; drop viewers that fall behind.
	var keep: Array[StreamPeerTCP] = []
	for c in stream_clients:
		if c.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		var r := c.put_partial_data(part)
		if r[0] == OK and int(r[1]) == part.size():
			keep.append(c)
		else:
			c.disconnect_from_host()  # too slow (or a half-sent frame): it can reconnect
	stream_clients = keep


func _capture_viewport() -> Viewport:
	var custom := get_tree().get_nodes_in_group("gdev_capture")
	if not custom.is_empty() and custom[0] is Viewport:
		return custom[0]
	return get_viewport()


## Quitting (or swapped out): no encode task may outlive this node's code (a task still running GDScript at exit
## crashes Godot: Sprout Hop, 2026-11-12). tests/thread_quit_test.gd checks every task user does this.
func _exit_tree() -> void:
	for t in tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	tasks.clear()


func _reap_tasks() -> void:
	for i in range(tasks.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(tasks[i]):
			WorkerThreadPool.wait_for_task_completion(tasks[i])
			tasks.remove_at(i)


func _encode_raw(data: PackedByteArray, w: int, h: int, path: String, width: int, is_frame: bool) -> void:
	_encode_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data), path, width, is_frame)


func _encode_image(img: Image, path: String, width: int, is_frame: bool) -> void:
	while img.get_width() >= width * 2:
		img.shrink_x2()
	if img.get_width() > width:
		img.resize(width, int(img.get_height() * float(width) / img.get_width()), Image.INTERPOLATE_BILINEAR)
	img.convert(Image.FORMAT_RGB8)
	var tmp := path + ".tmp"
	if img.save_jpg(tmp, 0.85) == OK:
		DirAccess.rename_absolute(tmp, path)
		if is_frame:
			_frame_saved.call_deferred(path)


func _frame_saved(path: String) -> void:
	frames.append(path)
	while frames.size() > MAX_FRAMES:
		DirAccess.remove_absolute(frames.pop_front())


## The viewport's picture, or null when nothing is drawn yet or it is gone (offscreen runs, 2026-10-30: a grab before
## the first draw logged "tex is null at texture_get_data" and _save_frame then called get_width on null).
## Always grab through this, never get_image() straight off get_texture() (dev.debt flags that).
static func _grab(vp: Viewport) -> Image:
	if vp == null or not is_instance_valid(vp) or not vp.is_inside_tree():
		return null
	var tex := vp.get_texture()
	if tex == null or not tex.get_rid().is_valid() or tex.get_width() <= 0 or tex.get_height() <= 0:
		return null
	var img := tex.get_image()
	return img if img != null and not img.is_empty() else null


# --- Reload self-test (GDEV_RELOAD_TEST=1; every game's tests/run.sh) -----------------------------------------------
## In the running game: (1) a brand-new class_name script (plus one extending it), a new plain script using it and an
## edit of loaded code using them all arrive together and work at once; (2) a generator changes and the live node that
## built its data from it in _ready rebuilds it (its _on_hot_reload runs); (3) the class cache file knows the new class,
## and forgets it when the file goes; (4) load_time_lint(): no live node builds data from a generator at load without
## an _on_hot_reload. Writes its scripts into res://zz_gdev_reload_check_<tag>/ and removes them; refuses a live folder.

## A generator that remembers what it made in a static cache (like Sprout Hop's levelgen): the cache must not survive.
const _GEN_SRC := "extends RefCounted\nstatic var _cache := {}\nstatic func make() -> int:\n\tif not _cache.has(\"v\"):\n\t\t_cache[\"v\"] = %d\n\treturn _cache[\"v\"]\n"
const _USER_SRC := "extends Node\nconst Gen = preload(\"%s\")\nvar data := 0\nvar hooks := 0\n\n\nfunc _ready() -> void:\n\tdata = Gen.make()\n\n\nfunc _on_hot_reload() -> void:\n\thooks += 1\n\tdata = Gen.make()\n%s"


func _selftest_main() -> void:
	for i in 30:
		await get_tree().process_frame  # (the game's own _ready and first frames first)
	var r: Dictionary = await reload_selftest()
	for f in r.fails:
		print("GDEV RELOAD TEST FAIL: " + str(f))
	print("GDEV RELOAD TEST: " + (("SKIPPED: " + str(r.skipped)) if r.has("skipped") else "PASS" if r.pass else "FAIL"))
	# Quit quietly (like the games' quiet_quit.gd): every sound stopped and the game freed, then real time for the
	# audio thread to drop the stopped playbacks, or the run reports "ObjectDB instances were leaked at exit".
	var tree := get_tree()
	tree.paused = true
	_stop_sounds(tree.root)
	if tree.current_scene != null:
		tree.current_scene.queue_free()
	for i in 6:
		await tree.process_frame
		_stop_sounds(tree.root)
		OS.delay_msec(100)
	preload("res://core/vr_watch.gd").quit_on_purpose(tree, 0 if r.pass else 1)  # (a bare quit() makes the arcade restart itself)


func _stop_sounds(n: Node) -> void:
	if n is AudioStreamPlayer or n is AudioStreamPlayer2D or n is AudioStreamPlayer3D:
		n.stop()
		n.stream = null
	for c in n.get_children():
		_stop_sounds(c)


func _put(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func reload_selftest() -> Dictionary:
	var fails: Array[String] = []
	var home := ProjectSettings.globalize_path("res://")
	if DirAccess.dir_exists_absolute(home.path_join(".git")) or home.contains("/Games/") or home.contains("/DuoArena"):
		# (a running copy of the game there would see the test scripts come and go)
		return {"pass": true, "fails": [], "skipped": "a live game folder (%s): run tests in a worktree" % home}
	var tag := "%d_%d" % [OS.get_process_id(), randi() % 1000000]
	var dir := SELFTEST_DIR + tag
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gen := dir + "/gen.gd"
	var user := dir + "/user.gd"
	var fresh := dir + "/fresh.gd"
	var kid := dir + "/fresh_kid.gd"
	var helper := dir + "/helper.gd"
	var cls := "GdevFresh" + tag.replace("_", "x")
	var kid_cls := "GdevFreshKid" + tag.replace("_", "x")
	_put(gen, _GEN_SRC % 1)
	_put(user, _USER_SRC % [gen, ""])
	_scan_files(false)
	var node: Node = (load(user) as GDScript).new()
	node.name = "GdevReloadCheck"
	add_child(node)
	if int(node.get("data")) != 1:
		fails.append("setup: the check node's data is %s, not 1" % node.get("data"))
	# 1. new classes + a new script using them + loaded code using them, all in one deploy
	_put(fresh, "class_name %s\nextends RefCounted\nstatic func value() -> int:\n\treturn 7\nstatic func make() -> %s:\n\treturn new()\n" % [cls, cls])
	_put(kid, "class_name %s\nextends %s\nfunc extra() -> int:\n\treturn 5\n" % [kid_cls, cls])
	_put(helper, "extends RefCounted\nstatic func twice() -> int:\n\treturn %s.value() * 2\n" % cls)
	_put(user, _USER_SRC % [gen, "\n\nfunc fresh() -> int:\n\tvar k: %s = %s.new()\n\tvar m: %s = %s.make()\n\treturn %s.value() + k.extra() + (1 if m != null else 0) + load(\"%s\").twice()\n" % [kid_cls, kid_cls, cls, cls, cls, helper]])
	_scan_files(false)
	await get_tree().process_frame
	if not node.has_method("fresh"):
		fails.append("a new class_name script (%s) and loaded code using it: the code was not reloaded (relaunch needed)" % cls)
	elif int(node.call("fresh")) != 7 + 5 + 1 + 14:
		fails.append("new classes: fresh() gave %s, not 27" % node.call("fresh"))
	# 2. a changed generator: the node that built its data from it in _ready rebuilds it
	var hooks_before := int(node.get("hooks"))
	_put(gen, _GEN_SRC % 2)
	_scan_files(false)
	await get_tree().process_frame
	await get_tree().process_frame
	if int(node.get("data")) != 2 or int(node.get("hooks")) <= hooks_before:
		fails.append("a changed generator: the node using it still has data %s (its _on_hot_reload ran %d times; a static _cache must be emptied too): data built at load needs a relaunch" % [node.get("data"), int(node.get("hooks")) - hooks_before])
	# 3. the next start knows the new classes, and forgets them with their files
	if not _cache_has(cls, fresh):
		fails.append("%s does not list the new class %s: a restart would break code using it" % [CLASS_CACHE, cls])
	# 4. live code that builds data from a generator at load must rebuild it on reload
	fails.append_array(load_time_lint())
	node.queue_free()
	# 5. every live game node's _on_hot_reload runs cleanly, twice (a SCRIPT ERROR fails the run in godot-test / run.sh)
	var hooked: Array[Node] = []
	_find_hooked(get_tree().root, hooked)
	var ran: Array[String] = []
	for n in hooked:
		var p: String = n.get_script().resource_path
		if n == node or not p.begins_with("res://") or p.begins_with("res://addons/") or p.begins_with("res://tests/"):
			continue
		for i in 2:
			if n.get_method_argument_count("_on_hot_reload") > 0:
				n.call("_on_hot_reload", [p])
			else:
				n.call("_on_hot_reload")
			for k in 10:
				await get_tree().process_frame
			if not is_instance_valid(n):
				break
		ran.append(p.get_file())
	print("GDEV RELOAD TEST: ran _on_hot_reload of %s" % (", ".join(ran) if not ran.is_empty() else "no live game node"))
	for f in [gen, user, fresh, kid, helper]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	_scan_files(false)
	if _cache_has(cls, fresh):
		fails.append("%s still lists %s after its file was deleted" % [CLASS_CACHE, cls])
	await get_tree().process_frame
	return {"pass": fails.is_empty(), "fails": fails}


func _cache_has(cls: String, path: String) -> bool:
	var cf := ConfigFile.new()
	if cf.load(CLASS_CACHE) != OK:
		return false
	for e in cf.get_value("", "list", []):
		if str(e.get("class", "")) == cls and str(e.get("path", "")) == path:
			return true
	return false


## Live nodes that use a GENERATOR: a data script (not a Node) with a RandomNumberGenerator, seed() or the date, like
## helpgen.gd, levelgen.gd or arenagen.gd, whose results the node builds things from (in _ready, build(), once a day).
## Each needs an _on_hot_reload() that rebuilds them, or a generator edit only shows after a relaunch. A node whose
## data is rebuilt some other way (every level start...) says why in a comment line "# hot-reload: <why>".
func load_time_lint() -> Array[String]:
	var out: Array[String] = []
	var by_class := {}
	for p in class_of:
		if str(class_of[p]) != "":
			by_class[class_of[p]] = p
	var seen := {}
	var nodes: Array[Node] = []
	_all_nodes(get_tree().root, nodes)
	for n in nodes:
		var s: Script = n.get_script()
		if s == null or seen.has(s):
			continue
		seen[s] = true
		var p := s.resource_path
		if not p.begins_with("res://") or p.begins_with("res://addons/") or p.begins_with("res://tests/") \
				or p.begins_with(SELFTEST_DIR) or p.begins_with(SHADOW_DIR) or n.has_method("_on_hot_reload"):
			continue
		var t := text_of(p) if hashes.has(p) else FileAccess.get_file_as_string(p)
		if t.contains("# hot-reload:"):
			continue
		var gens: Array[String] = []
		for g in _deps(t, by_class):
			if g != p and _is_generator(g):
				gens.append(g.get_file())
		if not gens.is_empty():
			out.append("%s builds things from the generator%s %s but has no _on_hot_reload(): an edit to %s only shows after a relaunch. Add func _on_hot_reload() that rebuilds them (or a '# hot-reload: <why>' comment if they are rebuilt another way)" % [p, "s" if gens.size() > 1 else "", ", ".join(gens), gens[0]])
	return out


func _all_nodes(node: Node, out: Array[Node]) -> void:
	out.append(node)
	for c in node.get_children():
		_all_nodes(c, out)


func _deps(text: String, by_class: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for m in RegEx.create_from_string("load\\(\"(res://[^\"]+\\.gd)\"\\)").search_all(text):
		out.append(m.get_string(1))
	for c in by_class:
		if mentions(text, c) and not out.has(by_class[c]):
			out.append(by_class[c])
	return out


func _is_generator(path: String) -> bool:
	if path.begins_with("res://addons/") or not ResourceLoader.has_cached(path):
		return false  # (not loaded: nothing live uses it)
	var sc := load(path) as Script
	if sc == null or ClassDB.is_parent_class(sc.get_instance_base_type(), "Node"):
		return false  # a node builds its own things: its own _on_hot_reload, if any
	var t := text_of(path) if hashes.has(path) else FileAccess.get_file_as_string(path)
	return t.contains("RandomNumberGenerator") or t.contains("seed(") or t.contains("Time.get_date") \
		or t.contains("get_datetime_dict") or t.contains("get_date_string")
