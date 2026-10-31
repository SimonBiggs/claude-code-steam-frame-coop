extends RefCounted
## KART RACE track extras built after track.gd's own parts: the cups' HAZARDS (chocolate / mud puddles, ice, glowing
## moon pads, gumdrops, mossy rocks, snowballs and meteor rocks) and the two newer places' props (JUNGLE: palm trees,
## giant leaves and flowers; SPACE: glowing crystals, light posts and big planets in the sky).
##   Props.build(track)    # called by track.gd build_info, adds everything under track.built

const PATCH_COLORS := {"chocolate": Color(0.38, 0.2, 0.1), "mud": Color(0.3, 0.22, 0.12), "ice": Color(0.75, 0.92, 1.0), "moon": Color(0.7, 0.4, 1.0)}
const BUMP_COLORS := {"gumdrop": [Color(1.0, 0.35, 0.55), Color(0.4, 0.85, 1.0), Color(1.0, 0.85, 0.3), Color(0.55, 1.0, 0.5)],
	"rock": [Color(0.5, 0.55, 0.45), Color(0.45, 0.5, 0.42)], "snowball": [Color(0.97, 0.98, 1.0)], "meteor": [Color(0.35, 0.3, 0.35)]}


static func build(t) -> void:
	if not t.hazards.is_empty():
		_hazards(t)
	match str(t.info.get("theme", "")):
		"jungle":
			_jungle(t)
		"space":
			_space(t)


static func _hazards(t) -> void:
	var looks: Dictionary = t.Cups.HAZARDS.get(t.hz_style, {})
	var patch_look := String(looks.get("patch_look", "mud"))
	var bump_look := String(looks.get("bump_look", "rock"))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_patch := false
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + t.look
	for h in t.hazards:
		var ha: Array = h
		if String(ha[2]) != "patch":
			continue
		any_patch = true
		var s0: float = ha[0]
		var lat: float = ha[1]
		var hw: float = ha[3]
		var ln: float = ha[4]
		var col: Color = PATCH_COLORS.get(patch_look, Color(0.3, 0.2, 0.1))
		# A rounded blob: rings of points in (s, lat) space, fanned from the middle.
		var mid: Array = t.point_at(s0 + ln * 0.5, lat)
		var c: Vector3 = (mid[0] as Vector3) + Vector3(0, 0.05, 0)
		var seg := 18
		var prev := Vector3.ZERO
		for k in seg + 1:
			var a := TAU * k / seg
			var wob := 1.0 + 0.08 * sin(a * 3.0 + s0)
			var p: Array = t.point_at(s0 + ln * 0.5 + cos(a) * ln * 0.5 * wob, lat + sin(a) * hw * wob)
			var q: Vector3 = (p[0] as Vector3) + Vector3(0, 0.05, 0)
			if k > 0:
				st.set_normal(Vector3.UP)
				st.set_color(col.lightened(0.12))
				st.add_vertex(c)
				st.set_color(col)
				st.add_vertex(prev)
				st.add_vertex(q)
			prev = q
		if patch_look == "moon":  # glowing rings on the moon pad
			for ring in [0.45, 0.8]:
				var rp := Vector3.ZERO
				for k in seg + 1:
					var a := TAU * k / seg
					var p: Array = t.point_at(s0 + ln * 0.5 + cos(a) * ln * 0.5 * float(ring), lat + sin(a) * hw * float(ring))
					var q: Vector3 = (p[0] as Vector3) + Vector3(0, 0.07, 0)
					if k > 0:
						var o := (q - rp).cross(Vector3.UP).normalized() * 0.12
						st.set_color(Color(1.0, 0.85, 1.0))
						for v in [rp - o, rp + o, q + o, rp - o, q + o, q - o]:
							st.add_vertex(v)
					rp = q
		elif patch_look == "chocolate":  # sprinkles
			for k in 10:
				var p: Array = t.point_at(s0 + rng.randf_range(0.2, 0.8) * ln, lat + rng.randf_range(-0.6, 0.6) * hw)
				var q: Vector3 = (p[0] as Vector3) + Vector3(0, 0.07, 0)
				var d := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
				var o := d.cross(Vector3.UP) * 0.05
				st.set_color(Color.from_hsv(rng.randf(), 0.6, 1.0))
				for v in [q - d * 0.18 - o, q + d * 0.18 - o, q + d * 0.18 + o, q - d * 0.18 - o, q + d * 0.18 + o, q - d * 0.18 + o]:
					st.add_vertex(v)
	if any_patch:
		var mi := MeshInstance3D.new()
		mi.name = "Puddles"
		mi.mesh = st.commit()
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		match patch_look:
			"ice":
				m.roughness = 0.05
				m.metallic = 0.3
				m.emission_enabled = true
				m.emission = Color(0.25, 0.35, 0.45)
			"moon":
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			"chocolate":
				m.roughness = 0.15
			_:
				m.roughness = 0.95
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.built.add_child(mi)
	# Bumpers: one merged mesh.
	if t.bumpers.is_empty():
		return
	var bs := SurfaceTool.new()
	bs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols: Array = BUMP_COLORS.get(bump_look, [Color(0.5, 0.5, 0.5)])
	var i := 0
	for b in t.bumpers:
		var ba: Array = b
		var c: Vector3 = ba[0]
		var r: float = ba[1]
		var col: Color = cols[i % cols.size()]
		i += 1
		match bump_look:
			"gumdrop":
				t.main.add_ellipsoid(bs, c + Vector3(0, r * 0.45, 0), Vector3(r, r * 0.95, r), col, 12, 7)
				t.main.add_ellipsoid(bs, c + Vector3(0, r * 1.25, 0), Vector3(r * 0.45, r * 0.25, r * 0.45), col.lightened(0.4), 8, 4)
			"rock":
				t.main.add_ellipsoid(bs, c + Vector3(0, r * 0.5, 0), Vector3(r * 1.05, r * 0.8, r * 0.95), col, 9, 5)
				t.main.add_ellipsoid(bs, c + Vector3(r * 0.2, r * 1.05, -r * 0.1), Vector3(r * 0.7, r * 0.25, r * 0.6), Color(0.35, 0.7, 0.3), 8, 4)
			"snowball":
				t.main.add_ellipsoid(bs, c + Vector3(0, r * 0.85, 0), Vector3(r, r, r), col, 12, 7)
				for e in [-0.3, 0.3]:  # a friendly face looking down the road
					t.main.add_ellipsoid(bs, c + Vector3(float(e) * r, r * 1.15, 0) + _back(t, ba) * r * 0.92, Vector3.ONE * r * 0.1, Color(0.1, 0.1, 0.12), 6, 3)
			"meteor":
				t.main.add_ellipsoid(bs, c + Vector3(0, r * 0.55, 0), Vector3(r, r * 0.85, r * 0.95), col, 9, 5)
				for k in 4:
					var a := TAU * k / 4.0 + 0.4
					t.main.add_ellipsoid(bs, c + Vector3(cos(a) * r * 0.8, r * 0.6, sin(a) * r * 0.8), Vector3.ONE * r * 0.22, Color(1.0, 0.55, 0.2), 6, 3)
	var bmi := MeshInstance3D.new()
	bmi.name = "Bumpers"
	bmi.mesh = bs.commit()
	var bm := StandardMaterial3D.new()
	bm.vertex_color_use_as_albedo = true
	bm.roughness = 0.35 if bump_look == "gumdrop" else 0.85
	if bump_look == "meteor" or t.is_night():
		bm.emission_enabled = true
		bm.emission = Color(0.25, 0.15, 0.1) if bump_look == "meteor" else Color(0.1, 0.1, 0.15)
	bmi.material_override = bm
	t.built.add_child(bmi)


## The direction back down the road from a bumper (karts come from there).
static func _back(t, ba: Array) -> Vector3:
	var p: Array = t.point_at(float(ba[2]), float(ba[3]))
	var yaw: float = p[1]
	return Vector3(sin(yaw), 0.0, cos(yaw))


static func _jungle(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150 + t.look
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Vector3 in t._side_spots(rng, 30, 2.5, 16.0):
		var h := rng.randf_range(5.0, 8.0)
		var lean := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
		for k in 6:  # a curved, ringed trunk
			var f := float(k) / 5.0
			t.main.add_ellipsoid(st, p + Vector3(0, f * h, 0) + lean * f * f * 2.0, Vector3(0.32, h / 9.0, 0.32) * (1.0 - f * 0.3),
				Color(0.55, 0.38, 0.22) if k % 2 == 0 else Color(0.48, 0.32, 0.18), 7, 4)
		var top := p + Vector3(0, h, 0) + lean * 2.0
		for k in 6:
			var a := TAU * k / 6.0 + rng.randf()
			var d := Vector3(cos(a), 0, sin(a))
			t.main.add_ellipsoid(st, top + d * 1.6 + Vector3(0, -0.35, 0), Vector3(0.9 + absf(cos(a)) * 0.9, 0.18, 0.9 + absf(sin(a)) * 0.9),
				Color(0.15, 0.55, 0.2).lightened(rng.randf_range(0.0, 0.15)), 7, 3)
		if rng.randf() < 0.5:
			for k in 3:
				t.main.add_ellipsoid(st, top + Vector3(rng.randf_range(-0.3, 0.3), -0.45, rng.randf_range(-0.3, 0.3)), Vector3.ONE * 0.25,
					Color(0.45, 0.3, 0.15), 6, 3)
	for p: Vector3 in t._side_spots(rng, 50, 0.5, 9.0):  # giant leaves and bright flowers by the road
		if rng.randf() < 0.6:
			t.main.add_ellipsoid(st, p + Vector3(0, 0.45, 0), Vector3(rng.randf_range(0.8, 1.4), 0.45, rng.randf_range(0.8, 1.4)),
				Color(0.18, 0.5, 0.2).lightened(rng.randf_range(0.0, 0.2)), 8, 4)
		else:
			var fc: Color = [Color(1.0, 0.3, 0.3), Color(1.0, 0.6, 0.15), Color(1.0, 0.4, 0.75), Color(1.0, 0.9, 0.3)][rng.randi() % 4]
			t.main.add_ellipsoid(st, p + Vector3(0, 0.6, 0), Vector3(0.35, 0.22, 0.35), fc, 8, 4)
			t.main.add_ellipsoid(st, p + Vector3(0, 0.25, 0), Vector3(0.12, 0.3, 0.12), Color(0.2, 0.55, 0.2), 5, 3)
	var mi := MeshInstance3D.new()
	mi.name = "Jungle"
	mi.mesh = st.commit()
	mi.material_override = t._vc(0.0)
	t.built.add_child(mi)


static func _space(t) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6160 + t.look
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow: Array[Color] = [Color(0.45, 1.0, 0.85), Color(0.85, 0.45, 1.0), Color(1.0, 0.85, 0.4)]
	for p: Vector3 in t._side_spots(rng, 40, 1.0, 16.0):  # glowing crystals
		var col: Color = glow[rng.randi() % glow.size()]
		var h := rng.randf_range(1.2, 3.5)
		for k in rng.randi_range(1, 3):
			var o := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
			t.main.add_ellipsoid(st, p + o + Vector3(0, h * 0.5, 0), Vector3(0.3, h * 0.55, 0.3) * rng.randf_range(0.6, 1.0), col, 5, 3)
	var mi := MeshInstance3D.new()
	mi.name = "Crystals"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.built.add_child(mi)
	# Big planets (one with a ring) hanging in the black sky.
	var ps := SurfaceTool.new()
	ps.begin(Mesh.PRIMITIVE_TRIANGLES)
	var planets := [[Color(1.0, 0.55, 0.35), 34.0], [Color(0.45, 0.7, 1.0), 22.0], [Color(0.8, 0.5, 1.0), 14.0]]
	for k in planets.size():
		var a := rng.randf() * TAU
		var c := Vector3(20 + cos(a) * 300.0, rng.randf_range(90.0, 160.0), -35 + sin(a) * 300.0)
		var pl: Array = planets[k]
		t.main.add_ellipsoid(ps, c, Vector3.ONE * float(pl[1]), pl[0], 16, 10)
		if k == 0:
			t.main.add_ellipsoid(ps, c, Vector3(float(pl[1]) * 1.9, 1.2, float(pl[1]) * 1.9), Color(1.0, 0.85, 0.6), 24, 3)
	var pmi := MeshInstance3D.new()
	pmi.name = "Planets"
	pmi.mesh = ps.commit()
	var pm := StandardMaterial3D.new()
	pm.vertex_color_use_as_albedo = true
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.disable_fog = true
	pmi.material_override = pm
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.built.add_child(pmi)
