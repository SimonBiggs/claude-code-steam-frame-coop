extends Node
## PAPER PLANES PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle).
##   "fold"  PIP'S PAPER FOLDS before every flight: three of GLIDER, DART, STUNT, RAINBOW, SWALLOW, COMET, plus
##           TODAY'S SKY as a fourth orb (the daily flight, the same sky for everyone).
## Big glass orbs float in an arc in the sky in front of the VR deck (deep.gd row_spots). A TV plane FLIES INTO one,
## a VR plane is THROWN into one (a pick is never a resting hand). The first one decides for the team (a dot in their
## colour circles it). Nobody took one by the wait (main.gd pick_time): the middle orb (it glows brightest) - a lone
## pilot or a little one is never stuck. The host sends the sticky "orbs" event [stage, entries, spots] (a machine
## joining mid-pick sees the orbs too) and "take" [i, slot].

const PickOrbs := preload("res://core/pick_orbs.gd")
const Deep := preload("res://games/paper_planes/deep.gd")

const AFTER := 1.0  # seconds the taken orb shows its dot before the orbs go
const OPEN := 0.8  # seconds after the orbs pop up before they can be taken

var main
var orbs: PickOrbs
var stage := ""  # host: "" | "mode" | "fold"
var options: Array = []
var spots: Array = []  # the orbs' places (world)
var t := 0.0
var chosen := -1
var chosen_by := -1
var done_t := 0.0
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


## Host / local: put up the orbs. entries: [{id, name, pic, color}], opts: what each orb means.
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	stage = new_stage
	options = opts
	on_done = done
	t = 0.0
	chosen = -1
	chosen_by = -1
	done_t = 0.0
	spots = Deep.row_spots(entries.size())
	show_row(new_stage, entries, spots)
	main.net.event("orbs", [new_stage, entries, spots])
	print("PICKS %s: %s" % [new_stage, opts])


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array, at: Array) -> void:
	if new_stage == "" or entries.is_empty() or at.size() < entries.size():
		orbs.clear()
		return
	orbs.show_orbs(new_stage, entries, Vector3(0.0, (at[0] as Vector3).y, 0.0), 4.0, 0.0, {"at": at, "scale": Deep.ORB_SCALE,
		"pop": true, "font": 72, "label_y": -1.05, "label_px": 0.006, "two_lines": true, "bob": 0.2})


## Orb i's middle in the world (bots fly there), INF if none.
func orb_position(i: int) -> Vector3:
	if i < 0 or i >= orbs.orbs.size() or not is_instance_valid(orbs.orbs[i]) or not (orbs.orbs[i] as Node3D).is_inside_tree():
		return Vector3.INF
	return (orbs.orbs[i] as Node3D).global_position


## Host / local: the orb a plane (or a VR paper plane) at pos is in (-1: none, or not open yet).
func hit_at(pos: Vector3, extra: float = 0.0) -> int:
	if not can_take() or orbs.orbs.is_empty():
		return -1
	return orbs.nearest_hit(pos, Deep.CATCH + extra)


## Host / local, every frame while the orbs are up. wait: seconds before the middle one is taken for the team.
func tick(delta: float, wait: float) -> void:
	if stage == "":
		return
	if chosen >= 0:
		done_t += delta
		if done_t >= AFTER:
			_finish()
		return
	t += minf(delta, 0.1)  # (a loading hitch never eats the wait)
	if t > wait:
		take(options.size() / 2, -1)  # nobody took one: the middle one (it glows brightest)


func can_take() -> bool:
	return stage != "" and chosen < 0 and t >= OPEN


## Seconds left to pick (the HUD timer).
func left(wait: float) -> float:
	return maxf(0.0, wait - t) if stage != "" and chosen < 0 else 0.0


## Host / local: orb i taken by slot (0 = the VR thrower or a flat host's pilot, -1: nobody chose, the middle one).
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
	var col: Color = main.party.color_of(slot) if slot >= 0 else Color(1, 1, 1)
	var at := orbs.take(i, col)
	if at != Vector3.INF:
		main.sfx.play("magic", -2.0, 1.0 + 0.1 * i)
		var cols: Array[Color] = [col, Color.WHITE]
		main.burst(at, cols, 40, 1.0)


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
