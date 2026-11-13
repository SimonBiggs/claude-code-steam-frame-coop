extends "res://core/pick_flow.gd"
## PARTY BOARD PICKS on the shared pick orbs (core/pick_orbs.gd), picture first (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), before the first party: any
##           person playing may take it (the first one decides).
##   "gift"  MANGO'S GIFTS from the second round: three of LUCKY DIE, SHORTCUT, UMBRELLA, DOUBLE STAR for whoever is
##           furthest behind (only they may take one; a CPU takes its own after deep.gd CPU_PICK s).
## Rows (deep.gd): the VR giant's three small orbs an arm's reach in front of the eyes ("vr", from the head after the
## VR height fit; they follow the giant when it walks or turns a lot), the hand moves into one and stays deep.gd DWELL s
## (a hand already in one when they pop up must leave and come back). No VR: three big orbs high over the middle of the
## island ("board"). TV / Deck players (and a flat host): the stick moves a dot in their colour from orb to orb (it
## starts on the middle one), A takes it. Nobody in time? The middle orb (it glows brightest).
## The host sends the sticky "orbs" event [{stage, entries, spots (board units), row, hover: {slot: orb}, allowed}] (a
## machine joining mid-pick sees the orbs and the dots too; cur_state on every machine) and the "pick_take" effect
## [orb, slot].

const Deep := preload("res://games/party_board/deep.gd")

const STICK := 0.55  # a stick this far over moves the dot one orb

var entries: Array = []
var row := ""  # every machine: "vr" | "board"
var allowed: Array = []  # host: pids who may take one ([] = every person playing)
var cpu_pid := -1  # host: a CPU's gift: it takes cpu_choice by itself
var cpu_choice := -1
var hover := {}  # host: slot -> the orb a TV player's dot is on
var stick_ready := {}  # host: slot -> the stick came back to the middle since the dot last moved
var row_head := Transform3D()  # host, VR row: the head the row was put in front of
var shown_key := ""
var shown_hover := ""
var shown_stage := ""
var cur_state := {}  # every machine: the orbs showing now ({} none; bots read it)


func _init() -> void:
	after = 1.1
	hand_r = Deep.HAND_R
	hand_dwell = Deep.DWELL


## The orbs live on the scaled board stage (spots in board units).
func orbs_parent() -> Node:
	return main.stage


## Host / local: put up the orbs (VR: in front of the giant's head; else over the board). who: the pids who may take
## one ([] = everyone playing); cpu / cpu_pick: a CPU's gift it takes by itself.
func begin(new_stage: String, new_entries: Array, opts: Array, done: Callable, who: Array = [], cpu: int = -1, cpu_pick: int = -1) -> void:
	start(new_stage, opts, done)
	entries = new_entries.duplicate(true)
	allowed = who.duplicate()
	cpu_pid = cpu
	cpu_choice = cpu_pick
	hover = {}
	stick_ready = {}
	if _vr_head() != null:
		row = "vr"
		row_head = _vr_head().global_transform
		spots = _vr_row(row_head)
	else:
		row = "board"
		spots = Deep.board_spots(entries.size())
	for pid in _tv_pickers():
		hover[pid] = entries.size() / 2
	_publish()


func _vr_head() -> Node3D:
	if main.vr_rig == null or main.vr_rig.camera == null:
		return null
	return main.vr_rig.camera


func _vr_row(head: Transform3D) -> Array:
	var out: Array = []
	for w in Deep.vr_spots(head, entries.size()):
		out.append(main.to_board(w))
	return out


## The whole pick state (orbs, places, every TV player's dot) as one fx every machine shows (show_state).
func _publish() -> void:
	publish([{"stage": stage, "entries": entries, "spots": spots.duplicate(), "row": row,
		"hover": hover.duplicate(), "allowed": allowed.duplicate()}])


func publish(payload: Array) -> void:
	main.fx("orbs", payload)


func orbs_off() -> Array:
	return [{}]


## Every machine: the orbs (and the TV players' dots) from the published state.
func show_state(v: Variant) -> void:
	var st: Dictionary = v if v is Dictionary else {}
	cur_state = st.duplicate()
	if st.is_empty() or String(st.get("stage", "")) == "":
		if showing() or shown_key != "":
			orbs.clear()
		shown_key = ""
		shown_hover = ""
		shown_stage = ""
		spots = [] if main.flow == null else spots
		return
	var es: Array = st.get("entries", [])
	var sp: Array = st.get("spots", [])
	var key := "%s|%s|%s" % [String(st.stage), str(es.map(func(e: Dictionary) -> String: return String(e.get("id", "")))), str(sp)]
	if key != shown_key:
		shown_key = key
		row = String(st.get("row", "board"))
		if main.flow == null:
			spots = sp.duplicate()
		_build(String(st.stage), es, sp)  # (also when the VR row followed the giant: the orbs bob round their new height)
		shown_hover = ""
	var hv: Dictionary = st.get("hover", {})
	var hk := str(hv)
	if hk != shown_hover:
		shown_hover = hk
		var cols := {}
		for s in hv:
			cols[s] = main.color_of(int(s))
		orbs.show_takers(hv, cols)


func _build(new_stage: String, es: Array, sp: Array) -> void:
	var at: Array = []
	for p in sp:
		at.append(main.to_world(p))
	var sc: float = Deep.VR_SCALE / main.S if row == "vr" else Deep.BOARD_SCALE
	# a modest ball, the names over it (never at the giant's eyes); hit_r in metres: the orbs live under the scaled stage
	# (origin in board units: the orbs bob round its height in the stage's own units, at: their places in the world)
	orbs.show_orbs(new_stage, es, sp[0], 0.0, 0.0, {"at": at, "scale": sc, "pop": true, "font": 56, "label_y": 1.2,
		"label_px": 0.0045, "two_lines": true, "bob": 0.04, "hit_r": PickOrbs.BALL_R * main.S, "dot_r": 0.8})
	if new_stage != shown_stage:
		shown_stage = new_stage
		main.pick_banner(new_stage)


func _tv_pickers() -> Array:
	var out: Array = []
	for pid in main.pids():
		if main.is_cpu(pid) or (pid == 0 and main.vr_rig != null):
			continue
		if allowed.is_empty() or allowed.has(pid):
			out.append(pid)
	return out


func _vr_may() -> bool:
	return main.vr_rig != null and not main.is_cpu(0) and (allowed.is_empty() or allowed.has(0))


func nobody() -> bool:
	return _tv_pickers().is_empty() and not _vr_may() and cpu_pid < 0


func wait_for() -> float:
	return Deep.wait_for(stage, nobody())


## VR row: the orbs follow the giant's head when they step away or turn (and everyone moves in again).
func follow(_delta: float) -> void:
	if row != "vr" or _vr_head() == null:
		return
	var h: Transform3D = _vr_head().global_transform
	if not head_moved(row_head, h):
		return
	row_head = h
	spots = _vr_row(h)
	reset_dwell()
	_publish()


## The VR giant's hands reaching into an orb (when they may pick).
func takers() -> Dictionary:
	if not _vr_may() or row != "vr":
		return {}
	var points := {}
	var rig = main.vr_rig
	for hid in ["l", "r"]:
		var hand: Node3D = rig.hand_l if hid == "l" else rig.hand_r
		if hand != null and hand.is_inside_tree():
			points[hid] = [hand.global_position, 0, "hand"]
	return points


## TV players move their dot along the row with the stick and press to take; a CPU's gift takes its own choice.
func extra_pick() -> Array:
	var got := _tv_pick()
	if got.is_empty() and cpu_pid >= 0 and cpu_choice >= 0 and t >= open + Deep.CPU_PICK:
		got = [cpu_choice, cpu_pid]
	return got


func _tv_pick() -> Array:
	var order := Deep.tv_order(spots)
	var changed := false
	var got: Array = []
	for pid in _tv_pickers():
		var inp: Dictionary = main.pad_input(pid)
		var sx := -float((inp.move as Vector3).x)  # (main.tv_dir: board x = -stick x)
		var cur := int(hover.get(pid, entries.size() / 2))
		var pos := maxi(0, order.find(cur))
		if absf(sx) > STICK and bool(stick_ready.get(pid, true)):
			var np := clampi(pos + (1 if sx > 0.0 else -1), 0, order.size() - 1)
			if np != pos:
				hover[pid] = int(order[np])
				changed = true
				main.fx("sfx", ["pop", -8.0, 1.2])
			stick_ready[pid] = false
		elif absf(sx) < 0.3:
			stick_ready[pid] = true
		if not hover.has(pid):
			hover[pid] = cur
			changed = true
		if bool(inp.pressed) and t >= open and got.is_empty():
			got = [int(hover[pid]), pid]
	if changed:
		_publish()
	return got


## Host: the take goes out as fx (every machine runs take_fx from it), the TV players' dots go.
func send_take(i: int, slot: int) -> void:
	hover = {}
	_publish()
	main.fx("pick_take", [i, slot])


func take_fx(i: int, slot: int) -> void:
	orbs.show_takers({}, {})
	shown_hover = "{}"
	super(i, slot)


func slot_color(slot: int) -> Color:
	return main.color_of(slot)


func fx(i: int, slot: int, at: Vector3, col: Color) -> void:
	if at != Vector3.INF:
		main.sfx.play("correct", -4.0, 1.0 + 0.1 * i)
		main.burst(main.to_board(at), col, 18)
	if slot == 0 and main.vr_rig != null:
		main.vr_rig.pulse(1, 0.5, 0.08)


## (The orbs go on every machine with the published empty state: show_state.)
func closed() -> void:
	entries = []
	hover = {}
