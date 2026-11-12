extends Node
## COASTER CREW PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), after the practice ride.
##   "gift"  BUTTONS' TRACK GIFTS before every ride from the third: three of BOOSTER, CORKSCREW, SPLASH, RAINBOW,
##           BIG STARS (deep.gd offer).
## Picking never stops the building: three giant glass orbs float over the near edge of the table at the VR builder's
## arm's reach (deep.gd row, main.gd space: they stay put while the table turns). The VR builder REACHES into one on
## purpose (a hand moves in after they pop up and stays DWELL s - a hand already resting there or swinging through never
## picks). The pad builder and the riders press X / A / B: each screen shows the three pictures over the buttons in the
## order the orbs stand on THAT screen (the riders' cameras circle the park). Nobody in time - or the lever is pulled -
## takes the middle orb (it glows brightest): a lone player is never stuck.
## Networked through the state store: "orbs" [serial, stage, entries] and "take" [serial, i, slot] (a machine joining
## mid-pick sees the orbs too); a TV machine sends the request "pick" [orb index].

const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const Party := preload("res://core/party.gd")
const Deep := preload("res://games/roller_coaster/deep.gd")
const VrRig := preload("res://core/vr_rig.gd")

const AFTER := 1.2  # seconds the taken orb shows its dot before the orbs go
const OPEN := 0.8  # seconds after the orbs pop up before they can be taken
const RESTING := 99  # inside[h]: a hand that was already in an orb when they opened
const BUTTONS: Array[String] = ["X", "A", "B"]
const PRESS: Array[String] = ["x", "accept", "back"]

var main
var orbs: PickOrbs
var stage := ""  # host: "" | "mode" | "gift"
var options: Array = []
var serial := 0
var shown_serial := -1  # every machine: the orbs showing
var shown_stage := ""
var shown_entries: Array = []
var taken_serial := -1
var t := 0.0
var chosen := -1
var chosen_by := -1
var done_t := 0.0
var on_done: Callable  # host: (stage, option, slot)
var history: Array = []  # [stage, option, by] (telemetry, bots)
var inside := {}  # hand -> orb index it is in now (-1 none)
var dwell := {}  # hand -> seconds in that orb
var strips := {}  # hud key -> [Control, order]


func _ready() -> void:
	name = "Picks"
	orbs = PickOrbs.new()
	orbs.name = "PickOrbs"
	orbs.collision_layer = 0
	main.add_child(orbs)


func active() -> bool:
	return stage != ""


## Any picks up on this machine (the 3D orbs, or only the pictures on the screens).
func showing() -> bool:
	return shown_stage != ""


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
	dwell = {}
	serial += 1
	main.net.state_set("orbs", [serial, new_stage, entries])
	sync_state()
	print("PICKS %s: %s" % [new_stage, opts])


## Every machine: show what the state store says (orbs up / taken / gone). again: rebuild (the VR builder's giant
## turned up on this TV machine).
func sync_state(again: bool = false) -> void:
	if again:
		shown_serial = -1
	var o: Array = main.net.state_get("orbs", [])
	var s := int(o[0]) if o.size() >= 3 else 0
	if s != shown_serial:
		shown_serial = s
		taken_serial = -1
		show_row(String(o[1]) if o.size() >= 3 else "", o[2] if o.size() >= 3 else [])
	var tk: Array = main.net.state_get("take", [])
	if tk.size() >= 3 and int(tk[0]) == shown_serial and shown_stage != "" and taken_serial != shown_serial:
		taken_serial = shown_serial
		take_fx(int(tk[1]), int(tk[2]))


## Every machine: the row of orbs ("" stage: none).
func show_row(new_stage: String, entries: Array) -> void:
	shown_stage = new_stage
	shown_entries = entries.duplicate(true)
	_clear_strips()
	if new_stage == "" or entries.is_empty():
		orbs.clear()
		return
	main.clear_banners()
	if not main.vr_builder_here():
		orbs.clear()  # no giant at the table: the screens' pictures are the picks (giant orbs would fill a TV view)
		return
	orbs.show_orbs(new_stage, entries, Deep.ROW_AT, Deep.ROW_GAP, 0.0, {"at": Deep.row(entries.size()), "scale": Deep.ORB_SCALE,
		"pop": true, "font": 64, "label_y": 1.3, "label_px": 0.0052, "two_lines": true, "bob": 0.04, "dot_size": 0.18})


## Orb i's middle in the world (bots aim there), INF if none.
func orb_position(i: int) -> Vector3:
	if i < 0 or i >= orbs.orbs.size() or not is_instance_valid(orbs.orbs[i]) or not (orbs.orbs[i] as Node3D).is_inside_tree():
		return Vector3.INF
	var o = orbs.orbs[i]
	return o.icon.global_position if o.icon != null and o.icon.is_inside_tree() else (o as Node3D).global_position


func can_take() -> bool:
	return stage != "" and chosen < 0 and t >= OPEN


## Seconds left to pick.
func left() -> float:
	return maxf(0.0, Deep.wait_for(stage, main.pick_solo()) - t) if stage != "" and chosen < 0 else 0.0


## The camera a screen (hud key: a slot, -1 the shared view) looks through.
func _cam_of(key: int) -> Camera3D:
	if main.cams.has(key) and is_instance_valid(main.cams[key]):
		return main.cams[key]
	if main.split != null:
		return main.split.shared_camera()
	return null


## The orbs in the order they stand on screen `key`, left to right (button k takes order[k]).
func order_for(key: int) -> Array:
	var right := Vector3.RIGHT
	var cam := _cam_of(key)
	if cam != null and cam.is_inside_tree():
		right = cam.global_transform.basis.x
	var at := Deep.row(shown_entries.size())
	var keyed: Array = []
	for i in at.size():
		keyed.append([(at[i] as Vector3).dot(right), i])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out: Array = []
	for k in keyed:
		out.append(int(k[1]))
	return out


## Every machine: a local player pressed X / A / B? Sends the orb that button shows on their screen (true: it was a pick
## button while the orbs are up, so the game doesn't also use it).
func local_press(slot: int) -> bool:
	if shown_stage == "" or taken_serial == shown_serial:
		return false
	for k in PRESS.size():
		if main.party.just_pressed(slot, PRESS[k]):
			var ord := order_for(slot)
			if k < ord.size():
				main.net.request(slot, "pick", [int(ord[k]), shown_serial])
			return true
	return false


## Host / local: a player took orb i (a request).
func press(slot: int, i: int, for_serial: int) -> void:
	if for_serial == serial and can_take():
		take(i, slot)


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
	var o := _hand_pick(delta)
	if o >= 0:
		take(o, 0)
		return
	if t > Deep.wait_for(stage, main.pick_solo()):
		take(options.size() / 2, -1)  # nobody took one: the middle one (it glows brightest)


## Host / local: the lever was pulled - the middle orb now (or the one already taken), at once.
func settle_now() -> void:
	if stage == "":
		return
	if chosen < 0:
		take(options.size() / 2, -1)
	_finish()


## The VR builder's pick this frame (-1 none): a hand moving into an orb and staying a moment.
func _hand_pick(delta: float) -> int:
	var rig = main.vr_rig
	if rig == null or main.builder == null or main.builder.riding:
		return -1
	var got := -1
	for h in [VrRig.LEFT, VrRig.RIGHT]:
		if h == VrRig.RIGHT and not (main.builder.held as Dictionary).is_empty():
			inside.erase(h)  # carrying a piece through an orb is never a pick
			continue
		var pos: Vector3 = rig.hand_point(h)
		var i := orbs.nearest_hit(pos, Deep.HAND_R)
		if not inside.has(h):  # where it was when the orbs came up: resting in one is never a pick until it leaves
			inside[h] = RESTING if i >= 0 else -1
		var before := int(inside[h])
		if before == RESTING:
			inside[h] = RESTING if i >= 0 else -1
			dwell[h] = 0.0
			continue
		if i != before:
			dwell[h] = 0.0
		inside[h] = i
		if i >= 0 and t >= OPEN:
			dwell[h] = float(dwell.get(h, 0.0)) + delta
			if float(dwell[h]) >= Deep.DWELL:
				got = i
				rig.pulse(h, 0.7, 0.08)
	return got


## Host / local: orb i taken by slot (-1: nobody chose, the middle one).
func take(i: int, slot: int) -> void:
	if stage == "" or chosen >= 0 or i < 0 or i >= options.size():
		return
	chosen = i
	chosen_by = slot
	main.net.state_set("take", [serial, i, slot])
	sync_state()
	print("PICK %s: %s took %d (%s)" % [stage, "nobody" if slot < 0 else ("the builder" if slot == 0 else "P%d" % (slot + 1)), i,
		str(options[i])])


## Every machine: a dot in the taker's colour circles orb i, a happy sound; the screens' picture glows.
func take_fx(i: int, slot: int) -> void:
	var col: Color = Party.COLORS[slot % Party.COLORS.size()] if slot >= 0 else Color(1, 1, 1)
	orbs.take(i, col)
	main.sound("ready", -4.0, 1.2 + 0.1 * i)
	for key in strips:
		var s: Control = (strips[key] as Array)[0]
		if is_instance_valid(s):
			for c in s.get_children():
				if int(c.get_meta("orb", -1)) != i:
					c.modulate.a = 0.3


func _finish() -> void:
	var st := stage
	var opt: Variant = options[chosen]
	history.append([st, str(opt), chosen_by])
	stage = ""
	options = []
	main.net.state_set("orbs", [serial, "", []])
	sync_state()
	if on_done.is_valid():
		on_done.call(st, opt, chosen_by)


# --- The pictures on every local screen ---------------------------------------------------------------------

func _process(_delta: float) -> void:
	if showing():
		_update_strips()
	elif not strips.is_empty():
		_clear_strips()


func _update_strips() -> void:
	var want := {}
	var locals: Array = main.party.local_slots()
	for key in main.huds:
		var h: Control = main.huds[key]
		if not is_instance_valid(h) or not h.is_visible_in_tree():
			continue
		if int(key) >= 0 and locals.has(int(key)):
			want[int(key)] = h
		elif int(key) < 0 and locals.is_empty():
			want[-1] = h  # nobody here plays: the pictures alone
	for key in strips.keys():
		var s: Array = strips[key]
		var gone: bool = not want.has(key) or not is_instance_valid(s[0])
		if not gone and str(order_for(int(key))) != str(s[1]):
			gone = true  # this screen's camera swung round: the pictures follow the orbs
		if gone:
			if is_instance_valid(s[0]):
				(s[0] as Node).queue_free()
			strips.erase(key)
	for key in want:
		if not strips.has(key):
			var ord := order_for(int(key))
			strips[key] = [_make_strip(want[key], int(key), ord), ord]
		_layout_strip(want[key], (strips[key] as Array)[0])


## Three pictures in this screen's order, the button under each.
func _make_strip(hud: Control, key: int, ord: Array) -> Control:
	var box := HBoxContainer.new()
	box.name = "PickStrip"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	for k in ord.size():
		var i: int = ord[k]
		var e: Dictionary = shown_entries[i]
		var col: Color = e.get("color", Color.WHITE)
		var v := VBoxContainer.new()
		v.set_meta("orb", i)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var pic := StoryCard.picture(String(e.get("pic", "star")), 96.0, col)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(pic)
		var nm := Label.new()
		nm.text = String(e.get("name", ""))
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_font_size_override("font_size", 22)
		nm.add_theme_color_override("font_color", col.lightened(0.35))
		nm.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1))
		nm.add_theme_constant_override("outline_size", 8)
		v.add_child(nm)
		if key >= 0:
			var bt := Label.new()
			bt.text = BUTTONS[k]
			bt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bt.add_theme_font_size_override("font_size", 30)
			bt.add_theme_color_override("font_color", Color(1, 1, 1))
			bt.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1))
			bt.add_theme_constant_override("outline_size", 10)
			v.add_child(bt)
		box.add_child(v)
	box.add_theme_constant_override("separation", 28)
	hud.add_child(box)
	if taken_serial == shown_serial:
		var tk: Array = main.net.state_get("take", [])
		if tk.size() >= 3:
			for c in box.get_children():
				if int(c.get_meta("orb", -1)) != int(tk[1]):
					c.modulate.a = 0.3
	return box


func _layout_strip(hud: Control, box: Control) -> void:
	var area: Vector2 = hud.size
	if area.x < 10.0:
		return
	var s := clampf(area.y / 720.0, 0.45, 1.3)
	box.scale = Vector2(s, s)
	var sz := box.get_combined_minimum_size()
	box.size = sz
	box.position = Vector2((area.x - sz.x * s) * 0.5, area.y * 0.3)


func _clear_strips() -> void:
	for key in strips:
		var s: Array = strips[key]
		if is_instance_valid(s[0]):
			(s[0] as Node).queue_free()
	strips.clear()
