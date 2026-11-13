extends "res://core/pick_flow.gd"
## BALLOON POP PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (skies.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session, after the practice balloons (the family's last mode in the middle).
##   "gift"  POPPY'S GIFTS before every round: three of DART, PUMP, SLOW, MAGNET, POP POP (skies.gd gift_choices).
## Three glass orbs float in a row in the park between the VR player and the middle, at chest height. A TV player
## runs into one, the VR player touches one with a glove; the first one decides for the team (a dot in their colour
## circles it). Nobody in time? The middle orb (it glows brightest) is taken - a solo VR player or a little one is
## never stuck. Host / local decide; the host sends the sticky "orbs" event [stage, entries] (a machine joining
## mid-pick sees the orbs too) and "take" [i, slot]; every machine draws.

const VrRig := preload("res://core/vr_rig.gd")

const WAIT := {"mode": 14.0, "gift": 10.0}
## The row: in front of the VR player's spot (wavegen.gd VR_HOME (0, 2)), between them and the middle.
const ROW := Vector3(0.0, 0.0, 0.75)  # 1.25 m ahead of the VR player: all three in view at once
const GAP := 1.0
const Y := 1.15
const SCALE := 0.5  # glass ball radius 0.3 m: a balloon's size
const TV_R := 0.45  # flat distance from an orb's middle a TV player must run to
const HAND_R := 0.12


func _init() -> void:
	after = 1.0
	waits = WAIT
	wait_default = 10.0
	hand_r = HAND_R
	foot_r = TV_R


## Host / local: put up the orbs. entries: [{id, name, pic, color}], opts: what each orb means.
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	start(new_stage, opts, done)
	show_row(new_stage, entries)
	publish([new_stage, entries])


func orbs_off() -> Array:
	return ["", []]


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array) -> void:
	if new_stage == "" or entries.is_empty():
		orbs.clear()
		return
	orbs.show_orbs(new_stage, entries, ROW, GAP, Y, {"scale": SCALE, "pop": true, "font": 64, "label_y": -1.05,
		"label_px": 0.008, "two_lines": true, "bob": 0.08})


## The TV players running under an orb, the VR player's gloves reaching into one.
func takers() -> Dictionary:
	var points := {}
	for slot in main.avatars:
		var a: Node3D = main.avatars[slot]
		points["p%d" % int(slot)] = [a.global_position, int(slot), "walk"]
	if main.vr_rig != null:
		for h in [VrRig.LEFT, VrRig.RIGHT]:
			points["h%d" % h] = [main.vr_rig.hand_point(h), 0, "hand"]
	return points


func slot_color(slot: int) -> Color:
	return main.player_color(slot)


func fx(i: int, slot: int, at: Vector3, _col: Color) -> void:
	if at != Vector3.INF:
		main.sound_at("power_up", at, -2.0, 1.0 + 0.1 * i)
		main.confetti(at, 24, 1.0)
	if slot == 0 and main.vr_rig != null and taker.begins_with("h"):
		main.vr_rig.pulse(int(taker.substr(1)), 0.5, 0.08)
