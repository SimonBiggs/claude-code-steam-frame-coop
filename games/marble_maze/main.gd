extends Node3D
## MARBLE MAZE - physics co-op. The VR player is a giant at a tabletop maze, tilting the whole board by
## its two side handles; the TV players (1-6) are marbles rolling through it in chase cams.
## Get EVERY marble into the goal before the clock runs out. Gems give points and extra time; holes
## drop you back to the team's furthest checkpoint. Shared score, twelve themed levels (bumpers, sliding
## blocks, planks, ice, mud, zoom arrows, teleporters), then they come back mirrored and faster.
## TEAMWORK: marbles bump softly (no knocking friends off the edge), TEAM PADS need marbles on them at
## the same time to open gates, marbles that are home steer a GUIDE STAR to tow stragglers, gems
## grabbed by different marbles close together make TEAM COMBOS, arriving together earns a bonus, and
## every gem fills the shared GEM JAR. Golden gems pop up as surprises. Awards at the end.
## Modes, networking and party join follow docs/GAME_DEV_GUIDE.md and games/duo_arena.

const VrText := preload("res://core/vr_text.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const BoardScript := preload("res://games/marble_maze/board.gd")
const MarbleScript := preload("res://games/marble_maze/marble.gd")
const TilterScript := preload("res://games/marble_maze/tilter.gd")
const JoinListenerScript := preload("res://games/marble_maze/join_listener.gd")

const MAX_PLAYERS := 7  # VR player + 6 marbles
const MAX_LOCAL_VIEWS := 6
const PAD_LEAVE_TIME := 20.0
const INTRO_TIME := 3.5
const FIRST_INTRO_TIME := 7.0
const CLEAR_TIME := 5.0
const EXTRA_TIME_PER_PLAYER := 8.0
const GEM_TIME := 3.0
const JAR_SIZE := 20
const COMBO_WINDOW := 3.0
const TOW_RADIUS := 0.08
const NONE := Vector2(99, 99)
const PLAYER_COLORS: Array[Color] = [Color(1.0, 0.85, 0.55), Color(1.0, 0.3, 0.3), Color(0.25, 0.6, 1.0),
	Color(0.35, 0.9, 0.35), Color(1.0, 0.8, 0.1), Color(0.8, 0.4, 1.0), Color(1.0, 0.55, 0.15)]
const SOUNDS := {
	"gem": [0.25, 880.0, 1760.0, 0.3, "sine", 0.0],
	"bump": [0.14, 260.0, 720.0, 0.4, "square", 0.05],
	"clack": [0.04, 1100.0, 500.0, 0.18, "square", 0.6],
	"fall": [0.8, 760.0, 80.0, 0.35, "tri", 0.0],
	"home": [0.55, 523.0, 1568.0, 0.35, "tri", 0.0],
	"grab": [0.06, 300.0, 200.0, 0.25, "sine", 0.3],
	"tick": [0.05, 1300.0, 1300.0, 0.14, "square", 0.0],
	"checkpoint": [0.3, 660.0, 990.0, 0.25, "square", 0.0],
	"go": [0.4, 440.0, 880.0, 0.35, "square", 0.0],
	"gate": [0.9, 220.0, 660.0, 0.4, "square", 0.1],
	"pad": [0.12, 500.0, 750.0, 0.25, "sine", 0.0],
	"boop": [0.1, 700.0, 520.0, 0.22, "sine", 0.0],
	"teleport": [0.35, 300.0, 1800.0, 0.3, "sine", 0.3],
	"golden": [0.6, 880.0, 2640.0, 0.35, "tri", 0.0],
	"jar": [1.0, 392.0, 1568.0, 0.4, "square", 0.0],
	"combo": [0.3, 990.0, 1980.0, 0.3, "tri", 0.0],
	"tow": [0.2, 300.0, 450.0, 0.2, "sine", 0.2],
}

var players: Array = []
var ready_to_play := false
var net: Node
var sfx: Node
var music: Node
var board: BoardScript
var board_y := 0.85
var pedestal: MeshInstance3D
var xr_interface: XRInterface
var mirror_vp: SubViewport
var mirror_t := 0.0
var synced := false
var join_listener: Node
var joy_owner := {}  # joypad device id -> player index
var views_root: Control
var last_view_area := Vector2.ZERO
var mats := {}
var meshes := {}

var state := "wait"  # wait, intro, play, clear, over
var state_t := 0.0
var level := 1
var score := 0
var best := 0
var time_left := 90.0
var levels_cleared := 0
var last_tick := -1
var cont_was := false
var net_tilt := Vector2.ZERO
var net_t := 0.0
var team_cp := -1
var golden := NONE
var golden_done := false
var jar := 0
var stars := 0
var level_stars := 0
var last_gem_t := -10.0
var last_gem_by := -1
var combo := 0
var first_home_t := -1.0
var level_t := 0.0
var stats := {}  # marble index -> {gems, falls, first, pads, tow, tp}
var seen_new := {}
var jar_mm: MultiMesh
var golden_node: MeshInstance3D

var center_label: Label
var help_label: Label
var center_tween: Tween
var vr_center: Label3D
var vr_board: Label3D


func _ready() -> void:
	randomize()
	_build_world()
	_build_hud()
	var menu := PauseMenuScript.new()
	menu.main = self
	add_child(menu)
	net = NetScript.new()
	net.name = "Net"
	net.main = self
	add_child(net)
	Input.joy_connection_changed.connect(_on_joy_changed)
	best = _load_best()
	if OS.has_environment("DUO_JOIN"):
		_show_center("Connecting to the VR player…", 0.0, false)
		net.join_finished.connect(func(ok: bool) -> void: _setup_game("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		var xr := XRServer.find_interface("OpenXR")
		if (xr != null and xr.is_initialized()) or OS.has_environment("DUO_HOST"):
			net.host()
		_setup_game(net.mode)


func _setup_game(mode: String) -> void:
	board.load_level(1)
	_build_players(mode)
	_build_views(mode)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_assign_joypads()
	ready_to_play = true
	_ensure_join_listener()
	_restore_party()
	if mode == "host":
		state = "wait"
		_show_center("MARBLE MAZE\nWaiting for the TV players to join…", 0.0)
	elif mode == "client":
		state = "wait"
		_show_center("CONNECTED", 1.5, false)
	else:
		_start_level(1)


func _exit_tree() -> void:
	XRServer.world_scale = 1.0  # global: never leave another game's scale behind


# --- Helpers -------------------------------------------------------------------------

func make_material(color: Color, glow: float) -> StandardMaterial3D:
	var key := "%s/%.2f" % [color.to_html(), glow]
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	mats[key] = m
	return m


func sphere_mesh(r: float) -> SphereMesh:
	var key := "s%.4f" % r
	if meshes.has(key):
		return meshes[key]
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 8
	meshes[key] = m
	return m


func box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func cyl_mesh(r_top: float, r_bottom: float, h: float, seg: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0, broadcast: bool = false) -> void:
	if sfx == null:
		sfx = SfxScript.new()
		add_child(sfx)
		for k in SOUNDS:
			var d: Array = SOUNDS[k]
			sfx.add_sound(k, d)
	sfx.play(sound_name, volume_db, pitch)
	if broadcast and net != null:
		net.event("sound", [sound_name, volume_db, pitch])


func burst(pos: Vector3, color: Color, amount: int = 14, broadcast: bool = true) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.35
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0, -1.6, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	p.mesh = box_mesh(Vector3.ONE * 0.012)
	p.material_override = make_material(color, 1.5)
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)
	if broadcast and net != null:
		net.event("burst", [pos, color, amount])


func popup(pos: Vector3, text: String, color: Color, broadcast: bool = true) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = 0.0009
	l.outline_size = 14
	l.modulate = color
	l.no_depth_test = false
	l.render_priority = 5
	if players.size() > 0 and players[0].vr:
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED  # VR text faces the player but never follows the head
	else:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.set_parallel()
	tw.tween_property(l, "global_position", pos + Vector3(0, 0.12, 0), 1.2)
	tw.tween_property(l, "modulate:a", 0.0, 1.2).set_delay(0.4)
	tw.tween_property(l, "outline_modulate:a", 0.0, 1.2).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)
	if broadcast and net != null:
		net.event("popup", [pos, text, color])


func board_world(p: Vector2, h: float = 0.03) -> Vector3:
	return board.to_global(Vector3(p.x, h, p.y))


func vertex_mat() -> StandardMaterial3D:
	if not mats.has("vertex"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.6
		mats["vertex"] = m
	return mats["vertex"]


## Several primitive meshes baked into one vertex-coloured mesh (one draw call).
## parts: [[Mesh, Transform3D, Color], ...]; cached by key.
func merged_mesh(key: String, parts: Array) -> ArrayMesh:
	if meshes.has(key):
		return meshes[key]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for part in parts:
		var m: Mesh = part[0]
		var xf: Transform3D = part[1]
		var c: Color = part[2]
		var arr: Array = m.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var raw = arr[Mesh.ARRAY_INDEX]
		var base := verts.size()
		var nb := xf.basis.inverse().transposed()
		for i in v.size():
			verts.append(xf * v[i])
			norms.append((nb * n[i]).normalized() if i < n.size() else Vector3.UP)
			cols.append(c)
		if raw is PackedInt32Array and not (raw as PackedInt32Array).is_empty():
			for i in (raw as PackedInt32Array):
				idx.append(base + i)
		else:
			for i in v.size():
				idx.append(base + i)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	meshes[key] = am
	return am


## A marble's two eyes (white with dark pupils) in one mesh.
func eyes_mesh() -> ArrayMesh:
	var w := sphere_mesh(0.0062)
	var k := sphere_mesh(0.0034)
	return merged_mesh("marble_eyes", [
		[w, Transform3D(Basis(), Vector3(-0.0085, 0, 0)), Color(1, 1, 1)],
		[w, Transform3D(Basis(), Vector3(0.0085, 0, 0)), Color(1, 1, 1)],
		[k, Transform3D(Basis(), Vector3(-0.0085, 0.0005, -0.0042)), Color(0.08, 0.06, 0.12)],
		[k, Transform3D(Basis(), Vector3(0.0085, 0.0005, -0.0042)), Color(0.08, 0.06, 0.12)]])


## A flat five-pointed star (both faces), about 2 units across: scale it down.
func star_mesh() -> ArrayMesh:
	if meshes.has("star"):
		return meshes["star"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	for i in 10:
		var a := PI / 2.0 + TAU * i / 10.0
		var r := 1.0 if i % 2 == 0 else 0.45
		pts.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	for face in [1.0, -1.0]:
		st.set_normal(Vector3(0, face, 0))
		for i in 10:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[(i + 1) % 10]
			st.add_vertex(Vector3(0, 0.15 * face, 0))
			if face > 0.0:
				st.add_vertex(b)
				st.add_vertex(a)
			else:
				st.add_vertex(a)
				st.add_vertex(b)
	var m := st.commit()
	meshes["star"] = m
	return m


# --- World ---------------------------------------------------------------------------

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.82, 1.0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.97, 0.92)
	e.ambient_light_energy = 0.65
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-60.0), deg_to_rad(30.0), 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 6.0
	add_child(sun)
	_build_room()
	pedestal = MeshInstance3D.new()
	pedestal.material_override = make_material(Color(0.95, 0.95, 1.0), 0.0)
	add_child(pedestal)
	board = BoardScript.new()
	board.name = "Board"
	board.main = self
	add_child(board)
	set_board_height(board_y)


## The cosy play-room round the table, baked into ONE mesh: floorboards, walls with windows, a rug,
## a toy shelf, giant blocks, a beanbag, a floor lamp, picture frames and bunting.
func _build_room() -> void:
	var parts: Array = []
	var wood := Color(0.82, 0.66, 0.46)
	parts.append([box_mesh(Vector3(10.0, 0.02, 9.6)), Transform3D(Basis(), Vector3(0, -0.01, 0.3)), wood])
	for i in 16:
		var z := -4.2 + i * 0.6
		parts.append([box_mesh(Vector3(10.0, 0.004, 0.015)), Transform3D(Basis(), Vector3(0, 0.001, z)), wood.darkened(0.18)])
	var wall := Color(0.98, 0.9, 0.8)
	var trim := Color(0.55, 0.75, 0.9)
	# Walls (back, left, right, front) with skirting and a dado rail.
	var walls: Array = [[Vector3(0, 1.5, -4.5), Vector3(10.0, 3.0, 0.1)], [Vector3(-5.0, 1.5, 0.3), Vector3(0.1, 3.0, 9.6)],
		[Vector3(5.0, 1.5, 0.3), Vector3(0.1, 3.0, 9.6)], [Vector3(0, 1.5, 5.1), Vector3(10.0, 3.0, 0.1)]]
	for w in walls:
		var at: Vector3 = w[0]
		var size: Vector3 = w[1]
		parts.append([box_mesh(size), Transform3D(Basis(), at), wall])
		var inward := -at.normalized()
		inward.y = 0.0
		var thin := Vector3(size.x if size.x > 1.0 else 0.03, 0.12, size.z if size.z > 1.0 else 0.03)
		parts.append([box_mesh(thin), Transform3D(Basis(), Vector3(at.x, 0.06, at.z) + inward * 0.05), Color(0.6, 0.45, 0.3)])
		parts.append([box_mesh(Vector3(thin.x, 0.05, thin.z)), Transform3D(Basis(), Vector3(at.x, 1.0, at.z) + inward * 0.05), trim])
	# Windows full of sky.
	for wx in [-2.2, 2.2]:
		parts.append([box_mesh(Vector3(1.5, 1.2, 0.04)), Transform3D(Basis(), Vector3(wx, 1.8, -4.43)), Color(0.6, 0.85, 1.0)])
		parts.append([box_mesh(Vector3(1.62, 0.07, 0.06)), Transform3D(Basis(), Vector3(wx, 2.42, -4.42)), Color(1, 1, 1)])
		parts.append([box_mesh(Vector3(1.62, 0.07, 0.06)), Transform3D(Basis(), Vector3(wx, 1.18, -4.42)), Color(1, 1, 1)])
		parts.append([box_mesh(Vector3(0.05, 1.2, 0.06)), Transform3D(Basis(), Vector3(wx, 1.8, -4.42)), Color(1, 1, 1)])
		parts.append([box_mesh(Vector3(1.5, 0.05, 0.06)), Transform3D(Basis(), Vector3(wx, 1.8, -4.42)), Color(1, 1, 1)])
	parts.append([box_mesh(Vector3(0.04, 1.1, 1.6)), Transform3D(Basis(), Vector3(-4.93, 1.8, -1.0)), Color(0.6, 0.85, 1.0)])
	# Picture frames.
	var pics: Array = [[Vector3(4.93, 1.7, -1.5), Color(1.0, 0.6, 0.4)], [Vector3(4.93, 1.6, 1.4), Color(0.5, 0.8, 0.5)], [Vector3(-4.93, 1.6, 2.2), Color(0.7, 0.6, 1.0)]]
	for pic in pics:
		var at: Vector3 = pic[0]
		parts.append([box_mesh(Vector3(0.04, 0.7, 0.9)), Transform3D(Basis(), at), Color(0.55, 0.38, 0.22)])
		parts.append([box_mesh(Vector3(0.05, 0.55, 0.75)), Transform3D(Basis(), at), pic[1]])
	# Round rug under the table.
	parts.append([cyl_mesh(2.0, 2.0, 0.01, 28), Transform3D(Basis(), Vector3(0, 0.005, 0)), Color(0.55, 0.8, 1.0)])
	parts.append([cyl_mesh(1.4, 1.4, 0.012, 28), Transform3D(Basis(), Vector3(0, 0.006, 0)), Color(1.0, 0.85, 0.5)])
	parts.append([cyl_mesh(0.8, 0.8, 0.014, 24), Transform3D(Basis(), Vector3(0, 0.007, 0)), Color(1.0, 0.6, 0.6)])
	# Giant toy blocks.
	var toy_cols: Array[Color] = [Color(1.0, 0.35, 0.35), Color(0.3, 0.6, 1.0), Color(1.0, 0.85, 0.2), Color(0.4, 0.9, 0.45), Color(0.85, 0.45, 1.0)]
	var toy_pos: Array[Vector3] = [Vector3(-2.6, 0.3, -2.4), Vector3(2.8, 0.25, -2.0), Vector3(-3.2, 0.2, 1.5), Vector3(3.0, 0.35, 2.2), Vector3(0.5, 0.3, -4.0)]
	for i in toy_pos.size():
		var sz: float = toy_pos[i].y * 2.0
		parts.append([box_mesh(Vector3(sz, sz, sz)), Transform3D(Basis(Vector3.UP, i * 0.7), toy_pos[i]), toy_cols[i]])
	parts.append([box_mesh(Vector3(0.3, 0.3, 0.3)), Transform3D(Basis(Vector3.UP, 0.3), Vector3(-2.5, 0.75, -2.35)), toy_cols[2]])
	# Toy shelf against the back wall.
	var shelf_c := Color(0.7, 0.5, 0.32)
	parts.append([box_mesh(Vector3(2.0, 1.4, 0.05)), Transform3D(Basis(), Vector3(0.0, 0.7, -4.4)), shelf_c.darkened(0.2)])
	for y in [0.02, 0.5, 1.0, 1.4]:
		parts.append([box_mesh(Vector3(2.0, 0.04, 0.4)), Transform3D(Basis(), Vector3(0.0, y, -4.22)), shelf_c])
	for sx in [-1.0, 1.0]:
		parts.append([box_mesh(Vector3(0.04, 1.42, 0.4)), Transform3D(Basis(), Vector3(sx, 0.7, -4.22)), shelf_c])
	var shelf_toys: Array = [[Vector3(-0.6, 0.62, -4.2), 0], [Vector3(-0.1, 0.6, -4.2), 1], [Vector3(0.5, 0.64, -4.2), 2], [Vector3(-0.5, 1.12, -4.2), 3],
		[Vector3(0.2, 1.1, -4.2), 4], [Vector3(0.7, 1.13, -4.2), 0]]
	for k in shelf_toys.size():
		var st_t: Array = shelf_toys[k]
		var at: Vector3 = st_t[0]
		if k % 2 == 0:
			parts.append([sphere_mesh(0.1), Transform3D(Basis(), at), toy_cols[int(st_t[1])]])
		else:
			parts.append([box_mesh(Vector3(0.18, 0.18, 0.18)), Transform3D(Basis(Vector3.UP, k * 0.5), at), toy_cols[int(st_t[1])]])
	# A squashy beanbag and a floor lamp.
	parts.append([sphere_mesh(0.5), Transform3D(Basis.from_scale(Vector3(1.0, 0.55, 1.0)), Vector3(3.3, 0.27, -0.8)), Color(0.95, 0.5, 0.35)])
	parts.append([cyl_mesh(0.03, 0.03, 1.6, 8), Transform3D(Basis(), Vector3(-3.8, 0.8, -3.5)), Color(0.3, 0.3, 0.32)])
	parts.append([cyl_mesh(0.2, 0.2, 0.03, 16), Transform3D(Basis(), Vector3(-3.8, 0.015, -3.5)), Color(0.3, 0.3, 0.32)])
	parts.append([cyl_mesh(0.18, 0.35, 0.35, 16), Transform3D(Basis(), Vector3(-3.8, 1.65, -3.5)), Color(1.0, 0.85, 0.55)])
	# The gem jar's stool and lid (the glass and gems are separate).
	parts.append([cyl_mesh(0.14, 0.17, 0.6, 14), Transform3D(Basis(), Vector3(-1.05, 0.3, -0.6)), Color(0.7, 0.5, 0.32)])
	parts.append([cyl_mesh(0.1, 0.1, 0.03, 14), Transform3D(Basis(), Vector3(-1.05, 0.875, -0.6)), Color(0.95, 0.4, 0.4)])
	# Bunting along the back wall.
	for i in 18:
		var x := -4.5 + i * 0.53
		var y := 2.75 - sin(float(i % 9) / 8.0 * PI) * 0.25
		var pm := PrismMesh.new()
		pm.size = Vector3(0.3, 0.32, 0.02)
		parts.append([pm, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(x, y, -4.42)), toy_cols[i % toy_cols.size()]])
	var room := MeshInstance3D.new()
	room.name = "Room"
	room.mesh = merged_mesh("playroom", parts)
	room.material_override = vertex_mat()
	add_child(room)
	_build_jar()


## The team's gem jar beside the table: every gem anyone grabs drops in; a full jar is a bonus.
func _build_jar() -> void:
	var glass := MeshInstance3D.new()
	glass.mesh = cyl_mesh(0.1, 0.1, 0.26, 16)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.8, 0.95, 1.0, 0.25)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.roughness = 0.1
	gm.metallic = 0.3
	glass.material_override = gm
	glass.position = Vector3(-1.05, 0.73, -0.6)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)
	jar_mm = MultiMesh.new()
	jar_mm.transform_format = MultiMesh.TRANSFORM_3D
	var pm := PrismMesh.new()
	pm.size = Vector3(0.04, 0.045, 0.04)
	jar_mm.mesh = pm
	jar_mm.instance_count = JAR_SIZE
	for i in JAR_SIZE:
		var a := i * 2.4
		var r := 0.045 if i % 3 != 0 else 0.0
		jar_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, a), Vector3(-1.05 + cos(a) * r, 0.625 + float(i / 3) * 0.032, -0.6 + sin(a) * r)))
	jar_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = jar_mm
	mmi.material_override = make_material(Color(0.3, 0.95, 1.0), 1.0)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func set_board_height(y: float) -> void:
	board_y = clampf(y, 0.4, 1.3)
	board.position = Vector3(0, board_y, 0)
	var h := board_y - 0.08
	pedestal.mesh = cyl_mesh(0.12, 0.3, h, 16)
	pedestal.position = Vector3(0, h * 0.5, 0)


# --- Players and views -----------------------------------------------------------------

func _build_players(mode: String) -> void:
	var t := TilterScript.new()
	t.main = self
	t.ghost = mode == "client"
	t.key_set = 0
	add_child(t)
	players.append(t)
	var top := MAX_PLAYERS - 1 if mode != "local" else MAX_LOCAL_VIEWS - 1
	for i in range(1, top + 1):
		var m := MarbleScript.new()
		m.index = i
		m.main = self
		m.board = board
		m.color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
		m.remote = mode == "host"
		if i == 1:
			m.key_set = 1 if mode == "client" else 0
			m.mouse_look = mode == "client"
		board.add_child(m)
		players.append(m)
		m.reset_to_start()
		m.set_active(i == 1)


func is_local(p) -> bool:
	return not p.vr and not p.remote and not p.ghost


func _apply_vr_performance() -> void:
	for n in get_children():
		if n is WorldEnvironment:
			var e: Environment = n.environment
			e.ssao_enabled = false
			e.fog_enabled = false
			e.glow_enabled = false
		elif n is DirectionalLight3D:
			n.shadow_enabled = false


func _build_views(mode: String) -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized() and mode != "client":
		xr_interface = xr
		print("VR headset found: player 1 tilts the maze in VR")
		Engine.physics_ticks_per_second = 90
		get_viewport().use_xr = true
		get_viewport().msaa_3d = Viewport.MSAA_2X
		_apply_vr_performance()
		var origin := XROrigin3D.new()
		add_child(origin)
		origin.global_position = Vector3(0, 0, 0.66)
		var cam := XRCamera3D.new()
		origin.add_child(cam)
		var left := XRController3D.new()
		left.tracker = "left_hand"
		left.pose = "aim"
		origin.add_child(left)
		var right := XRController3D.new()
		right.tracker = "right_hand"
		right.pose = "aim"
		origin.add_child(right)
		players[0].attach_xr(origin, cam, left, right)
		_build_vr_mirror(cam)
	else:
		print("No VR headset: %s" % ("TV marbles" if mode == "client" else "split screen, player 1 tilts the board"))
	_ensure_views_root()
	for p in players:
		if is_local(p) and p.active:
			_ensure_view(p)
	_layout_views()


## Low-res copy of the VR view for gdev (group gdev_capture), refreshed at 30 fps.
func _build_vr_mirror(xr_cam: XRCamera3D) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(480, 480)
	vp.world_3d = get_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	mirror_vp = vp
	vp.add_to_group("gdev_capture")
	add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 90.0
	cam.near = 0.02
	vp.add_child(cam)
	cam.current = true
	var follow := RemoteTransform3D.new()
	xr_cam.add_child(follow)
	follow.remote_path = follow.get_path_to(cam)


func _ensure_views_root() -> void:
	if views_root != null and is_instance_valid(views_root):
		return
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.12, 0.2)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	views_root = Control.new()
	views_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(views_root)
	views_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## One split-screen view (SubViewport + camera + HUD) per local player, created when they first play.
func _ensure_view(p) -> void:
	if p.has_meta("view") or not is_local(p):
		return
	_ensure_views_root()
	var container := SubViewportContainer.new()
	p.set_meta("view", container)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	views_root.add_child(container)
	var vp := SubViewport.new()
	vp.world_3d = get_world_3d()
	vp.msaa_3d = Viewport.MSAA_2X
	container.add_child(vp)
	var cam := Camera3D.new()
	cam.near = 0.01
	cam.far = 40.0
	cam.fov = 70.0
	vp.add_child(cam)
	cam.current = true
	if p.index == 0:
		p.attach_camera(cam)
	else:
		p.camera = cam
	var hud_layer := CanvasLayer.new()
	vp.add_child(hud_layer)
	var hud := Control.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tag := ColorRect.new()
	tag.color = p.color if p.index > 0 else Color(1.0, 0.85, 0.55)
	tag.size = Vector2(14, 14)
	tag.position = Vector2(14, 22)
	hud.add_child(tag)
	var l := _make_label(28)
	hud.add_child(l)
	l.position = Vector2(36, 10)
	p.hud = hud
	p.hud_label = l


## TV grid: 1 full, 2 side by side, 3-4 as 2x2, 5-6 as 3x2; smaller views render at lower resolution.
func _layout_views() -> void:
	if views_root == null or not is_instance_valid(views_root):
		return
	var shown: Array = []
	for p in players:
		if not p.has_meta("view"):
			continue
		var c: SubViewportContainer = p.get_meta("view")
		c.visible = p.active
		if p.active:
			shown.append(p)
	var n := shown.size()
	var area := views_root.size
	if area.x < 2.0 or area.y < 2.0:
		area = get_viewport().get_visible_rect().size
	last_view_area = views_root.size
	if n == 0:
		return
	var cols := 1
	var rows := 1
	if n == 2:
		cols = 2
	elif n > 2 and n <= 4:
		cols = 2
		rows = 2
	elif n > 4:
		cols = 3
		rows = 2
	var gap := 4.0
	var cell := Vector2((area.x - gap * (cols - 1)) / cols, (area.y - gap * (rows - 1)) / rows)
	var res_scale := 1.0 if n <= 2 else (0.7 if n <= 4 else 0.55)
	for k in n:
		var p = shown[k]
		var c: SubViewportContainer = p.get_meta("view")
		var col := k % cols
		var row := k / cols
		c.set_anchors_preset(Control.PRESET_TOP_LEFT)
		c.position = Vector2(col * (cell.x + gap), row * (cell.y + gap))
		c.size = cell
		var vp := c.get_child(0) as SubViewport
		if vp != null:
			vp.scaling_3d_scale = res_scale
			vp.msaa_3d = Viewport.MSAA_2X if n <= 2 else Viewport.MSAA_DISABLED
		if p.hud_label != null:
			var ui := clampf(minf(cell.x / 940.0, cell.y / 900.0), 0.5, 1.0)
			p.hud_label.add_theme_font_size_override("font_size", int(30.0 * ui))
	if players.size() > 0 and not players[0].vr:
		for node in get_children():
			if node is DirectionalLight3D:
				node.shadow_enabled = n <= 2


# --- Controllers and drop-in join ----------------------------------------------------

func _assign_joypads() -> void:
	var pads := Input.get_connected_joypads()
	joy_owner.clear()
	if net.mode == "host":
		if not players[0].vr and pads.size() > 0:
			players[0].joy = pads[0]
		return
	players[1].joy = pads[0] if pads.size() > 0 else -1
	if net.mode == "local":
		players[0].joy = pads[1] if pads.size() > 1 else -1
	for p in players:
		if p.joy >= 0 and is_local(p):
			joy_owner[p.joy] = p.index
	for id in pads:
		print("Joypad %d: %s" % [id, Input.get_joy_name(id)])


func _on_joy_changed(device: int, connected: bool) -> void:
	if not ready_to_play or net.mode == "host":
		return
	if connected:
		print("Joypad %d connected" % device)
		if joy_owner.has(device):
			return
		var pick = null
		for p in players:
			if is_local(p) and p.joy < 0 and int(p.get_meta("last_joy", -2)) == device:
				pick = p
				break
		if pick == null and players[1].joy < 0:
			pick = players[1]
		if pick == null:
			return  # unassigned: press A to join
		pick.joy = device
		joy_owner[device] = pick.index
		pick.pad_lost_t = -1.0
		if not pick.active and pick.has_meta("left_by_pad"):
			_request_join(pick)
	else:
		print("Joypad %d disconnected" % device)
		if not joy_owner.has(device):
			return
		var idx: int = joy_owner[device]
		joy_owner.erase(device)
		var p = players[idx]
		if p.joy != device:
			return
		p.joy = -1
		p.set_meta("last_joy", device)
		if idx >= 2 and p.active:
			p.pad_lost_t = 0.0
			_show_center("P%d: controller disconnected" % (idx + 1), 2.0, false)


## Called by the join listener for every input event: A on a controller nobody owns joins a marble.
func handle_join_input(event: InputEvent) -> bool:
	var pad := event as InputEventJoypadButton
	if pad == null or not pad.pressed or pad.button_index != JOY_BUTTON_A:
		return false
	if not ready_to_play or net.mode == "host" or get_tree().paused:
		return false
	var device := pad.device
	if joy_owner.has(device):
		var idx: int = joy_owner[device]
		if idx > 0 and not players[idx].active and is_local(players[idx]):
			_request_join(players[idx])
			return true
		return false
	return _join_slot(device) != null


func _next_free_index() -> int:
	for i in range(1, players.size()):
		var p = players[i]
		if not is_local(p) or p.active or p.has_meta("want_join") or p.joy >= 0 or p.pad_lost_t >= 0.0:
			continue
		return i
	return -1


func _join_slot(device: int):
	var idx := _next_free_index()
	if idx < 0:
		_show_center("All %d marbles are taken!" % (players.size() - 1), 1.5, false)
		return null
	var p = players[idx]
	if device >= 0:
		p.joy = device
		joy_owner[device] = idx
		print("Joypad %d joins as P%d" % [device, idx + 1])
	_request_join(p)
	return p


## Local: roll in now. TV machine: ask the host (retried by _check_join until it agrees).
func _request_join(p) -> void:
	p.remove_meta("left_by_pad")
	p.pad_lost_t = -1.0
	if net.mode == "client":
		p.set_meta("want_join", true)
		join_t = 0.0
	elif not p.active:
		_activate(p)
	_save_party()


func _activate(p) -> void:
	p.set_active(true)
	p.reset_to_start()
	if state == "play" or state == "intro":
		time_left += EXTRA_TIME_PER_PLAYER
	_show_center("PLAYER %d ROLLS IN!" % (p.index + 1), 1.5)
	sound("home", -4.0, 1.2, true)
	on_player_activity_changed(p)


func _leave(p) -> void:
	p.pad_lost_t = -1.0
	p.remove_meta("want_join")
	p.set_meta("left_by_pad", true)
	if net.mode == "client":
		net.send_action("leave", [], p.index)
	elif p.active:
		p.set_active(false)
		on_player_activity_changed(p)
		_show_center("PLAYER %d LEFT" % (p.index + 1), 1.5)
	_save_party()


func _save_party() -> void:
	var party: Array = []
	for p in players:
		if p.index >= 2 and is_local(p) and (p.active or p.has_meta("want_join")) and not p.has_meta("left_by_pad"):
			party.append([p.index, p.joy])
	Engine.set_meta("marble_maze_party", {"mode": net.mode, "party": party})


func _restore_party() -> void:
	if net.mode == "host" or not Engine.has_meta("marble_maze_party"):
		return
	var saved: Dictionary = Engine.get_meta("marble_maze_party")
	if str(saved.get("mode", "")) != net.mode:
		return
	var pads := Input.get_connected_joypads()
	var party: Array = saved.get("party", [])
	for entry in party:
		var e: Array = entry
		var idx: int = e[0]
		var device: int = e[1]
		if idx >= players.size():
			continue
		if device >= 0 and (not pads.has(device) or joy_owner.has(device)):
			continue
		var p = players[idx]
		if p.active or not is_local(p):
			continue
		if device >= 0:
			p.joy = device
			joy_owner[device] = idx
		_request_join(p)


func _ensure_join_listener() -> void:
	if join_listener != null and is_instance_valid(join_listener):
		return
	join_listener = JoinListenerScript.new()
	join_listener.name = "JoinListener"
	join_listener.main = self
	add_child(join_listener)


## Test hook: join a marble without a controller (index -1: the next free seat).
func debug_join(index: int = -1):
	if not ready_to_play or net.mode == "host":
		return null
	if index < 0:
		return _join_slot(-1)
	var p = players[index]
	_request_join(p)
	return p


var join_t := 0.0
func _check_join(delta: float) -> void:
	join_t -= delta
	if join_t > 0.0:
		return
	for p in players:
		if not p.has_meta("want_join") or not is_local(p):
			continue
		if p.active:
			p.remove_meta("want_join")
			continue
		join_t = 1.0
		net.send_action("join", [p.index], 1)  # sent as P2, like duo_arena's drop-in seats


func on_player_activity_changed(p) -> void:
	if p.active and is_local(p):
		_ensure_view(p)
	if p.active:
		p.remove_meta("want_join")
	_layout_views()
	print("Player %d is now %s" % [p.index + 1, "playing" if p.active else "waiting"])


func has_local_marble_keys() -> bool:
	for p in players:
		if p.index > 0 and is_local(p) and p.active and p.key_set != MarbleScript.NO_KEYS:
			return true
	return false


func active_marbles() -> Array:
	var out: Array = []
	for p in players:
		if p.index > 0 and p.active:
			out.append(p)
	return out


func home_count() -> int:
	var n := 0
	for p in active_marbles():
		if p.home:
			n += 1
	return n


# --- Game flow -----------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if music == null:
		music = MusicScript.new()
		add_child(music)
	music.play_track((level - 1) % 3)
	_ensure_join_listener()
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if views_root != null and is_instance_valid(views_root) and views_root.size != last_view_area:
		_layout_views()
	_update_vr_text()
	_update_extras(delta)
	var cont := _continue_pressed()
	var cont_edge := cont and not cont_was
	cont_was = cont
	if net.mode == "client":
		_client_update(delta, cont_edge)
		return
	_update_lost_pads(delta)
	state_t += delta
	board.t += delta
	var target := Vector2.ZERO
	if state == "play":
		target = players[0].want_tilt
	board.tilt = board.tilt.lerp(target, 1.0 - exp(-7.0 * delta))
	board.basis = board.tilt_basis(board.tilt)
	match state:
		"wait":
			board.tilt = Vector2.ZERO
		"intro":
			var dur := FIRST_INTRO_TIME if level == 1 else INTRO_TIME
			if state_t >= dur:
				state = "play"
				state_t = 0.0
				_show_center("GO!", 0.8)
				sound("go", 0.0, 1.0, true)
		"play":
			time_left -= delta
			level_t += delta
			var secs := int(ceilf(time_left))
			if secs <= 10 and secs != last_tick and secs > 0:
				last_tick = secs
				sound("tick", -2.0, 1.0 + (10 - secs) * 0.05, true)
			_authority_checks()
			if time_left <= 0.0:
				time_left = 0.0
				_game_over()
		"clear":
			if state_t > CLEAR_TIME or (state_t > 1.5 and cont_edge):
				_start_level(level + 1)
		"over":
			if state_t > 1.5 and cont_edge:
				_restart()


## Both machines: the golden gem, the gem jar and the guide stars' tow timers.
func _update_extras(delta: float) -> void:
	for p in players:
		if p.index > 0:
			p.towing = maxf(0.0, p.towing - delta)
	if jar_mm != null:
		jar_mm.visible_instance_count = jar % JAR_SIZE
	if golden != NONE or golden_node != null:
		if golden_node == null:
			golden_node = MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(0.045, 0.05, 0.045)
			golden_node.mesh = pm
			golden_node.material_override = make_material(Color(1.0, 0.8, 0.2), 2.2)
			golden_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			board.add_child(golden_node)
		golden_node.visible = golden != NONE and (state == "play" or state == "intro")
		if golden_node.visible:
			golden_node.position = Vector3(golden.x, 0.045 + sin(board.t * 4.0) * 0.01, golden.y)
			golden_node.rotation.y += delta * 4.0
			golden_node.scale = Vector3.ONE * (1.0 + 0.15 * sin(board.t * 9.0))


func _client_update(delta: float, cont_edge: bool) -> void:
	_check_join(delta)
	_update_lost_pads(delta)
	state_t += delta
	board.t += delta
	board.t = lerpf(board.t, net_t, 1.0 - exp(-2.0 * delta))
	net_t += delta
	board.tilt = board.tilt.lerp(net_tilt, 1.0 - exp(-14.0 * delta))
	board.basis = board.tilt_basis(board.tilt)
	if cont_edge and ((state == "clear" and state_t > 1.5) or (state == "over" and state_t > 1.5)):
		net.send_action("continue", [])


func _update_lost_pads(delta: float) -> void:
	for p in players:
		if p.pad_lost_t >= 0.0 and is_local(p):
			p.pad_lost_t += delta
			if p.pad_lost_t > PAD_LEAVE_TIME:
				_leave(p)


## A / Enter on this machine (VR: the trigger or A) moves on from the level-clear / game-over screens.
func _continue_pressed() -> bool:
	if state != "clear" and state != "over":
		return false
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER):
		return true
	for p in players:
		if is_local(p) and p.active and p.action_pressed():
			return true
	if players.size() > 0 and players[0].vr and players[0].action_pressed():
		return true
	return false


## Bot hook: same as pressing A on the end screens.
func debug_continue() -> void:
	if net.mode == "client":
		net.send_action("continue", [])
	else:
		_on_continue()


func _on_continue() -> void:
	if state == "clear" and state_t > 1.0:
		_start_level(level + 1)
	elif state == "over" and state_t > 1.0:
		_restart()


func _start_level(n: int) -> void:
	level = n
	board.load_level(n)
	board.tilt = Vector2.ZERO
	players[0].want_tilt = Vector2.ZERO
	players[0].grab_tilt = Vector2.ZERO
	for p in players:
		if p.index > 0:
			p.reset_to_start()
	var count := maxi(1, active_marbles().size())
	time_left = board.level_time(n) + EXTRA_TIME_PER_PLAYER * (count - 1)
	last_tick = -1
	state = "intro"
	state_t = 0.0
	level_t = 0.0
	team_cp = -1
	golden = NONE
	golden_done = false
	combo = 0
	last_gem_by = -1
	first_home_t = -1.0
	_apply_theme()
	var lap := (n - 1) / board.Levels.LEVELS.size()
	var title := "LEVEL %d: %s%s" % [n, board.level_name(n), "  (MIRRORED!)" if lap % 2 == 1 else ""]
	var fresh := board.level_new(n)
	if seen_new.has(fresh):
		fresh = ""
	elif fresh != "":
		seen_new[fresh] = true
	if n == 1:
		_show_center("MARBLE MAZE\nRoll EVERY marble into the glowing goal - it's a TEAM game!\n" \
			+ "VR: grab a side handle (right trigger) and tilt the board · left stick tilts too · A levels it\n" \
			+ "TV: left stick rolls your marble · right stick turns the camera · A joins\n" \
			+ "Bump gently! Home already? Steer your GUIDE STAR to tow your friends.\n\n" + title, FIRST_INTRO_TIME)
	elif fresh != "":
		_show_center(title + "\n" + fresh, FIRST_INTRO_TIME)
		state_t = INTRO_TIME - FIRST_INTRO_TIME  # a longer look at what's new
	else:
		_show_center(title + "\n" + board.level_tip(n), INTRO_TIME)
	sound("clear", -4.0, 1.0, true)
	net.event("level", [n])
	print("Level %d started: %s (%d marbles, %.0f s)" % [n, board.level_name(n), count, time_left])


## Each level's theme sets the mood: the sky colour outside and a hint of tint in the light.
func _apply_theme() -> void:
	var bg := board.theme_color(4)
	for c in get_children():
		if c is WorldEnvironment:
			var e: Environment = (c as WorldEnvironment).environment
			e.background_color = bg
			e.ambient_light_color = Color(1.0, 0.97, 0.92).lerp(bg, 0.25)


func _restart() -> void:
	score = 0
	levels_cleared = 0
	stars = 0
	jar = 0
	stats.clear()
	_start_level(1)


## Host / local: gems, team pads and gates, the golden gem, marbles reaching the goal (for marbles
## driven by the TV machine) and level clear.
func _authority_checks() -> void:
	var marbles := active_marbles()
	for p in marbles:
		if p.home or p.falling:
			continue
		var pos := Vector2(p.lp.x, p.lp.z)
		for i in board.gems.size():
			if board.gem_taken[i]:
				continue
			if pos.distance_to(board.gems[i]) < 0.5 * board.CELL:
				board.gem_taken[i] = true
				_gem_scored(p, board.gems[i], 10, GEM_TIME, Color(0.4, 1.0, 1.0))
		if golden != NONE and pos.distance_to(golden) < 0.55 * board.CELL:
			var at := golden
			golden = NONE
			_gem_scored(p, at, 30, 10.0, Color(1.0, 0.85, 0.2))
			sound("golden", 0.0, 1.0, true)
			_show_center("P%d GRABBED THE GOLDEN GEM!  +30  +10 s" % (p.index + 1), 1.8)
		if p.remote and board.in_goal(pos):
			p.home = true
			on_marble_home(p)
	_team_pads(marbles)
	_maybe_golden()
	_track_tows(marbles)
	if marbles.is_empty():
		return
	for p in marbles:
		if not p.home:
			return
	_level_clear()


## A gem (or the golden gem) was grabbed: score, time, the jar, and team combos for gems grabbed by
## DIFFERENT marbles close together.
func _gem_scored(p, at: Vector2, points: int, secs: float, col: Color) -> void:
	var now := level_t
	if last_gem_by >= 0 and last_gem_by != p.index and now - last_gem_t < COMBO_WINDOW:
		combo += 1
	else:
		combo = 0
	last_gem_t = now
	last_gem_by = p.index
	var bonus := 10 * combo
	score += points + bonus
	time_left += secs
	_stat(p.index, "gems", 1.0)
	var wp := board_world(at, 0.04)
	var txt := "+%d  +%ds" % [points, int(secs)]
	if combo > 0:
		txt = "TEAM COMBO x%d!  +%d" % [combo + 1, points + bonus]
		sound("combo", -2.0, 1.0 + 0.1 * combo, true)
	popup(wp + Vector3(0, 0.03, 0), txt, col if combo == 0 else Color(1.0, 0.7, 1.0))
	burst(wp, col, 14)
	sound("gem", -2.0, 1.0 + randf() * 0.2, true)
	jar += 1
	if jar % JAR_SIZE == 0:
		score += 100
		time_left += 10.0
		sound("jar", 0.0, 1.0, true)
		burst(Vector3(-1.05, 0.9, -0.6), Color(0.4, 1.0, 1.0), 30)
		_show_center("THE GEM JAR IS FULL!  +100  +10 s\nTeam gems so far: %d" % jar, 2.2)


## Team pads: a group's gates open (and stay open) once enough of its pads have a marble on them at
## the same time - every pad, or one per marble when there are fewer marbles than pads.
func _team_pads(marbles: Array) -> void:
	if board.pads.is_empty():
		return
	var on_count := [0, 0]
	var pad_total := [0, 0]
	var on_who: Array = [[], []]
	for i in board.pads.size():
		var pd: Array = board.pads[i]
		var g: int = pd[1]
		pad_total[g] += 1
		var hit := false
		for p in marbles:
			if p.home or p.falling:
				continue
			if board.pad_at(Vector2(p.lp.x, p.lp.z)) == i:
				hit = true
				on_who[g].append(p.index)
		if hit and not board.pad_on[i]:
			sound("pad", -4.0, 1.0 + 0.2 * on_count[g], true)
		board.pad_on[i] = hit
		if hit:
			on_count[g] += 1
	for g in 2:
		if board.gate_open[g] or pad_total[g] == 0:
			continue
		var need: int = mini(pad_total[g], maxi(1, marbles.size()))
		if on_count[g] >= need:
			board.gate_open[g] = true
			var col_name := "BLUE" if g == 0 else "PURPLE"
			_show_center("TEAMWORK!  The %s gate is open!" % col_name, 2.0)
			sound("gate", 0.0, 1.0, true)
			for idx in on_who[g]:
				_stat(int(idx), "pads", 1.0)
			for gc in board.gate_cells:
				if int(gc[1]) == g:
					var cell: Vector2i = gc[0]
					burst(board_world(board.center(cell.x, cell.y), 0.05), board.GROUP_COLORS[g], 12)
			print("Team pads: gate %d opened by %s" % [g, str(on_who[g])])


## Once per level a golden gem may pop up somewhere on the path, worth a lot.
func _maybe_golden() -> void:
	if golden_done or level_t < board.level_time(level) * 0.3:
		return
	golden_done = true
	if randf() > 0.7:
		return
	var spots: Array[Vector2] = []
	for cell in board.goal_dist:
		var c: Vector2i = cell
		var k: String = board.ch(c.x, c.y)
		if k in [".", "I", "M"] and int(board.goal_dist[cell]) > 3:
			spots.append(board.center(c.x, c.y))
	if spots.is_empty():
		return
	golden = spots[randi() % spots.size()]
	sound("golden", -2.0, 0.8, true)
	_show_center("A GOLDEN GEM APPEARED!\nWho can reach it?  +30  +10 s", 2.2)
	print("Golden gem at %s" % golden)


## Stats: home marbles towing a friend with their guide star (and a little tow sound).
func _track_tows(marbles: Array) -> void:
	for g in marbles:
		if not g.home or not g.guide_on:
			continue
		var gp: Vector2 = g.guide
		for p in marbles:
			if p == g or p.home or p.falling:
				continue
			if gp.distance_to(Vector2(p.lp.x, p.lp.z)) < TOW_RADIUS:
				_stat(g.index, "tow", get_physics_process_delta_time())
				break


func _stat(index: int, key: String, amount: float) -> void:
	if not stats.has(index):
		stats[index] = {"gems": 0.0, "falls": 0.0, "first": 0.0, "pads": 0.0, "tow": 0.0, "tp": 0.0}
	var st: Dictionary = stats[index]
	st[key] = float(st[key]) + amount


## Simulating machine: a home marble's guide star tows a nearby friend (never over an edge or a hole).
func guide_pull(m, here: Vector2) -> Vector2:
	if m.home or state != "play":
		return Vector2.ZERO
	for o in players:
		if o == m or o.index == 0 or not o.active or not o.home or not o.guide_on:
			continue
		var gp: Vector2 = o.guide
		var d := gp - here
		var l := d.length()
		if l > TOW_RADIUS or l < 0.004:
			continue
		var step := here + d / l * 0.02
		if not board.supported(step):
			continue
		if o.towing <= 0.0:
			sound("tow", -10.0, 1.2)
		o.towing = 0.4
		return (d * 40.0).limit_length(1.3) - m.v * 1.5
	return Vector2.ZERO


## Respawning marbles go to the team's furthest checkpoint if it beats their own.
func best_checkpoint(own: int) -> int:
	if team_cp >= 0 and board.checkpoint_dist(team_cp) < board.checkpoint_dist(own):
		return team_cp
	return own


func _level_clear() -> void:
	state = "clear"
	state_t = 0.0
	levels_cleared += 1
	var bonus := int(time_left) * 2
	score += bonus
	var all_gems: bool = not board.gem_taken.has(false)
	level_stars = 1 + (1 if all_gems else 0) + (1 if time_left >= board.level_time(level) * 0.4 else 0)
	stars += level_stars
	if score > best:
		best = score
		_save_best(best)
	var next_name := board.level_name(level + 1)
	var star_line := ["", "1 STAR", "2 STARS", "3 STARS!"][clampi(level_stars, 0, 3)] as String
	_show_center("LEVEL CLEAR!  %s\nTime bonus +%d   ·   Score %d   ·   Stars %d\nNext: %s\n\nA / Enter (VR: trigger) to roll on" \
		% [star_line, bonus, score, stars, next_name], CLEAR_TIME)
	sound("clear", 0.0, 1.2, true)
	burst(board_world(board.goal, 0.08), Color(1.0, 0.9, 0.3), 30)
	burst(board_world(board.goal, 0.08), Color(0.4, 1.0, 0.5), 30)
	print("Level %d cleared! score %d, %d stars" % [level, score, level_stars])


func _game_over() -> void:
	state = "over"
	state_t = 0.0
	var line := "Best: %d" % best
	if score > best:
		line = "NEW BEST SCORE!  (previous %d)" % best
		best = score
		_save_best(best)
	var awards := _awards()
	print("Awards: %s" % ", ".join(awards))
	var award_line := ("AWARDS: " + "  ·  ".join(awards)) if not awards.is_empty() else ""
	_show_center("TIME'S UP!\n%d of %d marbles made it home\nScore %d  ·  reached level %d  ·  Stars %d  ·  Team gems %d\n%s\n%s\n\nA / Enter (VR: trigger) to play again" \
		% [home_count(), active_marbles().size(), score, level, stars, jar, line, award_line], 0.0)
	sound("gameover", 0.0, 1.0, true)
	print("Game over: level %d, score %d" % [level, score])


## Fun awards from the session's stats (only for things somebody actually did).
func _awards() -> Array[String]:
	var out: Array[String] = []
	var names := {"gems": "GEM GOBBLER", "first": "SPEEDY ROLLER", "pads": "TEAM PLAYER", "tow": "TOW TRUCK", "tp": "SPACE TRAVELLER"}
	var minimum := {"gems": 1.0, "first": 1.0, "pads": 1.0, "tow": 0.5, "tp": 2.0}
	for key in names:
		var who := -1
		var top := 0.0
		for idx in stats:
			var st: Dictionary = stats[idx]
			if float(st[key]) > top:
				top = float(st[key])
				who = int(idx)
		if who > 0 and top >= float(minimum[key]):
			out.append("P%d %s" % [who + 1, names[key]])
	# Steadiest marble: the fewest falls (among marbles that played).
	var steady := -1
	var low := 9999.0
	for idx in stats:
		var st: Dictionary = stats[idx]
		if float(st["falls"]) < low:
			low = float(st["falls"])
			steady = int(idx)
	if steady > 0:
		out.append("P%d STEADY EDDIE" % (steady + 1))
	if levels_cleared > 0:
		out.append("VR GENTLE GIANT")
	return out


func _load_best() -> int:
	var cfg := ConfigFile.new()
	cfg.load("user://marble_maze_best.cfg")
	return int(cfg.get_value("best", "score", 0))


func _save_best(s: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("best", "score", s)
	cfg.save("user://marble_maze_best.cfg")


# --- Marble callbacks (from whichever machine simulates the marble) -------------------

func _forward_fx(kind: String, args: Array, p) -> void:
	if net.mode == "client":
		net.send_action("fx", [kind] + args, p.index)


func on_bump(p, i: int) -> void:
	board.bump_fx(i)
	p.bump_squash()
	sound("bump", -4.0, randf_range(0.9, 1.2))
	if p.joy >= 0:
		Input.start_joy_vibration(p.joy, 0.4, 0.6, 0.12)
	_forward_fx("bump", [i], p)


func on_wall_hit(p, impact: float) -> void:
	sound("clack", linear_to_db(clampf(impact * 2.0, 0.1, 1.0)) - 4.0, randf_range(0.8, 1.3))
	if p.joy >= 0 and impact > 0.4:
		Input.start_joy_vibration(p.joy, 0.2, 0.3, 0.06)


func on_marble_fell(p) -> void:
	var wp: Vector3 = board.to_global(p.lp)
	sound("fall", -2.0)
	burst(wp, p.color, 10, false)
	popup(wp + Vector3(0, 0.05, 0), "OOPS!", p.color, false)
	if p.joy >= 0:
		Input.start_joy_vibration(p.joy, 0.6, 0.4, 0.3)
	if net.mode != "client":
		_stat(p.index, "falls", 1.0)
	_forward_fx("fall", [wp], p)


func on_marble_respawn(p) -> void:
	burst(board.to_global(p.lp), Color(1, 1, 1), 8, false)


## A checkpoint: further along than the team's best? Then it's everyone's new respawn point.
func on_checkpoint(p) -> void:
	var wp: Vector3 = board.to_global(p.lp)
	sound("checkpoint", -4.0)
	var team := team_cp < 0 or board.checkpoint_dist(p.checkpoint) < board.checkpoint_dist(team_cp)
	if team:
		team_cp = p.checkpoint
		for o in players:
			if o.index > 0 and o.active and o.is_local() and not o.home:
				o.checkpoint = best_checkpoint(o.checkpoint)
	popup(wp + Vector3(0, 0.05, 0), "TEAM CHECKPOINT!" if team else "CHECKPOINT", Color(0.4, 0.85, 1.0), false)
	_forward_fx("cp", [wp], p)


## Teleporter whoosh at both ends.
func on_teleport(p, from: Vector2, to: Vector2) -> void:
	var a := board_world(from, 0.03)
	var b := board_world(to, 0.03)
	sound("teleport", -4.0, randf_range(0.9, 1.2))
	burst(a, Color(0.85, 0.5, 1.0), 10, false)
	burst(b, Color(0.4, 1.0, 0.9), 12, false)
	if net.mode != "client":
		_stat(p.index, "tp", 1.0)
	_forward_fx("tp", [a, b], p)


## Two marbles bumped into each other (gently, now): a friendly "boop".
func on_marble_boop(p, o) -> void:
	var mid: Vector3 = board.to_global((p.lp + o.lp) * 0.5)
	sound("boop", -6.0, randf_range(1.0, 1.3))
	popup(mid + Vector3(0, 0.04, 0), "boop!", Color(1.0, 0.75, 0.85), false)
	p.bump_squash()
	o.bump_squash()
	_forward_fx("boop", [mid], p)


## A marble dropped into the goal. Scored by the host (or local game); the TV machine only freezes it.
func on_marble_home(p) -> void:
	if net.mode == "client":
		net.send_action("home", [], p.index)  # the host scores it (it may not have seen the last frames)
		return
	score += 25
	var wp := board_world(board.goal, 0.06)
	popup(wp + Vector3(0, 0.05, 0), "P%d HOME! +25" % (p.index + 1), p.color)
	burst(wp, p.color, 20)
	sound("home", 0.0, 1.0 + 0.1 * home_count(), true)
	print("P%d reached the goal (%d/%d)" % [p.index + 1, home_count(), active_marbles().size()])
	var total := active_marbles().size()
	if home_count() == 1:
		first_home_t = level_t
		_stat(p.index, "first", 1.0)
		if total > 1:
			_show_center("P%d IS HOME!\nSteer your GUIDE STAR to tow your friends in!" % (p.index + 1), 2.0)
	elif home_count() == total and total > 1 and level_t - first_home_t <= 12.0:
		score += 50
		popup(wp + Vector3(0, 0.09, 0), "ALL TOGETHER! +50", Color(1.0, 0.9, 0.4))
		sound("combo", 0.0, 1.4, true)


# --- Networked co-op (see docs/GAME_DEV_GUIDE.md) ------------------------------------

func on_client_joined() -> void:
	_show_center("THE TV PLAYERS JOINED!", 1.5)
	_start_level(level if state != "over" else 1)


func on_client_left() -> void:
	for i in range(2, players.size()):
		if players[i].active:
			players[i].set_active(false)
	state = "wait"
	_show_center("The TV players left - waiting for them to come back…", 0.0)


func on_p2_action(action: String, args: Array, index: int = 1) -> void:
	if action == "join" and args.size() > 0:
		index = int(args[0])
	if index <= 0 or index >= players.size():
		return
	var p = players[index]
	match action:
		"join":
			if not p.active:
				_activate(p)
				print("Net: player %d joined the game" % (index + 1))
		"leave":
			if p.active:
				p.set_active(false)
				_show_center("PLAYER %d LEFT" % (index + 1), 1.5)
		"continue":
			_on_continue()
		"home":
			if state == "play" and p.active and not p.home and Vector2(p.lp.x, p.lp.z).distance_to(board.goal) < 0.2:
				p.home = true
				on_marble_home(p)
		"fx":
			if args.is_empty():
				return
			match str(args[0]):
				"bump":
					board.bump_fx(int(args[1]))
					sound("bump", -6.0)
				"fall":
					var wp: Vector3 = args[1]
					_stat(index, "falls", 1.0)
					sound("fall", -4.0)
					burst(wp, p.color, 10, false)
					popup(wp + Vector3(0, 0.05, 0), "OOPS!", p.color, false)
				"cp":
					sound("checkpoint", -6.0)
				"tp":
					sound("teleport", -6.0)
					burst(args[1], Color(0.85, 0.5, 1.0), 10, false)
					burst(args[2], Color(0.4, 1.0, 0.9), 12, false)
					_stat(index, "tp", 1.0)
				"boop":
					sound("boop", -8.0, 1.2)
					popup(args[1], "boop!", Color(1.0, 0.75, 0.85), false)
		"pause":
			var paused: bool = args[0]
			_set_pause_banner(paused, "A TV player opened the menu")
			get_tree().paused = paused


func _set_pause_banner(paused: bool, who: String) -> void:
	_show_center("PAUSED\n" + who if paused else "", 0.0, false)
	if vr_center != null and paused:
		VrText.snap(vr_center)


func toggle_vr_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_set_pause_banner(paused, "Wrist RESUME: carry on\nPull the trigger: back to the arcade")
	net.event("remote_pause", [paused])


func make_snapshot() -> Array:
	var ms: Array = []
	for i in range(1, players.size()):
		var p = players[i]
		ms.append([p.lp, p.active, p.home])
	var t = players[0]
	return [state, level, board.t, score, time_left, board.tilt, board_y, board.gem_taken.duplicate(), ms,
		t.head_transform(), t.hand_l_transform(), t.hand_r_transform(), state_t, best,
		board.gate_open.duplicate(), board.pad_on.duplicate(), golden, jar, stars, team_cp]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 14:
		return
	var lv: int = s[1]
	if lv != board.level_n or not synced:
		synced = true
		level = lv
		board.load_level(lv)
		_apply_theme()
		for p in players:
			if p.index > 0:
				p.reset_to_start()
	var new_state: String = s[0]
	if new_state != state:
		state = new_state
		state_t = float(s[12])
	net_t = s[2]
	if absf(board.t - net_t) > 0.5:
		board.t = net_t
	score = s[3]
	time_left = s[4]
	net_tilt = s[5]
	var by: float = s[6]
	if absf(by - board_y) > 0.001:
		set_board_height(by)
	var gt: Array = s[7]
	for i in mini(gt.size(), board.gem_taken.size()):
		board.gem_taken[i] = bool(gt[i])
	var ms: Array = s[8]
	for i in ms.size():
		var idx := i + 1
		if idx >= players.size():
			break
		var st: Array = ms[i]
		var p = players[idx]
		var act: bool = st[1]
		if act != p.active:
			p.set_active(act)
			if act:
				p.reset_to_start()
			on_player_activity_changed(p)
		if act and bool(st[2]) and not p.home and state == "play":
			p.home = true
		if not is_local(p):
			p.target_lp = st[0]
	var t = players[0]
	t.net_head = s[9]
	t.net_hand_l = s[10]
	t.net_hand_r = s[11]
	best = s[13]
	if s.size() >= 20:
		var go: Array = s[14]
		for g in mini(2, go.size()):
			board.gate_open[g] = bool(go[g])
		var po: Array = s[15]
		for i in mini(po.size(), board.pad_on.size()):
			board.pad_on[i] = bool(po[i])
		golden = s[16]
		jar = s[17]
		stars = s[18]
		var tcp: int = s[19]
		if tcp != team_cp and tcp >= 0:
			team_cp = tcp  # the host knows best (e.g. from its own marbles)


func apply_event(kind: String, args: Array) -> void:
	if not ready_to_play:
		return
	match kind:
		"sound":
			sound(args[0], args[1], args[2])
		"burst":
			burst(args[0], args[1], args[2], false)
		"popup":
			popup(args[0], args[1], args[2], false)
		"center":
			_show_center(args[0], args[1], false)
		"level":
			var lv: int = args[0]
			team_cp = -1
			golden = NONE
			if lv != board.level_n:
				level = lv
				board.load_level(lv)
			_apply_theme()
			for p in players:
				if p.index > 0:
					p.reset_to_start()
			state = "intro"
			state_t = 0.0
		"remote_pause":
			get_tree().paused = args[0]
			_set_pause_banner(args[0], "The VR player paused the game")


# --- HUD -----------------------------------------------------------------------------

func _make_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", maxi(4, size / 5))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	center_label = _make_label(46)
	layer.add_child(center_label)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label = _make_label(20)
	layer.add_child(help_label)
	help_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	help_label.offset_top = -64
	help_label.offset_bottom = -12
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.text = "Marble: left stick / arrows roll · right stick (Q/E, mouse on the TV) turns the camera · Start / Esc menu\n" \
		+ "Split screen P1 tilts the board: WASD / mouse / left stick, Space or A levels it  ·  More marbles: press A on another controller"


func _show_center(text: String, duration: float, broadcast: bool = true) -> void:
	if net and broadcast:
		net.event("center", [text, duration])
	center_label.text = text
	center_label.modulate.a = 1.0
	if center_tween:
		center_tween.kill()
	if duration > 0.0:
		center_tween = create_tween()
		center_tween.tween_interval(duration)
		center_tween.tween_property(center_label, "modulate:a", 0.0, 0.5)


func hud_text(p) -> String:
	if net.mode == "client" and not synced:
		return "Syncing with the VR player…"
	var gems := 0
	for g in board.gem_taken:
		if g:
			gems += 1
	var line := "LEVEL %d  ·  %s\nTIME %d   SCORE %d   STARS %d\nHOME %d/%d   GEMS %d/%d   JAR %d/%d" % [level, board.level_name(level),
		int(ceilf(time_left)), score, stars, home_count(), active_marbles().size(), gems, board.gem_taken.size(), jar % JAR_SIZE, JAR_SIZE]
	if p.index == 0:
		return line + "\nYOU TILT THE BOARD!" + ("\nGentle tilts help them sit on the pads!" if _gates_closed() else "")
	return line + "\n" + _marble_hint(p)


## A short "what do I do now?" line for one marble.
func _marble_hint(p) -> String:
	if state == "intro":
		return "Get ready to roll!"
	if state == "clear":
		return "LEVEL CLEAR! Press A to roll on"
	if state == "over":
		return "Press A to play again"
	if p.home:
		var left := active_marbles().size() - home_count()
		if left <= 0:
			return "EVERYONE'S HOME!"
		return "YOU'RE HOME! Steer your GUIDE STAR onto a friend to tow them in!"
	if p.falling:
		return "WHOOPS! Back to the team checkpoint…"
	var pos := Vector2(p.lp.x, p.lp.z)
	var pad := board.pad_at(pos)
	if pad >= 0 and _gates_closed():
		return "You're on a TEAM PAD! Stay put and wait for a friend on the other pad!"
	if _gates_closed():
		return "Find a glowing TEAM PAD - a friend goes to the other one!"
	if golden != NONE:
		return "A GOLDEN GEM! Grab it if you can!"
	var cc: Vector2i = board.cell_of(pos)
	match board.ch(cc.x, cc.y):
		"I":
			return "ICE! Steer gently, you'll slide!"
		"M":
			return "MUD! Keep pushing, it's slow!"
	if home_count() > 0:
		return "Your friends' guide stars can tow you - roll to them!"
	return "Roll to the glowing goal! Bump gently - it's a team game!"


func _gates_closed() -> bool:
	for g in 2:
		if board.group_has_pads(g) and not board.gate_open[g]:
			return true
	return false


func _update_vr_text() -> void:
	if help_label.modulate.a > 0.0 and level >= 2:
		help_label.modulate.a = maxf(0.0, help_label.modulate.a - get_process_delta_time() * 0.5)
	if players.is_empty() or not players[0].vr:
		return
	var cam: XRCamera3D = players[0].xr_camera
	if vr_center == null:
		vr_center = Label3D.new()
		vr_center.font_size = 44
		vr_center.outline_size = 26
		vr_center.pixel_size = 0.0022
		vr_center.no_depth_test = false
		vr_center.render_priority = 10
		vr_center.outline_render_priority = 9
		vr_center.width = 1100.0
		vr_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(vr_center)
	vr_center.text = center_label.text
	vr_center.modulate.a = center_label.modulate.a
	vr_center.outline_modulate = Color(0, 0, 0, center_label.modulate.a)
	VrText.follow(vr_center, cam, self, -0.05, 1.8)
	# Scoreboard hanging high above the far side of the table (world-locked, ~2.4 m away, above the banner).
	if vr_board == null:
		vr_board = Label3D.new()
		vr_board.font_size = 56
		vr_board.outline_size = 22
		vr_board.pixel_size = 0.0028
		vr_board.modulate = Color(1.0, 0.95, 0.7)
		vr_board.outline_modulate = Color(0, 0, 0)
		add_child(vr_board)
	vr_board.position = Vector3(0.0, board_y + 1.4, -1.6)
	var gems := 0
	for g in board.gem_taken:
		if g:
			gems += 1
	vr_board.text = "LEVEL %d · %s\nTIME %d    SCORE %d    STARS %d\nHOME %d/%d    GEMS %d/%d" % [level, board.level_name(level),
		int(ceilf(time_left)), score, stars, home_count(), active_marbles().size(), gems, board.gem_taken.size()]
	if state == "play" and _gates_closed():
		vr_board.text += "\nTEAM PADS: tilt gently so they can wait on them!"
	elif state == "play" and home_count() > 0 and home_count() < active_marbles().size():
		vr_board.text += "\nHelp the last marbles home!"
