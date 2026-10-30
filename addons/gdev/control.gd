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
##   vr     {head?, look?, left?, right?, trigger?, grip?, a?, b?, stick_l?, stick_r?}   drive the VR player in
##                                 fake VR (launch with BOT_VR=1): world positions [x,y,z] (or {head: [dx,dy,dz],
##                                 relative: true} to move by), look = point the head faces; trigger/grip 0..1,
##                                 a/b bools, sticks [x,y]. Sets the XR nodes and every fake_* field games read.
##                                 Returns the current head/hand positions. {} just reports.
##   camshot {camera?, path, width?, height?}   PNG from a camera (default: the VR head, the first XRCamera3D):
##                                 what the headset would show, rendered in its own viewport
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
			var img := _grab(get_viewport())
			if img != null:
				rec_tasks.append(WorkerThreadPool.add_task(_save_frame.bind(img, "%s/%08d.jpg" % [rec_dir, now - rec_t0])))
			rec_frames += 1
			_record_vr(now)


# The VR head's view, recorded next to the TV frames (rec/vr/<ms>.jpg) whenever there is an XR camera
# (fake VR: BOT_VR=1), so span sheets can show what the headset player saw.
var vr_vp: SubViewport
var vr_cam: Camera3D

func _record_vr(now: int) -> void:
	var head: Camera3D = _xr_nodes().head
	if head == null or not head.is_inside_tree():
		return
	if vr_vp == null or not is_instance_valid(vr_vp) or vr_vp.world_3d != head.get_world_3d():
		if vr_vp and is_instance_valid(vr_vp):
			vr_vp.queue_free()
		vr_vp = SubViewport.new()
		vr_vp.size = Vector2i(rec_width, int(rec_width * 9 / 16))
		vr_vp.world_3d = head.get_world_3d()
		vr_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vr_cam = Camera3D.new()
		vr_cam.fov = 90.0
		vr_vp.add_child(vr_cam)
		add_child(vr_vp)
		vr_cam.current = true
		DirAccess.make_dir_recursive_absolute(rec_dir + "/vr")
		return  # nothing drawn in it yet: grab from the next frame
	vr_cam.global_transform = head.global_transform
	vr_cam.near = head.near
	vr_cam.cull_mask = head.cull_mask
	var img := _grab(vr_vp)
	if img:
		rec_tasks.append(WorkerThreadPool.add_task(_save_frame.bind(img, "%s/vr/%08d.jpg" % [rec_dir, now - rec_t0])))


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
	rec_audio.flush()  # so span() sheets made right now have the latest sound, not a silent last tile


func _save_frame(img: Image, path: String) -> void:
	if img == null or img.is_empty():
		return
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
			var img := _grab(get_viewport())
			if img == null:
				return {"error": "nothing drawn yet"}
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
		"vr":
			return _vr(r)
		"camshot":
			return await _camshot(r)
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
	# Several lines: the last one is returned too when it's an unindented expression (like the brepl).
	var last := lines[lines.size() - 1]
	if not single and not last.begins_with("\t") and not last.begins_with(" ") and not _STATEMENT.any(func(k: String) -> bool: return last.begins_with(k)) \
			and not RegEx.create_from_string("^[\\w.\\[\\]\"]+\\s*[-+*/]?=[^=]").search(last):
		lines[lines.size() - 1] = "return " + last
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
		# Screen pixels: get_global_rect() ignores CanvasLayer offsets and split-view SubViewports.
		var xf := (n as Control).get_screen_transform()
		var sz := (n as Control).size * xf.get_scale()
		d["rect"] = [roundi(xf.origin.x), roundi(xf.origin.y), roundi(sz.x), roundi(sz.y)]
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


# --- fake VR (BOT_VR=1) ------------------------------------------------------------

func _xr_nodes() -> Dictionary:
	var root := get_tree().root
	var cams := root.find_children("*", "XRCamera3D", true, false)
	var ctrls := root.find_children("*", "XRController3D", true, false)
	var out := {"head": cams[0] if cams.size() else null, "left": null, "right": null}
	for c in ctrls:
		var t := str((c as XRController3D).tracker)
		if t == "left_hand" and out.left == null:
			out.left = c
		elif t == "right_hand" and out.right == null:
			out.right = c
	return out


func _v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## Every node with a fake_<name> property (core/vr_rig.gd, games' own VR players) gets the value.
func _set_fake(field: String, value) -> int:
	var n := 0
	for node in get_tree().root.find_children("*", "", true, false):
		if field in node:
			node.set(field, value)
			n += 1
	return n


## Fake hand trackers in the XRServer, so games that read the controller directly (hand.get_float("trigger"),
## is_button_pressed("ax_button"), the pose) get input exactly as from a real headset.
func _tracker(hand_name: String, node: XRController3D) -> XRPositionalTracker:
	var t := XRServer.get_tracker(hand_name) as XRPositionalTracker
	if t == null:
		t = XRControllerTracker.new()
		t.name = hand_name
		t.type = XRServer.TRACKER_CONTROLLER
		t.hand = XRPositionalTracker.TRACKER_HAND_LEFT if hand_name == "left_hand" else XRPositionalTracker.TRACKER_HAND_RIGHT
		XRServer.add_tracker(t)
		if node:
			_pose(t, node)
	return t


## The tracker pose = the node's transform relative to its XROrigin3D (what a headset would report).
func _pose(t: XRPositionalTracker, node: XRController3D) -> void:
	var origin := node.get_parent() as Node3D
	var local := origin.global_transform.affine_inverse() * node.global_transform if origin else node.transform
	# Tracker poses are in real metres; XRNode3D multiplies by world_scale (giant / tiny modes, e.g. 18 in
	# Coaster Crew), so divide it out or the hand flies off 18x too far.
	local.origin /= maxf(XRServer.world_scale, 0.001)
	t.set_pose(node.pose, local, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)


func _vr(r: Dictionary) -> Dictionary:
	var x := _xr_nodes()
	if x.head == null:
		return {"error": "no XRCamera3D: launch with env BOT_VR=1 (and a game that has a VR player)"}
	var tl := _tracker("left_hand", x.left)
	var tr := _tracker("right_hand", x.right)
	var rel := bool(r.get("relative", false))
	for k in ["head", "left", "right"]:
		if r.has(k) and x[k] != null:
			var n: Node3D = x[k]
			n.global_position = (n.global_position + _v3(r[k])) if rel else _v3(r[k])
			if k != "head":
				_pose(tl if k == "left" else tr, n)
	if r.has("look"):
		var h: Node3D = x.head
		var at := _v3(r.look)
		if at.distance_to(h.global_position) > 0.01:
			h.look_at(at, Vector3.UP)
	var changed := {}
	# Controller inputs (both hands: games differ on which hand fires), then the fake_* fields below.
	for t in [tl, tr]:
		if r.has("trigger"):
			t.set_input("trigger", float(r.trigger))
			t.set_input("trigger_click", float(r.trigger) > 0.5)
		if r.has("grip"):
			t.set_input("grip", float(r.grip))
			t.set_input("grip_click", float(r.grip) > 0.5)
		if r.has("a"):
			t.set_input("ax_button", bool(r.a))
		if r.has("b"):
			t.set_input("by_button", bool(r.b))
	if r.has("stick_l"):
		tl.set_input("primary", Vector2(float(r.stick_l[0]), float(r.stick_l[1])))
	if r.has("stick_r"):
		tr.set_input("primary", Vector2(float(r.stick_r[0]), float(r.stick_r[1])))
	for pair in [["trigger", "fake_trigger"], ["grip", "fake_grip"], ["a", "fake_a"], ["b", "fake_b"]]:
		if r.has(pair[0]):
			changed[pair[0]] = _set_fake(pair[1], r[pair[0]])
	for pair in [["stick_l", ["fake_stick_l", "fake_stick"]], ["stick_r", ["fake_stick_r"]]]:
		if r.has(pair[0]):
			var v := Vector2(float(r[pair[0]][0]), float(r[pair[0]][1]))
			for f in pair[1]:
				changed[f] = _set_fake(f, v)
	if r.has("trigger") or r.has("a"):
		_note("▶ vr " + str(r.keys().filter(func(k): return k in ["trigger", "a", "b", "grip", "stick_l", "stick_r"]).map(func(k): return "%s=%s" % [k, r[k]])))
	var pos := func(n): return [snappedf(n.global_position.x, 0.01), snappedf(n.global_position.y, 0.01), snappedf(n.global_position.z, 0.01)] if n else null
	return {"head": pos.call(x.head), "left": pos.call(x.left), "right": pos.call(x.right), "set": changed}


func _camshot(r: Dictionary) -> Dictionary:
	var src: Camera3D = null
	if r.has("camera"):
		src = get_tree().root.get_node_or_null(str(r.camera)) as Camera3D
	else:
		src = _xr_nodes().head
	if src == null:
		return {"error": "no camera (default is the VR head: launch with BOT_VR=1)"}
	var vp := SubViewport.new()
	vp.size = Vector2i(int(r.get("width", 1280)), int(r.get("height", 720)))
	vp.world_3d = src.get_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam := Camera3D.new()
	cam.fov = 90.0 if src is XRCamera3D else src.fov  # roughly a headset's field of view
	cam.near = src.near
	cam.far = src.far
	cam.cull_mask = src.cull_mask
	vp.add_child(cam)
	add_child(vp)
	cam.global_transform = src.global_transform
	cam.current = true
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := _grab(vp)
	vp.queue_free()
	if img == null:
		return {"error": "nothing drawn yet"}
	var path := str(r.get("path", ProjectSettings.globalize_path("res://.dev/camshot.png")))
	var err := img.save_png(path)
	return {"path": path} if err == OK else {"error": "save failed: %d" % err}


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
