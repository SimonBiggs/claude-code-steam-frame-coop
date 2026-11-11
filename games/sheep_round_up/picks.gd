extends Node
## SHEEP ROUND-UP PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (seasons.gd):
##   "mode"   GENTLE / BRAVE / HARD before the first field of a visit (the family's last mode in the middle).
##   "trick"  DOG TRICKS before fields 2, 4, 6 and 8 of a visit: three tricks not learned yet.
## The orbs float in a row just south of the pen (with a VR farmer: in front of the farmer, at chest height). A dog
## RUNS UNDER one (flat distance), the farmer TOUCHES one with a glove; the first touch decides for the team (a dot
## in their colour circles it). Nobody chooses in time? The middle orb (it glows brightest) is taken. The field's
## clock waits while the orbs are up. Host / local decide; the host keeps the "orbs" state [stage, entries, origin]
## (sticky: a machine joining mid-pick sees them) and sends "take" [i, slot] events; every machine draws.

const PickOrbs := preload("res://core/pick_orbs.gd")
const VrRig := preload("res://core/vr_rig.gd")

const WAIT := {"mode": 14.0, "trick": 12.0}
const AFTER := 1.2
const GAP := 1.5
const Y := 1.2
const DOG_R := 0.45  # + the orb's hit radius: how close (flat) a dog must run under an orb
const HAND_R := 0.15

var main: Node
var orbs: PickOrbs
var stage := ""
var options: Array = []
var origin := Vector3.ZERO
var t := 0.0
var chosen := -1
var chosen_by := -1
var done_t := 0.0
var on_done: Callable  # host: (stage, option, slot)
var history: Array = []  # [stage, option, by]


func _ready() -> void:
	name = "Picks"
	orbs = PickOrbs.new()
	orbs.collision_layer = 0
	main.add_child(orbs)


func active() -> bool:
	return stage != ""


func showing() -> bool:
	return not orbs.orbs.is_empty()


## Host: where the row goes: in front of a VR farmer (chest height), else just south of the pen (dogs run under it).
func row_origin() -> Vector3:
	if main.vr_rig != null and main.vr_rig.camera != null:
		var cam: Node3D = main.vr_rig.camera
		var f := -cam.global_basis.z
		f.y = 0.0
		f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
		var p: Vector3 = cam.global_position + f * 0.75
		return Vector3(p.x, maxf(0.6, cam.global_position.y - 0.45) - Y, p.z)
	return Vector3(0.0, 0.0, main.PEN + 1.6)


func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	stage = new_stage
	options = opts
	on_done = done
	t = float(WAIT.get(new_stage, 12.0))
	chosen = -1
	chosen_by = -1
	done_t = 0.0
	origin = row_origin()
	show_row(new_stage, entries, origin)
	main.net.state_set("orbs", [new_stage, entries, origin])
	print("PICKS %s: %s" % [new_stage, opts])


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array, at: Vector3) -> void:
	if new_stage == "" or entries.is_empty():
		orbs.clear()
		return
	var vr: bool = main.vr_rig != null
	orbs.show_orbs(new_stage, entries, at, GAP * (0.3 if vr else 1.0), Y, {"scale": 0.32 if vr else 0.8, "pop": true, "two_lines": true})


func tick(delta: float) -> void:
	if stage == "":
		return
	if chosen >= 0:
		done_t += delta
		if done_t >= AFTER:
			_finish()
		return
	t -= delta
	for slot in main.dogs:
		var d: Node3D = main.dogs[slot]
		var o := orbs.nearest_hit(Vector3(d.position.x, origin.y + Y, d.position.z), DOG_R)
		if o >= 0:
			take(o, int(slot))
			return
	if main.vr_rig != null:
		for h in [VrRig.LEFT, VrRig.RIGHT]:
			var o2 := orbs.nearest_hit(main.vr_rig.hand_point(h), HAND_R)
			if o2 >= 0:
				main.vr_rig.pulse(h, 0.6, 0.08)
				take(o2, 0)
				return
	if t <= 0.0:
		take(options.size() / 2, -1)


func take(i: int, slot: int) -> void:
	if chosen >= 0 or i < 0 or i >= options.size():
		return
	chosen = i
	chosen_by = slot
	take_fx(i, slot)
	main.net.event("take", [i, slot])
	print("PICK %s: %s took %d (%s)" % [stage, "nobody" if slot < 0 else "P%d" % (slot + 1), i, str(options[i])])


func take_fx(i: int, slot: int) -> void:
	var col: Color = main.party.color_of(slot) if slot >= 0 else Color(1, 1, 1)
	var at := orbs.take(i, col)
	if at != Vector3.INF:
		main.sound("ding", -2.0, 1.0 + 0.1 * i)
		main.burst(at, col, 14)


func _finish() -> void:
	var st := stage
	var opt: Variant = options[chosen]
	history.append([st, str(opt), chosen_by])
	stage = ""
	options = []
	orbs.clear()
	main.net.state_set("orbs", ["", [], Vector3.ZERO])
	if on_done.is_valid():
		on_done.call(st, opt, chosen_by)
