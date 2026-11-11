extends RefCounted
## Elemental Bender's story card pictures. core/story_pictures.gd finds this file by itself, so a game adds a picture
## here (a name in NAMES + its case in draw) and never touches core/story_card.gd. Drawn in a unit box:
## pic._p(x, y) / pic._circle(x, y, r, c) / pic._poly(pts, c) / pic._eye(x, y, r), size = pic.size,
## t = the picture's clock, bob = its gentle bob, color = the card's colour.
## (Kiko's crown is the shared "crown" icon; the temple lanterns use Giant's Table's "lantern".)

const NAMES: Array[String] = ["kiko", "portal", "airswirl", "waterdrop", "earthrock", "fireball", "general", "spirittree",
	"lightfruit", "iceshelf", "volcano", "skyruins", "frostgiant", "lavadrake", "stormhawk", "giftstone"]
## The element pictures in element order (AIR, WATER, EARTH, FIRE: elem.gd).
const ELEMENT_PICS: Array[String] = ["airswirl", "waterdrop", "earthrock", "fireball"]

const FUR := Color(0.95, 0.52, 0.18)
const CREAM := Color(1.0, 0.94, 0.84)
const SHADOW := Color(0.35, 0.12, 0.5)
const ELEM: Array[Color] = preload("res://games/elemental_bender/elem.gd").COLORS  # (one list: elem.gd)


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
		"iceshelf":  # a white ice island with blue spikes on a dark sea
			pic._poly([[0.0, 0.8], [1.0, 0.8], [1.0, 1.0], [0.0, 1.0]], Color(0.06, 0.28, 0.42))
			pic._poly([[0.08, 0.82], [0.2, 0.66], [0.8, 0.66], [0.92, 0.82]], Color(0.88, 0.94, 1.0))
			for k in 3:
				var x := 0.3 + k * 0.2
				var h := 0.32 - absf(k - 1) * 0.1
				pic._poly([[x - 0.07, 0.68], [x, 0.68 - h + bob * 0.3], [x + 0.07, 0.68]], Color(0.6, 0.85, 1.0))
			pic._circle(0.82, 0.2, 0.025, Color(1, 1, 1))
			pic._circle(0.2, 0.3 + fmod(t * 0.2, 0.3), 0.02, Color(1, 1, 1))
		"volcano":  # a dark volcano with lava pouring and a puff of smoke
			pic._poly([[0.0, 0.85], [1.0, 0.85], [1.0, 1.0], [0.0, 1.0]], Color(1.0, 0.4, 0.08))
			pic._poly([[0.1, 0.86], [0.4, 0.34], [0.6, 0.34], [0.9, 0.86]], Color(0.25, 0.2, 0.2))
			pic._poly([[0.42, 0.36], [0.58, 0.36], [0.55, 0.55], [0.5, 0.7], [0.46, 0.5]], Color(1.0, 0.5, 0.1))
			var sm := fmod(t * 0.3, 1.0)
			pic._circle(0.5 + sm * 0.1, 0.25 - sm * 0.15 + bob * 0.3, 0.07 + sm * 0.06, Color(0.6, 0.58, 0.6, 1.0 - sm))
		"skyruins":  # broken white columns on an island in the clouds
			pic._circle(0.2, 0.86, 0.14, Color(1, 1, 1))
			pic._circle(0.8, 0.88, 0.14, Color(1, 1, 1))
			pic._poly([[0.15, 0.7 + bob], [0.85, 0.7 + bob], [0.6, 0.92 + bob], [0.4, 0.92 + bob]], Color(0.55, 0.5, 0.45))
			pic._poly([[0.15, 0.66 + bob], [0.85, 0.66 + bob], [0.85, 0.72 + bob], [0.15, 0.72 + bob]], Color(0.5, 0.72, 0.42))
			pic._poly([[0.28, 0.66 + bob], [0.38, 0.66 + bob], [0.38, 0.3 + bob], [0.28, 0.3 + bob]], Color(0.95, 0.93, 0.88))
			pic._poly([[0.58, 0.66 + bob], [0.68, 0.66 + bob], [0.68, 0.46 + bob], [0.62, 0.42 + bob], [0.58, 0.48 + bob]], Color(0.95, 0.93, 0.88))
			pic._circle(0.5, 0.86, 0.16, Color(1, 1, 1))
		"frostgiant":  # a big pale-blue giant face with an icy crown and a friendly-grumpy brow
			var c := Color(0.7, 0.88, 1.0)
			pic._circle(0.5, 0.58 + bob, 0.34, c)
			for k in 4:
				var x := 0.26 + k * 0.16
				pic._poly([[x - 0.05, 0.3 + bob], [x, 0.1 + bob], [x + 0.05, 0.3 + bob]], Color(0.85, 0.95, 1.0))
			pic._poly([[0.3, 0.46 + bob], [0.46, 0.5 + bob], [0.46, 0.54 + bob], [0.3, 0.5 + bob]], Color(0.25, 0.4, 0.6))
			pic._poly([[0.7, 0.46 + bob], [0.54, 0.5 + bob], [0.54, 0.54 + bob], [0.7, 0.5 + bob]], Color(0.25, 0.4, 0.6))
			pic._eye(0.4, 0.6 + bob, 0.05)
			pic._eye(0.6, 0.6 + bob, 0.05)
			pic._poly([[0.38, 0.76 + bob], [0.62, 0.76 + bob], [0.6, 0.8 + bob], [0.4, 0.8 + bob]], Color(0.25, 0.4, 0.6))
		"lavadrake":  # an orange dragon head with little horns and a puff of fire
			var c := Color(1.0, 0.45, 0.12)
			pic._circle(0.42, 0.52 + bob, 0.26, c)
			pic._poly([[0.55, 0.45 + bob], [0.88, 0.55 + bob], [0.86, 0.66 + bob], [0.55, 0.68 + bob]], c)  # snout
			pic._poly([[0.28, 0.32 + bob], [0.2, 0.1 + bob], [0.36, 0.28 + bob]], Color(0.35, 0.15, 0.1))
			pic._poly([[0.46, 0.28 + bob], [0.48, 0.06 + bob], [0.54, 0.3 + bob]], Color(0.35, 0.15, 0.1))
			pic._eye(0.48, 0.46 + bob, 0.055)
			pic._circle(0.82, 0.54 + bob, 0.02, Color(0.3, 0.1, 0.05))
			var fl := 0.06 + absf(sin(t * 5.0)) * 0.04
			pic._circle(0.94, 0.62 + bob, fl, Color(1.0, 0.85, 0.3))
			for k in 3:
				pic._circle(0.3 + k * 0.08, 0.72 + bob, 0.035, Color(1.0, 0.8, 0.3))  # belly scales
		"stormhawk":  # a white hawk with wide wings and a yellow beak
			var c := Color(0.92, 0.96, 1.0)
			var fl := sin(t * 4.0) * 0.08
			pic._poly([[0.5, 0.5 + bob], [0.05, 0.3 + fl + bob], [0.15, 0.5 + bob], [0.05, 0.6 - fl + bob]], c.darkened(0.08))
			pic._poly([[0.5, 0.5 + bob], [0.95, 0.3 + fl + bob], [0.85, 0.5 + bob], [0.95, 0.6 - fl + bob]], c.darkened(0.08))
			pic._circle(0.5, 0.55 + bob, 0.17, c)
			pic._circle(0.5, 0.36 + bob, 0.12, c)
			pic._poly([[0.46, 0.4 + bob], [0.54, 0.4 + bob], [0.5, 0.5 + bob]], Color(1.0, 0.8, 0.2))
			pic._eye(0.45, 0.34 + bob, 0.035)
			pic._eye(0.55, 0.34 + bob, 0.035)
			pic._poly([[0.42, 0.7 + bob], [0.58, 0.7 + bob], [0.5, 0.86 + bob]], c.darkened(0.15))
		"giftstone":  # Kiko's altar: a glowing stone with a wrapped gift floating above it
			var c := Color(1.0, 0.85, 0.35) if color == Color.WHITE else color
			pic._poly([[0.25, 0.95], [0.3, 0.72], [0.7, 0.72], [0.75, 0.95]], Color(0.6, 0.58, 0.55))
			pic._circle(0.5, 0.45 + bob, 0.26, Color(c.r, c.g, c.b, 0.3))
			pic._poly([[0.36, 0.34 + bob], [0.64, 0.34 + bob], [0.64, 0.58 + bob], [0.36, 0.58 + bob]], c)
			pic._poly([[0.47, 0.34 + bob], [0.53, 0.34 + bob], [0.53, 0.58 + bob], [0.47, 0.58 + bob]], Color(1.0, 0.4, 0.5))
			pic._circle(0.44, 0.31 + bob, 0.05, Color(1.0, 0.4, 0.5))
			pic._circle(0.56, 0.31 + bob, 0.05, Color(1.0, 0.4, 0.5))
