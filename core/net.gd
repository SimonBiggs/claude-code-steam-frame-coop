extends Node
## Networked co-op over the home network. One machine hosts and simulates the game (usually the Steam Frame
## with the VR player); other machines join (env DUO_JOIN=<host>, or DUO_JOIN=auto to find one), render the
## shared world and drive their own players.
##
## MANY MACHINES (2026-10-24): any number of TV-style machines can join (the TV, Steam Decks...), up to
## `max_machines` (env DUO_MAX_MACHINES, default 32: no practical limit; the game's free seats are). Each says what it is (env DUO_MACHINE_KIND: "tv",
## "deck", ...; machine_kind_of(peer)), so a game can treat e.g. Deck players differently. A game opts in
## with `var multi_machine := true` on main; until then it keeps the old contract (ONE TV machine: any more
## are told the game is full and play on their own). Per-machine signals: machine_joined / machine_left,
## main.on_machine_joined(peer, kind) / on_machine_left(peer). core/party.gd tracks which machine owns
## which seat. A host doesn't need VR: host(false) runs a "flat host" (has_vr false; slot 0 is a normal
## pad/keyboard player), so TV + Decks, or just two Decks, can play together (games opt in, see above).
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
## Host: a TV machine connected / went away (every machine; old games treat it as "the TV").
signal client_connected
signal client_disconnected
## Host: a machine said hello (peer id, its kind: "tv", "deck", ...) / went away.
signal machine_joined(peer: int, kind: String)
signal machine_left(peer: int)

const DEFAULT_PORT := 7777
var PORT: int = int(OS.get_environment("DUO_PORT")) if OS.has_environment("DUO_PORT") else DEFAULT_PORT  # override for parallel tests
const SNAP_INTERVAL := 1.0 / 30.0
const JOIN_TIMEOUT := 5.0
## DUO_JOIN=auto: how long to listen for a host's beacon (it sends one a second).
const AUTO_FIND_SECONDS := 1.6
## State store deltas are batched and sent at most this often (seconds).
const STATE_INTERVAL := 1.0 / 30.0
## Player slots: 0 is the VR / host player, 1..6 are TV players.
const MAX_SLOTS := 7

var main
var mode := "local"  # "local", "host" or "client"
var connected := false  # host: at least one machine joined; client: joined the host
## This machine's kind, sent to the host when joining ("tv", "deck", ...).
var machine_kind: String = preload("res://core/machine.gd").kind()  # tv / deck / frame (core/machine.gd)
## Host: how many machines may join a game that supports several (multi_machine on main).
var max_machines: int = int(OS.get_environment("DUO_MAX_MACHINES")) if OS.has_environment("DUO_MAX_MACHINES") else 32  # ENet allows 4095; seats are the real limit
## Host: whether the host has a VR player (false: a flat host, see host()).
var has_vr := true
## Host: peer id -> {"kind": String} for every joined machine.
var machines := {}
## While a sys message handler runs on the host: the peer that sent it (0 = this machine).
var sys_sender := 0
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
	preload("res://core/ui_kit.gd").ensure_pad_ui_actions()  # every focus-driven menu works with a pad
	_since_unpause = 0.0  # starting counts as "just unpaused" (held buttons from the arcade)
	_was_paused = get_tree().paused


## Become the host: listen for TV machines. vr false = a flat host without a VR player (TV / Deck hosting).
func host(vr: bool = true) -> void:
	mode = "host"
	has_vr = vr and not OS.has_environment("DUO_FLAT_HOST")  # the arcade picked this machine as a flat host
	_try_listen()


## True when main opted in to several TV machines (and to flat hosts): `var multi_machine := true`.
func multi_machine_ok() -> bool:
	return main != null and is_instance_valid(main) and main.get("multi_machine") == true


## Host: how many machines this game takes now (1 for old one-TV games).
func machine_limit() -> int:
	return maxi(1, max_machines) if multi_machine_ok() else 1


## Inside an RPC handler on the host (on_p2_action, on_request, on_remote_state, sys handlers): the peer
## id of the machine that sent it (0 = this machine).
func sender_peer() -> int:
	return sys_sender if sys_sender != 0 else multiplayer.get_remote_sender_id()


## Host: how many machines are connected (client: 1 when joined).
func peer_count() -> int:
	return machines.size() if mode == "host" else (1 if connected else 0)


## This machine's peer id (1 on the host, 0 when not networked).
func my_peer_id() -> int:
	return multiplayer.get_unique_id() if mode != "local" and multiplayer.multiplayer_peer != null else 0


## Host: a one-off event for one machine only (e.g. a re-sync for a machine that just joined).
func event_to(peer: int, kind: String, args: Array) -> void:
	if mode == "host" and peer in multiplayer.get_peers():
		_event.rpc_id(peer, kind, args)


## Host: a one-off event for every machine except one (e.g. relaying a sound a machine already played).
func event_except(peer: int, kind: String, args: Array) -> void:
	if mode != "host":
		return
	for p in multiplayer.get_peers():
		if p != peer:
			_event.rpc_id(p, kind, args)


## Host: a joined machine's kind ("tv", "deck", ...; "" if unknown).
func machine_kind_of(peer: int) -> String:
	return str(machines.get(peer, {}).get("kind", ""))


## Keeps trying while the port is busy (e.g. an older copy of the game is still shutting down).
func _try_listen() -> void:
	_close_old_peer()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, maxi(1, max_machines)) != OK:
		print("Net: port %d busy, retrying" % PORT)
		get_tree().create_timer(1.0).timeout.connect(_try_listen)
		return
	# Busy games' snapshots exceed one network packet (~1.4 KB); compress them (both ends must match).
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("Net: hosting on port %d" % PORT)


## Become a TV machine: join the host at `address` (join_finished tells how it went). "auto" listens for a
## host's beacon on the home network for a moment and joins whoever is hosting (no host: join_finished(false)).
func join(address: String) -> void:
	var here := get_tree().current_scene.scene_file_path if get_tree().current_scene else ""
	if Engine.get_meta("duo_full", "-") == here:
		print("Net: the host's game was full, staying on this machine")
		join_finished.emit.call_deferred(false)  # (the arcade lobby clears duo_full: next game, try again)
		return
	if address == "auto":
		_join_auto()
		return
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


func _join_auto() -> void:
	var udp := PacketPeerUDP.new()
	if udp.bind(PORT + 2) != OK:
		print("Net: can't listen for hosts (port %d busy)" % (PORT + 2))
		join_finished.emit.call_deferred(false)
		return
	var until := Time.get_ticks_msec() + int(AUTO_FIND_SECONDS * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		while udp.get_available_packet_count() > 0:
			var msg := udp.get_packet().get_string_from_utf8()
			var ip := udp.get_packet_ip()
			if msg.begins_with("ARCADE_GAME ") and ip != "":
				udp.close()
				print("Net: found a host at %s" % ip)
				join(ip)
				return
	udp.close()
	print("Net: no host on the network")
	join_finished.emit(false)


## The multiplayer peer belongs to the SceneTree and survives scene reloads; close it so the port is freed.
func _close_old_peer() -> void:
	var old := multiplayer.multiplayer_peer
	if old != null and not old is OfflineMultiplayerPeer:
		old.close()
	multiplayer.multiplayer_peer = null


func _exit_tree() -> void:
	if has_meta("follow_udp") and get_meta("follow_udp") != null:  # _follow_headset's beacon listener
		(get_meta("follow_udp") as PacketPeerUDP).close()
	_close_old_peer()


var menu_was_down := false


func _process(delta: float) -> void:
	if not has_meta("pad_ui"):  # (also in _ready) so a hot-reloaded net.gd adds pad A/B too
		set_meta("pad_ui", true)
		preload("res://core/ui_kit.gd").ensure_pad_ui_actions()
	_ensure_caption()
	_follow_headset()
	_ensure_fullscreen()
	_hide_tv_cursor()
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
	if mode != "host":
		return
	if machines.size() >= machine_limit():
		# Full (or an old one-TV game): tell it, so it plays on its own instead of waiting, then drop it.
		print("Net: machine %d turned away (%d/%d)" % [id, machines.size(), machine_limit()])
		_sys_down.rpc_id(id, "_full", [machine_limit()])
		# Drop it once that message is out (not on a timer: meanwhile broadcasts to it would error).
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			var pp := (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(id)
			if pp:
				pp.peer_disconnect_later()
		return
	machines[id] = {"kind": "tv"}
	connected = true
	print("Net: machine %d joined (%d now)" % [id, machines.size()])
	_state_dirty.clear()
	_state_full.rpc_id(id, _state)  # a late joiner gets the whole store
	if main != null and main.has_method("on_client_joined"):
		main.on_client_joined()
	client_connected.emit()


func _on_peer_disconnected(id: int) -> void:
	if not machines.has(id):
		return  # one we turned away
	machines.erase(id)
	connected = not machines.is_empty()
	print("Net: machine %d left (%d now)" % [id, machines.size()])
	if main != null and main.has_method("on_machine_left"):
		main.on_machine_left(id)
	machine_left.emit(id)
	# Old one-TV games: "the TV left". Multi-machine games get it only when the last machine leaves.
	if not multi_machine_ok() or machines.is_empty():
		if main != null and main.has_method("on_client_left"):
			main.on_client_left()
		client_disconnected.emit()


func _on_connected() -> void:
	connected = true
	join_deadline = 0
	Engine.set_meta("duo_joined", true)
	print("Net: joined the host as a %s" % machine_kind)
	_sys_up.rpc_id(1, "_hello", [machine_kind])
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
	if mode != "client":
		return  # we left on purpose (e.g. the host's game was full)
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


## Host: send an engine message to one machine only.
func sys_send_to(peer: int, kind: String, args: Array) -> void:
	if mode == "host" and peer in multiplayer.get_peers():
		_sys_down.rpc_id(peer, kind, args)


## Send an engine message to the other machine(s) (host -> every client, or client -> host), reliably.
func sys_send(kind: String, args: Array) -> void:
	if not connected:
		return
	if mode == "host":
		_sys_down.rpc(kind, args)
	elif mode == "client":
		_sys_up.rpc_id(1, kind, args)


@rpc("any_peer", "call_remote", "reliable")
func _sys_up(kind: String, args: Array) -> void:
	if mode != "host":
		return
	var from := multiplayer.get_remote_sender_id()
	if not machines.has(from):
		return  # turned away
	if kind == "_hello":
		machines[from] = {"kind": str(args[0]) if args.size() > 0 else "tv"}
		print("Net: machine %d is a %s" % [from, machines[from].kind])
		if main != null and main.has_method("on_machine_joined"):
			main.on_machine_joined(from, machines[from].kind)
		machine_joined.emit(from, machines[from].kind)
		return
	sys_sender = from
	_sys_dispatch(kind, args)
	sys_sender = 0


@rpc("authority", "call_remote", "reliable")
func _sys_down(kind: String, args: Array) -> void:
	if mode != "client":
		return
	if kind == "_full":
		# The host's game takes no more machines: play on our own (no reconnect loop for this game).
		print("Net: the host's game is full (%d machine(s)), playing on this machine" % int(args[0]))
		Engine.set_meta("duo_full", get_tree().current_scene.scene_file_path if get_tree().current_scene else "")
		join_deadline = 0
		connected = false
		multiplayer.multiplayer_peer = null
		mode = "local"
		join_finished.emit(false)
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
		btn.position = Vector3(-0.15, 0.02, 0.12) * ws  # well out beside the wrist: games put their own displays on the glove (Party Board coins, Duo Arena HP)
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
	var paused := get_tree().paused
	# While paused, an ARCADE button appears above RESUME: touch it, or point at it and pull the
	# trigger, to go back to the arcade (Simon: "why can't I just press the menu's buttons?").
	var abtn := _wrist_arcade_button(hl)
	abtn.visible = paused
	if paused and hr != null and btn != null:
		abtn.position = btn.position + Vector3(0.0, 0.055, 0.0) * ws
		abtn.pixel_size = btn.pixel_size
		var to2: Vector3 = abtn.global_position - hr.global_position
		var fwd2: Vector3 = -hr.global_basis.z
		var along2 := to2.dot(fwd2)
		var off2 := (to2 - fwd2 * along2).length()
		var on_arc := to2.length() < 0.07 * ws or (along2 > 0.0 and off2 < 0.06 * ws)
		if on_arc and on_btn:
			# Pointing between the two: the one closer to the ray wins.
			var to1: Vector3 = btn.global_position - hr.global_position
			var off1 := (to1 - fwd2 * to1.dot(fwd2)).length()
			if off1 < off2:
				on_arc = false
			else:
				on_btn = false
		abtn.modulate = Color(1.0, 0.9, 0.3) if on_arc else Color(1.0, 0.7, 0.55)
		btn.modulate = Color(1.0, 0.9, 0.3) if on_btn else Color(0.55, 0.95, 1.0)
		if to2.length() < 0.07 * ws:
			set_meta("arc_touch_t", float(get_meta("arc_touch_t", 0.0)) + get_process_delta_time())
		else:
			set_meta("arc_touch_t", 0.0)
		if (on_arc and trig and not bool(get_meta("trig_was", false))) or float(get_meta("arc_touch_t", 0.0)) > 0.3:
			print("Net: VR arcade button")
			go_to_arcade()
			return
	# While paused, a trigger pull on the button resumes only when released quickly, so HOLDING the
	# trigger (even while pointing near the wrist, e.g. with a fishing rod) always goes to the arcade.
	var tap_resume := false
	# Only a pull that STARTED while paused counts: the pull that paused (still held) must not resume
	# the moment it is released.
	if paused and on_btn and trig and (float(get_meta("btn_hold", 0.0)) > 0.0 or not bool(get_meta("trig_was", false))):
		set_meta("btn_hold", float(get_meta("btn_hold", 0.0)) + get_process_delta_time())
	elif float(get_meta("btn_hold", 0.0)) > 0.0:
		tap_resume = float(get_meta("btn_hold", 0.0)) < 0.5 and not trig
		set_meta("btn_hold", 0.0)
	var down: bool = hl.is_button_pressed("menu_button") or hl.is_button_pressed("by_button") \
		or held_touch or (on_btn and trig and not paused) or tap_resume
	if has_meta("leaving"):
		down = false  # on the way to the arcade: a late trigger release must not pause again
	if down and not menu_was_down:
		print("Net: VR pause toggled")
		if main.has_method("toggle_vr_pause"):
			main.toggle_vr_pause()
		else:
			toggle_pause(0)
	# Leaving needs the trigger HELD for 1.5 s while paused, so a stray trigger pull doesn't quit.
	if trig and paused:
		set_meta("leave_t", float(get_meta("leave_t", 0.0)) + get_process_delta_time())
		if float(get_meta("leave_t", 0.0)) > 1.5:
			go_to_arcade()
	else:
		set_meta("leave_t", 0.0)
	menu_was_down = down
	set_meta("trig_was", trig)
	if btn != null:
		btn.text = "RESUME" if get_tree().paused else "MENU"


func _wrist_arcade_button(hl: XRController3D) -> Label3D:
	var b := hl.get_node_or_null("WristArcade") as Label3D
	if b == null:
		b = Label3D.new()
		b.name = "WristArcade"
		b.text = "ARCADE"
		b.font_size = 40
		b.outline_size = 18
		b.pixel_size = 0.0012
		b.process_mode = Node.PROCESS_MODE_ALWAYS
		b.visible = false
		hl.add_child(b)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		_face_camera(b, cam)
	return b


func _wrist_button(hl: XRController3D) -> Label3D:
	var btn := hl.get_node_or_null("WristMenu") as Label3D
	if btn == null:
		btn = Label3D.new()
		btn.name = "WristMenu"
		btn.font_size = 40
		btn.outline_size = 18
		btn.pixel_size = 0.0012
		btn.no_depth_test = false
		btn.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		btn.process_mode = Node.PROCESS_MODE_ALWAYS
		hl.add_child(btn)
		btn.position = Vector3(0.0, 0.07, 0.1)
	btn.no_depth_test = false  # (re)applied so buttons made before this fix also let the hand pass in front
	# No billboard in VR: each eye would see it turned differently (cross-eyed, Abigail/Simon).
	# Turn it towards the head once per frame instead; a Label3D reads from its +Z side.
	btn.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		_face_camera(btn, cam)
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


## "Claude:" captions from frame-say (addons/gdev/caption.gd, a dev tool that may be missing).
## Added once to the root so it survives game changes; created here because net.gd hot-reloads,
## so it switches on in a running game without a restart.
func _ensure_caption() -> void:
	var root := get_tree().root
	if not root.has_meta("vr_text_guard"):
		var g: Node = (load("res://core/vr_text_guard.gd") as GDScript).new()
		g.name = "VrTextGuard"
		root.set_meta("vr_text_guard", g)
		root.add_child.call_deferred(g)
	if root.has_meta("claude_caption") or not ResourceLoader.exists("res://addons/gdev/caption.gd"):
		return
	var c: Node = (load("res://addons/gdev/caption.gd") as GDScript).new()
	c.name = "ClaudeCaption"
	root.set_meta("claude_caption", c)
	root.add_child.call_deferred(c)


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


## TV machine playing on its own (it couldn't reach the headset when this game started): listen for the
## headset's "ARCADE_GAME <scene>" beacon and switch to that game as a client, so the TV and the
## headset never end up in different games (it happened twice on 2026-10-04).
func _follow_headset() -> void:
	if mode != "local" or not OS.has_environment("DUO_JOIN") or has_meta("following"):
		return
	if not has_meta("follow_udp"):
		var udp := PacketPeerUDP.new()
		set_meta("follow_udp", udp if udp.bind(PORT + 2) == OK else null)
	var u = get_meta("follow_udp")
	if u == null:
		return
	var udp: PacketPeerUDP = u
	while udp.get_available_packet_count() > 0:
		var msg := udp.get_packet().get_string_from_utf8()
		if not msg.begins_with("ARCADE_GAME "):
			continue
		var scene := msg.substr(12)
		if Engine.get_meta("duo_full", "-") == scene:
			continue  # that game turned us away as full: keep playing here
		print("Net: the headset is playing %s; joining it" % scene)
		set_meta("following", true)
		udp.close()
		get_tree().paused = false
		get_tree().change_scene_to_file.call_deferred(scene)
		return


## Turn a wrist button to face the head. Looking straight down at the wrist made the direction parallel to
## UP: looking_at gave a NaN basis, the button vanished, and reusing its (now NaN) scale kept it broken.
static func _face_camera(n: Node3D, cam: Camera3D) -> void:
	var d := n.global_position - cam.global_position
	if d.length() < 0.01:
		return
	var sc := n.global_basis.get_scale()
	if not sc.is_finite() or sc.length() < 0.001:
		sc = Vector3.ONE
	n.global_basis = preload("res://core/ui_kit.gd").face(d, Vector3.UP, cam.global_basis.y).scaled(sc)

