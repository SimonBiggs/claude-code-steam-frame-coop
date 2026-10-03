extends RefCounted
## The tabletop village: terrain height field, river, cottages, trees, campfire and the cosy room.
## Everything is deterministic (fixed layout + seeded RNG) so the host and the TV build the same world.
## World units: a knight is about 1 unit tall. The VR giant sees it at world_scale S (20 units = 1 m).

const S := 20.0              # XR world scale: 20 units = 1 real metre
const R := 14.0              # radius of the meadow
const RIM := 0.7             # wooden table rim around the meadow
const EDGE := R + RIM        # past this you fall off the table
const FLOOR_Y := -14.4       # the room floor (table top is 72 cm high)
const RIVER_HALF := 0.9      # river bed half-width
const BANK := 0.7            # bank slope width
const BED_Y := -0.6
const WATER_Y := -0.22
const HILLS := [
	[9.0, 6.0, 3.2, 1.1], [-9.5, 6.5, 3.0, 0.9], [-10.0, -1.5, 2.8, 1.2],
	[8.5, -9.5, 2.8, 1.0], [-6.0, -10.5, 2.6, 0.8], [3.5, 10.5, 2.4, 0.7],
]
const COTTAGES := [
	[4.6, 1.6, 0.3], [1.8, 5.0, 1.4], [-3.2, 4.3, 2.4], [-5.2, 0.4, 3.0], [5.0, -2.2, -0.4], [-4.4, -2.4, 3.8],
]
const COTTAGE_R := 1.25
const TREE_R := 0.45
const FIRE_R := 1.1  # stones around the campfire block walkers


static func river_z(x: float) -> float:
	return -5.5 + sin(x * 0.3) * 1.2


## Distance from the river's centre line (approximate, good enough for gameplay).
static func river_dist(x: float, z: float) -> float:
	return absf(z - river_z(x)) / sqrt(1.0 + pow(0.36 * cos(x * 0.3), 2.0))


## The bridge runs across the river at x = 0, turned to meet it square.
static func on_bridge(x: float, z: float) -> bool:
	var phi := -atan(0.36)
	var dz := z - river_z(0.0)
	var along := x * sin(phi) + dz * cos(phi)
	var across := x * cos(phi) - dz * sin(phi)
	return absf(across) < 0.95 and absf(along) < 2.15


static func in_water(x: float, z: float) -> bool:
	return river_dist(x, z) < RIVER_HALF + BANK * 0.55 and not on_bridge(x, z) and Vector2(x, z).length() < R


## Ground height at (x, z). Off the table it returns a big negative number.
static func height(x: float, z: float, with_bridge: bool = true) -> float:
	var r := Vector2(x, z).length()
	if r > EDGE:
		return -100.0
	if r > R:
		return 0.0  # wooden rim
	var h := 0.0
	for hill in HILLS:
		var d2 := pow(x - hill[0], 2.0) + pow(z - hill[1], 2.0)
		h += hill[3] * exp(-d2 / (hill[2] * hill[2]))
	h *= smoothstep(R, R - 1.2, r)  # flatten towards the rim
	var rd := river_dist(x, z)
	if rd < RIVER_HALF + BANK:
		var t := smoothstep(RIVER_HALF, RIVER_HALF + BANK, rd)
		h = lerpf(BED_Y, h, t)
		if with_bridge and on_bridge(x, z):
			h = maxf(h, 0.32)
	return h


## Static circular obstacles [x, z, radius] (cottages, trees, fire). Cached on the Engine.
static func obstacles() -> Array:
	if Engine.has_meta("gt_obstacles"):
		return Engine.get_meta("gt_obstacles")
	var list: Array = []
	for c in COTTAGES:
		list.append([c[0], c[1], COTTAGE_R])
	for t in trees():
		list.append([t[0], t[1], TREE_R])
	list.append([0.0, 0.0, FIRE_R])
	Engine.set_meta("gt_obstacles", list)
	return list


## Tree layout [x, z, kind(0 pine, 1 round), scale].
static func trees() -> Array:
	if Engine.has_meta("gt_trees"):
		return Engine.get_meta("gt_trees")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var list: Array = []
	var tries := 0
	while list.size() < 30 and tries < 2000:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(6.8, R - 0.9)
		var x := cos(a) * r
		var z := sin(a) * r
		if river_dist(x, z) < 2.3 or absf(x) < 2.0 and z < 0.0 and z > -9.0:
			continue
		var ok := true
		for c in COTTAGES:
			if Vector2(x - c[0], z - c[1]).length() < 2.6:
				ok = false
		for t in list:
			if Vector2(x - t[0], z - t[1]).length() < 2.0:
				ok = false
		if ok:
			list.append([x, z, rng.randi() % 2, rng.randf_range(0.85, 1.25)])
	Engine.set_meta("gt_trees", list)
	return list


## Flow fields for walking goblins: BFS step counts over a grid, towards the campfire or the
## table edge, with obstacles grown by the walker's size. Built once and cached on the Engine.
const GRID := 64


static func _cell() -> float:
	return 2.0 * EDGE / GRID


static func field(big: bool, to_edge: bool) -> PackedInt32Array:
	var key := "gt_field_%d_%d" % [int(big), int(to_edge)]
	if Engine.has_meta(key):
		return Engine.get_meta(key)
	var cs := _cell()
	var rad := 0.85 if big else 0.35
	var n := GRID * GRID
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var blocked := PackedByteArray()
	blocked.resize(n)
	var queue := PackedInt32Array()
	var obs := obstacles()
	for j in GRID:
		for i in GRID:
			var x := -EDGE + (i + 0.5) * cs
			var z := -EDGE + (j + 0.5) * cs
			var idx := j * GRID + i
			var r := Vector2(x, z).length()
			var goal := false
			if to_edge:
				goal = r > EDGE - 1.0 and r <= EDGE - 0.25
			else:
				goal = r < FIRE_R + rad + 0.5
			var b := r > EDGE - 0.25
			if not b and not goal:
				for o in obs:
					if big and o[2] <= TREE_R:
						continue  # ogres trample trees
					var dx: float = x - o[0]
					var dz: float = z - o[1]
					var rr: float = o[2] + rad
					if dx * dx + dz * dz < rr * rr:
						b = true
						break
			if goal and not b:
				dist[idx] = 0
				queue.append(idx)
			elif b:
				blocked[idx] = 1
	var head := 0
	while head < queue.size():
		var idx := queue[head]
		head += 1
		var ci := idx % GRID
		var cj := idx / GRID
		for dj in range(-1, 2):
			for di in range(-1, 2):
				var ni := ci + di
				var nj := cj + dj
				if ni < 0 or nj < 0 or ni >= GRID or nj >= GRID:
					continue
				var nidx := nj * GRID + ni
				if dist[nidx] >= 0 or blocked[nidx] == 1:
					continue
				dist[nidx] = dist[idx] + 1
				queue.append(nidx)
	Engine.set_meta(key, dist)
	return dist


## Which way to walk from pos along a flow field (ZERO when already there or lost).
static func flow_dir(pos: Vector3, big: bool, to_edge: bool) -> Vector3:
	var f := field(big, to_edge)
	var cs := _cell()
	var i := int((pos.x + EDGE) / cs)
	var j := int((pos.z + EDGE) / cs)
	if i < 0 or j < 0 or i >= GRID or j >= GRID:
		return Vector3.ZERO
	var here := f[j * GRID + i]
	if here == 0:
		return Vector3.ZERO
	var best := here if here > 0 else 1 << 30
	var bi := -1
	var bj := -1
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var ni := i + di
			var nj := j + dj
			if ni < 0 or nj < 0 or ni >= GRID or nj >= GRID:
				continue
			var v := f[nj * GRID + ni]
			if v >= 0 and v < best:
				best = v
				bi = ni
				bj = nj
	if bi < 0:
		return Vector3.ZERO
	var target := Vector3(-EDGE + (bi + 0.5) * cs, 0.0, -EDGE + (bj + 0.5) * cs)
	var d := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	return d.normalized() if d.length() > 0.01 else Vector3.ZERO


## Pushes a circle at pos out of the static obstacles. Returns the corrected position.
static func push_out(pos: Vector3, radius: float) -> Vector3:
	for o in obstacles():
		var dx: float = pos.x - o[0]
		var dz: float = pos.z - o[1]
		var min_d: float = o[2] + radius
		var d2 := dx * dx + dz * dz
		if d2 < min_d * min_d:
			var d := sqrt(d2)
			if d < 0.001:
				dx = 1.0
				dz = 0.0
				d = 1.0
			pos.x = o[0] + dx / d * min_d
			pos.z = o[1] + dz / d * min_d
	return pos


static func mat(color: Color, glow: float = 0.0, rough: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


static func sphere(radius: float, segs: int = 12) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segs
	m.rings = maxi(4, segs / 2)
	return m


static func cyl(top: float, bottom: float, h: float, segs: int = 10) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return m


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## A batch of meshes merged into one draw call (one material).
class Batch:
	var st := SurfaceTool.new()
	var count := 0
	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	func add(mesh: Mesh, xf: Transform3D) -> void:
		st.append_from(mesh, 0, xf)
		count += 1
	func build(parent: Node3D, material: Material) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		if count > 0:
			mi.mesh = st.commit()
		mi.material_override = material
		parent.add_child(mi)
		return mi


static func build(main: Node3D, vr: bool) -> void:
	# --- Environment: a warm, dim room lit by a lamp and the village campfire.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.1, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.62, 0.5)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	e.glow_intensity = 0.5 if vr else 0.8
	e.glow_bloom = 0.04
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.12
	env.environment = e
	main.add_child(env)

	var lamp := DirectionalLight3D.new()
	lamp.rotation_degrees = Vector3(-58, 35, 0)
	lamp.light_color = Color(1.0, 0.88, 0.7)
	lamp.light_energy = 1.1
	lamp.shadow_enabled = not vr
	lamp.directional_shadow_max_distance = 50.0
	main.add_child(lamp)

	_build_terrain(main)
	_build_props(main)
	_build_room(main)


static func _ground_color(x: float, z: float, r: float) -> Color:
	if r > R:
		return Color(0.55, 0.34, 0.18)  # wood
	var rd := river_dist(x, z)
	if rd < RIVER_HALF + 0.2:
		return Color(0.35, 0.42, 0.45)
	if rd < RIVER_HALF + BANK + 0.25:
		return Color(0.86, 0.76, 0.5)  # sandy bank
	var n := sin(x * 1.7) * sin(z * 1.3) * 0.5 + sin(x * 0.53 + z * 0.71) * 0.5
	var grass := Color(0.42, 0.7, 0.3).lerp(Color(0.55, 0.78, 0.32), n * 0.5 + 0.5)
	if r < 2.6:
		return Color(0.72, 0.58, 0.38).lerp(grass, smoothstep(1.8, 2.6, r))  # trodden earth around the fire
	# a dirt path from each cottage to the fire would be nice; keep a soft ring path instead
	var ring := absf(r - 7.2)
	if ring < 0.5:
		grass = grass.lerp(Color(0.78, 0.66, 0.44), (0.5 - ring) * 1.2)
	var h := height(x, z, false)
	return grass.lightened(clampf(h * 0.12, 0.0, 0.2))


static func _build_terrain(main: Node3D) -> void:
	var rings := 40
	var segs := 128
	var radii: Array[float] = []
	for i in rings + 1:
		radii.append(R * float(i) / rings)
	radii.append(R + 0.01)
	radii.append(EDGE)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	for ri in radii.size():
		var row: Array = []
		var r: float = radii[ri]
		for s in segs:
			var a := TAU * float(s) / segs
			var x := cos(a) * r
			var z := sin(a) * r
			var y := height(x, z, false) if r <= R else 0.0
			var n := Vector3.UP
			if r <= R - 0.05:
				var ep := 0.15
				n = Vector3(height(x - ep, z, false) - height(x + ep, z, false), 2.0 * ep,
					height(x, z - ep, false) - height(x, z + ep, false)).normalized()
			row.append([Vector3(x, y, z), _ground_color(x, z, r if ri < radii.size() - 2 else R + 0.3), n])
		grid.append(row)
	# Skirt: the table's outer edge going down.
	var skirt: Array = []
	for s in segs:
		var a := TAU * float(s) / segs
		skirt.append([Vector3(cos(a) * EDGE, -1.1, sin(a) * EDGE), Color(0.45, 0.27, 0.14), Vector3(cos(a), 0.0, sin(a))])
	grid.append(skirt)
	for ri in grid.size() - 1:
		var inner: Array = grid[ri]
		var outer: Array = grid[ri + 1]
		for s in segs:
			var s2 := (s + 1) % segs
			var quad := [inner[s], outer[s], outer[s2], inner[s2]]
			for idx in [0, 1, 2, 0, 2, 3]:
				var v: Array = quad[idx]
				st.set_color(v[1])
				st.set_normal(v[2])
				st.add_vertex(v[0])
	var terrain := MeshInstance3D.new()
	terrain.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	terrain.material_override = m
	main.add_child(terrain)

	# Water: one disc just below the banks; the terrain hides it everywhere except the river.
	var water := MeshInstance3D.new()
	water.mesh = cyl(R - 0.05, R - 0.05, 0.02, 64)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.35, 0.7, 0.95, 0.75)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.1
	wm.metallic = 0.2
	wm.emission_enabled = true
	wm.emission = Color(0.2, 0.45, 0.7)
	wm.emission_energy_multiplier = 0.4
	water.material_override = wm
	water.position.y = WATER_Y
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(water)

	# Thick tabletop under the meadow.
	var slab := MeshInstance3D.new()
	slab.mesh = cyl(EDGE, EDGE, 0.6, 64)
	slab.material_override = mat(Color(0.42, 0.25, 0.13))
	slab.position.y = -1.4
	main.add_child(slab)


static func _build_props(main: Node3D) -> void:
	var trunk := Batch.new()
	var pine := Batch.new()
	var leaf := Batch.new()
	var walls := Batch.new()
	var roofs := Batch.new()
	var doors := Batch.new()
	var windows := Batch.new()
	var stone := Batch.new()
	var flowers_a := Batch.new()
	var flowers_b := Batch.new()
	var wood := Batch.new()

	for t in trees():
		var x: float = t[0]
		var z: float = t[1]
		var sc: float = t[3]
		var y := height(x, z)
		var base := Transform3D(Basis().scaled(Vector3.ONE * sc), Vector3(x, y, z))
		trunk.add(cyl(0.12, 0.18, 0.9, 6), base * Transform3D(Basis(), Vector3(0, 0.45, 0)))
		if t[2] == 0:
			pine.add(cyl(0.0, 0.75, 1.3, 8), base * Transform3D(Basis(), Vector3(0, 1.3, 0)))
			pine.add(cyl(0.0, 0.55, 1.0, 8), base * Transform3D(Basis(), Vector3(0, 1.95, 0)))
		else:
			leaf.add(sphere(0.75, 10), base * Transform3D(Basis(), Vector3(0, 1.5, 0)))
			leaf.add(sphere(0.5, 8), base * Transform3D(Basis(), Vector3(0.3, 2.05, 0.1)))

	for c in COTTAGES:
		var x: float = c[0]
		var z: float = c[1]
		var y := height(x, z)
		var base := Transform3D(Basis(Vector3.UP, c[2]), Vector3(x, y, z))
		walls.add(box(Vector3(1.7, 1.15, 1.35)), base * Transform3D(Basis(), Vector3(0, 0.575, 0)))
		var roof := PrismMesh.new()
		roof.size = Vector3(2.0, 0.85, 1.6)
		roofs.add(roof, base * Transform3D(Basis(), Vector3(0, 1.57, 0)))
		walls.add(box(Vector3(0.22, 0.6, 0.22)), base * Transform3D(Basis(), Vector3(0.5, 1.75, 0.2)))  # chimney
		doors.add(box(Vector3(0.38, 0.62, 0.06)), base * Transform3D(Basis(), Vector3(0, 0.31, 0.68)))
		for wx in [-0.55, 0.55]:
			windows.add(box(Vector3(0.3, 0.28, 0.06)), base * Transform3D(Basis(), Vector3(wx, 0.68, 0.68)))
		for wz in [-0.3, 0.3]:
			windows.add(box(Vector3(0.06, 0.28, 0.3)), base * Transform3D(Basis(), Vector3(0.86, 0.68, wz)))

	# Campfire stone ring.
	for i in 9:
		var a := TAU * i / 9.0
		stone.add(sphere(0.3, 8), Transform3D(Basis().scaled(Vector3(1.0, 0.7, 1.0)), Vector3(cos(a) * 0.95, 0.12, sin(a) * 0.95)))
	# Stepping stones decoration along the ring path.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 70:
		var a := rng.randf() * TAU
		var r := rng.randf_range(2.5, R - 0.6)
		var x := cos(a) * r
		var z := sin(a) * r
		if river_dist(x, z) < 1.8:
			continue
		var y := height(x, z)
		var b: Batch = flowers_a if i % 2 == 0 else flowers_b
		b.add(sphere(0.09, 6), Transform3D(Basis(), Vector3(x, y + 0.1, z)))
		b.add(sphere(0.08, 6), Transform3D(Basis(), Vector3(x + 0.18, y + 0.08, z + 0.1)))
	# Wooden bridge over the river.
	var bz := river_z(0.0)
	var tilt := atan(0.36)
	var bb := Transform3D(Basis(Vector3.UP, -tilt), Vector3(0, 0, bz))
	wood.add(box(Vector3(1.9, 0.14, 4.3)), bb * Transform3D(Basis(), Vector3(0, 0.25, 0)))
	for side in [-0.95, 0.95]:
		wood.add(box(Vector3(0.1, 0.1, 4.3)), bb * Transform3D(Basis(), Vector3(side, 0.75, 0)))
		for zz in [-1.9, 0.0, 1.9]:
			wood.add(box(Vector3(0.1, 0.55, 0.1)), bb * Transform3D(Basis(), Vector3(side, 0.5, zz)))

	trunk.build(main, mat(Color(0.45, 0.28, 0.15)))
	pine.build(main, mat(Color(0.18, 0.5, 0.3)))
	leaf.build(main, mat(Color(0.35, 0.68, 0.25)))
	walls.build(main, mat(Color(0.98, 0.9, 0.74)))
	roofs.build(main, mat(Color(0.85, 0.35, 0.22)))
	doors.build(main, mat(Color(0.4, 0.24, 0.13)))
	windows.build(main, mat(Color(1.0, 0.8, 0.4), 2.2))
	stone.build(main, mat(Color(0.55, 0.53, 0.5)))
	flowers_a.build(main, mat(Color(1.0, 0.55, 0.75), 0.3))
	flowers_b.build(main, mat(Color(1.0, 0.92, 0.35), 0.3))
	wood.build(main, mat(Color(0.6, 0.4, 0.22)))


static func _build_room(main: Node3D) -> void:
	var legs := Batch.new()
	for a in [0.785, 2.356, 3.927, 5.498]:
		var p := Vector3(cos(a) * (EDGE - 2.5), (FLOOR_Y - 1.7) * 0.5, sin(a) * (EDGE - 2.5))
		legs.add(cyl(0.9, 0.7, -FLOOR_Y - 1.7, 10), Transform3D(Basis(), p))
	legs.build(main, mat(Color(0.38, 0.22, 0.12)))
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = cyl(160.0, 160.0, 0.2, 24)
	floor_mi.material_override = mat(Color(0.36, 0.22, 0.13))
	floor_mi.position.y = FLOOR_Y - 0.1
	main.add_child(floor_mi)
	var rug := MeshInstance3D.new()
	rug.mesh = cyl(30.0, 30.0, 0.1, 40)
	rug.material_override = mat(Color(0.62, 0.2, 0.18))
	rug.position.y = FLOOR_Y + 0.02
	main.add_child(rug)
	var rug2 := MeshInstance3D.new()
	rug2.mesh = cyl(26.0, 26.0, 0.1, 40)
	rug2.material_override = mat(Color(0.85, 0.65, 0.3))
	rug2.position.y = FLOOR_Y + 0.04
	main.add_child(rug2)
