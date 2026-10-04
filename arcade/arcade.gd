extends Node
## Launcher + lobby for the collection.
## - Steam Frame (OpenXR up, or DUO_HOST): hosts a lobby and shows the game list in VR.
## - TV (DUO_JOIN=<host>): joins the lobby and shows a controller-friendly picker.
## Whoever picks, both machines start the same game, which then does its own host/join.
## With a single game, ARCADE_GAME=<id>, or no lobby partner, it behaves like a plain local menu.

const GAMES := [
	{"id": "duo_arena", "cat": "action", "name": "DUO ARENA", "scene": "res://games/duo_arena/main.tscn",
		"blurb": "Neon first-person co-op arena shooter"},
	{"id": "ghost_lantern", "cat": "action", "name": "GHOST LANTERN", "scene": "res://games/ghost_lantern/main.tscn",
		"blurb": "Spooky-cute ghost hunt: VR lantern reveals ghosts, TV players vacuum them up"},
	{"id": "snowball_blitz", "cat": "action", "name": "SNOWBALL BLITZ", "scene": "res://games/snowball_blitz/main.tscn",
		"blurb": "Cosy snow-fort defence: throw real snowballs in VR, pack the walls on the TV"},
	{"id": "cannon_cove", "cat": "action", "name": "CANNON COVE", "scene": "res://games/cannon_cove/main.tscn",
		"blurb": "Pirate co-op: VR gunner aims the cannons, TV deckhands load them and patch leaks"},
	{"id": "kitchen_rush", "cat": "party", "name": "KITCHEN RUSH", "scene": "res://games/kitchen_rush/main.tscn",
		"blurb": "Co-op cooking chaos: VR chef chops and plates, TV runners fetch and serve"},
	{"id": "giants_table", "cat": "action", "name": "GIANT'S TABLE", "scene": "res://games/giants_table/main.tscn",
		"blurb": "Be a VR giant protecting a tiny tabletop village; TV players are the knights"},
	{"id": "rocket_workshop", "cat": "cosy", "name": "ROCKET WORKSHOP", "scene": "res://games/rocket_workshop/main.tscn",
		"blurb": "Cosy rocket puzzle: the VR pilot works the controls, the TV crew read the blueprints out loud"},
	{"id": "marble_maze", "cat": "sports", "name": "MARBLE MAZE", "scene": "res://games/marble_maze/main.tscn",
		"blurb": "Ball racing: VR tilts a giant tabletop maze, everyone on the TV is a marble"},
	{"id": "hide_and_seek", "cat": "party", "name": "HIDE AND SEEK", "scene": "res://games/hide_and_seek/main.tscn",
		"blurb": "VR seeker with a torch; TV hiders sneak or disguise as lamps, plants and boxes"},
	{"id": "block_builders", "cat": "cosy", "name": "BLOCK BUILDERS", "scene": "res://games/block_builders/main.tscn",
		"blurb": "VR giant builds bridges and springs; tiny TV runners race to the flag"},
	{"id": "dragon_rider", "cat": "action", "name": "DRAGON RIDER", "scene": "res://games/dragon_rider/main.tscn",
		"blurb": "VR steers a friendly dragon with the reins; TV gunners pop balloons from its back"},
	{"id": "bee_garden", "cat": "cosy", "name": "BEE GARDEN", "scene": "res://games/bee_garden/main.tscn",
		"blurb": "Cosy, no fighting: VR gardener plants and waters, TV bees make honey"},
	{"id": "paint_and_guess", "cat": "party", "name": "PAINT AND GUESS", "scene": "res://games/paint_and_guess/main.tscn",
		"blurb": "VR paints a secret word in the air; TV players race to guess it"},
	{"id": "rhythm_band", "cat": "party", "name": "RHYTHM BAND", "scene": "res://games/rhythm_band/main.tscn",
		"blurb": "VR drums with your hands; TV players hit notes on their highways"},
	{"id": "penalty_shootout", "cat": "sports", "name": "PENALTY SHOOTOUT", "scene": "res://games/penalty_shootout/main.tscn",
		"blurb": "VR goalkeeper saves with big gloves; TV strikers aim, power up and bend shots"},
	{"id": "fishing_lake", "cat": "cosy", "name": "FISHING LAKE", "scene": "res://games/fishing_lake/main.tscn",
		"blurb": "Relaxing: VR casts and reels from the jetty; TV rowers herd fish and net treasure"},
	{"id": "kart_race", "cat": "sports", "name": "KART RACE", "scene": "res://games/kart_race/main.tscn",
		"blurb": "VR turns a real steering wheel; TV racers drive in split screen, with items and ramps"},
	{"id": "tiny_town_tycoon", "cat": "cosy", "name": "TINY TOWN TYCOON", "scene": "res://games/tiny_town_tycoon/main.tscn",
		"blurb": "Build a cosy toy town together: the mayor places the buildings, the drivers bring it to life"},
	{"id": "party_board", "cat": "party", "name": "PARTY BOARD", "scene": "res://games/party_board/main.tscn",
		"blurb": "A Mario-Party-style board game on a diorama island: roll, hop, shop and duel for STARS, with a minigame after every round"},
	{"id": "mech_titans", "cat": "action", "name": "MECH TITANS", "scene": "res://games/mech_titans/main.tscn",
		"blurb": "Giant robot vs cute kaiju: VR pilot punches and beams from the cockpit, TV jets, trucks, drones and tanks support"},
]
## Tabs on the TV (LB/RB) and in VR (stick left/right). Empty categories are hidden.
const CATEGORIES := [
	{"id": "action", "name": "ACTION", "color": Color(1.0, 0.45, 0.35)},
	{"id": "adventure", "name": "ADVENTURE", "color": Color(0.65, 0.5, 1.0)},
	{"id": "party", "name": "PARTY", "color": Color(1.0, 0.8, 0.3)},
	{"id": "sports", "name": "SPORTS & RACING", "color": Color(0.35, 0.9, 0.5)},
	{"id": "cosy", "name": "COSY & PUZZLE", "color": Color(0.45, 0.8, 1.0)},
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
var buttons: Array[Button] = []  # (old menu; kept so a hot reload of an older arcade still works)
var cards: Dictionary = {}  # game index -> Button, for the category on screen
var cat := 0  # index into tabs()
var tab_bar: HBoxContainer
var grid: GridContainer
var vr_stick_x_ready := true
var vr_list: Label3D
var vr_cam: XRCamera3D
var hand_r: XRController3D
var stick_ready := true
var trigger_was := true  # a trigger still held from leaving a game must be released first
var starting := false


func _ready() -> void:
	get_tree().paused = false  # the lobby must never start paused (a game can leave the tree paused)
	XRServer.world_scale = 1.0  # a game (Giant's Table) may have left the world scaled up
	var wanted := OS.get_environment("ARCADE_GAME") if OS.has_environment("ARCADE_GAME") else ""
	# ARCADE_GAME only picks the FIRST game: coming back to the arcade must show the lobby, not
	# start that game again.
	if get_tree().root.has_meta("arcade_auto_started"):
		wanted = ""
	elif wanted != "":
		get_tree().root.set_meta("arcade_auto_started", true)
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
	_ensure_shared_nodes()
	_ensure_fullscreen()
	_hide_tv_cursor()
	if not has_meta("menu_v4") and (not buttons.is_empty() or grid == null) and status != null:
		set_meta("menu_v4", true)  # hot reload: replace an older TV menu with the category tabs
		for c in get_children():
			if c is CanvasLayer:
				c.queue_free()
		buttons.clear()
		_build_tv_menu()
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
		VrText.follow(vr_list, vr_cam, self, 0.25, 2.4)  # always findable; raised so a seated player's list stays above the floor
		if not has_meta("vr_floor"):
			set_meta("vr_floor", true)
			_build_vr_floor()


# --- TV menu ---------------------------------------------------------------

func _build_tv_menu() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TvMenu"
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.08)
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var glow := ColorRect.new()  # a soft band of colour behind the title
	glow.color = Color(0.12, 0.08, 0.3)
	layer.add_child(glow)
	glow.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	glow.custom_minimum_size = Vector2(0, 150)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	layer.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.position.y = 28
	var title := Label.new()
	title.text = "LIVING ROOM ARCADE"
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.3))
	title.add_theme_constant_override("outline_size", 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 24)
	status.add_theme_color_override("font_color", Color(0.75, 0.8, 0.95))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status)
	_set_status({"host": "Waiting for the TV... (or pick in VR)", "client": "Looking for the VR player..."}.get(mode, "Pick a game"))
	tab_bar = HBoxContainer.new()
	tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_bar.add_theme_constant_override("separation", 10)
	box.add_child(tab_bar)
	grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 16)
	var center := CenterContainer.new()
	center.custom_minimum_size = Vector2(1860, 0)
	center.add_child(grid)
	box.add_child(center)
	var hint := Label.new()
	hint.text = "LB / RB (Q / E): change category   ·   D-pad / arrows: choose   ·   A / Enter: play   ·   more games: just ask Claude!"
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	cat = maxi(0, tabs().find(_cat_index_of(selected)))
	_show_category(cat, false)


## Categories that have at least one game, as indices into CATEGORIES.
func tabs() -> Array[int]:
	var out: Array[int] = []
	for c in CATEGORIES.size():
		for g in GAMES:
			if str(g.get("cat", "action")) == str(CATEGORIES[c].id):
				out.append(c)
				break
	return out


func _cat_index_of(game_index: int) -> int:
	var id := str(GAMES[clampi(game_index, 0, GAMES.size() - 1)].get("cat", "action"))
	for c in CATEGORIES.size():
		if str(CATEGORIES[c].id) == id:
			return c
	return 0


func _games_in(tab: int) -> Array[int]:
	var out: Array[int] = []
	var t := tabs()
	if t.is_empty():
		return out
	var c: int = t[clampi(tab, 0, t.size() - 1)]
	for i in GAMES.size():
		if str(GAMES[i].get("cat", "action")) == str(CATEGORIES[c].id):
			out.append(i)
	return out


## Show one category's game cards (focus the selected game if it's in it, else the first).
func _show_category(tab: int, focus_first: bool) -> void:
	var t := tabs()
	if t.is_empty() or grid == null:
		return
	cat = wrapi(tab, 0, t.size())
	for child in tab_bar.get_children():
		child.queue_free()
	for k in t.size():
		var cd: Dictionary = CATEGORIES[t[k]]
		var tab_label := Label.new()
		tab_label.text = "  %s  " % cd.name
		tab_label.add_theme_font_size_override("font_size", 26 if k == cat else 22)
		var on := k == cat
		tab_label.add_theme_color_override("font_color", Color(0.05, 0.05, 0.1) if on else (cd.color as Color))
		var sb := StyleBoxFlat.new()
		sb.bg_color = (cd.color as Color) if on else Color(0.1, 0.1, 0.18)
		sb.set_corner_radius_all(18)
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		tab_label.add_theme_stylebox_override("normal", sb)
		tab_bar.add_child(tab_label)
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	cards.clear()
	var colour: Color = CATEGORIES[t[cat]].color
	var games := _games_in(cat)
	for i in games:
		var b := _make_card(i, colour)
		grid.add_child(b)
		cards[i] = b
	var target: int = selected if cards.has(selected) and not focus_first else (games[0] if not games.is_empty() else 0)
	if cards.has(target):
		(cards[target] as Button).grab_focus()


func _make_card(i: int, colour: Color) -> Button:
	var g: Dictionary = GAMES[i]
	var b := Button.new()
	b.custom_minimum_size = Vector2(600, 150)
	b.focus_mode = Control.FOCUS_ALL
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.08, 0.15)
	normal.border_color = colour.darkened(0.45)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(16)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(0.13, 0.12, 0.24)
	focus.border_color = colour
	focus.set_border_width_all(6)
	focus.shadow_color = Color(colour, 0.35)
	focus.shadow_size = 12
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", focus)
	b.add_theme_stylebox_override("pressed", focus)
	b.add_theme_stylebox_override("focus", focus)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	b.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 22
	v.offset_right = -22
	v.offset_top = 16
	v.offset_bottom = -12
	var name_label := Label.new()
	name_label.text = str(g.name)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", 30)
	name_label.add_theme_color_override("font_color", colour)
	v.add_child(name_label)
	var blurb := Label.new()
	blurb.text = str(g.blurb)
	blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override("font_size", 19)
	blurb.add_theme_color_override("font_color", Color(0.85, 0.87, 0.95))
	v.add_child(blurb)
	b.pressed.connect(_start_everywhere.bind(i))
	b.focus_entered.connect(_select.bind(i, true))
	return b


func _unhandled_input(event: InputEvent) -> void:
	if grid == null or starting:
		return
	var step := 0
	var pad := event as InputEventJoypadButton
	if pad and pad.pressed:
		if pad.button_index == JOY_BUTTON_LEFT_SHOULDER:
			step = -1
		elif pad.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			step = 1
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		if key.physical_keycode == KEY_Q or key.physical_keycode == KEY_PAGEUP:
			step = -1
		elif key.physical_keycode == KEY_E or key.physical_keycode == KEY_PAGEDOWN or key.physical_keycode == KEY_TAB:
			step = 1
	if step != 0:
		get_viewport().set_input_as_handled()
		_show_category(cat + step, true)


func _set_status(text: String) -> void:
	if status:
		status.text = text


## Keep the TV focus and the VR highlight in step (and tell the other machine).
func _select(index: int, broadcast: bool) -> void:
	selected = clampi(index, 0, GAMES.size() - 1)
	if not broadcast and grid != null:
		var want := tabs().find(_cat_index_of(selected))
		if want >= 0 and want != cat:
			_show_category(want, false)
		if cards.has(selected) and not (cards[selected] as Button).has_focus():
			(cards[selected] as Button).grab_focus()
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
	vr_list.pixel_size = 0.0026
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
	var t := tabs()
	var my_tab := maxi(0, t.find(_cat_index_of(selected)))
	lines.append("<   %s   >" % CATEGORIES[t[my_tab]].name if not t.is_empty() else "")
	lines.append("")
	var games := _games_in(my_tab)
	# A window of games around the selection so the list stays a comfortable size.
	var pos := maxi(0, games.find(selected))
	var first := clampi(pos - 3, 0, maxi(0, games.size() - 7))
	var last := mini(games.size(), first + 7)
	if first > 0:
		lines.append("^ more ^")
	for k in range(first, last):
		var i: int = games[k]
		lines.append((">>  %s  <<" if i == selected else "%s") % GAMES[i].name)
	if last < games.size():
		lines.append("v more v")
	lines.append("")
	lines.append("Stick up/down: choose  ·  left/right: category\nTrigger: play  (or pick on the TV)")
	vr_list.text = "\n".join(lines)


func _vr_input() -> void:
	var stick := hand_r.get_vector2("primary")
	var games := _games_in(maxi(0, tabs().find(_cat_index_of(selected))))
	if absf(stick.y) > 0.7 and stick_ready and not games.is_empty():
		stick_ready = false
		var pos := maxi(0, games.find(selected))
		_select(games[wrapi(pos + (-1 if stick.y > 0.0 else 1), 0, games.size())], true)
	elif absf(stick.y) < 0.3:
		stick_ready = true
	if absf(stick.x) > 0.7 and vr_stick_x_ready:
		vr_stick_x_ready = false
		var t := tabs()
		var next_tab := wrapi(t.find(_cat_index_of(selected)) + (1 if stick.x > 0.0 else -1), 0, t.size())
		var in_next := _games_in(next_tab)
		if not in_next.is_empty():
			_select(in_next[0], true)
			if grid != null:
				_show_category(next_tab, true)
	elif absf(stick.x) < 0.3:
		vr_stick_x_ready = true
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


## The lobby doesn't use core/net.gd, so start the same root-level helpers the games get from it:
## the VR text guard (also a capture mirror, so the live view isn't black here) and Claude's captions.
func _ensure_shared_nodes() -> void:
	var root := get_tree().root
	for pair in [["vr_text_guard", "res://core/vr_text_guard.gd"], ["claude_caption", "res://addons/gdev/caption.gd"]]:
		if root.has_meta(pair[0]) or not ResourceLoader.exists(pair[1]):
			continue
		var n: Node = (load(pair[1]) as GDScript).new()
		root.set_meta(pair[0], n)
		root.add_child.call_deferred(n)


## The TV machine (no VR) runs fullscreen (Simon). Done once per launch, so F11/Alt+Enter still work.
func _ensure_fullscreen() -> void:
	var root := get_tree().root
	if root.has_meta("fullscreen_done") or DisplayServer.get_name() == "headless":
		return
	root.set_meta("fullscreen_done", true)
	var xr := XRServer.primary_interface
	if xr != null and xr.is_initialized():
		return  # the headset draws through OpenXR, not the window
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## No mouse pointer over the TV picture (Simon); it comes back as soon as the mouse moves.
func _hide_tv_cursor() -> void:
	var root := get_tree().root
	if root.has_meta("cursor_hidden") or DisplayServer.get_name() == "headless":
		return
	root.set_meta("cursor_hidden", true)
	var xr := XRServer.primary_interface
	if xr == null or not xr.is_initialized():
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
