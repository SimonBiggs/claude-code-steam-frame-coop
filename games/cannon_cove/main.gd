extends Node3D
const VrText := preload("res://core/vr_text.gd")
## Cannon Cove: our pirate ship against waves of pirate ships, boarders and a sea monster.
## The VR gunner (player 1) swings and fires the cannons; the TV deckhands (players 2 to 7, drop-in:
## press A on a spare controller to join) keep the cannons loaded, patch leaks and shoot boarders. Gold for every ship sunk; the game ends when
## the hold fills with water and the ship goes down.

const World := preload("res://games/cannon_cove/world.gd")
const PlayerScript := preload("res://games/cannon_cove/player.gd")
const CannonScript := preload("res://games/cannon_cove/cannon.gd")
const BallScript := preload("res://games/cannon_cove/ball.gd")
const ShipScript := preload("res://games/cannon_cove/enemy_ship.gd")
const TentacleScript := preload("res://games/cannon_cove/tentacle.gd")
const BoarderScript := preload("res://games/cannon_cove/boarder.gd")
const LeakScript := preload("res://games/cannon_cove/leak.gd")
const HudScript := preload("res://games/cannon_cove/hud.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")

const GRAVITY := 9.8
const MAX_LEAKS := 7
const LEAK_RATE := 1.25  # % of the hold per second per leak (two deckhands)
const MAX_PLAYERS := 7  # the gunner (index 0) plus up to six deckhands (indices 1..6)
const PLAYER_COLORS: Array[Color] = [Color(0.25, 0.45, 0.95), Color(1.0, 0.75, 0.2), Color(1.0, 0.45, 0.8),
	Color(0.35, 0.9, 0.4), Color(0.3, 0.9, 0.95), Color(1.0, 0.5, 0.15), Color(0.7, 0.45, 1.0)]
const KEYS2_DEVICE := -2  # pseudo device id for the second keyboard set (arrows + Enter/Shift) on the TV
const CANNON_SPOTS := [
	[Vector3(-3.55, 0.85, 1.0), Vector3.LEFT],
	[Vector3(-3.55, 0.85, 6.0), Vector3.LEFT],
	[Vector3(3.55, 0.85, 1.0), Vector3.RIGHT],
	[Vector3(3.55, 0.85, 6.0), Vector3.RIGHT],
]
## Extra sounds made with core/sfx.gd's synth: [seconds, start Hz, end Hz, volume, wave, noise]
const EXTRA_SOUNDS := {
	"cannon": [0.9, 140.0, 28.0, 0.85, "saw", 0.75],
	"splash": [0.5, 900.0, 160.0, 0.35, "sine", 0.9],
	"musket": [0.2, 700.0, 120.0, 0.4, "square", 0.75],
	"dry": [0.06, 1900.0, 1500.0, 0.25, "square", 0.3],
	"coin": [0.3, 988.0, 1976.0, 0.3, "square", 0.0],
	"creak": [0.6, 150.0, 80.0, 0.4, "saw", 0.35],
	"hammer": [0.07, 520.0, 220.0, 0.4, "square", 0.6],
	"load": [0.18, 260.0, 620.0, 0.35, "tri", 0.15],
	"tentacle": [0.9, 95.0, 55.0, 0.55, "saw", 0.25],
	"rope": [0.4, 1200.0, 400.0, 0.2, "sine", 0.7],
}

var players: Array = []
var cameras: Array[Camera3D] = []
var cannons: Array = []
var xr_interface: XRInterface
var mirror_vp: SubViewport
var mirror_t := 0.0
var net: Node
var ready_to_play := false
var synced := false
var net_ids := 0
var ghost_nodes := {}
var ghost_cam: Camera3D
var vr_center: Label3D
var music  # core/music.gd (an AudioStreamPlayer)
var sfx: Node
var sea: Node3D
var sea_level := World.BASE_SEA
var gauge: Label3D
var gulls: Array[Node3D] = []
var t_world := 0.0

var wave := 0
var gold := 0
var water := 0.0
var ships_to_spawn := 0
var tentacles_to_spawn := 0
var spawn_timer := 0.0
var break_timer := 5.0
var in_break := true
var game_over := false
var game_over_time := 0.0
var hammer_t := 0.0

var info_label: Label
var center_label: Label
var help_label: Label
var center_tween: Tween
var join_t := 0.0
var view_grid: GridContainer
var view_count := 0
var say_t := 0.0


func _ready() -> void:
	randomize()
	var built: Dictionary = World.build(self)
	sea = built.sea
	_build_cannons()
	_build_extras()
	_build_hud()
	var menu := PauseMenuScript.new()
	menu.main = self
	add_child(menu)
	net = NetScript.new()
	net.name = "Net"
	net.main = self
	add_child(net)
	Input.joy_connection_changed.connect(_on_joy_changed)
	if OS.has_environment("DUO_JOIN"):
		# TV machine: join the VR gunner's game as the deckhands, or fall back to local split screen.
		_show_center("Connecting to the VR gunner…", 0.0)
		net.join_finished.connect(func(ok: bool) -> void: _setup_game("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		var xr := XRServer.find_interface("OpenXR")
		if (xr != null and xr.is_initialized()) or OS.has_environment("DUO_HOST"):
			net.host()
		_setup_game(net.mode)


func _setup_game(mode: String) -> void:
	_build_players(mode)
	_build_views(mode)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_assign_joypads()
	update_manned()
	ready_to_play = true
	print("Cannon Cove: %s mode" % mode)
	_rejoin_party()
	if mode == "host":
		_show_center("Waiting for the deckhands on the TV to join…", 0.0)
	elif mode == "client":
		_show_center("ALL ABOARD!", 1.5)
	else:
		_show_center("CANNON COVE\nGet ready, crew!", 2.5)


func next_net_id() -> int:
	net_ids += 1
	return net_ids


# --- World -------------------------------------------------------------------

func _build_cannons() -> void:
	for i in CANNON_SPOTS.size():
		var c := CannonScript.new()
		c.main = self
		c.index = i
		c.outboard = CANNON_SPOTS[i][1]
		c.position = CANNON_SPOTS[i][0]
		c.ammo = 2
		add_child(c)
		cannons.append(c)


func _build_extras() -> void:
	# The hold's water gauge, floating by the main mast where everyone (VR too) can see it.
	gauge = Label3D.new()
	gauge.font_size = 72
	gauge.outline_size = 26
	gauge.pixel_size = 0.006
	gauge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	gauge.position = Vector3(0, 3.4, -1.0)
	add_child(gauge)
	# Seagulls circling overhead.
	var white := World.mat(Color(0.98, 0.98, 0.98))
	for i in 4:
		var g := Node3D.new()
		for s in [-1.0, 1.0]:
			var wing := World.box(g, Vector3(0.7, 0.04, 0.22), Vector3(s * 0.33, 0, 0), white)
			wing.rotation.z = s * 0.35
		World.box(g, Vector3(0.12, 0.12, 0.4), Vector3.ZERO, white)
		add_child(g)
		gulls.append(g)


func _animate_world(delta: float) -> void:
	t_world += delta
	sea_level = lerpf(World.BASE_SEA, World.SUNK_SEA, clampf(water / 100.0, 0.0, 1.0))
	sea.position.y = sea_level
	for i in gulls.size():
		var a := t_world * (0.25 + i * 0.04) + i * 1.7
		var r := 14.0 + i * 5.0
		var g := gulls[i]
		g.position = Vector3(cos(a) * r, 13.0 + i * 1.5 + sin(t_world * 0.7 + i) * 0.6, sin(a) * r - 2.0)
		g.rotation = Vector3(0.0, -a, 0.25)
		var flap := sin(t_world * 6.0 + i) * 0.4
		var w0: Node3D = g.get_child(0)
		var w1: Node3D = g.get_child(1)
		w0.rotation.z = -0.35 - flap
		w1.rotation.z = 0.35 + flap
	gauge.text = "WATER IN THE HOLD  %d%%" % int(water)
	gauge.modulate = Color(0.5, 0.85, 1.0) if water < 60.0 else Color(1.0, 0.4, 0.3)


func make_material(color: Color, glow: float) -> StandardMaterial3D:
	return World.mat(color, glow)


## Keeps deckhands and boarders out of the cannons.
func cannon_obstacles() -> Array:
	var out := []
	for c in cannons:
		var p: Vector3 = c.global_position
		out.append([Vector2(p.x, p.z), 0.75])
	return out


func update_manned() -> void:
	var s: int = players[0].station if not players.is_empty() else 1
	for c in cannons:
		c.manned = c.index == s


# --- Effects (each one shows here and is sent to the other machine) ----------

func _sfx() -> Node:
	if sfx == null:
		sfx = SfxScript.new()
		add_child(sfx)
		for k in EXTRA_SOUNDS:
			var d: Array = EXTRA_SOUNDS[k]
			sfx.streams[k] = sfx._make(d[0], d[1], d[2], d[3], d[4], d[5])
	return sfx


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	_sfx().play(sound_name, volume_db, pitch)
	if net:
		net.event("sound", [sound_name, volume_db, pitch])


func popup(pos: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.font_size = 72
	l.outline_size = 26
	l.pixel_size = 0.008
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	add_child(l)
	l.global_position = pos
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "global_position", pos + Vector3.UP * 1.8, 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.6)
	t.tween_property(l, "outline_modulate:a", 0.0, 0.8).set_delay(0.6)
	t.chain().tween_callback(l.queue_free)
	if net:
		net.event("popup", [pos, text, color])


func _particles(pos: Vector3, color: Color, amount: int, size: float, speed: float, gravity: float, life: float, spread: float = 180.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var m := SphereMesh.new()
	m.radius = size
	m.height = size * 2.0
	m.radial_segments = 6
	m.rings = 3
	var mat := World.mat(color, 1.0)
	m.material = mat
	p.mesh = m
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


func smoke(pos: Vector3, size: float) -> void:
	_particles(pos, Color(0.95, 0.92, 0.88), 14, 0.35 * size, 3.0, -1.0, 1.0, 40.0)
	_particles(pos, Color(1.0, 0.7, 0.2), 8, 0.18 * size, 6.0, 0.0, 0.25, 30.0)
	if net:
		net.event("smoke", [pos, size])


func splash(pos: Vector3, size: float) -> void:
	_particles(pos, Color(0.7, 0.9, 1.0), int(18 * size), 0.16 * size, 8.0 * size, 14.0, 0.9, 25.0)
	_sfx().play("splash", -6.0, randf_range(0.8, 1.2))
	if net:
		net.event("splash", [pos, size])


func explosion(pos: Vector3, color: Color, size: float) -> void:
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 14
	sm.rings = 7
	ball.mesh = sm
	var mat := World.mat(color, 5.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball.material_override = mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ball)
	ball.global_position = pos
	ball.scale = Vector3.ONE * 0.3
	var t := ball.create_tween().set_parallel()
	t.tween_property(ball, "scale", Vector3.ONE * 3.0 * size, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.45).set_delay(0.1)
	t.chain().tween_callback(ball.queue_free)
	_particles(pos, Color(0.55, 0.35, 0.2), int(14 * size), 0.12, 9.0 * size, 18.0, 1.0)  # splinters
	_particles(pos, Color(0.9, 0.88, 0.85), 10, 0.4 * size, 2.5, -1.5, 1.2, 60.0)  # smoke
	if net:
		net.event("boom", [pos, color, size])


func musket_fx(shooter: int, from: Vector3, to: Vector3) -> void:
	var dist := from.distance_to(to)
	if dist > 0.5:
		var tracer := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.025, 0.025, dist)
		tracer.mesh = bm
		var mat := World.mat(Color(1.0, 0.9, 0.5), 3.0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tracer.material_override = mat
		tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tracer)
		var start := from + (to - from).normalized() * 0.6
		tracer.look_at_from_position((start + to) * 0.5, to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
		var t := tracer.create_tween()
		t.tween_property(mat, "albedo_color:a", 0.0, 0.15)
		t.tween_callback(tracer.queue_free)
	_particles(from + (to - from).normalized() * 0.9 + Vector3.DOWN * 0.15, Color(0.95, 0.95, 0.9), 6, 0.1, 1.5, -0.5, 0.6, 40.0)
	_sfx().play("musket", -6.0, randf_range(0.9, 1.15))
	if net:
		net.event("musket", [shooter, from, to])


func grapple_fx(from: Vector3, to: Vector3) -> void:
	var rope := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, from.distance_to(to))
	rope.mesh = bm
	rope.material_override = World.mat(Color(0.75, 0.6, 0.35))
	rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rope)
	rope.look_at_from_position((from + to) * 0.5, to, Vector3.UP)
	get_tree().create_timer(1.6).timeout.connect(rope.queue_free)
	_sfx().play("rope", -4.0)
	if net:
		net.event("grapple", [from, to])


func add_shake(pos: Vector3, amount: float) -> void:
	for p in players:
		var falloff := clampf(1.0 - p.global_position.distance_to(pos) / 25.0, 0.2, 1.0)
		p.shake = maxf(p.shake, amount * falloff)


## A cannonball (or, on the client, its look-alike).
func spawn_ball(origin: Vector3, vel: Vector3, enemy: bool, visual_only: bool) -> void:
	var b := BallScript.new()
	b.main = self
	b.vel = vel
	b.enemy = enemy
	b.visual_only = visual_only
	b.position = origin
	add_child(b)
	if not visual_only and net:
		net.event("ball", [origin, vel, enemy])


# --- Players -----------------------------------------------------------------

func _build_players(mode: String) -> void:
	# All seven crew slots exist from the start (so snapshots and net indices line up); the gunner and
	# player 2 start active, players 3-7 drop in when someone presses A on a spare controller.
	_ensure_players(mode)


## Creates any missing player slots (also after a hot reload that raised MAX_PLAYERS).
func _ensure_players(mode: String) -> void:
	while players.size() < MAX_PLAYERS:
		var i := players.size()
		var p := PlayerScript.new()
		p.index = i
		p.color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
		p.main = self
		p.ghost = mode == "client" and i == 0
		p.remote = mode == "host" and i >= 1
		if i == 0:
			p.station = 1
			p.position = cannons[1].stand_pos()
			p.key_set = 1 if mode == "local" else 0
			p.mouse_look = mode != "local"
		else:
			p.position = spawn_pos(i)
			p.key_set = 0 if i == 1 else -1
			p.mouse_look = i == 1
		add_child(p)
		players.append(p)
		if i >= 2:
			p.set_active(false)


func spawn_pos(i: int) -> Vector3:
	var pos := Vector3(-1.2 + 2.4 * ((i - 1) % 2), 0.0, -3.2 + 1.4 * ((i - 1) / 2))
	return World.constrain(pos, 0.35, cannon_obstacles())


func _apply_vr_performance() -> void:
	for n in get_children():
		if n is WorldEnvironment:
			var e: Environment = n.environment
			e.ssao_enabled = false
			e.fog_enabled = false
			e.glow_intensity = 0.4
		elif n is DirectionalLight3D:
			n.shadow_enabled = false


func _build_vr_mirror(xr_cam: XRCamera3D) -> SubViewport:
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
	return vp


## VR: the gunner is in the headset (main viewport). Otherwise one split-screen view per local player.
func _build_views(mode: String) -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized() and mode != "client":
		xr_interface = xr
		print("VR headset found: player 1 is the gunner in VR")
		Engine.physics_ticks_per_second = 90
		get_viewport().use_xr = true
		get_viewport().msaa_3d = Viewport.MSAA_2X
		_apply_vr_performance()
		var origin := XROrigin3D.new()
		add_child(origin)
		origin.global_position = players[0].global_position
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
		print("No VR headset: split screen")
	_ensure_view_grid()
	for p in players:
		if p.active:
			_ensure_view(p)
	if mode == "client":
		_add_bubble(players[1].hud, _build_ghost_mirror())
	_layout_views()


func _ensure_view_grid() -> GridContainer:
	if view_grid != null and is_instance_valid(view_grid):
		return view_grid
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view_grid = GridContainer.new()
	view_grid.add_theme_constant_override("h_separation", 4)
	view_grid.add_theme_constant_override("v_separation", 4)
	layer.add_child(view_grid)
	view_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return view_grid


## True for a crew member who is played on this machine with a flat screen view.
func _is_local_flat(p) -> bool:
	return not (p.vr or p.remote or p.ghost)


## Lazily builds a player's split-screen view (camera, SubViewport and HUD).
func _ensure_view(p) -> void:
	if p.has_meta("view") or not _is_local_flat(p):
		return
	var container := SubViewportContainer.new()
	p.set_meta("view", container)
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ensure_view_grid().add_child(container)
	var vp := SubViewport.new()
	vp.world_3d = get_world_3d()
	vp.msaa_3d = Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	container.add_child(vp)
	var cam := Camera3D.new()
	cam.far = 900.0
	vp.add_child(cam)
	cam.current = true
	cameras.append(cam)
	p.attach_camera(cam)
	var hud_layer := CanvasLayer.new()
	vp.add_child(hud_layer)
	var hud := HudScript.new()
	hud.player = p
	hud.main = self
	hud_layer.add_child(hud)
	p.hud = hud


## Split-screen grid: 1 view full, 2 side by side, 3-4 as 2x2, 5-6 as 3x2 (7 as 4x2). Empty cells
## invite another player to join. More views render at a lower 3D resolution with fewer shadows.
func _layout_views() -> void:
	if view_grid == null or not is_instance_valid(view_grid):
		return
	var views: Array = []
	for p in players:
		if p.has_meta("view"):
			var v: Control = p.get_meta("view")
			v.visible = p.active
			if p.active:
				views.append(v)
	var n := views.size()
	var cols := 1 if n <= 1 else (2 if n <= 4 else (3 if n <= 6 else 4))
	var rows := int(ceil(float(maxi(n, 1)) / float(cols)))
	view_grid.columns = cols
	for i in views.size():
		view_grid.move_child(views[i], i)
	var scale_3d := 1.0 if n <= 2 else (0.7 if n <= 4 else 0.55)
	for v in views:
		var vp: SubViewport = v.get_child(0)
		vp.scaling_3d_scale = scale_3d
		vp.msaa_3d = Viewport.MSAA_2X if n <= 2 else Viewport.MSAA_DISABLED
	# Empty grid cells: "press A to join" cards.
	var free_cells := cols * rows - n if n >= 3 and net.mode != "host" else 0
	var cards: Array = view_grid.get_children().filter(func(c: Node) -> bool: return c.has_meta("join_card"))
	while cards.size() < free_cells:
		var card := _make_join_card()
		view_grid.add_child(card)
		cards.append(card)
	for i in cards.size():
		var card: Control = cards[i]
		card.visible = i < free_cells
		view_grid.move_child(card, -1)
	if not players[0].vr:
		for c in get_children():
			if c is DirectionalLight3D:
				c.shadow_enabled = n <= 4
				c.directional_shadow_max_distance = 40.0 if n <= 2 else 25.0
	if n != view_count:
		view_count = n
		print("Split screen: %d view(s), %d column(s), 3D scale %.2f" % [n, cols, scale_3d])


func _make_join_card() -> Control:
	var card := PanelContainer.new()
	card.set_meta("join_card", true)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.1, 0.18)
	card.add_theme_stylebox_override("panel", sb)
	var l := _make_label(30)
	l.text = "MORE CREW?\nPress A on a spare controller to join"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	card.add_child(l)
	return card


## Client: a camera following the VR gunner's replicated head, shown as a round picture-in-picture.
func _build_ghost_mirror() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(400, 400)
	vp.world_3d = get_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	mirror_vp = vp
	add_child(vp)
	ghost_cam = Camera3D.new()
	ghost_cam.fov = 90.0
	ghost_cam.cull_mask = players[0].camera_cull_mask()
	vp.add_child(ghost_cam)
	ghost_cam.current = true
	return vp


func _add_bubble(hud: Control, source: SubViewport) -> void:
	if hud == null:
		return
	var bubble := TextureRect.new()
	bubble.texture = source.get_texture()
	bubble.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bubble.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bubble)
	bubble.size = Vector2(240, 240)
	bubble.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 24)
	var tag := Label.new()
	tag.text = "GUNNER (VR)"
	tag.add_theme_font_size_override("font_size", 22)
	tag.add_theme_constant_override("outline_size", 6)
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	bubble.add_child(tag)
	tag.position = Vector2(50, 240)


## The base controls, as before: player 2 gets the first controller (and the keyboard + mouse);
## in split screen the flat gunner gets the second. Other controllers join with A (see _poll_joins).
func _assign_joypads() -> void:
	var pads := Input.get_connected_joypads()
	if net.mode == "local":
		players[1].joy = pads[0] if pads.size() > 0 else -1  # deckhand
		players[0].joy = pads[1] if pads.size() > 1 else -1  # flat gunner
	elif net.mode == "client":
		players[1].joy = pads[0] if pads.size() > 0 else -1
	elif not players[0].vr:
		players[0].joy = pads[0] if pads.size() > 0 else -1
	for id in pads:
		print("Joypad %d: %s" % [id, Input.get_joy_name(id)])


## Which player (index) a device drives on this machine, or -1.
func device_owner(device: int) -> int:
	for p in players:
		if p.ghost or p.remote:
			continue
		if device >= 0 and p.joy == device:
			return p.index
		if device == KEYS2_DEVICE and p.key_set == 1 and p.index >= 1:
			return p.index
	return -1


func _base_player(p) -> bool:
	return p.index == 0 or p.index == 1


func _on_joy_changed(device: int, connected: bool) -> void:
	if not ready_to_play or net.mode == "host" and players[0].vr:
		return
	var owner := device_owner(device)
	if connected:
		print("Joypad %d connected: %s" % [device, Input.get_joy_name(device)])
		if owner >= 0:
			return
		# A player who lost this controller gets it back; otherwise refill the base slots as before.
		for p in players:
			if _is_local_flat(p) and p.get_meta("lost_pad", -1) == device and not p.active and p.joy < 0:
				p.remove_meta("lost_pad")
				_join_player(p, device)
				return
		if net.mode == "local":
			if players[1].joy < 0:
				players[1].joy = device
			elif players[0].joy < 0:
				players[0].joy = device
		elif net.mode == "client" and players[1].joy < 0:
			players[1].joy = device
		elif net.mode == "host" and not players[0].vr and players[0].joy < 0:
			players[0].joy = device
		return
	print("Joypad %d disconnected" % device)
	if owner < 0:
		return
	var p = players[owner]
	p.joy = -1
	if _base_player(p):
		return  # still has the keyboard
	# A drop-in player without a keyboard: their deckhand leaves until the controller comes back.
	p.set_meta("lost_pad", device)
	_leave_player(p)


## Drop-in join: a spare controller (or the arrow keys on the TV) pressing A / Enter.
func _poll_joins(delta: float) -> void:
	join_t -= delta
	if game_over or join_t > 0.0 or get_tree().paused or net.mode == "host":
		return
	for id in Input.get_connected_joypads():
		if not (Input.is_joy_button_pressed(id, JOY_BUTTON_A) or Input.is_joy_button_pressed(id, JOY_BUTTON_X)):
			continue
		var owner := device_owner(id)
		if owner < 0:
			var p = _free_slot()
			if p != null:
				_join_player(p, id)
		elif not players[owner].active and net.mode == "client":
			join_t = 1.0
			net.send_action("join", [], owner)  # the host hasn't answered yet: ask again
		return
	if net.mode == "client":
		var keys2 := Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_SLASH)
		if keys2:
			var owner := device_owner(KEYS2_DEVICE)
			if owner < 0:
				var p = _free_slot()
				if p != null:
					_join_player(p, KEYS2_DEVICE)
			elif not players[owner].active:
				join_t = 1.0
				net.send_action("join", [], owner)


func _free_slot():
	for p in players:
		if p.index >= 2 and _is_local_flat(p) and not p.active and p.joy < 0 and p.key_set < 0 and not p.has_meta("lost_pad"):
			return p
	for p in players:  # reuse a slot whose controller never came back
		if p.index >= 2 and _is_local_flat(p) and not p.active and p.joy < 0 and p.key_set < 0:
			p.remove_meta("lost_pad")
			return p
	return null


## Gives player p the device and brings them aboard (on the TV the host confirms via snapshots).
func _join_player(p, device: int) -> void:
	join_t = 0.6
	if device == KEYS2_DEVICE:
		p.key_set = 1
	elif device >= 0:
		p.joy = device
	_remember_party()
	print("Player %d joins with %s" % [p.index + 1, "the arrow keys" if device == KEYS2_DEVICE else "controller %d" % device])
	if net.mode == "client":
		net.send_action("join", [], p.index)
		_show_center("PLAYER %d IS COMING ABOARD!" % (p.index + 1), 1.2, false)
	else:
		p.position = spawn_pos(p.index)
		p.set_active(true)
		on_player_activity_changed(p)
		_show_center("PLAYER %d JOINED THE CREW!" % (p.index + 1), 1.5)


func _leave_player(p) -> void:
	if p.key_set == 1 and p.index >= 2:
		p.key_set = -1
	p.reset_crew_state()
	_remember_party()
	if net.mode == "client":
		net.send_action("leave", [], p.index)
	elif p.active:
		p.set_active(false)
		on_player_activity_changed(p)
		_show_center("Player %d left the crew" % (p.index + 1), 1.5)


## Keeps who-joined-with-what across scene reloads (restart, reconnect) so the crew stays aboard.
func _remember_party() -> void:
	var party := {}
	for p in players:
		if p.index >= 2 and _is_local_flat(p):
			if p.joy >= 0:
				party[p.joy] = p.index
			elif p.key_set == 1:
				party[KEYS2_DEVICE] = p.index
	Engine.set_meta("cc_party", party)


func _rejoin_party() -> void:
	if net.mode == "host" or not Engine.has_meta("cc_party"):
		return
	var party: Dictionary = Engine.get_meta("cc_party")
	var pads := Input.get_connected_joypads()
	for dev in party:
		var d: int = dev
		var idx: int = party[dev]
		if idx < 2 or idx >= players.size() or device_owner(d) >= 0:
			continue
		if d >= 0 and not pads.has(d):
			continue
		if d == KEYS2_DEVICE and net.mode != "client":
			continue
		_join_player(players[idx], d)


## Test hook: brings player `index` aboard without a device (tests/cannon_cove_bot.gd drives them).
func debug_join(index: int) -> bool:
	if index < 1 or index >= players.size():
		return false
	var p = players[index]
	match net.mode:
		"host":
			on_p2_action("join", [], index)
		"client":
			net.send_action("join", [], index)
		_:
			if not p.active:
				p.position = spawn_pos(index)
				p.set_active(true)
				on_player_activity_changed(p)
	return true


func on_player_activity_changed(p) -> void:
	if p.active and _is_local_flat(p):
		_ensure_view(p)
	if p.has_meta("view"):
		p.get_meta("view").visible = p.active
	_layout_views()
	print("Player %d is now %s on this screen" % [p.index + 1, "playing" if p.active else "waiting"])


func deckhands() -> Array:
	return players.filter(func(p): return not p.gunner and p.active)


## Deckhands beyond the classic two (0..4): used to scale the enemies to the size of the crew.
func crew_extra() -> int:
	return maxi(0, deckhands().size() - 2)


# --- Main loop ---------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	_update_vr_center()
	if music == null:
		music = MusicScript.new()
		add_child(music)
	music.play_track(maxi(wave - 1, 0) / 2)
	_animate_world(delta)
	_check_say(delta)
	if ghost_cam:
		ghost_cam.global_transform = players[0].net_head if players[0].net_head != Transform3D() else players[0].ghost_head.global_transform
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_update_hud()
	if players.size() < MAX_PLAYERS:
		_ensure_players(net.mode)
	_poll_joins(delta)
	if net.mode == "client":
		if game_over:
			game_over_time += delta
			if game_over_time > 1.5 and _restart_pressed():
				game_over_time = 0.0
				net.send_action("restart", [])
		return
	if game_over:
		game_over_time += delta
		var vr_restart: bool = players[0].vr and (players[0].hand_r.is_button_pressed("ax_button") or players[0].hand_l.is_button_pressed("ax_button"))
		if game_over_time > 1.5 and (_restart_pressed() or vr_restart):
			get_tree().reload_current_scene()
		return
	if net.mode == "host" and not net.connected:
		return  # hold the waves until the deckhands join
	_update_crew(delta)
	_update_water(delta)
	if in_break:
		break_timer -= delta
		if break_timer <= 0.0:
			_start_wave()
		return
	spawn_timer -= delta
	var ships := get_tree().get_nodes_in_group("ships").size()
	if spawn_timer <= 0.0:
		if ships_to_spawn > 0 and ships < 2 + wave / 2 + (1 if crew_extra() >= 2 else 0):
			_spawn_ship()
			ships_to_spawn -= 1
			spawn_timer = maxf(4.0, 9.0 - wave * 0.6)
		elif tentacles_to_spawn > 0 and get_tree().get_nodes_in_group("tentacles").size() < 1 + wave / 4 + crew_extra() / 3:
			_spawn_tentacle()
			tentacles_to_spawn -= 1
			spawn_timer = 5.0
	ships = get_tree().get_nodes_in_group("ships").size()
	if ships_to_spawn <= 0 and tentacles_to_spawn <= 0 and ships == 0 \
			and get_tree().get_nodes_in_group("tentacles").is_empty() and get_tree().get_nodes_in_group("boarders").is_empty():
		_end_wave()


func _start_wave() -> void:
	wave += 1
	in_break = false
	# A bigger crew (more than two deckhands) faces a few more ships, boarders and tentacles.
	var extra := crew_extra()
	ships_to_spawn = mini(1 + wave, 9) + extra / 2
	tentacles_to_spawn = 0 if wave < 3 else 1 + (wave - 3) / 2 + extra / 3
	spawn_timer = 0.5
	print("Wave %d started (%d deckhands, %d ships)" % [wave, deckhands().size(), ships_to_spawn])
	sound("wave")
	var sub := "Pirates ahoy!"
	if wave == 1:
		sub = "Pirate ships ahoy! Gunner: grab a cannon handle and FIRE!"
	elif wave == 3:
		sub = "Something big is stirring under the waves…"
	elif tentacles_to_spawn > 0:
		sub = "Pirates AND the sea monster!"
	_show_center("WAVE %d\n%s" % [wave, sub], 2.5)


func _end_wave() -> void:
	in_break = true
	break_timer = 6.0
	var bonus := 25 * wave
	gold += bonus
	print("Wave %d cleared, gold %d" % [wave, gold])
	sound("clear")
	sound("coin", -2.0, 1.0)
	_show_center("WAVE %d CLEARED!\n+%d GOLD bonus\nThe pumps are draining the hold…" % [wave, bonus], 3.0)


func _spawn_ship() -> void:
	var s := ShipScript.new()
	var kind := "raider"
	if wave >= 2 and randf() < 0.3 + wave * 0.04:
		kind = "galleon"
	s.setup(kind, wave, self)
	s.net_id = next_net_id()
	# Come in from port or starboard (where the cannons point), a little fore or aft.
	var side := -1.0 if randf() < 0.5 else 1.0
	var a := randf_range(-0.9, 0.9)
	var dir := Vector3(side * cos(a), 0.0, sin(a))
	s.position = dir * 95.0 + Vector3(0, sea_level, 0)
	s.heading = atan2(dir.x, dir.z)
	add_child(s)


func _spawn_tentacle() -> void:
	var t := TentacleScript.new()
	t.main = self
	t.net_id = next_net_id()
	t.side = -1.0 if randf() < 0.5 else 1.0
	t.max_hp = 4.0 + floorf(wave / 3.0)
	t.hp = t.max_hp
	t.position = Vector3(t.side * randf_range(6.8, 8.0), sea_level, randf_range(-7.0, 7.0))
	add_child(t)
	sound("tentacle", 0.0, 0.8)
	_show_center("THE SEA MONSTER!\nShoot the tentacle before it smashes the deck!", 2.0)
	splash(t.position, 2.0)


func spawn_boarder(ship) -> void:
	var b := BoarderScript.new()
	b.main = self
	b.net_id = next_net_id()
	var sp: Vector3 = ship.global_position
	var side := signf(sp.x) if absf(sp.x) > 1.0 else 1.0
	var z := clampf(sp.z * 0.3, -8.5, 8.0)
	b.swing_from = sp + Vector3.UP * 4.0
	b.swing_to = Vector3(side * 3.2, 0.0, z)
	add_child(b)
	grapple_fx(sp + Vector3.UP * 6.0, Vector3(side * World.HULL_HALF_W, 1.0, z))
	if not has_meta("boarders_announced"):
		set_meta("boarders_announced", true)
		_show_center("BOARDERS!\nDeckhands: shoot them with your muskets!", 2.0)


func boarder_count() -> int:
	return get_tree().get_nodes_in_group("boarders").size()


## Deckhands: auto-load cannons, patch leaks.
func _update_crew(delta: float) -> void:
	var patched_now := {}
	for p in deckhands():
		if p.carrying:
			var c = nearest_cannon(p.global_position, 1.9)
			if c != null and c.ammo < c.MAX_AMMO:
				_load(p, c)
		p.patching = false
		if p.use_held:
			var lk = nearest_leak(p.global_position, LeakScript.RANGE)
			if lk != null:
				lk.progress += delta / LeakScript.PATCH_TIME
				p.patching = true
				patched_now[lk] = true
	if not patched_now.is_empty():
		hammer_t -= delta
		if hammer_t <= 0.0:
			hammer_t = 0.28
			sound("hammer", -4.0, randf_range(0.9, 1.2))
	for lk in get_tree().get_nodes_in_group("leaks"):
		if lk.progress >= 1.0:
			var pos: Vector3 = lk.global_position
			lk.queue_free()
			gold += 5
			popup(pos + Vector3.UP * 1.2, "PATCHED! +5", Color(0.5, 1.0, 0.5))
			sound("clear", -6.0, 1.4)
			_particles(pos, Color(0.75, 0.55, 0.3), 10, 0.1, 4.0, 12.0, 0.6)
		elif not patched_now.has(lk):
			lk.progress = maxf(0.0, lk.progress - delta * 0.12)


func _load(p, c) -> void:
	c.ammo += 1
	p.carrying = false
	sound("load", -2.0)
	popup(c.global_position + Vector3.UP * 1.6, "LOADED!", Color(0.6, 1.0, 0.6))


func _update_water(delta: float) -> void:
	var leaks := get_tree().get_nodes_in_group("leaks").size()
	var rate := LEAK_RATE if deckhands().size() >= 2 else LEAK_RATE * 0.7
	rate *= 1.0 + 0.08 * crew_extra()  # more hands patch faster, so holes let in a little more
	if leaks > 0:
		water += leaks * rate * delta
	else:
		water -= (4.0 if in_break else 1.2) * delta
	water = clampf(water, 0.0, 100.0)
	if water >= 100.0:
		_on_game_over()


func nearest_cannon(pos: Vector3, max_d: float):
	var best = null
	var best_d := max_d
	for c in cannons:
		var d := Vector2(pos.x - c.global_position.x, pos.z - c.global_position.z).length()
		if d < best_d:
			best_d = d
			best = c
	return best


func nearest_leak(pos: Vector3, max_d: float):
	var best = null
	var best_d := max_d
	for lk in get_tree().get_nodes_in_group("leaks"):
		var d: float = Vector2(pos.x - lk.global_position.x, pos.z - lk.global_position.z).length()
		if d < best_d:
			best_d = d
			best = lk
	return best


## Host: a deckhand pressed or released "use".
func set_use(p, held: bool) -> void:
	p.use_held = held
	if not held:
		return
	if nearest_leak(p.global_position, LeakScript.RANGE) != null:
		return  # holding: patching
	if not p.carrying and p.global_position.distance_to(World.HOLD_POS) < 2.6:
		p.carrying = true
		sound("pickup", -4.0, 0.8)
		if not has_meta("first_ball"):
			set_meta("first_ball", true)
			print("Deckhand picked up a cannonball")
		return
	if p.carrying:
		var c = nearest_cannon(p.global_position, 2.8)
		if c != null and c.ammo < c.MAX_AMMO:
			_load(p, c)
		elif c != null:
			popup(c.global_position + Vector3.UP * 1.6, "FULL!", Color(1.0, 0.9, 0.5))
		else:
			p.carrying = false  # drop it (it rolls away)
			sound("dry", -6.0, 0.5)


func create_leak(pos: Vector3) -> void:
	var leaks := get_tree().get_nodes_in_group("leaks")
	if leaks.size() >= MAX_LEAKS:
		water = minf(100.0, water + 4.0)
		return
	var p := World.constrain(pos, 0.5, cannon_obstacles())
	for lk in leaks:
		if lk.global_position.distance_to(p) < 1.0:
			water = minf(100.0, water + 3.0)  # the same hole got bigger
			return
	var leak := LeakScript.new()
	leak.main = self
	leak.net_id = next_net_id()
	leak.position = p
	add_child(leak)
	sound("creak", -2.0, randf_range(0.8, 1.1))
	if not has_meta("leak_announced"):
		set_meta("leak_announced", true)
		_show_center("WE'VE GOT A LEAK!\nDeckhands: hold USE next to it to patch it!", 2.5)


# --- Gunner -------------------------------------------------------------------

func gunner_fire(p) -> bool:
	if game_over or p.station < 0:
		return false
	var c = cannons[p.station]
	return c.fire()


func ball_hit_test(pos: Vector3):
	for s in get_tree().get_nodes_in_group("ships"):
		if s.hit_test(pos):
			return s
	for t in get_tree().get_nodes_in_group("tentacles"):
		if t.alive() and t.distance_to_point(pos) < 1.1:
			return t
	return null


func on_ball_hit(target, pos: Vector3) -> void:
	explosion(pos, Color(1.0, 0.6, 0.2), 1.2)
	sound("big_kill", -4.0, 1.3)
	add_shake(pos, 0.15)
	if target.is_in_group("tentacles"):
		target.hit(3.0)
		popup(pos + Vector3.UP, "SPLAT!", Color(0.9, 0.6, 1.0))
	else:
		target.hit(1.0)
		if not target.sinking:
			popup(pos + Vector3.UP * 2.0, "HIT!", Color(1.0, 0.8, 0.3))


func on_ship_sunk(s) -> void:
	gold += s.gold
	var pos: Vector3 = s.global_position + Vector3.UP * 3.0
	popup(pos + Vector3.UP * 2.0, "SUNK!  +%d GOLD" % s.gold, Color(1.0, 0.85, 0.2))
	explosion(pos, Color(1.0, 0.75, 0.3), 2.2)
	sound("big_kill", 0.0, 0.8)
	sound("coin", -2.0)
	splash(s.global_position, 2.5)
	print("Sunk a %s, gold %d" % [s.kind, gold])


func enemy_ball_hit_deck(pos: Vector3) -> void:
	explosion(pos + Vector3.UP * 0.3, Color(1.0, 0.5, 0.2), 0.9)
	add_shake(pos, 0.5)
	sound("big_kill", -3.0, 1.1)
	create_leak(pos)


func on_tentacle_slam(_t, pos: Vector3) -> void:
	add_shake(pos, 0.6)
	sound("big_kill", -2.0, 0.6)
	_particles(pos + Vector3.UP * 0.3, Color(0.6, 0.85, 1.0), 16, 0.12, 6.0, 14.0, 0.8, 60.0)
	if net:
		net.event("slam", [pos])
	create_leak(pos)


func on_tentacle_killed(t) -> void:
	gold += 40
	popup(t.segs[t.SEGMENTS - 1].global_position + Vector3.UP, "BYE BYE MONSTER!  +40", Color(0.9, 0.6, 1.0))
	sound("big_kill", 0.0, 0.7)
	sound("coin", -2.0, 1.2)
	splash(Vector3(t.position.x, sea_level, t.position.z), 2.5)
	print("Tentacle defeated, gold %d" % gold)


# --- Deckhand muskets ------------------------------------------------------------

## Nudges a musket shot towards a boarder or tentacle that's roughly in front.
func musket_aim(from: Vector3, dir: Vector3) -> Vector3:
	var best := dir
	var best_dot := cos(deg_to_rad(7.0))
	var targets := []
	for b in get_tree().get_nodes_in_group("boarders"):
		if b.alive():
			targets.append(b.global_position + Vector3.UP * 1.0)
	for t in get_tree().get_nodes_in_group("tentacles"):
		if t.alive():
			for i in range(2, t.SEGMENTS, 2):
				targets.append(t.segs[i].global_position)
	for p in targets:
		var to: Vector3 = p - from
		var dist := to.length()
		if dist < 0.5 or dist > 40.0:
			continue
		var d := dir.dot(to / dist)
		if d > best_dot:
			best_dot = d
			best = to / dist
	return best


## [target or null, end point]
func musket_trace(from: Vector3, dir: Vector3) -> Array:
	var best_t := 45.0
	var target = null
	for b in get_tree().get_nodes_in_group("boarders"):
		var t: float = b.ray_hit(from, dir, best_t)
		if t < best_t:
			best_t = t
			target = b
	for tn in get_tree().get_nodes_in_group("tentacles"):
		if not tn.alive():
			continue
		var t: float = tn.ray_hit(from, dir, best_t)
		if t < best_t:
			best_t = t
			target = tn
	return [target, from + dir * best_t]


func musket_shot(p, from: Vector3, dir: Vector3) -> void:
	var tr := musket_trace(from, dir)
	var target = tr[0]
	musket_fx(p.index, from, tr[1])
	if target == null:
		return
	if p.hud:
		p.hud.hit_marker()
	else:
		net.event("hitmark", [p.index])
	if target.is_in_group("boarders"):
		sound("hit", -4.0)
		if target.hit(1.0):
			gold += 10
			popup(target.global_position + Vector3.UP * 2.0, "SPLASH! +10", Color(0.6, 0.9, 1.0))
			sound("dash", -4.0, 0.6)
			get_tree().create_timer(0.9).timeout.connect(func() -> void:
				if is_instance_valid(target):
					splash(Vector3(target.global_position.x, sea_level, target.global_position.z), 1.2))
	else:
		target.hit(1.0)
		sound("hit", -2.0, 0.6)


func boarder_stole(b, c) -> void:
	c.ammo = maxi(0, c.ammo - 1)
	popup(c.global_position + Vector3.UP * 1.8, "HEY! STOLEN!", Color(1.0, 0.45, 0.4))
	sound("pickup", -6.0, 0.6)
	_particles(b.global_position + Vector3.UP, Color(0.15, 0.15, 0.15), 4, 0.1, 2.0, 9.0, 0.5)


func boarder_hacked(_b, pos: Vector3) -> void:
	sound("hammer", -2.0, 0.6)
	create_leak(pos)


# --- Prompts ----------------------------------------------------------------------

## What this player should do next (shown at the bottom of their screen). A leading "!" makes it red.
func player_prompt(p) -> String:
	if game_over:
		return ""
	if p.gunner:
		var c = cannons[p.station]
		var keys := "Sticks aim · RT / A fire · LB / RB switch cannon"
		if p.joy < 0:
			keys = "WASD / mouse aim · SPACE / click fire · Q / E switch cannon" if p.key_set == 0 else "ARROWS aim · ENTER fire · , / . switch cannon"
		if c.ammo <= 0:
			return "!This cannon is EMPTY - switch cannon or wait for the deckhands\n" + keys
		return "%s cannon: %d balls\n%s" % [c.side_name(), c.ammo, keys]
	var use: String = p.use_name()
	var lk = nearest_leak(p.global_position, LeakScript.RANGE)
	if lk != null:
		if p.patching:
			return "Hammering… %d%%" % int(lk.progress * 100.0)
		return "!HOLD %s TO PATCH THE LEAK!" % use
	if p.hands_full_t > 0.0:
		return "!Hands full! Load the cannonball first (or press %s away from things to drop it)" % use
	if p.carrying:
		var empty := _emptiest_cannon()
		return "Carry the cannonball to a cannon!  (%s needs it most)" % empty
	if p.global_position.distance_to(World.HOLD_POS) < 2.6:
		return "PRESS %s TO GRAB A CANNONBALL" % use
	if not get_tree().get_nodes_in_group("boarders").is_empty():
		return "!BOARDERS! Shoot them with your musket (%s)" % p.fire_name()
	if not get_tree().get_nodes_in_group("leaks").is_empty():
		return "!Find the LEAK and patch it!"
	for c in cannons:
		if c.ammo <= 1:
			return "Fetch cannonballs from the pile at the front of the ship"
	return "Shoot boarders · fetch cannonballs · patch leaks"


func _emptiest_cannon() -> String:
	var best = cannons[0]
	for c in cannons:
		if c.ammo < best.ammo or (c.ammo == best.ammo and c.manned):
			best = c
	return "%s %s" % [best.side_name(), "FORE" if best.index % 2 == 0 else "AFT"]


# --- Game over ---------------------------------------------------------------------

func _on_game_over() -> void:
	if game_over:
		return
	game_over = true
	game_over_time = 0.0
	sound("gameover")
	print("Game over: wave %d, gold %d" % [wave, gold])
	var cfg := ConfigFile.new()
	cfg.load("user://cannon_cove_best.cfg")
	var best: int = cfg.get_value("best", "gold", 0)
	var best_line := "Best haul: %d gold" % best
	if gold > best:
		best_line = "NEW RECORD HAUL!  (previous %d)" % best
		cfg.set_value("best", "gold", gold)
		cfg.set_value("best", "wave", wave)
		cfg.save("user://cannon_cove_best.cfg")
	_show_center("THE SHIP SANK!\nWave %d  ·  %d gold\n%s\n\nPress A or Enter to set sail again" % [wave, gold, best_line], 0.0)


func _restart_pressed() -> bool:
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_R):
		return true
	for id in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(id, JOY_BUTTON_A):
			return true
	for p in players:
		if p.bot_fire and not p.ghost and not p.remote:
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_F11:
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


# --- Networked co-op -----------------------------------------------------------------

func on_client_joined() -> void:
	_show_center("THE DECKHANDS ARE ABOARD!", 1.5)


func on_client_left() -> void:
	_show_center("The deckhands left - waiting for them to come back…", 0.0)
	for p in players:
		if p.index >= 2 and p.active:
			p.reset_crew_state()
			p.set_active(false)  # the TV rejoins them when it reconnects


## Host: a TV deckhand did something.
func on_p2_action(action: String, args: Array, index: int = 1) -> void:
	if index < 0 or index >= players.size():
		return
	var p = players[index]
	match action:
		"use":
			set_use(p, args[0])
		"musket":
			if not has_meta("p2_fired"):
				set_meta("p2_fired", true)
				print("Net: a deckhand fired a musket")
			musket_shot(p, args[0], args[1])
		"join":
			if not p.active:
				p.set_active(true)
				_show_center("PLAYER %d JOINED THE CREW!" % (index + 1), 1.5)
				print("Net: player %d joined the game (%d deckhands)" % [index + 1, deckhands().size()])
		"leave":
			if p.active and index >= 1:
				p.reset_crew_state()
				p.set_active(false)
				_show_center("Player %d left the crew" % (index + 1), 1.5)
				print("Net: player %d left the game" % (index + 1))
		"restart":
			if game_over:
				get_tree().reload_current_scene()
		"pause":
			var paused: bool = args[0]
			_set_pause_banner(paused, "A deckhand opened the menu")
			get_tree().paused = paused


func _set_pause_banner(paused: bool, who: String) -> void:
	_show_center("PAUSED\n" + who if paused else "", 0.0, false)
	_update_vr_center()


func toggle_vr_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_set_pause_banner(paused, "Press the menu button to resume")
	net.event("remote_pause", [paused])


func make_snapshot() -> Array:
	var ps := []
	for p in players:
		ps.append(p.net_state())
	var cs := []
	for c in cannons:
		cs.append(c.net_state())
	var sh := []
	for s in get_tree().get_nodes_in_group("ships"):
		sh.append(s.net_state())
	var te := []
	for t in get_tree().get_nodes_in_group("tentacles"):
		te.append(t.net_state())
	var bo := []
	for b in get_tree().get_nodes_in_group("boarders"):
		bo.append(b.net_state())
	var lk := []
	for l in get_tree().get_nodes_in_group("leaks"):
		lk.append(l.net_state())
	return [wave, gold, water, game_over, in_break, ps, cs, sh, te, bo, lk]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play:
		return
	synced = true
	wave = s[0]
	gold = s[1]
	water = s[2]
	game_over = s[3]
	in_break = s[4]
	var ps: Array = s[5]
	for i in mini(players.size(), ps.size()):
		players[i].apply_net_state(ps[i])
	var cs: Array = s[6]
	for i in mini(cannons.size(), cs.size()):
		cannons[i].apply_net(cs[i])
	_sync_ghosts(s[7], "ship")
	_sync_ghosts(s[8], "tentacle")
	_sync_ghosts(s[9], "boarder")
	_sync_ghosts(s[10], "leak")


func _sync_ghosts(list: Array, kind: String) -> void:
	var seen := {}
	for item in list:
		var key := "%s:%d" % [kind, item[0]]
		seen[key] = true
		var g = ghost_nodes.get(key)
		if g == null or not is_instance_valid(g):
			g = _make_ghost(kind, item)
			ghost_nodes[key] = g
		g.apply_net(item)
	for key in ghost_nodes.keys():
		if key.begins_with(kind + ":") and not seen.has(key):
			var g = ghost_nodes[key]
			if is_instance_valid(g):
				g.queue_free()
			ghost_nodes.erase(key)


func _make_ghost(kind: String, item: Array) -> Node3D:
	match kind:
		"ship":
			var s := ShipScript.new()
			s.setup(item[1], wave, self)
			s.ghost = true
			s.net_id = item[0]
			s.position = item[2]
			s.net_target = item[2]
			s.heading = item[3]
			add_child(s)
			return s
		"tentacle":
			var t := TentacleScript.new()
			t.main = self
			t.ghost = true
			t.net_id = item[0]
			t.position = item[1]
			t.side = item[6]
			t.deck_target = item[7]
			add_child(t)
			return t
		"boarder":
			var b := BoarderScript.new()
			b.main = self
			b.ghost = true
			b.net_id = item[0]
			b.position = item[1]
			b.net_target = item[1]
			add_child(b)
			return b
	var lk := LeakScript.new()
	lk.main = self
	lk.ghost = true
	lk.net_id = item[0]
	lk.position = item[1]
	add_child(lk)
	return lk


func apply_event(kind: String, args: Array) -> void:
	if not ready_to_play:
		return
	match kind:
		"sound":
			_sfx().play(args[0], args[1], args[2])
		"popup":
			popup(args[0], args[1], args[2])
		"smoke":
			smoke(args[0], args[1])
		"splash":
			splash(args[0], args[1])
		"boom":
			explosion(args[0], args[1], args[2])
		"ball":
			spawn_ball(args[0], args[1], args[2], true)
		"cannon_fx":
			var i: int = args[0]
			if i >= 0 and i < cannons.size():
				cannons[i].fire_fx()
		"musket":
			var shooter: int = args[0]
			var mine: bool = shooter < players.size() and not players[shooter].ghost and not players[shooter].remote
			if not mine:
				musket_fx(shooter, args[1], args[2])
		"grapple":
			grapple_fx(args[0], args[1])
		"slam":
			var pos: Vector3 = args[0]
			add_shake(pos, 0.6)
			_particles(pos + Vector3.UP * 0.3, Color(0.6, 0.85, 1.0), 16, 0.12, 6.0, 14.0, 0.8, 60.0)
		"center":
			_show_center(args[0], args[1])
		"say":
			claude_say(args[0])
		"remote_pause":
			get_tree().paused = args[0]
			_set_pause_banner(args[0], "The VR gunner paused the game")
		"hitmark":
			var hi: int = args[0]
			if hi < players.size() and players[hi].hud:
				players[hi].hud.hit_marker()


# --- HUD ----------------------------------------------------------------------------

func _make_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", maxi(4, size / 5))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	info_label = _make_label(32)
	info_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	layer.add_child(info_label)
	info_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	info_label.offset_top = 14
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label = _make_label(58)
	layer.add_child(center_label)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label = _make_label(22)
	layer.add_child(help_label)
	help_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	help_label.offset_top = 60
	help_label.offset_bottom = 190
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.text = "DECKHANDS: move (stick / WASD), look (stick / mouse), musket RT / click, use A / E (grab ball, load, hold to patch)\n" \
		+ "MORE CREW: press A on another controller to jump in (up to 6 deckhands)\n" \
		+ "GUNNER: grab the glowing cannon handle in VR and fire with the trigger  ·  flat: sticks aim, RT fire, LB/RB switch cannon\n" \
		+ "Keep the cannons loaded, patch the leaks, sink the pirates, grab the gold!"


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
	if wave >= 2 and help_label.modulate.a > 0.0:
		help_label.modulate.a = maxf(0.0, help_label.modulate.a - get_process_delta_time())
	if net.mode == "client" and not synced:
		info_label.text = "Syncing with the VR gunner…"
		return
	info_label.text = "WAVE %d     GOLD %d     WATER %d%%" % [wave, gold, int(water)]


## VR can't show 2D overlays: mirror the centre banner on a head-locked Label3D.
func _update_vr_center() -> void:
	if players.is_empty() or not players[0].vr:
		return
	if vr_center == null:
		vr_center = Label3D.new()
		vr_center.font_size = 48
		vr_center.outline_size = 26
		vr_center.no_depth_test = true
		vr_center.render_priority = 10
		vr_center.outline_render_priority = 9
		vr_center.width = 900.0
		vr_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vr_center.pixel_size = 0.0026
		vr_center.position = Vector3(0.0, 0.05, -1.8)
		players[0].xr_camera.add_child(vr_center)
		players[0]._set_layers(vr_center, players[0].viewmodel_layer())
	vr_center.text = center_label.text
	vr_center.modulate.a = center_label.modulate.a
	vr_center.outline_modulate = Color(0, 0, 0, center_label.modulate.a)
	VrText.follow(vr_center, players[0].xr_camera, self, 0.05, 1.8)


# Messages from Claude (res://.dev/say.txt on the host), shown on the TV and in VR.
func _check_say(delta: float) -> void:
	say_t -= delta
	if say_t > 0.0:
		return
	say_t = 0.3
	var path := ProjectSettings.globalize_path("res://.dev/say.txt")
	if not FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(path).strip_edges()
	DirAccess.remove_absolute(path)
	if text != "":
		claude_say(text)


func claude_say(text: String) -> void:
	if net:
		net.event("say", [text])
	_show_center("Claude: " + text, 5.0 + text.length() * 0.08, false)
	_sfx().play("pickup", -6.0, 0.8)
