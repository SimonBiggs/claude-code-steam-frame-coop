extends Control
## One TV player's HUD: crosshair with a charge ring, warmth bar, frosty hurt vignette,
## repair prompt and a little fort map (wall health, snowmen, friends, cocoa).
## Simple mode (main.simple): just the crosshair, the hit marker, the frosty splat and which way it came
## from, and the player's "P2" in their colour. No how-to words (visual teaching): a pulsing glowing
## button in this player's own controls plus an icon sits under the crosshair - RT / CLICK / SPACE /
## ENTER + a snowball (throw) until they've thrown twice, STICK / MOUSE / an arrow key + an arrow (turn)
## while every snowman is off screen, a pulsing bolt when their controller is unplugged - and a glowing
## arrow round the crosshair points at the nearest snowman when none is in view. Each cue goes once the
## player has done it twice (main.cue_did / main.cue_learned).

const MAP_RANGE := 22.0
const MAP_SIZE := 92.0
const UiKit := preload("res://core/ui_kit.gd")

var player
var main
var hurt_flash := 0.0
var hit_flash := 0.0
var damage_marks: Array = []
var name_label: Label
var prompt: Label
var bar: ProgressBar
var cue_box: Control  # simple mode: the picture cue (glow + a row of button and icon)
var cue_a := 0.0
var cue_sig := ""
var turn_ang := 0.0  # simple mode: screen angle of the arrow towards the nearest off-screen snowman
var turn_a := 0.0
var off_t := 0.0  # how long every snowman has been off screen
var turn_shown := false


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
	if main.simple:
		_simple_text()
		queue_redraw()
		return
	bar.value = player.hp
	name_label.text = "P%d  WARMTH%s" % [player.index + 1, "      * MEGA SNOWBALL READY - throw it!" if player.mega else ""]
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


func _simple_text() -> void:
	bar.visible = false
	name_label.text = "P%d" % (player.index + 1)
	prompt.text = ""  # no words: picture cues instead (_update_cue)
	_update_turn(get_process_delta_time())
	_update_cue(get_process_delta_time())


## Simple mode: is any snowman in this player's view? If none is, the turn arrow points at the nearest.
func _update_turn(delta: float) -> void:
	var cam: Camera3D = player.camera
	var want := false
	if cam != null and player.active and not main.practice and not main.game_over and not player.is_down and not get_tree().paused \
			and not main.cue_learned(player, "turn"):
		var nearest = null
		var nd := INF
		var seen := false
		var vs := get_viewport().get_visible_rect().size
		for s in get_tree().get_nodes_in_group("snowmen"):
			if s.dead or s.kind == "target":
				continue
			var at: Vector3 = s.global_position + Vector3.UP * 1.0
			if not cam.is_position_behind(at):
				var sp := cam.unproject_position(at)
				if sp.x > vs.x * 0.08 and sp.x < vs.x * 0.92 and sp.y > 0.0 and sp.y < vs.y:
					seen = true
					break
			var d: float = s.global_position.distance_to(player.global_position)
			if d < nd:
				nd = d
				nearest = s
		if seen or nearest == null:
			if turn_shown and seen:
				main.cue_did(player, "turn")  # they turned to the snowman the arrow showed
			turn_shown = false
			off_t = 0.0
		else:
			off_t += delta
			if off_t > 1.5:
				want = true
				turn_shown = true
				var rel: Vector3 = Basis(Vector3.UP, -player.yaw) * (nearest.global_position - player.global_position)
				turn_ang = atan2(rel.z, rel.x)
				if rel.z > 0.0:
					turn_ang = 0.0 if rel.x >= 0.0 else PI  # behind you: point the way to turn, never down
	else:
		turn_shown = false
		off_t = 0.0
	turn_a = minf(1.0, turn_a + delta * 4.0) if want else maxf(0.0, turn_a - delta * 3.0)


## This player's own button: "throw" or "turn" (dir "left" / "right").
func _button(action: String, dir: String, s: float) -> Control:
	if player.joy >= 0:
		return UiKit.glyph("RT" if action == "throw" else "STICK", s)
	if action == "throw":
		if player.mouse_look:
			return UiKit.glyph("CLICK", s)
		return UiKit.glyph("ENTER" if player.keys() == 1 else "SPACE", s)
	if player.keys() == 1:
		var g := UiKit.glyph("KEY", s)  # an arrow key
		(g.get_child(0) as Label).text = ""
		var ic := UiKit.icon("arrow_" + dir, Color.WHITE, 26.0 * s)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		g.add_child(ic)
		return g
	return UiKit.glyph("MOUSE", s)


func _btn_sig() -> String:
	return "%d/%d/%s" % [player.joy, player.keys(), player.mouse_look]


## The soft halo behind a cue's button.
class CueGlow extends Control:
	var r := 30.0
	var a := 1.0

	func _draw() -> void:
		for i in 3:
			draw_circle(Vector2.ZERO, r * (1.0 + 0.35 * i), Color(1.0, 0.95, 0.6, 0.17 * a * (1.0 - 0.3 * i)))


func _update_cue(delta: float) -> void:
	var key := ""
	var dir := ""
	var playing: bool = not main.game_over and not get_tree().paused and not player.is_down \
		and (main.net.mode != "client" or main.synced)
	if player.joy < 0 and not player.has_keyboard():
		key = "plug"
	elif playing and not main.cue_learned(player, "throw") and (main.practice or main.wave > 0):
		key = "throw"
	elif playing and turn_a > 0.5 and turn_shown:
		key = "turn"
		dir = "left" if cos(turn_ang) < 0.0 else "right"
	player.set_meta("cue", key)
	var s := 2.1
	if cue_box == null:
		cue_box = Control.new()
		cue_box.name = "Cue"
		cue_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cue_box)
		var glow := CueGlow.new()
		glow.name = "Glow"
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cue_box.add_child(glow)
		player.set_meta("cue_box", cue_box)
	var full := "%s|%s|%s" % [key, dir, _btn_sig()]
	if key != "" and full != cue_sig:
		if cue_sig.get_slice("|", 0) != key:
			cue_a = 0.0  # a new cue fades in
		cue_sig = full
		var old := cue_box.get_node_or_null("Row")
		if old != null:
			cue_box.remove_child(old)
			old.queue_free()
		var row := HBoxContainer.new()
		row.name = "Row"
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		var items: Array = []
		match key:
			"plug":
				items = [UiKit.icon("bolt", Color(1.0, 0.75, 0.3), 56.0 * s)]
			"throw":
				items = [_button("throw", "", s), UiKit.icon("dot", Color(0.95, 0.98, 1.0), 64.0 * s)]
			"turn":
				items = [_button("turn", dir, s), UiKit.icon("arrow_" + dir, Color(1.0, 0.9, 0.4), 40.0 * s)]
		for k in items.size():
			var c: Control = items[k]
			if k == 0:
				c.name = "Button"
			c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(c)
		cue_box.add_child(row)
	cue_a = minf(1.0, cue_a + delta * 4.0) if key != "" else maxf(0.0, cue_a - delta * 2.5)
	var rw := cue_box.get_node_or_null("Row") as Control
	cue_box.visible = cue_a > 0.01 and rw != null
	if not cue_box.visible:
		if cue_a <= 0.01:
			cue_sig = ""
		return
	rw.size = rw.get_combined_minimum_size()
	var k2 := absf(sin(Time.get_ticks_msec() * 0.004))
	var at := Vector2(size.x * 0.5, size.y * 0.8)
	cue_box.position = at - Vector2(rw.size.x * 0.5, rw.size.y + 10.0 * k2)
	rw.position = Vector2.ZERO
	cue_box.modulate = Color(1.0 + 0.3 * k2, 1.0 + 0.3 * k2, 1.0 + 0.3 * k2, cue_a * (0.8 + 0.2 * k2))
	var btn := rw.get_node_or_null("Button") as Control
	var glow2 := cue_box.get_node_or_null("Glow") as CueGlow
	if btn != null:
		btn.pivot_offset = btn.size * 0.5
		btn.scale = Vector2.ONE * (1.0 + 0.15 * k2)
		if glow2 != null:
			glow2.position = btn.position + btn.size * 0.5
			glow2.r = btn.size.y * 0.75 * (1.0 + 0.2 * k2)
			glow2.a = cue_a
			glow2.queue_redraw()


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
	if main.simple and turn_a > 0.01:
		_draw_turn_arrow(c)
	if not main.simple:
		_draw_map(Vector2(size.x - MAP_SIZE - 30.0, size.y - MAP_SIZE - 30.0), MAP_SIZE)


## Simple mode: a fat glowing arrow round the crosshair pointing at the nearest snowman (off screen).
func _draw_turn_arrow(c: Vector2) -> void:
	var k := absf(sin(Time.get_ticks_msec() * 0.006))
	var d := Vector2(cos(turn_ang), sin(turn_ang))
	var n := Vector2(-d.y, d.x)
	var tip := c + d * (205.0 + 18.0 * k)
	var base := tip - d * 70.0
	var col := Color(1.0, 0.9, 0.35, turn_a * (0.7 + 0.3 * k))
	for i in 3:
		var g := 10.0 * (3 - i)
		draw_colored_polygon(PackedVector2Array([tip + d * g, base + n * (44.0 + g) - d * g * 0.5, base - n * (44.0 + g) - d * g * 0.5]),
			Color(1.0, 0.95, 0.6, 0.12 * turn_a))
	draw_colored_polygon(PackedVector2Array([tip, base + n * 44.0, base - n * 44.0]), col)
	var tail := PackedVector2Array([base + n * 18.0, base - n * 18.0, base - n * 18.0 - d * 50.0, base + n * 18.0 - d * 50.0])
	draw_colored_polygon(tail, col)
	draw_polyline(PackedVector2Array([tip, base + n * 44.0, base + n * 18.0, base + n * 18.0 - d * 50.0, base - n * 18.0 - d * 50.0,
		base - n * 18.0, base - n * 44.0, tip]), Color(0.2, 0.12, 0.0, 0.8 * turn_a), 3.0)


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
