extends Node
## MINI GOLF PARTY PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, one choice for everyone (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), before the first hole.
##   "gift"  GUS'S GIFTS after the practice putt of every course: three of BOUNCY BALL, MAGNET CUP, LONG PUTTER,
##           RAINBOW BALL, GIANT CUP.
## The pick green (deep.gd pick_green) opens out into three pads with a modest orb floating at waist height over each.
## Everyone PUTTS their ball onto a pad (main.gd asks pad_hit() for every ball); the VR golfer can also REACH a hand
## into an orb on purpose (it has to move in after they pop up and stay a moment - a hand already resting there or
## sweeping past never picks). The first one decides for everyone (a dot in their colour circles it). Nobody in
## time? The middle orb (it glows brightest) - a lone golfer or a little one is never stuck. The host sends the
## sticky "orbs" event [stage, entries, spots] (a machine joining mid-pick sees the orbs too) and "take" [i, slot].

const PickOrbs := preload("res://core/pick_orbs.gd")
const Deep := preload("res://games/mini_golf_party/deep.gd")

const AFTER := 1.2  # seconds the taken orb shows its dot before the next hole
const OPEN := 0.8  # seconds after the orbs pop up before they can be taken
const RESTING := 99  # inside[id]: a glove that was already in an orb when they opened

var main
var orbs: PickOrbs
var stage := ""  # host: "" | "mode" | "gift"
var options: Array = []
var spots: Array = []
var green: Dictionary = {}
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


## Host / local: put up the orbs over the pick green's pads. entries: [{id, name, pic, color}], opts: what each means.
func begin(new_stage: String, d: Dictionary, entries: Array, opts: Array, done: Callable) -> void:
	stage = new_stage
	green = d
	options = opts
	on_done = done
	t = 0.0
	chosen = -1
	chosen_by = -1
	done_t = 0.0
	inside = {}
	dwell = {}
	spots = []
	for i in entries.size():
		spots.append(Deep.orb_spot(d, i))
	show_row(new_stage, entries, spots)
	main.net.event("orbs", [new_stage, entries, spots])
	print("PICKS %s: %s" % [new_stage, opts])


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array, at: Array) -> void:
	if new_stage == "" or entries.is_empty() or at.size() < entries.size():
		orbs.clear()
		return
	orbs.show_orbs(new_stage, entries, at[0], 0.85, 0.0, {"at": at, "scale": Deep.ORB_SCALE, "pop": true, "font": 72,
		"label_y": -0.95, "label_px": 0.0055, "two_lines": true, "bob": 0.03})  # (names under the orbs, over the pads)


## Orb i's middle in the world (bots reach there), INF if none.
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


## Host: the pad a ball at p (Vector2 on the green) is on (-1: none, or not open yet).
func pad_hit(p: Vector2) -> int:
	if not can_take():
		return -1
	var i := Deep.pad_at(green, p)
	return i if i < options.size() else -1


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
	var o := _hand_pick(delta)
	if o >= 0:
		take(o, 0)
		return
	if t > Deep.wait_for(stage, main.pick_solo()):
		take(options.size() / 2, -1)  # nobody took one: the middle one (it glows brightest)


## The VR golfer's pick this frame (-1 none): a glove moving into an orb and staying a moment.
func _hand_pick(delta: float) -> int:
	if main.vr_rig == null:
		return -1
	var points := {"l": main.vr_rig.hand_l.global_position, "r": main.vr_rig.hand_r.global_position}
	var got := -1
	for id in points:
		var i := orbs.nearest_hit(points[id], Deep.HAND_R)
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
			if float(dwell[id]) >= Deep.DWELL:
				got = i
	return got


## Host / local: orb i taken by slot (-1: nobody chose, the middle one).
func take(i: int, slot: int) -> void:
	if stage == "" or chosen >= 0 or i < 0 or i >= options.size():
		return
	chosen = i
	chosen_by = slot
	take_fx(i, slot)
	main.net.event("take", [i, slot])
	print("PICK %s: %s took %d (%s)" % [stage, "nobody" if slot < 0 else "P%d" % (slot + 1), i, str(options[i])])


## Every machine: a dot in the taker's colour circles orb i, a happy sound and confetti.
func take_fx(i: int, slot: int) -> void:
	var col: Color = main.Party.COLORS[slot % main.Party.COLORS.size()] if slot >= 0 else Color(1, 1, 1)
	var at := orbs.take(i, col)
	if at != Vector3.INF:
		main.sfx.play("power_up", -4.0, 1.0 + 0.1 * i)
		main.celebrate_fx(at, col)
	if slot == 0 and main.vr_rig != null:
		main.vr_rig.pulse(main.VrRig.RIGHT, 0.6, 0.12)


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
