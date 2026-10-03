extends Node3D
## Kitchen Rush: co-op cooking chaos.
## Player 1 is the CHEF at the counter (VR hands, or button controls in split screen): chop and stack.
## Players 2-3 are RUNNERS (TV, first person): fetch ingredients to the pass, carry finished plates to customers.
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
const PLAYER_COLORS: Array[Color] = [Color(1.0, 0.45, 0.35), Color(0.3, 0.65, 1.0), Color(0.7, 0.45, 1.0)]
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
	KitchenScript.build(self)
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
		banner("Waiting for the runners on the TV to join…", 0.0)
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
	l.no_depth_test = true
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
	var count := 3 if mode != "local" else 2
	for i in range(1, count):
		var r := RunnerScript.new()
		r.index = i
		r.color = PLAYER_COLORS[i]
		r.main = self
		r.remote = mode == "host"
		r.key_set = 0 if i == 2 else 1
		r.mouse_look = i == 2
		r.position = L.RUNNER_SPAWN[i - 1]
		r.yaw = PI
		add_child(r)
		players.append(r)
	if players.size() > 2:
		players[2].set_active(false)  # player 3 wakes up when someone presses its button


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
	else:
		print("No VR headset: split screen")
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	layer.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for p in players:
		if p.vr or p.remote or p.ghost or p.camera != null:
			continue
		var container := SubViewportContainer.new()
		p.set_meta("view", container)
		container.stretch = true
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(container)
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
	for p in players:
		if p.index == 2 and not p.active and p.has_meta("view"):
			p.get_meta("view").visible = false
	if mode == "client":
		_add_bubble(players[1].hud, _build_ghost_mirror(), PLAYER_COLORS[0])


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
	var tag := Label.new()
	tag.text = "CHEF (VR)"
	tag.add_theme_font_size_override("font_size", 22)
	tag.add_theme_constant_override("outline_size", 6)
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_color_override("font_color", color)
	bubble.add_child(tag)
	tag.position = Vector2(80, 262)


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


func _on_joy_changed(_device: int, _connected: bool) -> void:
	if ready_to_play:
		_assign_joypads()


func on_player_activity_changed(p) -> void:
	if p.has_meta("view"):
		p.get_meta("view").visible = p.active
	print("Player %d is now %s" % [p.index + 1, "playing" if p.active else "waiting"])


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


## Order tickets hanging in front of the chef (one per waiting customer, in window order).
func _build_tickets() -> void:
	var rail := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(2.3, 0.03, 0.03)
	rail.mesh = rm
	rail.material_override = mat(Color(0.75, 0.75, 0.8))
	rail.position = Vector3(0, 1.78, -0.38)
	add_child(rail)
	for i in MAX_CUSTOMERS:
		var root := Node3D.new()
		root.position = Vector3(-0.84 + i * 0.56, 1.6, -0.38)
		add_child(root)
		var paper := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.5, 0.34)
		paper.mesh = q
		paper.material_override = mat(Color(1.0, 0.98, 0.9))
		root.add_child(paper)
		var label := Label3D.new()
		label.font_size = 30
		label.outline_size = 26
		label.outline_modulate = Color.BLACK
		label.pixel_size = 0.0018
		label.double_sided = false
		label.position = Vector3(0, 0.03, 0.01)
		label.width = 260.0
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		root.add_child(label)
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.44, 0.035, 0.01)
		bar.mesh = bm
		var bar_mat := StandardMaterial3D.new()
		bar_mat.albedo_color = Color(0.3, 1.0, 0.4)
		bar_mat.emission_enabled = true
		bar_mat.emission = Color(0.3, 1.0, 0.4)
		bar.material_override = bar_mat
		bar.position = Vector3(0, -0.135, 0.01)
		root.add_child(bar)
		tickets.append([root, label, bar, bar_mat])


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
		var label: Label3D = t[1]
		var parts: Array[String] = []
		for k in RECIPES[c.recipe]:
			parts.append(ItemScript.display_name(k) + ("*" if ItemScript.chops_needed(k) > 0 else ""))
		label.text = "%s\n%s" % [c.recipe, " ".join(parts)]
		label.modulate = Color(1.0, 0.95, 0.6) if c.frac > 0.3 else Color(1.0, 0.45, 0.35)
		var bar: MeshInstance3D = t[2]
		bar.scale.x = maxf(c.frac, 0.01)
		var bm: StandardMaterial3D = t[3]
		var col := Color(1.0, 0.25, 0.2).lerp(Color(0.3, 1.0, 0.4), clampf(c.frac * 1.6 - 0.2, 0.0, 1.0))
		bm.albedo_color = col
		bm.emission = col
		root.position.y = 1.6 + (sin(clock * 20.0) * 0.01 if c.frac < 0.25 else 0.0)


# --- Main loop -------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	clock += delta
	if music == null:
		music = MusicScript.new()
		add_child(music)
	music.play_track(maxi(shift - 1, 0))
	_update_tickets()
	_update_fire_visuals()
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
		_check_join()
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
		return
	_host_update(delta)


func _host_update(delta: float) -> void:
	_ensure_plates()
	_move_finished_plates()
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
		spawn_t = _spawn_interval() * randf_range(0.8, 1.2)
	if combo > 0 and clock - last_serve_time > COMBO_WINDOW:
		combo = 0
	if shift >= 2:
		if not fire_on:
			fire_t -= delta
			if fire_t <= 0.0:
				_start_fire()
		raccoon_t -= delta
		if raccoon_t <= 0.0 and not raccoon.active():
			raccoon_t = randf_range(30.0, 50.0) - shift * 2.0
			raccoon.start()
			banner("A cheeky RACCOON is sneaking in!\nRunners: bump into it to scare it off!", 2.5)
			sound("spit", 0.0, 0.7)


func shift_target() -> int:
	return 2 + shift * 2


func _spawn_interval() -> float:
	return maxf(5.0, 15.0 - shift * 2.0)


func _patience() -> float:
	return maxf(35.0, 85.0 - shift * 8.0)


func recipe_items(r: String) -> Array:
	return RECIPES.get(r, [])


func unlocked_recipes() -> Array:
	var out := []
	for i in mini(maxi(shift, 1), UNLOCKS.size()):
		out.append_array(UNLOCKS[i])
	return out


func _start_shift() -> void:
	shift += 1
	served_shift = 0
	in_break = false
	spawn_t = 0.5
	fire_t = randf_range(25.0, 40.0)
	raccoon_t = randf_range(15.0, 30.0)
	print("Shift %d started" % shift)
	var extra := ""
	if shift - 1 < UNLOCKS.size() and shift > 1:
		extra = "\nNEW RECIPE: " + ", ".join(PackedStringArray(UNLOCKS[shift - 1]))
	if shift == 2:
		extra += "\nWatch out for fires and raccoons!"
	banner("SHIFT %d\nServe %d orders!%s" % [shift, shift_target(), extra], 2.5)
	sound("wave")


func _end_shift() -> void:
	in_break = true
	break_t = 6.0
	print("Shift %d complete: coins %d, angry %d" % [shift, coins, angry])
	banner("SHIFT %d COMPLETE!\n%d coins so far\nNext shift: hungrier customers!" % [shift, coins], 4.0)
	sound("clear")
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
	c.max_patience = _patience()
	c.patience = c.max_patience
	c.position = Vector3(10.5, 0.0, L.CUSTOMER_Z[c.slot] + (2.5 if c.slot >= 2 else -2.5))
	add_child(c)
	sound("wave", -10.0, 1.6)


func on_customer_angry(c) -> void:
	angry += 1
	combo = 0
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
	banner("KITCHEN CLOSED!\nToo many hungry customers left\nShift %d  ·  %d served  ·  %d coins\n%s\n\nPress A / Enter (VR: trigger) to cook again" % [shift, served_total, coins, best_line], 0.0)


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
			print("Dish ready: %s" % r)
			sound("revive", 0.0, 1.2)
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
	sound("hit", -2.0, 0.9 + it.chops * 0.15)
	burst(it.global_position + Vector3.UP * 0.06, ItemScript.color_of(it.kind), 8, 0.035)
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
	var tip := int(round(10.0 * cust.frac))
	var mult := 1.0 + minf(combo - 1, 4) * 0.5
	var gain := int(round((10 + tip) * mult))
	coins += gain
	print("Served %s: +%d coins (combo %d), total %d" % [cust.recipe, gain, combo, coins])
	var text := "+%d coins" % gain
	if combo > 1:
		text += "\nCOMBO x%d!" % combo
	popup(cust.global_position + Vector3(-0.6, 2.3, 0), text, Color(1.0, 0.85, 0.2))
	sound("clear", -2.0, 1.0 + minf(combo, 5) * 0.08)
	burst(cust.global_position + Vector3.UP * 1.6, Color(1.0, 0.5, 0.8), 20, 0.06)
	burst(cust.global_position + Vector3.UP * 1.6, Color(0.5, 0.9, 1.0), 14, 0.06)
	if served_shift >= shift_target() and not in_break:
		_end_shift()


# --- Chaos: fire and raccoon ------------------------------------------------------------

func _start_fire() -> void:
	fire_on = true
	fire_hp = 3
	print("Fire on the stove!")
	sound("big_kill", -2.0, 0.8)
	banner("FIRE ON THE STOVE!\nRunners: grab the extinguisher and spray it!\n(The chef can't chop in the smoke)", 3.0)


func _spray(p) -> void:
	fire_hp -= 1
	sound("dash", 0.0, 0.6)
	burst(L.STOVE + Vector3(0.3, 1.1, 0.0), Color(0.95, 0.97, 1.0), 24, 0.1)
	if fire_hp <= 0:
		fire_on = false
		ext_holder = -1
		p.carry_kind = ""
		coins += 5
		fire_t = randf_range(35.0, 55.0) - shift * 2.0
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


func return_stolen(kind: String) -> void:
	var slot := free_pass_slot(Vector3.ZERO)
	if slot >= 0:
		spawn_item(kind, L.PASS_SLOTS[slot], -1)


func on_raccoon_scared(_runner_index: int) -> void:
	coins += 3
	print("Raccoon scared off")


# --- Networking ----------------------------------------------------------------

func on_client_joined() -> void:
	banner("THE RUNNERS ARE HERE!\nLet's cook!", 2.0)
	if shift == 0:
		break_t = 3.0


func on_client_left() -> void:
	banner("The TV players left - waiting for them to rejoin…", 0.0)


## Client: player 3 joins by pressing their button.
var join_t := 0.0
func _check_join() -> void:
	join_t -= get_process_delta_time()
	if players.size() < 3 or players[2].active or join_t > 0.0 or game_over:
		return
	if players[2].any_input():
		join_t = 1.0
		net.send_action("join", [], 2)


func on_p2_action(action: String, args: Array, index: int = 1) -> void:
	var p = players[index]
	match action:
		"use":
			runner_use(p)
		"join":
			if not p.active:
				p.set_active(true)
				p.global_position = L.RUNNER_SPAWN[1]
				banner("PLAYER %d JOINED THE KITCHEN!" % (index + 1), 1.5)
				print("Net: player %d joined" % (index + 1))
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
		players[0].net_state(), rs, its, cs, raccoon.net_state(), served_total]


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
	help_label = _make_label(20)
	layer.add_child(help_label)
	help_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	help_label.offset_top = -64
	help_label.offset_bottom = -12
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.text = "CHEF: chop ingredients (* = needs chopping) and stack them on a plate to match the tickets.\n" \
		+ "RUNNERS: fetch ingredients to the PASS, carry finished plates to the hungry customers at the window!"


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
	var s := "SHIFT %d   COINS %d\nSERVED %d/%d   ANGRY %d/%d" % [maxi(shift, 1), coins, served_shift, shift_target(), angry, MAX_ANGRY]
	if combo > 1:
		s += "   COMBO x%d" % combo
	return s


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
	if fire_on:
		t += "\nFIRE! The runners must put it out before you can chop"
	return t


func _update_hud() -> void:
	if shift >= 2 and help_label.modulate.a > 0.0:
		help_label.modulate.a = maxf(0.0, help_label.modulate.a - get_process_delta_time())
	if net.mode == "client" and not synced:
		info_label.text = "Syncing with the chef…"
		return
	info_label.text = "SHIFT %d     COINS %d     SERVED %d/%d     ANGRY %d/%d" % [maxi(shift, 1), coins, served_shift, shift_target(), angry, MAX_ANGRY]
	if combo > 1:
		info_label.text += "     COMBO x%d" % combo


## VR can't show 2D overlays: mirror the centre banner on a floating panel in front of the chef.
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
		vr_center.pixel_size = 0.0024
		vr_center.position = Vector3(0.0, 0.15, -1.6)
		vr_center.modulate = Color(1.0, 0.92, 0.55)
		players[0].xr_camera.add_child(vr_center)
		set_layers(vr_center, players[0].viewmodel_layer())
	vr_center.text = center_label.text
	vr_center.modulate.a = center_label.modulate.a
	vr_center.outline_modulate = Color(0, 0, 0, center_label.modulate.a)
