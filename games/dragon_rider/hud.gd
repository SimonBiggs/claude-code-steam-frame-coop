extends Control
## One split-screen view's HUD (drawn, so it scales cleanly with the view): player tag, score line,
## the four lanterns, a crosshair (gunners) or the next-ring marker (rider), markers for storm sprites
## off screen, the big centre banner and a small help line.

var player
var main
var ui_scale := 1.0
var hit_flash := 0.0
var hurt_flash := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func hit_marker() -> void:
	hit_flash = 1.0


func hurt() -> void:
	hurt_flash = 1.0


func _process(delta: float) -> void:
	hit_flash = maxf(0.0, hit_flash - delta * 5.0)
	hurt_flash = maxf(0.0, hurt_flash - delta * 1.5)
	queue_redraw()


func _text(pos: Vector2, text: String, fsize: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var font := ThemeDB.fallback_font
	var outline := Color(0.12, 0.05, 0.15, 0.9 * color.a)
	draw_string_outline(font, pos, text, align, width, fsize, maxi(4, fsize / 5), outline)
	draw_string(font, pos, text, align, width, fsize, color)


func _draw() -> void:
	if player == null or main == null:
		return
	var s := ui_scale
	var w := size.x
	var h := size.y
	var font := ThemeDB.fallback_font
	var cream := Color(1.0, 0.96, 0.86)
	# Hurt flash: a warm red frame when a lantern pops.
	if hurt_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.2, 0.2, 0.35 * hurt_flash), false, 18.0 * s)
	var role := "RIDER" if player.index == 0 else "GUNNER"
	_text(Vector2(18.0 * s, 36.0 * s), "P%d %s" % [player.index + 1, role], int(26.0 * s), player.color)
	_text(Vector2(18.0 * s, 68.0 * s), main.hud_line(), int(22.0 * s), cream)
	# Lanterns, top right.
	var lit: Array[bool] = main.dragon.lit
	for i in lit.size():
		var c := Vector2(w - (30.0 + i * 34.0) * s, 28.0 * s)
		var on: bool = lit[lit.size() - 1 - i]
		draw_circle(c, 12.0 * s, Color(1.0, 0.72, 0.3) if on else Color(0.2, 0.18, 0.2, 0.8))
		draw_arc(c, 12.0 * s, 0.0, TAU, 20, Color(0.15, 0.08, 0.1), 3.0 * s)
		if on:
			draw_circle(c, 5.0 * s, Color(1.0, 0.95, 0.75))

	var cam: Camera3D = player.camera
	if cam != null and main.phase != "over":
		if player.index == 0:
			var r: Dictionary = main.next_ring_info()
			if not r.is_empty():
				_marker(cam, r.pos, Color(1.0, 0.85, 0.3), 26.0 * s, s)
		else:
			for sp in get_tree().get_nodes_in_group("dr_sprites"):
				_marker(cam, (sp as Node3D).global_position, Color(0.85, 0.4, 1.0), 14.0 * s, s)
			var cc := size * 0.5
			var col := Color(1.0, 1.0, 1.0, 0.9).lerp(Color(1.0, 0.85, 0.3), hit_flash)
			draw_arc(cc, (16.0 + hit_flash * 8.0) * s, 0.0, TAU, 24, col, 3.0 * s)
			draw_circle(cc, 3.0 * s, col)

	# Centre banner (wrapped to the view's width).
	var a: float = main.center_alpha
	var text: String = main.center_text
	var wrap := w * 0.92
	var left := w * 0.04
	if a > 0.01 and text != "":
		var lines := text.split("\n")
		var sizes: Array[int] = []
		var heights: Array[float] = []
		var total := 0.0
		for i in lines.size():
			var fs := int(44.0 * s) if i == 0 else int(30.0 * s)
			sizes.append(fs)
			var hh := font.get_multiline_string_size(lines[i], HORIZONTAL_ALIGNMENT_CENTER, wrap, fs).y
			heights.append(hh)
			total += hh
		var y := h * 0.42 - total * 0.5
		draw_rect(Rect2(0, y - 14.0 * s, w, total + 28.0 * s), Color(0.05, 0.02, 0.1, 0.45 * a))
		for i in lines.size():
			_wrapped(Vector2(left, y + font.get_ascent(sizes[i])), lines[i], sizes[i], Color(1.0, 0.95, 0.85, a), wrap)
			y += heights[i]

	var help := ""
	var tip: String = main.hint_for(player)
	if player.index == 0:
		help = "W/S or stick: climb / dive   A/D: turn   Space / RT / A: flap\n" + (tip if tip != "" else "Fly through the GOLD rings and grab the stars!")
	else:
		help = "Aim: stick / mouse / arrows   Fire bubbles: RT / A / click / Enter\n" + (tip if tip != "" else "Pop the storm sprites before they pop the lanterns!")
	# The current tip, big and clear, just under the crosshair area for gunners.
	if tip != "" and player.index > 0 and main.center_alpha < 0.05:
		var ts := int(24.0 * s)
		_wrapped(Vector2(left, h * 0.72), tip, ts, Color(1.0, 0.92, 0.6, 0.95), wrap)
	var hs := int(17.0 * s)
	var hh2 := font.get_multiline_string_size(help, HORIZONTAL_ALIGNMENT_CENTER, wrap, hs).y
	_wrapped(Vector2(left, h - hh2 - 8.0 * s + font.get_ascent(hs)), help, hs, Color(1.0, 0.96, 0.86, 0.8), wrap)


func _wrapped(pos: Vector2, text: String, fsize: int, color: Color, width: float) -> void:
	var font := ThemeDB.fallback_font
	var outline := Color(0.12, 0.05, 0.15, 0.9 * color.a)
	draw_multiline_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, fsize, -1, maxi(4, fsize / 5), outline)
	draw_multiline_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, fsize, -1, color)


## A ring around something on screen, or an arrow at the edge pointing towards it.
func _marker(cam: Camera3D, world: Vector3, color: Color, radius: float, s: float) -> void:
	var local := cam.global_transform.affine_inverse() * world
	var margin := 40.0 * s
	if local.z < -0.5:
		var p := cam.unproject_position(world)
		if p.x > margin and p.x < size.x - margin and p.y > margin * 2.0 and p.y < size.y - margin:
			draw_arc(p, radius, 0.0, TAU, 20, color, 3.0 * s)
			return
	var dir := Vector2(local.x, -local.y)
	if dir.length() < 0.001:
		dir = Vector2(0, 1)
	dir = dir.normalized()
	var c := size * 0.5
	var half := c - Vector2(margin, margin * 1.5)
	var k := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var tip := c + dir * k
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([tip + dir * 14.0 * s, tip - dir * 8.0 * s + side * 12.0 * s, tip - dir * 8.0 * s - side * 12.0 * s])
	draw_colored_polygon(pts, color)
