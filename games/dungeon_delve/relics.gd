extends RefCounted
## DUNGEON DELVE relics: run-long treasures that change how you play. Between floors the camp has a
## RELIC ALTAR (after the 2nd floor of every biome and after its boss) with 2-3 relics on glowing
## stones: everyone walks onto ONE (it's theirs for the rest of the run). New relics unlock for good as
## Cinder's hoard grows (deep.gd: every coin you pick up goes into her hoard, bosses add a big pile).
## Pure data, so tests/dungeon_delve_floors_test.gd can prove every offer is fair (check_offer).
## In the run a relic is a pickup of kind BASE + index (deep.gd _collect gives it; Loot.mesh draws it).

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

const BASE := 100  ## pickup kind of relic 0
## id, name (2 words at most: the label over the stone), icon (UiKit), colour, hoard to unlock, vr: the VR
## knight can use it too (his own sword, no bombs / bows / running speed).
const LIST: Array[Dictionary] = [
	{"id": "fang", "name": "VAMPIRE FANG", "icon": "drop", "color": Color(1.0, 0.3, 0.4), "hoard": 0, "vr": true},  # every 4th monster you bop: +1 heart
	{"id": "thorns", "name": "THORN ARMOR", "icon": "shield", "color": Color(0.45, 0.9, 0.4), "hoard": 0, "vr": true},  # hurt you: monsters near you get hurt too
	{"id": "boots", "name": "SPEEDY BOOTS", "icon": "bolt", "color": Color(0.4, 0.85, 1.0), "hoard": 0, "vr": false},  # run faster
	{"id": "magnet", "name": "GOLD MAGNET", "icon": "coin", "color": Color(1.0, 0.82, 0.25), "hoard": 0, "vr": true},  # coins and hearts fly to you from the whole room
	{"id": "spin", "name": "WHIRLWIND", "icon": "star", "color": Color(0.95, 0.95, 1.0), "hoard": 0, "vr": false},  # your hit swings all the way round
	{"id": "fire", "name": "FIRE SWORD", "icon": "fire", "color": Color(1.0, 0.55, 0.2), "hoard": 0, "vr": true},  # monsters you hit burn for a bit
	{"id": "glass", "name": "GLASS SWORD", "icon": "gem", "color": Color(0.7, 0.95, 1.0), "hoard": 120, "vr": true},  # double damage, two hearts less
	{"id": "phoenix", "name": "PHOENIX FEATHER", "icon": "heart", "color": Color(1.0, 0.7, 0.2), "hoard": 260, "vr": true},  # knocked out? up again by yourself (once a floor)
	{"id": "egg", "name": "DRAGON EGG", "icon": "crown", "color": Color(1.0, 0.45, 0.3), "hoard": 450, "vr": true},  # a baby dragon flies with you and spits fire
	{"id": "boom", "name": "BOOM BAG", "icon": "plus", "color": Color(1.0, 0.65, 0.3), "hoard": 700, "vr": false},  # bigger bombs, a bomb back every room
	{"id": "triple", "name": "TRIPLE SHOT", "icon": "arrow_right", "color": Color(1.0, 0.9, 0.4), "hoard": 1000, "vr": false},  # arrows and magic fly three at a time
	{"id": "bubble", "name": "BUBBLE SHIELD", "icon": "dot", "color": Color(0.5, 0.75, 1.0), "hoard": 1400, "vr": true},  # the first hit in every room just pops a bubble
]
const OFFER := 3  ## choices on an altar
const MIN_OFFER := 2  ## an altar shows at least this many when that many are left to take


static func count() -> int:
	return LIST.size()


static func index_of(id: String) -> int:
	for i in LIST.size():
		if String(LIST[i]["id"]) == id:
			return i
	return -1


static func info(id: String) -> Dictionary:
	var i := index_of(id)
	return LIST[i] if i >= 0 else {}


static func kind_of(id: String) -> int:
	return BASE + index_of(id)


static func is_relic_kind(kind: int) -> bool:
	return kind >= BASE and kind < BASE + LIST.size()


static func id_of_kind(kind: int) -> String:
	return String(LIST[kind - BASE]["id"]) if is_relic_kind(kind) else ""


## Relics the family has unlocked with this much hoard.
static func unlocked(hoard: int) -> Array:
	var out: Array = []
	for r in LIST:
		if hoard >= int(r["hoard"]):
			out.append(String(r["id"]))
	return out


## The next relic still to unlock: {"id", "hoard"} or {} when every one is out.
static func next_unlock(hoard: int) -> Dictionary:
	for r in LIST:
		if hoard < int(r["hoard"]):
			return r
	return {}


## Does an altar stand at the camp after floor fl (0..3) of a biome? After the 2nd floor and after the boss.
static func altar_after(floor_i: int) -> bool:
	return floor_i == 1 or floor_i == 3


## Can this player take relic id? member: {"knight": bool, "relics": Array}
static func usable(id: String, member: Dictionary) -> bool:
	var r := info(id)
	if r.is_empty():
		return false
	if (member.get("relics", []) as Array).has(id):
		return false
	return bool(r["vr"]) or not bool(member.get("knight", false))


## The altar's relics: up to OFFER different unlocked relics, each one someone in the party can still take.
## party: [{"knight": bool, "relics": [...]}, ...]. Seeded (every machine, every retry: the same altar).
static func offer(seed_value: int, zone: int, floor_i: int, unlocked_ids: Array, party: Array) -> Array:
	var pool: Array = []
	for r in LIST:
		var id := String(r["id"])
		if not unlocked_ids.has(id):
			continue
		for m in party:
			if usable(id, m):
				pool.append(id)
				break
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, zone, floor_i, "relics"])
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	return pool.slice(0, mini(OFFER, pool.size()))


## "" when the offer is fair, else what's wrong (tests/dungeon_delve_floors_test.gd, every seed and party).
static func check_offer(o: Array, unlocked_ids: Array, party: Array) -> String:
	var takeable := 0
	for r in LIST:
		var id := String(r["id"])
		if not unlocked_ids.has(id):
			continue
		for m in party:
			if usable(id, m):
				takeable += 1
				break
	if o.size() > OFFER:
		return "%d relics on one altar" % o.size()
	if o.size() < mini(MIN_OFFER, takeable):
		return "only %d choices while %d could be taken" % [o.size(), takeable]
	var seen := {}
	for id in o:
		if seen.has(id):
			return "%s twice" % id
		seen[id] = true
		if index_of(String(id)) < 0:
			return "unknown relic %s" % id
		if not unlocked_ids.has(id):
			return "%s isn't unlocked yet" % id
		var anyone := false
		for m in party:
			if usable(String(id), m):
				anyone = true
		if not anyone:
			return "nobody can take %s" % id
	return ""


## The relic on its stone (cached mesh): a glowing gem in the relic's colour with its own little shape.
static func mesh(id: String) -> ArrayMesh:
	return ResCache.get_or_make("dd_relic_%s_v1" % id, func() -> Resource: return _build(id)) as ArrayMesh


static func _build(id: String) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var r := info(id)
	var col: Color = r.get("color", Color.WHITE)
	var gold := Color(1.0, 0.82, 0.25)
	match id:
		"fang":
			b.cone(0.1, 0.38, MeshKit.at(Vector3(0, 0.0, 0), Vector3.ONE, Vector3(PI, 0, 0)), Color(0.97, 0.95, 0.9), 8, true)
			b.sphere(0.06, MeshKit.at(Vector3(0, -0.2, 0)), col, 8, true)
		"thorns":
			b.sphere(0.17, Transform3D.IDENTITY, col.darkened(0.2), 10)
			for k in 8:
				var a := TAU * k / 8.0
				b.cone(0.05, 0.16, MeshKit.at(Vector3(cos(a), 0.0, sin(a)) * 0.18, Vector3.ONE, Vector3(0, -a, -PI * 0.5)), col, 5, true)
		"boots":
			b.rounded_box(Vector3(0.16, 0.28, 0.16), 0.04, MeshKit.at(Vector3(0, 0.05, 0)), Color(0.6, 0.4, 0.25))
			b.rounded_box(Vector3(0.16, 0.1, 0.3), 0.04, MeshKit.at(Vector3(0, -0.1, 0.07)), Color(0.6, 0.4, 0.25))
			b.box(Vector3(0.02, 0.12, 0.18), MeshKit.at(Vector3(-0.1, 0.08, 0)), col, true)
		"magnet":
			b.torus(0.17, 0.06, MeshKit.at(Vector3(0, 0.05, 0), Vector3(1, 1, 1), Vector3(PI * 0.5, 0, 0)), Color(0.9, 0.25, 0.3), 14, 6)
			b.box(Vector3(0.12, 0.1, 0.12), MeshKit.at(Vector3(-0.17, -0.12, 0)), Color(0.9, 0.9, 0.95), true)
			b.box(Vector3(0.12, 0.1, 0.12), MeshKit.at(Vector3(0.17, -0.12, 0)), Color(0.9, 0.9, 0.95), true)
		"spin":
			for k in 3:
				b.torus(0.12 + k * 0.07, 0.025, MeshKit.at(Vector3(0, -0.12 + k * 0.12, 0)), col, 14, 4, true)
		"fire", "glass":
			b.box(Vector3(0.06, 0.42, 0.025), MeshKit.at(Vector3(0, 0.1, 0)), col, true)
			b.box(Vector3(0.2, 0.04, 0.04), MeshKit.at(Vector3(0, -0.12, 0)), gold)
			b.cylinder(0.03, 0.03, 0.12, MeshKit.at(Vector3(0, -0.2, 0)), Color(0.5, 0.3, 0.2), 6)
			if id == "fire":
				b.cone(0.07, 0.18, MeshKit.at(Vector3(0, 0.38, 0)), Color(1.0, 0.85, 0.3), 6, true)
		"phoenix":
			b.cone(0.07, 0.42, MeshKit.at(Vector3(0, 0.05, 0), Vector3(1.0, 1.0, 0.35), Vector3(0, 0, 0.3)), col, 8, true)
			b.cone(0.05, 0.3, MeshKit.at(Vector3(0.06, 0.0, 0), Vector3(1.0, 1.0, 0.35), Vector3(0, 0, -0.2)), Color(1.0, 0.35, 0.2), 8, true)
		"egg":
			b.sphere(0.17, MeshKit.at(Vector3.ZERO, Vector3(1.0, 1.3, 1.0)), Color(1.0, 0.92, 0.75), 12)
			for k in 4:
				b.sphere(0.04, MeshKit.at(Vector3(cos(k * 1.7) * 0.15, -0.1 + k * 0.08, sin(k * 1.7) * 0.15)), col, 6, true)
		"boom":
			b.sphere(0.2, Transform3D.IDENTITY, Color(0.2, 0.2, 0.26), 12)
			b.cylinder(0.035, 0.035, 0.14, MeshKit.at(Vector3(0, 0.24, 0)), Color(0.6, 0.45, 0.3), 6)
			b.sphere(0.06, MeshKit.at(Vector3(0, 0.33, 0)), col, 6, true)
		"triple":
			for k in 3:
				var a2 := (k - 1) * 0.35
				b.box(Vector3(0.025, 0.42, 0.025), MeshKit.at(Vector3(sin(a2) * 0.12, 0.0, 0), Vector3.ONE, Vector3(0, 0, -a2)), Color(0.75, 0.55, 0.3))
				b.cone(0.05, 0.1, MeshKit.at(Vector3(sin(a2) * 0.32, 0.22 * cos(a2), 0), Vector3.ONE, Vector3(0, 0, -a2)), col, 6, true)
		"bubble":
			b.sphere(0.22, Transform3D.IDENTITY, col, 14, true)
			b.sphere(0.06, MeshKit.at(Vector3(-0.08, 0.1, 0.15)), Color(1, 1, 1), 6, true)
		_:
			b.sphere(0.18, Transform3D.IDENTITY, col, 10, true)
	b.torus(0.32, 0.025, MeshKit.at(Vector3(0, -0.28, 0)), gold, 18, 4, true)
	return b.build()
