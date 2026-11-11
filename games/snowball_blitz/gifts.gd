extends RefCounted
## SNOWBALL BLITZ: BOBO'S GIFTS, picture-first picks on the shared pick orbs (core/pick_orbs.gd). After every cleared
## wave three seeded gift orbs float in front of the fort; each player takes one by THROWING a snowball at it (the VR
## player too) or WALKING into it. Little coloured dots circle an orb for everyone who took it. Nobody chooses? When the
## time runs out the middle orb (it glows brightest) is taken for whoever hasn't, so little ones are never stuck.
## Gifts stack for the rest of the game, inside CAPS (so a long endless game never breaks). Some unlock for good as
## Bobo's village grows (saved igloos): unlocked(). Also the team MODE pick (GENTLE / BRAVE / HARD) on the first game
## of a visit: core/pick_orbs.gd MODES.
## Effects are [stat, "mul"|"add", amount] on a player's gifts (player.gd gift(stat)); the host sends everyone's in the
## sticky "gifts" event, so a TV machine throws its own player's bigger / quicker snowballs too.
##   ball    snowball size and hit (player.gd throws)          throw   time between throws (TV) / packing (VR)
##   walls   the walls snow back up faster (team: added up)    armor   snowmen's snowballs hurt the walls less (team)
##   mega    a MEGA SNOWBALL at the start of every wave (2: another halfway)
##   aim     the aim assist reaches a few degrees further

const Seeded := preload("res://core/seeded.gd")

const OFFER := 3
const WAIT := {"mode": 10.0, "gift": 12.0}
const GENTLE_WAIT := 1.5  # gentle mode: this much longer to choose
const MAX_NAME := 9
## Identity values (no gift) and caps, per player.
const BASE := {"ball": 1.0, "throw": 1.0, "walls": 0.0, "armor": 1.0, "mega": 0.0, "aim": 0.0}
const CAPS := {"ball": [1.0, 1.6], "throw": [0.55, 1.0], "walls": [0.0, 3.0], "armor": [0.5, 1.0], "mega": [0.0, 2.0], "aim": [0.0, 12.0]}
## Team caps (the whole party added up / multiplied together).
const TEAM_WALLS_MAX := 4.0  # extra snow per second on every wall (the walls regrow 1.5 by themselves)
const TEAM_ARMOR_MIN := 0.5
## igloos: Bobo's village size that unlocks it.
const GIFTS: Array[Dictionary] = [
	{"id": "big", "name": "BIG BALLS", "pic": "bigsnowball", "color": Color(0.35, 0.6, 1.0), "igloos": 0, "fx": [["ball", "mul", 1.2]]},
	{"id": "quick", "name": "QUICK", "pic": "bolt", "color": Color(1.0, 0.85, 0.3), "igloos": 0, "fx": [["throw", "mul", 0.85]]},
	{"id": "walls", "name": "WALLS", "pic": "snowwall", "color": Color(0.55, 0.8, 1.0), "igloos": 0, "fx": [["walls", "add", 1.0]]},
	{"id": "hat", "name": "WARM HAT", "pic": "warmhat", "color": Color(1.0, 0.45, 0.45), "igloos": 2, "fx": [["armor", "mul", 0.85]]},
	{"id": "mega", "name": "MEGA", "pic": "megasnowball", "color": Color(0.5, 0.75, 1.0), "igloos": 4, "fx": [["mega", "add", 1.0]]},
	{"id": "aim", "name": "AIM HELP", "pic": "aimstar", "color": Color(1.0, 0.6, 0.9), "igloos": 8, "fx": [["aim", "add", 4.0]]},
]


static func find(id: String) -> Dictionary:
	for d in GIFTS:
		if String(d.id) == id:
			return d
	return {}


static func unlocked(igloos: int) -> Array[String]:
	var out: Array[String] = []
	for d in GIFTS:
		if igloos >= int(d.igloos):
			out.append(String(d.id))
	return out


## The gift orbs after wave n of a game (seeded per game and wave: every machine shows the same three).
static func offer(game_seed: int, n: int, open: Array) -> Array:
	var pool := Seeded.shuffled(Seeded.rng(Seeded.derive(game_seed, "gifts%d" % n), "offer"), open.duplicate())
	return pool.slice(0, mini(OFFER, pool.size()))


## The orb taken for whoever didn't choose (the middle one).
static func default_pick(ids: Array) -> String:
	return "" if ids.is_empty() else String(ids[ids.size() / 2])


## A player's gift value for a stat (BASE when they have none).
static func value(gifts: Dictionary, stat: String) -> float:
	return float(gifts.get(stat, BASE.get(stat, 0.0)))


## Add gift `id` to a player's gifts (a Dictionary of stats), within CAPS.
static func apply(gifts: Dictionary, id: String) -> void:
	for fx in find(id).get("fx", []):
		var k := String(fx[0])
		var v := value(gifts, k)
		gifts[k] = v * float(fx[2]) if String(fx[1]) == "mul" else v + float(fx[2])
	clamp_gifts(gifts)


static func clamp_gifts(gifts: Dictionary) -> void:
	for k in CAPS:
		if gifts.has(k):
			gifts[k] = clampf(float(gifts[k]), float(CAPS[k][0]), float(CAPS[k][1]))


## The team's extra wall regrow (snow per second) and how much a snowman's snowball hurts the walls, from every
## playing player's gifts.
static func team_walls(all: Array) -> float:
	var w := 0.0
	for g in all:
		w += value(g, "walls")
	return minf(w, TEAM_WALLS_MAX)


static func team_armor(all: Array) -> float:
	var a := 1.0
	for g in all:
		a *= value(g, "armor")
	return maxf(a, TEAM_ARMOR_MIN)


## Problems with an offer (empty = fair).
static func check_offer(ids: Array, open: Array) -> Array[String]:
	var why: Array[String] = []
	if ids.size() != mini(OFFER, open.size()):
		why.append("%d gift orbs (want %d)" % [ids.size(), mini(OFFER, open.size())])
	var seen := {}
	for id in ids:
		if seen.has(id):
			why.append("%s twice" % id)
		seen[id] = true
		if not open.has(id):
			why.append("%s before it is unlocked" % id)
		if find(String(id)).is_empty():
			why.append("no gift called %s" % id)
	return why


## Problems with the gift list (empty = fine): names fit an orb, pictures exist (has_pic), every effect's stat is capped,
## a new family has a full offer, and a player who took every gift 30 times stays inside the caps (and the team ones).
static func check_lists(has_pic: Callable) -> Array[String]:
	var why: Array[String] = []
	var ids := {}
	for d in GIFTS:
		if ids.has(d.id):
			why.append("%s twice" % d.id)
		ids[d.id] = true
		if String(d.name).length() > MAX_NAME:
			why.append("%s's name is too long for an orb" % d.id)
		if not bool(has_pic.call(String(d.pic))):
			why.append("%s: no picture %s" % [d.id, d.pic])
		for fx in d.fx:
			if not CAPS.has(String(fx[0])):
				why.append("%s: %s has no cap" % [d.id, fx[0]])
	if unlocked(0).size() < OFFER:
		why.append("a new family has fewer than %d gifts" % OFFER)
	var g := {}
	for i in 30:
		for d in GIFTS:
			apply(g, String(d.id))
	for k in CAPS:
		var v := value(g, k)
		if v < float(CAPS[k][0]) - 0.001 or v > float(CAPS[k][1]) + 0.001:
			why.append("stacked %s = %.2f is outside its cap" % [k, v])
	if value(g, "ball") * 0.14 > 0.3 or value(g, "ball") * 1.6 > 3.0:
		why.append("stacked big snowballs are bigger than the host accepts")
	var party: Array = []
	for i in 7:
		party.append(g)
	if team_walls(party) > TEAM_WALLS_MAX or team_armor(party) < TEAM_ARMOR_MIN:
		why.append("a stacked party breaks the team caps")
	for id in ["mode", "gift"]:
		if not WAIT.has(id):
			why.append("no wait for %s" % id)
	return why