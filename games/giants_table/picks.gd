extends Node
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

const PickOrbs := preload("res://core/pick_orbs.gd")
const Deep := preload("res://games/giants_table/deep.gd")

const AFTER := 1.1  # seconds the taken orb shows its dot before the orbs go
const OPEN := 0.8  # seconds after the orbs pop up before they can be taken
const RESTING := 99  # inside[id]: a hand or a knight that was already in an orb when they opened

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
var inside := {}  # hand / knight id -> orb index it is in now (-1 none)
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
	# (world units: 20 = 1 m for the VR Giant. hit_r is the ball's own radius, so nearest_hit means "touching the ball";
	# the names sit just under each ball, never at the Giant's eyes)
	orbs.show_orbs(new_stage, entries, at[0], 0.0, 0.0, {"at": at, "scale": Deep.ORB_SCALE, "pop": true, "font": 56,
		"label_y": -1.05, "label_px": 0.0075, "two_lines": true, "bob": 0.05, "hit_r": PickOrbs.BALL_R, "dot_r": 0.8})


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


## This frame's pick ([orb, slot] or []): a VR grab point moving into a ball and staying a moment (slot 0), the flat
## Giant's hand hovering over one, or a knight walking under one they weren't under when the orbs came up.
func _pick(delta: float) -> Array:
	var points := {}  # id -> [point, slot, how]
	var g = main.giant
	if g != null and not g.ghost:
		for h in g.hands.size():
			points["h%d" % h] = [g.hands[h].pos, 0, "vr" if g.vr else "flat"]
	for k in main.knights():
		if k.active and not k.is_down and not k.carried and k.is_inside_tree():
			points["k%d" % int(k.index)] = [k.global_position, int(k.index), "walk"]
	var got: Array = []
	for id in points:
		var pos: Vector3 = points[id][0]
		var how: String = points[id][2]
		var i := -1
		if how == "vr":
			i = orbs.nearest_hit(pos, Deep.HAND_R)
		else:
			var reach := Deep.FLAT_R if how == "flat" else Deep.TV_R
			for j in spots.size():
				var sp: Vector3 = spots[j]
				if Vector2(sp.x - pos.x, sp.z - pos.z).length() < reach:
					i = j
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
			if float(dwell[id]) >= (Deep.TV_DWELL if how == "walk" else Deep.DWELL) and got.is_empty():
				got = [i, int(points[id][1])]
	return got


## Host / local: orb i taken by slot (0 = the Giant, 1.. a knight, -1: nobody chose, the middle one).
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
	var cols: Array = main.PLAYER_COLORS
	var col: Color = cols[slot % cols.size()] if slot >= 0 else Color(1, 1, 1)
	var at := orbs.take(i, col)
	if at != Vector3.INF:
		main.sound("chime", -4.0, 1.0 + 0.1 * i, false)
		main.burst(at, col, 18, 0.3, false)
	var g = main.giant
	if slot == 0 and g != null and g.vr and not g.ghost:
		for h in g.hands:
			g.haptic(h, 0.5, 0.08)


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
