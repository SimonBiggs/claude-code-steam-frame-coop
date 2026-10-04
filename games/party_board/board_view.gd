extends Node3D
## The board's look: Party Island as a diorama (terrain, beach, Candy Forest, the volcano with lava
## and smoke, the river with bridges, the lagoon pier), the spaces and stepping-stone paths, shops,
## the START arch, the STAR (moves between star spots) and the branch arrows shown at junctions.
## Everything static is baked with core/mesh_kit.gd (one mesh for the island, one for the spaces and
## paths, MultiMeshes for the props), so the whole board costs ~20 draw calls.
## Lives under main's `stage` node (board units; the stage scales it for the VR table or the TV).

const BD := preload("res://games/party_board/board_data.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const UiKit := preload("res://core/ui_kit.gd")

const WATER_SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled;
uniform vec3 deep : source_color = vec3(0.08, 0.36, 0.72);
uniform vec3 shallow : source_color = vec3(0.24, 0.78, 0.86);
uniform float island_r = 13.5;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	float d = length(lp.xz);
	vec3 c = mix(shallow, deep, smoothstep(island_r - 2.0, island_r + 7.0, d));
	float w = sin(lp.x * 1.6 + TIME * 1.2) * sin(lp.z * 1.25 - TIME * 0.9);
	float w2 = sin(lp.x * 0.7 - lp.z * 0.9 + TIME * 0.7);
	c += vec3(0.07) * smoothstep(0.55, 1.0, w) + vec3(0.03) * w2;
	ALBEDO = c;
	ROUGHNESS = 0.18;
	SPECULAR = 0.55;
}
"""

var data: BD
var vr_table := false
var star_node: Node3D
var star_space := -1
var arrows: Array[Node3D] = []
var arrow_targets: Array = []
var arrow_sel := -1
var sails: Node3D
var _t := 0.0
var _star_from := Vector3.ZERO
var _star_to := Vector3.ZERO
var _star_move := 1.0
var _flashes: Array = []  # [MeshInstance3D, time left]


## Build everything. vr: the island sits in a water dish on the VR player's table (no ocean to
## the horizon).
func build(p_data: BD, vr: bool) -> void:
	data = p_data
	vr_table = vr
	add_child(MeshKit.instance(ResCache.get_or_make("pb_island_v3", _island_mesh)))
	var spaces := MeshKit.instance(ResCache.get_or_make("pb_spaces_v3", _spaces_mesh), false)
	add_child(spaces)
	_build_water(vr)
	_build_props()
	_build_landmarks()
	_build_star()


# --- Terrain --------------------------------------------------------------------------------------

func _island_mesh() -> Resource:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 72
	var half := 16.0
	var step := half * 2.0 / n
	var hs := PackedFloat32Array()
	hs.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var x := -half + i * step
			var z := -half + j * step
			hs[j * (n + 1) + i] = BD.height(x, z)
	for j in n:
		for i in n:
			var h00 := hs[j * (n + 1) + i]
			var h10 := hs[j * (n + 1) + i + 1]
			var h01 := hs[(j + 1) * (n + 1) + i]
			var h11 := hs[(j + 1) * (n + 1) + i + 1]
			if maxf(maxf(h00, h10), maxf(h01, h11)) < -1.0:
				continue  # deep water: nothing to see
			var x0 := -half + i * step
			var z0 := -half + j * step
			var p00 := Vector3(x0, h00, z0)
			var p10 := Vector3(x0 + step, h10, z0)
			var p01 := Vector3(x0, h01, z0 + step)
			var p11 := Vector3(x0 + step, h11, z0 + step)
			_tri(st, p00, p10, p11)
			_tri(st, p00, p11, p01)
	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, MeshKit.vertex_material())
	return m


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for p: Vector3 in [a, b, c]:
		st.set_color(BD.ground_color(p.x, p.z, p.y))
		st.add_vertex(p)


# --- Spaces, paths, bridges -----------------------------------------------------------------------

func _spaces_mesh() -> Resource:
	var b := MeshKit.Builder.new()
	var stone := Color(0.93, 0.86, 0.7)
	var wood := Color(0.62, 0.42, 0.26)
	for s in data.spaces:
		var p: Vector3 = s["pos"]
		var type := String(s["type"])
		var cols: Array = BD.TYPE_COLORS[type]
		var tile: Color = cols[0]
		var emb: Color = cols[1]
		b.cylinder(0.84, 0.9, 0.24, MeshKit.at(p + Vector3(0, 0.06, 0)), tile.darkened(0.35), 20)
		b.cylinder(0.74, 0.76, 0.08, MeshKit.at(p + Vector3(0, 0.2, 0)), tile, 20)
		b.torus(0.76, 0.05, MeshKit.at(p + Vector3(0, 0.22, 0)), Color(1, 1, 1).lerp(tile, 0.3), 20, 6)
		var top := p + Vector3(0, 0.25, 0)
		match type:
			"blue":
				b.box(Vector3(0.62, 0.05, 0.16), MeshKit.at(top), emb)
				b.box(Vector3(0.16, 0.05, 0.62), MeshKit.at(top), emb)
			"red":
				b.box(Vector3(0.62, 0.05, 0.17), MeshKit.at(top), emb)
			"event":
				b.star(4, 0.4, 0.14, 0.05, MeshKit.at(top, Vector3.ONE, Vector3(-PI * 0.5, 0.0, 0.0)), emb)
			"shop":
				b.cylinder(0.3, 0.3, 0.06, MeshKit.at(top), Color(1.0, 0.86, 0.3), 16)
				b.torus(0.21, 0.035, MeshKit.at(top + Vector3(0, 0.03, 0)), Color(0.85, 0.6, 0.15), 14, 5)
			"duel":
				b.box(Vector3(0.7, 0.05, 0.13), MeshKit.at(top, Vector3.ONE, Vector3(0, PI * 0.25, 0)), emb)
				b.box(Vector3(0.7, 0.05, 0.13), MeshKit.at(top, Vector3.ONE, Vector3(0, -PI * 0.25, 0)), emb)
			"start":
				var nx: Vector3 = data.pos(int((s["next"] as Array)[0]))
				var dir := Vector3(nx.x - p.x, 0, nx.z - p.z).normalized()
				var yaw := atan2(dir.x, dir.z)
				b.wedge(Vector3(0.5, 0.06, 0.55), MeshKit.at(top + dir * 0.05, Vector3.ONE, Vector3(0, yaw + PI, 0)), emb)
		if p.y - BD.height(p.x, p.z) > 0.25:
			for k in 4:  # a little pier under spaces over water
				var a := k * TAU / 4.0 + 0.6
				var q := p + Vector3(cos(a) * 0.55, 0, sin(a) * 0.55)
				b.cylinder(0.08, 0.08, 1.4, MeshKit.at(Vector3(q.x, p.y - 0.62, q.z)), wood, 6)
	# Paths: stepping stones on land, plank bridges over water.
	for s in data.spaces:
		var a: Vector3 = s["pos"]
		for nid in s["next"]:
			var c: Vector3 = data.pos(int(nid))
			var flat := Vector3(c.x - a.x, 0, c.z - a.z)
			var len := flat.length()
			var dir := flat / len
			var yaw := atan2(dir.x, dir.z)
			var k := 0.95
			while k < len - 0.95:
				var q := a + dir * k
				var g := BD.height(q.x, q.z)
				if g < 0.28:
					var y := lerpf(a.y, c.y, k / len) + 0.05
					b.box(Vector3(1.05, 0.08, 0.3), MeshKit.at(Vector3(q.x, y, q.z), Vector3.ONE, Vector3(0, yaw, 0)), wood.lightened(0.1))
					var side := Vector3(dir.z, 0, -dir.x) * 0.52
					b.cylinder(0.05, 0.05, 0.42, MeshKit.at(Vector3(q.x, y + 0.2, q.z) + side), wood, 5)
					b.cylinder(0.05, 0.05, 0.42, MeshKit.at(Vector3(q.x, y + 0.2, q.z) - side), wood, 5)
					b.cylinder(0.06, 0.06, 1.3, MeshKit.at(Vector3(q.x, y - 0.6, q.z)), wood.darkened(0.2), 5)
					k += 0.34
				else:
					b.cylinder(0.2, 0.22, 0.07, MeshKit.at(Vector3(q.x, g + 0.03, q.z)), stone.darkened(fmod(k * 3.7, 1.0) * 0.12), 8)
					k += 0.5
	return b.build()


# --- Water ----------------------------------------------------------------------------------------

func _build_water(vr: bool) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = ResCache.get_or_make("pb_water_shader", func() -> Resource:
		var sh := Shader.new()
		sh.code = WATER_SHADER
		return sh)
	var water := MeshInstance3D.new()
	water.name = "Water"
	if vr:
		var disc := CylinderMesh.new()
		disc.top_radius = 16.6
		disc.bottom_radius = 16.6
		disc.height = 0.02
		disc.radial_segments = 48
		water.mesh = disc
		# The dish: a wooden rim and a base, sitting on the VR player's table.
		var b := MeshKit.Builder.new()
		b.torus(16.75, 0.42, MeshKit.at(Vector3(0, 0.0, 0)), Color(0.55, 0.36, 0.22), 56, 8)
		b.cylinder(17.0, 17.0, 1.2, MeshKit.at(Vector3(0, -0.62, 0)), Color(0.5, 0.33, 0.2), 48)
		add_child(MeshKit.instance(b.build(), false))
	else:
		var plane := PlaneMesh.new()
		plane.size = Vector2(900, 900)
		water.mesh = plane
	water.material_override = mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


# --- Props ----------------------------------------------------------------------------------------

func _build_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var spots := {"palm": [], "tree": [], "pine": [], "bush": [], "rock": [], "flower": [], "lolly": [], "cane": [],
		"gumdrop": [], "parasol": [], "mushroom": []}
	for k in 900:
		var p := Vector2(rng.randf_range(-13.5, 13.5), rng.randf_range(-13.5, 13.5))
		var h := BD.height(p.x, p.y)
		if h < 0.3 or not _clear(p, 1.25, 0.75):
			continue
		var zone := BD.zone_at(p)
		var on_cone := p.distance_to(BD.VOLCANO) < BD.VOLCANO_R * 0.9
		var kind := ""
		var r := rng.randf()
		match zone:
			"beach":
				var coast := p.length() > 10.6
				kind = ("palm" if r < 0.55 else ("parasol" if r < 0.7 else "rock")) if coast else ("palm" if r < 0.3 else ("bush" if r < 0.6 else "flower"))
			"candy":
				kind = "lolly" if r < 0.35 else ("cane" if r < 0.6 else ("gumdrop" if r < 0.9 else "mushroom"))
			"volcano":
				if on_cone:
					kind = "rock" if r < 0.5 else ""
				else:
					kind = "pine" if r < 0.45 else ("rock" if r < 0.8 else "bush")
			"meadow":
				kind = "tree" if r < 0.35 else ("flower" if r < 0.75 else "bush")
			"lagoon":
				kind = "flower" if r < 0.5 else ("bush" if r < 0.8 else "palm")
		if kind == "":
			continue
		var list: Array = spots[kind]
		if list.size() > 60:
			continue
		list.append(Vector3(p.x, h - 0.02, p.y))
	var meshes := {
		"palm": [MeshKit.prop("palm"), 0.62], "tree": [MeshKit.prop("tree"), 0.62], "pine": [MeshKit.prop("pine"), 0.6],
		"bush": [MeshKit.prop("bush"), 0.8], "rock": [MeshKit.prop("rock"), 0.8], "flower": [MeshKit.prop("flower"), 1.0],
		"mushroom": [MeshKit.prop("mushroom"), 1.4], "lolly": [ResCache.get_or_make("pb_lolly_v1", _lolly_mesh), 1.0],
		"cane": [ResCache.get_or_make("pb_cane_v1", _cane_mesh), 1.0], "gumdrop": [ResCache.get_or_make("pb_gumdrop_v1", _gumdrop_mesh), 1.0],
		"parasol": [ResCache.get_or_make("pb_parasol_v1", _parasol_mesh), 1.0],
	}
	var tints := {
		"lolly": PackedColorArray([Color(1, 0.6, 0.8), Color(0.6, 0.85, 1.0), Color(1.0, 0.9, 0.5), Color(0.7, 1.0, 0.7)]),
		"gumdrop": PackedColorArray([Color(1, 0.4, 0.5), Color(0.5, 0.8, 1.0), Color(1.0, 0.85, 0.3), Color(0.6, 1.0, 0.5), Color(0.8, 0.55, 1.0)]),
		"parasol": PackedColorArray([Color(1, 0.4, 0.4), Color(0.4, 0.7, 1.0), Color(1.0, 0.85, 0.3)]),
		"flower": PackedColorArray([Color(1, 0.6, 0.7), Color(1.0, 0.95, 0.5), Color(0.75, 0.65, 1.0), Color(1, 1, 1)]),
	}
	for kind in spots:
		var list: Array = spots[kind]
		if list.is_empty():
			continue
		var m: Array = meshes[kind]
		var xfs: Array = []
		var cols := PackedColorArray()
		var pal: PackedColorArray = tints.get(kind, PackedColorArray())
		for q in list:
			var s := float(m[1]) * rng.randf_range(0.8, 1.2)
			xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), q))
			if not pal.is_empty():
				cols.append(pal[rng.randi() % pal.size()])
		var mmi := MeshKit.scatter(m[0], xfs, cols, PackedColorArray(), not vr_table)
		mmi.name = "Props_" + String(kind)
		add_child(mmi)


## True if p is clear of every space (space_r) and path (path_r).
func _clear(p: Vector2, space_r: float, path_r: float) -> bool:
	for s in data.spaces:
		var a: Vector3 = s["pos"]
		var a2 := Vector2(a.x, a.z)
		if p.distance_to(a2) < space_r:
			return false
		for nid in s["next"]:
			var c: Vector3 = data.pos(int(nid))
			var c2 := Vector2(c.x, c.z)
			var ab := c2 - a2
			var t := clampf((p - a2).dot(ab) / ab.length_squared(), 0.0, 1.0)
			if p.distance_to(a2 + ab * t) < path_r:
				return false
	if BD.river_distance(p) < BD.RIVER_W + 0.4:
		return false
	return true


func _lolly_mesh() -> Resource:
	var b := MeshKit.Builder.new()
	b.cylinder(0.05, 0.05, 1.5, MeshKit.at(Vector3(0, 0.75, 0)), Color(0.98, 0.98, 0.95), 6)
	var c := Vector3(0, 1.75, 0)
	var rings := [[0.5, Color(1, 1, 1)], [0.4, Color(1, 0.55, 0.75)], [0.3, Color(1, 1, 1)], [0.2, Color(1, 0.55, 0.75)]]
	b.cylinder(0.56, 0.56, 0.14, MeshKit.at(c, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1, 0.55, 0.75), 18)
	for r in rings:
		var rr: Array = r
		b.torus(float(rr[0]), 0.06, MeshKit.at(c, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), rr[1], 18, 5)
	return b.build()


func _cane_mesh() -> Resource:
	var b := MeshKit.Builder.new()
	var pts: Array[Vector3] = []
	for k in 7:
		pts.append(Vector3(0, 0.25 * k, 0))
	for k in 6:
		var a := PI * float(k + 1) / 6.0
		pts.append(Vector3(0.28 - cos(a) * 0.28, 1.5 + sin(a) * 0.32, 0))
	for k in pts.size() - 1:
		b.capsule_between(pts[k], pts[k + 1], 0.09, Color(0.95, 0.2, 0.25) if k % 2 == 0 else Color(1, 1, 1), 6)
	return b.build()


func _gumdrop_mesh() -> Resource:
	var b := MeshKit.Builder.new()
	b.dome(0.42, MeshKit.at(Vector3.ZERO, Vector3(1, 1.25, 1)), Color(1, 1, 1), 12)
	b.sphere(0.06, MeshKit.at(Vector3(0.12, 0.4, 0.24)), Color(1, 1, 1), 6)
	return b.build()


func _parasol_mesh() -> Resource:
	var b := MeshKit.Builder.new()
	b.cylinder(0.04, 0.04, 1.6, MeshKit.at(Vector3(0, 0.8, 0)), Color(0.95, 0.95, 0.9), 6)
	b.cone(0.85, 0.35, MeshKit.at(Vector3(0, 1.68, 0)), Color(1, 1, 1), 10)
	b.box(Vector3(0.6, 0.04, 1.1), MeshKit.at(Vector3(0.55, 0.03, 0.2)), Color(1, 1, 1).darkened(0.1))
	return b.build()


# --- Landmarks: volcano fire, shops, start arch, windmill, lighthouse -------------------------------

func _build_landmarks() -> void:
	var b := MeshKit.Builder.new()
	var vh := BD.height(BD.VOLCANO.x, BD.VOLCANO.y)
	var vc := Vector3(BD.VOLCANO.x, vh + 0.1, BD.VOLCANO.y)
	b.cylinder(0.95, 0.95, 0.12, MeshKit.at(vc), Color(1.0, 0.45, 0.1), 16, true)
	b.sphere(0.35, MeshKit.at(vc + Vector3(0.3, 0.1, 0.2)), Color(1.0, 0.75, 0.2), 8, true)
	for k in 7:  # a lava stream down the north side
		var t := float(k) / 7.0
		var q := Vector2(BD.VOLCANO.x + 0.2 * sin(t * 5.0), BD.VOLCANO.y - 0.9 - t * 3.0)
		b.ellipsoid(Vector3(0.28, 0.08, 0.42), MeshKit.at(Vector3(q.x, BD.height(q.x, q.y) + 0.04, q.y)), Color(1.0, 0.4 + 0.2 * t, 0.1), 8, true)
	# Shops: a stall beside every shop space, facing the space.
	for s in data.spaces:
		if String(s["type"]) != "shop":
			continue
		var p: Vector3 = s["pos"]
		var out := Vector3(p.x, 0, p.z).normalized()
		var at := p + out * 1.8
		at.y = BD.height(at.x, at.z)
		var yaw := atan2(-out.x, -out.z)
		var basis := Basis(Vector3.UP, yaw)
		var wood := Color(0.6, 0.4, 0.25)
		b.box(Vector3(1.4, 0.6, 0.5), Transform3D(basis, at + basis * Vector3(0, 0.3, 0.15)), wood)
		b.box(Vector3(1.5, 0.06, 0.6), Transform3D(basis, at + basis * Vector3(0, 0.62, 0.15)), wood.lightened(0.2))
		for sx in [-0.68, 0.68]:
			b.cylinder(0.05, 0.05, 1.5, Transform3D(basis, at + basis * Vector3(float(sx), 0.75, -0.05)), wood, 6)
		for k in 6:
			var col := Color(1.0, 0.45, 0.4) if k % 2 == 0 else Color(1, 1, 1)
			b.box(Vector3(0.27, 0.05, 0.8), Transform3D(basis * Basis(Vector3.RIGHT, 0.35), at + basis * Vector3(-0.675 + k * 0.27, 1.5, 0.1)), col)
		b.cylinder(0.3, 0.3, 0.06, Transform3D(basis * Basis(Vector3.RIGHT, PI * 0.5), at + basis * Vector3(0, 1.85, 0.0)), Color(1.0, 0.85, 0.3), 14, true)
		b.sphere(0.1, Transform3D(basis, at + basis * Vector3(-0.35, 0.72, 0.2)), Color(0.9, 0.3, 0.3), 8)
		b.sphere(0.1, Transform3D(basis, at + basis * Vector3(0.0, 0.72, 0.2)), Color(0.3, 0.6, 1.0), 8)
		b.sphere(0.1, Transform3D(basis, at + basis * Vector3(0.35, 0.72, 0.2)), Color(1.0, 0.85, 0.3), 8)
	# START arch over space 0.
	var s0: Vector3 = data.pos(0)
	var n0: Vector3 = data.pos(1)
	var along := Vector3(n0.x - s0.x, 0, n0.z - s0.z).normalized()
	var across := Vector3(along.z, 0, -along.x)
	for sx in [-1.0, 1.0]:
		var post := s0 + across * float(sx) * 1.05
		b.cylinder(0.11, 0.13, 2.3, MeshKit.at(Vector3(post.x, s0.y + 1.1, post.z)), Color(0.95, 0.95, 1.0), 8)
		b.sphere(0.2, MeshKit.at(Vector3(post.x, s0.y + 2.35, post.z)), Color(1.0, 0.8, 0.3), 10, true)
	var arch_basis := Basis(Vector3.UP, atan2(across.x, across.z) + PI * 0.5)
	b.box(Vector3(2.3, 0.42, 0.14), Transform3D(arch_basis, s0 + Vector3(0, 2.15, 0)), Color(0.25, 0.55, 1.0))
	# Windmill in the meadow.
	var wm := Vector2(-6.2, -5.8)
	var wy := BD.height(wm.x, wm.y)
	b.cylinder(0.55, 0.85, 2.6, MeshKit.at(Vector3(wm.x, wy + 1.3, wm.y)), Color(0.96, 0.92, 0.85), 10)
	b.cone(0.75, 0.9, MeshKit.at(Vector3(wm.x, wy + 3.05, wm.y)), Color(0.85, 0.35, 0.3), 10)
	b.box(Vector3(0.35, 0.55, 0.1), MeshKit.at(Vector3(wm.x, wy + 0.3, wm.y + 0.78)), Color(0.5, 0.32, 0.2))
	# Lighthouse on the south-west beach.
	var lh := Vector2(-9.6, 8.9)
	var ly := maxf(BD.height(lh.x, lh.y), 0.2)
	for k in 5:
		b.cylinder(0.48 - k * 0.05, 0.52 - k * 0.05, 0.6, MeshKit.at(Vector3(lh.x, ly + 0.3 + k * 0.6, lh.y)), Color(0.95, 0.3, 0.3) if k % 2 == 0 else Color(1, 1, 1), 12)
	b.cylinder(0.3, 0.3, 0.4, MeshKit.at(Vector3(lh.x, ly + 3.2, lh.y)), Color(1.0, 0.95, 0.6), 10, true)
	b.cone(0.42, 0.45, MeshKit.at(Vector3(lh.x, ly + 3.62, lh.y)), Color(0.3, 0.3, 0.4), 10)
	add_child(MeshKit.instance(b.build(), not vr_table))
	var sign := UiKit.label3d("START", 0.32, Color(1, 1, 1), true)
	sign.no_depth_test = false
	sign.double_sided = true
	sign.position = s0 + Vector3(0, 2.15, 0)
	sign.basis = arch_basis
	sign.position += arch_basis.z * 0.08
	add_child(sign)
	# Windmill sails turn.
	sails = Node3D.new()
	sails.position = Vector3(wm.x, wy + 2.4, wm.y + 0.75)
	var sb := MeshKit.Builder.new()
	for k in 4:
		var a := k * TAU / 4.0
		sb.box(Vector3(0.22, 1.25, 0.04), MeshKit.at(Vector3(cos(a), sin(a), 0) * 0.68, Vector3.ONE, Vector3(0, 0, a - PI * 0.5)), Color(0.98, 0.95, 0.88))
	sb.sphere(0.12, MeshKit.at(Vector3.ZERO), Color(0.5, 0.32, 0.2), 8)
	sails.add_child(MeshKit.instance(sb.build(), false))
	add_child(sails)
	_build_smoke(vc)


func _build_smoke(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.name = "Smoke"
	var sm := SphereMesh.new()
	sm.radius = 0.4
	sm.height = 0.8
	sm.radial_segments = 8
	sm.rings = 4
	sm.material = MeshKit.material(Color(0.85, 0.85, 0.88, 0.7))
	p.mesh = sm
	p.amount = 9
	p.lifetime = 3.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.4
	p.direction = Vector3.UP
	p.spread = 15.0
	p.gravity = Vector3(0.15, 0.35, 0)
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 0.9
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.5, 1.0))
	curve.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = curve
	p.local_coords = true
	p.position = at + Vector3(0, 0.3, 0)
	add_child(p)


# --- The STAR -------------------------------------------------------------------------------------

func _build_star() -> void:
	star_node = Node3D.new()
	star_node.name = "Star"
	var b := MeshKit.Builder.new()
	b.star(5, 0.75, 0.34, 0.3, MeshKit.at(Vector3.ZERO), Color(1.0, 0.86, 0.25), true)
	b.star(5, 0.45, 0.2, 0.34, MeshKit.at(Vector3.ZERO), Color(1.0, 0.95, 0.6), true)
	var spin := MeshKit.instance(b.build(), false)
	spin.name = "Spin"
	spin.position.y = 2.1
	star_node.add_child(spin)
	var ring := MeshKit.Builder.new()
	ring.torus(0.95, 0.07, MeshKit.at(Vector3(0, 0.3, 0)), Color(1.0, 0.85, 0.3), 24, 6, true)
	for k in 8:
		var a := k * TAU / 8.0
		ring.sphere(0.08, MeshKit.at(Vector3(cos(a) * 0.95, 0.42, sin(a) * 0.95)), Color(1, 1, 0.8), 6, true)
	var r := MeshKit.instance(ring.build(), false)
	r.name = "Ring"
	star_node.add_child(r)
	var sparkle := CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.14, 0.14)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(1.0, 0.95, 0.5)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.material = sm
	sparkle.mesh = qm
	sparkle.amount = 10
	sparkle.lifetime = 1.4
	sparkle.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparkle.emission_sphere_radius = 0.9
	sparkle.gravity = Vector3(0, 0.6, 0)
	sparkle.initial_velocity_max = 0.2
	sparkle.position.y = 2.0
	sparkle.local_coords = true
	star_node.add_child(sparkle)
	star_node.visible = false
	add_child(star_node)


## Put the STAR on a space (animate: it flies over in an arc).
func set_star(space_id: int, animate: bool) -> void:
	if space_id < 0:
		star_node.visible = false
		star_space = -1
		return
	var target := data.pos(space_id)
	if not star_node.visible or not animate:
		star_node.position = target
		star_node.visible = true
		_star_move = 1.0
	else:
		_star_from = star_node.position
		_star_to = target
		_star_move = 0.0
	star_space = space_id


## World-ish (board units) position of the star's spinning part.
func star_top() -> Vector3:
	return star_node.position + Vector3(0, 2.1, 0)


# --- Branch arrows --------------------------------------------------------------------------------

## Show an arrow from `from` towards each option (space ids); `sel` is highlighted.
func show_arrows(from: int, options: Array, sel: int) -> void:
	hide_arrows()
	var p := data.pos(from)
	for i in options.size():
		var q := data.pos(int(options[i]))
		var dir := Vector3(q.x - p.x, 0, q.z - p.z).normalized()
		var a := Node3D.new()
		a.name = "Arrow%d" % i
		var b := MeshKit.Builder.new()
		var col := Color(1.0, 0.85, 0.3)
		b.box(Vector3(0.28, 0.12, 0.7), MeshKit.at(Vector3(0, 0, -0.1)), col, true)
		b.wedge(Vector3(0.75, 0.14, 0.55), MeshKit.at(Vector3(0, 0, 0.5), Vector3.ONE, Vector3(0, PI, 0)), col, true)
		var mi := MeshKit.instance(b.build(), false)
		mi.name = "Mesh"
		a.add_child(mi)
		var lab := UiKit.label3d(data.branch_name(from, int(options[i])), 0.34, Color(1, 1, 1), true)
		lab.no_depth_test = false
		lab.position = Vector3(0, 0.55, 0.2)
		lab.rotation = Vector3(-0.9, 0, 0)
		lab.name = "Label"
		a.add_child(lab)
		add_child(a)
		a.position = p + dir * 1.55 + Vector3(0, 0.9, 0)
		a.rotation.y = atan2(dir.x, dir.z)
		arrows.append(a)
	arrow_targets = options.duplicate()
	set_arrow_sel(sel)


func set_arrow_sel(sel: int) -> void:
	arrow_sel = sel
	for i in arrows.size():
		var a := arrows[i]
		if not is_instance_valid(a):
			continue
		var on := i == sel
		a.scale = Vector3.ONE * (1.35 if on else 0.85)
		var mi := a.get_node("Mesh") as MeshInstance3D
		mi.transparency = 0.0 if on else 0.45
		(a.get_node("Label") as Label3D).modulate = Color(1, 0.9, 0.4) if on else Color(0.8, 0.8, 0.85, 0.7)


func hide_arrows() -> void:
	for a in arrows:
		if is_instance_valid(a):
			a.queue_free()
	arrows.clear()
	arrow_targets.clear()
	arrow_sel = -1


# --- Effects --------------------------------------------------------------------------------------

## Make a space glow for a moment (landing feedback).
func flash_space(id: int, color: Color) -> void:
	var b := MeshKit.Builder.new()
	b.torus(0.85, 0.12, MeshKit.at(Vector3.ZERO), color, 24, 6, true)
	var mi := MeshKit.instance(b.build(), false)
	mi.position = data.pos(id) + Vector3(0, 0.3, 0)
	add_child(mi)
	_flashes.append([mi, 0.8])


func _process(delta: float) -> void:
	_t += delta
	if sails != null:
		sails.rotation.z += delta * 0.8
	if star_node != null and star_node.visible:
		var spin := star_node.get_node("Spin") as Node3D
		spin.rotation.y += delta * 1.6
		spin.position.y = 2.1 + 0.15 * sin(_t * 2.2)
		if _star_move < 1.0:
			_star_move = minf(1.0, _star_move + delta / 1.6)
			var k := _star_move * _star_move * (3.0 - 2.0 * _star_move)
			star_node.position = _star_from.lerp(_star_to, k) + Vector3(0, sin(k * PI) * 6.0, 0)
	for a in arrows:
		if is_instance_valid(a):
			var mi := a.get_node("Mesh") as Node3D
			mi.position.z = 0.15 * sin(_t * 6.0)
	for i in range(_flashes.size() - 1, -1, -1):
		var f: Array = _flashes[i]
		var mi: MeshInstance3D = f[0]
		f[1] = float(f[1]) - delta
		if float(f[1]) <= 0.0 or not is_instance_valid(mi):
			if is_instance_valid(mi):
				mi.queue_free()
			_flashes.remove_at(i)
			continue
		var k2 := float(f[1]) / 0.8
		mi.scale = Vector3.ONE * (1.0 + (1.0 - k2) * 0.6)
		mi.transparency = 1.0 - k2
