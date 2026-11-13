extends "res://core/pick_flow.gd"
## MINI GOLF PARTY PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, one choice for everyone (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), before the first hole.
##   "gift"  GUS'S GIFTS after the practice putt of every course: three of BOUNCY BALL, MAGNET CUP, LONG PUTTER,
##           RAINBOW BALL, GIANT CUP.
## The pick green (deep.gd pick_green) opens out into three pads with a modest orb floating at waist height over each.
## Everyone PUTTS their ball onto a pad (main.gd asks pad_hit() for every ball); the VR golfer can also REACH a hand
## into an orb on purpose (it has to move in after they pop up and stay a moment - a hand already resting there or
## sweeping past never picks). The first one decides for everyone (a dot in their colour circles it). Nobody in
## time? The middle orb (it glows brightest) - a lone golfer or a little one is never stuck. The host sends the
## sticky "orbs" event [stage, entries, spots] (a machine joining mid-pick sees the orbs too) and "take" [i, slot].

const Deep := preload("res://games/mini_golf_party/deep.gd")

var green: Dictionary = {}


func _init() -> void:
	after = 1.2  # (then the next hole)
	hand_r = Deep.HAND_R
	hand_dwell = Deep.DWELL


## Host / local: put up the orbs over the green's pads. entries: [{id, name, pic, color}], opts: what each orb means.
func begin(new_stage: String, d: Dictionary, entries: Array, opts: Array, done: Callable) -> void:
	start(new_stage, opts, done)
	green = d
	spots = []
	for i in entries.size():
		spots.append(Deep.orb_spot(d, i))
	show_row(new_stage, entries, spots)
	publish([new_stage, entries, spots])


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array, at: Array) -> void:
	if new_stage == "" or entries.is_empty() or at.size() < entries.size():
		orbs.clear()
		return
	orbs.show_orbs(new_stage, entries, at[0], 0.85, 0.0, {"at": at, "scale": Deep.ORB_SCALE, "pop": true, "font": 72,
		"label_y": -1.55, "label_px": 0.005, "two_lines": true, "bob": 0.03})  # (names under the orbs, over the pads)


func wait_for() -> float:
	return Deep.wait_for(stage, main.pick_solo())


## A putt stopping on a pad: that pad's orb (-1 none or not yet).
func pad_hit(p: Vector2) -> int:
	if not can_take():
		return -1
	var i := Deep.pad_at(green, p)
	return i if i < options.size() else -1


## The VR golfer's gloves reaching into an orb (TV golfers putt onto the pads: pad_hit).
func takers() -> Dictionary:
	if main.vr_rig == null:
		return {}
	return {"l": [main.vr_rig.hand_l.global_position, 0, "hand"], "r": [main.vr_rig.hand_r.global_position, 0, "hand"]}


func fx(i: int, slot: int, at: Vector3, col: Color) -> void:
	if at != Vector3.INF:
		main.sfx.play("power_up", -4.0, 1.0 + 0.1 * i)
		main.celebrate_fx(at, col)
	if slot == 0 and main.vr_rig != null:
		main.vr_rig.pulse(main.VrRig.RIGHT, 0.6, 0.12)
