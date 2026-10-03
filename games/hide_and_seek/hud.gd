extends Control
## One flat-screen player's HUD: what to do now, score, disguise / squeak status, "seeker nearby!" warning,
## the seeker's crosshair and the eyes-covered countdown. Scales down with the view when many share the TV.

var player
var main
var name_label: Label
var hint_label: Label
var big_label: Label
var ui := 1.0
var found_flash := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name_label = _label(26, player.color)
	hint_label = _label(26, Color(1.0, 0.96, 0.85))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	big_label = _label(80, Color(1.0, 0.95, 0.7))
	big_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


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
		for l in [name_label, hint_label]:
			l.add_theme_font_size_override("font_size", maxi(13, int(26 * ui)))
			l.add_theme_constant_override("outline_size", maxi(3, int(7 * ui)))
		big_label.add_theme_font_size_override("font_size", maxi(28, int(80 * ui)))
		big_label.add_theme_constant_override("outline_size", maxi(4, int(12 * ui)))
		name_label.position = Vector2(24 * ui, size.y - 60 * ui)
		hint_label.position = Vector2(size.x * 0.08, size.y * 0.7)
		hint_label.size = Vector2(size.x * 0.84, 90 * ui)
		big_label.position = Vector2(0, size.y * 0.3)
		big_label.size = Vector2(size.x, size.y * 0.3)


func _process(delta: float) -> void:
	found_flash = maxf(0.0, found_flash - delta * 1.5)
	if player == null or main == null:
		return
	var role_name := "SEEKER" if player.role == "seeker" else "HIDER"
	name_label.text = "P%d  ·  %s  ·  %d pts  (total %d)" % [player.index + 1, role_name, main.round_score(player.index), main.total_score(player.index)]
	hint_label.text = _hint()
	big_label.text = _big()
	queue_redraw()


func _big() -> String:
	if main.phase != "count":
		return ""
	var n := ceili(main.phase_t)
	if player.role == "seeker":
		return "Eyes covered!\n%d" % n
	return "HIDE!  %d" % n


func _hint() -> String:
	if main.pad_wait.has(player.index):
		return "CONTROLLER DISCONNECTED! Plug it back in within %d s to keep playing." % ceili(main.pad_wait[player.index])
	match main.phase:
		"wait":
			return "Waiting for players…"
		"intro":
			if player.role == "seeker":
				return "You're the SEEKER! Count to %d, then find everyone with your torch." % int(main.count_time)
			return "You're a HIDER! Run and hide while the seeker counts."
		"over":
			return "Press A / Enter to play again"
	if player.role == "seeker":
		if main.phase == "count":
			return "No peeking!"
		return "Click / Space / RT with a hider in the torch beam (3 m), or bump into them!  %d left" % main.hiders_left()
	if player.late:
		return "You joined mid-round: you're in the next round! Watching the seeker…"
	if player.found:
		return "FOUND! Watching the seeker… (you'll hide again next round)"
	var s: String
	if player.prop_kind >= 0:
		s = "You're a %s! Stay still…  A / Space: pop out" % main.WorldScript.PROP_NAMES[player.prop_kind]
	else:
		s = "A / Space / Enter: disguise as an object"
	if main.phase == "seek":
		s += "  ·  " + ("X / E: squeak for +%d" % main.TAUNT_POINTS if player.taunt_cd <= 0.0 else "squeak in %d s" % ceili(player.taunt_cd))
	return s


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
