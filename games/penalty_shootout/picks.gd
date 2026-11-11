extends Node
## PENALTY SHOOTOUT PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), after practice.
##   "gift"  LEO'S GIFTS before every match from the second: three of BIG GLOVES, SLOW-MO, CURVE BOOTS, GOLDEN BALL,
##           BIG STAR.
## Three big glass orbs float in the goal mouth (deep.gd row_spots). The strikers take turns to KICK the ball through
## one (main.gd runs the kicks: the keeper can't save while picking); the keeper REACHES into one on purpose (a VR
## glove has to move in after they pop up and stay a moment - a hand already resting there or sweeping past never
## picks; a flat keeper shuffles under one, away from where they stood when the orbs came up). The first one decides
## for the team (a dot in their colour circles it). Nobody in time? The middle orb (it glows brightest) - a lone
## keeper or a little one is never stuck. The host sends the sticky "orbs" event [stage, entries, spots] (a machine
## joining mid-pick sees the orbs too) and "take" [i, slot].

const PickOrbs := preload("res://core/pick_orbs.gd")
const Deep := preload("res://games/penalty_shootout/deep.gd")

const AFTER := 1.1  # seconds the taken orb shows its dot before the orbs go
const OPEN := 0.8  # seconds after the orbs pop up before they can be taken
const RESTING := 99  # inside[id]: a glove (or a flat keeper) that was already in an orb when they opened

var main
var orbs: PickOrbs
var stage := ""  # host: "" | "mode" | "gift"
var options: Array = []
var spots: Array = []
var t := 0.0
var chosen := -1
var chosen_by := -1
var done_t := 0.0
var on_done: Callable  # host: (stage, option, slot)
var history: Array = []  # [stage, option, by] (telemetry, bots)
var inside := {}  # glove id -> orb index it is in now (-1 none)
var dwell := {}  # glove id -> seconds in that orb


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
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	stage = new_stage
	options = opts
	on_done = done
	t = 0.0
	chosen = -1
	chosen_by = -1
	done_t = 0.0
	inside = {}
	dwell = {}
	spots = Deep.row_spots(entries.size())
	show_row(new_stage, entries, spots)
	main.net.event("orbs", [new_stage, entries, spots])
	print("PICKS %s: %s" % [new_stage, opts])


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array, at: Array) -> void:
	if new_stage == "" or entries.is_empty() or at.size() < entries.size():
		orbs.clear()
		return
	orbs.show_orbs(new_stage, entries, at[0], 2.2, 0.0, {"at": at, "scale": Deep.ORB_SCALE, "pop": true, "font": 64,
		"label_y": 1.05, "label_px": 0.0055, "two_lines": true, "bob": 0.05})  # (names over the orbs, under the crossbar)


## Orb i's middle in the world (bots aim there), INF if none.
func orb_position(i: int) -> Vector3:
	if i < 0 or i >= orbs.orbs.size() or not is_instance_valid(orbs.orbs[i]) or not (orbs.orbs[i] as Node3D).is_inside_tree():
		return Vector3.INF
	var o = orbs.orbs[i]
	return o.icon.global_position if o.icon != null and o.icon.is_inside_tree() else (o as Node3D).global_position


func can_take() -> bool:
	return stage != "" and chosen < 0 and t >= OPEN


## Seconds left to pick.
func left() -> float:
	return maxf(0.0, Deep.wait_for(stage, main.pick_solo()) - t) if stage != "" and chosen < 0 else 0.0


## Every machine: the orb a ball at pos is in (-1: none).
func ball_hit(pos: Vector3) -> int:
	if orbs.orbs.is_empty():
		return -1
	return orbs.nearest_hit(pos, Deep.CATCH + 0.11)


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
	var o := _keeper_pick(delta)
	if o >= 0:
		take(o, 0)
		return
	if t > Deep.wait_for(stage, main.pick_solo()):
		take(options.size() / 2, -1)  # nobody took one: the middle one (it glows brightest)


## The keeper's pick this frame (-1 none): a glove moving into an orb and staying a moment (VR), or a flat keeper
## shuffling under one they weren't under when the orbs came up.
func _keeper_pick(delta: float) -> int:
	var k = main.keeper
	if k == null:
		return -1
	var points := {}
	if k.vr:
		points = {"l": k.glove_l, "r": k.glove_r}
	else:
		points = {"flat": Vector3(float(k.kx), Deep.ROW_Y, Deep.ROW_Z)}
	var got := -1
	for id in points:
		var pos: Vector3 = points[id]
		var i := -1
		if id == "flat":
			for j in spots.size():
				if absf((spots[j] as Vector3).x - pos.x) < Deep.FLAT_R:
					i = j
		else:
			i = orbs.nearest_hit(pos, Deep.HAND_R)
		var before := int(inside.get(id, -1))
		if t < OPEN or before == RESTING:  # in an orb as they open: never a pick until it leaves
			inside[id] = RESTING if i >= 0 else -1
			dwell[id] = 0.0
			continue
		if i != before:
			dwell[id] = 0.0
		inside[id] = i
		if i >= 0:
			dwell[id] = float(dwell.get(id, 0.0)) + delta
			if float(dwell[id]) >= (Deep.DWELL if id != "flat" else 0.15):
				got = i
	return got


## Host / local: orb i taken by slot (0 = the keeper, a striker's index, -1: nobody chose, the middle one).
func take(i: int, slot: int) -> void:
	if stage == "" or chosen >= 0 or i < 0 or i >= options.size():
		return
	chosen = i
	chosen_by = slot
	take_fx(i, slot)
	main.net.event("take", [i, slot])
	print("PICK %s: %s took %d (%s)" % [stage, "nobody" if slot < 0 else ("the keeper" if slot == 0 else "P%d" % (slot + 1)), i,
		str(options[i])])


## Every machine: a dot in the taker's colour circles orb i, a happy sound and a burst.
func take_fx(i: int, slot: int) -> void:
	var col: Color = main.PLAYER_COLORS[slot] if slot >= 0 and slot < main.PLAYER_COLORS.size() else Color(1, 1, 1)
	var at := orbs.take(i, col)
	if at != Vector3.INF:
		main.sound("power", -4.0, 1.0 + 0.1 * i)
		main.burst(at, col, 18, false)
	if slot == 0 and main.keeper != null and main.keeper.vr:
		main.keeper.haptic("both")


func _finish() -> void:
	var st := stage
	var opt: Variant = options[chosen]
	history.append([st, str(opt), chosen_by])
	stage = ""
	options = []
	spots = []
	orbs.clear()
	main.net.event("orbs", ["", [], []])
	if on_done.is_valid():
		on_done.call(st, opt, chosen_by)