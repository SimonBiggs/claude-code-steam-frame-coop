extends Node3D
## LEO'S CORNER (simple mode): the story that grows beside the goal (layout from matchgen.gd).
##  - LEO'S STAR in the goal: on a star kick a big glowing gold star turns in the goal mouth where it shines
##    (main.star_now). A kick aimed at it that doesn't miss sends it flying to Leo (fly_star).
##  - STAR SOCKETS over Leo's head: one per star he asks for this match, lit gold as they come in.
##  - LION CUBS: Leo's fan club, one per play-day, bouncing beside him (they jump on goals and saves).
##  - PRIZES: one per star goal reached (scarf, balloon, drum, bunting, foam hand, trophy...), kept over days;
##    TODAY'S MATCH prizes wear a gold star. Ten prizes: Leo wears a crown.
## Every machine builds the same from main's synced values (set_family, set_tally, star_now), so the TV and
## Decks draw it from the host's snapshot and "leo" events. Cheap: one merged mesh per thing, no physics.

const MeshKit := preload("res://games/penalty_shootout/mesh_kit.gd")
const MatchGen := preload("res://games/penalty_shootout/matchgen.gd")
const GOLD := Color(1.0, 0.82, 0.2)
const SCARVES: Array[Color] = [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 1.0), Color(0.2, 0.85, 0.4), Color(1.0, 0.85, 0.15),
	Color(0.8, 0.4, 1.0), Color(1.0, 0.55, 0.15)]

var main
var star_mesh: ArrayMesh
var star_mat: StandardMaterial3D
var dim_mat: StandardMaterial3D
var goal_star: MeshInstance3D
var goal_star_glow: MeshInstance3D
var sockets: Array[MeshInstance3D] = []
var cubs_root: Node3D
var prizes_root: Node3D
var crown: Node3D
var flyers: Array = []  # [node, from, to, t]
var family_key := ""
var prize_total := 0
var tally_got := -1
var tally_goal := -1
var t := 0.0
var cheer_t := 0.0
var last_new: Node3D


func build() -> void:
	star_mesh = make_star_mesh(0.5, 0.22, 0.06)
	star_mat = StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.albedo_color = GOLD
	star_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	dim_mat = StandardMaterial3D.new()
	dim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dim_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.35)
	dim_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	goal_star = _star_node(star_mat)
	goal_star.top_level = true
	goal_star.visible = false
	add_child(goal_star)
	goal_star_glow = MeshInstance3D.new()  # a soft halo behind it
	var halo := SphereMesh.new()
	halo.radius = 0.5
	halo.height = 1.0
	halo.radial_segments = 16
	halo.rings = 8
	goal_star_glow.mesh = halo
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.albedo_color = Color(1.0, 0.9, 0.4, 0.22)
	goal_star_glow.material_override = hm
	goal_star_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	goal_star_glow.scale = Vector3(1.0, 1.0, 0.15)
	goal_star.add_child(goal_star_glow)
	for i in MatchGen.GOAL_MAX:
		var s := _star_node(dim_mat)
		s.top_level = true
		s.visible = false
		add_child(s)
		sockets.append(s)
	cubs_root = Node3D.new()
	cubs_root.name = "Cubs"
	add_child(cubs_root)
	prizes_root = Node3D.new()
	prizes_root.name = "Prizes"
	add_child(prizes_root)


func _star_node(mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = star_mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## A chunky five-point star in the xy plane (facing +z), r_out to the tips.
static func make_star_mesh(r_out: float, r_in: float, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim: Array[Vector2] = []
	for i in 10:
		var a := PI * 0.5 + TAU * i / 10.0
		var r := r_out if i % 2 == 0 else r_in
		rim.append(Vector2(cos(a), sin(a)) * r)
	for side in [1.0, -1.0]:
		var c := Vector3(0, 0, depth * side)
		for i in 10:
			var a: Vector2 = rim[i]
			var b: Vector2 = rim[(i + 1) % 10]
			st.add_vertex(c)
			if side > 0.0:
				st.add_vertex(Vector3(b.x, b.y, 0.0))
				st.add_vertex(Vector3(a.x, a.y, 0.0))
			else:
				st.add_vertex(Vector3(a.x, a.y, 0.0))
				st.add_vertex(Vector3(b.x, b.y, 0.0))
	st.generate_normals()
	return st.commit()


## Every machine: the cubs (one per play-day), the prizes ([[kind, day, golden], ...]) and Leo's crown.
func set_family(prizes: Array, days: int, crowned: bool) -> void:
	var key := var_to_str([prizes, days, crowned])
	if key == family_key:
		return
	var grown := family_key != ""
	family_key = key
	var old_cubs := cubs_root.get_child_count()
	for root in [cubs_root, prizes_root]:
		for c in (root as Node3D).get_children():
			root.remove_child(c)
			c.queue_free()
	last_new = null
	for i in MatchGen.cubs(days):
		var cub := MeshInstance3D.new()
		cub.name = "Cub%d" % i
		cub.mesh = cub_mesh(SCARVES[i % SCARVES.size()])
		cub.material_override = MeshKit.vertex_material(main.mats)
		cub.position = MatchGen.cub_slot(i)
		cub.rotation.y = 0.5
		cubs_root.add_child(cub)
		if grown and i >= old_cubs:
			_pop_in(cub, 1.0)
	for i in mini(prizes.size(), MatchGen.PRIZE_KEEP):
		var e: Array = prizes[i]
		var pr := MeshInstance3D.new()
		pr.name = "Prize%d" % i
		pr.mesh = prize_mesh(String(e[0]), bool(e[2]) if e.size() > 2 else false)
		pr.material_override = MeshKit.vertex_material(main.mats)
		pr.position = MatchGen.prize_slot(i)
		pr.rotation.y = 0.45
		prizes_root.add_child(pr)
		if grown and prizes.size() != prize_total and i == mini(prizes.size(), MatchGen.PRIZE_KEEP) - 1:
			_pop_in(pr, 1.0)
			last_new = pr
	prize_total = prizes.size()
	_set_crown(crowned)


func _pop_in(n: Node3D, s: float) -> void:
	n.scale = Vector3.ONE * 0.05
	n.create_tween().tween_property(n, "scale", Vector3.ONE * s, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_crown(on: bool) -> void:
	var mascot: Node3D = main.world.mascot if main.world != null else null
	if mascot == null:
		return
	if on and crown == null:
		crown = MeshInstance3D.new()
		(crown as MeshInstance3D).mesh = crown_mesh()
		(crown as MeshInstance3D).material_override = MeshKit.vertex_material(main.mats)
		crown.position = Vector3(0, 2.02, 0.02)
		mascot.add_child(crown)
	elif not on and crown != null:
		crown.queue_free()
		crown = null


## Every machine: Leo's star sockets for this match (goal of them, got lit).
func set_tally(got: int, goal: int) -> void:
	goal = clampi(goal, 0, MatchGen.GOAL_MAX)
	if got == tally_got and goal == tally_goal:
		return
	var more := goal == tally_goal and got > tally_got
	tally_got = got
	tally_goal = goal
	for i in sockets.size():
		var s := sockets[i]
		s.visible = i < goal
		if i < goal:
			s.global_position = MatchGen.star_socket(i, goal)
			s.material_override = star_mat if i < got else dim_mat
			if more and i == got - 1:
				_pop_in(s, 1.0)


## Every machine: a star flies from `from` (the goal mouth) to the next socket over Leo's head.
func fly_star(from: Vector3, socket: int, goal: int) -> void:
	var n := _star_node(star_mat)
	n.top_level = true
	add_child(n)
	n.global_position = from
	flyers.append([n, from, MatchGen.star_socket(clampi(socket, 0, maxi(0, goal - 1)), maxi(1, goal)), 0.0])
	cheer_t = 2.0


## Every machine: the cubs jump for joy for a moment.
func cheer() -> void:
	cheer_t = 2.0


func _process(delta: float) -> void:
	t += delta
	cheer_t = maxf(0.0, cheer_t - delta)
	# The star in the goal mouth.
	var sn: Vector2 = main.star_now
	var show_star: bool = sn != Vector2.INF and (main.state == "aim" or main.state == "runup" or main.state == "flight")
	goal_star.visible = show_star
	if show_star:
		goal_star.global_position = Vector3(sn.x, sn.y, 0.08)
		goal_star.rotation = Vector3(0.0, sin(t * 2.0) * 0.6, t * 0.6)
		var pulse := 0.85 + 0.12 * sin(t * 6.0)
		goal_star.scale = Vector3.ONE * pulse * 1.25
	# Sockets turn gently.
	for i in sockets.size():
		if sockets[i].visible:
			sockets[i].rotation.y = sin(t * 1.5 + i) * 0.5
	# Flying stars: an arc over to Leo.
	for f in flyers.duplicate():
		var n: Node3D = f[0]
		f[3] = float(f[3]) + delta
		var k := clampf(float(f[3]) / 1.1, 0.0, 1.0)
		var from: Vector3 = f[1]
		var to: Vector3 = f[2]
		n.global_position = from.lerp(to, k) + Vector3.UP * sin(k * PI) * 2.2
		n.rotation.y = k * TAU * 2.0
		n.scale = Vector3.ONE * (1.3 - 0.3 * k)
		if k >= 1.0:
			flyers.erase(f)
			n.queue_free()
			if main.has_method("on_star_landed"):
				main.on_star_landed()
	# Cubs bounce (jump high when cheering).
	var i := 0
	for c in cubs_root.get_children():
		var hop := absf(sin(t * (9.0 if cheer_t > 0.0 else 3.0) + i * 0.9)) * (0.35 if cheer_t > 0.0 else 0.05)
		(c as Node3D).position.y = hop
		i += 1
	if last_new != null and is_instance_valid(last_new):
		last_new.rotation.y = 0.45 + sin(t * 2.0) * 0.25


# --- Meshes --------------------------------------------------------------------------------------

## A lion cub fan (~0.7 m) with a scarf in its colour, facing +z.
static func cub_mesh(scarf: Color) -> ArrayMesh:
	var fur := Color(1.0, 0.74, 0.3)
	var mane := Color(0.88, 0.48, 0.14)
	return MeshKit.merge([
		[MeshKit.sphere(0.17, 10), MeshKit.at(Vector3(0, 0.2, 0), Vector3(1.0, 1.1, 0.9)), fur],
		[MeshKit.cyl(0.14, 0.16, 0.06, 10), MeshKit.at(Vector3(0, 0.36, 0)), scarf],
		[MeshKit.box(Vector3(0.07, 0.16, 0.03)), MeshKit.at(Vector3(0.06, 0.28, 0.15)), scarf],
		[MeshKit.sphere(0.2, 12), MeshKit.at(Vector3(0, 0.52, -0.02)), mane],
		[MeshKit.sphere(0.15, 12), MeshKit.at(Vector3(0, 0.52, 0.06)), fur],
		[MeshKit.sphere(0.06, 8), MeshKit.at(Vector3(0, 0.47, 0.19), Vector3(1.2, 0.8, 0.8)), Color(1.0, 0.9, 0.72)],
		[MeshKit.sphere(0.025, 6), MeshKit.at(Vector3(0, 0.5, 0.24)), Color(0.3, 0.15, 0.1)],
		[MeshKit.sphere(0.028, 6), MeshKit.at(Vector3(-0.055, 0.56, 0.18)), Color(0.05, 0.05, 0.1)],
		[MeshKit.sphere(0.028, 6), MeshKit.at(Vector3(0.055, 0.56, 0.18)), Color(0.05, 0.05, 0.1)],
		[MeshKit.sphere(0.05, 6), MeshKit.at(Vector3(-0.12, 0.66, 0.0)), fur],
		[MeshKit.sphere(0.05, 6), MeshKit.at(Vector3(0.12, 0.66, 0.0)), fur],
		[MeshKit.cyl(0.04, 0.04, 0.26, 6), MeshKit.at(Vector3(-0.17, 0.42, 0.02), Vector3.ONE, Vector3(0, 0, 0.5)), fur],  # arms up
		[MeshKit.cyl(0.04, 0.04, 0.26, 6), MeshKit.at(Vector3(0.17, 0.42, 0.02), Vector3.ONE, Vector3(0, 0, -0.5)), fur],
		[MeshKit.sphere(0.06, 6), MeshKit.at(Vector3(-0.08, 0.04, 0.05)), fur],
		[MeshKit.sphere(0.06, 6), MeshKit.at(Vector3(0.08, 0.04, 0.05)), fur],
	])


## Leo's crown.
static func crown_mesh() -> ArrayMesh:
	var parts: Array = [[MeshKit.cyl(0.24, 0.22, 0.12, 14), MeshKit.at(Vector3.ZERO), GOLD]]
	for k in 5:
		var a := TAU * k / 5.0
		parts.append([MeshKit.cyl(0.0, 0.06, 0.16, 6), MeshKit.at(Vector3(cos(a) * 0.2, 0.13, sin(a) * 0.2)), GOLD])
		parts.append([MeshKit.sphere(0.03, 6), MeshKit.at(Vector3(cos(a) * 0.2, 0.22, sin(a) * 0.2)), Color(1.0, 0.25, 0.3)])
	return MeshKit.merge(parts)


## One of Leo's prizes (~1 m), facing +z; golden = a TODAY'S MATCH prize (a gold star on top).
static func prize_mesh(kind: String, golden: bool) -> ArrayMesh:
	var parts: Array = []
	var top := 1.1
	match kind:
		"scarf":  # a long striped supporters' scarf on a stand
			parts.append([MeshKit.cyl(0.03, 0.03, 1.2, 6), MeshKit.at(Vector3(-0.4, 0.6, 0)), Color(0.5, 0.35, 0.2)])
			parts.append([MeshKit.cyl(0.03, 0.03, 1.2, 6), MeshKit.at(Vector3(0.4, 0.6, 0)), Color(0.5, 0.35, 0.2)])
			parts.append([MeshKit.box(Vector3(0.9, 0.05, 0.05)), MeshKit.at(Vector3(0, 1.18, 0)), Color(0.5, 0.35, 0.2)])
			for k in 7:
				var c := Color(0.9, 0.2, 0.2) if k % 2 == 0 else Color(1, 1, 1)
				parts.append([MeshKit.box(Vector3(0.7, 0.12, 0.03)), MeshKit.at(Vector3(0, 1.08 - k * 0.12, 0.02)), c])
			top = 1.25
		"balloon":  # a bunch of three balloons tied to a weight
			parts.append([MeshKit.cyl(0.12, 0.14, 0.12, 8), MeshKit.at(Vector3(0, 0.06, 0)), Color(0.4, 0.4, 0.45)])
			var cols := [Color(1.0, 0.3, 0.35), Color(0.3, 0.6, 1.0), Color(1.0, 0.85, 0.2)]
			for k in 3:
				var off := Vector3((k - 1) * 0.22, 1.0 + (0.12 if k == 1 else 0.0), 0.0)
				parts.append([MeshKit.cyl(0.006, 0.006, off.y - 0.1, 4), MeshKit.at(Vector3(off.x * 0.5, (off.y + 0.1) * 0.5, 0), Vector3.ONE,
					Vector3(0, 0, -atan2(off.x * 0.5, off.y))), Color(0.9, 0.9, 0.9)])
				parts.append([MeshKit.sphere(0.17, 10), MeshKit.at(off + Vector3.UP * 0.1, Vector3(1.0, 1.2, 1.0)), cols[k]])
			top = 1.5
		"drum":  # a big red supporters' drum on a stand
			parts.append([MeshKit.cyl(0.03, 0.03, 0.5, 6), MeshKit.at(Vector3(-0.25, 0.25, 0)), Color(0.3, 0.3, 0.35)])
			parts.append([MeshKit.cyl(0.03, 0.03, 0.5, 6), MeshKit.at(Vector3(0.25, 0.25, 0)), Color(0.3, 0.3, 0.35)])
			parts.append([MeshKit.cyl(0.36, 0.36, 0.42, 16), MeshKit.at(Vector3(0, 0.75, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.9, 0.2, 0.2)])
			parts.append([MeshKit.cyl(0.37, 0.37, 0.05, 16), MeshKit.at(Vector3(0, 0.75, 0.2), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.96, 0.93, 0.85)])
			parts.append([MeshKit.cyl(0.38, 0.38, 0.05, 16), MeshKit.at(Vector3(0, 0.75, -0.2), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), GOLD])
			parts.append([MeshKit.cyl(0.02, 0.02, 0.45, 6), MeshKit.at(Vector3(0.3, 1.15, 0.25), Vector3.ONE, Vector3(0.3, 0, 0.6)), Color(0.6, 0.4, 0.2)])
			parts.append([MeshKit.sphere(0.06, 6), MeshKit.at(Vector3(0.18, 0.97, 0.18)), Color(1, 1, 1)])
			top = 1.25
		"bunting":  # two poles with a string of coloured flags
			parts.append([MeshKit.cyl(0.03, 0.03, 1.3, 6), MeshKit.at(Vector3(-0.5, 0.65, 0)), Color(0.95, 0.95, 0.95)])
			parts.append([MeshKit.cyl(0.03, 0.03, 1.3, 6), MeshKit.at(Vector3(0.5, 0.65, 0)), Color(0.95, 0.95, 0.95)])
			var fc := [Color(1.0, 0.3, 0.3), Color(1.0, 0.85, 0.2), Color(0.3, 0.6, 1.0), Color(0.3, 0.85, 0.4), Color(0.85, 0.45, 1.0)]
			for k in 5:
				var x := -0.4 + k * 0.2
				var y := 1.2 - sin((k + 0.5) / 5.0 * PI) * 0.12
				parts.append([MeshKit.box(Vector3(0.12, 0.12, 0.02)), MeshKit.at(Vector3(x, y - 0.06, 0), Vector3.ONE, Vector3(0, 0, PI * 0.25)), fc[k]])
			top = 1.4
		"foamhand":  # a giant blue foam "number one" hand on a stick
			var c := Color(0.25, 0.7, 1.0)
			parts.append([MeshKit.cyl(0.03, 0.03, 0.7, 6), MeshKit.at(Vector3(0, 0.35, 0)), Color(0.6, 0.4, 0.2)])
			parts.append([MeshKit.box(Vector3(0.3, 0.2, 0.2)), MeshKit.at(Vector3(0, 0.8, 0)), c.darkened(0.15)])
			parts.append([MeshKit.sphere(0.2, 10), MeshKit.at(Vector3(0, 1.0, 0), Vector3(1.0, 0.9, 0.8)), c])
			parts.append([MeshKit.cyl(0.07, 0.07, 0.4, 8), MeshKit.at(Vector3(0, 1.32, 0)), c])
			parts.append([MeshKit.sphere(0.07, 8), MeshKit.at(Vector3(0, 1.52, 0)), c])
			parts.append([MeshKit.sphere(0.07, 8), MeshKit.at(Vector3(0.2, 1.02, 0.06), Vector3(1.0, 1.4, 1.0)), c])
			top = 1.65
		"trophy":  # a shiny gold cup on a plinth
			parts.append([MeshKit.box(Vector3(0.4, 0.3, 0.4)), MeshKit.at(Vector3(0, 0.15, 0)), Color(0.25, 0.2, 0.18)])
			parts.append([MeshKit.cyl(0.05, 0.12, 0.3, 10), MeshKit.at(Vector3(0, 0.45, 0)), GOLD])
			parts.append([MeshKit.cyl(0.26, 0.1, 0.4, 14), MeshKit.at(Vector3(0, 0.8, 0)), GOLD])
			parts.append([MeshKit.sphere(0.08, 6), MeshKit.at(Vector3(-0.28, 0.85, 0), Vector3(0.6, 1.4, 0.6)), GOLD])
			parts.append([MeshKit.sphere(0.08, 6), MeshKit.at(Vector3(0.28, 0.85, 0), Vector3(0.6, 1.4, 0.6)), GOLD])
			top = 1.1
		_:
			parts.append([MeshKit.sphere(0.3, 10), MeshKit.at(Vector3(0, 0.3, 0)), Color(1, 1, 1)])
	if golden:  # TODAY'S MATCH: a gold star on top
		parts.append([MeshKit.sphere(0.1, 8), MeshKit.at(Vector3(0, top + 0.1, 0), Vector3(1.0, 1.0, 0.4)), GOLD])
		for k in 5:
			var a := PI * 0.5 + TAU * k / 5.0
			parts.append([MeshKit.cyl(0.0, 0.05, 0.14, 4), MeshKit.at(Vector3(cos(a) * 0.12, top + 0.1 + sin(a) * 0.12, 0), Vector3.ONE,
				Vector3(0, 0, a - PI * 0.5)), GOLD])
	return MeshKit.merge(parts)
