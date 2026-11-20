extends Node
## End to end (core/tv_seat.gd): a streamed VR host in the arcade lobby, a pad at the TV presses A -> a real second
## copy of the arcade (headless here, like its host) starts, joins the lobby, follows the host into Balloon Pop and its
## pad takes a TV seat there, which the host sees as a seat on another machine. Then the TV screen is closed.
##   XDG_DATA_HOME=<scratch> DUO_PORT=<unique> DUO_HOST=1 BOT_VR=1 VR_WATCH_FAKE=1 DUO_FAKE_STREAMED_VR=1 \
##     TV_SEAT_VIRTUAL_REAL=1 TV_SEAT_TEST_PAD=1 timeout 150 godot-test --headless --path . res://tests/tv_seat_e2e.tscn
##   -> TV SEAT E2E: PASS / FAIL (XDG_DATA_HOME: the TV screen's user:// lives under ours; keep it out of the real one)

const TvSeat := preload("res://core/tv_seat.gd")
const Party := preload("res://core/party.gd")
const LIMIT := 120.0

var arcade: Node
var t := 0.0
var phase := "lobby"
var phase_t := 0.0
var fails: Array[String] = []
var said := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.set_meta("save_test_mode", true)
	arcade = load("res://arcade.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arcade)
	(func() -> void: get_tree().current_scene = arcade).call_deferred()
	print("TV SEAT E2E: started (port %s)" % OS.get_environment("DUO_PORT"))


func _seat() -> Node:
	return get_tree().root.get_node_or_null("TvSeat")


func _say(k: String, line: String) -> void:
	if not said.has(k):
		said[k] = true
		print("TV SEAT E2E: ", line)


func _process(delta: float) -> void:
	t += delta
	phase_t += delta
	var seat := _seat()
	if t > LIMIT:
		_end("timed out in phase %s" % phase)
		return
	match phase:
		"lobby":
			if t > 3.0 and seat != null:
				Engine.set_meta(Party.VIRTUAL_META, [Party.VIRTUAL_PAD_BASE])
				_next("pad")
		"pad":
			if phase_t > 1.0:
				if not seat.ui_text().begins_with(TvSeat.TEXT_JOIN):
					fails.append("a pad at the TV: prompt '%s' (got '%s')" % [TvSeat.TEXT_JOIN, seat.ui_text()])
				var e := InputEventJoypadButton.new()
				e.device = Party.VIRTUAL_PAD_BASE
				e.button_index = JOY_BUTTON_A
				e.pressed = true
				Input.parse_input_event(e)
				_next("press")
		"press":
			if phase_t > 0.2:
				var up := InputEventJoypadButton.new()
				up.device = Party.VIRTUAL_PAD_BASE
				up.button_index = JOY_BUTTON_A
				Input.parse_input_event(up)
				if seat.client_pid <= 0:
					_end("A pressed but no TV screen started")
					return
				_say("pid", "TV screen started, pid %d" % seat.client_pid)
				_next("joining")
		"joining":
			if phase_t > 0.6 and phase_t < 1.0 and not seat.client_joined and not seat.ui_text().begins_with(TvSeat.TEXT_STARTING):
				fails.append("while joining: prompt '%s' (got '%s')" % [TvSeat.TEXT_STARTING, seat.ui_text()])
				phase_t = 1.0
			if seat.client_joined:
				_say("joined", "TV screen joined the lobby after %.1f s" % phase_t)
				_next("settle")
			elif not seat.client_running():
				_end("the TV screen exited before joining")
		"settle":
			if phase_t > 0.6 and phase_t < 1.0 and seat.ui_text() != "":
				fails.append("prompt still up over the TV screen: %s" % seat.ui_text())
				phase_t = 1.0
			if phase_t > 2.0:
				var idx := -1
				for i in arcade.GAMES.size():
					if arcade.GAMES[i].id == "balloon_pop":
						idx = i
				arcade._request_start(idx)
				_next("game")
		"game":
			var main := get_tree().current_scene
			var party = main.get("party") if main != null and main != arcade else null
			if party is Node:
				for s in party.active_slots():
					if party.is_remote(s):
						_say("seat", "the TV screen's player sits as %s (machine %s) after %.1f s" % [party.name_of(s), party.machine_kind(s), phase_t])
						if seat.ui_text() != "":
							fails.append("prompt shows during the game: %s" % seat.ui_text())
						_next("close")
						return
		"close":
			if phase_t > 1.0:
				seat._kill_client("the e2e test is done")
				_next("closed")
		"closed":
			if phase_t > 1.5:
				if seat.client_running():
					fails.append("TV screen still running after the close")
				_end("")


func _next(p: String) -> void:
	phase = p
	phase_t = 0.0


func _end(why: String) -> void:
	if why != "":
		fails.append(why)
	var seat := _seat()
	if seat != null and seat.client_running():
		seat._kill_client("the e2e test ended")
	for f in fails:
		print("  FAIL ", f)
	print("TV SEAT E2E: %s (%d problems)" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
	phase = "done"
	set_process(false)
	get_tree().quit(0 if fails.is_empty() else 1)
