extends Node3D
## Rocket Workshop: a cosy talk-to-each-other puzzle game (no arena, no enemies).
## The pilot (VR, host, players[0]) stands at the rocket's control desk with buttons, plugs, a dial,
## switches, two cockpit wings (ALIEN HELLO and the THRUSTER CRANK) and the big launch lever, but
## can't see any instructions. The TV crew (1-6 players) walk round the workshop, read the blueprint
## boards on the walls and SAY what to do. They also fetch fuel canisters and paint pots, collect loose
## bolts, fix leaky pipes and catch the space cat. Get every module done and pull the lever before the
## countdown ends! Every rocket flies to the next planet on the SPACE MAP (and the crew get a launch
## cam). Mistakes just make the rocket burp and cost a few seconds. Stars, streaks and awards at the end.
##
## Files: puzzles.gd (module generation), panel.gd (pilot's desk), manual.gd (blueprint boards),
## jobs.gd (crew jobs), rocket.gd (rocket + launch fx), space.gd (planets, map, log, launch cam),
## operator.gd (pilot), player.gd (crew), world.gd (the workshop), join_listener.gd (drop-in join).
## The host is authoritative; modules travel to the TV in snapshots.

const P := preload("res://games/rocket_workshop/puzzles.gd")
const WorldScript := preload("res://games/rocket_workshop/world.gd")
const PanelScript := preload("res://games/rocket_workshop/panel.gd")
const ManualScript := preload("res://games/rocket_workshop/manual.gd")
const RocketScript := preload("res://games/rocket_workshop/rocket.gd")
const JobsScript := preload("res://games/rocket_workshop/jobs.gd")
const SpaceScript := preload("res://games/rocket_workshop/space.gd")
const OperatorScript := preload("res://games/rocket_workshop/operator.gd")
const PlayerScript := preload("res://games/rocket_workshop/player.gd")
const JoinListenerScript := preload("res://games/rocket_workshop/join_listener.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const VrText := preload("res://core/vr_text.gd")

const MANUAL_LAYER := 512  # blueprint content: drawn for the TV crew only
const PANEL_LAYER := 1024  # desk controls: drawn for the pilot only
const PAD_POS := Vector3(0, 0, -11.0)
const HATCH_POS := Vector3(0, 0, -8.0)
const LAUNCH_TIME := 11.5
const INTRO_TIME := 3.0
const FIRST_INTRO_TIME := 7.0
const MAX_PLAYERS := 7  # pilot + 6 crew
const MAX_LOCAL_VIEWS := 6
const PAD_LEAVE_TIME := 20.0
const PLAYER_COLORS: Array[Color] = [Color(1.0, 0.55, 0.25), Color(0.3, 0.65, 1.0), Color(0.55, 0.85, 0.35),
	Color(1.0, 0.4, 0.6), Color(0.75, 0.5, 1.0), Color(1.0, 0.85, 0.25), Color(0.3, 0.9, 0.85)]
const CREW_SPOTS: Array[Vector3] = [Vector3(-2.2, 0, 4.5), Vector3(2.2, 0, 4.5), Vector3(-4.4, 0, 5.6), Vector3(4.4, 0, 5.6),
	Vector3(-6.4, 0, 4.0), Vector3(6.4, 0, 4.0)]
const BOARD_PLACES := {"fuel": "left wall", "wires": "left wall", "gauge": "right wall", "switches": "right wall",
	"symbols": "back wall, middle", "alien": "back wall corner", "crank": "back wall corner"}
const NEW_LINES := {
	"alien": "NEW: ALIEN HELLO! Pilot: describe the alien on your LEFT wing. Crew: find it on the alien chart!",
	"crank": "NEW: THRUSTER CRANK on the pilot's RIGHT wing: grab the handle and wind it round!",
	"paint": "NEW JOB: PAINT! Only the pilot's screen says which colour - crew, fetch that pot from outside!",
	"bolts": "NEW JOB: LOOSE BOLTS! Crew: pick up all 3 shiny bolts (follow the golden beams).",
	"canister": "NEW JOB: FUEL CAN! Crew: carry it to the glowing ring by the rocket.",
	"pipe": "NEW JOB: LEAKY PIPE! Crew: stand by the sparks and HOLD A (keyboard: Space / Enter).",
}
const SOUNDS := {
	"boop": [0.09, 620.0, 900.0, 0.3, "sine", 0.0],
	"click": [0.03, 1600.0, 900.0, 0.2, "square", 0.3],
	"plug": [0.14, 300.0, 1000.0, 0.35, "tri", 0.1],
	"burp": [0.65, 150.0, 50.0, 0.65, "saw", 0.3],
	"solve": [0.4, 523.0, 1046.0, 0.35, "tri", 0.0],
	"allset": [0.9, 392.0, 1568.0, 0.4, "tri", 0.0],
	"tick": [0.06, 1300.0, 1300.0, 0.2, "sine", 0.0],
	"count": [0.3, 880.0, 870.0, 0.35, "sine", 0.0],
	"rumble": [3.2, 70.0, 28.0, 0.75, "saw", 0.9],
	"whoosh": [1.6, 300.0, 1400.0, 0.4, "sine", 0.7],
	"pop": [0.15, 400.0, 1400.0, 0.3, "sine", 0.1],
	"fix": [0.08, 2200.0, 700.0, 0.12, "saw", 0.6],
	"nap": [1.6, 400.0, 120.0, 0.4, "tri", 0.0],
	"beep": [0.18, 990.0, 990.0, 0.3, "square", 0.0],
	"boopy": [0.25, 520.0, 330.0, 0.35, "sine", 0.0],
	"zorp": [0.35, 220.0, 900.0, 0.3, "saw", 0.1],
	"crank": [0.05, 700.0, 500.0, 0.25, "square", 0.4],
	"meow": [0.45, 820.0, 560.0, 0.3, "tri", 0.05],
	"comet": [1.8, 1800.0, 300.0, 0.3, "sine", 0.5],
	"ting": [0.3, 1760.0, 2400.0, 0.25, "sine", 0.0],
	"splash": [0.4, 600.0, 150.0, 0.35, "sine", 0.8],
	"arrive": [1.1, 523.0, 2093.0, 0.4, "square", 0.0],
	"star": [0.22, 1320.0, 1980.0, 0.28, "tri", 0.0],
	"uhoh": [0.6, 520.0, 260.0, 0.35, "square", 0.0],
}
const HELLO_SOUNDS: Array[String] = ["beep", "boopy", "zorp"]

var players: Array = []
var ready_to_play := false
var net: Node
var sfx: Node
var music: Node
var mats := {}
var meshes := {}
var xr_interface: XRInterface
var mirror_vp: SubViewport
var mirror_t := 0.0
var panel: Node3D
var manual: Node3D
var rocket: Node3D
var jobs: Node3D
var space: Node3D
var synced := false
var join_listener: Node
var joy_owner := {}  # joypad device id -> player index
var views_root: Control
var last_view_area := Vector2.ZERO

var phase := "wait"  # wait, intro, work, ready, launch, over
var phase_t := 0.0
var rocket_n := 0
var rocket_name := ""
var modules: Array = []
var time_left := 0.0
var start_time := 1.0
var launched := 0
var mistakes := 0
var rocket_burps := 0
var launch_t := 0.0
var game_over := false
var game_over_time := 0.0
var best := 0
var last_tick := -1
var msg := ""
var msg_t := 0.0
var lever_hint_t := 0.0
var stars := 0
var last_stars := 0
var streak := 0
var bonus_next := 0.0
var events_left := 0
var event_at := 0.0
var seen_types := {}
var crew_stats := {}  # player index -> {read, deliver, fix, bolts, cat}
var cat_goal := Vector3.ZERO
var cat_meow_t := 2.0
var over_armed := false
var status_t := 0.0

var info_label: Label
var list_label: Label
var center_label: Label
var help_label: Label
var center_tween: Tween
var vr_center: Label3D


func _ready() -> void:
	randomize()
	var xr := XRServer.find_interface("OpenXR")
	var will_vr := xr != null and xr.is_initialized() and not OS.has_environment("DUO_JOIN")
	WorldScript.build(self, will_vr)
	rocket = RocketScript.new()
	rocket.main = self
	add_child(rocket)
	space = SpaceScript.new()
	space.main = self
	add_child(space)
	manual = ManualScript.new()
	manual.main = self
	add_child(manual)
	jobs = JobsScript.new()
	jobs.main = self
	add_child(jobs)
	_build_hud()
	best = _load_best()
	var menu := PauseMenuScript.new()
	menu.main = self
	add_child(menu)
	net = NetScript.new()
	net.name = "Net"
	net.main = self
	add_child(net)
	Input.joy_connection_changed.connect(_on_joy_changed)
	if OS.has_environment("DUO_JOIN"):
		_show_center("Connecting to the pilot…", 0.0)
		net.join_finished.connect(func(ok: bool) -> void: _setup_game("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if will_vr or OS.has_environment("DUO_HOST"):
			net.host()
		_setup_game(net.mode)


func _setup_game(mode: String) -> void:
	panel = PanelScript.new()
	panel.main = self
	panel.detail = mode != "client"
	add_child(panel)
	_build_players(mode)
	_build_views(mode)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mode == "client" else Input.MOUSE_MODE_VISIBLE
	_assign_joypads()
	ready_to_play = true
	_ensure_join_listener()
	_restore_party()
	if mode == "host":
		_show_center("Waiting for the TV crew to join…", 0.0)
	elif mode == "client":
		_show_center("CONNECTED!\nFind the boards with BOUNCING ARROWS and tell the pilot what they say!", 3.0)
	else:
		_show_center("ROCKET WORKSHOP\nPilot: work the desk.  Crew: read the blueprints out loud!", 3.0)


func _exit_tree() -> void:
	XRServer.world_scale = 1.0  # global: never leave another game's scale behind


# --- Shared materials, meshes and effects ------------------------------------

func make_material(color: Color, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


## Shared material per colour (so identical blobs batch together).
func color_mat(color: Color, glow: float) -> StandardMaterial3D:
	var key := "%s/%.2f" % [color.to_html(), glow]
	if not mats.has(key):
		mats[key] = make_material(color, glow)
	return mats[key]


func vertex_mat() -> StandardMaterial3D:
	if not mats.has("vertex"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.6
		mats["vertex"] = m
	return mats["vertex"]


func sphere_mesh(r: float) -> SphereMesh:
	var key := "s%.3f" % r
	if not meshes.has(key):
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 14
		sm.rings = 7
		meshes[key] = sm
	return meshes[key]


func box_mesh(size: Vector3) -> BoxMesh:
	var key := "b%s" % size
	if not meshes.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		meshes[key] = bm
	return meshes[key]


func cyl_mesh(r_top: float, r_bottom: float, h: float, seg: int) -> CylinderMesh:
	var key := "c%.3f/%.3f/%.3f/%d" % [r_top, r_bottom, h, seg]
	if not meshes.has(key):
		var cm := CylinderMesh.new()
		cm.top_radius = r_top
		cm.bottom_radius = r_bottom
		cm.height = h
		cm.radial_segments = seg
		cm.rings = 1
		meshes[key] = cm
	return meshes[key]


func capsule_mesh(r: float, h: float) -> CapsuleMesh:
	var key := "p%.3f/%.3f" % [r, h]
	if not meshes.has(key):
		var cm := CapsuleMesh.new()
		cm.radius = r
		cm.height = h
		cm.radial_segments = 12
		cm.rings = 4
		meshes[key] = cm
	return meshes[key]


## Several primitive meshes baked into one vertex-coloured mesh, so a little character is ONE draw
## call. parts: [[Mesh, Transform3D, Color], ...]; cached by key.
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


## Two little eyes in one mesh (crew faces).
func eyes_mesh() -> ArrayMesh:
	var e := sphere_mesh(0.035)
	return merged_mesh("eyes", [[e, Transform3D(Basis(), Vector3(-0.075, 0, 0)), Color(0.08, 0.06, 0.1)],
		[e, Transform3D(Basis(), Vector3(0.075, 0, 0)), Color(0.08, 0.06, 0.1)]])


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
		pts.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
	for face in [1.0, -1.0]:
		st.set_normal(Vector3(0, 0, face))
		for i in 10:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[(i + 1) % 10]
			st.add_vertex(Vector3(0, 0, 0.08 * face))
			if face > 0.0:
				st.add_vertex(a)
				st.add_vertex(b)
			else:
				st.add_vertex(b)
				st.add_vertex(a)
	var m := st.commit()
	meshes["star"] = m
	return m


## A friendly alien (one merged mesh): colour 0-2, 1-3 eyes, top 0 antenna / 1 horns / 2 big ears.
## Stands on y = 0, faces +Z, about `size` metres tall.
func alien_node(color_i: int, eye_n: int, top: int, size: float) -> Node3D:
	var key := "alien%d/%d/%d" % [color_i, eye_n, top]
	if not meshes.has(key):
		var skin: Color = P.ALIEN_COLORS[clampi(color_i, 0, 2)]
		var white := Color(1, 1, 1)
		var dark := Color(0.08, 0.06, 0.12)
		var parts: Array = []
		parts.append([sphere_mesh(0.5), Transform3D(Basis.from_scale(Vector3(1.0, 1.1, 0.95)), Vector3(0, 0.55, 0)), skin])
		parts.append([sphere_mesh(0.14), Transform3D(Basis.from_scale(Vector3(1.3, 0.7, 1.0)), Vector3(-0.22, 0.06, 0.05)), skin.darkened(0.2)])
		parts.append([sphere_mesh(0.14), Transform3D(Basis.from_scale(Vector3(1.3, 0.7, 1.0)), Vector3(0.22, 0.06, 0.05)), skin.darkened(0.2)])
		var xs: Array = [[0.0], [-0.17, 0.17], [-0.24, 0.0, 0.24]][clampi(eye_n, 1, 3) - 1]
		var er := 0.19 if eye_n == 1 else 0.13
		for k in xs.size():
			var x: float = xs[k]
			var y := 0.72 + (0.07 if eye_n == 3 and k == 1 else 0.0)
			parts.append([sphere_mesh(er), Transform3D(Basis(), Vector3(x, y, 0.4)), white])
			parts.append([sphere_mesh(er * 0.5), Transform3D(Basis(), Vector3(x, y, 0.4 + er * 0.75)), dark])
		parts.append([box_mesh(Vector3(0.26, 0.05, 0.05)), Transform3D(Basis(), Vector3(0, 0.38, 0.46)), dark])
		match top:
			0:
				for side in [-1.0, 1.0]:
					var b := Basis(Vector3.BACK, -side * 0.35)
					parts.append([cyl_mesh(0.025, 0.025, 0.35, 6), Transform3D(b, Vector3(side * 0.12, 1.12, 0) + b * Vector3(0, 0.1, 0)), dark])
					parts.append([sphere_mesh(0.08), Transform3D(Basis(), Vector3(side * 0.12, 1.12, 0) + b * Vector3(0, 0.3, 0)), Color(1.0, 0.95, 0.4)])
			1:
				for side in [-1.0, 1.0]:
					var b := Basis(Vector3.BACK, -side * 0.4)
					parts.append([cyl_mesh(0.0, 0.09, 0.3, 8), Transform3D(b, Vector3(side * 0.22, 1.05, 0) + b * Vector3(0, 0.08, 0)), Color(1.0, 0.95, 0.85)])
			_:
				for side in [-1.0, 1.0]:
					parts.append([sphere_mesh(0.22), Transform3D(Basis.from_scale(Vector3(0.35, 1.0, 0.8)), Vector3(side * 0.55, 0.78, 0)), skin.lightened(0.15)])
		merged_mesh(key, parts)
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = meshes[key]
	mi.material_override = vertex_mat()
	mi.scale = Vector3.ONE * size
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	return n


## One of the six puzzle shapes, standing upright, about `size` metres across.
func shape_node(id: int, size: float) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	match id:
		0:
			mi.mesh = sphere_mesh(size * 0.5)
		1:
			mi.mesh = box_mesh(Vector3.ONE * size * 0.8)
			mi.rotation.y = 0.5
		2:
			mi.mesh = cyl_mesh(0.0, size * 0.5, size, 14)
		3:
			var tm := TorusMesh.new()
			tm.inner_radius = size * 0.22
			tm.outer_radius = size * 0.5
			tm.rings = 16
			tm.ring_segments = 8
			mi.mesh = tm
			mi.rotation.x = PI / 2.0
		4:
			mi.mesh = capsule_mesh(size * 0.22, size)
			mi.rotation.z = PI / 2.0
		_:
			var pm := PrismMesh.new()
			pm.size = Vector3(size, size * 0.8, size * 0.6)
			mi.mesh = pm
	mi.material_override = color_mat(P.SHAPE_COLORS[clampi(id, 0, 5)], 0.25)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	return n


func set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for c in node.get_children():
		set_layers(c, layers)


## Local-only puff of particles.
func puff(pos: Vector3, color: Color, amount: int = 10, size: float = 0.08) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.gravity = Vector3(0, 1.0, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var m := SphereMesh.new()
	m.radius = size
	m.height = size * 2.0
	m.radial_segments = 6
	m.rings = 3
	m.material = color_mat(color, 0.3)
	p.mesh = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


## Networked burst: shown here and on the TV.
func burst(pos: Vector3, color: Color, amount: int = 16, size: float = 0.1) -> void:
	puff(pos, color, amount, size)
	net.event("burst", [pos, color, amount, size])


## A shower of little gold stars (local; host sends event "stars").
func star_burst(pos: Vector3, amount: int = 14) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 1.4
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -4.0, 0)
	p.angular_velocity_min = -300.0
	p.angular_velocity_max = 300.0
	p.scale_amount_min = 0.09
	p.scale_amount_max = 0.16
	p.mesh = star_mesh()
	p.material_override = color_mat(Color(1.0, 0.85, 0.2), 1.5)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.8).timeout.connect(p.queue_free)


func local_sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if sfx == null:
		sfx = SfxScript.new()
		add_child(sfx)
	if SOUNDS.has(sound_name):
		sfx.add_sound(sound_name, SOUNDS[sound_name])
	sfx.play(sound_name, volume_db, pitch)


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	local_sound(sound_name, volume_db, pitch)
	if net:
		net.event("sound", [sound_name, volume_db, pitch])


## Floating 3D text that rises and fades; shown on both machines (upright, not billboarded).
func popup(pos: Vector3, text: String, color: Color, broadcast: bool = true) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.font_size = 64
	l.outline_size = 18
	l.pixel_size = 0.008
	l.no_depth_test = true
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	l.global_position = pos
	if not players.is_empty() and players[0].vr:
		# Face the pilot (fixed, world-locked text); the crew only see it from behind sometimes.
		var to: Vector3 = pos - players[0].xr_camera.global_position
		l.global_basis = Basis(Vector3.UP, atan2(-to.x, -to.z))
	else:
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "global_position", pos + Vector3.UP * 1.2, 1.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.9)
	t.tween_property(l, "outline_modulate:a", 0.0, 0.9).set_delay(0.9)
	t.chain().tween_callback(l.queue_free)
	if broadcast:
		net.event("popup", [pos, text, color])


## A golden comet streaks across the sky (both machines; event "comet").
func spawn_comet() -> void:
	var c := Node3D.new()
	add_child(c)
	var head := MeshInstance3D.new()
	head.mesh = sphere_mesh(2.2)
	var hm := make_material(Color(1.0, 0.9, 0.5), 4.0)
	hm.disable_fog = true
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	head.material_override = hm
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.add_child(head)
	var trail := CPUParticles3D.new()
	trail.amount = 40
	trail.lifetime = 1.2
	trail.local_coords = false
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_min = 0.5
	trail.initial_velocity_max = 2.0
	trail.spread = 180.0
	trail.scale_amount_min = 0.5
	trail.scale_amount_max = 1.2
	var tm := SphereMesh.new()
	tm.radius = 1.4
	tm.height = 2.8
	tm.radial_segments = 6
	tm.rings = 3
	var tmat := make_material(Color(1.0, 0.75, 0.4), 2.5)
	tmat.disable_fog = true
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.material = tmat
	trail.mesh = tm
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.add_child(trail)
	var from := Vector3(-160, 120, -170)
	var to := Vector3(170, 85, -190)
	c.global_position = from
	var tw := c.create_tween()
	tw.tween_property(c, "global_position", to, 3.5)
	tw.tween_callback(c.queue_free)


# --- Puzzle state helpers ----------------------------------------------------

func module(type: String) -> Dictionary:
	for m in modules:
		if m.type == type:
			return m
	return {}


func _all_done() -> bool:
	for m in modules:
		if not m.done:
			return false
	return true


## Is this crew member carrying something (fuel, paint or the cat)?
func is_carrying(index: int) -> bool:
	for t in ["canister", "paint", "cat"]:
		var m := module(t)
		if not m.is_empty() and not m.done and int(m.carrier) == index:
			return true
	return false


## Keep a crew member on the floor, out of the pilot's booth, the walls and the launch pad.
func clamp_walk(p: Vector3) -> Vector3:
	p.y = 0.0
	p.x = clampf(p.x, -10.5, 10.5)
	p.z = clampf(p.z, -17.0, 7.6)
	if absf(p.x) > 3.9 and absf(p.z + 6.15) < 0.45:
		p.z = -6.6 if p.z < -6.15 else -5.7
	if absf(p.x) < 1.4 and p.z > -1.3 and p.z < 1.05:
		var dx := 1.4 - absf(p.x)
		var dz_back := 1.05 - p.z
		var dz_front := p.z + 1.3
		if dx < dz_back and dx < dz_front:
			p.x = 1.4 * (1.0 if p.x >= 0.0 else -1.0)
		elif dz_back < dz_front:
			p.z = 1.05
		else:
			p.z = -1.3
	var flat := Vector2(p.x - PAD_POS.x, p.z - PAD_POS.z)
	if flat.length() < 2.7:
		flat = flat.normalized() * 2.7 if flat.length() > 0.01 else Vector2(0, 2.7)
		p.x = PAD_POS.x + flat.x
		p.z = PAD_POS.z + flat.y
	return p


func pipe_point() -> Vector3:
	var m := module("pipe")
	if m.is_empty():
		return Vector3.ZERO
	return P.PIPE_SPOTS[int(m.spot)]


func pipe_near(pos: Vector3) -> bool:
	var m := module("pipe")
	if m.is_empty() or m.done or (phase != "work" and phase != "ready"):
		return false
	var s := pipe_point()
	return Vector2(pos.x - s.x, pos.z - s.z).length() < 2.0


## Host: a crew member is working on the leaky pipe.
func fix_pipe(index: int, amount: float) -> void:
	var m := module("pipe")
	if m.is_empty() or m.done or index <= 0 or index >= players.size():
		return
	if not pipe_near(players[index].global_position):
		return
	var add := clampf(amount, 0.0, 0.2)
	m.progress = minf(1.0, float(m.progress) + add)
	_stat(index, "fix", add)
	if float(m.progress) >= 1.0:
		burst(pipe_point(), Color(0.5, 0.8, 1.0), 20, 0.08)
		popup(pipe_point() + Vector3.UP * 1.2, "PIPE FIXED!", Color(0.5, 1.0, 0.6))
		_solve(m)


func _stat(index: int, key: String, amount: float) -> void:
	if not crew_stats.has(index):
		crew_stats[index] = {"read": 0.0, "deliver": 0.0, "fix": 0.0, "bolts": 0.0, "cat": 0.0}
	var s: Dictionary = crew_stats[index]
	s[key] = float(s[key]) + amount


# --- Game flow (host) ----------------------------------------------------------

func crew_count() -> int:
	var n := 0
	for p in players:
		if p.index > 0 and p.active:
			n += 1
	return n


func _start_rocket(n: int) -> void:
	var r := P.make_rocket(n, crew_count())
	rocket_n = n
	rocket_name = r.name
	modules = r.modules
	time_left = float(r.time) + bonus_next
	start_time = time_left
	if bonus_next > 0.0:
		print("Streak bonus: +%.0f s" % bonus_next)
	bonus_next = 0.0
	rocket_burps = 0
	phase = "intro"
	launch_t = 0.0
	last_tick = -1
	# Gentle chaos from rocket 3: a surprise or two in the middle of the countdown.
	events_left = 0
	if n >= 6:
		events_left = 1 + (1 if randf() < 0.5 else 0)
	elif n >= 3:
		events_left = 1 if randf() < 0.75 else 0
	event_at = time_left * randf_range(0.45, 0.7)
	var types: Array[String] = []
	var fresh: Array[String] = []
	for m in modules:
		types.append(m.type)
		if not seen_types.has(m.type):
			seen_types[m.type] = true
			if NEW_LINES.has(m.type) and n > 1:
				fresh.append(NEW_LINES[m.type])
	print("Rocket %d (%s) to %s: %s, %.0f s" % [n, rocket_name, P.PLANETS[P.planet(n)], ", ".join(types), time_left])
	sound("pop", -2.0, 0.8)
	if n == 1:
		phase_t = FIRST_INTRO_TIME
		_show_center("ROCKET WORKSHOP!  First stop: %s\nPILOT: you have the buttons, but no instructions.\n" % P.PLANETS[0] \
			+ "CREW: find the boards with BOUNCING ARROWS and read them out loud!\nFinish every job, then PULL THE LEVER, CRONK!", FIRST_INTRO_TIME)
	else:
		phase_t = INTRO_TIME + 2.0 * fresh.size()
		var head := "ROCKET #%d IS ON THE PAD!  Next stop: %s" % [n, P.PLANETS[P.planet(n)]]
		if fresh.is_empty():
			_show_center(head + "\nCrew: find the bouncing arrows.  Pilot: say the rocket's name!", phase_t)
		else:
			_show_center(head + "\n" + "\n".join(fresh), phase_t)


## Host: the pilot touched or moved something on the desk.
func on_panel(kind: String, args: Array) -> void:
	if kind == "lever":
		if phase == "ready":
			_start_launch()
		elif phase == "work" and lever_hint_t <= 0.0:
			lever_hint_t = 3.0
			_flash("Not yet! Finish every job first.")
			sound("boop", -6.0, 0.5)
		return
	if phase != "work" and phase != "ready":
		return
	match kind:
		"fuel":
			var m := module("fuel")
			if m.is_empty() or m.done:
				return
			var pressed: Array = m.pressed
			var answer: Array = m.answer
			pressed.append(int(args[0]))
			sound("plug", -4.0, 0.7 + int(args[0]) * 0.15)
			if pressed.size() >= answer.size():
				var mix := pressed.duplicate()
				mix.sort()
				if mix == answer:
					_solve(m)
				else:
					m.pressed = []
					_burp("That fuel mix was yucky!")
		"plug":
			var m := module("wires")
			if m.is_empty() or m.done:
				return
			var color := int(args[0])
			var socket := int(args[1])
			var order: Array = m.order
			var placed: Array = m.placed
			if placed.has(color) or socket < 0 or socket > 3 or int(placed[socket]) >= 0:
				return
			if socket < order.size() and int(order[socket]) == color:
				placed[socket] = color
				sound("plug", -2.0, 1.0)
				var all := true
				for i in order.size():
					if int(placed[i]) != int(order[i]):
						all = false
				if all:
					_solve(m)
			else:
				_burp("Wrong socket - zzzap!")
		"shape":
			var m := module("symbols")
			if m.is_empty() or m.done:
				return
			var layout: Array = m.layout
			var order: Array = m.order
			var step: int = m.step
			var shape := int(layout[int(args[0])])
			sound("boop", -4.0, 0.8 + step * 0.2)
			if shape == int(order[step]):
				m.step = step + 1
				if int(m.step) >= order.size():
					_solve(m)
			else:
				m.step = 0
				_burp("Wrong shape order!")
		"dial":
			var m := module("gauge")
			if not m.is_empty() and not m.done:
				m.value = clampi(int(args[0]), 1, 9)
		"set":
			var m := module("gauge")
			if m.is_empty() or m.done:
				return
			sound("boop", -4.0)
			if int(m.value) == int(m.answer):
				_solve(m)
			else:
				_burp("Too much pressure!" if int(m.value) > int(m.answer) else "Not enough pressure!")
		"switch":
			var m := module("switches")
			if m.is_empty() or m.done:
				return
			var state: Array = m.state
			var i := int(args[0])
			state[i] = not bool(state[i])
			sound("click", -4.0, 1.0)
		"check":
			var m := module("switches")
			if m.is_empty() or m.done:
				return
			sound("boop", -4.0)
			if m.state == m.answer:
				_solve(m)
			else:
				_burp("The switches are muddled!")
		"hello":
			var m := module("alien")
			var word := clampi(int(args[0]), 0, 2)
			sound(HELLO_SOUNDS[word], -2.0)
			if m.is_empty() or m.done:
				return
			if word == int(m.answer):
				popup(panel.control_world("hello%d" % word) + Vector3.UP * 0.35, P.HELLO_WORDS[word] + "!", P.HELLO_COLORS[word])
				_solve(m)
			else:
				_burp("That alien says hello differently!")
		"crank":
			var m := module("crank")
			var turns := int(args[0])
			sound("crank", -4.0, 0.8 + 0.12 * turns)
			if not m.is_empty() and not m.done:
				m.turns = turns
		"crank_go":
			var m := module("crank")
			if m.is_empty() or m.done:
				return
			sound("boop", -4.0)
			if int(m.turns) == int(m.answer):
				_solve(m)
			else:
				var why := "Too many turns!" if int(m.turns) > int(m.answer) else "Not enough turns!"
				m.turns = 0
				panel.reset_crank()
				_burp(why)


func _solve(m: Dictionary) -> void:
	m.done = true
	var title: String = P.TITLES[m.type]
	print("Module solved: %s (rocket %d, %.0f s left)" % [m.type, rocket_n, time_left])
	sound("solve", -2.0)
	_flash(title + " - DONE!")
	if not P.is_job(m.type) and manual.boards.has(m.type):
		var root: Node3D = manual.boards[m.type].root
		burst(root.global_position + root.global_basis.z * 0.5, Color(0.4, 1.0, 0.5), 18, 0.08)
	for p in players:
		if p.index == 0:
			p.haptic("r", 0.6)
	if _all_done() and phase == "work":
		phase = "ready"
		sound("allset", 0.0)
		print("All modules done: waiting for the launch lever")
		_show_center("ALL SYSTEMS GO!\nPULL THE LEVER, CRONK!", 6.0)  # David's wording


## A mistake: the rocket burps and the countdown loses a few seconds (never below 5).
func _burp(why: String) -> void:
	mistakes += 1
	rocket_burps += 1
	time_left = maxf(minf(time_left, 5.0), time_left - P.MISTAKE_SECONDS)
	print("Oops: %s (mistake %d, %.0f s left)" % [why, mistakes, time_left])
	sound("burp", 2.0, randf_range(0.85, 1.1))
	rocket.burp()
	net.event("burp", [])
	popup(PAD_POS + Vector3(0, 6.2, 0), "BURP!", Color(0.6, 1.0, 0.4))
	_show_center("Oops! The rocket burped!\n%s  (-%d s)" % [why, int(P.MISTAKE_SECONDS)], 2.2)
	_flash("Oops! " + why)
	if players[0].vr:
		players[0].haptic("l", 0.8)
		players[0].haptic("r", 0.8)


func _flash(text: String) -> void:
	msg = text
	msg_t = 3.0


func _start_launch() -> void:
	phase = "launch"
	launch_t = 0.0
	launched += 1
	# Stars: one for flying, one for no burps, one for being speedy.
	last_stars = 1 + (1 if rocket_burps == 0 else 0) + (1 if time_left >= start_time * 0.4 else 0)
	stars += last_stars
	streak = streak + 1 if rocket_burps == 0 else 0
	if streak >= 2:
		bonus_next = minf(5.0 * streak, 20.0)
	print("Rocket %d launched! (%d total, %.0f s to spare, %d stars, streak %d)" % [rocket_n, launched, time_left, last_stars, streak])
	_show_center("3", 0.9)
	sound("count", 0.0, 1.0)


func _launch_beats(prev: float, now: float) -> void:
	for k in [1, 2]:
		if prev < k and now >= k:
			_show_center(str(3 - k), 0.9)
			sound("count", 0.0, 1.0)
	if prev < 2.6 and now >= 2.6:
		sound("rumble", 2.0, 1.0)
	if prev < RocketScript.LIFTOFF and now >= RocketScript.LIFTOFF:
		var line := "LIFT OFF!\nRocket #%d (%s) is off to %s!" % [rocket_n, rocket_name, P.PLANETS[P.planet(rocket_n)]]
		if streak >= 2:
			line += "\nPERFECT STREAK x%d!  +%d s on the next rocket" % [streak, int(bonus_next)]
		_show_center(line, 3.0)
		sound("count", 2.0, 2.0)
		sound("whoosh", 0.0, 1.0)
		sound("allset", -2.0, 1.2)
		popup(PAD_POS + Vector3(0, 4.0, 2.0), "WHEEE!", Color(1.0, 0.85, 0.3))
		space.add_log(rocket_name, P.planet(rocket_n), last_stars, rocket_n)
		net.event("logged", [rocket_name, P.planet(rocket_n), last_stars, rocket_n])
	if prev < SpaceScript.ARRIVE_AT and now >= SpaceScript.ARRIVE_AT:
		var star_names: Array[String] = ["", "1 STAR", "2 STARS", "3 STARS!"]
		var star_txt: String = star_names[clampi(last_stars, 0, 3)]
		_show_center("TOUCHDOWN ON %s!\n%s   (total %d)" % [P.PLANETS[P.planet(rocket_n)], star_txt, stars], 1.6)
		sound("arrive", -2.0, 1.0)
		for k in last_stars:
			get_tree().create_timer(0.15 * k).timeout.connect(sound.bind("star", -4.0, 1.0 + 0.15 * k))
		star_burst(Vector3(0, 2.6, -2.5), 8 + 6 * last_stars)
		net.event("stars", [Vector3(0, 2.6, -2.5), 8 + 6 * last_stars])


## Host: crew jobs (fuel can, bolts, paint pots, the cat).
func _update_jobs(delta: float) -> void:
	var m := module("canister")
	if not m.is_empty() and not m.done:
		var carrier: int = m.carrier
		if carrier < 0:
			var at: Vector3 = m.pos
			for p in players:
				if p.index == 0 or not p.active or is_carrying(p.index):
					continue
				var pp: Vector3 = p.global_position
				if Vector2(pp.x - at.x, pp.z - at.z).length() < 1.4:
					m.carrier = p.index
					sound("pop", -2.0, 1.2)
					popup(at + Vector3.UP * 1.6, "GOT IT! To the rocket!", Color(1.0, 0.8, 0.4))
					print("Canister picked up by P%d" % (p.index + 1))
					break
		else:
			var p = players[carrier]
			var pp: Vector3 = p.global_position
			m.pos = Vector3(pp.x, 0.0, pp.z)
			if not p.active:
				m.carrier = -1
			elif Vector2(pp.x - HATCH_POS.x, pp.z - HATCH_POS.z).length() < 1.8:
				m.carrier = -1
				burst(HATCH_POS + Vector3.UP * 0.8, Color(1.0, 0.6, 0.2), 20, 0.1)
				popup(HATCH_POS + Vector3.UP * 2.0, "FUELLED UP!", Color(1.0, 0.8, 0.3))
				_stat(carrier, "deliver", 1.0)
				_solve(m)
	_update_bolts()
	_update_paint()
	_update_cat(delta)


func _update_bolts() -> void:
	var m := module("bolts")
	if m.is_empty() or m.done:
		return
	var spots: Array = m.spots
	var got: Array = m.got
	for i in 3:
		if bool(got[i]):
			continue
		var at: Vector3 = P.BOLT_SPOTS[int(spots[i])]
		for p in players:
			if p.index == 0 or not p.active:
				continue
			var pp: Vector3 = p.global_position
			if Vector2(pp.x - at.x, pp.z - at.z).length() < 1.1:
				got[i] = true
				var n := got.count(true)
				sound("ting", -2.0, 1.0 + 0.15 * n)
				popup(at + Vector3.UP * 1.4, "BOLT %d of 3!" % n, Color(1.0, 0.85, 0.3))
				burst(at + Vector3.UP * 0.4, Color(1.0, 0.85, 0.3), 12, 0.06)
				_stat(p.index, "bolts", 1.0)
				if n >= 3:
					_solve(m)
				break


func _update_paint() -> void:
	var m := module("paint")
	if m.is_empty() or m.done:
		return
	var carrier := int(m.carrier)
	if carrier >= 0:
		var p = players[carrier]
		var pp: Vector3 = p.global_position
		if not p.active:
			m.carrier = -1
			return
		# Walk into a different pot to swap colours.
		for i in 4:
			var spot: Vector3 = P.PAINT_SPOTS[i]
			if i != int(m.carry) and Vector2(pp.x - spot.x, pp.z - spot.z).length() < 0.65:
				m.carry = i
				sound("splash", -6.0, 1.3)
				popup(spot + Vector3.UP * 1.4, "%s PAINT" % P.COLOR_NAMES[i], P.COLORS[i])
				return
		if Vector2(pp.x - HATCH_POS.x, pp.z - HATCH_POS.z).length() < 1.8:
			var c := int(m.carry)
			m.carrier = -1
			m.carry = -1
			if c == int(m.answer):
				sound("splash", 0.0, 1.0)
				burst(PAD_POS + Vector3(0, 2.5, 1.0), P.COLORS[c], 26, 0.14)
				popup(HATCH_POS + Vector3.UP * 2.0, "SPLOSH! %s STRIPES!" % P.COLOR_NAMES[c], P.COLORS[c])
				_stat(carrier, "deliver", 1.0)
				_solve(m)
			else:
				burst(HATCH_POS + Vector3.UP * 0.6, P.COLORS[c], 14, 0.1)
				_burp("Wrong paint colour! Ask the pilot again.")
		return
	for p in players:
		if p.index == 0 or not p.active or is_carrying(p.index):
			continue
		var pp: Vector3 = p.global_position
		for i in 4:
			var spot: Vector3 = P.PAINT_SPOTS[i]
			if Vector2(pp.x - spot.x, pp.z - spot.z).length() < 0.65:
				m.carrier = p.index
				m.carry = i
				sound("splash", -6.0, 1.3)
				popup(spot + Vector3.UP * 1.4, "%s PAINT" % P.COLOR_NAMES[i], P.COLORS[i])
				print("P%d picked up the %s paint" % [p.index + 1, P.COLOR_NAMES[i]])
				return


## The space cat runs from the nearest crew member, but gets tired; catch it and carry it home.
func _update_cat(delta: float) -> void:
	var m := module("cat")
	if m.is_empty() or m.done:
		return
	var carrier := int(m.carrier)
	if carrier >= 0:
		var p = players[carrier]
		var pp: Vector3 = p.global_position
		if not p.active:
			m.carrier = -1
			return
		m.pos = Vector3(pp.x, 0.0, pp.z)
		if Vector2(pp.x - P.CAT_BASKET.x, pp.z - P.CAT_BASKET.z).length() < 1.6:
			m.pos = P.CAT_BASKET
			sound("meow", 0.0, 1.2)
			popup(P.CAT_BASKET + Vector3.UP * 1.6, "PURRRR! Home safe!", Color(1.0, 0.6, 0.8))
			burst(P.CAT_BASKET + Vector3.UP * 0.6, Color(1.0, 0.6, 0.8), 18, 0.08)
			_stat(carrier, "cat", 1.0)
			_solve(m)
		return
	var pos: Vector3 = m.pos
	var near = null
	var near_d := 4.0
	for p in players:
		if p.index == 0 or not p.active or is_carrying(p.index):
			continue
		var pp: Vector3 = p.global_position
		var d := Vector2(pp.x - pos.x, pp.z - pos.z).length()
		if d < 0.95:
			m.carrier = p.index
			sound("meow", 0.0, 1.0)
			popup(pos + Vector3.UP * 1.4, "GOTCHA! To the basket!", Color(1.0, 0.7, 0.4))
			print("Space cat caught by P%d" % (p.index + 1))
			return
		if d < near_d:
			near_d = d
			near = p
	var tired: float = m.tired
	var dir := Vector3.ZERO
	var speed := 1.1
	if near != null:
		var np: Vector3 = near.global_position
		dir = Vector3(pos.x - np.x, 0.0, pos.z - np.z).normalized()
		speed = 3.3 * (1.0 - 0.6 * tired)
		tired = minf(1.0, tired + delta * 0.09)
	else:
		tired = maxf(0.0, tired - delta * 0.04)
		if Vector2(pos.x - cat_goal.x, pos.z - cat_goal.z).length() < 0.5 or cat_goal == Vector3.ZERO:
			cat_goal = P.BOLT_SPOTS[randi() % P.BOLT_SPOTS.size()]
		dir = Vector3(cat_goal.x - pos.x, 0.0, cat_goal.z - pos.z).normalized()
	m.tired = tired
	# Slide along walls when cornered: try a few headings and keep the one that gets furthest.
	var best := clamp_walk(pos + dir * speed * delta)
	var best_gain := (best - pos).length()
	for turn in [0.8, -0.8, 1.6, -1.6]:
		var d2 := Basis(Vector3.UP, turn) * dir
		var cand := clamp_walk(pos + d2 * speed * delta)
		var gain := (cand - pos).length()
		if gain > best_gain * 1.6:
			best = cand
			best_gain = gain
	m.pos = best
	cat_meow_t -= delta
	if cat_meow_t <= 0.0:
		cat_meow_t = randf_range(2.5, 5.0)
		sound("meow", -6.0, randf_range(0.9, 1.3))


## Gentle chaos in the middle of a countdown: a cat sneaks in, a pipe springs a leak, bolts fall off,
## or a lucky golden comet flies over (free time!).
func _maybe_event() -> void:
	if events_left <= 0 or phase != "work" or time_left > event_at:
		return
	events_left -= 1
	event_at = time_left * randf_range(0.4, 0.6)
	var r := randf()
	if r < 0.4 and module("cat").is_empty():
		modules.append(P.make("cat", rocket_n))
		time_left += 25.0
		cat_goal = Vector3.ZERO
		sound("uhoh", 0.0)
		sound("meow", 0.0, 1.1)
		_show_center("UH OH! A SPACE CAT SNEAKED IN!\nCrew: catch it (walk into it) and pop it in its basket!  +25 s", 3.5)
		print("Event: space cat")
	elif r < 0.65:
		time_left += 15.0
		sound("comet", 0.0)
		spawn_comet()
		net.event("comet", [])
		_show_center("WOW! A GOLDEN COMET!\nMake a wish!  +15 s", 2.5)
		print("Event: comet")
	elif module("pipe").is_empty():
		modules.append(P.make("pipe", rocket_n))
		time_left += 20.0
		sound("uhoh", 0.0)
		_show_center("UH OH! A PIPE SPRANG A LEAK!\nCrew: follow the sparks and HOLD A!  +20 s", 3.0)
		print("Event: leak")
	elif module("bolts").is_empty():
		modules.append(P.make("bolts", rocket_n))
		time_left += 20.0
		sound("uhoh", 0.0)
		_show_center("BOINK! THREE BOLTS FELL OFF!\nCrew: find the shiny bolts!  +20 s", 3.0)
		print("Event: bolts")
	else:
		time_left += 15.0
		sound("comet", 0.0)
		spawn_comet()
		net.event("comet", [])
		_show_center("WOW! A GOLDEN COMET!\nMake a wish!  +15 s", 2.5)
		print("Event: comet")


## Host: who's standing in front of a board that still needs reading (for the BEST READER award).
func _track_readers(delta: float) -> void:
	for m in modules:
		if m.done or not manual.boards.has(m.type):
			continue
		var root: Node3D = manual.boards[m.type].root
		var n := root.global_basis.z
		for p in players:
			if p.index == 0 or not p.active:
				continue
			var to: Vector3 = p.global_position - root.global_position
			to.y = 0.0
			var ahead := to.dot(n)
			if ahead > 0.5 and ahead < 6.5 and absf(to.dot(root.global_basis.x)) < 2.5:
				_stat(p.index, "read", delta)


func _host_update(delta: float) -> void:
	msg_t -= delta
	lever_hint_t -= delta
	match phase:
		"wait":
			if net.mode != "host" or net.connected:
				_start_rocket(1)
		"intro":
			phase_t -= delta
			if phase_t <= 0.0:
				phase = "work"
		"work", "ready":
			if net.mode == "host" and not net.connected:
				return  # hold the countdown while the TV crew is away
			time_left -= delta
			_update_jobs(delta)
			_track_readers(delta)
			_maybe_event()
			var sec := ceili(time_left)
			if sec <= 10 and sec != last_tick and sec > 0:
				last_tick = sec
				sound("tick", -4.0 if sec > 5 else 0.0, 1.0 if sec > 5 else 1.3)
			if time_left <= 0.0:
				_on_game_over()
		"launch":
			var prev := launch_t
			launch_t += delta
			_launch_beats(prev, launch_t)
			if launch_t >= LAUNCH_TIME:
				_start_rocket(rocket_n + 1)
		"over":
			game_over_time += delta
			var trig: bool = players[0].vr_trigger_held()
			if not trig:
				over_armed = true  # a trigger still held from the desk doesn't count
			if game_over_time > 1.5 and (_restart_pressed() or (trig and over_armed)):
				get_tree().reload_current_scene()


func _awards() -> Array[String]:
	var out: Array[String] = []
	var names := {"read": "SUPER READER", "deliver": "DELIVERY CHAMP", "fix": "FIX-IT HERO", "bolts": "BOLT HUNTER", "cat": "CAT CUDDLER"}
	var minimum := {"read": 3.0, "deliver": 1.0, "fix": 0.3, "bolts": 1.0, "cat": 1.0}
	for key in names:
		var who := -1
		var top := 0.0
		for idx in crew_stats:
			var s: Dictionary = crew_stats[idx]
			if float(s[key]) > top:
				top = float(s[key])
				who = int(idx)
		if who > 0 and top >= float(minimum[key]):
			out.append("P%d %s" % [who + 1, names[key]])
	if launched > 0:
		out.append("PILOT " + ("STEADY HANDS" if mistakes <= launched else "LEVER LEGEND"))
	return out


func _on_game_over() -> void:
	phase = "over"
	game_over = true
	game_over_time = 0.0
	over_armed = false
	time_left = 0.0
	sound("nap", 0.0)
	print("Game over: %d rockets launched, %d burps, %d stars" % [launched, mistakes, stars])
	var best_line := "Best: %d rockets" % best
	if launched > best:
		best_line = "NEW BEST!  (before: %d)" % best
		best = launched
		_save_best(launched)
	var planet_line := "Planets visited: none yet" if launched == 0 else "Furthest planet: %s" % P.PLANETS[P.planet(launched)]
	var awards := _awards()
	var award_line := ("AWARDS: " + "  ·  ".join(awards)) if not awards.is_empty() else ""
	print("Awards: %s" % ", ".join(awards))
	_show_center("The rocket got sleepy and took a nap… Zzz\nRockets launched: %d   ·   Stars: %d   ·   Burps: %d\n%s   ·   %s\n%s\n\nPress A / Enter (VR: trigger) to play again" \
		% [launched, stars, mistakes, planet_line, best_line, award_line], 0.0)


func _load_best() -> int:
	var cfg := ConfigFile.new()
	cfg.load("user://rocket_workshop_best.cfg")
	return int(cfg.get_value("best", "rockets", 0))


func _save_best(rockets: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("best", "rockets", rockets)
	cfg.save("user://rocket_workshop_best.cfg")


func _restart_pressed() -> bool:
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER):
		return true
	for id in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(id, JOY_BUTTON_A):
			return true
	return false


func _clock() -> String:
	var s := maxi(0, ceili(time_left))
	return "%d:%02d" % [s / 60, s % 60]


## Text on the pilot's desk screen (world-space, only the pilot sees it). The status line takes
## turns between the useful messages.
func screen_text() -> String:
	var status := ""
	var tips: Array[String] = []
	match phase:
		"wait":
			status = "Waiting for the TV crew…"
		"intro":
			status = "Off to %s! Tell your crew its name." % P.PLANETS[P.planet(rocket_n)]
		"work":
			tips.append("Ask your crew what the blueprints say!")
			var paint := module("paint")
			if not paint.is_empty() and not paint.done:
				tips.append("PAINT JOB: tell the crew to bring %s paint!" % P.COLOR_NAMES[int(paint.answer)])
			var al := module("alien")
			if not al.is_empty() and not al.done:
				tips.append("Describe the alien on your LEFT to the crew!")
			var cat := module("cat")
			if not cat.is_empty() and not cat.done:
				tips.append("A space cat got in! Cheer the crew on!")
			if rocket_n <= 2 and launched == 0:
				tips.append("Touch buttons with a finger. Squeeze the trigger to grab.")
		"ready":
			status = "PULL THE LEVER, CRONK!"  # David's wording
		"launch":
			status = "LIFT OFF! Off to %s!" % P.PLANETS[P.planet(rocket_n)] if launch_t < SpaceScript.ARRIVE_AT else "WE LANDED ON %s!" % P.PLANETS[P.planet(rocket_n)]
		"over":
			status = "Zzz… pull the trigger to play again"
	if not tips.is_empty():
		status = tips[int(status_t / 3.5) % tips.size()]
	if msg_t > 0.0 and (phase == "work" or phase == "ready"):
		status = msg
	if rocket_n == 0:
		return "ROCKET WORKSHOP\n" + status
	return "ROCKET #%d  is called  %s\nTIME %s   STARS %d\n%s" % [rocket_n, rocket_name, _clock(), stars, status]


## The TV crew's launch camera (space.gd), or {} for their own view.
func launch_cam() -> Dictionary:
	return space.launch_cam(rocket_n, phase, launch_t)


## A short "what do I do now?" line under each crew member's view.
func crew_hint(p) -> String:
	if net.mode == "client" and not synced:
		return ""
	match phase:
		"wait":
			return "Waiting for the pilot…"
		"intro":
			if rocket_n == 1:
				return "Find a board with a BOUNCING ARROW and read it out loud!"
			return "New rocket! Ask the pilot: what is it called?"
		"launch":
			return "WHEEE! Watch it fly!"
		"over":
			return "Press A to play again!"
	var idx: int = p.index
	var can := module("canister")
	if not can.is_empty() and not can.done and int(can.carrier) == idx:
		return "Carry the FUEL to the glowing ring by the rocket!"
	var paint := module("paint")
	if not paint.is_empty() and not paint.done and int(paint.carrier) == idx:
		return "Is it the right colour? Take the %s paint to the glowing ring by the rocket!" % P.COLOR_NAMES[int(paint.carry)]
	var cat := module("cat")
	if not cat.is_empty() and not cat.done and int(cat.carrier) == idx:
		return "Pop the cat in its pink basket by the big door!"
	if p.fixing:
		return "Keep holding A… fixing!"
	var pos: Vector3 = p.global_position
	for m in modules:
		if m.done or not manual.boards.has(m.type):
			continue
		var root: Node3D = manual.boards[m.type].root
		var to: Vector3 = pos - root.global_position
		to.y = 0.0
		var ahead := to.dot(root.global_basis.z)
		if ahead > 0.3 and ahead < 6.5 and absf(to.dot(root.global_basis.x)) < 2.5:
			if m.type == "alien":
				return "Ask the pilot what their alien looks like, then find it here!"
			if m.has("rows") and (m.rows as Array).size() > 1:
				return "Read this board out loud! First ask: what is the rocket called?"
			return "Read this board out loud to the pilot!"
	if not cat.is_empty() and not cat.done:
		return "A SPACE CAT! Walk into it to catch it!"
	if not paint.is_empty() and not paint.done:
		return "PAINT JOB: ask the pilot which colour, then fetch that pot from the yard!"
	var bolts := module("bolts")
	if not bolts.is_empty() and not bolts.done:
		return "Find the shiny LOOSE BOLTS: follow the golden beams!"
	if not can.is_empty() and not can.done and int(can.carrier) < 0:
		return "Fetch the FUEL can: follow the orange beam!"
	var pipe := module("pipe")
	if not pipe.is_empty() and not pipe.done:
		return "Fix the LEAKY PIPE: stand by the sparks and HOLD A!"
	if phase == "ready":
		return "Shout: PULL THE LEVER, CRONK!"
	return "Walk to a board with a BOUNCING ARROW and read it out loud!"


# --- Main loop ---------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play or not is_inside_tree():
		return
	if music == null:
		music = MusicScript.new()
		add_child(music)
		music.volume_db = -20.0
	if music.has_method("play_track"):
		music.play_track([2, 0, 1][(maxi(rocket_n, 1) - 1) / 2 % 3])
	_ensure_join_listener()
	status_t += delta
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if views_root != null and is_instance_valid(views_root) and views_root.size != last_view_area:
		_layout_views()
	if net.mode == "client":
		if phase == "launch":
			var prev := launch_t
			launch_t += delta
			if prev < SpaceScript.ARRIVE_AT and launch_t >= SpaceScript.ARRIVE_AT:
				local_sound("arrive", -4.0)
		_check_join(delta)
		_update_lost_pads(delta)
		if game_over:
			game_over_time += delta
			if game_over_time > 1.5 and _restart_pressed():
				game_over_time = 0.0
				net.send_action("restart", [])
	else:
		_update_lost_pads(delta)
		_host_update(delta)
		# The pilot's pointer needs a free mouse (the pause menu captures it on resume).
		if not players[0].vr and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	rocket.update_visual(rocket_n, phase, launch_t, delta)
	space.update_space(rocket_n, phase, launch_t, delta)
	manual.update_boards(modules, rocket_n)
	jobs.update_visual(modules, delta)
	panel.update_panel(delta)
	_animate_world(delta)
	_update_hud()
	_update_vr_center()


## Ambient life: the planet mobile turns, clouds drift, gantry lights blink faster when ready.
func _animate_world(delta: float) -> void:
	var mob := get_node_or_null("Mobile") as Node3D
	if mob != null:
		mob.rotation.y += delta * 0.35
	var clouds := get_node_or_null("Clouds") as Node3D
	if clouds != null:
		clouds.position.x = fmod(clouds.position.x + delta * 0.6 + 40.0, 80.0) - 40.0
	if has_meta("gantry_mat"):
		var gm: StandardMaterial3D = get_meta("gantry_mat")
		var rate := 6.0 if phase == "ready" else 2.0
		gm.emission_energy_multiplier = 3.0 if fmod(status_t * rate, 2.0) < 1.0 else 0.3


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_F11:
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


# --- Players and views -------------------------------------------------------

func _build_players(mode: String) -> void:
	var op := OperatorScript.new()
	op.main = self
	op.ghost = mode == "client"
	add_child(op)
	players.append(op)
	var top := MAX_PLAYERS - 1 if mode != "local" else MAX_LOCAL_VIEWS - 1
	for i in range(1, top + 1):
		var p := PlayerScript.new()
		p.index = i
		p.color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
		p.main = self
		p.remote = mode == "host"
		p.key_set = PlayerScript.NO_KEYS
		if mode == "local":
			if i == 1:
				p.key_set = 0
		elif i == 1:
			p.key_set = 1
		elif i == 2:
			p.key_set = 0
			p.mouse_look = true
		p.position = CREW_SPOTS[(i - 1) % CREW_SPOTS.size()]
		add_child(p)
		players.append(p)
		p.set_active(i == 1)


func is_local(p) -> bool:
	return not p.vr and not p.remote and not p.ghost


func _apply_vr_performance() -> void:
	for n in get_children():
		if n is WorldEnvironment:
			var e: Environment = n.environment
			e.ssao_enabled = false
			e.fog_enabled = false
			e.glow_intensity = 0.5
		elif n is DirectionalLight3D:
			n.shadow_enabled = false


func _build_views(mode: String) -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized() and mode != "client":
		xr_interface = xr
		print("VR headset found: player 1 is the pilot")
		Engine.physics_ticks_per_second = 90
		get_viewport().use_xr = true
		get_viewport().msaa_3d = Viewport.MSAA_2X
		_apply_vr_performance()
		var origin := XROrigin3D.new()
		add_child(origin)
		origin.global_position = Vector3(0, 0, 0.12)
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
		if mode == "local":
			_build_flat_window(players[1])
	else:
		print("No VR headset: %s" % ("TV crew view" if mode == "client" else "split screen, player 1 works the desk with a pointer"))
	_ensure_views_root()
	for p in players:
		if (is_local(p) and p.active) or (p.index == 0 and not p.vr and not p.ghost):
			_ensure_view(p)
	_layout_views()


func _ensure_views_root() -> void:
	if views_root != null and is_instance_valid(views_root):
		return
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	views_root = Control.new()
	views_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(views_root)
	views_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## One split-screen view (SubViewport + camera + hint line) per local player, made when they first play.
func _ensure_view(p) -> void:
	if p.has_meta("view") or p.vr or p.ghost or p.remote or p.camera != null:
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
	vp.add_child(cam)
	cam.current = true
	p.attach_camera(cam)
	if p.index > 0:
		var hud_layer := CanvasLayer.new()
		vp.add_child(hud_layer)
		var l := _make_label(26)
		l.add_theme_color_override("font_color", p.color.lightened(0.45))
		hud_layer.add_child(l)
		l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		l.offset_top = -120
		l.offset_bottom = -70
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
		if p.index > 0 and p.hud_label != null:
			var ui := clampf(minf(cell.x / 940.0, cell.y / 900.0), 0.55, 1.0)
			p.hud_label.add_theme_font_size_override("font_size", int(28.0 * ui))
	if list_label != null:
		list_label.add_theme_font_size_override("font_size", 24 if n <= 2 else 18)
	if not players.is_empty() and not players[0].vr:
		for node in get_children():
			if node is DirectionalLight3D:
				node.shadow_enabled = n <= 2


## Low-res copy of the VR view, recorded by gdev (group gdev_capture) so others can watch.
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
	cam.cull_mask = xr_cam.cull_mask
	vp.add_child(cam)
	cam.current = true
	var follow := RemoteTransform3D.new()
	xr_cam.add_child(follow)
	follow.remote_path = follow.get_path_to(cam)


## VR without a TV machine: the crew member gets a window on this device.
func _build_flat_window(p) -> void:
	var win := Window.new()
	win.title = "Rocket Workshop - Crew"
	win.size = Vector2i(1920, 1080)
	win.world_3d = get_world_3d()
	win.msaa_3d = Viewport.MSAA_2X
	win.content_scale_size = Vector2i(1920, 1080)
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.scaling_3d_scale = 0.6
	add_child(win)
	var cam := Camera3D.new()
	win.add_child(cam)
	cam.current = true
	p.attach_camera(cam)


# --- Controllers and drop-in join ----------------------------------------------------

func _assign_joypads() -> void:
	var pads := Input.get_connected_joypads()
	joy_owner.clear()
	var a: int = pads[0] if pads.size() > 0 else -1
	var b: int = pads[1] if pads.size() > 1 else -1
	if net.mode == "host":
		players[0].joy = a if not players[0].vr else -1
		return
	players[1].joy = a
	if net.mode == "local" and not players[0].vr:
		players[0].joy = b
	for p in players:
		if p.index > 0 and p.joy >= 0 and is_local(p):
			joy_owner[p.joy] = p.index
	if players[0].joy >= 0 and net.mode == "local":
		joy_owner[players[0].joy] = 0


func _on_joy_changed(device: int, connected: bool) -> void:
	if not ready_to_play or net.mode == "host":
		return
	if connected:
		print("Joypad %d connected" % device)
		if joy_owner.has(device):
			return
		var pick = null
		for p in players:
			if p.index > 0 and is_local(p) and p.joy < 0 and int(p.get_meta("last_joy", -2)) == device:
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
		if idx >= 2 and p.active and p.key_set == PlayerScript.NO_KEYS:
			p.pad_lost_t = 0.0
			_show_center("P%d: controller disconnected" % (idx + 1), 2.0, false)


## Called by the join listener for every input event: A on a controller nobody owns joins the crew.
func handle_join_input(event: InputEvent) -> bool:
	var pad := event as InputEventJoypadButton
	if pad == null or not pad.pressed or pad.button_index != JOY_BUTTON_A:
		return false
	if not ready_to_play or net.mode == "host" or get_tree().paused or game_over:
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
		_show_center("All %d crew spots are taken!" % (players.size() - 1), 1.5, false)
		return null
	var p = players[idx]
	if device >= 0:
		p.joy = device
		joy_owner[device] = idx
		print("Joypad %d joins as P%d" % [device, idx + 1])
	_request_join(p)
	return p


## Local: walk in now. TV machine: ask the host (retried by _check_join until it agrees).
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
	p.position = CREW_SPOTS[(p.index - 1) % CREW_SPOTS.size()]
	p.net_started = false
	if phase == "work" or phase == "ready" or phase == "intro":
		time_left += 10.0  # a new crew member gets a little welcome time
	_show_center("PLAYER %d JOINED THE CREW!" % (p.index + 1), 1.5)
	sound("pop", -2.0, 1.4)
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
	Engine.set_meta("rocket_workshop_party", {"mode": net.mode, "party": party})


func _restore_party() -> void:
	if net.mode == "host" or not Engine.has_meta("rocket_workshop_party"):
		return
	var saved: Dictionary = Engine.get_meta("rocket_workshop_party")
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


## Test hook: join a crew member without a controller (index -1: the next free seat).
func debug_join(index: int = -1):
	if not ready_to_play or net.mode == "host":
		return null
	if index < 0:
		return _join_slot(-1)
	var p = players[index]
	_request_join(p)
	return p


## TV machine: ask the host to activate waiting crew; P3 (the keyboard + mouse seat) also joins by
## pressing its ACTION key or clicking.
var join_t := 0.0
func _check_join(delta: float) -> void:
	join_t -= delta
	if game_over:
		return
	if players.size() > 2 and not players[2].active and not players[2].has_meta("want_join") and players[2].action_held():
		_request_join(players[2])
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


func _update_lost_pads(delta: float) -> void:
	for p in players:
		if p.index > 0 and p.pad_lost_t >= 0.0 and is_local(p):
			p.pad_lost_t += delta
			if p.pad_lost_t > PAD_LEAVE_TIME:
				_leave(p)


func on_player_activity_changed(p) -> void:
	if p.active and is_local(p):
		_ensure_view(p)
	if p.active:
		p.remove_meta("want_join")
	_layout_views()
	print("Player %d is now %s on this screen" % [p.index + 1, "playing" if p.active else "waiting"])


# --- Networked co-op (see docs/GAME_DEV_GUIDE.md) ----------------------------

func on_client_joined() -> void:
	_show_center("THE TV CREW JOINED!", 1.5)


func on_client_left() -> void:
	for i in range(2, players.size()):
		if players[i].active:
			players[i].set_active(false)
	_show_center("The TV crew left - waiting for them to come back…", 0.0)


func on_p2_action(action: String, args: Array, index: int = 1) -> void:
	if action == "join" and args.size() > 0:
		index = int(args[0])
	if index <= 0 or index >= players.size():
		return
	var p = players[index]
	match action:
		"fix":
			if p.active and args.size() > 0:
				fix_pipe(index, float(args[0]))
		"join":
			if not p.active:
				_activate(p)
				print("Net: player %d joined the game" % (index + 1))
		"leave":
			if p.active:
				p.set_active(false)
				_show_center("PLAYER %d LEFT" % (index + 1), 1.5)
		"restart":
			if game_over:
				get_tree().reload_current_scene()
		"pause":
			var paused: bool = args[0]
			_set_pause_banner(paused, "A TV player opened the menu")
			get_tree().paused = paused


func _set_pause_banner(paused: bool, who: String) -> void:
	_show_center("PAUSED\n" + who if paused else "", 0.0, false)
	if vr_center != null and paused:
		VrText.snap(vr_center)
	_update_vr_center()


func toggle_vr_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_set_pause_banner(paused, "Wrist RESUME: carry on\nHOLD the trigger: back to the arcade")
	net.event("remote_pause", [paused])
	if panel != null:
		panel.block_held_grips()  # a trigger held through the pause menu mustn't grab anything


func make_snapshot() -> Array:
	var ps := []
	for p in players:
		if p.index == 0:
			ps.append([p.head_transform(), p.hand_r_transform(), p.hand_l_transform()])
		else:
			ps.append(p.active)  # the TV machine walks its own crew; it only needs who's playing
	# The rocket's name is left out on purpose: only the pilot can read it, the crew must ask.
	# Modules are deflated: their repeated dictionary keys squash well, keeping snapshots under the MTU.
	var raw := var_to_bytes(modules)
	return [phase, rocket_n, launched, time_left, raw.compress(FileAccess.COMPRESSION_DEFLATE), raw.size(), ps, launch_t,
		mistakes, panel.top, stars, streak, last_stars]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 13:
		return
	synced = true
	phase = s[0]
	rocket_n = s[1]
	launched = s[2]
	time_left = s[3]
	var packed: PackedByteArray = s[4]
	var got = bytes_to_var(packed.decompress(int(s[5]), FileAccess.COMPRESSION_DEFLATE))
	if got is Array:
		modules = got
	var ps: Array = s[6]
	for i in mini(players.size(), ps.size()):
		if i == 0:
			players[0].apply_net_state(ps[0])
		else:
			players[i].apply_net_state(bool(ps[i]))
	var lt: float = s[7]
	if phase != "launch" or absf(lt - launch_t) > 0.3:
		launch_t = lt
	mistakes = s[8]
	var top: float = s[9]
	if absf(top - panel.top) > 0.005:
		panel.set_top(top)
	stars = s[10]
	streak = s[11]
	last_stars = s[12]
	if game_over != (phase == "over"):
		game_over = phase == "over"
		game_over_time = 0.0


func apply_event(kind: String, args: Array) -> void:
	if not ready_to_play:
		return
	match kind:
		"sound":
			local_sound(args[0], args[1], args[2])
		"burst":
			puff(args[0], args[1], args[2], args[3])
		"popup":
			popup(args[0], args[1], args[2], false)
		"center":
			_show_center(args[0], args[1], false)
		"burp":
			rocket.burp()
		"comet":
			spawn_comet()
		"stars":
			star_burst(args[0], args[1])
		"logged":
			space.add_log(args[0], args[1], args[2], args[3])
		"remote_pause":
			get_tree().paused = args[0]
			_set_pause_banner(args[0], "The pilot paused the game")


# --- HUD ---------------------------------------------------------------------

func _make_label(font: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font)
	l.add_theme_constant_override("outline_size", maxi(6, font / 5))
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.15, 0.95))
	l.add_theme_color_override("font_color", Color(1.0, 0.96, 0.86))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	info_label = _make_label(32)
	layer.add_child(info_label)
	info_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	info_label.offset_top = 16
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list_label = _make_label(24)
	layer.add_child(list_label)
	list_label.position = Vector2(24, 70)
	center_label = _make_label(54)
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
	help_label.text = "Crew: left stick / WASD / arrows walk · right stick / mouse / Q E look · hold A / X / Space / Enter to fix pipes · walk into cans, pots, bolts and cats · more crew: press A on another controller\n" \
		+ "Pilot (split screen): mouse or controller pointer · click buttons · hold and drag plugs, the dial, the crank and the launch lever"


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


func _update_hud() -> void:
	if help_label.modulate.a > 0.0 and launched >= 2:
		help_label.modulate.a = maxf(0.0, help_label.modulate.a - get_process_delta_time() * 0.5)
	if net.mode == "client" and not synced:
		info_label.text = "Syncing with the pilot…"
		return
	if rocket_n == 0:
		info_label.text = "ROCKET WORKSHOP"
		list_label.text = ""
		return
	var streak_txt := "   STREAK %d" % streak if streak >= 2 else ""
	info_label.text = "ROCKET #%d  to %s      TIME %s      LAUNCHED %d      STARS %d%s" % [rocket_n, P.PLANETS[P.planet(rocket_n)],
		_clock(), launched, stars, streak_txt]
	if phase == "launch":
		list_label.text = ""
		return
	var lines: Array[String] = ["THIS ROCKET NEEDS:"]
	for m in modules:
		var t: String = m.type
		var line: String = P.TITLES[t]
		if m.done:
			line = "DONE  " + line
		elif t == "canister":
			line = "TODO  " + line + "  (carry it to the rocket)"
		elif t == "pipe":
			line = "TODO  " + line + "  (hold A next to it)"
		elif t == "bolts":
			line = "TODO  " + line + "  (%d of 3 found)" % (m.got as Array).count(true)
		elif t == "paint":
			line = "TODO  " + line + "  (ask the pilot which colour!)"
		elif t == "cat":
			line = "TODO  " + line + "  (catch it, carry it to its basket)"
		else:
			line = "TODO  " + line + "  (blueprint on the %s)" % BOARD_PLACES.get(t, "wall")
		lines.append(line)
	if phase == "ready":
		lines.append("\nTell the pilot: PULL THE LAUNCH LEVER!")
	list_label.text = "\n".join(lines)


## VR can't show 2D overlays: mirror the centre banner on a world-space panel that lazily follows
## the pilot's view (core/vr_text.gd: never stuck to the headset, never billboarded).
func _update_vr_center() -> void:
	if players.is_empty() or not players[0].vr:
		return
	if vr_center == null:
		vr_center = Label3D.new()
		vr_center.font_size = 46
		vr_center.outline_size = 26
		vr_center.no_depth_test = true
		vr_center.render_priority = 10
		vr_center.outline_render_priority = 9
		vr_center.width = 1000.0
		vr_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vr_center.pixel_size = 0.0022
		vr_center.modulate = Color(1.0, 0.95, 0.85)
		add_child(vr_center)
		set_layers(vr_center, PANEL_LAYER)
	vr_center.text = center_label.text
	vr_center.modulate.a = center_label.modulate.a
	vr_center.outline_modulate = Color(0, 0, 0, center_label.modulate.a)
	VrText.follow(vr_center, players[0].xr_camera, self, 0.3, 1.8)
