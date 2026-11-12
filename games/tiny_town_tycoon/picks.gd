extends Node
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

const PickOrbs := preload("res://core/pick_orbs.gd")
const Party := preload("res://core/party.gd")
const Deep := preload("res://games/tiny_town_tycoon/deep.gd")

const AFTER := 1.1  # seconds the taken orb shows its dot before the orbs go
const OPEN := 0.8  # seconds after the orbs pop up before they can be taken
const RESTING := 99  # inside[id]: a hand or a vehicle that was already in an orb when they opened

var main
var orbs: PickOrbs
var stage := ""  # host: "" | "mode" | "gift"
var options: Array = []
var spots: Array = []  # every machine: the orbs' middles (Vector3)
var row := ""  # every machine: "island" | "vr"
var t := 0.0
var chosen := -1
var chosen_by := -1
var done_t := 0.0
var on_done: Callable  # host: (stage, option, slot)
var history: Array = []  # [stage, option, by] (telemetry, bots)
var inside := {}  # hand / vehicle id -> orb index it is in now (-1 none)
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
	var at: Array = Deep.vr_spots(main.vr_rig.camera.global_transform, entries.size()) if new_row == "vr" else Deep.row_spots(main.town, entries.size())
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
	if new_row == "vr":  # a modest ball an arm's reach away; the names over each ball, never at the mayor's eyes
		orbs.show_orbs(new_stage, entries, at[0], 0.0, 0.0, {"at": at, "scale": Deep.VR_SCALE, "pop": true, "font": 56,
			"label_y": 1.2, "label_px": 0.0042, "two_lines": true, "bob": 0.01, "hit_r": PickOrbs.BALL_R, "dot_r": 0.8})
	else:  # over the road by the hall, the names over the balls (the toy town's houses stand round them)
		orbs.show_orbs(new_stage, entries, at[0], 0.0, 0.0, {"at": at, "scale": Deep.ORB_SCALE, "pop": true, "font": 64,
			"label_y": 1.25, "label_px": 0.0105, "two_lines": true, "bob": 0.08, "for_others": main.vr_rig != null})
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


## This frame's pick ([orb, slot] or []): a VR grab point moving into a small orb and staying a moment (slot 0), a
## driver's vehicle standing under an island orb, or the flat mayor's cursor held under one.
func _pick(delta: float) -> Array:
	var points := {}  # id -> [point, slot, hand]
	if row == "vr" and main.vr_rig != null:
		for h in 2:
			points["h%d" % h] = [main.vr_rig.hand_point(h), 0, true]
	elif row == "island":
		if main.flat != null:
			points["f"] = [main.flat.cursor_point(), 0, false]
		for slot in main.party.active_slots():
			var v: Node3D = main.fleet.vehicle_of(int(slot)) if int(slot) >= 1 else null
			if v != null:  # people only: the AI drivers never pick
				points["v%d" % int(slot)] = [v.position, int(slot), false]
	var got: Array = []
	for id in points:
		var pos: Vector3 = points[id][0]
		var hand: bool = points[id][2]
		var i := orbs.nearest_hit(pos, Deep.HAND_R) if hand else Deep.under(spots, pos)
		if not inside.has(id):  # where it was when the orbs came up: resting in one is never a pick until it leaves
			inside[id] = RESTING if i >= 0 else -1
		var before := int(inside[id])
		if before == RESTING:
			inside[id] = RESTING if i >= 0 else -1
			dwell[id] = 0.0
			continue
		if i != before:
			dwell[id] = 0.0
			if i >= 0:
				print("PICKS: %s is in orb %d (%.1f s)" % [id, i, t])
		inside[id] = i
		if i >= 0 and t >= OPEN:
			dwell[id] = float(dwell.get(id, 0.0)) + delta
			if float(dwell[id]) >= (Deep.DWELL if hand else Deep.TV_DWELL) and got.is_empty():
				got = [i, int(points[id][1])]
	return got


## Host / local: orb i taken by slot (0 = the mayor, a driver's slot, -1: nobody chose, the middle one).
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
		main.sfx.play_at("power_up", at, -4.0, 1.0 + 0.1 * i)
		main.view.call("burst", at, col, 18, 0.8 if row == "vr" else 0.5)
	if slot == 0 and row == "vr" and main.vr_rig != null:
		main.vr_rig.pulse(0, 0.5, 0.08)
		main.vr_rig.pulse(1, 0.5, 0.08)


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
