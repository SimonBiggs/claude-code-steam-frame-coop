extends Node
## gdev control server (offscreen test runs only). The bridge adds it when GDEV_CONTROL_PORT is set.
## HTTP on 127.0.0.1:<port>: POST a JSON body {"cmd": ..., args...}, get JSON back. Commands:
##   ping                          scene, fps, frame, size
##   eval   {code}                 run GDScript (statements, or one expression whose value is returned);
##                                 `tree`, `root`, `scene` and find(pattern) are in scope, await works
##   tree   {path?, depth?}        node tree: name, class, visible, text, rect, focus
##   ui     {}                     visible Controls with text or focus, plus which one has focus
##   press  {action|key|joy, frames?, device?, axis?, value?}   tap (or hold `frames`) an input
##   click  {x, y} | {node}        left click at a point or a node's centre
##   wait   {frames|seconds}
##   shot   {path, width?}         save a PNG of the screen (after the next drawn frame)
##   record {dir, fps?, width?} / record {stop: true}   JPG frames (inputs in a corner overlay), the Master
##                                 bus as mono float32 (audio.f32 + audio.rate) and inputs/marks (events.txt)
##   mark   {text}                 show a note in the recording overlay (e.g. "now testing the pause menu")
##   speed  {value}                Engine.time_scale
##   scene  {path}                 change_scene_to_file
##   quit
## The Bun client is ~/.local/share/gdev/godot.ts (brepl: godot.launch(...)).

var server := TCPServer.new()
var port := 0
# Recorder: frames go to rec_dir/<ms since start>.jpg; inputs and marks show in an overlay so the video
# explains itself. Encoding runs on worker threads, which must all be waited on (or their images leak).
var rec_dir := ""
var rec_every := 0.1
var rec_width := 960
var rec_t0 := 0
var rec_next := 0
var rec_frames := 0
var rec_tasks: Array[int] = []
var overlay: CanvasLayer
var rec_audio: FileAccess  # mono float32 samples of the Master bus, from recording start (rec/audio.f32)
var rec_capture: AudioEffectCapture
var overlay_label: Label
var overlay_lines: Array = []  # [text, until_ms]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	port = int(OS.get_environment("GDEV_CONTROL_PORT"))
	if server.listen(port, "127.0.0.1") != OK:
		push_error("gdev control: cannot listen on %d" % port)
		return
	print("gdev control: listening on %d" % port)


func _process(_delta: float) -> void:
	while server.is_listening() and server.is_connection_available():
		_serve(server.take_connection())
	for t in rec_tasks.filter(func(t: int) -> bool: return WorkerThreadPool.is_task_completed(t)):
		WorkerThreadPool.wait_for_task_completion(t)
		rec_tasks.erase(t)
	if rec_dir != "":
		_update_overlay()
		_pull_audio()
		var now := Time.get_ticks_msec()
		if now >= rec_next and rec_tasks.size() < 8:
			rec_next = maxi(rec_next + int(rec_every * 1000.0), now - int(rec_every * 1000.0))  # steady rate, no drift
			var img := get_viewport().get_texture().get_image()
			rec_tasks.append(WorkerThreadPool.add_task(_save_frame.bind(img, "%s/%08d.jpg" % [rec_dir, now - rec_t0])))
			rec_frames += 1


func _pull_audio() -> void:
	var n := rec_capture.get_frames_available()
	if n <= 0:
		return
	var st := rec_capture.get_buffer(n)
	var mono := PackedFloat32Array()
	mono.resize(st.size())
	for i in st.size():
		mono[i] = (st[i].x + st[i].y) * 0.5
	rec_audio.store_buffer(mono.to_byte_array())


func _save_frame(img: Image, path: String) -> void:
	if rec_width > 0 and rec_width < img.get_width():
		img.resize(rec_width, int(img.get_height() * float(rec_width) / img.get_width()), Image.INTERPOLATE_BILINEAR)
	img.save_jpg(path, 0.85)


func _note(text: String, seconds := 1.5) -> void:
	if rec_dir == "":
		return
	overlay_lines.append([text, Time.get_ticks_msec() + int(seconds * 1000.0)])
	var f := FileAccess.open(rec_dir + "/events.txt", FileAccess.READ_WRITE if FileAccess.file_exists(rec_dir + "/events.txt") else FileAccess.WRITE)
	f.seek_end()
	f.store_line("%.2f %s" % [(Time.get_ticks_msec() - rec_t0) / 1000.0, text])


func _update_overlay() -> void:
	var now := Time.get_ticks_msec()
	overlay_lines = overlay_lines.filter(func(l: Array) -> bool: return l[1] > now)
	var txt := "%.1fs" % ((now - rec_t0) / 1000.0)
	for l in overlay_lines.slice(-4):
		txt += "\n" + str(l[0])
	overlay_label.text = txt


func _start_recording(r: Dictionary) -> Dictionary:
	if r.get("stop", false):
		if rec_dir == "":
			return {"error": "not recording"}
		var dir := rec_dir
		rec_dir = ""
		for t in rec_tasks:
			WorkerThreadPool.wait_for_task_completion(t)
		rec_tasks.clear()
		overlay.queue_free()
		_pull_audio()
		rec_audio.close()
		for i in AudioServer.get_bus_effect_count(0):
			if AudioServer.get_bus_effect(0, i) == rec_capture:
				AudioServer.remove_bus_effect(0, i)
				break
		return {"dir": dir, "frames": rec_frames, "seconds": (Time.get_ticks_msec() - rec_t0) / 1000.0}
	rec_dir = str(r.get("dir", ""))
	if rec_dir == "":
		return {"error": "record needs dir"}
	DirAccess.make_dir_recursive_absolute(rec_dir)
	rec_every = 1.0 / maxf(1.0, float(r.get("fps", 10)))
	rec_width = int(r.get("width", 960))
	rec_t0 = Time.get_ticks_msec()
	rec_next = 0
	rec_frames = 0
	rec_capture = AudioEffectCapture.new()
	rec_capture.buffer_length = 2.0
	AudioServer.add_bus_effect(0, rec_capture)
	rec_audio = FileAccess.open(rec_dir + "/audio.f32", FileAccess.WRITE)
	FileAccess.open(rec_dir + "/audio.rate", FileAccess.WRITE).store_string(str(AudioServer.get_mix_rate()))
	overlay = CanvasLayer.new()
	overlay.layer = 128
	overlay_label = Label.new()
	overlay_label.position = Vector2(16, 12)
	overlay_label.add_theme_font_size_override("font_size", int(26 * get_viewport().size.y / 1080.0))
	overlay_label.add_theme_color_override("font_color", Color(1, 1, 0.4))
	overlay_label.add_theme_color_override("font_outline_color", Color.BLACK)
	overlay_label.add_theme_constant_override("outline_size", 8)
	overlay.add_child(overlay_label)
	add_child(overlay)
	return {"dir": rec_dir}


func _serve(peer: StreamPeerTCP) -> void:
	var raw := PackedByteArray()
	var body_start := -1
	var length := 0
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			raw.append_array(peer.get_data(n)[1])
		if body_start < 0:
			var text := raw.get_string_from_utf8()
			var i := text.find("\r\n\r\n")
			if i >= 0:
				body_start = text.substr(0, i).to_utf8_buffer().size() + 4
				for line in text.substr(0, i).split("\r\n"):
					if line.to_lower().begins_with("content-length:"):
						length = int(line.split(":")[1].strip_edges())
		if body_start >= 0 and raw.size() - body_start >= length:
			break
		await get_tree().process_frame
	var req = JSON.parse_string(raw.slice(body_start).get_string_from_utf8()) if body_start >= 0 else null
	var out: Dictionary
	if req is Dictionary and req.has("cmd"):
		out = await _run(req)
	else:
		out = {"error": "send a JSON body like {\"cmd\": \"ping\"}"}
	var bytes := JSON.stringify(out, "", false).to_utf8_buffer()
	peer.put_data(("HTTP/1.0 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n" % bytes.size()).to_utf8_buffer())
	peer.put_data(bytes)
	peer.disconnect_from_host()


func _run(r: Dictionary) -> Dictionary:
	match str(r.cmd):
		"ping":
			var s := get_tree().current_scene
			return {"scene": s.scene_file_path if s else "", "fps": Engine.get_frames_per_second(),
				"frame": Engine.get_process_frames(), "size": [get_viewport().size.x, get_viewport().size.y]}
		"eval":
			return await _eval(str(r.get("code", "")))
		"tree":
			var from: Node = get_tree().root.get_node_or_null(str(r.get("path", "/root")))
			if from == null:
				return {"error": "no node at " + str(r.get("path"))}
			return {"tree": _node_info(from, int(r.get("depth", 3)))}
		"ui":
			var items: Array = []
			_collect_ui(get_tree().root, items)
			var f := get_viewport().gui_get_focus_owner()
			return {"focus": _describe(f) if f else null, "items": items}
		"press":
			return await _press(r)
		"click":
			return await _click(r)
		"wait":
			if r.has("seconds"):
				await get_tree().create_timer(float(r.seconds), true, false, true).timeout
			else:
				for i in int(r.get("frames", 1)):
					await get_tree().process_frame
			return {"ok": true}
		"shot":
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var w := int(r.get("width", 0))
			if w > 0 and w < img.get_width():
				img.resize(w, int(img.get_height() * float(w) / img.get_width()), Image.INTERPOLATE_LANCZOS)
			var path := str(r.get("path", ProjectSettings.globalize_path("res://.dev/offscreen.png")))
			var err := img.save_png(path)
			return {"path": path, "size": [img.get_width(), img.get_height()]} if err == OK else {"error": "save failed: %d" % err}
		"record":
			return _start_recording(r)
		"mark":
			_note("# " + str(r.get("text", "")), float(r.get("seconds", 3.0)))
			return {"ok": true}
		"speed":
			Engine.time_scale = float(r.get("value", 1.0))
			return {"ok": true}
		"scene":
			var err := get_tree().change_scene_to_file(str(r.get("path", "")))
			await get_tree().process_frame
			await get_tree().process_frame
			return {"ok": err == OK} if err == OK else {"error": "change_scene failed: %d" % err}
		"quit":
			get_tree().quit.call_deferred()
			return {"ok": true}
	return {"error": "unknown cmd " + str(r.cmd)}


# --- eval ------------------------------------------------------------------------

const _STATEMENT := ["var ", "for ", "if ", "while ", "return", "await ", "pass", "match ", "print"]


func _eval(code: String) -> Dictionary:
	var lines := code.strip_edges().split("\n")
	var single := lines.size() == 1 and not _STATEMENT.any(func(k: String) -> bool: return lines[0].begins_with(k)) \
		and not RegEx.create_from_string("^[\\w.\\[\\]\"]+\\s*[-+*/]?=[^=]").search(lines[0])
	var body := "\treturn " + lines[0] if single else "\n".join(Array(lines).map(func(l: String) -> String: return "\t" + l))
	var src := "extends RefCounted\nvar tree: SceneTree\nvar root: Node\nvar scene: Node\n" \
		+ "func find(pattern: String) -> Array: return root.find_children(pattern, \"\", true, false)\n" \
		+ "func run():\n" + body + "\n\treturn null\n"
	var s := GDScript.new()
	s.source_code = src
	if s.reload() != OK:
		return {"error": "GDScript did not compile (see the game log for the line)", "source": src}
	var o: Object = s.new()
	o.tree = get_tree()
	o.root = get_tree().root
	o.scene = get_tree().current_scene
	var v = await o.run()
	return {"value": _jsonable(v)}


func _jsonable(v, depth := 0):
	if depth > 4:
		return str(v)
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return v
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(v)
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [v.x, v.y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [v.x, v.y, v.z]
		TYPE_COLOR:
			return v.to_html()
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY:
			return Array(v).map(func(x): return _jsonable(x, depth + 1))
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[str(k)] = _jsonable(v[k], depth + 1)
			return d
		TYPE_OBJECT:
			if v is Node:
				return _describe(v)
			return str(v)
	return str(v)


# --- tree / ui -----------------------------------------------------------------------

func _describe(n: Node) -> Dictionary:
	var d := {"name": str(n.name), "class": n.get_class(), "path": str(n.get_path())}
	var sc: Script = n.get_script()
	if sc and sc.resource_path != "":
		d["script"] = sc.resource_path
	if n is CanvasItem:
		d["visible"] = (n as CanvasItem).is_visible_in_tree()
	if "text" in n and n.text is String and n.text != "":
		d["text"] = n.text
	if n is Control:
		var r := (n as Control).get_global_rect()
		d["rect"] = [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]
		if (n as Control).has_focus():
			d["focus"] = true
	elif n is Node3D:
		var p := (n as Node3D).global_position
		d["pos"] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]
	return d


func _node_info(n: Node, depth: int) -> Dictionary:
	var d := _describe(n)
	if depth > 0 and n.get_child_count() > 0:
		d["children"] = n.get_children().filter(func(c: Node) -> bool: return c != self).map(func(c: Node) -> Dictionary: return _node_info(c, depth - 1))
	elif n.get_child_count() > 0:
		d["n_children"] = n.get_child_count()
	return d


func _collect_ui(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Control and (("text" in n and n.text is String and n.text != "") or (n as Control).has_focus() or n is BaseButton):
		out.append(_describe(n))
	for c in n.get_children():
		_collect_ui(c, out)


# --- input ------------------------------------------------------------------------

const JOY := {"a": JOY_BUTTON_A, "b": JOY_BUTTON_B, "x": JOY_BUTTON_X, "y": JOY_BUTTON_Y, "lb": JOY_BUTTON_LEFT_SHOULDER,
	"rb": JOY_BUTTON_RIGHT_SHOULDER, "start": JOY_BUTTON_START, "back": JOY_BUTTON_BACK, "up": JOY_BUTTON_DPAD_UP,
	"down": JOY_BUTTON_DPAD_DOWN, "left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT, "guide": JOY_BUTTON_GUIDE,
	"ls": JOY_BUTTON_LEFT_STICK, "rs": JOY_BUTTON_RIGHT_STICK}
const AXES := {"lx": JOY_AXIS_LEFT_X, "ly": JOY_AXIS_LEFT_Y, "rx": JOY_AXIS_RIGHT_X, "ry": JOY_AXIS_RIGHT_Y,
	"lt": JOY_AXIS_TRIGGER_LEFT, "rt": JOY_AXIS_TRIGGER_RIGHT}


## Tap (or hold for `frames`) an action, a key ("Enter", "A", "Space") or a joypad button/axis.
func _press(r: Dictionary) -> Dictionary:
	var down: InputEvent
	var up: InputEvent
	if r.has("action"):
		var a := StringName(str(r.action))
		if not InputMap.has_action(a):
			return {"error": "no action " + str(a)}
		down = InputEventAction.new(); down.action = a; down.pressed = true; down.strength = 1.0
		up = InputEventAction.new(); up.action = a; up.pressed = false
	elif r.has("key"):
		var code := OS.find_keycode_from_string(str(r.key))
		if code == KEY_NONE:
			return {"error": "unknown key " + str(r.key)}
		down = InputEventKey.new(); down.keycode = code; down.physical_keycode = code; down.pressed = true
		up = InputEventKey.new(); up.keycode = code; up.physical_keycode = code; up.pressed = false
	elif r.has("joy"):
		var name := str(r.joy).to_lower()
		if AXES.has(name):
			down = InputEventJoypadMotion.new(); down.axis = AXES[name]; down.axis_value = float(r.get("value", 1.0))
			up = InputEventJoypadMotion.new(); up.axis = AXES[name]; up.axis_value = 0.0
		elif JOY.has(name):
			down = InputEventJoypadButton.new(); down.button_index = JOY[name]; down.pressed = true; down.pressure = 1.0
			up = InputEventJoypadButton.new(); up.button_index = JOY[name]; up.pressed = false
		else:
			return {"error": "unknown joy input %s (buttons %s, axes %s)" % [name, JOY.keys(), AXES.keys()]}
		down.device = int(r.get("device", 0))
		up.device = down.device
	else:
		return {"error": "press needs action, key or joy"}
	_note("▶ " + str(r.get("action", r.get("key", r.get("joy", "")))) + (" %.1f" % float(r.value) if r.has("value") else ""))
	Input.parse_input_event(down)
	for i in maxi(1, int(r.get("frames", 2))):
		await get_tree().process_frame
	Input.parse_input_event(up)
	await get_tree().process_frame
	return {"ok": true}


func _click(r: Dictionary) -> Dictionary:
	var at := Vector2(float(r.get("x", 0)), float(r.get("y", 0)))
	if r.has("node"):
		var n: Node = get_tree().root.get_node_or_null(str(r.node))
		if not n is Control:
			return {"error": "no Control at " + str(r.node)}
		at = (n as Control).get_global_rect().get_center()
	_note("▶ click %d,%d" % [at.x, at.y])
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		Input.parse_input_event(e)
		await get_tree().process_frame
	return {"ok": true, "at": [at.x, at.y]}
