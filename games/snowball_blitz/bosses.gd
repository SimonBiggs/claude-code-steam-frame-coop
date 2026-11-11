extends RefCounted
## SNOWBALL BLITZ bosses and their TELLS (snowman.gd reads numbers() before every big attack; tests/snowball_blitz_gen_test.gd
## runs check()).
##   king   the SNOW KING (wave 7, then every 4th endless wave from 14): a VOLLEY of three big snowballs at a player (a
##          ring shows where they will land: step out of it, or block with the pan lid), and CALL (two snowmen hop out).
##   yeti   the YETI (wave 10, the finale): STOMP (a wide ring round it: the walls in it lose snow), a big THROW at a
##          player (a ring where it lands) and CALL (snow bunnies).
## Every big attack is TOLD for `tell` seconds on every machine: the boss glows and stands still and a pulsing ring
## lies on the snow until it lands (main.gd boss_tell -> "warn" event). GENTLE: a longer tell, softer hits, one helper,
## slower; HARD: a shorter tell (never under MIN_TELL), harder hits. ANGRY (under half its snow): attacks come faster,
## but never faster than tell + REST (a breather with nothing on the snow).

const KINDS: Array[String] = ["king", "yeti"]
const MIN_TELL := 1.2
const MIN_GENTLE_TELL := 2.0
const REST := 2.0  # seconds with no warning on the snow between attacks, at least
const MAX_HIT := 20.0  # a wall's snow (of 100) one attack takes, at most
const MAX_GENTLE_HIT := 9.0
const MAX_GENTLE_HELPERS := 1
const MAX_RING := 6.0  # the widest warning ring (m): a stomp never reaches past the fort's far side

const LIST := {
	"king": {"name": "SNOW KING", "pic": "snowking", "color": Color(0.55, 0.85, 1.0), "ring": Color(0.2, 0.45, 1.0), "attacks": ["volley", "volley", "call"],
		"tell": 1.5, "every": 5.5, "angry_every": 4.0, "damage": 12.0, "radius": 2.2, "stomp_r": 0.0,
		"helpers": 2, "helper": "snowman"},
	"yeti": {"name": "YETI", "pic": "yeti", "color": Color(0.75, 0.9, 1.0), "ring": Color(0.45, 0.35, 1.0), "attacks": ["stomp", "throw", "stomp", "call"],
		"tell": 1.7, "every": 6.0, "angry_every": 4.5, "damage": 14.0, "radius": 2.0, "stomp_r": 4.5,
		"helpers": 2, "helper": "bunny"},
}


static func info(kind: String) -> Dictionary:
	return LIST.get(kind, LIST["king"])


## The warning ring a boss's attack lies on the snow: its own deep "ring" colour (its pale glow colour vanished on
## the snow), a paler one for the call. palette.gd checks every one.
static func tell_color(kind: String, attack: String) -> Color:
	var c: Color = info(kind).ring
	return c.lerp(Color.WHITE, 0.25) if attack == "call" else c


## The numbers of a boss's attack right now.
static func numbers(kind: String, mode: String, angry: bool) -> Dictionary:
	var d := info(kind).duplicate()
	var every := float(d.angry_every if angry else d.every)
	match mode:
		"gentle":
			d.tell = maxf(float(d.tell) * 1.5, MIN_GENTLE_TELL)
			every *= 1.4
			d.damage = float(d.damage) * 0.5
			d.helpers = mini(int(d.helpers), MAX_GENTLE_HELPERS)
		"hard":
			d.tell = maxf(float(d.tell) * 0.85, MIN_TELL)
			every *= 0.85
			d.damage = float(d.damage) * 1.25
	d.every = maxf(every, float(d.tell) + REST)
	return d


## The attack after `count` attacks (they take turns).
static func attack(kind: String, count: int) -> String:
	var list: Array = info(kind).attacks
	return String(list[posmod(count, list.size())])


## Problems with a boss's design (empty = fair for the family).
static func check(kind: String) -> Array[String]:
	var why: Array[String] = []
	if not LIST.has(kind):
		return ["no boss called %s" % kind]
	if String(info(kind).name).length() > 12:
		why.append("%s: name too long for the banner" % kind)
	if (info(kind).attacks as Array).is_empty():
		why.append("%s: no attacks" % kind)
	for a in info(kind).attacks:
		if not ["volley", "throw", "stomp", "call"].has(String(a)):
			why.append("%s: no such attack %s" % [kind, a])
	for mode in ["gentle", "brave", "hard"]:
		for angry in [false, true]:
			var n := numbers(kind, mode, angry)
			var tag := "%s %s%s" % [kind, mode, " angry" if angry else ""]
			if float(n.tell) < (MIN_GENTLE_TELL if mode == "gentle" else MIN_TELL):
				why.append("%s: the warning is only %.1f s" % [tag, float(n.tell)])
			if float(n.damage) > (MAX_GENTLE_HIT if mode == "gentle" else MAX_HIT):
				why.append("%s: one hit takes %.0f snow" % [tag, float(n.damage)])
			if float(n.every) < float(n.tell) + REST:
				why.append("%s: attacks every %.1f s (no time to breathe)" % [tag, float(n.every)])
			if mode == "gentle" and int(n.helpers) > MAX_GENTLE_HELPERS:
				why.append("%s: calls %d helpers in gentle mode" % [tag, int(n.helpers)])
			if maxf(float(n.radius), float(n.stomp_r)) > MAX_RING:
				why.append("%s: its ring reaches %.0f m" % [tag, maxf(float(n.radius), float(n.stomp_r))])
			if float(n.radius) < 1.2:
				why.append("%s: its ring is too small to see" % tag)
	return why