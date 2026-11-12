extends Node
## BLOCK BUILDERS PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), before the first sky course.
##   "gift"  PUFF'S BLOCK GIFTS before every sky course from a session's second: three of STICKY BRICKS, BIG BRICKS,
##           BUILDER ROBOT, BLOCK BOX, JUMPY BOOTS.
## Rows (deep.gd): with runners who are people, three big orbs over the start island ("start": a runner STANDS under one
## deep.gd TV_DWELL s; running past never picks). A flat builder with only the buddy: three orbs over the middle of the
## course ("flat": the glove hovers under one TV_DWELL s). The VR builder with only the buddy: three small orbs an arm's
## reach in front of the builder's eyes ("vr": the hand moves into one and stays deep.gd DWELL s). The VR hand can
## touch any row's orb and the flat glove stand under any row's. Something already in an orb when they pop up must
## leave and come back. The first one decides (a dot in their colour circles it). Nobody in time? The middle orb (it
## glows brightest). The host sends the sticky "orbs" event [stage, entries, spots, row] (a machine joining mid-pick
## sees the orbs too) and "take" [orb, slot].

const PickOrbs := preload("res://core/pick_orbs.gd")
const Party := preload("res://core/party.gd")
const Deep := preload("res://games/block_builders/deep.gd")

const AFTER := 1.1  # seconds the taken orb shows its dot before the orbs go
const OPEN := 0.8  # seconds after the orbs pop up before they can be taken
const RESTING := 99  # inside[id]: a hand or a runner that was already in an orb when they opened

var main
var orbs: PickOrbs
var stage := ""  # host: "" | "mode" | "gift"
var options: Array = []
var spots: Array = []  # every machine: the orbs' middles (Vector3)
var row := ""  # every machine: "start" | "flat" | "vr"
var t := 0.0
var chosen := -1
var chosen_by := -1
var done_t := 0.0
var on_done: Callable  # host: (stage, option, slot)
var history: Array = []  # [stage, option, by] (telemetry, bots)
var inside := {}  # hand / runner id -> orb index it is in now (-1 none)
var dwell := {}  # id -> seconds in that orb


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
	var at: Array
	match new_row:
		"vr":
			at = Deep.vr_spots(main.builder.xr_camera.global_transform, entries.size())
		"flat":
			at = Deep.flat_spots(entries.size())
		_:
			at = Deep.row_spots(main.level_data(), entries.size())
	show_row(new_stage, entries, at, new_row)
	main.net.event("orbs", [new_stage, entries, spots, row])
	print("PICKS %s: %s (%s row)" % [new_stage, opts, row])


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array, at: Array, new_row: String) -> void:
	if new_stage == "" or entries.is_empty() or at.size() < entries.size():
		orbs.clear()
		spots = []
		row = ""
		return
	spots = at.duplicate()
	row = new_row
	match new_row:
		"vr":  # a modest ball an arm's reach away; the names over each ball, never at the builder's eyes
			var s := Deep.VR_SCALE * Deep.S
			orbs.show_orbs(new_stage, entries, at[0], 0.0, 0.0, {"at": at, "scale": s, "pop": true, "font": 56,
				"label_y": 1.2, "label_px": 0.0042 * Deep.S, "two_lines": true, "bob": 0.01 * Deep.S, "hit_r": PickOrbs.BALL_R, "dot_r": 0.8})
		"flat":
			orbs.show_orbs(new_stage, entries, at[0], 0.0, 0.0, {"at": at, "scale": Deep.FLAT_SCALE, "pop": true, "font": 64,
				"label_y": 1.2, "label_px": 0.0105, "two_lines": true, "bob": 0.08})
		_:  # the names over the balls: under them they met the runners' nameplates
			orbs.show_orbs(new_stage, entries, at[0], 0.0, 0.0, {"at": at, "scale": Deep.ORB_SCALE, "pop": true, "font": 64,
				"label_y": 1.25, "label_px": 0.0095, "two_lines": true, "bob": 0.06})
	main.pick_banner()


## Orb i's middle in the world (bots aim there), INF if none.
func orb_position(i: int) -> Vector3:
	if i < 0 or i >= orbs.orbs.size() or not is_instance_valid(orbs.orbs[i]) or not (orbs.orbs[i] as Node3D).is_inside_tree():
		return Vector3.INF
	var o = orbs.orbs[i]
	return o.icon.global_position if o.icon != null and o.icon.is_inside_tree() else (o as Node3D).global_position


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
	var got := _pick(delta)
	if got.size() == 2:
		take(int(got[0]), int(got[1]))
		return
	if t > Deep.wait_for(stage, main.pick_nobody()):
		take(options.size() / 2, -1)  # nobody took one: the middle one (it glows brightest)


## This frame's pick ([orb, slot] or []).
func _pick(delta: float) -> Array:
	var points := {}  # id -> [point, slot, hand]
	var b = main.builder
	if b != null and b.vr:
		points["h"] = [b.grab_point, 0, true]
	elif b != null and b.flat and not b.remote:
		points["g"] = [Vector3(b.cursor.x, 0.0, b.cursor.y), 0, false]
	for r in main.runners():
		if r.active and not r.buddy:  # people only: the buddy never picks
			points["r%d" % r.index] = [r.global_position, r.index, false]
	var got: Array = []
	for id in points:
		var pos: Vector3 = points[id][0]
		var hand: bool = points[id][2]
		var i := orbs.nearest_hit(pos, Deep.HAND_R * Deep.S) if hand else Deep.under(spots, pos)
		if not inside.has(id):  # where it was when the orbs came up: resting in one is never a pick until it leaves
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


## Host / local: orb i taken by slot (0 = the builder, a runner's index, -1: nobody chose, the middle one).
func take(i: int, slot: int) -> void:
	if stage == "" or chosen >= 0 or i < 0 or i >= options.size():
		return
	chosen = i
	chosen_by = slot
	take_fx(i, slot)
	main.net.event("take", [i, slot])
	print("PICK %s: %s took %d (%s)" % [stage, "nobody" if slot < 0 else "P%d" % (slot + 1), i, str(options[i])])


## Every machine: a dot in the taker's colour circles orb i, a happy sound and a burst.
func take_fx(i: int, slot: int) -> void:
	var col: Color = Party.COLORS[slot % Party.COLORS.size()] if slot >= 0 else Color(1, 1, 1)
	var at := orbs.take(i, col)
	if at != Vector3.INF:
		main.local_sound("ding", -4.0, 1.0 + 0.1 * i)
		main.burst(at, col, 18, 0.06 * Deep.S if row == "vr" else 0.12)
	if slot == 0 and row == "vr" and main.builder != null and main.builder.vr:
		main.builder._haptic(0.5, 0.08)


func _finish() -> void:
	var st := stage
	var opt: Variant = options[chosen]
	history.append([st, str(opt), chosen_by])
	stage = ""
	options = []
	spots = []
	orbs.clear()
	main.net.event("orbs", ["", [], [], ""])
	if on_done.is_valid():
		on_done.call(st, opt, chosen_by)
