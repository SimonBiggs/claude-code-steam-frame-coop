extends Node
## gdev bridge (development only). Installed as an autoload by the `gdev` CLI.
## - Hot-reloads edited .gd files in place (keeping state); restarts the scene when a .tscn changes.
## - Records a low-res frame every FRAME_INTERVAL seconds to res://.dev/frames/<unix_ms>.jpg.
## - Runs commands the CLI writes to res://.dev/cmd: restart, shot [width], pause, resume, record on|off, quit.

const DEV_DIR := "res://.dev"
const SELF_PATH := "res://addons/gdev/bridge.gd"
const FRAME_INTERVAL := 0.5  # override with env GDEV_FRAME_INTERVAL
const FRAME_WIDTH := 960
const MAX_FRAMES := 2400  # about 20 minutes at 0.5 s

var dev_dir := ""
var frames_dir := ""
var hashes := {}
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	_scan_files(true)
	if DisplayServer.get_name() != "headless":
		stream_server = TCPServer.new()
		if stream_server.listen(STREAM_PORT) == OK:
			_log("live view: http://%s:%d/" % [OS.get_environment("HOSTNAME") if OS.has_environment("HOSTNAME") else "localhost", STREAM_PORT])
		else:
			stream_server = null
	rd = RenderingServer.get_rendering_device()
	if OS.has_environment("GDEV_FRAME_INTERVAL"):
		frame_interval = float(OS.get_environment("GDEV_FRAME_INTERVAL"))
	if DisplayServer.get_name() == "headless":
		recording = false  # nothing is rendered, so there is nothing to record
	_log("bridge ready (pid %d)" % OS.get_process_id())


func _process(delta: float) -> void:
	if not is_instance_valid(caption) and ResourceLoader.exists("res://addons/gdev/caption.gd"):
		caption = (load("res://addons/gdev/caption.gd") as GDScript).new()
		add_child(caption)
	poll_t += delta
	if poll_t >= 0.25:
		poll_t = 0.0
		_scan_files(false)
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


func _scan_files(initial: bool) -> void:
	var paths: Array[String] = []
	_list_files("res://", paths)
	var scene_changed := false
	for path in paths:
		var h := FileAccess.get_md5(path)
		if hashes.get(path, "") == h:
			continue
		var known := hashes.has(path)
		hashes[path] = h
		if initial or not known or path == SELF_PATH:
			continue
		if path.ends_with(".gd"):
			_reload_script(path)
		elif ResourceLoader.has_cached(path) or path == get_tree().current_scene.scene_file_path:
			scene_changed = true  # only scenes in use restart the game (a new game's files don't)
	if scene_changed:
		_log("scene file changed, restarting scene")
		_restart()


func _reload_script(path: String) -> void:
	if not ResourceLoader.has_cached(path):
		return  # not loaded yet; it will be read fresh when first used
	var s := load(path) as GDScript
	if s == null:
		return
	s.source_code = FileAccess.get_file_as_string(path)
	var err := s.reload(true)
	if err != OK:
		_log("RELOAD FAILED %s: %s (fix it and save again)" % [path, error_string(err)])
		return
	_apply_new_defaults(s)
	_log("reloaded " + path)


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
				get_tree().quit()
			_:
				_log("unknown command: " + line)


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
	var img := vp.get_texture().get_image()
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
	var img := vp.get_texture().get_image()  # fallback (can hitch)
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
	for c in stream_clients:
		if c.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			c.put_data(part)
			c.put_data(jpeg)
			c.put_data("\r\n".to_utf8_buffer())


func _capture_viewport() -> Viewport:
	var custom := get_tree().get_nodes_in_group("gdev_capture")
	if not custom.is_empty() and custom[0] is Viewport:
		return custom[0]
	return get_viewport()


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
