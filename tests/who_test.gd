extends SceneTree
## Checks for core/who.gd (WHO joined / left: names, not "TV player") and core/machine.gd display_name
## (run headless: godot-test --headless --path . -s res://tests/who_test.gd). Prints WHO: PASS / FAIL.
##  - Names from hostnames: david-steamdeck -> David, nathanael-deck -> Nathanael, steamdeck -> Deck; TV / VR.
##  - Seat labels: a Deck's seat is its person ("David"), the TV's seats say "TV (P3)", local play "P3"; a seat
##    whose machine is leaving, or whose "leave" is being handled, still names that machine.
##  - 🐜 No generic join / leave text anywhere in core/, arcade/, games/: no "THE TV PLAYERS JOINED!", "PLAYER 3
##    LEFT", "A TV player opened the menu", "TV JOINED"... (Simon, 2026-10-24: "x TV players joined" -> say WHO).
##    New join / leave messages go through core/who.gd. Log lines (print) are fine.
const Who := preload("res://core/who.gd")
const Machine := preload("res://core/machine.gd")
const ClassicSeats := preload("res://core/classic_seats.gd")

## Generic join / leave text in a string literal (case-insensitive unless noted). Each: [regex, what it is].
const GENERIC := [
	["(?i)\"[^\"\\n]*\\btv (players?|crew|band|gunners|machine)\\b[^\"\\n]*\\b(joined|left|arrived)\\b", "\"the TV players joined/left\""],
	["\"[^\"\\n]*\\b(PLAYER|Player|player|P) ?%d\\b[^\"\\n]*\\b(JOINED|JOINS|joined|joins|LEFT|left(?! stick| hand| /)|ROLLS IN|CLIMBED|COMING ABOARD|flew home)", "\"PLAYER %d JOINED/LEFT\""],
	["(?i)\"an? (tv player|bee|runner|knight|deckhand|gunner) opened the menu\"", "\"A TV player opened the menu\""],
	["(?i)\"[^\"\\n]*\\b(tv|deck) (joined|left)\\b", "\"TV JOINED / DECK LEFT\""],
	["\"[^\"\\n]*%s (JOINED|JOINS|LEFT|joined|joins|left)\\b", "\"%s JOINED\" (a seat number / kind, not who)"],
	["\"(DECK|TV)\" if kind", "a machine kind shown as its name"],
]


class FakeNet extends Node:
	var mode := "host"
	var store := {}
	var sender := 0
	var me := 1
	var names := {1: "VR", 10: "David", 20: "TV", 30: "Simon"}
	func state_get(k: String, d: Variant = null) -> Variant:
		return store.get(k, d)
	func state_set(k: String, v: Variant) -> void:
		store[k] = v
	func sender_peer() -> int:
		return sender
	func my_peer_id() -> int:
		return me
	func peer_count() -> int:
		return 3
	func event_to(_peer: int, _kind: String, _args: Array) -> void:
		pass
	func machine_name_of(peer: int) -> String:
		return str(names.get(me if peer <= 0 else peer, "TV"))


class FakePlayer extends RefCounted:
	var index := 0
	var active := false
	var ghost := false
	var joy := -1
	var key_set := -1
	var label_when_gone := ""
	func set_active(on: bool) -> void:
		active = on


class FakeMain extends Node:
	var net: Node
	var seats: RefCounted
	var players: Array = []


func _initialize() -> void:
	var fails: Array[String] = []
	_check_names(fails)
	_check_labels(fails)
	_check_seats(fails)
	_check_no_generic(fails)
	_check_wiring(fails)
	print("WHO: %s" % ("PASS" if fails.is_empty() else "FAIL " + "; ".join(fails)))
	quit(1 if not fails.is_empty() else 0)


func _eq(fails: Array[String], got: Variant, want: Variant, what: String) -> void:
	if got != want:
		fails.append("%s: got %s, want %s" % [what, str(got), str(want)])


func _check_names(fails: Array[String]) -> void:
	for c in [["david-steamdeck", "David"], ["nathanael-deck", "Nathanael"], ["simon-steamdeck", "Simon"],
			["Esther-Deck\n", "Esther"], ["abigail-steam-deck.local", "Abigail"], ["steamdeck", "Deck"],
			["SteamDeck-OLED", "Deck"], ["", "Deck"], ["deck-david", "David"], ["simon_deck_2", "Simon"]]:
		_eq(fails, Machine.name_from_hostname(c[0], "deck"), c[1], "hostname %s" % c[0].strip_edges())
	if not OS.has_environment("DUO_MACHINE_NAME"):
		_eq(fails, Machine.display_name("tv"), "TV", "the Steam Machine / TV")
		_eq(fails, Machine.display_name("frame"), "VR", "the Frame")


func _check_labels(fails: Array[String]) -> void:
	_eq(fails, Who.seat_label("David", 2), "David", "a Deck's seat")
	_eq(fails, Who.seat_label("TV", 2, 3), "TV (P3)", "a TV seat")
	_eq(fails, Who.seat_label("TV", 1, 1), "TV (P2)", "the TV's only seat still says which pad")
	_eq(fails, Who.seat_label("David", 4, 2), "David (P5)", "a Deck with two pads")
	_eq(fails, Who.joined("David"), "David joined!", "joined")
	_eq(fails, Who.joined("TV (P3)", "the crew"), "TV (P3) joined the crew!", "joined the crew")
	_eq(fails, Who.left("Nathanael"), "Nathanael left", "left")
	_eq(fails, Who.names_line(["TV"]), "TV", "one name")
	_eq(fails, Who.names_line(["TV", "David"]), "TV and David", "two names")
	_eq(fails, Who.names_line(["TV", "David", "Simon"]), "TV, David and Simon", "three names")


func _check_seats(fails: Array[String]) -> void:
	var net := FakeNet.new()
	var main := FakeMain.new()
	main.net = net
	for i in 7:
		var p := FakePlayer.new()
		p.index = i
		main.players.append(p)
	var seats := ClassicSeats.new(main, {"is_local": func(p) -> bool: return not p.ghost,
		"deactivate": func(p) -> void:
			p.label_when_gone = Who.seat(main, p.index)
			p.active = false})
	main.seats = seats
	# Local play: plain seat numbers.
	net.mode = "local"
	_eq(fails, Who.seat(main, 2), "P3", "local play")
	net.mode = "host"
	# David's Deck (10) takes seat 1; the TV (20) seats 2 and 3.
	net.sender = 10
	seats.host_action("join", [1], 1)
	net.sender = 20
	seats.host_action("join", [2], 2)
	seats.host_action("join", [3], 3)
	net.sender = 0
	_eq(fails, Who.seat(main, 1), "David", "David's seat")
	_eq(fails, Who.seat(main, 3), "TV (P4)", "a TV seat")
	_eq(fails, Who.seat(main, 0), "VR", "the host's own seat")
	# A "leave" from the TV: the seat is free by the time the game shows it, the sender still says who.
	net.sender = 20
	seats.host_action("leave", [], 3)
	_eq(fails, Who.seat(main, 3), "TV (P4)", "seat freed by its own leave")
	net.sender = 0
	# David's Deck goes away: the seat freed while it leaves is still David's.
	main.players[1].active = true
	seats.machine_left(10)
	_eq(fails, main.players[1].label_when_gone, "David", "seat of a machine that left")
	# A TV machine (client 20) labels another machine's seat and its own.
	net.mode = "client"
	net.me = 20
	net.store["owners"] = {2: 20, 5: 30}
	_eq(fails, Who.seat(main, 5), "Simon", "another machine's seat on a TV machine")
	_eq(fails, Who.seat(main, 2), "TV (P3)", "this TV machine's own seat")
	_eq(fails, Who.seat(main, 4), "TV (P5)", "a seat this machine is still asking for")
	net.free()
	main.free()


## 🐜 One helper, no copies: generic "TV players joined" text fails here.
func _check_no_generic(fails: Array[String]) -> void:
	var res: Array = []
	for g in GENERIC:
		res.append([RegEx.create_from_string(g[0]), g[1]])
	var meta_re := RegEx.create_from_string("get_meta\\(\"[^\"]*\", null\\)")
	for dir in ["res://core", "res://arcade", "res://games"]:
		for path in _gd_files(dir):
			if path == "res://core/who.gd":
				continue
			var lines := FileAccess.get_file_as_string(path).split("\n")
			for i in lines.size():
				var line := lines[i].strip_edges()
				if line.begins_with("#") or line.contains("print(") or line.contains("push_warning("):
					continue
				for r in res:
					if (r[0] as RegEx).search(line) != null:
						fails.append("%s:%d generic join/leave text (%s): use core/who.gd" % [path, i + 1, r[1]])
				# (while here) get_meta(key, null) prints an error when the key is missing (net.gd did on every
				# scene change): write (get_meta(key) if has_meta(key) else null).
				if meta_re.search(line) != null:
					fails.append("%s:%d get_meta(key, null) errors when missing: use has_meta" % [path, i + 1])


## The pieces that make names reach every machine.
func _check_wiring(fails: Array[String]) -> void:
	var net := FileAccess.get_file_as_string("res://core/net.gd")
	if not net.contains("\"_hello\", [machine_kind, machine_name]"):
		fails.append("core/net.gd: the hello no longer sends this machine's name")
	if not net.contains("state_set(\"_names\""):
		fails.append("core/net.gd: the host no longer shares every machine's name")
	var arcade := FileAccess.get_file_as_string("res://arcade/arcade.gd")
	if not arcade.contains("_hello.rpc_id(1, my_kind, Machine.display_name(my_kind))"):
		fails.append("arcade: the lobby hello no longer sends this machine's name")
	if not FileAccess.get_file_as_string("res://core/party.gd").contains("Who.seat_in("):
		fails.append("core/party.gd: name_of no longer labels networked seats by machine")


func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir + "/" + d))
	return out
