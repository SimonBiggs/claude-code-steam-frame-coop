extends RefCounted
## SEASON KIT (shared by the second passes that dress a game for the season: Mini Golf Party, Penalty Shootout,
## Rhythm Band, Roller Coaster ...): the little seasonal props (a snowman, a pumpkin on leaves, a tub of flowers,
## sunflowers) baked into one core/mesh_kit.gd Builder, and the drifting things (blossom, leaves, snow) as ONE
## CPUParticles3D. A game keeps its own spots, size, colours and drift box; never its own copy of the props.
##   var b := MeshKit.Builder.new()
##   for i in spots.size(): SeasonKit.prop(b, season, spots[i], i, size, facing)
##   add_child(MeshKit.instance(b.build(), false))
##   add_child(SeasonKit.drift(colour, season, {"box": Vector3(12, 0.5, 5), "at": Vector3(0, 8, -9), "amount": 80}))
## And the ONE season test setting for every game (bots, deep tests, What's New "try"):
##   season = SeasonKit.override(G.GAME_ID, Seeded.season(), Deep.SEASONS)
## ARCADE_SEASON=winter dresses every game for winter; ARCADE_SEASON_<GAME_ID>=summer (e.g. ARCADE_SEASON_KART_RACE)
## just that one game (it wins over ARCADE_SEASON). A game never reads its own XX_SEASON env
## (tests/season_override_test.gd fails it).

const MeshKit := preload("res://core/mesh_kit.gd")

const SEASONS: Array[String] = ["spring", "summer", "autumn", "winter"]
const ENV := "ARCADE_SEASON"

static var _said := {}  # env=value lines already printed (a game may ask every frame)


## The season a game should use: ARCADE_SEASON_<GAME_ID>, else ARCADE_SEASON, else `fallback` (the game's own
## Seeded.season() etc.). `allowed`: the game's valid seasons (an Array, or a Dictionary keyed by season). A value
## that is set but not allowed prints a visible SEASON WARNING and uses `fallback` (never a quiet fallback).
static func override(game_id: String, fallback: String, allowed: Variant = SEASONS) -> String:
	for key in [ENV + "_" + game_id.to_upper(), ENV]:
		if not OS.has_environment(key):
			continue
		var v := OS.get_environment(key).strip_edges().to_lower()
		if v == "":
			continue
		var line := "%s=%s" % [key, v]
		if allowed.has(v):
			if not _said.has(line):
				_said[line] = true
				print("SeasonKit: %s season %s (%s)" % [game_id, v, line])
			return v
		if not _said.has(line):
			_said[line] = true
			print("SEASON WARNING: %s is not a %s season (allowed: %s): using %s" % [line, game_id, str(allowed.keys() if allowed is Dictionary else allowed), fallback])
			push_warning("SeasonKit: %s is not a %s season" % [line, game_id])
		return fallback
	return fallback


## One seasonal prop standing at `at` (on the ground), `size` times its 1 m-ish base size. facing: the way a face
## (the snowman's nose, the sunflowers) looks (+Z by default).
static func prop(b: MeshKit.Builder, s: String, at: Vector3, i: int, size: float = 1.0, facing: Vector3 = Vector3.BACK) -> void:
	var yaw := atan2(facing.x, facing.z)
	var xf := func(p: Vector3, sc: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> Transform3D:
		return Transform3D(Basis(Vector3.UP, yaw), at) * MeshKit.at(p * size, sc * size, rot)
	match s:
		"winter":  # a snowman with a carrot nose and a scarf, on a snow pile
			var w := Color(0.97, 0.98, 1.0)
			b.cylinder(0.45, 0.55, 0.1, xf.call(Vector3(0, 0.05, 0)), w, 12)
			b.sphere(0.3, xf.call(Vector3(0, 0.3, 0)), w, 10)
			b.sphere(0.22, xf.call(Vector3(0, 0.7, 0)), w, 10)
			b.sphere(0.15, xf.call(Vector3(0, 1.0, 0)), w, 10)
			b.cone(0.03, 0.15, xf.call(Vector3(0, 1.0, 0.16), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.5, 0.1), 6)
			b.cylinder(0.18, 0.18, 0.06, xf.call(Vector3(0, 0.86, 0)), [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 1.0)][i % 2], 10)
		"autumn":  # a pumpkin on a pile of leaves
			b.cylinder(0.45, 0.55, 0.1, xf.call(Vector3(0, 0.05, 0)), Color(0.9, 0.45, 0.12), 10)
			b.sphere(0.24, xf.call(Vector3(0.1, 0.25, 0), Vector3(1.25, 0.85, 1.25)), Color(1.0, 0.55, 0.1), 10)
			b.cylinder(0.025, 0.03, 0.1, xf.call(Vector3(0.1, 0.48, 0)), Color(0.3, 0.5, 0.15), 6)
			b.sphere(0.14, xf.call(Vector3(-0.25, 0.16, 0.18), Vector3(1.2, 0.85, 1.2)), Color(0.95, 0.7, 0.15), 8)
		"spring":  # a tub of tulips
			b.cylinder(0.28, 0.22, 0.3, xf.call(Vector3(0, 0.15, 0)), Color(0.55, 0.32, 0.18), 10)
			for k in 6:
				var a := float(k) * TAU / 6.0
				var top := Vector3(cos(a) * 0.14, 0.55 + 0.06 * (k % 2), sin(a) * 0.14)
				b.cylinder(0.012, 0.012, 0.25, xf.call(top - Vector3(0, 0.125, 0)), Color(0.3, 0.6, 0.25), 4)
				b.sphere(0.07, xf.call(top, Vector3(1.0, 1.3, 1.0)), [Color(1.0, 0.4, 0.6), Color(1.0, 1.0, 1.0), Color(1.0, 0.85, 0.3)][k % 3], 8)
		_:  # summer: two tall sunflowers
			for k in 2:
				var p := Vector3(k * 0.35 - 0.17, 0, k * 0.1)
				var h := 1.1 + 0.2 * k
				b.cylinder(0.02, 0.025, h, xf.call(p + Vector3(0, h * 0.5, 0)), Color(0.3, 0.6, 0.2), 6)
				b.cylinder(0.2, 0.2, 0.03, xf.call(p + Vector3(0, h + 0.05, 0.03), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.85, 0.15), 14)
				b.cylinder(0.1, 0.1, 0.04, xf.call(p + Vector3(0, h + 0.05, 0.05), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.4, 0.25, 0.1), 12)


## The season's drifting things as one particle node. o: at (its middle), box (emission half-extents), amount,
## lifetime, size (a leaf's width), speed (Vector2 min, max), dir.
static func drift(color: Color, s: String, o: Dictionary = {}) -> CPUParticles3D:
	var d := CPUParticles3D.new()
	d.name = "SeasonDrift"
	d.amount = int(o.get("amount", 80))
	d.lifetime = float(o.get("lifetime", 8.0))
	d.preprocess = d.lifetime
	d.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	d.emission_box_extents = o.get("box", Vector3(10.0, 0.5, 10.0))
	d.position = o.get("at", Vector3(0.0, 8.0, 0.0))
	d.direction = o.get("dir", Vector3(0.3, -1.0, 0.0))
	d.spread = 25.0
	d.gravity = Vector3(0.0, -0.4, 0.0)
	var sp: Vector2 = o.get("speed", Vector2(0.6, 1.4))
	d.initial_velocity_min = sp.x
	d.initial_velocity_max = sp.y
	d.angular_velocity_min = -90.0
	d.angular_velocity_max = 90.0
	var w := float(o.get("size", 0.14))
	var q := QuadMesh.new()
	q.size = Vector2(w, w * 0.7) if s != "winter" else Vector2(w * 0.7, w * 0.7)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	d.mesh = q
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return d
