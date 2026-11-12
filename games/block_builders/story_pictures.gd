extends RefCounted
## Block Builders' story card pictures (Puff's block gifts). core/story_pictures.gd finds this file by itself, so a
## game adds a picture here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit
## box: pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r), t = the picture's clock,
## bob = its gentle bob, color = the card's colour. The rest are other games' pictures (robot, gust, quake, house,
## tower, windmill, lighthouse, treehouse, castle, cloud, daisy, sun, pumpkin, snowflake).

const NAMES: Array[String] = ["stickybrick", "bigbrick", "blockbox", "jumpboots"]


static func _brick(pic, x: float, y: float, w: float, h: float, col: Color) -> void:
	pic._poly([[x, y], [x + w, y], [x + w, y + h], [x, y + h]], col.darkened(0.15))
	pic._poly([[x, y], [x + w, y], [x + w - 0.03, y + h * 0.35], [x + 0.03, y + h * 0.35]], col.lightened(0.15))
	for k in 2:  # the studs on top
		var sx := x + w * (0.3 + 0.4 * k)
		pic._poly([[sx - 0.05, y - 0.05], [sx + 0.05, y - 0.05], [sx + 0.05, y], [sx - 0.05, y]], col.lightened(0.25))


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"stickybrick":  # a brick with green goo dripping off it
			var drip := 0.06 + 0.05 * absf(sin(t * 2.0))
			_brick(pic, 0.22, 0.35 + bob, 0.56, 0.3, Color(1.0, 0.55, 0.25))
			var goo := Color(0.45, 0.95, 0.3)
			pic._poly([[0.2, 0.32 + bob], [0.8, 0.32 + bob], [0.78, 0.42 + bob], [0.22, 0.42 + bob]], goo)
			for dx in [0.3, 0.52, 0.7]:
				pic._poly([[dx - 0.03, 0.4 + bob], [dx + 0.03, 0.4 + bob], [dx + 0.02, 0.5 + bob + drip], [dx - 0.02, 0.5 + bob + drip]], goo)
				pic._circle(dx, 0.5 + bob + drip, 0.035, goo)
			pic._eye(0.4, 0.53 + bob, 0.035)
			pic._eye(0.6, 0.53 + bob, 0.035)
		"bigbrick":  # a big brick next to a small one, with a sparkle
			_brick(pic, 0.12, 0.62 + bob, 0.22, 0.14, Color(0.4, 0.75, 1.0))
			_brick(pic, 0.38, 0.32 + bob, 0.5, 0.44, color)
			var tw := 0.03 + 0.02 * absf(sin(t * 4.0))
			pic._poly([[0.82, 0.16 - tw * 2.0], [0.82 + tw, 0.16], [0.82, 0.16 + tw * 2.0], [0.82 - tw, 0.16]], Color(1.0, 0.95, 0.6))
		"blockbox":  # an open box full of bricks
			pic._poly([[0.18, 0.5], [0.82, 0.5], [0.78, 0.86], [0.22, 0.86]], Color(0.85, 0.6, 0.3))
			_brick(pic, 0.24, 0.34 + bob, 0.2, 0.18, Color(1.0, 0.4, 0.4))
			_brick(pic, 0.44, 0.28 + bob * 1.3, 0.2, 0.22, Color(0.4, 0.8, 1.0))
			_brick(pic, 0.6, 0.36 + bob, 0.18, 0.16, Color(1.0, 0.85, 0.3))
			pic._poly([[0.18, 0.5], [0.82, 0.5], [0.8, 0.58], [0.2, 0.58]], Color(0.95, 0.72, 0.4))
			pic._poly([[0.1, 0.42], [0.18, 0.5], [0.2, 0.58], [0.06, 0.48]], Color(0.75, 0.5, 0.25))
			pic._poly([[0.9, 0.42], [0.82, 0.5], [0.8, 0.58], [0.94, 0.48]], Color(0.75, 0.5, 0.25))
		"jumpboots":  # a pink boot bouncing on a spring
			var h := absf(sin(t * 3.5)) * 0.12
			var y := 0.5 - h + bob
			for k in 4:  # the coil
				var cy := y + 0.2 + k * (0.06 + h * 0.25)
				pic._poly([[0.36, cy], [0.6, cy + 0.03], [0.6, cy + 0.05], [0.36, cy + 0.02]], Color(0.8, 0.82, 0.88))
			pic._poly([[0.36, y - 0.22], [0.54, y - 0.22], [0.56, y + 0.02], [0.76, y + 0.06], [0.76, y + 0.18], [0.34, y + 0.18]], color)
			pic._poly([[0.36, y + 0.14], [0.76, y + 0.14], [0.76, y + 0.2], [0.34, y + 0.2]], color.darkened(0.3))
			pic._circle(0.46, y - 0.08, 0.03, Color(1, 1, 1, 0.8))
