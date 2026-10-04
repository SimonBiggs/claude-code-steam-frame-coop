extends Node3D
## One built hole: meshes (a few merged draw calls), colliders, water, zones, gimmicks, the cup and
## flag, the tee mat, decor, a critter audience and a caddy. Built from a hole_spec.gd on every
## machine (identical), placed on its plot by the game. Only the current and the next hole exist.
## Runtime (host / local): zone_effects() before each ball step (low gravity, conveyors, sand, cup
## assist), course_events() after it (cup, water, out of bounds, portals, cannon, loop, power-ups).
## The TV machine only calls update(t) so the gimmicks move in step with the host's clock.

const Defs := preload("res://games/mini_golf_party/defs.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Creatures := preload("res://core/creatures.gd")
const UiKit := preload("res://core/ui_kit.gd")
const Gimmicks := preload("res://games/mini_golf_party/gimmicks.gd")
const HoleSpec := preload("res://games/mini_golf_party/hole_spec.gd")

const GROUND_Y := -0.12

var spec: HoleSpec
var number := 1  ## 1-based hole number in the round
var gimmicks: Array = []  ## Gimmicks.Gimmick nodes (spec order)
var boxes: Array = []  ## Gimmicks.PowerBox nodes (spec order)
var crowd: Node3D
var caddy: Node3D
var flag: Node3D
var clock := 0.0
## Host: balls waiting in a cannon [[ball, fire_time, gimmick]].
var cannon_queue: Array = []
var _water_mat: StandardMaterial3D


## Build everything (call once, before or after adding to the tree).
func build(s: HoleSpec, hole_number: int) -> void:
	spec = s
	number = hole_number
	name = "Hole%d" % hole_number
	_build_floors()
	_build_walls()
	_build_zones()
	_build_cup()
	_build_tee()
	_build_decor()
	for g in spec.gimmicks:
		var n := Gimmicks.make(g, spec.theme)
		add_child(n)
		gimmicks.append(n)
	for p in spec.powerups:
		var bx := Gimmicks.PowerBox.new()
		bx.position = p
		add_child(bx)
		boxes.append(bx)
	_build_audience()
	update(0.0)


# --- World helpers ---------------------------------------------------------------------------------

func cup_world() -> Vector3:
	return to_global(spec.cup)


func tee_world() -> Vector3:
	return to_global(spec.tee)


## Unit direction (world, flat) from the tee towards the first waypoint (or the cup).
func tee_dir() -> Vector3:
	var target := spec.cup
	if not spec.route.is_empty():
		target = spec.route[0].p
	var d := to_global(target) - tee_world()
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else -global_basis.z


## Playing area rectangle in world XZ (approximate: the plot is rotated).
func world_bounds(margin: float = 0.0) -> Rect2:
	var b := spec.bounds().grow(margin)
	var r := Rect2(Vector2.ZERO, Vector2.ZERO)
	var first := true
	for c in [b.position, Vector2(b.end.x, b.position.y), b.end, Vector2(b.position.x, b.end.y)]:
		var cc: Vector2 = c
		var w := to_global(Vector3(cc.x, 0.0, cc.y))
		if first:
			r = Rect2(Vector2(w.x, w.z), Vector2.ZERO)
			first = false
		else:
			r = r.expand(Vector2(w.x, w.z))
	return r


func center_world() -> Vector3:
	var b := spec.bounds()
	var c := b.get_center()
	return to_global(Vector3(c.x, 0.0, c.y))


## Floor height (world y) under a world point, or NAN off the green.
func floor_at(p: Vector3) -> float:
	var l := to_local(p)
	var h := spec.floor_height(l.x, l.z)
	return h + global_position.y if not is_nan(h) else NAN


# --- Build: floors --------------------------------------------------------------------------------

func _felt(kind: String) -> Color:
	var space := spec.theme == "space"
	match kind:
		"plank":
			return Color(0.66, 0.47, 0.3)
		"metal":
			return Color(0.5, 0.55, 0.62)
		"sand":
			return Color(0.93, 0.83, 0.58)
	return Color(0.27, 0.43, 0.88) if space else Color(0.32, 0.72, 0.3)


func _build_floors() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.collision_layer = Defs.L_FLOOR
	body.collision_mask = 0
	add_child(body)
	var k := 0
	for f in spec.floors:
		var pts: PackedVector3Array = f.pts
		if pts.size() < 3:
			continue
		var kind := String(f.get("kind", "felt"))
		var top := _felt(kind).lerp(Color.WHITE, 0.03 * float(k % 2))
		k += 1
		var low := INF
		for p in pts:
			low = minf(low, p.y)
		var bottom := minf(GROUND_Y - 0.02, low - 0.05)
		_prism(st, pts, bottom, top, _side_color(kind))
		# collider: the slab down to FLOOR_DEPTH below its lowest corner
		var cpts := PackedVector3Array()
		for p in pts:
			cpts.append(p)
			cpts.append(Vector3(p.x, low - Defs.FLOOR_DEPTH, p.z))
		var shape := ConvexPolygonShape3D.new()
		shape.points = cpts
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		if kind == "plank":
			_plank_lines(st, pts)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "FloorMesh"
	mi.mesh = st.commit()
	mi.material_override = MeshKit.vertex_material()
	add_child(mi)


func _side_color(kind: String) -> Color:
	if spec.theme == "space":
		return Color(0.32, 0.35, 0.42) if kind != "plank" else Color(0.45, 0.32, 0.2)
	return Color(0.5, 0.36, 0.22) if kind != "metal" else Color(0.4, 0.42, 0.46)


## A convex slab: the top polygon (fan) plus its sides down to `bottom`.
func _prism(st: SurfaceTool, pts: PackedVector3Array, bottom: float, top_c: Color, side_c: Color) -> void:
	var n := pts.size()
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= float(n)
	# make the outline counter-clockwise seen from above (so the top faces up)
	var area := 0.0
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		area += (b.x - a.x) * (b.z + a.z)
	var ordered := pts
	if area > 0.0:
		ordered = PackedVector3Array()
		for i in range(n - 1, -1, -1):
			ordered.append(pts[i])
	for i in n:
		var a := ordered[i]
		var b := ordered[(i + 1) % n]
		st.set_color(top_c)
		st.add_vertex(c + Vector3(0.0, 0.0015, 0.0))
		st.set_color(top_c)
		st.add_vertex(b + Vector3(0.0, 0.0015, 0.0))
		st.set_color(top_c)
		st.add_vertex(a + Vector3(0.0, 0.0015, 0.0))
		var a0 := Vector3(a.x, bottom, a.z)
		var b0 := Vector3(b.x, bottom, b.z)
		for v in [a, b, b0, a, b0, a0]:
			st.set_color(side_c)
			st.add_vertex(v)


func _plank_lines(st: SurfaceTool, pts: PackedVector3Array) -> void:
	# dark seams across a plank bridge, every 0.2 m along its long side
	var a := pts[0]
	var b := pts[1]
	var d := pts[3] if pts.size() > 3 else pts[2]
	var along := b - a
	var across := d - a
	if along.length() < across.length():
		var tmp := along
		along = across
		across = tmp
	var count := int(along.length() / 0.2)
	for i in range(1, count):
		var o := a + along * (float(i) / count)
		var w := across.normalized() * 0.006
		var dl := along.normalized() * 0.006
		var col := Color(0.4, 0.27, 0.16)
		for v in [o - dl, o + dl, o + dl + across, o - dl, o + dl + across, o - dl + across]:
			st.set_color(col)
			st.add_vertex(v + Vector3.UP * 0.003)
		var _u := w


# --- Build: walls, posts, blocks --------------------------------------------------------------------

func _build_walls() -> void:
	var b := MeshKit.Builder.new()
	var space := spec.theme == "space"
	var rails := StaticBody3D.new()
	rails.name = "Rails"
	rails.collision_layer = Defs.L_RAIL
	rails.collision_mask = 0
	add_child(rails)
	var obst := StaticBody3D.new()
	obst.name = "Obstacles"
	obst.collision_layer = Defs.L_OBST
	obst.collision_mask = 0
	add_child(obst)
	var wood := Color(0.6, 0.4, 0.24)
	var cap := Color(0.82, 0.62, 0.38)
	if space:
		wood = Color(0.62, 0.66, 0.74)
		cap = Color(0.3, 0.95, 1.0)
	var stone := Color(0.62, 0.6, 0.56) if not space else Color(0.35, 0.38, 0.46)
	for w in spec.walls:
		var a: Vector3 = w.a
		var c: Vector3 = w.b
		var h := float(w.h)
		var kind := String(w.kind)
		var dir := c - a
		var length := dir.length()
		if length < 0.01:
			continue
		var x := dir / length
		var z := Vector3(-x.z, 0.0, x.x).normalized()
		var y := z.cross(x).normalized()
		var basis := Basis(x, y, z)
		var mid := (a + c) * 0.5
		var lo := minf(a.y, c.y)
		var depth := mid.y - (GROUND_Y - 0.02)
		# visual: the rail down to the ground, plus a cap strip along its top
		var vis_h := h + depth
		var col := wood if kind == "rail" else stone
		b.box(Vector3(length + Defs.WALL_T, vis_h, Defs.WALL_T), Transform3D(basis, mid + y * (h - vis_h * 0.5)), col)
		b.box(Vector3(length + Defs.WALL_T + 0.004, 0.018, Defs.WALL_T + 0.012), Transform3D(basis, mid + y * h), cap if kind == "rail" else col.lightened(0.15), space and kind == "rail")
		var body := rails if kind == "rail" else obst
		body.add_child(Gimmicks.box_shape(Vector3(length + Defs.WALL_T, h + 0.06, Defs.WALL_T), Transform3D(basis, mid + y * (h * 0.5 - 0.03))))
		var _u := lo
	for p in spec.posts:
		var at: Vector3 = p.at
		var r := float(p.r)
		var h2 := float(p.h)
		var look := String(p.look)
		var bumper := bool(p.bumper)
		_post_mesh(b, at, r, h2, look, bumper)
		var holder: StaticBody3D = obst
		if bumper:
			holder = StaticBody3D.new()
			holder.collision_layer = Defs.L_OBST
			holder.collision_mask = 0
			holder.set_meta("mgp_bumper", true)
			add_child(holder)
		holder.add_child(Gimmicks.cyl_shape(r, h2, Transform3D(Basis(), at + Vector3.UP * h2 * 0.5)))
	for k in spec.blocks:
		var at2: Vector3 = k.at
		var size: Vector3 = k.size
		var yaw := float(k.yaw)
		_block_mesh(b, at2, size, yaw, String(k.look))
		obst.add_child(Gimmicks.box_shape(size, Transform3D(Basis(Vector3.UP, yaw), at2 + Vector3.UP * size.y * 0.5)))
	if not b.is_empty():
		var mi := MeshKit.instance(b.build())
		mi.name = "WallMesh"
		add_child(mi)


func _post_mesh(b: MeshKit.Builder, at: Vector3, r: float, h: float, look: String, bumper: bool) -> void:
	var space := spec.theme == "space"
	match look:
		"barrel":
			b.cylinder(r * 0.92, r * 0.92, h, MeshKit.at(at + Vector3.UP * h * 0.5), Color(0.6, 0.38, 0.2), 12)
			b.cylinder(r, r, h * 0.62, MeshKit.at(at + Vector3.UP * h * 0.5), Color(0.55, 0.34, 0.18), 12)
			for yy in [0.15, 0.85]:
				b.cylinder(r * 1.01, r * 1.01, 0.025, MeshKit.at(at + Vector3.UP * h * float(yy)), Color(0.3, 0.3, 0.33), 12)
		"coin":
			b.cylinder(r, r, h, MeshKit.at(at + Vector3.UP * h * 0.5), Color(1.0, 0.8, 0.25), 14)
			b.cylinder(r * 0.7, r * 0.7, h + 0.01, MeshKit.at(at + Vector3.UP * h * 0.5), Color(1.0, 0.9, 0.45), 14)
		"pillar":
			b.cylinder(r, r * 1.1, h, MeshKit.at(at + Vector3.UP * h * 0.5), Color(0.75, 0.78, 0.85) if space else Color(0.78, 0.74, 0.66), 12)
			b.cylinder(r * 1.05, r * 1.05, 0.03, MeshKit.at(at + Vector3.UP * (h - 0.02)), Color(0.3, 0.9, 1.0) if space else Color(0.9, 0.85, 0.75), 12, space)
		_:
			var c := Color(0.95, 0.3, 0.35) if bumper else (Color(0.6, 0.65, 0.75) if space else Color(0.55, 0.52, 0.48))
			b.cylinder(r, r, h, MeshKit.at(at + Vector3.UP * h * 0.5), c, 14)
			if bumper:
				b.torus(r, 0.022, MeshKit.at(at + Vector3.UP * 0.06), Color(1.0, 1.0, 1.0), 14, 6)
				b.torus(r, 0.022, MeshKit.at(at + Vector3.UP * (h - 0.05)), Color(1.0, 1.0, 1.0), 14, 6)
				b.sphere(r * 0.45, MeshKit.at(at + Vector3.UP * (h + 0.02)), Color(1.0, 0.85, 0.3), 10, true)


func _block_mesh(b: MeshKit.Builder, at: Vector3, size: Vector3, yaw: float, look: String) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), at)
	var space := spec.theme == "space"
	match look:
		"crate":
			b.box(size, xf * MeshKit.at(Vector3.UP * size.y * 0.5), Color(0.68, 0.5, 0.3))
			b.box(size * Vector3(1.02, 0.18, 1.02), xf * MeshKit.at(Vector3.UP * size.y * 0.5), Color(0.5, 0.35, 0.2))
		"chest":
			b.rounded_box(size, 0.03, xf * MeshKit.at(Vector3.UP * size.y * 0.5), Color(0.55, 0.33, 0.18))
			b.box(size * Vector3(1.03, 0.12, 1.03), xf * MeshKit.at(Vector3.UP * size.y * 0.62), Color(1.0, 0.8, 0.25))
			b.box(Vector3(0.07, 0.09, 0.02), xf * MeshKit.at(Vector3(0.0, size.y * 0.55, size.z * 0.5 + 0.01)), Color(1.0, 0.85, 0.3), true)
		"console":
			b.rounded_box(size, 0.03, xf * MeshKit.at(Vector3.UP * size.y * 0.5), Color(0.42, 0.46, 0.56))
			b.box(Vector3(size.x * 0.8, 0.012, size.z * 0.6), xf * MeshKit.at(Vector3.UP * (size.y + 0.006)), Color(0.25, 0.9, 1.0), true)
		"skull":
			var c := Color(0.88, 0.85, 0.78)
			b.ellipsoid(Vector3(size.x * 0.5, size.y * 0.55, size.z * 0.5), xf * MeshKit.at(Vector3.UP * size.y * 0.45), c, 14)
			for s in [-1.0, 1.0]:
				b.sphere(size.x * 0.12, xf * MeshKit.at(Vector3(float(s) * size.x * 0.2, size.y * 0.6, size.z * 0.42)), Color(0.08, 0.08, 0.1), 10)
		_:
			var c2 := Color(0.5, 0.52, 0.58) if space else Color(0.6, 0.57, 0.52)
			b.rounded_box(size, minf(0.06, size.y * 0.3), xf * MeshKit.at(Vector3.UP * size.y * 0.5), c2)
			if space:
				b.box(Vector3(size.x * 1.01, 0.02, size.z * 1.01), xf * MeshKit.at(Vector3.UP * size.y * 0.75), Color(0.3, 0.9, 1.0), true)


# --- Build: zones (water planes, belts, low gravity, sand, funnels, boosters) ------------------------

func _build_zones() -> void:
	var deco := MeshKit.Builder.new()
	var space := spec.theme == "space"
	for z in spec.zones:
		var at: Vector3 = z.at
		var size: Vector2 = z.size
		var yaw := float(z.yaw)
		var xf := Transform3D(Basis(Vector3.UP, yaw), at)
		match String(z.type):
			"water":
				var w := MeshInstance3D.new()
				var pm := PlaneMesh.new()
				pm.size = size
				w.mesh = pm
				w.material_override = _water_material()
				w.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, -0.075, at.z))
				w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(w)
				if space:
					w.material_override = _void_material()
			"conveyor":
				var belt := MeshInstance3D.new()
				var bp := PlaneMesh.new()
				bp.size = size
				belt.mesh = bp
				belt.material_override = _belt_material(z.get("dir", Vector2(0, -1)), float(z.get("speed", 1.0)))
				belt.transform = xf * Transform3D(Basis(), Vector3.UP * 0.004)
				add_child(belt)
			"lowgrav":
				var col := Color(0.6, 0.45, 1.0, 0.0)
				deco.box(Vector3(size.x, 0.006, size.y), xf * MeshKit.at(Vector3.UP * 0.003), Color(0.55, 0.4, 1.0), true)
				var p := CPUParticles3D.new()
				p.amount = 18
				p.lifetime = 3.0
				p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
				p.emission_box_extents = Vector3(size.x * 0.5, 0.05, size.y * 0.5)
				p.direction = Vector3.UP
				p.spread = 10.0
				p.gravity = Vector3.UP * 0.05
				p.initial_velocity_min = 0.05
				p.initial_velocity_max = 0.15
				var pm2 := SphereMesh.new()
				pm2.radius = 0.015
				pm2.height = 0.03
				pm2.radial_segments = 6
				pm2.rings = 3
				pm2.material = MeshKit.material(Color(0.75, 0.6, 1.0), 2.0)
				p.mesh = pm2
				p.transform = xf
				add_child(p)
				var _u := col
			"sand":
				deco.box(Vector3(size.x, 0.008, size.y), xf * MeshKit.at(Vector3.UP * 0.004), Color(0.93, 0.83, 0.58))
				for i in 6:
					var o := Vector3(sin(i * 2.3) * size.x * 0.35, 0.009, cos(i * 1.7) * size.y * 0.35)
					deco.disc(0.04, xf * MeshKit.at(o), Color(0.85, 0.74, 0.5), 8)
			"funnel":
				var rad := float(z.get("radius", 0.8))
				for i in 3:
					var rr := rad * (0.4 + 0.3 * i)
					deco.torus(rr, 0.01, MeshKit.at(at + Vector3.UP * 0.004, Vector3(1.0, 0.15, 1.0)), Color(1, 1, 1, 1).lerp(_felt("felt"), 0.55), 28, 4)
			"boost":
				var dir2: Vector2 = z.get("dir", Vector2(0, -1))
				var ang := atan2(-dir2.x, -dir2.y)
				for i in 3:
					var o2 := Vector3(dir2.x, 0.0, dir2.y) * (float(i) - 1.0) * 0.16
					deco.polygon(PackedVector2Array([Vector2(-0.12, -0.03), Vector2(0.0, 0.07), Vector2(0.12, -0.03), Vector2(0.12, -0.08), Vector2(0.0, 0.02), Vector2(-0.12, -0.08)]), 0.004,
						Transform3D(Basis(Vector3.UP, ang) * Basis(Vector3.RIGHT, -PI * 0.5), at + o2 + Vector3.UP * 0.005), Color(1.0, 0.55, 0.15) if not space else Color(0.3, 1.0, 0.6), true)
	if not deco.is_empty():
		add_child(MeshKit.instance(deco.build(), false))


func _water_material() -> StandardMaterial3D:
	if _water_mat == null:
		_water_mat = StandardMaterial3D.new()
		_water_mat.albedo_color = Color(0.15, 0.55, 0.85, 0.88)
		_water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_water_mat.roughness = 0.08
		_water_mat.metallic = 0.25
		_water_mat.emission_enabled = true
		_water_mat.emission = Color(0.05, 0.2, 0.35)
	return _water_mat


func _void_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.02, 0.15)
	m.emission_enabled = true
	m.emission = Color(0.25, 0.1, 0.5)
	m.emission_energy_multiplier = 0.6
	return m


## Scrolling belt stripes (a tiny shader: the belt moves along `dir` in its own plane).
func _belt_material(dir: Vector2, speed: float) -> ShaderMaterial:
	var sh: Shader = ResCache.get_or_make("mgp_belt_shader_v1", func() -> Resource:
		var s := Shader.new()
		s.code = """
shader_type spatial;
uniform vec2 dir = vec2(0.0, -1.0);
uniform float speed = 1.0;
uniform vec3 col_a : source_color = vec3(0.2, 0.22, 0.26);
uniform vec3 col_b : source_color = vec3(1.0, 0.75, 0.2);
varying vec3 wpos;
void vertex() { wpos = VERTEX; }
void fragment() {
	float along = dot(wpos.xz, normalize(dir)) - TIME * speed;
	float across = dot(wpos.xz, vec2(-normalize(dir).y, normalize(dir).x));
	float chev = fract((along + abs(across) * 0.6) * 3.0);
	float m = step(0.55, chev);
	ALBEDO = mix(col_a, col_b, m * 0.85);
	EMISSION = col_b * m * 0.25;
	ROUGHNESS = 0.6;
}
"""
		return s)
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("dir", Vector2(dir.x, dir.y))
	m.set_shader_parameter("speed", speed)
	return m


# --- Build: cup, flag, tee, decor, audience ------------------------------------------------------------

func _build_cup() -> void:
	var space := spec.theme == "space"
	var c := spec.cup
	var mesh: ArrayMesh = ResCache.get_or_make("mgp_cup_%s_v1" % spec.theme, func() -> Resource:
		var b := MeshKit.Builder.new()
		b.disc(Defs.CUP_R, MeshKit.at(Vector3.UP * 0.003), Color(0.02, 0.02, 0.03), 20)
		b.torus(Defs.CUP_R + 0.008, 0.011, MeshKit.at(Vector3.UP * 0.004, Vector3(1.0, 0.35, 1.0)), Color(0.97, 0.97, 0.97), 20, 4)
		b.torus(Defs.CUP_R + 0.05, 0.006, MeshKit.at(Vector3.UP * 0.003, Vector3(1.0, 0.2, 1.0)), Color(0.3, 0.95, 1.0) if space else Color(1.0, 1.0, 1.0, 1.0), 24, 3, space)
		return b.build())
	var cup := MeshKit.instance(mesh, false)
	cup.position = c
	add_child(cup)
	flag = Node3D.new()
	flag.name = "Flag"
	flag.position = c
	add_child(flag)
	var pole: ArrayMesh = ResCache.get_or_make("mgp_flag_%s_v1" % spec.theme, func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cylinder(0.011, 0.011, 1.25, MeshKit.at(Vector3.UP * 0.625), Color(0.96, 0.96, 0.96), 8)
		b.sphere(0.025, MeshKit.at(Vector3.UP * 1.26), Color(1.0, 0.82, 0.3), 8, true)
		var fc := Color(0.15, 0.85, 1.0) if space else Color(0.92, 0.18, 0.2)
		b.polygon(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.4, -0.12), Vector2(0.0, -0.24)]), 0.01, MeshKit.at(Vector3(0.012, 1.24, 0.0)), fc, space)
		return b.build())
	flag.add_child(MeshKit.instance(pole, false))
	for k in 2:
		var l := UiKit.label3d(str(number), 0.075, Color(1, 1, 1), true)
		l.no_depth_test = false
		l.render_priority = 0
		l.outline_render_priority = -1
		l.outline_size = 8
		l.position = Vector3(0.14, 1.12, 0.012 if k == 0 else -0.012)
		l.rotation.y = 0.0 if k == 0 else PI
		flag.add_child(l)


func _build_tee() -> void:
	var space := spec.theme == "space"
	var mat: ArrayMesh = ResCache.get_or_make("mgp_tee_%s_v1" % spec.theme, func() -> Resource:
		var b := MeshKit.Builder.new()
		b.rounded_box(Vector3(0.5, 0.012, 0.42), 0.006, MeshKit.at(Vector3.UP * 0.006), Color(0.12, 0.3, 0.16) if not space else Color(0.15, 0.17, 0.3))
		b.disc(0.035, MeshKit.at(Vector3(0.0, 0.0125, 0.0)), Color(1.0, 0.85, 0.3), 10, space)
		for s in [-1.0, 1.0]:
			b.sphere(0.035, MeshKit.at(Vector3(float(s) * 0.21, 0.03, -0.15)), Color(1.0, 1.0, 1.0) if not space else Color(0.3, 0.95, 1.0), 8, space)
		return b.build())
	var t := MeshKit.instance(mat, false)
	t.position = spec.tee
	var d := tee_dir_local()
	t.rotation.y = atan2(-d.x, -d.z)
	add_child(t)


func tee_dir_local() -> Vector3:
	var target := spec.cup
	if not spec.route.is_empty():
		target = spec.route[0].p
	var d := target - spec.tee
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else Vector3.FORWARD


func _build_decor() -> void:
	if spec.decor.is_empty():
		return
	var b := MeshKit.Builder.new()
	for d in spec.decor:
		var pname := String(d.prop)
		var at: Vector3 = d.at
		var xf := Transform3D(Basis(Vector3.UP, float(d.yaw)).scaled(Vector3.ONE * float(d.scale)), at)
		if MeshKit.PROPS.has(pname):
			b.add_mesh(MeshKit.prop(pname, int(absf(at.x * 7.0 + at.z * 3.0)) % 3), xf)
		elif pname == "skullrock":
			b.ellipsoid(Vector3(0.9, 0.8, 0.8), xf * MeshKit.at(Vector3.UP * 0.6), Color(0.6, 0.58, 0.54), 12)
			for s in [-1.0, 1.0]:
				b.sphere(0.2, xf * MeshKit.at(Vector3(float(s) * 0.32, 0.8, 0.62)), Color(0.08, 0.08, 0.1), 10)
			b.box(Vector3(0.42, 0.16, 0.12), xf * MeshKit.at(Vector3(0.0, 0.08, 0.7)), Color(0.05, 0.05, 0.07))
			b.box(Vector3(0.42, 0.16, 0.12), xf * MeshKit.at(Vector3(0.0, 0.08, -0.7)), Color(0.05, 0.05, 0.07))
			for tx in [-0.12, 0.0, 0.12]:
				b.box(Vector3(0.07, 0.07, 0.04), xf * MeshKit.at(Vector3(float(tx), 0.2, 0.74)), Color(0.95, 0.93, 0.85))
		elif pname == "antenna":
			b.cylinder(0.03, 0.05, 1.6, xf * MeshKit.at(Vector3.UP * 0.8), Color(0.7, 0.74, 0.8), 8)
			b.dome(0.35, xf * MeshKit.at(Vector3(0.0, 1.5, 0.0), Vector3.ONE, Vector3(-0.9, 0.0, 0.0)), Color(0.85, 0.88, 0.92), 12)
			b.sphere(0.05, xf * MeshKit.at(Vector3(0.0, 1.62, 0.25)), Color(1.0, 0.3, 0.3), 8, true)
		elif pname == "satellite":
			b.box(Vector3(0.3, 0.3, 0.3), xf * MeshKit.at(Vector3.UP * 0.6), Color(0.8, 0.75, 0.4))
			for s in [-1.0, 1.0]:
				b.box(Vector3(0.6, 0.02, 0.3), xf * MeshKit.at(Vector3(float(s) * 0.5, 0.6, 0.0)), Color(0.2, 0.35, 0.8), true)
			b.cylinder(0.02, 0.02, 0.6, xf * MeshKit.at(Vector3.UP * 0.3), Color(0.6, 0.62, 0.66), 6)
	add_child(MeshKit.instance(b.build()))


func _build_audience() -> void:
	var b := spec.bounds()
	var cup := spec.cup
	var at := spec.crowd_at
	if at == Vector3.INF:
		var side := spec.crowd_side
		var x := (b.end.x + 0.9) if side > 0.0 else (b.position.x - 0.9)
		at = Vector3(x, GROUND_Y, cup.z)
	var xfs_a: Array = []
	var xfs_b: Array = []
	for i in 10:
		var row := i / 5
		var col := i % 5
		var p := at + Vector3(float(row) * 0.55 * signf(at.x - cup.x), 0.0, (float(col) - 2.0) * 0.5 + (0.25 if row == 1 else 0.0))
		var face := cup - p
		var yaw := atan2(face.x, face.z)
		var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * (0.55 if row == 0 else 0.65)), p + Vector3.UP * float(row) * 0.25)
		if i % 2 == 0:
			xfs_a.append(xf)
		else:
			xfs_b.append(xf)
	var space := spec.theme == "space"
	var holder := Node3D.new()
	holder.name = "Audience"
	add_child(holder)
	var ca := Creatures.crowd(xfs_a, 2, number * 3 + 1, "robot" if space else "crab")
	holder.add_child(ca)
	var cb := Creatures.crowd(xfs_b, 2, number * 5 + 2, "frog" if space else "penguin")
	holder.add_child(cb)
	crowd = holder
	# a little stand under the back row
	var stand := MeshKit.Builder.new()
	stand.box(Vector3(0.7, 0.25, 2.6), MeshKit.at(Vector3(at.x + 0.55 * signf(at.x - cup.x), GROUND_Y + 0.125, at.z)), Color(0.55, 0.38, 0.24) if not space else Color(0.35, 0.38, 0.46))
	holder.add_child(MeshKit.instance(stand.build()))
	# the caddy: a parrot (pirates) or a robot (space) by the tee
	var d := tee_dir_local()
	var right := Vector3(-d.z, 0.0, d.x)
	caddy = Creatures.monster("robot" if space else "bird", {"scale": 0.55 if not space else 0.5, "color": Color(0.2, 0.8, 0.35) if not space else Color(0.75, 0.8, 0.9)})
	caddy.position = spec.tee - right * 0.85 + d * 0.2 + Vector3.UP * (0.0 if space else 0.35)
	add_child(caddy)
	var anim := Creatures.anim(caddy)
	if anim != null:
		anim.face(right + d * 0.5, true)
		if not space:
			anim.flying = true


## Every crowd member cheers (0-1) for a moment; the caddy jumps.
func cheer(amount: float, seconds: float = 2.5) -> void:
	if crowd == null:
		return
	for c in crowd.get_children():
		if c is Creatures.Crowd:
			var cr: Creatures.Crowd = c
			cr.cheer = amount
			var tw := create_tween()
			tw.tween_interval(seconds)
			tw.tween_property(cr, "cheer", 0.0, 0.8)
	if caddy != null:
		var a := Creatures.anim(caddy)
		if a != null:
			a.play("cheer" if amount > 0.5 else "jump")


func caddy_sad() -> void:
	if caddy != null:
		var a := Creatures.anim(caddy)
		if a != null:
			a.play("hurt")


# --- Runtime --------------------------------------------------------------------------------------

## Drive the gimmicks from the hole clock (every machine).
func update(t: float) -> void:
	clock = t
	for g in gimmicks:
		(g as Gimmicks.Gimmick).update(t)
	if flag != null:
		flag.rotation.y = sin(t * 1.6) * 0.18


## Host: set the ball's zone effects for this tick (call before ball.step()).
func zone_effects(ball: Node3D) -> void:
	var b: Object = ball
	var p: Vector3 = ball.global_position
	var l := to_local(p)
	var gs := 1.0
	var dm := 1.0
	var push := Vector3.ZERO
	var awake := false
	var grounded: bool = b.get("grounded")
	var vel: Vector3 = b.get("vel")
	for z in spec.zones:
		if not _in_zone(z, l):
			continue
		match String(z.type):
			"lowgrav":
				gs = float(z.get("g", 0.25))
			"sand":
				dm = float(z.get("decel", 3.0))
			"conveyor":
				awake = true
				if grounded:
					var d2: Vector2 = z.get("dir", Vector2(0, -1))
					var belt := global_basis * Vector3(d2.x, 0.0, d2.y).normalized() * float(z.get("speed", 1.0))
					var vh := Vector3(vel.x, 0.0, vel.z)
					push += (belt - vh) * 2.6
			"funnel":
				var c := z.at as Vector3
				var to := Vector3(c.x - l.x, 0.0, c.z - l.z)
				var d := to.length()
				var rad := float(z.get("radius", 0.8))
				if d > 0.02 and d < rad:
					push += global_basis * (to / d) * float(z.get("accel", 0.8)) * (0.35 + 0.65 * d / rad)
					awake = true
	# kids' assist: a gentle pull into the cup when rolling slowly past it
	var cl := to_local(p)
	var tc := Vector3(spec.cup.x - cl.x, 0.0, spec.cup.z - cl.z)
	var dc := tc.length()
	var sp := vel.length()
	if dc < Defs.ASSIST_R and dc > 0.01 and sp < 1.1 and grounded and absf(cl.y - spec.cup.y - Defs.BALL_R) < 0.05:
		push += global_basis * (tc / dc) * Defs.ASSIST_ACCEL * (1.0 - dc / Defs.ASSIST_R + 0.3)
		awake = awake or sp > 0.02
	for g in gimmicks:
		if (g as Gimmicks.Gimmick).influence(p):
			awake = true
			break
	b.set("gscale", gs)
	b.set("decel_mult", dm)
	b.set("push", push)
	b.set("keep_awake", awake)


func _in_zone(z: Dictionary, l: Vector3) -> bool:
	var at: Vector3 = z.at
	var size: Vector2 = z.size
	var d := Vector3(l.x - at.x, 0.0, l.z - at.z)
	var yaw := float(z.get("yaw", 0.0))
	if yaw != 0.0:
		d = Basis(Vector3.UP, -yaw) * d
	if String(z.type) == "funnel":
		return d.length() < float(z.get("radius", 0.8))
	return absf(d.x) <= size.x * 0.5 and absf(d.z) <= size.y * 0.5 and l.y < at.y + 0.6


## Host: what happened to this ball on the course this tick. Returns "" or one of:
## "cup", "lip", "water", "oob", "portal", "cannon", "loop", "boost", "box:<i>".
func course_event(ball: Node3D) -> String:
	var b: Object = ball
	if String(b.get("state")) != "play" or b.get("rail") != null:
		return ""
	var p: Vector3 = ball.global_position
	var l := to_local(p)
	var vel: Vector3 = b.get("vel")
	var sp := vel.length()
	# cup
	var dc := Vector2(l.x - spec.cup.x, l.z - spec.cup.z).length()
	if dc < Defs.CUP_R and absf(l.y - spec.cup.y - Defs.BALL_R) < 0.07:
		if sp < Defs.CAPTURE_SPEED or (dc < Defs.CUP_R * 0.45 and sp < Defs.CAPTURE_SPEED * 1.35):
			return "cup"
		return "lip"
	# water and falling off
	for z in spec.zones:
		if String(z.type) == "water" and _in_zone(z, l) and l.y < -0.035:
			return "water"
	var bb := spec.bounds().grow(3.0)
	if l.y < -0.55 or not bb.has_point(Vector2(l.x, l.z)):
		return "oob"
	# party-mode boxes
	for i in boxes.size():
		var bx: Gimmicks.PowerBox = boxes[i]
		if not bx.taken and bx.visible and Vector2(l.x - bx.position.x, l.z - bx.position.z).length() < 0.2 and absf(l.y - bx.position.y) < 0.3:
			return "box:%d" % i
	for gi in gimmicks.size():
		var g: Gimmicks.Gimmick = gimmicks[gi]
		var gt := String(g.g.get("type", ""))
		if gt == "portal" and float(b.get("portal_cool")) <= 0.0:
			var a: Vector3 = g.g.get("a", Vector3.ZERO)
			if Vector2(l.x - a.x, l.z - a.z).length() < 0.2 and absf(l.y - a.y) < 0.12:
				return "portal:%d" % gi
		elif gt == "cannon":
			var c: Vector3 = g.g.get("at", Vector3.ZERO)
			if Vector2(l.x - c.x, l.z - c.z).length() < 0.2 and absf(l.y - c.y) < 0.12:
				return "cannon:%d" % gi
		elif gt == "loop":
			var lp: Gimmicks.Loop = g
			var rel := l - lp.start
			var along := rel.dot(lp.fwd)
			var lat := rel.dot(lp.right)
			var vl := global_basis.inverse() * vel
			if along > -0.06 and along < 0.14 and absf(lat) < 0.2 and vl.dot(lp.fwd) > 0.25 and absf(rel.y - Defs.BALL_R) < 0.08:
				return "loop:%d" % gi
	for z in spec.zones:
		if String(z.type) == "boost" and _in_zone(z, l):
			var d2: Vector2 = z.get("dir", Vector2(0, -1))
			var bd := global_basis * Vector3(d2.x, 0.0, d2.y).normalized()
			if vel.dot(bd) < float(z.get("speed", 3.8)) - 0.05:
				return "boost:%s" % str(float(z.get("speed", 3.8)))
	return ""


## Ballistic launch velocity from `from` to land on `to` after `t` seconds.
static func launch_velocity(from: Vector3, to: Vector3, t: float) -> Vector3:
	var d := to - from
	return Vector3(d.x / t, d.y / t + 0.5 * Defs.GRAVITY * t, d.z / t)
