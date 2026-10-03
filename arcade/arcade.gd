extends Node
## Launcher + lobby for the collection.
## - Steam Frame (OpenXR up, or DUO_HOST): hosts a lobby and shows the game list in VR.
## - TV (DUO_JOIN=<host>): joins the lobby and shows a controller-friendly picker.
## Whoever picks, both machines start the same game, which then does its own host/join.
## With a single game, ARCADE_GAME=<id>, or no lobby partner, it behaves like a plain local menu.

const GAMES := [
	{"id": "duo_arena", "name": "DUO ARENA", "scene": "res://games/duo_arena/main.tscn",
		"blurb": "Neon first-person co-op arena shooter"},
	{"id": "ghost_lantern", "name": "GHOST LANTERN", "scene": "res://games/ghost_lantern/main.tscn",
		"blurb": "Spooky-cute ghost hunt: VR lantern reveals ghosts, TV players vacuum them up"},
]
const DEFAULT_PORT := 7777
const JOIN_TIMEOUT_MS := 5000

var port: int = int(OS.get_environment("DUO_PORT")) if OS.has_environment("DUO_PORT") else DEFAULT_PORT
var mode := "local"  # "local", "host", "client"
var selected := 0
var join_deadline := 0
var status: Label
var buttons: Array[Button] = []
var vr_list: Label3D
var vr_cam: XRCamera3D
var hand_r: XRController3D
var stick_ready := true
var trigger_was := false
var starting := false


func _ready() -> void:
	var wanted := OS.get_environment("ARCADE_GAME") if OS.has_environment("ARCADE_GAME") else ""
	if wanted != "" or GAMES.size() == 1:
		_launch(_index_of(wanted))
		return
	var xr := XRServer.find_interface("OpenXR")
	if (xr != null and xr.is_initialized()) or OS.has_environment("DUO_HOST"):
		_host_lobby(xr != null and xr.is_initialized())
	elif OS.has_environment("DUO_JOIN"):
		_join_lobby(OS.get_environment("DUO_JOIN"))
	_build_tv_menu()


func _index_of(id: String) -> int:
	for i in GAMES.size():
		if GAMES[i].id == id:
			return i
	return 0


# --- Lobby networking ----------------------------------------------------------

func _host_lobby(with_vr: bool) -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, 1) != OK:
		print("Arcade: lobby port busy, picking locally")
		return
	mode = "host"
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(func(_id: int) -> void:
		_set_status("The TV is connected: pick a game!")
		_sync_selection.rpc(selected))
	if with_vr:
		_build_vr_view()
	print("Arcade: lobby hosting on %d" % port)


func _join_lobby(address: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, port) != OK:
		return
	mode = "client"
	multiplayer.multiplayer_peer = peer
	join_deadline = Time.get_ticks_msec() + JOIN_TIMEOUT_MS
	multiplayer.connected_to_server.connect(func() -> void:
		join_deadline = 0
		_set_status("Connected to the VR player: pick a game!")
		if OS.has_environment("ARCADE_AUTOPICK"):  # headless tests
			_start_everywhere(int(OS.get_environment("ARCADE_AUTOPICK"))))
	multiplayer.connection_failed.connect(_lobby_offline)
	multiplayer.server_disconnected.connect(_lobby_offline)
	print("Arcade: joining lobby at %s:%d" % [address, port])


func _lobby_offline() -> void:
	if mode != "client":
		return
	join_deadline = 0
	_close_peer()
	mode = "local"
	_set_status("No VR player found: playing on the TV")


func _close_peer() -> void:
	var old := multiplayer.multiplayer_peer
	if old != null and not old is OfflineMultiplayerPeer:
		old.close()
	multiplayer.multiplayer_peer = null


func _exit_tree() -> void:
	_close_peer()


@rpc("any_peer", "call_remote", "reliable")
func _request_start(index: int) -> void:
	if mode == "host":
		_start_everywhere(index)


@rpc("authority", "call_local", "reliable")
func _start(index: int) -> void:
	_launch(index)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _sync_selection(index: int) -> void:
	_select(index, false)


func _start_everywhere(index: int) -> void:
	if mode == "host":
		_start.rpc(index)
	elif mode == "client":
		_request_start.rpc_id(1, index)
	else:
		_launch(index)


## Close the lobby connection and load the game; the game sets up its own networking.
func _launch(index: int) -> void:
	if starting:
		return
	starting = true
	var game: Dictionary = GAMES[clampi(index, 0, GAMES.size() - 1)]
	print("Arcade: starting %s" % game.name)
	# The host keeps the lobby open briefly so the "start" message reaches the TV before it closes;
	# the TV waits a little longer so the host's game is listening by the time it joins.
	var delay := 0.4 if mode == "host" else (0.9 if mode == "client" else 0.1)
	if mode == "client":
		_close_peer()
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		_close_peer()
		get_tree().change_scene_to_file(game.scene))


func _process(_delta: float) -> void:
	if join_deadline > 0 and Time.get_ticks_msec() > join_deadline:
		_lobby_offline()
	if vr_list:
		_vr_input()


# --- TV menu ---------------------------------------------------------------

func _build_tv_menu() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.08)
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	layer.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	var title := Label.new()
	title.text = "LIVING ROOM ARCADE"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 26)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status)
	_set_status({"host": "Waiting for the TV… (or pick in VR)", "client": "Looking for the VR player…"}.get(mode, "Pick a game"))
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(0.3, 0.95, 1.0)
	focus.set_border_width_all(5)
	focus.set_corner_radius_all(10)
	for i in GAMES.size():
		var g: Dictionary = GAMES[i]
		var b := Button.new()
		b.text = "%s\n%s" % [g.name, g.blurb]
		b.custom_minimum_size = Vector2(900, 100)
		b.add_theme_font_size_override("font_size", 28)
		b.add_theme_stylebox_override("focus", focus)
		b.pressed.connect(_start_everywhere.bind(i))
		b.focus_entered.connect(_select.bind(i, true))
		box.add_child(b)
		buttons.append(b)
	var hint := Label.new()
	hint.text = "D-pad / arrows to choose  ·  A / Enter to play  ·  more games: just ask Claude!"
	hint.add_theme_font_size_override("font_size", 22)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	buttons[0].grab_focus()


func _set_status(text: String) -> void:
	if status:
		status.text = text


## Keep the TV focus and the VR highlight in step (and tell the other machine).
func _select(index: int, broadcast: bool) -> void:
	selected = clampi(index, 0, GAMES.size() - 1)
	if not broadcast and selected < buttons.size() and not buttons[selected].has_focus():
		buttons[selected].grab_focus()
	if broadcast and mode != "local" and multiplayer.multiplayer_peer != null:
		_sync_selection.rpc(selected)
	_refresh_vr()


# --- VR view (host) ------------------------------------------------------------

func _build_vr_view() -> void:
	get_viewport().use_xr = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.03, 0.08)
	env.environment = e
	add_child(env)
	var origin := XROrigin3D.new()
	add_child(origin)
	vr_cam = XRCamera3D.new()
	origin.add_child(vr_cam)
	hand_r = XRController3D.new()
	hand_r.tracker = "right_hand"
	hand_r.pose = "aim"
	origin.add_child(hand_r)
	vr_list = Label3D.new()
	vr_list.font_size = 44
	vr_list.outline_size = 22
	vr_list.pixel_size = 0.003
	vr_list.width = 1100.0
	vr_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vr_list.modulate = Color(0.85, 0.97, 1.0)
	add_child(vr_list)
	vr_list.position = Vector3(0, 1.5, -2.2)
	_refresh_vr()


func _refresh_vr() -> void:
	if vr_list == null:
		return
	var lines: Array[String] = ["LIVING ROOM ARCADE", ""]
	for i in GAMES.size():
		lines.append(("▶  %s  ◀" if i == selected else "%s") % GAMES[i].name)
	lines.append("")
	lines.append("Right stick: choose  ·  Trigger: play\n(or pick on the TV)")
	vr_list.text = "\n".join(lines)


func _vr_input() -> void:
	var y := hand_r.get_vector2("primary").y
	if absf(y) > 0.7 and stick_ready:
		stick_ready = false
		_select(selected + (-1 if y > 0.0 else 1), true)
	elif absf(y) < 0.3:
		stick_ready = true
	var trig := hand_r.get_float("trigger") > 0.6
	if trig and not trigger_was:
		_start_everywhere(selected)
	trigger_was = trig
