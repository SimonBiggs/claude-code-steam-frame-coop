extends RefCounted
## Crystal Saga's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["lumi", "shard", "bigfire", "snowflake", "twin", "longsword", "spin", "mighty", "windmill", "fountain", "rainbow",
	"archer", "healer", "bard", "starrain", "bubble", "guardian"]


static func draw(pic, kind: String, t: float, bob: float, _color: Color) -> void:
	var size: Vector2 = pic.size
	var white := Color(1.0, 1.0, 1.0)
	match kind:
		"lumi":  # Lumi (Crystal Saga): a little crystal fairy, glowing, with wings that flutter
			var flap := 0.06 * sin(t * 12.0)
			pic._poly([[0.42, 0.5 + bob], [0.12, 0.28 + bob - flap], [0.18, 0.62 + bob]], Color(0.8, 0.95, 1.0, 0.8))
			pic._poly([[0.58, 0.5 + bob], [0.88, 0.28 + bob - flap], [0.82, 0.62 + bob]], Color(0.8, 0.95, 1.0, 0.8))
			pic._circle(0.5, 0.52 + bob, 0.3, Color(0.55, 0.85, 1.0, 0.25))
			pic._poly([[0.5, 0.56 + bob], [0.64, 0.74 + bob], [0.5, 0.94 + bob], [0.36, 0.74 + bob]], Color(0.6, 0.85, 1.0))
			pic._circle(0.5, 0.44 + bob, 0.16, Color(0.95, 0.98, 1.0))
			pic._poly([[0.42, 0.3 + bob], [0.5, 0.12 + bob], [0.58, 0.3 + bob]], Color(0.55, 0.85, 1.0))
			pic._eye(0.44, 0.44 + bob, 0.045)
			pic._eye(0.56, 0.44 + bob, 0.045)
			pic.draw_arc(pic._p(0.5, 0.5 + bob), 0.05 * size.x, 0.3, PI - 0.3, 8, Color(0.3, 0.4, 0.6), 0.02 * size.x)
			pic._circle(0.5, 0.12 + bob, 0.03 + 0.01 * sin(t * 6.0), Color(1.0, 1.0, 0.7))
		"shard":  # a crystal shard (Crystal Saga), sparkling
			pic._poly([[0.5, 0.08 + bob], [0.7, 0.4 + bob], [0.6, 0.9 + bob], [0.4, 0.9 + bob], [0.3, 0.4 + bob]], Color(0.55, 0.85, 1.0))
			pic._poly([[0.5, 0.08 + bob], [0.56, 0.42 + bob], [0.5, 0.9 + bob], [0.3, 0.4 + bob]], Color(0.8, 0.95, 1.0))
			var tw := 0.5 + 0.5 * sin(t * 5.0)
			pic._circle(0.72, 0.22, 0.03 * tw + 0.01, white)
			pic._circle(0.26, 0.66, 0.025 * (1.0 - tw) + 0.01, white)
		"bigfire":  # BIG FIRE: a fireball with a flame on top
			var fl := 0.03 * sin(t * 14.0)
			pic._poly([[0.3, 0.55 + bob], [0.42, 0.1 + bob + fl], [0.5, 0.3 + bob], [0.6, 0.05 + bob - fl], [0.72, 0.55 + bob]], Color(1.0, 0.75, 0.2))
			pic._circle(0.5, 0.62 + bob, 0.28, Color(1.0, 0.45, 0.12))
			pic._circle(0.5, 0.64 + bob, 0.16, Color(1.0, 0.85, 0.35))
		"snowflake":  # ICE
			for k in 3:
				var a := k * PI / 3.0 + t * 0.4
				var d := Vector2(cos(a), sin(a)) * 0.38
				pic.draw_line(pic._p(0.5 - d.x, 0.5 - d.y), pic._p(0.5 + d.x, 0.5 + d.y), Color(0.75, 0.95, 1.0), 0.06 * size.x)
				for sgn in [-1.0, 1.0]:
					var tip: Vector2 = Vector2(0.5, 0.5) + d * 0.7 * float(sgn)
					var n: Vector2 = Vector2(-d.y, d.x) * 0.3
					pic.draw_line(pic._p(tip.x, tip.y), pic._p(tip.x + n.x + d.x * 0.25 * sgn, tip.y + n.y + d.y * 0.25 * sgn), Color(0.75, 0.95, 1.0), 0.04 * size.x)
					pic.draw_line(pic._p(tip.x, tip.y), pic._p(tip.x - n.x + d.x * 0.25 * sgn, tip.y - n.y + d.y * 0.25 * sgn), Color(0.75, 0.95, 1.0), 0.04 * size.x)
			pic._circle(0.5, 0.5, 0.07, white)
		"twin":  # TWIN SPARK: two sparks side by side
			for k in 2:
				var cx := 0.32 + k * 0.36
				var cy := 0.5 + (0.08 if k == 0 else -0.08) + bob
				var col := Color(0.85, 0.6, 1.0) if k == 0 else Color(0.6, 0.85, 1.0)
				var pts := []
				for i in 8:
					var a := i * TAU / 8.0 + t * 2.0
					var rr := 0.2 if i % 2 == 0 else 0.08
					pts.append([cx + cos(a) * rr, cy + sin(a) * rr])
				pic._poly(pts, col)
		"longsword", "spin", "mighty":  # sword tricks: a long sword, a sword in a whirl, a big golden sword
			var blade := Color(0.85, 0.92, 1.0) if kind != "mighty" else Color(1.0, 0.85, 0.3)
			var top := 0.06 if kind == "longsword" else 0.2
			var w := 0.05 if kind != "mighty" else 0.08
			if kind == "spin":
				pic.draw_arc(pic._p(0.5, 0.55), 0.36 * size.x, t * 4.0, t * 4.0 + PI * 1.5, 20, Color(0.5, 1.0, 0.8), 0.05 * size.x)
			pic._poly([[0.5 - w, 0.68], [0.5 - w, top + 0.06], [0.5, top], [0.5 + w, top + 0.06], [0.5 + w, 0.68]], blade)
			pic._poly([[0.32, 0.68], [0.68, 0.68], [0.68, 0.74], [0.32, 0.74]], Color(1.0, 0.8, 0.3))
			pic._poly([[0.46, 0.74], [0.54, 0.74], [0.54, 0.9], [0.46, 0.9]], Color(0.4, 0.28, 0.55))
			pic._circle(0.5, 0.92, 0.04, Color(0.5, 0.85, 1.0))
			if kind == "mighty":
				for k in 3:
					var a := t * 2.0 + k * TAU / 3.0
					pic._circle(0.5 + cos(a) * 0.3, 0.4 + sin(a) * 0.2, 0.035, Color(1.0, 1.0, 0.7))
		"windmill":  # Willowbrook's windmill, sails turning
			pic._poly([[0.38, 0.4], [0.62, 0.4], [0.68, 0.95], [0.32, 0.95]], Color(0.96, 0.92, 0.82))
			pic._poly([[0.34, 0.42], [0.5, 0.24], [0.66, 0.42]], Color(0.8, 0.35, 0.28))
			pic._poly([[0.45, 0.78], [0.55, 0.78], [0.55, 0.95], [0.45, 0.95]], Color(0.5, 0.32, 0.2))
			for k in 4:
				var a := t * 1.5 + k * PI * 0.5
				var d := Vector2(cos(a), sin(a))
				var n := Vector2(-d.y, d.x) * 0.06
				var c0 := Vector2(0.5, 0.42)
				pic._poly([[c0.x + n.x * 0.3, c0.y + n.y * 0.3], [c0.x + d.x * 0.4 + n.x, c0.y + d.y * 0.4 + n.y], [c0.x + d.x * 0.4 - n.x, c0.y + d.y * 0.4 - n.y]], Color(0.95, 0.9, 0.8))
			pic._circle(0.5, 0.42, 0.04, Color(0.75, 0.3, 0.25))
		"fountain":  # a sparkly fountain
			pic._poly([[0.12, 0.72], [0.88, 0.72], [0.8, 0.92], [0.2, 0.92]], Color(0.82, 0.82, 0.88))
			pic._poly([[0.17, 0.72], [0.83, 0.72], [0.8, 0.77], [0.2, 0.77]], Color(0.4, 0.7, 1.0))
			pic._poly([[0.46, 0.4], [0.54, 0.4], [0.56, 0.72], [0.44, 0.72]], Color(0.85, 0.85, 0.9))
			for k in 5:
				var ph := fmod(t * 0.8 + k * 0.2, 1.0)
				var dx := (k - 2) * 0.09 * ph
				pic._circle(0.5 + dx * 2.0, 0.36 - sin(ph * PI) * 0.22 + ph * 0.3, 0.035, Color(0.6, 0.85, 1.0))
		"rainbow":
			var cols: Array = [Color(1.0, 0.35, 0.35), Color(1.0, 0.65, 0.25), Color(1.0, 0.95, 0.35), Color(0.4, 0.9, 0.4), Color(0.4, 0.65, 1.0), Color(0.7, 0.45, 1.0)]
			for k in 6:
				pic.draw_arc(pic._p(0.5, 0.8), (0.42 - k * 0.05) * size.x, PI, TAU, 24, cols[k], 0.05 * size.x)
			for cl in [[0.14, 0.8, 0.09], [0.24, 0.84, 0.08], [0.76, 0.84, 0.08], [0.86, 0.8, 0.09]]:
				pic._circle(cl[0], cl[1], cl[2], white)
		"archer", "healer", "bard":  # the party's heroes (classes.gd): a little face with a hat and what they hold
			var hat := Color(0.35, 0.65, 0.35) if kind == "archer" else (Color(0.97, 0.97, 0.95) if kind == "healer" else Color(0.95, 0.45, 0.32))
			pic._poly([[0.3, 0.95], [0.34, 0.62 + bob], [0.66, 0.62 + bob], [0.7, 0.95]], hat)
			pic._circle(0.5, 0.46 + bob, 0.18, Color(1.0, 0.86, 0.74))
			pic._eye(0.44, 0.47 + bob, 0.035)
			pic._eye(0.56, 0.47 + bob, 0.035)
			pic.draw_arc(pic._p(0.5, 0.52 + bob), 0.05 * size.x, 0.3, PI - 0.3, 8, Color(0.5, 0.25, 0.25), 0.02 * size.x)
			match kind:
				"archer":
					pic._poly([[0.3, 0.36 + bob], [0.5, 0.2 + bob], [0.7, 0.36 + bob]], hat)
					pic._poly([[0.62, 0.24 + bob], [0.82, 0.08 + bob], [0.66, 0.3 + bob]], Color(1.0, 0.3, 0.3))
					pic.draw_arc(pic._p(0.84, 0.6), 0.22 * size.x, -PI * 0.5, PI * 0.5, 14, Color(0.6, 0.42, 0.26), 0.035 * size.x)
					pic.draw_line(pic._p(0.84, 0.38), pic._p(0.84, 0.82), Color(0.95, 0.95, 0.9), 0.012 * size.x)
				"healer":
					pic._poly([[0.28, 0.42 + bob], [0.5, 0.18 + bob], [0.72, 0.42 + bob], [0.66, 0.34 + bob], [0.34, 0.34 + bob]], hat)
					pic._poly([[0.47, 0.72], [0.53, 0.72], [0.53, 0.86], [0.47, 0.86]], Color(0.92, 0.32, 0.38))
					pic._poly([[0.43, 0.76], [0.57, 0.76], [0.57, 0.82], [0.43, 0.82]], Color(0.92, 0.32, 0.38))
					var gl := 0.5 + 0.5 * sin(t * 4.0)
					pic._circle(0.84, 0.3, 0.07 + 0.02 * gl, Color(1.0, 0.6, 0.7, 0.8))
					pic.draw_line(pic._p(0.84, 0.36), pic._p(0.8, 0.9), Color(0.6, 0.42, 0.26), 0.03 * size.x)
				_:
					pic._circle(0.5, 0.3 + bob, 0.14, hat)
					pic._circle(0.62, 0.24 + bob, 0.04, Color(1.0, 0.85, 0.4))
					pic._circle(0.82, 0.74, 0.11, Color(0.75, 0.5, 0.28))
					pic.draw_line(pic._p(0.78, 0.64), pic._p(0.66, 0.32), Color(0.55, 0.35, 0.2), 0.03 * size.x)
					var nt := fmod(t * 0.8, 1.0)
					pic._circle(0.18, 0.4 - nt * 0.25, 0.04, Color(1.0, 0.85, 0.35, 1.0 - nt))
					pic.draw_line(pic._p(0.22, 0.4 - nt * 0.25), pic._p(0.22, 0.26 - nt * 0.25), Color(1.0, 0.85, 0.35, 1.0 - nt), 0.015 * size.x)
		"starrain":  # STAR RAIN: stars falling from a little cloud
			for k in 3:
				var ph := fmod(t * 0.9 + k * 0.33, 1.0)
				var cx := 0.28 + k * 0.22
				var cy := 0.36 + ph * 0.55
				var pts := []
				for i in 10:
					var a := i * TAU / 10.0 - PI * 0.5
					var rr := 0.09 if i % 2 == 0 else 0.04
					pts.append([cx + cos(a) * rr, cy + sin(a) * rr])
				pic._poly(pts, Color(1.0, 0.92, 0.4, 1.0 - ph * 0.5))
			for cl in [[0.34, 0.2, 0.12], [0.5, 0.16, 0.15], [0.66, 0.2, 0.12]]:
				pic._circle(cl[0], cl[1] + bob, cl[2], Color(0.85, 0.85, 0.95))
		"bubble":  # BUBBLE: a shiny bubble round a little hero
			pic._circle(0.5, 0.52 + bob, 0.36, Color(0.6, 0.85, 1.0, 0.35))
			pic.draw_arc(pic._p(0.5, 0.52 + bob), 0.36 * size.x, 0.0, TAU, 32, Color(0.75, 0.92, 1.0), 0.025 * size.x)
			pic.draw_arc(pic._p(0.5, 0.52 + bob), 0.26 * size.x, PI * 1.1, PI * 1.45, 8, white, 0.03 * size.x)
			pic._circle(0.5, 0.48 + bob, 0.1, Color(1.0, 0.86, 0.74))
			pic._poly([[0.4, 0.72 + bob], [0.44, 0.58 + bob], [0.56, 0.58 + bob], [0.6, 0.72 + bob]], Color(0.5, 0.7, 1.0))
		"guardian":  # a crystal guardian: a big stone giant with a glowing crystal on his chest, in grumpy mist
			pic._circle(0.5, 0.55, 0.42, Color(0.35, 0.15, 0.5, 0.35))
			pic._poly([[0.28, 0.92], [0.24, 0.45 + bob], [0.76, 0.45 + bob], [0.72, 0.92]], Color(0.55, 0.5, 0.62))
			pic._poly([[0.36, 0.45 + bob], [0.38, 0.2 + bob], [0.62, 0.2 + bob], [0.64, 0.45 + bob]], Color(0.62, 0.58, 0.7))
			pic._poly([[0.16, 0.5 + bob], [0.24, 0.45 + bob], [0.26, 0.75 + bob], [0.14, 0.72 + bob]], Color(0.5, 0.45, 0.58))
			pic._poly([[0.84, 0.5 + bob], [0.76, 0.45 + bob], [0.74, 0.75 + bob], [0.86, 0.72 + bob]], Color(0.5, 0.45, 0.58))
			var gw := 0.5 + 0.5 * sin(t * 3.0)
			pic._circle(0.44, 0.31 + bob, 0.035, Color(1.0, 0.85 * gw + 0.15, 0.4))
			pic._circle(0.56, 0.31 + bob, 0.035, Color(1.0, 0.85 * gw + 0.15, 0.4))
			pic._poly([[0.5, 0.5 + bob], [0.58, 0.62 + bob], [0.5, 0.76 + bob], [0.42, 0.62 + bob]], Color(0.55, 0.85, 1.0))
			pic._poly([[0.5, 0.5 + bob], [0.53, 0.62 + bob], [0.5, 0.76 + bob], [0.46, 0.62 + bob]], Color(0.85, 0.97, 1.0))
