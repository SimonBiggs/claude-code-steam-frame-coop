extends Node3D
## Draws the town model (town.gd) on every machine, cheaply enough for the Steam Frame:
## - the garden table, the sea and the island terrain (one mesh each, rebuilt per island)
## - roads, rails, level crossings, street lamps and trees: one MultiMesh per tile shape
## - finished buildings: one MultiMesh per look (kind + colour variant + level), so a whole town of
##   houses costs a handful of draw calls; building sites are see-through blueprints with scaffolding
## - little animations: windmill sails, the big wheel, chimney smoke puffs, a toy train between joined
##   stations, buildings popping up when finished, fires, need icons bobbing over buildings
## - tiny citizens (core/creatures.gd looks in MultiMeshes) strolling along the pavements
## - job markers: a glowing ring + beacon for each TV player, only on that player's own view

const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const Art := preload("res://games/tiny_town_tycoon/art.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Town := preload("res://games/tiny_town_tycoon/town.gd")

const ROAD_SHAPES: Array[String] = ["dot", "end", "straight", "curve", "tee", "cross"]
const ICONS: Array[String] = ["fire", "road", "power", "water", "jobs", "workers", "stock", "shop", "fun", "build"]
## Render layers: markers for TV slot s are on layer MARKER_LAYER0 + s (only that view's camera sees them).
const MARKER_BIT0 := 10
const BASE_MASK := (1 << 10) - 1
const AVATAR_BIT := 1 << 19
const WALKER_SCALE := 0.011

var main: Node
var town: Town
var isl := {}
var vr := false
var snowy := false
## A building the mayor is holding (hidden from the town while held).
var hidden_id := 0
## Every building the view should treat as rising (id -> seconds left of the pop-up animation).
var rising := {}

var _static: Node3D
var _terrain: MeshInstance3D
var _sea: MeshInstance3D
var _trees: MultiMeshInstance3D
var _roads := {}  # shape -> MultiMeshInstance3D
var _rails := {}
var _cross: MultiMeshInstance3D
var _lamps: MultiMeshInstance3D
var _groups := {}  # look key -> MultiMeshInstance3D
var _sites := {}  # building id -> Node3D (blueprint + scaffold + material pile)
var _sails: MultiMeshInstance3D
var _sail_xf: Array[Transform3D] = []
var _wheels: MultiMeshInstance3D
var _wheel_xf: Array[Transform3D] = []
var _smoke: MultiMeshInstance3D
var _smoke_src: Array[Vector3] = []
var _icons := {}  # icon -> MultiMeshInstance3D
var _icon_pos := {}  # icon -> Array[Vector3]
var _fires := {}  # building id -> CPUParticles3D
var _walk_mm: Array[MultiMeshInstance3D] = []
var _walkers: Array[Dictionary] = []
var _waiting: MultiMeshInstance3D
var _rise_nodes := {}  # id -> MeshInstance3D
var _markers := {}  # slot -> Node3D
var _train: Node3D
var _train_route: Array[Vector3] = []
var _train_s := 0.0
var _train_dir := 1.0
var _train_pause := 0.0
var _lay_ver := -1
var _tree_ver := -1
var _bld_ver := -1
var _dirty := true
var _slow_t := 0.0
var _t := 0.0
var _route_ver := -1


func setup(p_main: Node, p_town: Town, p_isl: Dictionary, p_vr: bool) -> void:
	main = p_main
	town = p_town
	isl = p_isl
	vr = p_vr
	snowy = bool(isl.get("snow", false))


# --- Island ---------------------------------------------------------------------------------------

## Build the static scenery for the current island (table, sea, terrain). Call when the island changes.
func rebuild_island(p_isl: Dictionary) -> void:
	isl = p_isl
	snowy = bool(isl.get("snow", false))
	if _static == null:
		_static = Node3D.new()
		_static.name = "Static"
		add_child(_static)
		var table := MeshKit.instance(Art.table_mesh())
		_static.add_child(table)
		var garden := MeshKit.instance(Art.garden_mesh(), false)
		_static.add_child(garden)
		var big_trees := MeshKit.scatter_random(MeshKit.prop("tree"), 14, Vector3.ZERO, 14.0, 5.0, 1.1, 1.7, PackedColorArray(), 9)
		_static.add_child(big_trees)
		var bushes := MeshKit.scatter_random(MeshKit.prop("bush"), 18, Vector3.ZERO, 6.0, 2.6, 0.8, 1.3, PackedColorArray(), 10)
		_static.add_child(bushes)
		var flowers := MeshKit.scatter_random(MeshKit.prop("flower"), 40, Vector3.ZERO, 5.0, 2.6, 0.7, 1.1,
			PackedColorArray([Color(1.0, 0.5, 0.6), Color(1.0, 0.9, 0.4), Color(0.7, 0.6, 1.0)]), 11)
		_static.add_child(flowers)
		_sea = MeshInstance3D.new()
		_sea.name = "Sea"
		_sea.mesh = Art.sea_mesh(0.86)
		_sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_static.add_child(_sea)
		_sea.position = Vector3(0, Defs.SEA_Y, 0)
	_sea.material_override = Art.sea_material(isl.get("sea", Color(0.25, 0.62, 0.85)))
	if _terrain != null:
		_terrain.queue_free()
	_terrain = MeshKit.instance(Art.terrain_mesh(town.ter, isl))
	_terrain.name = "Terrain"
	add_child(_terrain)
	_lay_ver = -1
	_tree_ver = -1
	_dirty = true
	for id in _sites.keys():
		(_sites[id] as Node).queue_free()
	_sites.clear()


func mark_dirty() -> void:
	_dirty = true


# --- Per frame --------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if town == null:
		return
	_t += delta
	if town.lay_version != _lay_ver:
		_lay_ver = town.lay_version
		_rebuild_roads()
	if town.tree_version != _tree_ver:
		_tree_ver = town.tree_version
		_rebuild_trees()
	if town.version != _bld_ver or _dirty:
		_bld_ver = town.version
		_dirty = false
		_rebuild_buildings()
		_slow_t = 0.0
	_slow_t -= delta
	if _slow_t <= 0.0:
		_slow_t = 0.5
		_refresh_status()
	_animate(delta)
	_walk(delta)
	_train_tick(delta)


# --- Roads, rails, lamps, trees ------------------------------------------------------------------------

func _mm(mesh: Mesh, shadows: bool = false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


func _fill(mmi: MultiMeshInstance3D, xfs: Array[Transform3D]) -> void:
	mmi.multimesh.instance_count = xfs.size()
	for i in xfs.size():
		mmi.multimesh.set_instance_transform(i, xfs[i])
	mmi.visible = not xfs.is_empty()


func _cell_xf(x: int, z: int, k: int, y: float = 0.0) -> Transform3D:
	var c := Defs.cell_center(x, z)
	return Transform3D(Basis(Vector3.UP, k * PI * 0.5).scaled(Vector3.ONE * Defs.CELL), c + Vector3(0, y, 0))


func _rebuild_roads() -> void:
	var road_xf := {}
	var rail_xf := {}
	for s in ROAD_SHAPES:
		var a: Array[Transform3D] = []
		road_xf[s] = a
		var b: Array[Transform3D] = []
		rail_xf[s] = b
	var cross_xf: Array[Transform3D] = []
	var lamp_xf: Array[Transform3D] = []
	var n := Defs.GRID
	for z in n:
		for x in n:
			var l := town.layer(x, z)
			if l == Defs.L_NONE:
				continue
			if l == Defs.L_ROAD or l == Defs.L_CROSS:
				var mask := town.road_mask(x, z)
				var sh: Array = Art.shape_for(mask)
				(road_xf[String(sh[0])] as Array).append(_cell_xf(x, z, int(sh[1]), 0.0004))
				if l == Defs.L_CROSS:
					var rm := town.rail_mask(x, z)
					cross_xf.append(_cell_xf(x, z, 0 if (rm & 5) != 0 or rm == 0 else 1, 0.0006))
				elif (x + 2 * z) % 3 == 0:
					var off := Vector2(0.43, 0.43)
					if not (mask & 2):
						off = Vector2(0.43, 0.0)
					elif not (mask & 8):
						off = Vector2(-0.43, 0.0)
					elif not (mask & 4):
						off = Vector2(0.0, 0.43)
					elif not (mask & 1):
						off = Vector2(0.0, -0.43)
					var c := Defs.cell_center(x, z) + Vector3(off.x, 0.0, off.y) * Defs.CELL
					var yaw := atan2(-off.x, -off.y)
					lamp_xf.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * Defs.CELL), c))
			else:
				var rm2 := town.rail_mask(x, z)
				var sh2: Array = Art.shape_for(rm2)
				(rail_xf[String(sh2[0])] as Array).append(_cell_xf(x, z, int(sh2[1]), 0.0004))
	for s in ROAD_SHAPES:
		if not _roads.has(s):
			_roads[s] = _mm(Art.road_mesh(s))
			_rails[s] = _mm(Art.rail_mesh(s))
		var ra: Array[Transform3D] = road_xf[s]
		_fill(_roads[s], ra)
		var rb: Array[Transform3D] = rail_xf[s]
		_fill(_rails[s], rb)
	if _cross == null:
		_cross = _mm(Art.crossing_mesh())
		_lamps = _mm(Art.lamp_mesh(), true)
	_fill(_cross, cross_xf)
	_fill(_lamps, lamp_xf)
	_route_ver = -1


func _rebuild_trees() -> void:
	var kind := String(isl.get("tree", "tree"))
	if _trees == null or _trees.get_meta("kind", "") != kind:
		if _trees != null:
			_trees.queue_free()
		_trees = _mm(MeshKit.prop(kind), true)
		_trees.set_meta("kind", kind)
		_trees.multimesh.use_colors = true
	var xfs: Array[Transform3D] = []
	var cols := PackedColorArray()
	var n := Defs.GRID
	for z in n:
		for x in n:
			var cnt := int(town.trees[Town.idx(x, z)])
			for k in cnt:
				var h := (x * 73856093) ^ (z * 19349663) ^ (k * 83492791)
				var ox := (float(h % 1000) / 1000.0 - 0.5) * 0.6
				var oz := (float((h / 1000) % 1000) / 1000.0 - 0.5) * 0.6
				if cnt == 1:
					ox *= 0.3
					oz *= 0.3
				var s := 0.012 + float((h / 7) % 100) / 100.0 * 0.006
				var c := Defs.cell_center(x, z) + Vector3(ox, 0.0, oz) * Defs.CELL
				xfs.append(Transform3D(Basis(Vector3.UP, float(h % 628) / 100.0).scaled(Vector3.ONE * s), c))
				var tint := Color(1, 1, 1).lerp(Color(1.0, 1.0, 0.75), float((h / 13) % 100) / 400.0)
				if snowy:
					tint = tint.lerp(Color(0.85, 0.95, 1.0), 0.35)
				cols.append(tint)
	_trees.multimesh.instance_count = 0
	_trees.multimesh.use_colors = true
	_trees.multimesh.instance_count = xfs.size()
	for i in xfs.size():
		_trees.multimesh.set_instance_transform(i, xfs[i])
		_trees.multimesh.set_instance_color(i, cols[i])
	_trees.visible = not xfs.is_empty()


# --- Buildings ------------------------------------------------------------------------------------------

func building_xf(b: Dictionary) -> Transform3D:
	var c := town.center_of(b)
	return Transform3D(Basis(Vector3.UP, int(b["rot"]) * PI * 0.5).scaled(Vector3.ONE * Defs.CELL), c + Vector3(0, 0.0005, 0))


func _rebuild_buildings() -> void:
	var by_key := {}
	var meshes := {}
	_sail_xf.clear()
	_wheel_xf.clear()
	var live_sites := {}
	for id in town.buildings:
		var b: Dictionary = town.buildings[id]
		if int(id) == hidden_id:
			continue
		var kind := String(b["kind"])
		var xf := building_xf(b)
		if int(b["stage"]) < 1:
			live_sites[id] = true
			_update_site(b)
			continue
		if rising.has(id):
			continue
		var key := Art.building_key(kind, int(id), int(b["lvl"]), snowy)
		if not by_key.has(key):
			var arr: Array[Transform3D] = []
			by_key[key] = arr
			meshes[key] = Art.building_mesh(kind, int(id), int(b["lvl"]), snowy)
		(by_key[key] as Array).append(xf)
		if kind == "windmill":
			_sail_xf.append(xf * Transform3D(Basis(), Vector3(0, 0.62, 0.25)))
		elif kind == "ferris":
			_wheel_xf.append(xf * Transform3D(Basis(), Vector3(0, 1.0, 0)))
	for key in _groups:
		if not by_key.has(key):
			(_groups[key] as MultiMeshInstance3D).visible = false
			(_groups[key] as MultiMeshInstance3D).multimesh.instance_count = 0
	for key in by_key:
		if not _groups.has(key):
			_groups[key] = _mm(meshes[key], true)
		var xs: Array[Transform3D] = by_key[key]
		_fill(_groups[key], xs)
	for id in _sites.keys():
		if not live_sites.has(id):
			(_sites[id] as Node).queue_free()
			_sites.erase(id)
	if _sails == null:
		_sails = _mm(Art.windmill_sails(), true)
		_wheels = _mm(Art.ferris_wheel(), true)
	_sails.multimesh.instance_count = _sail_xf.size()
	_wheels.multimesh.instance_count = _wheel_xf.size()
	_route_ver = -1
	_refresh_status()


## A blueprint: the building in see-through blue, scaffolding and the delivered materials.
func _update_site(b: Dictionary) -> void:
	var id := int(b["id"])
	var site: Node3D = _sites.get(id, null)
	var kind := String(b["kind"])
	if site == null:
		site = Node3D.new()
		site.name = "Site%d" % id
		add_child(site)
		_sites[id] = site
		var ghost := MeshInstance3D.new()
		ghost.name = "Ghost"
		ghost.mesh = Art.building_mesh(kind, id, 1, snowy)
		ghost.material_override = Art.ghost_mat(Color(0.55, 0.8, 1.0, 0.38))
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		site.add_child(ghost)
		var scaf := MeshInstance3D.new()
		scaf.mesh = Art.scaffold_mesh(Defs.size_of(kind))
		site.add_child(scaf)
		var pile := Node3D.new()
		pile.name = "Pile"
		site.add_child(pile)
		site.scale = Vector3.ONE * 0.3
		var tw := site.create_tween()
		tw.tween_property(site, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var xf := building_xf(b)
	site.transform = Transform3D(xf.basis, xf.origin)
	site.scale = site.scale  # keep the tween's scale
	var pile2: Node3D = site.get_node("Pile")
	var have := int(b["mats"])
	if pile2.get_child_count() != have:
		for c in pile2.get_children():
			c.queue_free()
		var s := Defs.size_of(kind)
		for k in have:
			var m := MeshInstance3D.new()
			m.mesh = Art.cargo_mesh("bricks")
			m.position = Vector3(-s * 0.5 + 0.18 + k * 0.22, 0.0, s * 0.5 - 0.12)
			pile2.add_child(m)


## The building finished: pop it up out of the ground with a bounce.
func start_rise(id: int) -> void:
	var b: Dictionary = town.buildings.get(id, {})
	if b.is_empty():
		return
	rising[id] = 0.7
	var mi := MeshKit.instance(Art.building_mesh(String(b["kind"]), id, int(b["lvl"]), snowy))
	add_child(mi)
	var xf := building_xf(b)
	mi.transform = xf
	mi.scale = Vector3(Defs.CELL * 1.25, Defs.CELL * 0.05, Defs.CELL * 1.25)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(Defs.CELL * 0.9, Defs.CELL * 1.2, Defs.CELL * 0.9), 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3.ONE * Defs.CELL, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_rise_nodes[id] = mi
	dust(town.center_of(b), Defs.size_of(String(b["kind"])))
	_dirty = true


## A quick squash for a building that was just placed / upgraded.
func plonk(id: int) -> void:
	var site: Node3D = _sites.get(id, null)
	if site != null:
		var tw := site.create_tween()
		site.scale = Vector3(1.25, 0.7, 1.25)
		tw.tween_property(site, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


# --- Status: icons, fires, smoke, waiting people (twice a second) --------------------------------------------

func _icon_for(b: Dictionary) -> String:
	var n := int(b["needs"])
	if int(b["stage"]) < 1:
		return "build"
	if n & Defs.N_FIRE:
		return "fire"
	if n & Defs.N_ROAD:
		return "road"
	if n & Defs.N_POWER:
		return "power"
	if n & Defs.N_WATER:
		return "water"
	if n & Defs.N_JOBS:
		return "jobs"
	if n & Defs.N_WORKERS:
		return "workers"
	if n & Defs.N_STOCK:
		return "stock"
	if n & Defs.N_SHOP:
		return "shop"
	if n & Defs.N_FUN:
		return "fun"
	return ""


func _refresh_status() -> void:
	if town == null:
		return
	for ic in ICONS:
		var arr: Array[Vector3] = []
		_icon_pos[ic] = arr
	_smoke_src.clear()
	var waiting: Array[Transform3D] = []
	var burning := {}
	var night := float(main.get("night")) if main != null and main.get("night") != null else 0.0
	for id in town.buildings:
		var b: Dictionary = town.buildings[id]
		if int(id) == hidden_id:
			continue
		var kind := String(b["kind"])
		var s := Defs.size_of(kind)
		var c := town.center_of(b)
		var ic := _icon_for(b)
		if ic != "" and not (ic == "build" and int(b["mats"]) >= int(b["need"])):
			var top := 0.8 if s == 1 else 1.6
			if kind == "house":
				top = [0.0, 0.8, 1.1, 1.4][clampi(int(b["lvl"]), 1, 3)]
			(_icon_pos[ic] as Array).append(c + Vector3(0, top * Defs.CELL + 0.012, 0))
		if int(b["fire"]) > 0:
			burning[int(id)] = c
		if int(b["stage"]) >= 1:
			var rot := int(b["rot"])
			var basis := Basis(Vector3.UP, rot * PI * 0.5)
			match kind:
				"bakery":
					if int(b["work"]) > 0:
						_smoke_src.append(c + basis * Vector3(-0.18, 0.8, -0.22) * Defs.CELL)
				"house":
					var lvl := int(b["lvl"])
					if lvl < 3 and (snowy or night > 0.4 or int(id) % 3 == 0) and int(b["res"]) > 0:
						var p := Vector3(0.16, 0.66, -0.14) if lvl == 1 else Vector3(-0.18, 0.96, -0.16)
						_smoke_src.append(c + basis * p * Defs.CELL)
				"sawmill":
					if int(b["work"]) > 0:
						_smoke_src.append(c + basis * Vector3(0.2, 0.2, 0.75) * Defs.CELL)
			if kind == "house" and int(b["wait"]) > 0:
				var dc := town.door_cell(b)
				var dp := Defs.cell_center(dc.x, dc.y)
				var toward := (c - dp).normalized() * Defs.CELL * 0.38
				for k in mini(int(b["wait"]), 4):
					var side := Vector3(-toward.z, 0, toward.x).normalized() * (k - 1.5) * Defs.CELL * 0.14
					waiting.append(Transform3D(Basis(Vector3.UP, atan2(-toward.x, -toward.z)).scaled(Vector3.ONE * WALKER_SCALE), dp + toward + side))
		if _smoke_src.size() >= 24:
			break
	for ic in ICONS:
		if not _icons.has(ic):
			_icons[ic] = _mm(_icon_mesh(ic))
		var ps: Array[Vector3] = _icon_pos[ic]
		(_icons[ic] as MultiMeshInstance3D).multimesh.instance_count = ps.size()
		(_icons[ic] as MultiMeshInstance3D).visible = not ps.is_empty()
	# fires
	for id in _fires.keys():
		if not burning.has(id):
			(_fires[id] as Node).queue_free()
			_fires.erase(id)
	for id in burning:
		if not _fires.has(id):
			_fires[id] = _make_fire(burning[id])
	# smoke + waiting people
	if _smoke == null:
		var sm := MeshKit.Builder.new()
		sm.sphere(1.0, MeshKit.at(Vector3.ZERO), Color(1, 1, 1), 8)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 1.0
		_smoke = _mm(sm.build(mat))
		_smoke.multimesh.instance_count = 0
		_smoke.multimesh.use_colors = true
	_smoke.multimesh.instance_count = 0
	_smoke.multimesh.use_colors = true
	_smoke.multimesh.instance_count = _smoke_src.size() * 3
	if _waiting == null:
		_waiting = _mm(Art.citizen_mesh(1))
	_fill(_waiting, waiting)


func _make_fire(at: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 14 if vr else 24
	p.lifetime = 0.7
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = Defs.CELL * 0.3
	p.direction = Vector3.UP
	p.spread = 15.0
	p.gravity = Vector3(0, 0.05, 0)
	p.initial_velocity_min = 0.03
	p.initial_velocity_max = 0.06
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.008
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = mat
	p.mesh = bm
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.9, 0.3))
	grad.set_color(1, Color(1.0, 0.3, 0.1, 0.0))
	p.color_ramp = grad
	add_child(p)
	p.position = at + Vector3(0, Defs.CELL * 0.45, 0)
	p.emitting = true
	return p


## Need icons: a white bubble with a coloured symbol, always facing the viewer (no text).
func _icon_mesh(ic: String) -> ArrayMesh:
	return ResCache.get_or_make("ttt_icon_%s_%s" % [ic, Art.VER], func() -> Resource:
		var b := MeshKit.Builder.new()
		var s := 0.016
		var bubble := Color(1, 1, 1)
		var ring := Color(0.2, 0.2, 0.25)
		if ic == "fire":
			bubble = Color(1.0, 0.85, 0.8)
			ring = Color(0.9, 0.2, 0.15)
		b.panel(Vector2(s * 2.3, s * 2.3), s * 1.15, MeshKit.at(Vector3(0, 0, -0.0006)), ring, 5)
		b.panel(Vector2(s * 2.0, s * 2.0), s, MeshKit.at(Vector3.ZERO), bubble, 5)
		b.cone(s * 0.4, s * 0.6, MeshKit.at(Vector3(0, -s * 1.15, -0.0003), Vector3(1, 1, 0.2), Vector3(0, 0, PI)), ring, 3)
		var z := Vector3(0, 0, 0.0008)
		match ic:
			"power":
				var bolt := PackedVector2Array([Vector2(0.1, 0.75), Vector2(-0.4, -0.05), Vector2(-0.02, -0.05), Vector2(-0.15, -0.75),
					Vector2(0.4, 0.1), Vector2(0.02, 0.1)])
				var pts := PackedVector2Array()
				for p in bolt:
					pts.append(p * s)
				b.polygon(pts, 0.0006, MeshKit.at(z), Color(1.0, 0.8, 0.1))
			"water":
				b.sphere(s * 0.42, MeshKit.at(z + Vector3(0, -s * 0.2, 0), Vector3(1, 1, 0.2)), Color(0.25, 0.55, 1.0), 10)
				b.cone(s * 0.36, s * 0.55, MeshKit.at(z + Vector3(0, s * 0.3, 0), Vector3(1, 1, 0.2)), Color(0.25, 0.55, 1.0), 10)
			"road":
				b.box(Vector3(s * 0.5, s * 1.4, 0.0006), MeshKit.at(z), Color(0.35, 0.36, 0.4))
				for k in 3:
					b.box(Vector3(s * 0.08, s * 0.25, 0.0008), MeshKit.at(z + Vector3(0, -s * 0.45 + k * s * 0.45, 0.0002)), Color(1, 1, 1))
			"jobs", "workers":
				var col := Color(0.3, 0.55, 0.95) if ic == "jobs" else Color(0.5, 0.35, 0.85)
				b.sphere(s * 0.28, MeshKit.at(z + Vector3(0, s * 0.35, 0), Vector3(1, 1, 0.2)), col, 8)
				b.panel(Vector2(s * 0.9, s * 0.6), s * 0.25, MeshKit.at(z + Vector3(0, -s * 0.3, 0)), col, 3)
				if ic == "jobs":
					b.box(Vector3(s * 0.5, s * 0.35, 0.0006), MeshKit.at(z + Vector3(s * 0.4, -s * 0.45, 0.0004)), Color(0.55, 0.36, 0.2))
			"stock":
				b.box(Vector3(s * 1.0, s * 0.8, 0.0006), MeshKit.at(z + Vector3(0, -s * 0.1, 0)), Color(0.75, 0.5, 0.28))
				b.box(Vector3(s * 1.0, s * 0.1, 0.0008), MeshKit.at(z + Vector3(0, s * 0.05, 0.0002)), Color(0.5, 0.32, 0.18))
				b.sphere(s * 0.18, MeshKit.at(z + Vector3(-s * 0.2, s * 0.42, 0), Vector3(1, 1, 0.2)), Color(0.95, 0.3, 0.25), 6)
				b.sphere(s * 0.18, MeshKit.at(z + Vector3(s * 0.2, s * 0.42, 0), Vector3(1, 1, 0.2)), Color(0.5, 0.85, 0.3), 6)
			"shop":
				b.panel(Vector2(s * 1.1, s * 0.7), s * 0.1, MeshKit.at(z + Vector3(0, -s * 0.15, 0)), Color(0.3, 0.75, 0.7), 2)
				for k in 4:
					var c2 := Color(0.95, 0.3, 0.3) if k % 2 == 0 else Color(1, 1, 1)
					b.box(Vector3(s * 0.28, s * 0.25, 0.0008), MeshKit.at(z + Vector3(-s * 0.42 + k * s * 0.28, s * 0.35, 0.0002)), c2)
			"fun":
				b.sphere(s * 0.5, MeshKit.at(z + Vector3(0, s * 0.2, 0), Vector3(1, 1, 0.2)), Color(0.35, 0.75, 0.35), 8)
				b.box(Vector3(s * 0.16, s * 0.6, 0.0006), MeshKit.at(z + Vector3(0, -s * 0.45, 0)), Color(0.55, 0.36, 0.2))
			"fire":
				b.sphere(s * 0.45, MeshKit.at(z + Vector3(0, -s * 0.2, 0), Vector3(1, 1, 0.2)), Color(1.0, 0.45, 0.1), 8)
				b.cone(s * 0.4, s * 0.8, MeshKit.at(z + Vector3(0, s * 0.35, 0), Vector3(1, 1, 0.2)), Color(1.0, 0.45, 0.1), 8)
				b.sphere(s * 0.22, MeshKit.at(z + Vector3(0, -s * 0.2, 0.0004), Vector3(1, 1, 0.2)), Color(1.0, 0.9, 0.3), 6)
			"build":
				for k in 3:
					b.box(Vector3(s * 0.45, s * 0.28, 0.0006), MeshKit.at(z + Vector3(-s * 0.25 + (k % 2) * s * 0.5, -s * 0.35 + floorf(k * 0.5) * s * 0.32, 0)), Color(0.85, 0.42, 0.32))
				b.box(Vector3(s * 0.12, s * 0.7, 0.0006), MeshKit.at(z + Vector3(s * 0.3, s * 0.25, 0.0004), Vector3.ONE, Vector3(0, 0, -0.6)), Color(0.55, 0.36, 0.2))
				b.box(Vector3(s * 0.45, s * 0.2, 0.0006), MeshKit.at(z + Vector3(s * 0.1, s * 0.55, 0.0004), Vector3.ONE, Vector3(0, 0, -0.6)), Color(0.6, 0.62, 0.68))
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true
		mat.no_depth_test = false
		mat.render_priority = 3
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		return b.build(mat)) as ArrayMesh


# --- Animation --------------------------------------------------------------------------------------------

func _animate(delta: float) -> void:
	for i in _sail_xf.size():
		var a := _t * 1.6 + i * 0.7
		_sails.multimesh.set_instance_transform(i, _sail_xf[i] * Transform3D(Basis(Vector3.BACK, a), Vector3.ZERO))
	for i in _wheel_xf.size():
		_wheels.multimesh.set_instance_transform(i, _wheel_xf[i] * Transform3D(Basis(Vector3.RIGHT, _t * 0.35), Vector3.ZERO))
	for ic in _icons:
		var ps: Array[Vector3] = _icon_pos.get(ic, [] as Array[Vector3])
		var mmi: MultiMeshInstance3D = _icons[ic]
		var n := mini(ps.size(), mmi.multimesh.instance_count)
		for i in n:
			var bob := sin(_t * 3.0 + i * 1.3) * 0.002
			var pulse := 1.0 + (sin(_t * 8.0) * 0.12 if ic == "fire" else 0.0)
			mmi.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * pulse), ps[i] + Vector3(0, bob, 0)))
	if _smoke != null:
		var cnt := _smoke.multimesh.instance_count
		for i in cnt:
			var src := _smoke_src[i / 3] if i / 3 < _smoke_src.size() else Vector3.ZERO
			var ph := fposmod(_t * 0.4 + (i % 3) / 3.0 + float(i / 3) * 0.37, 1.0)
			var r := 0.002 + ph * 0.006
			var p := src + Vector3(sin(ph * 4.0 + i) * 0.004 + ph * 0.008, ph * 0.05, 0)
			_smoke.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * r), p))
			_smoke.multimesh.set_instance_color(i, Color(0.92, 0.92, 0.95, 0.55 * (1.0 - ph)))
	for id in rising.keys():
		rising[id] = float(rising[id]) - delta
		if float(rising[id]) <= 0.0:
			rising.erase(id)
			var mi: Node = _rise_nodes.get(id, null)
			if mi != null:
				mi.queue_free()
			_rise_nodes.erase(id)
			_dirty = true
	for slot in _markers:
		var m: Node3D = _markers[slot]
		if m.visible:
			var ring: Node3D = m.get_node("Ring")
			ring.rotation.y = _t * 1.5
			ring.scale = Vector3.ONE * (1.0 + sin(_t * 5.0) * 0.08)


# --- Citizens strolling ------------------------------------------------------------------------------------

## How many citizens walk about (capped for the GPU).
func set_walkers(count: int) -> void:
	var cap := 28 if vr else 44
	count = clampi(count, 0, cap)
	if _walk_mm.is_empty():
		for look in 4:
			var mmi := _mm(Art.citizen_mesh(look + 2))
			_walk_mm.append(mmi)
	while _walkers.size() < count:
		_walkers.append(_new_walker(_walkers.size()))
	while _walkers.size() > count:
		_walkers.pop_back()
	for look in 4:
		var n := 0
		for i in _walkers.size():
			if i % 4 == look:
				n += 1
		if _walk_mm[look].multimesh.instance_count != n:
			_walk_mm[look].multimesh.instance_count = n
		_walk_mm[look].visible = n > 0


func _new_walker(i: int) -> Dictionary:
	var cells: Array[Vector2i] = []
	for id in town.buildings:
		var b: Dictionary = town.buildings[id]
		if String(b["kind"]) == "house" and int(b["stage"]) >= 1:
			cells.append(town.door_cell(b))
	var start := Vector2i(Defs.GRID / 2, Defs.GRID / 2)
	if not cells.is_empty():
		start = cells[(i * 7 + randi()) % cells.size()]
	var side := 0.36 if i % 2 == 0 else -0.36
	return {"from": start, "to": start, "t": 1.0, "side": side, "speed": randf_range(0.5, 0.8), "pos": Defs.cell_center(start.x, start.y),
		"yaw": 0.0, "pause": randf_range(0.0, 2.0)}


func _walk(delta: float) -> void:
	if _walkers.is_empty():
		return
	var idx_in_look: Array[int] = [0, 0, 0, 0]
	for i in _walkers.size():
		var w: Dictionary = _walkers[i]
		var pause := float(w["pause"])
		if pause > 0.0:
			w["pause"] = pause - delta
		else:
			w["t"] = float(w["t"]) + delta * float(w["speed"])
			if float(w["t"]) >= 1.0:
				w["t"] = 0.0
				var cur: Vector2i = w["to"]
				var prev: Vector2i = w["from"]
				w["from"] = cur
				w["to"] = _next_cell(cur, prev)
				if randf() < 0.08:
					w["pause"] = randf_range(0.8, 2.5)
		var a: Vector2i = w["from"]
		var b: Vector2i = w["to"]
		var pa := Defs.cell_center(a.x, a.y)
		var pb := Defs.cell_center(b.x, b.y)
		var dir := (pb - pa)
		var flat := Vector3(dir.x, 0, dir.z)
		var side_v := Vector3(-flat.z, 0, flat.x).normalized() * float(w["side"]) * Defs.CELL if flat.length() > 0.0001 else Vector3.ZERO
		var p := pa.lerp(pb, float(w["t"])) + side_v
		var moving := pause <= 0.0 and flat.length() > 0.0001
		if moving:
			w["yaw"] = lerp_angle(float(w["yaw"]), atan2(flat.x, flat.z), 1.0 - exp(-10.0 * delta))
		var hop := absf(sin(_t * 9.0 + i)) * 0.0012 if moving else 0.0
		w["pos"] = p
		var look := i % 4
		var mm := _walk_mm[look].multimesh
		var k := idx_in_look[look]
		if k < mm.instance_count:
			var sway := sin(_t * 9.0 + i) * 0.12 if moving else 0.0
			mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, float(w["yaw"])) * Basis(Vector3.BACK, sway) * Basis().scaled(Vector3.ONE * WALKER_SCALE),
				p + Vector3(0, 0.0012 + hop, 0)))
		idx_in_look[look] = k + 1


func _next_cell(cur: Vector2i, prev: Vector2i) -> Vector2i:
	var opts: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var dv: Vector2i = d
		var n := cur + dv
		if town.has_road(n.x, n.y) and n != prev:
			opts.append(n)
	if opts.is_empty():
		if town.has_road(prev.x, prev.y) or prev != cur:
			return prev
		# no roads: potter about on the grass nearby
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var dv2: Vector2i = d
			var n2 := cur + dv2
			if town.inside(n2.x, n2.y) and town.is_land(n2.x, n2.y) and town.owner_id[Town.idx(n2.x, n2.y)] == 0:
				opts.append(n2)
		if opts.is_empty():
			return cur
	return opts[randi() % opts.size()]


# --- Toy train --------------------------------------------------------------------------------------------------

## True while a train runs (two stations joined by rails).
func has_train() -> bool:
	return _train_route.size() >= 2


func _train_tick(delta: float) -> void:
	var ver := town.version * 1000 + town.lay_version
	if ver != _route_ver:
		_route_ver = ver
		_find_route()
	if _train_route.size() < 2:
		if _train != null:
			_train.visible = false
		return
	if _train == null:
		_train = _make_train()
	_train.visible = true
	var length := float(_train_route.size() - 1)
	if _train_pause > 0.0:
		_train_pause -= delta
	else:
		_train_s += _train_dir * delta * 1.1
		if _train_s >= length or _train_s <= 0.0:
			_train_s = clampf(_train_s, 0.0, length)
			_train_dir = -_train_dir
			_train_pause = 2.5
			if main != null and main.has_method("train_arrived"):
				main.call("train_arrived")
	var cars := _train.get_children()
	for k in cars.size():
		var car: Node3D = cars[k]
		var s := clampf(_train_s - k * 0.62 * _train_dir, 0.0, length)
		var p := _route_point(s)
		var q := _route_point(clampf(s + 0.15 * _train_dir, 0.0, length))
		car.position = p + Vector3(0, 0.0025, 0)
		var d := q - p
		if d.length() > 0.0001:
			car.rotation.y = atan2(d.x, d.z)


func _route_point(s: float) -> Vector3:
	var i := clampi(int(floor(s)), 0, _train_route.size() - 1)
	var j := clampi(i + 1, 0, _train_route.size() - 1)
	return _train_route[i].lerp(_train_route[j], s - floor(s))


func _find_route() -> void:
	_train_route.clear()
	var st := town.of_kind("station")
	for i in st.size():
		for j in range(i + 1, st.size()):
			var r := town.rail_route(st[i], st[j])
			if r.size() >= 2:
				for c in r:
					_train_route.append(Defs.cell_center(c.x, c.y))
				_train_s = clampf(_train_s, 0.0, float(_train_route.size() - 1))
				return


func _make_train() -> Node3D:
	var t := Node3D.new()
	t.name = "Train"
	add_child(t)
	var loco := MeshKit.Builder.new()
	loco.rounded_box(Vector3(0.3, 0.22, 0.5), 0.04, MeshKit.at(Vector3(0, 0.17, 0)), Color(0.85, 0.2, 0.22), 1)
	loco.cylinder(0.11, 0.11, 0.32, MeshKit.at(Vector3(0, 0.22, 0.08), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.2, 0.22, 0.28), 10)
	loco.cylinder(0.04, 0.05, 0.12, MeshKit.at(Vector3(0, 0.38, 0.18)), Color(0.2, 0.2, 0.22), 8)
	loco.box(Vector3(0.28, 0.2, 0.16), MeshKit.at(Vector3(0, 0.3, -0.16)), Color(0.2, 0.45, 0.85))
	loco.sphere(0.03, MeshKit.at(Vector3(0, 0.22, 0.26)), Color(1.0, 0.95, 0.6), 6, true)
	var car := MeshKit.Builder.new()
	car.rounded_box(Vector3(0.28, 0.22, 0.5), 0.04, MeshKit.at(Vector3(0, 0.18, 0)), Color(0.3, 0.65, 0.95), 1)
	car.box(Vector3(0.29, 0.07, 0.4), MeshKit.at(Vector3(0, 0.23, 0)), Color(1.0, 0.95, 0.8), true)
	car.box(Vector3(0.3, 0.03, 0.52), MeshKit.at(Vector3(0, 0.3, 0)), Color(0.95, 0.95, 0.98))
	var lm := loco.build()
	var cm := car.build(null, Art.window_mat())
	for k in 3:
		var mi := MeshKit.instance(lm if k == 0 else cm)
		mi.scale = Vector3.ONE * Defs.CELL
		t.add_child(mi)
	return t


# --- Markers (job targets) -------------------------------------------------------------------------------------

## A glowing ring + light beam at `pos` for TV player `slot` (only their own view shows it).
func set_marker(slot: int, pos: Vector3, color: Color, on: bool) -> void:
	var m: Node3D = _markers.get(slot, null)
	if m == null:
		if not on:
			return
		m = Node3D.new()
		m.name = "Marker%d" % slot
		add_child(m)
		_markers[slot] = m
		var layer := 1 << (MARKER_BIT0 + clampi(slot, 0, 7))
		var ring := MeshInstance3D.new()
		ring.name = "Ring"
		var tm := TorusMesh.new()
		tm.inner_radius = Defs.CELL * 0.42
		tm.outer_radius = Defs.CELL * 0.52
		tm.rings = 24
		tm.ring_segments = 6
		ring.mesh = tm
		ring.material_override = MeshKit.material(color, 2.0)
		ring.layers = layer
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.scale = Vector3(1, 0.3, 1)
		m.add_child(ring)
		var beam := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = Defs.CELL * 0.12
		cm.bottom_radius = Defs.CELL * 0.3
		cm.height = 0.35
		cm.radial_segments = 10
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		beam.mesh = cm
		beam.material_override = Art.ghost_mat(Color(color.r, color.g, color.b, 0.22))
		beam.layers = layer
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.position.y = 0.175
		m.add_child(beam)
	m.visible = on
	if on:
		m.position = Vector3(pos.x, Defs.GROUND_Y + 0.002, pos.z)


## The cull mask a TV view's camera should use (its own markers + the VR player's avatar).
static func view_mask(slot: int) -> int:
	return BASE_MASK | AVATAR_BIT | (1 << (MARKER_BIT0 + clampi(slot, 0, 7)))


# --- Effects ----------------------------------------------------------------------------------------------------

## A puff of dust (placing / finishing a building).
func dust(at: Vector3, size: int = 1) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 16
	p.lifetime = 0.6
	p.explosiveness = 0.95
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = Defs.CELL * 0.5 * size
	p.emission_ring_inner_radius = Defs.CELL * 0.35 * size
	p.emission_ring_height = 0.001
	p.direction = Vector3.UP
	p.spread = 60.0
	p.gravity = Vector3(0, -0.05, 0)
	p.initial_velocity_min = 0.03
	p.initial_velocity_max = 0.07
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var sm := SphereMesh.new()
	sm.radius = 0.004
	sm.height = 0.008
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = MeshKit.material(Color(0.92, 0.88, 0.8, 0.8))
	p.mesh = sm
	add_child(p)
	p.position = at + Vector3(0, 0.003, 0)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


## Sparkles in a colour (deliveries, upgrades, happy moments).
func burst(at: Vector3, color: Color, amount: int = 14, size: float = 1.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.gravity = Vector3(0, -0.15, 0)
	p.initial_velocity_min = 0.06 * size
	p.initial_velocity_max = 0.12 * size
	p.mesh = Art.spark_mesh(color)
	p.scale_amount_min = 0.5 * size
	p.scale_amount_max = 1.0 * size
	add_child(p)
	p.position = at
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


## Fireworks over the island (milestones, island complete).
func fireworks(count: int = 6) -> void:
	var cols: Array[Color] = [Color(1, 0.4, 0.5), Color(1, 0.85, 0.3), Color(0.4, 0.8, 1), Color(0.6, 1, 0.5), Color(0.85, 0.5, 1)]
	for k in count:
		var delay := k * 0.45 + randf() * 0.2
		var at := Vector3(randf_range(-0.45, 0.45), Defs.GROUND_Y + randf_range(0.35, 0.6), randf_range(-0.45, 0.45))
		var c: Color = cols[k % cols.size()]
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if is_inside_tree():
				burst(at, c, 40 if not vr else 26, 3.5))
