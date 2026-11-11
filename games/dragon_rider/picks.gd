extends Node
## DRAGON RIDER PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), after the practice rings.
##   "gift"  SUNNY'S GIFTS before every stage: three of FIRE BREATH, SHIELD BUBBLE, BUNNY MAGNET, BUBBLE STORM, ZOOM WINGS.
## Three big glass orbs float across the sky ahead, ABOVE the flight line (deep.gd row_spots): the rider climbs and
## steers Sunny into one (reins in VR, the stick or keys flat), or a gunner bubbles one. Flying straight passes under
## them all (a pick is never a resting hand). The first one decides for the team (a dot in their colour circles it).
## Nobody took one by the time Sunny passes the row (or ROW_WAIT runs out): the middle orb (it glows brightest) - a
## solo rider or a little one is never stuck. The host sends the sticky "orbs" event [stage, entries, spots] (a machine
## joining mid-pick sees the orbs too) and "take" [i, slot].

const PickOrbs := preload("res://core/pick_orbs.gd")
const Deep := preload("res://games/dragon_rider/deep.gd")

const AFTER := 1.0  # seconds the taken orb shows its dot before the orbs go
const OPEN := 0.6  # seconds after the orbs pop up before they can be taken

var main
var orbs: PickOrbs
var stage := ""  # host: "" | "mode" | "gift"
var options: Array = []
var spots: Array = []  # the orbs' places (world)
var row_normal := Vector3.FORWARD  # Sunny's heading when the row appeared (passing the row = nobody chose)
var t := 0.0
var chosen := -1
var chosen_by := -1
var done_t := 0.0
var row_secs := Deep.ROW_SECS  # bots: a nearer row
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


## Host / local: put up the orbs ahead of Sunny. entries: [{id, name, pic, color}], opts: what each orb means.
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	stage = new_stage
	options = opts
	on_done = done
	t = 0.0
	chosen = -1
	chosen_by = -1
	done_t = 0.0
	var d: Node3D = main.dragon
	spots = Deep.row_spots(d.global_position, float(d.yaw), maxf(float(d.speed), float(d.cruise)), entries.size(), row_secs)
	row_normal = Basis(Vector3.UP, float(d.yaw)) * Vector3.FORWARD
	show_row(new_stage, entries, spots)
	main.net.event("orbs", [new_stage, entries, spots])
	print("PICKS %s: %s" % [new_stage, opts])


## Every machine: the row of orbs ("" stage: none). The orbs join the gunners' targets (bubbles pick them).
func show_row(new_stage: String, entries: Array, at: Array) -> void:
	if new_stage == "" or entries.is_empty() or at.size() < entries.size():
		_untarget()
		orbs.clear()
		return
	var sc := Deep.ORB_SCALE
	orbs.show_orbs(new_stage, entries, Vector3(0.0, (at[0] as Vector3).y, 0.0), Deep.ROW_GAP, 0.0, {"at": at, "scale": sc,
		"pop": true, "font": 72, "label_y": -1.05, "label_px": 0.006, "two_lines": true, "bob": 0.25, "group": "dr_targets"})
	for o in orbs.orbs:
		var n: Node3D = o
		n.set_meta("kind", "pickorb")
		n.set_meta("radius", PickOrbs.HIT_R * sc)
		n.set_meta("index", int(o.index))


func _untarget() -> void:
	for o in orbs.orbs:
		if is_instance_valid(o) and (o as Node).is_in_group("dr_targets"):
			(o as Node).remove_from_group("dr_targets")


## Orb i's middle in the world (bots fly there), INF if none.
func orb_position(i: int) -> Vector3:
	if i < 0 or i >= orbs.orbs.size() or not is_instance_valid(orbs.orbs[i]) or not (orbs.orbs[i] as Node3D).is_inside_tree():
		return Vector3.INF
	return (orbs.orbs[i] as Node3D).global_position


## Where the row floats (the middle orb), for the dragon's height band (main._simple_assist).
func row_center() -> Vector3:
	if spots.is_empty():
		return Vector3.INF
	return spots[spots.size() / 2]


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
	if t < OPEN:
		return
	var core: Vector3 = main.dragon.core_position()
	var o := orbs.nearest_hit(core, Deep.CATCH)
	if o >= 0:
		main.players[0].haptic("l", 0.6)
		main.players[0].haptic("r", 0.6)
		take(o, 0)
		return
	var mid: Vector3 = row_center()
	if t > Deep.ROW_WAIT or (mid != Vector3.INF and (core - mid).dot(row_normal) > Deep.catch_r() + 2.0):
		take(options.size() / 2, -1)  # flew past them all (or turned away): the middle one (it glows brightest)


## Host / local: orb i taken by slot (0 = the rider, a gunner's index, -1: nobody chose, the middle one).
func take(i: int, slot: int) -> void:
	if stage == "" or chosen >= 0 or i < 0 or i >= options.size():
		return
	chosen = i
	chosen_by = slot
	take_fx(i, slot)
	main.net.event("take", [i, slot])
	print("PICK %s: %s took %d (%s)" % [stage, "nobody" if slot < 0 else ("the rider" if slot == 0 else "P%d" % (slot + 1)), i, str(options[i])])


## Every machine: a dot in the taker's colour circles orb i, a happy sound and a burst.
func take_fx(i: int, slot: int) -> void:
	var col: Color = main.PLAYER_COLORS[slot] if slot >= 0 and slot < main.PLAYER_COLORS.size() else Color(1, 1, 1)
	var at := orbs.take(i, col)
	if at != Vector3.INF:
		main.local_sound("power", -3.0, 1.0 + 0.1 * i)
		main.puff(at, Color(1.0, 0.9, 0.4), 24, 0.3)


func _finish() -> void:
	var st := stage
	var opt: Variant = options[chosen]
	history.append([st, str(opt), chosen_by])
	stage = ""
	options = []
	spots = []
	_untarget()
	orbs.clear()
	main.net.event("orbs", ["", [], []])
	if on_done.is_valid():
		on_done.call(st, opt, chosen_by)
