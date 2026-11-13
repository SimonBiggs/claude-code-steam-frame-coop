extends "res://core/pick_flow.gd"
## KITCHEN RUSH PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (nights.gd):
##   "mode"  GENTLE / BRAVE / HARD after the practice toastie (the family's last mode in the middle).
##   "gift"  GRAN'S GIFTS before rounds 2, 4, 6 and 8: QUICK KNIFE, BIG POT, HELPER MOUSE, SKATES (three not taken).
## The orbs float in a row over the counter. A TV runner walks up to the pass under one, the VR chef touches one with
## a hand, the button chef grabs at the pass spot under one; the first one decides for the team (a dot in their
## colour circles it). Nobody chooses in time? The middle orb (it glows brightest) is taken.
## Host / local decide; the host sends the sticky "orbs" event [stage, entries] (a machine joining mid-pick sees the
## orbs too) and "take" [i, slot]; every machine draws.

const WAIT := {"mode": 14.0, "gift": 12.0}
const ROW := Vector3(0.0, 0.95, -0.2)
const GAP := 0.72
const Y := 0.8
const SCALE := 0.3
const VR_GAP := 0.45
const VR_Y := 0.38
const VR_SCALE := 0.2
const RUNNER_R := 0.6  # + the orb's hit radius: how close (flat) a runner must stand
const HAND_R := 0.12

var compact := false  # every machine: the VR chef's smaller row


func _init() -> void:
	after = 1.2
	waits = WAIT
	hand_r = HAND_R


## Host / local: put up the orbs over the pass. entries: [{id, name, pic, color}], opts: what each orb means.
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	start(new_stage, opts, done)
	var chef = main.players[0] if not main.players.is_empty() else null
	show_row(new_stage, entries, chef != null and chef.vr)
	publish([new_stage, entries, compact])


func orbs_off() -> Array:
	return ["", []]


## Every machine: the row of orbs ("" stage: none). small: the VR chef's row.
func show_row(new_stage: String, entries: Array, small: bool = false) -> void:
	compact = small
	if new_stage == "" or entries.is_empty():
		orbs.clear()
		return
	orbs.show_orbs(new_stage, entries, ROW, VR_GAP if small else GAP, VR_Y if small else Y, {"scale": VR_SCALE if small else SCALE,
		"pop": true, "font": 56, "label_y": -1.0, "two_lines": true, "touch": 0.0})


## The runners standing under an orb, the VR chef's hands reaching into one.
func takers() -> Dictionary:
	var points := {}
	for i in range(1, main.players.size()):
		var p = main.players[i]
		if p.active and not p.ghost:
			var at: Vector3 = p.global_position
			points["p%d" % i] = [Vector3(at.x, ROW.y + (VR_Y if compact else Y), at.z), i, "walk"]
	var chef = main.players[0] if not main.players.is_empty() else null
	if chef != null and chef.vr and not chef.ghost and chef.hand_l != null:
		for h in 2:
			points["h%d" % h] = [chef.hand_point(h), 0, "hand"]
	return points


func orb_at(kind: String, point: Variant) -> int:
	return orbs.nearest_hit(point, hand_r if kind == "hand" else RUNNER_R)


## The flat chef grabbing over the pass at `spot`: takes the orb above it (true if one).
func chef_grab_at(spot: Vector3) -> bool:
	if not can_take():
		return false
	var best := -1
	var best_d := 0.4
	for o in orbs.orbs:
		var d: float = absf(o.global_position.x - spot.x)
		if d < best_d:
			best_d = d
			best = o.index
	if best >= 0:
		take(best, 0)
	return best >= 0


func slot_color(slot: int) -> Color:
	return main.players[slot].color if slot < main.players.size() else Color(1, 1, 1)


func fx(i: int, _slot: int, at: Vector3, col: Color) -> void:
	if at != Vector3.INF:
		main.sfx_local("ding", -2.0, 1.0 + 0.1 * i)
		main.burst(at, col, 14, 0.05)
