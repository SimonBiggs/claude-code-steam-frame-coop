extends Node3D
## One level's sky route, built from a seed so the host and the TV machine build exactly the same
## thing: glowing rings to fly through, stars to scoop up on the way (one leg is a rainbow arc of
## stars), balloons for the gunners (one golden balloon gives everyone TRIPLE BUBBLES), floating sky
## islands with blossom trees, cottages, windmills and waterfalls, and on rescue levels little sky
## bunnies in bubble cages (gunners pop the cage, then the rider flies close to scoop them up).
## Boss levels have no rings (the Storm King is the goal), just the scenery, stars and balloons.
## Item ids: stars 1000+, balloons 2000+, golden balloon 3000, cages 4000+, rescues 5000+.
## `gone` holds the ids that were collected, popped or rescued.

const SPACING := 74.0
const FIRST := 95.0
const RING_R := 6.5
const RESCUE_R := 9.5
const BALLOON_COLORS: Array[Color] = [Color(1.0, 0.35, 0.4), Color(1.0, 0.8, 0.25), Color(0.4, 0.8, 1.0),
	Color(0.55, 0.95, 0.45), Color(0.95, 0.5, 1.0)]
const CRITTER_COLORS: Array[Color] = [Color(1.0, 0.75, 0.85), Color(0.75, 0.9, 1.0), Color(1.0, 0.92, 0.6),
	Color(0.8, 1.0, 0.75), Color(0.9, 0.8, 1.0)]
const WATERFALL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec4 col : source_color = vec4(0.7, 0.9, 1.0, 0.75);
void fragment() {
	float s = fract(UV.y * 6.0 - TIME * 1.6 + sin(UV.x * 18.0) * 0.08);
	ALBEDO = col.rgb + vec3(smoothstep(0.75, 1.0, s) * 0.35);
	ALPHA = col.a * (0.75 + 0.25 * s) * smoothstep(0.0, 0.08, UV.y) * (1.0 - smoothstep(0.85, 1.0, UV.y));
}
"""

var main
var seed_value := 0
var level := 1
var mission := "rings"
var rings: Array = []  # {pos: Vector3, normal: Vector3, radius: float, node: MeshInstance3D, final: bool}
var stars: Array = []  # {id, idx, pos}
var balloons: Array = []  # {id, node, pos}
var critters: Array = []  # {i, pos, node, cage, body, beacon}
var gone := {}
var t := 0.0
var shown_ring := -2
var ring_next_mat: StandardMaterial3D
var ring_later_mat: StandardMaterial3D
var ring_done_mat: StandardMaterial3D
var ring_final_mat: StandardMaterial3D
var star_mm: MultiMesh
var trunk_xf: Array = []
var crown_xf: Array = []
var house_xf: Array = []
var mill_xf: Array = []
var rock_xf: Array = []
var mill_blades: Array = []


func ring_count(lv: int) -> int:
	if main.SIMPLE_MODE:
		return [4, 5, 6][lv - 1] if lv <= 3 else mini(5 + lv / 2, 9)
	return mini(6 + (lv - 1) * 2, 14)


func build(seed_v: int, origin: Vector3, yaw: float, lv: int, mis: String = "rings") -> void:
	seed_value = seed_v
	level = lv
	mission = mis
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	ring_next_mat = main.color_mat(Color(1.0, 0.85, 0.3), 2.2)
	ring_later_mat = main.color_mat(Color(0.55, 0.85, 1.0), 0.7)
	ring_done_mat = main.color_mat(Color(0.5, 1.0, 0.6), 0.5)
	ring_final_mat = main.color_mat(Color(1.0, 0.5, 0.75), 2.5)
	var rock: StandardMaterial3D = main.color_mat(Color(0.55, 0.42, 0.5), 0.0)
	var grass: StandardMaterial3D = main.color_mat(Color(0.5, 0.78, 0.4), 0.0)
	var string_mat: StandardMaterial3D = main.color_mat(Color(0.95, 0.95, 0.95), 0.0)
	var simple: bool = main.SIMPLE_MODE
	var easy := simple and lv <= 2  # stage 1-2: big rings in an easy, gentle line; balloons close by
	var has_stars: bool = not simple or main.simple_has("stars", lv)
	var count := ring_count(lv)
	if mission == "rescue":
		count = maxi(5, count - 2)
	elif mission == "boss":
		count = 6
	var heading := yaw
	var pos := origin
	var prev := origin
	var star_pts: Array = []
	var arc_leg := count / 2 if count > 3 and has_stars else -1
	var critter_legs: Array = []
	if mission == "rescue":
		var nc := mini(3 + lv / 3, count - 1)
		for k in nc:
			critter_legs.append(1 + int(float(k) * (count - 1) / nc))
	var golden_leg := 1 + rng.randi() % maxi(1, count - 2)
	for k in count:
		var dist := FIRST if k == 0 else SPACING
		var wiggle := 0.55 * minf(1.0, 0.5 + lv * 0.15)
		var dy := 12.0
		if easy:
			dist = 60.0 if k == 0 else 62.0
			wiggle = 0.12 if lv == 1 else 0.25
			dy = 3.0 if lv == 1 else 6.0
		elif simple:
			wiggle = minf(wiggle, 0.4)
			dy = 8.0
		if k > 0:
			heading += rng.randf_range(-1.0, 1.0) * wiggle
		var y := clampf(pos.y + rng.randf_range(-dy, dy), 22.0, 85.0)
		pos = pos + Basis(Vector3.UP, heading) * Vector3.FORWARD * dist
		pos.y = y
		var normal := (pos - prev).normalized()
		var final := k == count - 1
		if mission != "boss":
			var r0 := RING_R
			if simple:
				r0 = 9.5 if lv == 1 else (8.5 if lv == 2 else 7.5)
			var radius := r0 * (1.3 if final else 1.0)
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = radius - 0.45
			tm.outer_radius = radius + 0.45
			tm.rings = 28
			tm.ring_segments = 8
			ring.mesh = tm
			ring.material_override = ring_later_mat
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(ring)
			ring.global_position = pos
			ring.basis = main.basis_y_to(normal)
			rings.append({"pos": pos, "normal": normal, "radius": radius, "node": ring, "final": final})
		# Stars along the way from the previous ring to this one (one leg: a rainbow arc of stars).
		var side := normal.cross(Vector3.UP).normalized()
		if not has_stars:
			pass
		elif k == arc_leg:
			var arc_h := 9.0 + rng.randf() * 3.0
			var pts: Array = []
			for j in 7:
				var f := 0.15 + j * 0.7 / 6.0
				var sp := prev.lerp(pos, f) + Vector3.UP * sin(f * PI) * arc_h
				star_pts.append(sp)
				pts.append(sp)
			_rainbow(pts)
		else:
			for j in 2:
				var f := 0.35 + j * 0.3
				var sp := prev.lerp(pos, f) + side * rng.randf_range(-3.0, 3.0) + Vector3.UP * rng.randf_range(-2.0, 2.0)
				if k == 0:
					sp = origin.lerp(pos, 0.55 + j * 0.2)
				star_pts.append(sp)
		# Balloons off to the sides for the gunners (and once per level a golden one).
		var nb := 2 if lv < 3 else 3
		if easy:
			nb = 3
		for j in nb:
			var s := -1.0 if rng.randf() < 0.5 else 1.0
			var bp := prev.lerp(pos, rng.randf_range(0.2, 0.9)) + side * s * rng.randf_range(9.0, 22.0) \
				+ Vector3.UP * rng.randf_range(-5.0, 9.0)
			if easy:
				bp = prev.lerp(pos, 0.2 + 0.25 * j + rng.randf_range(0.0, 0.1)) + side * s * rng.randf_range(5.0, 9.0) \
					+ Vector3.UP * rng.randf_range(-1.0, 4.0)
			var c: Color = BALLOON_COLORS[rng.randi() % BALLOON_COLORS.size()]
			_balloon(2000 + balloons.size(), bp, c, false, string_mat)
		if k == golden_leg and (not simple or main.simple_has("golden", lv)):
			var gs := -1.0 if rng.randf() < 0.5 else 1.0
			_balloon(3000, prev.lerp(pos, 0.5) + side * gs * rng.randf_range(10.0, 15.0) + Vector3.UP * rng.randf_range(2.0, 7.0),
				Color(1.0, 0.82, 0.25), true, string_mat)
		if critter_legs.has(k):
			var cs := -1.0 if rng.randf() < 0.5 else 1.0
			_critter(prev.lerp(pos, rng.randf_range(0.4, 0.6)) + side * cs * rng.randf_range(7.0, 11.0) + Vector3.UP * rng.randf_range(-2.0, 3.0))
		# A sky island beside the route, and a big one far off as scenery.
		var isl_side := -1.0 if rng.randf() < 0.5 else 1.0
		_island(prev.lerp(pos, 0.5) + side * isl_side * rng.randf_range(32.0, 55.0) + Vector3.UP * rng.randf_range(-22.0, -6.0),
			rng.randf_range(6.0, 12.0), rng, rock, grass, 1 + rng.randi() % 2, true)
		var far_pos := prev.lerp(pos, 0.5) - side * isl_side * rng.randf_range(110.0, 190.0) + Vector3.UP * rng.randf_range(-40.0, 10.0)
		var far_r := rng.randf_range(18.0, 34.0)
		if k % 2 == 0:
			_island(far_pos, far_r, rng, rock, grass, 0, false)
		prev = pos
	# The finish: a big island just past the last ring (or the end of the boss route).
	var end_n := (pos - origin).normalized() if rings.is_empty() else (rings[rings.size() - 1].normal as Vector3)
	_island(pos + end_n * 70.0 + Vector3.UP * -30.0, 22.0, rng, rock, grass, 3, false)
	_build_stars(star_pts)
	_build_multimeshes()
	# Draw distance: the Frame's GPU only draws what is near enough to matter.
	_cull(self)
	update_rings(0)


func _cull(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D and not c is MultiMeshInstance3D:
			(c as GeometryInstance3D).visibility_range_end = 480.0
		_cull(c)


func _balloon(id: int, bp: Vector3, c: Color, golden: bool, string_mat: Material) -> void:
	var b := Node3D.new()
	add_child(b)
	b.global_position = bp
	var bm := MeshInstance3D.new()
	bm.mesh = main.sphere_mesh(1.1)
	bm.material_override = main.color_mat(c, 1.6 if golden else 0.35)
	bm.scale = Vector3(1.0, 1.2, 1.0) * (1.35 if golden else 1.0)
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_child(bm)
	var st := MeshInstance3D.new()
	st.mesh = main.cyl_mesh(0.02, 0.02, 2.0, 4)
	st.material_override = string_mat
	st.position = Vector3(0, -2.3 * (1.3 if golden else 1.0), 0)
	st.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_child(st)
	b.set_meta("kind", "balloon")
	b.set_meta("id", id)
	b.set_meta("radius", 2.2 if golden else 1.7)
	b.set_meta("color", c)
	if golden:
		b.set_meta("golden", true)
	b.add_to_group("dr_targets")
	balloons.append({"id": id, "node": b, "pos": bp})


## A see-through rainbow ribbon under the arc of stars.
func _rainbow(pts: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols: Array[Color] = [Color(1.0, 0.35, 0.35), Color(1.0, 0.7, 0.25), Color(1.0, 0.95, 0.35), Color(0.4, 0.9, 0.45),
		Color(0.4, 0.65, 1.0), Color(0.75, 0.45, 1.0)]
	var first: Vector3 = pts[0]
	var last: Vector3 = pts[pts.size() - 1]
	var along := (last - first).normalized()
	var side := along.cross(Vector3.UP).normalized()
	var a0: Vector3 = first - along * 8.0 + Vector3.DOWN * 2.0
	var a1: Vector3 = last + along * 8.0 + Vector3.DOWN * 2.0
	var full: Array = [a0]
	full.append_array(pts)
	full.append(a1)
	for b in cols.size():
		var off := -2.0 - b * 0.55
		for i in full.size() - 1:
			var p0: Vector3 = full[i]
			var p1: Vector3 = full[i + 1]
			var q := [p0 + Vector3.UP * off + side * 0.0, p1 + Vector3.UP * off, p1 + Vector3.UP * (off - 0.55), p0 + Vector3.UP * (off - 0.55)]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(cols[b])
				st.set_normal(side)
				var v: Vector3 = q[idx]
				st.add_vertex(v)
	var m := st.commit()
	var mt := StandardMaterial3D.new()
	mt.vertex_color_use_as_albedo = true
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.albedo_color = Color(1, 1, 1, 0.6)
	m.surface_set_material(0, mt)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_stars(pts: Array) -> void:
	star_mm = MultiMesh.new()
	star_mm.transform_format = MultiMesh.TRANSFORM_3D
	var gm: SphereMesh = main.gem_mesh().duplicate()
	gm.material = main.color_mat(Color(1.0, 0.88, 0.3), 2.5)
	star_mm.mesh = gm
	star_mm.instance_count = pts.size()
	for i in pts.size():
		var sp: Vector3 = pts[i]
		stars.append({"id": 1000 + i, "idx": i, "pos": sp})
		star_mm.set_instance_transform(i, Transform3D(Basis(), sp))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = star_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## A little sky bunny on a cloud, inside a bubble cage the gunners have to pop first.
func _critter(at: Vector3) -> void:
	var i := critters.size()
	var n := Node3D.new()
	add_child(n)
	n.global_position = at
	var pad := MeshInstance3D.new()
	pad.mesh = main.sphere_mesh(1.0)
	pad.material_override = main.color_mat(Color(1.0, 1.0, 1.0), 0.3)
	pad.scale = Vector3(2.0, 0.6, 1.6)
	pad.position = Vector3(0, -0.9, 0)
	n.add_child(pad)
	var body := MeshInstance3D.new()
	body.mesh = critter_mesh(CRITTER_COLORS[i % CRITTER_COLORS.size()])
	n.add_child(body)
	var cage := MeshInstance3D.new()
	cage.mesh = main.sphere_mesh(1.0)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.7, 0.95, 1.0, 0.35)
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.emission_enabled = true
	cm.emission = Color(0.5, 0.85, 1.0)
	cm.emission_energy_multiplier = 0.8
	cm.roughness = 0.1
	cage.material_override = cm
	cage.scale = Vector3.ONE * 1.7
	cage.set_meta("kind", "cage")
	cage.set_meta("id", 4000 + i)
	cage.set_meta("radius", 1.9)
	cage.set_meta("hp", 2)
	cage.add_to_group("dr_targets")
	n.add_child(cage)
	var beacon := MeshInstance3D.new()
	beacon.mesh = main.cyl_mesh(0.35, 0.8, 30.0, 8)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(1.0, 0.9, 0.4, 0.35)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon.material_override = bmat
	beacon.position = Vector3(0, 15.0, 0)
	beacon.visible = false
	n.add_child(beacon)
	for m in [pad, body, cage, beacon]:
		(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	critters.append({"i": i, "pos": at, "node": n, "cage": cage, "body": body, "beacon": beacon})


## One vertex-coloured mesh for a sky bunny: body, head, ears, eyes, cheeks (a single draw call).
func critter_mesh(c: Color) -> ArrayMesh:
	var key := "critter" + c.to_html()
	if main.meshes.has(key):
		return main.meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_vsphere(st, Vector3(0, -0.15, 0), Vector3(0.55, 0.5, 0.5), c)
	_vsphere(st, Vector3(0, 0.45, -0.05), Vector3(0.42, 0.38, 0.4), c.lightened(0.1))
	for s in [-1.0, 1.0]:
		_vsphere(st, Vector3(0.17 * s, 0.98, 0.0), Vector3(0.1, 0.32, 0.08), c)
		_vsphere(st, Vector3(0.17 * s, 0.98, -0.03), Vector3(0.05, 0.22, 0.06), Color(1.0, 0.6, 0.7))
		_vsphere(st, Vector3(0.15 * s, 0.5, -0.38), Vector3(0.07, 0.09, 0.05), Color(0.08, 0.06, 0.1))
		_vsphere(st, Vector3(0.27 * s, 0.37, -0.32), Vector3(0.07, 0.05, 0.04), Color(1.0, 0.5, 0.55))
		_vsphere(st, Vector3(0.45 * s, -0.05, -0.15), Vector3(0.14, 0.18, 0.14), c.darkened(0.05))
	var m := st.commit()
	var mt := StandardMaterial3D.new()
	mt.vertex_color_use_as_albedo = true
	mt.roughness = 0.7
	mt.emission_enabled = true
	mt.emission = Color(0.25, 0.22, 0.25)
	m.surface_set_material(0, mt)
	main.meshes[key] = m
	return m


## A low-poly ellipsoid with a flat vertex colour, appended to a SurfaceTool.
static func _vsphere(st: SurfaceTool, c: Vector3, r: Vector3, col: Color, seg: int = 10, rings_n: int = 6) -> void:
	for i in rings_n:
		var a0 := PI * i / rings_n - PI * 0.5
		var a1 := PI * (i + 1) / rings_n - PI * 0.5
		for j in seg:
			var b0 := TAU * j / seg
			var b1 := TAU * (j + 1) / seg
			var p: Array[Vector3] = [
				Vector3(cos(a0) * cos(b0), sin(a0), cos(a0) * sin(b0)), Vector3(cos(a0) * cos(b1), sin(a0), cos(a0) * sin(b1)),
				Vector3(cos(a1) * cos(b1), sin(a1), cos(a1) * sin(b1)), Vector3(cos(a1) * cos(b0), sin(a1), cos(a1) * sin(b0))]
			for idx in [0, 2, 1, 0, 3, 2]:
				var u: Vector3 = p[idx]
				st.set_color(col)
				st.set_normal(u)
				st.add_vertex(c + u * r)


func _island(at: Vector3, r: float, rng: RandomNumberGenerator, rock: Material, grass: Material,
		trees: int, near: bool) -> void:
	var n := Node3D.new()
	add_child(n)
	n.global_position = at
	n.rotation.y = rng.randf() * TAU
	var base := MeshInstance3D.new()
	base.mesh = main.cyl_mesh(r, r * 0.12, r * 1.5, 9)
	base.material_override = rock
	base.position = Vector3(0, -r * 0.75, 0)
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(base)
	var top := MeshInstance3D.new()
	top.mesh = main.cyl_mesh(r * 1.04, r * 1.04, 0.8, 9)
	top.material_override = grass
	top.position = Vector3(0, 0.3, 0)
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(top)
	var xf := n.global_transform
	for k in trees + (2 if r > 15.0 else 0):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, r * 0.6)
		var tp := Vector3(cos(a) * d, 0.7, sin(a) * d)
		var h := rng.randf_range(2.5, 4.5) * (1.0 + r * 0.03)
		trunk_xf.append(xf * Transform3D(Basis().scaled(Vector3(1.0, h, 1.0)), tp + Vector3(0, h * 0.5, 0)))
		crown_xf.append(xf * Transform3D(Basis().scaled(Vector3.ONE * h * 0.6), tp + Vector3(0, h * 1.2, 0)))
	# Cottages (and sometimes a windmill) on the bigger islands.
	if r > 7.5:
		var houses := 1 + (1 if r > 14.0 else 0)
		for k in houses:
			var a := rng.randf() * TAU
			var hp := Vector3(cos(a) * r * 0.45, 0.7, sin(a) * r * 0.45)
			house_xf.append(xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.6, 2.3)), hp))
		if near and mill_blades.size() < 3 and rng.randf() < 0.6:
			var mp := Vector3(-r * 0.3, 0.7, r * 0.3)
			var mxf := xf * Transform3D(Basis().scaled(Vector3.ONE * 2.2), mp)
			mill_xf.append(mxf)
			var blades := MeshInstance3D.new()
			blades.mesh = _blades_mesh()
			blades.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(blades)
			blades.global_transform = mxf * Transform3D(Basis(), Vector3(0, 3.3, -0.62))
			mill_blades.append(blades)
	# A waterfall pouring off the edge of some islands near the route.
	if near and r > 8.0 and rng.randf() < 0.7:
		var wf := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(r * 0.25, r * 1.6)
		wf.mesh = qm
		wf.material_override = _waterfall_mat()
		wf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(wf)
		wf.position = Vector3(0, -r * 0.8 + 0.6, r * 0.98)
	# Little rocks floating around it.
	for k in 5:
		var a := rng.randf() * TAU
		var d := r * rng.randf_range(1.2, 1.7)
		var rp := Vector3(cos(a) * d, rng.randf_range(-r * 0.8, r * 0.3), sin(a) * d)
		var sc := rng.randf_range(0.4, 1.0) * (0.6 + r * 0.06)
		rock_xf.append(xf * Transform3D(Basis(Vector3(rng.randf(), 1.0, rng.randf()).normalized(), rng.randf() * TAU).scaled(Vector3(sc, sc * 0.8, sc)), rp))


func _waterfall_mat() -> ShaderMaterial:
	if not main.mats.has("waterfall"):
		var sm := ShaderMaterial.new()
		sm.shader = Shader.new()
		sm.shader.code = WATERFALL_SHADER
		main.mats["waterfall"] = sm
	return main.mats["waterfall"]


## Merged, vertex-coloured meshes for cottages, windmills and their blades (cached on main).
func _house_mesh(kind: String) -> ArrayMesh:
	var key := "house_" + kind
	if main.meshes.has(key):
		return main.meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if kind == "cottage":
		_vbox(st, Vector3(0, 0.5, 0), Vector3(1.4, 1.0, 1.0), Color(1.0, 0.95, 0.85))
		_roof(st, Vector3(0, 1.0, 0), Vector3(1.6, 0.75, 1.2), Color(0.85, 0.35, 0.3))
		_vbox(st, Vector3(0.0, 0.32, -0.51), Vector3(0.3, 0.6, 0.04), Color(0.5, 0.32, 0.22))
		for s in [-1.0, 1.0]:
			_vbox(st, Vector3(0.45 * s, 0.6, -0.51), Vector3(0.26, 0.24, 0.04), Color(1.0, 0.85, 0.4))
		_vbox(st, Vector3(0.45, 1.5, 0.2), Vector3(0.18, 0.5, 0.18), Color(0.6, 0.45, 0.4))
	else:
		_vbox(st, Vector3(0, 1.4, 0), Vector3(1.0, 2.8, 1.0), Color(0.95, 0.9, 0.82))
		_roof(st, Vector3(0, 2.8, 0), Vector3(1.2, 0.8, 1.2), Color(0.45, 0.55, 0.85))
		_vbox(st, Vector3(0.0, 0.35, -0.51), Vector3(0.32, 0.7, 0.04), Color(0.5, 0.32, 0.22))
		_vbox(st, Vector3(0.0, 3.3, -0.55), Vector3(0.16, 0.16, 0.2), Color(0.4, 0.3, 0.25))
	var m := st.commit()
	var mt := StandardMaterial3D.new()
	mt.vertex_color_use_as_albedo = true
	mt.roughness = 0.8
	m.surface_set_material(0, mt)
	main.meshes[key] = m
	return m


func _blades_mesh() -> ArrayMesh:
	if main.meshes.has("mill_blades"):
		return main.meshes["mill_blades"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 4:
		var b := Basis(Vector3.BACK, k * PI * 0.5)
		var c: Vector3 = b * Vector3(0, 0.85, 0)
		var sz: Vector3 = (b * Vector3(0.28, 1.6, 0.04)).abs()
		_vbox(st, c, sz, Color(0.98, 0.96, 0.9))
	_vbox(st, Vector3.ZERO, Vector3(0.22, 0.22, 0.12), Color(0.5, 0.35, 0.25))
	var m := st.commit()
	var mt := StandardMaterial3D.new()
	mt.vertex_color_use_as_albedo = true
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.surface_set_material(0, mt)
	main.meshes["mill_blades"] = m
	return m


static func _vbox(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var faces := [
		[Vector3.UP, [Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]],
		[Vector3.DOWN, [Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z)]],
		[Vector3.RIGHT, [Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z)]],
		[Vector3.LEFT, [Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z)]],
		[Vector3.BACK, [Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z)]],
		[Vector3.FORWARD, [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z)]],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var v: Array = f[1]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_normal(n)
			var p: Vector3 = v[idx]
			st.add_vertex(c + p)


## A pitched roof (ridge along X) sitting on top of a box.
static func _roof(st: SurfaceTool, base: Vector3, s: Vector3, col: Color) -> void:
	var hx := s.x * 0.5
	var hz := s.z * 0.5
	var a := base + Vector3(-hx, 0, -hz)
	var b := base + Vector3(hx, 0, -hz)
	var c := base + Vector3(hx, 0, hz)
	var d := base + Vector3(-hx, 0, hz)
	var r0 := base + Vector3(-hx, s.y, 0)
	var r1 := base + Vector3(hx, s.y, 0)
	var tris := [[a, r0, r1], [a, r1, b], [d, c, r1], [d, r1, r0], [a, d, r0], [b, r1, c]]
	for tr in tris:
		var p0: Vector3 = tr[0]
		var p1: Vector3 = tr[1]
		var p2: Vector3 = tr[2]
		var n := (p1 - p0).cross(p2 - p0).normalized()
		if n.y < -0.01:
			n = -n
		for v in [p0, p1, p2]:
			st.set_color(col)
			st.set_normal(n)
			var vv: Vector3 = v
			st.add_vertex(vv)


## Trees, cottages, windmills and floating rocks: one MultiMesh each for the whole course.
func _build_multimeshes() -> void:
	var trunk_m: CylinderMesh = main.cyl_mesh(0.25, 0.4, 1.0, 6).duplicate()
	trunk_m.material = main.color_mat(Color(0.45, 0.3, 0.22), 0.0)
	var crown_m: SphereMesh = main.sphere_mesh(1.0).duplicate()
	crown_m.material = main.color_mat(Color(1.0, 0.6, 0.75), 0.15)
	var rock_m: BoxMesh = main.box_mesh(Vector3.ONE).duplicate()
	rock_m.material = main.color_mat(Color(0.55, 0.42, 0.5), 0.0)
	for pair in [[trunk_m, trunk_xf], [crown_m, crown_xf], [_house_mesh("cottage"), house_xf], [_house_mesh("mill"), mill_xf],
			[rock_m, rock_xf]]:
		var xfs: Array = pair[1]
		if xfs.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pair[0]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


## Highlight the ring to fly through next (gold), later ones in blue, passed ones in green.
func update_rings(next_i: int) -> void:
	if next_i == shown_ring:
		return
	shown_ring = next_i
	for i in rings.size():
		var r: Dictionary = rings[i]
		var node: MeshInstance3D = r.node
		if i < next_i:
			node.material_override = ring_done_mat
			node.scale = Vector3.ONE * 0.9
		elif i == next_i:
			node.material_override = ring_final_mat if r.final else ring_next_mat
			node.scale = Vector3.ONE
		else:
			node.material_override = ring_later_mat
			node.scale = Vector3.ONE


func next_ring(next_i: int) -> Dictionary:
	if next_i >= 0 and next_i < rings.size():
		return rings[next_i]
	return {}


func animate(delta: float) -> void:
	t += delta
	for s in stars:
		if not gone.has(int(s.id)):
			var sp: Vector3 = s.pos
			star_mm.set_instance_transform(int(s.idx), Transform3D(Basis(Vector3.UP, t * 2.0 + float(s.id)), sp))
	for b in balloons:
		var node: Node3D = b.node
		if node.visible:
			var p: Vector3 = b.pos
			node.global_position = p + Vector3(0, sin(t * 1.2 + float(b.id)) * 0.6, 0)
			if node.has_meta("golden"):
				node.rotation.y = t * 1.5
	for bl in mill_blades:
		var bn: MeshInstance3D = bl
		bn.rotate_object_local(Vector3.BACK, delta * 0.9)
	for c in critters:
		var body: MeshInstance3D = c.body
		if body.get_parent() == c.node:
			body.position = Vector3(0, absf(sin(t * 3.0 + float(c.i))) * 0.25, 0)
			body.rotation.y = sin(t * 0.8 + float(c.i)) * 0.6
		else:
			# Rescued: riding on the deck, bouncing and looking around.
			body.position.y = 0.35 + absf(sin(t * 4.0 + float(c.i))) * 0.12
			body.rotation.y = PI + sin(t * 1.3 + float(c.i)) * 0.8
		var beacon: MeshInstance3D = c.beacon
		if beacon.visible:
			beacon.scale = Vector3(1.0 + sin(t * 5.0) * 0.15, 1.0, 1.0 + sin(t * 5.0) * 0.15)
	if shown_ring >= 0 and shown_ring < rings.size():
		var r: Dictionary = rings[shown_ring]
		var node: MeshInstance3D = r.node
		node.scale = Vector3.ONE * (1.0 + sin(t * 4.0) * 0.04)


func remove_item(id: int) -> void:
	if gone.has(id):
		return
	gone[id] = true
	if id >= 1000 and id < 2000:
		for s in stars:
			if int(s.id) == id:
				star_mm.set_instance_transform(int(s.idx), Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0, -9999, 0)))
		return
	if id >= 4000 and id < 5000:
		var c: Dictionary = critters[clampi(id - 4000, 0, critters.size() - 1)]
		var cage: MeshInstance3D = c.cage
		cage.visible = false
		if cage.is_in_group("dr_targets"):
			cage.remove_from_group("dr_targets")
		(c.beacon as MeshInstance3D).visible = not gone.has(5000 + int(c.i))
		return
	if id >= 5000 and id < 6000:
		var c2: Dictionary = critters[clampi(id - 5000, 0, critters.size() - 1)]
		(c2.beacon as MeshInstance3D).visible = false
		var cage2: MeshInstance3D = c2.cage
		cage2.visible = false
		if cage2.is_in_group("dr_targets"):
			cage2.remove_from_group("dr_targets")
		var body: MeshInstance3D = c2.body
		# Hop aboard: sit on the deck between the gunners.
		var seat := Vector3((0.75 if int(c2.i) % 2 == 0 else -0.75), 0.0, 1.0 + (int(c2.i) / 2) * 1.3)
		body.reparent(main.dragon, false)
		body.position = seat
		body.scale = Vector3.ONE * 0.55
		body.visibility_range_end = 0.0
		return
	for b in balloons:
		if int(b.id) == id:
			var node: Node3D = b.node
			node.visible = false
			if node.is_in_group("dr_targets"):
				node.remove_from_group("dr_targets")


## Rescued bunnies ride on the dragon: free them with the course (they belong to this level).
func _exit_tree() -> void:
	for c in critters:
		var body: MeshInstance3D = c.body
		if is_instance_valid(body) and body.get_parent() != c.node:
			body.queue_free()


func gone_ids() -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in gone.keys():
		out.append(int(k))
	return out


func remaining_balloons() -> int:
	var n := 0
	for b in balloons:
		if not gone.has(int(b.id)):
			n += 1
	return n


func critter_open(i: int) -> bool:
	return gone.has(4000 + i) and not gone.has(5000 + i)


func rescued_count() -> int:
	var n := 0
	for c in critters:
		if gone.has(5000 + int(c.i)):
			n += 1
	return n
