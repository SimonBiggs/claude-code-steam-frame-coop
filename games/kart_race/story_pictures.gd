extends RefCounted
## Kart Race's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["kart", "partyhat", "cowboy", "wizard", "boltbot", "kartsmall", "kartbig", "lollipop", "snail",
	"spoiler", "spanner", "mushroom", "mushrooms", "bubble", "banana", "horn", "shelf"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	var size: Vector2 = pic.size
	var white := Color(1.0, 1.0, 1.0)
	match kind:
		"kart", "kartsmall", "kartbig":  # medium / LIGHT (small, zippy) / HEAVY (big and chunky) karts
			_kart(pic, t, bob, color, 0.78 if kind == "kartsmall" else (1.18 if kind == "kartbig" else 1.0))
		"lollipop":
			pic.draw_line(pic._p(0.5, 0.55 + bob), pic._p(0.5, 0.95), Color(1, 1, 1), 0.05 * size.x)
			pic._circle(0.5, 0.36 + bob, 0.28, color)
			for k in 3:
				pic.draw_arc(pic._p(0.5, 0.36 + bob), (0.08 + k * 0.07) * size.x, t * 2.0 + k, t * 2.0 + k + 4.0, 16, white, 0.025 * size.x)
		"snail":  # GENTLE: a happy slow snail
			pic._poly([[0.1, 0.82 + bob], [0.85, 0.82 + bob], [0.9, 0.74 + bob], [0.2, 0.72 + bob]], Color(0.75, 0.9, 0.5))
			pic._circle(0.5, 0.56 + bob, 0.22, color)
			for k in 3:
				pic.draw_arc(pic._p(0.5, 0.56 + bob), (0.05 + k * 0.055) * size.x, 0.0 + k, TAU * 0.8 + k, 14, color.darkened(0.35), 0.02 * size.x)
			pic._circle(0.82, 0.62 + bob, 0.08, Color(0.75, 0.9, 0.5))
			pic.draw_line(pic._p(0.82, 0.56 + bob), pic._p(0.8, 0.42 + bob), Color(0.6, 0.75, 0.4), 0.018 * size.x)
			pic.draw_line(pic._p(0.86, 0.56 + bob), pic._p(0.9, 0.43 + bob), Color(0.6, 0.75, 0.4), 0.018 * size.x)
			pic._eye(0.8, 0.41 + bob, 0.035)
			pic._eye(0.9, 0.42 + bob, 0.035)
		"spoiler":
			pic._poly([[0.1, 0.3 + bob], [0.9, 0.3 + bob], [0.85, 0.42 + bob], [0.15, 0.42 + bob]], color)
			for x in [0.32, 0.68]:
				pic._poly([[x - 0.04, 0.42 + bob], [x + 0.04, 0.42 + bob], [x + 0.04, 0.68 + bob], [x - 0.04, 0.68 + bob]], color.darkened(0.3))
			pic._poly([[0.15, 0.68 + bob], [0.85, 0.68 + bob], [0.85, 0.82 + bob], [0.15, 0.82 + bob]], Color(0.3, 0.32, 0.4))
		"spanner":  # fit a new part
			var a := sin(t * 3.0) * 0.15
			var c := Vector2(0.5, 0.5 + bob)
			var d := Vector2(cos(-0.8 + a), sin(-0.8 + a))
			pic.draw_line(pic._p(c.x - d.x * 0.3, c.y - d.y * 0.3), pic._p(c.x + d.x * 0.3, c.y + d.y * 0.3), Color(0.75, 0.78, 0.85), 0.1 * size.x)
			for e in [-1.0, 1.0]:
				var q := c + d * 0.33 * float(e)
				pic._circle(q.x, q.y, 0.12, Color(0.75, 0.78, 0.85))
				pic._circle(q.x + d.x * 0.06 * float(e), q.y + d.y * 0.06 * float(e), 0.06, color.darkened(0.5))
		"mushroom", "mushrooms":  # ZOOM / TRIPLE ZOOM
			var n := 3 if kind == "mushrooms" else 1
			for k in n:
				var x := 0.5 if n == 1 else 0.22 + k * 0.28
				var sc := 1.0 if n == 1 else 0.6
				var y := 0.5 + bob + (0.0 if n == 1 else (0.1 if k != 1 else -0.05))
				pic._poly([[x - 0.12 * sc, y], [x + 0.12 * sc, y], [x + 0.1 * sc, y + 0.3 * sc], [x - 0.1 * sc, y + 0.3 * sc]], Color(1.0, 0.95, 0.85))
				var cap := []
				for j in 13:
					var ang := PI + PI * j / 12.0
					cap.append([x + cos(ang) * 0.34 * sc, y + 0.02 + sin(ang) * 0.3 * sc])
				pic._poly(cap, Color(1.0, 0.3, 0.3))
				for dot in [[-0.15, -0.12], [0.12, -0.18], [0.02, -0.06]]:
					pic._circle(x + float(dot[0]) * sc, y + float(dot[1]) * sc, 0.05 * sc, white)
				pic._eye(x - 0.05 * sc, y + 0.14 * sc, 0.03 * sc)
				pic._eye(x + 0.05 * sc, y + 0.14 * sc, 0.03 * sc)
		"bubble":  # the bubble shield
			var wob := 1.0 + 0.04 * sin(t * 4.0)
			pic._circle(0.5, 0.5 + bob, 0.36 * wob, Color(0.55, 0.85, 1.0, 0.45))
			pic.draw_arc(pic._p(0.5, 0.5 + bob), 0.36 * wob * size.x, 0.0, TAU, 32, Color(0.85, 0.95, 1.0), 0.025 * size.x)
			pic.draw_arc(pic._p(0.5, 0.5 + bob), 0.26 * size.x, 3.6, 4.6, 10, white, 0.04 * size.x)
			pic._circle(0.42, 0.34 + bob, 0.04, white)
		"banana":
			var pts := []
			for k in 9:
				var a := PI * 0.15 + PI * 0.7 * k / 8.0
				pts.append([0.5 + cos(a) * 0.36, 0.2 + bob + sin(a) * 0.5])
			for k in 9:
				var a := PI * 0.85 - PI * 0.7 * k / 8.0
				pts.append([0.5 + cos(a) * 0.24, 0.24 + bob + sin(a) * 0.36])
			pic._poly(pts, Color(1.0, 0.88, 0.25))
			pic._circle(0.22, 0.38 + bob, 0.035, Color(0.45, 0.32, 0.15))
			pic._circle(0.78, 0.38 + bob, 0.035, Color(0.45, 0.32, 0.15))
		"horn":  # the silly honk
			pic._poly([[0.15, 0.42 + bob], [0.35, 0.42 + bob], [0.35, 0.58 + bob], [0.15, 0.58 + bob]], Color(0.55, 0.35, 0.25))
			pic._poly([[0.35, 0.45 + bob], [0.78, 0.28 + bob], [0.78, 0.72 + bob], [0.35, 0.55 + bob]], color)
			pic._circle(0.12, 0.5 + bob, 0.1, Color(1.0, 0.35, 0.4))
			for k in 3:
				var r := 0.08 + k * 0.07 + fmod(t * 0.3, 0.07)
				pic.draw_arc(pic._p(0.8, 0.5 + bob), r * size.x, -0.7, 0.7, 8, Color(1, 1, 1, 0.8 - k * 0.2), 0.02 * size.x)
		"shelf":  # Bolt's trophy shelf
			pic._poly([[0.08, 0.5], [0.92, 0.5], [0.92, 0.56], [0.08, 0.56]], Color(0.6, 0.42, 0.25))
			pic._poly([[0.08, 0.86], [0.92, 0.86], [0.92, 0.92], [0.08, 0.92]], Color(0.6, 0.42, 0.25))
			var cols := [Color(1.0, 0.82, 0.2), Color(0.85, 0.88, 0.95), Color(0.85, 0.5, 0.25)]
			for k in 3:
				var x := 0.25 + k * 0.25
				for y in [0.5, 0.86]:
					var c: Color = cols[(k + (1 if y > 0.6 else 0)) % 3]
					pic._poly([[x - 0.06, y - 0.03], [x + 0.06, y - 0.03], [x + 0.03, y - 0.12], [x - 0.03, y - 0.12]], c.darkened(0.2))
					pic._circle(x, y - 0.2 + bob * 0.5, 0.09, c)
		"partyhat":
			pic._poly([[0.2, 0.86 + bob], [0.8, 0.86 + bob], [0.5, 0.14 + bob]], color)
			for k in 3:
				var y := 0.36 + k * 0.18
				var w := (y - 0.14) / 0.72 * 0.3
				pic._poly([[0.5 - w, y + bob], [0.5 + w, y + bob], [0.5 + w + 0.025, y + 0.06 + bob], [0.5 - w - 0.025, y + 0.06 + bob]], Color(1.0, 0.95, 0.4))
			pic._circle(0.5, 0.13 + bob, 0.08, white)
		"cowboy":
			pic._poly([[0.05, 0.66 + bob], [0.95, 0.66 + bob], [0.85, 0.76 + bob], [0.15, 0.76 + bob]], Color(0.6, 0.38, 0.2))
			pic._poly([[0.3, 0.68 + bob], [0.7, 0.68 + bob], [0.66, 0.3 + bob], [0.5, 0.38 + bob], [0.34, 0.3 + bob]], Color(0.68, 0.45, 0.25))
			pic._poly([[0.31, 0.58 + bob], [0.69, 0.58 + bob], [0.69, 0.64 + bob], [0.31, 0.64 + bob]], Color(0.95, 0.3, 0.3))
		"wizard":
			pic._poly([[0.08, 0.8 + bob], [0.92, 0.8 + bob], [0.82, 0.88 + bob], [0.18, 0.88 + bob]], color.darkened(0.2))
			pic._poly([[0.26, 0.82 + bob], [0.74, 0.82 + bob], [0.6, 0.35 + bob], [0.72, 0.1 + bob], [0.5, 0.3 + bob]], color)
			for st_p in [[0.45, 0.6], [0.58, 0.42], [0.5, 0.74]]:
				pic._circle(st_p[0], st_p[1] + bob, 0.035 + 0.01 * sin(t * 5.0 + st_p[0] * 9.0), Color(1.0, 0.92, 0.35))
		"boltbot":  # Bolt: the friendly track-building robot, a chequered flag on his antenna and a wrench in hand
			var metal := Color(0.55, 0.7, 0.9)
			var flag_x := 0.5 + sin(t * 6.0) * 0.02
			pic.draw_line(pic._p(0.5, 0.2 + bob), pic._p(0.5, 0.05 + bob), Color(0.35, 0.4, 0.5), 0.02 * size.x)
			for k in 4:  # the chequered flag
				var cx := flag_x + 0.01 + (k % 2) * 0.06
				var cy := 0.04 + int(k / 2.0) * 0.05
				pic._poly([[cx, cy + bob], [cx + 0.06, cy + bob], [cx + 0.06, cy + 0.05 + bob], [cx, cy + 0.05 + bob]],
					Color(0.1, 0.1, 0.12) if (k == 0 or k == 3) else white)
			pic._poly([[0.28, 0.2 + bob], [0.72, 0.2 + bob], [0.74, 0.5 + bob], [0.26, 0.5 + bob]], metal)
			pic._eye(0.4, 0.34 + bob, 0.07)
			pic._eye(0.6, 0.34 + bob, 0.07)
			pic.draw_arc(pic._p(0.5, 0.41 + bob), 0.06 * size.x, 0.3, 2.85, 12, Color(0.15, 0.2, 0.3), 0.014 * size.x)
			pic._poly([[0.3, 0.54 + bob], [0.7, 0.54 + bob], [0.68, 0.82 + bob], [0.32, 0.82 + bob]], metal.darkened(0.15))
			pic._circle(0.5, 0.67 + bob, 0.07, Color(1.0, 0.6, 0.2).lightened(0.2 * (0.5 + 0.5 * sin(t * 4.0))))
			pic._poly([[0.3, 0.58 + bob], [0.18, 0.7 + bob], [0.22, 0.73 + bob], [0.33, 0.63 + bob]], metal)
			var lift := sin(t * 5.0) * 0.04
			pic._poly([[0.7, 0.58 + bob], [0.82, 0.48 + bob + lift], [0.85, 0.51 + bob + lift], [0.72, 0.64 + bob]], metal)
			pic.draw_line(pic._p(0.84, 0.5 + bob + lift), pic._p(0.9, 0.36 + bob + lift), Color(0.75, 0.75, 0.8), 0.03 * size.x)
			pic._circle(0.91, 0.34 + bob + lift, 0.035, Color(0.75, 0.75, 0.8))
			pic._circle(0.92, 0.32 + bob + lift, 0.016, color)
			for x in [0.38, 0.62]:
				pic._circle(x, 0.88, 0.07, Color(0.15, 0.15, 0.18))
				pic._circle(x, 0.88, 0.03, Color(0.7, 0.7, 0.75))


## A kart seen from the side; sc < 1 is the small zippy LIGHT kart, > 1 the big HEAVY one (chunkier wheels).
static func _kart(pic, t: float, bob: float, color: Color, sc: float) -> void:
	var size: Vector2 = pic.size
	var roll := t * 8.0 / sc
	var cx := 0.5
	var by := 0.62 + (1.0 - sc) * 0.12
	var w := 0.38 * sc
	var h := 0.14 * sc
	pic._poly([[cx - w, by + bob], [cx + w, by + bob], [cx + w * 0.86, by + h + bob], [cx - w * 0.86, by + h + bob]], color)
	pic._poly([[cx + w * 0.3, by - h * 0.9 + bob], [cx + w * 0.82, by - h * 0.9 + bob], [cx + w, by + bob], [cx + w * 0.26, by + bob]], color.lightened(0.25))
	pic._poly([[cx - w * 1.05, by - h * 1.2 + bob], [cx - w * 0.68, by - h * 1.2 + bob], [cx - w * 0.68, by + bob], [cx - w * 1.05, by + bob]], color.darkened(0.2))
	pic._circle(cx - w * 0.2, by - h * 1.4 + bob, 0.12 * sc, Color(0.97, 0.97, 1.0))
	pic._poly([[cx - w * 0.14, by - h * 1.7 + bob], [cx + w * 0.16, by - h * 1.7 + bob], [cx + w * 0.16, by - h * 1.2 + bob], [cx - w * 0.14, by - h * 1.2 + bob]], Color(0.2, 0.6, 1.0))
	var wr := 0.1 * sc * (1.15 if sc > 1.05 else 1.0)
	for x in [cx - w * 0.6, cx + w * 0.6]:
		pic._circle(x, by + h + 0.04 * sc, wr, Color(0.1, 0.1, 0.12))
		pic.draw_line(pic._p(x, by + h + 0.04 * sc), pic._p(x + cos(roll) * wr * 0.7, by + h + 0.04 * sc + sin(roll) * wr * 0.7), Color(0.85, 0.85, 0.9), 0.02 * size.x)
	if sc < 0.9:  # zippy: speed lines
		for k in 3:
			var x := cx - w - 0.06 - fmod(t * 0.8 + k * 0.33, 1.0) * 0.12
			pic.draw_line(pic._p(x, by - 0.05 + k * 0.06), pic._p(x - 0.08, by - 0.05 + k * 0.06), Color(1, 1, 1, 0.7), 0.015 * size.x)
	for k in 3:
		var x := 0.02 - fmod(t * 0.6 + k * 0.33, 1.0) * 0.1
		pic._circle(cx - w - 0.06 + x, by + 0.06 + k * 0.04, 0.025, Color(1.0, 1.0, 1.0, 0.6))
