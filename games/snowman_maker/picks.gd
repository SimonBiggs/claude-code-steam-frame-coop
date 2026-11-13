extends "res://core/pick_flow.gd"
## SNOWMAN MAKER PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), before the first snow day.
##   "gift"  TUMBLE'S GIFTS before every day from the second: three of COSY SCARF, CARROT NOSE, MAGIC HAT, SPARKLE
##           BUTTONS, SNOW BOOTS.
## Three small glass orbs float an arm's reach in front of the VR builder (deep.gd row_spots, from where they stand and
## look when the orbs come up; with no VR builder, bigger ones stand just past the build circle). A TV player WALKS UNDER one;
## the VR builder REACHES into one on purpose (a glove has to move in after they pop up and stay a moment - a hand
## already resting there or sweeping past never picks). A player already standing under one when they pop up must
## step out and back in. The first one decides for the team (a dot in their colour circles it). Nobody in time? The
## middle orb (it glows brightest): a lone player or a little one is never stuck. The host sends the sticky "orbs"
## event [stage, entries, spots, scale] (a machine joining mid-pick sees the orbs too) and "take".

const Deep := preload("res://games/snowman_maker/deep.gd")


func _init() -> void:
	after = 1.1
	hand_r = Deep.HAND_R
	hand_dwell = Deep.DWELL
	foot_dwell = Deep.TV_DWELL


## Host / local: put up the orbs. entries: [{id, name, pic, color}], opts: what each orb means.
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	start(new_stage, opts, done)
	var vr: bool = main.vr_rig != null
	spots = Deep.row_spots(entries.size(), vr, main.vr_rig.head_position() if vr else Deep.G.VR_START,
		main.vr_rig.head_forward() if vr else Vector3.FORWARD)
	show_row(new_stage, entries, spots, Deep.orb_scale(vr))
	publish([new_stage, entries, spots, Deep.orb_scale(vr)])


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array, at: Array, scale: float = Deep.ORB_SCALE) -> void:
	if new_stage == "" or entries.is_empty() or at.size() < entries.size():
		orbs.clear()
		return
	# (names under the orbs: never at the VR builder's eyes; by the VR builder the orbs sit an arm's reach away, small)
	orbs.show_orbs(new_stage, entries, at[0], 0.7, 0.0, {"at": at, "scale": scale, "pop": true, "font": 56,
		"label_y": -1.3, "label_px": 0.005 if scale < 0.4 else 0.007, "two_lines": true, "bob": 0.04})


func wait_for() -> float:
	return Deep.wait_for(stage, main.pick_nobody())


## The VR builder's gloves (VR, slot 0) and the TV players' rollers under an orb.
func takers() -> Dictionary:
	var points := {}
	if main.vr_rig != null:
		for h in 2:
			points["g%d" % h] = [main.vr_rig.hand_point(h), 0, "hand"]
	for slot in main.avatars:
		var a: Node3D = main.avatars[slot]
		if is_instance_valid(a):
			points["s%d" % int(slot)] = [a.position, int(slot), "walk"]
	return points


func orb_at(kind: String, point: Variant) -> int:
	if kind == "hand":
		return orbs.nearest_hit(point, hand_r)
	var pos: Vector3 = point
	var i := -1
	for j in spots.size():
		var sp: Vector3 = spots[j]
		if Vector2(sp.x - pos.x, sp.z - pos.z).length() < Deep.tv_r(main.vr_rig != null):
			i = j
	return i


func fx(i: int, slot: int, at: Vector3, col: Color) -> void:
	if at != Vector3.INF:
		main.sfx.play_at("power_up", at, -4.0, 1.0 + 0.1 * i)
		main.burst(at, col, 18, 3.0)
	if slot == 0 and main.vr_rig != null:
		main.vr_rig.pulse(0, 0.5, 0.08)
		main.vr_rig.pulse(1, 0.5, 0.08)
