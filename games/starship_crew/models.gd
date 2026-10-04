extends RefCounted
## Starship Crew: every mesh in the game, built in code from core/mesh_kit.gd primitives and cached in
## core/res_cache.gd (one draw call per mesh, plus one for its glowing parts).
## Conventions: metres; the player ship flies towards -Z; enemy ships and space objects face +Z (towards
## the player ship) unless noted; meshes are centred on their own origin unless noted.

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

const VERSION := "v3"

## Ship paint jobs (cosmetic, unlocked by achievements; see main.gd PAINT_UNLOCKS).
const PAINTS: Array = [
	{"id": "classic", "name": "CLASSIC", "hull": Color(0.9, 0.92, 0.97), "trim": Color(1.0, 0.55, 0.2), "unlock": "Always yours!"},
	{"id": "ocean", "name": "OCEAN BLUE", "hull": Color(0.55, 0.8, 0.97), "trim": Color(0.12, 0.38, 0.85), "unlock": "Finish a voyage"},
	{"id": "candy", "name": "CANDY", "hull": Color(1.0, 0.76, 0.88), "trim": Color(0.35, 0.86, 0.72), "unlock": "Reach the pirate mothership"},
	{"id": "tiger", "name": "TIGER", "hull": Color(1.0, 0.72, 0.22), "trim": Color(0.16, 0.13, 0.14), "unlock": "Rescue 5 escape pods"},
	{"id": "whale", "name": "WHALE SONG", "hull": Color(0.5, 0.58, 0.96), "trim": Color(0.86, 0.96, 1.0), "unlock": "Befriend 3 space whales"},
	{"id": "gold", "name": "GOLDEN", "hull": Color(1.0, 0.85, 0.38), "trim": Color(0.88, 0.3, 0.25), "unlock": "Deliver the cake!"},
]

const DARK := Color(0.2, 0.22, 0.28)
const GLASS := Color(0.45, 0.85, 1.0)


static func paint(id: String) -> Dictionary:
	for p in PAINTS:
		var d: Dictionary = p
		if String(d["id"]) == id:
			return d
	return PAINTS[0]


static func _cached(key: String, maker: Callable) -> ArrayMesh:
	return ResCache.get_or_make("sc_%s_%s" % [key, VERSION], maker) as ArrayMesh


# --- The player ship --------------------------------------------------------------------------

## The ship's outside: belly, nose, wings, engines and hull rims round the deck (deck at y = 0,
## x -8..8, z -6..9, bridge x -3.2..3.2, z -11..-6). Paint-dependent.
static func ship_hull(paint_id: String) -> ArrayMesh:
	return _cached("hull_" + paint_id, func() -> Resource:
		var p := paint(paint_id)
		var hull: Color = p["hull"]
		var trim: Color = p["trim"]
		var b := MeshKit.Builder.new()
		var under := hull.darkened(0.25)
		# Belly under the main deck and the bridge.
		b.rounded_box(Vector3(17.0, 1.6, 15.8), 0.7, MeshKit.at(Vector3(0, -0.92, 1.5)), under, 2)
		b.rounded_box(Vector3(7.2, 1.5, 6.0), 0.6, MeshKit.at(Vector3(0, -0.86, -8.4)), under, 2)
		b.ellipsoid(Vector3(3.5, 1.0, 1.9), MeshKit.at(Vector3(0, -0.55, -11.0)), hull, 16)
		b.ellipsoid(Vector3(1.4, 0.35, 0.7), MeshKit.at(Vector3(0, 0.05, -12.3)), trim, 12)
		# Rims along the top of the outer walls (a cartoon rounded edge).
		b.capsule_between(Vector3(-8.3, 0.0, -6.0), Vector3(-8.3, 0.0, 9.0), 0.42, hull, 10)
		b.capsule_between(Vector3(8.3, 0.0, -6.0), Vector3(8.3, 0.0, 9.0), 0.42, hull, 10)
		b.capsule_between(Vector3(-8.3, 0.0, 9.2), Vector3(8.3, 0.0, 9.2), 0.42, hull, 10)
		b.capsule_between(Vector3(-8.3, 0.0, -6.1), Vector3(-3.4, 0.0, -6.1), 0.36, hull, 10)
		b.capsule_between(Vector3(3.4, 0.0, -6.1), Vector3(8.3, 0.0, -6.1), 0.36, hull, 10)
		b.capsule_between(Vector3(-3.45, 0.0, -11.1), Vector3(-3.45, 0.0, -6.1), 0.36, hull, 10)
		b.capsule_between(Vector3(3.45, 0.0, -11.1), Vector3(3.45, 0.0, -6.1), 0.36, hull, 10)
		# Trim stripes on the belly sides.
		b.box(Vector3(0.06, 0.28, 15.0), MeshKit.at(Vector3(-8.52, -0.75, 1.5)), trim)
		b.box(Vector3(0.06, 0.28, 15.0), MeshKit.at(Vector3(8.52, -0.75, 1.5)), trim)
		# Wings with trim and tip lights.
		for sx in [-1.0, 1.0]:
			var s: float = sx
			var wing := PackedVector2Array([Vector2(0.0, -2.5), Vector2(5.8, 2.6), Vector2(6.2, 6.0), Vector2(0.0, 7.5)])
			b.polygon(wing, 0.4, MeshKit.at(Vector3(s * 8.4 + (s * 0.0), -0.45, 0.0), Vector3(s, 1.0, 1.0), Vector3(PI * 0.5, 0.0, 0.0)), hull)
			b.box(Vector3(0.35, 0.44, 3.4), MeshKit.at(Vector3(s * 14.3, -0.45, 4.3)), trim)
			b.sphere(0.32, MeshKit.at(Vector3(s * 14.4, -0.2, 2.5)), Color(1.0, 0.3, 0.3) if s < 0.0 else Color(0.3, 1.0, 0.4), 10, true)
			# Engine pods on the wings.
			b.capsule_between(Vector3(s * 11.5, -0.5, 1.0), Vector3(s * 11.5, -0.5, 8.0), 0.9, hull.darkened(0.1), 12)
			b.cylinder(0.72, 0.85, 0.5, MeshKit.at(Vector3(s * 11.5, -0.5, 8.6), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), DARK, 14)
			b.disc(0.62, MeshKit.at(Vector3(s * 11.5, -0.5, 8.86), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.6, 0.25), 14, true)
			b.box(Vector3(0.12, 0.5, 5.0), MeshKit.at(Vector3(s * 11.5, 0.42, 4.0)), trim)
		# Main engines at the stern.
		for ex in [-4.6, 0.0, 4.6]:
			var x: float = ex
			b.cylinder(1.25, 1.45, 2.6, MeshKit.at(Vector3(x, -0.5, 10.4), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), hull.darkened(0.15), 16)
			b.torus(1.3, 0.16, MeshKit.at(Vector3(x, -0.5, 11.6), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), trim, 16, 6)
			b.disc(1.1, MeshKit.at(Vector3(x, -0.5, 11.72), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.45, 0.8, 1.0), 16, true)
		# Little antenna dish on the science side, and portholes along the hull.
		b.cylinder(0.08, 0.1, 1.4, MeshKit.at(Vector3(8.6, 0.8, -5.0)), DARK, 6)
		b.dome(0.55, MeshKit.at(Vector3(8.6, 1.55, -5.0), Vector3(1, 0.4, 1), Vector3(0, 0, PI)), Color(0.85, 0.87, 0.92), 12)
		for k in 6:
			var z := -4.0 + k * 2.4
			b.sphere(0.2, MeshKit.at(Vector3(-8.62, -0.55, z), Vector3(0.4, 1, 1)), Color(1.0, 0.85, 0.5), 8, true)
			b.sphere(0.2, MeshKit.at(Vector3(8.62, -0.55, z), Vector3(0.4, 1, 1)), Color(1.0, 0.85, 0.5), 8, true)
		return b.build())


## A torpedo (about 0.9 m long, nose towards -Z): carried by the crew, loaded, and fired.
static func torpedo() -> ArrayMesh:
	return _cached("torpedo", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.capsule(0.13, 0.85, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.95, 0.95, 0.97), 12)
		b.cylinder(0.135, 0.135, 0.12, MeshKit.at(Vector3(0, 0, -0.18), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.95, 0.25, 0.25), 12)
		b.cylinder(0.135, 0.135, 0.08, MeshKit.at(Vector3(0, 0, 0.12), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.95, 0.25, 0.25), 12)
		b.sphere(0.07, MeshKit.at(Vector3(0, 0, -0.42)), Color(1.0, 0.85, 0.3), 8, true)
		for k in 4:
			var a := k * PI * 0.5
			b.box(Vector3(0.02, 0.16, 0.18), MeshKit.at(Vector3(cos(a) * 0.15, sin(a) * 0.15, 0.36), Vector3.ONE, Vector3(0, 0, a)), Color(0.95, 0.25, 0.25))
		return b.build())


## A station console body (origin at the floor, screen facing +Z). The screen itself is separate.
static func console() -> ArrayMesh:
	return _cached("console", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.rounded_box(Vector3(0.95, 0.85, 0.55), 0.08, MeshKit.at(Vector3(0, 0.425, 0)), Color(0.82, 0.84, 0.9), 2)
		b.rounded_box(Vector3(1.0, 0.12, 0.62), 0.05, MeshKit.at(Vector3(0, 0.88, 0.03)), DARK, 1)
		b.wedge(Vector3(0.9, 0.42, 0.36), MeshKit.at(Vector3(0, 1.15, -0.08)), Color(0.75, 0.77, 0.84))
		for k in 3:
			b.sphere(0.035, MeshKit.at(Vector3(-0.25 + k * 0.25, 0.95, 0.24)), [Color(1, 0.4, 0.35), Color(1, 0.85, 0.3), Color(0.4, 1, 0.5)][k], 6, true)
		return b.build())


## The glowing core of the reactor (origin at the floor).
static func reactor_core() -> ArrayMesh:
	return _cached("reactor_core", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cylinder(0.42, 0.42, 1.9, MeshKit.at(Vector3(0, 1.05, 0)), Color(0.5, 0.95, 1.0), 16, true)
		b.sphere(0.5, MeshKit.at(Vector3(0, 2.05, 0)), Color(0.65, 1.0, 1.0), 14, true)
		return b.build())


## The reactor's housing: base, pillars and rings (origin at the floor).
static func reactor_frame() -> ArrayMesh:
	return _cached("reactor_frame", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cylinder(0.95, 1.05, 0.35, MeshKit.at(Vector3(0, 0.17, 0)), Color(0.4, 0.42, 0.5), 18)
		b.cylinder(0.8, 0.8, 0.2, MeshKit.at(Vector3(0, 2.5, 0)), Color(0.4, 0.42, 0.5), 18)
		for k in 4:
			var a := k * PI * 0.5 + PI * 0.25
			b.capsule_between(Vector3(cos(a) * 0.72, 0.3, sin(a) * 0.72), Vector3(cos(a) * 0.72, 2.45, sin(a) * 0.72), 0.08, Color(0.72, 0.74, 0.8), 8)
		b.torus(0.66, 0.06, MeshKit.at(Vector3(0, 0.8, 0)), Color(1.0, 0.75, 0.3), 18, 6)
		b.torus(0.66, 0.06, MeshKit.at(Vector3(0, 1.6, 0)), Color(1.0, 0.75, 0.3), 18, 6)
		return b.build())


## A turret gun: dome base with twin barrels along -Z (pivot at the base).
static func turret_gun() -> ArrayMesh:
	return _cached("turret_gun", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.dome(0.7, MeshKit.at(Vector3.ZERO), Color(0.78, 0.8, 0.88), 14)
		b.rounded_box(Vector3(0.8, 0.45, 0.8), 0.15, MeshKit.at(Vector3(0, 0.55, 0)), Color(0.55, 0.58, 0.66), 2)
		for sx in [-0.18, 0.18]:
			var x: float = sx
			b.cylinder(0.09, 0.11, 1.3, MeshKit.at(Vector3(x, 0.58, -0.85), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), DARK, 10)
			b.sphere(0.09, MeshKit.at(Vector3(x, 0.58, -1.5)), Color(0.4, 1.0, 0.9), 8, true)
		return b.build())


## The armoury's torpedo rack (origin at the floor, torpedoes sit on it separately).
static func torpedo_rack() -> ArrayMesh:
	return _cached("rack", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.rounded_box(Vector3(1.5, 1.4, 0.6), 0.06, MeshKit.at(Vector3(0, 0.7, -0.08)), Color(0.55, 0.42, 0.3), 1)
		b.rounded_box(Vector3(1.55, 0.08, 0.75), 0.03, MeshKit.at(Vector3(0, 0.55, 0)), DARK, 1)
		b.rounded_box(Vector3(1.55, 0.08, 0.75), 0.03, MeshKit.at(Vector3(0, 1.05, 0)), DARK, 1)
		b.box(Vector3(0.6, 0.18, 0.02), MeshKit.at(Vector3(0, 1.3, 0.23)), Color(1.0, 0.8, 0.2), true)
		return b.build())


## The torpedo tube loader: a pedestal with a round hatch on top.
static func tube_loader() -> ArrayMesh:
	return _cached("tube", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cylinder(0.55, 0.62, 0.9, MeshKit.at(Vector3(0, 0.45, 0)), Color(0.7, 0.72, 0.8), 16)
		b.torus(0.42, 0.08, MeshKit.at(Vector3(0, 0.92, 0)), Color(0.95, 0.3, 0.3), 16, 6)
		b.disc(0.36, MeshKit.at(Vector3(0, 0.91, 0)), DARK, 16)
		b.capsule_between(Vector3(0, 0.9, -0.45), Vector3(0, 0.9, -1.4), 0.18, Color(0.6, 0.62, 0.7), 10)
		return b.build())


# --- Space objects --------------------------------------------------------------------------

## Pirate ships by kind: "scout" (small, quick), "raider" (shielded), "brute" (big, two shields).
static func pirate(kind: String) -> ArrayMesh:
	return _cached("pirate_" + kind, func() -> Resource:
		var b := MeshKit.Builder.new()
		var red := Color(0.78, 0.2, 0.24)
		var dark := Color(0.22, 0.18, 0.24)
		var gold := Color(1.0, 0.78, 0.3)
		match kind:
			"scout":
				b.ellipsoid(Vector3(1.1, 0.6, 2.1), MeshKit.at(Vector3.ZERO), red, 14)
				b.dome(0.6, MeshKit.at(Vector3(0, 0.35, 0.5), Vector3(1, 0.8, 1.3)), GLASS.darkened(0.3), 12)
				for sx in [-1.0, 1.0]:
					var s: float = sx
					b.polygon(PackedVector2Array([Vector2(0, -0.6), Vector2(2.0, 0.6), Vector2(2.0, 1.0), Vector2(0, 0.9)]), 0.15,
						MeshKit.at(Vector3(s * 0.9, 0, -0.2), Vector3(s, 1, 1), Vector3(PI * 0.5, 0, 0)), dark)
					b.sphere(0.18, MeshKit.at(Vector3(s * 2.8, 0.0, 0.2)), Color(1.0, 0.4, 0.3), 8, true)
				b.cylinder(0.35, 0.5, 0.6, MeshKit.at(Vector3(0, 0, -2.1), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), dark, 12)
				b.disc(0.32, MeshKit.at(Vector3(0, 0, -2.42), Vector3.ONE, Vector3(-PI * 0.5, 0, 0)), Color(1.0, 0.5, 0.2), 12, true)
				_flag(b, Vector3(0, 0.6, -0.8), 0.9)
			"raider":
				b.rounded_box(Vector3(3.2, 1.5, 5.0), 0.6, MeshKit.at(Vector3.ZERO), red, 2)
				b.rounded_box(Vector3(2.2, 1.0, 1.8), 0.4, MeshKit.at(Vector3(0, 0.9, -0.8)), dark, 2)
				b.dome(0.7, MeshKit.at(Vector3(0, 1.3, 0.1), Vector3(1.2, 0.7, 1)), GLASS.darkened(0.3), 12)
				for sx in [-1.0, 1.0]:
					var s: float = sx
					b.capsule_between(Vector3(s * 2.3, -0.2, -1.8), Vector3(s * 2.3, -0.2, 1.8), 0.55, dark, 12)
					b.cylinder(0.14, 0.18, 1.2, MeshKit.at(Vector3(s * 1.0, 0.0, 2.9), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.3, 0.3, 0.35), 8)
					b.disc(0.45, MeshKit.at(Vector3(s * 2.3, -0.2, -2.35), Vector3.ONE, Vector3(-PI * 0.5, 0, 0)), Color(1.0, 0.5, 0.2), 12, true)
				b.sphere(0.22, MeshKit.at(Vector3(-0.5, 0.2, 2.5)), Color(1.0, 0.9, 0.5), 8, true)
				b.sphere(0.22, MeshKit.at(Vector3(0.5, 0.2, 2.5)), Color(1.0, 0.9, 0.5), 8, true)
				b.box(Vector3(3.3, 0.18, 0.2), MeshKit.at(Vector3(0, 0.3, 2.45)), gold)
				_flag(b, Vector3(0, 1.4, -1.5), 1.3)
			_:
				b.rounded_box(Vector3(5.6, 2.6, 7.4), 1.0, MeshKit.at(Vector3.ZERO), Color(0.45, 0.22, 0.42), 2)
				b.cone(1.6, 2.6, MeshKit.at(Vector3(0, -0.2, 4.6), Vector3(1, 0.6, 1), Vector3(PI * 0.5, 0, 0)), Color(0.75, 0.75, 0.8), 12)
				b.rounded_box(Vector3(3.0, 1.4, 2.6), 0.5, MeshKit.at(Vector3(0, 1.8, -1.2)), dark, 2)
				for sx in [-1.0, 1.0]:
					var s: float = sx
					b.sphere(0.42, MeshKit.at(Vector3(s * 1.4, 0.6, 3.6)), Color(1.0, 0.85, 0.25), 10, true)
					b.cylinder(0.25, 0.32, 2.0, MeshKit.at(Vector3(s * 3.2, 0.3, 1.2), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.3, 0.3, 0.35), 10)
					b.capsule_between(Vector3(s * 3.4, -0.4, -3.0), Vector3(s * 3.4, -0.4, 1.0), 0.8, dark, 12)
					b.disc(0.7, MeshKit.at(Vector3(s * 3.4, -0.4, -3.85), Vector3.ONE, Vector3(-PI * 0.5, 0, 0)), Color(1.0, 0.5, 0.2), 12, true)
				b.box(Vector3(5.7, 0.25, 0.3), MeshKit.at(Vector3(0, 0.9, 3.6)), gold)
				_flag(b, Vector3(0, 2.5, -2.0), 1.8)
		return b.build())


## A jolly-roger flag on a little mast (skull drawn with spheres).
static func _flag(b: MeshKit.Builder, at: Vector3, s: float) -> void:
	b.cylinder(0.04 * s, 0.05 * s, 1.4 * s, MeshKit.at(at + Vector3(0, 0.7 * s, 0)), Color(0.35, 0.25, 0.18), 6)
	b.box(Vector3(0.9 * s, 0.6 * s, 0.03), MeshKit.at(at + Vector3(0.47 * s, 1.1 * s, 0)), Color(0.08, 0.08, 0.1))
	b.sphere(0.13 * s, MeshKit.at(at + Vector3(0.47 * s, 1.15 * s, 0.03)), Color(0.95, 0.95, 0.92), 8)
	b.box(Vector3(0.45 * s, 0.05 * s, 0.02), MeshKit.at(at + Vector3(0.47 * s, 0.93 * s, 0.03), Vector3.ONE, Vector3(0, 0, 0.6)), Color(0.95, 0.95, 0.92))
	b.box(Vector3(0.45 * s, 0.05 * s, 0.02), MeshKit.at(at + Vector3(0.47 * s, 0.93 * s, 0.03), Vector3.ONE, Vector3(0, 0, -0.6)), Color(0.95, 0.95, 0.92))


## The pirate mothership's body (about 36 m wide). Destructible parts are separate meshes.
static func mothership() -> ArrayMesh:
	return _cached("mothership", func() -> Resource:
		var b := MeshKit.Builder.new()
		var hull := Color(0.4, 0.2, 0.4)
		var dark := Color(0.2, 0.15, 0.22)
		var gold := Color(1.0, 0.75, 0.3)
		b.ellipsoid(Vector3(11.0, 4.2, 9.0), MeshKit.at(Vector3.ZERO), hull, 20)
		b.rounded_box(Vector3(9.0, 3.0, 6.0), 1.2, MeshKit.at(Vector3(0, 4.0, -2.0)), dark, 2)
		b.dome(2.6, MeshKit.at(Vector3(0, 5.4, -1.0), Vector3(1.2, 0.8, 1)), GLASS.darkened(0.4), 14)
		for sx in [-1.0, 1.0]:
			var s: float = sx
			b.capsule_between(Vector3(s * 9.0, -0.5, 0.0), Vector3(s * 17.0, -0.5, 0.0), 1.6, dark, 14)
			b.capsule_between(Vector3(s * 6.0, -2.5, -7.0), Vector3(s * 6.0, -2.5, 4.0), 2.2, hull.darkened(0.2), 14)
			b.disc(2.0, MeshKit.at(Vector3(s * 6.0, -2.5, -8.25), Vector3.ONE, Vector3(-PI * 0.5, 0, 0)), Color(1.0, 0.45, 0.2), 16, true)
			b.sphere(0.9, MeshKit.at(Vector3(s * 4.0, 1.6, 8.3)), Color(1.0, 0.85, 0.2), 12, true)
		# A big grumpy skull on the front.
		b.ellipsoid(Vector3(3.2, 2.8, 0.6), MeshKit.at(Vector3(0, 0.6, 8.8)), Color(0.95, 0.93, 0.88), 16)
		b.sphere(0.85, MeshKit.at(Vector3(-1.2, 1.1, 9.25), Vector3(1, 1, 0.4)), Color(0.08, 0.06, 0.1), 10)
		b.sphere(0.85, MeshKit.at(Vector3(1.2, 1.1, 9.25), Vector3(1, 1, 0.4)), Color(0.08, 0.06, 0.1), 10)
		b.sphere(0.32, MeshKit.at(Vector3(-1.2, 1.1, 9.5)), Color(1.0, 0.3, 0.3), 8, true)
		b.sphere(0.32, MeshKit.at(Vector3(1.2, 1.1, 9.5)), Color(1.0, 0.3, 0.3), 8, true)
		b.box(Vector3(2.4, 0.3, 0.3), MeshKit.at(Vector3(0, -0.9, 9.3)), Color(0.08, 0.06, 0.1))
		b.box(Vector3(23.0, 0.5, 0.5), MeshKit.at(Vector3(0, -1.0, 7.6)), gold)
		_flag(b, Vector3(0, 6.6, -3.0), 4.0)
		return b.build())


## Mothership parts: "generator" (shield pod), "cannon" (the big blaster), "core" (opens in stage 3).
static func boss_part(kind: String) -> ArrayMesh:
	return _cached("boss_" + kind, func() -> Resource:
		var b := MeshKit.Builder.new()
		match kind:
			"generator":
				b.sphere(2.0, MeshKit.at(Vector3.ZERO), Color(0.3, 0.25, 0.35), 14)
				b.torus(2.1, 0.3, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.75, 0.3), 18, 6)
				b.sphere(1.1, MeshKit.at(Vector3(0, 0, 1.4)), Color(0.4, 1.0, 0.6), 12, true)
			"cannon":
				b.rounded_box(Vector3(3.6, 2.4, 3.0), 0.6, MeshKit.at(Vector3.ZERO), Color(0.25, 0.22, 0.28), 2)
				b.cylinder(0.9, 1.2, 4.5, MeshKit.at(Vector3(0, 0, 3.2), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.35, 0.33, 0.4), 14)
				b.torus(1.0, 0.2, MeshKit.at(Vector3(0, 0, 5.4), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.4, 0.3), 16, 6, true)
			_:
				b.sphere(2.2, MeshKit.at(Vector3.ZERO), Color(1.0, 0.45, 0.85), 16, true)
				b.torus(2.6, 0.35, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.8, 0.3), 18, 6)
		return b.build())


## The armour shell that covers the mothership core (two halves open sideways).
static func core_shell() -> ArrayMesh:
	return _cached("core_shell", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.dome(3.0, MeshKit.at(Vector3(0, 0, 0), Vector3(1, 1, 0.7), Vector3(PI * 0.5, 0, PI * 0.5)), Color(0.32, 0.28, 0.36), 14)
		b.box(Vector3(0.3, 4.0, 0.3), MeshKit.at(Vector3(0, 0, 1.6)), Color(1.0, 0.75, 0.3))
		return b.build())


## A friendly space whale (about 30 m long, head towards -Z).
static func whale() -> ArrayMesh:
	return _cached("whale", func() -> Resource:
		var b := MeshKit.Builder.new()
		var blue := Color(0.35, 0.5, 0.95)
		var belly := Color(0.82, 0.88, 1.0)
		b.ellipsoid(Vector3(5.5, 4.6, 13.0), MeshKit.at(Vector3(0, 0, 0)), blue, 20)
		b.ellipsoid(Vector3(4.6, 2.6, 11.0), MeshKit.at(Vector3(0, -2.4, -0.6)), belly, 18)
		b.ellipsoid(Vector3(2.2, 1.6, 6.0), MeshKit.at(Vector3(0, 0.6, 14.5)), blue, 14)
		b.polygon(PackedVector2Array([Vector2(0, 0), Vector2(-6.5, 3.5), Vector2(-5.5, -0.5), Vector2(6.5, 3.5), Vector2(5.5, -0.5)]), 0.5,
			MeshKit.at(Vector3(0, 0.8, 20.0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), blue.darkened(0.15))
		for sx in [-1.0, 1.0]:
			var s: float = sx
			b.ellipsoid(Vector3(3.6, 0.5, 1.6), MeshKit.at(Vector3(s * 5.6, -1.8, -2.5), Vector3.ONE, Vector3(0, s * 0.4, s * 0.5)), blue.darkened(0.1), 12)
			b.sphere(0.9, MeshKit.at(Vector3(s * 4.2, 0.4, -9.4)), Color(1, 1, 1), 12)
			b.sphere(0.5, MeshKit.at(Vector3(s * 4.55, 0.45, -9.85)), Color(0.08, 0.08, 0.15), 10)
			b.sphere(0.16, MeshKit.at(Vector3(s * 4.75, 0.7, -10.05)), Color(1, 1, 1), 6, true)
			b.sphere(0.6, MeshKit.at(Vector3(s * 3.6, -0.9, -10.4), Vector3(1, 0.5, 0.4)), Color(1.0, 0.6, 0.7), 8)
		for k in 7:
			b.sphere(0.45, MeshKit.at(Vector3(0, 4.3 - absf(k - 3) * 0.25, -6.0 + k * 2.6)), Color(0.6, 1.0, 0.95), 8, true)
		b.capsule_between(Vector3(-2.0, -1.2, -12.6), Vector3(2.0, -1.2, -12.6), 0.25, Color(0.15, 0.15, 0.3), 8)
		return b.build())


## An escape pod (about 3 m) with a cute alien looking out of the window. Nose towards +Z.
static func escape_pod() -> ArrayMesh:
	return _cached("pod", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.capsule(1.0, 3.2, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.95, 0.95, 0.97), 14)
		b.cylinder(1.02, 1.02, 0.5, MeshKit.at(Vector3(0, 0, -0.3), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.55, 0.2), 14)
		b.dome(0.6, MeshKit.at(Vector3(0, 0.0, 1.35), Vector3(1, 1, 0.7), Vector3(PI * 0.5, 0, 0)), GLASS, 12)
		b.sphere(0.4, MeshKit.at(Vector3(0, -0.05, 1.3)), Color(0.5, 0.95, 0.45), 10)
		b.sphere(0.12, MeshKit.at(Vector3(-0.15, 0.05, 1.65)), Color(0.05, 0.05, 0.1), 6)
		b.sphere(0.12, MeshKit.at(Vector3(0.15, 0.05, 1.65)), Color(0.05, 0.05, 0.1), 6)
		b.sphere(0.2, MeshKit.at(Vector3(0, 1.05, -0.6)), Color(1.0, 0.3, 0.3), 8, true)
		return b.build())


## The trading post: a station with a ring and docking arms (about 30 m).
static func trading_post() -> ArrayMesh:
	return _cached("trading_post", func() -> Resource:
		var b := MeshKit.Builder.new()
		var purple := Color(0.55, 0.4, 0.8)
		var gold := Color(1.0, 0.8, 0.35)
		b.sphere(6.0, MeshKit.at(Vector3.ZERO), purple, 18)
		b.torus(12.0, 1.4, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(0.25, 0, 0)), Color(0.85, 0.86, 0.92), 28, 8)
		for k in 4:
			var a := k * PI * 0.5
			b.tube(Vector3.ZERO, Vector3(cos(a) * 11.0, sin(a) * 11.0 * 0.25, sin(a) * 11.0), 0.6, 0.6, Color(0.7, 0.72, 0.8), 8)
		for k in 16:
			var a2 := k * TAU / 16.0
			b.sphere(0.45, MeshKit.at(Vector3(cos(a2) * 12.0, sin(a2) * 12.0 * sin(0.25), sin(a2) * 12.0 * cos(0.25))), [gold, Color(0.5, 1.0, 0.9), Color(1.0, 0.5, 0.8)][k % 3], 6, true)
		b.cylinder(1.4, 2.2, 4.0, MeshKit.at(Vector3(0, 7.5, 0)), gold, 14)
		b.sphere(1.2, MeshKit.at(Vector3(0, 10.0, 0)), Color(1.0, 0.9, 0.5), 10, true)
		return b.build())


## Party Station, the goal: a space station shaped like a giant birthday cake.
static func party_station() -> ArrayMesh:
	return _cached("party_station", func() -> Resource:
		var b := MeshKit.Builder.new()
		var cream := Color(1.0, 0.95, 0.88)
		var pink := Color(1.0, 0.62, 0.78)
		b.cylinder(16.0, 16.0, 7.0, MeshKit.at(Vector3(0, -6.0, 0)), pink, 32)
		b.cylinder(12.0, 12.0, 6.0, MeshKit.at(Vector3(0, 0.5, 0)), cream, 32)
		b.cylinder(8.0, 8.0, 5.0, MeshKit.at(Vector3(0, 6.0, 0)), Color(0.6, 0.85, 1.0), 28)
		b.torus(16.0, 0.9, MeshKit.at(Vector3(0, -2.6, 0)), cream, 32, 6)
		b.torus(12.0, 0.8, MeshKit.at(Vector3(0, 3.5, 0)), pink, 28, 6)
		b.torus(8.0, 0.7, MeshKit.at(Vector3(0, 8.5, 0)), cream, 24, 6)
		for k in 7:
			var a := k * TAU / 7.0
			var p := Vector3(cos(a) * 5.0, 10.6, sin(a) * 5.0)
			b.cylinder(0.45, 0.45, 3.2, MeshKit.at(p), [Color(1, 0.5, 0.5), Color(0.5, 0.8, 1), Color(1, 0.9, 0.4)][k % 3], 8)
			b.sphere(0.6, MeshKit.at(p + Vector3(0, 2.2, 0), Vector3(1, 1.6, 1)), Color(1.0, 0.8, 0.3), 8, true)
		for k in 24:
			var a2 := k * TAU / 24.0
			b.sphere(0.5, MeshKit.at(Vector3(cos(a2) * 16.1, -6.0 + (k % 3) * 2.0, sin(a2) * 16.1)), Color(1, 1, 0.7), 6, true)
		return b.build())


## The donut-shaped bakery station the voyage starts from.
static func bakery_station() -> ArrayMesh:
	return _cached("bakery_station", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.torus(10.0, 4.2, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(1.1, 0, 0)), Color(0.85, 0.6, 0.35), 32, 14)
		var icing := Color(1.0, 0.55, 0.75)
		b.torus(10.0, 3.6, MeshKit.at(Vector3(0, 0.0, 0.0), Vector3(1, 1, 1), Vector3(1.1, 0, 0)).translated_local(Vector3(0, 1.3, 0)), icing, 32, 12)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for k in 40:
			var a := rng.randf() * TAU
			var r := 10.0 + rng.randf_range(-2.4, 2.4)
			var local := Vector3(cos(a) * r, 4.9, sin(a) * r)
			var xf := MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(1.1, 0, 0)) * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), local)
			b.capsule(0.22, 1.1, xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO),
				[Color(1, 1, 1), Color(0.4, 0.8, 1), Color(1, 0.9, 0.3), Color(0.5, 1, 0.5)][k % 4], 6)
		return b.build())


## A lumpy asteroid (flat-shaded, about 2 m across; scale it per instance). variant 0..2.
static func asteroid(variant: int) -> ArrayMesh:
	return _cached("asteroid_%d" % variant, func() -> Resource:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 10
		sphere.rings = 6
		var arrays := sphere.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var base := [Color(0.55, 0.5, 0.46), Color(0.5, 0.45, 0.52), Color(0.6, 0.52, 0.42)][variant % 3] as Color
		for i in range(0, idx.size(), 3):
			var tri: Array[Vector3] = []
			for k in 3:
				var v := verts[idx[i + k]]
				var h := sin(v.x * 4.1 + variant * 1.7) * cos(v.y * 3.3 - variant) * sin(v.z * 3.7 + 0.5)
				tri.append(v * (0.82 + 0.28 * h))
			var n := (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
			var shade := base.darkened(0.12 * absf(sin(float(i) * 0.37)))
			for k in 3:
				st.set_color(shade)
				st.set_normal(-n)
				st.add_vertex(tri[k])
		var m := st.commit()
		m.surface_set_material(0, MeshKit.vertex_material(false, false))
		return m)


## A thin glowing bolt (laser), length 1 along -Z (scale z for longer bolts).
static func bolt() -> ArrayMesh:
	return _cached("bolt", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.capsule(0.12, 1.0, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1, 1, 1), 8, true)
		return b.build())


## Speed streak (a thin box 1 m long along Z), drawn additive.
static func streak() -> ArrayMesh:
	return _cached("streak", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.box(Vector3(0.05, 0.05, 1.0), MeshKit.at(Vector3.ZERO), Color(0.8, 0.9, 1.0))
		return b.build(MeshKit.additive_material()))


## Glowing storm cloud blob (a soft sphere with a few lumps), drawn additive.
static func storm_cell() -> ArrayMesh:
	return _cached("storm_cell", func() -> Resource:
		var b := MeshKit.Builder.new()
		var c := Color(0.32, 0.18, 0.45)
		b.sphere(1.0, MeshKit.at(Vector3.ZERO), c, 14)
		b.sphere(0.7, MeshKit.at(Vector3(0.6, 0.3, 0.2)), c, 12)
		b.sphere(0.6, MeshKit.at(Vector3(-0.6, -0.2, 0.3)), c, 12)
		return b.build(MeshKit.additive_material()))


## A ringed planet (sphere + ring), cached per colour pair.
static func planet(col: Color, ring: Color) -> ArrayMesh:
	return _cached("planet_%s_%s" % [col.to_html(false), ring.to_html(false)], func() -> Resource:
		var b := MeshKit.Builder.new()
		b.sphere(1.0, MeshKit.at(Vector3.ZERO), col, 24)
		b.ellipsoid(Vector3(1.01, 0.35, 1.01), MeshKit.at(Vector3(0, 0.25, 0)), col.lightened(0.15), 24)
		b.ellipsoid(Vector3(1.005, 0.2, 1.005), MeshKit.at(Vector3(0, -0.4, 0)), col.darkened(0.15), 24)
		if ring.a > 0.0:
			b.torus(1.7, 0.18, MeshKit.at(Vector3.ZERO, Vector3(1, 0.12, 1), Vector3(0.0, 0, 0.0)), ring, 36, 4)
		return b.build())


## The captain's flight stick (pivot at its base, handle up +Y).
static func flight_stick() -> ArrayMesh:
	return _cached("flight_stick", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cylinder(0.018, 0.024, 0.2, MeshKit.at(Vector3(0, 0.1, 0)), Color(0.3, 0.32, 0.38), 10)
		b.capsule(0.045, 0.14, MeshKit.at(Vector3(0, 0.23, 0)), Color(0.15, 0.15, 0.18), 12)
		b.sphere(0.02, MeshKit.at(Vector3(0, 0.3, -0.02)), Color(1.0, 0.3, 0.3), 8, true)
		return b.build())


## The throttle lever (pivot at its base, arm up +Y, knob on top).
static func throttle_lever() -> ArrayMesh:
	return _cached("throttle", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cylinder(0.016, 0.02, 0.2, MeshKit.at(Vector3(0, 0.1, 0)), Color(0.3, 0.32, 0.38), 10)
		b.rounded_box(Vector3(0.12, 0.07, 0.07), 0.025, MeshKit.at(Vector3(0, 0.22, 0)), Color(1.0, 0.75, 0.25), 2)
		return b.build())


## A big round push button (top at y = 0, so the node sits on the dashboard surface). col = cap colour.
static func push_button(radius: float, col: Color) -> ArrayMesh:
	return _cached("button_%.3f_%s" % [radius, col.to_html(false)], func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cylinder(radius, radius * 1.05, 0.035, MeshKit.at(Vector3(0, 0.0175, 0)), col, 18, true)
		b.sphere(radius * 0.92, MeshKit.at(Vector3(0, 0.03, 0), Vector3(1, 0.3, 1)), col.lightened(0.25), 14, true)
		return b.build())
