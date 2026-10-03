extends Control
## One flat player's HUD: crosshair, what to do next, the hold's water level and the cannons' ammo.

var player
var main
var prompt: Label
var hit_flash := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	prompt = Label.new()
	prompt.add_theme_font_size_override("font_size", 30)
	prompt.add_theme_constant_override("outline_size", 8)
	prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(prompt)


func hit_marker() -> void:
	hit_flash = 1.0


func _process(delta: float) -> void:
	hit_flash = maxf(0.0, hit_flash - delta * 6.0)
	_fit_to_view()
	prompt.size = Vector2(size.x - 80.0, 120.0)
	prompt.position = Vector2(40.0, size.y - 230.0)
	var text: String = main.player_prompt(player)
	prompt.text = text
	prompt.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55) if not text.begins_with("!") else Color(1.0, 0.5, 0.4))
	if text.begins_with("!"):
		prompt.text = text.substr(1)
	queue_redraw()


## Scales the whole HUD down in smaller split-screen views (full size at 960x720 and up).
func _fit_to_view() -> void:
	if anchor_right != 0.0 or anchor_bottom != 0.0:
		set_anchors_preset(Control.PRESET_TOP_LEFT)
	var vs := get_viewport().get_visible_rect().size
	var s := clampf(minf(vs.y / 720.0, vs.x / 960.0), 0.45, 1.0)
	scale = Vector2(s, s)
	position = Vector2.ZERO
	size = vs / s


func _draw() -> void:
	var font := get_theme_default_font()
	var c := size * 0.5
	# Who this view belongs to, in the player's colour.
	var who: String = "P%d GUNNER" % (player.index + 1) if player.gunner else "P%d DECKHAND" % (player.index + 1)
	draw_string_outline(font, Vector2(size.x - 260.0, size.y - 22.0), who, HORIZONTAL_ALIGNMENT_RIGHT, 240.0, 28, 8, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(size.x - 260.0, size.y - 22.0), who, HORIZONTAL_ALIGNMENT_RIGHT, 240.0, 28, player.color)
	if not player.gunner:
		# Crosshair.
		var col := Color(1, 1, 1, 0.85) if hit_flash <= 0.0 else Color(1.0, 0.4, 0.3)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(c + d * 7.0, c + d * 17.0, Color(0, 0, 0, 0.6), 5.0)
			draw_line(c + d * 7.0, c + d * 17.0, col, 2.5)
		if hit_flash > 0.0:
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(c + d * 9.0, c + d * 20.0, Color(1, 1, 1, hit_flash), 3.0)
		# Carried cannonball.
		if player.carrying:
			var bc := Vector2(size.x - 90.0, size.y - 90.0)
			draw_circle(bc, 34.0, Color(0, 0, 0, 0.5))
			draw_circle(bc, 28.0, Color(0.12, 0.12, 0.14))
			draw_circle(bc + Vector2(-9, -9), 7.0, Color(1, 1, 1, 0.35))
	# Water in the hold: a vertical gauge on the left.
	var water: float = main.water
	var gx := 30.0
	var gh := minf(260.0, size.y * 0.4)
	var gy := size.y - 60.0 - gh
	draw_rect(Rect2(gx - 4, gy - 4, 44, gh + 8), Color(0, 0, 0, 0.55))
	var fill := gh * water / 100.0
	var wcol := Color(0.3, 0.7, 1.0) if water < 60.0 else Color(1.0, 0.35 + 0.2 * sin(Time.get_ticks_msec() * 0.012), 0.3)
	draw_rect(Rect2(gx, gy + gh - fill, 36, fill), wcol)
	draw_string(font, Vector2(gx - 4, gy - 12), "WATER %d%%" % int(water), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	# Cannon ammo, top-left: one row per cannon.
	var y := 40.0
	for cn in main.cannons:
		var ammo: int = cn.ammo
		var name_col := Color(1.0, 0.9, 0.5) if cn.manned else Color(0.85, 0.85, 0.85)
		var label: String = "%s %s" % [cn.side_name(), "FORE" if cn.index % 2 == 0 else "AFT"]
		draw_string(font, Vector2(26, y + 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, name_col)
		for i in cn.MAX_AMMO:
			var p := Vector2(196 + i * 24, y)
			draw_circle(p, 9.0, Color(0, 0, 0, 0.6))
			if i < ammo:
				draw_circle(p, 7.0, Color(0.95, 0.95, 0.95))
		if ammo == 0:
			draw_string(font, Vector2(196 + 4 * 24, y + 8), "EMPTY!", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 0.4, 0.3))
		y += 28.0
