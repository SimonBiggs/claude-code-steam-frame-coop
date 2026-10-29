extends RefCounted
## Ghost Lantern's story card pictures (core/story_pictures.gd finds this file by itself): grannyboo (Granny Boo:
## an old ghost with spectacles, a bun and a pink shawl, knitting), the ghost kinds snoozy (in a nightcap, with
## bubbles), zippy (a pink ghost with a bow, zooming), peekaboo (peeking out from behind a curtain in a witch hat),
## goldie (a golden ghost with sparkles), kingghost (in a crown) and jar (a little ghost in a jar, ghost = color).

const NAMES: Array[String] = ["grannyboo", "snoozy", "zippy", "peekaboo", "goldie", "kingghost", "jar"]


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
		"jar":
			pic._poly([[0.24, 0.24], [0.76, 0.24], [0.8, 0.9], [0.2, 0.9]], Color(0.75, 0.9, 1.0, 0.35))
			_ghost(pic, t, 0.5, 0.52 + bob, 0.17, color)
			pic._poly([[0.22, 0.16], [0.78, 0.16], [0.78, 0.25], [0.22, 0.25]], Color(0.8, 0.6, 0.3))
			pic.draw_arc(pic._p(0.5, 0.56), 0.3 * size.x, -2.6, -2.0, 8, Color(1.0, 1.0, 1.0, 0.7), 0.025 * size.x)
