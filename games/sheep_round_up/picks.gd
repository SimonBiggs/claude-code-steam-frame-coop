extends "res://core/pick_flow.gd"
## SHEEP ROUND-UP PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (seasons.gd):
##   "mode"   GENTLE / BRAVE / HARD before the first field of a visit (the family's last mode in the middle).
##   "trick"  DOG TRICKS before fields 2, 4, 6 and 8 of a visit: three tricks not learned yet.
## The orbs float in a row just south of the pen (with a VR farmer: in front of the farmer, at chest height). A dog
## RUNS UNDER one (flat distance), the farmer TOUCHES one with a glove; the first touch decides for the team (a dot
## in their colour circles it). Nobody chooses in time? The middle orb (it glows brightest) is taken. The field's
## clock waits while the orbs are up. Host / local decide; the host keeps the "orbs" state [stage, entries, origin]
## (sticky: a machine joining mid-pick sees them) and sends "take" [i, slot] events; every machine draws.

const VrRig := preload("res://core/vr_rig.gd")

const WAIT := {"mode": 14.0, "trick": 12.0}
const GAP := 1.5
const Y := 1.2
const DOG_R := 0.45  # + the orb's hit radius: how close (flat) a dog must run under an orb
const HAND_R := 0.15

var origin := Vector3.ZERO


func _init() -> void:
	after = 1.2
	waits = WAIT
	hand_r = HAND_R
	sync = "state"


## Where the row goes: in front of the VR farmer's head, else over the field by the pen.
func row_origin() -> Vector3:
	if main.vr_rig != null and main.vr_rig.camera != null:
		var cam: Node3D = main.vr_rig.camera
		var f := -cam.global_basis.z
		f.y = 0.0
		f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
		var p: Vector3 = cam.global_position + f * 0.9
		return Vector3(p.x, maxf(0.5, cam.global_position.y - 0.6) - Y, p.z)
	return Vector3(0.0, 0.0, main.PEN + 1.6)


## Host / local: put up the orbs. entries: [{id, name, pic, color}], opts: what each orb means.
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	start(new_stage, opts, done)
	origin = row_origin()
	show_row(new_stage, entries, origin)
	publish([new_stage, entries, origin])


func orbs_off() -> Array:
	return ["", [], Vector3.ZERO]


func show_row(new_stage: String, entries: Array, at: Vector3) -> void:
	if new_stage == "" or entries.is_empty():
		orbs.clear()
		return
	var vr: bool = main.vr_rig != null
	orbs.show_orbs(new_stage, entries, at, GAP * (0.3 if vr else 1.0), Y, {"scale": 0.2 if vr else 0.8, "pop": true, "two_lines": true})


## The dogs running under an orb, the VR farmer's hands reaching into one.
func takers() -> Dictionary:
	var points := {}
	for slot in main.dogs:
		var d: Node3D = main.dogs[slot]
		points["d%d" % int(slot)] = [Vector3(d.position.x, origin.y + Y, d.position.z), int(slot), "run"]
	if main.vr_rig != null:
		for h in [VrRig.LEFT, VrRig.RIGHT]:
			points["h%d" % h] = [main.vr_rig.hand_point(h), 0, "hand"]
	return points


func orb_at(kind: String, point: Variant) -> int:
	return orbs.nearest_hit(point, hand_r if kind == "hand" else DOG_R)


func slot_color(slot: int) -> Color:
	return main.party.color_of(slot)


func fx(i: int, slot: int, at: Vector3, col: Color) -> void:
	if at != Vector3.INF:
		main.sound("ding", -2.0, 1.0 + 0.1 * i)
		main.burst(at, col, 14)
	if slot == 0 and main.vr_rig != null and taker.begins_with("h"):
		main.vr_rig.pulse(int(taker.substr(1)), 0.6, 0.08)
