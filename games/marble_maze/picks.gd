extends "res://core/pick_flow.gd"
## MARBLE MAZE PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (worlds.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session, before the first story / daily maze (the family's last mode in the
##           middle).
##   "gift"  BOBO'S MARBLES before each place's first maze, today's maze and a session's first maze: three of HEAVY,
##           BOUNCY, MAGNET, STICKY, ZOOMY (worlds.gd gift_choices) - the whole team rolls as that kind.
## They happen on the PICK BOARD (main.gd PICK_MAP, an open room): three small glass orbs hover over the floor near
## the giant's edge (children of the board, so they tilt with it). A marble rolls UNDER one, the VR giant touches one
## with a hand; the first one decides for the team (a dot in their colour circles it). Nobody in time? The middle
## orb (it glows brightest) is taken. Host / local decide; the host sends the sticky "orbs" event [stage, entries]
## (a machine joining mid-pick sees the orbs too) and "take" [i, slot]; every machine draws.

const WAIT := {"mode": 14.0, "gift": 12.0}
const ROW := Vector3(0.0, 0.0, 0.25)
const GAP := 0.33
const Y := 0.1  # the orb's middle above the floor: a marble (r 0.028) rolls under it
const SCALE := 0.065  # glass ball radius 0.6 * 0.055 = 3.3 cm: modest in VR, clear in the TV chase cams
const MARBLE_R := 0.045  # flat distance from the orb's middle a marble must roll to
const HAND_R := 0.035


func _init() -> void:
	after = 1.2
	waits = WAIT
	hand_r = HAND_R
	foot_r = MARBLE_R


## The orbs sit on the board (they tilt with it).
func orbs_parent() -> Node:
	return main.board


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
	orbs.show_orbs(new_stage, entries, ROW, GAP, Y, {"scale": SCALE, "pop": true, "font": 64, "label_y": 1.35, "label_px": 0.008,
		"two_lines": true, "touch": 0.0, "bob": 0.15})


## The marbles rolling under an orb, the VR giant's hands reaching into one.
func takers() -> Dictionary:
	var points := {}
	for p in main.active_marbles():
		if not p.falling:
			points["m%d" % int(p.index)] = [p.global_position, int(p.index), "roll"]
	var giant = main.players[0] if not main.players.is_empty() else null
	if giant != null and giant.vr and giant.hand_r != null:
		points["hl"] = [(giant.hand_l as Node3D).global_position, 0, "hand"]
		points["hr"] = [(giant.hand_r as Node3D).global_position, 0, "hand"]
	return points


func slot_color(slot: int) -> Color:
	return main.players[slot].color if slot < main.players.size() else Color(1, 1, 1)


func fx(i: int, _slot: int, at: Vector3, col: Color) -> void:
	if at != Vector3.INF:
		main.sound("ring", -2.0, 1.0 + 0.1 * i)
		main.burst(at, col, 14, false)
