extends RefCounted
## Soft Dodgeball's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r) / pic.draw_*(...), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.
## The park's other things use other games' pictures (daisy, sunflower, sapling, balloon, bunny).

const NAMES: Array[String] = ["tumtum", "squishball", "goldball", "cushion", "toadstool", "curveball", "stomp", "ballshower", "ballmagnet",
	"slide", "swing", "seesaw", "trampoline", "roundabout", "bouncycastle"]  # "duckling" is Bubble Bath's (picture names are shared across games)

const SKIN := Color(1.0, 0.82, 0.68)
const JUMPER := Color(1.0, 0.6, 0.25)
const HAIR := Color(0.55, 0.3, 0.15)


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"tumtum":  # TumTum the friendly giant: big round tummy with a target on it, waving
			var wave := sin(t * 5.0) * 0.06
			pic._circle(0.5, 0.78 + bob, 0.3, JUMPER)  # tummy
			pic._circle(0.5, 0.8 + bob, 0.15, Color(1.0, 0.25, 0.3))  # the target
			pic._circle(0.5, 0.8 + bob, 0.1, Color.WHITE)
			pic._circle(0.5, 0.8 + bob, 0.05, Color(1.0, 0.25, 0.3))
			pic._circle(0.2, 0.62 + bob, 0.07, SKIN)  # left mitten
			pic._circle(0.84, 0.42 + bob + wave, 0.07, SKIN)  # waving mitten
			pic._poly([[0.7, 0.62 + bob], [0.78, 0.6 + bob], [0.86, 0.44 + bob + wave], [0.8, 0.42 + bob + wave]], JUMPER)
			pic._circle(0.5, 0.36 + bob, 0.21, SKIN)  # head
			pic._poly([[0.29, 0.32 + bob], [0.36, 0.17 + bob], [0.5, 0.13 + bob], [0.64, 0.17 + bob], [0.71, 0.32 + bob], [0.6, 0.24 + bob], [0.4, 0.24 + bob]], HAIR)
			pic._eye(0.42, 0.34 + bob, 0.045)
			pic._eye(0.58, 0.34 + bob, 0.045)
			pic._circle(0.36, 0.42 + bob, 0.035, Color(1.0, 0.6, 0.6))  # cheeks
			pic._circle(0.64, 0.42 + bob, 0.035, Color(1.0, 0.6, 0.6))
			pic._poly([[0.42, 0.44 + bob], [0.58, 0.44 + bob], [0.5, 0.5 + bob]], Color(0.65, 0.15, 0.2))  # big smile
		"squishball":  # a soft ball bouncing and squishing
			var h := absf(sin(t * 3.5))
			var sq := 1.0 - 0.25 * (1.0 - h) * (1.0 - h)
			var y := 0.78 - h * 0.4 + bob
			pic._poly([[0.3, 0.9], [0.7, 0.9], [0.62, 0.93], [0.38, 0.93]], Color(0, 0, 0, 0.25))  # shadow
			var pts: Array = []
			for i in 16:
				var a := TAU * float(i) / 16.0
				pts.append([0.5 + cos(a) * 0.17 / sq, y + sin(a) * 0.17 * sq])
			pic._poly(pts, color)
			pic._circle(0.44, y - 0.06 * sq, 0.045, Color(1, 1, 1, 0.7))  # shine
		"goldball":  # TODAY'S PARK: a golden ball with twinkles
			pic._circle(0.5, 0.55 + bob, 0.27, Color(1.0, 0.78, 0.2))
			pic._circle(0.5, 0.55 + bob, 0.21, Color(1.0, 0.86, 0.35))
			pic._circle(0.42, 0.46 + bob, 0.06, Color(1, 1, 1, 0.75))
			for i in 4:
				var a := t * 1.5 + TAU * float(i) / 4.0
				var tw := 0.02 + 0.015 * absf(sin(t * 4.0 + float(i)))
				var cx := 0.5 + cos(a) * 0.38
				var cy := 0.55 + sin(a) * 0.38 + bob
				pic._poly([[cx, cy - tw * 2.0], [cx + tw, cy], [cx, cy + tw * 2.0], [cx - tw, cy]], Color(1.0, 0.95, 0.6))
		"cushion":  # a puffy park cushion to hide behind
			var puff := 1.0 + 0.03 * sin(t * 2.5)
			for b in [[0.3, 0.62, 0.16], [0.5, 0.52, 0.2], [0.7, 0.62, 0.16], [0.5, 0.68, 0.18]]:
				pic._circle(b[0], b[1] + bob, b[2] * puff, color)
			pic._circle(0.42, 0.48 + bob, 0.05, color.lightened(0.4))
			pic._eye(0.44, 0.6 + bob, 0.04)  # a sleepy happy face
			pic._eye(0.56, 0.6 + bob, 0.04)
			pic._poly([[0.46, 0.68 + bob], [0.54, 0.68 + bob], [0.5, 0.71 + bob]], color.darkened(0.4))
		"toadstool":  # a red toadstool with white spots
			pic._poly([[0.42, 0.55 + bob], [0.58, 0.55 + bob], [0.6, 0.88 + bob], [0.4, 0.88 + bob]], Color(0.98, 0.94, 0.85))
			var cap: Array = []
			for i in 13:
				var a := PI + PI * float(i) / 12.0
				cap.append([0.5 + cos(a) * 0.32, 0.56 + sin(a) * 0.26 + bob])
			pic._poly(cap, Color(0.9, 0.2, 0.2))
			for s in [[0.38, 0.45, 0.04], [0.55, 0.38, 0.05], [0.66, 0.5, 0.035], [0.47, 0.52, 0.03]]:
				pic._circle(s[0], s[1] + bob, s[2], Color.WHITE)
			pic._eye(0.46, 0.68 + bob, 0.03)
			pic._eye(0.54, 0.68 + bob, 0.03)
		"curveball":  # CURVE BALL: a ball swooping round a curvy dotted path to a target
			for i in 7:
				var k := float(i) / 6.0
				var x := 0.15 + k * 0.6
				var y := 0.75 - sin(k * PI) * 0.35 + k * -0.2
				pic._circle(x, y + bob, 0.02 + 0.01 * k, Color(1, 1, 1, 0.5 + 0.4 * k))
			pic._circle(0.82, 0.48 + bob, 0.12, Color(1.0, 0.3, 0.35))
			pic._circle(0.82, 0.48 + bob, 0.07, Color.WHITE)
			pic._circle(0.82, 0.48 + bob, 0.03, Color(1.0, 0.3, 0.35))
			var bx := 0.15 + fmod(t * 0.5, 1.0) * 0.6
			var kk := (bx - 0.15) / 0.6
			pic._circle(bx, 0.75 - sin(kk * PI) * 0.35 - kk * 0.2 + bob, 0.09, color)
		"stomp":  # TumTum's STOMP: a big foot coming down and a wobbly wave rolling out
			var lift := absf(sin(t * 3.0)) * 0.12
			pic._poly([[0.36, 0.2 - lift + bob], [0.56, 0.2 - lift + bob], [0.58, 0.58 - lift + bob], [0.34, 0.58 - lift + bob]], Color(1.0, 0.6, 0.25))
			pic._poly([[0.28, 0.58 - lift + bob], [0.7, 0.58 - lift + bob], [0.72, 0.7 - lift + bob], [0.26, 0.7 - lift + bob]], Color(0.45, 0.3, 0.2))
			for s in [-1.0, 1.0]:
				for k in 3:
					var x := 0.5 + float(s) * (0.3 + 0.08 * k)
					pic._poly([[x, 0.86 + bob], [x + float(s) * 0.05, 0.76 + bob], [x + float(s) * 0.1, 0.86 + bob]], Color(1.0, 0.2, 0.35, 0.9 - 0.25 * k))
			pic._poly([[0.1, 0.88 + bob], [0.9, 0.88 + bob], [0.9, 0.92 + bob], [0.1, 0.92 + bob]], Color(1.0, 0.2, 0.35))
		"ballshower":  # a BALL SHOWER: a cloud raining soft balls into a circle
			pic._circle(0.38, 0.25 + bob, 0.13, Color(0.92, 0.92, 1.0))
			pic._circle(0.56, 0.22 + bob, 0.16, Color(0.95, 0.95, 1.0))
			pic._circle(0.7, 0.28 + bob, 0.11, Color(0.92, 0.92, 1.0))
			for i in 5:
				var x := 0.3 + 0.1 * float(i)
				var y := 0.42 + fmod(t * 0.8 + float(i) * 0.37, 1.0) * 0.38
				pic._circle(x, y + bob, 0.04, [Color(1.0, 0.4, 0.5), Color(1.0, 0.8, 0.3), Color(0.4, 0.85, 0.5)][i % 3])
			var ring: Array = []
			for i in 16:
				var a := TAU * float(i) / 16.0
				ring.append([0.5 + cos(a) * 0.32, 0.88 + sin(a) * 0.06 + bob])
			pic._poly(ring, Color(0.55, 0.3, 1.0, 0.6))
		"ballmagnet":  # BALL MAGNET: a red horseshoe magnet pulling a ball
			pic._poly([[0.2, 0.25 + bob], [0.36, 0.25 + bob], [0.36, 0.6 + bob], [0.2, 0.6 + bob]], Color(0.95, 0.25, 0.25))
			pic._poly([[0.2, 0.6 + bob], [0.36, 0.6 + bob], [0.36, 0.72 + bob], [0.2, 0.72 + bob]], Color(0.85, 0.85, 0.9))
			pic._poly([[0.44, 0.25 + bob], [0.6, 0.25 + bob], [0.6, 0.6 + bob], [0.44, 0.6 + bob]], Color(0.95, 0.25, 0.25))
			pic._poly([[0.44, 0.6 + bob], [0.6, 0.6 + bob], [0.6, 0.72 + bob], [0.44, 0.72 + bob]], Color(0.85, 0.85, 0.9))
			pic._poly([[0.2, 0.18 + bob], [0.6, 0.18 + bob], [0.6, 0.27 + bob], [0.2, 0.27 + bob]], Color(0.95, 0.25, 0.25))
			var pull := 0.06 * sin(t * 4.0)
			pic._circle(0.4, 0.86 - pull + bob, 0.08, Color(1.0, 0.75, 0.2))
			for k in 2:
				pic._poly([[0.27 + 0.26 * k, 0.76 + bob], [0.29 + 0.26 * k, 0.76 + bob], [0.33 + 0.1 * k, 0.8 + bob], [0.31 + 0.1 * k, 0.8 + bob]], Color(1, 1, 1, 0.6))
		"slide":  # a playground slide: ladder up, slide down
			pic._poly([[0.22, 0.2 + bob], [0.25, 0.2 + bob], [0.25, 0.9 + bob], [0.22, 0.9 + bob]], Color(0.75, 0.78, 0.85))
			pic._poly([[0.38, 0.2 + bob], [0.41, 0.2 + bob], [0.41, 0.9 + bob], [0.38, 0.9 + bob]], Color(0.75, 0.78, 0.85))
			for k in 5:
				var y := 0.3 + 0.13 * float(k)
				pic._poly([[0.25, y + bob], [0.38, y + bob], [0.38, y + 0.025 + bob], [0.25, y + 0.025 + bob]], Color(0.75, 0.78, 0.85))
			pic._poly([[0.2, 0.17 + bob], [0.44, 0.17 + bob], [0.44, 0.22 + bob], [0.2, 0.22 + bob]], Color(0.3, 0.55, 1.0))
			pic._poly([[0.4, 0.17 + bob], [0.48, 0.17 + bob], [0.88, 0.85 + bob], [0.88, 0.9 + bob], [0.78, 0.9 + bob]], Color(1.0, 0.82, 0.25))
		"swing":  # a swing on a frame, swinging
			pic._poly([[0.12, 0.9 + bob], [0.16, 0.9 + bob], [0.3, 0.15 + bob], [0.26, 0.15 + bob]], Color(0.95, 0.3, 0.3))
			pic._poly([[0.84, 0.9 + bob], [0.88, 0.9 + bob], [0.74, 0.15 + bob], [0.7, 0.15 + bob]], Color(0.95, 0.3, 0.3))
			pic._poly([[0.26, 0.13 + bob], [0.74, 0.13 + bob], [0.74, 0.17 + bob], [0.26, 0.17 + bob]], Color(0.75, 0.78, 0.85))
			var sw := sin(t * 2.0) * 0.18
			var sx := 0.5 + sw
			pic._poly([[0.42, 0.15 + bob], [0.44, 0.15 + bob], [sx - 0.06, 0.72 + bob], [sx - 0.08, 0.72 + bob]], Color(0.6, 0.6, 0.65))
			pic._poly([[0.56, 0.15 + bob], [0.58, 0.15 + bob], [sx + 0.08, 0.72 + bob], [sx + 0.06, 0.72 + bob]], Color(0.6, 0.6, 0.65))
			pic._poly([[sx - 0.12, 0.71 + bob], [sx + 0.12, 0.71 + bob], [sx + 0.12, 0.76 + bob], [sx - 0.12, 0.76 + bob]], Color(1.0, 0.82, 0.25))
		"seesaw":  # a seesaw rocking on its middle
			pic._poly([[0.42, 0.88 + bob], [0.58, 0.88 + bob], [0.5, 0.68 + bob]], Color(0.95, 0.3, 0.3))
			var tilt := sin(t * 2.0) * 0.12
			pic._poly([[0.1, 0.68 + tilt + bob], [0.9, 0.68 - tilt + bob], [0.9, 0.73 - tilt + bob], [0.1, 0.73 + tilt + bob]], Color(0.3, 0.55, 1.0))
			pic._circle(0.16, 0.6 + tilt * 0.9 + bob, 0.06, Color(1.0, 0.82, 0.25))
			pic._circle(0.84, 0.6 - tilt * 0.9 + bob, 0.06, Color(0.35, 0.8, 0.4))
		"trampoline":  # a trampoline with a ball bouncing on it
			pic._poly([[0.12, 0.7 + bob], [0.88, 0.7 + bob], [0.82, 0.78 + bob], [0.18, 0.78 + bob]], Color(0.2, 0.22, 0.28))
			pic._poly([[0.1, 0.66 + bob], [0.9, 0.66 + bob], [0.9, 0.71 + bob], [0.1, 0.71 + bob]], Color(0.3, 0.55, 1.0))
			for x in [0.18, 0.5, 0.82]:
				pic._poly([[x - 0.015, 0.71 + bob], [x + 0.015, 0.71 + bob], [x + 0.015, 0.92 + bob], [x - 0.015, 0.92 + bob]], Color(0.75, 0.78, 0.85))
			var h := absf(sin(t * 3.0))
			pic._circle(0.5, 0.58 - h * 0.38 + bob, 0.08, color)
		"roundabout":  # a playground roundabout, turning
			var ring: Array = []
			for i in 20:
				var a := TAU * float(i) / 20.0
				ring.append([0.5 + cos(a) * 0.38, 0.7 + sin(a) * 0.12 + bob])
			pic._poly(ring, Color(1.0, 0.82, 0.25))
			for k in 4:
				var a := t * 1.5 + TAU * float(k) / 4.0
				var x := 0.5 + cos(a) * 0.3
				var y := 0.7 + sin(a) * 0.09
				pic._poly([[x - 0.015, y - 0.25 + bob], [x + 0.015, y - 0.25 + bob], [x + 0.015, y + bob], [x - 0.015, y + bob]], [Color(0.95, 0.3, 0.3), Color(0.3, 0.55, 1.0)][k % 2])
			pic._poly([[0.47, 0.72 + bob], [0.53, 0.72 + bob], [0.53, 0.92 + bob], [0.47, 0.92 + bob]], Color(0.75, 0.78, 0.85))
		"bouncycastle":  # a puffy bouncy castle with four towers
			pic._poly([[0.15, 0.55 + bob], [0.85, 0.55 + bob], [0.85, 0.9 + bob], [0.15, 0.9 + bob]], Color(0.95, 0.3, 0.3))
			for x in [0.18, 0.4, 0.6, 0.82]:
				pic._poly([[x - 0.06, 0.35 + bob], [x + 0.06, 0.35 + bob], [x + 0.06, 0.6 + bob], [x - 0.06, 0.6 + bob]], Color(1.0, 0.82, 0.25))
				pic._poly([[x - 0.08, 0.36 + bob], [x + 0.08, 0.36 + bob], [x, 0.2 + bob]], Color(0.3, 0.55, 1.0))
			pic._poly([[0.4, 0.68 + bob], [0.6, 0.68 + bob], [0.6, 0.9 + bob], [0.4, 0.9 + bob]], Color(0.35, 0.8, 0.4))
