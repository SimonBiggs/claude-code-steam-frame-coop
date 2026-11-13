extends "res://core/pick_flow.gd"
## STARSHIP CREW PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), before the first seeded
##           trip's first mission.
##   "gift"  CAPTAIN WHISKERS' SHIP MODULES before every mission from the second of a seeded trip: three of BUBBLE
##           SHIELD, TRACTOR BEAM, TURBO, MEGA LASER, STAR BOOST.
## Three big glass orbs float in space just ahead of the ship, above its usual line (deep.gd row_spots: space x, y,
## so they slide past like the rings when the ship steers). The PILOT steers until one sits straight ahead and holds it
## there (deep.gd DWELL; a ship already lined up with one when they open must move off and come back: a resting ship
## never picks); a GUNNER zaps one with their crosshair (a press: deliberate). The CPU gunner never picks. The first
## one decides for the team (a dot in their colour circles it). Nobody in time? The middle orb (it glows brightest):
## a lone player or a little one is never stuck. The host sends the sticky "orbs" event [stage, entries, spots] (a
## machine joining mid-pick sees the orbs too) and "take".

const Deep := preload("res://games/starship_crew/deep.gd")
const Space := preload("res://games/starship_crew/space.gd")


func _init() -> void:
	after = 1.1
	open = Deep.OPEN
	foot_dwell = Deep.DWELL  # (lined up this long: sliding past never picks)


## Host / local: put up the orbs ahead of the ship. entries: [{id, name, pic, color}], opts: what each orb means.
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	start(new_stage, opts, done)
	show_row(new_stage, entries, Deep.row_spots(entries.size()))
	publish([new_stage, entries, spots])


## Every machine: the row of orbs ("" stage: none); spots in space (Vector2).
func show_row(new_stage: String, entries: Array, at: Array) -> void:
	if new_stage == "" or entries.is_empty() or at.size() < entries.size():
		orbs.clear()
		spots = []
		return
	spots = at.duplicate()
	orbs.position = Vector3.ZERO
	var places: Array = []
	for s in spots:
		var p: Vector2 = s
		places.append(Vector3(p.x, p.y + Space.SHIP_Y, Deep.ROW_Z))
	orbs.show_orbs(new_stage, entries, places[0], 4.0, 0.0, {"at": places, "scale": Deep.ORB_SCALE, "pop": true, "font": 64,
		"label_y": -1.05, "label_px": 0.008, "two_lines": true, "bob": 0.1})
	follow_space()


## Every machine: the orbs ride with the starfield.
func follow_space() -> void:
	if main.space != null:
		orbs.position = Vector3(-main.space.off.x, -main.space.off.y, 0.0)


func wait_for() -> float:
	return Deep.wait_for(stage, main.pick_nobody())


## The VR pilot steering the ship to line up with an orb (and holding it there).
func takers() -> Dictionary:
	if main.vr_rig == null:
		return {}
	return {"ship": [main.space.off, 0, "steer"]}


func orb_at(_kind: String, point: Variant) -> int:
	return Deep.lined_up(spots, point)


## The pull towards the orb the ship is lined up with (Vector2.ZERO none).
func hold_pull() -> Vector2:
	var line := int(inside.get("ship", -1))
	if stage == "" or chosen >= 0 or line < 0 or line == RESTING or line >= spots.size():
		return Vector2.ZERO
	return spots[line] - main.space.off


## A TV crew member zapped the screen at uv: takes the orb there (true if one).
func zap_at(slot: int, uv: Vector2) -> bool:
	if not can_take() or slot < 0:
		return false
	var best := -1
	var bd := INF
	for i in orbs.orbs.size():
		var w := orb_position(i)
		if w == Vector3.INF:
			continue
		var s: Vector2 = main.project(w)
		var d := Vector2((s.x - uv.x) * main.ASPECT, s.y - uv.y).length()
		if d < 0.2 and d < bd:
			bd = d
			best = i
	if best >= 0:
		take(best, slot)
		return true
	return false


func fx(i: int, slot: int, at: Vector3, col: Color) -> void:
	if at != Vector3.INF:
		main.sfx.play_at("power_up", at, -4.0, 1.0 + 0.1 * i)
		main.confetti(at, col, 30)
	if slot == 0 and main.vr_rig != null:
		main.vr_rig.pulse(0, 0.5, 0.08)
		main.vr_rig.pulse(1, 0.5, 0.08)
