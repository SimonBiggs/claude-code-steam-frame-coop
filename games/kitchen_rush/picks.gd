extends Node
## KITCHEN RUSH PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (nights.gd):
##   "mode"  GENTLE / BRAVE / HARD after the practice toastie (the family's last mode in the middle).
##   "gift"  GRAN'S GIFTS before rounds 2, 4, 6 and 8: QUICK KNIFE, BIG POT, HELPER MOUSE, SKATES (three not taken).
## The orbs float in a row over the counter. A TV runner walks up to the pass under one, the VR chef touches one with
## a hand, the button chef grabs at the pass spot under one; the first one decides for the team (a dot in their
## colour circles it). Nobody chooses in time? The middle orb (it glows brightest) is taken.
## Host / local decide; the host sends the sticky "orbs" event [stage, entries] (a machine joining mid-pick sees the
## orbs too) and "take" [i, slot]; every machine draws.

const PickOrbs := preload("res://core/pick_orbs.gd")

const WAIT := {"mode": 14.0, "gift": 12.0}
const AFTER := 1.2  # seconds the taken orb shows its dot before the orbs go
## Over the middle of the counter: a runner at the pass stands ~0.7 m away (flat), the VR chef reaches it.
const ROW := Vector3(0.0, 0.95, -0.2)
const GAP := 0.72
const Y := 0.8
const SCALE := 0.3
## With a VR chef the row is smaller and lower (chest height, within reach, never filling the headset view).
const VR_GAP := 0.45
const VR_Y := 0.38
const VR_SCALE := 0.2
const RUNNER_R := 0.6  # + the orb's hit radius: how close (flat) a runner must stand
const HAND_R := 0.12

var main: Node
var orbs: PickOrbs
var stage := ""  # host: "" | "mode" | "gift"
var options: Array = []
var t := 0.0
var chosen := -1
var chosen_by := -1
var done_t := 0.0
var on_done: Callable  # host: (stage, option, slot)
var history: Array = []  # [stage, option, by] (telemetry)
var compact := false  # every machine: the VR chef's smaller row


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
	t = float(WAIT.get(new_stage, 12.0))
	chosen = -1
	chosen_by = -1
	done_t = 0.0
	var chef = main.players[0] if not main.players.is_empty() else null
	show_row(new_stage, entries, chef != null and chef.vr)
	main.net.event("orbs", [new_stage, entries, compact])
	print("PICKS %s: %s" % [new_stage, opts])


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array, small: bool = false) -> void:
	compact = small
	if new_stage == "" or entries.is_empty():
		orbs.clear()
		return
	orbs.show_orbs(new_stage, entries, ROW, VR_GAP if small else GAP, VR_Y if small else Y, {"scale": VR_SCALE if small else SCALE,
		"pop": true, "font": 56, "label_y": -1.0, "two_lines": true, "touch": 0.0})


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
	for i in range(1, main.players.size()):
		var p = main.players[i]
		if not p.active or p.ghost:
			continue
		var at: Vector3 = p.global_position
		var o := orbs.nearest_hit(Vector3(at.x, ROW.y + (VR_Y if compact else Y), at.z), RUNNER_R)
		if o >= 0:
			take(o, i)
			return
	var chef = main.players[0] if not main.players.is_empty() else null
	if chef != null and chef.vr and not chef.ghost and chef.hand_l != null:
		for h in 2:
			var o2 := orbs.nearest_hit(chef.hand_point(h), HAND_R)
			if o2 >= 0:
				take(o2, 0)
				return
	if t <= 0.0:
		take(options.size() / 2, -1)  # the middle one (it glows brightest)


## Host / local: the button chef grabbed at a counter spot; the orb over it (by x) is taken. True if it took one.
func chef_grab_at(spot: Vector3) -> bool:
	if stage == "" or chosen >= 0:
		return false
	var best := -1
	var best_d := 0.4
	for o in orbs.orbs:
		var d: float = absf(o.global_position.x - spot.x)
		if d < best_d:
			best_d = d
			best = o.index
	if best >= 0:
		take(best, 0)
	return best >= 0


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
	var col: Color = main.players[slot].color if slot >= 0 and slot < main.players.size() else Color(1, 1, 1)
	var at := orbs.take(i, col)
	if at != Vector3.INF:
		main.sfx_local("ding", -2.0, 1.0 + 0.1 * i)
		main.burst(at, col, 14, 0.05)


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
