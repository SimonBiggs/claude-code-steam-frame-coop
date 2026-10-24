extends SceneTree
## Checks for core/classic_seats.gd and the classic games that use it (run headless:
## godot-test --headless --path . -s res://tests/classic_seats_test.gd). Prints CLASSIC SEATS: PASS / FAIL.
##  - Every classic game (players array + on_p2_action) that says multi_machine goes through ClassicSeats
##    (host_action, handle_event, machine_left, all_left) and carries no copy of the seat code (the copies
##    drifted apart before: 🐜 one shared home), and has "multi": true in the arcade (and the reverse).
##  - ClassicSeats itself: join arbitration between two machines, owner checks, per-machine leave.
const ClassicSeats := preload("res://core/classic_seats.gd")
const COPY_FUNCS := "func (_grant_seat|remote_owner_ok|_free_seats_of|_free_seat|_sync_seats|_on_seat_moved|_move_input|_owners|_foreign|_mine|_deck_solo)\\("
const NEEDS := ["ClassicSeats.new(", "seats.host_action(", "seats.handle_event(", "seats.machine_left(", "seats.all_left(", "seats.sync()", "seats.request_joins("]


class FakeNet extends Node:
	var mode := "host"
	var store := {}
	var sender := 0
	var me := 1
	var events: Array = []
	var sent: Array = []
	var machine_kind := "tv"
	func state_get(k: String, d: Variant = null) -> Variant:
		return store.get(k, d)
	func state_set(k: String, v: Variant) -> void:
		store[k] = v
	func sender_peer() -> int:
		return sender
	func my_peer_id() -> int:
		return me
	func peer_count() -> int:
		return 2
	func event_to(peer: int, kind: String, args: Array) -> void:
		events.append([peer, kind, args])
	func send_action(action: String, args: Array, index: int = 1) -> void:
		sent.append([action, args, index])


class FakePlayer extends RefCounted:
	var index := 0
	var active := false
	var ghost := false
	var joy := -1
	var key_set := -1
	func set_active(on: bool) -> void:
		active = on


class FakeMain extends Node:
	var net: Node
	var players: Array = []


func _initialize() -> void:
	var fails: Array[String] = []
	_check_games(fails)
	_check_helper(fails)
	print("CLASSIC SEATS: %s" % ("PASS" if fails.is_empty() else "FAIL " + "; ".join(fails)))
	quit(1 if not fails.is_empty() else 0)


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _check_games(fails: Array[String]) -> void:
	var arcade := _read("res://arcade/arcade.gd")
	var copy_re := RegEx.create_from_string(COPY_FUNCS)
	var owners_re := RegEx.create_from_string("state_set\\(\"owners\"")
	for id in DirAccess.get_directories_at("res://games"):
		var main := _read("res://games/%s/main.gd" % id)
		if main == "":
			continue
		var multi := main.contains("var multi_machine := true")
		var in_arcade := arcade.contains("\"id\": \"%s\", \"multi\": true" % id)
		if multi != in_arcade and arcade.contains("\"id\": \"%s\"" % id):
			fails.append("%s: multi_machine=%s but arcade multi=%s" % [id, multi, in_arcade])
		var classic := main.contains("func on_p2_action") and not main.contains("core/party.gd")
		if not classic:
			continue
		for f in DirAccess.get_files_at("res://games/%s" % id):
			if not f.ends_with(".gd"):
				continue
			var src := _read("res://games/%s/%s" % [id, f])
			if copy_re.search(src) != null or owners_re.search(src) != null or src.contains("remote_owner_ok"):
				fails.append("%s/%s: a copy of the seat code (use core/classic_seats.gd)" % [id, f])
		if multi:
			for n in NEEDS:
				if not main.contains(n):
					fails.append("%s: multi_machine but no %s" % [id, n])


func _check_helper(fails: Array[String]) -> void:
	var net := FakeNet.new()
	var main := FakeMain.new()
	main.net = net
	for i in 7:
		var p := FakePlayer.new()
		p.index = i
		main.players.append(p)
	var seats := ClassicSeats.new(main, {"free_actions": ["pause"], "is_local": func(p) -> bool: return not p.ghost})
	# Machine 10 asks for seat 1: granted.
	net.sender = 10
	if seats.host_action("join", [1], 1) != 1:
		fails.append("first join of seat 1 not granted")
	# Machine 20 asks for seat 1 too: it gets seat 2, and is told so.
	net.sender = 20
	var got := seats.host_action("join", [1], 1)
	if got != 2 or net.events.is_empty() or net.events[-1] != [20, "seat", [1, 2]]:
		fails.append("second machine asking for a taken seat: got %d, events %s" % [got, net.events])
	# Machine 20 can't drive seat 1; 10 can; anyone may pause.
	if seats.host_action("fire", [], 1) != -1 or seats.remote_ok(1):
		fails.append("machine 20 may drive machine 10's seat")
	if seats.host_action("pause", [true], 1) != 1:
		fails.append("pause from any machine dropped")
	net.sender = 10
	if seats.host_action("fire", [], 1) != 1 or not seats.remote_ok(1):
		fails.append("owner's action dropped")
	# Machine 10 leaves: only its seat goes.
	main.players[1].active = true
	main.players[2].active = true
	var freed := seats.machine_left(10)
	if freed != [1] or main.players[1].active or not main.players[2].active or seats.owners().has(1):
		fails.append("machine_left(10) freed %s, seat 2 active=%s" % [freed, main.players[2].active])
	# Host's own calls (peer 0) always pass; "leave" frees the seat.
	net.sender = 20
	seats.host_action("leave", [], 2)
	if seats.owners().has(2):
		fails.append("leave didn't free the seat")
	# TV machine: a seat another machine owns is foreign (a ghost), ours is not.
	net.mode = "client"
	net.me = 30
	net.store["owners"] = {1: 31, 3: 30}
	if not seats.foreign(1) or seats.foreign(3) or not seats.mine(3) or seats.mine(1):
		fails.append("foreign/mine wrong on a TV machine")
	main.players[2].active = false  # seat 2: free on this machine
	main.players[1].joy = 4
	main.players[1].set_meta(ClassicSeats.WANT, true)
	seats.sync()
	if not main.players[1].ghost or main.players[1].joy != -1 or main.players[2].joy != 4 or not main.players[2].has_meta(ClassicSeats.WANT):
		fails.append("sync didn't move our controls off another machine's seat")
	main.free()
	net.free()
