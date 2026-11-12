extends Node
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

const PickOrbs := preload("res://core/pick_orbs.gd")
const VrRig := preload("res://core/vr_rig.gd")

const WAIT := {"mode": 14.0, "island": 12.0, "gift": 10.0}
const AFTER := 1.0  # seconds the taken orb shows its dot before the orbs go
const ROW_R := 5.0  # beach units from the chest towards the giant (who wades at ISLAND * S + 0.25 = 9 units): an arm away
const GAP := 2.2  # beach units between orbs (more than 2 x TV_R: a digger touches one at a time)
const Y := 2.0  # beach units above the sand (diggers touch by distance across the sand; ~1.3 m up for the giant). At 1.5 a two-line name
# under the ball dipped into the sand (a seated giant saw SUNNY ISLE's bottom line cut off, 2026-11-12).
const SCALE := 1.0
const TV_R := 0.95  # beach units from an orb's middle a digger must run to
const HAND_R := 0.06  # metres (the glove)

var main: Node
var orbs: PickOrbs
var stage := ""  # host: "" | "mode" | "island" | "gift"
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
	main.beach.add_child(orbs)


func active() -> bool:
	return stage != ""


func showing() -> bool:
	return not orbs.orbs.is_empty()


## Host: where the row goes: [middle (beach-local, on the sand), yaw] - towards `toward` (the giant playing alone,
## or the far side for the TV cameras), the first orb on the left as `viewer` (the side they look from) sees it.
func row_at(toward: Vector3, viewer: Vector3 = Vector3.INF) -> Array:
	var d := Vector2(toward.x, toward.z)
	d = d.normalized() if d.length() > 0.1 else Vector2(0.0, 1.0)
	var v := d if viewer == Vector3.INF else Vector2(viewer.x, viewer.z).normalized()
	return [Vector3(d.x, 0.0, d.y) * ROW_R, atan2(v.x, v.y)]


## Beach-local spot of orb i of n in a row (the deep test checks them all on the sand).
static func spot_of(row: Array, i: int, n: int) -> Vector3:
	var yaw := float(row[1])
	return (row[0] as Vector3) + Vector3(cos(yaw), 0.0, -sin(yaw)) * (float(i) - (n - 1) * 0.5) * GAP + Vector3(0.0, Y, 0.0)


## Host / local: put up the orbs. entries: [{id, name, pic, color}], opts: what each orb means.
func begin(new_stage: String, entries: Array, opts: Array, row: Array, done: Callable) -> void:
	stage = new_stage
	options = opts
	on_done = done
	t = float(WAIT.get(new_stage, 10.0)) * wait_scale
	chosen = -1
	chosen_by = -1
	done_t = 0.0
	show_row(new_stage, entries, row)
	main.net.event("orbs", [new_stage, entries, row])
	print("PICKS %s: %s" % [new_stage, opts])


## Every machine: the row of orbs ("" stage: none). row: [middle, yaw] (row_at). The orbs live under the beach, so
## everything is in beach units; touches and glove hits are in the world (scaled by S).
func show_row(new_stage: String, entries: Array, row: Array) -> void:
	if new_stage == "" or entries.is_empty() or row.size() < 2:
		orbs.clear()
		return
	orbs.position = row[0]
	orbs.rotation.y = float(row[1])
	var s: float = main.S
	orbs.show_orbs(new_stage, entries, Vector3.ZERO, GAP, Y, {"scale": SCALE, "pop": true, "font": 64,
		"label_y": -1.25, "label_px": 0.007, "two_lines": true, "bob": 0.12, "hit_r": PickOrbs.BALL_R * s})


## The middle of orb i, beach-local (bots walk there) / in the world (bots reach there).
func orb_position(i: int) -> Vector3:
	if i < 0 or i >= orbs.orbs.size() or not is_instance_valid(orbs.orbs[i]):
		return Vector3.INF
	return main.beach.to_local((orbs.orbs[i] as Node3D).global_position)


func orb_global(i: int) -> Vector3:
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
	t -= minf(delta, 0.1)  # (a loading hitch never eats the wait: nobody gets to pick otherwise)
	var s: float = main.S
	for slot in main.avatars:
		var a: Node3D = main.avatars[slot]
		var o := orbs.at_point(a.global_position, TV_R * s)
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


## Every machine: a dot in the taker's colour circles orb i, a happy sound and a burst.
func take_fx(i: int, slot: int) -> void:
	var col: Color = main.party.color_of(slot) if slot >= 0 and main.avatars.has(slot) else Color(1, 1, 1)
	var at := orbs.take(i, col)
	if at != Vector3.INF:
		main.sfx.play_at("power_up", at, -2.0, 1.0 + 0.1 * i)
		main.burst_at(main.beach.to_local(at), Color(1.0, 0.9, 0.4))


func _finish() -> void:
	var st := stage
	var opt: Variant = options[chosen]
	history.append([st, str(opt), chosen_by])
	stage = ""
	options = []
	orbs.clear()
	main.net.event("orbs", ["", [], []])
	if on_done.is_valid():
		on_done.call(st, opt, chosen_by)
