extends RefCounted
## ELEMENTAL BENDER boons and element masters: run-long gifts, picked picture-first on Kiko's ALTAR.
## - MASTERS: before a run (the "GET READY" breather) the altar shows a stone per unlocked master; everyone bends one
##   (shoot / punch it, or walk onto it): you start on that element and get its twist for the whole run.
##     FIRE MASTER   fire hits harder              WATER MASTER  Healing Tide heals everyone near you
##     EARTH MASTER  rock skin: hits hurt less     AIR MASTER    bigger pushes, a bigger Tornado Burst
##     SPIRIT MASTER Spirit State lasts longer and fills faster
## - BOONS: in every breather after a wave the altar shows THREE gift stones (seeded per temple and wave); everyone
##   takes ONE (they stack). Nobody chooses? After WAIT seconds the middle (glowing brightest) stone is taken for
##   whoever hasn't, so little ones are never stuck. Works the same for the VR master, TV benders and Decks: the host
##   decides (net state "pick" / "perks"), every machine builds the stones and reads the perks.
## Unlocks for good as the Spirit Tree grows (saved waves cleared) and Generals fall (saved fruit): unlocked_*().
## mods(perk) turns a player's master + boons into numbers; shape_shots() applies them to that player's shots.

const E := preload("res://games/elemental_bender/elem.gd")
const PickOrbs := preload("res://core/pick_orbs.gd")
const Seeded := preload("res://core/seeded.gd")

const OFFER := 3
const WAIT := 14.0  # seconds before the middle stone is taken for whoever hasn't picked
const WAIT_FAST := 5.0
const MASTER_WAIT := 16.0
## id, name (1-2 short words: the stone's label), pic (a story picture or 3D icon kind), colour, unlock: saved
## waves cleared (Spirit Tree) or Generals beaten (fruit).
const BOONS: Array[Dictionary] = [
	{"id": "big", "name": "BIG BLASTS", "color": Color(1.0, 0.55, 0.2), "waves": 0, "generals": 0},
	{"id": "power", "name": "STRONG HITS", "color": Color(1.0, 0.3, 0.3), "waves": 0, "generals": 0},
	{"id": "shield", "name": "ROCK SHIELD", "color": Color(0.7, 0.5, 0.3), "waves": 0, "generals": 0},
	{"id": "spirit", "name": "LONG SPIRIT", "color": Color(0.75, 0.9, 1.0), "waves": 0, "generals": 0},
	{"id": "heal", "name": "HEALING RAIN", "color": Color(0.4, 1.0, 0.6), "waves": 0, "generals": 0},
	{"id": "swift", "name": "SWIFT FEET", "color": Color(0.4, 0.9, 1.0), "waves": 0, "generals": 0},
	{"id": "gale", "name": "GALE PUSH", "color": Color(0.92, 0.97, 1.0), "waves": 3, "generals": 0},
	{"id": "chi", "name": "CHI SPRING", "color": Color(0.3, 0.6, 1.0), "waves": 6, "generals": 0},
	{"id": "spark", "name": "SPIRIT SPARK", "color": Color(1.0, 0.9, 0.4), "waves": 12, "generals": 1},
	{"id": "triple", "name": "TRIPLE SHOT", "color": Color(1.0, 0.85, 0.3), "waves": 20, "generals": 2},
	{"id": "leaf", "name": "LIFE LEAF", "color": Color(0.5, 0.95, 0.35), "waves": 30, "generals": 3},
]
const MASTERS: Array[Dictionary] = [
	{"id": "fire", "name": "FIRE", "element": E.FIRE, "waves": 0, "generals": 0},
	{"id": "water", "name": "WATER", "element": E.WATER, "waves": 0, "generals": 0},
	{"id": "earth", "name": "EARTH", "element": E.EARTH, "waves": 2, "generals": 0},
	{"id": "air", "name": "AIR", "element": E.AIR, "waves": 5, "generals": 0},
	{"id": "spirit", "name": "SPIRIT", "element": -1, "waves": 999999, "generals": 3},
]


static func boon(id: String) -> Dictionary:
	for b in BOONS:
		if String(b.id) == id:
			return b
	return {}


static func master(id: String) -> Dictionary:
	for m in MASTERS:
		if String(m.id) == id:
			return m
	return {}


static func pick_name(kind: String, id: String) -> String:
	if kind == "mode":
		return PickOrbs.mode_name(id)  # (GENTLE / BRAVE / HARD: the shared names)
	return String((master(id) if kind == "master" else boon(id)).get("name", id.to_upper()))


static func pick_color(kind: String, id: String) -> Color:
	if kind == "mode":
		return PickOrbs.mode_color(id)
	if kind == "master":
		var e := int(master(id).get("element", -1))
		return E.COLORS[e] if e >= 0 else Color(1.0, 0.95, 0.7)
	return boon(id).get("color", Color.WHITE)


static func _open(list: Array[Dictionary], waves: int, generals: int) -> Array[String]:
	var out: Array[String] = []
	for d in list:
		if waves >= int(d.waves) or (int(d.generals) > 0 and generals >= int(d.generals)):
			out.append(String(d.id))
	return out


static func unlocked_boons(waves: int, generals: int) -> Array[String]:
	return _open(BOONS, waves, generals)


static func unlocked_masters(waves: int, generals: int) -> Array[String]:
	return _open(MASTERS, waves, generals)


## The three gift stones after wave n of a temple (distinct, from the unlocked ones; seeded).
static func offer(temple_seed: int, n: int, open: Array) -> Array:
	var pool := Seeded.shuffled(Seeded.rng(Seeded.derive(temple_seed, "boons%d" % n), "offer"), open.duplicate())
	return pool.slice(0, mini(OFFER, pool.size()))


## Problems with an offer (empty = fair).
static func check_offer(ids: Array, open: Array) -> Array[String]:
	var why: Array[String] = []
	if ids.size() != mini(OFFER, open.size()):
		why.append("an altar with %d stones" % ids.size())
	var seen := {}
	for id in ids:
		if seen.has(id):
			why.append("the altar shows %s twice" % id)
		seen[id] = true
		if not open.has(id):
			why.append("the altar shows %s before it is unlocked" % id)
		if boon(String(id)).is_empty():
			why.append("no boon called %s" % id)
		elif String(boon(String(id)).name).length() > 13:
			why.append("%s's name is too long for a stone" % id)
	return why


## A player's numbers from perk {"m": master id, "b": [boon ids]}.
static func mods(perk: Dictionary) -> Dictionary:
	var m := {"dmg": 1.0, "radius": 1.0, "knock": 1.0, "taken": 1.0, "spirit_time": 0.0, "speed": 1.0, "chi_cost": 1.0,
		"spirit_fill": 1.0, "triple": false, "leaf": 0.0, "heal_wave": 0.0, "fire_dmg": 1.0, "tornado": 9.0,
		"team_heal": false}
	match String(perk.get("m", "")):
		"fire":
			m.fire_dmg = 1.3
		"water":
			m.team_heal = true
		"earth":
			m.taken *= 0.8
		"air":
			m.knock *= 1.4
			m.tornado = 12.0
		"spirit":
			m.spirit_time += 5.0
			m.spirit_fill *= 1.3
	for id in perk.get("b", []):
		match String(id):
			"big":
				m.radius *= 1.35
				m.dmg *= 1.1
			"power":
				m.dmg *= 1.25
			"shield":
				m.taken *= 0.75
			"spirit":
				m.spirit_time += 6.0
			"heal":
				m.heal_wave += 30.0
			"swift":
				m.speed *= 1.2
			"gale":
				m.knock *= 1.6
			"chi":
				m.chi_cost *= 0.6
			"spark":
				m.spirit_fill *= 1.5
			"triple":
				m.triple = true
			"leaf":
				m.leaf += 6.0
	m.dmg = minf(m.dmg, 3.0)
	m.radius = minf(m.radius, 2.2)
	m.knock = minf(m.knock, 3.0)
	m.taken = maxf(m.taken, 0.35)
	m.speed = minf(m.speed, 1.6)
	m.chi_cost = maxf(m.chi_cost, 0.3)
	m.spirit_time = minf(m.spirit_time, 18.0)
	return m


## A player's shots with their boons and master applied (on the machine that fires them: the host trusts the numbers).
static func shape_shots(m: Dictionary, shots: Array) -> Array:
	var out: Array = []
	for p0 in shots:
		var p: Dictionary = (p0 as Dictionary).duplicate()
		var dmg := float(p.get("damage", 0.0)) * float(m.dmg)
		if int(p.get("element", -1)) == E.FIRE:
			dmg *= float(m.fire_dmg)
		p["damage"] = dmg
		p["radius"] = float(p.get("radius", 0.5)) * float(m.radius)
		p["knockback"] = float(p.get("knockback", 0.0)) * float(m.knock)
		out.append(p)
	if bool(m.triple) and shots.size() == 1:
		var base: Dictionary = out[0]
		for side in [-1.0, 1.0]:
			var q := base.duplicate()
			q["vel"] = (base.get("vel", Vector3.ZERO) as Vector3).rotated(Vector3.UP, float(side) * 0.2)
			q["damage"] = float(base.damage) * 0.45
			if q.has("rise_from"):
				q.erase("rise")
				q.erase("rise_from")
			out.append(q)
	return out
