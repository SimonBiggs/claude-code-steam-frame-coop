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
##   var input := UiInput.for_party(party, slot)            # a core/party.gd seat (pad or keyboard)
##   var vr_input := UiInput.for_rig(vr_rig)                 # the VR player via core/vr_rig.gd
##
## Polling (not _input) means it works in split-screen SubViewports, while paused (if the owner
## processes) and with Input.parse_input_event from bots. Call note_event(ev) from _input so PAD_ANY
## also hears controllers that Input.get_connected_joypads() doesn't list (bots' fake pads).

const Me := preload("res://core/ui_input.gd")

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

var party: Node = null    ## core/party.gd PartyManager: read `slot`'s buttons through it (see for_party)
var slot := -1            ## the party slot
var rig: Node = null      ## core/vr_rig.gd VrRig: guarded trigger / A and the right stick (see for_rig)
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


## A reader for one party seat (core/party.gd): its pad or keyboard, with the party's guards (buttons
## held when the player joined or the game unpaused don't count). Remote seats read as idle.
## slot -1 = any seat played on this machine (party.local_slots()).
static func for_party(p_party: Node, p_slot: int) -> Me:
	var r: Me = Me.new(PAD_NONE, KEYS_NONE)
	r.party = p_party
	r.slot = p_slot
	return r


## A reader for the VR player (core/vr_rig.gd): the rig's guarded trigger / A confirm, the right stick
## moves up/down, and `hand` becomes the rig's right hand (for pointing).
static func for_rig(p_rig: Node) -> Me:
	var r: Me = Me.new(PAD_NONE, KEYS_NONE)
	r.bind_rig(p_rig)
	return r


## Switch this reader to a party seat (slot -1 = any local seat). Also usable together with bind_rig
## (e.g. dialogue that anyone - TV or VR - can advance).
func bind_party(p_party: Node, p_slot: int) -> void:
	party = p_party
	slot = p_slot
	device = PAD_NONE
	keys = KEYS_NONE


## Switch this reader to the VR rig.
func bind_rig(p_rig: Node) -> void:
	rig = p_rig
	hand = p_rig.get("hand_r") if p_rig != null else null
	device = PAD_NONE
	keys = KEYS_NONE


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
	if party != null and is_instance_valid(party):
		var seats: Array = [slot] if slot >= 0 else party.call("local_slots")
		for seat in seats:
			_party_state(int(seat), s)
	if (hand != null and is_instance_valid(hand)) or (rig != null and is_instance_valid(rig)):
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


func _party_state(seat: int, s: Dictionary) -> void:
	var pairs := {"confirm": "accept", "cancel": "back", "tab_prev": "lb", "tab_next": "rb",
		"up": "up", "down": "down", "left": "left", "right": "right"}
	for a in pairs:
		if bool(party.call("pressed", seat, pairs[a])):
			s[a] = true
	var mv: Vector2 = party.call("stick", seat, "move")  # y DOWN, like pads
	if mv.y < -0.55:
		s["up"] = true
	elif mv.y > 0.55:
		s["down"] = true
	if mv.x < -0.55:
		s["left"] = true
	elif mv.x > 0.55:
		s["right"] = true


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


## A float action of the VR hand ("trigger"); fake hands use node metadata of the same name; with a
## rig, the trigger counts only when the rig's guard allows it.
func hand_float(n: String) -> float:
	if rig != null and is_instance_valid(rig):
		if n == "trigger" and bool(rig.call("trigger_down")):
			return maxf(0.61, float(rig.call("trigger_value")))
		return 0.0
	if hand == null or not is_instance_valid(hand):
		return 0.0
	if hand is XRController3D:
		return (hand as XRController3D).get_float(n)
	return float(hand.get_meta(n, 0.0))


## A button of the VR hand ("ax_button", "by_button"); fake hands use metadata; with a rig, A is the
## rig's guarded A (the Steam Frame has no B).
func hand_bool(n: String) -> bool:
	if rig != null and is_instance_valid(rig):
		return n == "ax_button" and bool(rig.call("a_down"))
	if hand == null or not is_instance_valid(hand):
		return false
	if hand is XRController3D:
		return (hand as XRController3D).is_button_pressed(n)
	return bool(hand.get_meta(n, false))


## A Vector2 action of the VR hand ("primary" stick, y UP); fake hands use metadata; with a rig, its
## right stick.
func hand_vec(n: String) -> Vector2:
	if rig != null and is_instance_valid(rig):
		var v2: Vector2 = rig.call("stick_right")
		return v2 if n == "primary" else Vector2.ZERO
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
	if party != null and is_instance_valid(party):
		if slot >= 0 and int(party.call("device_of", slot)) == -2:  # Party.KEYBOARD
			return {"confirm": "SPACE", "cancel": "BKSP", "tab_prev": "Q", "tab_next": "E"}
		return {"confirm": "A", "cancel": "B", "tab_prev": "LB", "tab_next": "RB"}
	if rig != null:
		return {"confirm": "TRIGGER", "cancel": "B", "tab_prev": "LB", "tab_next": "RB"}
	var pad := device != PAD_NONE or keys == KEYS_NONE
	if pad:
		return {"confirm": "A", "cancel": "B", "tab_prev": "LB", "tab_next": "RB"}
	if keys == KEYS_ARROWS:
		return {"confirm": "ENTER", "cancel": "BKSP", "tab_prev": "PGUP", "tab_next": "PGDN"}
	return {"confirm": "SPACE", "cancel": "X", "tab_prev": "Q", "tab_next": "E"}
