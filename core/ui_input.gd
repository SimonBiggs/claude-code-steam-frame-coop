extends RefCounted
## Per-player UI input: polls ONE player's controller, key set and/or VR hand and turns it into UI
## actions ("up", "down", "left", "right", "confirm", "cancel", "tab_prev", "tab_next") with key repeat.
## Used by menus, dialogue, hint cards and results screens so six players can each drive their own UI.
##
##   const UiInput := preload("res://core/ui_input.gd")
##   var input := UiInput.new(joy_device, UiInput.KEYS_NONE)   # or (UiInput.PAD_ANY, UiInput.KEYS_ALL)
##   input.latch()                        # ignore the A that is still held from the previous screen
##   for action in input.poll(delta): ... # in _process
##
## Polling (not _input) means it works in split-screen SubViewports, while paused (if the owner
## processes) and with Input.parse_input_event from bots. Call note_event(ev) from _input so PAD_ANY
## also hears controllers that Input.get_connected_joypads() doesn't list (bots' fake pads).

const PAD_NONE := -1   ## no controller
const PAD_ANY := -2    ## any controller
const KEYS_NONE := -1  ## no keyboard
const KEYS_WASD := 0   ## WASD move, Space/F confirm, X/Backspace back, Q/E tabs
const KEYS_ARROWS := 1 ## arrows move, Enter confirm, Backspace/Delete back, PageUp/PageDown tabs
const KEYS_ALL := 2    ## both sets

## Physical keys per key set and action.
const KEYMAP := {
	0: {"up": [KEY_W], "down": [KEY_S], "left": [KEY_A], "right": [KEY_D], "confirm": [KEY_SPACE, KEY_F],
		"cancel": [KEY_X, KEY_BACKSPACE], "tab_prev": [KEY_Q], "tab_next": [KEY_E]},
	1: {"up": [KEY_UP], "down": [KEY_DOWN], "left": [KEY_LEFT], "right": [KEY_RIGHT], "confirm": [KEY_ENTER, KEY_KP_ENTER],
		"cancel": [KEY_BACKSPACE, KEY_DELETE], "tab_prev": [KEY_PAGEUP], "tab_next": [KEY_PAGEDOWN]},
}
const ACTIONS: Array[String] = ["up", "down", "left", "right", "confirm", "cancel", "tab_prev", "tab_next"]
const DIRECTIONS: Array[String] = ["up", "down", "left", "right"]

var device := PAD_NONE    ## joypad id, PAD_ANY or PAD_NONE
var keys := KEYS_ALL      ## key set, or KEYS_NONE
var hand: Node3D = null   ## optional VR hand (XRController3D, or a fake Node3D with metas): trigger / A
                          ## = confirm, B = cancel, stick up/down = up/down
var repeat_delay := 0.38  ## seconds before a held direction repeats
var repeat_rate := 0.1    ## seconds between repeats
var _held := {}
var _latched := {}
var _repeat := {}
var _seen_pads := {}


func _init(p_device: int = PAD_NONE, p_keys: int = KEYS_ALL, p_hand: Node3D = null) -> void:
	device = p_device
	keys = p_keys
	hand = p_hand


## Ignore everything currently held until it is released.
func latch() -> void:
	var now := state()
	for a in now:
		if bool(now[a]):
			_latched[a] = true
	_held = now


## Feed input events so PAD_ANY also hears fake/remapped controllers (call from the owner's _input).
func note_event(ev: InputEvent) -> void:
	if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
		_seen_pads[ev.device] = true


## Is an action held right now (and not latched)? E.g. hold-to-skip.
func held(action: String) -> bool:
	return bool(state().get(action, false)) and not _latched.has(action)


## Current raw state of every action: {action: bool}.
func state() -> Dictionary:
	var s := {}
	for a in ACTIONS:
		s[a] = false
	if keys >= 0:
		var sets: Array = [0, 1] if keys == KEYS_ALL else [keys]
		for set_i in sets:
			var km: Dictionary = KEYMAP[set_i]
			for a in km:
				for k in km[a]:
					if Input.is_physical_key_pressed(k):
						s[a] = true
	if device >= 0:
		_pad_state(device, s)
	elif device == PAD_ANY:
		var pads: Array[int] = Input.get_connected_joypads()
		for d in _seen_pads:
			if not pads.has(int(d)):
				pads.append(int(d))
		for d in pads:
			_pad_state(d, s)
	if hand != null and is_instance_valid(hand):
		if hand_float("trigger") > 0.6 or hand_bool("ax_button"):
			s["confirm"] = true
		if hand_bool("by_button"):
			s["cancel"] = true
		var v := hand_vec("primary")
		if v.y > 0.6:
			s["up"] = true
		elif v.y < -0.6:
			s["down"] = true
	return s


func _pad_state(d: int, s: Dictionary) -> void:
	var ly := Input.get_joy_axis(d, JOY_AXIS_LEFT_Y)
	var lx := Input.get_joy_axis(d, JOY_AXIS_LEFT_X)
	if Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_UP) or ly < -0.55:
		s["up"] = true
	if Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_DOWN) or ly > 0.55:
		s["down"] = true
	if Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT) or lx < -0.55:
		s["left"] = true
	if Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT) or lx > 0.55:
		s["right"] = true
	if Input.is_joy_button_pressed(d, JOY_BUTTON_A):
		s["confirm"] = true
	if Input.is_joy_button_pressed(d, JOY_BUTTON_B):
		s["cancel"] = true
	if Input.is_joy_button_pressed(d, JOY_BUTTON_LEFT_SHOULDER):
		s["tab_prev"] = true
	if Input.is_joy_button_pressed(d, JOY_BUTTON_RIGHT_SHOULDER):
		s["tab_next"] = true


## A float action of the VR hand ("trigger"); fake hands use node metadata of the same name.
func hand_float(n: String) -> float:
	if hand == null or not is_instance_valid(hand):
		return 0.0
	if hand is XRController3D:
		return (hand as XRController3D).get_float(n)
	return float(hand.get_meta(n, 0.0))


## A button of the VR hand ("ax_button", "by_button"); fake hands use metadata.
func hand_bool(n: String) -> bool:
	if hand == null or not is_instance_valid(hand):
		return false
	if hand is XRController3D:
		return (hand as XRController3D).is_button_pressed(n)
	return bool(hand.get_meta(n, false))


## A Vector2 action of the VR hand ("primary" stick); fake hands use metadata.
func hand_vec(n: String) -> Vector2:
	if hand == null or not is_instance_valid(hand):
		return Vector2.ZERO
	if hand is XRController3D:
		return (hand as XRController3D).get_vector2(n)
	var v: Variant = hand.get_meta(n, Vector2.ZERO)
	return v if v is Vector2 else Vector2.ZERO


## Actions fired this frame: fresh presses, plus repeats for held directions.
func poll(delta: float) -> PackedStringArray:
	var out := PackedStringArray()
	var now := state()
	for a in ACTIONS:
		var down: bool = now[a]
		if _latched.has(a):
			if not down:
				_latched.erase(a)
			continue
		var was: bool = _held.get(a, false)
		if down and not was:
			out.append(a)
			_repeat[a] = repeat_delay
		elif down and DIRECTIONS.has(a):
			var t: float = float(_repeat.get(a, repeat_delay)) - delta
			if t <= 0.0:
				out.append(a)
				t = repeat_rate
			_repeat[a] = t
	_held = now
	return out


## Prompt glyph names for this input ("A"/"B" for pads, key names for keyboards).
func glyphs() -> Dictionary:
	var pad := device != PAD_NONE or keys == KEYS_NONE
	if pad:
		return {"confirm": "A", "cancel": "B", "tab_prev": "LB", "tab_next": "RB"}
	if keys == KEYS_ARROWS:
		return {"confirm": "ENTER", "cancel": "BKSP", "tab_prev": "PGUP", "tab_next": "PGDN"}
	return {"confirm": "SPACE", "cancel": "X", "tab_prev": "Q", "tab_next": "E"}
