extends "res://core/pick_flow.gd"
## BLOCK BUILDERS PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), before the first sky course.
##   "gift"  PUFF'S BLOCK GIFTS before every sky course from a session's second: three of STICKY BRICKS, BIG BRICKS,
##           BUILDER ROBOT, BLOCK BOX, JUMPY BOOTS.
## Rows (deep.gd): with runners who are people, three big orbs over the start island ("start": a runner STANDS under one
## deep.gd TV_DWELL s; running past never picks). A flat builder with only the buddy: three orbs over the middle of the
## course ("flat": the glove hovers under one TV_DWELL s). The VR builder with only the buddy: three small orbs an arm's
## reach in front of the builder's eyes ("vr": the hand moves into one and stays deep.gd DWELL s). The VR hand can
## touch any row's orb and the flat glove stand under any row's. Something already in an orb when they pop up must
## leave and come back. The first one decides (a dot in their colour circles it). Nobody in time? The middle orb (it
## glows brightest). The host sends the sticky "orbs" event [stage, entries, spots, row] (a machine joining mid-pick
## sees the orbs too) and "take" [orb, slot].

const Deep := preload("res://games/block_builders/deep.gd")

var row := ""  # every machine: "start" | "flat" | "vr"


func _init() -> void:
	after = 1.1
	hand_r = Deep.HAND_R * Deep.S
	hand_dwell = Deep.DWELL
	foot_dwell = Deep.TV_DWELL


## Host / local: put up the orbs. entries: [{id, name, pic, color}], opts: what each orb means.
func begin(new_stage: String, entries: Array, opts: Array, new_row: String, done: Callable) -> void:
	start(new_stage, opts, done)
	var at: Array
	match new_row:
		"vr":
			at = Deep.vr_spots(main.builder.xr_camera.global_transform, entries.size())
		"flat":
			at = Deep.flat_spots(entries.size())
		_:
			at = Deep.row_spots(main.level_data(), entries.size())
	show_row(new_stage, entries, at, new_row)
	publish([new_stage, entries, spots, row])


func orbs_off() -> Array:
	return ["", [], [], ""]


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array, at: Array, new_row: String) -> void:
	if new_stage == "" or entries.is_empty() or at.size() < entries.size():
		orbs.clear()
		spots = []
		row = ""
		return
	spots = at.duplicate()
	row = new_row
	match new_row:
		"vr":  # a modest ball an arm's reach away; the names over each ball, never at the builder's eyes
			var s := Deep.VR_SCALE * Deep.S
			orbs.show_orbs(new_stage, entries, at[0], 0.0, 0.0, {"at": at, "scale": s, "pop": true, "font": 56,
				"label_y": 1.2, "label_px": 0.0042, "two_lines": true, "bob": 0.01, "hit_r": PickOrbs.BALL_R, "dot_r": 0.8})
		"flat":
			orbs.show_orbs(new_stage, entries, at[0], 0.0, 0.0, {"at": at, "scale": Deep.FLAT_SCALE, "pop": true, "font": 64,
				"label_y": 1.2, "label_px": 0.0105, "two_lines": true, "bob": 0.08})
		_:  # the names over the balls: under them they met the runners' nameplates
			orbs.show_orbs(new_stage, entries, at[0], 0.0, 0.0, {"at": at, "scale": Deep.ORB_SCALE, "pop": true, "font": 64,
				"label_y": 1.25, "label_px": 0.0095, "two_lines": true, "bob": 0.06})
	main.pick_banner()


func wait_for() -> float:
	return Deep.wait_for(stage, main.pick_nobody())


## The VR builder's grab point, a flat builder's cursor, the runners standing under an orb (the buddy never picks).
func takers() -> Dictionary:
	var points := {}
	var b = main.builder
	if b != null and b.vr:
		points["h"] = [b.grab_point, 0, "hand"]
	elif b != null and b.flat and not b.remote:
		points["g"] = [Vector3(b.cursor.x, 0.0, b.cursor.y), 0, "cursor"]
	for r in main.runners():
		if r.active and not r.buddy:
			points["r%d" % r.index] = [r.global_position, r.index, "walk"]
	return points


func orb_at(kind: String, point: Variant) -> int:
	return orbs.nearest_hit(point, hand_r) if kind == "hand" else Deep.under(spots, point)


func fx(i: int, slot: int, at: Vector3, col: Color) -> void:
	if at != Vector3.INF:
		main.local_sound("ding", -4.0, 1.0 + 0.1 * i)
		main.burst(at, col, 18, 0.2 if row == "vr" else 0.12)
	if slot == 0 and row == "vr" and main.builder != null and main.builder.vr:
		main.builder._haptic(0.5, 0.08)
