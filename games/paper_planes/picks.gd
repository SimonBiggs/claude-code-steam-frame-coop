extends "res://core/pick_flow.gd"
## PAPER PLANES PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle).
##   "fold"  PIP'S PAPER FOLDS before every flight: three of GLIDER, DART, STUNT, RAINBOW, SWALLOW, COMET, plus
##           TODAY'S SKY as a fourth orb (the daily flight, the same sky for everyone).
## Big glass orbs float in an arc in the sky in front of the VR deck (deep.gd row_spots). A TV plane FLIES INTO one,
## a VR plane is THROWN into one (a pick is never a resting hand). The first one decides for the team (a dot in their
## colour circles it). Nobody took one by the wait (main.gd pick_time): the middle orb (it glows brightest) - a lone
## pilot or a little one is never stuck. The host sends the sticky "orbs" event [stage, entries, spots] (a machine
## joining mid-pick sees the orbs too) and "take" [i, slot].

const Deep := preload("res://games/paper_planes/deep.gd")

var wait_s := 12.0  # main sets the wait (its pick_time) before tick()


func _init() -> void:
	after = 1.0


## Host / local: put up the orbs. entries: [{id, name, pic, color}], opts: what each orb means.
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
	orbs.show_orbs(new_stage, entries, Vector3(0.0, (at[0] as Vector3).y, 0.0), 4.0, 0.0, {"at": at, "scale": Deep.ORB_SCALE,
		"pop": true, "font": 72, "label_y": 1.1, "label_px": 0.006, "two_lines": true, "bob": 0.2})  # (names over the orbs: under them is the grass)


## A plane at pos: the orb it flies into (-1 none or not yet). The game takes it.
func hit_at(pos: Vector3, extra: float = 0.0) -> int:
	if not can_take() or orbs.orbs.is_empty():
		return -1
	return orbs.nearest_hit(pos, Deep.CATCH + extra)


func wait_for() -> float:
	return wait_s


func slot_color(slot: int) -> Color:
	return main.party.color_of(slot)


func fx(i: int, _slot: int, at: Vector3, col: Color) -> void:
	if at != Vector3.INF:
		main.sfx.play("magic", -2.0, 1.0 + 0.1 * i)
		var cols: Array[Color] = [col, Color.WHITE]
		main.burst(at, cols, 40, 1.0)
