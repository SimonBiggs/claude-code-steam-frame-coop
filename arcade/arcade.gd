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
	{"id": "snowball_blitz", "name": "SNOWBALL BLITZ", "scene": "res://games/snowball_blitz/main.tscn",
		"blurb": "Cosy snow-fort defence: throw real snowballs in VR, pack the walls on the TV"},
	{"id": "cannon_cove", "name": "CANNON COVE", "scene": "res://games/cannon_cove/main.tscn",
		"blurb": "Pirate co-op: VR gunner aims the cannons, TV deckhands load them and patch leaks"},
	{"id": "kitchen_rush", "name": "KITCHEN RUSH", "scene": "res://games/kitchen_rush/main.tscn",
		"blurb": "Co-op cooking chaos: VR chef chops and plates, TV runners fetch and serve"},
	{"id": "giants_table", "name": "GIANT'S TABLE", "scene": "res://games/giants_table/main.tscn",
		"blurb": "Be a VR giant protecting a tiny tabletop village; TV players are the knights"},
	{"id": "rocket_workshop", "name": "ROCKET WORKSHOP", "scene": "res://games/rocket_workshop/main.tscn",
		"blurb": "Cosy rocket puzzle: the VR pilot works the controls, the TV crew read the blueprints out loud"},
	{"id": "marble_maze", "name": "MARBLE MAZE", "scene": "res://games/marble_maze/main.tscn",
		"blurb": "Ball racing: VR tilts a giant tabletop maze, everyone on the TV is a marble"},
	{"id": "hide_and_seek", "name": "HIDE AND SEEK", "scene": "res://games/hide_and_seek/main.tscn",
		"blurb": "VR seeker with a torch; TV hiders sneak or disguise as lamps, plants and boxes"},
	{"id": "block_builders", "name": "BLOCK BUILDERS", "scene": "res://games/block_builders/main.tscn",
		"blurb": "VR giant builds bridges and springs; tiny TV runners race to the flag"},
	{"id": "dragon_rider", "name": "DRAGON RIDER", "scene": "res://games/dragon_rider/main.tscn",
		"blurb": "VR steers a friendly dragon with the reins; TV gunners pop balloons from its back"},
	{"id": "bee_garden", "name": "BEE GARDEN", "scene": "res://games/bee_garden/main.tscn",
		"blurb": "Cosy, no fighting: VR gardener plants and waters, TV bees make honey"},
]
const VrText := preload("res://core/vr_text.gd")
const DEFAULT_PORT := 7777
const JOIN_TIMEOUT_MS := 5000

# The lobby listens one port above the games, so a TV still looking for the lobby never
# connects to a game that's already running on the headset.
var port: int = (int(OS.get_environment("DUO_PORT")) if OS.has_environment("DUO_PORT") else DEFAULT_PORT) + 1
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
	XRServer.world_scale = 1.0  # a game (Giant's Table) may have left the world scaled up
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
	if multiplayer.connected_to_server.get_connections().size() > 0:
		return  # already set up by an earlier attempt: just retry with the new peer
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
	_set_status("No VR player found yet (still looking…). You can also play on the TV")


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
	if not has_meta("menu_v2") and not buttons.is_empty():  # hot reload: rebuild the TV menu as two columns
		set_meta("menu_v2", true)
		var layer := buttons[0].get_parent()
		while layer != null and not layer is CanvasLayer:
			layer = layer.get_parent()
		if layer != null:
			layer.queue_free()
		buttons.clear()
		_build_tv_menu()
		_select(selected, false)
	if join_deadline > 0 and Time.get_ticks_msec() > join_deadline:
		_lobby_offline()
	# TV: if the VR player already started a game without us, join it (their game broadcasts it).
	if mode != "host" and not starting and OS.has_environment("DUO_JOIN"):
		_listen_for_game()
	# TV: keep looking for the VR player's lobby (they may be mid-game or restarting).
	if mode == "local" and not starting and OS.has_environment("DUO_JOIN") and not OS.has_environment("ARCADE_GAME"):
		if Time.get_ticks_msec() > int(get_meta("retry_at", 0)):
			set_meta("retry_at", Time.get_ticks_msec() + 4000)
			port = (int(OS.get_environment("DUO_PORT")) if OS.has_environment("DUO_PORT") else DEFAULT_PORT) + 1
			_join_lobby(OS.get_environment("DUO_JOIN"))
	if vr_list:
		_vr_input()
		VrText.follow(vr_list, vr_cam, self, -0.1, 2.2)  # always findable, wherever you look
		if not has_meta("vr_floor"):
			set_meta("vr_floor", true)
			_build_vr_floor()


# --- TV menu ---------------------------------------------------------------

func _build_tv_menu() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.08)
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	layer.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	var title := Label.new()
	title.text = "LIVING ROOM ARCADE"
	title.add_theme_font_size_override("font_size", 56)
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
	# Two columns so all the games fit on the TV.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	for i in GAMES.size():
		var g: Dictionary = GAMES[i]
		var b := Button.new()
		b.text = "%s\n%s" % [g.name, g.blurb]
		b.custom_minimum_size = Vector2(820, 96)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 20)
		b.add_theme_stylebox_override("focus", focus)
		b.pressed.connect(_start_everywhere.bind(i))
		b.focus_entered.connect(_select.bind(i, true))
		grid.add_child(b)
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


## A glowing floor and a ring of pillars so the VR lobby isn't a black void.
func _build_vr_floor() -> void:
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mesh.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.05, 0.06, 0.14)
	fm.emission_enabled = true
	fm.emission = Color(0.1, 0.25, 0.5)
	fm.emission_energy_multiplier = 0.4
	floor_mesh.material_override = fm
	add_child(floor_mesh)
	for i in 12:
		var a := TAU * i / 12.0
		var pillar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.3, 3.0, 0.3)
		pillar.mesh = bm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color.from_hsv(float(i) / 12.0, 0.6, 1.0)
		pillar.material_override = m
		pillar.position = Vector3(sin(a) * 7.0, 1.5, cos(a) * 7.0)
		add_child(pillar)


func _listen_for_game() -> void:
	if not has_meta("listen"):
		var udp := PacketPeerUDP.new()
		var base: int = int(OS.get_environment("DUO_PORT")) if OS.has_environment("DUO_PORT") else DEFAULT_PORT
		if udp.bind(base + 2) != OK:
			set_meta("listen", null)
			return
		set_meta("listen", udp)
	var u = get_meta("listen")
	if u == null:
		return
	var udp: PacketPeerUDP = u
	while udp.get_available_packet_count() > 0:
		var msg := udp.get_packet().get_string_from_utf8()
		if not msg.begins_with("ARCADE_GAME "):
			continue
		var scene := msg.substr(12)
		for i in GAMES.size():
			if GAMES[i].scene == scene:
				print("Arcade: the VR player is already playing %s, joining" % GAMES[i].name)
				udp.close()
				remove_meta("listen")
				mode = "client"
				_launch(i)
				return
