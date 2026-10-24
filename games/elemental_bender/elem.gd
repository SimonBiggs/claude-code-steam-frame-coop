extends RefCounted
## ELEMENTAL BENDER: shared element data (names, colours, the counter cycle) and the attack recipes
## used by every bender (TV benders and the VR master), so the host and the TV machine build the
## exact same shots from the same inputs.
## Counter cycle: AIR > EARTH > WATER > FIRE > AIR. A counter hit does x2 damage (yellow "!" number),
## the same element does x0.5 (grey number), anything else x1.

const MeshKit := preload("res://core/mesh_kit.gd")

const AIR := 0
const WATER := 1
const EARTH := 2
const FIRE := 3
const NAMES: Array[String] = ["AIR", "WATER", "EARTH", "FIRE"]
const COLORS: Array[Color] = [Color(0.9, 0.95, 1.0), Color(0.15, 0.5, 1.0), Color(0.35, 0.75, 0.2), Color(1.0, 0.4, 0.08)]
const ROBES: Array[Color] = [Color(0.95, 0.65, 0.2), Color(0.2, 0.35, 0.7), Color(0.25, 0.5, 0.2), Color(0.65, 0.12, 0.1)]
## BEATS[a] is the element that a deals double damage to.
const BEATS: Array[int] = [EARTH, FIRE, WATER, AIR]
const ROCK := Color(0.5, 0.38, 0.25)
const SPECIALS: Array[String] = ["TORNADO BURST!", "HEALING TIDE!", "EARTHQUAKE!", "FIRE NOVA!"]
const SPECIAL_COST: Array[float] = [30.0, 35.0, 40.0, 30.0]
const ATTACK_CD: Array[float] = [0.35, 0.4, 0.75, 0.16]
const SPIRIT_TIME := 12.0
## Element sounds (core/sfx.gd names).
const SOUNDS: Array[String] = ["whoosh", "splash", "crash", "fire"]


## Damage multiplier of an `attacker` element hitting a `target` element (-1 = no element).
static func multiplier(attacker: int, target: int) -> float:
	if attacker < 0 or target < 0:
		return 1.0
	if BEATS[attacker] == target:
		return 2.0
	if attacker == target:
		return 0.5
	return 1.0


## The element that beats `e` (what a practice dummy of element e glows in).
static func beater(e: int) -> int:
	return BEATS.find(e)


## Cached plain material (MeshKit's cache: survives hot reloads, freed at exit).
static func mat(c: Color, glow: float = 0.0) -> StandardMaterial3D:
	return MeshKit.material(c, glow)


## The primary attack of element `e` fired from `from` along `aim` by a bender standing at `feet`
## looking along `fwd`. `power` scales damage (VR left-hand jabs are weaker). Returns shot dictionaries
## (see projectile.gd). Earth rocks rise out of the ground in front of the bender before they fly.
static func primary_shots(e: int, from: Vector3, aim: Vector3, feet: Vector3, fwd: Vector3, power: float = 1.0) -> Array:
	var p := {"element": e, "team": 0, "pos": from}
	match e:
		AIR:
			p.merge({"vel": aim * 26.0, "damage": 7.0, "knockback": 18.0, "radius": 0.7, "life": 0.8, "pierce": true})
		WATER:
			p.merge({"vel": aim * 23.0, "damage": 13.0, "knockback": 6.0, "radius": 0.5, "life": 1.3, "effect": "slow"})
		EARTH:
			var low := feet + fwd * 1.4 + Vector3.DOWN * 0.5
			p.merge({"vel": aim * 20.0, "damage": 26.0, "knockback": 12.0, "radius": 0.6, "life": 1.6,
				"effect": "stun", "rise": 0.15, "rise_from": low, "pos": low + Vector3.UP * 1.7})
		_:
			p.merge({"vel": aim * 32.0, "damage": 9.0, "knockback": 3.0, "radius": 0.35, "life": 1.0})
	p["damage"] = float(p["damage"]) * power
	return [p]


## Spirit State: all four elements at once, fanned out a little.
static func spirit_shots(from: Vector3, aim: Vector3, feet: Vector3, fwd: Vector3) -> Array:
	var out: Array = []
	for e in 4:
		var a := aim.rotated(Vector3.UP, (e - 1.5) * 0.12)
		out.append_array(primary_shots(e, from, a, feet, fwd))
	return out


## Fire Nova: a ring of 18 blazing fireballs around `here`.
static func nova_shots(here: Vector3) -> Array:
	var out: Array = []
	for i in 18:
		var d := Vector3(cos(i * TAU / 18.0), 0.0, sin(i * TAU / 18.0))
		out.append({"element": FIRE, "team": 0, "pos": here + Vector3.UP * 1.1 + d * 0.6, "vel": d * 22.0,
			"damage": 14.0, "knockback": 7.0, "radius": 0.45, "life": 0.9, "pierce": true})
	return out


## Shots as plain arrays for net events: [e, team, pos, vel, radius, life, rise, rise_from].
static func pack_shot(p: Dictionary) -> Array:
	return [int(p.get("element", FIRE)), int(p.get("team", 0)), p.get("pos", Vector3.ZERO), p.get("vel", Vector3.ZERO),
		snappedf(float(p.get("radius", 0.5)), 0.01), snappedf(float(p.get("life", 1.0)), 0.01),
		float(p.get("rise", 0.0)), p.get("rise_from", Vector3.ZERO)]


static func unpack_shot(a: Array) -> Dictionary:
	var p := {"element": int(a[0]), "team": int(a[1]), "pos": a[2], "vel": a[3], "radius": float(a[4]), "life": float(a[5])}
	if float(a[6]) > 0.0:
		p["rise"] = float(a[6])
		p["rise_from"] = a[7]
	return p
