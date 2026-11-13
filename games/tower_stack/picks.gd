extends "res://core/pick_flow.gd"
## TOWER STACK PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices:
##   "mode"   GENTLE / BRAVE / HARD before the first job of a visit (the family's last mode in the middle).
##   "build"  WREN'S NEXT JOB between jobs: three buildings (castle, lighthouse, windmill, ...) to build next, each a
##            seeded towergen job of the same level (so every one is validated). TODAY'S TOWER is never swapped.
## The orbs float in a row over the (empty) stage. A TV player WALKS into one, the VR giant TOUCHES one with a hand;
## the first touch decides for the team (a dot in their colour circles it). Nobody chooses in time? The middle orb
## (it glows brightest) is taken, so little ones are never stuck. The round clock waits while the orbs are up.
## Host / local decide; the host keeps the "orbs" state [stage, entries] (sticky: a machine joining mid-pick sees the
## orbs too) and sends "take" [i, slot] events; every machine draws.

const WAIT := {"mode": 12.0, "build": 10.0}
const ROW := Vector3(0.0, 0.0, -0.6)
const GAP := 2.4
const Y := 2.4
const AVATAR_R := 0.25  # + PickOrbs.HIT_R: how close (flat) a TV player's feet must be under an orb
const HAND_R := 0.2


func _init() -> void:
	after = 1.0
	waits = WAIT
	wait_default = 10.0
	hand_r = HAND_R
	sync = "state"


## Host / local: put up the orbs over the build site. entries: [{id, name, pic, color}], opts: what each orb means.
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	start(new_stage, opts, done)
	show_row(new_stage, entries)
	publish([new_stage, entries])


func orbs_off() -> Array:
	return ["", []]


func show_row(new_stage: String, entries: Array) -> void:
	if new_stage == "" or entries.is_empty():
		orbs.clear()
		return
	orbs.show_orbs(new_stage, entries, ROW, GAP, Y)


## The TV players standing under an orb, the VR player's hands reaching into one.
func takers() -> Dictionary:
	var points := {}
	for slot in main.avatars:
		var a: Node3D = main.avatars[slot]
		points["p%d" % int(slot)] = [Vector3(a.position.x, ROW.y + Y, a.position.z), int(slot), "walk"]
	if main.vr_rig != null:
		for w in 2:
			points["h%d" % w] = [main.vr_rig.hand_point(w), 0, "hand"]
	return points


func orb_at(kind: String, point: Variant) -> int:
	return orbs.nearest_hit(point, hand_r if kind == "hand" else AVATAR_R)


func slot_color(slot: int) -> Color:
	return main.party.color_of(slot)


func fx(i: int, slot: int, at: Vector3, _col: Color) -> void:
	if at != Vector3.INF:
		main.sfx.play_at("ding", at, -2.0, 1.0 + 0.1 * i)
	if slot == 0 and main.vr_rig != null and taker.begins_with("h"):
		main.vr_rig.pulse(int(taker.substr(1)), 0.6, 0.08)
