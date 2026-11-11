extends RefCounted
## ELEMENTAL BENDER bosses: every island's 5th wave brings its own boss (arenas.gd "boss"):
##   general  SHADOW GENERAL (TEMPLE ISLAND): swaps element every 5 seconds (the classic boss).
##   giant    FROST GIANT (ICE SHELF, WATER: beat him with EARTH): raises his fists and glows white, a blue ring
##            on the ground shows where it lands, then STOMP: a shockwave round him. Powered up: ice shards too.
##   drake    LAVA DRAKE (VOLCANO RIM, FIRE: beat it with WATER): its mouth glows, then a FAN of fireballs.
##            Powered up: a wider fan.
##   hawk     STORM HAWK (SKY RUINS, AIR: beat it with FIRE): rises and glows, a line of rings shows its path,
##            then a DIVE along it. Powered up: two dives.
## Every boss attack is told first (TELL seconds of glow + a ring on the ground on every machine) and has a
## kind GENTLE version (a longer tell, half the damage, no helpers, slower): the game turns it on when the team is
## having a hard time (main.gd boss_gentle) and for a solo small player. At half health a boss POWERS UP (phase 2):
## a little faster, and the giant and drake call two helpers (not in gentle).
## check(kind) is the validator (tests/elemental_bender_gen_test.gd).

const E := preload("res://games/elemental_bender/elem.gd")

const KINDS: Array[String] = ["general", "giant", "drake", "hawk"]
const MIN_TELL := 1.2
const MIN_GENTLE_TELL := 2.0
const MAX_HIT := 22.0
const MAX_GENTLE_HIT := 11.0
const PHASE2_AT := 0.5

const LIST := {
	"general": {"name": "SHADOW GENERAL", "pic": "general", "element": -1, "attack": "swap", "tell": 0.0, "every": 5.0,
		"damage": 0.0, "radius": 0.0, "helpers": 0, "color": Color(0.75, 0.5, 1.0)},
	"giant": {"name": "FROST GIANT", "pic": "frostgiant", "element": E.WATER, "attack": "stomp", "tell": 1.4, "every": 6.0,
		"damage": 18.0, "radius": 6.5, "helpers": 2, "color": Color(0.7, 0.9, 1.0), "shards": 3},
	"drake": {"name": "LAVA DRAKE", "pic": "lavadrake", "element": E.FIRE, "attack": "fan", "tell": 1.3, "every": 5.5,
		"damage": 12.0, "radius": 3.0, "helpers": 2, "color": Color(1.0, 0.5, 0.15), "shots": 5, "shots2": 7},
	"hawk": {"name": "STORM HAWK", "pic": "stormhawk", "element": E.AIR, "attack": "dive", "tell": 1.5, "every": 6.0,
		"damage": 16.0, "radius": 2.2, "helpers": 0, "color": Color(0.85, 0.95, 1.0), "dive_len": 16.0, "dives2": 2},
}


static func info(kind: String) -> Dictionary:
	return LIST.get(kind, LIST["general"])


static func index_of(kind: String) -> int:
	return maxi(0, KINDS.find(kind))


## The numbers a boss uses right now: `gentle` for little teams, `phase2` once it has powered up.
static func numbers(kind: String, gentle: bool, phase2: bool) -> Dictionary:
	var d := info(kind).duplicate()
	if gentle:
		d.tell = maxf(float(d.tell) * 1.6, MIN_GENTLE_TELL) if float(d.tell) > 0.0 else 0.0
		d.every = float(d.every) * 1.35
		d.damage = float(d.damage) * 0.5
		d.helpers = 0
	if phase2 and not gentle:
		d.every = float(d.every) * 0.8
	d.shots_now = int(d.get("shots2" if phase2 else "shots", 0))
	d.dives_now = int(d.get("dives2", 1)) if phase2 else 1
	d.shards_now = int(d.get("shards", 0)) if phase2 else 0
	return d


## Problems with a boss's design (empty = kid-fair).
static func check(kind: String) -> Array[String]:
	var why: Array[String] = []
	if not LIST.has(kind):
		return ["no boss called %s" % kind]
	var d: Dictionary = LIST[kind]
	if String(d.name).length() > 16:
		why.append("%s: its name is too long for the health bar" % kind)
	var el := int(d.element)
	if el >= 0 and E.beater(el) < 0:
		why.append("%s: nothing beats its element" % kind)
	if String(d.attack) == "swap":
		return why
	for gentle in [false, true]:
		for p2 in [false, true]:
			var n := numbers(kind, gentle, p2)
			var tag := "%s%s%s" % [kind, " gentle" if gentle else "", " powered up" if p2 else ""]
			if float(n.tell) < (MIN_GENTLE_TELL if gentle else MIN_TELL):
				why.append("%s: the warning glow is only %.1f s" % [tag, float(n.tell)])
			if float(n.damage) > (MAX_GENTLE_HIT if gentle else MAX_HIT):
				why.append("%s: one hit takes %.0f health" % [tag, float(n.damage)])
			if float(n.every) < float(n.tell) + 2.5:
				why.append("%s: attacks come every %.1f s (no time to breathe)" % [tag, float(n.every)])
			if gentle and int(n.helpers) > 0:
				why.append("%s: calls helpers in gentle mode" % tag)
			if int(n.helpers) > 2:
				why.append("%s: calls %d helpers" % [tag, int(n.helpers)])
			if int(n.shots_now) > 9:
				why.append("%s: a fan of %d fireballs" % [tag, int(n.shots_now)])
	if float(d.radius) > 8.0:
		why.append("%s: its stomp reaches %.0f m (the temple is 6 m)" % [kind, float(d.radius)])
	return why
