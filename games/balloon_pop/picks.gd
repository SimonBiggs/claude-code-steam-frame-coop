extends Node
## BALLOON POP PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (skies.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session, after the practice balloons (the family's last mode in the middle).
##   "gift"  POPPY'S GIFTS before every round: three of DART, PUMP, SLOW, MAGNET, POP POP (skies.gd gift_choices).
## Three glass orbs float in a row in the park between the VR player and the middle, at chest height. A TV player
## runs into one, the VR player touches one with a glove; the first one decides for the team (a dot in their colour
## circles it). Nobody in time? The middle orb (it glows brightest) is taken - a solo VR player or a little one is
## never stuck. Host / local decide; the host sends the sticky "orbs" event [stage, entries] (a machine joining
## mid-pick sees the orbs too) and "take" [i, slot]; every machine draws.

const PickOrbs := preload("res://core/pick_orbs.gd")
const VrRig := preload("res://core/vr_rig.gd")

const WAIT := {"mode": 14.0, "gift": 10.0}
const AFTER := 1.0  # seconds the taken orb shows its dot before the orbs go
## The row: in front of the VR player's spot (wavegen.gd VR_HOME (0, 2)), between them and the middle.
const ROW := Vector3(0.0, 0.0, 0.75)  # 1.25 m ahead of the VR player: all three in view at once
const GAP := 1.0
const Y := 1.15
const SCALE := 0.5  # glass ball radius 0.3 m: a balloon's size
const TV_R := 0.45  # flat distance from an orb's middle a TV player must run to
const HAND_R := 0.12

var main: Node
var orbs: PickOrbs
var stage := ""  # host: "" | "mode" | "gift"
var options: Array = []
var t := 0.0
var chosen := -1
var chosen_by := -1
var done_t := 0.0
var wait_scale := 1.0  # bots: shorter waits
var on_done: Callable  # host: (stage, option, slot)
var history: Array = []  # [stage, option, by] (telemetry)


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
	orbs.show_orbs(new_stage, entries, ROW, GAP, Y, {"scale": SCALE, "pop": true, "font": 64, "label_y": -1.05,
		"label_px": 0.008, "two_lines": true, "bob": 0.08})


## The middle of orb i (bots walk there).
func orb_position(i: int) -> Vector3:
	if i < 0 or i >= orbs.orbs.size() or not is_instance_valid(orbs.orbs[i]):
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
	t -= delta
	for slot in main.avatars:
		var a: Node3D = main.avatars[slot]
		var o := orbs.at_point(a.global_position, TV_R)
		if o >= 0:
			take(o, int(slot))
			return
	if main.vr_rig != null:
		for h in [VrRig.LEFT, VrRig.RIGHT]:
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


## Every machine: a dot in the taker's colour circles orb i, a happy sound.
func take_fx(i: int, slot: int) -> void:
	var col: Color = main.player_color(slot) if slot >= 0 else Color(1, 1, 1)
	var at := orbs.take(i, col)
	if at != Vector3.INF:
		main.sound_at("power_up", at, -2.0, 1.0 + 0.1 * i)
		main.confetti(at, 24, 1.0)


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
