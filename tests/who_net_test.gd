extends SceneTree
## WHO joined, over the real network code: ONE headless Godot holds a host and three joining machines (each in its own
## branch with its own SceneMultiplayer, so it is one test process, not four: the family plays while tests run).
## Each machine is named like a real one (VR host, David's Deck, the TV with two pads, Nathanael's Deck), joins with
## core/net.gd, claims seats through core/classic_seats.gd, and the game shows join / leave text with core/who.gd.
## Checks the host says "David joined!", "TV (P3) joined!", "Nathanael left" (never "TV player" / "PLAYER 3"), and
## every machine labels every seat the same way.
##   godot-test --headless --path . -s res://tests/who_net_test.gd     (DUO_PORT: a private port; prints WHO NET: PASS)
const Net := preload("res://core/net.gd")
const Who := preload("res://core/who.gd")
const ClassicSeats := preload("res://core/classic_seats.gd")

## [name, seats it plays]. Machine 0 hosts (VR).
const MACHINES := [["VR", []], ["David", [1]], ["TV", [2, 3]], ["Nathanael", [4]]]


class Seat extends RefCounted:
	var index := 0
	var active := false
	var ghost := false
	var joy := -1
	var key_set := -1
	func set_active(on: bool) -> void:
		active = on


## A tiny classic game (players array + on_p2_action), as far as core/net.gd is concerned.
class Game extends Node:
	var net: Node
	var seats: RefCounted
	var players: Array = []
	var multi_machine := true
	var said: Array[String] = []

	func say(text: String) -> void:
		said.append(text)
		print("WHO NET %s: %s" % [net.machine_name, text])

	func on_machine_joined(peer: int, _kind: String) -> void:
		say(Who.joined(net.machine_name_of(peer)))

	func on_machine_left(peer: int) -> void:
		seats.machine_left(peer)
		say(Who.left(net.machine_name_of(peer)))

	func on_client_left() -> void:
		seats.all_left()

	func on_p2_action(action: String, args: Array, index: int = 1) -> void:
		index = seats.host_action(action, args, index)
		if index < 0:
			return
		match action:
			"join":
				if not players[index].active:
					players[index].active = true
					say(Who.joined(Who.seat(self, index), "the crew"))
			"leave":
				if players[index].active:
					players[index].active = false
					say(Who.left(Who.seat(self, index)))
			"pause":
				say(Who.paused_by(net.machine_name_of(net.sender_peer())))


var games: Array = []
var t := 0.0
var step := 0
var fails: Array[String] = []


func _setup() -> void:
	for k in MACHINES.size():
		var branch := Node.new()
		branch.name = "M%d" % k
		root.add_child(branch)
		set_multiplayer(SceneMultiplayer.new(), branch.get_path())  # its own connection, like its own machine
		var g := Game.new()
		g.name = "Game"
		var n := Net.new()
		n.name = "Net"
		n.machine_name = MACHINES[k][0]
		n.machine_kind = "frame" if k == 0 else ("tv" if MACHINES[k][0] == "TV" else "deck")
		n.main = g
		g.net = n
		for i in 7:
			var s := Seat.new()
			s.index = i
			g.players.append(s)
		g.seats = ClassicSeats.new(g, {})
		branch.add_child(g)
		g.add_child(n)
		games.append(g)
	games[0].net.host(true)


func _process(delta: float) -> bool:
	t += delta
	if games.is_empty():
		_setup()  # (the root is in the tree from the first frame on)
		return false
	if step == 0 and t > 1.0:
		step = 1
		for k in range(1, games.size()):
			games[k].net.join("127.0.0.1")
	elif step == 1 and t > 3.0:
		step = 2
		for k in range(1, games.size()):
			for s in MACHINES[k][1]:
				games[k].net.send_action("join", [s], s)
	elif step == 2 and t > 5.0:
		step = 3
		games[2].net.send_action("pause", [true], 2)
		_check_labels()
	elif step == 3 and t > 6.0:
		step = 4
		var m3: Node = games[3].get_parent()
		m3.queue_free()  # Nathanael's Deck goes away
	elif step == 4 and t > 8.5:
		_check_host()
		print("WHO NET: %s" % ("PASS" if fails.is_empty() else "FAIL " + "; ".join(fails)))
		quit(1 if not fails.is_empty() else 0)
		return true
	if t > 30.0:
		print("WHO NET: FAIL timed out at step %d" % step)
		quit(1)
		return true
	return false


## Every machine labels every seat the same way: David, TV (P3), TV (P4), Nathanael.
func _check_labels() -> void:
	var want := ["David", "TV (P3)", "TV (P4)", "Nathanael"]
	for k in games.size():
		var g: Game = games[k]
		var got: Array = []
		for s in [1, 2, 3, 4]:
			got.append(Who.seat(g, s))
		if got != want:
			fails.append("%s labels the seats %s (want %s)" % [g.net.machine_name, got, want])


func _check_host() -> void:
	var said: Array[String] = games[0].said
	for want in ["David joined!", "TV joined!", "Nathanael joined!", "David joined the crew!", "TV (P3) joined the crew!",
			"TV (P4) joined the crew!", "Nathanael joined the crew!", "TV opened the menu", "Nathanael left"]:
		if not want in said:
			fails.append("host never said \"%s\" (said %s)" % [want, said])
	for line in said:
		if line.to_lower().contains("tv player") or line.contains("PLAYER") or line.contains("P5"):
			fails.append("generic text: %s" % line)
