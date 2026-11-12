extends Node
## PARTY BOARD PICKS on the shared pick orbs (core/pick_orbs.gd), picture first (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), before the first party: any
##           person playing may take it (the first one decides).
##   "gift"  MANGO'S GIFTS from the second round: three of LUCKY DIE, SHORTCUT, UMBRELLA, DOUBLE STAR for whoever is
##           furthest behind (only they may take one; a CPU takes its own after deep.gd CPU_PICK s).
## Rows (deep.gd): the VR giant's three small orbs an arm's reach in front of the eyes ("vr", from the head after the
## VR height fit; they follow the giant when it walks or turns a lot), the hand moves into one and stays deep.gd DWELL s
## (a hand already in one when they pop up must leave and come back). No VR: three big orbs over the south of the
## island ("board"). TV / Deck players (and a flat host): the stick moves a dot in their colour from orb to orb (it
## starts on the middle one), A takes it. Nobody in time? The middle orb (it glows brightest).
## The host publishes the "orbs" state {stage, entries, spots (board units), row, hover: {slot: orb}, allowed} (a
## machine joining mid-pick sees the orbs and the dots too) and the "pick_take" effect [orb, slot].

const PickOrbs := preload("res://core/pick_orbs.gd")
const Deep := preload("res://games/party_board/deep.gd")

const AFTER := 1.1  # seconds the taken orb shows its dot before the orbs go
const OPEN := 0.8  # seconds after the orbs pop up before they can be taken
const RESTING := 99  # inside[id]: a hand that was already at an orb when they opened
const STICK := 0.55  # a stick this far over moves the dot one orb

var main
var orbs: PickOrbs
var stage := ""  # host: "" | "mode" | "gift"
var options: Array = []
var entries: Array = []
var spots: Array = []  # every machine: the orbs' middles (board units)
var row := ""  # every machine: "vr" | "board"
var allowed: Array = []  # host: pids who may take one ([] = every person playing)
var cpu_pid := -1  # host: a CPU's gift: it takes cpu_choice by itself
var cpu_choice := -1
var t := 0.0
var chosen := -1
var chosen_by := -1
var done_t := 0.0
var on_done: Callable  # host: (stage, option, slot)
var history: Array = []  # [stage, option, by] (telemetry, bots)
var inside := {}  # hand id -> orb index it is at now (-1 none)
var dwell := {}  # hand id -> seconds at that orb
var hover := {}  # host: slot -> the orb a TV player's dot is on
var stick_ready := {}  # host: slot -> the stick came back to the middle since the dot last moved
var row_head := Transform3D()  # host, VR row: the head the row was put in front of
var shown_key := ""
var shown_hover := ""


func _ready() -> void:
	name = "Picks"
	orbs = PickOrbs.new()
	orbs.collision_layer = 0
	main.stage.add_child(orbs)


func active() -> bool:
	return stage != ""


func showing() -> bool:
	return not orbs.orbs.is_empty()


## Host / local: put up the orbs. entries: [{id, name, pic, color}], opts: what each orb means; who: pids that may
## take one ([] = every person); cpu: a CPU pid that takes cpu_pick (an index) by itself (-1 none).
func begin(new_stage: String, new_entries: Array, opts: Array, done: Callable, who: Array = [], cpu: int = -1, cpu_pick: int = -1) -> void:
	stage = new_stage
	options = opts
	entries = new_entries.duplicate(true)
	on_done = done
	allowed = who.duplicate()
	cpu_pid = cpu
	cpu_choice = cpu_pick
	t = 0.0
	chosen = -1
	chosen_by = -1
	done_t = 0.0
	inside = {}
	dwell = {}
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
	print("PICKS %s: %s (%s row, %s)" % [new_stage, opts, row, "anyone" if who.is_empty() else str(who)])


func _vr_head() -> Node3D:
	if main.vr_rig == null or main.vr_rig.camera == null:
		return null
	return main.vr_rig.camera


func _vr_row(head: Transform3D) -> Array:
	var out: Array = []
	for w in Deep.vr_spots(head, entries.size()):
		out.append(main.to_board(w))
	return out


func _publish() -> void:
	main.net.state_set("orbs", {"stage": stage, "entries": entries, "spots": spots.duplicate(), "row": row,
		"hover": hover.duplicate(), "allowed": allowed.duplicate()})


## Every machine: the "orbs" state.
func show_state(v: Variant) -> void:
	var st: Dictionary = v if v is Dictionary else {}
	if st.is_empty() or String(st.get("stage", "")) == "":
		if showing() or shown_key != "":
			orbs.clear()
		shown_key = ""
		shown_hover = ""
		spots = [] if main.flow == null else spots
		return
	var es: Array = st.get("entries", [])
	var sp: Array = st.get("spots", [])
	var key := "%s|%s|%s" % [String(st.stage), str(es.map(func(e: Dictionary) -> String: return String(e.get("id", "")))), str(sp)]
	if key != shown_key:
		var moved := shown_key.begins_with("%s|" % String(st.stage)) and showing() and orbs.orbs.size() == sp.size()
		shown_key = key
		row = String(st.get("row", "board"))
		if main.flow == null:
			spots = sp.duplicate()
		if moved:  # (the VR row followed the giant: the same orbs, new places)
			for i in sp.size():
				if is_instance_valid(orbs.orbs[i]):
					(orbs.orbs[i] as Node3D).global_position = main.to_world(sp[i])
		else:
			_build(String(st.stage), es, sp)
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
	orbs.show_orbs(new_stage, es, at[0], 0.0, 0.0, {"at": at, "scale": sc, "pop": true, "font": 56, "label_y": 1.2,
		"label_px": 0.0045, "two_lines": true, "bob": 0.04, "hit_r": PickOrbs.BALL_R * main.S, "dot_r": 0.8})
	main.pick_banner(new_stage)


## Orb i's middle in the world (bots aim there), INF if none.
func orb_position(i: int) -> Vector3:
	if i < 0 or i >= orbs.orbs.size() or not is_instance_valid(orbs.orbs[i]) or not (orbs.orbs[i] as Node3D).is_inside_tree():
		return Vector3.INF
	var o = orbs.orbs[i]
	return o.icon.global_position if o.icon != null and o.icon.is_inside_tree() else (o as Node3D).global_position


## The people who may pick with a stick here (TV / Deck seats, a flat host's slot 0).
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


## Nobody here who could take one (the middle one comes sooner).
func nobody() -> bool:
	return _tv_pickers().is_empty() and not _vr_may() and cpu_pid < 0


## Seconds left to pick.
func left() -> float:
	return maxf(0.0, Deep.wait_for(stage, nobody()) - t) if stage != "" and chosen < 0 else 0.0


## Host / local, every frame while the orbs are up (before main.consume_presses).
func tick(delta: float) -> void:
	if stage == "":
		return
	if chosen >= 0:
		done_t += delta
		if done_t >= AFTER:
			_finish()
		return
	t += minf(delta, 0.1)  # (a loading hitch never eats the wait)
	_follow_head()
	var got := _vr_pick(delta)
	if got.is_empty():
		got = _tv_pick()
	if got.is_empty() and cpu_pid >= 0 and cpu_choice >= 0 and t >= OPEN + Deep.CPU_PICK:
		got = [cpu_choice, cpu_pid]
	if got.size() == 2:
		take(int(got[0]), int(got[1]))
		return
	if t > Deep.wait_for(stage, nobody()):
		take(options.size() / 2, -1)  # nobody took one: the middle one (it glows brightest)


## Host, VR row: the giant walked or turned a lot since the orbs popped up: the row moves to stay in front.
func _follow_head() -> void:
	if row != "vr" or _vr_head() == null:
		return
	var h: Transform3D = _vr_head().global_transform
	var f_now := (-h.basis.z).slide(Vector3.UP)
	var f_was := (-row_head.basis.z).slide(Vector3.UP)
	var turned := f_now.length() > 0.2 and f_was.length() > 0.2 and f_now.normalized().dot(f_was.normalized()) < 0.9
	if h.origin.distance_to(row_head.origin) < 0.3 and not turned:
		return
	row_head = h
	spots = _vr_row(h)
	inside = {}
	dwell = {}
	_publish()


## The VR hands: [orb, 0] once a hand has stayed in one DWELL s.
func _vr_pick(delta: float) -> Array:
	if not _vr_may() or row != "vr":
		return []
	var rig = main.vr_rig
	var got: Array = []
	for hid in ["l", "r"]:
		var hand: Node3D = rig.hand_l if hid == "l" else rig.hand_r
		if hand == null or not hand.is_inside_tree():
			continue
		var i := orbs.nearest_hit(hand.global_position, Deep.HAND_R)
		if not inside.has(hid):  # where it was when the orbs came up: resting at one is never a pick until it leaves
			inside[hid] = RESTING if i >= 0 else -1
		var before := int(inside[hid])
		if before == RESTING:
			inside[hid] = RESTING if i >= 0 else -1
			dwell[hid] = 0.0
			continue
		if i != before:
			dwell[hid] = 0.0
		inside[hid] = i
		if i >= 0 and t >= OPEN:
			dwell[hid] = float(dwell.get(hid, 0.0)) + delta
			if float(dwell[hid]) >= Deep.DWELL and got.is_empty():
				got = [i, 0]
	return got


## TV players: the stick moves their dot, A takes the orb it is on.
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
		if bool(inp.pressed) and t >= OPEN and got.is_empty():
			got = [int(hover[pid]), pid]
	if changed:
		_publish()
	return got


## Host / local: orb i taken by slot (-1: nobody chose, the middle one).
func take(i: int, slot: int) -> void:
	if stage == "" or chosen >= 0 or i < 0 or i >= options.size():
		return
	chosen = i
	chosen_by = slot
	hover = {}
	_publish()
	main.fx("pick_take", [i, slot])
	print("PICK %s: %s took %d (%s)" % [stage, "nobody" if slot < 0 else "P%d" % (slot + 1), i, str(options[i])])


## Every machine: a dot in the taker's colour circles orb i, a happy sound and a puff.
func take_fx(i: int, slot: int) -> void:
	var col: Color = main.color_of(slot) if slot >= 0 else Color(1, 1, 1)
	orbs.show_takers({}, {})
	shown_hover = "{}"
	var at := orbs.take(i, col)
	if at != Vector3.INF:
		main.sfx.play("correct", -4.0, 1.0 + 0.1 * i)
		main.burst(main.to_board(at), col, 18)
	if slot == 0 and main.vr_rig != null:
		main.vr_rig.pulse(1, 0.5, 0.08)


func _finish() -> void:
	var st := stage
	var opt: Variant = options[chosen]
	history.append([st, str(opt), chosen_by])
	stage = ""
	options = []
	entries = []
	spots = []
	hover = {}
	main.net.state_set("orbs", {})
	if on_done.is_valid():
		on_done.call(st, opt, chosen_by)
