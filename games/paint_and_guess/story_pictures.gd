extends RefCounted
## Paint and Guess's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.
## smudge (the gallery cat in her beret), paintpot, goldframe (TODAY'S GALLERY) tell the story; smiley, snake and
## butterfly are easy things to paint (games/paint_and_guess/paintgen.gd THINGS). Every other thing to paint is
## another game's picture (names are shared across games).

const NAMES: Array[String] = ["smudge", "paintpot", "goldframe", "smiley", "snake", "butterfly"]

const FUR := Color(0.98, 0.72, 0.4)
const BERET := Color(0.85, 0.2, 0.35)
const PAINTS: Array[Color] = [Color(1.0, 0.3, 0.3), Color(1.0, 0.85, 0.2), Color(0.3, 0.75, 1.0), Color(0.4, 0.9, 0.4), Color(0.8, 0.45, 1.0)]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"smudge":  # Smudge the gallery cat: ginger, a red beret, a paint brush in her paw
			var tail := sin(t * 2.5) * 0.06
			pic._poly([[0.72, 0.86 + bob], [0.8, 0.84 + bob], [0.95 + tail, 0.6 + bob], [0.9 + tail, 0.58 + bob]], FUR.darkened(0.1))  # tail
			pic._circle(0.5, 0.75 + bob, 0.24, FUR)  # body
			pic._circle(0.5, 0.8 + bob, 0.13, Color(1.0, 0.92, 0.8))  # tummy
			pic._poly([[0.3, 0.3 + bob], [0.33, 0.1 + bob], [0.45, 0.24 + bob]], FUR)  # ears
			pic._poly([[0.7, 0.3 + bob], [0.67, 0.1 + bob], [0.55, 0.24 + bob]], FUR)
			pic._poly([[0.33, 0.27 + bob], [0.345, 0.15 + bob], [0.42, 0.24 + bob]], Color(1.0, 0.65, 0.7))
			pic._circle(0.5, 0.38 + bob, 0.2, FUR)  # head
			pic._circle(0.38, 0.33 + bob, 0.045, FUR.darkened(0.15))  # stripes
			pic._circle(0.62, 0.33 + bob, 0.045, FUR.darkened(0.15))
			pic._poly([[0.28, 0.24 + bob], [0.5, 0.12 + bob], [0.68, 0.18 + bob], [0.6, 0.27 + bob], [0.36, 0.29 + bob]], BERET)  # beret
			pic._circle(0.53, 0.12 + bob, 0.025, BERET.darkened(0.2))
			pic._eye(0.43, 0.38 + bob, 0.045)
			pic._eye(0.57, 0.38 + bob, 0.045)
			pic._poly([[0.47, 0.45 + bob], [0.53, 0.45 + bob], [0.5, 0.48 + bob]], Color(1.0, 0.5, 0.6))  # nose
			for s in [-1.0, 1.0]:  # whiskers
				pic.draw_line(pic._p(0.5 + s * 0.06, 0.47 + bob), pic._p(0.5 + s * 0.2, 0.44 + bob), Color(1, 1, 1, 0.8), maxf(1.0, pic.size.x * 0.008))
				pic.draw_line(pic._p(0.5 + s * 0.06, 0.48 + bob), pic._p(0.5 + s * 0.2, 0.5 + bob), Color(1, 1, 1, 0.8), maxf(1.0, pic.size.x * 0.008))
			var wave := sin(t * 4.0) * 0.04
			pic.draw_line(pic._p(0.3, 0.7 + bob), pic._p(0.12, 0.5 + bob + wave), Color(0.6, 0.4, 0.2), maxf(2.0, pic.size.x * 0.03))  # brush
			pic._circle(0.12, 0.5 + bob + wave, 0.04, PAINTS[int(t * 0.7) % PAINTS.size()])
			pic._circle(0.31, 0.71 + bob, 0.06, FUR.lightened(0.1))  # paw
		"paintpot":  # a pot of paint with a brush, colours swirling
			var c: Color = PAINTS[int(t * 0.5) % PAINTS.size()]
			pic._poly([[0.25, 0.45 + bob], [0.75, 0.45 + bob], [0.7, 0.88 + bob], [0.3, 0.88 + bob]], Color(0.85, 0.87, 0.92))
			pic._poly([[0.25, 0.45 + bob], [0.75, 0.45 + bob], [0.74, 0.52 + bob], [0.26, 0.52 + bob]], c)
			pic._poly([[0.3, 0.52 + bob], [0.38, 0.52 + bob], [0.36, 0.66 + bob], [0.32, 0.64 + bob]], c)  # a drip
			pic._circle(0.34, 0.66 + bob, 0.025, c)
			pic.draw_line(pic._p(0.55, 0.48 + bob), pic._p(0.72, 0.12 + bob), Color(0.6, 0.4, 0.2), maxf(2.0, pic.size.x * 0.04))
			pic._poly([[0.5, 0.5 + bob], [0.6, 0.5 + bob], [0.58, 0.4 + bob], [0.52, 0.4 + bob]], c)
		"goldframe":  # TODAY'S GALLERY: a golden picture frame with a little sun painted in it, twinkling
			pic._poly([[0.12, 0.2 + bob], [0.88, 0.2 + bob], [0.88, 0.85 + bob], [0.12, 0.85 + bob]], Color(1.0, 0.78, 0.2))
			pic._poly([[0.2, 0.28 + bob], [0.8, 0.28 + bob], [0.8, 0.77 + bob], [0.2, 0.77 + bob]], Color(0.12, 0.14, 0.3))
			pic._circle(0.5, 0.52 + bob, 0.11, Color(1.0, 0.85, 0.3))
			for i in 8:
				var a := TAU * float(i) / 8.0 + t
				pic.draw_line(pic._p(0.5 + cos(a) * 0.14, 0.52 + bob + sin(a) * 0.14), pic._p(0.5 + cos(a) * 0.2, 0.52 + bob + sin(a) * 0.2),
					Color(1.0, 0.85, 0.3), maxf(1.5, pic.size.x * 0.02))
			for i in 4:
				var tw := 0.02 + 0.015 * absf(sin(t * 4.0 + float(i)))
				var cx: float = [0.12, 0.88, 0.12, 0.88][i]
				var cy: float = [0.2, 0.2, 0.85, 0.85][i] + bob
				pic._poly([[cx, cy - tw * 2.0], [cx + tw, cy], [cx, cy + tw * 2.0], [cx - tw, cy]], Color(1.0, 0.97, 0.7))
		"smiley":  # a big happy face
			pic._circle(0.5, 0.52 + bob, 0.36, Color(1.0, 0.85, 0.2))
			pic._circle(0.38, 0.42 + bob, 0.05, Color(0.2, 0.15, 0.1))
			pic._circle(0.62, 0.42 + bob, 0.05, Color(0.2, 0.15, 0.1))
			pic.draw_arc(pic._p(0.5, 0.52 + bob), pic.size.x * 0.2, 0.35, PI - 0.35, 16, Color(0.2, 0.15, 0.1), maxf(2.0, pic.size.x * 0.035))
		"snake":  # a friendly wiggly snake
			var pts := PackedVector2Array()
			for i in 17:
				var x := 0.12 + 0.68 * float(i) / 16.0
				pts.append(pic._p(x, 0.62 + bob + sin(float(i) * 0.8 + t * 3.0) * 0.1))
			pic.draw_polyline(pts, Color(0.35, 0.8, 0.35), maxf(3.0, pic.size.x * 0.1))
			for i in range(1, 16, 3):
				pic._circle(0.12 + 0.68 * float(i) / 16.0, 0.62 + bob + sin(float(i) * 0.8 + t * 3.0) * 0.1, 0.022, Color(1.0, 0.9, 0.3))
			var hy := 0.62 + bob + sin(16.0 * 0.8 + t * 3.0) * 0.1
			pic._circle(0.84, hy, 0.09, Color(0.35, 0.8, 0.35))
			pic._eye(0.86, hy - 0.03, 0.03)
			pic.draw_line(pic._p(0.92, hy + 0.02), pic._p(0.98, hy + 0.04), Color(1.0, 0.3, 0.35), maxf(1.0, pic.size.x * 0.012))
		"butterfly":  # a butterfly with spotty wings, flapping
			var f := 0.75 + 0.25 * absf(sin(t * 5.0))
			for s in [-1.0, 1.0]:
				pic._poly([[0.5, 0.48 + bob], [0.5 + s * 0.4 * f, 0.18 + bob], [0.5 + s * 0.42 * f, 0.5 + bob]], Color(1.0, 0.55, 0.75))
				pic._poly([[0.5, 0.52 + bob], [0.5 + s * 0.34 * f, 0.56 + bob], [0.5 + s * 0.24 * f, 0.8 + bob]], Color(0.6, 0.5, 1.0))
				pic._circle(0.5 + s * 0.27 * f, 0.36 + bob, 0.045, Color(1.0, 0.95, 0.5))
			pic._poly([[0.47, 0.32 + bob], [0.53, 0.32 + bob], [0.52, 0.76 + bob], [0.48, 0.76 + bob]], Color(0.3, 0.2, 0.25))
			pic._circle(0.5, 0.3 + bob, 0.045, Color(0.3, 0.2, 0.25))
			pic.draw_line(pic._p(0.49, 0.27 + bob), pic._p(0.42, 0.14 + bob), Color(0.3, 0.2, 0.25), maxf(1.0, pic.size.x * 0.012))
			pic.draw_line(pic._p(0.51, 0.27 + bob), pic._p(0.58, 0.14 + bob), Color(0.3, 0.2, 0.25), maxf(1.0, pic.size.x * 0.012))
