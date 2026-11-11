extends Node
## WHACK-A-MOLE PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle).
##   "crop"  which crop Fig plants when a bed is full (story.gd offers) - was two seed packets in the holes.
##   "gift"  FIG'S HAMMER GIFTS before every round: three of BIG HAMMER, SLEEPY DUST, GOLD GLOVE, BOING HAMMER,
##           CARROT BAG.
## Three little glass orbs float in a row over the front of the table: a hammer-kid runs into one, the VR giant bonks
## one with the mallet (or touches it with a glove) - the front row is an easy reach from where the giant stands, so a
## giant playing alone always gets every orb. The first one decides for the team (a dot in their colour circles it).
## Nobody in time? The middle orb (it glows brightest) is taken - a solo giant or a little one is never stuck. The
## host sends the sticky "orbs" event [stage, entries] (a machine joining mid-pick sees the orbs too) and "take" [i, slot].

const PickOrbs := preload("res://core/pick_orbs.gd")
const VrRig := preload("res://core/vr_rig.gd")
const Props := preload("res://games/whack_a_mole/props.gd")

const WAIT := {"mode": 14.0, "crop": 12.0, "gift": 10.0}
const AFTER := 1.0  # seconds the taken orb shows its dot before the orbs go
const ROW_Z := 0.95  # over the table's front edge (the giant stands at Props.HALF.y + 0.5)
const GAP := 0.95  # metres between orbs (more than 2 x TV_R: a hammer-kid touches one at a time)
const Y := 0.3  # above the table top
const SCALE := 0.3
const TV_R := 0.27  # how near a hammer-kid's feet must come to an orb's middle (across the table)
const HAND_R := 0.06  # the glove
const OPEN := 0.8  # seconds after the orbs pop up before they can be taken (a resting mallet never picks by itself)
const SWING := 0.6  # m/s: the mallet must be swung at an orb (like at a mole), a glove moved into one

var main: Node
var orbs: PickOrbs
var stage := ""  # host: "" | "mode" | "crop" | "gift"
var options: Array = []
var t := 0.0
var chosen := -1
var chosen_by := -1
var done_t := 0.0
var wait_scale := 1.0  # bots: shorter waits
var on_done: Callable  # host: (stage, option, slot)
var history: Array = []  # [stage, option, by] (telemetry, bots)


func _ready() -> void:
	name = "Picks"
	orbs = PickOrbs.new()
	orbs.collision_layer = 0
	main.add_child(orbs)


func active() -> bool:
	return stage != ""


func showing() -> bool:
	return not orbs.orbs.is_empty()


## The middle of the row (on the table top).
static func row_origin() -> Vector3:
	return Vector3(0.0, Props.TABLE_Y, ROW_Z)


## Where orb i of n floats (the deep test checks every one is over the table and in the giant's reach).
static func spot_of(i: int, n: int) -> Vector3:
	return PickOrbs.spot(i, n, row_origin(), GAP, Y)


## Host / local: put up the orbs. entries: [{id, name, pic, color}], opts: what each orb means.
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	stage = new_stage
	options = opts
	on_done = done
	t = float(WAIT.get(new_stage, 10.0)) * wait_scale
	chosen = -1
	chosen_by = -1
	done_t = 0.0
	show_row(new_stage, entries)
	main.net.event("orbs", [new_stage, entries])
	print("PICKS %s: %s" % [new_stage, opts])


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array) -> void:
	if new_stage == "" or entries.is_empty():
		orbs.clear()
		return
	orbs.show_orbs(new_stage, entries, row_origin(), GAP, Y, {"scale": SCALE, "pop": true, "font": 64,
		"label_y": 1.15, "label_px": 0.0055, "two_lines": true, "bob": 0.06})


## Orb i's middle in the world (bots run / reach there), INF if none.
func orb_position(i: int) -> Vector3:
	if i < 0 or i >= orbs.orbs.size() or not is_instance_valid(orbs.orbs[i]) or not (orbs.orbs[i] as Node3D).is_inside_tree():
		return Vector3.INF
	return (orbs.orbs[i] as Node3D).global_position


## Host / local, every frame while the orbs are up.
func tick(delta: float) -> void:
	if stage == "":
		return
	if chosen >= 0:
		done_t += delta
		if done_t >= AFTER:
			_finish()
		return
	var open := float(WAIT.get(stage, 10.0)) * wait_scale - t >= OPEN
	t -= minf(delta, 0.1)  # (a loading hitch never eats the wait)
	if not open:
		return
	for slot in main.avatars:
		var a: Node3D = main.avatars[slot]
		var o := orbs.at_point(a.global_position, TV_R)
		if o >= 0:
			take(o, int(slot))
			return
	if main.vr_rig != null:
		if main.mallet_head != null and main.mallet_vel.length() > SWING:
			var om := orbs.nearest_hit(main.mallet_head.global_position, Props.HEAD_R * main.mallet_head.scale.x)
			if om >= 0:
				main.vr_rig.pulse(VrRig.RIGHT, 0.6, 0.08)
				take(om, 0)
				return
		for h in [VrRig.LEFT, VrRig.RIGHT]:
			if main.vr_rig.hand_speed(h) < SWING * 0.5:
				continue
			var o2 := orbs.nearest_hit(main.vr_rig.hand_point(h), HAND_R)
			if o2 >= 0:
				main.vr_rig.pulse(h, 0.5, 0.08)
				take(o2, 0)
				return
	if t <= 0.0:
		take(options.size() / 2, -1)  # the middle one (it glows brightest)


## Host / local: orb i taken by slot (-1: nobody chose, the middle one).
func take(i: int, slot: int) -> void:
	if chosen >= 0 or i < 0 or i >= options.size():
		return
	chosen = i
	chosen_by = slot
	take_fx(i, slot)
	main.net.event("take", [i, slot])
	print("PICK %s: %s took %d (%s)" % [stage, "nobody" if slot < 0 else "P%d" % (slot + 1), i, str(options[i])])


## Every machine: a dot in the taker's colour circles orb i, a happy sound and a burst.
func take_fx(i: int, slot: int) -> void:
	var col: Color = main.party.color_of(slot) if slot >= 0 and main.avatars.has(slot) else Color(1, 1, 1)
	var at := orbs.take(i, col)
	if at != Vector3.INF:
		main.sfx.play_at("power_up", at, -2.0, 1.0 + 0.1 * i)
		main.burst_at(at, Color(1.0, 0.9, 0.4))


func _finish() -> void:
	var st := stage
	var opt: Variant = options[chosen]
	history.append([st, str(opt), chosen_by])
	stage = ""
	options = []
	orbs.clear()
	main.net.event("orbs", ["", []])
	if on_done.is_valid():
		on_done.call(st, opt, chosen_by)