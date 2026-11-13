extends "res://core/pick_flow.gd"
## SOFT DODGEBALL PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), before the first round.
##   "gift"  TUMTUM'S BALL GIFTS before every round from the second: three of SQUISHY BALL, CURVE BALL, BUBBLE
##           SHIELD, SPEEDY SHOES, BALL MAGNET.
## With runners on the court the three big orbs float over the front of the court (deep.gd row_spots) and a runner
## STANDS under one for deep.gd TV_DWELL s (running past never picks). With only the VR giant here (CPU runners fill
## in) three small orbs float an arm's reach in front of the giant (deep.gd vr_spots) and a hand moves into one and
## stays deep.gd DWELL s. A hand or runner already in an orb when they pop up must leave and come back. The first one
## decides (a dot in their colour circles it). Nobody in time? The middle orb (it glows brightest): a lone player or a
## little one is never stuck. The host sends the sticky "orbs" event [stage, entries, spots, vr] (a machine joining
## mid-pick sees the orbs too) and "take" [orb, slot].

const Deep := preload("res://games/dodge_ball/deep.gd")

var vr_row := false  # every machine: the small row in front of the VR giant


func _init() -> void:
	after = 1.1
	hand_r = Deep.HAND_R
	hand_dwell = Deep.DWELL
	foot_dwell = Deep.TV_DWELL


## Host / local: put up the orbs. entries: [{id, name, pic, color}], opts: what each orb means. vr: in front of the
## VR giant (only they pick), else over the court (the runners pick).
func begin(new_stage: String, entries: Array, opts: Array, vr: bool, done: Callable) -> void:
	start(new_stage, opts, done)
	var in_vr: bool = vr and main.vr_rig != null
	var at := Deep.vr_spots(main.vr_rig.head_position(), entries.size()) if in_vr else Deep.row_spots(entries.size())
	show_row(new_stage, entries, at, in_vr)
	publish([new_stage, entries, spots, vr_row])


func orbs_off() -> Array:
	return ["", [], [], false]


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array, at: Array, vr: bool) -> void:
	if new_stage == "" or entries.is_empty() or at.size() < entries.size():
		orbs.clear()
		spots = []
		return
	spots = at.duplicate()
	vr_row = vr
	if vr:  # a modest ball an arm's reach away; the names just under each ball, never at the giant's eyes
		orbs.show_orbs(new_stage, entries, at[0], 0.0, 0.0, {"at": at, "scale": Deep.VR_SCALE, "pop": true, "font": 56,
			"label_y": -1.15, "label_px": 0.0042, "two_lines": true, "bob": 0.01, "hit_r": PickOrbs.BALL_R, "dot_r": 0.8})
	else:
		orbs.show_orbs(new_stage, entries, at[0], 0.0, 0.0, {"at": at, "scale": Deep.ORB_SCALE, "pop": true, "font": 64,
			"label_y": -1.1, "label_px": 0.0105, "two_lines": true, "bob": 0.08})


func wait_for() -> float:
	return Deep.wait_for(stage, main.pick_nobody())


## The VR giant's hands (their row) or the people's runners standing under an orb (CPU runners never pick).
func takers() -> Dictionary:
	var points := {}
	if vr_row and main.vr_rig != null:
		for h in 2:
			points["h%d" % h] = [main.vr_rig.hand_point(h), 0, "hand"]
	elif not vr_row:
		for id in main.avatars:
			if int(id) < 10 and not main.out.has(id):
				points["r%d" % int(id)] = [(main.avatars[id] as Node3D).position, int(id), "walk"]
	return points


func orb_at(kind: String, point: Variant) -> int:
	return orbs.nearest_hit(point, hand_r) if kind == "hand" else Deep.under(spots, point)


func fx(i: int, slot: int, at: Vector3, col: Color) -> void:
	if at != Vector3.INF:
		main.sfx.play_at("power_up", at, -4.0, 1.0 + 0.1 * i)
		main.burst(at, col, 18, 0.06 if vr_row else 0.12)
	if slot == 0 and vr_row and main.vr_rig != null:
		main.vr_rig.pulse(0, 0.5, 0.08)
		main.vr_rig.pulse(1, 0.5, 0.08)
