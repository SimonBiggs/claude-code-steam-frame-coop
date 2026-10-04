extends Control
## One player's half-screen HUD: crosshair, health, hit markers, hurt flash and a radar.

const RADAR_RANGE := 22.0
const RADAR_SIZE := 95.0

var player
var radar_only := false  # VR wrist radar: draw just the radar, filling the control
var main
var hurt_flash := 0.0
var hit_flash := 0.0
var damage_marks: Array = []  # [world position, time left]
var name_label: Label
var bar: ProgressBar
var ui_scale := 1.0  # set by main: smaller HUD in smaller split-screen views


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if radar_only:
		return

	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_constant_override("outline_size", 6)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	name_label.add_theme_color_override("font_color", player.color)
	add_child(name_label)

	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(300, 20)
	bar.size = Vector2(300, 20)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = player.color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	add_child(bar)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and bar:
		name_label.position = Vector2(28, size.y - 92)
		bar.position = Vector2(28, size.y - 52)


func hurt() -> void:
	hurt_flash = 1.0


func damage_from(pos: Vector3) -> void:
	for m in damage_marks:
		if m[0].distance_to(pos) < 1.5:
			m[0] = pos
			m[1] = 1.0
			return
	damage_marks.append([pos, 1.0])


func hit_marker() -> void:
	hit_flash = 1.0


func _process(delta: float) -> void:
	if radar_only:
		queue_redraw()
		return
	_apply_scale()
	hurt_flash = maxf(0.0, hurt_flash - delta * 5.0)
	hit_flash = maxf(0.0, hit_flash - delta * 6.0)
	for m in damage_marks:
		m[1] -= delta * 1.2
	damage_marks = damage_marks.filter(func(m): return m[1] > 0.0)
	name_label.position = Vector2(28, size.y - 92)
	bar.position = Vector2(28, size.y - 52)
	bar.max_value = player.stat("max_hp")
	bar.value = player.hp
	var status := ""
	if player.is_down:
		status = "  ·  DOWN! partner, come revive me"
	else:
		if player.bubble_t > 0.0:
			status += "  ·  BUBBLE %ds" % int(ceil(player.bubble_t))
		if player.rapid_t > 0.0:
			status += "  ·  RAPID %ds" % int(ceil(player.rapid_t))
		if player.spread_t > 0.0:
			status += "  ·  SPREAD %ds" % int(ceil(player.spread_t))
	name_label.text = "PLAYER %d%s" % [player.index + 1, status]
	queue_redraw()


func _draw() -> void:
	if radar_only:
		_draw_radar(size / 2.0, minf(size.x, size.y) / 2.0 - 4.0)
		return
	var c := size / 2.0
	if hurt_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.1, 0.1, 0.12 * hurt_flash))
	if player.bubble_t > 0.0 and not player.is_down:
		for i in 4:
			var inset := i * 12.0
			draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0), Color(0.4, 0.65, 1.0, 0.16 * (1.0 - i / 4.0)), false, 12.0)
	if player.hp < player.stat("max_hp") * 0.3 and not player.is_down:
		var pulse := 0.12 + 0.08 * sin(Time.get_ticks_msec() * 0.008)
		for i in 6:
			var inset := i * 14.0
			draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0), Color(1, 0, 0, pulse * (1.0 - i / 6.0)), false, 14.0)

	# Red arcs pointing at whatever is hurting you (up = in front).
	for m in damage_marks:
		var rel: Vector3 = Basis(Vector3.UP, -player.yaw) * (m[0] - player.global_position)
		var ang := atan2(rel.z, rel.x)
		var alpha: float = clampf(m[1], 0.0, 1.0)
		draw_arc(c, 150.0, ang - 0.35, ang + 0.35, 16, Color(1.0, 0.15, 0.1, 0.85 * alpha), 14.0)

	# Crosshair.
	if not player.is_down:
		var col: Color = player.color.lightened(0.6)
		var gap := 7.0
		var length := 12.0
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + d * gap, c + d * (gap + length), Color(0, 0, 0, 0.6), 5.0)
			draw_line(c + d * gap, c + d * (gap + length), col, 2.5)
		draw_circle(c, 2.0, col)
		if hit_flash > 0.0:
			var hc := Color(1, 1, 1, hit_flash)
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(c + d * 9.0, c + d * 18.0, hc, 3.0)

	_draw_radar(Vector2(size.x - RADAR_SIZE - 30.0, size.y - RADAR_SIZE - 30.0), RADAR_SIZE)


## Radar: forward is up.
func _draw_radar(rc: Vector2, radius: float) -> void:
	draw_circle(rc, radius, Color(0.0, 0.02, 0.05, 0.75 if radar_only else 0.55))
	draw_arc(rc, radius, 0.0, TAU, 48, Color(player.color, 0.7), 2.0)
	draw_arc(rc, radius * 0.5, 0.0, TAU, 32, Color(player.color, 0.25), 1.0)
	var radar_scale := radius / RADAR_RANGE
	var inv := Basis(Vector3.UP, -player.yaw)
	for e in get_tree().get_nodes_in_group("enemies"):
		var p := _radar_point(e.global_position, inv, radar_scale, radius)
		draw_circle(rc + p, clampf(e.radius * 5.0, 3.0, 9.0), e.color)
	for pk in get_tree().get_nodes_in_group("pickups"):
		var q := _radar_point(pk.global_position, inv, radar_scale, radius)
		draw_rect(Rect2(rc + q - Vector2(5, 5), Vector2(10, 10)), pk.color)
	for partner in main.players:
		if partner == player or not partner.active:
			continue
		var pp := _radar_point(partner.global_position, inv, radar_scale, radius)
		if not partner.is_down or int(Time.get_ticks_msec() / 250) % 2 == 0:
			draw_circle(rc + pp, 7.0, partner.color)
			draw_arc(rc + pp, 9.0, 0.0, TAU, 16, Color.WHITE, 1.5)
	# Self arrow.
	draw_colored_polygon(PackedVector2Array([rc + Vector2(0, -9), rc + Vector2(6, 6), rc + Vector2(-6, 6)]), player.color.lightened(0.5))


func _radar_point(world_pos: Vector3, inv: Basis, radar_scale: float, radius: float) -> Vector2:
	var rel: Vector3 = inv * (world_pos - player.global_position)
	var p := Vector2(rel.x, rel.z) * radar_scale
	return p.limit_length(radius - 6.0)


## Scale the whole HUD (via its CanvasLayer) and keep it filling the view.
func _apply_scale() -> void:
	var layer := get_parent() as CanvasLayer
	if layer == null:
		return
	var s := clampf(ui_scale, 0.3, 2.0)
	if layer.scale.x != s:
		layer.scale = Vector2(s, s)
	if anchor_right != 0.0 or anchor_bottom != 0.0:
		set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	var want := get_viewport().get_visible_rect().size / s
	if size != want:
		size = want
