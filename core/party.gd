extends Node
## PartyManager: who is playing on the TV, and with which controller.
##
## Owns the device -> player-slot mapping. Slot 0 is the VR / host player (not managed here unless
## `allow_slot0` is on, e.g. local play without a headset); slots 1..6 are TV players.
## - Drop-in: press A on a controller nobody owns (never Start: Start is the pause menu), or Space /
##   Enter on the keyboard (keyboard + mouse is a player too).
## - A controller that disconnects keeps its seat for `leave_after` seconds, then the player leaves.
##   Plugging it back in (Input.joy_connection_changed) restores the seat, even after leaving.
## - On the TV machine (net.mode == "client") joins are requested from the host, which confirms them;
##   on the host the TV machine's slots show up with device REMOTE. The roster survives scene reloads
##   (restart, reconnect, next game) through Engine metadata.
## - Per-slot input that reads only that slot's device: pressed / just_pressed / just_released,
##   stick, trigger, look, nav (menu navigation with key repeat). Buttons held when a player joins
##   or when the game unpauses must be released before they count (no accidental "accept").
## Usage:
##   const Party := preload("res://core/party.gd")
##   party = Party.new(); party.name = "Party"; add_child(party)   # main.party: the pause menu uses it
##   party.player_joined.connect(_on_joined); party.player_left.connect(_on_left)
##   if party.just_pressed(slot, "accept"): ...   var mv := party.stick(slot, "move")
## Bots: party.add_virtual_pad() -> device; press its buttons with party.inject_button() (or
## tests/bot_kit.gd); party.join_device(device) joins it directly.

## A player took a seat (device = pad id, KEYBOARD, or REMOTE on the host for TV-machine players).
signal player_joined(slot: int, device: int)
## A player left their seat (controller gone too long, leave(), or the TV machine disconnected).
signal player_left(slot: int)
## A join attempt failed: reason is "full", "closed" (joins not accepted now) or "refused" (join_filter).
signal join_refused(device: int, reason: String)
## A seated player's controller disconnected (they leave after `leave_after` s unless it comes back).
signal device_lost(slot: int)
## The controller came back in time.
signal device_restored(slot: int)

const MAX_SLOTS := 7
const NONE := -1
const KEYBOARD := -2
const REMOTE := -3
## Virtual (bot) pads get device ids from here up; tests treat ids below this as real hardware.
const VIRTUAL_PAD_BASE := 40
## Same palette as the existing games: P1 (VR) blue, P2 gold, P3 pink, P4 green, P5 white, P6 purple, P7 teal.
const COLORS: Array[Color] = [Color(0.3, 0.7, 1.0), Color(1.0, 0.75, 0.25), Color(1.0, 0.45, 0.85),
	Color(0.55, 1.0, 0.25), Color(0.95, 0.95, 1.0), Color(0.7, 0.45, 1.0), Color(0.25, 1.0, 0.85)]
## Engine metadata: the roster (survives scene reloads), virtual pads, and the bot "ignore real pads" flag.
const ROSTER_META := "core_party_roster"
const VIRTUAL_META := "core_party_virtual_pads"
const BOT_IGNORE_META := "bot_ignore_real_pads"
const REJOIN_WINDOW_MS := 600000  # a pad that left within 10 minutes rejoins its seat when plugged in

## Standard action names -> bit. "accept" = A, "back" = B; "dpad" matches any d-pad direction.
const ACTIONS := {
	"accept": 1, "a": 1, "back": 2, "b": 2, "x": 4, "y": 8, "lb": 16, "rb": 32, "lt": 64, "rt": 128,
	"start": 256, "select": 512, "l3": 1024, "r3": 2048,
	"up": 4096, "down": 8192, "left": 16384, "right": 32768, "dpad": 61440,
}
const _PAD_BUTTONS: Array[int] = [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y,
	JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_START, JOY_BUTTON_BACK,
	JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN,
	JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]
const _PAD_BITS: Array[int] = [1, 2, 4, 8, 16, 32, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768]
## Keyboard + mouse player: accept Space/Enter/left click, back Backspace/right click, x F, y R,
## lb Q, rb E, lt Shift, rt Ctrl, start Tab, select M, l3 V, d-pad = arrow keys, move = WASD, look = mouse.
const _KEYS: Array[int] = [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_BACKSPACE, KEY_F, KEY_R, KEY_Q, KEY_E,
	KEY_SHIFT, KEY_CTRL, KEY_TAB, KEY_M, KEY_V, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]
const _KEY_BITS: Array[int] = [1, 1, 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 4096, 8192, 16384, 32768]
const _JOIN_KEYS: Array[int] = [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]
const FREE := 0
const PENDING := 1
const ACTIVE := 2
## Steam Input's desktop layout can turn a pad's A into a key press: a keyboard join waits this
## long and is dropped if any pad button went down around it (no phantom keyboard players).
const KEYBOARD_JOIN_DELAY := 0.15

## Seconds a disconnected controller keeps its seat.
var leave_after := 20.0
## Keyboard + mouse may join (Space / Enter).
var allow_keyboard := true
## Slot 0 is joinable like a TV seat (local play without a headset: "P1" on the keyboard / a pad).
var allow_slot0 := false
## Highest slot a player can take (1..6).
var max_slot := 6
## Joins are processed at all (turn it off during a round; joiners get join_refused "closed").
var accept_joins := true
## Host / local: optional func(slot: int) -> bool deciding whether a join is allowed.
var join_filter: Callable
## At start, if nobody was restored, the first connected controller takes a seat by itself.
var auto_join_first_pad := true
## Radial dead zone for sticks.
var deadzone := 0.2
## Extra devices to ignore (e.g. a broken pad).
var ignored_devices: Array[int] = []
var main: Node
var net: Node

var _started := false
var _device := PackedInt32Array()
var _state := PackedInt32Array()
var _lost_t := PackedFloat32Array()
var _last_device := PackedInt32Array()
var _left_msec := PackedInt64Array()
var _pending_t := PackedFloat32Array()
var _names := PackedStringArray()
# Input masks for two contexts (0 = _process, 1 = _physics_process), MAX_SLOTS each.
var _now := PackedInt32Array()
var _prev := PackedInt32Array()
var _latch := PackedInt32Array()
var _guard := PackedInt32Array()
var _nav_dir: Array[Vector2i] = []
var _nav_out: Array[Vector2i] = []
var _nav_t := PackedFloat32Array()
var _nav_guard := PackedByteArray()
var _mouse_acc := Vector2.ZERO
var _mouse_frame := Vector2.ZERO
var _was_paused := false
var _net_hooked: Node
var _kb_join_t := -1.0
var _clock := 0.0  # game seconds (deterministic under --fixed-fps)
var _last_pad_t := -100.0


func _init() -> void:
	_device.resize(MAX_SLOTS)
	_device.fill(NONE)
	_state.resize(MAX_SLOTS)
	_lost_t.resize(MAX_SLOTS)
	_lost_t.fill(-1.0)
	_last_device.resize(MAX_SLOTS)
	_last_device.fill(NONE)
	_left_msec.resize(MAX_SLOTS)
	_pending_t.resize(MAX_SLOTS)
	_names.resize(MAX_SLOTS)
	_now.resize(MAX_SLOTS * 2)
	_prev.resize(MAX_SLOTS * 2)
	_latch.resize(MAX_SLOTS * 2)
	_guard.resize(MAX_SLOTS)
	_nav_t.resize(MAX_SLOTS)
	_nav_guard.resize(MAX_SLOTS)
	for i in MAX_SLOTS:
		_nav_dir.append(Vector2i.ZERO)
		_nav_out.append(Vector2i.ZERO)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # joins, timers and the unpause guard work while paused
	process_priority = -100  # sample input before the game's _process reads it
	process_physics_priority = -100
	if main == null:
		main = get_parent()
	if not Input.joy_connection_changed.is_connected(_on_joy_changed):
		Input.joy_connection_changed.connect(_on_joy_changed)
	_was_paused = get_tree().paused


# --- Roster ----------------------------------------------------------------------------

## The slot driven by `device` (pending or seated), or -1.
func owner_of(device: int) -> int:
	if device == NONE or device == REMOTE:
		return -1
	for s in MAX_SLOTS:
		if _state[s] != FREE and _device[s] == device:
			return s
	return -1


## The device driving `slot` (NONE if free, REMOTE on the host for TV-machine players).
func device_of(slot: int) -> int:
	if slot < 0 or slot >= MAX_SLOTS or _state[slot] == FREE:
		return NONE
	return _device[slot]


## Seated slots in ascending order (local and, on the host, remote ones). Lost-controller seats count.
func active_slots() -> Array[int]:
	var out: Array[int] = []
	for s in MAX_SLOTS:
		if _state[s] == ACTIVE:
			out.append(s)
	return out


## Seated slots driven by input on THIS machine (the ones that need a split-screen view here).
func local_slots() -> Array[int]:
	var out: Array[int] = []
	for s in MAX_SLOTS:
		if _state[s] == ACTIVE and _device[s] != REMOTE:
			out.append(s)
	return out


## How many seats are taken.
func player_count() -> int:
	return active_slots().size()


func is_active(slot: int) -> bool:
	return slot >= 0 and slot < MAX_SLOTS and _state[slot] == ACTIVE


## TV machine: asked the host, waiting for its answer.
func is_pending(slot: int) -> bool:
	return slot >= 0 and slot < MAX_SLOTS and _state[slot] == PENDING


## Seated and driven from this machine.
func is_local(slot: int) -> bool:
	return is_active(slot) and _device[slot] != REMOTE


## Host: seated and driven by the TV machine.
func is_remote(slot: int) -> bool:
	return is_active(slot) and _device[slot] == REMOTE


## Seated, but the controller is unplugged (they leave after leave_after seconds).
func is_lost(slot: int) -> bool:
	return is_active(slot) and _lost_t[slot] >= 0.0


## "P1".."P7", or the name given with set_player_name().
func name_of(slot: int) -> String:
	if slot >= 0 and slot < MAX_SLOTS and _names[slot] != "":
		return _names[slot]
	return "P%d" % (slot + 1)


func set_player_name(slot: int, player_name: String) -> void:
	if slot >= 0 and slot < MAX_SLOTS:
		_names[slot] = player_name


func color_of(slot: int) -> Color:
	return COLORS[posmod(slot, COLORS.size())]


## Human-readable device name for HUDs and logs.
static func device_label(device: int) -> String:
	if device == KEYBOARD:
		return "keyboard"
	if device == REMOTE:
		return "TV"
	if device == NONE:
		return "nobody"
	if device >= VIRTUAL_PAD_BASE:
		return "bot pad %d" % device
	return "pad %d" % device


## Seat `device` (a pad id or KEYBOARD) in `slot` (-1: its old seat, else the lowest free one).
## Local play: seated now. TV machine: asks the host (is_pending until it answers). Returns the
## slot, or -1 (join_refused tells why). Bots call this directly.
func join_device(device: int, slot: int = -1) -> int:
	var have := owner_of(device)
	if have >= 0:
		return have
	if _mode() == "host":
		return -1  # the headset has no TV controllers; TV players join from the TV machine
	if slot < 0 or not _slot_free(slot):
		slot = _free_slot(device)
	if slot < 0:
		join_refused.emit(device, "full")
		return -1
	if _mode() == "client":
		_state[slot] = PENDING
		_device[slot] = device
		_pending_t[slot] = 0.0
		_guard_slot(slot)
		_send_join(slot)
		print("Party: %s asks to join as %s" % [device_label(device), name_of(slot)])
		_persist()
		return slot
	if not accept_joins:
		join_refused.emit(device, "closed")
		return -1
	if join_filter.is_valid() and not bool(join_filter.call(slot)):
		join_refused.emit(device, "refused")
		return -1
	_seat(slot, device)
	return slot


## Free a seat (a player quits from a menu, or the game kicks them). Tells the other machine.
## allow_rejoin: plugging the same controller in again brings the player back (used when a
## controller stayed away too long); pressing A always works.
func leave(slot: int, allow_rejoin: bool = false) -> void:
	if slot < 0 or slot >= MAX_SLOTS or _state[slot] == FREE:
		return
	var was_active := _state[slot] == ACTIVE
	var dev := _device[slot]
	if _mode() == "client":
		_send(["leave", slot])
	elif _mode() == "host" and dev == REMOTE:
		_send(["left", slot])
	_unseat(slot)
	if dev >= 0 or dev == KEYBOARD:
		_last_device[slot] = dev  # pressing A on it again prefers this seat
		_left_msec[slot] = Time.get_ticks_msec() if allow_rejoin else -REJOIN_WINDOW_MS - 1
	if was_active:
		print("Party: %s left" % name_of(slot))
		player_left.emit(slot)
	_persist()


func _seat(slot: int, device: int) -> void:
	_state[slot] = ACTIVE
	_device[slot] = device
	_lost_t[slot] = -1.0
	_guard_slot(slot)
	print("Party: %s joined as %s" % [device_label(device), name_of(slot)])
	_persist()
	player_joined.emit(slot, device)


func _unseat(slot: int) -> void:
	_state[slot] = FREE
	_device[slot] = NONE
	_lost_t[slot] = -1.0
	for c in 2:
		_now[c * MAX_SLOTS + slot] = 0
		_prev[c * MAX_SLOTS + slot] = 0
		_latch[c * MAX_SLOTS + slot] = 0


func _slot_free(slot: int) -> bool:
	return slot >= _first_slot() and slot <= mini(max_slot, MAX_SLOTS - 1) and _state[slot] == FREE


func _first_slot() -> int:
	return 0 if allow_slot0 and _mode() != "client" else 1


## The device's previous seat if it's free, else the lowest free seat.
func _free_slot(device: int) -> int:
	for s in range(_first_slot(), mini(max_slot, MAX_SLOTS - 1) + 1):
		if _state[s] == FREE and _last_device[s] == device:
			return s
	for s in range(_first_slot(), mini(max_slot, MAX_SLOTS - 1) + 1):
		if _state[s] == FREE:
			return s
	return -1


# --- Devices ---------------------------------------------------------------------------

## Pads that can play: connected real pads (minus ignored ones) plus virtual bot pads.
func connected_pads() -> Array[int]:
	var out: Array[int] = []
	for d in Input.get_connected_joypads():
		if not _ignored(d):
			out.append(d)
	for d in _virtual_pads():
		if not out.has(d):
			out.append(d)
	return out


## Bot / test hook: plug in a virtual controller and return its device id (>= VIRTUAL_PAD_BASE).
## Its buttons and sticks are driven with inject_button() / inject_axis().
func add_virtual_pad() -> int:
	var pads := _virtual_pads()
	var id := VIRTUAL_PAD_BASE
	while pads.has(id) or Input.get_connected_joypads().has(id):
		id += 1
	pads.append(id)
	Engine.set_meta(VIRTUAL_META, pads)
	_on_joy_changed(id, true)
	return id


## Bot / test hook: unplug a virtual controller (as if its battery died).
func remove_virtual_pad(device: int) -> void:
	var pads := _virtual_pads()
	pads.erase(device)
	Engine.set_meta(VIRTUAL_META, pads)
	_on_joy_changed(device, false)


## Bot / test hook: re-plug a virtual controller that was removed.
func replug_virtual_pad(device: int) -> void:
	var pads := _virtual_pads()
	if not pads.has(device):
		pads.append(device)
		Engine.set_meta(VIRTUAL_META, pads)
	_on_joy_changed(device, true)


## Bot / test hook: press or release a button on any device through Godot's Input (like a real pad).
func inject_button(device: int, button: JoyButton, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	e.pressed = down
	Input.parse_input_event(e)


## Bot / test hook: move an axis (sticks: -1..1, triggers: 0..1) on any device.
func inject_axis(device: int, axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)


func _virtual_pads() -> Array[int]:
	var out: Array[int] = []
	var raw: Array = Engine.get_meta(VIRTUAL_META, [])
	for d in raw:
		out.append(int(d))
	return out


func _ignored(device: int) -> bool:
	if device < 0:
		return false
	if ignored_devices.has(device):
		return true
	return Engine.has_meta(BOT_IGNORE_META) and device < VIRTUAL_PAD_BASE


func _on_joy_changed(device: int, connected: bool) -> void:
	if _ignored(device) or not _started or _mode() == "host":
		return
	if connected:
		_on_pad_connected(device)
	else:
		_on_pad_disconnected(device)


func _on_pad_disconnected(device: int) -> void:
	var s := owner_of(device)
	if s < 0:
		return
	if _state[s] == PENDING:
		_unseat(s)
		_persist()
		return
	_lost_t[s] = 0.0
	print("Party: %s lost its controller (%s)" % [name_of(s), device_label(device)])
	device_lost.emit(s)
	_persist()


func _on_pad_connected(device: int) -> void:
	if owner_of(device) >= 0:
		var s0 := owner_of(device)
		if _lost_t[s0] >= 0.0:
			_restore_device(s0, device)
		return
	# 1. A seat waiting for exactly this controller, 2. any seat waiting for a lost controller.
	var pick := -1
	var oldest := -1.0
	for s in MAX_SLOTS:
		if is_active(s) and _lost_t[s] >= 0.0 and _lost_t[s] > oldest:
			oldest = _lost_t[s]
			pick = s
	if pick >= 0:
		_restore_device(pick, device)
		return
	# 3. The seat this controller left a while ago: plugging it back in brings the player back.
	for s in MAX_SLOTS:
		if _state[s] == FREE and _last_device[s] == device \
				and Time.get_ticks_msec() - _left_msec[s] < REJOIN_WINDOW_MS:
			join_device(device, s)
			return


func _restore_device(slot: int, device: int) -> void:
	_device[slot] = device
	_lost_t[slot] = -1.0
	_guard_slot(slot)
	print("Party: %s got a controller back (%s)" % [name_of(slot), device_label(device)])
	device_restored.emit(slot)
	_persist()


# --- Per-slot input ----------------------------------------------------------------------

## The action's button is held (and was pressed since the player joined / the game unpaused).
## Actions: accept/a, back/b, x, y, lb, rb, lt, rt, start, select, l3, r3, up/down/left/right, dpad.
func pressed(slot: int, action: String) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		return false
	var bit: int = ACTIONS.get(action, 0)
	var i := _ctx() * MAX_SLOTS + slot
	return (_now[i] & bit & ~_guard[slot]) != 0


## The action's button went down this frame (works in _process and _physics_process; quick taps
## between frames count too).
func just_pressed(slot: int, action: String) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		return false
	var bit: int = ACTIONS.get(action, 0)
	var i := _ctx() * MAX_SLOTS + slot
	return (_now[i] & ~_prev[i] & bit & ~_guard[slot]) != 0


## The action's button was let go this frame.
func just_released(slot: int, action: String) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		return false
	var bit: int = ACTIONS.get(action, 0)
	var i := _ctx() * MAX_SLOTS + slot
	return (_prev[i] & ~_now[i] & bit & ~_guard[slot]) != 0


## The lowest seated slot that just pressed `action` ("anyone press A to continue"), or -1.
func any_just_pressed(action: String) -> int:
	for s in MAX_SLOTS:
		if _state[s] == ACTIVE and just_pressed(s, action):
			return s
	return -1


## A stick as a Vector2 (x right, y DOWN, like Input.get_vector), dead zone applied, length <= 1.
## which: "move" (left stick / WASD), "look" (right stick; keyboard: zero, use look()), "dpad".
func stick(slot: int, which: String = "move") -> Vector2:
	var dev := device_of(slot)
	if dev == NONE or dev == REMOTE:
		return Vector2.ZERO
	var v := Vector2.ZERO
	match which:
		"move", "left_stick":
			if dev == KEYBOARD:
				v = Vector2(_key(KEY_D) - _key(KEY_A), _key(KEY_S) - _key(KEY_W))
			else:
				v = Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
		"look", "right_stick":
			if dev != KEYBOARD:
				v = Vector2(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y))
		"dpad":
			var m := _now[_ctx() * MAX_SLOTS + slot]
			v = Vector2(float((m & 32768) != 0) - float((m & 16384) != 0), float((m & 8192) != 0) - float((m & 4096) != 0))
			return v.limit_length(1.0)
	return _dead(v)


## Analog trigger 0..1: which = "lt" or "rt" (keyboard: Shift / Ctrl as 0 or 1).
func trigger(slot: int, which: String = "rt") -> float:
	var dev := device_of(slot)
	if dev == NONE or dev == REMOTE:
		return 0.0
	if dev == KEYBOARD:
		return 1.0 if pressed(slot, which) else 0.0
	return clampf(Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT if which == "lt" else JOY_AXIS_TRIGGER_RIGHT), 0.0, 1.0)


## How far to turn a camera this frame, in radians (x yaw, y pitch; y DOWN positive): the right
## stick times `speed` rad/s, or the keyboard player's mouse movement. Call from _process.
func look(slot: int, delta: float, speed: float = 2.6, mouse_sensitivity: float = 0.0025) -> Vector2:
	var dev := device_of(slot)
	if dev == KEYBOARD:
		return _mouse_frame * mouse_sensitivity
	return stick(slot, "look") * speed * delta


## Menu navigation for this frame: one step per press of the d-pad / left stick / arrows / WASD,
## repeating while held (0.4 s, then every 0.12 s). Vector2i(0, -1) is up. Call from _process.
func nav(slot: int) -> Vector2i:
	if slot < 0 or slot >= MAX_SLOTS:
		return Vector2i.ZERO
	return _nav_out[slot]


## Rumble a slot's controller (weak/strong 0..1).
func rumble(slot: int, weak: float, strong: float, duration: float = 0.15) -> void:
	var dev := device_of(slot)
	if dev >= 0 and dev < VIRTUAL_PAD_BASE:
		Input.start_joy_vibration(dev, weak, strong, duration)


## Buttons held right now on `slot` must be released before they count (e.g. after a screen change).
func guard(slot: int) -> void:
	if slot >= 0 and slot < MAX_SLOTS:
		_guard_slot(slot)


func guard_all() -> void:
	for s in MAX_SLOTS:
		_guard_slot(s)


func _guard_slot(slot: int) -> void:
	var dev := _device[slot]
	var held := 0
	if dev != NONE and dev != REMOTE:
		held = _poll(dev)
	var g := held
	if _state[slot] == PENDING or (dev >= 0 and Input.is_joy_button_pressed(dev, JOY_BUTTON_A)):
		g |= 1  # the A press that joined must not also "accept" in the game
	_guard[slot] = g
	for c in 2:
		_latch[c * MAX_SLOTS + slot] = 0
		_now[c * MAX_SLOTS + slot] = held
		_prev[c * MAX_SLOTS + slot] = held
	_nav_guard[slot] = 1


func _ctx() -> int:
	return 1 if Engine.is_in_physics_frame() else 0


func _dead(v: Vector2) -> Vector2:
	var l := v.length()
	if l < deadzone:
		return Vector2.ZERO
	return v / l * minf(1.0, (l - deadzone) / (1.0 - deadzone))


func _key(k: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(k) else 0.0


func _poll(dev: int) -> int:
	var m := 0
	if dev == KEYBOARD:
		for i in _KEYS.size():
			if Input.is_physical_key_pressed(_KEYS[i] as Key):
				m |= _KEY_BITS[i]
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			m |= 1
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			m |= 2
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			m |= 2048
		return m
	if dev < 0:
		return 0
	for i in _PAD_BUTTONS.size():
		if Input.is_joy_button_pressed(dev, _PAD_BUTTONS[i] as JoyButton):
			m |= _PAD_BITS[i]
	if Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT) > 0.5:
		m |= 64
	if Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT) > 0.5:
		m |= 128
	return m


func _roll(c: int) -> void:
	for s in MAX_SLOTS:
		var i := c * MAX_SLOTS + s
		var held := 0
		if _state[s] != FREE:
			var dev := _device[s]
			if dev != NONE and dev != REMOTE and _lost_t[s] < 0.0:
				held = _poll(dev)
		_prev[i] = _now[i]
		_now[i] = held | _latch[i]
		_latch[i] = 0
		_guard[s] &= held


func _update_nav(delta: float) -> void:
	for s in MAX_SLOTS:
		_nav_out[s] = Vector2i.ZERO
		if _state[s] == FREE:
			continue
		var m := _now[s] & ~_guard[s]
		var v := Vector2(float((m & 32768) != 0) - float((m & 16384) != 0), float((m & 8192) != 0) - float((m & 4096) != 0))
		var st := stick(s, "move")
		if st.length() > 0.55:
			v += st
		var d := Vector2i.ZERO
		if absf(v.x) > absf(v.y) and absf(v.x) > 0.1:
			d = Vector2i(int(signf(v.x)), 0)
		elif absf(v.y) > 0.1:
			d = Vector2i(0, int(signf(v.y)))
		if d == Vector2i.ZERO:
			_nav_guard[s] = 0
		elif _nav_guard[s] != 0:
			d = Vector2i.ZERO  # held since join / unpause: wait for neutral
		if d != _nav_dir[s]:
			_nav_dir[s] = d
			_nav_t[s] = 0.4
			_nav_out[s] = d
		elif d != Vector2i.ZERO:
			_nav_t[s] -= delta
			if _nav_t[s] <= 0.0:
				_nav_t[s] = 0.12
				_nav_out[s] = d


# --- Frame upkeep ------------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	_try_start()
	var paused := get_tree().paused
	if paused != _was_paused:
		_was_paused = paused
		guard_all()  # buttons held across a pause / unpause must be released first
	_roll(0)
	_mouse_frame = _mouse_acc
	_mouse_acc = Vector2.ZERO
	_update_nav(delta)
	if not _started:
		return
	_hook_net()
	if _kb_join_t >= 0.0:
		_kb_join_t -= delta
		if _kb_join_t < 0.0 and _can_join_now() and owner_of(KEYBOARD) < 0:
			join_device(KEYBOARD)
	if not paused:
		for s in MAX_SLOTS:
			if _state[s] == ACTIVE and _lost_t[s] >= 0.0:
				_lost_t[s] += delta
				if _lost_t[s] > leave_after:
					print("Party: %s's controller stayed away %.0f s" % [name_of(s), leave_after])
					leave(s, true)
	if _mode() == "client":
		for s in MAX_SLOTS:
			if _state[s] == PENDING:
				_pending_t[s] += delta
				if _pending_t[s] > 1.0:
					_pending_t[s] = 0.0
					_send_join(s)  # retried until the host answers


func _physics_process(_delta: float) -> void:
	_roll(1)


func _input(event: InputEvent) -> void:
	var jb := event as InputEventJoypadButton
	if jb != null:
		if not jb.pressed:
			return
		_last_pad_t = _clock
		_kb_join_t = -1.0  # that "key" was probably this pad (Steam desktop layout)
		if _ignored(jb.device):
			return
		var s := owner_of(jb.device)
		if s >= 0:
			_latch_button(s, jb.button_index)
			return
		if jb.button_index == JOY_BUTTON_A and _can_join_now():
			if join_device(jb.device) >= 0:
				get_viewport().set_input_as_handled()
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		if owner_of(KEYBOARD) >= 0:
			_mouse_acc += mm.relative
		return
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo:
		var ks := owner_of(KEYBOARD)
		if ks >= 0:
			var idx := _KEYS.find(int(k.physical_keycode))
			if idx >= 0:
				for c in 2:
					_latch[c * MAX_SLOTS + ks] |= _KEY_BITS[idx]
			return
		if allow_keyboard and _JOIN_KEYS.has(int(k.physical_keycode)) and _can_join_now() \
				and _clock - _last_pad_t > KEYBOARD_JOIN_DELAY:
			_kb_join_t = KEYBOARD_JOIN_DELAY
			get_viewport().set_input_as_handled()
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		var ms := owner_of(KEYBOARD)
		if ms >= 0:
			var bit := 1 if mb.button_index == MOUSE_BUTTON_LEFT else (2 if mb.button_index == MOUSE_BUTTON_RIGHT else 0)
			for c in 2:
				_latch[c * MAX_SLOTS + ms] |= bit


func _latch_button(slot: int, button: int) -> void:
	var idx := _PAD_BUTTONS.find(button)
	if idx < 0:
		return
	for c in 2:
		_latch[c * MAX_SLOTS + slot] |= _PAD_BITS[idx]


func _can_join_now() -> bool:
	return _started and accept_joins and not get_tree().paused and _mode() != "host"


func _mode() -> String:
	var n := _net()
	return str(n.mode) if n != null else "local"


func _net() -> Node:
	if net != null and is_instance_valid(net):
		return net
	if main != null and is_instance_valid(main):
		var n = main.get("net")
		if n is Node:
			net = n
			return net
	return null


## Starts once the game is set up (main.ready_to_play) and the TV machine is connected.
func _try_start() -> void:
	if _started:
		return
	var n := _net()
	if n != null and str(n.mode) == "client" and not bool(n.connected):
		return
	if main != null and is_instance_valid(main):
		var r = main.get("ready_to_play")
		if typeof(r) == TYPE_BOOL and not r:
			return
	_started = true
	_hook_net()
	if _mode() != "host":
		_restore()
		if auto_join_first_pad and local_slots().is_empty() and not _any_pending():
			var pads := connected_pads()
			if not pads.is_empty():
				join_device(pads[0])


func _any_pending() -> bool:
	for s in MAX_SLOTS:
		if _state[s] == PENDING:
			return true
	return false


# --- Network (TV machine asks, host confirms) ------------------------------------------

func _hook_net() -> void:
	var n := _net()
	if n == null or n == _net_hooked or not n.has_method("add_sys_handler"):
		return
	_net_hooked = n
	n.add_sys_handler("party", _on_party_msg)
	if not n.client_disconnected.is_connected(_on_client_gone):
		n.client_disconnected.connect(_on_client_gone)


func _send(args: Array) -> void:
	var n := _net()
	if n != null and n.has_method("sys_send"):
		n.sys_send("party", args)


func _send_join(slot: int) -> void:
	_send(["join", slot, _names[slot]])


func _on_party_msg(args: Array) -> void:
	if args.size() < 2:
		return
	var op := str(args[0])
	var slot := int(args[1])
	if slot < 0 or slot >= MAX_SLOTS:
		return
	if _mode() == "host":
		match op:
			"join":
				_host_join(slot, str(args[2]) if args.size() > 2 else "")
			"leave":
				if _state[slot] == ACTIVE and _device[slot] == REMOTE:
					_unseat(slot)
					print("Party: %s (TV) left" % name_of(slot))
					player_left.emit(slot)
		return
	match op:
		"ok":
			if _state[slot] == PENDING:
				_seat(slot, _device[slot])
		"no":
			if _state[slot] == PENDING:
				var dev := _device[slot]
				_unseat(slot)
				_persist()
				join_refused.emit(dev, str(args[2]) if args.size() > 2 else "refused")
		"left":
			if _state[slot] != FREE:
				var dev2 := _device[slot]
				_unseat(slot)
				_last_device[slot] = dev2
				_left_msec[slot] = -REJOIN_WINDOW_MS - 1  # removed by the host: no automatic rejoin
				_persist()
				player_left.emit(slot)


func _host_join(slot: int, player_name: String) -> void:
	if _state[slot] == ACTIVE and _device[slot] == REMOTE:
		_send(["ok", slot])  # a retry: they missed our answer
		return
	if slot < 1 or slot > mini(max_slot, MAX_SLOTS - 1) or _state[slot] != FREE:
		_send(["no", slot, "full"])
		return
	if not accept_joins:
		_send(["no", slot, "closed"])
		return
	if join_filter.is_valid() and not bool(join_filter.call(slot)):
		_send(["no", slot, "refused"])
		return
	if player_name != "":
		_names[slot] = player_name
	_send(["ok", slot])
	_seat(slot, REMOTE)


## Host: the TV machine went away; its players leave (it re-joins them when it reconnects).
func _on_client_gone() -> void:
	for s in MAX_SLOTS:
		if _state[s] == ACTIVE and _device[s] == REMOTE:
			_unseat(s)
			player_left.emit(s)


# --- Persistence across scene reloads ----------------------------------------------------

func _persist() -> void:
	if _mode() == "host":
		return
	var slots: Array = []
	for s in MAX_SLOTS:
		if _state[s] != FREE:
			slots.append([s, _device[s]])
	Engine.set_meta(ROSTER_META, {"slots": slots, "names": _names.duplicate()})


func _restore() -> void:
	var saved: Dictionary = Engine.get_meta(ROSTER_META, {})
	var slots: Array = saved.get("slots", [])
	var names: PackedStringArray = saved.get("names", PackedStringArray())
	var pads := connected_pads()
	for entry in slots:
		var e: Array = entry
		var slot: int = int(e[0])
		var dev: int = int(e[1])
		if dev == KEYBOARD and not allow_keyboard:
			continue
		if dev != KEYBOARD and not pads.has(dev):
			continue
		if slot < names.size() and names[slot] != "":
			_names[slot] = names[slot]
		join_device(dev, slot)
