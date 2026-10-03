extends Control
## One TV player's HUD: crosshair with a charge ring, warmth bar, frosty hurt vignette,
## repair prompt and a little fort map (wall health, snowmen, friends, cocoa).

const MAP_RANGE := 22.0
const MAP_SIZE := 92.0

var player
var main
var hurt_flash := 0.0
var hit_flash := 0.0
var damage_marks: Array = []
var name_label: Label
var prompt: Label
var bar: ProgressBar


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name_label = _label(26, player.color)
	add_child(name_label)
	prompt = _label(30, Color(1.0, 0.9, 0.7))
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(prompt)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(300, 20)
	bar.size = Vector2(300, 20)
	bar.max_value = 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.6, 0.3)
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	add_child(bar)


func _label(font: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font)
	l.add_theme_constant_override("outline_size", 7)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func hurt() -> void:
	hurt_flash = 1.0


func hit_marker() -> void:
	hit_flash = 1.0


func damage_from(pos: Vector3) -> void:
	for m in damage_marks:
		if m[0].distance_to(pos) < 1.5:
			m[0] = pos
			m[1] = 1.0
			return
	damage_marks.append([pos, 1.0])


## Shrink the whole HUD in small split-screen views (3+ players) so it doesn't cover the view.
func _fit_to_view() -> void:
	var vs := get_viewport().get_visible_rect().size
	if vs.x < 1.0 or vs.y < 1.0:
		return
	var k := clampf(minf(vs.x / 900.0, vs.y / 600.0), 0.45, 1.0)
	if anchor_right != 0.0 or anchor_bottom != 0.0:
		set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	scale = Vector2(k, k)
	size = vs / k


func _process(delta: float) -> void:
	_fit_to_view()
	hurt_flash = maxf(0.0, hurt_flash - delta * 4.0)
	hit_flash = maxf(0.0, hit_flash - delta * 6.0)
	for m in damage_marks:
		m[1] -= delta * 1.2
	damage_marks = damage_marks.filter(func(m): return m[1] > 0.0)
	name_label.position = Vector2(28, size.y - 92)
	bar.position = Vector2(28, size.y - 52)
	bar.value = player.hp
	name_label.text = "P%d  WARMTH%s" % [player.index + 1, "      ★ MEGA SNOWBALL READY - throw it!" if player.mega else ""]
	var text := ""
	if player.is_down:
		text = "BRRR! You're frozen solid!\nA friend can stand next to you to thaw you out"
	elif player.repairing:
		var hp: float = main.seg_hp[player.repair_seg]
		text = "Packing snow…  %d%%" % int(hp / main.seg_max * 100.0)
	elif player.repair_seg >= 0:
		text = "This wall is crumbling!  Hold %s to pack it" % ("X / LB" if player.joy >= 0 else ("E / right-click" if player.keys() == 0 else "Ctrl"))
	elif player.joy < 0 and not player.has_keyboard():
		text = "Controller unplugged - plug it back in to keep playing"
	prompt.text = text
	prompt.size = Vector2(size.x, 100)
	prompt.position = Vector2(0, size.y * 0.62)
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	# Frosty vignette when hit, and a gentle one when cold.
	var cold: float = clampf(1.0 - player.hp / 40.0, 0.0, 1.0) * 0.6 if not player.is_down else 0.8
	var frost := maxf(hurt_flash, cold)
	if frost > 0.0:
		for i in 7:
			var inset := i * 16.0
			draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0), Color(0.75, 0.9, 1.0, 0.16 * frost * (1.0 - i / 7.0)), false, 16.0)
	for m in damage_marks:
		var rel: Vector3 = Basis(Vector3.UP, -player.yaw) * (m[0] - player.global_position)
		var ang := atan2(rel.z, rel.x)
		var alpha: float = clampf(m[1], 0.0, 1.0)
		draw_arc(c, 150.0, ang - 0.35, ang + 0.35, 16, Color(0.6, 0.85, 1.0, 0.85 * alpha), 14.0)
	if not player.is_down:
		var col := Color(1, 1, 1, 0.9)
		draw_arc(c, 9.0, 0.0, TAU, 20, Color(0, 0, 0, 0.5), 4.0)
		draw_arc(c, 9.0, 0.0, TAU, 20, col, 2.0)
		var ch: float = player.charge()
		if player.charging:
			draw_arc(c, 22.0, -PI / 2.0, -PI / 2.0 + TAU * ch, 32, Color(0, 0, 0, 0.6), 8.0)
			draw_arc(c, 22.0, -PI / 2.0, -PI / 2.0 + TAU * ch, 32, player.color.lightened(0.4), 5.0)
		if hit_flash > 0.0:
			var hc := Color(1.0, 0.85, 0.4, hit_flash)
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(c + d * 12.0, c + d * 22.0, hc, 3.0)
	_draw_map(Vector2(size.x - MAP_SIZE - 30.0, size.y - MAP_SIZE - 30.0), MAP_SIZE)


## Top-down fort map, forward is up.
func _draw_map(rc: Vector2, radius: float) -> void:
	draw_circle(rc, radius, Color(0.05, 0.06, 0.12, 0.6))
	draw_arc(rc, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 2.0)
	var k := radius / MAP_RANGE
	var inv := Basis(Vector3.UP, -player.yaw)
	var n: int = main.segments
	for i in n:
		var a := TAU * i / n
		var frac: float = main.seg_hp[i] / main.seg_max
		var col := Color(1.0, 0.3, 0.25).lerp(Color(0.85, 0.95, 1.0), frac)
		if frac <= 0.0:
			col = Color(1.0, 0.2, 0.2, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.01))
		var p0 := _map_point(Vector3(cos(a - 0.3), 0, sin(a - 0.3)) * main.fort_r, inv, k, radius)
		var p1 := _map_point(Vector3(cos(a + 0.3), 0, sin(a + 0.3)) * main.fort_r, inv, k, radius)
		draw_line(rc + p0, rc + p1, col, 3.0 + 4.0 * frac)
	for s in get_tree().get_nodes_in_group("snowmen"):
		var q := _map_point(s.global_position, inv, k, radius)
		draw_circle(rc + q, clampf(s.s * 3.5, 3.0, 9.0), Color(0.75, 0.88, 1.0) if s.kind != "king" else Color(1.0, 0.8, 0.3))
	for cup in get_tree().get_nodes_in_group("cocoa"):
		var q := _map_point(cup.global_position, inv, k, radius)
		draw_rect(Rect2(rc + q - Vector2(4, 4), Vector2(8, 8)), Color(0.6, 0.85, 1.0) if cup.kind == "mega" else Color(0.75, 0.45, 0.25))
	for partner in main.players:
		if partner == player or not partner.active:
			continue
		var pp := _map_point(partner.global_position, inv, k, radius)
		if not partner.is_down or int(Time.get_ticks_msec() / 250) % 2 == 0:
			draw_circle(rc + pp, 6.0, partner.color)
	draw_colored_polygon(PackedVector2Array([rc + Vector2(0, -8), rc + Vector2(6, 6), rc + Vector2(-6, 6)]), player.color.lightened(0.4))


func _map_point(world_pos: Vector3, inv: Basis, k: float, radius: float) -> Vector2:
	var rel: Vector3 = inv * (world_pos - player.global_position)
	return (Vector2(rel.x, rel.z) * k).limit_length(radius - 5.0)
