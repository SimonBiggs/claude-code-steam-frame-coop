extends Node
## SNOWMAN MAKER PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), before the first snow day.
##   "gift"  TUMBLE'S GIFTS before every day from the second: three of COSY SCARF, CARROT NOSE, MAGIC HAT, SPARKLE
##           BUTTONS, SNOW BOOTS.
## Three small glass orbs float an arm's reach in front of the VR builder (deep.gd row_spots, from where they stand and
## look when the orbs come up; with no VR builder, bigger ones stand in the build circle). A TV player WALKS UNDER one;
## the VR builder REACHES into one on purpose (a glove has to move in after they pop up and stay a moment - a hand
## already resting there or sweeping past never picks). A player already standing under one when they pop up must
## step out and back in. The first one decides for the team (a dot in their colour circles it). Nobody in time? The
## middle orb (it glows brightest): a lone player or a little one is never stuck. The host sends the sticky "orbs"
## event [stage, entries, spots, scale] (a machine joining mid-pick sees the orbs too) and "take".

const PickOrbs := preload("res://core/pick_orbs.gd")
const Deep := preload("res://games/snowman_maker/deep.gd")
const Party := preload("res://core/party.gd")

const AFTER := 1.1  # seconds the taken orb shows its dot before the orbs go
const OPEN := 0.8  # seconds after the orbs pop up before they can be taken
const RESTING := 99  # inside[id]: a glove or a roller that was already in an orb when they opened

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
var inside := {}  # glove / slot id -> orb index it is in now (-1 none)
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
	var vr: bool = main.vr_rig != null
	spots = Deep.row_spots(entries.size(), vr, main.vr_rig.head_position() if vr else Deep.G.VR_START,
		main.vr_rig.head_forward() if vr else Vector3.FORWARD)
	show_row(new_stage, entries, spots, Deep.orb_scale(vr))
	main.net.event("orbs", [new_stage, entries, spots, Deep.orb_scale(vr)])
	print("PICKS %s: %s" % [new_stage, opts])


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array, at: Array, scale: float = Deep.ORB_SCALE) -> void:
	if new_stage == "" or entries.is_empty() or at.size() < entries.size():
		orbs.clear()
		return
	# (names under the orbs: never at the VR builder's eyes; by the VR builder the orbs sit an arm's reach away, small)
	orbs.show_orbs(new_stage, entries, at[0], 0.7, 0.0, {"at": at, "scale": scale, "pop": true, "font": 56,
		"label_y": -1.3, "label_px": 0.005 if scale < 0.4 else 0.007, "two_lines": true, "bob": 0.04})


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


## This frame's pick ([orb, slot] or []): a glove moving into an orb and staying a moment (VR, slot 0), or a TV
## player walking under one they weren't under when the orbs came up.
func _pick(delta: float) -> Array:
	var points := {}  # id -> [point, slot, is_glove]
	if main.vr_rig != null:
		for h in 2:
			points["g%d" % h] = [main.vr_rig.hand_point(h), 0, true]
	for slot in main.avatars:
		var a: Node3D = main.avatars[slot]
		if is_instance_valid(a):
			points["s%d" % int(slot)] = [a.position, int(slot), false]
	var got: Array = []
	for id in points:
		var pos: Vector3 = points[id][0]
		var glove: bool = points[id][2]
		var i := -1
		if glove:
			i = orbs.nearest_hit(pos, Deep.HAND_R)
		else:
			for j in spots.size():
				var sp: Vector3 = spots[j]
				if Vector2(sp.x - pos.x, sp.z - pos.z).length() < Deep.tv_r(main.vr_rig != null):
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
			if float(dwell[id]) >= (Deep.DWELL if glove else Deep.TV_DWELL) and got.is_empty():
				got = [i, int(points[id][1])]
	return got


## Host / local: orb i taken by slot (0 = the VR builder or P1, -1: nobody chose, the middle one).
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
		main.burst(at, col, 18, 3.0)
	if slot == 0 and main.vr_rig != null:
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
	main.net.event("orbs", ["", [], []])
	if on_done.is_valid():
		on_done.call(st, opt, chosen_by)
