extends "res://core/pick_flow.gd"
## TREASURE DIG PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"    GENTLE / BRAVE / HARD once a session (the family's last mode in the middle).
##   "island"  which island next (story.gd offers: three kinds, the least visited first) - was two signposts.
##   "gift"    CAPTAIN PEG'S TOOLS before every island: three of BIG SPADE, DETECTOR, PEG'S MAP, POLLY, LUCKY CHARM.
## Three glass orbs float in a row on the sand: behind the chest, where every TV camera looks, or, with a VR giant
## here, between the chest and the giant wherever they wade (the row turns to face them, so the giant always sees
## and reaches every orb; behind the chest they hid under it and the island's hump, 2026-11-12). A TV digger runs into one, the giant
## touches one with a glove; the first one decides for the team (a dot in their colour circles it). Nobody in time?
## The middle orb (it glows brightest) is taken - a solo giant or a little one is never stuck. The host sends the
## sticky "orbs" event [stage, entries, row] (a machine joining mid-pick sees the orbs too) and "take" [i, slot].

const VrRig := preload("res://core/vr_rig.gd")

const WAIT := {"mode": 14.0, "island": 12.0, "gift": 10.0}
const ROW_R := 5.0  # beach units from the chest towards the giant (who wades at ISLAND * S + 0.25 = 9 units): an arm away
const GAP := 2.2  # beach units between orbs (more than 2 x TV_R: a digger touches one at a time)
const Y := 2.0  # beach units above the sand (diggers touch by distance across the sand; ~1.3 m up for the giant). At 1.5 a two-line name
# under the ball dipped into the sand (a seated giant saw SUNNY ISLE's bottom line cut off, 2026-11-12).
const SCALE := 1.0
const TV_R := 0.95  # beach units from an orb's middle a digger must run to
const HAND_R := 0.06  # metres (the glove)


func _init() -> void:
	after = 1.0
	waits = WAIT
	wait_default = 10.0
	hand_r = HAND_R


## The orbs live on the beach (scaled by main.S).
func orbs_parent() -> Node:
	return main.beach


## The row: [middle (beach units), yaw] from the chest towards `toward`, facing `viewer` (default the same way).
func row_at(toward: Vector3, viewer: Vector3 = Vector3.INF) -> Array:
	var d := Vector2(toward.x, toward.z)
	d = d.normalized() if d.length() > 0.1 else Vector2(0.0, 1.0)
	var v := d if viewer == Vector3.INF else Vector2(viewer.x, viewer.z).normalized()
	return [Vector3(d.x, 0.0, d.y) * ROW_R, atan2(v.x, v.y)]


static func spot_of(row: Array, i: int, n: int) -> Vector3:
	var yaw := float(row[1])
	return (row[0] as Vector3) + Vector3(cos(yaw), 0.0, -sin(yaw)) * (float(i) - (n - 1) * 0.5) * GAP + Vector3(0.0, Y, 0.0)


## Host / local: put up the orbs. entries: [{id, name, pic, color}], opts: what each orb means, row: row_at(...).
func begin(new_stage: String, entries: Array, opts: Array, row: Array, done: Callable) -> void:
	start(new_stage, opts, done)
	show_row(new_stage, entries, row)
	publish([new_stage, entries, row])


func show_row(new_stage: String, entries: Array, row: Array) -> void:
	if new_stage == "" or entries.is_empty() or row.size() < 2:
		orbs.clear()
		return
	orbs.position = row[0]
	orbs.rotation.y = float(row[1])
	var s: float = main.S
	orbs.show_orbs(new_stage, entries, Vector3.ZERO, GAP, Y, {"scale": SCALE, "pop": true, "font": 64,
		"label_y": -1.25, "label_px": 0.007, "two_lines": true, "bob": 0.12, "hit_r": PickOrbs.BALL_R * s})


## Orb i's middle in beach units (bots walk there), INF if none.
func orb_position(i: int) -> Vector3:
	if i < 0 or i >= orbs.orbs.size() or not is_instance_valid(orbs.orbs[i]):
		return Vector3.INF
	return main.beach.to_local((orbs.orbs[i] as Node3D).global_position)


func orb_global(i: int) -> Vector3:
	if i < 0 or i >= orbs.orbs.size() or not is_instance_valid(orbs.orbs[i]):
		return Vector3.INF
	return (orbs.orbs[i] as Node3D).global_position


## The diggers running under an orb, the VR giant's gloves reaching into one.
func takers() -> Dictionary:
	var points := {}
	for slot in main.avatars:
		var a: Node3D = main.avatars[slot]
		points["p%d" % int(slot)] = [a.global_position, int(slot), "walk"]
	if main.vr_rig != null:
		for h in [VrRig.LEFT, VrRig.RIGHT]:
			points["h%d" % h] = [main.vr_rig.hand_point(h), 0, "hand"]
	return points


func orb_at(kind: String, point: Variant) -> int:
	return orbs.nearest_hit(point, hand_r) if kind == "hand" else orbs.at_point(point, TV_R * float(main.S))


func slot_color(slot: int) -> Color:
	return main.party.color_of(slot) if main.avatars.has(slot) else Color(1, 1, 1)


func fx(i: int, slot: int, at: Vector3, _col: Color) -> void:
	if at != Vector3.INF:
		main.sfx.play_at("power_up", at, -2.0, 1.0 + 0.1 * i)
		main.burst_at(main.beach.to_local(at), Color(1.0, 0.9, 0.4))
	if slot == 0 and main.vr_rig != null and taker.begins_with("h"):
		main.vr_rig.pulse(int(taker.substr(1)), 0.5, 0.08)
