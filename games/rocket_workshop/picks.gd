extends Node
## ROCKET WORKSHOP PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session, after the practice rocket (the family's last mode in the middle).
##   "gift"  SPROCKET'S PART GIFTS before every rocket from rocket 3: three of BOOSTERS, FINS, PARACHUTE, SHIELD.
## The orbs float in a row over the far half of the pilot's desk (deep.gd row_spots). The VR pilot TOUCHES one on
## purpose: a hand has to move INTO an orb after they pop up (a hand already resting there never picks). A flat
## pilot or a lone Deck CLICKS one (the pointer's ray). A crew member WALKS up to the desk's far side under one.
## The first one decides for the team (a dot in their colour circles it). Nobody in time? The middle orb (it glows
## brightest) - a lone pilot or a little one is never stuck. The host sends the sticky "orbs" event [stage, entries,
## spots] (a machine joining mid-pick sees the orbs too) and "take" [i, slot].

const PickOrbs := preload("res://core/pick_orbs.gd")
const Deep := preload("res://games/rocket_workshop/deep.gd")

const AFTER := 1.1  # seconds the taken orb shows its dot before the orbs go
const OPEN := 0.8  # seconds after the orbs pop up before they can be taken
const RESTING := 99  # inside[hand]: a hand that was already in an orb when they opened

var main
var orbs: PickOrbs
var stage := ""  # host: "" | "mode" | "gift"
var options: Array = []
var spots: Array = []
var t := 0.0
var chosen := -1
var chosen_by := -1
var done_t := 0.0
var on_done: Callable  # host: (stage, option, slot)
var history: Array = []  # [stage, option, by] (telemetry, bots)
var inside := {}  # hand id -> orb index it is in now (-1 none): a pick is a hand moving in
var was_held := false  # the pointer's button last frame (a click is a press, not a hold)


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
	inside = {}
	was_held = true  # (a button already down when they pop up is not a click)
	spots = Deep.row_spots(entries.size(), float(main.panel.top) if main.panel != null else 0.9)
	show_row(new_stage, entries, spots)
	main.net.event("orbs", [new_stage, entries, spots])
	print("PICKS %s: %s" % [new_stage, opts])


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array, at: Array) -> void:
	if new_stage == "" or entries.is_empty() or at.size() < entries.size():
		orbs.clear()
		return
	orbs.show_orbs(new_stage, entries, at[0], Deep.ROW_GAP, 0.0, {"at": at, "scale": Deep.ORB_SCALE, "pop": true, "font": 48,
		"label_y": 1.15, "label_px": 0.0016, "two_lines": true, "touch": 0.0, "bob": 0.02})


## Orb i's middle in the world (bots go there), INF if none.
func orb_position(i: int) -> Vector3:
	if i < 0 or i >= orbs.orbs.size() or not is_instance_valid(orbs.orbs[i]) or not (orbs.orbs[i] as Node3D).is_inside_tree():
		return Vector3.INF
	var o = orbs.orbs[i]
	return o.icon.global_position if o.icon != null and o.icon.is_inside_tree() else (o as Node3D).global_position


func can_take() -> bool:
	return stage != "" and chosen < 0 and t >= OPEN


## Seconds left to pick.
func left() -> float:
	return maxf(0.0, float(Deep.WAIT.get(stage, 14.0)) - t) if stage != "" and chosen < 0 else 0.0


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
	var o := _pilot_pick()
	if o >= 0:
		take(o, 0)
		return
	if t >= OPEN:
		for p in main.players:
			if p.index == 0 or not p.active:
				continue
			var i := orbs.at_point(p.global_position, Deep.crew_r())
			if i >= 0:
				take(i, p.index)
				return
	if t > float(Deep.WAIT.get(stage, 14.0)):
		take(options.size() / 2, -1)  # nobody took one: the middle one (it glows brightest)


## The pilot's pick this frame (-1 none): a VR hand moving into an orb, or a click on one.
func _pilot_pick() -> int:
	var op = main.players[0] if not main.players.is_empty() else null
	if op == null or op.ghost:
		return -1
	var got := -1
	var held := false
	var clicked := false
	for h in op.panel_hands():
		if bool(h.pointer):
			held = held or bool(h.grip)
			if bool(h.grip) and not was_held and t >= OPEN:
				clicked = true
				got = _pointer_orb(op, h.pos)
			continue
		var id := String(h.id)
		var i := orbs.nearest_hit(h.pos, Deep.HAND_R)
		var before := int(inside.get(id, -1))
		if t < OPEN or before == RESTING:  # resting in an orb as they open: never a pick until it leaves
			inside[id] = RESTING if i >= 0 else -1
			continue
		inside[id] = i
		if i >= 0 and before != i:
			got = i
	was_held = held
	if clicked and got < 0:
		return -1
	return got


## A click: the orb nearest the pointer's ray from the pilot's camera (or a bot's pointer point).
func _pointer_orb(op, pos: Vector3) -> int:
	var r := PickOrbs.HIT_R * Deep.ORB_SCALE + Deep.POINTER_R
	var cam: Camera3D = op.camera
	if cam == null or not cam.is_inside_tree() or not op.bot_hand.is_empty() or op.cursor.x < 0.0:
		return orbs.nearest_hit(pos, r + 0.08)
	var from := cam.project_ray_origin(op.cursor)
	var dir := cam.project_ray_normal(op.cursor)
	var best := -1
	var bd := r
	for i in orbs.orbs.size():
		var c := orb_position(i)
		if c == Vector3.INF:
			continue
		var along := (c - from).dot(dir)
		var d := (from + dir * along).distance_to(c)
		if along > 0.0 and d < bd:
			bd = d
			best = i
	return best


## Host / local: orb i taken by slot (0 = the pilot, a crew index, -1: nobody chose, the middle one).
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
	var col: Color = main.PLAYER_COLORS[slot] if slot >= 0 and slot < main.PLAYER_COLORS.size() else Color(1, 1, 1)
	var at := orbs.take(i, col)
	if at != Vector3.INF:
		main.local_sound("solve", -4.0, 1.0 + 0.1 * i)
		main.burst(at, col, 14, 0.03)
	if slot == 0 and main.players.size() > 0 and main.players[0].vr:
		main.players[0].haptic("r", 0.5)


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
