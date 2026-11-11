extends RefCounted
## DUO ARENA seeded arenas, routes and the wave curve (no nodes: zone.gd builds what this describes).
## - ZONES: NEON CITY (home), DINO JUNGLE (mud geysers), LAVA RIM (lava vents), ICE RINK (frost puffs), STAR DECK
##   (zap pads). A run starts in NEON CITY; after each boss (waves 5, 10, ...) Nova warps the arena to the next zone
##   of the run's ROUTE (seeded from the unlocked zones: saved waves cleared over all days open new ones).
## - layout(seed, zone): cover pillars and hazard pads, seeded. check() proves it fair: nothing on the start spots
##   or the pick orbs, nothing overlapping, inside the wall, and every open spot of the floor reachable on foot.
## - plan(n, mode, players): wave n's monsters (count, toughness, speed, bite, gap, most at once) for GENTLE (little
##   ones), BRAVE (normal) or HARD. check_curve() proves the curve smooth: every wave a little harder than the last
##   (never a cliff), gentle <= brave <= hard, and a gentle solo wave 1 is tiny.
## - Pads TELL first (glow + hiss for tell seconds), then burst. tell/damage per mode: hazard_numbers().
## Used by main.gd (host decides, sends "zone" [seed, zone, leg] to every machine) and tests/duo_arena_gen_test.gd.

const Seeded := preload("res://core/seeded.gd")

const GAME_ID := "duo_arena"
const ARENA_RADIUS := 18.0
const FINALE_WAVE := 15
const LEG := 5  # waves per zone (a boss ends every leg)
const MODES: Array[String] = ["gentle", "brave", "hard"]
## Keep clear: the players' start spots and the pick orbs (main.gd PRACTICE_SPOTS / zone.gd ORB_ROW).
const SAFE_SPOTS: Array[Vector3] = [Vector3.ZERO, Vector3(-2.5, 0, 4), Vector3(2.5, 0, 4), Vector3(7.5, 0, 4),
	Vector3(-6, 0, 7.5), Vector3(-2, 0, 7.5), Vector3(2, 0, 7.5), Vector3(6, 0, 7.5),
	Vector3(-5.2, 0, -3.5), Vector3(-2.6, 0, -3.5), Vector3(0, 0, -3.5), Vector3(2.6, 0, -3.5), Vector3(5.2, 0, -3.5)]
const SAFE_R := 2.5
const PILLAR_HALF := 1.0  # pillars are 2 x 2 m
const MIN_TELL := 1.2
const GENTLE_TELL := 2.2
const MAX_PAD_HIT := 14.0
## id, name (short: a banner), pic (story picture), floor line colour (mood), floor base, hazard, unlock (waves).
const ZONES: Array[Dictionary] = [
	{"id": "neon", "name": "NEON CITY", "pic": "neoncity", "line": Color(0.15, 0.75, 1.0), "base": Color(0.07, 0.08, 0.11),
		"hazard": "", "waves": 0},
	{"id": "jungle", "name": "DINO JUNGLE", "pic": "junglezone", "line": Color(0.35, 1.0, 0.35), "base": Color(0.05, 0.1, 0.05),
		"hazard": "geyser", "waves": 3},
	{"id": "lava", "name": "LAVA RIM", "pic": "lavazone", "line": Color(1.0, 0.4, 0.1), "base": Color(0.12, 0.05, 0.04),
		"hazard": "lava", "waves": 8},
	{"id": "ice", "name": "ICE RINK", "pic": "icezone", "line": Color(0.6, 0.9, 1.0), "base": Color(0.12, 0.15, 0.2),
		"hazard": "frost", "waves": 15},
	{"id": "star", "name": "STAR DECK", "pic": "starzone", "line": Color(0.8, 0.45, 1.0), "base": Color(0.06, 0.04, 0.12),
		"hazard": "zap", "waves": 25},
]
## Hazard pads: colour, damage (brave), push, a sound.
const HAZARDS := {
	"geyser": {"color": Color(0.55, 0.85, 0.3), "damage": 8.0, "push": 9.0},
	"lava": {"color": Color(1.0, 0.35, 0.05), "damage": 11.0, "push": 6.0},
	"frost": {"color": Color(0.7, 0.95, 1.0), "damage": 7.0, "push": 11.0},
	"zap": {"color": Color(0.85, 0.5, 1.0), "damage": 10.0, "push": 7.0},
}
## Mode numbers: monsters (count / toughness / speed / bite), pad tell + damage, boss gentleness (bosses.gd).
const MODE_NUM := {
	"gentle": {"count": 0.6, "hp": 0.7, "grow": 0.07, "speed": 0.8, "bite": 0.5, "alive": 0.6, "gap": 1.4},
	"brave": {"count": 1.0, "hp": 1.0, "grow": 0.12, "speed": 1.0, "bite": 1.0, "alive": 1.0, "gap": 1.0},
	"hard": {"count": 1.3, "hp": 1.3, "grow": 0.13, "speed": 1.12, "bite": 1.25, "alive": 1.3, "gap": 0.8},
}


static func zone(id: String) -> Dictionary:
	for z in ZONES:
		if String(z.id) == id:
			return z
	return ZONES[0]


static func zone_ids() -> Array[String]:
	var out: Array[String] = []
	for z in ZONES:
		out.append(String(z.id))
	return out


static func unlocked_zones(waves_total: int) -> Array[String]:
	var out: Array[String] = []
	for z in ZONES:
		if waves_total >= int(z.waves):
			out.append(String(z.id))
	return out


## TODAY'S ARENA: the same seed on every machine all day.
static func daily_seed(date: String = "") -> int:
	return Seeded.daily_seed(GAME_ID, date)


## The run's zones, one per leg of LEG waves: NEON CITY first, then the other unlocked zones in a seeded order
## (each once before any repeats). Endless runs keep cycling.
static func route(seed_value: int, open: Array) -> Array[String]:
	var others: Array = []
	for z in open:
		if String(z) != "neon":
			others.append(String(z))
	var r := Seeded.rng(seed_value, "route")
	var out: Array[String] = ["neon"]
	out.append_array(Seeded.shuffled(r, others))
	return out


## Which zone wave n is fought in (leg = (n - 1) / LEG).
static func zone_for_wave(rt: Array, n: int) -> String:
	if rt.is_empty():
		return "neon"
	return String(rt[(maxi(1, n) - 1) / LEG % rt.size()])


## The seed of one leg's layout.
static func leg_seed(seed_value: int, leg: int) -> int:
	return Seeded.derive(seed_value, "leg%d" % leg)


## A zone's arena: {"zone", "pillars": [Vector3], "pads": [{p, r, period, offset}]}.
static func layout(seed_value: int, zone_id: String) -> Dictionary:
	var r := Seeded.rng(seed_value, "layout_" + zone_id)
	var pillars: Array = []
	var want := r.randi_range(3, 6)
	var tries := 0
	while pillars.size() < want and tries < 200:
		tries += 1
		var a := r.randf() * TAU
		var d := r.randf_range(6.5, 13.0)
		var p := Vector3(cos(a) * d, 0.0, sin(a) * d).snapped(Vector3(0.5, 1.0, 0.5))
		if _near_safe(p, PILLAR_HALF * 1.5):
			continue
		var ok := true
		for q in pillars:
			if (q as Vector3).distance_to(p) < 5.0:
				ok = false
				break
		if ok:
			pillars.append(p)
	var pads: Array = []
	if String(zone(zone_id).hazard) != "":
		var npads := r.randi_range(3, 5)
		tries = 0
		while pads.size() < npads and tries < 300:
			tries += 1
			var a := r.randf() * TAU
			var d := r.randf_range(6.0, 14.0)
			var p := Vector3(cos(a) * d, 0.0, sin(a) * d).snapped(Vector3(0.5, 1.0, 0.5))
			var rad := snappedf(r.randf_range(1.5, 2.2), 0.1)
			if _near_safe(p, rad):
				continue
			var ok := true
			for q in pillars:
				if _pad_hits_pillar(p, rad, q):
					ok = false
			for q in pads:
				if (q.p as Vector3).distance_to(p) < rad + float(q.r) + 1.5:
					ok = false
			if ok:
				pads.append({"p": p, "r": rad, "period": snappedf(r.randf_range(6.0, 9.0), 0.1),
					"offset": snappedf(r.randf_range(3.0, 7.0), 0.1)})
	return {"zone": zone_id, "pillars": pillars, "pads": pads}


static func _near_safe(p: Vector3, r: float) -> bool:
	for s in SAFE_SPOTS:
		if s.distance_to(p) < SAFE_R + r:
			return true
	return false


static func _pad_hits_pillar(p: Vector3, rad: float, q: Vector3) -> bool:
	return absf(p.x - q.x) < PILLAR_HALF + rad + 0.5 and absf(p.z - q.z) < PILLAR_HALF + rad + 0.5


## Problems with a layout (empty = fair).
static func check(lay: Dictionary) -> Array[String]:
	var why: Array[String] = []
	var zid := String(lay.get("zone", ""))
	if zone(zid).id != zid:
		why.append("no zone called %s" % zid)
	var pillars: Array = lay.get("pillars", [])
	var pads: Array = lay.get("pads", [])
	if pillars.size() < 2:
		why.append("only %d pillars to hide behind" % pillars.size())
	for i in pillars.size():
		var p: Vector3 = pillars[i]
		if Vector2(p.x, p.z).length() + PILLAR_HALF * 1.5 > ARENA_RADIUS - 3.0:
			why.append("pillar %d sits too near the wall (monsters come in there)" % i)
		if _near_safe(p, PILLAR_HALF):
			why.append("pillar %d stands on a start spot or a pick orb" % i)
		for j in range(i + 1, pillars.size()):
			if p.distance_to(pillars[j]) < 4.0:
				why.append("pillars %d and %d squash the path between them" % [i, j])
	for i in pads.size():
		var d: Dictionary = pads[i]
		var p: Vector3 = d.p
		if Vector2(p.x, p.z).length() + float(d.r) > ARENA_RADIUS - 1.0:
			why.append("pad %d pokes through the wall" % i)
		if _near_safe(p, float(d.r)):
			why.append("pad %d is on a start spot or a pick orb" % i)
		if float(d.period) < GENTLE_TELL + 3.0:
			why.append("pad %d bursts every %.1f s (no rest between)" % [i, float(d.period)])
		for q in pillars:
			if _pad_hits_pillar(p, float(d.r), q):
				why.append("pad %d is under a pillar" % i)
		for j in range(i + 1, pads.size()):
			if p.distance_to(pads[j].p) < float(d.r) + float(pads[j].r) + 1.0:
				why.append("pads %d and %d touch (no safe path between)" % [i, j])
	if zone(zid).hazard != "" and pads.is_empty():
		why.append("%s has no hazard pads" % zid)
	if zone(zid).hazard == "" and not pads.is_empty():
		why.append("%s has pads but no hazard" % zid)
	why.append_array(_reach(pillars))
	return why


## Flood fill on a 1 m grid: every open cell inside the wall can be walked to from the middle.
static func _reach(pillars: Array) -> Array[String]:
	var lim := int(ARENA_RADIUS) - 1
	var open := {}
	for x in range(-lim, lim + 1):
		for z in range(-lim, lim + 1):
			var c := Vector2(x, z)
			if c.length() > ARENA_RADIUS - 1.0:
				continue
			var blocked := false
			for q in pillars:
				if absf(x - q.x) <= PILLAR_HALF + 0.4 and absf(z - q.z) <= PILLAR_HALF + 0.4:
					blocked = true
					break
			if not blocked:
				open[c] = true
	if not open.has(Vector2.ZERO):
		return ["the middle is blocked"]
	var seen := {Vector2.ZERO: true}
	var todo: Array = [Vector2.ZERO]
	while not todo.is_empty():
		var c: Vector2 = todo.pop_back()
		for dv in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var n: Vector2 = c + dv
			if open.has(n) and not seen.has(n):
				seen[n] = true
				todo.append(n)
	if seen.size() < open.size():
		return ["%d spots of floor can't be reached" % (open.size() - seen.size())]
	return []


## Wave n's monsters for a mode and party size. boss waves: half the monsters (the boss is the star).
static func plan(n: int, mode: String, players: int) -> Dictionary:
	var m: Dictionary = MODE_NUM.get(mode, MODE_NUM.brave)
	var extra := maxi(0, players - 2)
	var w := maxi(1, n)
	var count := int(round((8 + w * 2.3) * (1.0 + 0.3 * extra) * float(m.count)))
	if mode == "gentle" and players <= 1:
		count = int(round(count * 0.8))
	count = maxi(2, count)
	var boss := w % LEG == 0
	return {"wave": w, "count": maxi(2, count / 2) if boss else count, "base_count": count, "boss": boss,
		"hp": (1.0 + (w - 1) * float(m.grow)) * float(m.hp),
		"speed": (1.0 + minf(w, 12) * 0.03) * float(m.speed),
		"bite": float(m.bite),
		"alive": int(round((8 + w + 3 * extra) * float(m.alive))),
		"gap": maxf(0.25, 1.1 - w * 0.07) / (1.0 + 0.15 * extra) * float(m.gap)}


## How hard a wave feels (one number): monsters x toughness x speed x bite, a little more when they come faster.
## (A boss wave counts its monsters before halving: the boss stands in for the other half.)
static func threat(p: Dictionary) -> float:
	return float(p.base_count) * float(p.hp) * float(p.speed) * (0.5 + 0.5 * float(p.bite)) * (1.0 + 0.1 / maxf(0.25, float(p.gap)))


## Problems with the wave curve of a mode + party (empty = smooth).
static func check_curve(mode: String, players: int, waves: int = 20) -> Array[String]:
	var why: Array[String] = []
	var prev := 0.0
	for n in range(1, waves + 1):
		var p := plan(n, mode, players)
		var t := threat(p)
		if prev > 0.0:
			if t < prev * 0.98:
				why.append("%s x%d: wave %d is easier than the wave before" % [mode, players, n])
			var cliff := 1.6 if n <= 2 else 1.4
			if t > prev * cliff:
				why.append("%s x%d: wave %d jumps %.0f%% harder" % [mode, players, n, (t / prev - 1.0) * 100.0])
		prev = t
		if int(p.alive) < 3:
			why.append("%s x%d: wave %d lets only %d monsters out" % [mode, players, n, int(p.alive)])
	var g := threat(plan(1, "gentle", 1))
	if int(plan(1, "gentle", 1).count) > 6:
		why.append("gentle solo wave 1 has %d monsters (little ones need a tiny start)" % int(plan(1, "gentle", 1).count))
	if mode != "gentle" and threat(plan(3, mode, players)) < threat(plan(3, "gentle", players)):
		why.append("%s is easier than gentle" % mode)
	if mode == "hard" and threat(plan(3, mode, players)) < threat(plan(3, "brave", players)):
		why.append("hard is easier than brave")
	if g <= 0.0:
		why.append("gentle wave 1 is empty")
	return why


## A pad's tell and damage in a mode.
static func hazard_numbers(hazard: String, mode: String) -> Dictionary:
	var h: Dictionary = HAZARDS.get(hazard, {"color": Color.WHITE, "damage": 0.0, "push": 0.0})
	var tell := GENTLE_TELL if mode == "gentle" else (MIN_TELL + 0.1 if mode == "hard" else MIN_TELL + 0.4)
	var dmg := float(h.damage) * (0.5 if mode == "gentle" else (1.25 if mode == "hard" else 1.0))
	return {"tell": tell, "damage": dmg, "push": float(h.push), "color": h.color}


## Problems with the hazards' numbers (empty = fair).
static func check_hazards() -> Array[String]:
	var why: Array[String] = []
	for hz in HAZARDS:
		for mode in MODES:
			var n := hazard_numbers(hz, mode)
			if float(n.tell) < (GENTLE_TELL if mode == "gentle" else MIN_TELL):
				why.append("%s %s: warns only %.1f s" % [hz, mode, float(n.tell)])
			if float(n.damage) > MAX_PAD_HIT:
				why.append("%s %s: hits for %.0f" % [hz, mode, float(n.damage)])
	return why


## How many city lights (the pylons round the arena, zone.gd) a family has lit: one per wave cleared, ever.
const LIGHTS := 40
static func lights(waves_total: int) -> int:
	return clampi(waves_total, 0, LIGHTS)
