extends "res://core/pick_flow.gd"
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

const Deep := preload("res://games/rhythm_band/deep.gd")

const BUTTONS: Array[String] = ["X", "A", "B"]

var shown_stage := ""  # every machine: the orbs showing
var shown_entries: Array = []
var strips := {}  # player index -> the HUD strip (Control)


func _init() -> void:
	after = 1.2
	hand_r = Deep.HAND_R
	hand_dwell = Deep.DWELL


## Host / local: put up the orbs round the drum kit. entries: [{id, name, pic, color}], opts: what each orb means.
func begin(new_stage: String, entries: Array, opts: Array, done: Callable) -> void:
	start(new_stage, opts, done)
	show_row(new_stage, entries)
	publish([new_stage, entries])


func orbs_off() -> Array:
	return ["", []]


func closed() -> void:
	show_row("", [])


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
		"label_y": -1.1, "label_px": 0.0055, "two_lines": true, "bob": 0.04, "dot_size": 0.18})  # (names under the orbs: over them they lined up with the band's P2 / P3 tags)
	_place()


func _world(lp: Vector3) -> Vector3:
	var d = main.players[0] if main.players.size() > 0 else null
	if d != null and d.rig != null and d.rig.is_inside_tree():
		# (height and spread follow the player's size like the drums; the distance out shrinks less, or a seated
		# player's row sank into the hi-hat and crash: core/vr_view_check.gd pick_hidden)
		var k: float = d.kit_s
		return d.rig.to_global(Vector3(lp.x * k, lp.y * k, lp.z * maxf(k, Deep.ROW_Z_MIN_S)))
	return main.DRUM_SPOT + Vector3(0.0, 1.45, 0.0) + lp


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


func wait_for() -> float:
	return Deep.wait_for(stage, main.pick_solo())


## Orb indices left to right as player idx sees them (their buttons X A B).
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
	var at: Array = []
	for lp in Deep.row_local(shown_entries.size()):
		at.append(_world(lp))
	return order_along(at, right)


## Host / local: player idx pressed button k (0 X, 1 A, 2 B): the k-th orb from their left.
func press(idx: int, k: int) -> void:
	if not can_take() or k < 0 or k > 2:
		return
	var ord := order_for(idx)
	if k < ord.size():
		take(int(ord[k]), idx)


## The drummer's stick tips (VR, or a remote VR drummer's sent tips) reaching into an orb.
func takers() -> Dictionary:
	var d = main.players[0]
	if d == null or not (d.vr or d.fake_vr or d.remote):
		return {}
	var points := {}
	for h in 2:
		points["t%d" % h] = [d.tips[h] if not d.remote else d.net_tips[h], 0, "hand"]
	return points


func take_fx(i: int, slot: int) -> void:
	super(i, slot)
	for idx in strips:
		dim_strip(strips[idx], i)


func slot_color(slot: int) -> Color:
	return main.PLAYER_COLORS[slot] if slot < main.PLAYER_COLORS.size() else Color(1, 1, 1)


func fx(i: int, slot: int, at: Vector3, col: Color) -> void:
	if at != Vector3.INF:
		main.sound("ready", -4.0, 1.2 + 0.1 * i)
		main.burst(at, col, 18, false)
	var d = main.players[0]
	if slot == 0 and d != null and d.vr and d.has_method("haptic"):
		d.haptic("both")


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
			var ord := order_for(p.index)
			var buttons: Array = []
			for k in ord.size():
				buttons.append(_button_text(p, k))
			var box := strip(shown_entries, ord, buttons)
			p.hud.add_child(box)
			strips[p.index] = box
		elif not want and has:
			strips[p.index].queue_free()
			strips.erase(p.index)
		if want:
			layout_strip(p.hud, strips[p.index])


func _button_text(p, k: int) -> String:
	if int(p.joy) >= 0:
		return BUTTONS[k]
	if p.index == 0:
		return ["A", "S", "D"][k]
	return ["←", "↓", "→"][k]


func _clear_strips() -> void:
	for idx in strips:
		if is_instance_valid(strips[idx]):
			strips[idx].queue_free()
	strips.clear()
