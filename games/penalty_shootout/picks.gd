extends "res://core/pick_flow.gd"
## PENALTY SHOOTOUT PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), after practice.
##   "gift"  LEO'S GIFTS before every match from the second: three of BIG GLOVES, SLOW-MO, CURVE BOOTS, GOLDEN BALL,
##           BIG STAR.
## Three big glass orbs float in the goal mouth (deep.gd row_spots). The strikers take turns to KICK the ball through
## one (main.gd runs the kicks: the keeper can't save while picking); the keeper REACHES into one on purpose (a VR
## glove has to move in after they pop up and stay a moment - a hand already resting there or sweeping past never
## picks; a flat keeper shuffles under one, away from where they stood when the orbs came up). The first one decides
## for the team (a dot in their colour circles it). Nobody in time? The middle orb (it glows brightest) - a lone
## keeper or a little one is never stuck. The host sends the sticky "orbs" event [stage, entries, spots] (a machine
## joining mid-pick sees the orbs too) and "take" [i, slot].

const Deep := preload("res://games/penalty_shootout/deep.gd")

const FLAT_DWELL := 0.15  # a flat keeper standing under an orb


func _init() -> void:
	after = 1.1
	hand_r = Deep.HAND_R
	hand_dwell = Deep.DWELL
	foot_dwell = FLAT_DWELL


## Host / local: put up the orbs in the goal mouth. entries: [{id, name, pic, color}], opts: what each orb means.
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	start(new_stage, opts, done)
	spots = Deep.row_spots(entries.size())
	show_row(new_stage, entries, spots)
	publish([new_stage, entries, spots])


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array, at: Array) -> void:
	if new_stage == "" or entries.is_empty() or at.size() < entries.size():
		orbs.clear()
		return
	orbs.show_orbs(new_stage, entries, at[0], 2.2, 0.0, {"at": at, "scale": Deep.ORB_SCALE, "pop": true, "font": 64,
		"label_y": -1.25, "label_px": 0.006, "two_lines": true, "bob": 0.05})  # (names under the orbs: never at a VR keeper's eyes)


func wait_for() -> float:
	return Deep.wait_for(stage, main.pick_solo())


## A kicked ball at pos: the orb it hits (-1 none). The game takes it after can_take().
func ball_hit(pos: Vector3) -> int:
	if orbs.orbs.is_empty():
		return -1
	return orbs.nearest_hit(pos, Deep.CATCH + 0.11)


## The VR keeper's gloves reaching into an orb, or a flat keeper standing under one.
func takers() -> Dictionary:
	var k = main.keeper
	if k == null:
		return {}
	if k.vr:
		return {"l": [k.glove_l, 0, "hand"], "r": [k.glove_r, 0, "hand"]}
	return {"flat": [Vector3(float(k.kx), Deep.ROW_Y, Deep.ROW_Z), 0, "flat"]}


func orb_at(kind: String, point: Variant) -> int:
	if kind == "hand":
		return orbs.nearest_hit(point, hand_r)
	var i := -1
	for j in spots.size():
		if absf((spots[j] as Vector3).x - (point as Vector3).x) < Deep.FLAT_R:
			i = j
	return i


func slot_color(slot: int) -> Color:
	return main.PLAYER_COLORS[slot] if slot < main.PLAYER_COLORS.size() else Color(1, 1, 1)


func fx(i: int, slot: int, at: Vector3, col: Color) -> void:
	if at != Vector3.INF:
		main.sound("power", -4.0, 1.0 + 0.1 * i)
		main.burst(at, col, 18, false)
	if slot == 0 and main.keeper != null and main.keeper.vr:
		main.keeper.haptic("both")
