extends RefCounted
## Mini Golf Party's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r), t = the picture's clock, bob = its gentle
## bob, color = the card's colour. GUS the gopher looks after the garden course.

const NAMES: Array[String] = ["gopher", "golfball", "golfflag", "trophy", "gnome"]

const FUR := Color(0.72, 0.5, 0.3)
const BELLY := Color(0.95, 0.82, 0.62)
const GOLD := Color(1.0, 0.8, 0.2)


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"gopher":  # Gus: a round, smiling gopher peeking out of his molehill, waving
			var wave := sin(t * 5.0) * 0.06
			pic._circle(0.5, 0.95, 0.36, Color(0.55, 0.38, 0.22))  # the molehill
			pic._circle(0.5, 0.62 + bob, 0.22, FUR)  # body
			pic._circle(0.5, 0.68 + bob, 0.14, BELLY)
			pic._circle(0.3, 0.27 + bob, 0.06, FUR.darkened(0.15))  # ears
			pic._circle(0.7, 0.27 + bob, 0.06, FUR.darkened(0.15))
			pic._circle(0.5, 0.4 + bob, 0.2, FUR)  # head
			pic._circle(0.5, 0.48 + bob, 0.1, BELLY)  # muzzle
			pic._eye(0.42, 0.36 + bob, 0.045)
			pic._eye(0.58, 0.36 + bob, 0.045)
			pic._circle(0.5, 0.45 + bob, 0.035, Color(0.95, 0.5, 0.55))  # nose
			pic._poly([[0.465, 0.52 + bob], [0.535, 0.52 + bob], [0.535, 0.58 + bob], [0.465, 0.58 + bob]], Color.WHITE)  # teeth
			pic._poly([[0.5, 0.52 + bob], [0.505, 0.52 + bob], [0.505, 0.58 + bob], [0.5, 0.58 + bob]], BELLY.darkened(0.3))
			pic._poly([[0.7, 0.6 + bob], [0.78, 0.6 + bob], [0.86 + wave, 0.4 + bob], [0.8 + wave, 0.38 + bob]], FUR)  # waving arm
			pic._circle(0.84 + wave, 0.38 + bob, 0.05, FUR.darkened(0.1))
			pic._poly([[0.3, 0.2 + bob], [0.7, 0.2 + bob], [0.62, 0.12 + bob], [0.38, 0.12 + bob]], color)  # a little cap
			pic._poly([[0.62, 0.2 + bob], [0.8, 0.2 + bob], [0.8, 0.23 + bob], [0.62, 0.23 + bob]], color.darkened(0.2))
		"golfball":  # a golf ball rolling to the cup (the ball in `color`)
			var roll := fmod(t * 0.25, 1.0)
			pic._poly([[0.1, 0.78], [0.9, 0.78], [0.9, 0.86], [0.1, 0.86]], Color(0.3, 0.8, 0.4))
			pic._circle(0.78, 0.8, 0.09, Color(0.1, 0.12, 0.1))
			var x := 0.22 + roll * 0.4
			pic._circle(x, 0.62 + bob, 0.16, color.lightened(0.3))
			pic._circle(x - 0.05, 0.57 + bob, 0.03, Color(1, 1, 1, 0.7))
			for k in 4:
				var a := TAU * k / 4.0 + t * 3.0
				pic._circle(x + cos(a) * 0.08, 0.62 + sin(a) * 0.08 + bob, 0.02, color.darkened(0.15))
		"golfflag":  # the flag in the cup (the flag in `color`)
			var flap := sin(t * 4.0) * 0.03
			pic._circle(0.5, 0.86, 0.3, Color(0.3, 0.8, 0.4))
			pic._circle(0.46, 0.84, 0.08, Color(0.1, 0.12, 0.1))
			pic._poly([[0.47, 0.84], [0.5, 0.84], [0.5, 0.12 + bob], [0.47, 0.12 + bob]], Color.WHITE)
			pic._poly([[0.5, 0.12 + bob], [0.82, 0.2 + flap + bob], [0.5, 0.36 + bob]], color)
			pic._circle(0.6, 0.23 + bob, 0.035, GOLD)
		"trophy":  # a shiny golden cup
			pic._poly([[0.3, 0.2 + bob], [0.7, 0.2 + bob], [0.64, 0.5 + bob], [0.36, 0.5 + bob]], GOLD)
			pic._circle(0.5, 0.48 + bob, 0.14, GOLD)
			pic._circle(0.26, 0.32 + bob, 0.07, GOLD.darkened(0.15))
			pic._circle(0.74, 0.32 + bob, 0.07, GOLD.darkened(0.15))
			pic._poly([[0.46, 0.6 + bob], [0.54, 0.6 + bob], [0.56, 0.72 + bob], [0.44, 0.72 + bob]], GOLD.darkened(0.2))
			pic._poly([[0.32, 0.72 + bob], [0.68, 0.72 + bob], [0.68, 0.82 + bob], [0.32, 0.82 + bob]], color)
			pic._circle(0.42, 0.3 + bob, 0.04, Color(1, 1, 1, 0.6))
			var tw := 0.5 + 0.5 * sin(t * 6.0)
			pic._circle(0.78, 0.14 + bob, 0.025 * tw + 0.01, Color.WHITE)
		"gnome":  # a garden gnome (the hat in `color`)
			pic._poly([[0.28, 0.9], [0.72, 0.9], [0.62, 0.52 + bob], [0.38, 0.52 + bob]], Color(0.3, 0.45, 0.9))
			pic._circle(0.5, 0.46 + bob, 0.12, Color(1.0, 0.82, 0.72))
			pic._poly([[0.38, 0.5 + bob], [0.62, 0.5 + bob], [0.5, 0.74 + bob]], Color.WHITE)  # beard
			pic._eye(0.45, 0.43 + bob, 0.025)
			pic._eye(0.55, 0.43 + bob, 0.025)
			pic._circle(0.5, 0.49 + bob, 0.03, Color(1.0, 0.6, 0.6))
			pic._poly([[0.36, 0.38 + bob], [0.64, 0.38 + bob], [0.5, 0.06 + bob]], color)  # hat
