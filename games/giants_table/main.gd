extends Node3D
## GIANT'S TABLE: a cosy village on a big wooden table. Waves of goblins climb up the table edges
## to steal the embers of the village campfire.
##  - Player 1 (VR, host) is the GIANT: grab goblins and boulders with your hands and throw them.
##  - Players 2 and 3 (TV) are tiny KNIGHTS: sword, crossbow, carry embers home, revive each other.
##  - Armoured goblins: knights only (too spiky for the giant). Ogres: giant only (too big for knights).
## Modes (see docs/GAME_DEV_GUIDE.md): DUO_JOIN=<host> client, VR or DUO_HOST=1 host, else local split screen.

const W := preload("res://games/giants_table/world.gd")
const GiantScript := preload("res://games/giants_table/giant.gd")
const KnightScript := preload("res://games/giants_table/knight.gd")
const GoblinScript := preload("res://games/giants_table/goblin.gd")
const BoulderScript := preload("res://games/giants_table/boulder.gd")
const EmberScript := preload("res://games/giants_table/ember.gd")
const BoltScript := preload("res://games/giants_table/bolt.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")

const MAX_EMBERS := 10
const BOULDER_COUNT := 8
const DOWN_GRACE := 20.0  # seconds the giant has to carry a knight to the fire when all knights are down
const FIRE_HOME := 2.6    # drop an ember this close to the fire and it goes home
const PLAYER_COLORS: Array[Color] = [Color(0.3, 0.6, 1.0), Color(1.0, 0.72, 0.2), Color(1.0, 0.45, 0.75)]

var max_embers := MAX_EMBERS
var players: Array = []
var giant
var net: Node
var ready_to_play := false
var xr_interface: XRInterface
var vr_on := false
var mirror_vp: SubViewport
var mirror_t := 0.0
var net_ids := 0
var ghost_nodes := {}
var synced := false
var sfx: Node
var music: AudioStreamPlayer

var wave := 0
var score := 0
var embers := MAX_EMBERS
var spawn_queue: Array = []
var spawn_timer := 0.0
var break_timer := 4.0
var in_break := true
var game_over := false
var game_over_time := 0.0
var down_t := 0.0
var boulder_t := 0.0
var kills := {}  # how goblins were beaten (stats for tests)

var info_label: Label
var center_label: Label
var help_label: Label
var center_tween: Tween
var vr_center: Label3D
var fire_light: OmniLight3D
var flames: Array = []
var ember_orbs: Array = []
var fire_t := 0.0


func _ready() -> void:
	randomize()
	var xr := XRServer.find_interface("OpenXR")
	vr_on = xr != null and xr.is_initialized() and not OS.has_environment("DUO_JOIN")
	if OS.has_environment("GT_FAKE_VR") and not OS.has_environment("DUO_JOIN"):
		vr_on = true  # tests: run the VR code paths headless, without a headset
	W.build(self, vr_on)
	_build_fire()
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
		_show_center("Connecting to the Giant…", 0.0)
		net.join_finished.connect(func(ok: bool) -> void: _setup_game("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if vr_on or OS.has_environment("DUO_HOST"):
			net.host()
		_setup_game(net.mode)


func _setup_game(mode: String) -> void:
	_build_players(mode)
	_build_views(mode)
	_assign_joypads()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if mode != "client":
		for i in BOULDER_COUNT:
			var a := TAU * (i + 0.5) / BOULDER_COUNT
			_spawn_boulder(Vector3(cos(a) * (W.R - 0.2), 0.0, sin(a) * (W.R - 0.2)), false)
	ready_to_play = true
	print("Giant's Table: %s mode" % mode)
	var knight_help := "KNIGHTS: left stick / W S move · right stick / A D turn · RT / Space sword · LT / F crossbow · A / Shift jump\n"
	if mode == "local":
		help_label.text = knight_help \
			+ "GIANT (left screen): mouse or 2nd controller moves the hand · hold left click / RT to grab · flick and let go to throw\n" \
			+ "Armoured goblins: KNIGHTS only · Big ogres: GIANT only · Bring dropped embers home · The Giant can carry knights!"
	else:
		help_label.text = knight_help \
			+ "Player 3: press attack on the 2nd controller (or Enter / arrow keys) to join  ·  The GIANT in VR grabs and throws goblins and boulders\n" \
			+ "Armoured goblins: KNIGHTS only · Big ogres: GIANT only · Bring dropped embers home · Stand by a fallen friend to revive them"
	if mode == "host":
		_show_center("Waiting for the knights to join…", 0.0)
	elif mode == "client":
		_show_center("CONNECTED\nDefend the campfire!", 2.0)
	else:
		_show_center("GIANT'S TABLE\nDefend the campfire!", 2.5)


func next_net_id() -> int:
	net_ids += 1
	return net_ids


func knights() -> Array:
	return players.slice(1)


# --- Players and views -------------------------------------------------------

func _build_players(mode: String) -> void:
	giant = GiantScript.new()
	giant.main = self
	giant.color = PLAYER_COLORS[0]
	add_child(giant)
	players.append(giant)
	var count := 2 if mode != "local" else 1
	for i in range(1, count + 1):
		var k := KnightScript.new()
		k.main = self
		k.index = i
		k.color = PLAYER_COLORS[i]
		k.remote = mode == "host"
		k.key_set = i - 1
		k.position = Vector3(-1.2 + 2.4 * (i - 1), 0.0, 3.2)
		add_child(k)
		players.append(k)


func _build_views(mode: String) -> void:
	if vr_on and mode != "client":
		xr_interface = XRServer.find_interface("OpenXR")
		print("VR headset found: player 1 is the Giant")
		Engine.physics_ticks_per_second = 90
		get_viewport().use_xr = xr_interface != null and xr_interface.is_initialized()
		get_viewport().msaa_3d = Viewport.MSAA_2X
		var origin := XROrigin3D.new()
		add_child(origin)
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
		giant.setup_vr(origin, cam, left, right)
		_build_vr_mirror(cam)
	elif mode == "client":
		giant.setup_ghost()
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
	if not giant.vr and not giant.ghost:
		var vp := _add_view(row, giant)
		var cam := Camera3D.new()
		vp.add_child(cam)
		cam.current = true
		giant.setup_flat(cam, true)
	for k in knights():
		if k.remote:
			continue
		var vp := _add_view(row, k)
		var cam := Camera3D.new()
		vp.add_child(cam)
		cam.current = true
		k.attach_camera(cam)
		var hud := CanvasLayer.new()
		vp.add_child(hud)
		k.hud_label = _make_label(30)
		k.hud_label.add_theme_color_override("font_color", k.color.lightened(0.3))
		hud.add_child(k.hud_label)
		k.hud_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		k.hud_label.offset_top = -110
		k.hud_label.offset_left = 30
		k.hint_label = _make_label(34)
		k.hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hud.add_child(k.hint_label)
		k.hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		k.hint_label.offset_left = -500
		k.hint_label.offset_right = 500
		k.hint_label.offset_top = -330
		k.hint_label.offset_bottom = -200
	if players.size() > 2:
		players[2].set_active(false)
		on_player_activity_changed(players[2])


func _add_view(row: HBoxContainer, p) -> SubViewport:
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
	return vp


## Low-res copy of the giant's VR view for gdev / people watching.
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
	cam.near = 0.4
	cam.far = 2000.0
	cam.cull_mask = xr_cam.cull_mask
	vp.add_child(cam)
	cam.current = true
	var follow := RemoteTransform3D.new()
	xr_cam.add_child(follow)
	follow.remote_path = follow.get_path_to(cam)


func _assign_joypads() -> void:
	var pads := Input.get_connected_joypads()
	var locals: Array = []
	for k in knights():
		if not k.remote:
			locals.append(k)
	for i in locals.size():
		locals[i].joy = pads[i] if pads.size() > i else -1
	if giant.flat:
		giant.joy = pads[locals.size()] if pads.size() > locals.size() else -1
	for id in pads:
		print("Joypad %d: %s" % [id, Input.get_joy_name(id)])


func _on_joy_changed(_device: int, _connected: bool) -> void:
	if ready_to_play:
		_assign_joypads()


func on_player_activity_changed(p) -> void:
	if p.has_meta("view"):
		p.get_meta("view").visible = p.active


# --- Effects -----------------------------------------------------------------

func make_material(color: Color, glow: float) -> StandardMaterial3D:
	return W.mat(color, glow)


func burst(pos: Vector3, color: Color, amount: int = 16, size: float = 0.12) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -16, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var m := BoxMesh.new()
	m.size = Vector3.ONE * size
	m.material = W.mat(color, 1.5)
	p.mesh = m
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)
	if net:
		net.event("burst", [pos, color, amount, size])


func sound(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if sfx == null:
		sfx = SfxScript.new()
		add_child(sfx)
	sfx.play(sound_name, volume_db, pitch)
	if net:
		net.event("sound", [sound_name, volume_db, pitch])


## Floating 3D text, readable by the knights up close and by the giant from their seat.
func popup(pos: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.font_size = 64
	l.outline_size = 18
	l.pixel_size = 0.009
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	l.global_position = pos
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "global_position", pos + Vector3.UP * 1.2, 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.7)
	t.tween_property(l, "outline_modulate:a", 0.0, 0.8).set_delay(0.7)
	t.chain().tween_callback(l.queue_free)
	if net:
		net.event("popup", [pos, text, color])


## Something heavy hit the table: dust, a thump, and a buzz in the giant's nearest hand.
func add_thud(pos: Vector3, impact: float) -> void:
	if impact < 3.0:
		return
	burst(pos + Vector3.UP * 0.2, Color(0.85, 0.75, 0.55), int(clampf(impact, 6.0, 20.0)), 0.1)
	sound("hit", clampf(-14.0 + impact * 0.4, -14.0, 0.0), clampf(1.4 - impact * 0.02, 0.5, 1.4))
	if giant and giant.vr:
		giant.thud_haptic(pos, impact / 30.0)


# --- Campfire ----------------------------------------------------------------

func _build_fire() -> void:
	var logs := MeshInstance3D.new()
	var lm := W.cyl(0.13, 0.13, 1.3, 8)
	logs.mesh = lm
	logs.material_override = W.mat(Color(0.42, 0.25, 0.12))
	logs.rotation = Vector3(PI / 2.0, 0.6, 0.0)
	logs.position.y = 0.15
	add_child(logs)
	var logs2 := MeshInstance3D.new()
	logs2.mesh = lm
	logs2.material_override = logs.material_override
	logs2.rotation = Vector3(PI / 2.0, -0.6, 0.0)
	logs2.position.y = 0.22
	add_child(logs2)
	for spec in [[Color(1.0, 0.4, 0.1), 0.5, 1.4], [Color(1.0, 0.7, 0.2), 0.32, 1.0], [Color(1.0, 0.95, 0.6), 0.16, 0.6]]:
		var f := MeshInstance3D.new()
		f.mesh = W.cyl(0.0, spec[1], spec[2], 10)
		var m := W.mat(spec[0], 4.0)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		f.material_override = m
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.position.y = 0.25 + spec[2] * 0.5
		add_child(f)
		flames.append(f)
	fire_light = OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.6, 0.3)
	fire_light.light_energy = 2.5
	fire_light.omni_range = 9.0
	fire_light.position.y = 1.2
	add_child(fire_light)
	var sparks := CPUParticles3D.new()
	sparks.amount = 14
	sparks.lifetime = 1.4
	sparks.direction = Vector3.UP
	sparks.spread = 20.0
	sparks.initial_velocity_min = 1.0
	sparks.initial_velocity_max = 2.2
	sparks.gravity = Vector3(0, 0.5, 0)
	var sm := BoxMesh.new()
	sm.size = Vector3.ONE * 0.05
	sm.material = W.mat(Color(1.0, 0.7, 0.3), 4.0)
	sparks.mesh = sm
	sparks.position.y = 0.8
	add_child(sparks)
	for i in MAX_EMBERS:
		var o := MeshInstance3D.new()
		o.mesh = W.sphere(0.13, 8)
		o.material_override = W.mat(Color(1.0, 0.6, 0.2), 4.0)
		o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(o)
		ember_orbs.append(o)


func _update_fire(delta: float) -> void:
	fire_t += delta
	var strength := clampf(float(embers) / MAX_EMBERS, 0.0, 1.0)
	for i in flames.size():
		var f: MeshInstance3D = flames[i]
		var flick := 1.0 + sin(fire_t * (9.0 + i * 3.0)) * 0.08 + sin(fire_t * 23.0 + i) * 0.05
		var s := (0.35 + 0.65 * strength) * flick
		f.scale = Vector3(s, s * (1.0 + 0.1 * sin(fire_t * 13.0 + i)), s)
		f.visible = embers > 0
	fire_light.light_energy = (0.6 + 2.2 * strength) * (1.0 + sin(fire_t * 17.0) * 0.08)
	for i in ember_orbs.size():
		var o: MeshInstance3D = ember_orbs[i]
		o.visible = i < embers
		var a := fire_t * 0.8 + TAU * i / MAX_EMBERS
		o.position = Vector3(cos(a) * 1.45, 1.3 + sin(fire_t * 2.0 + i) * 0.15, sin(a) * 1.45)


# --- Main loop ---------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	if music == null:
		music = MusicScript.new()
		add_child(music)
	music.play_track(maxi(wave - 1, 0) / 2)
	_update_fire(delta)
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_update_hud()
	_update_vr_center()
	if net.mode == "client":
		_check_join()
		if game_over:
			game_over_time += delta
			if game_over_time > 1.5 and _restart_pressed():
				game_over_time = 0.0
				net.send_action("restart", [])
		return
	if game_over:
		game_over_time += delta
		if game_over_time > 1.5 and (_restart_pressed() or giant.restart_held()):
			get_tree().reload_current_scene()
		return
	if net.mode == "host" and not net.connected:
		return  # hold the waves until the knights join
	_host_knights(delta)
	_update_boulders(delta)
	if in_break:
		break_timer -= delta
		if break_timer <= 0.0:
			_start_wave()
	elif not spawn_queue.is_empty():
		spawn_timer -= delta
		var alive := get_tree().get_nodes_in_group("goblins").size()
		if spawn_timer <= 0.0 and alive < mini(6 + wave * 2, 18):
			_spawn_goblin(spawn_queue.pop_back())
			spawn_timer = maxf(0.5, 1.6 - wave * 0.08)
	elif get_tree().get_nodes_in_group("goblins").is_empty():
		_end_wave()
	_check_lose(delta)


func _restart_pressed() -> bool:
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_R):
		return true
	for k in knights():
		if not k.remote and k.active and k.any_attack_held():
			return true
	return false


## TV: player 3 joins by pressing attack on the second controller / keyboard set.
var join_t := 0.0
func _check_join() -> void:
	join_t -= get_process_delta_time()
	if players.size() < 3 or players[2].active or join_t > 0.0 or game_over:
		return
	if players[2].any_attack_held():
		join_t = 1.0
		net.send_action("join", [], 2)


# --- Waves -------------------------------------------------------------------

func _start_wave() -> void:
	wave += 1
	in_break = false
	print("Wave %d started" % wave)
	spawn_queue.clear()
	for i in 3 + wave * 2:
		spawn_queue.append("goblin")
	if wave >= 2:
		for i in mini(wave - 1, 6):
			spawn_queue.append("armored")
	if wave >= 3:
		for i in 1 + (wave - 3) / 3:
			spawn_queue.append("ogre")
	spawn_queue.shuffle()
	spawn_queue.append("goblin")  # the first one out is always an easy one
	spawn_timer = 0.5
	sound("wave")
	var extra := ""
	if wave == 2:
		extra = "\nArmoured goblins! Only KNIGHTS can beat them"
	elif wave == 3:
		extra = "\nAn OGRE! Only the GIANT can lift it - throw it off the table!"
	_show_center("WAVE %d%s" % [wave, extra], 2.5 if extra != "" else 1.4)
	if wave == 2:
		create_tween().tween_property(help_label, "modulate:a", 0.0, 1.0)


func _end_wave() -> void:
	in_break = true
	break_timer = 4.0
	embers = mini(embers + 1, MAX_EMBERS)
	for k in knights():
		if not k.active:
			continue
		if k.is_down:
			_revive(k, 0.6)
		else:
			k.hp = minf(KnightScript.MAX_HP, k.hp + 30.0)
	_show_center("WAVE %d CLEARED!\nThe campfire grows: +1 ember" % wave, 2.6)
	sound("clear")


func _spawn_goblin(kind: String) -> void:
	var a := randf() * TAU
	var dir := Vector3(cos(a), 0.0, sin(a))
	var g := GoblinScript.new()
	g.setup(kind, self)
	g.net_id = next_net_id()
	g.position = dir * (W.EDGE - 0.3) + Vector3.DOWN * 1.0
	add_child(g)
	g.rotation.y = atan2(dir.x, dir.z)
	g.flying = true
	g.hop = true
	g.vel = -dir * 2.5 + Vector3.UP * 11.0


func _check_lose(delta: float) -> void:
	# The fire goes out when no embers are left anywhere to win back.
	if embers <= 0:
		var recoverable := not get_tree().get_nodes_in_group("embers").is_empty()
		for g in get_tree().get_nodes_in_group("goblins"):
			if g.carrying:
				recoverable = true
		for k in knights():
			if k.carrying:
				recoverable = true
		if not recoverable:
			_on_game_over("The goblins stole the campfire!")
			return
	var any_active := false
	var any_up := false
	for k in knights():
		if k.active:
			any_active = true
			if not k.is_down:
				any_up = true
	if any_active and not any_up:
		var before := int(DOWN_GRACE - down_t)
		down_t += delta
		var left := int(DOWN_GRACE - down_t)
		if left != before:
			_show_center("ALL KNIGHTS ARE DOWN!\nGiant: carry a knight to the campfire!  %d" % maxi(left, 0), 0.0)
		if down_t >= DOWN_GRACE:
			_on_game_over("All the knights fell asleep!")
	elif down_t > 0.0:
		down_t = 0.0
		_show_center("", 0.0)


func _on_game_over(reason: String) -> void:
	if game_over:
		return
	game_over = true
	game_over_time = 0.0
	giant.release_all()
	print("Game over: %s wave=%d score=%d" % [reason, wave, score])
	sound("gameover")
	var how := "Press A / X (VR) or attack (knights) to play again"
	_show_center("GAME OVER\n%s\nWave %d   ·   Score %d\n%s" % [reason, wave, score, how], 0.0)


# --- Goblins -----------------------------------------------------------------

func goblin_steals(g) -> void:
	if embers <= 0 or g.carrying:
		return
	embers -= 1
	g.carrying = true
	var away := Vector3(g.global_position.x, 0.0, g.global_position.z)
	if away.length() < 0.1:
		away = Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1))
	g.flee_target = away.normalized() * (W.EDGE + 3.0)
	sound("spit", -2.0, 0.9)
	popup(g.grab_center() + Vector3.UP * 0.8, "Ember stolen!", Color(1.0, 0.55, 0.3))


func goblin_takes_loose_ember(g, e) -> void:
	if g.carrying:
		return
	e.queue_free()
	g.carrying = true
	var away := Vector3(g.global_position.x, 0.0, g.global_position.z)
	g.flee_target = away.normalized() * (W.EDGE + 3.0)
	sound("spit", -4.0, 1.1)


func goblin_escaped(g) -> void:
	if g.has_meta("dead"):
		return
	g.set_meta("dead", true)
	popup(g.grab_center() + Vector3.UP * 0.8, "An ember got away!", Color(1.0, 0.4, 0.3))
	sound("hurt", -2.0, 0.6)
	g.queue_free()


func goblin_defeated(g, how: String, by) -> void:
	if g.has_meta("dead"):
		return
	g.set_meta("dead", true)
	var points: int = GoblinScript.KINDS[g.kind].points
	score += points
	var stat_key := "%s:%s" % [g.kind, how]
	kills[stat_key] = kills.get(stat_key, 0) + 1
	var pos: Vector3 = g.global_position
	var center: Vector3 = g.grab_center()
	var c: Color = g.color
	burst(center, c, 18 if g.kind != "ogre" else 34, 0.12 if g.kind != "ogre" else 0.22)
	burst(center, Color(1.0, 0.95, 0.7), 8, 0.08)
	if g.kind == "ogre":
		sound("big_kill", -2.0, 1.2)
	else:
		sound("kill", -6.0, randf_range(1.1, 1.4))
	var words := {"squash": "SQUASH!", "fell": "BYE BYE!", "slam": "BOOM!", "boulder": "BONK!", "knight": "POW!"}
	popup(center + Vector3.UP * 0.5, "%s +%d" % [words.get(how, "POW!"), points], c.lightened(0.4))
	if how in ["squash", "slam", "boulder"]:
		add_thud(pos, 12.0)
	if g.carrying:
		if how != "fell" and Vector2(pos.x, pos.z).length() < W.EDGE and pos.y > -2.0:
			var gh := W.height(pos.x, pos.z)
			_spawn_ember(Vector3(pos.x, maxf(gh, 0.0), pos.z))
		else:
			embers = mini(embers + 1, MAX_EMBERS)
			popup(Vector3(0.0, 2.6, 0.0), "The ember flew home!", Color(1.0, 0.75, 0.35))
	g.queue_free()


# --- Knights (host side) -----------------------------------------------------

func knight_action(k, action: String, args: Array) -> void:
	if net.mode == "client":
		net.send_action(action, args, k.index)
	else:
		do_knight_action(k.index, action, args)


func on_p2_action(action: String, args: Array, index: int = 1) -> void:
	match action:
		"join":
			var k = players[index]
			if not k.active:
				k.set_active(true)
				k.hp = KnightScript.MAX_HP
				k.global_position = Vector3(1.5, 0.0, 3.0)
				_show_center("PLAYER %d JOINED!" % (index + 1), 1.5)
				print("Net: player %d joined the game" % (index + 1))
		"restart":
			if game_over:
				get_tree().reload_current_scene()
		"pause":
			var paused: bool = args[0]
			_set_pause_banner(paused, "A knight opened the menu")
			get_tree().paused = paused
		_:
			do_knight_action(index, action, args)


func do_knight_action(index: int, action: String, args: Array) -> void:
	var k = players[index]
	if not k.active or k.is_down or game_over:
		return
	match action:
		"swing":
			var pos: Vector3 = args[0]
			var f: float = args[1]
			var fwd := Basis(Vector3.UP, f) * Vector3(0, 0, -1)
			if k.remote:
				k.swing_t = 0.25
				k.sword_cd = KnightScript.SWORD_CD
			var hit := false
			for g in get_tree().get_nodes_in_group("goblins"):
				if g.held or g.has_meta("dead"):
					continue
				var to: Vector3 = g.global_position - pos
				to.y = 0.0
				var d := to.length()
				var reach: float = 1.25 + g.radius
				if d > reach or absf(g.global_position.y - pos.y) > 1.5:
					continue
				if d > 0.3 and fwd.dot(to / d) < 0.25:
					continue
				g.hit_by_knight(2.0, to / maxf(d, 0.01), k)
				hit = true
			if hit:
				burst(pos + fwd * 0.9 + Vector3.UP * 0.5, Color(1.0, 1.0, 0.85), 8, 0.06)
		"shoot":
			var origin: Vector3 = args[0]
			var dir: Vector3 = args[1]
			spawn_bolt(origin, dir, k, false)


func spawn_bolt(origin: Vector3, dir: Vector3, shooter, visual_only: bool) -> void:
	var b := BoltScript.new()
	b.main = self
	b.shooter = shooter
	b.visual_only = visual_only
	add_child(b)
	b.global_position = origin
	b.launch(dir)


## Nudges a knight's aim towards a goblin roughly in front of them.
func auto_aim(from: Vector3, dir: Vector3) -> Vector3:
	var best := dir
	var best_dot := cos(deg_to_rad(28.0))
	for g in get_tree().get_nodes_in_group("goblins"):
		var to: Vector3 = g.grab_center() - from
		var dist := to.length()
		if dist < 0.3 or dist > 16.0:
			continue
		var flat_dir := Vector3(to.x, 0.0, to.z).normalized()
		var d := dir.dot(flat_dir)
		if d > best_dot:
			best_dot = d
			best = (to + Vector3.UP * dist * dist * 0.004).normalized()
	return best


func knight_hurt(k, dmg: float, from: Vector3) -> void:
	if k.is_down or k.carried or not k.active or game_over:
		return
	k.hp -= dmg
	k.on_hurt(from)
	net.event("hurt", [k.index, from])
	sound("hurt", -6.0, 1.0 + k.index * 0.15)
	if k.hp <= 0.0:
		k.hp = 0.0
		k.set_down(true)
		k.revive_progress = 0.0
		sound("down", -2.0)
		burst(k.global_position + Vector3.UP * 0.5, k.color, 18)
		popup(k.global_position + Vector3.UP * 1.6, "P%d is down!" % (k.index + 1), k.color)
		print("P%d is down" % (k.index + 1))
		if k.carrying:
			k.carrying = false
			_spawn_ember(k.global_position + Vector3.UP * 0.05)


func _revive(k, fraction: float) -> void:
	print("P%d is back on their feet" % (k.index + 1))
	k.set_down(false)
	k.hp = KnightScript.MAX_HP * fraction
	k.revive_progress = 0.0
	burst(k.global_position + Vector3.UP * 0.6, Color(0.6, 1.0, 0.6), 18)
	sound("revive", -2.0)
	popup(k.global_position + Vector3.UP * 1.6, "Back on your feet!", Color(0.7, 1.0, 0.7))


func _host_knights(delta: float) -> void:
	for k in knights():
		if not k.active:
			continue
		var pos: Vector3 = k.global_position
		var fire_d := Vector2(pos.x, pos.z).length()
		if k.carried and not k.held:
			_fall_knight(k, delta)
			continue
		if k.carried:
			continue
		if k.is_down:
			var helper := false
			for o in knights():
				if o != k and o.active and not o.is_down and not o.carried and o.global_position.distance_to(pos) < KnightScript.REVIVE_RANGE:
					helper = true
			if helper or fire_d < 2.6:
				k.revive_progress += delta / KnightScript.REVIVE_TIME
			else:
				k.revive_progress = maxf(0.0, k.revive_progress - delta * 0.2)
			if k.revive_progress >= 1.0:
				_revive(k, 0.6)
			continue
		if fire_d < 3.0:
			k.hp = minf(KnightScript.MAX_HP, k.hp + 5.0 * delta)  # warm by the fire
		if not k.carrying:
			for e in get_tree().get_nodes_in_group("embers"):
				if e.held or e.flying or e.is_queued_for_deletion():
					continue
				if e.global_position.distance_to(pos) < 0.9:
					e.queue_free()
					k.carrying = true
					sound("pickup", -4.0)
					popup(pos + Vector3.UP * 1.8, "Got an ember!", Color(1.0, 0.75, 0.35))
					break
		elif fire_d < 2.4:
			k.carrying = false
			embers = mini(embers + 1, MAX_EMBERS)
			score += 5
			sound("revive", -4.0, 1.3)
			popup(Vector3(0.0, 2.4, 0.0), "Ember home! +5", Color(1.0, 0.8, 0.4))


## A knight the giant let go of floats down (knights are light: no fall damage).
func _fall_knight(k, delta: float) -> void:
	k.fall_vel.y = maxf(k.fall_vel.y - 30.0 * delta, -11.0)
	k.fall_vel.x *= 1.0 - minf(1.0, delta * 1.5)
	k.fall_vel.z *= 1.0 - minf(1.0, delta * 1.5)
	var p: Vector3 = k.global_position + k.fall_vel * delta
	var g := W.height(p.x, p.z)
	for b in get_tree().get_nodes_in_group("boulders"):
		if b.held or b.flying:
			continue
		var bp: Vector3 = b.global_position
		if Vector2(p.x - bp.x, p.z - bp.z).length() < b.radius:
			g = maxf(g, bp.y + b.radius * 1.8)
	if g < -50.0 and p.y < -4.0:
		p = Vector3(0.0, 0.0, 2.4)
		k.carried = false
		popup(p + Vector3.UP * 1.6, "Whoops! Back to the campfire", k.color)
		sound("revive", -6.0, 0.8)
	elif p.y <= g:
		p = W.push_out(Vector3(p.x, g, p.z), KnightScript.BODY_R)
		p.y = maxf(W.height(p.x, p.z), g)
		k.carried = false
		sound("dash", -8.0, 0.7)
	k.global_position = p
	k.net_target = p
	if not k.carried and k.is_down and Vector2(p.x, p.z).length() < 3.2:
		_revive(k, 0.8)


func on_grabbed(obj) -> void:
	sound("pickup", -6.0, 0.8 if obj.is_in_group("boulders") else 1.2)
	if obj.is_in_group("knights"):
		popup(obj.grab_center() + Vector3.UP * 1.2, "Wheee!", obj.color)
	elif obj.is_in_group("goblins") and randf() < 0.5:
		popup(obj.grab_center() + Vector3.UP * 0.9, ["Eek!", "Put me down!", "Help!"].pick_random(), Color(0.7, 1.0, 0.5))


func on_released(_obj, v: Vector3) -> void:
	if v.length() > 14.0:
		sound("dash", -6.0, 0.6)


# --- Boulders and embers -----------------------------------------------------

func _spawn_boulder(pos: Vector3, drop: bool) -> void:
	var b := BoulderScript.new()
	b.main = self
	b.net_id = next_net_id()
	b.position = pos
	add_child(b)
	if drop:
		b.flying = true
		b.vel = Vector3.ZERO
	else:
		b.position.y = W.height(pos.x, pos.z)


func _update_boulders(delta: float) -> void:
	boulder_t -= delta
	if boulder_t > 0.0:
		return
	boulder_t = 2.5
	if get_tree().get_nodes_in_group("boulders").size() < BOULDER_COUNT:
		var a := randf() * TAU
		_spawn_boulder(Vector3(cos(a) * (W.R - 0.4), 9.0, sin(a) * (W.R - 0.4)), true)


func boulder_lost(b) -> void:
	b.queue_free()


func _spawn_ember(pos: Vector3) -> void:
	var e := EmberScript.new()
	e.main = self
	e.net_id = next_net_id()
	e.position = pos
	add_child(e)
	e.flying = true  # pops out and lands (home, if it lands by the fire)
	e.vel = Vector3(randf_range(-2.0, 2.0), 7.0, randf_range(-2.0, 2.0))


func ember_landed(e) -> void:
	var p: Vector3 = e.global_position
	if Vector2(p.x, p.z).length() < FIRE_HOME:
		ember_home(e, "Ember home! +5")


func ember_home(e, msg: String) -> void:
	if e.has_meta("home"):
		return
	e.set_meta("home", true)
	e.queue_free()
	embers = mini(embers + 1, MAX_EMBERS)
	score += 5
	sound("revive", -4.0, 1.3)
	popup(Vector3(0.0, 2.6, 0.0), msg, Color(1.0, 0.8, 0.4))


# --- Networking --------------------------------------------------------------

func on_client_joined() -> void:
	_show_center("THE KNIGHTS HAVE ARRIVED!", 1.5)


func on_client_left() -> void:
	_show_center("The knights left - waiting for them to come back…", 0.0)


func _set_pause_banner(paused: bool, who: String) -> void:
	_show_center("PAUSED\n" + who if paused else "", 0.0, false)
	_update_vr_center()


func toggle_vr_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_set_pause_banner(paused, "Press the menu button to resume")
	net.event("remote_pause", [paused])


func make_snapshot() -> Array:
	var ps: Array = []
	for p in players:
		ps.append(p.net_state())
	var gs: Array = []
	for g in get_tree().get_nodes_in_group("goblins"):
		if not g.is_queued_for_deletion():
			gs.append(g.net_item())
	var bs: Array = []
	for b in get_tree().get_nodes_in_group("boulders"):
		if not b.is_queued_for_deletion():
			bs.append(b.net_item())
	var es: Array = []
	for e in get_tree().get_nodes_in_group("embers"):
		if not e.is_queued_for_deletion():
			es.append(e.net_item())
	return [wave, score, embers, game_over, down_t, ps, gs, bs, es]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play:
		return
	synced = true
	wave = s[0]
	score = s[1]
	embers = s[2]
	var was_over := game_over
	game_over = s[3]
	if game_over and not was_over:
		game_over_time = 0.0
	down_t = s[4]
	var ps: Array = s[5]
	for i in mini(players.size(), ps.size()):
		players[i].apply_net_state(ps[i])
	_sync_ghosts(s[6], "goblin")
	_sync_ghosts(s[7], "boulder")
	_sync_ghosts(s[8], "ember")


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
	var n: Node3D
	match kind:
		"goblin":
			var g := GoblinScript.new()
			g.setup(item[1], self)
			n = g
		"boulder":
			n = BoulderScript.new()
		_:
			n = EmberScript.new()
	n.set("main", self)
	n.set("ghost", true)
	n.set("net_id", item[0])
	n.position = item[2]
	add_child(n)
	return n


func apply_event(kind: String, args: Array) -> void:
	if not ready_to_play:
		return
	match kind:
		"sound":
			sound(args[0], args[1], args[2])
		"burst":
			burst(args[0], args[1], args[2], args[3])
		"popup":
			popup(args[0], args[1], args[2])
		"center":
			_show_center(args[0], args[1])
		"remote_pause":
			get_tree().paused = args[0]
			_set_pause_banner(args[0], "The Giant paused the game")
		"hurt":
			var i: int = args[0]
			if i < players.size():
				players[i].on_hurt(args[1])


# --- HUD ---------------------------------------------------------------------

func _make_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", maxi(6, size / 4))
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02, 0.95))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	info_label = _make_label(32)
	info_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.65))
	layer.add_child(info_label)
	info_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	info_label.offset_top = 16
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label = _make_label(56)
	center_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	layer.add_child(center_label)
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	help_label = _make_label(22)
	layer.add_child(help_label)
	help_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	help_label.offset_top = 70
	help_label.offset_bottom = 200
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.text = "KNIGHTS: left stick / W S move · right stick / A D turn · RT / Space sword · LT / F crossbow · A / Shift jump\n" \
		+ "GIANT: mouse moves the hand · hold left click to grab · flick and let go to throw (VR: grip or trigger)\n" \
		+ "Armoured goblins: KNIGHTS only · Big ogres: GIANT only · Bring dropped embers home · Stand by a fallen friend to revive them"


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


## VR can't show 2D overlays: mirror the centre banner on a Label3D in front of the giant's eyes.
func _update_vr_center() -> void:
	if giant == null or not giant.vr:
		return
	if vr_center == null:
		vr_center = Label3D.new()
		vr_center.font_size = 48
		vr_center.outline_size = 26
		vr_center.outline_modulate = Color.BLACK
		vr_center.no_depth_test = true
		vr_center.render_priority = 10
		vr_center.outline_render_priority = 9
		vr_center.width = 900.0
		vr_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vr_center.modulate = Color(1.0, 0.95, 0.8)
		vr_center.pixel_size = 0.0026 * W.S
		vr_center.position = Vector3(0.0, -0.12, -1.7) * W.S
		giant.xr_camera.add_child(vr_center)
		giant._set_layers(vr_center, 1)
	vr_center.text = center_label.text
	vr_center.modulate.a = center_label.modulate.a
	vr_center.outline_modulate.a = center_label.modulate.a


func _update_hud() -> void:
	if wave >= 2 and help_label.modulate.a > 0.0:
		help_label.modulate.a = maxf(0.0, help_label.modulate.a - get_process_delta_time() * 0.5)
	if net.mode == "client" and not synced:
		info_label.text = "Syncing with the Giant…"
		return
	info_label.text = "WAVE %d      SCORE %d      CAMPFIRE EMBERS %d / %d" % [wave, score, embers, MAX_EMBERS]
