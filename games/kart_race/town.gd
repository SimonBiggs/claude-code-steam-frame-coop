extends RefCounted
## BOLT'S RACE TOWN (deep.gd TOWN): little buildings by the start of every track, one more every Deep.TOWN_EVERY races
## the family finishes (saved "races"), then balloons over it. Built as one merged mesh from the town size, placed by
## main.gd beside the start straight on the other side of the road from Bolt's shelf (inside the GAP trackgen.gd keeps
## clear of any other part of the track). Local +Z faces the road, +X runs along it (the way the karts go).
##   var node := Town.build(main, Deep.town_size(races))

const Deep := preload("res://games/kart_race/deep.gd")

## Where each building stands in the town's space (x along the road, z away from it: negative = further back).
const SPOTS: Array[Vector2] = [Vector2(-9.0, 0.0), Vector2(-3.0, 0.5), Vector2(3.0, 0.0), Vector2(9.0, 0.5), Vector2(15.0, 0.0),
	Vector2(-6.0, -6.0), Vector2(0.5, -7.0), Vector2(7.0, -6.0), Vector2(13.0, -7.5), Vector2(19.0, -6.0)]
const WIDTH := 34.0  # metres along the road it needs (main.gd keeps it on the start straight)


## flip: mirror along the road (the town on the other side of the road still runs the way the karts go).
static func build(main, size: Vector2i, flip: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "BoltTown"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow := SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_glow := false
	for i in mini(size.x, Deep.TOWN.size()):
		var at := Vector3(SPOTS[i].x * (-1.0 if flip else 1.0), 0.0, SPOTS[i].y)
		any_glow = _building(main, st, glow, String(Deep.TOWN[i][0]), at, i) or any_glow
	for j in size.y:  # balloons over the finished town
		var c: Color = [Color(1.0, 0.35, 0.4), Color(0.4, 0.7, 1.0), Color(1.0, 0.85, 0.3), Color(0.5, 0.95, 0.5),
			Color(0.85, 0.5, 1.0), Color(1.0, 0.6, 0.2)][j % 6]
		var p := Vector3((-8.0 + j * 5.0) * (-1.0 if flip else 1.0), 9.0 + (j % 2) * 2.0, -3.0 - (j % 3))
		main.add_ellipsoid(st, p, Vector3(0.9, 1.1, 0.9), c, 10, 6)
		main.add_cyl(st, p - Vector3(0, 3.4, 0), 0.02, 4.6, Color(0.9, 0.9, 0.9))
	var mi := MeshInstance3D.new()
	mi.name = "Town"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.6
	mi.material_override = m
	root.add_child(mi)
	if any_glow:
		var gi := MeshInstance3D.new()
		gi.name = "TownLights"
		gi.mesh = glow.commit()
		var gm := StandardMaterial3D.new()
		gm.vertex_color_use_as_albedo = true
		gm.vertex_color_is_srgb = true
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gi.material_override = gm
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(gi)
	root.set_meta("buildings", mini(size.x, Deep.TOWN.size()))
	root.set_meta("balloons", size.y)
	return root


## One building at `at`. Returns true when it put something in the glow mesh.
## Where the town of n buildings stands by the start of track t (a prepared track.gd): {"xf": Transform3D, "flip": bool},
## or {} when no spot beside the start straight is clear of every road (tests/kart_deep_test.gd: that never happens).
## Tries the far side of the road from Bolt's shelf first, then further back / along.
const PLACES: Array = [[-3.0, 1.0], [-3.0, -1.0], [-14.0, 1.0], [6.0, -1.0], [-14.0, -1.0], [10.0, 1.0]]
const FRONT := 7.5  # metres past the wall to the front row's centres (clear of the grandstands and the shelf)


static func place(t, n: int) -> Dictionary:
	for cand in PLACES:
		var s0 := float(cand[0])
		var side := float(cand[1])
		var flip := side > 0.0
		var p: Array = t.point_at(s0, side * (t.wall_at(s0) + FRONT))
		var yaw := float(p[1]) + (-PI * 0.5 if flip else PI * 0.5)
		var xf := Transform3D(Basis(Vector3.UP, yaw), p[0])
		var ok := true
		for i in mini(n, SPOTS.size()):
			for off in [Vector3.ZERO, Vector3(2.5, 0, 0), Vector3(-2.5, 0, 0), Vector3(0, 0, 2.5), Vector3(0, 0, -2.5)]:
				var w: Vector3 = xf * (spot(i, flip) + off)
				var lr: Array = t.locate(w, -1)
				if absf(float(lr[2])) < t.wall_at(float(lr[1])) + 2.0:
					ok = false
					break
			if not ok:
				break
		if ok:
			return {"xf": xf, "flip": flip}
	return {}


## The spots' centres in the town's space (main.gd checks each stands clear of every road before placing the town).
static func spot(i: int, flip: bool) -> Vector3:
	return Vector3(SPOTS[i].x * (-1.0 if flip else 1.0), 0.0, SPOTS[i].y)


static func _building(main, st: SurfaceTool, glow: SurfaceTool, id: String, at: Vector3, i: int) -> bool:
	var red := Color(0.95, 0.3, 0.3)
	var white := Color(0.95, 0.95, 0.97)
	var grey := Color(0.4, 0.42, 0.48)
	var blue := Color(0.35, 0.6, 1.0)
	var yellow := Color(1.0, 0.82, 0.25)
	match id:
		"tyres":  # a tower of tyres, red and white
			for k in 6:
				main.add_cyl(st, at + Vector3(0, 0.3 + k * 0.55, 0), 0.9, 0.5, Color(0.12, 0.12, 0.14), Basis(), 12)
				main.add_cyl(st, at + Vector3(0, 0.3 + k * 0.55, 0), 0.92, 0.12, red if k % 2 == 0 else white, Basis(), 12)
		"flags":  # three tall poles with chequered and coloured flags
			for k in 3:
				var p := at + Vector3(-1.6 + k * 1.6, 0, 0)
				main.add_cyl(st, p + Vector3(0, 2.6, 0), 0.06, 5.2, white)
				var fc: Color = [red, blue, yellow][k]
				for q in 6:
					var c := (Color(0.1, 0.1, 0.12) if (q + int(q / 3.0)) % 2 == 0 else white) if k == 1 else fc
					main.add_box(st, p + Vector3(0.3 + (q % 3) * 0.32, 4.9 - int(q / 3.0) * 0.32, 0), Vector3(0.32, 0.32, 0.04), c)
		"garage":  # a little workshop with a striped roll door
			main.add_box(st, at + Vector3(0, 1.6, -0.5), Vector3(5.0, 3.2, 3.6), Color(0.85, 0.85, 0.9))
			main.add_box(st, at + Vector3(0, 3.35, -0.5), Vector3(5.4, 0.3, 4.0), blue)
			for k in 5:
				main.add_box(st, at + Vector3(0, 0.3 + k * 0.5, 1.32), Vector3(3.4, 0.42, 0.05), grey if k % 2 == 0 else grey.lightened(0.3))
		"snacks":  # a snack stand with a striped awning and a giant ice cream on top
			main.add_box(st, at + Vector3(0, 0.6, 0), Vector3(3.0, 1.2, 1.6), Color(1.0, 0.9, 0.75))
			for k in 6:
				main.add_box(st, at + Vector3(-1.25 + k * 0.5, 2.3, 0.4), Vector3(0.5, 0.12, 2.2), red if k % 2 == 0 else white,
					Basis(Vector3.RIGHT, 0.25))
			for x in [-1.4, 1.4]:
				main.add_cyl(st, at + Vector3(x, 1.2, 1.2), 0.06, 2.4, white)
			main.add_cyl(st, at + Vector3(0, 3.0, 0), 0.25, 1.0, Color(0.85, 0.6, 0.3))
			main.add_ellipsoid(st, at + Vector3(0, 3.7, 0), Vector3(0.55, 0.5, 0.55), Color(1.0, 0.65, 0.8), 10, 6)
		"tower":  # a control tower with a glass top that lights up
			main.add_cyl(st, at + Vector3(0, 3.0, 0), 0.8, 6.0, white, Basis(), 12)
			main.add_cyl(st, at + Vector3(0, 6.9, 0), 1.5, 0.3, grey, Basis(), 14)
			main.add_cyl(glow, at + Vector3(0, 7.6, 0), 1.35, 1.1, Color(0.55, 0.85, 1.0), Basis(), 14)
			main.add_cyl(st, at + Vector3(0, 8.3, 0), 1.6, 0.3, red, Basis(), 14)
			main.add_ellipsoid(glow, at + Vector3(0, 9.0, 0), Vector3(0.25, 0.25, 0.25), red, 8, 4)
			return true
		"arch":  # an arch of balloons
			for k in 13:
				var a := PI * k / 12.0
				var c: Color = [red, blue, yellow, Color(0.5, 0.95, 0.5)][k % 4]
				main.add_ellipsoid(st, at + Vector3(-cos(a) * 2.6, sin(a) * 3.2 + 0.3, 0), Vector3(0.42, 0.5, 0.42), c, 8, 5)
		"hotair":  # a hot-air balloon tied down, floating up high
			main.add_box(st, at + Vector3(0, 0.45, 0), Vector3(1.0, 0.9, 1.0), Color(0.6, 0.4, 0.22))
			for x in [-0.4, 0.4]:
				for z in [-0.4, 0.4]:
					main.add_cyl(st, at + Vector3(x, 2.2, z), 0.02, 2.6, Color(0.5, 0.4, 0.3))
			for k in 6:
				var a := TAU * k / 6.0
				main.add_ellipsoid(st, at + Vector3(cos(a) * 0.9, 5.2, sin(a) * 0.9), Vector3(1.4, 2.0, 1.4), [red, yellow][k % 2], 10, 6)
		"statue":  # Bolt on a plinth, waving
			main.add_box(st, at + Vector3(0, 0.6, 0), Vector3(2.0, 1.2, 2.0), Color(0.8, 0.78, 0.72))
			var gold := Color(1.0, 0.8, 0.3)
			main.add_box(st, at + Vector3(0, 2.0, 0), Vector3(1.1, 1.4, 0.8), gold)
			main.add_box(st, at + Vector3(0, 3.1, 0), Vector3(0.9, 0.75, 0.75), gold)
			main.add_box(st, at + Vector3(0.85, 2.8, 0), Vector3(0.25, 1.1, 0.25), gold, Basis(Vector3.BACK, -0.5))
			main.add_cyl(st, at + Vector3(0, 3.7, 0), 0.04, 0.5, gold)
			main.add_ellipsoid(glow, at + Vector3(0, 4.0, 0), Vector3(0.15, 0.15, 0.15), Color(1.0, 0.4, 0.3), 8, 4)
			main.add_ellipsoid(glow, at + Vector3(-0.2, 3.15, 0.38), Vector3(0.1, 0.1, 0.05), Color(0.6, 0.9, 1.0), 6, 3)
			main.add_ellipsoid(glow, at + Vector3(0.2, 3.15, 0.38), Vector3(0.1, 0.1, 0.05), Color(0.6, 0.9, 1.0), 6, 3)
			return true
		"wheel":  # a small big wheel (it faces the road)
			for x in [-1.6, 1.6]:
				main.add_box(st, at + Vector3(x * 0.6, 2.6, -0.2), Vector3(0.2, 5.4, 0.2), white, Basis(Vector3.BACK, x * 0.12))
			for k in 10:
				var a := TAU * k / 10.0
				var p := at + Vector3(cos(a) * 3.2, 5.0 + sin(a) * 3.2, 0.3)
				main.add_box(st, (at + Vector3(0, 5.0, 0.3) + p) * 0.5, Vector3(0.1, 3.2, 0.1), white, Basis(Vector3.BACK, a + PI * 0.5))
				main.add_box(st, p - Vector3(0, 0.5, 0), Vector3(0.8, 0.7, 0.8), [red, blue, yellow, Color(0.5, 0.95, 0.5)][k % 4])
		"fireworks":  # a rocket tower with glowing stars on top
			main.add_cyl(st, at + Vector3(0, 2.0, 0), 0.5, 4.0, Color(0.3, 0.3, 0.45))
			main.add_cyl(st, at + Vector3(0, 4.6, 0), 0.35, 1.2, red)
			for k in 5:
				var a := TAU * k / 5.0
				main.add_ellipsoid(glow, at + Vector3(cos(a) * 1.3, 6.5 + sin(a * 2.0) * 0.4, sin(a) * 1.3), Vector3(0.22, 0.22, 0.22),
					[yellow, red, blue, Color(0.5, 0.95, 0.5), Color(1.0, 0.6, 0.9)][k], 6, 3)
			return true
	return false