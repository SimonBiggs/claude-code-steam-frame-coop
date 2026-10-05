extends Node3D
## SIMPLE_MODE toys round the table, in reach of the VR giant (Simon's rule: everything you can reach
## does something). Touch them with either hand:
##   little trees and flags on the board's rim wobble, the bell by the goal rings (it also rings when a
##   marble gets home), the toy windmill on the left stool spins, the tiny lighthouse lights up and
##   sweeps its beam, and the spare marbles in the bowl on the right stool get nudged - or grab one with
##   the right trigger and throw it (they bounce on the floor, roll on the board and pop back home).
## Cheap: one merged mesh for the stools, the rim toys share a few meshes, the spare marbles are one
## MultiMesh. Only the host simulates the toys; touches are sent to the TV machine as "prop" events.

const SPARE := 5
const SPARE_R := 0.022
const TOUCH := 0.07
const STOOL_X := 0.86
const STOOL_Z := 0.42
const STOOL_DROP := 0.12  # stool tops sit this far below the board
const BOWL_R := 0.075

var main
var stools_root: Node3D
var legs: MeshInstance3D
# Wobbly things: [node, spring angle, spring speed, axis, touch height]. 0..2 trees, 3..4 flags, 5 bell.
var wobblers: Array = []
var bell: Node3D
var windmill_blades: Node3D
var windmill_spin := 0.6
var lamp: MeshInstance3D
var lamp_mat: StandardMaterial3D
var beam: MeshInstance3D
var light_t := 0.0
var spare_mm: MultiMesh
var spare_pos: Array[Vector3] = []
var spare_vel: Array[Vector3] = []
var spare_state: Array[int] = []  # 0 in the bowl, 1 rolling free, 2 held
var spare_rest: Array[float] = []
var held := -1
var trig_was := false
var last_hand := [Vector3.ZERO, Vector3.ZERO]
var hand_vel := [Vector3.ZERO, Vector3.ZERO]
var touching := {}  # prop id -> true while a hand is on it (one reaction per touch)
var touched := {}  # prop id -> true once ever (bots)
var t := 0.0


func _ready() -> void:
	_build_stools()
	_build_rim_toys()
	_build_spares()


func _mat(col: Color, glow: float = 0.0) -> StandardMaterial3D:
	return main.make_material(col, glow)


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func stool_top(side: int) -> Vector3:
	return Vector3(STOOL_X * side, main.board_y - STOOL_DROP, STOOL_Z)


func windmill_pos() -> Vector3:
	return stool_top(-1) + Vector3(-0.045, 0.0, -0.035)


func lighthouse_pos() -> Vector3:
	return stool_top(-1) + Vector3(0.06, 0.0, 0.05)


func bowl_pos() -> Vector3:
	return stool_top(1)


# --- Building -----------------------------------------------------------------------

func _build_stools() -> void:
	stools_root = Node3D.new()
	add_child(stools_root)
	var wood := Color(0.72, 0.5, 0.32)
	var white := Color(0.97, 0.96, 0.92)
	var red := Color(0.9, 0.25, 0.25)
	var parts: Array = []
	for side in [-1.0, 1.0]:
		var top := Vector3(STOOL_X * side, 0.0, STOOL_Z)
		parts.append([main.cyl_mesh(0.15, 0.15, 0.03, 18), Transform3D(Basis(), top + Vector3(0, -0.015, 0)), wood])
	# The bowl (an open dish: a squashed ring and a base) on the right stool.
	var bowl := Vector3(STOOL_X, 0.0, STOOL_Z)
	parts.append([main.cyl_mesh(BOWL_R, BOWL_R * 0.7, 0.012, 16), Transform3D(Basis(), bowl + Vector3(0, 0.006, 0)), Color(0.4, 0.75, 1.0)])
	var ring := TorusMesh.new()
	ring.inner_radius = BOWL_R - 0.01
	ring.outer_radius = BOWL_R + 0.008
	ring.rings = 16
	ring.ring_segments = 6
	parts.append([ring, Transform3D(Basis.from_scale(Vector3(1.0, 2.0, 1.0)), bowl + Vector3(0, 0.022, 0)), Color(0.4, 0.75, 1.0)])
	# The windmill's tower and the lighthouse's striped body (the moving bits are separate).
	var wm := windmill_pos() - stool_top(-1) + Vector3(-STOOL_X, 0.0, STOOL_Z)
	parts.append([main.cyl_mesh(0.018, 0.032, 0.15, 8), Transform3D(Basis(), wm + Vector3(0, 0.075, 0)), Color(0.95, 0.85, 0.6)])
	parts.append([main.cyl_mesh(0.0, 0.03, 0.04, 8), Transform3D(Basis(), wm + Vector3(0, 0.17, 0)), red])
	var lh := lighthouse_pos() - stool_top(-1) + Vector3(-STOOL_X, 0.0, STOOL_Z)
	for k in 4:
		var r0 := 0.026 - k * 0.003
		parts.append([main.cyl_mesh(r0 - 0.003, r0, 0.035, 10), Transform3D(Basis(), lh + Vector3(0, 0.0175 + k * 0.035, 0)), red if k % 2 == 0 else white])
	parts.append([main.cyl_mesh(0.0, 0.022, 0.025, 10), Transform3D(Basis(), lh + Vector3(0, 0.185, 0)), red])
	var mi := MeshInstance3D.new()
	mi.mesh = main.merged_mesh("mm_stools", parts)
	mi.material_override = main.vertex_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stools_root.add_child(mi)
	# Stool legs: unit-tall, stretched to the table height every frame.
	legs = MeshInstance3D.new()
	legs.mesh = main.merged_mesh("mm_legs", [
		[main.cyl_mesh(0.03, 0.05, 1.0, 8), Transform3D(Basis(), Vector3(-STOOL_X, 0.5, STOOL_Z)), wood.darkened(0.2)],
		[main.cyl_mesh(0.03, 0.05, 1.0, 8), Transform3D(Basis(), Vector3(STOOL_X, 0.5, STOOL_Z)), wood.darkened(0.2)]])
	legs.material_override = main.vertex_mat()
	add_child(legs)
	# Windmill sails (four paddles facing the giant) and the lighthouse lamp + beam.
	windmill_blades = Node3D.new()
	windmill_blades.position = wm + Vector3(0, 0.14, 0.035)
	stools_root.add_child(windmill_blades)
	var sails := []
	for k in 4:
		var b := Basis(Vector3.BACK, k * PI * 0.5)
		sails.append([main.box_mesh(Vector3(0.016, 0.075, 0.004)), Transform3D(b, b * Vector3(0, 0.042, 0)), [Color(1, 1, 1), Color(0.3, 0.6, 1.0)][k % 2]])
	sails.append([main.sphere_mesh(0.01), Transform3D(), red])
	var sm := MeshInstance3D.new()
	sm.mesh = main.merged_mesh("mm_sails", sails)
	sm.material_override = main.vertex_mat()
	sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	windmill_blades.add_child(sm)
	lamp_mat = StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.95, 0.6)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.9, 0.4)
	lamp_mat.emission_energy_multiplier = 0.2
	lamp = _part(stools_root, main.sphere_mesh(0.016), lamp_mat, lh + Vector3(0, 0.158, 0))
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(1.0, 0.95, 0.5, 0.3)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cone := CylinderMesh.new()
	cone.top_radius = 0.004
	cone.bottom_radius = 0.06
	cone.height = 0.35
	cone.radial_segments = 8
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	beam = MeshInstance3D.new()
	beam.mesh = cone
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lamp.add_child(beam)
	beam.visible = false


## Trees on three corners of the board's rim, two flags on the near edge and the goal bell. They're
## children of the board, so they tilt with it.
func _build_rim_toys() -> void:
	var board = main.board
	var tree_parts := [
		[main.cyl_mesh(0.006, 0.008, 0.04, 6), Transform3D(Basis(), Vector3(0, 0.02, 0)), Color(0.55, 0.36, 0.2)],
		[main.sphere_mesh(0.026), Transform3D(Basis.from_scale(Vector3(1.0, 1.15, 1.0)), Vector3(0, 0.062, 0)), Color(0.3, 0.75, 0.3)],
		[main.sphere_mesh(0.018), Transform3D(Basis(), Vector3(0.012, 0.085, 0.004)), Color(0.4, 0.85, 0.35)]]
	var tree_mesh: ArrayMesh = main.merged_mesh("mm_tree", tree_parts)
	var flag_mesh: ArrayMesh = main.merged_mesh("mm_flag", [
		[main.cyl_mesh(0.003, 0.003, 0.09, 6), Transform3D(Basis(), Vector3(0, 0.045, 0)), Color(0.95, 0.95, 0.95)],
		[main.box_mesh(Vector3(0.04, 0.026, 0.003)), Transform3D(Basis(), Vector3(0.021, 0.075, 0)), Color(1.0, 0.4, 0.3)]])
	var flag_mesh2: ArrayMesh = main.merged_mesh("mm_flag2", [
		[main.cyl_mesh(0.003, 0.003, 0.09, 6), Transform3D(Basis(), Vector3(0, 0.045, 0)), Color(0.95, 0.95, 0.95)],
		[main.box_mesh(Vector3(0.04, 0.026, 0.003)), Transform3D(Basis(), Vector3(0.021, 0.075, 0)), Color(1.0, 0.85, 0.2)]])
	var spots: Array = [[tree_mesh, Vector2i(0, 9)], [tree_mesh, Vector2i(0, 0)], [tree_mesh, Vector2i(11, 0)],
		[flag_mesh, Vector2i(3, 9)], [flag_mesh2, Vector2i(7, 9)]]
	for s in spots:
		var cell: Vector2i = s[1]
		var c: Vector2 = board.center(cell.x, cell.y)
		var n := Node3D.new()
		n.position = Vector3(c.x, board.WALL_H - 0.002, c.y)
		board.add_child(n)
		var mi := MeshInstance3D.new()
		mi.mesh = s[0]
		mi.material_override = main.vertex_mat()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
		wobblers.append([n, 0.0, 0.0, Vector3(1, 0, 0.3).normalized(), 0.055])
	# The bell: a little golden dome hanging from a post, beside the goal (moved each level).
	bell = Node3D.new()
	board.add_child(bell)
	var post := _part(bell, main.cyl_mesh(0.003, 0.003, 0.09, 6), _mat(Color(0.5, 0.35, 0.2)), Vector3(0, 0.045, 0))
	post.name = "Post"
	var swing := Node3D.new()
	swing.name = "Swing"
	swing.position = Vector3(0, 0.088, 0)
	bell.add_child(swing)
	_part(swing, main.cyl_mesh(0.008, 0.022, 0.03, 12), _mat(Color(1.0, 0.8, 0.25), 0.4), Vector3(0, -0.018, 0))
	_part(swing, main.sphere_mesh(0.006), _mat(Color(0.5, 0.35, 0.2)), Vector3(0, -0.036, 0))
	wobblers.append([swing, 0.0, 0.0, Vector3(0, 0, 1), -0.018])
	on_level()


func _build_spares() -> void:
	spare_mm = MultiMesh.new()
	spare_mm.transform_format = MultiMesh.TRANSFORM_3D
	spare_mm.use_colors = true
	spare_mm.mesh = main.sphere_mesh(SPARE_R)
	spare_mm.instance_count = SPARE
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = spare_mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.2
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.top_level = true
	add_child(mmi)
	var cols: Array[Color] = [Color(1.0, 0.35, 0.35), Color(0.3, 0.6, 1.0), Color(1.0, 0.85, 0.2), Color(0.4, 0.9, 0.45), Color(0.85, 0.45, 1.0)]
	for i in SPARE:
		spare_mm.set_instance_color(i, cols[i % cols.size()])
		spare_pos.append(_bowl_spot(i))
		spare_vel.append(Vector3.ZERO)
		spare_state.append(0)
		spare_rest.append(0.0)


func _bowl_spot(i: int) -> Vector3:
	if i == 0:
		return bowl_pos() + Vector3(0, 0.012 + SPARE_R, 0)
	var a := i * TAU / 4.0
	return bowl_pos() + Vector3(cos(a) * 0.042, 0.016 + SPARE_R, sin(a) * 0.042)


## A new level: move the bell next to the goal (onto the nearest rim wall, preferring the near edge).
func on_level() -> void:
	var board = main.board
	if bell == null or board.rows.is_empty():
		return
	var g: Vector2i = board.cell_of(board.goal)
	var best := Vector2i(g.x, board.H - 1)
	var bd := 999.0
	for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
		var c: Vector2i = g + d
		if board.ch(c.x, c.y) != "#":
			continue
		var score := float(d.length()) - (0.5 if c.y == board.H - 1 else 0.0)
		if score < bd:
			bd = score
			best = c
	var p: Vector2 = board.center(best.x, best.y)
	bell.position = Vector3(p.x, board.WALL_H - 0.002, p.y)


# --- Reactions (host: from touches; TV machine: from "prop" events) ---------------------

## id: 0..4 rim trees/flags, 5 bell, 6 windmill, 7 lighthouse.
func react(id: int, broadcast: bool = true) -> void:
	touched[id] = true
	if id >= 0 and id < wobblers.size():
		var w: Array = wobblers[id]
		w[2] = 9.0 if id == 5 else 6.0
		if id == 5:
			main.sound("bell", -2.0, 1.0)
		else:
			main.sound("rustle", -8.0, randf_range(0.9, 1.3))
	elif id == 6:
		windmill_spin = 14.0
		main.sound("whirr", -6.0)
	elif id == 7:
		light_t = 5.0
		main.sound("horn", -6.0)
	if broadcast and main.net != null and main.net.mode == "host":
		main.net.event("prop", [id])


func ring_bell(broadcast: bool = true) -> void:
	react(5, broadcast)


func _process(delta: float) -> void:
	t += delta
	stools_root.position.y = main.board_y - STOOL_DROP
	legs.scale = Vector3(1.0, maxf(0.05, main.board_y - STOOL_DROP - 0.03), 1.0)
	for w in wobblers:
		var n: Node3D = w[0]
		var a: float = w[1]
		var sp: float = w[2]
		sp += (-60.0 * a - 3.0 * sp) * delta
		a += sp * delta
		w[1] = a
		w[2] = sp
		n.basis = Basis(w[3], a * 0.5) if absf(a) > 0.0005 else Basis()
	windmill_spin = move_toward(windmill_spin, 0.6, delta * 3.0)
	windmill_blades.rotate_z(-windmill_spin * delta)
	light_t = maxf(0.0, light_t - delta)
	lamp_mat.emission_energy_multiplier = 3.0 if light_t > 0.0 else 0.2
	beam.visible = light_t > 0.0
	if beam.visible:
		beam.basis = Basis(Vector3.UP, t * 3.0) * Basis(Vector3.RIGHT, PI * 0.5)
		beam.position = beam.basis * Vector3(0, -0.175, 0)
	if main.net != null and main.net.mode == "client":
		_draw_spares()
		return
	var tl = main.players[0] if not main.players.is_empty() else null
	if tl != null and tl.vr:
		_hands(tl, delta)
	_sim_spares(delta)
	_draw_spares()


## The giant's hands: touch toys, nudge or grab-and-throw the spare marbles.
func _hands(tl, delta: float) -> void:
	var hands: Array = [tl.hand_l.global_position, tl.hand_r.global_position]
	for h in 2:
		var hp: Vector3 = hands[h]
		if delta > 0.0:
			hand_vel[h] = (hand_vel[h] as Vector3).lerp((hp - (last_hand[h] as Vector3)) / delta, 0.5)
		last_hand[h] = hp
	var targets: Array = []
	for id in 8:
		targets.append(touch_point(id))
	for id in targets.size():
		var near := false
		for hp in hands:
			if (hp as Vector3).distance_to(targets[id]) < TOUCH:
				near = true
		if near and not touching.has(id):
			touching[id] = true
			react(id)
			tl.hand_r.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.05, 0.0)
		elif not near and touching.has(id):
			touching.erase(id)
	# Spare marbles: right trigger near one (and not on a handle) grabs it; letting go throws it.
	var trig: bool = tl.vr_trigger() and not tl.grabbing
	var rp: Vector3 = hands[1]
	if trig and not trig_was and held < 0:
		var best := -1
		var bd := 0.07
		for i in SPARE:
			var d := spare_pos[i].distance_to(rp)
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			held = best
			spare_state[best] = 2
			touched[8] = true
			main.sound("grab", -6.0, 1.4)
	if held >= 0 and not trig:
		spare_state[held] = 1
		spare_vel[held] = (hand_vel[1] as Vector3).limit_length(4.0)
		spare_rest[held] = 0.0
		held = -1
		main.sound("boop", -6.0, 0.8)
	trig_was = trig
	if held >= 0:
		spare_pos[held] = rp + tl.hand_r.global_basis * Vector3(0, -0.01, -0.04)
	# Nudge: a hand moving through a spare marble pushes it.
	for i in SPARE:
		if spare_state[i] == 2:
			continue
		for h in 2:
			var hp: Vector3 = hands[h]
			var d := spare_pos[i] - hp
			if d.length() < SPARE_R + 0.035:
				var hv: Vector3 = hand_vel[h]
				spare_vel[i] += d.normalized() * 0.4 + hv * 0.6
				spare_state[i] = 1
				spare_rest[i] = 0.0
				if not touched.has(8):
					touched[8] = true
				if spare_vel[i].length() > 0.3 and randf() < 0.3:
					main.sound("clack", -10.0, 1.4)


## Tiny ballistic marbles: gravity, the floor, the stool tops, the bowl and the board's top.
func _sim_spares(delta: float) -> void:
	var board = main.board
	for i in SPARE:
		if spare_state[i] != 1:
			continue
		var p := spare_pos[i]
		var v := spare_vel[i]
		v.y -= 9.8 * delta
		p += v * delta
		# Floor.
		if p.y < SPARE_R:
			p.y = SPARE_R
			if v.y < -0.4:
				main.sound("clack", linear_to_db(clampf(-v.y * 0.3, 0.05, 1.0)) - 8.0, 0.9)
			v.y = -v.y * 0.45
			v.x *= 0.96
			v.z *= 0.96
		# Stool tops (the bowl holds marbles in).
		for side in [-1, 1]:
			var top := stool_top(side)
			var flat := Vector2(p.x - top.x, p.z - top.z)
			if flat.length() < 0.15 and p.y < top.y + SPARE_R and p.y > top.y - 0.05:
				p.y = top.y + SPARE_R
				v.y = absf(v.y) * 0.4
				v.x *= 0.9
				v.z *= 0.9
				if side == 1 and flat.length() < BOWL_R:
					v *= 0.85
		# The board's top (it doesn't care about walls: it's a toy marble, not a player).
		var lp: Vector3 = board.to_local(p)
		var hs: Vector2 = board.half_size()
		if absf(lp.x) < hs.x and absf(lp.z) < hs.y and lp.y < SPARE_R and lp.y > -0.06:
			lp.y = SPARE_R
			p = board.to_global(lp)
			var up: Vector3 = board.global_basis.y
			var vn := v.dot(up)
			if vn < 0.0:
				v -= up * vn * 1.4
			v *= 0.985
		spare_pos[i] = p
		spare_vel[i] = v
		spare_rest[i] += delta
		var lost := p.distance_to(bowl_pos()) > 4.0 or p.y < -0.5
		if (spare_rest[i] > 6.0 and v.length() < 0.15) or spare_rest[i] > 14.0 or lost:
			spare_state[i] = 0
			spare_vel[i] = Vector3.ZERO
			spare_pos[i] = _bowl_spot(i)
			main.burst(spare_pos[i], Color(1, 1, 1), 6, false)
			main.sound("boing", -10.0, 1.3)


func _draw_spares() -> void:
	for i in SPARE:
		if spare_state[i] == 0:
			spare_pos[i] = _bowl_spot(i)
		spare_mm.set_instance_transform(i, Transform3D(Basis(), spare_pos[i]))


## Bots: positions to touch, by prop id (0..7), and 8 = a spare marble.
func touch_point(id: int) -> Vector3:
	if id < wobblers.size():
		var w: Array = wobblers[id]
		var n: Node3D = w[0]
		return n.global_position + n.global_basis.y * float(w[4])
	if id == 6:
		return windmill_blades.global_position
	if id == 7:
		return lamp.global_position + Vector3(0, -0.06, 0)
	return spare_pos[0]
