extends "res://core/pick_flow.gd"
## CANNON COVE PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), after target practice.
##   "gift"  POLLY'S CANNON GIFTS before every wave: three of BOUNCY BALLS, NET SHOT, BIG BARREL, GOLDEN BALL, QUICK LOAD.
## Three big glass orbs bob on the sea off the gunner's cannon (deep.gd row_spots: inside its swing and reach). The
## gunner SHOOTS one (aim and fire: a pick is never a resting hand), or a deckhand muskets one. The first one hit
## decides for the team (a dot in their colour circles it). Nobody hit one by ROW_WAIT: the middle orb (it glows
## brightest) - a lone gunner or a little one is never stuck. The host sends the sticky "orbs" event
## [stage, entries, spots] (a machine joining mid-pick sees the orbs too) and "take" [i, slot].

const Deep := preload("res://games/cannon_cove/deep.gd")


func _init() -> void:
	after = 1.2


## Host / local: put up the orbs off the gunner's cannon. entries: [{id, name, pic, color}], opts: what each orb means.
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	start(new_stage, opts, done)
	var c = main.cannons[clampi(int(main.players[0].station), 0, main.cannons.size() - 1)]
	spots = Deep.row_spots(c.global_position, c.outboard, float(main.sea_level), entries.size())
	show_row(new_stage, entries, spots)
	publish([new_stage, entries, spots])


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array, at: Array) -> void:
	if new_stage == "" or entries.is_empty() or at.size() < entries.size():
		orbs.clear()
		return
	orbs.show_orbs(new_stage, entries, Vector3(0.0, (at[0] as Vector3).y, 0.0), 8.0, 0.0, {"at": at, "scale": Deep.ORB_SCALE,
		"pop": true, "font": 72, "label_y": 1.2, "label_px": 0.006, "two_lines": true, "bob": 0.2})  # (names over the orbs: under them is the sea)


## A cannonball at pos: the orb it hits (-1 none). The game takes it after can_take().
func ball_hit(pos: Vector3, extra: float = 0.0) -> int:
	if orbs.orbs.is_empty():
		return -1
	return orbs.nearest_hit(pos, Deep.CATCH + extra)


## The first orb along a ray: [index (-1 none), distance].
func ray_hit(from: Vector3, dir: Vector3, max_d: float) -> Array:
	var best := -1
	var best_t := max_d
	for o in orbs.orbs:
		if not is_instance_valid(o) or not (o as Node3D).is_inside_tree():
			continue
		var c: Vector3 = (o as Node3D).global_position
		var tt := (c - from).dot(dir)
		if tt < 0.0 or tt > best_t:
			continue
		if (from + dir * tt).distance_to(c) < float(o.hit_radius):
			best_t = tt
			best = int(o.index)
	return [best, best_t]


func wait_for() -> float:
	return Deep.ROW_WAIT


func slot_color(slot: int) -> Color:
	return main.PLAYER_COLORS[slot] if slot < main.PLAYER_COLORS.size() else Color(1, 1, 1)


func fx(i: int, _slot: int, at: Vector3, _col: Color) -> void:
	if at != Vector3.INF:
		main.local_sound("bullseye", -3.0, 1.0 + 0.1 * i)
		main.confetti(at + Vector3.UP * 1.0, false)
