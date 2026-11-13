extends "res://core/pick_flow.gd"
## OBSTACLE RUSH PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), before the first seeded course.
##   "gift"  COACH JELLY'S GIFTS before every course from a show's second: three of SPRING SHOES, GLIDE CAPE, STAR
##           MAGNET, BUBBLE, ZOOM SHOES.
## With runners on the course the three big orbs float over the start, across the course just past the start line
## (deep.gd row_spots), and a runner STANDS under one for deep.gd TV_DWELL s (running past never picks; main keeps
## everyone behind deep.gd FENCE while they are up). With only the VR giant here (CPU runners fill in) three small orbs
## float an arm's reach in front of the giant (deep.gd vr_spots) and a hand moves into one and stays deep.gd DWELL s.
## A hand or runner already in an orb when they pop up must leave and come back. The first one decides (a dot in their
## colour circles it). Nobody in time? The middle orb (it glows brightest): a lone player or a little one is never
## stuck. The host sends the sticky "orbs" event [stage, entries, spots, vr] (a machine joining mid-pick sees the orbs
## too) and "take" [orb, slot].

const Deep := preload("res://games/obstacle_rush/deep.gd")

var vr_row := false  # every machine: the small row in front of the VR giant
var entries_now: Array = []  # host: the shown row's entries (a VR refit puts the row up again in front of the head)


func _init() -> void:
	after = 1.1
	hand_r = Deep.HAND_R
	hand_dwell = Deep.DWELL
	foot_dwell = Deep.TV_DWELL


## Host / local: put up the orbs. entries: [{id, name, pic, color}], opts: what each orb means. vr: in front of the
## VR giant (only they pick), else over the start (the runners pick).
func begin(new_stage: String, entries: Array, opts: Array, vr: bool, done: Callable) -> void:
	start(new_stage, opts, done)
	var in_vr: bool = vr and main.vr_rig != null
	entries_now = entries
	if in_vr and not main.vr_rig.refitted.is_connected(_on_refit):
		main.vr_rig.refitted.connect(_on_refit)
	var at := Deep.vr_spots(main.vr_rig.head_position(), entries.size(), main.course.desc) if in_vr else Deep.row_spots(main.course.desc, entries.size())
	show_row(new_stage, entries, at, in_vr)
	publish([new_stage, entries, spots, vr_row])


## The VR player refitted (stood up, sat down): the row goes up again in front of the head.
func _on_refit(_h: float) -> void:
	if not vr_row or stage == "" or chosen >= 0 or main.vr_rig == null:
		return
	var at := Deep.vr_spots(main.vr_rig.head_position(), entries_now.size(), main.course.desc)
	show_row(stage, entries_now, at, true)
	publish([stage, entries_now, spots, vr_row])
	reset_dwell()


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
			"label_y": -1.15, "label_px": 0.0042, "two_lines": true, "bob": 0.01 * Deep.VR_S, "hit_r": PickOrbs.BALL_R, "dot_r": 0.8})
	else:  # the names over the balls: under them they met the runners' nameplates. Only runners take these: a VR giant
		# watching from beside the table may see one behind a course piece (for_others).
		orbs.show_orbs(new_stage, entries, at[0], 0.0, 0.0, {"at": at, "scale": Deep.ORB_SCALE, "pop": true, "font": 64,
			"label_y": 1.25, "label_px": 0.0105, "two_lines": true, "bob": 0.08, "for_others": main.vr_rig != null})
	main.pick_banner()


func wait_for() -> float:
	return Deep.wait_for(stage, main.pick_nobody())


## The VR giant's hands (their row) or the people's runners standing under an orb (CPU runners never pick).
func takers() -> Dictionary:
	var points := {}
	if vr_row and main.vr_rig != null:
		for h in 2:
			points["h%d" % h] = [main.vr_rig.hand_point(h), 0, "hand"]
	elif not vr_row:
		for id in main.runners:
			if int(id) < 10:
				points["r%d" % int(id)] = [(main.runners[id] as Node3D).position, int(id), "walk"]
	return points


func orb_at(kind: String, point: Variant) -> int:
	return orbs.nearest_hit(point, hand_r) if kind == "hand" else Deep.under(spots, point)


func fx(i: int, slot: int, at: Vector3, col: Color) -> void:
	if at != Vector3.INF:
		main.sfx.play_at("power_up", at, -4.0, 1.0 + 0.1 * i)
		main.confetti(at, col, 18)
	if slot == 0 and vr_row and main.vr_rig != null:
		main.vr_rig.pulse(0, 0.5, 0.08)
		main.vr_rig.pulse(1, 0.5, 0.08)
