extends Node
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

const PickOrbs := preload("res://core/pick_orbs.gd")
const Deep := preload("res://games/paint_and_guess/deep.gd")

const AFTER := 1.1  # seconds the taken orb shows its dot before the orbs go
const OPEN := 0.8  # seconds after the orbs pop up before they can be taken
const RESTING := 99  # inside[id]: a hand or a ring that was already at an orb when they opened

var main
var orbs: PickOrbs
var stage := ""  # host: "" | "mode" | "gift"
var options: Array = []
var spots: Array = []  # every machine: the orbs' middles (world)
var flat_spots: Array = []  # every machine, canvas row: the orbs in canvas metres (x, y, z in front)
var row := ""  # every machine: "canvas" | "vr"
var t := 0.0
var chosen := -1
var chosen_by := -1
var done_t := 0.0
var on_done: Callable  # host: (stage, option, slot)
var history: Array = []  # [stage, option, by] (telemetry, bots)
var inside := {}  # hand / ring id -> orb index it is at now (-1 none)
var dwell := {}  # id -> seconds at that orb
var row_head := Transform3D()  # host, VR row: the head the row was put in front of
var rests: Array = []  # canvas row: a ring on the canvas under each orb (where to rest your brush ring)


func _ready() -> void:
	name = "Picks"
	orbs = PickOrbs.new()
	orbs.collision_layer = 0
	main.add_child(orbs)


func active() -> bool:
	return stage != ""


func showing() -> bool:
	return not orbs.orbs.is_empty()


## Host / local: put up the orbs. entries: [{id, name, pic, color}], opts: what each orb means.
func begin(new_stage: String, entries: Array, opts: Array, new_row: String, done: Callable) -> void:
	stage = new_stage
	options = opts
	on_done = done
	t = 0.0
	chosen = -1
	chosen_by = -1
	done_t = 0.0
	inside = {}
	dwell = {}
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
	main.net.event("orbs", [new_stage, entries, spots, row, flat_spots])
	print("PICKS %s: %s (%s row)" % [new_stage, opts, row])


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


## A ring on the canvas under an orb in its colour: rest your brush ring in it.
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


## Orb i's middle in the world (bots aim there), INF if none.
func orb_position(i: int) -> Vector3:
	if i < 0 or i >= orbs.orbs.size() or not is_instance_valid(orbs.orbs[i]) or not (orbs.orbs[i] as Node3D).is_inside_tree():
		return Vector3.INF
	var o = orbs.orbs[i]
	return o.icon.global_position if o.icon != null and o.icon.is_inside_tree() else (o as Node3D).global_position


## The canvas point under orb i (canvas row; bots and flat players rest a ring there), INF if none.
func under_point(i: int) -> Vector2:
	if i < 0 or i >= flat_spots.size():
		return Vector2.INF
	return Vector2((flat_spots[i] as Vector3).x, Deep.UNDER_Y)


## Seconds left to pick.
func left() -> float:
	return maxf(0.0, Deep.wait_for(stage, main.pick_nobody()) - t) if stage != "" and chosen < 0 else 0.0


## Host / local, every frame while the orbs are up.
func tick(delta: float) -> void:
	if stage == "":
		return
	if chosen >= 0:
		done_t += delta
		if done_t >= AFTER:
			_finish()
		return
	t += minf(delta, 0.1)  # (a loading hitch never eats the wait)
	_follow_head()
	var got := _pick(delta)
	if got.size() == 2:
		take(int(got[0]), int(got[1]))
		return
	if t > Deep.wait_for(stage, main.pick_nobody()):
		take(options.size() / 2, -1)  # nobody took one: the middle one (it glows brightest)


## Host, VR row: the artist moved a lot since the orbs popped up (the easel fit moves them at the start, a walk, a
## turn): the row moves to stay an arm's reach in front of them (every machine gets the new places).
func _follow_head() -> void:
	if row != "vr" or main.players[0].head == null:
		return
	var h: Transform3D = main.players[0].head.global_transform
	var f_now := (-h.basis.z).slide(Vector3.UP)
	var f_was := (-row_head.basis.z).slide(Vector3.UP)
	var turned := f_now.length() > 0.2 and f_was.length() > 0.2 and f_now.normalized().dot(f_was.normalized()) < 0.9
	if h.origin.distance_to(row_head.origin) < 0.3 and not turned:
		return
	row_head = h
	spots = Deep.vr_spots(h, spots.size())
	for i in mini(spots.size(), orbs.orbs.size()):
		if is_instance_valid(orbs.orbs[i]):
			(orbs.orbs[i] as Node3D).global_position = spots[i]
	inside = {}
	dwell = {}
	main.net.event("orbs", [stage, orbs.entries, spots, row, flat_spots])


## This frame's pick ([orb, slot] or []).
func _pick(delta: float) -> Array:
	var points := {}  # id -> [point (Vector3 world for a hand, Vector2 canvas for a ring), slot, hand]
	var a = main.players[0]
	if row == "vr":
		if (a.vr or a.fake_vr) and a.hand != null:
			points["h"] = [a.hand.global_position, 0, true]
	else:
		if a.cursor_on and not a.ghost:
			points["a"] = [a.cursor, 0, false]
		for g in main.active_guessers():
			points["g%d" % g.index] = [g.tv_cursor, g.index, false]
	var got: Array = []
	for id in points:
		var hand: bool = points[id][2]
		var i := orbs.nearest_hit(points[id][0], Deep.HAND_R) if hand else Deep.under(flat_spots, points[id][0])
		if not inside.has(id):  # where it was when the orbs came up: resting at one is never a pick until it leaves
			inside[id] = RESTING if i >= 0 else -1
		var before := int(inside[id])
		if before == RESTING:
			inside[id] = RESTING if i >= 0 else -1
			dwell[id] = 0.0
			continue
		if i != before:
			dwell[id] = 0.0
		inside[id] = i
		if i >= 0 and t >= OPEN:
			dwell[id] = float(dwell.get(id, 0.0)) + delta
			if float(dwell[id]) >= (Deep.DWELL if hand else Deep.TV_DWELL) and got.is_empty():
				got = [i, int(points[id][1])]
	return got


## Host / local: orb i taken by slot (0 = the artist, a guesser's index, -1: nobody chose, the middle one).
func take(i: int, slot: int) -> void:
	if stage == "" or chosen >= 0 or i < 0 or i >= options.size():
		return
	chosen = i
	chosen_by = slot
	take_fx(i, slot)
	main.net.event("take", [i, slot])
	print("PICK %s: %s took %d (%s)" % [stage, "nobody" if slot < 0 else "P%d" % (slot + 1), i, str(options[i])])


## Every machine: a dot in the taker's colour circles orb i, a happy sound and a puff.
func take_fx(i: int, slot: int) -> void:
	var col: Color = main.PLAYER_COLORS[slot % main.PLAYER_COLORS.size()] if slot >= 0 else Color(1, 1, 1)
	var at := orbs.take(i, col)
	if at != Vector3.INF:
		main.sound("vote", -4.0, 1.0 + 0.1 * i)
		main.puff(at, col, 18)
	if slot == 0 and main.players[0].vr:
		main.players[0].buzz(0.5, 0.08)


func _finish() -> void:
	var st := stage
	var opt: Variant = options[chosen]
	history.append([st, str(opt), chosen_by])
	stage = ""
	options = []
	orbs.clear()
	_clear_rests()
	spots = []
	flat_spots = []
	row = ""
	main.net.event("orbs", ["", [], [], "", []])
	if on_done.is_valid():
		on_done.call(st, opt, chosen_by)
