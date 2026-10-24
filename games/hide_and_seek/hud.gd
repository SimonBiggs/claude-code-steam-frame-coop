extends Control
## One flat-screen player's HUD. No how-to words (visual teaching): a big word at most (HIDE! / SEEK! /
## the countdown number), and low in the view a picture cue (cue.gd): the player's own button glyph plus
## a picture of what to do. Each action cue goes once that player has done it twice (main.cue_did /
## cue_learned). A glowing pointer shows the way to the jail bell (friends in jail) or the nearest star.
## Also: the "seeker nearby!" warmth edge, the squeak cooldown bar, the seeker's crosshair (with a
## pulsing button glyph beside it while a hider is in the torch beam) and the dark eyes-covered screen.
## Scales down with the view when many share the TV.

const CueScript := preload("res://games/hide_and_seek/cue.gd")
const UiKit := preload("res://core/ui_kit.gd")

var player
var main
var name_label: Label
var big_label: Label
var cue: Control
var pointer: Control
var aim_glyph: Control  # seeker: the torch button beside the crosshair while a hider is in the beam
var aim_sig := ""
var ui := 1.0
var found_flash := 0.0
var cue_key := ""
var prop_was := -1
var taunt_was := 0.0
var sniff_was := 0.0
var breaks_was := -1
var stars_was := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name_label = _label(26, player.color)
	big_label = _label(80, Color(1.0, 0.95, 0.7))
	big_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pointer = CueScript.Pointer.new()
	add_child(pointer)
	cue = CueScript.new()
	add_child(cue)


func _label(font: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font)
	l.add_theme_constant_override("outline_size", 7)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func flash_found() -> void:
	found_flash = 1.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and name_label:
		# Full size for 1-2 views; smaller in 2x2 and 3x2 grids.
		ui = clampf(minf(size.x / 900.0, size.y / 1000.0), 0.45, 1.0)
		name_label.add_theme_font_size_override("font_size", maxi(13, int(26 * ui)))
		name_label.add_theme_constant_override("outline_size", maxi(3, int(7 * ui)))
		big_label.add_theme_font_size_override("font_size", maxi(28, int(80 * ui)))
		big_label.add_theme_constant_override("outline_size", maxi(4, int(12 * ui)))
		name_label.position = Vector2(24 * ui, size.y - 60 * ui)
		big_label.position = Vector2(0, size.y * 0.08)  # above the hider's own critter and name tag
		big_label.size = Vector2(size.x, size.y * 0.32)


func _process(delta: float) -> void:
	found_flash = maxf(0.0, found_flash - delta * 1.5)
	if player == null or main == null:
		return
	if pointer.cam == null and player.camera != null:
		pointer.cam = player.camera
	name_label.text = "P%d   %d" % [player.index + 1, main.total_score(player.index) + (0 if main.phase == "over" else main.round_score(player.index))]
	big_label.text = _big()
	_note_done()
	_update_cue(delta)
	_update_aim_glyph()
	queue_redraw()


func _big() -> String:
	match main.phase:
		"intro":
			return "SEEK!" if player.role == "seeker" else "HIDE!"
		"count":
			var n := ceili(main.phase_t)
			return str(n) if player.role == "seeker" else "HIDE!\n%d" % n
	return ""


## What this player just did (on the machine that draws their view): each counts towards retiring a cue.
func _note_done() -> void:
	if player.prop_kind >= 0 and prop_was < 0 and player.is_hiding():
		main.cue_did(player, "disguise")
	prop_was = player.prop_kind
	if player.taunt_cd > taunt_was + 1.0 and main.phase == "seek":
		main.cue_did(player, "squeak")
	taunt_was = player.taunt_cd
	if player.role == "seeker":
		if main.sniff_cd > sniff_was + 1.0:
			main.cue_did(player, "sniff")
		sniff_was = main.sniff_cd
	var bell: Vector3 = main.bell_pos()
	if breaks_was >= 0 and main.jail_breaks < breaks_was and main.phase == "seek" and player.is_hiding() \
			and Vector2(player.global_position.x - bell.x, player.global_position.z - bell.z).length() < 1.6:
		main.cue_did(player, "bell")  # rang the bell
	breaks_was = main.jail_breaks
	var taken: int = main.star_taken.count(true)
	if taken > stars_was and player.is_hiding():
		for k in main.star_idx.size():
			if k < main.star_taken.size() and main.star_taken[k]:
				var at: Vector3 = main.star_spot(int(main.star_idx[k]))
				if Vector2(player.global_position.x - at.x, player.global_position.z - at.z).length() < 1.3:
					main.cue_did(player, "star")
					break
	stars_was = taken


## The button this player presses for an action ("fire": torch / disguise, "alt": squeak, "sniff").
func button(action: String, sc: float) -> Control:
	var pad: bool = player.joy >= 0 or not player.uses_keyboard()
	match action:
		"fire":
			if pad:
				return UiKit.glyph("RT" if player.role == "seeker" else "A", sc)
			if player.mouse_look and player.role == "seeker":
				return UiKit.glyph("CLICK", sc)
			return UiKit.glyph("SPACE" if player.keys() == 0 else "ENTER", sc)
		"alt":
			if pad:
				return UiKit.glyph("X", sc)
			return UiKit.glyph("E" if player.keys() == 0 else "CTRL", sc)
		"sniff":
			return UiKit.glyph("LB" if pad else "Q", sc)
	return UiKit.glyph("A", sc)


func _has_sniff_button() -> bool:
	return player.joy >= 0 or not player.uses_keyboard() or player.keys() == 0


## [key, pointer target or null]: which picture cue this view shows now.
func cue_now() -> Array:
	var none := ["", null]
	if not player.active or get_tree().paused or (main.net.mode == "client" and not main.synced):
		return none
	if main.pad_wait.has(player.index):
		return ["plug", null]
	var ph: String = main.phase
	if ph == "intro":
		match main.round_type:
			"stars":
				return ["round_stars", null]
			"night":
				return ["round_night", null]
		return none
	if ph == "over":
		return ["again", null] if main.over_t > 2.0 else none
	if ph != "count" and ph != "seek":
		return none
	if player.role == "seeker":
		if ph != "seek":
			return none
		if main.torch_target(player) != null and not main.cue_learned(player, "torch"):
			return ["torch_hit", null]
		if main.sniff_cd <= 0.0 and _has_sniff_button() and not main.cue_learned(player, "sniff") and _hider_near(main.SNIFF_RANGE):
			return ["sniff", null]
		if not main.cue_learned(player, "torch"):
			return ["torch", null]
		return none
	if player.late:
		return ["watch", null]
	if player.found:
		return ["jail", null] if main.jail_breaks > 0 and main.hiders_left() > 0 else ["watch", null]
	if main.sneezed.has(player.index):
		return ["achoo", null]
	if ph == "seek" and main.jailed_count() > 0 and main.jail_breaks > 0 and not main.cue_learned(player, "bell"):
		return ["bell", main.bell_pos() + Vector3.UP * 1.2]
	# Hiding time teaches the disguise; seeking time teaches the squeak first (the disguise after).
	if ph == "seek" and player.taunt_cd <= 0.0 and not main.cue_learned(player, "squeak"):
		return ["squeak", null]
	if player.prop_kind < 0:
		if main.round_type == "stars" and main.star_taken.has(false) and not main.cue_learned(player, "star"):
			return ["star", _nearest_star()]
		if not main.cue_learned(player, "disguise"):
			return ["disguise", null]
	return none


func _hider_near(r: float) -> bool:
	for h in main.players:
		if h.is_hiding() and Vector2(h.global_position.x - player.global_position.x, h.global_position.z - player.global_position.z).length() < r:
			return true
	return false


func _nearest_star():
	var best = null
	var best_d := INF
	for k in main.star_idx.size():
		if k < main.star_taken.size() and not main.star_taken[k]:
			var at: Vector3 = main.star_spot(int(main.star_idx[k]))
			var d: float = at.distance_to(player.global_position)
			if d < best_d:
				best_d = d
				best = at + Vector3.UP * 0.9
	return best


func _update_cue(delta: float) -> void:
	var kt := cue_now()
	var k: String = kt[0]
	cue_key = k
	pointer.on = kt[1] != null
	if kt[1] != null:
		pointer.target = kt[1]
		pointer.col = Color(1.0, 0.8, 0.25) if k == "bell" else Color(1.0, 0.92, 0.4)
	var p = player
	var col: Color = p.color
	var extra := "%d|%d|%s|%s" % [int(p.joy >= 0), p.keys(), p.mouse_look, p.role]
	cue.set_cue(k, extra, func(sc: float) -> Array:
		match k:
			"plug":
				return [UiKit.icon("bolt", Color(1.0, 0.8, 0.3), 64.0 * sc)]
			"round_stars":
				return [UiKit.icon("star", Color(1.0, 0.85, 0.2), 64.0 * sc), UiKit.icon("star", Color(1.0, 0.85, 0.2), 48.0 * sc),
					UiKit.icon("star", Color(1.0, 0.85, 0.2), 36.0 * sc)]
			"round_night":
				return [CueScript.moon_icon(64.0 * sc), CueScript.critter_icon(54.0 * sc, col.darkened(0.6), true)]
			"again":
				return [UiKit.glyph("A" if p.joy >= 0 or not p.uses_keyboard() else "ENTER", sc), UiKit.icon("play", Color(1.0, 0.9, 0.45), 48.0 * sc)]
			"torch", "torch_hit":
				return [button("fire", sc), CueScript.torch_icon(48.0 * sc), CueScript.critter_icon(44.0 * sc, Color(0.5, 0.85, 1.0))]
			"sniff":
				return [button("sniff", sc), CueScript.nose_icon(50.0 * sc)]
			"watch":
				return [UiKit.icon("eye", Color(0.85, 0.9, 1.0), 56.0 * sc)]
			"jail":
				return [UiKit.icon("lock", Color(0.8, 0.82, 0.9), 54.0 * sc), CueScript.bell_icon(54.0 * sc)]
			"achoo":
				return [UiKit.icon("exclaim", Color(1.0, 0.5, 0.3), 60.0 * sc), CueScript.critter_icon(50.0 * sc, col)]
			"bell":
				return [CueScript.bell_icon(60.0 * sc), UiKit.icon("lock", Color(0.8, 0.82, 0.9), 44.0 * sc)]
			"star":
				return [UiKit.icon("star", Color(1.0, 0.85, 0.2), 60.0 * sc), CueScript.critter_icon(48.0 * sc, col)]
			"disguise":
				var glow: bool = main.round_type == "night"
				return [button("fire", sc), CueScript.critter_icon(48.0 * sc, col, glow), UiKit.icon("arrow_right", Color(1.0, 0.9, 0.45), 36.0 * sc),
					CueScript.box_icon(52.0 * sc)]
			"squeak":
				return [button("alt", sc), CueScript.squeak_icon(48.0 * sc, col)]
		return [], delta)


## Seeker: a pulsing torch button just right of the crosshair while a hider is in the beam.
func _update_aim_glyph() -> void:
	var show: bool = cue_key == "torch_hit"
	if not show:
		if aim_glyph != null:
			aim_glyph.visible = false
		return
	var sig := "%d|%d|%s|%.2f" % [int(player.joy >= 0), player.keys(), player.mouse_look, ui]
	if aim_glyph == null or sig != aim_sig:
		if aim_glyph != null:
			aim_glyph.queue_free()
		aim_sig = sig
		aim_glyph = button("fire", 1.6 * ui)
		aim_glyph.name = "AimGlyph"
		add_child(aim_glyph)
	aim_glyph.visible = true
	aim_glyph.size = aim_glyph.get_combined_minimum_size()
	var k := absf(sin(Time.get_ticks_msec() * 0.008))
	aim_glyph.pivot_offset = aim_glyph.size * 0.5
	aim_glyph.scale = Vector2.ONE * (1.0 + 0.2 * k)
	aim_glyph.position = size / 2.0 + Vector2(44.0 * ui, -aim_glyph.size.y * 0.5)


func _draw() -> void:
	if player == null:
		return
	var c := size / 2.0
	if found_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.9, 0.4, 0.3 * found_flash))
	if player.role == "seeker":
		if main.phase == "count":
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.02, 0.06, 0.98))
		elif main.phase == "seek":
			var target: bool = main.torch_target(player) != null
			var col := Color(1.0, 0.85, 0.3, 0.95) if target else Color(1, 1, 1, 0.6)
			draw_arc(c, (26.0 if target else 14.0) * ui, 0.0, TAU, 28, col, maxf(2.0, 3.0 * ui), true)
			draw_circle(c, 3.0, col)
		return
	if not player.is_hiding() or main.phase != "seek":
		return
	# "Seeker nearby!" warmth meter (hiders only).
	var s = main.players[0]
	var d: float = s.global_position.distance_to(player.global_position)
	var heat := clampf(1.0 - (d - 1.5) / 6.0, 0.0, 1.0)
	if heat > 0.0:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012 * (0.5 + heat))
		var edge := Color(1.0, 0.45, 0.25, heat * (0.25 + 0.2 * pulse))
		var w := 26.0 * ui
		draw_rect(Rect2(0, 0, size.x, w), edge)
		draw_rect(Rect2(0, size.y - w, size.x, w), edge)
		draw_rect(Rect2(0, 0, w, size.y), edge)
		draw_rect(Rect2(size.x - w, 0, w, size.y), edge)
	# Squeak cooldown.
	var bw := 160.0 * ui
	var bp := Vector2(size.x - bw - 24.0 * ui, size.y - 44.0 * ui)
	draw_rect(Rect2(bp - Vector2(3, 3), Vector2(bw + 6, 14.0 * ui + 6)), Color(0, 0, 0, 0.55))
	var frac: float = 1.0 - clampf(player.taunt_cd / main.TAUNT_COOLDOWN, 0.0, 1.0)
	draw_rect(Rect2(bp, Vector2(bw * frac, 14.0 * ui)), Color(1.0, 0.8, 0.35) if frac >= 1.0 else Color(0.6, 0.6, 0.7))
