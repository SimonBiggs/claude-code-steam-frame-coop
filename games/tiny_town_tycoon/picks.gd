extends "res://core/pick_flow.gd"
## TINY TOWN TYCOON PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), once the practice is done.
##   "gift"  BENNY'S BUILDER GIFTS right after the mode and every morning: three of SPEEDY CRANE, DOUBLE HOUSES,
##           HAPPY PARK, ZOOMY WHEELS, SUNNY DAY.
## Rows (deep.gd): "island" - three orbs over road cells by the town hall; a driver STANDS their vehicle under one
## deep.gd TV_DWELL s (driving past never picks) and the flat mayor holds the cursor under one. When the VR mayor is
## here too those orbs are for the others (it can't reach the middle of the table). "vr" - only the VR mayor: three
## small orbs an arm's reach in front of their eyes; a hand moves into one and stays deep.gd DWELL s. Something already
## in an orb when they pop up must leave and come back. The first one decides (a dot in their colour circles it).
## Nobody in time? The middle orb (it glows brightest). The host sends the sticky "orbs" event [stage, entries, spots,
## row] (a machine joining mid-pick sees the orbs too) and "take" [orb, slot].

const Deep := preload("res://games/tiny_town_tycoon/deep.gd")

var row := ""  # every machine: "island" | "vr"


func _init() -> void:
	after = 1.1
	hand_r = Deep.HAND_R
	hand_dwell = Deep.DWELL
	foot_dwell = Deep.TV_DWELL


## Host / local: put up the orbs. entries: [{id, name, pic, color}], opts: what each orb means.
func begin(new_stage: String, entries: Array, opts: Array, new_row: String, done: Callable) -> void:
	start(new_stage, opts, done)
	var at: Array = Deep.vr_spots(main.vr_rig.camera.global_transform, entries.size()) if new_row == "vr" else Deep.row_spots(main.town, entries.size())
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
	if new_row == "vr":  # a modest ball an arm's reach away; the names over each ball, never at the mayor's eyes
		orbs.show_orbs(new_stage, entries, at[0], 0.0, 0.0, {"at": at, "scale": Deep.VR_SCALE, "pop": true, "font": 56,
			"label_y": 1.2, "label_px": 0.0042, "two_lines": true, "bob": 0.01, "hit_r": PickOrbs.BALL_R, "dot_r": 0.8})
	else:  # over the road by the hall, the names over the balls (the toy town's houses stand round them)
		orbs.show_orbs(new_stage, entries, at[0], 0.0, 0.0, {"at": at, "scale": Deep.ORB_SCALE, "pop": true, "font": 64,
			"label_y": 1.25, "label_px": 0.0105, "two_lines": true, "bob": 0.08, "for_others": main.vr_rig != null})
	main.pick_banner()


func wait_for() -> float:
	return Deep.wait_for(stage, main.pick_nobody())


## The VR mayor's hands (their row), or on the island a flat mayor's cursor and the people's vehicles (AI drivers never pick).
func takers() -> Dictionary:
	var points := {}
	if row == "vr" and main.vr_rig != null:
		for h in 2:
			points["h%d" % h] = [main.vr_rig.hand_point(h), 0, "hand"]
	elif row == "island":
		if main.flat != null:
			points["f"] = [main.flat.cursor_point(), 0, "cursor"]
		for slot in main.party.active_slots():
			var v: Node3D = main.fleet.vehicle_of(int(slot)) if int(slot) >= 1 else null
			if v != null:
				points["v%d" % int(slot)] = [v.position, int(slot), "drive"]
	return points


func orb_at(kind: String, point: Variant) -> int:
	return orbs.nearest_hit(point, hand_r) if kind == "hand" else Deep.under(spots, point)


func fx(i: int, slot: int, at: Vector3, col: Color) -> void:
	if at != Vector3.INF:
		main.sfx.play_at("power_up", at, -4.0, 1.0 + 0.1 * i)
		main.view.call("burst", at, col, 18, 0.8 if row == "vr" else 0.5)
	if slot == 0 and row == "vr" and main.vr_rig != null:
		main.vr_rig.pulse(0, 0.5, 0.08)
		main.vr_rig.pulse(1, 0.5, 0.08)
