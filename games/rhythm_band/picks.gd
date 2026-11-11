extends Node
## RHYTHM BAND PICKS on the shared pick orbs (core/pick_orbs.gd), picture first, team choices (deep.gd):
##   "mode"  GENTLE / BRAVE / HARD once a session (the family's last mode in the middle), after practice.
##   "gift"  DOODLE'S INSTRUMENT GIFTS before every song from the second: three of BIG DRUM, SHAKER, GOLD MIC,
##           SLOW SONG, CONFETTI.
## Three small glass orbs float in front of the drummer at arm's reach (deep.gd row_local, kit-relative: they come along
## when the drummer walks). The VR drummer REACHES into one on purpose (a stick tip moves in after they pop up and stays
## a moment - a hand already resting there or swinging through never picks). The flat drummer and the guitarists press
## X / A / B: each of their screens shows the three pictures over the buttons, in the order the orbs stand on THAT
## screen (from the crowd the drummer's left is on the right). The first one decides for the band (a dot in their
## colour circles it). Nobody in time? The middle orb (it glows brightest) - a lone player is never stuck.
## The host sends the sticky "orbs" event [stage, entries] (a machine joining mid-pick sees them too) and
## "take" [i, slot]. Every machine places the orbs from the drummer's rig.

const PickOrbs := preload("res://core/pick_orbs.gd")
const StoryCard := preload("res://core/story_card.gd")
const Deep := preload("res://games/rhythm_band/deep.gd")

const AFTER := 1.2  # seconds the taken orb shows its dot before the orbs go
const OPEN := 0.8  # seconds after the orbs pop up before they can be taken
const RESTING := 99  # inside[h]: a hand that was already in an orb when they opened
const BUTTONS: Array[String] = ["X", "A", "B"]

var main
var orbs: PickOrbs
var stage := ""  # host: "" | "mode" | "gift"
var options: Array = []
var shown_stage := ""  # every machine: the orbs showing
var shown_entries: Array = []
var t := 0.0
var chosen := -1
var chosen_by := -1
var done_t := 0.0
var on_done: Callable  # host: (stage, option, slot)
var history: Array = []  # [stage, option, by] (telemetry, bots)
var inside := {}  # hand -> orb index it is in now (-1 none)
var dwell := {}  # hand -> seconds in that orb
var strips := {}  # player index -> the HUD strip (Control)


func _ready() -> void:
	name = "Picks"
	orbs = PickOrbs.new()
	orbs.name = "PickOrbs"
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
	dwell = {}
	show_row(new_stage, entries)
	main.net.event("orbs", [new_stage, entries])
	print("PICKS %s: %s" % [new_stage, opts])


## Every machine: the row of orbs ("" stage: none) and the pictures on every local screen.
func show_row(new_stage: String, entries: Array) -> void:
	shown_stage = new_stage
	shown_entries = entries.duplicate(true)
	_clear_strips()
	if new_stage == "" or entries.is_empty():
		orbs.clear()
		return
	var at: Array = []
	for lp in Deep.row_local(entries.size()):
		at.append(_world(lp))
	orbs.show_orbs(new_stage, entries, at[0], 0.42, 0.0, {"at": at, "scale": Deep.ORB_SCALE, "pop": true, "font": 64,
		"label_y": -1.3, "label_px": 0.0055, "two_lines": true, "bob": 0.04, "dot_size": 0.18})  # (names under the orbs)
	_place()


## A kit-relative spot in the world (the drummer's rig; the riser before it exists).
func _world(lp: Vector3) -> Vector3:
	var d = main.players[0] if main.players.size() > 0 else null
	if d != null and d.rig != null and d.rig.is_inside_tree():
		return d.rig.to_global(lp * d.kit_s)
	return main.DRUM_SPOT + Vector3(0.0, 1.45, 0.0) + lp


## Every frame: the orbs follow the drummer's kit (they walk with it). (PickOrbs bobs each orb round base_y: the
## row node sits at the origin, so its local places are world places.)
func _place() -> void:
	var lps := Deep.row_local(orbs.orbs.size())
	for i in orbs.orbs.size():
		var o = orbs.orbs[i]
		if is_instance_valid(o):
			var w := _world(lps[i])
			o.position.x = w.x
			o.position.z = w.z
	if not lps.is_empty():
		orbs.base_y = _world(lps[0]).y


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


## The orbs in the order they stand on player `idx`'s screen, left to right (button k takes order[k]).
func order_for(idx: int) -> Array:
	var right := Vector3.RIGHT
	if idx <= 0:
		var d = main.players[0]
		if d.camera != null and d.camera.is_inside_tree() and not d.vr:
			right = d.camera.global_transform.basis.x
		elif d.rig != null and d.rig.is_inside_tree():
			right = d.rig.global_transform.basis.x
	else:
		right = main.stage.tv_camera(idx).basis.x
	var lps := Deep.row_local(shown_entries.size())
	var keyed: Array = []
	for i in lps.size():
		keyed.append([_world(lps[i]).dot(right), i])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out: Array = []
	for k in keyed:
		out.append(int(k[1]))
	return out


## Host / local: player idx pressed button k (0 X, 1 A, 2 B; the flat drummer: its drums).
func press(idx: int, k: int) -> void:
	if not can_take() or k < 0 or k > 2:
		return
	var ord := order_for(idx)
	if k < ord.size():
		take(int(ord[k]), idx)


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


## The VR drummer's pick this frame (-1 none): a stick tip moving into an orb and staying a moment.
func _hand_pick(delta: float) -> int:
	var d = main.players[0]
	if d == null or not (d.vr or d.fake_vr or d.remote):
		return -1
	var got := -1
	for h in 2:
		var pos: Vector3 = d.tips[h] if not d.remote else d.net_tips[h]
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
	return got


## Host / local: orb i taken by slot (a player index; -1: nobody chose, the middle one).
func take(i: int, slot: int) -> void:
	if stage == "" or chosen >= 0 or i < 0 or i >= options.size():
		return
	chosen = i
	chosen_by = slot
	take_fx(i, slot)
	main.net.event("take", [i, slot])
	print("PICK %s: %s took %d (%s)" % [stage, "nobody" if slot < 0 else ("the drummer" if slot == 0 else "P%d" % (slot + 1)), i,
		str(options[i])])


## Every machine: a dot in the taker's colour circles orb i, a happy sound and a burst; the screens' picture glows.
func take_fx(i: int, slot: int) -> void:
	var col: Color = main.PLAYER_COLORS[slot] if slot >= 0 and slot < main.PLAYER_COLORS.size() else Color(1, 1, 1)
	var at := orbs.take(i, col)
	if at != Vector3.INF:
		main.sound("ready", -4.0, 1.2 + 0.1 * i)
		main.burst(at, col, 18, false)
	for idx in strips:
		var s: Control = strips[idx]
		if is_instance_valid(s):
			for c in s.get_children():
				if int(c.get_meta("orb", -1)) != i:
					c.modulate.a = 0.3
	var d = main.players[0]
	if slot == 0 and d != null and d.vr and d.has_method("haptic"):
		d.haptic("both")


func _finish() -> void:
	var st := stage
	var opt: Variant = options[chosen]
	history.append([st, str(opt), chosen_by])
	stage = ""
	options = []
	show_row("", [])
	main.net.event("orbs", ["", []])
	if on_done.is_valid():
		on_done.call(st, opt, chosen_by)


# --- The pictures on every local screen ---------------------------------------------------------------------

func _process(_delta: float) -> void:
	if showing():
		_place()
		_update_strips()


func _update_strips() -> void:
	for p in main.players:
		var want: bool = p.active and main.is_local(p) and p.hud != null and is_instance_valid(p.hud) \
			and not (p.index == 0 and (p.vr or p.fake_vr))
		var has: bool = strips.has(p.index) and is_instance_valid(strips[p.index])
		if want and not has:
			strips[p.index] = _make_strip(p)
		elif not want and has:
			strips[p.index].queue_free()
			strips.erase(p.index)
		if want:
			_layout_strip(p, strips[p.index])


## Three pictures in this player's screen order, the button under each.
func _make_strip(p) -> Control:
	var box := HBoxContainer.new()
	box.name = "PickStrip"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var ord := order_for(p.index)
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
	p.hud.add_child(box)
	return box


func _layout_strip(p, box: Control) -> void:
	var area: Vector2 = p.hud.size
	if area.x < 10.0:
		return
	var s := clampf(area.y / 720.0, 0.45, 1.3)
	box.scale = Vector2(s, s)
	var sz := box.get_combined_minimum_size()
	box.size = sz
	box.position = Vector2((area.x - sz.x * s) * 0.5, area.y * 0.3)


func _clear_strips() -> void:
	for idx in strips:
		if is_instance_valid(strips[idx]):
			strips[idx].queue_free()
	strips.clear()
