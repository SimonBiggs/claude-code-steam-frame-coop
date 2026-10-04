extends "res://tests/engine_ui/part_base.gd"
## Engine test part: core/mesh_kit.gd, core/creatures.gd and core/sky_kit.gd.
## Checks winding/normals of every primitive, builder surfaces (incl. glow), the old merge() format,
## MultiMesh scatter, every prop, every humanoid class / hat / item / hair style, every monster
## (near, far and auto LOD), every animation, and every sky preset (TV and VR) with blends,
## time of day and lightning. Prints draw-call estimates.

const MeshKit := preload("res://core/mesh_kit.gd")
const Creatures := preload("res://core/creatures.gd")
const SkyKit := preload("res://core/sky_kit.gd")
const ResCache := preload("res://core/res_cache.gd")


func run() -> void:
	tag = "world"
	_test_primitives()
	_test_builder()
	_test_props_and_scatter()
	await _test_creatures()
	await _test_animations()
	await _test_skies()


# --- MeshKit ---------------------------------------------------------------------------------------

## Every triangle's Godot front face (clockwise) must agree with its vertex normals, and for closed
## convex shapes point away from the centre.
func _winding(mesh: ArrayMesh, convex: bool, label: String, center: Vector3 = Vector3.ZERO) -> void:
	var bad_n := 0
	var bad_c := 0
	var tris := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			var a := v[idx[t]]
			var b := v[idx[t + 1]]
			var c := v[idx[t + 2]]
			var g := (c - a).cross(b - a)
			if g.length_squared() < 1e-14:
				continue
			tris += 1
			if g.dot(n[idx[t]] + n[idx[t + 1]] + n[idx[t + 2]]) <= 0.0:
				bad_n += 1
			if convex and g.dot((a + b + c) / 3.0 - center) <= 0.0:
				bad_c += 1
	check(tris > 0 and bad_n == 0 and bad_c == 0, "%s: %d tris, front faces agree with normals%s (bad %d/%d)" % [label, tris,
		" and point outwards" if convex else "", bad_n, bad_c])


func _one(kind: String, xf: Transform3D = Transform3D.IDENTITY) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	match kind:
		"box": b.box(Vector3(1, 2, 3), xf)
		"rounded_box": b.rounded_box(Vector3(1, 0.6, 0.8), 0.15, xf, Color.WHITE, 3)
		"sphere": b.sphere(0.5, xf)
		"ellipsoid": b.ellipsoid(Vector3(0.3, 0.6, 0.4), xf)
		"dome": b.dome(0.5, xf)
		"cylinder": b.cylinder(0.3, 0.5, 1.0, xf)
		"cone": b.cone(0.4, 1.0, xf)
		"capsule": b.capsule(0.25, 1.2, xf)
		"torus": b.torus(0.6, 0.15, xf)
		"wedge": b.wedge(Vector3(1, 0.5, 1.5), xf)
		"prism": b.prism(6, 0.5, 0.4, xf)
		"disc": b.disc(0.5, xf)
		"panel": b.panel(Vector2(1.2, 0.6), 0.1, xf, Color.WHITE, 4, false, true)
		"star": b.star(5, 0.5, 0.2, 0.1, xf)
		"polygon": b.polygon(PackedVector2Array([Vector2(0, 0), Vector2(1, 0.2), Vector2(0.8, -0.5), Vector2(0.1, -0.4)]), 0.02, xf)
		"tube": b.tube(Vector3(0, 0, 0), Vector3(0.5, 1, 0.2), 0.1, 0.05)
		"capsule_between": b.capsule_between(Vector3(0, 0, 0), Vector3(-0.3, 0.8, 0.4), 0.1)
	return b.build()


func _test_primitives() -> void:
	var convex := ["box", "rounded_box", "sphere", "ellipsoid", "dome", "cylinder", "cone", "capsule", "wedge", "prism"]
	var inside := {"dome": Vector3(0, 0.2, 0), "wedge": Vector3(0, -0.12, -0.3)}
	for k in convex:
		_winding(_one(k), true, k, inside.get(k, Vector3.ZERO))
	for k in ["torus", "disc", "panel", "star", "polygon", "tube", "capsule_between"]:
		_winding(_one(k), false, k)
	# transformed, non-uniformly scaled and mirrored parts keep their faces outward
	var xf := Transform3D(Basis.from_euler(Vector3(0.4, 1.1, -0.3)) * Basis.from_scale(Vector3(1.5, 0.5, 2.0)), Vector3(3, 1, -2))
	_winding(_one("sphere", xf), true, "sphere rotated + squashed", xf.origin)
	_winding(_one("rounded_box", xf), true, "rounded box rotated + squashed", xf.origin)
	var mirror := Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO)
	_winding(_one("box", mirror), true, "mirrored box")
	_winding(_one("cone", mirror), true, "mirrored cone")
	# vertex counts are what the generators promise
	var sb := MeshKit.Builder.new()
	sb.sphere(1.0, Transform3D.IDENTITY, Color.WHITE, 12)
	check(sb.vertex_count() == 13 * 7, "sphere(12 segs) has 91 vertices (got %d)" % sb.vertex_count())
	var bb := MeshKit.Builder.new()
	bb.box(Vector3.ONE)
	check(bb.vertex_count() == 24 and bb.triangle_count() == 12, "box: 24 verts, 12 tris")
	var rb := MeshKit.Builder.new()
	rb.rounded_box(Vector3.ONE, 0.2, Transform3D.IDENTITY, Color.WHITE, 2)
	check(rb.vertex_count() == 6 * 36, "rounded box (2 segs): 216 verts (got %d)" % rb.vertex_count())
	var aabb := _one("rounded_box").get_aabb()
	check(aabb.size.distance_to(Vector3(1, 0.6, 0.8)) < 0.01, "rounded box keeps its outer size (%s)" % aabb.size)
	var sph := _one("sphere").get_aabb()
	check(absf(sph.size.y - 1.0) < 0.001, "sphere is 2r tall")


func _test_builder() -> void:
	var b := MeshKit.Builder.new()
	b.box(Vector3.ONE, MeshKit.at(Vector3(0, 0.5, 0)), Color(0.8, 0.3, 0.2))
	b.sphere(0.2, MeshKit.at(Vector3(0, 1.2, 0)), Color(1, 0.9, 0.3), 10, true)
	b.add_mesh(SphereMesh.new(), MeshKit.at(Vector3(1, 0, 0), Vector3.ONE * 0.3), Color(0.2, 0.6, 1.0))
	var m := b.build()
	check(m.get_surface_count() == 2, "builder with a glowing part -> 2 surfaces (lit + glow)")
	check(m.surface_get_name(0) == "lit" and m.surface_get_name(1) == "glow", "surfaces are named lit/glow")
	check(m.surface_get_material(0) == MeshKit.vertex_material() and m.surface_get_material(1) == MeshKit.glow_material(),
		"surface materials are the shared kit materials")
	var vm := MeshKit.vertex_material()
	check(vm.vertex_color_use_as_albedo and vm.vertex_color_is_srgb, "vertex material uses sRGB vertex colours")
	# re-adding a kit mesh keeps its glow surface
	var b2 := MeshKit.Builder.new()
	b2.add_mesh(m, MeshKit.at(Vector3(5, 0, 0)))
	check(b2.build().get_surface_count() == 2, "add_mesh keeps the glow surface")
	# the old games' merge format, with a flag in UV.x
	var merged := MeshKit.merge([[BoxMesh.new(), Transform3D.IDENTITY, Color.RED], [SphereMesh.new(), MeshKit.at(Vector3.UP), Color.BLUE, 1.0]])
	var arr := merged.surface_get_arrays(0)
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	check(arr[Mesh.ARRAY_TEX_UV] != null and cols.size() > 0, "merge() keeps colours and writes the flag to UV")
	check(MeshKit.material(Color.RED, 1.0) == MeshKit.material(Color.RED, 1.0), "material() is cached per colour")
	check(MeshKit.aim(Vector3.ZERO, Vector3(1, 0, 0)).basis.y.distance_to(Vector3(1, 0, 0)) < 0.001, "aim() points +Y along dir")


func _test_props_and_scatter() -> void:
	var total := 0
	for p in MeshKit.prop_names():
		var m := MeshKit.prop(p)
		var ok := m != null and m.get_surface_count() >= 1 and m.get_aabb().size.length() > 0.05
		check(ok, "prop %s (%d surface(s), %s)" % [p, m.get_surface_count(), m.get_aabb().size])
		total += m.get_surface_count()
		_winding(m, false, "prop %s normals" % p)
	check(MeshKit.prop("tree") == MeshKit.prop("tree"), "props are cached")
	var xfs: Array = []
	var cols := PackedColorArray()
	for i in 200:
		xfs.append(MeshKit.at(Vector3(i % 20, 0, i / 20)))
		cols.append(Color(randf(), 1, 1))
	var mmi := MeshKit.scatter(MeshKit.prop("grass"), xfs, cols)
	add_child(mmi)
	check(mmi.multimesh.instance_count == 200 and mmi.multimesh.use_colors, "scatter: 200 tinted grass tufts in one MultiMesh")
	var forest := MeshKit.scatter_random(MeshKit.prop("pine"), 60, Vector3.ZERO, 40.0, 8.0, 0.7, 1.4, PackedColorArray([Color(1, 1, 1), Color(0.8, 1, 0.8)]), 3)
	add_child(forest)
	check(forest.multimesh.instance_count == 60, "scatter_random: a 60-tree forest in one draw call")
	mmi.queue_free()
	forest.queue_free()
	print("[world] props: %d meshes, %d surfaces in total" % [MeshKit.prop_names().size(), total])


# --- Creatures -------------------------------------------------------------------------------------

func _draw_calls(n: Node) -> int:
	var c := 0
	var gi := n as GeometryInstance3D
	if gi != null and gi.is_visible_in_tree():
		var mi := gi as MeshInstance3D
		if mi != null and mi.mesh != null:
			c += mi.mesh.get_surface_count()
		elif gi is MultiMeshInstance3D or gi is CPUParticles3D:
			c += 1
	for ch in n.get_children():
		c += _draw_calls(ch)
	return c


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


func _test_creatures() -> void:
	var holder := Node3D.new()
	add_child(holder)
	var report: PackedStringArray = []
	var i := 0
	for cls in Creatures.CLASSES:
		var h := Creatures.humanoid({"class": cls, "seed": i})
		holder.add_child(h)
		h.position = Vector3(i % 6, 0, i / 6) * 1.5
		var dc := _draw_calls(h)
		var nodes := _count_nodes(h)
		check(Creatures.anim(h) != null and h.get_node_or_null("Model/Head/Mesh") != null and dc <= 9 and nodes <= 20,
			"humanoid %s: %d draw calls, %d nodes" % [cls, dc, nodes])
		report.append("%s %d" % [cls, dc])
		i += 1
	print("[world] humanoid draw calls: " + ", ".join(report))
	# every hat, item and hair style at least once
	for hat in Creatures.HATS:
		var h2 := Creatures.humanoid({"class": "villager", "hat": hat})
		holder.add_child(h2)
		check(h2.get_node_or_null("Model/Head/Mesh") != null, "hat " + hat)
	for item in Creatures.ITEMS:
		var h3 := Creatures.humanoid({"class": "villager", "weapon": item, "offhand": item if item in ["shield", "book", "bow", "lantern"] else "none"})
		holder.add_child(h3)
		check(h3.get_node_or_null("Model/ArmR/Mesh") != null, "item " + item)
	for style in Creatures.HAIR_STYLES:
		for beard in Creatures.BEARDS:
			var h4 := Creatures.humanoid({"class": "villager", "hair_style": style, "beard": beard, "ears": "pointy" if beard == "long" else "round"})
			holder.add_child(h4)
	check(true, "every hair style x beard combination builds")
	for s in 12:
		var opts := Creatures.random_humanoid_opts(s)
		var h5 := Creatures.humanoid(opts)
		holder.add_child(h5)
		check(Creatures.CLASSES.has(str(opts["class"])), "random humanoid %d: %s" % [s, opts["class"]])
	# identical looks share their meshes
	var a1 := Creatures.humanoid({"class": "knight", "seed": 5})
	var a2 := Creatures.humanoid({"class": "knight", "seed": 5})
	holder.add_child(a1)
	holder.add_child(a2)
	check((a1.get_node("Model/Torso") as MeshInstance3D).mesh == (a2.get_node("Model/Torso") as MeshInstance3D).mesh, "identical looks share meshes (cached)")
	# LODs
	var far := Creatures.humanoid({"class": "mage", "lod": "far"})
	holder.add_child(far)
	check(_draw_calls(far) <= 2 and far.get_node_or_null("Model/Far") != null, "far LOD: one merged mesh (%d draw calls)" % _draw_calls(far))
	var auto := Creatures.humanoid({"class": "mage", "lod": "auto", "lod_distance": 10.0})
	holder.add_child(auto)
	var far_mi := auto.get_node("Model/Far") as MeshInstance3D
	var near_mi := auto.get_node("Model/Torso") as MeshInstance3D
	check(far_mi.visibility_range_begin == 10.0 and near_mi.visibility_range_end == 10.0, "auto LOD switches at lod_distance")
	var big := Creatures.humanoid({"class": "king", "scale": 2.0})
	holder.add_child(big)
	check(absf(Creatures.height_of(big) - 2.2) < 0.01, "scale 2 humanoid is 2.2 m tall")
	# monsters
	report.clear()
	for kind in Creatures.list_kinds():
		var m := Creatures.monster(kind, {"seed": 1})
		holder.add_child(m)
		var dc2 := _draw_calls(m)
		var info: Array = Creatures.MONSTER_INFO[kind]
		check(Creatures.anim(m) != null and dc2 <= int(info[1]) + 2, "monster %s (%s rig): %d draw calls" % [kind, info[0], dc2])
		report.append("%s %d" % [kind, dc2])
		var mf := Creatures.monster(kind, {"lod": "far", "color": Color(0.9, 0.5, 0.9)})
		holder.add_child(mf)
		check(_draw_calls(mf) <= 2, "monster %s far LOD: %d draw call(s)" % [kind, _draw_calls(mf)])
		var boss := Creatures.monster(kind, {"boss": true})
		holder.add_child(boss)
	print("[world] monster draw calls: " + ", ".join(report))
	# crowds
	var seats: Array = []
	for k in 120:
		seats.append(MeshKit.at(Vector3(k % 20, 0, k / 20) * 0.7))
	var crowd := Creatures.crowd(seats, 4, 9)
	holder.add_child(crowd)
	crowd.cheer = 1.0
	var pens := Creatures.crowd(seats.slice(0, 30), 3, 2, "penguin")
	holder.add_child(pens)
	await frames(3)
	check(crowd.size() == 120 and _draw_calls(crowd) <= 8, "crowd of 120 in %d draw calls" % _draw_calls(crowd))
	check(pens.size() == 30 and _draw_calls(pens) <= 6, "penguin crowd of 30 in %d draw calls" % _draw_calls(pens))
	await frames(10)
	holder.queue_free()
	await frames(2)


func _test_animations() -> void:
	var holder := Node3D.new()
	add_child(holder)
	var subjects: Array = [Creatures.humanoid({"class": "knight"}), Creatures.monster("wolf"), Creatures.monster("bat"),
		Creatures.monster("slime"), Creatures.monster("dragon"), Creatures.monster("mimic"), Creatures.monster("ghost"),
		Creatures.monster("fish"), Creatures.monster("spider"), Creatures.monster("robot"), Creatures.humanoid({"class": "mage", "lod": "far"})]
	var finished := {}
	for s in subjects:
		var n: Node3D = s
		holder.add_child(n)
		var an := Creatures.anim(n)
		an.action_finished.connect(func(a: String) -> void: finished[a] = int(finished.get(a, 0)) + 1)
	await frames(2)
	for s in subjects:
		Creatures.anim(s).walk(2.5)
	await wait(0.5)
	var knight: Node3D = subjects[0]
	var leg := knight.get_node("Model/LegL") as Node3D
	check(absf(leg.rotation.x) > 0.05, "walk cycle swings the legs (%.2f rad)" % leg.rotation.x)
	for s in subjects:
		Creatures.anim(s).walk(0.0)
	for action in ["attack", "hurt", "cast", "cheer", "jump", "wave", "talk", "nod"]:
		for s in subjects:
			Creatures.anim(s).play(action, -1.0, Vector3(1, 0, 0))
		await wait(1.6)
		check(int(finished.get(action, 0)) == subjects.size(), "%s finished on all %d creatures" % [action, subjects.size()])
	var an0 := Creatures.anim(knight)
	an0.hurt(Color(1, 1, 1), Vector3(0, 0, 1))
	await frames(2)
	var torso := knight.get_node("Model/Torso") as MeshInstance3D
	check(torso.material_overlay != null, "hurt flash puts an overlay on")
	await wait(0.6)
	check(torso.material_overlay == null, "and takes it off again")
	an0.play("victory")
	await wait(2.0)
	check(an0.is_busy(), "victory loops until stop()")
	an0.stop()
	an0.faint()
	await wait(1.0)
	var model := knight.get_node("Model") as Node3D
	check(model.rotation.x < -1.2 and an0.is_down(), "faint lies down (%.2f)" % model.rotation.x)
	an0.revive()
	await wait(1.0)
	check(absf(model.rotation.x) < 0.3, "revive gets back up")
	an0.face(Vector3(1, 0, 0))
	await wait(0.8)
	check(absf(angle_difference(knight.rotation.y, PI * 0.5)) < 0.05, "face() turns towards +X")
	Creatures.face_now(knight, Vector3(0, 0, -1))
	check(absf(angle_difference(knight.rotation.y, PI)) < 0.01, "face_now() snaps")
	an0.squash(0.4)
	an0.blink()
	var bat := Creatures.anim(subjects[2])
	bat.flying = false
	await wait(0.2)
	bat.flying = true
	await frames(5)
	holder.queue_free()
	await frames(2)


# --- SkyKit ----------------------------------------------------------------------------------------

func _test_skies() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.position = Vector3(5, 2, 3)
	var expect := {"night": "Stars", "spooky": "Fireflies", "stormy": "Rain", "snowy": "Snow", "underwater": "Bubbles",
		"dungeon": "Dust", "indoor": "Dust", "space": "Planet", "day": "Clouds"}
	for vr in [false, true]:
		var report: PackedStringArray = []
		for p in SkyKit.preset_names():
			var holder := Node3D.new()
			add_child(holder)
			var sky := SkyKit.apply(holder, p, vr)
			await frames(2)
			var ok := sky.env != null and sky.sun != null and sky.preset == p
			if vr:
				ok = ok and not sky.env.fog_enabled and not sky.env.ssao_enabled and not sky.env.glow_enabled and not sky.sun.shadow_enabled
			if expect.has(p):
				var extra := sky.find_child(str(expect[p]), true, false) as Node3D
				ok = ok and extra != null and extra.visible
			var dome := sky.get_node("Dome") as Node3D
			ok = ok and dome.global_position.distance_to(cam.global_position) < 0.01
			check(ok, "sky %s (%s): %d extra draw call(s)" % [p, "VR" if vr else "TV", sky.draw_calls()])
			report.append("%s %d" % [p, sky.draw_calls()])
			holder.queue_free()
			await frames(1)
		print("[world] sky extras draw calls (%s): %s" % ["VR" if vr else "TV", ", ".join(report)])
	check(SkyKit.resolve("cave") == "dungeon" and SkyKit.resolve("cosy") == "indoor" and SkyKit.resolve("nope") == "day", "aliases resolve")
	# blending and the day/night cycle
	var h2 := Node3D.new()
	add_child(h2)
	var sky2 := SkyKit.apply(h2, "day", false)
	var day_top := sky2.sky_mat.sky_top_color
	sky2.set_preset("night", 0.6)
	await wait(0.3)
	var mid_top := sky2.sky_mat.sky_top_color
	await wait(0.5)
	var stars := sky2.find_child("Stars", true, false) as Node3D
	check(mid_top != day_top and mid_top != sky2.sky_mat.sky_top_color and stars != null and stars.visible, "day -> night blend passes through the middle and shows the stars")
	for hour in [0.0, 6.0, 7.5, 12.0, 17.5, 19.0, 21.0]:
		sky2.set_time_of_day(hour)
		await frames(1)
	sky2.set_time_of_day(12.0)
	var noon_e := sky2.sun.light_energy
	check(sky2.preset == "day" and noon_e > 1.0, "noon is day (sun %.2f)" % noon_e)
	sky2.set_time_of_day(23.0)
	check(sky2.preset == "night" and (sky2.find_child("Stars", true, false) as Node3D).visible, "23:00 is night with stars")
	var struck := [0]
	sky2.lightning.connect(func(s: float) -> void: struck[0] += 1)
	sky2.set_preset("stormy")
	sky2.flash(1.0)
	await wait(0.4)
	check(int(struck[0]) >= 1, "lightning signal fires")
	sky2.set_rain(false)
	sky2.set_snow(true)
	sky2.set_clouds(5)
	var torch := SkyKit.flicker_light()
	h2.add_child(torch)
	await wait(0.2)
	check(torch.light_energy != 1.6, "flicker_light flickers (%.2f)" % torch.light_energy)
	h2.queue_free()
	cam.queue_free()
	await frames(2)
