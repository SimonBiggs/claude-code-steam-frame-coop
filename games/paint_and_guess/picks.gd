extends "res://core/pick_flow.gd"
## PAINT AND GUESS PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), before the first game.
##   "gift"  SMUDGE'S BRUSH GIFTS before every later game: three of BIG BRUSH, RAINBOW BRUSH, STAMPS, SLOW CLOCK,
##           PEEK GLASS.
## Rows (deep.gd): with guessers who are people, or a flat artist, three orbs in front of the canvas ("canvas"): a TV
## player's brush ring - or the artist's brush (mouse / stick, the VR laser or a touch) - rests on the canvas UNDER one
## deep.gd TV_DWELL s (sweeping past never picks). The VR artist alone: three small orbs an arm's reach in front of the
## artist's eyes ("vr"): the hand moves into one and stays deep.gd DWELL s. Something already there when they pop up
## must leave and come back. The first one decides (a dot in their colour circles it). Nobody in time? The middle orb
## (it glows brightest). The host sends the sticky "orbs" event [stage, entries, spots, row, canvas spots] (a machine
## joining mid-pick sees the orbs too) and "take" [orb, slot].

const Deep := preload("res://games/paint_and_guess/deep.gd")

var flat_spots: Array = []  # every machine, canvas row: the orbs in canvas metres (x, y, z in front)
var row := ""  # every machine: "canvas" | "vr"
var row_head := Transform3D()  # host, VR row: the head the row was put in front of
var rests: Array = []  # canvas row: a ring on the canvas under each orb (where to rest your brush ring)


func _init() -> void:
	after = 1.1
	hand_r = Deep.HAND_R
	hand_dwell = Deep.DWELL
	foot_dwell = Deep.TV_DWELL


## Host / local: put up the orbs. entries: [{id, name, pic, color}], opts: what each orb means. new_row: "vr" in front
## of the VR artist's head, else "canvas" in front of the canvas (rings rest under them).
func begin(new_stage: String, entries: Array, opts: Array, new_row: String, done: Callable) -> void:
	start(new_stage, opts, done)
	var at: Array = []
	var cs: Array = []
	if new_row == "vr":
		row_head = main.players[0].head.global_transform
		at = Deep.vr_spots(row_head, entries.size())
	else:
		cs = Deep.canvas_spots(entries.size())
		for c in cs:
			var v: Vector3 = c
			at.append(main.canvas.canvas_to_world(Vector2(v.x, v.y), v.z))
	show_row(new_stage, entries, at, new_row, cs)
	publish([new_stage, entries, spots, row, flat_spots])


func orbs_off() -> Array:
	return ["", [], [], "", []]


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array, at: Array, new_row: String, cs: Array = []) -> void:
	_clear_rests()
	if new_stage == "" or entries.is_empty() or at.size() < entries.size():
		orbs.clear()
		spots = []
		flat_spots = []
		row = ""
		return
	spots = at.duplicate()
	flat_spots = cs.duplicate()
	row = new_row
	if new_row == "vr":  # a modest ball an arm's reach away; the names over each ball, never at the artist's eyes
		orbs.show_orbs(new_stage, entries, at[0], 0.0, 0.0, {"at": at, "scale": Deep.VR_SCALE, "pop": true, "font": 56,
			"label_y": 1.2, "label_px": 0.0045, "two_lines": true, "bob": 0.004, "hit_r": PickOrbs.BALL_R, "dot_r": 0.8})
	else:  # in front of the canvas, the names over the balls (the spot to rest a ring on is under each one)
		orbs.show_orbs(new_stage, entries, at[0], 0.0, 0.0, {"at": at, "scale": Deep.CANVAS_SCALE, "pop": true, "font": 56,
			"label_y": 1.25, "label_px": 0.0067, "two_lines": true, "bob": 0.006})
		for i in mini(entries.size(), cs.size()):
			_rest_ring((cs[i] as Vector3).x, (entries[i] as Dictionary).get("color", Color.WHITE))
	main.pick_banner()


func _rest_ring(x: float, col: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "RestRing"
	var tm := TorusMesh.new()
	tm.inner_radius = Deep.TV_R * 0.62
	tm.outer_radius = Deep.TV_R * 0.72
	tm.rings = 24
	tm.ring_segments = 4
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.canvas.board_root.add_child(mi)
	mi.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, Deep.UNDER_Y, 0.01))
	rests.append(mi)


func _clear_rests() -> void:
	for r in rests:
		if is_instance_valid(r):
			(r as Node).queue_free()
	rests.clear()


func closed() -> void:
	orbs.clear()
	_clear_rests()
	flat_spots = []
	row = ""


## Canvas row: where on the canvas to rest a ring for orb i (canvas metres), INF if none.
func under_point(i: int) -> Vector2:
	if i < 0 or i >= flat_spots.size():
		return Vector2.INF
	return Vector2((flat_spots[i] as Vector3).x, Deep.UNDER_Y)


func wait_for() -> float:
	return Deep.wait_for(stage, main.pick_nobody())


## VR row: the orbs follow the artist's head when they step away or turn (and everyone moves in again).
func follow(_delta: float) -> void:
	if row != "vr" or main.players[0].head == null:
		return
	var h: Transform3D = main.players[0].head.global_transform
	if not head_moved(row_head, h):
		return
	row_head = h
	spots = Deep.vr_spots(h, spots.size())
	for i in mini(spots.size(), orbs.orbs.size()):
		if is_instance_valid(orbs.orbs[i]):
			(orbs.orbs[i] as Node3D).global_position = spots[i]
	reset_dwell()
	publish([stage, orbs.entries, spots, row, flat_spots])


## VR row: the artist's hand. Canvas row: the artist's and the guessers' rings resting under an orb (canvas metres).
func takers() -> Dictionary:
	var points := {}
	var a = main.players[0]
	if row == "vr":
		if (a.vr or a.fake_vr) and a.hand != null:
			points["h"] = [a.hand.global_position, 0, "hand"]
	else:
		if a.cursor_on and not a.ghost:
			points["a"] = [a.cursor, 0, "ring"]
		for g in main.active_guessers():
			points["g%d" % g.index] = [g.tv_cursor, g.index, "ring"]
	return points


func orb_at(kind: String, point: Variant) -> int:
	return orbs.nearest_hit(point, hand_r) if kind == "hand" else Deep.under(flat_spots, point)


func slot_color(slot: int) -> Color:
	return main.PLAYER_COLORS[slot % main.PLAYER_COLORS.size()]


func fx(i: int, slot: int, at: Vector3, col: Color) -> void:
	if at != Vector3.INF:
		main.sound("vote", -4.0, 1.0 + 0.1 * i)
		main.puff(at, col, 18)
	if slot == 0 and main.players[0].vr:
		main.players[0].buzz(0.5, 0.08)
