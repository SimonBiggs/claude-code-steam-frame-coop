extends "res://core/pick_flow.gd"
## HIDE AND SEEK PICKS on the shared pick flow, EVERYONE VOTES (core/pick_flow.gd vote mode): the MODE pick before
## the first round (everyone) and PIP'S GIFT before every later round (the side it helps: the seeker or the hiders).
## The orbs float over the counting room's floor (deep.gd pick_spots); stand under one, or reach a VR hand into it,
## for deep.gd DWELL s: that is your vote (a dot in your colour). Everyone who may pick has voted (or the time is up):
## the most votes win, a tie goes to the middle orb; nobody who may pick is here for EMPTY_WAIT s: the middle one.
## deep_play.gd starts it (begin) and applies the result; the snapshot (deep_play pack) draws the orbs on every machine.

const Deep := preload("res://games/hide_and_seek/deep.gd")

var deep  # deep_play.gd
var side := ""  # gift: "seeker" / "hider"


func _init() -> void:
	vote = true
	tie_rule = "middle"
	after = 0.6
	foot_dwell = Deep.DWELL
	hand_dwell = Deep.DWELL
	hand_r = Deep.HAND_R
	foot_r = Deep.PICK_TOUCH
	waits = Deep.PICK_WAIT.duplicate()
	empty_wait = Deep.EMPTY_WAIT


## Host / local: a new pick over the counting room's floor.
func begin(new_stage: String, ids: Array, gift_side: String, done: Callable) -> void:
	side = gift_side
	start(new_stage, ids, done)
	spots = Deep.pick_spots(main.md())
	publish([new_stage, ids])


## Every machine: the row (deep_play draws it from the snapshot).
func show_row(new_stage: String, ids: Array, gift_side: String) -> void:
	var entries: Array = []
	for id in ids:
		if new_stage == "mode":
			var m := PickOrbs.mode(String(id))
			entries.append({"id": id, "name": String(m.name), "pic": String(m.pic), "color": m.color})
		else:
			var g := Deep.gift(String(id))
			entries.append({"id": id, "name": String(g.name), "pic": String(g.pic), "color": g.color})
	var at := Deep.pick_spots(main.md())
	orbs.show_orbs(new_stage, entries, Vector3.ZERO, Deep.PICK_GAP, Deep.PICK_Y, {"at": at, "scale": 0.45, "touch": Deep.PICK_TOUCH,
		"pop": true, "two_lines": true, "label_y": -0.9, "for_others": new_stage == "gift" and gift_side == "hider"})


## Who may pick: everyone for the mode; the seeker (P1) or the hiders for a gift (deep_play.can_pick).
func takers() -> Dictionary:
	var out := {}
	for p in main.players:
		if not deep.can_pick(p):
			continue
		out["f%d" % p.index] = [p.global_position, p.index, "foot"]
		if p.vr and p.hand_l != null:
			out["l%d" % p.index] = [p.hand_l.global_position, p.index, "hand"]
			out["r%d" % p.index] = [p.hand_r.global_position, p.index, "hand"]
	return out


## Everyone who may pick votes (even one still walking over: the house is small).
func voters(_points: Dictionary) -> Array:
	var out: Array = []
	for p in main.players:
		if deep.can_pick(p):
			out.append(int(p.index))
	return out


func orb_at(kind: String, point: Variant) -> int:
	for i in spots.size():
		var sp: Vector3 = spots[i]
		if kind == "hand":
			if (point as Vector3).distance_to(sp + Vector3.UP * Deep.PICK_Y) < hand_r:
				return i
		elif Vector2((point as Vector3).x - sp.x, (point as Vector3).z - sp.z).length() < foot_r:
			return i
	return -1


func slot_color(slot: int) -> Color:
	return main.players[slot].color if slot >= 0 and slot < main.players.size() else Color(1, 1, 1)


func vote_fx(i: int, slot: int) -> void:
	deep.stats.picks += 1
	main.sound("ding", -2.0, 1.0 + 0.1 * i)
	if i < spots.size():
		var o: Vector3 = (spots[i] as Vector3) + Vector3.UP * Deep.PICK_Y
		main.burst(o, slot_color(slot), 14)
		main.net.event("burst", [o, slot_color(slot), 14, 0.08])


## The take shows on every machine through deep_play's "deep_take" event.
func send_take(i: int, slot: int) -> void:
	take_fx(i, slot)
	main.net.event("deep_take", [i, slot])
