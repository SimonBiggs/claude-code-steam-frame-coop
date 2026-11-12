extends RefCounted
## Snowman Maker's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.
## (Tumble is the shared "penguin"; the gifts reuse "scarf", "carrot", "tophat"; the snow globe is Fruit Catch's.)

const NAMES: Array[String] = ["sunbeam", "snowslide", "sparklebuttons", "snowboots"]

const SNOW := Color(0.97, 0.98, 1.0)
const FROST := Color(0.55, 0.65, 0.85)
const COAL := Color(0.15, 0.15, 0.2)


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"sunbeam":  # a smiling sun peeking from a cloud, a beam onto a little melting snowball
			pic._poly([[0.42, 0.3 + bob], [0.62, 0.3 + bob], [0.82, 0.9], [0.22, 0.9]], Color(1.0, 0.85, 0.4, 0.45))  # the beam
			for k in 8:
				var a := float(k) * TAU / 8.0 + t * 0.6
				var c := Vector2(0.52, 0.24 + bob)
				pic._poly([[c.x + cos(a - 0.15) * 0.15, c.y + sin(a - 0.15) * 0.15], [c.x + cos(a) * 0.25, c.y + sin(a) * 0.25],
					[c.x + cos(a + 0.15) * 0.15, c.y + sin(a + 0.15) * 0.15]], Color(1.0, 0.7, 0.15))
			pic._circle(0.52, 0.24 + bob, 0.14, Color(1.0, 0.82, 0.2))
			pic._eye(0.47, 0.22 + bob, 0.025)
			pic._eye(0.57, 0.22 + bob, 0.025)
			pic._poly([[0.47, 0.29 + bob], [0.57, 0.29 + bob], [0.52, 0.33 + bob]], Color(0.85, 0.35, 0.2))
			pic._circle(0.27, 0.3 + bob, 0.09, Color.WHITE)  # the cloud it peeks from
			pic._circle(0.36, 0.33 + bob, 0.08, Color.WHITE)
			pic._circle(0.2, 0.35 + bob, 0.07, Color.WHITE)
			pic._circle(0.52, 0.88, 0.26, Color(0.6, 0.8, 1.0, 0.6))  # a puddle
			pic._circle(0.52, 0.78, 0.12, FROST)  # the snowball, getting small
			pic._circle(0.52, 0.78, 0.105, SNOW)
			pic._circle(0.62, 0.86, 0.025, Color(0.6, 0.8, 1.0))  # drips
			pic._circle(0.42, 0.87, 0.02, Color(0.6, 0.8, 1.0))
		"snowslide":  # a giant snowball rolling down a hill, puffs of snow behind it
			pic._poly([[0.0, 0.45], [1.0, 0.95], [0.0, 0.95]], Color(0.85, 0.9, 1.0))  # the hill
			pic._poly([[0.0, 0.45], [1.0, 0.95], [1.0, 1.0], [0.0, 1.0]], Color(0.62, 0.36, 1.0, 0.35))
			var x := 0.3 + fmod(t * 0.15, 0.4)
			var y := 0.45 + (x - 0.0) * 0.5 - 0.2
			pic._circle(x - 0.2, y + 0.06, 0.06, Color.WHITE)  # puffs
			pic._circle(x - 0.3, y + 0.1, 0.045, Color.WHITE)
			pic._circle(x, y, 0.2, FROST)
			pic._circle(x, y, 0.18, SNOW)
			var a := -t * 3.0  # it rolls
			for k in 3:
				var q := a + float(k) * TAU / 3.0
				pic._circle(x + cos(q) * 0.1, y + sin(q) * 0.1, 0.022, FROST)
		"sparklebuttons":  # a snowman's tummy with three shiny golden buttons and sparkles
			pic._circle(0.5, 0.62 + bob, 0.34, FROST)
			pic._circle(0.5, 0.62 + bob, 0.32, SNOW)
			for k in 3:
				var by := 0.42 + k * 0.17 + bob
				pic._circle(0.5, by, 0.065, Color(0.85, 0.6, 0.1))
				pic._circle(0.5, by, 0.05, Color(1.0, 0.85, 0.25))
				pic._circle(0.48, by - 0.02, 0.015, Color.WHITE)
			for k in 4:  # twinkles
				var a := float(k) * TAU / 4.0 + t
				var s := 0.035 + 0.015 * sin(t * 4.0 + k)
				var c := Vector2(0.5 + cos(a) * 0.3, 0.55 + bob + sin(a) * 0.22)
				pic._poly([[c.x, c.y - s * 2.0], [c.x + s * 0.6, c.y], [c.x, c.y + s * 2.0], [c.x - s * 0.6, c.y]], Color(1.0, 0.95, 0.5))
				pic._poly([[c.x - s * 2.0, c.y], [c.x, c.y + s * 0.6], [c.x + s * 2.0, c.y], [c.x, c.y - s * 0.6]], Color(1.0, 0.95, 0.5))
		"snowboots":  # two green snow boots with white fluffy tops and speed lines
			for k in 2:
				var ox := 0.18 + k * 0.34
				var oy := 0.1 * k + bob
				var g := Color(0.3, 0.85, 0.55).darkened(0.12 * k)
				pic._poly([[ox, 0.3 + oy], [ox + 0.2, 0.3 + oy], [ox + 0.2, 0.62 + oy], [ox + 0.34, 0.66 + oy],
					[ox + 0.36, 0.78 + oy], [ox, 0.78 + oy]], g)
				pic._poly([[ox - 0.01, 0.78 + oy], [ox + 0.37, 0.78 + oy], [ox + 0.37, 0.82 + oy], [ox - 0.01, 0.82 + oy]], COAL)
				pic._circle(ox + 0.04, 0.3 + oy, 0.06, Color.WHITE)
				pic._circle(ox + 0.1, 0.28 + oy, 0.07, Color.WHITE)
				pic._circle(ox + 0.17, 0.3 + oy, 0.06, Color.WHITE)
			for k in 3:  # whoosh lines
				var ly := 0.45 + k * 0.12 + bob
				pic._poly([[0.0, ly], [0.12, ly - 0.012], [0.12, ly + 0.012]], Color(1.0, 1.0, 1.0, 0.8))
