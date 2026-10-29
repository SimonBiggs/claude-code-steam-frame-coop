extends RefCounted
## Dragon Rider's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.
## (Sky bunnies use Whack-a-Mole's "bunny": any picture works in every game.)

const NAMES: Array[String] = ["dragon", "bell", "ribbon", "crown", "flowerchain"]

const SCALE := Color(0.95, 0.45, 0.3)
const BELLY := Color(1.0, 0.85, 0.55)
const GOLD := Color(1.0, 0.8, 0.2)


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"dragon":  # Sunny: a round, smiling dragon face with little horns, flapping wings behind
			var flap := sin(t * 4.0) * 0.06
			pic._poly([[0.3, 0.5 + bob], [0.04, 0.22 + flap + bob], [0.12, 0.52 + bob], [0.06, 0.6 + bob], [0.3, 0.62 + bob]], SCALE.darkened(0.25))
			pic._poly([[0.7, 0.5 + bob], [0.96, 0.22 + flap + bob], [0.88, 0.52 + bob], [0.94, 0.6 + bob], [0.7, 0.62 + bob]], SCALE.darkened(0.25))
			pic._poly([[0.36, 0.3 + bob], [0.32, 0.12 + bob], [0.44, 0.26 + bob]], Color(1.0, 0.95, 0.8))  # horns
			pic._poly([[0.64, 0.3 + bob], [0.68, 0.12 + bob], [0.56, 0.26 + bob]], Color(1.0, 0.95, 0.8))
			pic._circle(0.5, 0.48 + bob, 0.24, SCALE)
			pic._circle(0.5, 0.62 + bob, 0.15, BELLY)  # snout
			pic._circle(0.44, 0.6 + bob, 0.02, SCALE.darkened(0.4))  # nostrils
			pic._circle(0.56, 0.6 + bob, 0.02, SCALE.darkened(0.4))
			pic._eye(0.41, 0.42 + bob, 0.05)
			pic._eye(0.59, 0.42 + bob, 0.05)
			pic._poly([[0.42, 0.68 + bob], [0.58, 0.68 + bob], [0.5, 0.73 + bob]], Color(0.85, 0.3, 0.35))
			for i in 3:  # a little puff of smoke
				var y := 0.62 - fmod(t * 0.5 + i * 0.33, 1.0) * 0.3
				pic._circle(0.8 + i * 0.03, y + bob, 0.03 + i * 0.01, Color(1, 1, 1, 0.5))
		"bell":  # a golden bell (the ribbon in `color`)
			var swing := sin(t * 3.0) * 0.04
			pic._poly([[0.44 + swing, 0.2 + bob], [0.56 + swing, 0.2 + bob], [0.56 + swing, 0.28 + bob], [0.44 + swing, 0.28 + bob]], color)
			pic._circle(0.5 + swing, 0.42 + bob, 0.16, GOLD)
			pic._poly([[0.34 + swing, 0.42 + bob], [0.66 + swing, 0.42 + bob], [0.76 + swing, 0.7 + bob], [0.24 + swing, 0.7 + bob]], GOLD)
			pic._poly([[0.22 + swing, 0.68 + bob], [0.78 + swing, 0.68 + bob], [0.78 + swing, 0.74 + bob], [0.22 + swing, 0.74 + bob]], GOLD.darkened(0.2))
			pic._circle(0.5 + swing * 2.0, 0.79 + bob, 0.05, GOLD.darkened(0.3))
			pic._circle(0.42 + swing, 0.44 + bob, 0.04, Color(1, 1, 1, 0.5))
		"ribbon":  # a winner's rosette (in `color`)
			pic._poly([[0.4, 0.55 + bob], [0.3, 0.9 + bob], [0.42, 0.84 + bob], [0.48, 0.92 + bob]], color.darkened(0.2))
			pic._poly([[0.6, 0.55 + bob], [0.7, 0.9 + bob], [0.58, 0.84 + bob], [0.52, 0.92 + bob]], color.darkened(0.2))
			for i in 10:
				var a := TAU * i / 10.0 + t * 0.5
				pic._circle(0.5 + cos(a) * 0.2, 0.42 + sin(a) * 0.2 + bob, 0.09, color)
			pic._circle(0.5, 0.42 + bob, 0.15, Color.WHITE)
			pic._circle(0.5, 0.42 + bob, 0.11, GOLD)
		"crown":  # the Storm King's crown, won
			pic._poly([[0.2, 0.7 + bob], [0.8, 0.7 + bob], [0.84, 0.32 + bob], [0.67, 0.5 + bob], [0.5, 0.26 + bob], [0.33, 0.5 + bob], [0.16, 0.32 + bob]], GOLD)
			pic._poly([[0.2, 0.7 + bob], [0.8, 0.7 + bob], [0.8, 0.78 + bob], [0.2, 0.78 + bob]], GOLD.darkened(0.2))
			for x in [0.16, 0.5, 0.84]:
				pic._circle(x, 0.3 + bob, 0.045, Color.WHITE)
			pic._circle(0.35, 0.62 + bob, 0.04, Color(0.9, 0.2, 0.3))
			pic._circle(0.5, 0.62 + bob, 0.05, Color(0.3, 0.6, 1.0))
			pic._circle(0.65, 0.62 + bob, 0.04, Color(0.3, 0.85, 0.4))
		"flowerchain":  # a garland of blossoms (in `color`) - one more each day
			for i in 6:
				var x := 0.12 + i * 0.152
				var y := 0.5 + sin(i * 1.1) * 0.1 + bob
				if i > 0:
					pic._poly([[x - 0.15, 0.5 + sin((i - 1) * 1.1) * 0.1 + bob], [x, y], [x, y + 0.02], [x - 0.15, 0.52 + sin((i - 1) * 1.1) * 0.1 + bob]], Color(0.3, 0.65, 0.3))
				for k in 5:
					var a := TAU * k / 5.0 + t
					pic._circle(x + cos(a) * 0.04, y + sin(a) * 0.04, 0.035, color if i % 2 == 0 else Color.WHITE)
				pic._circle(x, y, 0.025, GOLD)
