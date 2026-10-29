extends SceneTree
## core/party.gd: an A press that arrives after its (virtual) pad was unplugged must not seat anyone.
## Input.parse_input_event queues the event; it reaches party._input after the bot (or a battery) has
## already made the player leave and unplugged the pad. treasure_dig_bot's drop-in/out test flaked on
## this under load (the late player came straight back: 3 players, want 2).
##   godot-test --headless --path . -s res://tests/party_stale_press_test.gd

const Party := preload("res://core/party.gd")

var fails := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var p := Party.new()
	root.add_child(p)
	for i in 30:
		await process_frame
	var dev: int = p.add_virtual_pad()
	_press(dev)
	for i in 5:
		await process_frame
	var slot: int = p.owner_of(dev)
	_expect(slot >= 0, "A on a virtual pad seats a player (slot %d)" % slot)
	# The same frame: an A press is queued, then the player leaves and the pad is unplugged.
	_press(dev)
	p.leave(slot)
	p.remove_virtual_pad(dev)
	for i in 10:
		await process_frame
	_expect(p.owner_of(dev) < 0 and not p.is_active(slot), "the stale A from the unplugged pad seats nobody (%d players)" % p.player_count())
	# A real pad (device 0, like the offscreen runner's injected presses) still joins.
	_press(0)
	for i in 5:
		await process_frame
	_expect(p.owner_of(0) >= 0, "device 0's A still joins")
	print("BOT RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)


func _press(dev: int) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = dev
		e.button_index = JOY_BUTTON_A
		e.pressed = down
		Input.parse_input_event(e)


func _expect(ok: bool, what: String) -> void:
	print(("ok   " if ok else "SCRIPT ERROR: ") + what)
	if not ok:
		fails += 1
