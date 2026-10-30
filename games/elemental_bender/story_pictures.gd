extends RefCounted
## Elemental Bender's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.
## (Kiko's crown is the shared "crown" icon; the temple lanterns use Giant's Table's "lantern".)

const NAMES: Array[String] = ["kiko", "portal", "airswirl", "waterdrop", "earthrock", "fireball", "general", "spirittree",
	"lightfruit"]
## The element pictures in element order (AIR, WATER, EARTH, FIRE: elem.gd).
const ELEMENT_PICS: Array[String] = ["airswirl", "waterdrop", "earthrock", "fireball"]

const FUR := Color(0.95, 0.52, 0.18)
const CREAM := Color(1.0, 0.94, 0.84)
const SHADOW := Color(0.35, 0.12, 0.5)
const ELEM: Array[Color] = [Color(0.9, 0.95, 1.0), Color(0.15, 0.5, 1.0), Color(0.35, 0.75, 0.2), Color(1.0, 0.4, 0.08)]


static func draw(pic, kind: String, t: float, bob: float, color: Color) -> void:
	match kind:
		"kiko":  # the little temple fox: big ears, a cream chin, a fluffy tail with four coloured tips
			var c := FUR if color == Color.WHITE else FUR.lerp(color, 0.25)
			var wag := sin(t * 3.0) * 0.04
			pic._poly([[0.62, 0.86], [0.92, 0.6 + wag], [0.98, 0.42 + wag], [0.86, 0.5 + wag], [0.66, 0.74]], c)  # tail
			for k in 4:
				pic._circle(0.9 + k * 0.02, 0.44 + wag + k * 0.035, 0.035, ELEM[k])
			pic._circle(0.5, 0.78 + bob * 0.5, 0.2, c)  # body
			pic._circle(0.5, 0.8 + bob * 0.5, 0.11, CREAM)
			pic._poly([[0.26, 0.38 + bob], [0.3, 0.08 + bob], [0.44, 0.3 + bob]], c)  # ears
			pic._poly([[0.74, 0.38 + bob], [0.7, 0.08 + bob], [0.56, 0.3 + bob]], c)
			pic._poly([[0.3, 0.33 + bob], [0.32, 0.16 + bob], [0.4, 0.3 + bob]], Color(0.35, 0.18, 0.12))
			pic._poly([[0.7, 0.33 + bob], [0.68, 0.16 + bob], [0.6, 0.3 + bob]], Color(0.35, 0.18, 0.12))
			pic._circle(0.5, 0.45 + bob, 0.21, c)  # head
			pic._poly([[0.32, 0.5 + bob], [0.68, 0.5 + bob], [0.5, 0.66 + bob]], CREAM)  # muzzle
			pic._circle(0.5, 0.6 + bob, 0.03, Color(0.15, 0.08, 0.06))  # nose
			pic._eye(0.42, 0.43 + bob, 0.045)
			pic._eye(0.58, 0.43 + bob, 0.045)
		"portal":  # a swirly shadow portal standing on the grass
			var c := SHADOW if color == Color.WHITE else SHADOW.lerp(color, 0.3)
			pic._poly([[0.0, 0.88], [1.0, 0.88], [1.0, 1.0], [0.0, 1.0]], Color(0.36, 0.6, 0.28))
			pic._circle(0.5, 0.5, 0.36, c.lightened(0.25))
			pic._circle(0.5, 0.5, 0.3, c)
			for k in 3:
				var a := t * 2.0 + k * TAU / 3.0
				pic._circle(0.5 + cos(a) * 0.18, 0.5 + sin(a) * 0.18, 0.05, Color(0.75, 0.5, 1.0))
			pic._circle(0.5, 0.5, 0.1, Color(0.12, 0.04, 0.18))
		"airswirl":  # a white gust: three curls of wind
			var c := ELEM[0] if color == Color.WHITE else color
			for k in 3:
				var y := 0.3 + k * 0.2 + bob
				var sh := sin(t * 3.0 + k) * 0.04
				pic._poly([[0.12 + sh, y], [0.7 + sh, y], [0.7 + sh, y + 0.06], [0.12 + sh, y + 0.06]], c)
				pic._circle(0.74 + sh, y - 0.04, 0.09, c)
				pic._circle(0.74 + sh, y - 0.04, 0.045, Color(0.55, 0.75, 0.95))
		"waterdrop":  # a big blue water drop with a shine
			var c := ELEM[1] if color == Color.WHITE else color
			pic._poly([[0.5, 0.1 + bob], [0.72, 0.5 + bob], [0.28, 0.5 + bob]], c)
			pic._circle(0.5, 0.62 + bob, 0.25, c)
			pic._circle(0.42, 0.58 + bob, 0.06, Color(0.8, 0.92, 1.0))
		"earthrock":  # a green-brown boulder with a little sprout on top
			var c := Color(0.55, 0.42, 0.28)
			pic._poly([[0.15, 0.85], [0.22, 0.45 + bob], [0.45, 0.3 + bob], [0.75, 0.38 + bob], [0.88, 0.7], [0.8, 0.88]], c)
			pic._poly([[0.3, 0.5 + bob], [0.45, 0.4 + bob], [0.55, 0.5 + bob]], c.lightened(0.2))
			var g := ELEM[2] if color == Color.WHITE else color
			pic._poly([[0.48, 0.32 + bob], [0.52, 0.32 + bob], [0.52, 0.18 + bob], [0.48, 0.18 + bob]], g.darkened(0.2))
			pic._circle(0.43, 0.17 + bob, 0.06, g)
			pic._circle(0.57, 0.15 + bob, 0.06, g)
		"fireball":  # a round orange fireball with flames streaming up
			var c := ELEM[3] if color == Color.WHITE else color
			var fl := sin(t * 9.0) * 0.03
			pic._poly([[0.28, 0.6], [0.32 + fl, 0.18], [0.45, 0.4], [0.5 - fl, 0.08], [0.58, 0.38], [0.7 + fl, 0.2], [0.72, 0.6]], c)
			pic._circle(0.5, 0.64 + bob * 0.5, 0.24, c)
			pic._circle(0.5, 0.66 + bob * 0.5, 0.14, Color(1.0, 0.8, 0.3))
			pic._circle(0.5, 0.68 + bob * 0.5, 0.06, Color(1.0, 0.97, 0.7))
		"general":  # the Shadow General: a big purple hood, a white mask and a glowing orb
			var c := SHADOW if color == Color.WHITE else SHADOW.lerp(color, 0.3)
			pic._poly([[0.15, 1.0], [0.3, 0.45 + bob], [0.5, 0.25 + bob], [0.7, 0.45 + bob], [0.85, 1.0]], c)
			pic._circle(0.5, 0.45 + bob, 0.2, c)
			pic._poly([[0.38, 0.38 + bob], [0.62, 0.38 + bob], [0.6, 0.58 + bob], [0.5, 0.64 + bob], [0.4, 0.58 + bob]], Color(0.95, 0.95, 0.92))
			pic._poly([[0.42, 0.44 + bob], [0.48, 0.44 + bob], [0.47, 0.48 + bob], [0.43, 0.48 + bob]], Color(0.1, 0.05, 0.12))
			pic._poly([[0.52, 0.44 + bob], [0.58, 0.44 + bob], [0.57, 0.48 + bob], [0.53, 0.48 + bob]], Color(0.1, 0.05, 0.12))
			var e := int(t / 1.5) % 4
			pic._circle(0.5, 0.14 + bob, 0.08, ELEM[e])
		"spirittree":  # a round blossom tree with glowing fruit, on a little mound
			var c := Color(1.0, 0.68, 0.8) if color == Color.WHITE else color.lerp(Color(1.0, 0.68, 0.8), 0.5)
			pic._circle(0.5, 1.02, 0.3, Color(0.36, 0.6, 0.28))
			pic._poly([[0.45, 0.85], [0.55, 0.85], [0.53, 0.5], [0.47, 0.5]], Color(0.45, 0.3, 0.17))
			pic._circle(0.5, 0.4 + bob * 0.4, 0.3, c)
			pic._circle(0.33, 0.48 + bob * 0.4, 0.17, c.darkened(0.06))
			pic._circle(0.67, 0.48 + bob * 0.4, 0.17, c.darkened(0.06))
			for k in 4:
				var a := k * 1.6 + 0.4
				pic._circle(0.5 + cos(a) * 0.2, 0.42 + sin(a) * 0.16 + bob * 0.4, 0.05, ELEM[k])
		"lightfruit":  # one glowing fruit on a leafy stalk
			var c := Color(1.0, 0.85, 0.3) if color == Color.WHITE else color
			var pulse := 0.9 + sin(t * 3.0) * 0.1
			pic._circle(0.5, 0.58 + bob, 0.34 * pulse, Color(c.r, c.g, c.b, 0.25))
			pic._poly([[0.48, 0.12], [0.52, 0.12], [0.52, 0.36 + bob], [0.48, 0.36 + bob]], Color(0.45, 0.3, 0.17))
			pic._poly([[0.52, 0.2], [0.78, 0.1], [0.7, 0.26]], Color(0.3, 0.65, 0.25))
			pic._circle(0.5, 0.58 + bob, 0.22, c)
			pic._circle(0.43, 0.5 + bob, 0.06, c.lightened(0.6))
