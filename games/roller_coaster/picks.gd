extends "res://core/pick_flow.gd"
## COASTER CREW PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), after the practice ride.
##   "gift"  BUTTONS' TRACK GIFTS before every ride from the third: three of BOOSTER, CORKSCREW, SPLASH, RAINBOW,
##           BIG STARS (deep.gd offer).
## Picking never stops the building: three giant glass orbs float over the near edge of the table at the VR builder's
## arm's reach (deep.gd row, main.gd space: they stay put while the table turns). The VR builder REACHES into one on
## purpose (a hand moves in after they pop up and stays DWELL s - a hand already resting there or swinging through never
## picks). The pad builder and the riders press X / A / B: each screen shows the three pictures over the buttons in the
## order the orbs stand on THAT screen (the riders' cameras circle the park). Nobody in time - or the lever is pulled -
## takes the middle orb (it glows brightest): a lone player is never stuck.
## Networked through the state store: "orbs" [serial, stage, entries] and "take" [serial, i, slot] (a machine joining
## mid-pick sees the orbs too); a TV machine sends the request "pick" [orb index].

const Deep := preload("res://games/roller_coaster/deep.gd")
const VrRig := preload("res://core/vr_rig.gd")

const BUTTONS: Array[String] = ["X", "A", "B"]
const PRESS: Array[String] = ["x", "accept", "back"]

var serial := 0
var shown_serial := -1  # every machine: the orbs showing
var shown_stage := ""
var shown_entries: Array = []
var taken_serial := -1
var strips := {}  # hud key -> [Control, order]


func _init() -> void:
	after = 1.2
	hand_r = Deep.HAND_R
	hand_dwell = Deep.DWELL
	sync = "state"


func showing() -> bool:
	return shown_stage != ""


## Host / local: put up the orbs (net state "orbs" [serial, stage, entries]; every machine shows them in sync_state).
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	start(new_stage, opts, done)
	serial += 1
	publish([serial, new_stage, entries])


func publish(payload: Array) -> void:
	super(payload)
	sync_state()


func orbs_off() -> Array:
	return [serial, "", []]


func closed() -> void:
	pass  # (the orbs go in sync_state from the published state)


## Every machine: show the orbs and the take from net state ("orbs" [serial, stage, entries], "take" [serial, i, slot]).
func sync_state(again: bool = false) -> void:
	if again:
		shown_serial = -1
	var o: Array = main.net.state_get("orbs", [])
	var s := int(o[0]) if o.size() >= 3 else 0
	if s != shown_serial:
		shown_serial = s
		taken_serial = -1
		show_row(String(o[1]) if o.size() >= 3 else "", o[2] if o.size() >= 3 else [])
	var tk: Array = main.net.state_get("take", [])
	if tk.size() >= 3 and int(tk[0]) == shown_serial and shown_stage != "" and taken_serial != shown_serial:
		taken_serial = shown_serial
		take_fx(int(tk[1]), int(tk[2]))


func show_row(new_stage: String, entries: Array) -> void:
	shown_stage = new_stage
	shown_entries = entries.duplicate(true)
	_clear_strips()
	if new_stage == "" or entries.is_empty():
		orbs.clear()
		return
	main.clear_banners()
	if not main.vr_builder_here():
		orbs.clear()  # no giant at the table: the screens' pictures are the picks (giant orbs would fill a TV view)
		return
	orbs.show_orbs(new_stage, entries, Deep.ROW_AT, Deep.ROW_GAP, 0.0, {"at": Deep.row(entries.size()), "scale": Deep.ORB_SCALE,
		"pop": true, "font": 64, "label_y": 1.3, "label_px": 0.0052, "two_lines": true, "bob": 0.04, "dot_size": 0.18})


func wait_for() -> float:
	return Deep.wait_for(stage, main.pick_solo())


func _cam_of(key: int) -> Camera3D:
	if main.cams.has(key) and is_instance_valid(main.cams[key]):
		return main.cams[key]
	if main.split != null:
		return main.split.shared_camera()
	return null


## Orb indices left to right as screen `key` sees them (its buttons X A B).
func order_for(key: int) -> Array:
	var right := Vector3.RIGHT
	var cam := _cam_of(key)
	if cam != null and cam.is_inside_tree():
		right = cam.global_transform.basis.x
	return order_along(Deep.row(shown_entries.size()), right)


## Every machine: a local player pressed X / A / B: ask the host for that orb (true: a pick button was pressed).
func local_press(slot: int) -> bool:
	if shown_stage == "" or taken_serial == shown_serial:
		return false
	for k in PRESS.size():
		if main.party.just_pressed(slot, PRESS[k]):
			var ord := order_for(slot)
			if k < ord.size():
				main.net.request(slot, "pick", [int(ord[k]), shown_serial])
			return true
	return false


## Host: slot asked for orb i of pick for_serial.
func press(slot: int, i: int, for_serial: int) -> void:
	if for_serial == serial and can_take():
		take(i, slot)


## Host: decide now (the round must go on): the middle one if nobody chose, and the orbs go.
func settle_now() -> void:
	if stage == "":
		return
	if chosen < 0:
		take(default_pick(), -1)
	_finish()


## The VR builder's hands reaching into an orb (not while riding; carrying a piece through one is never a pick).
func takers() -> Dictionary:
	var rig = main.vr_rig
	if rig == null or main.builder == null or main.builder.riding:
		return {}
	var points := {}
	for h in [VrRig.LEFT, VrRig.RIGHT]:
		if h == VrRig.RIGHT and not (main.builder.held as Dictionary).is_empty():
			continue
		points["h%d" % h] = [rig.hand_point(h), 0, "hand"]
	return points


func send_take(i: int, slot: int) -> void:
	main.net.state_set("take", [serial, i, slot])
	sync_state()


func take_fx(i: int, slot: int) -> void:
	super(i, slot)
	for key in strips:
		dim_strip((strips[key] as Array)[0], i)


func fx(i: int, _slot: int, _at: Vector3, _col: Color) -> void:
	main.sound("ready", -4.0, 1.2 + 0.1 * i)
	if taker.begins_with("h") and main.vr_rig != null:
		main.vr_rig.pulse(int(taker.substr(1)), 0.7, 0.08)


# --- The pictures on every local screen ---------------------------------------------------------------------

func _process(_delta: float) -> void:
	if showing():
		_update_strips()
	elif not strips.is_empty():
		_clear_strips()


func _update_strips() -> void:
	var want := {}
	var locals: Array = main.party.local_slots()
	for key in main.huds:
		var h: Control = main.huds[key]
		if not is_instance_valid(h) or not h.is_visible_in_tree():
			continue
		if int(key) >= 0 and locals.has(int(key)):
			want[int(key)] = h
		elif int(key) < 0 and locals.is_empty():
			want[-1] = h  # nobody here plays: the pictures alone
	for key in strips.keys():
		var s: Array = strips[key]
		var gone: bool = not want.has(key) or not is_instance_valid(s[0])
		if not gone and str(order_for(int(key))) != str(s[1]):
			gone = true  # this screen's camera swung round: the pictures follow the orbs
		if gone:
			if is_instance_valid(s[0]):
				(s[0] as Node).queue_free()
			strips.erase(key)
	for key in want:
		if not strips.has(key):
			var ord := order_for(int(key))
			var box := strip(shown_entries, ord, BUTTONS if int(key) >= 0 else [])
			(want[key] as Control).add_child(box)
			if taken_serial == shown_serial:
				var tk: Array = main.net.state_get("take", [])
				if tk.size() >= 3:
					dim_strip(box, int(tk[1]))
			strips[key] = [box, ord]
		layout_strip(want[key], (strips[key] as Array)[0])


func _clear_strips() -> void:
	for key in strips:
		var s: Array = strips[key]
		if is_instance_valid(s[0]):
			(s[0] as Node).queue_free()
	strips.clear()
