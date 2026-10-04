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
## The village grows: after each wave a new building rises on one of these spots (they're reserved as
## obstacles from the start, so the goblins' paths never change). [kind, x, z, radius, yaw]
const GROWTH := [
	["well", -2.8, 1.6, 0.75, 0.0], ["market", 2.6, -1.0, 0.95, 0.4], ["bakery", -1.6, -3.0, 1.05, -0.3],
	["windmill", -10.0, -1.5, 1.0, 0.0], ["statue", -2.0, 7.2, 0.8, 3.0], ["barn", 10.5, -2.0, 1.25, 1.4],
	["tower", -6.5, 8.5, 0.9, 0.0], ["chapel", -7.4, 3.0, 1.0, 1.2],
]
const GROWTH_NAMES := {"well": "a WELL", "market": "a MARKET STALL", "bakery": "a BAKERY", "windmill": "a WINDMILL",
	"statue": "a STATUE OF THE GIANT", "barn": "a BARN", "tower": "a WATCHTOWER", "chapel": "a CHAPEL"}
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
	if Engine.has_meta("gt_obstacles2"):
		return Engine.get_meta("gt_obstacles2")
	var list: Array = []
	for c in COTTAGES:
		list.append([c[0], c[1], COTTAGE_R])
	for t in trees():
		list.append([t[0], t[1], TREE_R])
	for gsite in GROWTH:
		list.append([gsite[1], gsite[2], gsite[3]])
	list.append([0.0, 0.0, FIRE_R])
	Engine.set_meta("gt_obstacles2", list)
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
	var key := "gt_field2_%d_%d" % [int(big), int(to_edge)]
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


## skip_scenery: the trees and cottages are built by scenery.gd instead (simple mode: they react to touch).
static func build(main: Node3D, vr: bool, skip_scenery: bool = false) -> void:
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
	_build_props(main, skip_scenery)
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


static func _build_props(main: Node3D, skip_scenery: bool = false) -> void:
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

	for t in ([] if skip_scenery else trees()):
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

	for c in ([] if skip_scenery else COTTAGES):
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


## Builds the first `count` growth buildings as a few merged meshes under `parent` (the windmill's
## sails are returned separately in out["sails"] so they can turn).
static func build_growth(parent: Node3D, from: int, count: int, out: Dictionary) -> void:
	var b := {"walls": Batch.new(), "roof": Batch.new(), "wood": Batch.new(), "stone": Batch.new(),
		"glow": Batch.new(), "red": Batch.new(), "white": Batch.new(), "green": Batch.new(), "gold": Batch.new()}
	for i in range(from, mini(count, GROWTH.size())):
		var g: Array = GROWTH[i]
		var x: float = g[1]
		var z: float = g[2]
		var base := Transform3D(Basis(Vector3.UP, g[4]), Vector3(x, height(x, z), z))
		_growth_building(g[0], base, b, parent, out)
	var mats := {"walls": mat(Color(0.98, 0.9, 0.74)), "roof": mat(Color(0.8, 0.33, 0.2)), "wood": mat(Color(0.55, 0.36, 0.2)),
		"stone": mat(Color(0.66, 0.64, 0.6)), "glow": mat(Color(1.0, 0.8, 0.4), 2.2), "red": mat(Color(0.88, 0.22, 0.2)),
		"white": mat(Color(0.97, 0.96, 0.92)), "green": mat(Color(0.35, 0.7, 0.3)), "gold": mat(Color(1.0, 0.8, 0.3), 0.8)}
	for k in b:
		var batch: Batch = b[k]
		if batch.count > 0:
			var mi := batch.build(parent, mats[k])
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


static func _growth_building(kind: String, base: Transform3D, b: Dictionary, parent: Node3D, out: Dictionary) -> void:
	var at := func(p: Vector3) -> Transform3D: return base * Transform3D(Basis(), p)
	match kind:
		"well":
			b.stone.add(cyl(0.6, 0.65, 0.55, 12), at.call(Vector3(0, 0.27, 0)))
			b.glow.add(cyl(0.45, 0.45, 0.02, 12), at.call(Vector3(0, 0.5, 0)))
			for sx in [-0.5, 0.5]:
				b.wood.add(box(Vector3(0.1, 1.1, 0.1)), at.call(Vector3(sx, 0.8, 0)))
			var roof := PrismMesh.new()
			roof.size = Vector3(1.4, 0.45, 0.9)
			b.roof.add(roof, at.call(Vector3(0, 1.55, 0)))
			b.wood.add(box(Vector3(0.18, 0.2, 0.18)), at.call(Vector3(0, 1.0, 0)))  # bucket
		"market":
			for sx in [-0.8, 0.8]:
				for sz in [-0.5, 0.5]:
					b.wood.add(box(Vector3(0.08, 1.3, 0.08)), at.call(Vector3(sx, 0.65, sz)))
			b.wood.add(box(Vector3(1.7, 0.5, 0.5)), at.call(Vector3(0, 0.25, 0.3)))
			for i in 5:
				var stripe: Batch = b.red if i % 2 == 0 else b.white
				var sx2 := -0.72 + i * 0.36
				stripe.add(box(Vector3(0.36, 0.06, 1.25)), base * Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(sx2, 1.35, 0)))
			for i in 6:
				var fruit: Batch = b.red if i % 3 == 0 else (b.green if i % 3 == 1 else b.gold)
				fruit.add(sphere(0.11, 6), at.call(Vector3(-0.6 + i * 0.24, 0.6, 0.3)))
		"bakery":
			b.walls.add(box(Vector3(1.6, 1.1, 1.3)), at.call(Vector3(0, 0.55, 0)))
			var roof2 := PrismMesh.new()
			roof2.size = Vector3(1.9, 0.75, 1.55)
			b.roof.add(roof2, at.call(Vector3(0, 1.47, 0)))
			b.stone.add(cyl(0.16, 0.2, 0.8, 8), at.call(Vector3(-0.45, 1.75, -0.2)))
			b.glow.add(box(Vector3(0.5, 0.35, 0.06)), at.call(Vector3(0, 0.55, 0.66)))
			b.gold.add(sphere(0.22, 8), base * Transform3D(Basis().scaled(Vector3(1.3, 0.6, 0.6)), Vector3(0, 1.25, 0.72)))  # bread sign
		"windmill":
			b.stone.add(cyl(0.5, 0.8, 2.6, 10), at.call(Vector3(0, 1.3, 0)))
			b.roof.add(cyl(0.0, 0.65, 0.8, 10), at.call(Vector3(0, 3.0, 0)))
			b.glow.add(box(Vector3(0.3, 0.4, 0.06)), at.call(Vector3(0, 0.9, 0.72)))
			b.wood.add(box(Vector3(0.36, 0.6, 0.06)), at.call(Vector3(0, 0.3, 0.8)))
			var sails := Node3D.new()
			sails.transform = base * Transform3D(Basis(), Vector3(0, 2.4, 0.75))
			parent.add_child(sails)
			var sb := Batch.new()
			for k in 4:
				sb.add(box(Vector3(0.32, 1.45, 0.04)), Transform3D(Basis(Vector3.BACK, k * PI / 2.0), Vector3.ZERO) * Transform3D(Basis(), Vector3(0, 0.78, 0)))
			sb.add(cyl(0.1, 0.1, 0.2, 8), Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO))
			sb.build(sails, mat(Color(0.95, 0.92, 0.85)))
			out["sails"] = sails
		"statue":
			b.stone.add(box(Vector3(1.0, 0.6, 1.0)), at.call(Vector3(0, 0.3, 0)))
			b.stone.add(cyl(0.3, 0.42, 0.8, 10), at.call(Vector3(0, 1.0, 0)))
			b.stone.add(sphere(0.32, 10), at.call(Vector3(0, 1.6, 0)))
			b.stone.add(cyl(0.12, 0.32, 0.4, 10), at.call(Vector3(0, 2.0, 0)))  # the giant's pointy hat
			b.gold.add(box(Vector3(0.6, 0.12, 0.05)), at.call(Vector3(0, 0.42, 0.51)))  # plaque
			for i in 6:
				var a := TAU * i / 6.0
				var fl: Batch = b.red if i % 2 == 0 else b.gold
				fl.add(sphere(0.09, 6), at.call(Vector3(cos(a) * 0.75, 0.08, sin(a) * 0.75)))
		"barn":
			b.red.add(box(Vector3(2.2, 1.4, 1.6)), at.call(Vector3(0, 0.7, 0)))
			var roof3 := PrismMesh.new()
			roof3.size = Vector3(2.5, 0.9, 1.85)
			b.roof.add(roof3, at.call(Vector3(0, 1.85, 0)))
			b.white.add(box(Vector3(0.8, 0.9, 0.06)), at.call(Vector3(0, 0.45, 0.82)))
			b.red.add(box(Vector3(0.7, 0.08, 0.08)), base * Transform3D(Basis(Vector3.BACK, 0.85), Vector3(0, 0.45, 0.86)))
			b.red.add(box(Vector3(0.7, 0.08, 0.08)), base * Transform3D(Basis(Vector3.BACK, -0.85), Vector3(0, 0.45, 0.86)))
			b.gold.add(box(Vector3(0.5, 0.18, 0.5)), at.call(Vector3(1.4, 0.09, 0.5)))  # hay bale
		"tower":
			b.stone.add(cyl(0.6, 0.7, 2.8, 10), at.call(Vector3(0, 1.4, 0)))
			for k in 6:
				var a := TAU * k / 6.0
				b.stone.add(box(Vector3(0.25, 0.3, 0.25)), at.call(Vector3(cos(a) * 0.55, 2.95, sin(a) * 0.55)))
			b.glow.add(box(Vector3(0.22, 0.35, 0.06)), at.call(Vector3(0, 1.9, 0.66)))
			b.wood.add(box(Vector3(0.05, 1.0, 0.05)), at.call(Vector3(0, 3.4, 0)))
			b.red.add(box(Vector3(0.04, 0.32, 0.5)), at.call(Vector3(0, 3.7, 0.25)))
		_:
			b.walls.add(box(Vector3(1.3, 1.3, 1.8)), at.call(Vector3(0, 0.65, 0)))
			var roof4 := PrismMesh.new()
			roof4.size = Vector3(1.6, 0.8, 2.0)
			b.roof.add(roof4, at.call(Vector3(0, 1.7, 0)))
			b.walls.add(box(Vector3(0.6, 0.9, 0.6)), at.call(Vector3(0, 2.0, -0.6)))
			b.roof.add(cyl(0.0, 0.42, 1.0, 4), at.call(Vector3(0, 2.95, -0.6)))
			b.gold.add(sphere(0.12, 8), at.call(Vector3(0, 2.2, -0.29)))  # the bell
			b.glow.add(box(Vector3(0.3, 0.5, 0.06)), at.call(Vector3(0, 0.75, 0.91)))


## Where each cottage's chimney puffs smoke from (world space).
static func chimney_tops() -> PackedVector3Array:
	var pts := PackedVector3Array()
	for c in COTTAGES:
		var x: float = c[0]
		var z: float = c[1]
		var base := Transform3D(Basis(Vector3.UP, c[2]), Vector3(x, height(x, z), z))
		pts.append(base * Vector3(0.5, 2.1, 0.2))
	return pts


## The door of cottage i (where villagers come out).
static func cottage_door(i: int) -> Vector3:
	var c: Array = COTTAGES[i % COTTAGES.size()]
	var x: float = c[0]
	var z: float = c[1]
	var base := Transform3D(Basis(Vector3.UP, c[2]), Vector3(x, height(x, z), z))
	return base * Vector3(0, 0, 0.95)


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
