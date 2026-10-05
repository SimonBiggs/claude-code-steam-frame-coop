extends Node3D
## The city for one mission: ground + roads (one merged mesh), blocks of buildings (ONE merged mesh per
## block, rebuilt only when a building in it changes state), the landmark to protect (hospital, power
## plant, moon dome), shelters, rescue spots, trees / lamps / cars as MultiMeshes, and the backdrop.
## Built from (place, seed), so the host and the TV machine build the same city.
##
## Buildings: hp 0..100, state 0 = standing, 1 = damaged (bitten top, darker), 2 = rubble. The host
## changes hp (damage_building / repair_building) and publishes states through the net store ("bld",
## one byte per building: state | burning << 2); every machine shows them with apply_states().
## Collision is analytic (AABBs on XZ) for gameplay (push_out, ray_hit); each building also has a
## StaticBody3D box so TV cameras (core/camera_rig.gd) don't clip through walls.

const Data := preload("res://games/mech_titans/data.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

const CELL := 26.0  ## grid pitch: 10 m road + 16 m block
const ROAD := 10.0
const CELLS: Array[float] = [-52.0, -26.0, 0.0, 26.0, 52.0]
const STATE_OK := 0
const STATE_DAMAGED := 1
const STATE_RUBBLE := 2

var place := "downtown"
var place_info: Dictionary = {}
var seed_value := 1
var night := false
var protect := ""  ## "", "hospital", "plant", "dome"

## Building records: {pos: Vector3 (base centre), size: Vector3, kind, wall: Color, roof: Color, block: int,
## hp: float, state: int, fire: bool, weight: float, seed: int}
var buildings: Array[Dictionary] = []
var blocks: Array[MeshInstance3D] = []
var block_members: Array = []  ## block index -> Array[int] building indices
var bodies: Array[StaticBody3D] = []
var landmark: Node3D
var landmark_pos := Vector3.ZERO
var landmark_radius := 8.0
var landmark_hp := 100.0
var shelters: Array[Vector3] = []
var rescue_spots: Array[Vector3] = []
var water_level := -0.4
var has_water := false
var trees_mm: MultiMesh
var tree_xf: Array[Transform3D] = []
var tree_down := PackedByteArray()
var cars_mm: MultiMesh
var cars: Array[Dictionary] = []  ## {pos, yaw, speed, axis (0 = along x, 1 = along z), lane, crushed}
var boulders: Array[Vector3] = []  ## spots for claw boulders (snowy / volcano / moon)
var _open := {}  ## "x,z" -> what is in that open cell ("plaza", "start", "arrival", "shelter", "landmark", "water")
var _rng := RandomNumberGenerator.new()
var _fires := {}  ## building index -> CPUParticles3D
var _t := 0.0


## Build everything. place: a Data.PLACES key.
func build(p_place: String, p_seed: int, p_night: bool, p_protect: String) -> void:
	place = p_place
	place_info = Data.PLACES.get(place, Data.PLACES["downtown"])
	seed_value = p_seed
	night = p_night
	protect = p_protect
	_rng.seed = p_seed * 7919 + 13
	_plan_cells()
	_build_ground()
	_build_buildings()
	_build_landmark()
	_build_shelters()
	_build_props()
	_build_backdrop()
	_pick_rescue_spots()


# --- Layout ---------------------------------------------------------------------------------------

func _key(x: float, z: float) -> String:
	return "%d,%d" % [int(x), int(z)]


func _plan_cells() -> void:
	_open[_key(0, 0)] = "plaza"
	_open[_key(0, 26)] = "start"
	_open[_key(0, 52)] = "start"
	_open[_key(0, -26)] = "arrival"
	_open[_key(0, -52)] = "arrival"  # a clear boulevard from the north edge: bosses walk in without getting stuck
	_open[_key(-26, 52)] = "shelter"
	_open[_key(26, 52)] = "shelter"
	var water: String = place_info.get("water", "")
	if water == "north":
		has_water = true
		for x in CELLS:
			_open[_key(x, -52)] = "water"
	elif water == "all":
		has_water = true
	match protect:
		"hospital":
			_open[_key(-26, 0)] = "landmark"
			landmark_pos = Vector3(-26, 0, 0)
		"plant":
			_open[_key(26, -26)] = "landmark"
			landmark_pos = Vector3(26, 0, -26)
		"dome":
			_open[_key(0, 0)] = "landmark"
			landmark_pos = Vector3(0, 0, 0)
	shelters = [Vector3(-26, 0, 52), Vector3(26, 0, 52)]


func is_open_cell(x: float, z: float) -> bool:
	return _open.has(_key(x, z))


# --- Ground, roads, water -------------------------------------------------------------------------

func _build_ground() -> void:
	var b := MeshKit.Builder.new()
	var g: Color = place_info["ground"]
	var road: Color = place_info["road"]
	var plaza: Color = place_info["plaza"]
	var island := String(place_info.get("water", "")) == "all"
	if island:
		b.cylinder(Data.MAP + 14.0, Data.MAP + 22.0, 1.0, MeshKit.at(Vector3(0, -0.5, 0)), g, 28)
	else:
		var far := 420.0
		var north_cut := -Data.MAP + 6.0 if has_water else -far * 0.5
		var depth := far * 0.5 - north_cut
		b.box(Vector3(far, 1.0, depth), MeshKit.at(Vector3(0, -0.5, north_cut + depth * 0.5)), g)
	# Roads: a 10 m grid between the cells, with dashed centre lines.
	var line := Color(0.95, 0.9, 0.55) if place != "snowy" else Color(0.75, 0.78, 0.85)
	var half := 2.5 * CELL
	for i in 6:
		var c := -half + i * CELL
		var z0 := -half + (CELL if has_water and not island else 0.0)
		var zl := half * 2.0 - (CELL if has_water and not island else 0.0)
		b.box(Vector3(ROAD, 0.06, zl), MeshKit.at(Vector3(c, 0.03, z0 + zl * 0.5)), road)
		b.box(Vector3(half * 2.0, 0.06, ROAD), MeshKit.at(Vector3(0, 0.031, c)), road)
		if i > 0 and i < 5:
			var n := 9
			for k in n:
				var t := -half + (k + 0.5) * half * 2.0 / n
				b.box(Vector3(0.35, 0.02, 3.0), MeshKit.at(Vector3(c, 0.075, t)), line)
				b.box(Vector3(3.0, 0.02, 0.35), MeshKit.at(Vector3(t, 0.076, c)), line)
	# Pavements / plazas under every cell.
	for x in CELLS:
		for z in CELLS:
			var what: String = _open.get(_key(x, z), "block")
			if what == "water":
				continue
			var col := plaza if what != "block" else plaza.lerp(g, 0.35)
			b.rounded_box(Vector3(CELL - ROAD, 0.16, CELL - ROAD), 0.3, MeshKit.at(Vector3(x, 0.08, z)), col)
			if what == "plaza":
				b.cylinder(6.0, 6.5, 0.5, MeshKit.at(Vector3(x, 0.25, z)), plaza.darkened(0.15), 20)
				b.cylinder(5.0, 5.0, 0.12, MeshKit.at(Vector3(x, 0.52, z)), Color(0.4, 0.7, 1.0), 20)
			elif what == "start":
				b.cylinder(7.0, 7.0, 0.1, MeshKit.at(Vector3(x, 0.17, z)), Color(0.95, 0.75, 0.25), 24)
				b.cylinder(6.0, 6.0, 0.11, MeshKit.at(Vector3(x, 0.18, z)), plaza.darkened(0.25), 24)
	if place == "moon":
		for i in 14:
			var p := Vector3(_rng.randf_range(-150, 150), 0.02, _rng.randf_range(-150, 150))
			if absf(p.x) < Data.MAP + 8 and absf(p.z) < Data.MAP + 8:
				continue
			var r := _rng.randf_range(6.0, 16.0)
			b.cylinder(r, r * 1.15, 0.6, MeshKit.at(p), g.darkened(0.12), 18)
			b.cylinder(r * 0.8, r * 0.8, 0.62, MeshKit.at(p + Vector3(0, 0.02, 0)), g.darkened(0.3), 18)
	var mi := MeshKit.instance(b.build(), false)
	mi.name = "Ground"
	add_child(mi)
	if has_water:
		_build_water(island)


func _build_water(island: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	var pm := PlaneMesh.new()
	pm.size = Vector2(700, 700)
	pm.subdivide_width = 24
	pm.subdivide_depth = 24
	mi.mesh = pm
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 deep : source_color = vec4(0.12, 0.38, 0.62, 1.0);
uniform vec4 shallow : source_color = vec4(0.3, 0.7, 0.85, 1.0);
void vertex() {
	VERTEX.y += sin(VERTEX.x * 0.05 + TIME * 0.9) * 0.25 + cos(VERTEX.z * 0.06 + TIME * 0.7) * 0.25;
}
void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(wp.x * 0.21 + TIME * 1.3) * cos(wp.z * 0.17 - TIME) * 0.5 + 0.5;
	ALBEDO = mix(deep.rgb, shallow.rgb, w * 0.45);
	ROUGHNESS = 0.25;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, water_level, 0.0 if island else -Data.MAP + 6.0 - 350.0)
	add_child(mi)
	if not island:
		# A dock edge and piers so the harbour looks like one.
		var b := MeshKit.Builder.new()
		var wood := Color(0.55, 0.4, 0.28)
		b.box(Vector3(160, 1.4, 2.0), MeshKit.at(Vector3(0, -0.2, -Data.MAP + 6.0)), Color(0.55, 0.55, 0.58))
		for i in 4:
			var x := -45.0 + i * 30.0
			b.box(Vector3(5.0, 0.5, 26.0), MeshKit.at(Vector3(x, 0.15, -Data.MAP - 7.0)), wood)
			for k in 5:
				b.cylinder(0.35, 0.35, 3.0, MeshKit.at(Vector3(x + (2.2 if k % 2 == 0 else -2.2), -1.0, -Data.MAP - 18.0 + k * 5.0)), wood.darkened(0.3), 8)
		# Cranes
		for i in 2:
			var cx := -30.0 + i * 60.0
			var cz := -Data.MAP + 1.0
			var yel := Color(1.0, 0.75, 0.2)
			b.box(Vector3(1.2, 18.0, 1.2), MeshKit.at(Vector3(cx, 9.0, cz)), yel)
			b.box(Vector3(1.0, 1.0, 16.0), MeshKit.at(Vector3(cx, 18.0, cz - 5.0)), yel)
			b.box(Vector3(3.0, 2.0, 3.0), MeshKit.at(Vector3(cx, 17.0, cz + 3.0)), yel.darkened(0.3))
			b.cylinder(0.08, 0.08, 6.0, MeshKit.at(Vector3(cx, 15.0, cz - 11.0)), Color(0.2, 0.2, 0.2), 4)
		add_child(MeshKit.instance(b.build(), false))


# --- Buildings ----------------------------------------------------------------------------------

func _build_buildings() -> void:
	var walls: Array = place_info["walls"]
	var roof: Color = place_info["roof"]
	var hts: Vector2 = place_info["heights"]
	var density: float = place_info.get("density", 1.0)
	for x in CELLS:
		for z in CELLS:
			if is_open_cell(x, z):
				continue
			var block := blocks.size()
			var members: Array[int] = []
			var span := CELL - ROAD - 2.0  # 14 m usable
			var layout := _rng.randi_range(0, 3)
			var rects: Array[Rect2] = []
			match layout:
				0:
					rects.append(Rect2(-span * 0.5, -span * 0.5, span, span))
				1:
					rects.append(Rect2(-span * 0.5, -span * 0.5, span * 0.48, span))
					rects.append(Rect2(span * 0.02, -span * 0.5, span * 0.48, span))
				2:
					rects.append(Rect2(-span * 0.5, -span * 0.5, span, span * 0.48))
					rects.append(Rect2(-span * 0.5, span * 0.02, span, span * 0.48))
				_:
					for qx in 2:
						for qz in 2:
							rects.append(Rect2(-span * 0.5 + qx * span * 0.51, -span * 0.5 + qz * span * 0.51, span * 0.49, span * 0.49))
			for r in rects:
				if _rng.randf() > density and members.size() > 0:
					continue
				var shrink := _rng.randf_range(0.75, 0.95)
				var size := Vector3(r.size.x * shrink, 0.0, r.size.y * shrink)
				var kind := _pick_kind()
				var h := _rng.randf_range(hts.x, hts.y)
				if kind == "house" or kind == "chalet" or kind == "hut" or kind == "shop":
					h = minf(h, hts.x + 2.5)
				if kind == "dome":
					h = minf(size.x, size.z) * 0.55
				if kind == "tank":
					h = clampf(h, 6.0, 10.0)
				size.y = h
				var center := Vector3(x + r.position.x + r.size.x * 0.5, 0.0, z + r.position.y + r.size.y * 0.5)
				var wall: Color = walls[_rng.randi() % walls.size()]
				var rec := {"pos": center, "size": size, "kind": kind, "wall": wall, "roof": roof, "block": block,
					"hp": 100.0, "state": STATE_OK, "fire": false, "weight": maxf(1.0, size.x * size.z * size.y / 400.0),
					"seed": _rng.randi()}
				members.append(buildings.size())
				buildings.append(rec)
				_add_body(rec)
			block_members.append(members)
			var mi := MeshInstance3D.new()
			mi.name = "Block%d" % block
			add_child(mi)
			blocks.append(mi)
			_rebuild_block(block)


func _pick_kind() -> String:
	var r := _rng.randf()
	match place:
		"harbour":
			return "warehouse" if r < 0.4 else ("house" if r < 0.8 else "tower")
		"powerplant":
			return "factory" if r < 0.4 else ("tank" if r < 0.65 else ("house" if r < 0.85 else "tower"))
		"snowy":
			return "chalet" if r < 0.7 else "shop"
		"volcano":
			return "hut" if r < 0.6 else "house"
		"moon":
			return "dome" if r < 0.5 else "tower"
	return "tower" if r < 0.6 else ("shop" if r < 0.8 else "house")


func _add_body(rec: Dictionary) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var s: Vector3 = rec["size"]
	box.size = s
	cs.shape = box
	sb.add_child(cs)
	add_child(sb)
	sb.position = (rec["pos"] as Vector3) + Vector3(0, s.y * 0.5, 0)
	bodies.append(sb)


func _rebuild_block(block: int) -> void:
	var b := MeshKit.Builder.new()
	var members: Array = block_members[block]
	for i in members:
		var rec: Dictionary = buildings[int(i)]
		var m := building_mesh(rec)
		b.add_mesh(m, Transform3D(Basis(), rec["pos"]))
	if b.is_empty():
		blocks[block].mesh = null
		return
	blocks[block].mesh = b.build()


## The cached mesh of a building in its current state (origin at its base centre).
func building_mesh(rec: Dictionary) -> ArrayMesh:
	var s: Vector3 = rec["size"]
	var key := "mt_bld_%s_%s_%d_%.1f_%.1f_%.1f_%s_%s_%d" % [place, rec["kind"], int(rec["state"]), s.x, s.y, s.z,
		(rec["wall"] as Color).to_html(false), "n" if night else "d", int(rec["seed"]) % 97]
	return ResCache.get_or_make(key, func() -> ArrayMesh: return _make_building(rec))


func _make_building(rec: Dictionary) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var s: Vector3 = rec["size"]
	var kind: String = rec["kind"]
	var wall: Color = rec["wall"]
	var roof: Color = rec["roof"]
	var state: int = rec["state"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(rec["seed"])
	var win := Color(1.0, 0.86, 0.45) if night else Color(0.62, 0.82, 0.98)
	if state == STATE_RUBBLE:
		_rubble(b, s, wall, roof, rng)
		return b.build()
	var h := s.y
	if state == STATE_DAMAGED:
		h = s.y * 0.72
		wall = wall.darkened(0.18)
	match kind:
		"tower":
			b.box(Vector3(s.x, h, s.z), MeshKit.at(Vector3(0, h * 0.5, 0)), wall)
			var floors := maxi(1, int(h / 3.0))
			for f in floors:
				var y := 1.6 + f * 3.0
				if y > h - 0.8:
					break
				b.box(Vector3(s.x * 0.84, 1.2, 0.12), MeshKit.at(Vector3(0, y, s.z * 0.5 + 0.04)), win, night)
				b.box(Vector3(s.x * 0.84, 1.2, 0.12), MeshKit.at(Vector3(0, y, -s.z * 0.5 - 0.04)), win, night)
				b.box(Vector3(0.12, 1.2, s.z * 0.84), MeshKit.at(Vector3(s.x * 0.5 + 0.04, y, 0)), win, night)
				b.box(Vector3(0.12, 1.2, s.z * 0.84), MeshKit.at(Vector3(-s.x * 0.5 - 0.04, y, 0)), win, night)
			if state == STATE_OK:
				b.box(Vector3(s.x + 0.4, 0.5, s.z + 0.4), MeshKit.at(Vector3(0, h + 0.25, 0)), roof)
				b.box(Vector3(2.0, 1.2, 2.0), MeshKit.at(Vector3(s.x * 0.2, h + 1.0, -s.z * 0.15)), roof.lightened(0.2))
				if rng.randf() < 0.5:
					b.cylinder(0.12, 0.12, 3.0, MeshKit.at(Vector3(-s.x * 0.25, h + 2.0, s.z * 0.2)), Color(0.8, 0.8, 0.85), 6)
					b.sphere(0.3, MeshKit.at(Vector3(-s.x * 0.25, h + 3.5, s.z * 0.2)), Color(1.0, 0.3, 0.25), 8, true)
		"house", "chalet":
			var wh := h * 0.62
			b.box(Vector3(s.x, wh, s.z), MeshKit.at(Vector3(0, wh * 0.5, 0)), wall)
			var rc := roof if kind == "house" else Color(0.97, 0.98, 1.0)
			if state == STATE_OK:
				var rh := h - wh
				b.wedge(Vector3(s.x + 0.6, rh, s.z * 0.5 + 0.3), MeshKit.at(Vector3(0, wh + rh * 0.5, s.z * 0.25 + 0.15)), rc)
				b.wedge(Vector3(s.x + 0.6, rh, s.z * 0.5 + 0.3), MeshKit.at(Vector3(0, wh + rh * 0.5, -s.z * 0.25 - 0.15), Vector3.ONE, Vector3(0, PI, 0)), rc)
				b.box(Vector3(0.9, 2.0, 0.9), MeshKit.at(Vector3(s.x * 0.28, wh + rh * 0.7, -s.z * 0.15)), wall.darkened(0.3))
			b.box(Vector3(1.4, 2.2, 0.15), MeshKit.at(Vector3(0, 1.1, s.z * 0.5 + 0.05)), Color(0.45, 0.3, 0.2))
			for sx in [-1.0, 1.0]:
				b.box(Vector3(1.3, 1.1, 0.12), MeshKit.at(Vector3(sx * s.x * 0.3, wh * 0.6, s.z * 0.5 + 0.05)), win, night)
				b.box(Vector3(1.3, 1.1, 0.12), MeshKit.at(Vector3(sx * s.x * 0.3, wh * 0.6, -s.z * 0.5 - 0.05)), win, night)
		"shop":
			b.box(Vector3(s.x, h, s.z), MeshKit.at(Vector3(0, h * 0.5, 0)), wall)
			b.box(Vector3(s.x * 0.86, 1.6, 0.14), MeshKit.at(Vector3(0, 1.4, s.z * 0.5 + 0.05)), win, night)
			var stripe := Color(1.0, 0.4, 0.4) if rng.randf() < 0.5 else Color(0.35, 0.65, 1.0)
			b.wedge(Vector3(s.x * 0.9, 0.8, 1.6), MeshKit.at(Vector3(0, 2.8, s.z * 0.5 + 0.8)), stripe)
			if state == STATE_OK:
				b.box(Vector3(s.x * 0.6, 1.0, 0.2), MeshKit.at(Vector3(0, h + 0.4, s.z * 0.45)), Color(1.0, 0.9, 0.4), night)
		"warehouse":
			b.box(Vector3(s.x, h * 0.7, s.z), MeshKit.at(Vector3(0, h * 0.35, 0)), wall)
			if state == STATE_OK:
				b.cylinder(s.x * 0.5, s.x * 0.5, s.z, MeshKit.at(Vector3(0, h * 0.7, 0), Vector3(1.0, 1.0, h * 0.6 / s.x), Vector3(PI * 0.5, 0, 0)), roof, 12)
			b.box(Vector3(s.x * 0.4, h * 0.45, 0.15), MeshKit.at(Vector3(0, h * 0.225, s.z * 0.5 + 0.05)), wall.darkened(0.35))
		"factory":
			b.box(Vector3(s.x, h * 0.6, s.z), MeshKit.at(Vector3(0, h * 0.3, 0)), wall)
			b.box(Vector3(s.x * 0.8, 1.0, 0.12), MeshKit.at(Vector3(0, h * 0.4, s.z * 0.5 + 0.04)), win, night)
			if state == STATE_OK:
				for i in 2:
					var cx := (-0.25 + i * 0.5) * s.x
					b.cylinder(0.8, 1.0, h, MeshKit.at(Vector3(cx, h * 0.5 + h * 0.3, -s.z * 0.2)), Color(0.85, 0.85, 0.88), 10)
					b.cylinder(0.85, 0.85, 0.6, MeshKit.at(Vector3(cx, h * 1.1, -s.z * 0.2)), Color(1.0, 0.35, 0.3), 10)
		"tank":
			var r := minf(s.x, s.z) * 0.45
			b.cylinder(r, r, h, MeshKit.at(Vector3(0, h * 0.5, 0)), wall, 14)
			b.cylinder(r + 0.1, r + 0.1, 0.5, MeshKit.at(Vector3(0, h * 0.3, 0)), wall.darkened(0.2), 14)
			if state == STATE_OK:
				b.dome(r, MeshKit.at(Vector3(0, h, 0)), wall.lightened(0.15), 14)
		"hut":
			var r2 := minf(s.x, s.z) * 0.45
			b.cylinder(r2, r2, h * 0.55, MeshKit.at(Vector3(0, h * 0.275, 0)), wall, 12)
			if state == STATE_OK:
				b.cone(r2 + 1.0, h * 0.6, MeshKit.at(Vector3(0, h * 0.55 + h * 0.3, 0)), Color(0.85, 0.7, 0.4), 12)
			b.box(Vector3(1.2, 2.0, 0.3), MeshKit.at(Vector3(0, 1.0, r2)), Color(0.4, 0.28, 0.2))
		"dome":
			var r3 := minf(s.x, s.z) * 0.48
			if state == STATE_OK:
				b.dome(r3, MeshKit.at(Vector3(0, 0, 0), Vector3(1.0, h / r3, 1.0)), wall, 16)
			else:
				b.cylinder(r3, r3, h * 0.4, MeshKit.at(Vector3(0, h * 0.2, 0)), wall, 16)
			b.torus(r3, 0.25, MeshKit.at(Vector3(0, 0.6, 0)), Color(0.4, 0.85, 1.0), 16, 6, true)
			b.box(Vector3(2.0, 2.4, 1.6), MeshKit.at(Vector3(0, 1.2, r3)), wall.darkened(0.2))
	if state == STATE_DAMAGED:
		# Jagged chunks on the broken top, a scorch band and a few loose bricks around.
		for i in 5:
			var cs := Vector3(rng.randf_range(1.0, 2.6), rng.randf_range(0.8, 2.2), rng.randf_range(1.0, 2.6))
			var cp := Vector3(rng.randf_range(-s.x * 0.4, s.x * 0.4), h + cs.y * 0.3, rng.randf_range(-s.z * 0.4, s.z * 0.4))
			b.box(cs, MeshKit.at(cp, Vector3.ONE, Vector3(rng.randf_range(-0.5, 0.5), rng.randf(), rng.randf_range(-0.5, 0.5))), wall.darkened(0.1))
		b.box(Vector3(s.x + 0.1, 0.6, s.z + 0.1), MeshKit.at(Vector3(0, h - 0.3, 0)), Color(0.25, 0.22, 0.22))
		for i in 4:
			var lp := Vector3(rng.randf_range(-s.x * 0.7, s.x * 0.7), 0.4, rng.randf_range(-s.z * 0.7, s.z * 0.7))
			b.box(Vector3(1.0, 0.8, 1.0), MeshKit.at(lp, Vector3.ONE, Vector3(0, rng.randf() * 3.0, 0.3)), wall.darkened(0.25))
	return b.build()


func _rubble(b: MeshKit.Builder, s: Vector3, wall: Color, roof: Color, rng: RandomNumberGenerator) -> void:
	b.box(Vector3(s.x * 0.9, 0.5, s.z * 0.9), MeshKit.at(Vector3(0, 0.25, 0)), Color(0.45, 0.42, 0.4))
	for i in 12:
		var cs := Vector3(rng.randf_range(1.2, 3.2), rng.randf_range(0.8, 2.0), rng.randf_range(1.2, 3.2))
		var cp := Vector3(rng.randf_range(-s.x * 0.4, s.x * 0.4), rng.randf_range(0.4, 1.6), rng.randf_range(-s.z * 0.4, s.z * 0.4))
		var col := wall.darkened(rng.randf_range(0.0, 0.35)) if i % 3 != 0 else roof
		b.box(cs, MeshKit.at(cp, Vector3.ONE, Vector3(rng.randf_range(-0.6, 0.6), rng.randf() * 3.0, rng.randf_range(-0.6, 0.6))), col)
	# A little "under repair" cone so kids know it can be fixed.
	b.cone(0.5, 1.2, MeshKit.at(Vector3(s.x * 0.45, 0.6, s.z * 0.45)), Color(1.0, 0.55, 0.15), 8)
	b.cylinder(0.42, 0.42, 0.18, MeshKit.at(Vector3(s.x * 0.45, 0.55, s.z * 0.45)), Color(1, 1, 1), 8)


# --- Landmark, shelters, rescue spots -------------------------------------------------------------

func _build_landmark() -> void:
	if protect == "":
		return
	landmark = Node3D.new()
	landmark.name = "Landmark"
	add_child(landmark)
	landmark.position = landmark_pos
	var b := MeshKit.Builder.new()
	var win := Color(1.0, 0.86, 0.45) if night else Color(0.62, 0.82, 0.98)
	match protect:
		"hospital":
			landmark_radius = 8.5
			b.box(Vector3(14, 13, 12), MeshKit.at(Vector3(0, 6.5, 0)), Color(0.96, 0.96, 0.98))
			for f in 3:
				var y := 2.2 + f * 3.6
				b.box(Vector3(12.0, 1.3, 0.12), MeshKit.at(Vector3(0, y, 6.05)), win, night)
				b.box(Vector3(12.0, 1.3, 0.12), MeshKit.at(Vector3(0, y, -6.05)), win, night)
			for side in [1.0, -1.0]:
				b.box(Vector3(1.4, 4.2, 0.2), MeshKit.at(Vector3(side * 7.1, 9.0, 0), Vector3.ONE, Vector3(0, PI * 0.5, 0)), Color(0.95, 0.2, 0.25), true)
				b.box(Vector3(4.2, 1.4, 0.2), MeshKit.at(Vector3(side * 7.1, 9.0, 0), Vector3.ONE, Vector3(0, PI * 0.5, 0)), Color(0.95, 0.2, 0.25), true)
			b.box(Vector3(1.4, 4.2, 0.2), MeshKit.at(Vector3(0, 9.6, 6.15)), Color(0.95, 0.2, 0.25), true)
			b.box(Vector3(4.2, 1.4, 0.2), MeshKit.at(Vector3(0, 9.6, 6.15)), Color(0.95, 0.2, 0.25), true)
			b.cylinder(4.5, 4.5, 0.3, MeshKit.at(Vector3(0, 13.15, 0)), Color(0.3, 0.32, 0.36), 20)
			b.box(Vector3(0.5, 0.05, 3.0), MeshKit.at(Vector3(-0.9, 13.32, 0)), Color(1, 1, 1))
			b.box(Vector3(0.5, 0.05, 3.0), MeshKit.at(Vector3(0.9, 13.32, 0)), Color(1, 1, 1))
			b.box(Vector3(1.4, 0.05, 0.5), MeshKit.at(Vector3(0, 13.32, 0)), Color(1, 1, 1))
		"plant":
			landmark_radius = 10.0
			b.box(Vector3(14, 8, 10), MeshKit.at(Vector3(-2, 4, 2)), Color(0.85, 0.87, 0.9))
			b.box(Vector3(12, 1.2, 0.12), MeshKit.at(Vector3(-2, 4.5, 7.05)), win, night)
			for i in 2:
				var p := Vector3(4.0 + i * 5.5, 0, -4.0)
				b.cylinder(2.6, 3.6, 13.0, MeshKit.at(p + Vector3(0, 6.5, 0)), Color(0.82, 0.82, 0.86), 16)
				b.cylinder(2.7, 2.7, 1.0, MeshKit.at(p + Vector3(0, 10.0, 0)), Color(0.95, 0.3, 0.3), 16)
			b.box(Vector3(3.0, 3.0, 0.3), MeshKit.at(Vector3(-2, 6.5, 7.2)), Color(1.0, 0.85, 0.2), true)
			b.polygon(PackedVector2Array([Vector2(0.2, 1.2), Vector2(-0.6, -0.1), Vector2(0.05, -0.1), Vector2(-0.3, -1.2), Vector2(0.7, 0.2), Vector2(0.05, 0.2)]),
				0.2, MeshKit.at(Vector3(-2, 6.5, 7.4)), Color(0.2, 0.2, 0.25))
			_steam(Vector3(4.0, 13.5, -4.0))
			_steam(Vector3(9.5, 13.5, -4.0))
		"dome":
			landmark_radius = 11.0
			b.dome(11.0, MeshKit.at(Vector3.ZERO, Vector3(1.0, 0.7, 1.0)), Color(0.75, 0.88, 1.0), 20)
			b.torus(11.0, 0.5, MeshKit.at(Vector3(0, 0.5, 0)), Color(0.4, 0.9, 1.0), 20, 6, true)
			for i in 6:
				var a := i * TAU / 6.0
				b.box(Vector3(0.6, 7.0, 0.6), MeshKit.at(Vector3(cos(a) * 8.5, 3.0, sin(a) * 8.5), Vector3.ONE, Vector3(0, -a, 0.55)), Color(0.85, 0.86, 0.9))
			b.cylinder(0.25, 0.25, 6.0, MeshKit.at(Vector3(0, 10.5, 0)), Color(0.9, 0.9, 0.95), 6)
			b.sphere(0.6, MeshKit.at(Vector3(0, 13.6, 0)), Color(1.0, 0.4, 0.3), 10, true)
	landmark.add_child(MeshKit.instance(b.build()))
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = landmark_radius * 0.8
	cyl.height = 12.0
	cs.shape = cyl
	sb.add_child(cs)
	sb.position = Vector3(0, 6, 0)
	landmark.add_child(sb)


func _steam(p: Vector3) -> void:
	var s := CPUParticles3D.new()
	s.amount = 10
	s.lifetime = 3.0
	s.direction = Vector3.UP
	s.spread = 12.0
	s.initial_velocity_min = 2.0
	s.initial_velocity_max = 3.0
	s.gravity = Vector3(0.6, 0.3, 0)
	s.scale_amount_min = 2.0
	s.scale_amount_max = 3.5
	var sm := SphereMesh.new()
	sm.radius = 0.6
	sm.height = 1.2
	sm.radial_segments = 8
	sm.rings = 4
	sm.material = MeshKit.material(Color(0.95, 0.95, 0.98, 0.55))
	s.mesh = sm
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.0))
	s.scale_amount_curve = curve
	landmark.add_child(s)
	s.position = p


func _build_shelters() -> void:
	var b := MeshKit.Builder.new()
	for p in shelters:
		b.cylinder(6.0, 6.0, 0.14, MeshKit.at(p + Vector3(0, 0.2, 0)), Color(0.3, 0.9, 0.45), 24, true)
		b.dome(5.0, MeshKit.at(p + Vector3(0, 0.2, -4.0), Vector3(1.0, 0.7, 1.0)), Color(0.45, 0.6, 0.4), 16)
		b.box(Vector3(3.2, 2.8, 1.0), MeshKit.at(p + Vector3(0, 1.4, 0.6)), Color(0.4, 0.42, 0.45))
		b.box(Vector3(2.4, 2.3, 0.2), MeshKit.at(p + Vector3(0, 1.2, 1.15)), Color(0.25, 0.75, 0.4), true)
	add_child(MeshKit.instance(b.build()))
	for p in shelters:
		var pillar := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 2.2
		cm.bottom_radius = 3.2
		cm.height = 40.0
		cm.radial_segments = 16
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		pillar.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(0.25, 0.9, 0.4, 0.22)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		pillar.material_override = mat
		pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pillar.position = p + Vector3(0, 20.0, 0)
		add_child(pillar)
		var sign := Label3D.new()
		sign.text = "SHELTER"
		sign.font_size = 96
		sign.pixel_size = 0.02
		sign.outline_size = 24
		sign.modulate = Color(0.6, 1.0, 0.7)
		sign.position = p + Vector3(0, 4.6, 1.3)
		add_child(sign)


func _pick_rescue_spots() -> void:
	var cand: Array[Vector3] = []
	for rec in buildings:
		var p: Vector3 = rec["pos"]
		var s: Vector3 = rec["size"]
		if p.z > 40.0:
			continue
		# Only on the street side of a block (the south edge, next to an east-west road), so a rescue
		# truck can always drive right up to them.
		var c := p + Vector3(0, 0, s.z * 0.5 + 2.2)
		var cz := CELLS[0]
		for cv in CELLS:
			if absf(p.z - cv) < absf(p.z - cz):
				cz = cv
		if c.z < cz + 6.0 or push_out(c, 1.0).distance_to(c) > 0.01:
			continue
		cand.append(c)
	for i in cand.size():
		var j := _rng.randi_range(i, cand.size() - 1)
		var t := cand[i]
		cand[i] = cand[j]
		cand[j] = t
	rescue_spots = []
	for c in cand:
		var ok := true
		for r in rescue_spots:
			if r.distance_to(c) < 22.0:
				ok = false
		if ok:
			rescue_spots.append(c)
		if rescue_spots.size() >= 8:
			break


# --- Props: trees, lamps, cars, backdrop -------------------------------------------------------------

func _build_props() -> void:
	var tree_kind: String = place_info.get("trees", "tree")
	if tree_kind != "":
		var xfs: Array = []
		for x in CELLS:
			for z in CELLS:
				var what: String = _open.get(_key(x, z), "block")
				if what == "plaza" or what == "start":
					for k in 8:
						var a := k * TAU / 8.0 + 0.3
						var r := 9.0 + (k % 2) * 2.0
						xfs.append(_tree_xf(Vector3(x + cos(a) * r, 0, z + sin(a) * r)))
				elif what == "block" and _rng.randf() < 0.5:
					var cx := x + (_rng.randf_range(-7.5, 7.5))
					xfs.append(_tree_xf(Vector3(cx, 0, z + (7.6 if _rng.randf() < 0.5 else -7.6))))
		for i in 30:
			var a2 := _rng.randf() * TAU
			var r2 := _rng.randf_range(Data.MAP + 10.0, Data.MAP + 40.0)
			var p := Vector3(cos(a2) * r2, 0, sin(a2) * r2)
			if has_water and (p.z < -Data.MAP + 4.0 or String(place_info.get("water", "")) == "all"):
				continue
			xfs.append(_tree_xf(p))
		var mmi := MeshKit.scatter(MeshKit.prop(tree_kind), xfs, PackedColorArray(), PackedColorArray(), false)
		mmi.name = "Trees"
		add_child(mmi)
		trees_mm = mmi.multimesh
		for x in xfs:
			tree_xf.append(x)
		tree_down.resize(xfs.size())
	# Lamp posts at the crossings.
	var lamps: Array = []
	for i in 6:
		for k in 6:
			var c := Vector3(-65.0 + i * CELL, 0, -65.0 + k * CELL)
			if has_water and c.z < -Data.MAP + 8.0:
				continue
			lamps.append(Transform3D(Basis().scaled(Vector3.ONE * 2.2), c + Vector3(5.6, 0, 5.6)))
	var lmi := MeshKit.scatter(MeshKit.prop("lamp_post"), lamps, PackedColorArray(), PackedColorArray(), false)
	lmi.name = "Lamps"
	add_child(lmi)
	_build_cars()
	if place == "snowy" or place == "volcano" or place == "moon":
		for i in 6:
			var a3 := i * TAU / 6.0 + 0.4
			boulders.append(Vector3(cos(a3) * 38.0, 0, sin(a3) * 38.0))


func _tree_xf(p: Vector3) -> Transform3D:
	var sc := _rng.randf_range(1.7, 2.4)
	return Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * sc), p)


func _car_mesh() -> ArrayMesh:
	return ResCache.get_or_make("mt_car_v1", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		b.rounded_box(Vector3(1.7, 0.8, 3.6), 0.25, MeshKit.at(Vector3(0, 0.75, 0)), Color(1, 1, 1))
		b.rounded_box(Vector3(1.5, 0.7, 1.9), 0.25, MeshKit.at(Vector3(0, 1.4, -0.2)), Color(0.85, 0.9, 1.0))
		for sx in [-0.85, 0.85]:
			for sz in [-1.15, 1.15]:
				b.cylinder(0.38, 0.38, 0.3, MeshKit.at(Vector3(sx, 0.38, sz), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(0.12, 0.12, 0.14), 10)
		b.box(Vector3(1.2, 0.2, 0.08), MeshKit.at(Vector3(0, 0.85, 1.81)), Color(1.0, 0.95, 0.7), true)
		return b.build())


func _build_cars() -> void:
	var n: int = place_info.get("cars", 12)
	var xfs: Array = []
	var cols := PackedColorArray()
	var palette := [Color(1.0, 0.35, 0.3), Color(0.3, 0.6, 1.0), Color(1.0, 0.85, 0.3), Color(0.4, 0.85, 0.5), Color(0.95, 0.95, 0.95), Color(0.8, 0.5, 1.0)]
	for i in n:
		var axis := _rng.randi_range(0, 1)
		var line := -52.0 + _rng.randi_range(0, 5) * CELL - 13.0
		var lane := 2.4 if _rng.randf() < 0.5 else -2.4
		var t := _rng.randf_range(-60.0, 60.0)
		var pos := Vector3(t, 0, line + lane) if axis == 0 else Vector3(line + lane, 0, t)
		if has_water and pos.z < -Data.MAP + 8.0:
			pos.z = -Data.MAP + 12.0
		var speed := _rng.randf_range(3.0, 6.0) * (1.0 if lane > 0 else -1.0) if _rng.randf() < 0.6 else 0.0
		cars.append({"pos": pos, "axis": axis, "speed": speed, "crushed": 0.0})
		xfs.append(_car_xf(cars[i]))
		cols.append(palette[i % palette.size()])
	var mmi := MeshKit.scatter(_car_mesh(), xfs, cols, PackedColorArray(), false)
	mmi.name = "Cars"
	add_child(mmi)
	cars_mm = mmi.multimesh


func _car_xf(c: Dictionary) -> Transform3D:
	var yaw := 0.0
	var spd: float = c["speed"]
	if int(c["axis"]) == 0:
		yaw = PI * 0.5 if spd >= 0.0 else -PI * 0.5
	else:
		yaw = 0.0 if spd >= 0.0 else PI
	var squash: float = c["crushed"]
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1.0 + squash * 0.3, 1.0 - squash * 0.75, 1.0 + squash * 0.1)), c["pos"])


func _build_backdrop() -> void:
	var b := MeshKit.Builder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 5
	match place:
		"downtown", "powerplant":
			for i in 40:
				var a := i * TAU / 40.0 + rng.randf() * 0.1
				var r := rng.randf_range(130.0, 170.0)
				var h := rng.randf_range(15.0, 55.0)
				var w := rng.randf_range(10.0, 20.0)
				var col := Color(0.55, 0.62, 0.75).lerp(Color(0.75, 0.8, 0.88), rng.randf())
				if night:
					col = Color(0.12, 0.14, 0.22)
				b.box(Vector3(w, h, w), MeshKit.at(Vector3(cos(a) * r, h * 0.5, sin(a) * r), Vector3.ONE, Vector3(0, -a, 0)), col)
				if night:
					for k in int(h / 8.0):
						b.box(Vector3(w * 0.6, 0.8, 0.2), MeshKit.at(Vector3(cos(a) * (r - w * 0.5 - 0.2), 4.0 + k * 8.0, sin(a) * (r - w * 0.5 - 0.2)), Vector3.ONE, Vector3(0, -a + PI * 0.5, 0)), Color(1.0, 0.85, 0.45), true)
		"snowy":
			for i in 18:
				var a2 := i * TAU / 18.0 + rng.randf() * 0.2
				var r2 := rng.randf_range(140.0, 190.0)
				var h2 := rng.randf_range(45.0, 90.0)
				var p := Vector3(cos(a2) * r2, 0, sin(a2) * r2)
				b.cone(h2 * 0.75, h2, MeshKit.at(p + Vector3(0, h2 * 0.5, 0)), Color(0.55, 0.6, 0.7), 10)
				b.cone(h2 * 0.32, h2 * 0.43, MeshKit.at(p + Vector3(0, h2 * 0.785, 0)), Color(0.97, 0.98, 1.0), 10)
		"volcano":
			var vp := Vector3(0, 0, -150.0)
			b.cone(80.0, 70.0, MeshKit.at(vp + Vector3(0, 35.0, 0)), Color(0.42, 0.33, 0.3), 18)
			b.cylinder(16.0, 16.0, 2.0, MeshKit.at(vp + Vector3(0, 61.0, 0)), Color(1.0, 0.45, 0.15), 14, true)
			for i in 8:
				var a3 := rng.randf() * TAU
				var r3 := rng.randf_range(160.0, 260.0)
				var h3 := rng.randf_range(8.0, 25.0)
				b.dome(h3 * 2.0, MeshKit.at(Vector3(cos(a3) * r3, -1.0, sin(a3) * r3), Vector3(1.0, 0.5, 1.0)), Color(0.4, 0.6, 0.35), 12)
		"harbour":
			for i in 6:
				var x := -160.0 + i * 64.0
				b.dome(rng.randf_range(20, 35), MeshKit.at(Vector3(x, -1.0, -260.0), Vector3(1.0, 0.4, 0.6)), Color(0.45, 0.58, 0.48), 12)
			b.cylinder(3.0, 4.0, 22.0, MeshKit.at(Vector3(90.0, 11.0, -140.0)), Color(0.95, 0.95, 0.95), 12)
			b.cylinder(4.1, 4.1, 3.0, MeshKit.at(Vector3(90.0, 6.0, -140.0)), Color(0.95, 0.3, 0.3), 12)
			b.sphere(2.4, MeshKit.at(Vector3(90.0, 23.5, -140.0)), Color(1.0, 0.95, 0.6), 10, true)
		"moon":
			for i in 14:
				var a4 := i * TAU / 14.0 + rng.randf() * 0.2
				var r4 := rng.randf_range(150.0, 210.0)
				var h4 := rng.randf_range(15.0, 40.0)
				b.dome(h4 * 2.2, MeshKit.at(Vector3(cos(a4) * r4, -2.0, sin(a4) * r4), Vector3(1.0, 0.45, 1.0)), Color(0.5, 0.5, 0.56), 12)
			for i in 5:
				var p5 := Vector3(-40.0 + i * 20.0, 0, 66.0)
				b.cylinder(0.3, 0.3, 12.0, MeshKit.at(p5 + Vector3(0, 6, 0)), Color(0.9, 0.9, 0.95), 6)
				b.dome(3.0, MeshKit.at(p5 + Vector3(0, 12.0, 0), Vector3(1.0, 0.35, 1.0), Vector3(0.6, 0, 0)), Color(0.85, 0.87, 0.92), 12)
	if not b.is_empty():
		var mi := MeshKit.instance(b.build(), false)
		mi.name = "Backdrop"
		add_child(mi)


# --- Gameplay queries (all machines) -----------------------------------------------------------------

## Push a circle (centre p, radius r on XZ) out of every standing building and the landmark.
## Rubble only blocks when `rubble_blocks`.
func push_out(p: Vector3, r: float, rubble_blocks: bool = false) -> Vector3:
	for rec in buildings:
		var st: int = rec["state"]
		if st == STATE_RUBBLE and not rubble_blocks:
			continue
		var c: Vector3 = rec["pos"]
		var hs: Vector3 = (rec["size"] as Vector3) * 0.5
		var dx := p.x - c.x
		var dz := p.z - c.z
		if absf(dx) > hs.x + r or absf(dz) > hs.z + r:
			continue
		var qx := clampf(dx, -hs.x, hs.x)
		var qz := clampf(dz, -hs.z, hs.z)
		var ox := dx - qx
		var oz := dz - qz
		var d := sqrt(ox * ox + oz * oz)
		if d >= r:
			continue
		if d < 0.0001:
			# Inside: leave along the shortest axis.
			var px := hs.x + r - absf(dx)
			var pz := hs.z + r - absf(dz)
			if px < pz:
				p.x += signf(dx if dx != 0.0 else 1.0) * px
			else:
				p.z += signf(dz if dz != 0.0 else 1.0) * pz
		else:
			p.x += ox / d * (r - d)
			p.z += oz / d * (r - d)
	if landmark != null:
		var to := Vector2(p.x - landmark_pos.x, p.z - landmark_pos.z)
		var lr := landmark_radius * 0.8 + r
		if to.length() < lr:
			var n := to.normalized() if to.length() > 0.001 else Vector2(0, 1)
			p.x = landmark_pos.x + n.x * lr
			p.z = landmark_pos.z + n.y * lr
	return p


## Nearest standing building hit by a ray (distance along `dir`, INF = none). dir must be normalised.
func ray_hit(from: Vector3, dir: Vector3, max_d: float) -> float:
	var best := INF
	for rec in buildings:
		if int(rec["state"]) == STATE_RUBBLE:
			continue
		var c: Vector3 = rec["pos"]
		var s: Vector3 = rec["size"]
		var h := s.y * (0.72 if int(rec["state"]) == STATE_DAMAGED else 1.0)
		var t := _ray_box(from, dir, Vector3(c.x - s.x * 0.5, 0.0, c.z - s.z * 0.5), Vector3(c.x + s.x * 0.5, h, c.z + s.z * 0.5))
		if t < best and t <= max_d:
			best = t
	return best


static func _ray_box(o: Vector3, d: Vector3, lo: Vector3, hi: Vector3) -> float:
	var tmin := -INF
	var tmax := INF
	for k in 3:
		if absf(d[k]) < 0.000001:
			if o[k] < lo[k] or o[k] > hi[k]:
				return INF
		else:
			var t1 := (lo[k] - o[k]) / d[k]
			var t2 := (hi[k] - o[k]) / d[k]
			if t1 > t2:
				var tt := t1
				t1 = t2
				t2 = tt
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return INF
	if tmax < 0.0:
		return INF
	return maxf(tmin, 0.0)


## Index of the standing building whose footprint is nearest to p (within max_d), or -1.
func nearest_building(p: Vector3, max_d: float = 1e9, include_damaged: bool = true) -> int:
	var best := -1
	var bd := max_d
	for i in buildings.size():
		var rec: Dictionary = buildings[i]
		var st: int = rec["state"]
		if st == STATE_RUBBLE or (st == STATE_DAMAGED and not include_damaged):
			continue
		var d := footprint_distance(i, p)
		if d < bd:
			bd = d
			best = i
	return best


## Distance on XZ from p to building i's footprint (0 inside).
func footprint_distance(i: int, p: Vector3) -> float:
	var rec: Dictionary = buildings[i]
	var c: Vector3 = rec["pos"]
	var hs: Vector3 = (rec["size"] as Vector3) * 0.5
	var dx := maxf(absf(p.x - c.x) - hs.x, 0.0)
	var dz := maxf(absf(p.z - c.z) - hs.z, 0.0)
	return sqrt(dx * dx + dz * dz)


## Top-centre of a building (for fires, popups, aiming).
func building_top(i: int) -> Vector3:
	var rec: Dictionary = buildings[i]
	var s: Vector3 = rec["size"]
	var h := s.y * (0.72 if int(rec["state"]) == STATE_DAMAGED else (0.25 if int(rec["state"]) == STATE_RUBBLE else 1.0))
	return (rec["pos"] as Vector3) + Vector3(0, h, 0)


# --- Damage (host decides; returns true if the visible state changed) --------------------------------

func damage_building(i: int, amount: float) -> bool:
	if i < 0 or i >= buildings.size():
		return false
	var rec: Dictionary = buildings[i]
	rec["hp"] = clampf(float(rec["hp"]) - amount, 0.0, 100.0)
	return _update_state(i)


func repair_building(i: int, amount: float) -> bool:
	if i < 0 or i >= buildings.size():
		return false
	var rec: Dictionary = buildings[i]
	rec["hp"] = clampf(float(rec["hp"]) + amount, 0.0, 100.0)
	return _update_state(i)


func set_fire(i: int, on: bool) -> bool:
	if i < 0 or i >= buildings.size():
		return false
	var rec: Dictionary = buildings[i]
	if int(rec["state"]) == STATE_RUBBLE:
		on = false
	if bool(rec["fire"]) == on:
		return false
	rec["fire"] = on
	_update_fire_fx(i)
	return true


func _update_state(i: int) -> bool:
	var rec: Dictionary = buildings[i]
	var hp: float = rec["hp"]
	var old: int = rec["state"]
	var st := old
	# Hysteresis so repairs and damage don't flicker between states.
	if hp <= 0.0:
		st = STATE_RUBBLE
	elif old == STATE_RUBBLE and hp >= 35.0:
		st = STATE_DAMAGED
	elif old == STATE_OK and hp < 60.0:
		st = STATE_DAMAGED
	elif old == STATE_DAMAGED and hp >= 85.0:
		st = STATE_OK
	if st == old:
		return false
	_set_state(i, st)
	if st == STATE_RUBBLE:
		set_fire(i, false)
	return true


func _set_state(i: int, st: int) -> void:
	var rec: Dictionary = buildings[i]
	rec["state"] = st
	_rebuild_block(int(rec["block"]))
	var sb := bodies[i]
	var s: Vector3 = rec["size"]
	var h := s.y * (0.72 if st == STATE_DAMAGED else (0.15 if st == STATE_RUBBLE else 1.0))
	var shape := (sb.get_child(0) as CollisionShape3D).shape as BoxShape3D
	shape.size = Vector3(s.x, maxf(h, 0.3), s.z)
	sb.position.y = maxf(h, 0.3) * 0.5
	sb.collision_layer = 0 if st == STATE_RUBBLE else 1


## Host: one byte per building (state | fire << 2) for the net store.
func pack_states() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(buildings.size())
	for i in buildings.size():
		var rec: Dictionary = buildings[i]
		out[i] = int(rec["state"]) | (4 if bool(rec["fire"]) else 0)
	return out


## Every machine: show these states. Returns the indices that changed (for debris / sounds).
func apply_states(bytes: PackedByteArray) -> Array[int]:
	var changed: Array[int] = []
	var dirty := {}
	for i in mini(bytes.size(), buildings.size()):
		var st := bytes[i] & 3
		var fire := (bytes[i] & 4) != 0
		var rec: Dictionary = buildings[i]
		if int(rec["state"]) != st:
			rec["state"] = st
			rec["hp"] = 100.0 if st == STATE_OK else (50.0 if st == STATE_DAMAGED else 0.0)
			dirty[int(rec["block"])] = true
			changed.append(i)
			var sb := bodies[i]
			var s: Vector3 = rec["size"]
			var h := s.y * (0.72 if st == STATE_DAMAGED else (0.15 if st == STATE_RUBBLE else 1.0))
			var shape := (sb.get_child(0) as CollisionShape3D).shape as BoxShape3D
			shape.size = Vector3(s.x, maxf(h, 0.3), s.z)
			sb.position.y = maxf(h, 0.3) * 0.5
			sb.collision_layer = 0 if st == STATE_RUBBLE else 1
		if bool(rec["fire"]) != fire:
			rec["fire"] = fire
			_update_fire_fx(i)
	for blk in dirty:
		_rebuild_block(int(blk))
	return changed


## 0..100: how broken the city is (weighted by building size).
func damage_percent() -> float:
	var total := 0.0
	var lost := 0.0
	for rec in buildings:
		var w: float = rec["weight"]
		total += w * 100.0
		lost += w * (100.0 - float(rec["hp"]))
	return 0.0 if total <= 0.0 else lost / total * 100.0


func burning() -> Array[int]:
	var out: Array[int] = []
	for i in buildings.size():
		if bool(buildings[i]["fire"]):
			out.append(i)
	return out


func _update_fire_fx(i: int) -> void:
	var on: bool = buildings[i]["fire"]
	if on and not _fires.has(i):
		var f := _make_fire()
		add_child(f)
		f.position = building_top(i)
		_fires[i] = f
	elif not on and _fires.has(i):
		var f2: Node3D = _fires[i]
		_fires.erase(i)
		if is_instance_valid(f2):
			var p := f2 as CPUParticles3D
			if p != null:
				p.emitting = false
			get_tree().create_timer(1.6).timeout.connect(f2.queue_free)


func _make_fire() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 18
	p.lifetime = 1.0
	p.direction = Vector3.UP
	p.spread = 20.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, 1.5, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 2.2
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.0))
	p.scale_amount_curve = curve
	var sm := SphereMesh.new()
	sm.radius = 0.7
	sm.height = 1.4
	sm.radial_segments = 8
	sm.rings = 4
	sm.material = MeshKit.material(Color(1.0, 0.55, 0.15), 2.0)
	p.mesh = sm
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.4))
	grad.set_color(1, Color(1.0, 0.25, 0.1))
	p.color_ramp = grad
	return p


# --- Cosmetic per-frame: cars drive, things get squashed ----------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if cars_mm == null:
		return
	for i in cars.size():
		var c: Dictionary = cars[i]
		var spd: float = c["speed"]
		if spd == 0.0 or float(c["crushed"]) > 0.0:
			continue
		var p: Vector3 = c["pos"]
		if int(c["axis"]) == 0:
			p.x += spd * delta
			if absf(p.x) > Data.MAP + 6.0:
				p.x = -signf(p.x) * (Data.MAP + 5.0)
		else:
			p.z += spd * delta
			if absf(p.z) > Data.MAP + 6.0:
				p.z = -signf(p.z) * (Data.MAP + 5.0)
				if has_water and p.z < -Data.MAP + 8.0:
					p.z = -Data.MAP + 12.0
		c["pos"] = p
		cars_mm.set_instance_transform(i, _car_xf(c))


## A giant foot came down at p: flatten cars and trees within r (cosmetic, every machine).
## Returns how many things got squashed.
func squash_at(p: Vector3, r: float) -> int:
	var n := 0
	if cars_mm != null:
		for i in cars.size():
			var c: Dictionary = cars[i]
			if float(c["crushed"]) > 0.0:
				continue
			var cp: Vector3 = c["pos"]
			if Vector2(cp.x - p.x, cp.z - p.z).length() < r:
				c["crushed"] = 1.0
				cars_mm.set_instance_transform(i, _car_xf(c))
				n += 1
	if trees_mm != null:
		for i in tree_xf.size():
			if tree_down[i] != 0:
				continue
			var t: Transform3D = tree_xf[i]
			if Vector2(t.origin.x - p.x, t.origin.z - p.z).length() < r:
				tree_down[i] = 1
				var away := Vector3(t.origin.x - p.x, 0, t.origin.z - p.z).normalized()
				var axis := Vector3(away.z, 0, -away.x)
				if axis.length() < 0.1:
					axis = Vector3.RIGHT
				var bent := Transform3D(Basis(axis.normalized(), 1.3) * t.basis, t.origin)
				trees_mm.set_instance_transform(i, bent)
				n += 1
	return n
