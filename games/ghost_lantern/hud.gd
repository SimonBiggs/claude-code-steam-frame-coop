extends Control
## One flat-screen player's HUD: crosshair, courage bar, capture bar and a hint line.
## Simple mode (visual teaching, no how-to words): no hint line; low in the view a pulsing glowing
## button in this player's own controls plus a picture (cue.gd, UiKit glyph / icon):
##  - lantern (split screen) in practice: MOUSE / STICK + a lantern beam + a ghost (shine on the sleepy
##    ghost); a glowing arrow at the view's edge when the sleepy ghost is off screen.
##  - vacuum: RT / SPACE / ENTER + a ghost when a lit ghost is in front (hold to vacuum it), and STICK /
##    MOUSE / an arrow key + an arrow (with a glowing arrow at the view's edge) when the nearest lit ghost
##    is off screen.
##  - a pulsing bolt while this player's controller is unplugged.
## Each goes once this player has done it twice (main.cue_did / cue_learned).

const CueScript := preload("res://games/ghost_lantern/cue.gd")
const UiKit := preload("res://core/ui_kit.gd")

var player
var main
var hurt_flash := 0.0
var name_label: Label
var hint_label: Label
var ui := 1.0  # shrinks with the view when many players share the TV
# Simple mode picture cue (cue.gd) and what it counts towards.
var cue: Control
var cue_key := ""
var cue_dir := ""
var edge_on := false   # draw the glowing edge arrow towards edge_pos
var edge_pos := Vector3.ZERO
var last_catches := 0


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
	if main.simple:
		name_label.text = "P%d" % (player.index + 1)
	if main.simple:
		hint_label.text = ""  # no how-to line: the picture cue shows it
		hint_label.visible = false
		_update_cue(delta)
	else:
		hint_label.text = _hint()
	queue_redraw()


func _hint() -> String:
	if main.pad_wait.has(player.index):
		return "CONTROLLER DISCONNECTED! Plug it back in within %d s to keep playing." % ceili(main.pad_wait[player.index])
	if main.simple:
		return _simple_hint()
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


## Simple mode: one short line while practising (lantern) / until a vacuum's first catch.
func _simple_hint() -> String:
	if player.role == "lantern":
		return "SHINE THE LIGHT!" if main.practice else ""
	if main.tv_caught.has(player.index) or main.night > 3:
		return ""
	if player.joy >= 0:
		return "HOLD RT!"
	return "HOLD SPACE!" if player.keys() == 0 else "HOLD ENTER!"


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
	if main.simple:
		if edge_on:
			_draw_edge_arrow()
		return  # no courage bar: nobody gets spooked
	# Courage bar.
	var bar_pos := Vector2(28, size.y - 50) * Vector2(ui, 1.0) + Vector2(0.0, 50.0 * (1.0 - ui))
	var bw := 300.0 * ui
	var bh := 20.0 * ui
	draw_rect(Rect2(bar_pos - Vector2(3, 3), Vector2(bw + 6, bh + 6)), Color(0, 0, 0, 0.6))
	var frac := clampf(player.courage / player.MAX_COURAGE, 0.0, 1.0)
	draw_rect(Rect2(bar_pos, Vector2(bw * frac, bh)), Color(0.75, 0.45, 1.0).lerp(Color(0.45, 1.0, 0.6), frac))


# --- Simple mode picture cues ---------------------------------------------------

## The ghost this player should look at: the lantern's sleepy practice ghost, or (vacuum) the nearest
## ghost that is showing (lit by the lantern, or glowing). null if none.
func _target():
	var best = null
	var best_d := 14.0
	for g in main.get_tree().get_nodes_in_group("ghosts"):
		if player.role == "lantern":
			if g.kind == "sleepy":
				return g
			continue
		if g.kind == "sleepy" or (g.reveal < 0.35 and g.kind != "glowy"):
			continue
		var d: float = g.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = g
	return best


## Is pos inside this view (with a margin)?
func _on_screen(pos: Vector3) -> bool:
	var cam: Camera3D = player.camera
	if cam == null or cam.is_position_behind(pos):
		return false
	var sp := cam.unproject_position(pos)
	var m := size * 0.12
	return sp.x > m.x and sp.y > m.y and sp.x < size.x - m.x and sp.y < size.y - m.y


## [key, dir]: "plug", "shine" (lantern), "turn" (vacuum: a lit ghost off screen), "vac", or "".
func _cue_now() -> Array:
	edge_on = false
	if not player.active or main.game_over or not main.ready_to_play or main.get_tree().paused \
			or (main.net.mode == "client" and not main.synced):
		return ["", ""]
	if main.pad_lost(player.index):
		return ["plug", ""]
	var g = _target()
	if g == null:
		return ["", ""]
	var pos: Vector3 = g.global_position
	var on := _on_screen(pos)
	if player.role == "lantern":
		if not main.practice or main.cue_learned(player, "shine") or g.reveal > 0.5:
			return ["", ""]
		edge_on = not on
		edge_pos = pos
		return ["shine", ""]
	if not on:
		if main.cue_learned(player, "turn"):
			return ["", ""]
		edge_on = true
		edge_pos = pos
		var loc: Vector3 = player.camera.global_basis.inverse() * (pos - player.camera.global_position)
		return ["turn", "right" if loc.x > 0.0 else "left"]
	if main.cue_learned(player, "vac") or main.night > 3:
		return ["", ""]
	return ["vac", ""]


## This player's own button for a cue.
func _cue_button(k: String, dir: String, sc: float) -> Control:
	var pad: bool = player.joy >= 0
	if k == "vac":
		if pad or not player.uses_keyboard():
			return UiKit.glyph("RT", sc)
		return UiKit.glyph("SPACE" if player.keys() == 0 else "ENTER", sc)
	# Aim / turn: the stick, the mouse, or the arrow keys (P2 turns with left / right).
	if pad:
		return UiKit.glyph("STICK", sc)
	if player.mouse_look:
		return UiKit.glyph("MOUSE", sc)
	if player.keys() == 1:
		return CueScript.arrow_key(dir if dir != "" else "left", sc)
	return UiKit.glyph("STICK", sc)


func _update_cue(delta: float) -> void:
	_count_cues()
	if cue == null or not is_instance_valid(cue):
		cue = CueScript.new()
		add_child(cue)
	var was := cue_key
	var kd := _cue_now()
	cue_key = kd[0]
	cue_dir = kd[1]
	if was == "turn" and cue_key != "turn" and cue_key != "plug":
		main.cue_did(player, "turn")  # turned until the ghost came into view
	var k: String = cue_key
	var dir: String = cue_dir
	var gc: Color = player.color.lerp(Color(0.75, 1.0, 0.85), 0.5)
	cue.set_cue(k, "%s|%s|%s|%d" % [dir, player.joy >= 0, player.mouse_look, player.keys()], func(sc: float) -> Array:
		match k:
			"plug":
				return [UiKit.icon("bolt", Color(1.0, 0.8, 0.3), 64.0 * sc)]
			"shine":
				return [_cue_button(k, dir, sc), CueScript.beam_icon(48.0 * sc), CueScript.ghost_icon(52.0 * sc)]
			"turn":
				return [_cue_button(k, dir, sc), UiKit.icon("arrow_" + dir, Color(1.0, 0.9, 0.45), 48.0 * sc)]
		return [_cue_button(k, dir, sc), CueScript.ghost_icon(56.0 * sc, gc)], delta)


## Catches come from the host (mirrored on the TV): count each new one.
func _count_cues() -> void:
	var n: int = int(main.tv_catches.get(player.index, 0))
	for i in maxi(0, n - last_catches):
		main.cue_did(player, "vac")
	last_catches = n


## A big glowing arrow at the edge of the view, pointing the way to edge_pos.
func _draw_edge_arrow() -> void:
	var cam: Camera3D = player.camera
	if cam == null:
		return
	var loc: Vector3 = cam.global_basis.inverse() * (edge_pos - cam.global_position)
	var d := Vector2(loc.x, -loc.y)
	if loc.z > 0.0:
		d = Vector2(1.0 if loc.x >= 0.0 else -1.0, 0.0)  # behind: point round the short way
	if d.length() < 0.001:
		d = Vector2.RIGHT
	d = d.normalized()
	var c := size / 2.0
	var k := absf(sin(Time.get_ticks_msec() * 0.005))
	var reach := minf(size.x, size.y) * 0.38
	var at := c + d * (reach + 14.0 * k * ui)
	var r := (46.0 + 10.0 * k) * maxf(ui, 0.6)
	var side := Vector2(-d.y, d.x)
	for i in 3:
		draw_circle(at, r * (1.0 + 0.35 * i), Color(1.0, 0.95, 0.6, 0.12 * (1.0 - 0.3 * i)))
	var tip := at + d * r
	var pts := PackedVector2Array([tip, at - d * r * 0.2 + side * r * 0.75, at - d * r * 0.2 + side * r * 0.25,
		at - d * r * 0.9 + side * r * 0.25, at - d * r * 0.9 - side * r * 0.25, at - d * r * 0.2 - side * r * 0.25,
		at - d * r * 0.2 - side * r * 0.75])
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_colored_polygon(pts, Color(1.0, 0.9, 0.45, 0.75 + 0.25 * k))
	draw_polyline(outline, Color(0.3, 0.2, 0.05, 0.8), maxf(2.0, 3.0 * ui), true)
