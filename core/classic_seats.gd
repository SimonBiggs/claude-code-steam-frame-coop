extends RefCounted
## Many machines for CLASSIC games (a `players` array + on_p2_action, like duo_arena): ONE home for "which
## machine drives which seat", so no game carries its own copy (docs/MULTI_MACHINE.md, "Classic games").
##
##   const ClassicSeats := preload("res://core/classic_seats.gd")
##   var seats: ClassicSeats        # core/net.gd finds it here (main.seats) to drop other machines' state/actions
##   seats = ClassicSeats.new(self, {
##       "no_keys": PlayerScript.NO_KEYS,       # key_set value meaning "no keyboard keys" (default -1)
##       "free_actions": ["pause", "restart"],  # actions any machine may send for any seat (default ["pause"])
##       "full": func(): _show_center("All seats are taken!", 1.5, false),
##   })
##
## Host
## - Seat owners live in the state store (`owners`: {seat index: peer id}), so every machine knows them.
## - on_p2_action starts with `index = seats.host_action(action, args, index)` / `if index < 0: return`:
##   "join" is granted to the sending machine (net.sender_peer()), or redirected to the first free seat
##   (event_to(peer, "seat", [asked, got]); got -1 = all full); "leave" frees the seat; any other action
##   for a seat the sender doesn't own is dropped. core/net.gd already drops state / actions for seats the
##   sender doesn't own (remote_ok), so player scripts need no owner checks of their own.
## - on_machine_left(peer): `seats.machine_left(peer)` frees and deactivates ONLY that machine's seats.
##   on_client_left() (the LAST machine left): `seats.all_left()`.
## - First machine only: `if not seats.first_machine(): return` in on_client_joined, so a second machine
##   doesn't restart the round for everyone.
## TV machine (client)
## - Seats other machines own are ghosts here (mirrored from snapshots, never driven): `seats.sync()` every
##   frame moves our controls off a seat someone else took (to a free seat) and frees seats nobody owns.
## - `seats.request_joins(delta)` asks the host for every local seat marked want_join (once a second) until
##   `seats.joined(p)`: active AND granted to this machine. Never clear want_join just because the seat is
##   active: the host may still hand out another seat ("seat" event -> apply_event -> seats.handle_event).
## - `seats.free_index(skip)`: next free local seat, skipping seats other machines own.
## Local play
## - `seats.deck_alone()` / `seats.deck_solo(slot)`: a Steam Deck on its own (DUO_MACHINE_KIND=deck) is ONE
##   full-screen player on the first pad (no keyboard seat); more controllers drop in as usual.
##
## Game-specific bits are options (Callables; all optional, defaults use the usual player fields
## index / active / ghost / joy / key_set / mouse_look / pad_lost_t and the main methods named below):
##   is_local(p) -> bool      default main._is_local(p) / main.is_local(p) / p.is_local()
##   player(i) -> player      default main.players[i] (null past the end); e.g. _ensure_player
##   seat_limit() -> int      seats free_index() looks at (1..limit-1); default players.size()
##   keys(p) -> key set       the keyboard set p really plays with (default p.key_set)
##   seat_free(p) -> bool     "nobody uses this local seat"; default: not active / joining / holding a pad
##   ghost(p, on)             extra work when a seat becomes a ghost (on) or ours again (off)
##   moved(from, to)          after a seat's controls moved to another seat (client)
##   full()                   the host had no free seat for us
##   deactivate(p)            a machine's seat goes away (default: p.set_active(false) if active)
##   save() / layout() / ensure_view(p)   default main._save_party / _layout_views / _ensure_view
##   max_seats (int)          seats 1..max_seats-1 can be owned (default 7)
##   index_in_args (Array)    actions whose seat is args[0] (sent as P2 before the seat exists; default ["join"])

const WANT := "want_join"

var main: Node
var max_seats := 7
var no_keys: Variant = -1
var free_actions: Array = ["pause"]
var index_in_args: Array = ["join"]
var _cb := {}


func _init(game: Node, opts: Dictionary = {}) -> void:
	main = game
	max_seats = int(opts.get("max_seats", max_seats))
	no_keys = opts.get("no_keys", no_keys)
	free_actions = opts.get("free_actions", free_actions)
	index_in_args = opts.get("index_in_args", index_in_args)
	for k in opts:
		if opts[k] is Callable:
			_cb[k] = opts[k]


func _net() -> Node:
	return main.get("net") if main != null and is_instance_valid(main) else null


func _mode() -> String:
	var n := _net()
	return n.mode if n != null else "local"


func _call(name: String, args: Array = [], fallback: Variant = null) -> Variant:
	if _cb.has(name):
		return (_cb[name] as Callable).callv(args)
	return fallback


func _main_call(method: String, args: Array = []) -> Variant:
	return main.callv(method, args) if main.has_method(method) else null


# --- Who owns what (every machine) ------------------------------------------------------------------

## {seat index: peer id} for every seat a machine has claimed (set on the host, replicated everywhere).
func owners() -> Dictionary:
	var n := _net()
	return n.state_get("owners", {}) if n != null else {}


## TV machine: a seat another machine drives (a ghost here). Always false on the host / in local play.
func foreign(i: int) -> bool:
	if _mode() != "client":
		return false
	var o := owners()
	return o.has(i) and int(o[i]) != _net().my_peer_id()


## This machine drives seat i (always true on the host / in local play).
func mine(i: int) -> bool:
	return _mode() != "client" or int(owners().get(i, -1)) == _net().my_peer_id()


## A local seat's join went through: it is playing AND the host gave it to this machine.
func joined(p) -> bool:
	return p.active and mine(p.index)


## Host: true for the first (only) machine; a later machine must not restart the round for everyone.
func first_machine() -> bool:
	var n := _net()
	return n == null or n.peer_count() <= 1


func is_local(p) -> bool:
	if _cb.has("is_local"):
		return _cb["is_local"].call(p)
	if main.has_method("_is_local"):
		return main._is_local(p)
	if main.has_method("is_local"):
		return main.is_local(p)
	return p.is_local()


func player(i: int):
	if _cb.has("player"):
		return _cb["player"].call(i)
	var ps: Array = main.players
	return ps[i] if i >= 0 and i < ps.size() else null


# --- Host --------------------------------------------------------------------------------------------

## Host: may machine `peer` drive seat i? (peer 0 = this machine / a test call; default: the RPC sender)
func owner_ok(i: int, peer: int = -1) -> bool:
	var n := _net()
	if n == null or n.mode != "host":
		return true
	if peer < 0:
		peer = n.sender_peer()
	return peer == 0 or int(owners().get(i, -1)) == peer


## Host, from core/net.gd for every TV state packet (action "") / action: drop it unless the sender owns
## the seat, or the action is one any machine may send ("join", free_actions).
func remote_ok(index: int, action: String = "", args: Array = []) -> bool:
	if action == "join" or action in free_actions:
		return true
	if action in index_in_args and args.size() > 0:
		index = int(args[0])
	return owner_ok(index)


## Host: start of on_p2_action. Returns the seat the action is for, or -1 to ignore it. "join" is granted
## (or redirected to a free seat, telling the sender with a "seat" event); "leave" frees the seat.
func host_action(action: String, args: Array, index: int) -> int:
	if action in index_in_args and args.size() > 0:
		index = int(args[0])
	if action in free_actions:
		return index if index >= 0 and index < max_seats else -1
	if index <= 0 or index >= max_seats:
		return -1
	if action == "join":
		var peer: int = _net().sender_peer() if _net() != null else 0
		var got := grant(index, peer)
		if got != index:
			_net().event_to(peer, "seat", [index, got])
		return got
	if not owner_ok(index):
		return -1
	if action == "leave":
		release(index)
	return index


## Host: give seat i to machine `peer`, or the first free seat if another machine has it (-1: all full).
func grant(i: int, peer: int) -> int:
	if peer == 0:
		return i
	var o: Dictionary = owners().duplicate()
	if int(o.get(i, peer)) != peer:
		i = -1
		for j in range(1, max_seats):
			if not o.has(j):
				i = j
				break
		if i < 0:
			return -1
	o[i] = peer
	_net().state_set("owners", o)
	return i


## Host: seat i has nobody now.
func release(i: int) -> void:
	var n := _net()
	if n == null or n.mode != "host":
		return
	var o: Dictionary = owners().duplicate()
	if o.erase(i):
		n.state_set("owners", o)


## Host: machine `peer` left: free and deactivate only its seats. Returns them, lowest first.
func machine_left(peer: int) -> Array:
	var o: Dictionary = owners().duplicate()
	var freed: Array = []
	for k in o.keys():
		if int(o[k]) == peer:
			o.erase(k)
			freed.append(int(k))
	freed.sort()
	_net().state_set("owners", o)
	for i in freed:
		var p = player(i)
		if p != null:
			_deactivate(p)
	return freed


## Host: the LAST machine left: nobody owns a seat; every TV seat sits out until a machine is back.
func all_left() -> void:
	_net().state_set("owners", {})
	for p in main.players:
		if p.index > 0:
			_deactivate(p)


func _deactivate(p) -> void:
	if _cb.has("deactivate"):
		_cb["deactivate"].call(p)
	elif p.active:
		p.set_active(false)


# --- TV machine ----------------------------------------------------------------------------------------

## Client, every frame: seats other machines took become ghosts (our controls move to a free seat); seats
## nobody else owns any more are ours to drive again.
func sync() -> void:
	if _mode() != "client":
		return
	var changed := false
	for p in main.players:
		if p.index == 0:
			continue
		var f := foreign(p.index)
		if f and not p.ghost:
			if _has_controls(p):
				var to_i := free_index(p.index)
				if to_i >= 0:
					var to = player(to_i)
					move_input(p, to)
					_call("moved", [p, to])
			set_ghost(p, true)
			changed = true
		elif not f and p.ghost:
			set_ghost(p, false)
			changed = true
	if changed:
		_refresh()


## Client: apply_event hook; true when it was the host's "seat" answer (it gave another seat).
func handle_event(kind: String, args: Array) -> bool:
	if kind != "seat":
		return false
	_on_seat_moved(int(args[0]), int(args[1]))
	return true


## Client: the host gave seat `got` instead of `asked` (another machine has it; -1 = all full).
func _on_seat_moved(asked: int, got: int) -> void:
	var from = player(asked) if asked > 0 else null
	if from == null:
		return
	if got < 0:
		from.remove_meta(WANT)
		_call("full")
		return
	var to = player(got)
	if to == null:
		return
	if to.ghost:
		set_ghost(to, false)
	move_input(from, to)
	set_ghost(from, true)
	_call("moved", [from, to])
	print("Seat P%d is taken: playing as P%d" % [asked + 1, got + 1])
	_refresh()


## Client: ask the host for every local seat that wants to join, once a second (now: right away), until it
## is ours.
var _ask_t := 0.0
func request_joins(delta: float, now: bool = false) -> void:
	_ask_t = 0.0 if now else _ask_t - delta
	if _ask_t > 0.0:
		return
	for p in main.players:
		if p.index <= 0 or not p.has_meta(WANT) or not is_local(p):
			continue
		if joined(p):
			p.remove_meta(WANT)
			continue
		_ask_t = 1.0
		_net().send_action("join", [p.index], 1)  # sent as P2: the host may not have this seat yet


## Next free local seat: nobody uses it, no controller waits to reclaim it, and no other machine owns it.
func free_index(skip: int = -1) -> int:
	var top: int = _call("seat_limit", [], main.players.size())
	for i in range(1, top):
		if i == skip or foreign(i):
			continue
		if i >= main.players.size():
			return i  # not created yet (player() makes it)
		var p = main.players[i]
		if is_local(p) and _seat_free(p):
			return i
	return -1


func _seat_free(p) -> bool:
	if _cb.has("seat_free"):
		return _cb["seat_free"].call(p)
	return not p.active and not p.has_meta(WANT) and p.joy < 0 and ("pad_lost_t" not in p or p.pad_lost_t < 0.0)


## The keyboard set seat p plays with (no_keys: none).
func keys_of(p) -> Variant:
	return _cb["keys"].call(p) if _cb.has("keys") else p.key_set


func _has_controls(p) -> bool:
	return p.joy >= 0 or keys_of(p) != no_keys or p.has_meta(WANT)


## Client: hand a seat's controls (controller, keys, mouse, a pending join) to another seat.
func move_input(from, to) -> void:
	if from == to:
		return
	var jo = main.get("joy_owner")
	to.joy = from.joy
	if to.joy >= 0 and jo is Dictionary:
		jo[to.joy] = to.index
	to.key_set = keys_of(from)
	if "mouse_look" in from:
		to.mouse_look = from.mouse_look
		from.mouse_look = false
	if from.has_meta(WANT):
		to.set_meta(WANT, true)
	from.joy = -1
	from.key_set = no_keys
	from.remove_meta(WANT)


## Client: seat p becomes a mirror of another machine's player (on) or drivable here again (off).
func set_ghost(p, on: bool) -> void:
	p.ghost = on
	if on:
		var jo = main.get("joy_owner")
		if p.joy >= 0 and jo is Dictionary and jo.get(p.joy, -1) == p.index:
			jo.erase(p.joy)
		p.joy = -1
		p.key_set = no_keys
		if "mouse_look" in p:
			p.mouse_look = false
		if "pad_lost_t" in p:
			p.pad_lost_t = -1.0
		p.remove_meta(WANT)
	elif p.active:
		_call_view(p)
	_call("ghost", [p, on])


func _call_view(p) -> void:
	if _cb.has("ensure_view"):
		_cb["ensure_view"].call(p)
	else:
		_main_call("_ensure_view", [p])


func _refresh() -> void:
	if _cb.has("layout"):
		_cb["layout"].call()
	else:
		_main_call("_layout_views")
	if _cb.has("save"):
		_cb["save"].call()
	else:
		_main_call("_save_party")


# --- Local play: a Steam Deck on its own -------------------------------------------------------------

## A Steam Deck playing on its own (local play, DUO_MACHINE_KIND=deck).
func deck_alone() -> bool:
	var n := _net()
	return n != null and n.mode == "local" and n.machine_kind == "deck"


## Exactly ONE player (seat `solo`) on the Deck's built-in controls (the first joypad; no keyboard player),
## full screen. Other seats sit out; more controllers drop in as usual.
func deck_solo(solo: int = 0) -> void:
	var pads := Input.get_connected_joypads()
	var jo = main.get("joy_owner")
	if jo is Dictionary:
		jo.clear()
	for p in main.players:
		p.joy = -1
		if p.index != solo and p.index > 0 and p.active:
			p.set_active(false)
			_main_call("on_player_activity_changed", [p])
	var me = player(solo)
	me.joy = pads[0] if pads.size() > 0 else -1
	if me.joy >= 0 and jo is Dictionary:
		jo[me.joy] = solo
	if _cb.has("layout"):
		_cb["layout"].call()
	else:
		_main_call("_layout_views")
