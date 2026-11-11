extends RefCounted
## Whack A Mole's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.

const NAMES: Array[String] = ["farmer", "mole", "bunny", "lettuce", "carrot", "pumpkin", "sunflower", "strawberry", "corn", "melon", "apple",
	"bighammer", "sleepydust", "goldglove", "boinghammer", "carrotbag", "stampede", "moleden"]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	var size: Vector2 = pic.size
	var white := Color(1.0, 1.0, 1.0)
	match kind:
		"farmer":  # Farmer Fig (Whack-a-Mole): a round face under a big straw hat, a sprig on top
			pic._circle(0.5, 0.6 + bob, 0.26, Color(0.98, 0.78, 0.6))
			pic._poly([[0.08, 0.42 + bob], [0.92, 0.42 + bob], [0.8, 0.36 + bob], [0.2, 0.36 + bob]], Color(0.95, 0.8, 0.35))
			pic._poly([[0.28, 0.37 + bob], [0.72, 0.37 + bob], [0.66, 0.16 + bob], [0.34, 0.16 + bob]], Color(0.95, 0.8, 0.35))
			pic._poly([[0.28, 0.33 + bob], [0.72, 0.33 + bob], [0.71, 0.28 + bob], [0.29, 0.28 + bob]], color)
			pic._eye(0.41, 0.58 + bob, 0.05)
			pic._eye(0.59, 0.58 + bob, 0.05)
			pic.draw_arc(pic._p(0.5, 0.66 + bob), 0.09 * size.x, 0.3, PI - 0.3, 10, Color(0.4, 0.15, 0.12), 0.022 * size.x)
			pic._circle(0.33, 0.68 + bob, 0.04, Color(1.0, 0.5, 0.55, 0.7))
			pic._circle(0.67, 0.68 + bob, 0.04, Color(1.0, 0.5, 0.55, 0.7))
			pic.draw_line(pic._p(0.62, 0.17 + bob), pic._p(0.7, 0.04 + bob), Color(0.3, 0.6, 0.25), 0.025 * size.x)
			pic._circle(0.72, 0.05 + bob, 0.04, Color(0.4, 0.8, 0.3))
		"mole", "bunny":  # a cheeky mole (fur = color) or a white bunny peeking from a hole
			pic._poly([[0.12, 0.82], [0.88, 0.82], [0.8, 0.94], [0.2, 0.94]], Color(0.35, 0.22, 0.12))
			var fur := color if kind == "mole" else Color(0.97, 0.97, 1.0)
			if kind == "bunny":
				for x in [0.38, 0.62]:
					pic._poly([[x - 0.06, 0.35 + bob], [x, 0.02 + bob], [x + 0.06, 0.35 + bob]], fur)
					pic._poly([[x - 0.03, 0.33 + bob], [x, 0.1 + bob], [x + 0.03, 0.33 + bob]], Color(1.0, 0.7, 0.78))
			pic._circle(0.5, 0.58 + bob, 0.27, fur)
			pic._poly([[0.23, 0.6 + bob], [0.77, 0.6 + bob], [0.77, 0.85], [0.23, 0.85]], fur)
			pic._circle(0.5, 0.68 + bob, 0.14, fur.lightened(0.35))
			pic._eye(0.41, 0.5 + bob, 0.055)
			pic._eye(0.59, 0.5 + bob, 0.055)
			pic._circle(0.5, 0.6 + bob, 0.05, Color(1.0, 0.55, 0.65))
			if kind == "mole":
				pic._poly([[0.46, 0.66 + bob], [0.54, 0.66 + bob], [0.54, 0.71 + bob], [0.46, 0.71 + bob]], white)
		"lettuce", "carrot", "pumpkin", "sunflower", "strawberry", "corn", "melon", "apple":
			_veg(pic, kind, t, bob, color)
		"bighammer", "sleepydust", "goldglove", "boinghammer", "carrotbag", "stampede", "moleden":
			_deep(pic, kind, t, bob)


## A soft mallet (Fig's hammer gifts): head centre (x, y), head half-length hl, tilted by `tilt`.
static func _mallet(pic, x: float, y: float, hl: float, tilt: float, head: Color) -> void:
	var size: Vector2 = pic.size
	var d := Vector2(cos(tilt), sin(tilt))
	var n := Vector2(-d.y, d.x)
	pic.draw_line(pic._p(x, y), pic._p(x + n.x * 0.5, y + n.y * 0.5), Color(0.95, 0.75, 0.35), 0.06 * size.x)
	var a := Vector2(x, y) - d * hl
	var b := Vector2(x, y) + d * hl
	var w := hl * 0.75
	pic._poly([[a.x - n.x * w, a.y - n.y * w], [b.x - n.x * w, b.y - n.y * w], [b.x + n.x * w, b.y + n.y * w], [a.x + n.x * w, a.y + n.y * w]], head)
	pic._circle(a.x, a.y, w, Color(1.0, 0.97, 0.9))
	pic._circle(b.x, b.y, w, Color(1.0, 0.97, 0.9))


## The second pass's pictures (deep.gd): Fig's hammer gifts, the stampede, the holiday garden.
static func _deep(pic, kind: String, t: float, bob: float) -> void:
	var size: Vector2 = pic.size
	var fur := Color(0.55, 0.36, 0.24)
	match kind:
		"bighammer":  # a huge soft mallet, swinging
			_mallet(pic, 0.5, 0.36 + bob, 0.3, -0.2 + sin(t * 3.0) * 0.15, Color(1.0, 0.35, 0.45))
		"sleepydust":  # a sleepy moon sprinkling sparkles, zzz
			pic._circle(0.42, 0.42 + bob, 0.26, Color(1.0, 0.92, 0.55))
			pic._circle(0.54, 0.36 + bob, 0.22, Color(0.25, 0.3, 0.6))
			pic.draw_arc(pic._p(0.33, 0.48 + bob), 0.05 * size.x, 0.2, PI - 0.2, 8, Color(0.4, 0.3, 0.2), 0.02 * size.x)
			for k in 6:
				var y := fmod(t * 0.3 + k * 0.17, 1.0)
				pic._circle(0.3 + k * 0.08, 0.6 + y * 0.35, 0.025, Color(0.75, 0.8, 1.0, 1.0 - y))
			for k in 3:
				var z := Vector2(0.72 + k * 0.07, 0.3 - k * 0.09 + bob)
				pic._poly([[z.x - 0.03, z.y - 0.03], [z.x + 0.03, z.y - 0.03], [z.x - 0.03, z.y + 0.03], [z.x + 0.03, z.y + 0.03]], Color(0.75, 0.8, 1.0))
		"goldglove":  # a big golden glove with a sparkle
			var g := Color(1.0, 0.8, 0.2)
			pic._circle(0.5, 0.58 + bob, 0.24, g)
			for k in 4:
				pic._poly([[0.31 + k * 0.1, 0.5 + bob], [0.39 + k * 0.1, 0.5 + bob], [0.39 + k * 0.1, 0.2 + bob], [0.31 + k * 0.1, 0.2 + bob]], g)
				pic._circle(0.35 + k * 0.1, 0.2 + bob, 0.04, g)
			pic._poly([[0.22, 0.6 + bob], [0.3, 0.45 + bob], [0.36, 0.62 + bob]], g)
			pic._poly([[0.36, 0.78 + bob], [0.64, 0.78 + bob], [0.64, 0.92 + bob], [0.36, 0.92 + bob]], Color(0.95, 0.95, 1.0))
			var tw := 0.06 + 0.03 * sin(t * 6.0)
			pic._poly([[0.8, 0.2 - tw], [0.82, 0.18], [0.8 + tw, 0.2], [0.82, 0.22], [0.8, 0.2 + tw], [0.78, 0.22], [0.8 - tw, 0.2], [0.78, 0.18]], Color.WHITE)
		"boinghammer":  # a springy green mallet with boing lines
			var hop := absf(sin(t * 4.0)) * 0.08
			_mallet(pic, 0.5, 0.38 - hop + bob, 0.22, 0.0, Color(0.4, 0.9, 0.6))
			for k in 3:
				pic.draw_arc(pic._p(0.5, 0.9), (0.1 + 0.08 * k) * size.x, PI + 0.4, TAU - 0.4, 12, Color(0.4, 0.9, 0.6, 0.8 - 0.2 * k), 0.02 * size.x)
		"carrotbag":  # a sack full of carrots
			for a in [-0.16, 0.0, 0.16]:
				pic._poly([[0.44 + a, 0.42 + bob], [0.56 + a, 0.42 + bob], [0.5 + a, 0.12 + bob]], Color(1.0, 0.55, 0.15))
				pic._poly([[0.48 + a, 0.14 + bob], [0.52 + a, 0.14 + bob], [0.5 + a, 0.02 + bob]], Color(0.35, 0.75, 0.3))
			pic._circle(0.5, 0.66 + bob, 0.28, Color(0.8, 0.62, 0.38))
			pic._poly([[0.26, 0.42 + bob], [0.74, 0.42 + bob], [0.7, 0.5 + bob], [0.3, 0.5 + bob]], Color(0.65, 0.48, 0.28))
		"stampede":  # a line of little moles running, dust behind them
			for k in 3:
				var x := 0.22 + k * 0.28
				var h := absf(sin(t * 8.0 + k)) * 0.05
				pic._circle(x - 0.1, 0.84, 0.05, Color(0.85, 0.75, 0.6, 0.6))
				pic._circle(x, 0.62 - h, 0.12, fur)
				pic._eye(x + 0.04, 0.58 - h, 0.03)
				pic._circle(x + 0.11, 0.64 - h, 0.03, Color(1.0, 0.55, 0.65))
				pic._poly([[x - 0.06, 0.72 - h], [x - 0.02, 0.72 - h], [x - 0.04, 0.8], [x - 0.08, 0.8]], fur.darkened(0.2))
				pic._poly([[x + 0.03, 0.72 - h], [x + 0.07, 0.72 - h], [x + 0.08, 0.8], [x + 0.04, 0.8]], fur.darkened(0.2))
		"moleden":  # a happy mole in a striped deckchair with a sun hat
			pic._poly([[0.2, 0.9], [0.3, 0.35], [0.4, 0.35], [0.32, 0.9]], Color(0.75, 0.55, 0.35))
			pic._poly([[0.62, 0.9], [0.7, 0.62], [0.78, 0.62], [0.72, 0.9]], Color(0.75, 0.55, 0.35))
			for k in 4:
				var c := Color(0.95, 0.4, 0.35) if k % 2 == 0 else Color(1.0, 0.97, 0.92)
				pic._poly([[0.3 + k * 0.03, 0.35 + k * 0.08], [0.38 + k * 0.03, 0.35 + k * 0.08], [0.41 + k * 0.03, 0.43 + k * 0.08], [0.33 + k * 0.03, 0.43 + k * 0.08]], c)
			pic._poly([[0.42, 0.66], [0.8, 0.62], [0.8, 0.7], [0.42, 0.74]], Color(0.95, 0.4, 0.35))
			pic._circle(0.52, 0.5 + bob, 0.15, fur)
			pic._poly([[0.42, 0.55 + bob], [0.66, 0.55 + bob], [0.68, 0.68], [0.42, 0.68]], fur)
			pic._eye(0.5, 0.48 + bob, 0.03)
			pic._eye(0.58, 0.48 + bob, 0.03)
			pic._circle(0.55, 0.55 + bob, 0.03, Color(1.0, 0.55, 0.65))
			pic._poly([[0.3, 0.38 + bob], [0.74, 0.38 + bob], [0.66, 0.33 + bob], [0.38, 0.33 + bob]], Color(0.98, 0.85, 0.45))
			pic._poly([[0.42, 0.34 + bob], [0.62, 0.34 + bob], [0.6, 0.24 + bob], [0.44, 0.24 + bob]], Color(0.98, 0.85, 0.45))
			pic._circle(0.84, 0.18, 0.08, Color(1.0, 0.85, 0.3))


## Farmer Fig's crops (Whack-a-Mole garden beds).
static func _veg(pic, v: String, t: float, bob: float, _color: Color) -> void:
	var size: Vector2 = pic.size
	var leaf := Color(0.35, 0.75, 0.3)
	match v:
		"lettuce":
			for b in [[0.32, 0.6, 0.2], [0.68, 0.6, 0.2], [0.5, 0.5, 0.24], [0.5, 0.68, 0.2]]:
				pic._circle(b[0], b[1] + bob, b[2], Color(0.45, 0.85, 0.35).darkened(0.1 * b[2]))
			pic._circle(0.5, 0.56 + bob, 0.12, Color(0.75, 0.95, 0.5))
		"carrot":
			pic._poly([[0.36, 0.3 + bob], [0.64, 0.3 + bob], [0.5, 0.95 + bob]], Color(1.0, 0.55, 0.15))
			for a in [-0.12, 0.0, 0.12]:
				pic._poly([[0.47, 0.3 + bob], [0.53, 0.3 + bob], [0.5 + a, 0.06 + bob]], leaf)
		"pumpkin":
			for b in [[0.3, 0.2], [0.7, 0.2], [0.5, 0.25]]:
				pic._circle(b[0], 0.6 + bob, b[1], Color(1.0, 0.5, 0.1).lightened(0.1 if b[0] == 0.5 else 0.0))
			pic._poly([[0.46, 0.38 + bob], [0.54, 0.38 + bob], [0.56, 0.24 + bob], [0.5, 0.24 + bob]], Color(0.4, 0.55, 0.2))
		"sunflower":
			pic.draw_line(pic._p(0.5, 0.55), pic._p(0.5, 0.98), leaf, 0.05 * size.x)
			for i in 10:
				var a := i * TAU / 10.0 + t * 0.4
				pic._circle(0.5 + cos(a) * 0.2, 0.4 + sin(a) * 0.2 + bob, 0.09, Color(1.0, 0.85, 0.2))
			pic._circle(0.5, 0.4 + bob, 0.14, Color(0.5, 0.3, 0.12))
		"strawberry":
			pic._poly([[0.22, 0.4 + bob], [0.78, 0.4 + bob], [0.72, 0.6 + bob], [0.5, 0.92 + bob], [0.28, 0.6 + bob]], Color(0.95, 0.2, 0.3))
			for p in [[0.38, 0.5], [0.6, 0.5], [0.5, 0.62], [0.42, 0.74], [0.58, 0.72]]:
				pic._circle(p[0], p[1] + bob, 0.018, Color(1.0, 0.9, 0.5))
			pic._poly([[0.3, 0.4 + bob], [0.5, 0.28 + bob], [0.7, 0.4 + bob], [0.5, 0.46 + bob]], leaf)
		"corn":
			pic._poly([[0.38, 0.2 + bob], [0.62, 0.2 + bob], [0.64, 0.75 + bob], [0.36, 0.75 + bob]], Color(1.0, 0.88, 0.3))
			for y in 5:
				for x in 2:
					pic._circle(0.45 + x * 0.1, 0.27 + y * 0.1 + bob, 0.035, Color(1.0, 0.95, 0.5))
			pic._poly([[0.36, 0.95 + bob], [0.28, 0.4 + bob], [0.46, 0.75 + bob]], leaf)
			pic._poly([[0.64, 0.95 + bob], [0.72, 0.4 + bob], [0.54, 0.75 + bob]], leaf)
		"melon":
			pic._circle(0.5, 0.58 + bob, 0.34, Color(0.3, 0.65, 0.3))
			for x in [-0.2, 0.0, 0.2]:
				pic.draw_line(pic._p(0.5 + x * 0.6, 0.26 + bob), pic._p(0.5 + x, 0.58 + bob), Color(0.55, 0.85, 0.45), 0.03 * size.x)
				pic.draw_line(pic._p(0.5 + x, 0.58 + bob), pic._p(0.5 + x * 0.6, 0.9 + bob), Color(0.55, 0.85, 0.45), 0.03 * size.x)
		"apple":
			pic._circle(0.39, 0.6 + bob, 0.24, Color(0.9, 0.15, 0.2))
			pic._circle(0.61, 0.6 + bob, 0.24, Color(0.9, 0.15, 0.2))
			pic._circle(0.38, 0.52 + bob, 0.07, Color(1.0, 0.5, 0.5, 0.7))
			pic.draw_line(pic._p(0.5, 0.4 + bob), pic._p(0.54, 0.22 + bob), Color(0.45, 0.28, 0.15), 0.03 * size.x)
			pic._poly([[0.54, 0.28 + bob], [0.72, 0.2 + bob], [0.6, 0.34 + bob]], leaf)
