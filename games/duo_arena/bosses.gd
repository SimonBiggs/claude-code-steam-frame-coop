extends RefCounted
## DUO ARENA bosses and their TELLS (enemy.gd reads numbers() every attack; tests/duo_arena_gen_test.gd runs check()).
##   boss   ORB OVERLORD (wave 5): glows brighter and brighter, a red ring grows on the floor round it, then SLAMS.
##   rex    KING REX (wave 10): rears up, roars, the red ring shows the STOMP. Calls raptors every other stomp.
##   omega  OMEGA OVERLORD (wave 15, the finale): the Orb Overlord's slam, wider, and raptors join in.
## Every attack is TOLD for `tell` seconds (glow + a pulsing ring that stays on the floor until it lands, on every
## machine) and the boss stands still while it tells. GENTLE: a long tell, half the hit, no helpers, slower; HARD:
## a shorter tell (never under MIN_TELL), harder hits. ANGRY (half health, or a long fight): attacks come faster,
## but never faster than tell + REST.

const KINDS: Array[String] = ["boss", "rex", "omega"]
const MIN_TELL := 1.2
const MIN_GENTLE_TELL := 2.0
const REST := 2.0  # seconds with no warning on the floor between attacks, at least
const MAX_HIT := 24.0
const MAX_GENTLE_HIT := 10.0

const LIST := {
	"boss": {"name": "ORB OVERLORD", "pic": "orbking", "tell": 1.5, "every": 6.0, "angry_every": 4.0, "damage": 18.0,
		"radius": 4.5, "helpers": 2, "helper": "runner", "color": Color(1.0, 0.15, 0.6)},
	"rex": {"name": "KING REX", "pic": "kingrex", "tell": 1.6, "every": 7.0, "angry_every": 4.8, "damage": 16.0,
		"radius": 5.5, "helpers": 2, "helper": "raptor", "color": Color(0.95, 0.2, 0.3)},
	"omega": {"name": "OMEGA OVERLORD", "pic": "omegaorb", "tell": 1.5, "every": 6.0, "angry_every": 4.0, "damage": 18.0,
		"radius": 5.5, "helpers": 2, "helper": "raptor", "color": Color(1.0, 0.78, 0.2)},
}


static func info(kind: String) -> Dictionary:
	return LIST.get(kind, LIST["boss"])


## The numbers of a boss's attack right now.
static func numbers(kind: String, mode: String, angry: bool) -> Dictionary:
	var d := info(kind).duplicate()
	var every := float(d.angry_every if angry else d.every)
	match mode:
		"gentle":
			d.tell = maxf(float(d.tell) * 1.5, MIN_GENTLE_TELL)
			every *= 1.4
			d.damage = float(d.damage) * 0.5
			d.helpers = 0
		"hard":
			d.tell = maxf(float(d.tell) * 0.85, MIN_TELL)
			every *= 0.85
			d.damage = float(d.damage) * 1.25
	d.every = maxf(every, float(d.tell) + REST)
	return d


## Problems with a boss's design (empty = fair for the family).
static func check(kind: String) -> Array[String]:
	var why: Array[String] = []
	if not LIST.has(kind):
		return ["no boss called %s" % kind]
	if String(info(kind).name).length() > 16:
		why.append("%s: name too long for the banner" % kind)
	for mode in ["gentle", "brave", "hard"]:
		for angry in [false, true]:
			var n := numbers(kind, mode, angry)
			var tag := "%s %s%s" % [kind, mode, " angry" if angry else ""]
			if float(n.tell) < (MIN_GENTLE_TELL if mode == "gentle" else MIN_TELL):
				why.append("%s: the warning is only %.1f s" % [tag, float(n.tell)])
			if float(n.damage) > (MAX_GENTLE_HIT if mode == "gentle" else MAX_HIT):
				why.append("%s: one hit takes %.0f health" % [tag, float(n.damage)])
			if float(n.every) < float(n.tell) + REST:
				why.append("%s: attacks every %.1f s (no time to breathe)" % [tag, float(n.every)])
			if mode == "gentle" and int(n.helpers) > 0:
				why.append("%s: calls helpers in gentle mode" % tag)
			if float(n.radius) > 7.0:
				why.append("%s: its slam reaches %.0f m" % [tag, float(n.radius)])
	return why
