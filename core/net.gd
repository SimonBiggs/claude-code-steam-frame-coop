extends Node
## Networked co-op over the home network. The Steam Frame (VR) hosts and simulates the game;
## the Steam Machine joins as player 2 (env DUO_JOIN=<host>), renders the shared world and drives its own player.
## Host -> client: 30 Hz snapshots plus reliable one-off events. Client -> host: player 2 state and actions.

signal join_finished(ok: bool)

const DEFAULT_PORT := 7777
var PORT: int = int(OS.get_environment("DUO_PORT")) if OS.has_environment("DUO_PORT") else DEFAULT_PORT  # override for parallel tests
const SNAP_INTERVAL := 1.0 / 30.0
const JOIN_TIMEOUT := 5.0

var main
var mode := "local"  # "local", "host" or "client"
var connected := false
var snap_t := 0.0
var join_deadline := 0  # Time.get_ticks_msec() when an unanswered join gives up (0 = not joining)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep the connection alive while the game is paused


func host() -> void:
	mode = "host"
	_try_listen()


## Keeps trying while the port is busy (e.g. an older copy of the game is still shutting down).
func _try_listen() -> void:
	_close_old_peer()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, 1) != OK:
		print("Net: port %d busy, retrying" % PORT)
		get_tree().create_timer(1.0).timeout.connect(_try_listen)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("Net: hosting on port %d" % PORT)


func join(address: String) -> void:
	_close_old_peer()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, PORT) != OK:
		join_finished.emit(false)
		return
	mode = "client"
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_give_up)
	multiplayer.server_disconnected.connect(_on_server_gone)
	# After a successful game, keep retrying (the host may just be restarting).
	var wait := 3600.0 if Engine.has_meta("duo_joined") else JOIN_TIMEOUT
	join_deadline = Time.get_ticks_msec() + int(wait * 1000.0)
	print("Net: joining %s:%d" % [address, PORT])


## The multiplayer peer belongs to the SceneTree and survives scene reloads; close it so the port is freed.
func _close_old_peer() -> void:
	var old := multiplayer.multiplayer_peer
	if old != null and not old is OfflineMultiplayerPeer:
		old.close()
	multiplayer.multiplayer_peer = null


func _exit_tree() -> void:
	_close_old_peer()


var menu_was_down := false


func _process(delta: float) -> void:
	_check_vr_menu()
	if join_deadline > 0 and Time.get_ticks_msec() > join_deadline:
		_give_up()
	if mode == "host" and connected:
		snap_t -= delta
		if snap_t <= 0.0:
			snap_t = SNAP_INTERVAL
			_snapshot.rpc(main.make_snapshot())


# --- Connection events -------------------------------------------------------

func _on_peer_connected(_id: int) -> void:
	connected = true
	print("Net: player 2 joined")
	main.on_client_joined()


func _on_peer_disconnected(_id: int) -> void:
	connected = false
	print("Net: player 2 left")
	main.on_client_left()


func _on_connected() -> void:
	connected = true
	join_deadline = 0
	Engine.set_meta("duo_joined", true)
	print("Net: joined the host")
	join_finished.emit(true)


func _give_up() -> void:
	if mode != "client" or connected:
		return
	join_deadline = 0
	multiplayer.multiplayer_peer = null
	mode = "local"
	if Engine.has_meta("duo_joined"):
		print("Net: host not reachable, retrying")
		get_tree().create_timer(1.0).timeout.connect(get_tree().reload_current_scene)
	else:
		print("Net: no host found, playing locally")
		join_finished.emit(false)


func _on_server_gone() -> void:
	print("Net: host disconnected, reconnecting")
	connected = false
	multiplayer.multiplayer_peer = null
	get_tree().create_timer(1.0).timeout.connect(get_tree().reload_current_scene)


# --- Sending -----------------------------------------------------------------

## Host: broadcast a one-off event (sound, burst, banner, ...) to the client.
func event(kind: String, args: Array) -> void:
	if mode == "host" and connected:
		_event.rpc(kind, args)


## Client: report a local player's position and view every physics tick.
func send_state(pos: Vector3, yaw: float, pitch: float, index: int = 1) -> void:
	if mode == "client" and connected:
		_px_state.rpc_id(1, index, pos, yaw, pitch)


## Client: a local player did something the host must simulate (fire, dash, restart, join).
func send_action(action: String, args: Array, index: int = 1) -> void:
	if mode == "client" and connected:
		_px_action.rpc_id(1, index, action, args)


## Leave the current game and return both machines to the arcade picker.
func go_to_arcade() -> void:
	if has_meta("leaving"):
		return
	set_meta("leaving", true)
	if mode == "client" and connected:
		_request_arcade.rpc_id(1)
	elif mode == "host" and connected:
		_to_arcade.rpc()
	else:
		_to_arcade()


@rpc("any_peer", "call_remote", "reliable")
func _request_arcade() -> void:
	if mode == "host":
		_to_arcade.rpc()


@rpc("authority", "call_local", "reliable")
func _to_arcade() -> void:
	get_tree().paused = false
	# Let the message reach the other machine before this one drops the connection.
	get_tree().create_timer(0.4).timeout.connect(func() -> void:
		_close_old_peer()
		get_tree().change_scene_to_file("res://arcade.tscn"))


# --- RPCs (same node path /root/Main/Net on both machines) -------------------

@rpc("authority", "call_remote", "unreliable_ordered")
func _snapshot(s: Array) -> void:
	if mode == "client":
		main.apply_snapshot(s)


@rpc("authority", "call_remote", "reliable")
func _event(kind: String, args: Array) -> void:
	main.apply_event(kind, args)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _px_state(index: int, pos: Vector3, yaw: float, pitch: float) -> void:
	if mode == "host" and index > 0 and index < main.players.size():
		main.players[index].apply_remote_state(pos, yaw, pitch)


@rpc("any_peer", "call_remote", "reliable")
func _px_action(index: int, action: String, args: Array) -> void:
	if mode == "host" and index > 0 and index < main.players.size():
		main.on_p2_action(action, args, index)


## VR pause: a MENU button on the left wrist (tap it with the right hand, or point and pull the
## trigger), or the left menu / Y button where SteamVR passes them through. Runs even while paused.
## While paused, pulling the trigger anywhere else goes back to the arcade.
func _check_vr_menu() -> void:
	if main == null or main.players.is_empty() or not main.players[0].vr:
		return
	var hl: XRController3D = main.players[0].hand_l
	var hr = main.players[0].get("hand_r")
	var btn := _wrist_button(hl)
	var on_btn := false
	var trig := false
	if hr != null and btn != null:
		var to: Vector3 = btn.global_position - hr.global_position
		var fwd: Vector3 = -hr.global_basis.z
		var along := to.dot(fwd)
		on_btn = to.length() < 0.08 or (along > 0.0 and (to - fwd * along).length() < 0.07)
		trig = hr.get_float("trigger") > 0.7
		btn.modulate = Color(1.0, 0.9, 0.3) if on_btn else Color(0.55, 0.95, 1.0)
	var touching: bool = hr != null and btn != null and (btn.global_position - hr.global_position).length() < 0.08
	var down: bool = hl.is_button_pressed("menu_button") or hl.is_button_pressed("by_button") \
		or touching or (on_btn and trig)
	if down and not menu_was_down:
		print("Net: VR pause toggled")
		main.toggle_vr_pause()
	elif trig and not get_meta("trig_was", true) and not on_btn and get_tree().paused:
		go_to_arcade()
	menu_was_down = down
	set_meta("trig_was", trig)
	if btn != null:
		btn.text = "RESUME" if get_tree().paused else "MENU"


func _wrist_button(hl: XRController3D) -> Label3D:
	var btn := hl.get_node_or_null("WristMenu") as Label3D
	if btn == null:
		btn = Label3D.new()
		btn.name = "WristMenu"
		btn.font_size = 40
		btn.outline_size = 18
		btn.pixel_size = 0.0012
		btn.no_depth_test = true
		btn.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		btn.process_mode = Node.PROCESS_MODE_ALWAYS
		hl.add_child(btn)
		btn.position = Vector3(0.0, 0.07, 0.1)
	return btn
