extends Node
## TOWER STACK PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices:
##   "mode"   GENTLE / BRAVE / HARD before the first job of a visit (the family's last mode in the middle).
##   "build"  WREN'S NEXT JOB between jobs: three buildings (castle, lighthouse, windmill, ...) to build next, each a
##            seeded towergen job of the same level (so every one is validated). TODAY'S TOWER is never swapped.
## The orbs float in a row over the (empty) stage. A TV player WALKS into one, the VR giant TOUCHES one with a hand;
## the first touch decides for the team (a dot in their colour circles it). Nobody chooses in time? The middle orb
## (it glows brightest) is taken, so little ones are never stuck. The round clock waits while the orbs are up.
## Host / local decide; the host sends "orbs" [stage, entries] and "take" [i, slot] events, every machine draws.

const PickOrbs := preload("res://core/pick_orbs.gd")

const WAIT := {"mode": 12.0, "build": 10.0}
const AFTER := 1.0  # seconds the taken orb shows its dot before the orbs go
const ROW := Vector3(0.0, 0.0, 0.2)
const GAP := 2.8
const Y := 1.5
const AVATAR_Y := 1.0  # a TV player touches with this point over their feet
const AVATAR_R := 0.45
const HAND_R := 0.2

var main: Node
var orbs: PickOrbs
var stage := ""  # host: "" | "mode" | "build"
var options: Array = []  # host: what each orb means (mode ids / job descriptions)
var t := 0.0
var chosen := -1
var chosen_by := -1
var done_t := 0.0
var on_done: Callable  # host: (stage, option)
var history: Array = []  # host: what was chosen this round (telemetry)


func _ready() -> void:
	name = "Picks"
	orbs = PickOrbs.new()
	main.add_child(orbs)


func active() -> bool:
	return stage != ""


## Host / local: put up the orbs. entries: [{id, name, pic, color}], options: what each one means.
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	stage = new_stage
	options = opts
	on_done = done
	t = float(WAIT.get(new_stage, 10.0))
	chosen = -1
	chosen_by = -1
	done_t = 0.0
	show_row(new_stage, entries)
	if main.net.mode == "host":
		main.net.event("orbs", [new_stage, entries])


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array) -> void:
	if new_stage == "" or entries.is_empty():
		orbs.clear()
		return
	orbs.show_orbs(new_stage, entries, ROW, GAP, Y)


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
		var i := orbs.nearest_hit(a.position + Vector3.UP * AVATAR_Y, AVATAR_R)
		if i >= 0:
			take(i, int(slot))
			return
	if main.vr_rig != null:
		for w in 2:
			var i2 := orbs.nearest_hit(main.vr_rig.hand_point(w), HAND_R)
			if i2 >= 0:
				main.vr_rig.pulse(w, 0.6, 0.08)
				take(i2, 0)
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
	if main.net.mode == "host":
		main.net.event("take", [i, slot])
	print("PICK %s: %s took %d (%s)" % [stage, "nobody" if slot < 0 else "P%d" % (slot + 1), i, str(options[i])])


## Every machine: a dot in the taker's colour circles orb i, a happy sound.
func take_fx(i: int, slot: int) -> void:
	var col: Color = main.party.color_of(slot) if slot >= 0 else Color(1, 1, 1)
	var at := orbs.take(i, col)
	if at != Vector3.INF:
		main.sfx.play_at("ding", at, -2.0, 1.0 + 0.1 * i)


func _finish() -> void:
	var st := stage
	var opt: Variant = options[chosen]
	history.append([st, opt if opt is String else str(opt), chosen_by >= 0])
	stage = ""
	options = []
	orbs.clear()
	if main.net.mode == "host":
		main.net.event("orbs", ["", []])
	if on_done.is_valid():
		on_done.call(st, opt)
