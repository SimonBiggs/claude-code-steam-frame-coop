extends Node
## BotKit: shared helpers for headless bot tests.
## - Ignores the REAL controllers attached to this machine (their presses are swallowed and
##   core/party.gd skips them), so a pad on the couch can't pause or join a test.
## - Resumes the game if something else paused it (allow_pause = true while you pause on purpose).
## - Virtual pads: press / hold buttons, move sticks and triggers, for a device or a party slot.
## - Fake-VR driver for core/vr_rig.gd: put the head and hands somewhere, reach for points, pull
##   the trigger, push the sticks, change the head height (sitting / a kid), so VR code runs headless.
## - BOT_PLAYERS handling, a timeline (at / every) and a progress printer with timestamps.
## - assert_true / assert_eq print "SCRIPT ERROR: BOT ASSERT FAILED: ..." so test runs that grep for
##   SCRIPT ERROR catch them; finish() prints a summary and quits (exit code 1 on failures).
## Usage (first thing in the bot's _ready, before the game is instanced):
##   const BotKit := preload("res://tests/bot_kit.gd")
##   kit = BotKit.new(); add_child(kit)
##   main = load("res://games/<id>/main.tscn").instantiate(); add_child(main); kit.main = main
##   kit.at(2.0, "join a pad", func() -> void: kit.join_bot(main.party))
##   kit.assert_true(main.party.player_count() == 1, "the pad joined")

## First device id of virtual pads (same as core/party.gd); lower ids are real hardware.
const FAKE_PAD_BASE := 40
const PARTY_IGNORE_META := "bot_ignore_real_pads"
const SAVE_TEST_META := "save_test_mode"
const BUTTONS := {
	"accept": JOY_BUTTON_A, "a": JOY_BUTTON_A, "back": JOY_BUTTON_B, "b": JOY_BUTTON_B,
	"x": JOY_BUTTON_X, "y": JOY_BUTTON_Y, "lb": JOY_BUTTON_LEFT_SHOULDER, "rb": JOY_BUTTON_RIGHT_SHOULDER,
	"start": JOY_BUTTON_START, "select": JOY_BUTTON_BACK, "l3": JOY_BUTTON_LEFT_STICK,
	"r3": JOY_BUTTON_RIGHT_STICK, "up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN,
	"left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT,
}

## The game's main node (optional; used to tell the host when resuming on the TV machine).
var main: Node
## Seconds since the kit started (process time, keeps counting while paused).
var t := 0.0
## Set while the test pauses on purpose; otherwise a pause longer than resume_after is undone.
var allow_pause := false
var resume_after := 1.0
var checks := 0
var failures := 0
## Print every passing check too.
var verbose := true

var _paused_t := 0.0
var _timeline: Array = []  # [time, label, Callable, done]
var _repeats: Array = []  # [interval, next, Callable]
var _filter: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -200  # timeline steps run before the game's frame
	Engine.set_meta(PARTY_IGNORE_META, true)
	Engine.set_meta(SAVE_TEST_META, true)
	_filter = RealPadFilter.new()
	_filter.name = "BotRealPadFilter"
	get_tree().root.add_child.call_deferred(_filter)
	var real := Input.get_connected_joypads()
	if not real.is_empty():
		info("ignoring %d real controller(s): %s" % [real.size(), str(real)])


func _exit_tree() -> void:
	if _filter != null and is_instance_valid(_filter):
		_filter.queue_free()


## Sits last under the root, so it sees input first: real controllers are swallowed.
class RealPadFilter extends Node:
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _input(event: InputEvent) -> void:
		var jb := event as InputEventJoypadButton
		var jm := event as InputEventJoypadMotion
		if (jb != null and jb.device < FAKE_PAD_BASE) or (jm != null and jm.device < FAKE_PAD_BASE):
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	t += delta
	_unstick(delta)
	for step in _timeline:
		var s: Array = step
		if not bool(s[3]) and t >= float(s[0]):
			s[3] = true
			info(str(s[1]))
			var c: Callable = s[2]
			if c.is_valid():
				c.call()
	for r in _repeats:
		var rr: Array = r
		if t >= float(rr[1]):
			rr[1] = t + float(rr[0])
			var c2: Callable = rr[2]
			if c2.is_valid():
				var out: Variant = c2.call()
				if out is String and str(out) != "":
					info(str(out))


# --- Timeline and printing ------------------------------------------------------------------

## Print a line with the kit's clock: "[  12.3s] message".
func info(msg: String) -> void:
	print("[%6.1fs] %s" % [t, msg])


## Run `fn` once when the clock reaches `time` (prints `label` first).
func at(time: float, label: String, fn: Callable = Callable()) -> void:
	_timeline.append([time, label, fn, false])


## Call `fn` every `interval` seconds; if it returns a non-empty String, print it (progress lines).
func every(interval: float, fn: Callable) -> void:
	_repeats.append([interval, t + interval, fn])


## True once every timeline step has run.
func timeline_done() -> bool:
	for step in _timeline:
		var s: Array = step
		if not bool(s[3]):
			return false
	return true


## BOT_PLAYERS (clamped to 1..cap), or `default`.
static func bot_players(default: int, cap: int = 6) -> int:
	var n := int(OS.get_environment("BOT_PLAYERS")) if OS.has_environment("BOT_PLAYERS") else default
	return clampi(n, 1, cap)


# --- Assertions -------------------------------------------------------------------------------

## Count a check; a failure prints a SCRIPT ERROR-style line (test runs grep for those).
func assert_true(cond: bool, msg: String) -> bool:
	checks += 1
	if cond:
		if verbose:
			info("ok   " + msg)
		return true
	failures += 1
	printerr("SCRIPT ERROR: BOT ASSERT FAILED: %s (at %.1fs)" % [msg, t])
	return false


## Check a == b (same type; numbers compared approximately).
func assert_eq(a: Variant, b: Variant, msg: String) -> bool:
	var same: bool = typeof(a) == typeof(b) and a == b
	if not same and (a is float or a is int) and (b is float or b is int):
		same = is_equal_approx(float(a), float(b))
	return assert_true(same, "%s (got %s, want %s)" % [msg, str(a), str(b)])


## Check |a - b| <= tolerance.
func assert_near(a: float, b: float, tolerance: float, msg: String) -> bool:
	return assert_true(absf(a - b) <= tolerance, "%s (got %.3f, want %.3f +- %.3f)" % [msg, a, b, tolerance])


## Print the summary and quit (exit code 1 if anything failed).
func finish(quit: bool = true) -> void:
	if failures == 0:
		info("BOT RESULT: PASS (%d checks)" % checks)
	else:
		printerr("SCRIPT ERROR: BOT RESULT: FAIL (%d of %d checks failed)" % [failures, checks])
	if quit:
		get_tree().quit(1 if failures > 0 else 0)


# --- Pause guard ----------------------------------------------------------------------------

func _unstick(delta: float) -> void:
	if not get_tree().paused or allow_pause:
		_paused_t = 0.0
		return
	_paused_t += delta
	if _paused_t < resume_after:
		return
	_paused_t = 0.0
	info("the game was paused by something else (a real controller?) - resuming")
	get_tree().call_group("pause_menu", "sync_remote_pause", false)
	get_tree().paused = false
	var net: Node = main.get("net") if main != null and is_instance_valid(main) else null
	if net != null and str(net.mode) == "client":
		net.send_action("pause", [false])


# --- Virtual pads -----------------------------------------------------------------------------

## Press and release a button (one quick tap; party's just_pressed still sees it).
func pad_press(device: int, button: JoyButton) -> void:
	pad_hold(device, button, true)
	pad_hold(device, button, false)


## Press (down = true) or release a button and leave it there.
func pad_hold(device: int, button: JoyButton, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	e.pressed = down
	Input.parse_input_event(e)


## Move a stick: which = "left" / "move" or "right" / "look". v.y DOWN positive (like a real pad).
func pad_stick(device: int, which: String, v: Vector2) -> void:
	var right := which == "right" or which == "look"
	_axis(device, JOY_AXIS_RIGHT_X if right else JOY_AXIS_LEFT_X, v.x)
	_axis(device, JOY_AXIS_RIGHT_Y if right else JOY_AXIS_LEFT_Y, v.y)


## Analog trigger: which = "lt" or "rt", value 0..1.
func pad_trigger(device: int, which: String, value: float) -> void:
	_axis(device, JOY_AXIS_TRIGGER_LEFT if which == "lt" else JOY_AXIS_TRIGGER_RIGHT, value)


func _axis(device: int, axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)


## Tap a standard action ("accept", "back", "x", "up", ...) on a party slot's device.
func slot_press(party: Node, slot: int, action: String) -> void:
	var dev: int = party.device_of(slot)
	if dev < 0:
		assert_true(false, "slot_press: slot %d has no pad" % slot)
		return
	pad_press(dev, BUTTONS.get(action, JOY_BUTTON_A))


## Hold or release a standard action on a party slot's pad.
func slot_hold(party: Node, slot: int, action: String, down: bool) -> void:
	var dev: int = party.device_of(slot)
	if dev >= 0:
		pad_hold(dev, BUTTONS.get(action, JOY_BUTTON_A), down)


## Move a stick on a party slot's pad (y DOWN positive).
func slot_stick(party: Node, slot: int, which: String, v: Vector2) -> void:
	var dev: int = party.device_of(slot)
	if dev >= 0:
		pad_stick(dev, which, v)


## Plug in a virtual pad and press A on it (drop-in join, like a person would). Returns the device.
func join_bot(party: Node) -> int:
	var dev: int = party.add_virtual_pad()
	pad_press(dev, JOY_BUTTON_A)
	return dev


# --- Fake VR (core/vr_rig.gd in fake mode) ----------------------------------------------------

## Put the head and hands at origin-local positions (head looks along -Z, hands point forward).
func vr_pose(rig: Node, head: Vector3, left: Vector3, right: Vector3) -> void:
	rig.camera.position = head
	rig.camera.basis = Basis()
	rig.hand_l.position = left
	rig.hand_l.basis = Basis()
	rig.hand_r.position = right
	rig.hand_r.basis = Basis()


## A relaxed idle: head bobbing slightly, hands swinging, so velocity / fit code sees movement.
func vr_idle(rig: Node, head_height: float = 1.6) -> void:
	var s := sin(t * 2.0)
	vr_pose(rig, Vector3(0.0, head_height + 0.01 * s, 0.0),
		Vector3(-0.25, head_height - 0.5 + 0.05 * s, -0.3), Vector3(0.25, head_height - 0.45 - 0.05 * s, -0.35))


## Move a hand towards a WORLD point at `speed` m/s; true once it is there.
func vr_reach(rig: Node, which: int, world_point: Vector3, speed: float, delta: float) -> bool:
	var h: Node3D = rig.hand(which)
	var local: Vector3 = (rig as Node3D).global_transform.affine_inverse() * world_point
	h.position = h.position.move_toward(local, speed * delta)
	return h.position.distance_to(local) < 0.005


## Turn the head to look at a WORLD point.
func vr_look_at(rig: Node, world_point: Vector3) -> void:
	var cam: Node3D = rig.camera
	var to := world_point - cam.global_position
	if to.length() > 0.01:
		cam.global_basis = Basis.looking_at(to.normalized(), Vector3.UP if absf(to.normalized().y) < 0.98 else Vector3.FORWARD)


## Pull the right trigger (0..1), press A, push the sticks (VR sticks: y UP positive).
func vr_trigger(rig: Node, value: float) -> void:
	rig.fake_trigger = value


## Hold or release the fake A button.
func vr_a(rig: Node, down: bool) -> void:
	rig.fake_a = down


## Push the fake thumbsticks (y UP = forward, like OpenXR).
func vr_stick(rig: Node, left: Vector2, right: Vector2 = Vector2.ZERO) -> void:
	rig.fake_stick_l = left
	rig.fake_stick_r = right


## Real head height in metres (e.g. 1.1 = someone sat down; the rig re-fits after a few seconds).
func vr_head_height(rig: Node, h: float) -> void:
	var cam: Node3D = rig.camera
	cam.position.y = h * float(rig.world_scale)
