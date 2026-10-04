extends Node3D
## OBSTACLE RUSH: the base of every course. A course script extends this, fills in its description
## in describe() and builds itself in build_course() with the helpers below:
##   box_top / ramp / disc_top / bumper / rail  static pieces: ONE merged vertex-coloured mesh for the
##                                              whole course + one StaticBody3D with many shapes
##   add_obstacle(...)                         moving obstacles (core of the replicated phase list)
##   add_route / add_checkpoint / set_finish   where CPU runners go, where you respawn, where it ends
##   stands / gate / balloons / backdrop        the show: crowds, arches, flags, candy hills
## Only the current course is loaded; main frees it before building the next one.
## Both machines build the same course from (course id, seed), so door patterns and the like match.

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Creatures := preload("res://core/creatures.gd")
const Obs := preload("res://games/obstacle_rush/obstacles.gd")

const PASTELS: Array[Color] = [Color(1.0, 0.62, 0.78), Color(0.55, 0.82, 1.0), Color(1.0, 0.86, 0.45),
	Color(0.6, 0.92, 0.65), Color(0.78, 0.66, 1.0), Color(1.0, 0.72, 0.5)]
const TRIM := Color(0.98, 0.97, 0.94)
const GOO_SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform vec4 col_a : source_color = vec4(0.98, 0.42, 0.78, 1.0);
uniform vec4 col_b : source_color = vec4(0.62, 0.32, 0.98, 1.0);
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float w = sin(wp.x * 0.31 + TIME * 1.1) * 0.5 + sin(wp.z * 0.23 - TIME * 0.8 + wp.x * 0.1) * 0.5;
	float bub = smoothstep(0.92, 1.0, sin(wp.x * 1.7 + TIME * 0.6) * sin(wp.z * 1.9 - TIME * 0.5));
	vec3 c = mix(col_a.rgb, col_b.rgb, w * 0.5 + 0.5) + vec3(bub * 0.35);
	ALBEDO = c;
	ROUGHNESS = 0.18;
	EMISSION = c * 0.22;
}
"""

# --- Description (describe()) ---
var course_id := ""
var title := ""
var style := "race"  ## race | survival | team | hunt | final
var style_name := "RACE"
var tagline := ""
var tips: Array[String] = []
var music_mood := "race"
var sky_preset := "day"
var duration := 120.0
var kill_y := -10.0
var goo_y := -8.0
var qualify_frac := 0.7
var palette: Array[Color] = PASTELS.duplicate()

# --- Built data ---
var main: Node
var seed_value := 0
var rng := RandomNumberGenerator.new()
var spawns: Array[Vector3] = []
var spawn_yaw := 0.0
var route: Array[Vector3] = []
var route_w: Array[float] = []
var route_jump: Array[bool] = []
var alt_routes: Array = []  ## extra CPU routes: each [points, widths, jumps]
var checkpoints: Array[Vector3] = []
var checkpoint_yaw: Array[float] = []
var checkpoint_prog: Array[float] = []
var finish_box := AABB()
var has_finish := false
var booth_feet := Vector3(26, 14, -40)
var booth_yaw := PI * 0.5
var bridge_spots: Array = []  ## [center Vector3, yaw float, length float]
var cheer_spots: Array[Vector3] = []  ## confetti cannons (the Game Master's CHEER)
var podium_spot := Vector3.ZERO
var obstacles: Array = []  ## Obs.Obstacle, in build order (replicated by index)
var hazards: Array = []  ## obstacles that knock runners
var seesaws: Array = []
var tilts: Array = []
var spinners: Array = []
var hex: Obs.HexField
var crowd: Node3D
var ct := 0.0  ## course clock (seconds since built)
var spin_mult := 1.0  ## Game Master SPIN boost (host; mirrored)
var base_mult := 1.0  ## course's own speed-up over time (survival)
var twist := 0.0  ## Game Master TILT wheel -1..1 (host; mirrored)
var host := true
var _cum: Array[float] = []
var _b: MeshKit.Builder
var _static: StaticBody3D
var _goo: MeshInstance3D


# --- To override ---------------------------------------------------------------------------------

## Set the description fields (title, style, tagline, tips, mood, duration...).
func describe() -> void:
	pass


## Build the geometry, obstacles, route, checkpoints, finish and spawns.
func build_course() -> void:
	pass


## Host: course rules every physics tick (runners = Array of runner nodes in play).
func host_rules(_dt: float, _runners: Array) -> void:
	pass


## A CPU runner's next target, or Vector3.INF to follow the route (arenas override this).
func cpu_target(_r: Node, _brain: RefCounted) -> Vector3:
	return Vector3.INF


## Route point i for a CPU runner (lets a course move it, e.g. to the door it picked).
func route_point(_i: int, p: Vector3, _brain: RefCounted) -> Vector3:
	return p


## Can the Game Master use `action` here? Returns "" if yes, else a short reason.
func gm_block_reason(action: String) -> String:
	if action == "bridge" and bridge_spots.is_empty() and not has_method("gm_repair"):
		return "No gaps to bridge here"
	return ""


# --- Setup ------------------------------------------------------------------------------------------

## Called by main: describe, build, bake.
func setup(m: Node, seed_v: int, is_host: bool) -> void:
	main = m
	seed_value = seed_v
	host = is_host
	rng.seed = seed_v
	describe()
	_b = MeshKit.Builder.new()
	_static = StaticBody3D.new()
	_static.name = "Static"
	_static.collision_layer = Obs.L_WORLD
	_static.collision_mask = 0
	add_child(_static)
	build_course()
	_bake()
	_compute_route()


func _bake() -> void:
	if not _b.is_empty():
		var mi := MeshKit.instance(_b.build())
		mi.name = "CourseMesh"
		add_child(mi)
	_b = MeshKit.Builder.new()
	goo(goo_y)


# --- Static pieces --------------------------------------------------------------------------------

## A solid box whose TOP is at top_center (size x/z footprint, y thickness). rot in radians (YXZ).
func box_top(top_center: Vector3, size: Vector3, color: Color, rot: Vector3 = Vector3.ZERO, meta: Dictionary = {}, radius: float = 0.14) -> CollisionShape3D:
	var basis := Basis.from_euler(rot)
	var center := top_center - basis * Vector3(0, size.y * 0.5, 0)
	return box_at(center, size, color, rot, meta, radius)


## A solid box centred at `center`.
func box_at(center: Vector3, size: Vector3, color: Color, rot: Vector3 = Vector3.ZERO, meta: Dictionary = {}, radius: float = 0.14) -> CollisionShape3D:
	var basis := Basis.from_euler(rot)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(basis, center)
	if meta.is_empty():
		_static.add_child(cs)
	else:
		var body := StaticBody3D.new()
		body.collision_layer = Obs.L_WORLD
		body.collision_mask = 0
		for k in meta:
			body.set_meta(str(k), meta[k])
		body.add_child(cs)
		add_child(body)
	if radius > 0.0 and minf(size.x, minf(size.y, size.z)) > radius * 2.2:
		_b.rounded_box(size, radius, Transform3D(basis, center), color, 1)
	else:
		_b.box(size, Transform3D(basis, center), color)
	return cs


## A floor slab with a white trim lip round its top edge (the candy look). Top at top_center.
func slab(top_center: Vector3, size: Vector3, color: Color, meta: Dictionary = {}) -> void:
	box_top(top_center, size, color, Vector3.ZERO, meta)
	var t := top_center + Vector3(0, -0.02, 0)
	for side in [-1.0, 1.0]:
		var s: float = side
		_b.box(Vector3(0.16, 0.12, size.z), MeshKit.at(t + Vector3(s * (size.x * 0.5 - 0.02), -0.03, 0)), TRIM)
		_b.box(Vector3(size.x, 0.12, 0.16), MeshKit.at(t + Vector3(0, -0.03, s * (size.z * 0.5 - 0.02))), TRIM)


## A checkerboard floor of tiles (visual) on one collider.
func checker_slab(top_center: Vector3, size: Vector3, a: Color, b: Color, tile: float = 2.0) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = top_center - Vector3(0, size.y * 0.5, 0)
	_static.add_child(cs)
	_b.box(Vector3(size.x, size.y - 0.04, size.z), MeshKit.at(top_center - Vector3(0, size.y * 0.5 + 0.02, 0)), a.darkened(0.15))
	var nx := maxi(1, int(round(size.x / tile)))
	var nz := maxi(1, int(round(size.z / tile)))
	for i in nx:
		for j in nz:
			var c := a if (i + j) % 2 == 0 else b
			var p := top_center + Vector3(-size.x * 0.5 + (i + 0.5) * size.x / nx, -0.03, -size.z * 0.5 + (j + 0.5) * size.z / nz)
			_b.box(Vector3(size.x / nx - 0.03, 0.06, size.z / nz - 0.03), MeshKit.at(p), c)


## A sloped walkway from `a` to `b` (points on its top surface, centre line), `width` wide.
func ramp(a: Vector3, b: Vector3, width: float, color: Color, thick: float = 0.6) -> void:
	var d := b - a
	var flat := Vector2(d.x, d.z)
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, flat.length())
	var length := d.length()
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var mid := (a + b) * 0.5 - basis * Vector3(0, thick * 0.5, 0)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, thick, length)
	cs.shape = bs
	cs.transform = Transform3D(basis, mid)
	_static.add_child(cs)
	_b.rounded_box(Vector3(width, thick, length), 0.12, Transform3D(basis, mid), color, 1)
	var n := int(length / 1.2)
	for k in n:
		var p := a.lerp(b, (k + 0.5) / n) + basis * Vector3(0, 0.02, 0)
		_b.box(Vector3(width * 0.9, 0.04, 0.12), Transform3D(basis, p), TRIM)


## A round platform (top at top_center).
func disc_top(top_center: Vector3, radius: float, thick: float, color: Color, meta: Dictionary = {}) -> void:
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = thick
	cs.shape = cyl
	cs.position = top_center - Vector3(0, thick * 0.5, 0)
	if meta.is_empty():
		_static.add_child(cs)
	else:
		var body := StaticBody3D.new()
		body.collision_layer = Obs.L_WORLD
		for k in meta:
			body.set_meta(str(k), meta[k])
		body.add_child(cs)
		add_child(body)
	_b.cylinder(radius, radius * 0.94, thick, MeshKit.at(cs.position), color, 28)
	_b.torus(radius - 0.06, 0.08, MeshKit.at(top_center + Vector3(0, -0.02, 0)), TRIM, 28, 5)


## A springy round pillar runners bounce off.
func bumper(base: Vector3, radius: float = 0.6, height: float = 1.4, color: Color = Color(1.0, 0.4, 0.5)) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Obs.L_WORLD
	body.set_meta("kind", "bumper")
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	cs.shape = cyl
	cs.position = base + Vector3(0, height * 0.5, 0)
	body.add_child(cs)
	add_child(body)
	_b.cylinder(radius, radius * 1.05, height, MeshKit.at(base + Vector3(0, height * 0.5, 0)), color, 16)
	_b.torus(radius * 1.02, 0.09, MeshKit.at(base + Vector3(0, height * 0.75, 0)), TRIM, 16, 5)
	_b.dome(radius, MeshKit.at(base + Vector3(0, height, 0)), color.lightened(0.3), 16)


## A low rail along a line (keeps runners on, can be jumped). Top at a.y + height.
func rail(a: Vector3, b: Vector3, height: float = 0.7, color: Color = TRIM) -> void:
	var d := b - a
	var length := Vector2(d.x, d.z).length()
	var yaw := atan2(-d.x, -d.z)
	var mid := (a + b) * 0.5 + Vector3(0, height * 0.5, 0)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.3, height, length)
	cs.shape = bs
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), mid)
	_static.add_child(cs)
	_b.rounded_box(Vector3(0.3, height, length), 0.1, Transform3D(Basis(Vector3.UP, yaw), mid), color, 1)
	var n := int(length / 2.0)
	for k in n + 1:
		var p := a.lerp(b, float(k) / maxf(1.0, n)) + Vector3(0, height + 0.12, 0)
		_b.sphere(0.2, MeshKit.at(p), palette[k % palette.size()], 8)


## A wall (solid) from a to b.
func wall(a: Vector3, b: Vector3, height: float, color: Color, thick: float = 0.5) -> void:
	var d := b - a
	var length := Vector2(d.x, d.z).length()
	var yaw := atan2(-d.x, -d.z)
	var mid := (a + b) * 0.5 + Vector3(0, height * 0.5, 0)
	box_at(mid, Vector3(thick, height, length), color, Vector3(0, yaw, 0))


# --- Obstacles ---------------------------------------------------------------------------------------

## Add a moving obstacle at a transform (it is added to the tree, then set up). Returns it.
func add_obstacle(o: Node3D, at: Vector3, yaw: float = 0.0) -> Node3D:
	add_child(o)
	o.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	if o.has_method("setup"):
		o.call("setup")
	obstacles.append(o)
	if o is Obs.Sweeper or o is Obs.Hammer:
		hazards.append(o)
	if o is Obs.Seesaw:
		seesaws.append(o)
	if o is Obs.TiltDeck:
		tilts.append(o)
	if o is Obs.Spinner:
		spinners.append(o)
	return o


func sweeper(center: Vector3, length: float, omega: float, arms: int = 2, height: float = 0.55, color: Color = Obs.RED, start: float = 0.0) -> Obs.Sweeper:
	var s := Obs.Sweeper.new()
	s.length = length
	s.omega = omega
	s.arms = arms
	s.height = height
	s.color = color
	s.start = start
	add_obstacle(s, center)
	return s


func hammer(pivot: Vector3, lane_yaw: float, arm: float, omega: float, offset: float, amp: float = 1.1, color: Color = Obs.PINK) -> Obs.Hammer:
	var h := Obs.Hammer.new()
	h.arm = arm
	h.omega = omega
	h.offset = offset
	h.amp = amp
	h.color = color
	add_obstacle(h, pivot, lane_yaw)
	return h


func spinner(top_center: Vector3, radius: float, omega: float, color: Color = Obs.BLUE) -> Obs.Spinner:
	var s := Obs.Spinner.new()
	s.radius = radius
	s.omega = omega
	s.color = color
	add_obstacle(s, top_center)
	return s


func seesaw(top_center: Vector3, size: Vector3, color: Color = Obs.YELLOW) -> Obs.Seesaw:
	var s := Obs.Seesaw.new()
	s.size = size
	s.color = color
	s.host = host
	add_obstacle(s, top_center - Vector3(0, size.y * 0.5, 0))
	return s


func tilt_deck(top_center: Vector3, size: Vector3, color: Color = Obs.MINT, wobble: float = 0.05) -> Obs.TiltDeck:
	var t := Obs.TiltDeck.new()
	t.size = size
	t.color = color
	t.wobble = wobble
	t.host = host
	add_obstacle(t, top_center - Vector3(0, size.y * 0.5, 0))
	return t


func conveyor(top_center: Vector3, size: Vector3, push_dir: Vector3, speed: float) -> Obs.Conveyor:
	var c := Obs.Conveyor.new()
	c.size = size
	c.dir = push_dir.normalized()
	c.speed = speed
	add_obstacle(c, top_center - Vector3(0, size.y * 0.5, 0))
	return c


func door_row(center: Vector3, width: float, count: int, real_count: int) -> Obs.DoorRow:
	var d := Obs.DoorRow.new()
	d.width = width
	d.count = count
	var idx: Array[int] = []
	for i in count:
		idx.append(i)
	# deterministic shuffle from the course seed
	for i in range(count - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := idx[i]
		idx[i] = idx[j]
		idx[j] = tmp
	for k in real_count:
		d.real.append(idx[k])
	add_obstacle(d, center)
	return d


# --- Route, checkpoints, finish ----------------------------------------------------------------------

## A CPU route point: `w` = how far left/right of it a runner may aim, `jump` = jump just before it.
func add_route(p: Vector3, w: float = 1.0, jump: bool = false) -> void:
	route.append(p)
	route_w.append(w)
	route_jump.append(jump)


## A respawn spot (in route order).
func add_checkpoint(p: Vector3, yaw: float = 0.0) -> void:
	checkpoints.append(p)
	checkpoint_yaw.append(yaw)


func set_finish(center: Vector3, size: Vector3) -> void:
	finish_box = AABB(center - size * 0.5, size)
	has_finish = true


func at_finish(p: Vector3) -> bool:
	return has_finish and finish_box.has_point(p + Vector3.UP * 0.5)


func _compute_route() -> void:
	_cum.clear()
	var total := 0.0
	for i in route.size():
		if i > 0:
			total += route[i].distance_to(route[i - 1])
		_cum.append(total)
	checkpoint_prog.clear()
	for c in checkpoints:
		checkpoint_prog.append(progress(c))


## Distance along the route to the point nearest p (for rankings and checkpoints).
func progress(p: Vector3) -> float:
	if route.size() < 2:
		return 0.0
	var best := INF
	var best_prog := 0.0
	for i in route.size() - 1:
		var a := route[i]
		var b := route[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var q := a + ab * t
		var d := q.distance_to(p)
		if d < best - 0.001:
			best = d
			best_prog = _cum[i] + ab.length() * t
	return best_prog


func route_length() -> float:
	return _cum[_cum.size() - 1] if not _cum.is_empty() else 1.0


## Position on the route at progress `s` (metres along it).
func point_at(s: float) -> Vector3:
	if route.is_empty():
		return Vector3.ZERO
	for i in route.size() - 1:
		if s <= _cum[i + 1]:
			var seg := _cum[i + 1] - _cum[i]
			return route[i].lerp(route[i + 1], clampf((s - _cum[i]) / maxf(seg, 0.001), 0.0, 1.0))
	return route[route.size() - 1]


## Index of the latest checkpoint at or before progress `prog`.
func checkpoint_index(prog: float) -> int:
	var best := 0
	for i in checkpoints.size():
		if checkpoint_prog[i] <= prog + 0.5:
			best = i
	return best


## Where runner number k of n starts (a grid behind the start line).
func spawn_for(k: int) -> Vector3:
	if spawns.is_empty():
		return Vector3(0, 0.1, 0)
	return spawns[k % spawns.size()]


# --- Hits and planning --------------------------------------------------------------------------------

## Knock impulse for a runner touching any hazard (Vector3.ZERO: none).
func hazard_hit(r: Node3D) -> Vector3:
	for h in hazards:
		var imp: Vector3 = h.hit(r)
		if imp != Vector3.ZERO:
			return imp
	return Vector3.ZERO


## For CPU runners: 0 = safe, 1 = a low bar is coming (jump), 2 = something you can't jump (wait).
func threat(feet: Vector3, t_ahead: float) -> int:
	var out := 0
	for h in hazards:
		if h.threat(feet, t_ahead):
			if h.jumpable:
				out = maxi(out, 1)
			else:
				return 2
	return out


# --- Per tick (both machines) ---------------------------------------------------------------------------

func tick(dt: float) -> void:
	ct += dt
	var m := spin_mult * base_mult
	for o in obstacles:
		o.speed_mult = m
		if o is Obs.TiltDeck:
			(o as Obs.TiltDeck).target = twist
		o.tick(dt)
	if hex != null:
		hex.tick(dt, host)


## Host: seesaw loads etc. from the runners on the course.
func host_tick(dt: float, runners: Array) -> void:
	for s in seesaws:
		var ss: Obs.Seesaw = s
		for r in runners:
			var rn: Node3D = r
			if rn.visible and ss.over(rn.global_position):
				ss.loads.append(ss.lateral(rn.global_position))
	host_rules(dt, runners)


# --- Replication ------------------------------------------------------------------------------------

func net_values() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.append(ct)
	out.append(spin_mult)
	out.append(base_mult)
	out.append(twist)
	for o in obstacles:
		out.append(o.net_value())
	return out


func apply_net_values(v: PackedFloat32Array) -> void:
	if v.size() < 4:
		return
	ct = v[0]
	spin_mult = v[1]
	base_mult = v[2]
	twist = v[3]
	for i in mini(obstacles.size(), v.size() - 4):
		obstacles[i].set_net_phase(v[i + 4])


## Extra replicated bytes (hex tiles, dropped ring segments...).
func net_bits() -> PackedByteArray:
	if hex != null:
		return hex.bits()
	return PackedByteArray()


func apply_net_bits(b: PackedByteArray) -> void:
	if hex != null:
		hex.apply_bits(b)


# --- Game Master helpers -----------------------------------------------------------------------------

## Where to put a helper pad near progress `prog` (a bit ahead of a struggling runner): [pos, yaw] or [].
func helper_spot(kind: String, prog: float) -> Array:
	if kind == "bridge":
		var best: Array = []
		var best_d := INF
		for b in bridge_spots:
			var bs: Array = b
			var c: Vector3 = bs[0]
			var bp := progress(c)
			var d := bp - prog
			if d > -12.0 and absf(d) < best_d:
				best_d = absf(d)
				best = bs
		return best
	var space := get_world_3d().direct_space_state
	for k in 8:
		var s := prog + 5.0 + k * 2.0
		var p := point_at(s)
		var ahead := point_at(s + 2.0)
		var yaw := atan2(-(ahead.x - p.x), -(ahead.z - p.z))
		var side := Vector3(cos(yaw), 0.0, -sin(yaw)) * rng.randf_range(-1.2, 1.2)
		var from := p + side + Vector3.UP * 3.0
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 8.0, Obs.L_WORLD)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		var col: Object = hit["collider"]
		if n.y < 0.95 or col is AnimatableBody3D:
			continue
		if col is StaticBody3D and (col as StaticBody3D).has_meta("kind"):
			continue
		return [hit["position"], yaw]
	return []


# --- Show decoration -------------------------------------------------------------------------------

## The goo everything falls into: a big wobbly candy-slime plane.
func goo(y: float) -> void:
	if _goo != null:
		return
	_goo = MeshInstance3D.new()
	_goo.name = "Goo"
	var pm := PlaneMesh.new()
	pm.size = Vector2(420, 420)
	pm.subdivide_width = 0
	pm.subdivide_depth = 0
	_goo.mesh = pm
	var mat: ShaderMaterial = ResCache.get_or_make("or_goo_mat_v1", func() -> Resource:
		var sh := Shader.new()
		sh.code = GOO_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		return m)
	_goo.material_override = mat
	_goo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_goo.position = Vector3(0, y, -40)
	add_child(_goo)


## Bleachers with a cheering crowd along a line (a to b), the crowd facing `facing`.
func stands(a: Vector3, b: Vector3, facing: Vector3, rows: int = 3, density: float = 1.1, seed_add: int = 0) -> void:
	var d := b - a
	var length := Vector2(d.x, d.z).length()
	var along := Vector3(d.x, 0, d.z).normalized()
	var back := -Vector3(facing.x, 0, facing.z).normalized()
	var yaw := atan2(-along.x, -along.z)
	var xfs: Array = []
	var per_row := int(length * density)
	for r in rows:
		var step_top := a + back * (r * 1.4 + 0.7) + Vector3(0, r * 0.9 + 0.5, 0)
		var center := step_top + along * length * 0.5 - Vector3(0, (r * 0.9 + 0.5) * 0.5 + 0.5, 0)
		_b.box(Vector3(length + 0.4, r * 0.9 + 1.5, 1.4), Transform3D(Basis(Vector3.UP, yaw), center), palette[r % palette.size()].darkened(0.1 + r * 0.05))
		_b.box(Vector3(length + 0.4, 0.1, 0.12), Transform3D(Basis(Vector3.UP, yaw), step_top + along * length * 0.5 + facing.normalized() * 0.65), TRIM)
		for i in per_row:
			var t := (i + 0.5 + rng.randf_range(-0.25, 0.25)) / per_row
			var p := step_top + along * length * t + back * rng.randf_range(-0.2, 0.2)
			var face_yaw := atan2(facing.x, facing.z) + rng.randf_range(-0.3, 0.3)
			xfs.append(Transform3D(Basis(Vector3.UP, face_yaw).scaled(Vector3.ONE * rng.randf_range(0.82, 1.0)), p))
	# back wall with flags
	var top := a + back * (rows * 1.4 + 0.4) + Vector3(0, rows * 0.9 + 0.5, 0)
	_b.box(Vector3(length + 0.4, 2.2, 0.3), Transform3D(Basis(Vector3.UP, yaw), top + along * length * 0.5 + Vector3(0, 0.6, 0)), Color(0.35, 0.3, 0.55))
	var nflags := int(length / 4.0)
	for k in nflags + 1:
		var fp := top + along * length * float(k) / maxf(1.0, nflags) + Vector3(0, 1.7, 0)
		_b.cylinder(0.05, 0.05, 1.8, MeshKit.at(fp + Vector3(0, 0.9, 0)), TRIM, 6)
		_b.polygon(PackedVector2Array([Vector2(0, 0), Vector2(0.9, 0.3), Vector2(0, 0.6)]), 0.03,
			Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), fp + Vector3(0, 1.4, 0)), palette[k % palette.size()])
	if xfs.is_empty():
		return
	if crowd == null:
		crowd = Node3D.new()
		crowd.name = "Crowds"
		add_child(crowd)
	var c := Creatures.crowd(xfs, 4, 7 + seed_add + seed_value % 5, "humanoid")
	crowd.add_child(c)


## Set how excited the crowds are (0..1).
func set_cheer(v: float) -> void:
	if crowd == null:
		return
	for c in crowd.get_children():
		if "cheer" in c:
			c.set("cheer", v)


## An arch over the course with a big world-space word (START / FINISH). Text faces +Z (towards
## runners coming from +Z) unless yaw turns it.
func gate(center: Vector3, width: float, word: String, color: Color, yaw: float = 0.0) -> void:
	var basis := Basis(Vector3.UP, yaw)
	for side in [-1.0, 1.0]:
		var s: float = side
		var p := center + basis * Vector3(s * (width * 0.5 + 0.4), 0, 0)
		box_at(p + Vector3(0, 2.6, 0), Vector3(0.8, 5.2, 0.8), color, Vector3(0, yaw, 0))
		_b.sphere(0.6, MeshKit.at(p + Vector3(0, 5.5, 0)), Obs.YELLOW, 12)
		for k in 4:
			_b.torus(0.48, 0.07, Transform3D(basis, p + Vector3(0, 0.6 + k * 1.2, 0)), TRIM, 12, 4)
	_b.rounded_box(Vector3(width + 1.6, 1.4, 0.6), 0.2, Transform3D(basis, center + Vector3(0, 5.1, 0)), color.darkened(0.15), 1)
	for k in int(width / 1.2) + 1:
		var lp := center + basis * Vector3(-width * 0.5 + k * 1.2, 4.35, 0.32)
		_b.sphere(0.12, MeshKit.at(lp), [Obs.YELLOW, Color.WHITE, Obs.PINK][k % 3] as Color, 6, true)
	if word == "FINISH":
		for k in int(width / 0.8):
			for row in 2:
				var cp := center + basis * Vector3(-width * 0.5 + (k + 0.5) * 0.8, 0.012, (row - 0.5) * 0.8)
				_b.box(Vector3(0.78, 0.03, 0.78), Transform3D(basis, cp), Color.WHITE if (k + row) % 2 == 0 else Color(0.1, 0.1, 0.12))
	for f in [1.0, -1.0]:
		var face: float = f
		var l := Label3D.new()
		l.text = word
		l.font_size = 120
		l.pixel_size = 0.012
		l.outline_size = 24
		l.modulate = Color(1, 1, 1)
		l.outline_modulate = color.darkened(0.6)
		l.position = center + basis * Vector3(0, 5.1, 0.34 * face)
		l.rotation.y = yaw + (0.0 if face > 0.0 else PI)
		l.no_depth_test = false
		add_child(l)


## Floating balloons (visual only).
func balloons(center: Vector3, count: int, spread: float) -> void:
	for k in count:
		var p := center + Vector3(rng.randf_range(-spread, spread), rng.randf_range(0.0, 3.0), rng.randf_range(-spread, spread))
		var c: Color = palette[k % palette.size()]
		_b.ellipsoid(Vector3(0.5, 0.62, 0.5), MeshKit.at(p), c, 10)
		_b.cylinder(0.01, 0.01, 2.0, MeshKit.at(p + Vector3(0, -1.6, 0)), TRIM, 3)


## Candy hills, lollipops and clouds far away (one merged mesh).
func backdrop(center: Vector3, radius: float) -> void:
	var b := MeshKit.Builder.new()
	for k in 16:
		var a := TAU * k / 16.0 + rng.randf_range(-0.15, 0.15)
		var r := radius + rng.randf_range(0.0, 40.0)
		var p := center + Vector3(cos(a) * r, -30.0 + rng.randf_range(-6, 4), sin(a) * r)
		var c: Color = palette[k % palette.size()]
		var s := rng.randf_range(14.0, 26.0)
		b.dome(s, MeshKit.at(p, Vector3(1.0, rng.randf_range(0.8, 1.6), 1.0)), c.lightened(0.15), 14)
		if k % 3 == 0:
			var lp := p + Vector3(0, s * 1.2, 0)
			b.cylinder(0.6, 0.6, s * 1.2, MeshKit.at(p + Vector3(0, s * 0.6, 0)), TRIM, 8)
			b.cylinder(5.0, 5.0, 1.2, MeshKit.at(lp, Vector3.ONE, Vector3(PI * 0.5, a, 0)), palette[(k + 2) % palette.size()], 18)
			b.torus(3.2, 0.6, MeshKit.at(lp + Vector3(0, 0, 0), Vector3.ONE, Vector3(PI * 0.5, a, 0)), TRIM, 18, 6)
	var mi := MeshKit.instance(b.build(), false)
	mi.name = "Backdrop"
	add_child(mi)


## Little confetti cannons (visual) at the spots the CHEER button fires from.
func cannons(spots: Array[Vector3]) -> void:
	for p in spots:
		cheer_spots.append(p)
		_b.cylinder(0.35, 0.45, 0.5, MeshKit.at(p + Vector3(0, 0.25, 0)), Color(0.3, 0.3, 0.4), 10)
		_b.cylinder(0.25, 0.3, 0.9, MeshKit.aim(p + Vector3(0, 0.8, 0), Vector3(0, 1, 0.2)), Obs.PINK, 10)
		_b.torus(0.27, 0.06, MeshKit.aim(p + Vector3(0, 1.22, 0.08), Vector3(0, 1, 0.2)), Obs.YELLOW, 10, 4)
