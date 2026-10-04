extends Node3D
const VrText := preload("res://core/vr_text.gd")
## Kitchen Rush: co-op cooking chaos.
## Player 1 is the CHEF at the counter (VR hands, or button controls in split screen): chop and stack.
## Players 2-7 are RUNNERS (TV, first person, split screen): fetch ingredients to the pass, carry finished plates
## to customers. Extra runners drop in by pressing A / Start on a controller nobody owns yet.
## The host simulates everything; the TV machine mirrors it from snapshots (see core/net.gd).

const L := preload("res://games/kitchen_rush/layout.gd")
const KitchenScript := preload("res://games/kitchen_rush/kitchen.gd")
const ItemScript := preload("res://games/kitchen_rush/item.gd")
const CustomerScript := preload("res://games/kitchen_rush/customer.gd")
const RaccoonScript := preload("res://games/kitchen_rush/raccoon.gd")
const ChefScript := preload("res://games/kitchen_rush/chef.gd")
const RunnerScript := preload("res://games/kitchen_rush/runner.gd")
const HudScript := preload("res://games/kitchen_rush/hud.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const JoinInputScript := preload("res://games/kitchen_rush/join_input.gd")
const GuideScript := preload("res://games/kitchen_rush/guide.gd")

const RECIPES := {
	"SALAD": ["lettuce", "tomato", "cucumber"],
	"TOASTIE": ["bun", "cheese"],
	"BURGER": ["bun", "patty", "lettuce", "tomato"],
	"PIZZA": ["dough", "tomato", "cheese"],
}
const UNLOCKS := [["SALAD", "TOASTIE"], ["BURGER"], ["PIZZA"]]  # new recipes at shifts 1, 2 and 3
const MAX_ANGRY := 5
const MAX_CUSTOMERS := 4
const COMBO_WINDOW := 12.0
const MAX_RUNNERS := 6  # player indices 1..6 (P2..P7); index 0 is the chef
const PLAYER_COLORS: Array[Color] = [Color(1.0, 0.45, 0.35), Color(0.3, 0.65, 1.0), Color(0.7, 0.45, 1.0),
	Color(0.35, 0.9, 0.4), Color(1.0, 0.82, 0.2), Color(1.0, 0.45, 0.8), Color(0.25, 0.92, 0.9)]
const LEAVE_AFTER_UNPLUG := 15.0  # a runner whose controller is unplugged this long leaves the kitchen
## A day in the kitchen: breakfast, lunch and dinner, each rated with up to three stars.
const SHIFT_NAMES := ["BREAKFAST", "LUNCH", "DINNER"]
const RUSH_TIME := 25.0
## Extra sounds made with core/sfx.gd: [seconds, start Hz, end Hz, volume, wave, noise]
const EXTRA_SOUNDS := {
	"chop": [0.09, 320.0, 90.0, 0.5, "square", 0.55],
	"ding": [0.9, 1568.0, 1560.0, 0.3, "sine", 0.0],
	"star": [0.45, 880.0, 1760.0, 0.32, "tri", 0.0],
	"coin": [0.25, 988.0, 1976.0, 0.28, "square", 0.0],
	"cheer": [0.8, 520.0, 1250.0, 0.26, "tri", 0.45],
	"cluck": [0.16, 700.0, 500.0, 0.18, "saw", 0.4],
	"rush": [0.7, 330.0, 990.0, 0.35, "saw", 0.1],
	"splat": [0.2, 220.0, 80.0, 0.35, "sine", 0.7],
}
const BUBBLE_SHADER := """
shader_type canvas_item;
uniform vec4 ring_color : source_color = vec4(1.0, 0.5, 0.4, 1.0);
void fragment() {
	float r = length(UV - 0.5);
	vec4 c = texture(TEXTURE, UV);
	float inside = 1.0 - smoothstep(0.485, 0.5, r);
	float ring = smoothstep(0.45, 0.47, r);
	COLOR = vec4(mix(c.rgb, ring_color.rgb, ring), inside);
}
"""

var players: Array = []
var ready_to_play := false
var net: Node
var sfx: Node
var music: AudioStreamPlayer
var mats := {}
var net_ids := 0
var ghost_nodes := {}
var synced := false
var xr_interface: XRInterface
var mirror_vp: SubViewport
var mirror_t := 0.0
var ghost_cam: Camera3D
var vr_center: Label3D
var cameras: Array[Camera3D] = []
var bubble_rect: TextureRect
var bubble_tag: Label
var join_cd := {}  # player index -> seconds until another join request may be sent

# Game state (simulated on the host, mirrored on the client).
var shift := 0
var coins := 0
var served_shift := 0
var served_total := 0
var angry := 0
var combo := 0
var last_serve_time := -100.0
var clock := 0.0
var in_break := true
var break_t := 3.0
var spawn_t := 1.0
var game_over := false
var game_over_t := 0.0
var fire_on := false
var fire_hp := 0
var fire_t := 30.0
var ext_holder := -1
var raccoon_t := 25.0
var raccoon: Node3D
var stars: Array = []  # stars earned per finished shift
var angry_at_start := 0
var frac_sum := 0.0
var rush_t := 0.0
var rush_done := false
var critic_done := false
var customers_spawned := 0
var stats: Array = []  # per player
var parts: Dictionary = {}  # animated bits of the kitchen (fan, bell, chickens, butterflies, menu)
var chef_task: Dictionary = {}
var vr_hint: Label3D
var stats_label: Label
var stats_text := ""
var help_panel: PanelContainer
var bell_t := 0.0
var cluck_t := 4.0
var chicken_goals: Array = []

# Visuals
var fire_node: Node3D
var ext_node: Node3D
var tickets: Array = []  # [root, label, bar]
var info_label: Label
var center_label: Label
var help_label: Label
var center_tween: Tween


func _ready() -> void:
	randomize()
	parts = KitchenScript.build(self)
	for i in MAX_RUNNERS + 1:
		stats.append({"fetched": 0, "served": 0, "sprays": 0, "raccoons": 0, "chops": 0, "dishes": 0})
	_build_hud()
	_build_fire_and_extinguisher()
	_build_tickets()
	raccoon = RaccoonScript.new()
	raccoon.main = self
	add_child(raccoon)
	var menu := PauseMenuScript.new()
	menu.main = self
	add_child(menu)
	net = NetScript.new()
	net.name = "Net"
	net.main = self
	add_child(net)
	Input.joy_connection_changed.connect(_on_joy_changed)
	if OS.has_environment("DUO_JOIN"):
		banner("Connecting to the chef…", 0.0, false)
		net.join_finished.connect(func(ok: bool) -> void: _setup_game("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		var xr := XRServer.find_interface("OpenXR")
		if (xr != null and xr.is_initialized()) or OS.has_environment("DUO_HOST"):
			net.host()
		_setup_game(net.mode)


func _setup_game(mode: String) -> void:
	raccoon.ghost = mode == "client"
	_build_players(mode)
	_build_views(mode)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_assign_joypads()
	ready_to_play = true
	print("Kitchen Rush: %s mode" % mode)
	if mode == "host":
		banner("KITCHEN RUSH\nWaiting for the runners on the TV to join…\nTry chopping: swing a knife down through a vegetable!", 0.0)
		_practice_veg()
	elif mode == "client":
		banner("CONNECTED TO THE KITCHEN!", 1.5, false)
	else:
		banner("KITCHEN RUSH\nGet ready to cook!", 2.5)


func next_net_id() -> int:
	net_ids += 1
	return net_ids


# --- Small helpers -------------------------------------------------------------

func mat(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f" % [color.to_html(), glow]
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


func set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		node.layers = layers
	for c in node.get_children():
		set_layers(c, layers)


func add_chef_hat(parent: Node3D, pos: Vector3, s: float) -> void:
	var hat := Node3D.new()
	hat.position = pos
	hat.scale = Vector3.ONE * s
	parent.add_child(hat)
	var band := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.17
	c.bottom_radius = 0.16
	c.height = 0.16
	c.radial_segments = 14
	c.rings = 1
	band.mesh = c
	band.material_override = mat(Color.WHITE)
	band.position.y = 0.08
	hat.add_child(band)
	var puff := MeshInstance3D.new()
	var s2 := SphereMesh.new()
	s2.radius = 0.22
	s2.height = 0.3
	s2.radial_segments = 14
	s2.rings = 7
	puff.mesh = s2
	puff.material_override = mat(Color.WHITE)
	puff.position.y = 0.22
	hat.add_child(puff)


func add_sign(pos: Vector3, text: String, color: Color, font: int, billboard: bool) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font
	l.outline_size = maxi(12, font / 3)
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.modulate = color
	l.pixel_size = 0.005
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.position = pos
	if not billboard:
		l.rotation.y = -PI / 2.0 if pos.x > 5.0 else 0.0
	add_child(l)
	return l


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	sfx_local(sound_name, volume_db, pitch)
	if net:
		net.event("sound", [sound_name, volume_db, pitch])


func sfx_local(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if sfx == null:
		sfx = SfxScript.new()
		add_child(sfx)
		for k in EXTRA_SOUNDS:
			var d: Array = EXTRA_SOUNDS[k]
			sfx.add_sound(k, d)
	sfx.play(sound_name, volume_db, pitch)


func burst(pos: Vector3, color: Color, amount: int = 16, size: float = 0.08) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -9, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var m := BoxMesh.new()
	m.size = Vector3.ONE * size
	m.material = mat(color, 1.0)
	p.mesh = m
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)
	if net:
		net.event("burst", [pos, color, amount, size])


## Floating text that rises and fades; shown on both machines.
func popup(pos: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.font_size = 64
	l.outline_size = 22
	l.pixel_size = 0.004
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	l.global_position = pos
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "global_position", pos + Vector3.UP * 0.6, 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.8)
	t.tween_property(l, "outline_modulate:a", 0.0, 0.6).set_delay(0.8)
	t.chain().tween_callback(l.queue_free)
	if net:
		net.event("popup", [pos, text, color])


func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func input_blocked() -> bool:
	return get_tree().paused or game_over or not ready_to_play


# --- Players & views -------------------------------------------------------------

func _build_players(mode: String) -> void:
	var chef := ChefScript.new()
	chef.index = 0
	chef.color = PLAYER_COLORS[0]
	chef.main = self
	chef.ghost = mode == "client"
	add_child(chef)
	players.append(chef)
	_ensure_runners(mode)


## Runners 1..6 always exist (so the host can accept any index); all but runner 1 wait until they join.
## Called again every frame, so a hot-reloaded game grows the extra runners lazily.
func _ensure_runners(mode: String) -> void:
	while players.size() <= MAX_RUNNERS:
		var i := players.size()
		var r := RunnerScript.new()
		r.index = i
		r.color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
		r.main = self
		r.remote = mode == "host"
		# Keyboards: P2 arrows + Enter; P3 on the TV machine WASD + mouse. Everyone else uses a controller.
		r.key_set = 1 if i == 1 else (0 if i == 2 and mode == "client" else -1)
		r.mouse_look = r.key_set == 0
		r.position = runner_spawn(i)
		r.yaw = PI
		add_child(r)
		players.append(r)
		if i >= 2:
			r.set_active(false)


func runner_spawn(i: int) -> Vector3:
	var base: Vector3 = L.RUNNER_SPAWN[(i - 1) % 2]
	return base + Vector3(0.0, 0.0, -0.8 * floorf((i - 1) / 2.0))


func _apply_vr_performance() -> void:
	for n in get_children():
		if n is WorldEnvironment:
			var e: Environment = n.environment
			e.ssao_enabled = false
			e.fog_enabled = false
			e.glow_intensity = 0.3
		elif n is DirectionalLight3D:
			n.shadow_enabled = false


func _build_views(mode: String) -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized() and mode != "client":
		xr_interface = xr
		print("VR headset found: player 1 is the chef in VR")
		Engine.physics_ticks_per_second = 90
		get_viewport().use_xr = true
		get_viewport().msaa_3d = Viewport.MSAA_2X
		_apply_vr_performance()
		var origin := XROrigin3D.new()
		add_child(origin)
		origin.global_position = L.CHEF_POS
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
		var mirror := _build_vr_mirror(cam)
		if mode == "local":
			_build_flat_window(players[1])
			_add_bubble(players[1].hud, mirror, PLAYER_COLORS[0])
	elif OS.has_environment("KR_FAKE_VR") and mode != "client":
		# Tests: the VR chef's code runs without a headset; the bot moves the hands.
		print("Fake VR: the bot drives the VR chef")
		var origin := XROrigin3D.new()
		add_child(origin)
		origin.global_position = L.CHEF_POS
		var cam := XRCamera3D.new()
		origin.add_child(cam)
		cam.position = Vector3(0, 1.2, 0)
		var left := XRController3D.new()
		left.tracker = "left_hand"
		origin.add_child(left)
		left.position = Vector3(-0.25, 0.9, -0.2)
		var right := XRController3D.new()
		right.tracker = "right_hand"
		origin.add_child(right)
		right.position = Vector3(0.25, 0.9, -0.2)
		players[0].fake_vr = true
		players[0].attach_xr(origin, cam, left, right)
	else:
		print("No VR headset: split screen")
	_view_grid()
	for p in players:
		if p.active and _wants_view(p):
			_ensure_view(p)
	if mode == "client":
		_add_bubble(players[1].hud, _build_ghost_mirror(), PLAYER_COLORS[0])
	_layout_views()


func _wants_view(p) -> bool:
	return not (p.vr or p.remote or p.ghost) and (p.camera == null or p.has_meta("view"))


## The split-screen grid on the main window (created lazily, so hot reloads can add it too).
func _view_grid() -> GridContainer:
	var grid := get_node_or_null("ViewLayer/Grid") as GridContainer
	if grid != null:
		return grid
	var layer := CanvasLayer.new()
	layer.name = "ViewLayer"
	layer.layer = -1
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid = GridContainer.new()
	grid.name = "Grid"
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	layer.add_child(grid)
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for p in players:  # views made by an older version of this script
		if p.has_meta("view"):
			var c: Control = p.get_meta("view")
			if c.get_parent() != grid:
				c.reparent(grid, false)
	return grid


## One SubViewport (camera + HUD) for a local player.
func _ensure_view(p) -> void:
	if p.has_meta("view") or p.camera != null:
		return
	var container := SubViewportContainer.new()
	p.set_meta("view", container)
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_grid().add_child(container)
	var vp := SubViewport.new()
	vp.world_3d = get_world_3d()
	vp.msaa_3d = Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	container.add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	cameras.append(cam)
	p.attach_camera(cam)
	var hud_layer := CanvasLayer.new()
	vp.add_child(hud_layer)
	var hud := HudScript.new()
	hud.player = p
	hud.main = self
	hud.chef = p.index == 0
	hud_layer.add_child(hud)
	p.hud = hud


## 1 view: full screen, 2: side by side, 3-4: 2x2, 5-6: 3x2, 7: 4x2. Empty cells invite more players.
## More views render at a lower resolution, with fewer effects, to keep the frame rate up.
func _layout_views() -> void:
	var grid := _view_grid()
	var views: Array = []
	for p in players:
		if p.has_meta("view"):
			var c: Control = p.get_meta("view")
			c.visible = p.active
			if p.active:
				views.append(c)
	var n := views.size()
	var cols := 1
	if n == 2:
		cols = 2
	elif n >= 3 and n <= 4:
		cols = 2
	elif n >= 5 and n <= 6:
		cols = 3
	elif n >= 7:
		cols = 4
	grid.columns = cols
	var scale_3d := 1.0 if n <= 2 else (0.7 if n <= 4 else 0.55)
	for i in views.size():
		var c: Control = views[i]
		grid.move_child(c, i)
		var vp := c.get_child(0) as SubViewport
		if vp:
			vp.scaling_3d_scale = scale_3d
			vp.msaa_3d = Viewport.MSAA_2X if n <= 2 else Viewport.MSAA_DISABLED
	# Fillers for the empty grid cells.
	var rows := ceili(float(n) / float(cols)) if n > 0 else 0
	var need := rows * cols - n if n > 2 else 0
	var fillers: Array = []
	for c in grid.get_children():
		if c.has_meta("filler"):
			fillers.append(c)
	while fillers.size() < need:
		var f := ColorRect.new()
		f.set_meta("filler", true)
		f.color = Color(0.06, 0.07, 0.1)
		f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		f.size_flags_vertical = Control.SIZE_EXPAND_FILL
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := _make_label(30)
		l.text = "Grab a controller\nand press A to join!"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
		f.add_child(l)
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		grid.add_child(f)
		fillers.append(f)
	for i in fillers.size():
		var f: Control = fillers[i]
		f.visible = i < need
		grid.move_child(f, grid.get_child_count() - 1)
	# Effects: shared by every view, so trim them when the screen is split many ways.
	if players.is_empty() or players[0].vr:
		return
	for nd in get_children():
		if nd is WorldEnvironment and nd.environment:
			nd.environment.ssao_enabled = n <= 2
		elif nd is DirectionalLight3D:
			nd.shadow_enabled = n <= 4
			nd.directional_shadow_max_distance = 30.0 if n <= 2 else 18.0


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


## Client: a camera that follows the chef's replicated head, for the picture-in-picture bubble.
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


func _add_bubble(hud: Control, source: SubViewport, color: Color) -> void:
	if hud == null:
		return
	var bubble := TextureRect.new()
	bubble.texture = source.get_texture()
	bubble.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bubble.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = BUBBLE_SHADER
	m.set_shader_parameter("ring_color", color)
	bubble.material = m
	hud.add_child(bubble)
	bubble.size = Vector2(260, 260)
	bubble.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 24)
	bubble_rect = bubble
	var tag := Label.new()
	tag.text = "CHEF (VR)"
	tag.add_theme_font_size_override("font_size", 22)
	tag.add_theme_constant_override("outline_size", 6)
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_color_override("font_color", color)
	bubble.add_child(tag)
	tag.position = Vector2(80, 262)
	bubble_tag = tag


## The VR bubble shrinks with its view in a 2x2 / 3x2 split.
func _update_bubble() -> void:
	if bubble_rect == null or not is_instance_valid(bubble_rect):
		return
	var hud := bubble_rect.get_parent() as Control
	if hud == null:
		return
	var sz := clampf(minf(hud.size.x, hud.size.y) * 0.3, 110.0, 260.0)
	var k := sz / 260.0
	bubble_rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bubble_rect.size = Vector2(sz, sz)
	bubble_rect.position = Vector2(hud.size.x - sz - 24.0 * k, 24.0 * k)
	if bubble_tag:
		bubble_tag.add_theme_font_size_override("font_size", maxi(12, int(22.0 * k)))
		bubble_tag.position = Vector2(80.0 * k, sz + 2.0)


## VR without a TV machine: the runner gets an OS window on this device.
func _build_flat_window(p) -> void:
	var win := Window.new()
	win.title = "Kitchen Rush - Runner"
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
	cameras.append(cam)
	p.attach_camera(cam)
	var hud_layer := CanvasLayer.new()
	win.add_child(hud_layer)
	var hud := HudScript.new()
	hud.player = p
	hud.main = self
	hud_layer.add_child(hud)
	p.hud = hud


func _assign_joypads() -> void:
	var pads := Input.get_connected_joypads()
	var mode: String = net.mode
	if mode == "client":
		players[1].joy = pads[0] if pads.size() > 0 else -1
		players[2].joy = pads[1] if pads.size() > 1 else -1
	elif mode == "local":
		players[1].joy = pads[0] if pads.size() > 0 else -1
		if not players[0].vr:
			players[0].joy = pads[1] if pads.size() > 1 else -1
	elif not players[0].vr:
		players[0].joy = pads[0] if pads.size() > 0 else -1
	for id in pads:
		print("Joypad %d: %s" % [id, Input.get_joy_name(id)])


## Can TV players drop in on this machine? (Not on the host, nor in VR without a TV machine.)
func drop_in_allowed() -> bool:
	if not ready_to_play or players.size() <= MAX_RUNNERS:
		return false
	return net.mode == "client" or (net.mode == "local" and not players[0].vr)


func _owner_of_joy(device: int):
	for p in players:
		if p.joy == device:
			return p
	return null


## Each controller drives exactly one player (by device id). Unplugging leaves that player idle and,
## after a while, out of the kitchen; plugging back in (or any new controller pressing A) rejoins.
func _on_joy_changed(device: int, connected: bool) -> void:
	if not ready_to_play:
		return
	if not connected:
		var p = _owner_of_joy(device)
		if p != null:
			p.joy = -1
			if p.index >= 1:
				p.lost_joy = device
				p.lost_t = 0.0
			print("Joypad %d unplugged from player %d" % [device, p.index + 1])
		return
	print("Joypad %d connected: %s" % [device, Input.get_joy_name(device)])
	if _owner_of_joy(device) != null:
		return
	for i in range(1, players.size()):
		var r = players[i]
		if r.lost_joy == device and r.joy < 0:
			_give_joy(r, device)
			return
	# Same as before for the first two pads: they belong to P2 (and P3 on the TV / the button chef).
	if players[1].joy < 0 and drop_in_allowed():
		_give_joy(players[1], device)
	elif net.mode == "client" and players[2].joy < 0 and players[2].lost_joy < 0:
		players[2].joy = device
	elif net.mode == "local" and not players[0].vr and players[0].joy < 0:
		players[0].joy = device
	elif net.mode == "host" and not players[0].vr and players[0].joy < 0:
		players[0].joy = device


func _give_joy(p, device: int) -> void:
	p.joy = device
	p.lost_joy = -1
	p.lost_t = 0.0
	print("Joypad %d now drives player %d" % [device, p.index + 1])
	if not p.active:
		request_join(p.index)


## Called by the JoinInput node for every input event. True = consumed (a controller just joined).
func on_join_input(event: InputEvent) -> bool:
	var b := event as InputEventJoypadButton
	if b == null or not b.pressed or not drop_in_allowed() or game_over or get_tree().paused:
		return false
	if b.button_index != JOY_BUTTON_A and b.button_index != JOY_BUTTON_START:
		return false
	if _owner_of_joy(b.device) != null:
		return false
	var target = null
	for i in range(1, players.size()):  # a player waiting for its unplugged controller
		if players[i].lost_joy >= 0 and players[i].joy < 0:
			target = players[i]
			break
	if target == null and players[1].joy < 0:
		target = players[1]
	if target == null and net.mode == "local" and players[0].joy < 0:
		players[0].joy = b.device
		print("Joypad %d now drives the button chef" % b.device)
		return true
	if target == null:
		for i in range(2, players.size()):
			if players[i].joy < 0 and not players[i].active:
				target = players[i]
				break
	if target == null:
		return false
	_give_joy(target, b.device)
	return true


## A local player wants in: the host decides (networked), or just let them in (split screen).
func request_join(i: int) -> void:
	if i < 1 or i >= players.size() or players[i].active:
		return
	if net.mode == "client":
		if join_cd.get(i, 0.0) > 0.0:
			return
		join_cd[i] = 1.0
		net.send_action("join", [], i)
	else:
		_set_runner_active(players[i], true)


func request_leave(i: int) -> void:
	if i < 1 or i >= players.size() or not players[i].active:
		return
	if net.mode == "client":
		net.send_action("leave", [], i)
	else:
		_set_runner_active(players[i], false)


## Host / split screen: a runner joins or leaves the kitchen.
func _set_runner_active(p, on: bool) -> void:
	if p.active == on:
		return
	if not on:
		_drop_carry(p)
	p.set_active(on)
	if on:
		p.global_position = runner_spawn(p.index)
		p.net_target = p.global_position
		p.yaw = PI
	var n := active_runners()
	if on:
		banner("P%d JOINED THE KITCHEN!  (%d runners)" % [p.index + 1, n], 1.5)
		sound("wave", -6.0, 1.3)
	else:
		banner("P%d left the kitchen  (%d runners)" % [p.index + 1, n], 1.5)
	print("Net: player %d %s (%d runners)" % [p.index + 1, "joined" if on else "left", n])
	if not p.remote:
		on_player_activity_changed(p)


## A leaving runner puts down what they carry: plates go back to a counter corner, the extinguisher home.
func _drop_carry(p) -> void:
	if p.carry_kind == "extinguisher":
		ext_holder = -1
	var it = p.carry
	if it != null and is_instance_valid(it):
		if it.is_plate():
			it.holder = -1
			it.global_position = L.OUT_SLOTS[0]
			for sl in L.OUT_SLOTS:
				if item_at(sl, 0.18) == null:
					it.global_position = sl
					break
		else:
			remove_item(it)
	p.carry = null
	p.carry_kind = ""


func active_runners() -> int:
	var n := 0
	for i in range(1, players.size()):
		if players[i].active:
			n += 1
	return maxi(n, 1)


## Tests: make TV player `index` join as if they pressed A.
func debug_join(index: int) -> void:
	_ensure_runners(net.mode)
	if net.mode == "host":
		_set_runner_active(players[index], true)
	else:
		request_join(index)


func on_player_activity_changed(p) -> void:
	if p.active and _wants_view(p):
		_ensure_view(p)
	if p.active and not p.remote and p.index >= 1 and net.mode == "client":
		p.global_position = runner_spawn(p.index)
		p.yaw = PI
	if p.has_meta("view"):
		_layout_views()
	print("Player %d is now %s" % [p.index + 1, "playing" if p.active else "waiting"])


## Client / split screen: waiting players with their own controls join by pressing their button;
## a runner whose controller was unplugged for a while leaves (it rejoins when plugged back in).
func _drop_in_update(delta: float) -> void:
	for k in join_cd.keys():
		join_cd[k] = float(join_cd[k]) - delta
	if not drop_in_allowed() or game_over or get_tree().paused:
		return
	for i in range(1, players.size()):
		var p = players[i]
		if not p.active and (p.joy >= 0 or p.key_set >= 0) and p.any_input():
			request_join(i)
		if p.lost_joy >= 0 and p.joy < 0:
			p.lost_t += delta
			if p.active and p.key_set < 0 and p.lost_t > LEAVE_AFTER_UNPLUG:
				p.lost_t = -INF
				request_leave(i)


# --- Fire, extinguisher, ticket rail ----------------------------------------------

func _build_fire_and_extinguisher() -> void:
	fire_node = Node3D.new()
	add_child(fire_node)
	fire_node.position = L.STOVE + Vector3(0.3, 1.0, 0.0)
	var flames := CPUParticles3D.new()
	flames.amount = 28
	flames.lifetime = 0.7
	flames.direction = Vector3.UP
	flames.spread = 20.0
	flames.initial_velocity_min = 1.0
	flames.initial_velocity_max = 2.2
	flames.gravity = Vector3(0, 1.5, 0)
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 0.18
	flames.scale_amount_min = 0.6
	flames.scale_amount_max = 1.3
	var fm := SphereMesh.new()
	fm.radius = 0.09
	fm.height = 0.18
	fm.radial_segments = 8
	fm.rings = 4
	fm.material = mat(Color(1.0, 0.55, 0.1), 4.0)
	flames.mesh = fm
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.9, 0.3))
	grad.set_color(1, Color(1.0, 0.2, 0.05, 0.0))
	flames.color_ramp = grad
	fire_node.add_child(flames)
	var smoke := CPUParticles3D.new()
	smoke.amount = 12
	smoke.lifetime = 1.8
	smoke.direction = Vector3.UP
	smoke.spread = 25.0
	smoke.initial_velocity_min = 0.6
	smoke.initial_velocity_max = 1.2
	smoke.gravity = Vector3(0, 0.3, 0)
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 2.5
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	sm.radial_segments = 8
	sm.rings = 4
	sm.material = mat(Color(0.45, 0.45, 0.5))
	smoke.mesh = sm
	smoke.position.y = 0.5
	fire_node.add_child(smoke)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.15)
	light.light_energy = 2.5
	light.omni_range = 4.0
	fire_node.add_child(light)
	fire_node.visible = false
	ext_node = Node3D.new()
	add_child(ext_node)
	var can := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.08
	cm.bottom_radius = 0.08
	cm.height = 0.42
	cm.radial_segments = 12
	cm.rings = 1
	can.mesh = cm
	can.material_override = mat(Color(0.95, 0.15, 0.12))
	ext_node.add_child(can)
	var nozzle := MeshInstance3D.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(0.04, 0.04, 0.2)
	nozzle.mesh = nm
	nozzle.material_override = mat(Color(0.15, 0.15, 0.15))
	nozzle.position = Vector3(0, 0.2, -0.1)
	ext_node.add_child(nozzle)


## Order tickets hanging in front of the chef (one per waiting customer, in window order). Each shows
## the dish name, the customer's colour, the ingredients as little 3D models on a ledge (a green ring =
## already on the plate, orange = needs chopping) and a patience bar.
func _build_tickets() -> void:
	var rail := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(2.5, 0.03, 0.03)
	rail.mesh = rm
	rail.material_override = mat(Color(0.75, 0.75, 0.8))
	rail.position = Vector3(0, 2.0, -0.62)
	add_child(rail)
	for i in MAX_CUSTOMERS:
		var root := Node3D.new()
		root.position = Vector3(-0.9 + i * 0.6, 1.75, -0.62)
		root.rotation.x = 0.12  # tilted towards the chef's eyes
		add_child(root)
		var paper := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.54, 0.46)
		paper.mesh = q
		paper.material_override = mat(Color(1.0, 0.98, 0.9))
		paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(paper)
		var swatch := MeshInstance3D.new()
		var sw := CylinderMesh.new()
		sw.top_radius = 0.04
		sw.bottom_radius = 0.04
		sw.height = 0.01
		sw.radial_segments = 12
		sw.rings = 1
		swatch.mesh = sw
		swatch.rotation.x = PI / 2.0
		swatch.position = Vector3(-0.21, 0.15, 0.01)
		var sw_mat := StandardMaterial3D.new()
		swatch.material_override = sw_mat
		root.add_child(swatch)
		var label := Label3D.new()
		label.font_size = 64
		label.outline_size = 0
		label.modulate = Color(0.2, 0.12, 0.1)
		label.pixel_size = 0.0016
		label.double_sided = false
		label.position = Vector3(0.03, 0.15, 0.012)
		root.add_child(label)
		var ledge := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.52, 0.015, 0.12)
		ledge.mesh = lb
		ledge.material_override = mat(Color(0.85, 0.65, 0.4))
		ledge.position = Vector3(0, -0.13, 0.06)
		root.add_child(ledge)
		var icons := Node3D.new()
		icons.position = Vector3(0, -0.122, 0.06)
		root.add_child(icons)
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.48, 0.035, 0.01)
		bar.mesh = bm
		var bar_mat := StandardMaterial3D.new()
		bar_mat.albedo_color = Color(0.3, 1.0, 0.4)
		bar_mat.emission_enabled = true
		bar_mat.emission = Color(0.3, 1.0, 0.4)
		bar.material_override = bar_mat
		bar.position = Vector3(0, -0.2, 0.01)
		root.add_child(bar)
		tickets.append([root, label, bar, bar_mat, swatch, sw_mat, icons, ""])


## Rebuilds a ticket's ingredient models when its order changes.
func _ticket_icons(t: Array, recipe: String) -> void:
	var icons: Node3D = t[6]
	for c in icons.get_children():
		c.queue_free()
	var items: Array = RECIPES.get(recipe, [])
	for j in items.size():
		var slot := Node3D.new()
		slot.position = Vector3((j - (items.size() - 1) * 0.5) * 0.125, 0.0, 0.0)
		icons.add_child(slot)
		var it := ItemScript.new()
		it.main = self
		it.kind = items[j]
		it.ghost = true
		it.scale = Vector3.ONE * 0.8
		slot.add_child(it)
		it.remove_from_group("kr_items")
		it.set_process(false)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.045
		tm.outer_radius = 0.058
		tm.rings = 12
		tm.ring_segments = 4
		ring.mesh = tm
		ring.name = "Ring"
		ring.position.y = 0.002
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		slot.add_child(ring)
	t[7] = recipe


## The plate (if any) that's being built for this recipe: its contents count as ticked off.
func _plate_for(recipe: String):
	for h in L.PLATE_HOME.size():
		var p = _home_plate(h)
		if p == null or p.recipe != "" or p.contents.is_empty():
			continue
		var ok := true
		for k in p.contents:
			if not RECIPES[recipe].has(k):
				ok = false
		if ok:
			return p
	return null


func _update_tickets() -> void:
	var by_slot := {}
	for c in get_tree().get_nodes_in_group("kr_customers"):
		if c.waiting():
			by_slot[c.slot] = c
	for i in tickets.size():
		var t: Array = tickets[i]
		var root: Node3D = t[0]
		var c = by_slot.get(i)
		root.visible = c != null
		if c == null:
			continue
		if t[7] != c.recipe:
			_ticket_icons(t, c.recipe)
		var label: Label3D = t[1]
		label.text = c.recipe + ("  VIP!" if c.ctype == "critic" else "")
		label.modulate = Color(0.2, 0.12, 0.1) if c.frac > 0.3 else Color(0.85, 0.15, 0.1)
		var sw_mat: StandardMaterial3D = t[5]
		if c.body_mat:
			sw_mat.albedo_color = c.body_mat.albedo_color
		var bar: MeshInstance3D = t[2]
		bar.scale.x = maxf(c.frac, 0.01)
		var bm: StandardMaterial3D = t[3]
		var col := Color(1.0, 0.25, 0.2).lerp(Color(0.3, 1.0, 0.4), clampf(c.frac * 1.6 - 0.2, 0.0, 1.0))
		bm.albedo_color = col
		bm.emission = col
		root.position.y = 1.75 + (sin(clock * 20.0) * 0.01 if c.frac < 0.25 else 0.0)
		# Tick off what's already on a plate; orange rings for things that still need chopping.
		var plate = _plate_for(c.recipe)
		var icons: Node3D = t[6]
		var items: Array = RECIPES.get(c.recipe, [])
		for j in mini(items.size(), icons.get_child_count()):
			var ring := icons.get_child(j).get_node_or_null("Ring") as MeshInstance3D
			if ring == null:
				continue
			var k: String = items[j]
			if plate != null and plate.contents.has(k):
				ring.visible = true
				ring.material_override = mat(Color(0.3, 1.0, 0.4), 1.5)
			elif ItemScript.chops_needed(k) > 0:
				ring.visible = true
				ring.material_override = mat(Color(1.0, 0.6, 0.2), 0.8)
			else:
				ring.visible = false


# --- Main loop -------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if not has_meta("signs_fixed"):  # hot-reload fix for signs built before the kitchen.gd change
		set_meta("signs_fixed", true)
		for c in get_children():
			if c is Label3D and (c.text == "FRIDGE" or c.text == "PANTRY"):
				c.rotation.y = PI / 2.0
			elif c is Label3D and c.text.begins_with("PASS"):
				c.billboard = BaseMaterial3D.BILLBOARD_DISABLED
				c.font_size = 22
				c.position.y = L.COUNTER_TOP + 0.012
				c.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	clock += delta
	if players.size() <= MAX_RUNNERS:
		_ensure_runners(net.mode)
	if get_node_or_null("JoinInput") == null:
		var ji := JoinInputScript.new()
		ji.name = "JoinInput"
		ji.main = self
		add_child(ji)
	_update_bubble()
	if net.mode != "host":
		_drop_in_update(delta)
	if music == null:
		music = MusicScript.new()
		add_child(music)
	music.play_track(1 if rush_t > 0.0 else maxi(shift - 1, 0))
	_update_tickets()
	_update_fire_visuals()
	_animate_kitchen(delta)
	_update_guides()
	_update_vr_center()
	if ghost_cam:
		ghost_cam.global_transform = players[0].head_t
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_update_hud()
	if net.mode == "client":
		if game_over:
			game_over_t += delta
			if game_over_t > 1.5 and _restart_pressed():
				game_over_t = 0.0
				net.send_action("restart", [])
		return
	if game_over:
		game_over_t += delta
		var vr_restart: bool = players[0].vr and players[0].hand_r.get_float("trigger") > 0.6
		if game_over_t > 2.0 and (_restart_pressed() or vr_restart):
			get_tree().reload_current_scene()
		return
	if net.mode == "host" and not net.connected:
		_ensure_plates()
		chef_task = _compute_chef_task()
		return
	_host_update(delta)


func _host_update(delta: float) -> void:
	_ensure_plates()
	_move_finished_plates()
	chef_task = _compute_chef_task()
	rush_t = maxf(0.0, rush_t - delta)
	if in_break:
		break_t -= delta
		if break_t <= 0.0:
			_start_shift()
		return
	spawn_t -= delta
	var waiting := _waiting_customers()
	if waiting.is_empty():
		spawn_t = minf(spawn_t, 1.5)
	if spawn_t <= 0.0 and waiting.size() < MAX_CUSTOMERS:
		_spawn_customer()
		spawn_t = _spawn_interval() * randf_range(0.8, 1.2) * (0.35 if rush_t > 0.0 else 1.0)
	# Dinner rush: from the first dinner on, halfway through the shift a crowd turns up (double coins!).
	if shift >= 3 and shift % 3 == 0 and not rush_done and served_shift >= shift_target() / 3:
		rush_done = true
		rush_t = RUSH_TIME
		spawn_t = 0.5
		banner("DINNER RUSH!\nA crowd of hungry customers - DOUBLE COINS for %d seconds!" % int(RUSH_TIME), 2.5)
		sound("rush", 0.0, 1.0)
		print("Dinner rush!")
	if combo > 0 and clock - last_serve_time > COMBO_WINDOW:
		combo = 0
	if shift >= 2:
		if not fire_on:
			fire_t -= delta
			if fire_t <= 0.0:
				_start_fire()
		raccoon_t -= delta
		if raccoon_t <= 0.0 and not raccoon.active():
			raccoon_t = (randf_range(30.0, 50.0) - shift * 2.0) / _chaos_scale()
			raccoon.start()
			banner("A cheeky RACCOON is sneaking in!\nRunners: bump into it to scare it off!", 2.5)
			sound("spit", 0.0, 0.7)


## Extra runners beyond two make the kitchen busier (the chef is still the bottleneck, so only modestly).
func _extra_runners() -> int:
	return maxi(0, active_runners() - 2)


func shift_target() -> int:
	return 2 + shift * 2 + int((_extra_runners() + 1) / 2.0)


func _spawn_interval() -> float:
	return maxf(4.0, (15.0 - shift * 2.0) / (1.0 + 0.1 * _extra_runners()))


## More hands, more trouble: fires burn hotter and come back sooner.
func _chaos_scale() -> float:
	return 1.0 + 0.12 * _extra_runners()


func _patience() -> float:
	return maxf(35.0, 85.0 - shift * 8.0)


func recipe_items(r: String) -> Array:
	return RECIPES.get(r, [])


func unlocked_recipes() -> Array:
	var out := []
	for i in mini(maxi(shift, 1), UNLOCKS.size()):
		out.append_array(UNLOCKS[i])
	return out


## "DAY 1 · LUNCH" etc.
func shift_name(sh: int = -1) -> String:
	if sh < 0:
		sh = shift
	sh = maxi(sh, 1)
	return "DAY %d  ·  %s" % [(sh - 1) / 3 + 1, SHIFT_NAMES[(sh - 1) % 3]]


func _start_shift() -> void:
	shift += 1
	served_shift = 0
	in_break = false
	spawn_t = 0.5
	angry_at_start = angry
	frac_sum = 0.0
	rush_done = false
	critic_done = false
	fire_t = randf_range(25.0, 40.0) / _chaos_scale()
	raccoon_t = randf_range(15.0, 30.0) / _chaos_scale()
	print("Shift %d started (%s)" % [shift, shift_name()])
	for it in all_items():  # practice vegetables still lying about make room for real orders
		if it.has_meta("practice") and it.holder == -1:
			burst(it.global_position, Color(1.0, 1.0, 1.0), 8, 0.04)
			remove_item(it)
	var extra := ""
	if shift - 1 < UNLOCKS.size() and shift > 1:
		extra = "\nNEW RECIPE: " + ", ".join(PackedStringArray(UNLOCKS[shift - 1]))
	if shift == 2:
		extra += "\nWatch out for fires and raccoons!"
	if shift % 3 == 0:
		extra += "\nDinner time gets BUSY…"
	if active_runners() > 2:
		extra += "\n%d runners: busier kitchen!" % active_runners()
	banner("%s\nServe %d orders!%s" % [shift_name(), shift_target(), extra], 3.0)
	sound("wave")
	sound("ding", -6.0, 1.0)
	_update_menu_board()


func _end_shift() -> void:
	in_break = true
	break_t = 7.0
	rush_t = 0.0
	var angry_now := angry - angry_at_start
	var avg := frac_sum / maxf(1.0, float(served_shift))
	var n := 1
	if angry_now == 0 and avg >= 0.35:
		n = 3
	elif angry_now <= 1:
		n = 2
	stars.append(n)
	coins += n * 10
	var total := 0
	for st in stars:
		total += int(st)
	print("Shift %d complete: coins %d, angry %d, %d stars (avg patience left %.2f)" % [shift, coins, angry, n, avg])
	var praise: String = ["Phew, we made it!", "Good job, team!", "PERFECT SERVICE!"][n - 1]
	var next := "Next: %s - hungrier customers!" % SHIFT_NAMES[shift % 3]
	if shift % 3 == 0:
		next = "DAY %d DONE! Total stars: %d\nTomorrow the customers are even hungrier!" % [(shift - 1) / 3 + 1, total]
		_show_stats("END OF DAY %d - CREW AWARDS" % ((shift - 1) / 3 + 1), 7.0)
	banner("%s COMPLETE!\n%d STAR%s  -  %s  (+%d coins)\n%s" % [SHIFT_NAMES[(shift - 1) % 3], n, "S" if n > 1 else "", praise, n * 10, next], 5.0)
	show_stars(n)
	net.event("stars", [n])
	sound("clear")
	sound("cheer", -4.0)
	if fire_on:
		fire_on = false
		ext_holder = -1
		for i in range(1, players.size()):
			if players[i].carry_kind == "extinguisher":
				players[i].carry_kind = ""


func _waiting_customers() -> Array:
	var out := []
	for c in get_tree().get_nodes_in_group("kr_customers"):
		if c.waiting():
			out.append(c)
	return out


func _spawn_customer() -> void:
	var taken := {}
	for c in _waiting_customers():
		taken[c.slot] = true
	var free := []
	for i in MAX_CUSTOMERS:
		if not taken.has(i):
			free.append(i)
	if free.is_empty():
		return
	var c := CustomerScript.new()
	c.main = self
	c.net_id = next_net_id()
	c.slot = free.pick_random()
	c.recipe = unlocked_recipes().pick_random()
	# A finished plate that nobody is waiting for (its customer left)? Usually send someone who wants it.
	var wanted := []
	for w in _waiting_customers():
		wanted.append(w.recipe)
	for it in all_items():
		if it.is_plate() and it.recipe != "":
			if wanted.has(it.recipe):
				wanted.erase(it.recipe)
			elif randf() < 0.75:
				c.recipe = it.recipe
				break
	c.color_index = randi() % CustomerScript.COLORS.size()
	# Personalities: the very first customer is a patient granny who wants a simple toastie.
	var types := ["kid", "granny", "robot", "pirate", "alien", "knight"]
	c.ctype = types.pick_random()
	customers_spawned += 1
	if customers_spawned == 1 and served_total == 0:
		c.ctype = "granny"
		c.recipe = "TOASTIE"
	elif shift >= 2 and not critic_done and served_shift >= 1 and randf() < 0.35:
		critic_done = true
		c.ctype = "critic"
		banner("A VIP FOOD CRITIC is here!\nServe the %s fast for a big tip!" % c.recipe, 2.5)
		sound("ding", -2.0, 1.3)
	c.max_patience = _patience() * float(CustomerScript.TYPES[c.ctype][0])
	c.patience = c.max_patience
	c.position = Vector3(10.5, 0.0, L.CUSTOMER_Z[c.slot] + (2.5 if c.slot >= 2 else -2.5))
	add_child(c)
	sound("wave", -10.0, 1.6)


func on_customer_angry(c) -> void:
	angry += 1
	combo = 0
	sound("splat", -2.0, 0.8)
	print("A customer left angry (%d/%d)" % [angry, MAX_ANGRY])
	sound("hurt", 0.0, 0.8)
	popup(c.global_position + Vector3.UP * 2.0, "HMPH!  (%d/%d)" % [angry, MAX_ANGRY], Color(1.0, 0.4, 0.3))
	if angry >= MAX_ANGRY:
		_game_over()


func _game_over() -> void:
	game_over = true
	game_over_t = 0.0
	sound("gameover")
	print("Game over: shift %d, coins %d, served %d" % [shift, coins, served_total])
	var cfg := ConfigFile.new()
	cfg.load("user://kitchen_rush_best.cfg")
	var best: int = cfg.get_value("best", "coins", 0)
	var best_line := "Best: %d coins" % best
	if coins > best:
		best_line = "NEW BEST!  (previous %d)" % best
		cfg.set_value("best", "coins", coins)
		cfg.save("user://kitchen_rush_best.cfg")
	var total := 0
	for st in stars:
		total += int(st)
	banner("KITCHEN CLOSED!\nToo many hungry customers left\n%s  ·  %d served  ·  %d coins  ·  %d stars\n%s\nPress A / Enter (VR: trigger) to cook again" % [shift_name(), served_total, coins, total, best_line], 0.0)
	_show_stats("CREW AWARDS", 0.0)


func _restart_pressed() -> bool:
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_R):
		return true
	for id in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(id, JOY_BUTTON_A):
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


# --- Items -------------------------------------------------------------------------

func all_items() -> Array:
	return get_tree().get_nodes_in_group("kr_items")


func spawn_item(kind: String, pos: Vector3, holder: int):
	var it := ItemScript.new()
	it.main = self
	it.kind = kind
	it.net_id = next_net_id()
	it.holder = holder
	it.position = pos
	add_child(it)
	return it


func remove_item(it) -> void:
	if it == null or not is_instance_valid(it):
		return
	it.holder = -2
	it.remove_from_group("kr_items")
	it.queue_free()


## The item resting closest to pos (within r, horizontally), or null.
func item_at(pos: Vector3, r: float):
	var best = null
	var best_d := r
	for it in all_items():
		if it.holder != -1:
			continue
		var d := flat_dist(it.global_position, pos)
		if d < best_d and absf(it.global_position.y - pos.y) < 0.3:
			best_d = d
			best = it
	return best


func _home_plate(h: int):
	for it in all_items():
		if it.is_plate() and it.home == h:
			return it
	return null


func _ensure_plates() -> void:
	for h in L.PLATE_HOME.size():
		if _home_plate(h) == null and item_at(L.PLATE_HOME[h], 0.2) == null:
			var p = spawn_item("plate", L.PLATE_HOME[h], -1)
			p.home = h


## Finished plates slide to a free corner of the counter, where the runners can pick them up.
func _move_finished_plates() -> void:
	for it in all_items():
		if not it.is_plate() or it.recipe == "" or it.holder != -1:
			continue
		var at_out := false
		for s in L.OUT_SLOTS:
			if flat_dist(it.global_position, s) < 0.05:
				at_out = true
		if at_out:
			continue
		for s in L.OUT_SLOTS:
			if item_at(s, 0.18) == null:
				burst(it.global_position + Vector3.UP * 0.1, Color(1.0, 0.85, 0.3), 10, 0.04)
				it.global_position = s
				break


func chef_pick_target(point: Vector3, r: float):
	var best = null
	var best_d := r
	for it in all_items():
		if it.holder != -1:
			continue
		var d: float = (it.global_position + Vector3.UP * 0.04).distance_to(point)
		if d < best_d:
			best_d = d
			best = it
	return best


func chef_grab(it) -> void:
	it.holder = 0
	sfx_local("pickup", -10.0, 1.3)


## The chef let go of an item at pos. Returns false if a button chef should keep holding it.
func chef_release(it, pos: Vector3, buttons: bool) -> bool:
	var top := L.COUNTER_TOP
	if flat_dist(pos, L.TRASH) < 0.17 and pos.y < top + 0.5:
		_trash(it)
		return true
	if it.is_plate():
		it.holder = -1
		if it.home >= 0:
			it.global_position = L.PLATE_HOME[it.home]
		else:
			it.global_position = _counter_spot(pos)
		return true
	var plate = null
	for p in all_items():
		if p.is_plate() and p.holder == -1 and flat_dist(p.global_position, pos) < 0.2 and pos.y < top + 0.5:
			plate = p
	if plate != null:
		var why := plate_accepts(plate, it)
		if why == "":
			add_to_plate(plate, it)
			return true
		popup(plate.global_position + Vector3.UP * 0.3, why, Color(1.0, 0.6, 0.4))
		sfx_local("hit", -8.0, 0.6)
		if buttons:
			return false
		pos += Vector3(0.0, 0.0, -0.2)
	var target := pos if buttons else _counter_spot(pos)
	if buttons:
		var other = item_at(target, 0.12)
		if other != null and other != it:
			popup(target + Vector3.UP * 0.3, "No room!", Color(1.0, 0.6, 0.4))
			return false
	it.holder = -1
	it.global_position = target
	it.rotation = Vector3.ZERO
	sfx_local("dash", -16.0, 1.8)
	return true


## Where an item dropped at pos ends up: on the counter top, snapped to a nearby spot.
func _counter_spot(pos: Vector3) -> Vector3:
	var x := clampf(pos.x, -L.COUNTER_HALF.x + 0.07, L.COUNTER_HALF.x - 0.07)
	var z := clampf(pos.z, -L.COUNTER_HALF.y + 0.06, L.COUNTER_HALF.y - 0.06)
	var p := Vector3(x, L.COUNTER_TOP, z)
	var spots: Array = L.PASS_SLOTS + [L.BOARD] + L.OUT_SLOTS
	for s in spots:
		if flat_dist(p, s) < 0.12:
			return s
	return p


func _trash(it) -> void:
	sound("hit", -4.0, 0.5)
	burst(L.TRASH + Vector3.UP * 0.1, Color(0.6, 0.6, 0.6), 8, 0.04)
	if it.is_plate() and it.home >= 0:
		it.contents = []
		it.recipe = ""
		it.holder = -1
		it.global_position = L.PLATE_HOME[it.home]
		return
	remove_item(it)


## "" if the ingredient can go on the plate, otherwise why not.
func plate_accepts(plate, it) -> String:
	if plate.recipe != "":
		return "This dish is finished!"
	if not it.is_ready():
		return "Chop it first!"
	if plate.contents.has(it.kind):
		return "Already has %s" % ItemScript.display_name(it.kind)
	var c: Array = plate.contents + [it.kind]
	for r in unlocked_recipes():
		var ok := true
		for k in c:
			if not RECIPES[r].has(k):
				ok = false
		if ok:
			return ""
	return "No recipe needs that here!"


func add_to_plate(plate, it) -> void:
	plate.contents = plate.contents + [it.kind]
	remove_item(it)
	sound("pickup", -6.0, 0.9 + plate.contents.size() * 0.1)
	for r in unlocked_recipes():
		var want: Array = RECIPES[r].duplicate()
		var have: Array = plate.contents.duplicate()
		want.sort()
		have.sort()
		if want == have:
			plate.recipe = r
			plate.home = -1
			stats[0].dishes += 1
			print("Dish ready: %s" % r)
			sound("revive", 0.0, 1.2)
			ring_bell()
			popup(plate.global_position + Vector3.UP * 0.35, "DING! %s" % r, Color(1.0, 0.9, 0.3))
			burst(plate.global_position + Vector3.UP * 0.15, Color(1.0, 0.85, 0.3), 18, 0.05)
			if players[0].vr:
				players[0].hand_l.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.15, 0.0)
			return


## Chop an ingredient once. Returns true if it was chopped.
func chop(it) -> bool:
	if fire_on:
		popup(it.global_position + Vector3.UP * 0.3, "Too smoky! Put out the fire!", Color(1.0, 0.5, 0.3))
		sfx_local("hit", -10.0, 0.5)
		it.chop_cd = 0.4
		return false
	if not it.needs_chop() or it.chop_cd > 0.0:
		return false
	it.chops += 1
	it.chop_cd = 0.2
	it.squash = 1.0
	stats[0].chops += 1
	sound("chop", 0.0, 0.9 + it.chops * 0.12)
	burst(it.global_position + Vector3.UP * 0.06, ItemScript.color_of(it.kind), 12, 0.035)
	if it.is_ready():
		popup(it.global_position + Vector3.UP * 0.25, "CHOPPED!", Color(0.6, 1.0, 0.5))
		sound("pickup", -8.0, 1.4)
	return true


func item_label(it) -> String:
	if it.is_plate():
		if it.recipe != "":
			return it.recipe + " (finished)"
		return "PLATE" if it.contents.is_empty() else "PLATE with " + _names(it.contents)
	var n := ItemScript.display_name(it.kind)
	if it.needs_chop():
		return "%s (chop %d/%d)" % [n, it.chops, ItemScript.chops_needed(it.kind)]
	return n + (" (chopped)" if ItemScript.chops_needed(it.kind) > 0 else "")


func _names(kinds: Array) -> String:
	var parts: Array[String] = []
	for k in kinds:
		parts.append(ItemScript.display_name(k))
	return ", ".join(parts)


# --- Runners -----------------------------------------------------------------------

## What pressing the button would do for runner p right now: {act, text, ...}. Works on both machines.
func resolve(p) -> Dictionary:
	var pos: Vector3 = p.global_position
	var c: String = p.carry_kind
	if c == "":
		var plate = null
		var best := 1.8
		for it in all_items():
			if it.is_plate() and it.recipe != "" and it.holder == -1:
				var d := flat_dist(pos, it.global_position)
				if d < best:
					best = d
					plate = it
		if plate != null:
			return {"act": "take_plate", "item": plate, "text": "Pick up the %s" % plate.recipe}
		if fire_on and ext_holder == -1 and flat_dist(pos, L.EXT_POS) < 1.8:
			return {"act": "take_ext", "text": "Grab the FIRE EXTINGUISHER"}
		var src := ""
		var best_s := 1.8
		for s in L.SOURCES:
			var d2 := flat_dist(pos, s[1])
			if d2 < best_s:
				best_s = d2
				src = s[0]
		if src != "":
			return {"act": "take", "kind": src, "text": "Pick up %s" % ItemScript.display_name(src)}
		if fire_on:
			return {"text": "FIRE! Get the extinguisher (back wall, right of the door)"}
		return {}
	if c == "extinguisher":
		if fire_on and flat_dist(pos, L.STOVE) < 2.4:
			return {"act": "spray", "text": "SPRAY the fire!"}
		if flat_dist(pos, L.EXT_POS) < 1.8:
			return {"act": "put_ext", "text": "Hang up the extinguisher"}
		return {"text": "Run to the STOVE and spray!" if fire_on else "Put it back on its stand"}
	if c.begins_with("plate:"):
		var r := c.substr(6)
		var best_c = null
		var near = null
		for cu in get_tree().get_nodes_in_group("kr_customers"):
			if not cu.waiting() or flat_dist(pos, cu.serve_point()) > 2.0:
				continue
			near = cu
			if cu.recipe == r and (best_c == null or cu.frac < best_c.frac):
				best_c = cu
		if best_c != null:
			return {"act": "serve", "cust": best_c, "text": "Serve the %s!" % r}
		if near != null:
			return {"text": "This one wants %s - find who ordered %s" % [near.recipe, r]}
		return {"text": "Take the %s to the SERVING WINDOW" % r}
	var nm := ItemScript.display_name(c)
	if pos.z < 0.0 and pos.z > -2.2 and absf(pos.x) < 1.8:
		var slot := free_pass_slot(pos)
		if slot >= 0:
			return {"act": "drop", "slot": slot, "text": "Put the %s on the PASS" % nm}
		return {"text": "The pass is full - the chef needs to catch up!"}
	for s in L.SOURCES:
		if s[0] == c and flat_dist(pos, s[1]) < 1.8:
			return {"act": "return", "text": "Put the %s back" % nm}
	return {"text": "Bring the %s to the PASS (front of the counter)" % nm}


func free_pass_slot(near: Vector3) -> int:
	var best := -1
	var best_d := INF
	for i in L.PASS_SLOTS.size():
		var s: Vector3 = L.PASS_SLOTS[i]
		if item_at(s, 0.15) != null:
			continue
		var d := absf(s.x - near.x)
		if d < best_d:
			best_d = d
			best = i
	return best


## Host: runner p pressed their button.
func runner_use(p) -> void:
	if input_blocked():
		return
	var r := resolve(p)
	var act: String = r.get("act", "")
	match act:
		"take_plate":
			var it = r["item"]
			it.holder = p.index
			p.carry = it
			p.carry_kind = "plate:" + it.recipe
			sound("pickup", -4.0, 1.2)
		"take_ext":
			ext_holder = p.index
			p.carry_kind = "extinguisher"
			sound("pickup", -4.0, 0.7)
		"take":
			var kind: String = r["kind"]
			p.carry = spawn_item(kind, p.carry_point(), p.index)
			p.carry_kind = kind
			stats[p.index].fetched += 1
			sound("pickup", -6.0, 1.0)
		"spray":
			_spray(p)
		"put_ext":
			ext_holder = -1
			p.carry_kind = ""
			sound("dash", -8.0, 0.8)
		"serve":
			_serve(p, r["cust"])
		"drop":
			var slot: int = r["slot"]
			var it2 = p.carry
			if it2 != null and is_instance_valid(it2):
				it2.holder = -1
				it2.global_position = L.PASS_SLOTS[slot]
				it2.rotation = Vector3.ZERO
			p.carry = null
			p.carry_kind = ""
			sound("dash", -6.0, 1.3)
			burst(L.PASS_SLOTS[slot] + Vector3.UP * 0.05, Color(1.0, 0.9, 0.5), 6, 0.03)
		"return":
			remove_item(p.carry)
			p.carry = null
			p.carry_kind = ""
			sound("dash", -8.0, 0.9)
		_:
			sound("hit", -14.0, 0.7)


func _serve(p, cust) -> void:
	remove_item(p.carry)
	p.carry = null
	p.carry_kind = ""
	cust.serve()
	served_shift += 1
	served_total += 1
	combo = combo + 1 if clock - last_serve_time < COMBO_WINDOW else 1
	last_serve_time = clock
	var tip_mult := float(CustomerScript.TYPES.get(cust.ctype, [1.0, 1.0])[1])
	var tip := int(round(10.0 * cust.frac * tip_mult))
	var mult := 1.0 + minf(combo - 1, 4) * 0.5
	if rush_t > 0.0:
		mult *= 2.0
	var gain := int(round((10 + tip) * mult))
	coins += gain
	frac_sum += cust.frac
	stats[p.index].served += 1
	print("Served %s to a %s: +%d coins (combo %d), total %d" % [cust.recipe, cust.ctype, gain, combo, coins])
	var text := "+%d coins" % gain
	if combo > 1:
		text += "\nCOMBO x%d!" % combo
	if rush_t > 0.0:
		text += "\nRUSH x2!"
	if cust.ctype == "critic":
		coins += 25
		text += "\nTHE CRITIC LOVED IT! +25"
		sound("cheer", 0.0, 1.1)
	sound("coin", -4.0, 1.0)
	popup(cust.global_position + Vector3(-0.6, 2.3, 0), text, Color(1.0, 0.85, 0.2))
	sound("clear", -2.0, 1.0 + minf(combo, 5) * 0.08)
	burst(cust.global_position + Vector3.UP * 1.6, Color(1.0, 0.5, 0.8), 20, 0.06)
	burst(cust.global_position + Vector3.UP * 1.6, Color(0.5, 0.9, 1.0), 14, 0.06)
	if served_shift >= shift_target() and not in_break:
		_end_shift()


# --- Chaos: fire and raccoon ------------------------------------------------------------

func _start_fire() -> void:
	fire_on = true
	fire_hp = 3 + int((_extra_runners() + 1) / 2.0)
	print("Fire on the stove!")
	sound("big_kill", -2.0, 0.8)
	banner("FIRE ON THE STOVE!\nRunners: grab the extinguisher and spray it!\n(The chef can't chop in the smoke)", 3.0)


func _spray(p) -> void:
	fire_hp -= 1
	stats[p.index].sprays += 1
	sound("dash", 0.0, 0.6)
	burst(L.STOVE + Vector3(0.3, 1.1, 0.0), Color(0.95, 0.97, 1.0), 24, 0.1)
	if fire_hp <= 0:
		fire_on = false
		ext_holder = -1
		p.carry_kind = ""
		coins += 5
		fire_t = (randf_range(35.0, 55.0) - shift * 2.0) / _chaos_scale()
		print("Fire is out")
		popup(L.STOVE + Vector3.UP * 1.6, "FIRE OUT!  +5", Color(0.6, 0.9, 1.0))
		sound("revive")
		banner("Phew! Fire's out. Back to cooking!", 1.5)


func _update_fire_visuals() -> void:
	fire_node.visible = fire_on
	if fire_on:
		fire_node.scale = Vector3.ONE * (1.0 + 0.1 * sin(clock * 9.0))
	if ext_holder >= 1 and ext_holder < players.size():
		var p = players[ext_holder]
		ext_node.global_position = p.carry_point() + Vector3.UP * 0.05
		ext_node.rotation.y = p.yaw
	else:
		ext_node.global_position = L.EXT_POS + Vector3(0, 0.82, 0)
		ext_node.rotation.y = 0.0


# --- Juice, guidance and the lively kitchen ------------------------------------------------

## While the VR chef waits for the TV runners: two vegetables to practise chopping on.
func _practice_veg() -> void:
	for k in [["tomato", 1], ["cucumber", 2]]:
		var it = spawn_item(k[0], L.PASS_SLOTS[k[1]], -1)
		it.set_meta("practice", true)


## Big stars pop up over the counter at the end of a shift (seen by the chef and the runners).
func show_stars(n: int) -> void:
	for i in 3:
		var star := MeshInstance3D.new()
		star.mesh = _star_mesh()
		var m := StandardMaterial3D.new()
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(1.0, 0.82, 0.2) if i < n else Color(0.35, 0.35, 0.4)
		if i < n:
			m.emission_enabled = true
			m.emission = Color(1.0, 0.75, 0.2)
			m.emission_energy_multiplier = 1.5
		star.material_override = m
		star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(star)
		star.position = Vector3(-0.6 + i * 0.6, 2.45, -0.55)
		star.scale = Vector3.ONE * 0.01
		var tw := star.create_tween()
		tw.tween_interval(0.35 * i)
		tw.tween_callback(func() -> void:
			if i < n:
				sfx_local("star", -2.0, 1.0 + i * 0.15)
				burst(star.global_position, Color(1.0, 0.85, 0.3), 14, 0.05)
			else:
				sfx_local("hit", -10.0, 0.6))
		tw.tween_property(star, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(star, "rotation:y", TAU, 1.2).set_trans(Tween.TRANS_CUBIC)
		tw.tween_interval(2.5)
		tw.tween_property(star, "scale", Vector3.ONE * 0.01, 0.3)
		tw.tween_callback(star.queue_free)


func _star_mesh() -> ArrayMesh:
	if has_meta("kr_star_mesh"):
		return get_meta("kr_star_mesh")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	for k in 10:
		var r := 0.22 if k % 2 == 0 else 0.09
		var a := PI / 2.0 + k * TAU / 10.0
		pts.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
	for k in 10:
		st.set_normal(Vector3.BACK)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(pts[k])
		st.add_vertex(pts[(k + 1) % 10])
	var mesh := st.commit()
	set_meta("kr_star_mesh", mesh)
	return mesh


## DING! The service bell on the counter wobbles when a dish is ready.
func ring_bell() -> void:
	bell_t = 1.0
	sound("ding", -2.0, 1.0)
	if net:
		net.event("bell", [])


func _animate_kitchen(delta: float) -> void:
	var fan: Node3D = parts.get("fan")
	if fan:
		fan.rotation.y += delta * (2.5 if not rush_t > 0.0 else 6.0)
	var bell: Node3D = parts.get("bell")
	if bell:
		bell_t = maxf(0.0, bell_t - delta * 1.5)
		bell.rotation.z = sin(clock * 40.0) * 0.25 * bell_t
		bell.scale = Vector3.ONE * (1.0 + 0.2 * bell_t)
	var open_sign: Label3D = parts.get("open_sign")
	if open_sign:
		open_sign.modulate.a = 0.85 + 0.15 * sin(clock * 3.0)
	# Chickens wander and peck in the garden.
	var chickens: Array = parts.get("chickens", [])
	while chicken_goals.size() < chickens.size():
		chicken_goals.append(Vector3.ZERO)
	for i in chickens.size():
		var ch: Node3D = chickens[i]
		var goal: Vector3 = chicken_goals[i]
		var side := -1.0 if i == 0 else 1.0
		if goal == Vector3.ZERO or ch.position.distance_to(goal) < 0.2:
			chicken_goals[i] = Vector3(side * randf_range(5.2, 8.3), 0.0, randf_range(-10.8, -6.8))
			goal = chicken_goals[i]
		var to := goal - ch.position
		var pecking := fmod(clock + i * 2.3, 5.0) < 1.6
		var head: Node3D = ch.get_node_or_null("Head")
		if pecking:
			if head:
				head.position = Vector3(0, 0.4 + absf(sin(clock * 12.0)) * 0.12, -0.26)
		else:
			ch.position += to.normalized() * delta * 0.6
			ch.rotation.y = lerp_angle(ch.rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-6.0 * delta))
			ch.position.y = absf(sin(clock * 10.0)) * 0.03
			if head:
				head.position = Vector3(0, 0.55, -0.18)
	cluck_t -= delta
	if cluck_t <= 0.0 and not chickens.is_empty():
		cluck_t = randf_range(5.0, 11.0)
		sfx_local("cluck", -16.0, randf_range(0.9, 1.3))
	# Butterflies flutter over the garden beds.
	var bfs: MultiMeshInstance3D = parts.get("butterflies")
	if bfs:
		var mm := bfs.multimesh
		for i in mm.instance_count:
			var a := clock * (0.5 + i * 0.07) + i * 1.9
			var p := Vector3(-4.5 + i * 1.8 + sin(a) * 1.2, 1.0 + sin(a * 2.3) * 0.35, -8.6 + cos(a * 0.8) * 1.2)
			var flap := sin(clock * 22.0 + i) * 0.9
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.BACK, flap), p))


## What's on today's menu (the chalkboard by the back door).
func _update_menu_board() -> void:
	var menu: Label3D = parts.get("menu")
	if menu == null:
		return
	var lines: Array[String] = ["TODAY'S MENU"]
	for r in unlocked_recipes():
		lines.append("%s = %s" % [r, _names(RECIPES[r]).to_lower().replace(", ", " + ")])
	lines.append("(* chop: lettuce, tomato, cucumber, cheese)")
	menu.text = "\n".join(lines)


## Bouncing arrows only one player sees: the chef's next ingredient, each runner's next job.
func _update_guides() -> void:
	for p in players:
		if not p.active or p.ghost or p.remote:
			_hide_guide(p)
			continue
		var want = null
		var k := 1.0
		if p.index == 0:
			var it = chef_task.get("item")
			if it != null and is_instance_valid(it):
				want = it.global_position + Vector3.UP * 0.12
				k = 0.18
			elif chef_task.has("spot"):
				var sp: Vector3 = chef_task["spot"]
				want = sp + Vector3.UP * 0.12
				k = 0.18
			else:
				var pl = chef_task.get("plate")
				if pl != null and is_instance_valid(pl):
					want = pl.global_position + Vector3.UP * 0.12
					k = 0.18
		else:
			var job := runner_job(p)
			if job.has("pos"):
				want = job["pos"]
				k = 0.6
				var w: Vector3 = want
				if flat_dist(w, p.global_position) < 1.3:
					want = null
		if want == null:
			_hide_guide(p)
			continue
		var g: Node3D = p.get_meta("guide") if p.has_meta("guide") else null
		if g == null:
			g = GuideScript.new()
			g.color = p.color.lightened(0.3) if p.index > 0 else Color(1.0, 0.9, 0.3)
			g.layer = p.viewmodel_layer() if p.index == 0 else p.guide_layer()
			add_child(g)
			p.set_meta("guide", g)
		g.point(want, k)


func _hide_guide(p) -> void:
	if p.has_meta("guide"):
		var g: Node3D = p.get_meta("guide")
		g.hide_arrow()


## The recipes still to be made, most urgent first (finished plates and plates in hands don't count).
func _open_orders() -> Array:
	var cs := _waiting_customers()
	cs.sort_custom(func(a, b) -> bool: return a.frac < b.frac)
	var need := []
	for c in cs:
		need.append(c.recipe)
	for it in all_items():
		if it.is_plate() and it.recipe != "":
			need.erase(it.recipe)
	for i in range(1, players.size()):
		var ck: String = players[i].carry_kind
		if ck.begins_with("plate:"):
			need.erase(ck.substr(6))
	return need


## Host: the chef's next step: {text, item, plate} (shown in VR / on the button chef's screen).
func _compute_chef_task() -> Dictionary:
	if game_over:
		return {}
	var held_items: Array = []
	if not players.is_empty():
		for h in players[0].held:
			if h != null and is_instance_valid(h):
				held_items.append(h)
	var need := _open_orders()
	if need.is_empty():
		var first := shift == 0 and not ready_for_orders()
		for it in all_items():
			if it.holder == -1 and it.needs_chop():
				return {"text": "Practise chopping: swing a knife DOWN through the %s!" % ItemScript.display_name(it.kind), "item": it}
		if first:
			return {"text": "Waiting for the runners to join…"}
		return {"text": "All orders done! Waiting for hungry customers…" if shift > 0 else ""}
	# Pair plates with orders (a plate already started keeps its order).
	var plates: Array = []
	for h in L.PLATE_HOME.size():
		var pl = _home_plate(h)
		if pl != null and pl.recipe == "":
			plates.append(pl)
	for r in need:
		var target = null
		for pl in plates:
			if not pl.contents.is_empty():
				var ok := true
				for kk in pl.contents:
					if not RECIPES[r].has(kk):
						ok = false
				if ok:
					target = pl
					break
		if target == null:
			for pl in plates:
				if pl.contents.is_empty():
					target = pl
					break
		if target == null:
			continue
		for kind in RECIPES[r]:
			if target.contents.has(kind):
				continue
			for it in held_items:
				if it.kind == kind and not it.is_plate():
					if it.needs_chop():
						return {"text": "Put the %s down on the counter and CHOP it!" % ItemScript.display_name(kind), "spot": L.BOARD}
					return {"text": "Drop the %s on the glowing plate (let go of the trigger)" % ItemScript.display_name(kind), "plate": target}
			for it in all_items():
				if it.holder != -1 or it.is_plate() or it.kind != kind:
					continue
				if it.needs_chop():
					if fire_on:
						return {"text": "FIRE! Too smoky to chop - runners, spray it out!", "item": it}
					return {"text": "CHOP the %s: swing a knife DOWN through it!  (%d more)" % [ItemScript.display_name(kind), ItemScript.chops_needed(kind) - it.chops], "item": it}
				return {"text": "Grab the %s (right trigger) and drop it on the glowing plate" % ItemScript.display_name(kind), "item": it, "plate": target}
		var missing: Array[String] = []
		for kind in RECIPES[r]:
			if not target.contents.has(kind):
				missing.append(ItemScript.display_name(kind))
		return {"text": "%s needs %s - the runners are fetching it…" % [r, " + ".join(missing)], "plate": target}
	return {"text": "Both plates are busy - finish one!"}


func ready_for_orders() -> bool:
	return net.mode != "host" or net.connected


## What a runner should do next: {text, pos}. Works on both machines (uses only mirrored state).
func runner_job(p) -> Dictionary:
	var c: String = p.carry_kind
	if c.begins_with("plate:"):
		var r := c.substr(6)
		var best = null
		for cu in get_tree().get_nodes_in_group("kr_customers"):
			if cu.waiting() and cu.recipe == r and (best == null or cu.frac < best.frac):
				best = cu
		if best != null:
			return {"text": "SERVE the %s to the customer who wants it!" % r, "pos": best.global_position + Vector3.UP * 3.4}
		return {"text": "Nobody wants this %s right now - wait by the window" % r}
	if c == "extinguisher":
		if fire_on:
			return {"text": "SPRAY THE FIRE on the stove!", "pos": L.STOVE + Vector3.UP * 1.6}
		return {"text": "Put the extinguisher back on its stand", "pos": L.EXT_POS + Vector3.UP * 1.3}
	if c != "":
		return {"text": "Bring the %s to the PASS (the front edge of the counter)" % ItemScript.display_name(c), "pos": Vector3(0, 1.4, -0.13)}
	var idle := _idle_runners()
	var my := idle.find(p.index)
	if fire_on and ext_holder == -1 and my == 0:
		return {"text": "FIRE! Grab the EXTINGUISHER (by the back door)", "pos": L.EXT_POS + Vector3.UP * 1.3}
	if raccoon.visible and raccoon.carry_kind == "" and my == idle.size() - 1:
		return {"text": "A RACCOON! Run into it to scare it off!", "pos": raccoon.global_position + Vector3.UP * 1.0}
	var open := _open_orders()
	for it in all_items():
		if it.is_plate() and it.recipe != "" and it.holder == -1:
			for cu in get_tree().get_nodes_in_group("kr_customers"):
				if cu.waiting() and cu.recipe == it.recipe:
					return {"text": "A %s is READY! Pick it up from the counter corner" % it.recipe, "pos": it.global_position + Vector3.UP * 0.5}
	var missing := _missing_ingredients(open)
	if missing.is_empty():
		return {"text": "Nothing to fetch right now - watch for ready plates!"}
	var kind: String = missing[maxi(my, 0) % missing.size()]
	var where := "the GARDEN (out the back door)" if L.source_pos(kind).z < -6.0 else ("the FRIDGE" if L.source_pos(kind).z < 1.0 else "the PANTRY")
	return {"text": "FETCH a %s from %s" % [ItemScript.display_name(kind), where], "pos": L.source_pos(kind) + Vector3.UP * 1.9, "kind": kind}


func _idle_runners() -> Array:
	var out := []
	for i in range(1, players.size()):
		if players[i].active and players[i].carry_kind == "":
			out.append(i)
	return out


## Ingredients the two most urgent orders still need that nobody has yet (on a plate, on the counter,
## in the chef's hands or being carried).
func _missing_ingredients(open: Array) -> Array:
	var missing := []
	for r in open.slice(0, 2):
		for k in RECIPES[r]:
			missing.append(k)
	for h in L.PLATE_HOME.size():
		var pl = _home_plate(h)
		if pl != null and pl.recipe == "":
			for k in pl.contents:
				missing.erase(k)
	for it in all_items():
		if not it.is_plate() and (it.holder == -1 or it.holder == 0):
			missing.erase(it.kind)
	for i in range(1, players.size()):
		missing.erase(players[i].carry_kind)
	return missing


# --- Stats and awards --------------------------------------------------------------

func _award(i: int) -> String:
	var st: Dictionary = stats[i]
	if i == 0:
		if st.dishes >= 12:
			return "MASTER CHEF"
		if st.chops >= 40:
			return "CHOP CHAMPION"
		return "HEAD CHEF"
	var cats := [["served", "SPEEDY SERVER"], ["fetched", "VEGGIE HUNTER"], ["sprays", "FIREFIGHTER"], ["raccoons", "RACCOON WRANGLER"]]
	var best := "KITCHEN HELPER"
	var best_score := 0.0
	for cat in cats:
		var key: String = cat[0]
		var mine := float(st[key])
		if mine <= 0.0:
			continue
		var top := 0.0
		for j in range(1, players.size()):
			top = maxf(top, float(stats[j][key]))
		var score := mine / maxf(1.0, top) + (0.5 if key == "sprays" or key == "raccoons" else 0.0)
		if score > best_score:
			best_score = score
			best = cat[1]
	return best


func _stats_lines() -> String:
	var lines: Array[String] = []
	var c: Dictionary = stats[0]
	lines.append("CHEF  ·  %d chops  ·  %d dishes   -   %s!" % [c.chops, c.dishes, _award(0)])
	for i in range(1, players.size()):
		var st: Dictionary = stats[i]
		if not players[i].active and st.fetched + st.served == 0:
			continue
		lines.append("P%d  ·  %d fetched  ·  %d served  ·  %d sprays  ·  %d raccoons   -   %s!" % [i + 1, st.fetched, st.served, st.sprays, st.raccoons, _award(i)])
	return "\n".join(lines)


func _show_stats(title: String, duration: float) -> void:
	_apply_stats(title + "\n" + _stats_lines(), duration)
	net.event("stats", [stats_text, duration])
	print("Stats:\n" + stats_text)


func _apply_stats(text: String, duration: float) -> void:
	stats_text = text
	stats_label.text = text
	stats_label.modulate.a = 1.0
	if duration > 0.0:
		var tw := stats_label.create_tween()
		tw.tween_interval(duration)
		tw.tween_property(stats_label, "modulate:a", 0.0, 0.6)
		tw.tween_callback(func() -> void: stats_text = "")


func return_stolen(kind: String) -> void:
	var slot := free_pass_slot(Vector3.ZERO)
	if slot >= 0:
		spawn_item(kind, L.PASS_SLOTS[slot], -1)


func on_raccoon_scared(runner_index: int) -> void:
	coins += 3
	if runner_index >= 0 and runner_index < stats.size():
		stats[runner_index].raccoons += 1
	print("Raccoon scared off")


# --- Networking ----------------------------------------------------------------

func on_client_joined() -> void:
	banner("THE RUNNERS ARE HERE!\nLet's cook!", 2.0)
	if shift == 0:
		break_t = 3.0


func on_client_left() -> void:
	# The TV machine reloads when it reconnects: its extra players will press to join again.
	for i in range(2, players.size()):
		if players[i].active:
			_drop_carry(players[i])
			players[i].set_active(false)
	banner("The TV players left - waiting for them to rejoin…", 0.0)


func on_p2_action(action: String, args: Array, index: int = 1) -> void:
	if index < 1 or index > MAX_RUNNERS:
		return
	_ensure_runners(net.mode)
	var p = players[index]
	match action:
		"use":
			runner_use(p)
		"join":
			_set_runner_active(p, true)
		"leave":
			if index >= 2:
				_set_runner_active(p, false)
		"restart":
			if game_over:
				get_tree().reload_current_scene()
		"pause":
			var paused: bool = args[0]
			_set_pause_banner(paused, "A TV player opened the menu")
			get_tree().paused = paused


func _set_pause_banner(paused: bool, who: String) -> void:
	banner("PAUSED\n" + who if paused else "", 0.0, false)
	_update_vr_center()


func toggle_vr_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_set_pause_banner(paused, "Press the menu button to resume")
	net.event("remote_pause", [paused])


func make_snapshot() -> Array:
	var rs := []
	for i in range(1, players.size()):
		rs.append(players[i].net_state())
	var its := []
	for it in all_items():
		its.append(it.net_state())
	var cs := []
	for c in get_tree().get_nodes_in_group("kr_customers"):
		cs.append(c.net_state())
	return [shift, coins, served_shift, angry, combo, game_over, in_break, fire_on, ext_holder,
		players[0].net_state(), rs, its, cs, raccoon.net_state(), served_total, rush_t, stars]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play:
		return
	synced = true
	shift = s[0]
	coins = s[1]
	served_shift = s[2]
	angry = s[3]
	combo = s[4]
	game_over = s[5]
	in_break = s[6]
	fire_on = s[7]
	ext_holder = s[8]
	players[0].apply_net_state(s[9])
	var rs: Array = s[10]
	for i in mini(rs.size(), players.size() - 1):
		players[i + 1].apply_net_state(rs[i])
	_sync_ghosts(s[11], "item")
	_sync_ghosts(s[12], "cust")
	raccoon.apply_net(s[13])
	served_total = s[14]
	if s.size() > 16:
		rush_t = s[15]
		stars = s[16]
		if not has_meta("menu_shift") or int(get_meta("menu_shift")) != shift:
			set_meta("menu_shift", shift)
			_update_menu_board()


func _sync_ghosts(list: Array, kind: String) -> void:
	var seen := {}
	for entry in list:
		var key := "%s:%d" % [kind, int(entry[0])]
		seen[key] = true
		var g = ghost_nodes.get(key)
		if g == null or not is_instance_valid(g):
			g = _make_ghost(kind, entry)
			ghost_nodes[key] = g
		g.apply_net(entry)
	for key in ghost_nodes.keys():
		if key.begins_with(kind + ":") and not seen.has(key):
			var g = ghost_nodes[key]
			if is_instance_valid(g):
				if kind == "item":
					g.remove_from_group("kr_items")
				else:
					g.remove_from_group("kr_customers")
				g.queue_free()
			ghost_nodes.erase(key)


func _make_ghost(kind: String, entry: PackedFloat32Array) -> Node3D:
	if kind == "item":
		var it := ItemScript.new()
		it.main = self
		it.ghost = true
		it.net_id = int(entry[0])
		it.kind = ItemScript.kind_from(int(entry[1]))
		it.position = Vector3(entry[2], entry[3], entry[4])
		it.apply_net(entry)
		add_child(it)
		return it
	var c := CustomerScript.new()
	c.main = self
	c.ghost = true
	c.net_id = int(entry[0])
	c.recipe = ItemScript.recipe_from(int(entry[1]))
	c.position = Vector3(entry[2], entry[3], entry[4])
	c.color_index = int(entry[7])
	c.slot = int(entry[8])
	if entry.size() > 9:
		c.ctype = CustomerScript.type_from(int(entry[9]))
	add_child(c)
	return c


func apply_event(kind: String, args: Array) -> void:
	if not ready_to_play:
		return
	match kind:
		"sound":
			sfx_local(args[0], args[1], args[2])
		"burst":
			burst(args[0], args[1], args[2], args[3])
		"popup":
			popup(args[0], args[1], args[2])
		"center":
			banner(args[0], args[1], false)
		"remote_pause":
			get_tree().paused = args[0]
			_set_pause_banner(args[0], "The chef paused the game")
		"stars":
			show_stars(args[0])
		"stats":
			_apply_stats(args[0], args[1])
		"bell":
			bell_t = 1.0


# --- HUD -------------------------------------------------------------------------

func _make_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", maxi(6, size / 5))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	info_label = _make_label(30)
	info_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	layer.add_child(info_label)
	info_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	info_label.offset_top = 14
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label = _make_label(56)
	center_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	layer.add_child(center_label)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# How to play: one panel at the top until the first shift is done.
	help_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.06, 0.08, 0.8)
	sb.border_color = Color(1.0, 0.6, 0.45, 0.95)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	help_panel.add_theme_stylebox_override("panel", sb)
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(help_panel)
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	help_panel.offset_top = -330
	help_panel.offset_bottom = -24
	help_label = _make_label(22)
	help_label.text = "HOW TO PLAY  -  cook what the customers order!\n" \
		+ "RUNNERS (TV): left stick move, right stick look, A = pick up / put down / serve\n" \
		+ "    1. Follow your ARROW to FETCH an ingredient (fridge, pantry or the garden out the back)\n" \
		+ "    2. Put it on the PASS - the yellow strip at the front of the counter\n" \
		+ "    3. When a plate glows gold, carry it to the customer showing that dish at the window\n" \
		+ "    FIRE? grab the red extinguisher and spray the stove.  RACCOON? run into it!\n" \
		+ "CHEF (VR): swing a knife DOWN through vegetables to chop them, grab with the right trigger,\n" \
		+ "    drop ingredients on the glowing plate to match the tickets.  Left stick slides, A recenters."
	help_panel.add_child(help_label)
	help_panel.resized.connect(func() -> void:
		var area := help_panel.get_parent_area_size()
		help_panel.position = Vector2((area.x - help_panel.size.x) * 0.5, area.y - help_panel.size.y - 24.0))
	stats_label = _make_label(28)
	stats_label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	layer.add_child(stats_label)
	stats_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	stats_label.offset_top = -300
	stats_label.offset_bottom = -30
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## Big centre message on both machines (and on a floating panel in VR).
func banner(text: String, duration: float, broadcast: bool = true) -> void:
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


func status_text() -> String:
	var s := "%s   COINS %d\nSERVED %d/%d   ANGRY %d/%d" % [shift_name(), coins, served_shift, shift_target(), angry, MAX_ANGRY]
	if combo > 1:
		s += "   COMBO x%d" % combo
	if rush_t > 0.0:
		s += "\nRUSH! x2 COINS"
	return s


func total_stars() -> int:
	var n := 0
	for st in stars:
		n += int(st)
	return n


func orders_text() -> String:
	var lines: Array[String] = ["ORDERS:"]
	var cs := _waiting_customers()
	cs.sort_custom(func(a, b) -> bool: return a.frac < b.frac)
	for c in cs:
		lines.append("%s  %s  %d%%" % [c.recipe, _names(RECIPES[c.recipe]), int(c.frac * 100.0)])
	if cs.is_empty():
		lines.append("(none yet)")
	var ready_plates: Array[String] = []
	for it in all_items():
		if it.is_plate() and it.recipe != "" and it.holder == -1:
			ready_plates.append(it.recipe)
	if not ready_plates.is_empty():
		lines.append("READY TO SERVE: " + ", ".join(ready_plates))
	return "\n".join(lines)


func chef_hint(chef) -> String:
	var sp := L.spot_pos(chef.cursor)
	var names := ["PASS 1", "PASS 2", "PASS 3", "PASS 4", "BIN", "LEFT PLATE", "BOARD", "RIGHT PLATE"]
	var here := ""
	if chef.cursor == 5 or chef.cursor == 7:
		var p = _home_plate(0 if chef.cursor == 5 else 1)
		if p != null:
			here = item_label(p)
	else:
		var it = item_at(sp, 0.2)
		if it != null:
			here = item_label(it)
	var t: String = names[chef.cursor]
	if here != "":
		t += ": " + here
	var task: String = chef_task.get("text", "")
	if task != "":
		t = "NEXT: " + task.replace("swing a knife DOWN through it", "press Shift / X").replace("(right trigger)", "(Space / A)").replace(" (let go of the trigger)", "") + "\n" + t
	elif fire_on:
		t += "\nFIRE! The runners must put it out before you can chop"
	return t


func _update_hud() -> void:
	var dt := get_process_delta_time()
	var show_help := shift == 0 or (shift == 1 and served_total < 2 and not in_break)
	help_panel.modulate.a = clampf(help_panel.modulate.a + (dt if show_help else -dt * 0.7), 0.0, 1.0)
	help_panel.visible = help_panel.modulate.a > 0.0
	if net.mode == "client" and not synced:
		info_label.text = "Syncing with the chef…"
		return
	info_label.text = "%s     COINS %d     SERVED %d/%d     ANGRY %d/%d     STARS %d" % [shift_name(), coins, served_shift, shift_target(), angry, MAX_ANGRY, total_stars()]
	if combo > 1:
		info_label.text += "     COMBO x%d" % combo
	if rush_t > 0.0:
		info_label.text += "     RUSH! DOUBLE COINS %ds" % int(rush_t)


## VR can't show 2D overlays: mirror the centre banner on a floating panel in front of the chef.
func _update_vr_center() -> void:
	if players.is_empty() or not players[0].vr:
		return
	if vr_center == null:
		vr_center = Label3D.new()
		vr_center.font_size = 48
		vr_center.outline_size = 26
		vr_center.no_depth_test = false
		vr_center.render_priority = 10
		vr_center.outline_render_priority = 9
		vr_center.width = 900.0
		vr_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vr_center.pixel_size = 0.0024
		vr_center.position = Vector3(0.0, 0.15, -1.6)
		vr_center.modulate = Color(1.0, 0.92, 0.55)
		players[0].xr_camera.add_child(vr_center)
		set_layers(vr_center, players[0].viewmodel_layer())
	vr_center.text = center_label.text
	vr_center.modulate.a = center_label.modulate.a
	vr_center.outline_modulate = Color(0, 0, 0, center_label.modulate.a)
	# The tickets hang just in front of the chef's eyes and the counter is below them, so the banner and
	# the "next step" hint float further out, between the ticket rail and the counter's far edge
	# (the end-of-day awards go above the ticket rail).
	VrText.follow(vr_center, players[0].xr_camera, self, -0.3, 1.6)
	if vr_hint == null:
		vr_hint = Label3D.new()
		vr_hint.font_size = 40
		vr_hint.outline_size = 22
		vr_hint.no_depth_test = false
		vr_hint.render_priority = 10
		vr_hint.outline_render_priority = 9
		vr_hint.width = 800.0
		vr_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(vr_hint)
		set_layers(vr_hint, players[0].viewmodel_layer())
	var stats_mode: bool = stats_text != ""
	if stats_mode != vr_hint.get_meta("stats_mode", false):
		vr_hint.set_meta("stats_mode", stats_mode)
		VrText.snap(vr_hint)
	var hint: String = stats_text if stats_mode else str(chef_task.get("text", ""))
	vr_hint.pixel_size = 0.0016 if stats_mode else 0.0019
	vr_hint.modulate = Color(0.9, 0.97, 1.0) if stats_mode else (Color(1.0, 0.55, 0.45) if fire_on else Color(1.0, 0.95, 0.6))
	vr_hint.text = hint
	vr_hint.visible = hint != "" and not game_over or stats_mode
	VrText.follow(vr_hint, players[0].xr_camera, self, -0.62 if not stats_mode else 0.75, 1.6)
