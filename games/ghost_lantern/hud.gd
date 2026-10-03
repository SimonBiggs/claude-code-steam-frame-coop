extends Control
## One flat-screen player's HUD: crosshair, courage bar, capture bar and a hint line.

var player
var main
var hurt_flash := 0.0
var name_label: Label
var hint_label: Label
var ui := 1.0  # shrinks with the view when many players share the TV


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name_label = _label(24, player.color)
	hint_label = _label(26, Color(0.85, 1.0, 0.85))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _label(font: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font)
	l.add_theme_constant_override("outline_size", 7)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func hurt() -> void:
	hurt_flash = 1.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and name_label:
		# Full size for 1-2 views (a half-width 1080p view); smaller in 2x2 and 3x2 grids.
		ui = clampf(minf(size.x / 900.0, size.y / 1000.0), 0.45, 1.0)
		name_label.add_theme_font_size_override("font_size", maxi(12, int(24 * ui)))
		hint_label.add_theme_font_size_override("font_size", maxi(12, int(26 * ui)))
		name_label.add_theme_constant_override("outline_size", maxi(3, int(7 * ui)))
		hint_label.add_theme_constant_override("outline_size", maxi(3, int(7 * ui)))
		name_label.position = Vector2(28 * ui, size.y - 86 * ui)
		hint_label.position = Vector2(size.x * 0.1, size.y * 0.66)
		hint_label.size = Vector2(size.x * 0.8, 80 * ui)


func _process(delta: float) -> void:
	hurt_flash = maxf(0.0, hurt_flash - delta * 2.0)
	if player == null or main == null:
		return
	var role_name := "SPIRIT LANTERN" if player.role == "lantern" else "GHOST VACUUM"
	name_label.text = "P%d  ·  %s  ·  COURAGE" % [player.index + 1, role_name]
	hint_label.text = _hint()
	queue_redraw()


func _hint() -> String:
	if main.pad_wait.has(player.index):
		return "CONTROLLER DISCONNECTED! Plug it back in within %d s to keep playing." % ceili(main.pad_wait[player.index])
	if player.is_down:
		return "SPOOKED! Stand still: a friend next to you will cheer you up."
	if main.game_over:
		return ""
	if player.role == "lantern":
		var bell := "E / right click: ring the bell" if player.bell_cd <= 0.0 else "Bell in %d s" % ceili(player.bell_cd)
		return "Point the lantern at ghosts  ·  hold Space / click to focus  ·  " + bell
	var lantern_p = main.players[0]
	if lantern_p.is_down:
		return "The lantern-bearer is spooked! Go stand next to them!"
	if player.vac_on and main.vac_progress(player) < 0.0:
		return "NO LIGHT! Shout where you need the lantern!"
	if main.night <= 1:
		return "Ghosts only show up in the lantern's light. Hold fire to vacuum them!"
	return ""


func _draw() -> void:
	if player == null:
		return
	var c := size / 2.0
	if hurt_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 1.0, 0.55, 0.28 * hurt_flash))
	if player.is_down:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.2, 0.1, 0.35, 0.35))
	var progress: float = main.vac_progress(player)
	if player.role == "vacuum":
		var ring_col := Color(0.5, 1.0, 0.65, 0.9) if progress >= 0.0 else Color(1, 1, 1, 0.55)
		draw_arc(c, 34.0 * ui, 0.0, TAU, 32, ring_col, maxf(2.0, 3.0 * ui), true)
		draw_circle(c, 3.0, ring_col)
		if progress >= 0.0:
			var w := 220.0 * ui
			var top := c + Vector2(-w / 2.0, 52.0 * ui)
			draw_rect(Rect2(top - Vector2(3, 3), Vector2(w + 6, 16.0 * ui + 6.0)), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(top, Vector2(w * clampf(progress, 0.0, 1.0), 16.0 * ui)), Color(0.45, 1.0, 0.6))
	else:
		draw_arc(c, 10.0, 0.0, TAU, 20, Color(0.85, 1.0, 0.75, 0.8), 2.0, true)
	# Courage bar.
	var bar_pos := Vector2(28, size.y - 50) * Vector2(ui, 1.0) + Vector2(0.0, 50.0 * (1.0 - ui))
	var bw := 300.0 * ui
	var bh := 20.0 * ui
	draw_rect(Rect2(bar_pos - Vector2(3, 3), Vector2(bw + 6, bh + 6)), Color(0, 0, 0, 0.6))
	var frac := clampf(player.courage / player.MAX_COURAGE, 0.0, 1.0)
	draw_rect(Rect2(bar_pos, Vector2(bw * frac, bh)), Color(0.75, 0.45, 1.0).lerp(Color(0.45, 1.0, 0.6), frac))
