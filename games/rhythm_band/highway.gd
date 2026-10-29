extends Control
## One TV view's overlay, drawn in code each frame (no nodes per note, so six views stay cheap):
## the band bar (crowd meter, star meter, combo, score, song progress), and for a guitarist the 3-lane
## note highway in perspective with X / A / B target rings (gold STAR notes; the road turns gold during
## STAR POWER). The SETLIST menu card: tonight's songs, your level (EASY / NORMAL / ROCK) and READY.
## For the flat drummer: the bar and key hints.
## Simple mode (main.SIMPLE_MODE): no words or numbers - a thin song-progress line and your colour; the
## first song has just the two outer lanes (X and B), the middle lane joins in song 2 (its ring pulses
## in the intro); a hit bursts its ring; the ring of the next note pulses in song 1; keyboard players
## get little arrows under the rings; PRACTICE shows one slow note waiting on its ring.
## Visual teaching (simple mode, no how-to words): a pulsing glowing pad button and a glowing arrow
## point at the ring to hit, in this player's own controls (X / A / B, or an arrow key cap for a
## keyboard player, whose rings show arrows instead of pad letters): above the ring in PRACTICE, the
## intro and while that lane is empty, beside the road for an outer lane's next note. The flat drummer
## gets the drum's button (X A B Y / A S D F) over the glowing 3D arrow on the drum to hit. Each cue
## fades once that lane / drum has been hit twice (main.cue_did / cue_learned).

const LANE_COLORS: Array[Color] = [Color(0.3, 0.6, 1.0), Color(0.35, 0.95, 0.4), Color(1.0, 0.35, 0.35)]
const LANE_BUTTONS: Array[String] = ["X", "A", "B"]
const DEPTH := 3.6
const UiKit := preload("res://core/ui_kit.gd")

var main
var p
var font: Font
# Simple mode picture cue (a "Cue" box of UiKit glyphs / icons on top of the drawing).
var rings: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]  # target ring centres (last frame)
var ring_r := 30.0
var next_lane := -1  # the lane of the next note (within a second)
var lane_busy: Array[bool] = [false, false, false]  # a note is on its way down this lane
var cue_box: Control
var cue_sig := ""
var cue_a := 0.0
var cue_glow := Vector2.ZERO  # where the halo goes (the glyph's centre)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	if main != null and p != null and main.SIMPLE_MODE:
		_update_cue(delta)
	queue_redraw()


# --- Simple mode picture cues (no words) ------------------------------------------------------

func _keyboard_only() -> bool:
	return p.index > 0 and int(p.joy) < 0 and int(p.key_set) != int(p.NO_KEYS)


## What this view should show now: [key, place, lane or pad] (key "" for nothing). place: "above" the
## ring, "side" of the road (outer lanes, notes coming), "drum" (over the flat drummer's 3D arrow).
func _want_cue() -> Array:
	var none := ["", "", -1]
	if not p.active or main.get_tree().paused or (main.net.mode == "client" and not main.synced):
		return none
	var st: String = main.state
	if p.index == 0:
		if p.vr or p.fake_vr or p.ghost or int(p.cue_pad) < 0 or p.camera == null:
			return none
		return ["pad%d" % int(p.cue_pad), "drum", int(p.cue_pad)]
	var lanes: Array[int] = main.lanes_now()
	if st == "practice":
		if int(p.prac_step) < main.PRACTICE_LANES.size():
			var l: int = main.PRACTICE_LANES[int(p.prac_step)]
			if not main.cue_learned(p, "lane%d" % l):
				return ["lane%d" % l, "above", l]
		return none
	if st == "intro":
		for l in lanes:
			if not main.cue_learned(p, "lane%d" % l):
				return ["lane%d" % l, "above", l]
		return none
	if st != "play":
		return none
	if next_lane >= 0 and next_lane != 1 and not main.cue_learned(p, "lane%d" % next_lane):
		return ["lane%d" % next_lane, "side", next_lane]
	if lanes.has(1) and not main.cue_learned(p, "lane1") and not lane_busy[1]:
		return ["lane1", "above", 1]  # the new middle lane: shown between its notes (the ring pulses)
	return none


## A key cap (keyboard) with a letter or an arrow icon in it.
func _keycap(text: String, icon_kind: String, s: float) -> Control:
	var g := UiKit.glyph("KEY", s)
	var l := g.get_child(0) as Label
	l.text = text
	if icon_kind != "":
		l.text = ""
		var ic := UiKit.icon(icon_kind, Color.WHITE, 26.0 * s)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		g.add_child(ic)
	return g


## The button in this player's own controls.
func _cue_button(idx: int, s: float) -> Control:
	var arrows: Array[String] = ["arrow_left", "arrow_down", "arrow_right"]
	if p.index == 0:
		if int(p.joy) >= 0:
			return UiKit.glyph(["X", "A", "B", "Y"][idx], s)
		return _keycap(["A", "S", "D", "F"][idx], "", s)
	if _keyboard_only():
		return _keycap("", arrows[idx], s)
	return UiKit.glyph(LANE_BUTTONS[idx], s)


func _update_cue(delta: float) -> void:
	var want := _want_cue()
	var key: String = want[0]
	var place: String = want[1]
	var idx: int = want[2]
	p.set_meta("cue", key)
	var ui := clampf(minf(size.x / 960.0, size.y / 760.0), 0.42, 1.3)
	var s := 2.2 * ui  # big: a kid sees it from the sofa
	if cue_box == null:
		cue_box = Control.new()
		cue_box.name = "Cue"
		cue_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cue_box)
	var sig := "%s/%s/%d/%d/%.2f" % [key, place, int(int(p.joy) >= 0), int(_keyboard_only()), s]
	if key != "" and sig != cue_sig:
		if cue_sig.get_slice("/", 0) != key:
			cue_a = 0.0  # a new cue fades in
		cue_sig = sig
		for c in cue_box.get_children():
			cue_box.remove_child(c)
			c.queue_free()
		var box: BoxContainer = VBoxContainer.new() if place != "side" else HBoxContainer.new()
		box.name = "Row"
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", int(6 * s))
		cue_box.add_child(box)
		var col: Color = LANE_COLORS[idx].lightened(0.45) if p.index > 0 else Color(1.0, 0.95, 0.6)
		var btn := _cue_button(idx, s)
		btn.name = "Button"
		var arrow: Control = null
		if place == "above":
			arrow = UiKit.icon("arrow_down", col, 34.0 * s)
		elif place == "side":
			arrow = UiKit.icon("arrow_right" if idx == 0 else "arrow_left", col, 34.0 * s)
		if place == "side" and idx == 2:
			box.add_child(arrow)
			box.add_child(btn)
		else:
			box.add_child(btn)
			if arrow != null:
				box.add_child(arrow)
		for c in box.get_children():
			var ctl := c as Control
			ctl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # a round X, not a tall pill
	if key != "":
		cue_a = minf(1.0, cue_a + delta * 4.0)
	else:
		cue_a = maxf(0.0, cue_a - delta * 2.5)  # the old cue fades away
	cue_box.visible = cue_a > 0.01 and cue_box.get_child_count() > 0
	if not cue_box.visible:
		if cue_a <= 0.01:
			cue_sig = ""
		return
	var row := cue_box.get_child(0) as Control
	if row == null:
		return
	row.size = row.get_combined_minimum_size()
	var sz := row.size
	var now := Time.get_ticks_msec() * 0.001
	var k := absf(sin(now * 4.0))
	var bob := 10.0 * ui * k  # nudges towards the ring / drum
	var cur_place: String = cue_sig.get_slice("/", 1)
	var cur_idx: int = int(cue_sig.get_slice("/", 0).trim_prefix("lane").trim_prefix("pad"))
	var pos := Vector2.ZERO
	match cur_place:
		"above":
			var ring: Vector2 = rings[cur_idx]
			pos = ring - Vector2(sz.x * 0.5, ring_r * 1.3 + sz.y - bob)
		"side":
			var ring: Vector2 = rings[cur_idx]
			if cur_idx == 0:
				pos = Vector2(ring.x - ring_r * 1.3 - sz.x + bob, ring.y - sz.y * 0.5)
			else:
				pos = Vector2(ring.x + ring_r * 1.3 - bob, ring.y - sz.y * 0.5)
		"drum":
			var d = p
			if d.camera == null or cur_idx < 0 or cur_idx >= d.pads.size():
				return
			var at: Vector3 = d.rig.to_global(d.pads[cur_idx].position + Vector3(0.0, 0.46, 0.0))
			if d.camera.is_position_behind(at):
				return
			var sp: Vector2 = d.camera.unproject_position(at)
			pos = sp - Vector2(sz.x * 0.5, sz.y + bob * 0.5)
	cue_box.position = pos
	row.position = Vector2.ZERO
	cue_box.modulate = Color(1.0 + 0.3 * k, 1.0 + 0.3 * k, 1.0 + 0.3 * k, cue_a * (0.8 + 0.2 * k))
	var btn := row.get_node_or_null("Button") as Control
	if btn != null:
		btn.pivot_offset = btn.size * 0.5
		btn.scale = Vector2.ONE * (1.0 + 0.15 * k)
		cue_glow = pos + btn.position + btn.size * 0.5


## The soft glow behind the cue's button (drawn under it).
func _draw_cue_glow(ui: float) -> void:
	if cue_box == null or not cue_box.visible:
		return
	var k := absf(sin(Time.get_ticks_msec() * 0.004))
	var r := 34.0 * ui * (1.0 + 0.2 * k)
	for i in 3:
		draw_circle(cue_glow, r * (1.0 + 0.35 * i), Color(1.0, 0.95, 0.6, 0.16 * cue_a * (1.0 - 0.3 * i)))


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 20.0 or h < 20.0 or main == null or p == null:
		return
	var ui := clampf(minf(w / 960.0, h / 760.0), 0.42, 1.3)
	if main.SIMPLE_MODE:
		if p.index > 0:
			_draw_highway(w, h, ui)
		_draw_top_simple(w, ui)
		_draw_cue_glow(ui)
		return
	if main.state == "menu":
		_draw_top(w, ui)
		_draw_menu(w, h, ui)
		return
	if p.index > 0:
		_draw_highway(w, h, ui)
	else:
		_draw_drum_help(w, h, ui)
	_draw_top(w, ui)
	var st: String = main.state
	if st == "results" or st == "tour":
		_draw_stars(Vector2(w * 0.5, h * 0.2), ui, int(main.last_stars) if st == "results" else -1)


func _text(pos: Vector2, s: String, fs: int, col: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	draw_string_outline(font, pos, s, align, width, fs, maxi(4, fs / 5), Color(0, 0, 0, 0.85 * col.a))
	draw_string(font, pos, s, align, width, fs, col)


func _draw_top(w: float, ui: float) -> void:
	var bh := 54.0 * ui
	draw_rect(Rect2(0, 0, w, bh), Color(0, 0, 0, 0.45))
	var fs := int(22 * ui)
	var x := 12.0 * ui
	var tag_col: Color = main.PLAYER_COLORS[p.index]
	draw_rect(Rect2(x, 10 * ui, 14 * ui, 14 * ui), tag_col)
	var lvl: int = int(main.drum_level) if p.index == 0 else int(p.level)
	var who := "P%d %s  ·  %s" % [p.index + 1, "DRUMS" if p.index == 0 else "GUITAR", main.LEVEL_NAMES[lvl]]
	_text(Vector2(x + 20 * ui, 24 * ui), who, fs, Color.WHITE)
	var acc := ""
	var tot: int = int(p.hits) + int(p.misses)
	if tot > 0:
		acc = "  %d%%" % int(100.0 * float(p.hits) / float(tot))
	_text(Vector2(x + 20 * ui, 46 * ui), "STREAK %d%s" % [int(p.streak), acc], int(18 * ui), Color(1, 1, 1, 0.9))
	# Crowd meter in the middle.
	var mw := minf(w * 0.34, 340.0 * ui)
	var mx := w * 0.5 - mw * 0.5
	var my := 12.0 * ui
	var crowd: float = main.crowd
	draw_rect(Rect2(mx, my, mw, 16 * ui), Color(0.1, 0.1, 0.12))
	var c := Color(1.0, 0.3, 0.3).lerp(Color(1.0, 0.9, 0.2), clampf(crowd * 2.0, 0.0, 1.0))
	if crowd > 0.5:
		c = Color(1.0, 0.9, 0.2).lerp(Color(0.3, 1.0, 0.4), (crowd - 0.5) * 2.0)
	draw_rect(Rect2(mx, my, mw * crowd, 16 * ui), c)
	draw_rect(Rect2(mx, my, mw, 16 * ui), Color(1, 1, 1, 0.6), false, 2.0)
	_text(Vector2(mx, my + 36 * ui), "CROWD", int(16 * ui), Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	# Star meter (gold) under the crowd meter.
	var sm: float = main.star_meter_value()
	var sy := my + 19 * ui
	draw_rect(Rect2(mx, sy, mw, 6 * ui), Color(0.1, 0.1, 0.12))
	var gold := Color(1.0, 0.82, 0.25)
	if main.star_ready() or main.star_active():
		gold = gold.lightened(0.4 * absf(sin(Time.get_ticks_msec() * 0.008)))
	draw_rect(Rect2(mx, sy, mw * sm, 6 * ui), gold)
	var combo: int = main.combo
	var mult: int = main.multiplier()
	var ctext := "COMBO %d" % combo + ("  x%d" % mult if mult > 1 else "")
	_text(Vector2(mx, my + 36 * ui), ctext, int(16 * ui), Color(1.0, 0.9, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, mw)
	# Score + song on the right, with a progress line.
	var g = main.song
	var right := w - 12.0 * ui
	var sw := 300.0 * ui
	_text(Vector2(right - sw, 24 * ui), "SCORE %d" % int(main.score), fs, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, sw)
	if g != null:
		var title := "%d/%d %s" % [int(main.tour_pos) + 1, int(main.SONGS_PER_TOUR), str(g.title)]
		_text(Vector2(right - sw, 46 * ui), title, int(16 * ui), Color(0.7, 0.9, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, sw)
		var prog := clampf(float(main.song_t) / maxf(1.0, float(g.length)), 0.0, 1.0)
		draw_rect(Rect2(0, bh - 3 * ui, w * prog, 3 * ui), Color(0.6, 0.9, 1.0, 0.8))


## Simple mode: your colour in the corner and how far through the song we are. No numbers.
func _draw_top_simple(w: float, ui: float) -> void:
	draw_rect(Rect2(10 * ui, 10 * ui, 16 * ui, 16 * ui), main.PLAYER_COLORS[p.index])
	var g = main.song
	if g != null and main.state == "play":
		var prog := clampf(float(main.song_t) / maxf(1.0, float(g.length)), 0.0, 1.0)
		draw_rect(Rect2(0, 0, w, 5 * ui), Color(0, 0, 0, 0.4))
		draw_rect(Rect2(0, 0, w * prog, 5 * ui), Color(0.6, 0.9, 1.0, 0.8))


## A small arrow under a ring for keyboard players (left / down / right), drawn, not written.
func _draw_arrow(c: Vector2, lane: int, r: float, col: Color) -> void:
	var dirs: Array[Vector2] = [Vector2.LEFT, Vector2.DOWN, Vector2.RIGHT]
	var d := dirs[lane]
	var side := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([c + d * r, c - d * r * 0.6 + side * r * 0.8, c - d * r * 0.6 - side * r * 0.8]), col)


func _proj(hit_y: float, h0: float, cx: float, bw: float, u: float, lane_x: float) -> Vector2:
	var z := 1.0 + u * (DEPTH - 1.0)
	return Vector2(cx + lane_x * bw / 3.0 / z, h0 + (hit_y - h0) / z)


func _draw_highway(w: float, h: float, ui: float) -> void:
	var hit_y := h - 74.0 * ui
	var top_y := h * 0.34
	var h0 := (DEPTH * top_y - hit_y) / (DEPTH - 1.0)
	var cx := w * 0.5
	var bw := minf(w * 0.6, 540.0 * ui)
	var g = main.song
	var playing: bool = main.state == "play" and g != null
	var look := 1.7
	if g != null:
		look = clampf(3.2 * float(g.spb), 1.35, 2.0)
	if int(p.level) == 0:
		look *= 1.3  # EASY: the balls come slower
	var st: float = main.song_t
	var star_on: bool = main.star_active()
	# Road.
	var under := -0.12
	var poly := PackedVector2Array([_proj(hit_y, h0, cx, bw, under, -1.6), _proj(hit_y, h0, cx, bw, under, 1.6),
		_proj(hit_y, h0, cx, bw, 1.0, 1.6), _proj(hit_y, h0, cx, bw, 1.0, -1.6)])
	draw_colored_polygon(poly, Color(0.35, 0.25, 0.04, 0.7) if star_on else Color(0.05, 0.04, 0.12, 0.62))
	var simple: bool = main.SIMPLE_MODE
	var lanes: Array[int] = main.lanes_now()
	var edges: Array = [-1.6, -0.5, 0.5, 1.6] if lanes.size() == 3 else [-1.6, 0.0, 1.6]
	for e in edges:
		var ef: float = e
		var a := _proj(hit_y, h0, cx, bw, under, ef)
		var b := _proj(hit_y, h0, cx, bw, 1.0, ef)
		draw_line(a, b, Color(1, 1, 1, 0.35 if absf(ef) < 1.0 else 0.6), 2.0 * ui)
	# Beat lines scroll towards you (brighter on the bar line).
	if g != null and playing:
		var spb: float = g.spb
		var b0 := int(ceilf(st / spb))
		var bt := b0 * spb
		while bt < st + look:
			var u := (bt - st) / look
			var l := _proj(hit_y, h0, cx, bw, u, -1.6)
			var r := _proj(hit_y, h0, cx, bw, u, 1.6)
			var bar_line := b0 % 4 == 0
			draw_line(l, r, Color(1, 1, 1, 0.35 if bar_line else 0.14), (3.0 if bar_line else 1.5) * ui)
			b0 += 1
			bt = b0 * spb
	# Simple mode: which ring to pulse (the practice note's lane, the next note's lane in song 1, the
	# new middle lane in song 2's intro).
	var pulse_lane := -1
	var now := Time.get_ticks_msec() * 0.001
	next_lane = -1
	lane_busy = [false, false, false]
	if simple and playing and p.judged.size() == g.g_t.size():
		var k0 := maxi(0, int(p.next_idx) - 1)
		while k0 < g.g_t.size():
			if p.judged[k0] == 0 and float(g.g_t[k0]) > st - 0.1:
				if float(g.g_t[k0]) - st < 1.0:
					next_lane = g.g_lane[k0]
				break
			k0 += 1
	if simple:
		if main.state == "practice" and int(p.prac_step) < main.PRACTICE_LANES.size():
			pulse_lane = main.PRACTICE_LANES[int(p.prac_step)]
		elif main.state == "intro" and int(main.tour_pos) == 1:
			pulse_lane = 1
		elif playing and int(main.tour_pos) == 0 and p.judged.size() == g.g_t.size():
			var k := maxi(0, int(p.next_idx) - 1)
			while k < g.g_t.size():
				if p.judged[k] == 0 and float(g.g_t[k]) > st - 0.1:
					if float(g.g_t[k]) - st < 1.0:
						pulse_lane = g.g_lane[k]
					break
				k += 1
	# Target rings with the button letters (and the keyboard keys under them).
	for lane in lanes:
		var pos := _proj(hit_y, h0, cx, bw, 0.0, float(lane - 1))
		var col := LANE_COLORS[lane]
		var fl: float = p.lane_flash[lane]
		var rr := 30.0 * ui
		rings[lane] = pos
		ring_r = rr
		if lane == pulse_lane:
			var pk := absf(sin(now * 5.0))
			draw_arc(pos, rr * (1.25 + 0.25 * pk), 0.0, TAU, 28, Color(1, 1, 1, 0.5 + 0.5 * pk), 4.0 * ui)
		draw_circle(pos, rr, Color(col.r, col.g, col.b, 0.18 + 0.6 * fl))
		draw_arc(pos, rr, 0.0, TAU, 28, col.lightened(0.3 * fl), 4.0 * ui)
		var ht: float = p.hit_t[lane]
		if simple and ht > 0.0:
			draw_arc(pos, rr * (1.0 + (1.0 - ht) * 1.2), 0.0, TAU, 28, Color(1.0, 0.9, 0.4, ht), 6.0 * ui * ht)
		if simple and _keyboard_only():
			_draw_arrow(pos, lane, 14 * ui, Color(1, 1, 1, 0.95))  # their own key, not a pad letter
			continue
		_text(pos + Vector2(-rr, 9 * ui), LANE_BUTTONS[lane], int(26 * ui), Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER, rr * 2.0)
		if simple:
			if int(p.key_set) != int(p.NO_KEYS):
				_draw_arrow(pos + Vector2(0, rr + 20 * ui), lane, 10 * ui, Color(1, 1, 1, 0.7))
			continue
		var kh: String = p.key_hint(lane)
		if kh != "":
			_text(pos + Vector2(-rr * 2.0, rr + 22 * ui), kh, int(15 * ui), Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, rr * 4.0)
	# PRACTICE: one note slides down and waits on its ring.
	if simple and main.state == "practice" and pulse_lane >= 0:
		var u := clampf(1.0 - float(p.prac_t) / 1.6, 0.0, 1.0)
		var z0 := 1.0 + u * (DEPTH - 1.0)
		var bob := 0.0 if u > 0.0 else -4.0 * ui * absf(sin(now * 5.0))
		var ppos := _proj(hit_y, h0, cx, bw, u, float(pulse_lane - 1)) + Vector2(0, bob)
		var pr := 25.0 * ui / maxf(z0, 0.75)
		draw_circle(ppos, pr, LANE_COLORS[pulse_lane])
		draw_circle(ppos + Vector2(-pr * 0.25, -pr * 0.3), pr * 0.35, Color(1, 1, 1, 0.55))
	# Notes (only the few on screen: from the player's cursor until the horizon).
	if playing and p.judged.size() == g.g_t.size():
		var n: int = g.g_t.size()
		var i := maxi(0, int(p.next_idx) - 3)
		while i < n:
			var tn: float = g.g_t[i]
			var dt := tn - st
			if dt > look:
				break
			var j: int = p.judged[i]
			var lane: int = g.g_lane[i]
			i += 1
			if j == 1 or j == 2 or j == 4 or dt < -0.25:
				continue
			if j == 0:
				lane_busy[lane] = true
			var u := dt / look
			var z := 1.0 + u * (DEPTH - 1.0)
			var pos := _proj(hit_y, h0, cx, bw, u, float(lane - 1))
			var r := 25.0 * ui / maxf(z, 0.75)
			var gold_note: bool = g.g_star[i - 1] == 1
			var col := LANE_COLORS[lane] if j == 0 else Color(0.4, 0.4, 0.45)
			if j == 0 and (gold_note or star_on):
				col = Color(1.0, 0.82, 0.25)
			draw_circle(pos + Vector2(0, 3 * ui / z), r, Color(0, 0, 0, 0.5))
			if gold_note and j == 0:
				_draw_star(pos, r * 1.45, Color(1.0, 0.95, 0.6))
			draw_circle(pos, r, col)
			draw_circle(pos + Vector2(-r * 0.25, -r * 0.3), r * 0.35, Color(1, 1, 1, 0.55 if j == 0 else 0.2))
	if simple:
		return
	# Judgement pop + hints.
	var jt: float = p.judge_t
	if jt > 0.0:
		var jc: Color = p.judge_col
		jc.a = clampf(jt * 2.0, 0.0, 1.0)
		var fs := int((34.0 + 10.0 * jt) * ui)
		_text(Vector2(cx - 200 * ui, hit_y - 80 * ui - (0.8 - jt) * 30 * ui), str(p.judge_text), fs, jc, HORIZONTAL_ALIGNMENT_CENTER, 400 * ui)
	if int(p.streak) >= 5:
		_text(Vector2(cx - 200 * ui, top_y - 10 * ui), "%d IN A ROW!" % int(p.streak), int(24 * ui), Color(1.0, 0.85, 0.3), HORIZONTAL_ALIGNMENT_CENTER, 400 * ui)
	if playing and main.star_ready():
		var k := 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() * 0.008))
		_text(Vector2(cx - 300 * ui, top_y - 78 * ui), "STAR POWER READY!  Press Y!", int(30 * ui), Color(1.0, 0.85, 0.3, k), HORIZONTAL_ALIGNMENT_CENTER, 600 * ui)
	elif star_on:
		_text(Vector2(cx - 300 * ui, top_y - 78 * ui), "STAR POWER!  x2", int(30 * ui), Color(1.0, 0.85, 0.3), HORIZONTAL_ALIGNMENT_CENTER, 600 * ui)
	var hint := ""
	if int(p.miss_run) >= 5 and playing:
		hint = "Press the button when a ball touches its ring!"
	elif playing and g.g_t.size() > 0 and st < float(g.g_t[0]) + 1.0:
		hint = "Balls fly down the road: press X, A or B as they reach the rings"
	elif playing and int(p.miss_run) >= 8 and int(p.level) > 0:
		hint = "Too fast? Pick EASY in the setlist next time!"
	if hint != "":
		_text(Vector2(cx - 300 * ui, top_y - 44 * ui), hint, int(20 * ui), Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 600 * ui)


func _draw_drum_help(w: float, h: float, ui: float) -> void:
	var lines := "DRUMS: A S D F keys  ·  mouse left / right  ·  controller X A B Y\nHit each drum as its ball lands in the ring"
	if main.players.size() > 0 and main.players[0].fake_vr:
		lines = "DRUMS: (bot hands)"
	var y := h - 52.0 * ui
	for ln in lines.split("\n"):
		_text(Vector2(0, y), ln, int(20 * ui), Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER, w)
		y += 26.0 * ui


func _draw_stars(center: Vector2, ui: float, n: int) -> void:
	var count := 5
	var shown := n
	if n < 0:
		return
	var r := 34.0 * ui
	for k in count:
		var c := center + Vector2((k - 2) * r * 2.4, 0.0)
		var pts := PackedVector2Array()
		for q in 10:
			var a := -PI * 0.5 + q * PI / 5.0
			var rr := r if q % 2 == 0 else r * 0.42
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		draw_colored_polygon(pts, Color(1.0, 0.85, 0.2) if k < shown else Color(0.3, 0.3, 0.35, 0.8))
		pts.append(pts[0])
		draw_polyline(pts, Color(0, 0, 0, 0.8), 2.0 * ui)


func _draw_star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for q in 10:
		var a := -PI * 0.5 + q * PI / 5.0
		var rr := r if q % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, col)


## The SETLIST menu: tonight's three songs, your level (left / right) and READY (A).
func _draw_menu(w: float, h: float, ui: float) -> void:
	var cw := minf(w * 0.86, 760.0 * ui)
	var ch := minf(h * 0.72, 520.0 * ui)
	var x0 := w * 0.5 - cw * 0.5
	var y0 := maxf(64.0 * ui, h * 0.5 - ch * 0.5)
	draw_rect(Rect2(x0, y0, cw, ch), Color(0.06, 0.04, 0.14, 0.88))
	draw_rect(Rect2(x0, y0, cw, ch), Color(1.0, 0.8, 0.3, 0.8), false, 3.0 * ui)
	var y := y0 + 46 * ui
	_text(Vector2(x0, y), "TONIGHT'S SETLIST", int(34 * ui), Color(1.0, 0.85, 0.3), HORIZONTAL_ALIGNMENT_CENTER, cw)
	y += 40 * ui
	var sl: Array = main.setlist
	for k in sl.size():
		var si: int = sl[k]
		var line := "%d.  %s   (%d BPM)" % [k + 1, main.SongGen.song_name(si), int(main.SongGen.song_bpm(si))]
		_text(Vector2(x0, y), line, int(24 * ui), Color(0.75, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER, cw)
		y += 30 * ui
	y += 18 * ui
	if p.index == 0:
		_text(Vector2(x0, y), "DRUMS: %s" % main.LEVEL_NAMES[int(main.drum_level)], int(30 * ui), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, cw)
		y += 36 * ui
		_text(Vector2(x0, y), "A / S / D: EASY / NORMAL / ROCK  ·  F: START THE SHOW", int(20 * ui), Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER, cw)
	else:
		var lvl: int = int(p.level)
		var names: Array[String] = ["EASY", "NORMAL", "ROCK"]
		var cols: Array[Color] = [Color(0.4, 1.0, 0.5), Color(0.4, 0.75, 1.0), Color(1.0, 0.45, 0.4)]
		var bw := cw * 0.26
		var gap := cw * 0.04
		var bx := x0 + (cw - bw * 3.0 - gap * 2.0) * 0.5
		for k in 3:
			var r := Rect2(bx + k * (bw + gap), y, bw, 50 * ui)
			var on := k == lvl
			draw_rect(r, Color(cols[k].r, cols[k].g, cols[k].b, 0.85 if on else 0.18))
			if on:
				draw_rect(r, Color.WHITE, false, 4.0 * ui)
			_text(Vector2(r.position.x, r.position.y + 35 * ui), names[k], int(26 * ui), Color.WHITE if on else Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER, bw)
		y += 82 * ui
		var desc: Array[String] = ["Fewer notes, slower balls, extra time to hit them", "The full song", "Extra notes and a tighter beat - for grown-ups!"]
		_text(Vector2(x0, y), desc[lvl], int(20 * ui), Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER, cw)
		y += 40 * ui
		if p.menu_ready:
			_text(Vector2(x0, y), "READY!  Waiting for the band…", int(28 * ui), Color(0.5, 1.0, 0.6), HORIZONTAL_ALIGNMENT_CENTER, cw)
		else:
			var k2 := 0.65 + 0.35 * absf(sin(Time.get_ticks_msec() * 0.005))
			_text(Vector2(x0, y), "LEFT / RIGHT: pick your level  ·  A: READY!", int(26 * ui), Color(1.0, 0.9, 0.4, k2), HORIZONTAL_ALIGNMENT_CENTER, cw)
	y = y0 + ch - 20 * ui
	var left := maxf(0.0, float(main.MENU_AUTO) - float(main.state_t))
	var who := "The drummer starts the show with the CRASH"
	if main.players.size() > 0 and not main.players[0].vr and main.net.mode == "local":
		who = "Starts when everyone is READY"
	_text(Vector2(x0, y), "%s  ·  %d" % [who, int(ceilf(left))], int(18 * ui), Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, cw)
