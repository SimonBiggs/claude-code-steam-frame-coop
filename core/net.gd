extends Node
## Networked co-op over the home network. The Steam Frame (VR) hosts and simulates the game;
## the Steam Machine joins as player 2 (env DUO_JOIN=<host>), renders the shared world and drives its own player.
## Host -> client: 30 Hz snapshots plus reliable one-off events. Client -> host: player 2 state and actions.
##
## Engine additions (docs/engine/systems.md), all optional for a game:
## - Replicated STATE STORE for menu-heavy / turn-based games: the host calls state_set(key, value);
##   changed keys reach the client reliably (batched, at most 30 times a second) and a client that joins
##   late gets everything. Every machine emits state_changed(key, value), so UI code is the same on all.
## - request(slot, action, args): "a player wants to do X". Runs main.on_request() right away on the
##   host / in local play, or sends it to the host from the TV machine. Same code everywhere.
## - just_unpaused(): true briefly after the game was unpaused (or started), to ignore held buttons.
## - System messages (sys_send / add_sys_handler) used by core/party.gd; games normally don't need them.
## - Most callbacks on `main` are optional now (has_method checks); see the table in the docs.
##
## Bandwidth tips (the Frame's Wi-Fi is shared with the family): snapshots go out 30 times a second and
## are range-coder compressed, but keep them small: round floats you don't need precisely, leave out
## defaults and idle objects, pack bit flags into one int, send one-off things (sounds, bursts, text)
## as event()s, and slowly changing things (scores, menus, turn order, inventories) through the state
## store, which only sends what changed. Never put a value that changes every frame into the store.

signal join_finished(ok: bool)
## Every machine: a replicated state key changed (value null = the key was erased).
signal state_changed(key: String, value: Variant)
## Host: the TV machine connected / went away.
signal client_connected
signal client_disconnected

const DEFAULT_PORT := 7777
var PORT: int = int(OS.get_environment("DUO_PORT")) if OS.has_environment("DUO_PORT") else DEFAULT_PORT  # override for parallel tests
const SNAP_INTERVAL := 1.0 / 30.0
const JOIN_TIMEOUT := 5.0
## State store deltas are batched and sent at most this often (seconds).
const STATE_INTERVAL := 1.0 / 30.0
## Player slots: 0 is the VR / host player, 1..6 are TV players.
const MAX_SLOTS := 7

var main
var mode := "local"  # "local", "host" or "client"
var connected := false
var snap_t := 0.0
var join_deadline := 0  # Time.get_ticks_msec() when an unanswered join gives up (0 = not joining)
var _state := {}  # replicated key -> value (every machine)
var _state_dirty := {}  # host: keys changed since the last flush
var _state_t := 0.0
var _sys_handlers := {}  # kind -> Array of Callables
var _was_paused := false
var _since_unpause := 0.0  # game seconds since the last unpause (or start)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep the connection alive while the game is paused
	_since_unpause = 0.0  # starting counts as "just unpaused" (held buttons from the arcade)
	_was_paused = get_tree().paused


## Become the host (the headset, or DUO_HOST=1): listen for the TV machine.
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
	# Busy games' snapshots exceed one network packet (~1.4 KB); compress them (both ends must match).
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("Net: hosting on port %d" % PORT)


## Become the TV machine: join the host at `address` (join_finished tells how it went).
func join(address: String) -> void:
	_close_old_peer()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, PORT) != OK:
		join_finished.emit(false)
		return
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)  # must match the host
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
	_track_pause()
	if not get_tree().paused:
		_since_unpause += delta
	_check_vr_menu()
	_beacon(delta)
	if join_deadline > 0 and Time.get_ticks_msec() > join_deadline:
		_give_up()
	if mode == "host" and connected:
		snap_t -= delta
		if snap_t <= 0.0:
			snap_t = SNAP_INTERVAL
			if main != null and main.has_method("make_snapshot"):
				_snapshot.rpc(main.make_snapshot())
	_flush_state(delta)


# --- Connection events -------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	connected = true
	print("Net: player 2 joined")
	_state_dirty.clear()
	_state_full.rpc_id(id, _state)  # a late joiner gets the whole store
	if main != null and main.has_method("on_client_joined"):
		main.on_client_joined()
	client_connected.emit()


func _on_peer_disconnected(_id: int) -> void:
	connected = false
	print("Net: player 2 left")
	if main != null and main.has_method("on_client_left"):
		main.on_client_left()
	client_disconnected.emit()


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


## Any machine: player `slot` wants to do `action`. On the host and in local play the game's
## main.on_request(slot, action, args) runs right away (classic games: on_p2_action); on the TV
## machine it is sent to the host. Write game logic once, call it the same way everywhere.
func request(slot: int, action: String, args: Array = []) -> void:
	if mode == "client":
		if connected:
			_px_request.rpc_id(1, slot, action, args)
	else:
		_dispatch_request(slot, action, args)


func _dispatch_request(slot: int, action: String, args: Array) -> void:
	if main == null:
		return
	if action == "pause" and not _classic_game():
		# The shared pause menu sends "pause" [bool]; engine-style games get it handled here.
		var paused: bool = args.size() > 0 and bool(args[0])
		_set_paused(paused, slot, false)
		return
	if main.has_method("on_request"):
		main.on_request(slot, action, args)
	elif main.has_method("on_p2_action"):
		main.on_p2_action(action, args, slot)


## Host / local: pause or resume everyone (used by the VR wrist MENU when the game has no
## toggle_vr_pause()). Calls main.on_pause_changed(paused, by_slot) on both machines if it exists.
func toggle_pause(by_slot: int = 0) -> void:
	_set_paused(not get_tree().paused, by_slot, true)


func _set_paused(paused: bool, by_slot: int, from_vr: bool) -> void:
	get_tree().paused = paused
	_track_pause()
	if mode == "host" and connected:
		sys_send("_pause", [paused, by_slot])
	if not paused or from_vr:
		get_tree().call_group("pause_menu", "sync_remote_pause", paused)
	if main != null and main.has_method("on_pause_changed"):
		main.on_pause_changed(paused, by_slot)


## True for `window` seconds after the game was unpaused (or started): ignore buttons that are
## still held from the pause menu or the arcade. Works on every machine, in any callback.
func just_unpaused(window: float = 0.3) -> bool:
	_track_pause()
	if get_tree().paused:
		return false
	return _since_unpause < window


func _track_pause() -> void:
	if not is_inside_tree():
		return
	var p := get_tree().paused
	if _was_paused and not p:
		_since_unpause = 0.0
	_was_paused = p


# --- Replicated state store ------------------------------------------------------------

## Host / local: set a replicated value (null erases the key). Only changed keys are sent, in
## one reliable batch per frame (at most 30 Hz). Arrays and dictionaries are copied, so changing
## yours afterwards does nothing until you call state_set again. Emits state_changed here too.
func state_set(key: String, value: Variant) -> void:
	if mode == "client":
		if not has_meta("warned_state"):
			set_meta("warned_state", true)
			push_warning("Net: state_set('%s') on the TV machine is ignored; use request() and let the host set it" % key)
		return
	if value is Array or value is Dictionary:
		value = value.duplicate(true)
	if typeof(value) == TYPE_NIL:
		if not _state.has(key):
			return
		_state.erase(key)
	else:
		if _state.has(key) and typeof(_state[key]) == typeof(value) and _state[key] == value:
			return
		_state[key] = value
	_state_dirty[key] = true
	state_changed.emit(key, value)


## Any machine: read a replicated value (or `default` if it was never set / was erased).
func state_get(key: String, default: Variant = null) -> Variant:
	return _state.get(key, default)


## Any machine: true if the key is set.
func state_has(key: String) -> bool:
	return _state.has(key)


## Any machine: a copy of the whole store (for debugging or a late UI build).
func state_all() -> Dictionary:
	return _state.duplicate(true)


## Host / local: erase every key (e.g. a new match). Erasures replicate like changes.
func state_clear() -> void:
	for k in _state.keys():
		state_set(str(k), null)


func _flush_state(delta: float) -> void:
	if mode != "host" or _state_dirty.is_empty():
		return
	if not connected:
		_state_dirty.clear()  # a client that connects later gets everything in _state_full
		return
	_state_t -= delta
	if _state_t > 0.0:
		return
	_state_t = STATE_INTERVAL
	var changes := {}
	for k in _state_dirty:
		changes[k] = _state.get(k)  # null = erased
	_state_dirty.clear()
	_state_delta.rpc(changes)


@rpc("authority", "call_remote", "reliable")
func _state_delta(changes: Dictionary) -> void:
	for k in changes:
		var key := str(k)
		var v: Variant = changes[k]
		if typeof(v) == TYPE_NIL:
			_state.erase(key)
		else:
			_state[key] = v
		state_changed.emit(key, v)


@rpc("authority", "call_remote", "reliable")
func _state_full(all: Dictionary) -> void:
	for k in _state.keys():
		if not all.has(k):
			_state.erase(k)
			state_changed.emit(str(k), null)
	for k in all:
		var key := str(k)
		var v: Variant = all[k]
		var same: bool = _state.has(key) and typeof(_state[key]) == typeof(v) and _state[key] == v
		_state[key] = v
		if not same:
			state_changed.emit(key, v)


# --- System messages (engine modules such as core/party.gd) ----------------------------

## Register a handler for engine messages of one kind: handler(args: Array). Kept per kind; freed
## nodes' handlers are dropped automatically. Re-registering the same Callable is a no-op.
func add_sys_handler(kind: String, handler: Callable) -> void:
	var list: Array = _sys_handlers.get(kind, [])
	if not list.has(handler):
		list.append(handler)
	_sys_handlers[kind] = list


## Send an engine message to the other machine (host -> client or client -> host), reliably.
func sys_send(kind: String, args: Array) -> void:
	if not connected:
		return
	if mode == "host":
		_sys_down.rpc(kind, args)
	elif mode == "client":
		_sys_up.rpc_id(1, kind, args)


@rpc("any_peer", "call_remote", "reliable")
func _sys_up(kind: String, args: Array) -> void:
	if mode == "host":
		_sys_dispatch(kind, args)


@rpc("authority", "call_remote", "reliable")
func _sys_down(kind: String, args: Array) -> void:
	if mode != "client":
		return
	if kind == "_pause":
		var paused: bool = bool(args[0])
		get_tree().paused = paused
		_track_pause()
		get_tree().call_group("pause_menu", "sync_remote_pause", paused)
		if main != null and main.has_method("on_pause_changed"):
			main.on_pause_changed(paused, int(args[1]))
		return
	_sys_dispatch(kind, args)


func _sys_dispatch(kind: String, args: Array) -> void:
	var list: Array = _sys_handlers.get(kind, [])
	for h in list.duplicate():
		var c: Callable = h
		if c.is_valid():
			c.call(args)
		else:
			list.erase(h)


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
	if mode == "client" and main != null and main.has_method("apply_snapshot"):
		main.apply_snapshot(s)


@rpc("authority", "call_remote", "reliable")
func _event(kind: String, args: Array) -> void:
	if main != null and main.has_method("apply_event"):
		main.apply_event(kind, args)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _px_state(index: int, pos: Vector3, yaw: float, pitch: float) -> void:
	if mode != "host" or main == null or index <= 0 or index >= MAX_SLOTS:
		return
	if _classic_game():
		if index < main.players.size():
			main.players[index].apply_remote_state(pos, yaw, pitch)
	elif main.has_method("on_remote_state"):
		main.on_remote_state(index, pos, yaw, pitch)


@rpc("any_peer", "call_remote", "reliable")
func _px_action(index: int, action: String, args: Array) -> void:
	if mode != "host" or main == null or index <= 0 or index >= MAX_SLOTS:
		return
	if _classic_game():
		# Classic games (on_p2_action): the host must have created player index already.
		if index < main.players.size():
			main.on_p2_action(action, args, index)
		return
	_dispatch_request(index, action, args)


## Client -> host: net.request() from the TV machine.
@rpc("any_peer", "call_remote", "reliable")
func _px_request(slot: int, action: String, args: Array) -> void:
	if mode == "host" and slot > 0 and slot < MAX_SLOTS:
		_dispatch_request(slot, action, args)


## A game written for the classic contract (players array + on_p2_action), like the first 17 games.
func _classic_game() -> bool:
	return main.has_method("on_p2_action") and "players" in main


## VR pause: a MENU button on the left wrist (tap it with the right hand, or point and pull the
## trigger), or the left menu / Y button where SteamVR passes them through. Runs even while paused.
## While paused, pulling the trigger anywhere else goes back to the arcade.
func _check_vr_menu() -> void:
	if main == null:
		return
	var hl: XRController3D = null
	var hr = null
	var rig = main.get("vr_rig")  # core/vr_rig.gd
	if rig != null and is_instance_valid(rig) and rig.is_inside_tree() and rig.get("hand_l") != null:
		hl = rig.hand_l
		hr = rig.hand_r
	elif "players" in main and not main.players.is_empty() and main.players[0].get("vr") == true:
		hl = main.players[0].hand_l
		hr = main.players[0].get("hand_r")
	if hl == null or not is_instance_valid(hl):
		return
	var btn := _wrist_button(hl)
	var ws := 1.0  # games like Giant's Table scale the world (XROrigin3D.world_scale)
	if hl.get_parent() is XROrigin3D:
		ws = (hl.get_parent() as XROrigin3D).world_scale
	if btn != null:
		btn.position = Vector3(-0.08, 0.03, 0.1) * ws  # beside the wrist, clear of the games' wrist displays
		btn.pixel_size = 0.0012 * ws
	var on_btn := false
	var trig := false
	if hr != null and btn != null:
		var to: Vector3 = btn.global_position - hr.global_position
		var fwd: Vector3 = -hr.global_basis.z
		var along := to.dot(fwd)
		on_btn = to.length() < 0.08 * ws or (along > 0.0 and (to - fwd * along).length() < 0.07 * ws)
		trig = (rig.trigger_value() if rig != null and hl == rig.get("hand_l") else hr.get_float("trigger")) > 0.7
		btn.modulate = Color(1.0, 0.9, 0.3) if on_btn else Color(0.55, 0.95, 1.0)
	var touching: bool = hr != null and btn != null and (btn.global_position - hr.global_position).length() < 0.08 * ws
	# A touch has to be held briefly, so brushing past the wrist while busy doesn't pause.
	if touching:
		set_meta("touch_t", float(get_meta("touch_t", 0.0)) + get_process_delta_time())
	else:
		set_meta("touch_t", 0.0)
	var held_touch: bool = float(get_meta("touch_t", 0.0)) > 0.35
	var down: bool = hl.is_button_pressed("menu_button") or hl.is_button_pressed("by_button") \
		or held_touch or (on_btn and trig)
	if down and not menu_was_down:
		print("Net: VR pause toggled")
		if main.has_method("toggle_vr_pause"):
			main.toggle_vr_pause()
		else:
			toggle_pause(0)
	# Leaving needs the trigger HELD for 1.5 s while paused, so a stray trigger pull doesn't quit.
	if trig and not on_btn and get_tree().paused:
		set_meta("leave_t", float(get_meta("leave_t", 0.0)) + get_process_delta_time())
		if float(get_meta("leave_t", 0.0)) > 1.5:
			go_to_arcade()
	else:
		set_meta("leave_t", 0.0)
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


## Host: once a second, tell the home network which game is running (UDP broadcast on port + 2),
## so a TV still sitting in the arcade lobby can jump straight into it.
func _beacon(delta: float) -> void:
	if mode != "host":
		return
	set_meta("beacon_t", float(get_meta("beacon_t", 0.0)) - delta)
	if float(get_meta("beacon_t", 0.0)) > 0.0:
		return
	set_meta("beacon_t", 1.0)
	if not has_meta("beacon"):
		var udp := PacketPeerUDP.new()
		udp.set_broadcast_enabled(true)
		udp.set_dest_address("255.255.255.255", PORT + 2)
		set_meta("beacon", udp)
	var u: PacketPeerUDP = get_meta("beacon")
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path != "":
		u.put_packet(("ARCADE_GAME " + scene.scene_file_path).to_utf8_buffer())
