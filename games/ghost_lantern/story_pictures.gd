extends RefCounted
## Ghost Lantern's story card pictures (core/story_pictures.gd finds this file by itself): grannyboo (Granny Boo:
## an old ghost with spectacles, a bun and a pink shawl, knitting), the ghost kinds snoozy (in a nightcap, with
## bubbles), zippy (a pink ghost with a bow, zooming), peekaboo (peeking out from behind a curtain in a witch hat),
## goldie (a golden ghost with sparkles), kingghost (in a crown) and jar (a little ghost in a jar, ghost = color).

## Second pass: boing (a ghost on a spring over a glowing ring), puff (a dandelion-clock ghost), the wings attic (a
## round moon window under roof beams), cellar (jam jars on a shelf by a barrel), greenhouse (a glass roof over a
## flower pot), and the lantern gifts biglight (a wide beam), longlight (a long beam), dizzystars (a dizzy ghost with
## stars) and supersuck (a vacuum nozzle slurping).
const NAMES: Array[String] = ["grannyboo", "snoozy", "zippy", "peekaboo", "goldie", "kingghost", "jar",
	"boing", "puff", "attic", "cellar", "greenhouse", "biglight", "longlight", "dizzystars", "supersuck"]


## A little lantern at (x, y) with a beam of half-angle `spread` and length `length` shining right.
static func _lantern(pic, x: float, y: float, spread: float, length: float, t: float) -> void:
	var a := 0.85 + 0.15 * sin(t * 3.0)
	pic._poly([[x + 0.06, y], [x + 0.06 + length, y - spread], [x + 0.06 + length, y + spread]], Color(1.0, 0.92, 0.5, 0.45 * a))
	pic._poly([[x - 0.07, y - 0.09], [x + 0.07, y - 0.09], [x + 0.07, y + 0.09], [x - 0.07, y + 0.09]], Color(0.95, 0.72, 0.3))
	pic._circle(x, y, 0.055, Color(1.0, 0.95, 0.6))
	pic._poly([[x - 0.04, y - 0.09], [x + 0.04, y - 0.09], [x, y - 0.15]], Color(0.6, 0.4, 0.2))


## A round friendly ghost: head at (x, y), radius r, wavy skirt below.
static func _ghost(pic, t: float, x: float, y: float, r: float, c: Color, sleepy: bool = false) -> void:
	var size: Vector2 = pic.size
	var pts := []
	for i in 13:
		var a := PI + PI * float(i) / 12.0
		pts.append([x + cos(a) * r, y + sin(a) * r])
	var wav := sin(t * 5.0) * 0.02
	pts.append([x + r, y + r * 1.1])
	for k in 4:
		var fx := x + r - (k + 0.5) * r * 0.5
		pts.append([fx, y + r * (1.25 if k % 2 == 0 else 1.0) + wav * (1.0 if k % 2 == 0 else -1.0)])
	pts.append([x - r, y + r * 1.1])
	pic._poly(pts, c)
	if sleepy:
		for sx in [-1.0, 1.0]:
			pic.draw_arc(pic._p(x + sx * r * 0.35, y + r * 0.05), r * 0.16 * size.x, 0.2, PI - 0.2, 8, Color(0.15, 0.12, 0.3), 0.025 * size.x)
	else:
		pic._circle(x - r * 0.35, y + r * 0.02, r * 0.17, Color(0.12, 0.1, 0.22))
		pic._circle(x + r * 0.35, y + r * 0.02, r * 0.17, Color(0.12, 0.1, 0.22))
		pic._circle(x - r * 0.3, y - r * 0.04, r * 0.06, Color.WHITE)
		pic._circle(x + r * 0.4, y - r * 0.04, r * 0.06, Color.WHITE)
	pic.draw_arc(pic._p(x, y + r * 0.35), r * 0.2 * size.x, 0.3, PI - 0.3, 10, Color(0.45, 0.15, 0.3), 0.02 * size.x)
	pic._circle(x - r * 0.62, y + r * 0.35, r * 0.13, Color(1.0, 0.55, 0.65, 0.7))
	pic._circle(x + r * 0.62, y + r * 0.35, r * 0.13, Color(1.0, 0.55, 0.65, 0.7))


## Ghost Lantern's pictures: Granny Boo, the ghost kinds and a ghost in a jar.
static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	var size: Vector2 = pic.size
	match kind:
		"grannyboo":
			_ghost(pic, t, 0.5, 0.45 + bob, 0.3, Color(0.94, 0.93, 1.0))
			pic._circle(0.5, 0.16 + bob, 0.09, Color(0.72, 0.72, 0.78))  # bun
			pic._poly([[0.18, 0.62 + bob], [0.82, 0.62 + bob], [0.7, 0.74 + bob], [0.3, 0.74 + bob]], Color(1.0, 0.55, 0.7))  # shawl
			for sx in [0.395, 0.605]:
				pic.draw_arc(pic._p(sx, 0.455 + bob), 0.075 * size.x, 0.0, TAU, 16, Color(0.85, 0.62, 0.2), 0.022 * size.x)
			pic.draw_line(pic._p(0.47, 0.455 + bob), pic._p(0.53, 0.455 + bob), Color(0.85, 0.62, 0.2), 0.02 * size.x)
			# knitting: a ball of wool and needles
			pic._circle(0.84, 0.78 + bob, 0.08, Color(0.5, 0.75, 1.0))
			pic.draw_line(pic._p(0.74, 0.66 + bob), pic._p(0.95, 0.86 + bob), Color(0.8, 0.7, 0.5), 0.015 * size.x)
		"snoozy":
			_ghost(pic, t, 0.45, 0.5 + bob, 0.28, color, true)
			pic._poly([[0.22, 0.32 + bob], [0.66, 0.26 + bob], [0.85, 0.12 + bob]], Color(0.35, 0.45, 1.0))
			pic._circle(0.86, 0.12 + bob, 0.05, Color.WHITE)
			for i in 3:
				var ph := fmod(t * 0.5 + float(i) / 3.0, 1.0)
				pic.draw_arc(pic._p(0.78 + sin(ph * 6.0) * 0.03, 0.55 - ph * 0.4), (0.02 + ph * 0.05) * size.x, 0.0, TAU, 12, Color(0.75, 0.9, 1.0, 1.0 - ph), 0.015 * size.x)
		"zippy":
			var dx := sin(t * 4.0) * 0.06
			for k in 3:
				pic.draw_line(pic._p(0.08 + k * 0.04, 0.4 + k * 0.1), pic._p(0.28 + k * 0.04, 0.4 + k * 0.1), Color(1.0, 0.8, 0.95, 0.8), 0.025 * size.x)
			_ghost(pic, t, 0.56 + dx, 0.48 + bob, 0.25, color)
			pic._poly([[0.56 + dx, 0.27 + bob], [0.42 + dx, 0.18 + bob], [0.44 + dx, 0.32 + bob]], Color(1.0, 0.35, 0.6))
			pic._poly([[0.56 + dx, 0.27 + bob], [0.7 + dx, 0.18 + bob], [0.68 + dx, 0.32 + bob]], Color(1.0, 0.35, 0.6))
		"peekaboo":
			var peek := 0.5 + 0.5 * sin(t * 1.8)
			_ghost(pic, t, 0.38 + peek * 0.12, 0.52, 0.24, color)
			pic._poly([[0.22 + peek * 0.12, 0.33], [0.54 + peek * 0.12, 0.33], [0.4 + peek * 0.12, 0.05]], Color(0.32, 0.12, 0.48))
			pic._poly([[0.14 + peek * 0.12, 0.35], [0.62 + peek * 0.12, 0.35], [0.62 + peek * 0.12, 0.3], [0.14 + peek * 0.12, 0.3]], Color(0.32, 0.12, 0.48))
			pic._poly([[0.5, 0.05], [0.95, 0.05], [0.95, 0.95], [0.5, 0.95]], Color(0.6, 0.15, 0.3))  # the curtain
			for k in 3:
				pic.draw_line(pic._p(0.6 + k * 0.12, 0.08), pic._p(0.6 + k * 0.12, 0.92), Color(0.45, 0.1, 0.22), 0.02 * size.x)
		"goldie":
			_ghost(pic, t, 0.5, 0.48 + bob, 0.28, Color(1.0, 0.85, 0.3))
			for k in 4:
				var a := t * 2.0 + k * TAU / 4.0
				pic._circle(0.5 + cos(a) * 0.4, 0.5 + sin(a) * 0.36, 0.035, Color(1.0, 1.0, 0.7))
		"kingghost":
			_ghost(pic, t, 0.5, 0.52 + bob, 0.3, Color(0.75, 0.9, 1.0))
			pic._poly([[0.3, 0.3 + bob], [0.7, 0.3 + bob], [0.74, 0.12 + bob], [0.62, 0.22 + bob], [0.5, 0.08 + bob], [0.38, 0.22 + bob], [0.26, 0.12 + bob]], Color(1.0, 0.8, 0.25))
			pic._circle(0.5, 0.24 + bob, 0.03, Color(1.0, 0.25, 0.45))
		"boing":
			var hop := absf(sin(t * 2.5)) * 0.18
			for k in 3:  # the warning ring where it lands
				pic.draw_arc(pic._p(0.5, 0.88), (0.12 + 0.08 * k) * size.x, 0.0, TAU, 24, Color(0.5, 0.92, 1.0, 0.8 - 0.2 * k), 0.018 * size.x)
			for k in 4:
				pic.draw_arc(pic._p(0.5, 0.72 - hop - k * 0.04), 0.08 * size.x, 0.0, TAU, 12, Color(0.8, 0.95, 1.0), 0.015 * size.x)
			_ghost(pic, t, 0.5, 0.38 - hop, 0.22, Color(0.5, 0.92, 1.0))
			pic._circle(0.5, 0.17 - hop, 0.08, Color(1.0, 0.45, 0.4))
			pic.draw_line(pic._p(0.36, 0.1 - hop), pic._p(0.64, 0.1 - hop), Color(1.0, 0.9, 0.3), 0.03 * size.x)
		"puff":
			for k in 10:
				var a := TAU * float(k) / 10.0 + t * 0.4
				pic.draw_line(pic._p(0.5, 0.45 + bob), pic._p(0.5 + cos(a) * 0.36, 0.45 + bob + sin(a) * 0.36), Color(1.0, 1.0, 0.9, 0.5), 0.01 * size.x)
				pic._circle(0.5 + cos(a) * 0.36, 0.45 + bob + sin(a) * 0.36, 0.04, Color(1.0, 1.0, 0.92))
			_ghost(pic, t, 0.5, 0.45 + bob, 0.22, Color(1.0, 1.0, 0.82))
			for k in 2:  # pufflings drifting off
				var ph := fmod(t * 0.3 + k * 0.5, 1.0)
				pic._circle(0.2 + 0.6 * k + sin(ph * 6.0) * 0.03, 0.9 - ph * 0.2, 0.05, Color(1.0, 0.97, 0.75, 1.0 - ph))
		"attic":
			pic._poly([[0.05, 0.45], [0.5, 0.08], [0.95, 0.45]], Color(0.36, 0.24, 0.16))
			pic._poly([[0.15, 0.45], [0.5, 0.18], [0.85, 0.45], [0.85, 0.95], [0.15, 0.95]], Color(0.5, 0.36, 0.24))
			pic._circle(0.5, 0.42, 0.13, Color(0.75, 0.85, 1.0))
			pic.draw_arc(pic._p(0.5, 0.42), 0.13 * size.x, 0.0, TAU, 20, Color(0.3, 0.2, 0.12), 0.025 * size.x)
			pic._circle(0.27, 0.82, 0.08, Color(0.7, 0.45, 0.25))  # a teddy
			pic._circle(0.22, 0.73, 0.035, Color(0.6, 0.38, 0.2))
			pic._poly([[0.55, 0.75], [0.85, 0.75], [0.85, 0.95], [0.55, 0.95]], Color(0.35, 0.55, 0.9))  # a toy box
		"cellar":
			pic._poly([[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]], Color(0.28, 0.26, 0.3))
			pic._poly([[0.08, 0.36], [0.92, 0.36], [0.92, 0.4], [0.08, 0.4]], Color(0.45, 0.28, 0.16))
			for k in 4:
				var jc: Color = [Color(1.0, 0.3, 0.35), Color(1.0, 0.65, 0.2), Color(0.6, 0.3, 0.8), Color(1.0, 0.85, 0.3)][k]
				pic._poly([[0.14 + k * 0.2, 0.18], [0.26 + k * 0.2, 0.18], [0.26 + k * 0.2, 0.36], [0.14 + k * 0.2, 0.36]], jc)
			pic._circle(0.5, 0.74, 0.2, Color(0.5, 0.32, 0.18))  # a barrel
			pic.draw_line(pic._p(0.3, 0.66), pic._p(0.7, 0.66), Color(0.3, 0.3, 0.32), 0.025 * size.x)
			pic.draw_line(pic._p(0.3, 0.82), pic._p(0.7, 0.82), Color(0.3, 0.3, 0.32), 0.025 * size.x)
		"greenhouse":
			pic._poly([[0.05, 0.4], [0.5, 0.08], [0.95, 0.4], [0.95, 0.95], [0.05, 0.95]], Color(0.7, 1.0, 0.8, 0.35))
			for k in 4:
				pic.draw_line(pic._p(0.05 + k * 0.3, 0.4), pic._p(0.05 + k * 0.3, 0.95), Color(0.95, 0.95, 0.95), 0.015 * size.x)
			pic._poly([[0.36, 0.7], [0.64, 0.7], [0.6, 0.92], [0.4, 0.92]], Color(0.8, 0.45, 0.28))
			for k in 5:
				var a := -PI + PI * float(k) / 4.0
				pic.draw_line(pic._p(0.5, 0.7), pic._p(0.5 + cos(a) * 0.22, 0.62 + sin(a) * 0.25), Color(0.3, 0.7, 0.3), 0.03 * size.x)
			pic._circle(0.5, 0.4 + bob, 0.07, Color(1.0, 0.45, 0.6))
		"biglight":
			_lantern(pic, 0.18, 0.5, 0.36, 0.7, t)
			_ghost(pic, t, 0.72, 0.28, 0.08, Color(0.6, 1.0, 0.75))
			_ghost(pic, t, 0.74, 0.68, 0.08, Color(1.0, 0.62, 0.9))
		"longlight":
			_lantern(pic, 0.1, 0.5, 0.12, 0.82, t)
			_ghost(pic, t, 0.86, 0.5, 0.08, Color(0.62, 0.78, 1.0))
		"dizzystars":
			_ghost(pic, t, 0.5, 0.55 + bob, 0.26, Color(0.6, 1.0, 0.75), true)
			for k in 4:
				var a := t * 2.5 + TAU * float(k) / 4.0
				var sx := 0.5 + cos(a) * 0.3
				var sy := 0.22 + sin(a) * 0.08
				pic._poly([[sx, sy - 0.05], [sx + 0.015, sy - 0.01], [sx + 0.05, sy], [sx + 0.015, sy + 0.01], [sx, sy + 0.05], [sx - 0.015, sy + 0.01], [sx - 0.05, sy], [sx - 0.015, sy - 0.01]], Color(1.0, 0.9, 0.3))
		"supersuck":
			pic._poly([[0.05, 0.6], [0.45, 0.48], [0.45, 0.62], [0.05, 0.72]], Color(0.5, 0.55, 0.65))  # the nozzle
			pic._poly([[0.45, 0.42], [0.55, 0.42], [0.55, 0.68], [0.45, 0.68]], Color(0.4, 1.0, 0.6))
			for k in 3:
				var ph := fmod(t * 0.8 + k / 3.0, 1.0)
				pic.draw_arc(pic._p(0.55 + (1.0 - ph) * 0.3, 0.55), (0.05 + (1.0 - ph) * 0.12) * size.x, -1.2, 1.2, 10, Color(0.55, 1.0, 0.65, ph), 0.02 * size.x)
			_ghost(pic, t, 0.8, 0.45 + bob * 0.5, 0.12, Color(0.6, 1.0, 0.75))
		"jar":
			pic._poly([[0.24, 0.24], [0.76, 0.24], [0.8, 0.9], [0.2, 0.9]], Color(0.75, 0.9, 1.0, 0.35))
			_ghost(pic, t, 0.5, 0.52 + bob, 0.17, color)
			pic._poly([[0.22, 0.16], [0.78, 0.16], [0.78, 0.25], [0.22, 0.25]], Color(0.8, 0.6, 0.3))
			pic.draw_arc(pic._p(0.5, 0.56), 0.3 * size.x, -2.6, -2.0, 8, Color(1.0, 1.0, 1.0, 0.7), 0.025 * size.x)
