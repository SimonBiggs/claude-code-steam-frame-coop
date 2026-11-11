extends RefCounted
## Fishing Lake's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["fish", "otter", "lure_worm", "lure_spinner", "lure_lily", "lure_glow", "lure_gold", "fish_pond"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"fish":  # a friendly fish swimming right, body = color
			var wag := sin(t * 6.0) * 0.05
			pic._poly([[0.22, 0.52 + bob], [0.04, 0.32 + bob + wag], [0.06, 0.72 + bob + wag]], color.darkened(0.25))
			var body := []
			for i in 20:
				var a := TAU * float(i) / 20.0
				body.append([0.52 + cos(a) * 0.34, 0.52 + bob + sin(a) * 0.22])
			pic._poly(body, color)
			pic._poly([[0.42, 0.34 + bob], [0.6, 0.2 + bob], [0.62, 0.34 + bob]], color.darkened(0.2))
			pic._circle(0.52, 0.6 + bob, 0.1, color.lightened(0.35))
			pic._eye(0.72, 0.46 + bob, 0.06)
			pic._circle(0.84, 0.58 + bob, 0.02, Color(0.15, 0.1, 0.1))
		"otter":  # Ollie: a round brown otter face with a cream muzzle and whiskers
			var fur := Color(0.62, 0.42, 0.25)
			pic._circle(0.24, 0.24 + bob, 0.09, fur.darkened(0.15))
			pic._circle(0.76, 0.24 + bob, 0.09, fur.darkened(0.15))
			pic._circle(0.5, 0.52 + bob, 0.36, fur)
			pic._circle(0.5, 0.66 + bob, 0.2, Color(0.95, 0.86, 0.7))
			pic._eye(0.37, 0.44 + bob, 0.07)
			pic._eye(0.63, 0.44 + bob, 0.07)
			pic._circle(0.5, 0.58 + bob, 0.06, Color(0.15, 0.1, 0.1))
			for sy in [-0.03, 0.03]:
				pic.draw_line(pic._p(0.38, 0.66 + bob + sy), pic._p(0.12, 0.62 + bob + sy * 2.0), Color(0.3, 0.2, 0.15), 2.0)
				pic.draw_line(pic._p(0.62, 0.66 + bob + sy), pic._p(0.88, 0.62 + bob + sy * 2.0), Color(0.3, 0.2, 0.15), 2.0)
			pic._poly([[0.44, 0.74 + bob], [0.56, 0.74 + bob], [0.5, 0.8 + bob]], Color(0.75, 0.35, 0.4))
		"lure_worm":  # a wiggly pink worm on a hook
			var pts := []
			for i in 9:
				var u := float(i) / 8.0
				pts.append(pic._p(0.2 + u * 0.55, 0.62 + bob + sin(u * 7.0 + t * 4.0) * 0.07))
			pic.draw_polyline(PackedVector2Array(pts), color, pic.size.x * 0.09, true)
			pic._circle(0.75, 0.62 + bob + sin(7.0 + t * 4.0) * 0.07, 0.05, color.lightened(0.2))
			pic._eye(0.76, 0.6 + bob + sin(7.0 + t * 4.0) * 0.07, 0.025)
			pic.draw_arc(pic._p(0.3, 0.32 + bob), pic.size.x * 0.1, 0.0, PI, 12, Color(0.75, 0.78, 0.82), pic.size.x * 0.025)
			pic.draw_line(pic._p(0.4, 0.32 + bob), pic._p(0.4, 0.08 + bob), Color(0.85, 0.85, 0.9), 2.0)
		"lure_spinner":  # a shiny spinning blade and a red bead
			var w := 0.18 * absf(cos(t * 5.0)) + 0.05
			pic.draw_line(pic._p(0.5, 0.06 + bob), pic._p(0.5, 0.9 + bob), Color(0.85, 0.85, 0.9), 2.0)
			var blade := []
			for i in 16:
				var a := TAU * float(i) / 16.0
				blade.append([0.5 + cos(a) * w, 0.42 + bob + sin(a) * 0.2])
			pic._poly(blade, color)
			pic._circle(0.5 - w * 0.3, 0.36 + bob, 0.04, Color(1, 1, 1, 0.8))
			pic._circle(0.5, 0.7 + bob, 0.07, Color(0.9, 0.2, 0.2))
			pic._poly([[0.42, 0.8 + bob], [0.58, 0.8 + bob], [0.5, 0.95 + bob]], Color(1.0, 0.6, 0.2))
		"lure_lily":  # a little green bug on a lily pad
			pic._poly([[0.1, 0.72 + bob], [0.5, 0.52 + bob], [0.9, 0.72 + bob], [0.5, 0.9 + bob]], Color(0.25, 0.6, 0.3))
			pic._circle(0.5, 0.52 + bob, 0.2, color)
			pic._circle(0.5, 0.32 + bob, 0.11, color.darkened(0.2))
			pic.draw_line(pic._p(0.5, 0.36 + bob), pic._p(0.5, 0.7 + bob), color.darkened(0.45), 2.0)
			pic._eye(0.45, 0.3 + bob, 0.035)
			pic._eye(0.55, 0.3 + bob, 0.035)
			for s in [-1.0, 1.0]:
				pic.draw_line(pic._p(0.5 + s * 0.18, 0.5 + bob), pic._p(0.5 + s * 0.32, 0.42 + bob + sin(t * 8.0) * 0.03), Color(0.15, 0.2, 0.1), 2.0)
		"lure_glow":  # a glowing ball lure with soft rings
			var g := 0.5 + 0.5 * sin(t * 3.0)
			pic._circle(0.5, 0.5 + bob, 0.36, Color(color.r, color.g, color.b, 0.15 + 0.1 * g))
			pic._circle(0.5, 0.5 + bob, 0.25, Color(color.r, color.g, color.b, 0.35))
			pic._circle(0.5, 0.5 + bob, 0.15, color.lightened(0.4))
			pic._circle(0.45, 0.45 + bob, 0.05, Color(1, 1, 1, 0.9))
			pic.draw_line(pic._p(0.5, 0.02 + bob), pic._p(0.5, 0.35 + bob), Color(0.85, 0.85, 0.9), 2.0)
		"lure_gold":  # a golden fly with sparkly wings
			for s in [-1.0, 1.0]:
				pic._poly([[0.5, 0.5 + bob], [0.5 + s * 0.36, 0.28 + bob + sin(t * 10.0) * 0.05], [0.5 + s * 0.3, 0.55 + bob]], Color(1.0, 1.0, 0.85, 0.75))
			pic._circle(0.5, 0.55 + bob, 0.14, color)
			pic._circle(0.5, 0.72 + bob, 0.1, color.darkened(0.2))
			pic._eye(0.46, 0.5 + bob, 0.03)
			pic._eye(0.54, 0.5 + bob, 0.03)
			for i in 3:
				var a := t * 2.0 + float(i) * 2.1
				pic._circle(0.5 + cos(a) * 0.38, 0.5 + bob + sin(a) * 0.32, 0.03, Color(1.0, 0.95, 0.5))
		"fish_pond":  # Ollie's round pond with logs, a lily and two fish
			pic._circle(0.5, 0.58 + bob, 0.42, Color(0.55, 0.38, 0.22))
			pic._circle(0.5, 0.58 + bob, 0.36, Color(0.25, 0.55, 0.85))
			pic._circle(0.32, 0.46 + bob, 0.08, Color(0.3, 0.7, 0.3))
			for i in 2:
				var a := t * 1.2 + float(i) * PI
				var fx := 0.5 + cos(a) * 0.18
				var fy := 0.62 + bob + sin(a) * 0.1
				pic._circle(fx, fy, 0.06, Color(1.0, 0.6, 0.2) if i == 0 else Color(1.0, 0.85, 0.25))
			pic._circle(0.7, 0.4 + bob, 0.05, Color(1.0, 0.95, 0.6))
