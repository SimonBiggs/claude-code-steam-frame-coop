extends SceneTree
## FIRST GOAL: every arcade game has games/<id>/first_goal.gd (core/first_goal.gd): what the player is, the one thing
## to do first for TV and VR ([button, short text]), a small-win condition, and expressions that parse. The FirstGoal
## service is in core/services.gd (so every game shows it without code of its own).
## Runtime: every game bot runs the service too, and a data expression that fails on the real game is an engine ERROR
## from res:// (bots fail on it).
##   godot-test --headless --path . -s res://tests/first_goal_test.gd     Prints FIRST GOAL: PASS / FAIL.

const FirstGoal := preload("res://core/first_goal.gd")

var fails := 0


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FIRST GOAL: FAIL ", what)


## A stand-in game main + net (state store) + awards, built from source so the test needs no game.
const FAKE_SRC := """
extends Node
var score := 0
var hits := [0, 0, 0, 0]
var awards: Object = null
var net: Object = null
"""
const FAKE_NET := """
extends Node
var mode := "host"
var store := {}
func state_set(k: String, v: Variant) -> void:
	store[k] = v
func state_get(k: String, d: Variant = null) -> Variant:
	return store.get(k, d)
"""
const FAKE_AWARDS := """
extends RefCounted
var stats := {}
func get_stat(i: int, s: String) -> float:
	return float((stats.get(i, {}) as Dictionary).get(s, 0.0))
"""


func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## Every player has their own first goal: split-screen seats, whose win it was, host -> TV machine sync, and
## remembering per seat per profile (backlog 2026-11-20: one card for the whole window; host-only wins).
func _seat_tests() -> void:
	_expect(FirstGoal.key_of("g", "tv", 0) == "g/tv" and FirstGoal.key_of("g", "deck", 1) == "g/deck#2", "remember keys per seat")
	var main: Node = _script(FAKE_SRC).new()
	var net: Node = _script(FAKE_NET).new()
	main.net = net
	main.awards = _script(FAKE_AWARDS).new()
	main.awards.stats = {1: {"score": 0.0}, 2: {"score": 0.0, "deaths": 0.0}}
	var host: Node = FirstGoal.new()
	host.main = main
	host.game = "fake"
	host.data = {"you": "a Tester", "do": {"tv": ["A", "Go!"], "vr": ["TRIGGER", "Go!"]}, "rise": "v('score', 0)"}
	var s1: Variant = _seat(host, 1, 0)
	var s2: Variant = _seat(host, 2, 1)
	host.seats = [s1, s2]
	for s in host.seats:
		host._cur = s
		host._bases(s)
		s.state = "show"
	# P2's own stat rises with the shared score: P2's win alone, at once; deaths are not wins
	main.score = 1
	main.awards.stats[2]["score"] = 1.0
	main.awards.stats[1]["deaths"] = 3.0
	_expect(_won(host, s2, 0.25), "the player whose own awards stat rose won")
	_expect(not _won(host, s1, 0.25), "the other player did not win from the shared score (yet)")
	# per-player data: only that player's own number counts
	host.data["rise_p"] = "v('hits', [])[p]"
	for s in host.seats:
		host._cur = s
		host._bases(s)
	main.score = 2
	main.hits[1] = 1
	_expect(_won(host, s1, 2.0), "rise_p: P1's own hit is P1's win")
	_expect(not _won(host, s2, 2.0), "rise_p: P1's hit is not P2's win, however long the shared score waits")
	host.data.erase("rise_p")
	# host publishes, a TV machine shows / remembers its own player's win
	host._win(s2, true)
	s2.local = false  # (P2 sits at the TV machine)
	host._publish()
	var fgs: Dictionary = net.state_get(FirstGoal.NET_KEY, {})
	_expect((fgs.get("won", {}) as Dictionary).has("2") and not (fgs.get("won", {}) as Dictionary).has("1"), "host publishes who won (%s)" % str(fgs))
	_expect(bool(fgs.get("go", false)), "host publishes that play started")
	var cnet: Node = _script(FAKE_NET).new()
	cnet.mode = "client"
	cnet.store = net.store.duplicate(true)
	var cmain: Node = _script(FAKE_SRC).new()
	cmain.net = cnet
	var client: Node = FirstGoal.new()
	client.main = cmain
	client.game = "fake"
	client.data = host.data
	var path := "user://first_goal_test_%d.cfg" % OS.get_process_id()
	client.save_path = path
	var c2: Variant = _seat(client, 2, 1)
	client.seats = [c2]
	client._cur = c2
	client._bases(c2)
	c2.state = "show"
	client._step_seat(c2, 0.25, false, true, client._host_fg())
	_expect(c2.state == "done", "the TV machine marks its player's first goal done from the host's word (%s)" % c2.state)
	var cfg := ConfigFile.new()
	_expect(cfg.load(path) == OK and bool(cfg.get_value(FirstGoal.profile(), "fake/tv#2", false)), "remembered on the TV machine, for that seat")
	_expect(not bool(cfg.get_value(FirstGoal.profile(), "fake/tv", false)), "the machine's first player is not remembered by someone else's win")
	var again: Variant = _seat(client, 2, 1)
	client._cur = again
	_expect(client._remembered(again), "next time that seat's first goal stays off")
	# a seat with its own role (Cannon Cove's flat P1 gunner): their own card says so, others keep theirs
	client.data = {"you_tv": "a Deckhand", "you_vr": "the Gunner", "do": {"tv": ["A", "Carry!"], "vr": ["GRIP", "Pull!"]},
		"seats": {0: {"you": "the Gunner", "do": ["RT", "Fire!"]}}, "rise": "0"}
	var g0: Variant = _seat(client, 0, 0)
	_expect(client._you(g0).contains("GUNNER") and String(client._pair(g0)[1]) == "Fire!", "seat 0 has its own role on a flat screen")
	_expect(client._you(c2).contains("DECKHAND"), "the other seats keep theirs")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for n in [host, client, main, cmain, net, cnet]:
		n.free()


func _seat(fg: Node, slot: int, idx: int) -> Variant:
	var s: Variant = FirstGoal.Seat.new()
	s.slot = slot
	s.idx = idx
	s.local = true
	s.rescue = FirstGoal.Rescue.new()
	return s


func _won(fg: Node, s: Variant, dt: float) -> bool:
	fg._cur = s
	return fg._won(s, dt)


func _initialize() -> void:
	var games: Array = load("res://arcade/arcade.gd").GAMES
	var n := 0
	for g in games:
		var id := String(g.id)
		n += 1
		for p in FirstGoal.problems_of(id):
			_expect(false, p)
	# every game folder with a main scene that the arcade lists is covered above; a game folder the arcade doesn't
	# list yet (being built) still needs data before it lands
	for id in FirstGoal.game_ids():
		var listed := false
		for g in games:
			listed = listed or String(g.id) == id
		if not listed:
			for p in FirstGoal.problems_of(id):
				_expect(false, p)
	var services: Array = load("res://core/services.gd").SERVICES
	var has := false
	for e in services:
		has = has or String(e.path) == "res://core/first_goal.gd"
	_expect(has, "core/first_goal.gd is not a service in core/services.gd")
	# the helper's own pieces: remembered per profile, sums nested scores
	var fg: Node = FirstGoal.new()
	_expect(is_equal_approx(fg.sum({"a": 2, "b": [1, 3.5]}), 6.5), "sum() of nested scores")
	_expect(FirstGoal.profile() != "", "a profile name")
	_expect(FirstGoal.game_of(null) == "", "game_of(null)")
	fg.free()
	_seat_tests()
	print("FIRST GOAL: %d games checked, %d problems" % [n, fails])
	print("FIRST GOAL: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(1 if fails > 0 else 0)
