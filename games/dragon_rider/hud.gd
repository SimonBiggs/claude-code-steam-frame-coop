extends Control
## One split-screen view's HUD (drawn, so it scales cleanly with the view): player tag, score line,
## the four lanterns, a crosshair (gunners) or the next-ring marker (rider), markers for storm sprites
## off screen, the big centre banner and a small help line.
## Simple mode (main.SIMPLE_MODE): no how-to words (visual teaching). A pulsing glowing button in this
## player's own controls plus an icon sits low in the view: the flat rider gets STICK / a W A S D key +
## an arrow the way to the next ring (until two rings flown through) and RT / SPACE + a forward arrow
## to flap when the ring is far ahead (until flapped twice); a gunner gets RT / CLICK / SPACE / ENTER +
## a bubble (fire, until two presses), STICK / MOUSE / an arrow key + an arrow when their practice
## balloon or a storm sprite is off screen (until they've turned to it twice), and a pulsing bolt when
## their controller is unplugged. The next ring / practice balloon marker is a big glowing arrow at the
## view's edge. Each cue goes once done twice (main.cue_did / main.cue_learned).

const UiKit := preload("res://core/ui_kit.gd")
const BUBBLE := Color(0.7, 0.95, 1.0)

var player
var main
var ui_scale := 1.0
var hit_flash := 0.0
var hurt_flash := 0.0
var cue_box: Control  # simple mode: the picture cue (glow + a row of button and icon)
var cue_a := 0.0
var cue_sig := ""
var off_t := 0.0  # gunner: how long their aim target has been off screen
var aim_dir := ""
var aim_shown := false
var steer_t := 0.0  # rider: how long the next ring has been off to one side
var steer_dir := ""
var edge_arrow := false  # simple mode: a glowing edge arrow was drawn this frame (bot)
var texts: Array[String] = []  # simple mode: every word drawn this frame (bot checks them)


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
	if player != null and main != null and main.SIMPLE_MODE:
		_update_cue(delta)
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
	if main.SIMPLE_MODE:
		_draw_simple(s, w, h)
		return
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


## Simple mode: no score, lanterns or help text. Markers (the next ring for the rider; your own
## practice balloon and storm sprites for gunners: big glowing arrows when off screen), the crosshair
## and one short headline. How to play is shown by the picture cue (_update_cue), never in words.
func _draw_simple(s: float, w: float, h: float) -> void:
	texts.clear()
	edge_arrow = false
	var cam: Camera3D = player.camera
	if cam != null:
		if player.index == 0:
			var r: Dictionary = main.next_ring_info()
			if not r.is_empty():
				_marker(cam, r.pos, Color(1.0, 0.85, 0.3), 30.0 * s, s, true)
		else:
			var mine = main.practice_balloons.get(player.index)
			if mine != null and is_instance_valid(mine):
				_marker(cam, (mine as Node3D).global_position, player.color, 34.0 * s, s, true)
			for sp in get_tree().get_nodes_in_group("dr_sprites"):
				_marker(cam, (sp as Node3D).global_position, Color(0.85, 0.4, 1.0), 14.0 * s, s)
			var cc := size * 0.5
			var col := Color(1.0, 1.0, 1.0, 0.9).lerp(Color(1.0, 0.85, 0.3), hit_flash)
			draw_arc(cc, (16.0 + hit_flash * 8.0) * s, 0.0, TAU, 24, col, 3.0 * s)
			draw_circle(cc, 3.0 * s, col)
	var a: float = main.center_alpha
	var text: String = (main.center_text as String).get_slice("\n", 0)
	if a > 0.01 and text != "":
		var fs := int(64.0 * s)
		texts.append(text)
		_wrapped(Vector2(w * 0.04, h * 0.3), text, fs, Color(1.0, 0.95, 0.75, a), w * 0.92)


# --- Simple mode: picture cues ----------------------------------------------------

func _has_keyboard() -> bool:
	if player.index == 0:
		return player.key_set >= 0
	return player.mouse_look or player.key_set < player.KEYS.size()


func _playing() -> bool:
	return not get_tree().paused and main.phase in ["practice", "intro", "fly"] \
		and (main.net.mode != "client" or main.phase != "wait")


## Rider: which way is the next ring (dragon-local)? "left" / "right" / "up" / "down", or "" (ahead).
func _ring_dir() -> String:
	var r: Dictionary = main.next_ring_info()
	if r.is_empty():
		return ""
	var core: Vector3 = main.dragon.core_position()
	var to: Vector3 = (r.pos as Vector3) - core
	var err := wrapf(atan2(-to.x, -to.z) - float(main.dragon.yaw), -PI, PI)
	if absf(err) > 0.25:
		return "left" if err > 0.0 else "right"
	if to.y > 6.0:
		return "up"
	if to.y < -6.0:
		return "down"
	return ""


## Gunner: their aim target (own practice balloon, else the nearest storm sprite, else a Storm King
## orb). Off screen for a moment: the aim cue shows the way to turn; turning to it counts as done.
func _update_aim(delta: float) -> void:
	var cam: Camera3D = player.camera
	var target: Node3D = null
	if cam != null and _playing() and not main.cue_learned(player, "aim"):
		var mine = main.practice_balloons.get(player.index)
		if mine != null and is_instance_valid(mine):
			target = mine
		else:
			var nd := 70.0
			for n in get_tree().get_nodes_in_group("dr_targets"):
				var kind: String = n.get_meta("kind", "")
				if kind != "sprite" and kind != "orb":
					continue
				var d: float = (n as Node3D).global_position.distance_to(cam.global_position)
				if d < nd:
					nd = d
					target = n
	if target == null:
		off_t = 0.0
		aim_shown = false
		aim_dir = ""
		return
	var local := cam.global_transform.affine_inverse() * target.global_position
	var seen := false
	if local.z < -0.5:
		var sp := cam.unproject_position(target.global_position)
		seen = sp.x > size.x * 0.1 and sp.x < size.x * 0.9 and sp.y > size.y * 0.08 and sp.y < size.y * 0.92
	if seen:
		if aim_shown:
			main.cue_did(player, "aim")  # they turned to it
		aim_shown = false
		off_t = 0.0
		aim_dir = ""
		return
	off_t += delta
	if off_t > 1.5:
		aim_shown = true
		if absf(local.x) >= absf(local.y) or local.z > 0.0:
			aim_dir = "left" if local.x < 0.0 else "right"
		else:
			aim_dir = "up" if local.y > 0.0 else "down"


## This player's own button for `action`: "steer", "flap", "fire" or "aim" (dir: an arrow's way).
func _button(action: String, dir: String, s: float) -> Control:
	if player.joy >= 0:
		match action:
			"flap", "fire":
				return UiKit.glyph("RT", s)
		return UiKit.glyph("STICK", s)
	if player.index == 0:  # the flat rider: W A S D + Space
		if action == "flap":
			return UiKit.glyph("SPACE", s)
		return _key_cap({"left": "A", "right": "D", "up": "W", "down": "S"}.get(dir, "W"), s)
	if action == "fire":
		if player.mouse_look:
			return UiKit.glyph("CLICK", s)
		return UiKit.glyph("ENTER" if player.key_set == 1 else "SPACE", s)
	if player.key_set == 1:  # arrow keys
		var g := _key_cap("", s)
		var ic := UiKit.icon("arrow_" + dir, Color.WHITE, 26.0 * s)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		g.add_child(ic)
		return g
	if player.mouse_look:
		return UiKit.glyph("MOUSE", s)
	return _key_cap({"left": "A", "right": "D", "up": "W", "down": "S"}.get(dir, "W"), s)


## A keyboard key cap with a letter on it (UiKit.glyph would draw "A" as the round pad button).
func _key_cap(letter: String, s: float) -> PanelContainer:
	var g := UiKit.glyph("KEY", s)
	(g.get_child(0) as Label).text = letter
	return g


func _btn_sig() -> String:
	return "%d/%d/%s" % [player.joy, player.key_set, player.mouse_look]


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
	if player.index == 0:
		var d := _ring_dir() if _playing() and not main.cue_learned(player, "steer") else ""
		if d != "" and d == steer_dir:
			steer_t += delta
		else:
			steer_t = 0.0
			steer_dir = d
		if player.joy < 0 and not _has_keyboard():
			key = "plug"
		elif steer_dir != "" and steer_t > 0.8:
			key = "steer"
			dir = steer_dir
		elif _playing() and main.cue_learned(player, "steer") and not main.cue_learned(player, "flap") and main.flap_moment():
			key = "flap"
	else:
		_update_aim(delta)
		if player.joy < 0 and not _has_keyboard():
			key = "plug"
		elif aim_shown and aim_dir != "":
			key = "aim"
			dir = aim_dir
		elif _playing() and not main.cue_learned(player, "fire"):
			key = "fire"
	player.set_meta("cue", key)
	var s := 1.9 * ui_scale
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
	var full := "%s|%s|%s|%.2f" % [key, dir, _btn_sig(), s]
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
		row.add_theme_constant_override("separation", int(10 * s))
		var items: Array = []
		match key:
			"plug":
				items = [UiKit.icon("bolt", Color(1.0, 0.75, 0.3), 56.0 * s)]
			"steer":
				items = [_button("steer", dir, s), UiKit.icon("arrow_" + dir, Color(1.0, 0.85, 0.3), 40.0 * s)]
			"flap":
				items = [_button("flap", "", s), UiKit.icon("arrow_up", Color(1.0, 0.85, 0.3), 40.0 * s)]
			"fire":
				items = [_button("fire", "", s), UiKit.icon("dot", BUBBLE, 56.0 * s)]
			"aim":
				items = [_button("aim", dir, s), UiKit.icon("arrow_" + dir, player.color, 40.0 * s)]
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
	var at := Vector2(size.x * 0.5, size.y * 0.86)
	cue_box.position = at - Vector2(rw.size.x * 0.5, rw.size.y + 10.0 * k2 * ui_scale)
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


func _wrapped(pos: Vector2, text: String, fsize: int, color: Color, width: float) -> void:
	var font := ThemeDB.fallback_font
	var outline := Color(0.12, 0.05, 0.15, 0.9 * color.a)
	draw_multiline_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, fsize, -1, maxi(4, fsize / 5), outline)
	draw_multiline_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, fsize, -1, color)


## A ring around something on screen, or an arrow at the edge pointing towards it.
## glow (simple mode): a pulsing ring with a halo on screen, a big glowing pulsing arrow off screen.
func _marker(cam: Camera3D, world: Vector3, color: Color, radius: float, s: float, glow: bool = false) -> void:
	var local := cam.global_transform.affine_inverse() * world
	var margin := (70.0 if glow else 40.0) * s
	var k := absf(sin(Time.get_ticks_msec() * 0.006))
	if local.z < -0.5:
		var p := cam.unproject_position(world)
		if p.x > margin and p.x < size.x - margin and p.y > margin * 2.0 and p.y < size.y - margin:
			if glow:
				for i in 3:
					draw_arc(p, radius * (1.0 + 0.12 * k) + 6.0 * s * i, 0.0, TAU, 28,
						Color(color.r, color.g, color.b, 0.25 * (1.0 - 0.3 * i)), 6.0 * s)
			draw_arc(p, radius * ((1.0 + 0.12 * k) if glow else 1.0), 0.0, TAU, 28 if glow else 20, color, (4.0 if glow else 3.0) * s)
			return
	var dir := Vector2(local.x, -local.y)
	if dir.length() < 0.001:
		dir = Vector2(0, 1)
	dir = dir.normalized()
	var c := size * 0.5
	var half := c - Vector2(margin, margin * 1.5)
	var reach := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var tip := c + dir * reach
	var side := Vector2(-dir.y, dir.x)
	if glow:  # a fat glowing arrow, bobbing towards the way to look
		edge_arrow = true
		var at := tip - dir * 30.0 * s * (1.0 - k)
		var hl := 46.0 * s
		var hw := 36.0 * s
		for i in 3:
			var g := 8.0 * s * (3 - i)
			draw_colored_polygon(PackedVector2Array([at + dir * g, at - dir * (hl + g * 0.5) + side * (hw + g),
				at - dir * (hl + g * 0.5) - side * (hw + g)]), Color(color.r, color.g, color.b, 0.14))
		var base := at - dir * hl
		var body := PackedVector2Array([at, base + side * hw, base + side * hw * 0.42, base + side * hw * 0.42 - dir * 34.0 * s,
			base - side * hw * 0.42 - dir * 34.0 * s, base - side * hw * 0.42, base - side * hw])
		draw_colored_polygon(body, Color(color.r, color.g, color.b, 0.75 + 0.25 * k))
		body.append(at)
		draw_polyline(body, Color(0.15, 0.06, 0.1, 0.8), 3.0 * s)
		return
	var pts := PackedVector2Array([tip + dir * 14.0 * s, tip - dir * 8.0 * s + side * 12.0 * s, tip - dir * 8.0 * s - side * 12.0 * s])
	draw_colored_polygon(pts, color)
