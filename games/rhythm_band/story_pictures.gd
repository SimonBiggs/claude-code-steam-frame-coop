extends RefCounted
## Rhythm Band's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.
## The animal fans use other games' pictures (bunny, puppy, penguin, polarbear, toucan, sheep).

const NAMES: Array[String] = ["frog", "goldrecord", "fanclub", "musicnote", "dino", "bongos", "guitar", "discoball"]

const FROG := Color(0.35, 0.8, 0.3)
const GOLD := Color(1.0, 0.8, 0.2)
const WOOD := Color(0.62, 0.38, 0.18)


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"frog":  # Doodle: a round green frog singing into a microphone, with a little bow tie
			var hop := absf(sin(t * 3.0)) * 0.03
			pic._circle(0.5, 0.66 + bob - hop, 0.25, FROG)  # body
			pic._circle(0.5, 0.72 + bob - hop, 0.15, Color(0.75, 0.95, 0.6))  # tummy
			pic._circle(0.5, 0.42 + bob - hop, 0.22, FROG)  # head
			pic._circle(0.37, 0.26 + bob - hop, 0.1, FROG)  # eye bumps
			pic._circle(0.63, 0.26 + bob - hop, 0.1, FROG)
			pic._eye(0.37, 0.26 + bob - hop, 0.07)
			pic._eye(0.63, 0.26 + bob - hop, 0.07)
			var open := 0.03 + 0.03 * absf(sin(t * 6.0))
			pic._poly([[0.38, 0.47 + bob - hop], [0.62, 0.47 + bob - hop], [0.5, 0.5 + open + bob - hop]], Color(0.75, 0.15, 0.25))  # singing
			pic._circle(0.33, 0.44 + bob - hop, 0.03, Color(1.0, 0.55, 0.6))  # cheeks
			pic._circle(0.67, 0.44 + bob - hop, 0.03, Color(1.0, 0.55, 0.6))
			pic._poly([[0.42, 0.6 + bob - hop], [0.5, 0.63 + bob - hop], [0.42, 0.66 + bob - hop]], color)  # bow tie
			pic._poly([[0.58, 0.6 + bob - hop], [0.5, 0.63 + bob - hop], [0.58, 0.66 + bob - hop]], color)
			pic._poly([[0.77, 0.55 + bob], [0.8, 0.55 + bob], [0.8, 0.9 + bob], [0.77, 0.9 + bob]], Color(0.35, 0.35, 0.4))  # mic stand
			pic._circle(0.785, 0.5 + bob, 0.05, Color(0.25, 0.25, 0.3))
			for i in 2:  # notes floating up
				var y := 0.35 - fmod(t * 0.25 + i * 0.5, 1.0) * 0.3
				_note(pic, 0.86 - i * 0.08, y, 0.035, GOLD.lerp(color, 0.5))
		"goldrecord":  # a shiny golden record (TODAY'S SONG)
			var spin := t * 1.5
			pic._circle(0.5, 0.52 + bob, 0.36, GOLD.darkened(0.15))
			for k in 3:
				pic._circle(0.5, 0.52 + bob, 0.32 - k * 0.06, GOLD.lightened(0.08 * (k % 2)))
			pic._circle(0.5, 0.52 + bob, 0.1, color)
			pic._circle(0.5, 0.52 + bob, 0.025, Color(0.1, 0.1, 0.1))
			pic._circle(0.5 + cos(spin) * 0.22, 0.52 + bob + sin(spin) * 0.22, 0.04, Color(1, 1, 1, 0.6))  # glint
		"fanclub":  # three happy fans with glow sticks
			for k in 3:
				var x := 0.25 + k * 0.25
				var jump := absf(sin(t * 4.0 + k)) * 0.04
				var c: Color = [Color(1.0, 0.5, 0.6), Color(0.5, 0.75, 1.0), Color(1.0, 0.8, 0.3)][k]
				pic._circle(x, 0.72 + bob - jump, 0.11, c)
				pic._circle(x, 0.5 + bob - jump, 0.09, c.lightened(0.3))
				pic._eye(x - 0.03, 0.48 + bob - jump, 0.022)
				pic._eye(x + 0.03, 0.48 + bob - jump, 0.022)
				pic._poly([[x + 0.08, 0.6 + bob - jump], [x + 0.11, 0.6 + bob - jump], [x + 0.16, 0.3 + bob - jump], [x + 0.13, 0.3 + bob - jump]], color.lightened(0.3))
		"musicnote":  # two joined notes bouncing
			var b2 := sin(t * 4.0) * 0.03
			_note(pic, 0.36, 0.7 + bob + b2, 0.11, color)
			_note(pic, 0.66, 0.62 + bob - b2, 0.11, color)
			pic._poly([[0.44, 0.24 + bob + b2], [0.74, 0.16 + bob - b2], [0.74, 0.24 + bob - b2], [0.44, 0.32 + bob + b2]], color.darkened(0.2))
		"dino":  # a friendly green dinosaur stomping
			var stomp := absf(sin(t * 3.0)) * 0.04
			var g := Color(0.45, 0.8, 0.35)
			pic._poly([[0.1, 0.7 + bob], [0.35, 0.58 + bob], [0.35, 0.72 + bob]], g.darkened(0.1))  # tail
			pic._circle(0.5, 0.64 + bob, 0.2, g)  # body
			pic._circle(0.68, 0.36 + bob, 0.13, g)  # head
			pic._poly([[0.6, 0.45 + bob], [0.68, 0.45 + bob], [0.62, 0.6 + bob], [0.55, 0.58 + bob]], g)  # neck
			pic._eye(0.72, 0.32 + bob, 0.04)
			pic._poly([[0.72, 0.42 + bob], [0.8, 0.41 + bob], [0.76, 0.44 + bob]], Color(0.3, 0.15, 0.15))
			for k in 3:  # back spikes
				pic._poly([[0.38 + k * 0.08, 0.47 + bob], [0.42 + k * 0.08, 0.38 + bob], [0.46 + k * 0.08, 0.47 + bob]], color)
			pic._poly([[0.38, 0.78 + bob - stomp], [0.46, 0.78 + bob - stomp], [0.46, 0.9 + bob - stomp], [0.38, 0.9 + bob - stomp]], g.darkened(0.15))
			pic._poly([[0.54, 0.78 + bob], [0.62, 0.78 + bob], [0.62, 0.9 + bob], [0.54, 0.9 + bob]], g.darkened(0.15))
		"bongos":  # two bongo drums
			for k in 2:
				var x2 := 0.33 + k * 0.34
				var r2 := 0.15 - k * 0.02
				var hit := absf(sin(t * 5.0 + k * 1.6)) * 0.02
				pic._poly([[x2 - r2, 0.48 + bob], [x2 + r2, 0.48 + bob], [x2 + r2 * 0.8, 0.85 + bob], [x2 - r2 * 0.8, 0.85 + bob]], WOOD)
				pic._poly([[x2 - r2, 0.58 + bob], [x2 + r2, 0.58 + bob], [x2 + r2, 0.62 + bob], [x2 - r2, 0.62 + bob]], color)
				pic._circle(x2, 0.48 + bob + hit, r2, Color(0.96, 0.9, 0.78))
		"guitar":  # a rock guitar
			var tilt := sin(t * 2.0) * 0.02
			pic._poly([[0.52 + tilt, 0.12 + bob], [0.58 + tilt, 0.12 + bob], [0.56, 0.55 + bob], [0.5, 0.55 + bob]], WOOD.darkened(0.2))  # neck
			pic._poly([[0.5 + tilt, 0.06 + bob], [0.6 + tilt, 0.06 + bob], [0.6 + tilt, 0.14 + bob], [0.5 + tilt, 0.14 + bob]], Color(0.2, 0.2, 0.25))
			pic._circle(0.5, 0.62 + bob, 0.16, color)
			pic._circle(0.56, 0.76 + bob, 0.18, color)
			pic._circle(0.53, 0.66 + bob, 0.05, Color(0.15, 0.1, 0.1))
			pic._poly([[0.46, 0.8 + bob], [0.64, 0.8 + bob], [0.64, 0.84 + bob], [0.46, 0.84 + bob]], Color(0.2, 0.2, 0.2))
		"discoball":  # a sparkly mirror ball on a string
			pic._poly([[0.49, 0.0], [0.51, 0.0], [0.51, 0.22 + bob], [0.49, 0.22 + bob]], Color(0.7, 0.7, 0.75))
			pic._circle(0.5, 0.52 + bob, 0.3, Color(0.75, 0.78, 0.85))
			for k in 14:
				var a := float(k) * 2.4 + t * 1.2
				var rr := 0.08 + fmod(k * 0.37, 0.18)
				var c2 := Color.WHITE if k % 3 == 0 else color.lightened(0.3 * (k % 2))
				pic._circle(0.5 + cos(a) * rr, 0.52 + bob + sin(a) * rr * 0.9, 0.035, c2)
			for k in 4:  # sparkles
				var a2 := t * 2.0 + k * 1.57
				pic._circle(0.5 + cos(a2) * 0.42, 0.52 + sin(a2) * 0.4, 0.02 + 0.015 * absf(sin(t * 6.0 + k)), Color(1, 1, 0.8))


## A music note (head + stem) at (x, y) with head radius r.
static func _note(pic, x: float, y: float, r: float, c: Color) -> void:
	pic._circle(x, y, r, c)
	pic._poly([[x + r * 0.7, y], [x + r, y], [x + r, y - r * 4.5], [x + r * 0.7, y - r * 4.5]], c)
