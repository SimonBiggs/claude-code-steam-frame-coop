extends RefCounted
## Cannon Cove's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.
## (The Kraken's crown uses Dragon Rider's "crown": any picture works in every game.)

const NAMES: Array[String] = ["parrot", "doubloon", "pearl", "anchor", "starfish", "bunting", "treasuremap", "bouncyball", "netshot",
	"bigbarrel", "quickload", "krakenarm", "squall", "harbour"]

const RED := Color(0.95, 0.2, 0.15)
const GREEN := Color(0.2, 0.8, 0.3)
const BLUE := Color(0.2, 0.45, 1.0)
const YELLOW := Color(1.0, 0.85, 0.2)
const GOLD := Color(1.0, 0.8, 0.2)


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"parrot":  # Polly: a round red parrot with a yellow beak, a green wing that flaps and a little pirate hat
			var flap := sin(t * 6.0) * 0.07
			pic._poly([[0.5, 0.78 + bob], [0.42, 0.97 + bob], [0.5, 0.92 + bob], [0.58, 0.97 + bob]], BLUE)  # tail
			pic._circle(0.5, 0.6 + bob, 0.22, RED)  # body
			pic._circle(0.5, 0.66 + bob, 0.13, YELLOW.lightened(0.3))  # belly
			pic._poly([[0.3, 0.52 + bob], [0.12, 0.62 + bob - flap], [0.2, 0.78 + bob], [0.34, 0.72 + bob]], GREEN)  # wings
			pic._poly([[0.7, 0.52 + bob], [0.88, 0.62 + bob - flap], [0.8, 0.78 + bob], [0.66, 0.72 + bob]], GREEN)
			pic._circle(0.5, 0.34 + bob, 0.17, RED)  # head
			pic._eye(0.43, 0.32 + bob, 0.05)
			pic._eye(0.57, 0.32 + bob, 0.05)
			pic._poly([[0.44, 0.4 + bob], [0.56, 0.4 + bob], [0.5, 0.53 + bob]], YELLOW)  # beak
			pic._poly([[0.3, 0.22 + bob], [0.7, 0.22 + bob], [0.62, 0.1 + bob], [0.5, 0.06 + bob], [0.38, 0.1 + bob]], Color(0.12, 0.12, 0.15))  # hat
			pic._circle(0.5, 0.15 + bob, 0.03, Color.WHITE)
		"doubloon":  # a shiny gold coin with a star, spinning a little
			var squash := 0.75 + 0.25 * absf(cos(t * 2.0))
			var c := GOLD if color == Color.WHITE else color
			pic._poly(_ellipse(0.5, 0.52 + bob, 0.32 * squash, 0.32, 20), c.darkened(0.2))
			pic._poly(_ellipse(0.5, 0.5 + bob, 0.3 * squash, 0.3, 20), c)
			pic._poly(_star(0.5, 0.5 + bob, 0.15 * squash, 0.15, 0.07), c.lightened(0.35))
			pic._circle(0.5 - 0.14 * squash, 0.36 + bob, 0.04, Color(1, 1, 1, 0.6))
		"pearl":  # an open shell with a big shiny pearl
			pic._poly([[0.16, 0.7 + bob], [0.84, 0.7 + bob], [0.72, 0.84 + bob], [0.28, 0.84 + bob]], Color(1.0, 0.7, 0.75))
			var open := 0.05 + absf(sin(t * 1.5)) * 0.05
			pic._poly(_fan(0.5, 0.66 + bob - open, 0.34, PI, TAU), Color(1.0, 0.75, 0.8))
			for i in 4:
				var a := PI + PI * (i + 1) / 5.0
				pic._poly([[0.5, 0.66 + bob - open], [0.5 + cos(a) * 0.33, 0.66 + bob - open + sin(a) * 0.33], [0.5 + cos(a + 0.05) * 0.33, 0.66 + bob - open + sin(a + 0.05) * 0.33]], Color(0.9, 0.5, 0.6))
			pic._circle(0.5, 0.66 + bob, 0.11, Color(0.97, 0.97, 1.0))
			pic._circle(0.46, 0.62 + bob, 0.035, Color.WHITE)
		"anchor":  # a friendly anchor (in `color`, gold by default)
			var c := GOLD if color == Color.WHITE else color
			var sw := sin(t * 2.0) * 0.03
			pic._circle(0.5 + sw, 0.18 + bob, 0.08, c)
			pic._circle(0.5 + sw, 0.18 + bob, 0.04, c.darkened(0.5))  # the ring's hole
			pic._poly([[0.46 + sw, 0.24 + bob], [0.54 + sw, 0.24 + bob], [0.54 + sw, 0.78 + bob], [0.46 + sw, 0.78 + bob]], c)
			pic._poly([[0.3 + sw, 0.34 + bob], [0.7 + sw, 0.34 + bob], [0.7 + sw, 0.41 + bob], [0.3 + sw, 0.41 + bob]], c)
			pic._poly([[0.16 + sw, 0.58 + bob], [0.24 + sw, 0.56 + bob], [0.36 + sw, 0.74 + bob], [0.5 + sw, 0.8 + bob], [0.64 + sw, 0.74 + bob],
				[0.76 + sw, 0.56 + bob], [0.84 + sw, 0.58 + bob], [0.72 + sw, 0.82 + bob], [0.5 + sw, 0.9 + bob], [0.28 + sw, 0.82 + bob]], c)
			pic._poly([[0.1 + sw, 0.6 + bob], [0.22 + sw, 0.5 + bob], [0.24 + sw, 0.64 + bob]], c)
			pic._poly([[0.9 + sw, 0.6 + bob], [0.78 + sw, 0.5 + bob], [0.76 + sw, 0.64 + bob]], c)
		"starfish":  # a smiling orange starfish
			var c := Color(1.0, 0.55, 0.25) if color == Color.WHITE else color
			var wig := sin(t * 2.5) * 0.02
			pic._poly(_star(0.5, 0.53 + bob, 0.4 + wig, 0.4 + wig, 0.17), c)
			for i in 5:
				var a := -PI / 2.0 + TAU * i / 5.0
				pic._circle(0.5 + cos(a) * 0.22, 0.53 + bob + sin(a) * 0.22, 0.025, c.lightened(0.4))
			pic._eye(0.44, 0.5 + bob, 0.045)
			pic._eye(0.56, 0.5 + bob, 0.045)
			pic._poly([[0.44, 0.6 + bob], [0.56, 0.6 + bob], [0.5, 0.65 + bob]], Color(0.6, 0.15, 0.15))
		"bunting":  # a string of pirate flags (one more each play-day)
			var cols := [RED, YELLOW, BLUE, GREEN, Color.WHITE]
			for i in 5:
				var x := 0.1 + i * 0.18
				var y := 0.3 + sin(i * 0.9) * 0.04 + bob
				var flt := sin(t * 3.0 + i) * 0.02
				pic._poly([[x, y], [x + 0.16, y + 0.02], [x + 0.08 + flt, y + 0.3]], cols[i % cols.size()] if i != 2 else color)
			pic._poly([[0.06, 0.28 + bob], [0.94, 0.33 + bob], [0.94, 0.35 + bob], [0.06, 0.3 + bob]], Color(0.72, 0.6, 0.4))
		"treasuremap":  # an old map with a dotted path to a red X
			var paper := Color(0.98, 0.88, 0.62)
			pic._poly([[0.12, 0.2 + bob], [0.88, 0.16 + bob], [0.9, 0.82 + bob], [0.1, 0.86 + bob]], paper)
			pic._poly([[0.12, 0.2 + bob], [0.2, 0.2 + bob], [0.18, 0.86 + bob], [0.1, 0.86 + bob]], paper.darkened(0.12))
			pic._poly(_ellipse(0.55, 0.52 + bob, 0.22, 0.16, 12), Color(0.55, 0.8, 0.45))  # an island
			for i in 6:
				var f := i / 5.0
				pic._circle(0.3 + f * 0.3, 0.72 - f * 0.25 + sin(f * 5.0) * 0.04 + bob, 0.015, Color(0.5, 0.3, 0.15))
			var pulse := 1.0 + sin(t * 4.0) * 0.12
			pic._poly([[0.62 - 0.07 * pulse, 0.4 + bob], [0.64 - 0.07 * pulse, 0.38 + bob], [0.66 + 0.07 * pulse, 0.5 + bob], [0.64 + 0.07 * pulse, 0.52 + bob]], RED)
			pic._poly([[0.66 + 0.07 * pulse, 0.4 + bob], [0.68 + 0.07 * pulse, 0.42 + bob], [0.62 - 0.07 * pulse, 0.52 + bob], [0.6 - 0.07 * pulse, 0.5 + bob]], RED)

		"bouncyball":  # a pink cannonball bouncing off the waves (BOUNCY BALLS)
			var c := Color(1.0, 0.45, 0.7) if color == Color.WHITE else color
			var hop := absf(sin(t * 3.0)) * 0.25
			pic._poly([[0.05, 0.86], [0.2, 0.8], [0.35, 0.86], [0.5, 0.8], [0.65, 0.86], [0.8, 0.8], [0.95, 0.86], [0.95, 0.95], [0.05, 0.95]], BLUE)
			for i in 3:
				pic._circle(0.22 + i * 0.12, 0.62 - sin(i * 1.2) * 0.12, 0.025, Color(1, 1, 1, 0.7))
			pic._circle(0.62, 0.6 - hop, 0.17, Color(0.2, 0.2, 0.25))
			pic._circle(0.62, 0.6 - hop, 0.13, c)
			pic._circle(0.57, 0.55 - hop, 0.04, Color(1, 1, 1, 0.8))
		"netshot":  # a green rope net with corner weights (NET SHOT)
			var c := Color(0.55, 0.9, 0.5) if color == Color.WHITE else color
			var sw := sin(t * 2.0) * 0.02
			for i in 5:
				var f := 0.2 + i * 0.15
				pic._poly([[f - 0.012 + sw, 0.2], [f + 0.012 + sw, 0.2], [f + 0.012 - sw, 0.8], [f - 0.012 - sw, 0.8]], c)
				pic._poly([[0.2, f - 0.012 + bob], [0.8, f - 0.012 + bob], [0.8, f + 0.012 + bob], [0.2, f + 0.012 + bob]], c)
			for p2 in [[0.2, 0.2], [0.8, 0.2], [0.2, 0.8], [0.8, 0.8]]:
				pic._circle(p2[0], p2[1] + bob, 0.05, Color(0.35, 0.35, 0.4))
		"bigbarrel":  # a fat cannon with a huge ball (BIG BARREL)
			var c := Color(1.0, 0.6, 0.2) if color == Color.WHITE else color
			pic._poly([[0.12, 0.5 + bob], [0.62, 0.32 + bob], [0.7, 0.56 + bob], [0.2, 0.74 + bob]], Color(0.25, 0.25, 0.3))
			pic._circle(0.66, 0.44 + bob, 0.13, Color(0.15, 0.15, 0.18))
			pic._circle(0.3, 0.78 + bob, 0.12, Color(0.55, 0.38, 0.2))
			pic._circle(0.3, 0.78 + bob, 0.05, Color(0.35, 0.22, 0.1))
			var fly := fmod(t * 0.6, 1.0)
			pic._circle(0.72 + fly * 0.12, 0.3 - fly * 0.1 + bob, 0.15, c)
		"quickload":  # a cannonball zooming with speed lines (QUICK LOAD)
			var c := Color(0.45, 0.85, 1.0) if color == Color.WHITE else color
			var z := fmod(t * 1.5, 1.0) * 0.08
			for i in 3:
				var y := 0.42 + i * 0.09 + bob
				pic._poly([[0.1 + z, y], [0.45 + z, y - 0.015], [0.45 + z, y + 0.015]], c)
			pic._circle(0.64, 0.51 + bob, 0.18, Color(0.18, 0.18, 0.22))
			pic._circle(0.59, 0.45 + bob, 0.05, Color(1, 1, 1, 0.6))
		"krakenarm":  # a purple Kraken arm curling up out of the waves
			var c := Color(0.55, 0.3, 0.75) if color == Color.WHITE else color
			var sway := sin(t * 2.0) * 0.04
			for i in 7:
				var f := i / 6.0
				var x := 0.4 + sin(f * 2.6) * 0.18 + sway * f
				pic._circle(x, 0.82 - f * 0.6 + bob * f, 0.11 - f * 0.06, c)
				if i % 2 == 1:
					pic._circle(x - 0.04, 0.82 - f * 0.6 + bob * f, 0.025, c.lightened(0.5))
			pic._poly([[0.05, 0.86], [0.2, 0.8], [0.35, 0.86], [0.5, 0.8], [0.65, 0.86], [0.8, 0.8], [0.95, 0.86], [0.95, 0.95], [0.05, 0.95]], BLUE)
		"squall":  # a grey rain cloud with slanting rain
			var c := Color(0.25, 0.55, 1.0) if color == Color.WHITE else color
			for i in 6:
				var x := 0.25 + i * 0.1
				var y := 0.55 + fmod(t * 0.8 + i * 0.37, 0.3)
				pic._poly([[x, y], [x + 0.02, y], [x - 0.05, y + 0.12], [x - 0.07, y + 0.12]], c)
			pic._circle(0.35, 0.38 + bob, 0.15, Color(0.5, 0.53, 0.62))
			pic._circle(0.55, 0.32 + bob, 0.19, Color(0.55, 0.58, 0.67))
			pic._circle(0.72, 0.4 + bob, 0.13, Color(0.5, 0.53, 0.62))
			pic._poly([[0.22, 0.4 + bob], [0.84, 0.4 + bob], [0.84, 0.52 + bob], [0.22, 0.52 + bob]], Color(0.5, 0.53, 0.62))
		"harbour":  # Polly's harbour: an island with a hut, a beacon and a jetty
			pic._poly(_ellipse(0.5, 0.78, 0.42, 0.1, 16), Color(0.96, 0.84, 0.56))
			pic._poly([[0.05, 0.86], [0.95, 0.86], [0.95, 0.95], [0.05, 0.95]], BLUE)
			pic._poly([[0.25, 0.75], [0.48, 0.75], [0.48, 0.55], [0.25, 0.55]], Color(0.97, 0.94, 0.86))
			pic._poly([[0.21, 0.56], [0.52, 0.56], [0.365, 0.42]], RED)
			pic._poly([[0.62, 0.75], [0.72, 0.75], [0.7, 0.35], [0.64, 0.35]], Color(0.97, 0.94, 0.86))
			var glow := 0.05 + absf(sin(t * 1.5)) * 0.02
			pic._circle(0.67, 0.3, glow, YELLOW)
			pic._poly([[0.48, 0.8], [0.9, 0.8], [0.9, 0.83], [0.48, 0.83]], Color(0.6, 0.42, 0.24))


static func _ellipse(cx: float, cy: float, rx: float, ry: float, n: int) -> Array:
	var pts: Array = []
	for i in n:
		var a := TAU * i / n
		pts.append([cx + cos(a) * rx, cy + sin(a) * ry])
	return pts


static func _star(cx: float, cy: float, rx: float, ry: float, inner: float) -> Array:
	var pts: Array = []
	for i in 10:
		var a := -PI / 2.0 + PI * i / 5.0
		var k := 1.0 if i % 2 == 0 else inner / maxf(rx, 0.001)
		pts.append([cx + cos(a) * rx * k, cy + sin(a) * ry * k])
	return pts


static func _fan(cx: float, cy: float, r: float, a0: float, a1: float) -> Array:
	var pts: Array = [[cx, cy]]
	for i in 13:
		var a := lerpf(a0, a1, i / 12.0)
		pts.append([cx + cos(a) * r, cy + sin(a) * r])
	return pts
