extends RefCounted
## ELEMENTAL BENDER arenas: the run moves from island to island. Every 5 waves (a SEGMENT, ending with that island's
## boss) the team travels to the next island Kiko's spirit portal finds: TEMPLE ISLAND first (home: the classic
## island, calm, the Shadow General), then the islands the family has unlocked, in a seeded order:
##   ICE SHELF    snow and ice spikes on a cold sea; FROST GEYSERS puff up and push you (boss: the FROST GIANT)
##   VOLCANO RIM  black rock and glowing crystals in a lava sea; LAVA VENTS bubble, then burst (the LAVA DRAKE)
##   SKY RUINS    broken columns on an island in the clouds; WIND SPOUTS blow you away (the STORM HAWK)
## Islands unlock for good as the Spirit Tree grows and Generals fall (unlocked()). Every island has the same shape
## (the temple dais, four platforms, the beach), so portals, VR walking and the camera work everywhere; its props,
## colours, sky, sea and hazard differ. Props and hazards are seeded from the temple seed (TEMPLE ISLAND keeps its
## classic layout, seed 7), so every machine builds the same island from [arena id, temple seed].
## check(id, seed) is the validator: vents on open ground, away from the temple, the altar, the tree and each other,
## with a long enough warning glow; and every spot of open ground (portals, the altar) is reachable on foot from the
## temple (a flood fill over a 1 m grid).

const Seeded := preload("res://core/seeded.gd")

const ISLAND_R := 36.0  # == world.gd
const CLASSIC_SEED := 7
const SEGMENT := 5  # waves per island (the 5th is its boss)
const TREE_AT := Vector3(-12.5, 0.0, -5.0)  # == wavegen.gd (the Spirit Tree)
## The altar stones (picks between waves) stand in a row in front of the temple.
const ALTAR_Z := -11.0
const ALTAR_HALF := 8.0  # metres either side of the middle
## Hazard vents.
const VENT_R := Vector2(12.5, 18.0)  # between the temple steps and the portals
const VENT_GAP := 7.0
const VENT_CLEAR := 0.6
const MIN_TELL := 1.5  # seconds of warning glow (gentle: GENTLE_TELL)
const GENTLE_TELL := 2.4
const MAX_HAZARD_DMG := 12.0
const GRID := 1.0

const LIST: Array[Dictionary] = [
	{"id": "temple", "name": "TEMPLE ISLAND", "pic": "spirittree", "sky": "sunset", "ground": Color(0.36, 0.6, 0.28),
		"shore": Color(0.9, 0.82, 0.6), "sea": Color(0.1, 0.4, 0.65), "sea_glow": 0.0, "stone": Color(0.75, 0.72, 0.65),
		"hazard": "", "boss": "general", "generals": 0, "waves": 0},
	{"id": "ice", "name": "ICE SHELF", "pic": "iceshelf", "sky": "snowy", "ground": Color(0.74, 0.84, 0.94),
		"shore": Color(0.62, 0.8, 0.92), "sea": Color(0.06, 0.28, 0.42), "sea_glow": 0.0, "stone": Color(0.7, 0.8, 0.9),
		"hazard": "frost", "boss": "giant", "generals": 1, "waves": 8},
	{"id": "volcano", "name": "VOLCANO RIM", "pic": "volcano", "sky": "sunset", "ground": Color(0.3, 0.24, 0.23),
		"shore": Color(0.14, 0.12, 0.12), "sea": Color(1.0, 0.38, 0.08), "sea_glow": 1.6, "stone": Color(0.42, 0.36, 0.34),
		"hazard": "lava", "boss": "drake", "generals": 2, "waves": 16},
	{"id": "sky", "name": "SKY RUINS", "pic": "skyruins", "sky": "day", "ground": Color(0.5, 0.72, 0.42),
		"shore": Color(0.8, 0.78, 0.72), "sea": Color(0.95, 0.96, 1.0), "sea_glow": 0.15, "stone": Color(0.88, 0.85, 0.78),
		"hazard": "wind", "boss": "hawk", "generals": 3, "waves": 26},
]
## Hazards: what a vent does when it bursts (fighters / raiders inside its radius).
const HAZARDS := {
	"frost": {"name": "FROST GEYSER", "color": Color(0.7, 0.92, 1.0), "dmg": 5.0, "push": 9.0, "lift": 6.0, "raider_dmg": 8.0, "effect": "freeze", "period": Vector2(7.0, 10.0)},
	"lava": {"name": "LAVA VENT", "color": Color(1.0, 0.45, 0.1), "dmg": 10.0, "push": 6.0, "lift": 7.0, "raider_dmg": 25.0, "effect": "", "period": Vector2(7.5, 10.5)},
	"wind": {"name": "WIND SPOUT", "color": Color(0.9, 1.0, 0.95), "dmg": 3.0, "push": 16.0, "lift": 9.0, "raider_dmg": 6.0, "effect": "", "period": Vector2(6.5, 9.0)},
}

static var _lay_cache := {}
static var _reach_cache := {}


static func ids() -> Array[String]:
	var out: Array[String] = []
	for a in LIST:
		out.append(String(a.id))
	return out


static func info(id: String) -> Dictionary:
	for a in LIST:
		if String(a.id) == id:
			return a
	return LIST[0]


## The islands this family has opened (saved Generals beaten / waves cleared over all days).
static func unlocked(generals: int, waves: int) -> Array[String]:
	var out: Array[String] = []
	for a in LIST:
		if generals >= int(a.generals) or waves >= int(a.waves):
			out.append(String(a.id))
	return out


## The island of segment k (waves k*SEGMENT+1 .. (k+1)*SEGMENT) of a temple: a round trip that starts at home
## (TEMPLE ISLAND, then the other unlocked islands in a seeded order, then home again...). "open" = unlocked() when the
## segment starts (one may open mid-run); prev: the island the run is on now (never the same island twice in a row).
static func arena_for(temple_seed: int, k: int, open: Array, prev: String = "") -> String:
	if k <= 0:
		return "temple"
	var others: Array = []
	for id in ids():
		if id != "temple" and open.has(id):
			others.append(id)
	var route: Array = ["temple"]
	route.append_array(Seeded.shuffled(Seeded.rng(temple_seed, "islands"), others))
	if route.size() == 1:
		return "temple"
	var pick := String(route[k % route.size()])
	if pick == prev:
		pick = String(route[(k + 1) % route.size()])
	return pick


static func segment_of(wave: int) -> int:
	return maxi(0, int((maxi(1, wave) - 1) / SEGMENT))


## The seed an island's props and vents are built from (TEMPLE ISLAND: the classic layout).
static func layout_seed(temple_seed: int, id: String) -> int:
	return CLASSIC_SEED if id == "temple" else Seeded.derive(temple_seed, "isle_" + id)


## The four training platforms' centres (5 x 5 m boxes, the stepping stone 4 m further in).
static func platforms() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in 4:
		out.append(Vector3(cos(i * TAU / 4.0), 0, sin(i * TAU / 4.0)) * 19.0)
	return out


## An island's props and the far scenery, cached:
## {props: [{kind, p, r, ...}], mountains: [[angle, dist, height]], vents: [{p, r, period, offset}]}.
## Prop kinds: tree (h, cones, color), rock (size, rot), spike / crystal (h), pine (h), column (h), deadtree (h).
static func layout(id: String, seed_value: int) -> Dictionary:
	var key := "%s:%d" % [id, seed_value]
	if _lay_cache.has(key):
		return _lay_cache[key]
	if _lay_cache.size() > 24:
		_lay_cache.clear()
	var lay := _classic() if id == "temple" else _themed(id, seed_value)
	lay["id"] = id
	lay["seed"] = seed_value
	lay["vents"] = _vents(id, seed_value, lay)
	_lay_cache[key] = lay
	return lay


## TEMPLE ISLAND: exactly the source game's island (seed 7: 34 trees and rocks).
static func _classic() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = CLASSIC_SEED
	var props: Array = []
	while props.size() < 34:
		var a := rng.randf() * TAU
		var r := rng.randf_range(11.0, ISLAND_R - 2.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var clear := true
		for q in platforms():
			if p.distance_to(q) < 6.0:
				clear = false
		if not clear:
			continue
		if rng.randf() < 0.7:
			var h := rng.randf_range(2.5, 4.0)
			var cones := rng.randf() < 0.5
			var col := Color(0.25, 0.55, 0.25)
			if not cones:
				col = Color(1.0, 0.65, 0.78) if rng.randf() < 0.5 else Color(0.25, 0.55, 0.25)
			props.append({"kind": "tree", "p": p, "h": h, "cones": cones, "color": col, "r": 0.28})
		else:
			var size := rng.randf_range(0.8, 1.8)
			var rot := Vector3(rng.randf(), rng.randf() * 3.0, rng.randf())
			props.append({"kind": "rock", "p": p, "size": size, "rot": rot, "r": size * 0.75})
	# (the one tree that stood where Kiko's altar is now steps aside: the same random numbers, one tree fewer)
	props = props.filter(func(pr: Dictionary) -> bool: return not _in_altar(pr.p, 0.5))
	return {"props": props, "mountains": _mountains(rng)}


static func _mountains(rng: RandomNumberGenerator) -> Array:
	var mountains: Array = []
	for i in 14:
		var a := i * TAU / 14.0 + rng.randf() * 0.3
		var d := rng.randf_range(140.0, 200.0)
		var h := rng.randf_range(40.0, 90.0)
		mountains.append([a, d, h])
	return mountains


## The other islands: seeded props of the island's own kinds, kept off the platforms, the Spirit Tree and the altar.
static func _themed(id: String, seed_value: int) -> Dictionary:
	var rng := Seeded.rng(seed_value, "props")
	var kinds: Array = {"ice": [["spike", 0.4], ["pine", 0.35], ["rock", 0.25]],
		"volcano": [["rock", 0.5], ["crystal", 0.3], ["deadtree", 0.2]],
		"sky": [["column", 0.45], ["tree", 0.3], ["rock", 0.25]]}.get(id, [["rock", 1.0]])
	var props: Array = []
	var want := 28
	var tries := 0
	while props.size() < want and tries < 600:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(11.5, ISLAND_R - 2.5)
		var p := Vector3(snappedf(cos(a) * r, 0.01), 0.0, snappedf(sin(a) * r, 0.01))
		if not _prop_spot_ok(p, props):
			continue
		var roll := rng.randf()
		var kind := "rock"
		for k in kinds:
			roll -= float(k[1])
			if roll <= 0.0:
				kind = String(k[0])
				break
		match kind:
			"rock":
				var size := rng.randf_range(0.9, 1.9)
				props.append({"kind": "rock", "p": p, "size": size, "rot": Vector3(rng.randf(), rng.randf() * 3.0, rng.randf()), "r": size * 0.75})
			"tree":
				props.append({"kind": "tree", "p": p, "h": rng.randf_range(2.5, 3.8), "cones": false,
					"color": Color(1.0, 0.65, 0.78) if rng.randf() < 0.6 else Color(0.3, 0.6, 0.3), "r": 0.28})
			"spike", "crystal":
				props.append({"kind": kind, "p": p, "h": rng.randf_range(1.6, 3.4), "rot": rng.randf() * TAU, "r": 0.7})
			"column":
				props.append({"kind": kind, "p": p, "h": rng.randf_range(1.2, 4.5), "rot": rng.randf() * TAU, "r": 0.6})
			_:
				props.append({"kind": kind, "p": p, "h": rng.randf_range(2.2, 3.6), "rot": rng.randf() * TAU, "r": 0.3})
	return {"props": props, "mountains": _mountains(rng)}


static func _prop_spot_ok(p: Vector3, props: Array) -> bool:
	for q in platforms():
		if p.distance_to(q) < 6.0:
			return false
	if Vector2(p.x - TREE_AT.x, p.z - TREE_AT.z).length() < 4.0:
		return false
	if _in_altar(p, 2.0):
		return false
	for o in props:
		if (o.p as Vector3).distance_to(p) < float(o.r) + 2.2:
			return false
	return true


static func _in_altar(p: Vector3, margin: float) -> bool:
	return absf(p.x) < ALTAR_HALF + margin and p.z < -7.0 + margin and p.z > ALTAR_Z - 3.0 - margin


## The island's hazard vents (none on TEMPLE ISLAND).
static func _vents(id: String, seed_value: int, lay: Dictionary) -> Array:
	var hz := String(info(id).hazard)
	if hz == "":
		return []
	var out := _place_vents(Seeded.rng(seed_value, "vents"), hz, lay)
	# A crowded island can leave room for only 2 of the first try's vents (check() wants 3: TODAY'S RAIDERS on
	# 2027-04-28 / 2027-07-02 would have had a 2-vent island): lay them out again until 3+ fit.
	var k := 0
	while out.size() < 3 and k < 30:
		k += 1
		out = _place_vents(Seeded.rng(seed_value, "vents%d" % k), hz, lay)
	return out


static func _place_vents(rng: RandomNumberGenerator, hz: String, lay: Dictionary) -> Array:
	var want := 4
	var out: Array = []
	var tries := 0
	var per: Vector2 = HAZARDS[hz].period
	while out.size() < want and tries < 300:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(VENT_R.x, VENT_R.y)
		var vr := snappedf(rng.randf_range(2.0, 2.6), 0.01)
		var p := Vector3(snappedf(cos(a) * r, 0.01), 0.0, snappedf(sin(a) * r, 0.01))
		var v := {"p": p, "r": vr, "period": snappedf(rng.randf_range(per.x, per.y), 0.01), "offset": snappedf(rng.randf_range(2.0, 6.0), 0.01)}
		if _vent_problems(v, out, lay).is_empty():
			out.append(v)
	return out


static func _vent_problems(v: Dictionary, others: Array, lay: Dictionary) -> Array[String]:
	var why: Array[String] = []
	var p: Vector3 = v.p
	var r := Vector2(p.x, p.z).length()
	if r < VENT_R.x - 0.02 or r > VENT_R.y + 0.02:
		why.append("a vent %.1f m from the temple" % r)
	var b := blocked(p, float(v.r) + VENT_CLEAR, lay)
	if b != "":
		why.append("a vent at (%.0f, %.0f) is %s" % [p.x, p.z, b])
	if Vector2(p.x - TREE_AT.x, p.z - TREE_AT.z).length() < float(v.r) + 3.0:
		why.append("a vent in the Spirit Tree")
	if _in_altar(p, float(v.r) + 1.0):
		why.append("a vent on the altar")
	for o in others:
		if (o.p as Vector3).distance_to(p) < VENT_GAP:
			why.append("vents at (%.0f, %.0f) and (%.0f, %.0f) are too close" % [p.x, p.z, (o.p as Vector3).x, (o.p as Vector3).z])
	if float(v.period) < GENTLE_TELL + 4.0:
		why.append("a vent bursts every %.1f s (too often)" % float(v.period))
	return why


## Why a spot on the ground is not free for something `clear` metres round (empty = free): the temple dais, a
## training platform or its stepping stone, a prop, the beach. lay: an island's layout() ({} = TEMPLE ISLAND).
static func blocked(p: Vector3, clear: float, lay: Dictionary = {}) -> String:
	if lay.is_empty():
		lay = layout("temple", CLASSIC_SEED)
	var flat := Vector2(p.x, p.z)
	if flat.length() < 8.5 + clear:
		return "on the temple steps"
	if flat.length() > ISLAND_R - 2.0 - clear:
		return "too near the sea"
	for q in platforms():
		if Vector2(q.x, q.z).distance_to(flat) < 3.6 + clear:
			return "on a training platform"
		var st := q * (15.0 / 19.0)
		if Vector2(st.x, st.z).distance_to(flat) < 1.5 + clear:
			return "on a stepping stone"
	for pr in lay.props:
		var q: Vector3 = pr.p
		if Vector2(q.x, q.z).distance_to(flat) < float(pr.r) + clear:
			return "on a %s" % pr.kind
	return ""


## Is a spot reachable on foot from the temple (flood fill over a 1 m grid round props and platforms)?
static func reachable(p: Vector3, lay: Dictionary) -> bool:
	var m: PackedByteArray = _reach(lay)
	var n := int(ceil(ISLAND_R / GRID)) * 2 + 1
	var h := int(n / 2)
	var ix := clampi(roundi(p.x / GRID) + h, 0, n - 1)
	var iz := clampi(roundi(p.z / GRID) + h, 0, n - 1)
	# (a spot may sit on the edge of a blocked cell: any reachable neighbour counts)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var x := ix + dx
			var z := iz + dz
			if x >= 0 and z >= 0 and x < n and z < n and m[z * n + x] == 2:
				return true
	return false


## 0 = blocked, 1 = open, 2 = reached from the temple.
static func _reach(lay: Dictionary) -> PackedByteArray:
	var key := "%s:%d" % [String(lay.get("id", "?")), int(lay.get("seed", 0))]
	if _reach_cache.has(key):
		return _reach_cache[key]
	if _reach_cache.size() > 24:
		_reach_cache.clear()
	var n := int(ceil(ISLAND_R / GRID)) * 2 + 1
	var h := int(n / 2)
	var m := PackedByteArray()
	m.resize(n * n)
	var rr := (ISLAND_R - 1.0) / GRID
	for z in n:
		for x in n:
			var dx := float(x - h)
			var dz := float(z - h)
			m[z * n + x] = 1 if dx * dx + dz * dz <= rr * rr else 0
	var mark := func(c: Vector3, rad: float) -> void:
		var cx := roundi(c.x / GRID) + h
		var cz := roundi(c.z / GRID) + h
		var k := int(ceil(rad / GRID))
		for z in range(maxi(0, cz - k), mini(n, cz + k + 1)):
			for x in range(maxi(0, cx - k), mini(n, cx + k + 1)):
				var wx := float(x - h) * GRID
				var wz := float(z - h) * GRID
				if Vector2(wx - c.x, wz - c.z).length() < rad:
					m[z * n + x] = 0
	for pr in lay.props:
		mark.call(pr.p, float(pr.r) + 0.3)
	for q in platforms():
		mark.call(q, 3.3)
	var queue: Array[int] = [h * n + h]
	m[h * n + h] = 2
	var qi := 0
	while qi < queue.size():
		var c: int = queue[qi]
		qi += 1
		var cx := c % n
		var cz := int(c / n)
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var x: int = cx + int(d[0])
			var z: int = cz + int(d[1])
			if x < 0 or z < 0 or x >= n or z >= n:
				continue
			var i := z * n + x
			if m[i] == 1:
				m[i] = 2
				queue.append(i)
	_reach_cache[key] = m
	return m


## Problems with one island (empty = fair): its vents, the altar spots and the far ring reachable from the temple.
static func check(id: String, seed_value: int) -> Array[String]:
	var why: Array[String] = []
	var lay := layout(id, seed_value)
	var a := info(id)
	var hz := String(a.hazard)
	var vents: Array = lay.vents
	if hz == "" and not vents.is_empty():
		why.append("%s has vents but no hazard" % id)
	if hz != "":
		if vents.size() < 3:
			why.append("%s has only %d vents" % [id, vents.size()])
		var h: Dictionary = HAZARDS[hz]
		if float(h.dmg) > MAX_HAZARD_DMG:
			why.append("%s vents hit too hard (%.0f)" % [id, float(h.dmg)])
		for i in vents.size():
			for w in _vent_problems(vents[i], vents.slice(0, i), lay):
				why.append("%s: %s" % [id, w])
			if not reachable(vents[i].p, lay):
				why.append("%s: a vent nobody can walk to" % id)
	for x in [-ALTAR_HALF + 1.5, 0.0, ALTAR_HALF - 1.5]:
		var s := Vector3(float(x), 0.0, ALTAR_Z)
		if not reachable(s, lay):
			why.append("%s: the altar stone at x=%.0f can't be reached" % [id, float(x)])
	for pr in lay.props:
		var q: Vector3 = pr.p
		if Vector2(q.x - TREE_AT.x, q.z - TREE_AT.z).length() < 2.5:
			why.append("%s: a %s in the Spirit Tree" % [id, pr.kind])
		if _in_altar(q, 0.5):
			why.append("%s: a %s on the altar" % [id, pr.kind])
	return why
