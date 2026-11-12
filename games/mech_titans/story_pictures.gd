extends RefCounted
## Mech Titans' story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["momo", "sanctuary", "titanpod", "titanframe", "crownkaiju", "kite", "toypark"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	var size: Vector2 = pic.size
	match kind:
		"momo":  # Momo: the Titans' first kaiju friend, a mint-green baby kaiju with soft back spikes, waving hello
			var skin := Color(0.45, 0.85, 0.6)
			var belly := Color(0.85, 1.0, 0.8)
			pic._poly([[0.3, 0.8 + bob], [0.04, 0.9 + bob], [0.08, 0.8 + bob], [0.28, 0.68 + bob]], skin.darkened(0.15))
			for k in 4:  # back spikes
				var x := 0.24 + k * 0.1
				var y := 0.5 - sin(k * 0.9) * 0.18 + 0.12
				pic._poly([[x - 0.05, y + 0.06 + bob], [x - 0.03, y - 0.08 + bob], [x + 0.05, y + 0.04 + bob]], Color(0.4, 0.6, 1.0))
			pic._circle(0.48, 0.68 + bob, 0.24, skin)
			pic._circle(0.52, 0.72 + bob, 0.15, belly)
			pic._circle(0.58, 0.34 + bob, 0.2, skin)
			pic._eye(0.52, 0.31 + bob, 0.06)
			pic._eye(0.67, 0.31 + bob, 0.06)
			pic.draw_arc(pic._p(0.6, 0.4 + bob), 0.06 * size.x, 0.3, 2.85, 12, Color(0.15, 0.3, 0.2), 0.014 * size.x)
			pic._circle(0.46, 0.4 + bob, 0.03, Color(1.0, 0.55, 0.6, 0.7))
			pic._circle(0.74, 0.4 + bob, 0.03, Color(1.0, 0.55, 0.6, 0.7))
			var wave := sin(t * 7.0) * 0.07
			pic._poly([[0.7, 0.6 + bob], [0.86 + wave * 0.3, 0.42 + bob + wave], [0.9 + wave * 0.3, 0.46 + bob + wave], [0.74, 0.66 + bob]], skin)
			pic._poly([[0.32, 0.62 + bob], [0.24, 0.72 + bob], [0.28, 0.75 + bob], [0.36, 0.68 + bob]], skin)
			for x in [0.38, 0.6]:
				pic._circle(x, 0.9 + bob * 0.5, 0.06, skin.darkened(0.15))
			pic._circle(0.88, 0.16 + bob, 0.035 + 0.01 * sin(t * 5.0), color.lightened(0.3))
		"sanctuary":  # the Kaiju Sanctuary: green hills with a pond, a little kaiju friend and hearts floating up
			pic._circle(0.3, 1.05, 0.45, Color(0.45, 0.78, 0.4))
			pic._circle(0.78, 1.1, 0.48, Color(0.38, 0.7, 0.36))
			pic._poly([[0.5, 0.82], [0.8, 0.8], [0.86, 0.86], [0.55, 0.9]], Color(0.45, 0.7, 1.0))
			var sk := Color(0.45, 0.85, 0.6)
			pic._circle(0.32, 0.66 + bob, 0.12, sk)
			pic._circle(0.38, 0.5 + bob, 0.09, sk)
			pic._eye(0.35, 0.48 + bob, 0.03)
			pic._eye(0.42, 0.48 + bob, 0.03)
			for k in 3:
				var hy := fposmod(0.55 - t * 0.12 - k * 0.2, 0.6)
				var hx := 0.55 + k * 0.13 + sin(t * 2.0 + k) * 0.02
				pic._circle(hx - 0.025, 0.15 + hy, 0.03, Color(1.0, 0.4, 0.5))
				pic._circle(hx + 0.025, 0.15 + hy, 0.03, Color(1.0, 0.4, 0.5))
				pic._poly([[hx - 0.055, 0.16 + hy], [hx + 0.055, 0.16 + hy], [hx, 0.23 + hy]], Color(1.0, 0.4, 0.5))
		"titanpod":  # an upgrade pod: a glowing capsule (the card's colour) with light beaming up
			pic._poly([[0.4, 0.0], [0.6, 0.0], [0.66, 0.3], [0.34, 0.3]], Color(color.r, color.g, color.b, 0.25))
			pic._poly([[0.32, 0.3 + bob], [0.68, 0.3 + bob], [0.72, 0.82 + bob], [0.28, 0.82 + bob]], color)
			pic._circle(0.5, 0.3 + bob, 0.18, color.lightened(0.35))
			pic._poly([[0.36, 0.5 + bob], [0.64, 0.5 + bob], [0.64, 0.6 + bob], [0.36, 0.6 + bob]], Color(1, 1, 1, 0.8))
			pic._poly([[0.22, 0.82], [0.78, 0.82], [0.84, 0.92], [0.16, 0.92]], Color(0.35, 0.38, 0.45))
			for k in 4:
				var a := t * 2.0 + k * 1.57
				pic._circle(0.5 + cos(a) * 0.3, 0.55 + sin(a) * 0.12 + bob, 0.025, Color(1.0, 0.95, 0.6))
		"titanframe":  # the Titan robot in the card's colour, waving a big fist
			var bodyc := color
			var trim := Color(0.95, 0.95, 0.98)
			pic._poly([[0.36, 0.9], [0.44, 0.9], [0.44, 0.66], [0.36, 0.66]], bodyc.darkened(0.2))
			pic._poly([[0.56, 0.9], [0.64, 0.9], [0.64, 0.66], [0.56, 0.66]], bodyc.darkened(0.2))
			pic._poly([[0.3, 0.68 + bob], [0.7, 0.68 + bob], [0.74, 0.36 + bob], [0.26, 0.36 + bob]], bodyc)
			pic._poly([[0.4, 0.5 + bob], [0.6, 0.5 + bob], [0.6, 0.6 + bob], [0.4, 0.6 + bob]], trim)
			pic._circle(0.5, 0.55 + bob, 0.04, Color(0.4, 0.9, 1.0))
			pic._poly([[0.38, 0.36 + bob], [0.62, 0.36 + bob], [0.6, 0.18 + bob], [0.4, 0.18 + bob]], trim)
			pic._poly([[0.42, 0.24 + bob], [0.58, 0.24 + bob], [0.58, 0.3 + bob], [0.42, 0.3 + bob]], Color(0.35, 0.85, 1.0))
			var wave := sin(t * 6.0) * 0.05
			pic._poly([[0.7, 0.42 + bob], [0.82, 0.3 + bob + wave], [0.86, 0.34 + bob + wave], [0.74, 0.48 + bob]], bodyc.darkened(0.1))
			pic._circle(0.86 + wave * 0.3, 0.27 + bob + wave, 0.07, trim)
			pic._poly([[0.3, 0.42 + bob], [0.18, 0.56 + bob], [0.22, 0.6 + bob], [0.32, 0.5 + bob]], bodyc.darkened(0.1))
			pic._circle(0.18, 0.62 + bob, 0.07, trim)
		"kite":  # a diamond kite (the card's colour) with a white cross, a wavy string and a bow tail, bobbing in the wind
			var sway := sin(t * 2.0) * 0.03
			var cx := 0.55 + sway
			var cy := 0.3 + bob
			pic._poly([[cx, cy - 0.22], [cx + 0.17, cy], [cx, cy + 0.26], [cx - 0.17, cy]], color)
			pic._poly([[cx, cy - 0.22], [cx + 0.17, cy], [cx, cy]], color.lightened(0.25))
			pic.draw_line(pic._p(cx, cy - 0.22), pic._p(cx, cy + 0.26), Color(1, 1, 1), 0.012 * size.x)
			pic.draw_line(pic._p(cx - 0.17, cy), pic._p(cx + 0.17, cy), Color(1, 1, 1), 0.012 * size.x)
			var prev: Vector2 = pic._p(cx, cy + 0.26)
			for k in 8:
				var f := float(k + 1) / 8.0
				var p: Vector2 = pic._p(cx - 0.35 * f + sin(t * 3.0 + f * 6.0) * 0.03, cy + 0.26 + 0.42 * f)
				pic.draw_line(prev, p, Color(0.95, 0.95, 0.95), 0.008 * size.x)
				prev = p
			for k in 3:
				var f2 := 0.25 + k * 0.25
				var bx := cx - 0.35 * f2 + sin(t * 3.0 + f2 * 6.0) * 0.03
				var by := cy + 0.26 + 0.42 * f2
				var bc := [Color(1.0, 0.85, 0.2), Color(0.3, 0.8, 1.0), Color(0.4, 0.9, 0.4)][k] as Color
				pic._poly([[bx - 0.04, by - 0.025], [bx, by], [bx - 0.04, by + 0.025]], bc)
				pic._poly([[bx + 0.04, by - 0.025], [bx, by], [bx + 0.04, by + 0.025]], bc)
		"toypark":  # Momo's toy park: a green hill with a teddy, a balloon, a beach ball and a pumpkin, a little flag on top
			pic._circle(0.5, 1.15, 0.6, Color(0.45, 0.78, 0.4))
			pic.draw_line(pic._p(0.5, 0.56), pic._p(0.5, 0.3), Color(0.5, 0.35, 0.2), 0.012 * size.x)
			pic._poly([[0.5, 0.3], [0.64, 0.35], [0.5, 0.4]], Color(1.0, 0.4, 0.5))
			# teddy
			var tb := Color(0.82, 0.48, 0.2)
			pic._circle(0.24, 0.72 + bob, 0.09, tb)
			pic._circle(0.24, 0.58 + bob, 0.07, tb)
			pic._circle(0.19, 0.53 + bob, 0.03, tb)
			pic._circle(0.29, 0.53 + bob, 0.03, tb)
			pic._eye(0.22, 0.57 + bob, 0.015)
			pic._eye(0.26, 0.57 + bob, 0.015)
			# balloon on a string
			var bx := 0.38 + sin(t * 1.5) * 0.02
			pic.draw_line(pic._p(0.38, 0.66), pic._p(bx, 0.36 + bob), Color(0.95, 0.95, 0.95), 0.006 * size.x)
			pic._circle(bx, 0.3 + bob, 0.07, Color(0.98, 0.25, 0.35))
			# beach ball
			pic._circle(0.66, 0.66 + bob * 0.5, 0.08, Color(1.0, 0.82, 0.15))
			pic._poly([[0.66, 0.58 + bob * 0.5], [0.7, 0.66 + bob * 0.5], [0.66, 0.74 + bob * 0.5]], Color(0.95, 0.2, 0.25))
			pic._poly([[0.66, 0.58 + bob * 0.5], [0.62, 0.66 + bob * 0.5], [0.66, 0.74 + bob * 0.5]], Color(0.2, 0.5, 1.0))
			# pumpkin
			pic._circle(0.8, 0.76, 0.07, Color(1.0, 0.52, 0.08))
			pic._circle(0.86, 0.76, 0.06, Color(0.95, 0.45, 0.05))
			pic._poly([[0.82, 0.69], [0.84, 0.69], [0.84, 0.65], [0.82, 0.65]], Color(0.3, 0.5, 0.15))
			for k in 3:  # sparkles: it keeps growing
				var a := t * 1.2 + k * 2.1
				pic._circle(0.5 + cos(a) * 0.38, 0.4 + sin(a) * 0.18, 0.015 + 0.008 * sin(t * 5.0 + k), Color(1.0, 0.95, 0.6))
		"crownkaiju":  # a big boss kaiju (the card's colour) with a golden crown and sparks round it
			var skin2 := color
			pic._circle(0.5, 0.68 + bob, 0.27, skin2)
			pic._circle(0.5, 0.74 + bob, 0.16, skin2.lightened(0.4))
			pic._circle(0.5, 0.36 + bob, 0.2, skin2)
			pic._eye(0.43, 0.34 + bob, 0.055)
			pic._eye(0.57, 0.34 + bob, 0.055)
			pic.draw_arc(pic._p(0.5, 0.43 + bob), 0.05 * size.x, 0.3, 2.85, 10, skin2.darkened(0.6), 0.014 * size.x)
			var gold := Color(1.0, 0.82, 0.25)
			pic._poly([[0.38, 0.2 + bob], [0.62, 0.2 + bob], [0.64, 0.08 + bob], [0.57, 0.14 + bob], [0.5, 0.04 + bob], [0.43, 0.14 + bob], [0.36, 0.08 + bob]], gold)
			pic._circle(0.5, 0.15 + bob, 0.02, Color(1.0, 0.3, 0.4))
			for k in 5:
				var a2 := t * 1.5 + k * 1.26
				pic._circle(0.5 + cos(a2) * 0.4, 0.5 + sin(a2) * 0.36, 0.018 + 0.008 * sin(t * 6.0 + k), gold.lightened(0.3))
			pic._circle(0.3, 0.92 + bob * 0.5, 0.07, skin2.darkened(0.15))
			pic._circle(0.7, 0.92 + bob * 0.5, 0.07, skin2.darkened(0.15))
