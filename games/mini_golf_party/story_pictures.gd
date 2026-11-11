extends RefCounted
## Mini Golf Party's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r), t = the picture's clock, bob = its gentle
## bob, color = the card's colour. GUS the gopher looks after the garden course.

const NAMES: Array[String] = ["gopher", "golfball", "golfflag", "trophy", "gnome", "magnetcup", "longputter", "rainbowball",
	"giantcup", "scarecrow", "treehouse"]

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
		"magnetcup":  # a red horseshoe magnet pulling a ball into the cup
			var pull := sin(t * 4.0) * 0.03
			pic._circle(0.5, 0.86, 0.3, Color(0.3, 0.8, 0.4))
			pic._circle(0.5, 0.84, 0.1, Color(0.1, 0.12, 0.1))
			pic._poly([[0.28, 0.12 + bob], [0.42, 0.12 + bob], [0.42, 0.42 + bob], [0.58, 0.42 + bob], [0.58, 0.12 + bob],
				[0.72, 0.12 + bob], [0.72, 0.5 + bob], [0.28, 0.5 + bob]], color)
			pic._poly([[0.28, 0.12 + bob], [0.42, 0.12 + bob], [0.42, 0.2 + bob], [0.28, 0.2 + bob]], Color(0.9, 0.9, 0.95))
			pic._poly([[0.58, 0.12 + bob], [0.72, 0.12 + bob], [0.72, 0.2 + bob], [0.58, 0.2 + bob]], Color(0.9, 0.9, 0.95))
			pic._circle(0.32 + pull, 0.74, 0.06, Color.WHITE)
			pic._circle(0.2, 0.66, 0.015, Color(1, 1, 1, 0.7))
			pic._circle(0.24, 0.6, 0.012, Color(1, 1, 1, 0.5))
		"longputter":  # a very long golf club and a dotted line to the cup
			pic._poly([[0.1, 0.8], [0.9, 0.8], [0.9, 0.88], [0.1, 0.88]], Color(0.3, 0.8, 0.4))
			pic._circle(0.84, 0.82, 0.06, Color(0.1, 0.12, 0.1))
			pic._poly([[0.12, 0.06 + bob], [0.16, 0.06 + bob], [0.3, 0.72], [0.26, 0.72]], Color(0.85, 0.87, 0.9))
			pic._poly([[0.2, 0.7], [0.36, 0.7], [0.36, 0.78], [0.2, 0.78]], color)
			pic._circle(0.42, 0.74, 0.04, Color.WHITE)
			for k in 5:
				var f := fmod(t * 0.5 + k * 0.2, 1.0)
				pic._circle(0.48 + f * 0.34, 0.76 + f * 0.04, 0.015, color.lightened(0.4))
		"rainbowball":  # a ball rolling with a rainbow trail behind it
			var cols: Array = [Color(1, 0.3, 0.3), Color(1, 0.7, 0.2), Color(1, 0.95, 0.3), Color(0.3, 0.85, 0.4), Color(0.35, 0.6, 1)]
			for c in cols.size():
				var y := 0.42 + c * 0.05
				pic._poly([[0.08, y + bob], [0.56, y + bob], [0.56, y + 0.05 + bob], [0.08, y + 0.05 + bob]], cols[c])
			pic._circle(0.66, 0.52 + bob, 0.16, Color.WHITE)
			pic._circle(0.61, 0.47 + bob, 0.035, Color(1, 1, 1, 0.8))
			pic._circle(0.7, 0.56 + bob, 0.02, Color(0.8, 0.8, 0.85))
			pic._circle(0.64, 0.6 + bob, 0.02, Color(0.8, 0.8, 0.85))
		"giantcup":  # a huge cup with a tiny flag and a ball dropping in
			pic._circle(0.5, 0.78, 0.42, Color(0.3, 0.8, 0.4))
			pic._circle(0.5, 0.74, 0.28, Color.WHITE)
			pic._circle(0.5, 0.74, 0.25, Color(0.1, 0.12, 0.1))
			pic._poly([[0.7, 0.74], [0.73, 0.74], [0.73, 0.18], [0.7, 0.18]], Color.WHITE)
			pic._poly([[0.73, 0.18], [0.9, 0.24], [0.73, 0.3]], color)
			var drop := fmod(t * 0.6, 1.0)
			pic._circle(0.45, 0.2 + drop * 0.5, 0.05, Color.WHITE)
		"scarecrow":  # a friendly scarecrow with a straw hat
			pic._poly([[0.48, 0.3], [0.52, 0.3], [0.52, 0.95], [0.48, 0.95]], Color(0.55, 0.38, 0.2))
			pic._poly([[0.15, 0.45 + bob], [0.85, 0.45 + bob], [0.85, 0.5 + bob], [0.15, 0.5 + bob]], Color(0.55, 0.38, 0.2))
			pic._poly([[0.36, 0.42 + bob], [0.64, 0.42 + bob], [0.62, 0.72 + bob], [0.38, 0.72 + bob]], color)
			pic._circle(0.5, 0.3 + bob, 0.12, Color(0.95, 0.85, 0.6))
			pic._eye(0.46, 0.28 + bob, 0.02)
			pic._eye(0.54, 0.28 + bob, 0.02)
			pic._circle(0.5, 0.33 + bob, 0.02, Color(1.0, 0.5, 0.1))
			pic._poly([[0.28, 0.2 + bob], [0.72, 0.2 + bob], [0.72, 0.23 + bob], [0.28, 0.23 + bob]], Color(0.9, 0.75, 0.3))
			pic._poly([[0.38, 0.2 + bob], [0.62, 0.2 + bob], [0.56, 0.08 + bob], [0.44, 0.08 + bob]], Color(0.9, 0.75, 0.3))
			pic._circle(0.15, 0.47 + bob, 0.04, Color(0.95, 0.85, 0.4))
			pic._circle(0.85, 0.47 + bob, 0.04, Color(0.95, 0.85, 0.4))
		"treehouse":  # a little house up a big tree, with a ladder
			pic._poly([[0.44, 0.5], [0.56, 0.5], [0.58, 0.95], [0.42, 0.95]], Color(0.5, 0.33, 0.18))
			pic._circle(0.5, 0.3 + bob * 0.5, 0.3, Color(0.3, 0.65, 0.3))
			pic._circle(0.3, 0.38 + bob * 0.5, 0.16, Color(0.35, 0.7, 0.35))
			pic._circle(0.7, 0.38 + bob * 0.5, 0.16, Color(0.35, 0.7, 0.35))
			pic._poly([[0.36, 0.4], [0.64, 0.4], [0.64, 0.6], [0.36, 0.6]], Color(0.85, 0.6, 0.35))
			pic._poly([[0.32, 0.4], [0.68, 0.4], [0.5, 0.26]], color)
			pic._poly([[0.46, 0.46], [0.54, 0.46], [0.54, 0.54], [0.46, 0.54]], Color(0.4, 0.75, 1.0))
			for k in 4:
				pic._poly([[0.62, 0.66 + k * 0.08], [0.74, 0.66 + k * 0.08], [0.74, 0.68 + k * 0.08], [0.62, 0.68 + k * 0.08]], Color(0.6, 0.4, 0.22))
