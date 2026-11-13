extends "res://core/pick_flow.gd"
## WHACK-A-MOLE PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle).
##   "crop"  which crop Fig plants when a bed is full (story.gd offers) - was two seed packets in the holes.
##   "gift"  FIG'S HAMMER GIFTS before every round: three of BIG HAMMER, SLEEPY DUST, GOLD GLOVE, BOING HAMMER,
##           CARROT BAG.
## Three little glass orbs float in a row over the front of the table: a hammer-kid runs into one, the VR giant bonks
## one with the mallet (or touches it with a glove) - the front row is an easy reach from where the giant stands, so a
## giant playing alone always gets every orb. The first one decides for the team (a dot in their colour circles it).
## Nobody in time? The middle orb (it glows brightest) is taken - a solo giant or a little one is never stuck. The
## host sends the sticky "orbs" event [stage, entries] (a machine joining mid-pick sees the orbs too) and "take" [i, slot].

const VrRig := preload("res://core/vr_rig.gd")
const Props := preload("res://games/whack_a_mole/props.gd")

const WAIT := {"mode": 14.0, "crop": 12.0, "gift": 10.0}
const ROW_Z := 0.95  # over the table's front edge (the giant stands at Props.HALF.y + 0.5)
const GAP := 0.95  # metres between orbs (more than 2 x TV_R: a hammer-kid touches one at a time)
const Y := 0.3  # above the table top
const SCALE := 0.3
const TV_R := 0.27  # how near a hammer-kid's feet must come to an orb's middle (across the table)
const HAND_R := 0.06  # the glove
const SWING := 0.6  # m/s: the mallet must be swung at an orb (like at a mole)


func _init() -> void:
	after = 1.0
	waits = WAIT
	wait_default = 10.0
	hand_r = HAND_R
	foot_r = TV_R


static func row_origin() -> Vector3:
	return Vector3(0.0, Props.TABLE_Y, ROW_Z)


static func spot_of(i: int, n: int) -> Vector3:
	return PickOrbs.spot(i, n, row_origin(), GAP, Y)


## Host / local: put up the orbs over the table's front edge. entries: [{id, name, pic, color}], opts: what each means.
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
	orbs.show_orbs(new_stage, entries, row_origin(), GAP, Y, {"scale": SCALE, "pop": true, "font": 64,
		"label_y": 1.15, "label_px": 0.0055, "two_lines": true, "bob": 0.06})


## The hammer-kids running under an orb; the VR giant's gloves reaching into one or the mallet swung at one.
func takers() -> Dictionary:
	var points := {}
	for slot in main.avatars:
		var a: Node3D = main.avatars[slot]
		points["p%d" % int(slot)] = [a.global_position, int(slot), "walk"]
	if main.vr_rig != null:
		if main.mallet_head != null:  # (always a taker: a swing is the move in, a resting mallet is in no orb)
			points["mallet"] = [main.mallet_head.global_position, 0, "mallet"]
		for h in [VrRig.LEFT, VrRig.RIGHT]:
			points["h%d" % h] = [main.vr_rig.hand_point(h), 0, "hand"]
	return points


func orb_at(kind: String, point: Variant) -> int:
	match kind:
		"mallet":
			if main.mallet_vel.length() <= SWING:
				return -1
			return orbs.nearest_hit(point, Props.HEAD_R * main.mallet_head.scale.x)
		"hand":
			return orbs.nearest_hit(point, hand_r)
	return orbs.at_point(point, foot_r)


## A mallet swung through an orb takes it as it hits (like a mole); a glove stays a moment.
func dwell_for(kind: String) -> float:
	return 0.0 if kind == "mallet" else super(kind)


func slot_color(slot: int) -> Color:
	return main.party.color_of(slot) if main.avatars.has(slot) else Color(1, 1, 1)


func fx(i: int, slot: int, at: Vector3, _col: Color) -> void:
	if at != Vector3.INF:
		main.sfx.play_at("power_up", at, -2.0, 1.0 + 0.1 * i)
		main.burst_at(at, Color(1.0, 0.9, 0.4))
	if slot == 0 and main.vr_rig != null:
		if taker == "mallet":
			main.vr_rig.pulse(VrRig.RIGHT, 0.6, 0.08)
		elif taker.begins_with("h"):
			main.vr_rig.pulse(int(taker.substr(1)), 0.5, 0.08)
