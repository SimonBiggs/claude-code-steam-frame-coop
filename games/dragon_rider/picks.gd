extends "res://core/pick_flow.gd"
## DRAGON RIDER PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), after the practice rings.
##   "gift"  SUNNY'S GIFTS before every stage: three of FIRE BREATH, SHIELD BUBBLE, BUNNY MAGNET, BUBBLE STORM, ZOOM WINGS.
## Three big glass orbs float across the sky ahead, ABOVE the flight line (deep.gd row_spots): the rider climbs and
## steers Sunny into one (reins in VR, the stick or keys flat), or a gunner bubbles one. Flying straight passes under
## them all (a pick is never a resting hand). The first one decides for the team (a dot in their colour circles it).
## Nobody took one by the time Sunny passes the row (or ROW_WAIT runs out): the middle orb (it glows brightest) - a
## solo rider or a little one is never stuck. The host sends the sticky "orbs" event [stage, entries, spots] (a machine
## joining mid-pick sees the orbs too) and "take" [i, slot].

const Deep := preload("res://games/dragon_rider/deep.gd")

var row_normal := Vector3.FORWARD  # Sunny's heading when the row appeared (passing the row = nobody chose)
var row_secs := Deep.ROW_SECS  # bots: a nearer row


func _init() -> void:
	after = 1.0
	open = 0.6


## Host / local: put up the orbs ahead of Sunny. entries: [{id, name, pic, color}], opts: what each orb means.
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	start(new_stage, opts, done)
	var d: Node3D = main.dragon
	spots = Deep.row_spots(d.global_position, float(d.yaw), maxf(float(d.speed), float(d.cruise)), entries.size(), row_secs)
	row_normal = Basis(Vector3.UP, float(d.yaw)) * Vector3.FORWARD
	show_row(new_stage, entries, spots)
	publish([new_stage, entries, spots])


## Every machine: the row of orbs ("" stage: none).
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


## The orbs stop being aim-assist targets (they're going).
func _untarget() -> void:
	for o in orbs.orbs:
		if is_instance_valid(o) and (o as Node).is_in_group("dr_targets"):
			(o as Node).remove_from_group("dr_targets")


func closed() -> void:
	_untarget()
	orbs.clear()


func row_center() -> Vector3:
	if spots.is_empty():
		return Vector3.INF
	return spots[spots.size() / 2]


func wait_for() -> float:
	return Deep.ROW_WAIT


## Sunny flies through an orb (on entering: no dwell, a dragon never hovers).
func takers() -> Dictionary:
	return {"core": [main.dragon.core_position(), 0, "fly"]}


func orb_at(_kind: String, point: Variant) -> int:
	return orbs.nearest_hit(point, Deep.CATCH)


func dwell_for(_kind: String) -> float:
	return 0.0


## Flew past them all (or turned away): nobody chose.
func passed() -> bool:
	var mid: Vector3 = row_center()
	return mid != Vector3.INF and (main.dragon.core_position() - mid).dot(row_normal) > Deep.catch_r() + 2.0


func slot_color(slot: int) -> Color:
	return main.PLAYER_COLORS[slot] if slot < main.PLAYER_COLORS.size() else Color(1, 1, 1)


func fx(i: int, slot: int, at: Vector3, _col: Color) -> void:
	if at != Vector3.INF:
		main.local_sound("power", -3.0, 1.0 + 0.1 * i)
		main.puff(at, Color(1.0, 0.9, 0.4), 24, 0.3)
	if slot == 0 and taker == "core":
		main.players[0].haptic("l", 0.6)
		main.players[0].haptic("r", 0.6)
