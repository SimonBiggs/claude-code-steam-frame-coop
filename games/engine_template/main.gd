extends Node3D
## ENGINE TEMPLATE ("Star Catch"): the smallest complete game on the shared engine. Copy this folder
## to start a new game, then replace the gameplay. Read docs/engine/systems.md alongside it.
## Stars pop up around a little park and everyone catches them: TV players run into them, the VR
## player touches them with a glove. Y on a controller swaps between split screen and one shared
## view. The best score is saved.
## Shows: net modes (local / host / TV machine), core/party.gd drop-in seats, core/split_view.gd
## views + VR bubble, core/camera_rig.gd follow + group cameras, core/vr_rig.gd (or its Avatar on the
## TV), the state store (score, view mode), net.request (TV -> host), snapshots, events, core/save.gd.

const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const SfxScript := preload("res://core/sfx.gd")
const Party := preload("res://core/party.gd")
const SplitView := preload("res://core/split_view.gd")
const VrRig := preload("res://core/vr_rig.gd")
const CameraRig := preload("res://core/camera_rig.gd")
const Save := preload("res://core/save.gd")
const VrText := preload("res://core/vr_text.gd")

const GAME_ID := "engine_template"
const ARENA := 8.0
const SPEED := 4.5
const MAX_STARS := 6

# --- The networking contract (see docs/engine/systems.md) ---
var net: Node
var ready_to_play := false
# --- Engine modules (these member names are what core/ looks for) ---
var party: Party
var split: SplitView
var vr_rig: VrRig
var save: Save
var sfx: Node

var avatars := {}  # slot -> Node3D: TV players (every machine)
var cams := {}  # slot -> CameraRig: one per local view
var group_cam: CameraRig  # the shared view's camera
var hud_labels := {}  # slot -> Label (-1 = the shared view's)
var vr_avatar: VrRig.Avatar  # TV machine: the VR player as seen from the TV
var vr_label: Label3D  # host: score on the back of the VR player's left glove
var vr_banner: Label3D  # host: "PAUSED" in front of the VR player
var tv_banner: Label  # TV: "PAUSED" over every view
var stars := {}  # id -> Node3D
var next_star := 0
var star_t := 0.0
var send_t := 0.0  # TV machine: positions go to the host 30 times a second


func _ready() -> void:
	_build_world()
	var menu := PauseMenuScript.new()
	menu.main = self
	add_child(menu)
	net = NetScript.new()
	net.name = "Net"  # RPCs resolve to /root/Main/Net on both machines
	net.main = self
	add_child(net)
	net.state_changed.connect(_on_state_changed)
	party = Party.new()
	party.name = "Party"
	add_child(party)
	party.player_joined.connect(_on_player_joined)
	party.player_left.connect(_on_player_left)
	save = Save.new()
	save.game_id = GAME_ID
	save.defaults = {"best": 0}
	add_child(save)
	if OS.has_environment("DUO_JOIN"):
		net.join_finished.connect(func(ok: bool) -> void: _setup("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if VrRig.headset_available() or OS.has_environment("DUO_HOST"):
			net.host()
		_setup(net.mode)


func _setup(mode: String) -> void:
	if VrRig.wanted(mode):
		vr_rig = VrRig.new()
		vr_rig.bounds = Rect2(-ARENA, -ARENA, ARENA * 2.0, ARENA * 2.0)
		add_child(vr_rig)
		vr_rig.place(Vector3(0.0, 0.0, ARENA * 0.6), 0.0)
		vr_label = Label3D.new()
		vr_label.font_size = 48
		vr_label.outline_size = 14
		vr_label.pixel_size = 0.0009
		vr_label.position = Vector3(0.0, 0.05, 0.06)  # back of the hand, clear of the wrist MENU
		vr_label.rotation = Vector3(-1.2, 0.0, 0.0)
		vr_rig.hand_l.add_child(vr_label)
	if mode != "host":
		split = SplitView.new()
		add_child(split)
		split.bind_party(party)
		group_cam = CameraRig.new()
		group_cam.camera = split.shared_camera()
		group_cam.group_min_distance = 9.0
		add_child(group_cam)
		group_cam.follow_group([], -60.0, 0.0, 0.0)
		hud_labels[-1] = _hud_label(split.shared_hud())
		if mode == "client":
			vr_avatar = VrRig.Avatar.new()
			add_child(vr_avatar)
			split.set_bubble(VrRig.build_mirror(self, vr_avatar.head, false))
		elif vr_rig != null:
			split.set_bubble(vr_rig.mirror)  # fake VR in bots
	# Local play without a headset: someone on the TV plays slot 0 ("P1") too.
	party.allow_slot0 = mode == "local" and vr_rig == null
	if mode != "client":
		net.state_set("score", 0)
		net.state_set("best", int(save.data["best"]))
		net.state_set("shared", false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_to_play = true
	print("Star Catch: %s mode%s" % [mode, " with a VR player" if vr_rig != null else ""])


# --- World --------------------------------------------------------------------------------

func _build_world() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.7, 0.95)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.8, 0.9)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = ARENA + 1.0
	disc.bottom_radius = ARENA + 1.0
	disc.height = 0.2
	disc.radial_segments = 32
	ground.mesh = disc
	ground.material_override = _mat(Color(0.4, 0.75, 0.35), 0.0)
	ground.position.y = -0.1
	add_child(ground)


func _mat(c: Color, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


# --- Players ------------------------------------------------------------------------------

func _on_player_joined(slot: int, _device: int) -> void:
	var a := _ensure_avatar(slot)
	if party.is_local(slot) and split != null:
		var c := CameraRig.new()
		c.camera = split.camera(slot)
		c.party = party
		c.slot = slot
		c.pivot_height = 1.0
		c.pitch = -0.45
		add_child(c)
		c.follow(a, 6.0, 0.0)
		cams[slot] = c
		hud_labels[slot] = _hud_label(split.hud(slot))
	_refresh_group()
	sound("pickup", -6.0, 0.8)


func _on_player_left(slot: int) -> void:
	if avatars.has(slot):
		(avatars[slot] as Node).queue_free()
		avatars.erase(slot)
	if cams.has(slot):
		(cams[slot] as Node).queue_free()
		cams.erase(slot)
	hud_labels.erase(slot)
	_refresh_group()


func _ensure_avatar(slot: int) -> Node3D:
	if avatars.has(slot) and is_instance_valid(avatars[slot]):
		return avatars[slot]
	var a := Node3D.new()
	a.name = "Avatar%d" % slot
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.2
	cap.radial_segments = 12
	cap.rings = 4
	body.mesh = cap
	body.material_override = _mat(party.color_of(slot), 0.2)
	body.position.y = 0.6
	a.add_child(body)
	add_child(a)
	a.position = Vector3(-3.0 + slot, 0.0, 2.0)
	avatars[slot] = a
	return a


func _refresh_group() -> void:
	if group_cam != null:
		group_cam.set_targets(avatars.values())


func _hud_label(parent: Control) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 40)
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	parent.add_child(l)
	l.position = Vector2(24.0, 16.0)
	return l


## Local TV players walk with their left stick, relative to their camera. The TV machine moves its
## own players instantly and tells the host where they are (net.send_state).
func _move_local_players(delta: float) -> void:
	send_t -= delta
	var send := send_t <= 0.0
	if send:
		send_t = 1.0 / 30.0
	for slot in party.local_slots():
		if not avatars.has(slot):
			continue
		var a: Node3D = avatars[slot]
		var mv := party.stick(slot, "move")
		if mv != Vector2.ZERO:
			var cam := split.active_camera(slot)
			var f := -cam.global_basis.z
			f.y = 0.0
			f = f.normalized()
			var r := Vector3(-f.z, 0.0, f.x)
			var dir := r * mv.x - f * mv.y
			var p := a.position + dir * SPEED * delta
			p.y = 0.0
			a.position = p.limit_length(ARENA)
			a.rotation.y = atan2(-dir.x, -dir.z)
		if net.mode == "client" and send:
			net.send_state(a.position, a.rotation.y, 0.0, slot)
		if party.just_pressed(slot, "y"):
			net.request(slot, "toggle_view")


## Host: a TV player moved on the TV machine (core/net.gd calls this for engine-style games).
func on_remote_state(slot: int, pos: Vector3, yaw: float, _pitch: float) -> void:
	if avatars.has(slot):
		var a: Node3D = avatars[slot]
		a.position = pos
		a.rotation.y = yaw


## Host / local: a player asked for something (net.request from any machine lands here).
func on_request(_slot: int, action: String, _args: Array) -> void:
	match action:
		"toggle_view":
			net.state_set("shared", not bool(net.state_get("shared", false)))


## Every machine: the game was paused or resumed (wrist MENU, or a TV pause menu). Nothing in
## the paused game processes, so put the banners up right here.
func on_pause_changed(paused: bool, by_slot: int) -> void:
	var why := "PAUSED by %s\n%s" % [party.name_of(by_slot),
		"Wrist MENU: carry on" if vr_rig != null else "Start: menu"]
	if vr_rig != null:
		if vr_banner == null:
			vr_banner = Label3D.new()
			vr_banner.font_size = 64
			vr_banner.outline_size = 26
			vr_banner.pixel_size = 0.002
			add_child(vr_banner)
		vr_banner.text = why
		vr_banner.visible = paused
		VrText.snap(vr_banner)
		VrText.follow(vr_banner, vr_rig.camera, self, 0.0)
	if split != null:
		if tv_banner == null:
			var layer := CanvasLayer.new()
			layer.layer = 5
			add_child(layer)
			tv_banner = Label.new()
			tv_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tv_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			tv_banner.add_theme_font_size_override("font_size", 64)
			tv_banner.add_theme_constant_override("outline_size", 14)
			tv_banner.add_theme_color_override("font_outline_color", Color.BLACK)
			layer.add_child(tv_banner)
			tv_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tv_banner.text = why
		tv_banner.visible = paused


## Every machine: a replicated value changed.
func _on_state_changed(key: String, value: Variant) -> void:
	match key:
		"shared":
			if split != null:
				split.set_shared(bool(value))


# --- Game loop (host / local simulate; the TV machine draws) -------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if net.mode != "host":
		_move_local_players(delta)
	_update_hud()
	if net.mode == "client":
		return
	star_t -= delta
	if star_t <= 0.0 and stars.size() < MAX_STARS:
		star_t = 1.2
		_spawn_star()
	for id in stars.keys():
		var s: Node3D = stars[id]
		var by := _catcher(s.position)
		if by >= 0:
			_catch(int(id), by)
	if vr_rig != null and vr_rig.trigger_pressed():
		vr_rig.pulse(VrRig.RIGHT, 0.3, 0.05)  # (a real game would do something here)


func _spawn_star() -> void:
	var ang := randf() * TAU
	var pos := Vector3(cos(ang), 0.0, sin(ang)) * randf_range(1.5, ARENA - 0.5) + Vector3.UP * randf_range(0.6, 1.4)
	next_star += 1
	_make_star(next_star, pos)


func _make_star(id: int, pos: Vector3) -> Node3D:
	var s := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.22
	m.height = 0.44
	m.radial_segments = 12
	m.rings = 6
	s.mesh = m
	s.material_override = _mat(Color(1.0, 0.85, 0.2), 2.0)
	add_child(s)
	s.position = pos
	stars[id] = s
	return s


## Who is touching the star: a TV player's body, or a VR glove (slot 0). -1 = nobody.
func _catcher(p: Vector3) -> int:
	if vr_rig != null and vr_rig.touching_any(p, 0.3) >= 0:
		return 0
	for slot in avatars:
		var a: Node3D = avatars[slot]
		if Vector2(a.position.x - p.x, a.position.z - p.z).length() < 0.7:
			return int(slot)
	return -1


func _catch(id: int, by: int) -> void:
	var s: Node3D = stars[id]
	stars.erase(id)
	if by == 0 and vr_rig != null:
		var hand := vr_rig.touching_any(s.position, 0.3)
		vr_rig.pulse(hand if hand >= 0 else VrRig.RIGHT, 0.5, 0.08)
	pop(s.position, party.color_of(by))
	s.queue_free()
	var score := int(net.state_get("score", 0)) + 1
	net.state_set("score", score)
	if score > int(save.data["best"]):
		save.data["best"] = score
		save.mark_dirty()
		net.state_set("best", score)


## A little burst and a sound, on both machines (host sends it as an event).
func pop(pos: Vector3, color: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.08
	bm.material = _mat(color, 2.0)
	p.mesh = bm
	add_child(p)
	p.position = pos
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)
	sound("pickup", -4.0, 1.3)
	net.event("pop", [pos, color])


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if sfx == null:
		sfx = SfxScript.new()
		add_child(sfx)
	sfx.play(sound_name, volume_db, pitch)


func _update_hud() -> void:
	var line := "STARS %d   BEST %d" % [int(net.state_get("score", 0)), int(net.state_get("best", 0))]
	for slot in hud_labels:
		var l: Label = hud_labels[slot]
		if not is_instance_valid(l):
			continue
		if int(slot) < 0 and party.local_slots().is_empty():
			l.text = "STAR CATCH\nPress A to join"  # the shared view shows while nobody is seated
		else:
			l.text = (party.name_of(int(slot)) + "   " if int(slot) >= 0 else "") + line + "\nY: shared / split view"
	if vr_label != null:
		vr_label.text = line


# --- Networking ---------------------------------------------------------------------------

## Host, 30 Hz: what the TV machine must draw that it doesn't simulate itself.
func make_snapshot() -> Array:
	var ids := PackedInt32Array()
	var pos := PackedVector3Array()
	for id in stars:
		ids.append(int(id))
		pos.append((stars[id] as Node3D).position)
	var pose := vr_rig.pack_pose() if vr_rig != null else PackedFloat32Array()
	return [pose, ids, pos]


## TV machine: mirror the host's world.
func apply_snapshot(s: Array) -> void:
	if not ready_to_play:
		return
	if vr_avatar != null:
		vr_avatar.apply_pose(s[0])
	var ids: PackedInt32Array = s[1]
	var pos: PackedVector3Array = s[2]
	var seen := {}
	for i in ids.size():
		seen[ids[i]] = true
		var st: Node3D = stars[ids[i]] if stars.has(ids[i]) else _make_star(ids[i], pos[i])
		st.position = st.position.lerp(pos[i], 0.5)
	for id in stars.keys():
		if not seen.has(id):
			(stars[id] as Node).queue_free()
			stars.erase(id)


## TV machine: one-off events from the host.
func apply_event(kind: String, args: Array) -> void:
	match kind:
		"pop":
			pop(args[0], args[1])
