extends "res://core/pick_flow.gd"
## GIANT'S TABLE PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), after the practice.
##   "gift"  SPARKY'S GIFTS in every break from wave 2: three of BIG FIRE, EMBER SHIELD, KNIGHT HELPERS, SLEEPY DUST,
##           BIG HANDS.
## Three glass orbs float over open ground in front of the Giant's seat (deep.gd row_spots: ~42 cm from the VR
## Giant's eyes, a modest 7 cm ball). The VR Giant REACHES into one on purpose (a grab point has to move in after
## they pop up and stay DWELL seconds - a hand already resting there or sweeping past never picks); the flat Giant
## (a flat host, a lone Deck, local play) HOVERS its hand over one; a knight WALKS UNDER one. A hand or knight already
## in one when they pop up must leave and come back. The first one decides for the team (a dot in their colour
## circles it). Nobody in time? The middle orb (it glows brightest): a lone player or a little one is never stuck.
## The host sends the sticky "orbs" event [stage, entries, spots] (a machine joining mid-pick sees the orbs too) and
## "take" [orb, slot].

const Deep := preload("res://games/giants_table/deep.gd")


func _init() -> void:
	after = 1.1
	hand_r = Deep.HAND_R
	hand_dwell = Deep.DWELL
	foot_dwell = Deep.TV_DWELL


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
	# (world units: 20 = 1 m for the VR Giant. hit_r is the ball's own radius, so nearest_hit means "touching the ball";
	# the names sit just under each ball, never at the Giant's eyes)
	orbs.show_orbs(new_stage, entries, at[0], 0.0, 0.0, {"at": at, "scale": Deep.ORB_SCALE, "pop": true, "font": 56,
		"label_y": -1.05, "label_px": 0.0075, "two_lines": true, "bob": 0.05, "hit_r": PickOrbs.BALL_R, "dot_r": 0.8})


func wait_for() -> float:
	return Deep.wait_for(stage, main.pick_nobody())


## The Giant's hands (VR: into the ball; flat: over it, like a knight) and the knights standing under one.
func takers() -> Dictionary:
	var points := {}
	var g = main.giant
	if g != null and not g.ghost:
		for h in g.hands.size():
			points["h%d" % h] = [g.hands[h].pos, 0, "hand" if g.vr else "flat"]
	for k in main.knights():
		if k.active and not k.is_down and not k.carried and k.is_inside_tree():
			points["k%d" % int(k.index)] = [k.global_position, int(k.index), "walk"]
	return points


func orb_at(kind: String, point: Variant) -> int:
	if kind == "hand":
		return orbs.nearest_hit(point, hand_r)
	var pos: Vector3 = point
	var reach := Deep.FLAT_R if kind == "flat" else Deep.TV_R
	var i := -1
	for j in spots.size():
		var sp: Vector3 = spots[j]
		if Vector2(sp.x - pos.x, sp.z - pos.z).length() < reach:
			i = j
	return i


func dwell_for(kind: String) -> float:
	return foot_dwell if kind == "walk" else hand_dwell


func slot_color(slot: int) -> Color:
	var cols: Array = main.PLAYER_COLORS
	return cols[slot % cols.size()]


func fx(i: int, slot: int, at: Vector3, col: Color) -> void:
	if at != Vector3.INF:
		main.sound("chime", -4.0, 1.0 + 0.1 * i, false)
		main.burst(at, col, 18, 0.3, false)
	var g = main.giant
	if slot == 0 and g != null and g.vr and not g.ghost:
		for h in g.hands:
			g.haptic(h, 0.5, 0.08)
