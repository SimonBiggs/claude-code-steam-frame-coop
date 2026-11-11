extends Node
## MARBLE MAZE PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (worlds.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session, before the first story / daily maze (the family's last mode in the
##           middle).
##   "gift"  BOBO'S MARBLES before each place's first maze, today's maze and a session's first maze: three of HEAVY,
##           BOUNCY, MAGNET, STICKY, ZOOMY (worlds.gd gift_choices) - the whole team rolls as that kind.
## They happen on the PICK BOARD (main.gd PICK_MAP, an open room): three small glass orbs hover over the floor near
## the giant's edge (children of the board, so they tilt with it). A marble rolls UNDER one, the VR giant touches one
## with a hand; the first one decides for the team (a dot in their colour circles it). Nobody in time? The middle
## orb (it glows brightest) is taken. Host / local decide; the host sends the sticky "orbs" event [stage, entries]
## (a machine joining mid-pick sees the orbs too) and "take" [i, slot]; every machine draws.

const PickOrbs := preload("res://core/pick_orbs.gd")

const WAIT := {"mode": 14.0, "gift": 12.0}
const AFTER := 1.2  # seconds the taken orb shows its dot before the orbs go
## In board space: a row across the board 0.25 m towards the giant from the middle (row 7 of the pick map).
const ROW := Vector3(0.0, 0.0, 0.25)
const GAP := 0.33
const Y := 0.1  # the orb's middle above the floor: a marble (r 0.028) rolls under it
const SCALE := 0.065  # glass ball radius 0.6 * 0.055 = 3.3 cm: modest in VR, clear in the TV chase cams
const MARBLE_R := 0.045  # flat distance from the orb's middle a marble must roll to
const HAND_R := 0.035

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


func _ready() -> void:
	name = "Picks"
	orbs = PickOrbs.new()
	orbs.collision_layer = 0
	main.board.add_child(orbs)


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
	show_row(new_stage, entries)
	main.net.event("orbs", [new_stage, entries])
	print("PICKS %s: %s" % [new_stage, opts])


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array) -> void:
	if new_stage == "" or entries.is_empty():
		orbs.clear()
		return
	orbs.show_orbs(new_stage, entries, ROW, GAP, Y, {"scale": SCALE, "pop": true, "font": 64, "label_y": 1.35, "label_px": 0.008,
		"two_lines": true, "touch": 0.0, "bob": 0.15})


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
	for p in main.active_marbles():
		if p.falling:
			continue
		var o := orbs.at_point(p.global_position, MARBLE_R)
		if o >= 0:
			take(o, p.index)
			return
	var giant = main.players[0] if not main.players.is_empty() else null
	if giant != null and giant.vr and giant.hand_r != null:
		for h in [giant.hand_l, giant.hand_r]:
			var o2 := orbs.nearest_hit((h as Node3D).global_position, HAND_R)
			if o2 >= 0:
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
	var col: Color = main.players[slot].color if slot >= 0 and slot < main.players.size() else Color(1, 1, 1)
	var at := orbs.take(i, col)
	if at != Vector3.INF:
		main.sound("ring", -2.0, 1.0 + 0.1 * i)
		main.burst(at, col, 14, false)


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
