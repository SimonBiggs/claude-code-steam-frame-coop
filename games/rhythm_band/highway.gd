extends Control
## One TV view's overlay, drawn in code each frame (no nodes per note, so six views stay cheap):
## the band bar (crowd meter, combo, score, song progress), and for a guitarist the 3-lane note
## highway in perspective with X / A / B target rings. For the flat drummer: the bar and key hints.

const LANE_COLORS: Array[Color] = [Color(0.3, 0.6, 1.0), Color(0.35, 0.95, 0.4), Color(1.0, 0.35, 0.35)]
const LANE_BUTTONS: Array[String] = ["X", "A", "B"]
const DEPTH := 3.6

var main
var p
var font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 20.0 or h < 20.0 or main == null or p == null:
		return
	var ui := clampf(minf(w / 960.0, h / 760.0), 0.42, 1.3)
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
	var who := "P%d %s" % [p.index + 1, "DRUMS" if p.index == 0 else "GUITAR"]
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
		var title := "%d/%d %s" % [int(main.song_idx) + 1, int(main.SONGS_PER_TOUR), str(g.title)]
		_text(Vector2(right - sw, 46 * ui), title, int(16 * ui), Color(0.7, 0.9, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, sw)
		var prog := clampf(float(main.song_t) / maxf(1.0, float(g.length)), 0.0, 1.0)
		draw_rect(Rect2(0, bh - 3 * ui, w * prog, 3 * ui), Color(0.6, 0.9, 1.0, 0.8))


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
	var st: float = main.song_t
	# Road.
	var under := -0.12
	var poly := PackedVector2Array([_proj(hit_y, h0, cx, bw, under, -1.6), _proj(hit_y, h0, cx, bw, under, 1.6),
		_proj(hit_y, h0, cx, bw, 1.0, 1.6), _proj(hit_y, h0, cx, bw, 1.0, -1.6)])
	draw_colored_polygon(poly, Color(0.05, 0.04, 0.12, 0.62))
	for e in [-1.6, -0.5, 0.5, 1.6]:
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
	# Target rings with the button letters (and the keyboard keys under them).
	for lane in 3:
		var pos := _proj(hit_y, h0, cx, bw, 0.0, float(lane - 1))
		var col := LANE_COLORS[lane]
		var fl: float = p.lane_flash[lane]
		var rr := 30.0 * ui
		draw_circle(pos, rr, Color(col.r, col.g, col.b, 0.18 + 0.6 * fl))
		draw_arc(pos, rr, 0.0, TAU, 28, col.lightened(0.3 * fl), 4.0 * ui)
		_text(pos + Vector2(-rr, 9 * ui), LANE_BUTTONS[lane], int(26 * ui), Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER, rr * 2.0)
		var kh: String = p.key_hint(lane)
		if kh != "":
			_text(pos + Vector2(-rr * 2.0, rr + 22 * ui), kh, int(15 * ui), Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, rr * 4.0)
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
			var u := dt / look
			var z := 1.0 + u * (DEPTH - 1.0)
			var pos := _proj(hit_y, h0, cx, bw, u, float(lane - 1))
			var r := 25.0 * ui / maxf(z, 0.75)
			var col := LANE_COLORS[lane] if j == 0 else Color(0.4, 0.4, 0.45)
			draw_circle(pos + Vector2(0, 3 * ui / z), r, Color(0, 0, 0, 0.5))
			draw_circle(pos, r, col)
			draw_circle(pos + Vector2(-r * 0.25, -r * 0.3), r * 0.35, Color(1, 1, 1, 0.55 if j == 0 else 0.2))
	# Judgement pop + hints.
	var jt: float = p.judge_t
	if jt > 0.0:
		var jc: Color = p.judge_col
		jc.a = clampf(jt * 2.0, 0.0, 1.0)
		var fs := int((34.0 + 10.0 * jt) * ui)
		_text(Vector2(cx - 200 * ui, hit_y - 80 * ui - (0.8 - jt) * 30 * ui), str(p.judge_text), fs, jc, HORIZONTAL_ALIGNMENT_CENTER, 400 * ui)
	if int(p.streak) >= 5:
		_text(Vector2(cx - 200 * ui, top_y - 10 * ui), "%d IN A ROW!" % int(p.streak), int(24 * ui), Color(1.0, 0.85, 0.3), HORIZONTAL_ALIGNMENT_CENTER, 400 * ui)
	var hint := ""
	if int(p.miss_run) >= 5 and playing:
		hint = "Press the button when a ball touches its ring!"
	elif playing and g.g_t.size() > 0 and st < float(g.g_t[0]) + 1.0:
		hint = "Balls fly down the road: press X, A or B as they reach the rings"
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
