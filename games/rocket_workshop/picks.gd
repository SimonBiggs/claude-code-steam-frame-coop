extends "res://core/pick_flow.gd"
## ROCKET WORKSHOP PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session, after the practice rocket (the family's last mode in the middle).
##   "gift"  SPROCKET'S PART GIFTS before every rocket from rocket 3: three of BOOSTERS, FINS, PARACHUTE, SHIELD.
## The orbs float in a row over the far half of the pilot's desk (deep.gd row_spots). The VR pilot TOUCHES one on
## purpose: a hand has to move INTO an orb after they pop up (a hand already resting there never picks). A flat
## pilot or a lone Deck CLICKS one (the pointer's ray). A crew member WALKS up to the desk's far side under one.
## The first one decides for the team (a dot in their colour circles it). Nobody in time? The middle orb (it glows
## brightest) - a lone pilot or a little one is never stuck. The host sends the sticky "orbs" event [stage, entries,
## spots] (a machine joining mid-pick sees the orbs too) and "take" [i, slot].

const Deep := preload("res://games/rocket_workshop/deep.gd")

var was_held := false  # the pointer's button last frame (a click is a press, not a hold)


func _init() -> void:
	after = 1.1
	waits = Deep.WAIT
	wait_default = 14.0
	hand_r = Deep.HAND_R


## Host / local: put up the orbs over the panel. entries: [{id, name, pic, color}], opts: what each orb means.
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	start(new_stage, opts, done)
	was_held = true  # (a button already down when they pop up is not a click)
	spots = Deep.row_spots(entries.size(), float(main.panel.top) if main.panel != null else 0.9)
	show_row(new_stage, entries, spots)
	publish([new_stage, entries, spots])


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array, at: Array) -> void:
	if new_stage == "" or entries.is_empty() or at.size() < entries.size():
		orbs.clear()
		return
	orbs.show_orbs(new_stage, entries, at[0], Deep.ROW_GAP, 0.0, {"at": at, "scale": Deep.ORB_SCALE, "pop": true, "font": 56,
		"label_y": 0.9, "label_px": 0.004, "two_lines": true, "touch": 0.0, "bob": 0.02})


## The pilot's hands reaching into an orb (a pointer hand clicks instead: extra_pick) and the crew walking under one.
func takers() -> Dictionary:
	var points := {}
	var op = main.players[0] if not main.players.is_empty() else null
	if op != null and not op.ghost:
		for h in op.panel_hands():
			if not bool(h.pointer):
				points["h" + String(h.id)] = [h.pos, 0, "hand"]
	for p in main.players:
		if p.index != 0 and p.active:
			points["p%d" % p.index] = [p.global_position, int(p.index), "walk"]
	return points


func orb_at(kind: String, point: Variant) -> int:
	return orbs.nearest_hit(point, hand_r) if kind == "hand" else orbs.at_point(point, Deep.crew_r())


## The pilot's pointer: a click (a press, not a hold) on an orb takes it.
func extra_pick() -> Array:
	var op = main.players[0] if not main.players.is_empty() else null
	if op == null or op.ghost:
		return []
	var got := -1
	var held := false
	for h in op.panel_hands():
		if bool(h.pointer):
			held = held or bool(h.grip)
			if bool(h.grip) and not was_held and t >= open:
				got = _pointer_orb(op, h.pos)
	was_held = held
	return [got, 0] if got >= 0 else []


func _pointer_orb(op, pos: Vector3) -> int:
	var r := PickOrbs.HIT_R * Deep.ORB_SCALE + Deep.POINTER_R
	var cam: Camera3D = op.camera
	if cam == null or not cam.is_inside_tree() or not op.bot_hand.is_empty() or op.cursor.x < 0.0:
		return orbs.nearest_hit(pos, r + 0.08)
	var from := cam.project_ray_origin(op.cursor)
	var dir := cam.project_ray_normal(op.cursor)
	var best := -1
	var bd := r
	for i in orbs.orbs.size():
		var c := orb_position(i)
		if c == Vector3.INF:
			continue
		var along := (c - from).dot(dir)
		var d := (from + dir * along).distance_to(c)
		if along > 0.0 and d < bd:
			bd = d
			best = i
	return best


func slot_color(slot: int) -> Color:
	return main.PLAYER_COLORS[slot] if slot < main.PLAYER_COLORS.size() else Color(1, 1, 1)


func fx(i: int, slot: int, at: Vector3, col: Color) -> void:
	if at != Vector3.INF:
		main.local_sound("solve", -4.0, 1.0 + 0.1 * i)
		main.burst(at, col, 14, 0.03)
	if slot == 0 and main.players.size() > 0 and main.players[0].vr:
		main.players[0].haptic("r", 0.5)
