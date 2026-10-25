extends RefCounted
## DUNGEON DELVE deep loot: what can lie on the floor, spill out of chests and pots, or sit in the shop.
##  coins (the party's gold), potions (a hero keeps them: Y drinks one, +3 hearts; the knight drinks
##  at once), hearts (+1 now), keys (the party's), bombs (B throws one: breaks cracked walls, big
##  damage, never hurts friends), heart containers (+1 heart for good), and the abilities a hero
##  wears on X (one at a time; picking another swaps it): DASH (zip away, nothing can hit you),
##  SHIELD BASH (shove through shields), BOW (shoot from afar). In the shop: SWORD +1 and a LUCKY
##  CHARM (gets you back up once by itself).

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

enum { COIN, COIN5, POTION, HEART, KEY, BOMBS, DASH, BASH, BOW, MAXHEART, SWORD, CHARM }
const ABILITIES: Array[int] = [DASH, BASH, BOW]
const NAMES := {COIN: "GOLD", COIN5: "GOLD", POTION: "POTION", HEART: "HEART", KEY: "KEY", BOMBS: "3 BOMBS",
	DASH: "DASH", BASH: "SHIELD BASH", BOW: "BOW", MAXHEART: "+1 HEART", SWORD: "SWORD +1", CHARM: "LUCKY CHARM"}
const ICONS := {COIN: "coin", COIN5: "coin", POTION: "potion", HEART: "heart", KEY: "key", BOMBS: "fire",
	DASH: "bolt", BASH: "shield", BOW: "arrow_right", MAXHEART: "heart", SWORD: "sword", CHARM: "star"}
const ABILITY_NAMES := {"dash": DASH, "bash": BASH, "bow": BOW}
const PRICES := {POTION: 12, HEART: 6, BOMBS: 12, DASH: 25, BASH: 25, BOW: 30, MAXHEART: 35, SWORD: 30, CHARM: 40, KEY: 20}


static func ability_id(kind: int) -> String:
	match kind:
		DASH:
			return "dash"
		BASH:
			return "bash"
		BOW:
			return "bow"
	return ""


## What a chest gives: gold plus (sometimes) something better. g = how deep (0..11).
static func chest_loot(rng: RandomNumberGenerator, g: int, big: bool) -> Array:
	var out: Array = [COIN5, COIN5]
	if big:
		out.append(COIN5)
	var x := rng.randf()
	if big:
		out.append([SWORD, ABILITIES[rng.randi_range(0, 2)], POTION, BOMBS][rng.randi_range(0, 3)])
	elif x < 0.3:
		out.append(POTION)
	elif x < 0.5:
		out.append(BOMBS)
	elif x < 0.62:
		out.append(ABILITIES[rng.randi_range(0, 2)])
	elif x < 0.8:
		out.append(HEART)
	for k in g / 4:
		out.append(COIN5)
	return out


## The shop: four things, a bit dearer deeper down.
static func shop_stock(rng: RandomNumberGenerator, zone: int, heroic: bool) -> Array:
	var pool: Array = [POTION, POTION, BOMBS, MAXHEART, SWORD, DASH, BASH, BOW, CHARM, HEART]
	var out: Array = [[POTION, 0]]
	while out.size() < 4:
		var k: int = pool[rng.randi_range(0, pool.size() - 1)]
		var dup := false
		for o in out:
			if int((o as Array)[0]) == k:
				dup = true
		if not dup:
			out.append([k, 0])
	for o in out:
		var a: Array = o
		var price := float(PRICES[int(a[0])]) * 1.3 * (1.0 + 0.35 * zone) * (1.25 if heroic else 1.0)
		a[1] = int(round(price))
	return out


## The look of a pickup (cached, one draw call; glowing bits make them easy to spot).
static func mesh(kind: int) -> ArrayMesh:
	return ResCache.get_or_make("dd_loot_%d_v1" % kind, func() -> Resource: return _build(kind)) as ArrayMesh


static func _build(kind: int) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var gold := Color(1.0, 0.82, 0.25)
	match kind:
		COIN, COIN5:
			var s := 1.0 if kind == COIN else 1.35
			b.cylinder(0.13 * s, 0.13 * s, 0.035, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), gold, 14, true)
			b.cylinder(0.09 * s, 0.09 * s, 0.045, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.92, 0.5), 12, true)
		POTION:
			b.sphere(0.16, MeshKit.at(Vector3(0, 0.0, 0)), Color(1.0, 0.3, 0.45), 12, true)
			b.cylinder(0.05, 0.06, 0.12, MeshKit.at(Vector3(0, 0.18, 0)), Color(0.85, 0.9, 1.0), 8)
			b.cylinder(0.055, 0.055, 0.05, MeshKit.at(Vector3(0, 0.26, 0)), Color(0.6, 0.4, 0.25), 8)
		HEART, MAXHEART:
			var s2 := 1.0 if kind == HEART else 1.5
			var red := Color(1.0, 0.3, 0.4)
			b.sphere(0.1 * s2, MeshKit.at(Vector3(-0.07, 0.05, 0) * s2), red, 10, true)
			b.sphere(0.1 * s2, MeshKit.at(Vector3(0.07, 0.05, 0) * s2), red, 10, true)
			b.cone(0.15 * s2, 0.2 * s2, MeshKit.at(Vector3(0, -0.09, 0) * s2, Vector3(1.0, 1.0, 0.65), Vector3(PI, 0, 0)), red, 12, true)
			if kind == MAXHEART:
				b.torus(0.3, 0.025, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), gold, 16, 4, true)
		KEY:
			b.torus(0.1, 0.03, MeshKit.at(Vector3(0, 0.16, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), gold, 14, 6, true)
			b.box(Vector3(0.045, 0.28, 0.045), MeshKit.at(Vector3(0, -0.04, 0)), gold, true)
			b.box(Vector3(0.09, 0.045, 0.045), MeshKit.at(Vector3(0.05, -0.13, 0)), gold, true)
			b.box(Vector3(0.07, 0.045, 0.045), MeshKit.at(Vector3(0.04, -0.03, 0)), gold, true)
		BOMBS:
			for k in 3:
				var o := Vector3(-0.13 + k * 0.13, 0.0, 0.0)
				b.sphere(0.1, MeshKit.at(o), Color(0.18, 0.18, 0.24), 10)
				b.sphere(0.035, MeshKit.at(o + Vector3(0, 0.12, 0)), Color(1.0, 0.65, 0.2), 6, true)
		DASH:
			b.polygon(PackedVector2Array([Vector2(0.05, 0.25), Vector2(-0.12, -0.02), Vector2(0.0, -0.02), Vector2(-0.06, -0.25), Vector2(0.13, 0.04), Vector2(0.01, 0.04)]), 0.05, Transform3D.IDENTITY, Color(0.5, 0.85, 1.0), true)
		BASH:
			b.cylinder(0.2, 0.2, 0.05, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.55, 0.65, 0.85), 14)
			b.torus(0.2, 0.03, MeshKit.at(Vector3(0, 0, 0.02), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), gold, 14, 4, true)
		BOW:
			b.torus(0.22, 0.025, MeshKit.at(Vector3(0.0, 0, 0), Vector3(0.5, 1.0, 1.0), Vector3(PI * 0.5, 0, 0)), Color(0.7, 0.5, 0.3), 16, 4)
			b.box(Vector3(0.012, 0.42, 0.012), MeshKit.at(Vector3(-0.0, 0, 0)), Color(1.0, 1.0, 0.9), true)
			b.box(Vector3(0.3, 0.02, 0.02), MeshKit.at(Vector3(0.05, 0, 0)), Color(0.8, 0.6, 0.35))
		SWORD:
			b.box(Vector3(0.05, 0.4, 0.02), MeshKit.at(Vector3(0, 0.12, 0)), Color(0.8, 0.9, 1.0), true)
			b.box(Vector3(0.18, 0.035, 0.035), MeshKit.at(Vector3(0, -0.09, 0)), gold)
			b.cylinder(0.025, 0.025, 0.12, MeshKit.at(Vector3(0, -0.16, 0)), Color(0.5, 0.3, 0.2), 6)
		CHARM:
			b.star(5, 0.2, 0.09, 0.05, Transform3D.IDENTITY, Color(1.0, 0.9, 0.35), true)
	return b.build()
