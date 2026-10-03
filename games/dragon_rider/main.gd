extends Node3D
## DRAGON RIDER: a co-op flying adventure through a sunset sky.
## The rider (VR, host, players[0]) sits in the saddle of a big friendly dragon and steers it with the
## reins (hand positions): fly through the glowing rings and scoop up stars. Right trigger flaps.
## The gunners (TV players 1-6) sit on the deck on the dragon's back with bubble cannons and look
## all around: pop balloons for points and pop the storm sprites before they sneak in and pop the
## dragon's four lanterns. Fly through the last ring to finish the level (it re-lights a lantern).
## All lanterns out = game over.
##
## Files: dragon.gd (model + flight), course.gd (rings, stars, balloons, islands from a seed),
## rider.gd (players[0]), gunner.gd (players 1-6), sprite.gd, bubble.gd, hud.gd, world.gd (sky),
## join_listener.gd (drop-in join with A). The host simulates; the TV machine mirrors snapshots and
## rebuilds the same course from the level seed.

const WorldScript := preload("res://games/dragon_rider/world.gd")
const DragonScript := preload("res://games/dragon_rider/dragon.gd")
const CourseScript := preload("res://games/dragon_rider/course.gd")
const RiderScript := preload("res://games/dragon_rider/rider.gd")
const GunnerScript := preload("res://games/dragon_rider/gunner.gd")
const SpriteScript := preload("res://games/dragon_rider/sprite.gd")
const BubbleScript := preload("res://games/dragon_rider/bubble.gd")
const HudScript := preload("res://games/dragon_rider/hud.gd")
const JoinListenerScript := preload("res://games/dragon_rider/join_listener.gd")
const SfxScript := preload("res://core/sfx.gd")
const MusicScript := preload("res://core/music.gd")
const NetScript := preload("res://core/net.gd")
const PauseMenuScript := preload("res://core/pause_menu.gd")
const VrText := preload("res://core/vr_text.gd")

const MAX_PLAYERS := 7  # rider + 6 gunners
const MAX_LOCAL_VIEWS := 6
const INTRO_TIME := 6.0
const DONE_TIME := 7.0
const PAD_LEAVE_TIME := 20.0
const BUBBLE_SPEED := 36.0
const PLAYER_COLORS: Array[Color] = [Color(1.0, 0.6, 0.3), Color(0.35, 0.7, 1.0), Color(0.55, 0.9, 0.4),
	Color(1.0, 0.45, 0.7), Color(0.75, 0.55, 1.0), Color(1.0, 0.85, 0.3), Color(0.4, 0.95, 0.85)]
const SOUNDS := {
	"bubble": [0.09, 380.0, 900.0, 0.16, "sine", 0.05],
	"pop": [0.12, 900.0, 260.0, 0.32, "sine", 0.35],
	"ring": [0.55, 660.0, 1320.0, 0.32, "tri", 0.0],
	"bullseye": [0.7, 784.0, 1568.0, 0.35, "tri", 0.0],
	"star": [0.25, 1250.0, 2500.0, 0.22, "sine", 0.0],
	"flap": [0.4, 140.0, 55.0, 0.45, "sine", 0.65],
	"giggle": [0.35, 900.0, 1500.0, 0.18, "square", 0.25],
	"lantern": [0.7, 420.0, 70.0, 0.5, "saw", 0.45],
	"miss": [0.35, 330.0, 220.0, 0.22, "tri", 0.0],
	"zap": [0.18, 1600.0, 300.0, 0.28, "saw", 0.5],
	"hit": [0.06, 500.0, 300.0, 0.2, "square", 0.3],
	"levelup": [1.0, 392.0, 1568.0, 0.4, "tri", 0.0],
	"gameover": [1.4, 330.0, 50.0, 0.45, "saw", 0.15],
	"join": [0.45, 330.0, 1320.0, 0.3, "sine", 0.0],
}
const VIGNETTE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, depth_test_disabled, blend_mix;
uniform float strength = 0.0;
varying vec3 lp;
void vertex() {
	lp = VERTEX;
}
void fragment() {
	vec3 d = normalize(lp);
	float edge = 1.0 - smoothstep(0.35, 0.85, -d.z);
	ALBEDO = vec3(0.04, 0.02, 0.06);
	ALPHA = clamp(edge * strength, 0.0, 0.92);
}
"""

var players: Array = []
var ready_to_play := false
var net: Node
var sfx: Node
var music: Node
var world: Node3D
var dragon: Node3D
var course: Node3D
var arrow: Node3D
var mats := {}
var meshes := {}
var xr_interface: XRInterface
var mirror_vp: SubViewport
var mirror_t := 0.0
var views_root: Control
var view_count := 0
var last_view_area := Vector2.ZERO
var joy_owner := {}  # joypad device id -> player index
var join_listener: Node
var synced := false
var bubble_mat: StandardMaterial3D

var phase := "wait"  # wait, intro, fly, done, over
var phase_t := 0.0
var level := 0
var level_seed := 0
var course_origin := Vector3.ZERO
var course_yaw := 0.0
var ring_i := 0
var ring_last_d := -1.0
var score := 0
var stars_got := 0
var rings_got := 0
var level_rings := 0
var sprites_popped := 0
var distance := 0.0
var sprite_t := 4.0
var next_id := 0
var best := 0
var game_over_time := 0.0
var confirm_was := true
var center_text := ""
var center_alpha := 0.0
var center_left := 0.0  # seconds before the banner fades (0: stays)
var fallback_label: Label
var vr_center: Label3D
var vr_status: Label3D
var vignette: MeshInstance3D
var vignette_mat: ShaderMaterial
var join_t := 0.0


func _ready() -> void:
	randomize()
	var xr := XRServer.find_interface("OpenXR")
	var will_vr := xr != null and xr.is_initialized() and not OS.has_environment("DUO_JOIN")
	world = WorldScript.new()
	world.main = self
	add_child(world)
	world.build(will_vr)
	dragon = DragonScript.new()
	dragon.name = "Dragon"
	dragon.main = self
	add_child(dragon)
	dragon.position = Vector3(0, 45, 0)
	_build_arrow()
	bubble_mat = StandardMaterial3D.new()
	bubble_mat.albedo_color = Color(0.75, 0.95, 1.0, 0.5)
	bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bubble_mat.emission_enabled = true
	bubble_mat.emission = Color(0.55, 0.85, 1.0)
	bubble_mat.emission_energy_multiplier = 0.9
	bubble_mat.roughness = 0.1
	_build_fallback_label()
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
		show_center("Connecting to the dragon rider…", 0.0, false)
		net.join_finished.connect(func(ok: bool) -> void: _setup_game("client" if ok else "local"))
		net.join(OS.get_environment("DUO_JOIN"))
	else:
		if will_vr or OS.has_environment("DUO_HOST"):
			net.host()
		_setup_game(net.mode)


func _exit_tree() -> void:
	XRServer.world_scale = 1.0  # global: never leak a scale into the next game


func _setup_game(mode: String) -> void:
	_build_players(mode)
	_build_views(mode)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_assign_joypads()
	ready_to_play = true
	_ensure_join_listener()
	_restore_party()
	if mode == "host":
		show_center("DRAGON RIDER\nWaiting for the gunners on the TV to join…\nPractice flying: hands back = climb, forward = dive, left / right = turn", 0.0)
	elif mode == "client":
		show_center("CONNECTED!\nClimb aboard, gunners!", 2.0, false)


# --- Shared materials, meshes and effects ------------------------------------

func make_material(color: Color, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.75
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


func color_mat(color: Color, glow: float) -> StandardMaterial3D:
	var key := "%s/%.2f" % [color.to_html(), glow]
	if not mats.has(key):
		mats[key] = make_material(color, glow)
	return mats[key]


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
		cm.radial_segments = 14
		cm.rings = 4
		meshes[key] = cm
	return meshes[key]


func prism_mesh(size: Vector3) -> PrismMesh:
	var key := "r%s" % size
	if not meshes.has(key):
		var pm := PrismMesh.new()
		pm.size = size
		pm.left_to_right = 0.2
		meshes[key] = pm
	return meshes[key]


## A chunky low-poly star gem.
func gem_mesh() -> SphereMesh:
	if not meshes.has("gem"):
		var sm := SphereMesh.new()
		sm.radius = 0.9
		sm.height = 1.8
		sm.radial_segments = 5
		sm.rings = 2
		meshes["gem"] = sm
	return meshes["gem"]


## A basis whose Y axis points along dir.
func basis_y_to(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)


func puff(pos: Vector3, color: Color, amount: int = 12, size: float = 0.15) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -2.0, 0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	var key := "puff%s%.2f" % [color.to_html(), size]
	if not meshes.has(key):
		var m := SphereMesh.new()
		m.radius = size
		m.height = size * 2.0
		m.radial_segments = 6
		m.rings = 3
		m.material = color_mat(color, 1.2)
		meshes[key] = m
	p.mesh = meshes[key]
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func burst(pos: Vector3, color: Color, amount: int = 16, size: float = 0.15) -> void:
	puff(pos, color, amount, size)
	net.event("burst", [pos, color, amount, size])


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


## Floating text that rides along with the dragon (local = dragon-local position).
func popup(local: Vector3, text: String, color: Color, broadcast: bool = true) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.outline_modulate = Color(0.1, 0.03, 0.1, 0.9)
	l.font_size = 64
	l.outline_size = 20
	l.pixel_size = 0.012
	l.no_depth_test = true
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dragon.add_child(l)
	l.position = local
	if not players.is_empty() and players[0].vr:
		var to: Vector3 = l.global_position - players[0].xr_camera.global_position
		l.global_basis = Basis(Vector3.UP, atan2(-to.x, -to.z))  # upright, facing the rider
	else:
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "position", local + Vector3.UP * 1.5, 1.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.9)
	t.tween_property(l, "outline_modulate:a", 0.0, 0.8).set_delay(0.9)
	t.chain().tween_callback(l.queue_free)
	if broadcast:
		net.event("popup", [local, text, color])


func to_dragon_local(world_pos: Vector3) -> Vector3:
	return dragon.global_transform.affine_inverse() * world_pos


## A gold arrow floating ahead of the dragon's nose, pointing at the next ring.
func _build_arrow() -> void:
	arrow = Node3D.new()
	dragon.add_child(arrow)
	arrow.position = Vector3(0, 0.6, -9.0)
	var m := MeshInstance3D.new()
	m.mesh = prism_mesh(Vector3(0.9, 1.3, 0.22))
	m.material_override = color_mat(Color(1.0, 0.82, 0.3), 2.0)
	m.rotation.x = -PI / 2.0
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arrow.add_child(m)
	arrow.visible = false


# --- Game flow (host) ----------------------------------------------------------

func _start_level(n: int) -> void:
	level = n
	level_seed = randi() % 1000000
	course_origin = dragon.global_position
	course_yaw = dragon.yaw
	_build_course()
	ring_i = 0
	ring_last_d = -1.0
	level_rings = 0
	sprite_t = 2.0
	phase = "intro"
	phase_t = INTRO_TIME if n == 1 else 3.5
	if music != null and music.has_method("play_track"):
		music.play_track(n - 1)
	print("Level %d: %d rings, seed %d, %d gunners" % [n, course.rings.size(), level_seed, gunner_count()])
	sound("levelup", -4.0, 0.8 + n * 0.05)
	if n == 1:
		show_center("DRAGON RIDER\nRider: fly through the GOLD rings and scoop up the stars\nReins: hands back = up, forward = down, left / right = turn, trigger = flap, A = re-centre\nGunners: pop the balloons, and the storm sprites before they pop our lanterns!", INTRO_TIME)
	else:
		show_center("LEVEL %d\n%d rings to the sunset gate. Watch out, more storm sprites!" % [n, course.rings.size()], phase_t)


func _build_course() -> void:
	if course != null and is_instance_valid(course):
		var old := course
		for b in old.balloons:
			var node: Node3D = b.node
			if node.is_in_group("dr_targets"):
				node.remove_from_group("dr_targets")
		get_tree().create_timer(8.0).timeout.connect(func() -> void:
			if is_instance_valid(old):
				old.queue_free())
	course = CourseScript.new()
	course.main = self
	add_child(course)
	course.build(level_seed, course_origin, course_yaw, level)


func _host_update(delta: float) -> void:
	match phase:
		"wait":
			if net.mode != "host" or net.connected:
				_start_level(1)
		"intro":
			phase_t -= delta
			if phase_t <= 0.0:
				phase = "fly"
		"done":
			phase_t -= delta
			if phase_t <= DONE_TIME - 1.5 and _confirm_pressed():
				phase_t = 0.0
			if phase_t <= 0.0:
				_start_level(level + 1)
		"over":
			game_over_time += delta
			if game_over_time > 1.5 and _confirm_pressed():
				get_tree().reload_current_scene()
	if phase == "intro" or phase == "fly":
		distance += dragon.speed * delta
		_check_rings()
		_check_stars()
		if phase == "fly" and (net.mode != "host" or net.connected):
			_spawn_sprites(delta)
	if phase != "over":
		for s in get_tree().get_nodes_in_group("dr_sprites"):
			s.host_update(delta)


func _check_rings() -> void:
	if course == null or ring_i >= course.rings.size():
		return
	var r: Dictionary = course.rings[ring_i]
	var rp: Vector3 = r.pos
	var rn: Vector3 = r.normal
	var rel: Vector3 = dragon.core_position() - rp
	var d := rel.dot(rn)
	var crossed := ring_last_d < 0.0 and d >= 0.0
	ring_last_d = d
	if not crossed and not (d > 0.0 and rel.length() > 160.0):
		return
	var lateral := (rel - rn * d).length()
	var radius: float = r.radius
	var final: bool = r.final
	if crossed and lateral <= radius + 1.0:
		rings_got += 1
		level_rings += 1
		var pts := 100
		var label := "RING! +100"
		if lateral < radius * 0.4:
			pts = 150
			label = "BULLSEYE! +150"
			sound("bullseye", -2.0)
		else:
			sound("ring", -2.0, 1.0 + ring_i * 0.04)
		score += pts
		burst(rp, Color(1.0, 0.85, 0.35), 24, 0.25)
		popup(Vector3(0, 1.6, -7.0), label, Color(1.0, 0.9, 0.4))
		players[0].haptic("l", 0.5)
		players[0].haptic("r", 0.5)
	else:
		sound("miss", -4.0)
		popup(Vector3(0, 1.6, -7.0), "Missed a ring!", Color(0.7, 0.85, 1.0))
	ring_i += 1
	ring_last_d = -1.0
	if ring_i < course.rings.size():
		var nr: Dictionary = course.rings[ring_i]
		var np: Vector3 = nr.pos
		var nn: Vector3 = nr.normal
		ring_last_d = (dragon.core_position() - np).dot(nn)
	if final or ring_i >= course.rings.size():
		_level_complete()


func _check_stars() -> void:
	if course == null:
		return
	var core: Vector3 = dragon.core_position()
	for st in course.stars:
		var id: int = st.id
		if course.gone.has(id):
			continue
		var sp: Vector3 = st.pos
		if core.distance_squared_to(sp) < 6.0 * 6.0:
			course.remove_item(id)
			stars_got += 1
			score += 25
			sound("star", -3.0, 1.0 + (stars_got % 5) * 0.08)
			burst(sp, Color(1.0, 0.9, 0.3), 14, 0.15)
			popup(Vector3(0.8, 1.2, -6.0), "STAR +25", Color(1.0, 0.92, 0.4))


func gunner_count() -> int:
	var n := 0
	for i in range(1, players.size()):
		if players[i].active:
			n += 1
	return maxi(n, 1)


func sprite_speed() -> float:
	return 6.5 + level * 0.7


func _spawn_sprites(delta: float) -> void:
	sprite_t -= delta
	var g := gunner_count()
	var alive := get_tree().get_nodes_in_group("dr_sprites").size()
	var cap := 1 + level + g / 2
	if sprite_t > 0.0 or alive >= cap:
		return
	sprite_t = maxf(2.2, 8.0 - level) / (0.75 + 0.25 * g)
	var local := Vector3(randf_range(-26.0, 26.0), randf_range(-6.0, 10.0), -randf_range(45.0, 65.0))
	if level >= 2 and randf() < 0.3:
		local = Vector3(randf_range(30.0, 45.0) * (-1.0 if randf() < 0.5 else 1.0), randf_range(-5.0, 8.0), randf_range(-20.0, 30.0))
	var s := SpriteScript.new()
	next_id += 1
	s.net_id = next_id
	s.main = self
	s.hp = 1 if g < 4 else 2
	s.target = dragon.random_lit()
	add_child(s)
	s.global_position = dragon.global_transform * local
	s.vel = dragon.velocity * 0.8
	sound("giggle", -8.0, randf_range(0.9, 1.2))


func on_sprite_reached(s: Node3D) -> void:
	if s.is_queued_for_deletion():
		return
	var t: int = s.target
	s.remove_from_group("dr_sprites")
	s.remove_from_group("dr_targets")
	s.queue_free()
	if not dragon.lit[t]:
		return
	dragon.lit[t] = false
	var lp: Vector3 = dragon.LANTERNS[t]
	burst(dragon.lantern_world(t), Color(1.0, 0.6, 0.25), 22, 0.18)
	sound("lantern", 0.0)
	sound("giggle", -2.0, 1.3)
	popup(Vector3(lp.x * 2.0, 1.6, lp.z), "A SPRITE POPPED A LANTERN!", Color(1.0, 0.55, 0.45))
	players[0].haptic("l", 0.9)
	players[0].haptic("r", 0.9)
	_hurt_all()
	net.event("hurt", [])
	print("Lantern %d popped: %d left" % [t, dragon.lit_count()])
	if dragon.lit_count() <= 0:
		_on_game_over()


func _hurt_all() -> void:
	for p in players:
		if p.hud != null:
			p.hud.hurt()


## Spawn a bubble from a gunner's cannon (host: real; TV machine: just for show). Bubbles keep the
## dragon's speed, so things flying along with the dragon are hit where you aim; aim assist adds the
## lead for balloons and sprites that are close to the crosshair.
func fire_bubble(index: int, y: float, p: float, visual_only: bool) -> void:
	if index <= 0 or index >= players.size():
		return
	var g = players[index]
	var eye: Vector3 = g.eye_position()
	var from: Vector3 = g.muzzle_position()
	var aim: Vector3 = g.aim_basis(y, p) * Vector3.FORWARD
	var dir := (eye + aim * 40.0 - from).normalized()
	var t := assist_target(eye, aim)
	if t != null:
		dir = _lead_dir(from, t)
	var b := BubbleScript.new()
	b.mesh = sphere_mesh(0.24)
	b.material_override = bubble_mat
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.main = self
	b.vel = dir * BUBBLE_SPEED + dragon.velocity
	b.owner_index = index
	b.visual_only = visual_only
	add_child(b)
	b.global_position = from
	if visual_only or not g.remote:
		local_sound("bubble", -10.0, 1.0 + (index % 3) * 0.15)
	else:
		local_sound("bubble", -16.0, 1.0 + (index % 3) * 0.15)  # the rider hears the gunners behind


## The target nearest to the crosshair, if it is within a few degrees of it.
func assist_target(from: Vector3, dir: Vector3) -> Node3D:
	var best_t: Node3D = null
	var best_dot := cos(deg_to_rad(6.0))
	for t in get_tree().get_nodes_in_group("dr_targets"):
		var n := t as Node3D
		var to := n.global_position - from
		var dist := to.length()
		if dist < 1.0 or dist > 70.0:
			continue
		var d := dir.dot(to / dist)
		if d > best_dot:
			best_dot = d
			best_t = n
	return best_t


func target_velocity(n: Node3D) -> Vector3:
	if n.get_meta("kind", "") == "sprite":
		return n.net_vel if n.ghost else n.vel
	return Vector3.ZERO


## Direction for a bubble (which keeps the dragon's velocity) to meet a moving target.
func _lead_dir(from: Vector3, n: Node3D) -> Vector3:
	var rel_v: Vector3 = target_velocity(n) - dragon.velocity
	var aim_pt := n.global_position
	for k in 3:
		var tt := from.distance_to(aim_pt) / BUBBLE_SPEED
		aim_pt = n.global_position + rel_v * tt
	return (aim_pt - from).normalized()


func on_bubble_hit(b: Node3D, target: Node3D) -> void:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return
	var by: int = b.owner_index
	var kind: String = target.get_meta("kind", "")
	if kind == "balloon":
		var c: Node3D = target.get_parent()
		var id: int = target.get_meta("id")
		if c != course or course.gone.has(id):
			return
		course.remove_item(id)
		score += 30
		var col: Color = target.get_meta("color", Color.WHITE)
		burst(target.global_position, col, 18, 0.2)
		sound("pop", -3.0, randf_range(0.9, 1.25))
		popup(to_dragon_local(target.global_position) + Vector3.UP * 1.5, "+30", col)
		_hit_marker(by)
	elif kind == "sprite":
		target.hp -= 1
		target.hit()
		_hit_marker(by)
		if target.hp > 0:
			sound("hit", -4.0)
			return
		target.remove_from_group("dr_sprites")
		target.remove_from_group("dr_targets")
		sprites_popped += 1
		score += 50
		burst(target.global_position, Color(0.75, 0.45, 1.0), 22, 0.22)
		sound("zap", -2.0, randf_range(0.9, 1.2))
		popup(to_dragon_local(target.global_position) + Vector3.UP * 1.5, "POP! +50", Color(0.85, 0.6, 1.0))
		target.queue_free()


func _hit_marker(index: int) -> void:
	if index <= 0 or index >= players.size():
		return
	var p = players[index]
	if p.hud != null:
		p.hud.hit_marker()
	elif p.remote:
		net.event("hit", [index])


func _level_complete() -> void:
	phase = "done"
	phase_t = DONE_TIME
	confirm_was = true
	var relit := false
	for i in dragon.lit.size():
		if not dragon.lit[i]:
			dragon.lit[i] = true
			relit = true
			break
	var bonus := 200 * level
	score += bonus
	for s in get_tree().get_nodes_in_group("dr_sprites"):
		s.remove_from_group("dr_sprites")
		s.remove_from_group("dr_targets")
		burst(s.global_position, Color(0.75, 0.45, 1.0), 10, 0.15)
		s.queue_free()
	_check_best()
	sound("levelup", 0.0, 1.0)
	print("Level %d complete: rings %d/%d, stars %d, score %d" % [level, level_rings, course.rings.size(), stars_got, score])
	show_center("LEVEL %d COMPLETE!\nRings %d / %d   ·   Stars %d   ·   Bonus +%d   ·   Score %d\n%s\nNext level soon (A / Enter, VR: trigger = go now)" % [
		level, level_rings, course.rings.size(), stars_got, bonus, score,
		"A lantern is lit again!" if relit else "All four lanterns are shining!"], DONE_TIME)


func _on_game_over() -> void:
	phase = "over"
	game_over_time = 0.0
	confirm_was = true
	sound("gameover", 0.0)
	var new_best := _check_best()
	print("Game over: level %d, score %d, stars %d, %.0f m" % [level, score, stars_got, distance])
	show_center("THE LANTERNS WENT OUT!\nLevel %d   ·   Score %d   ·   Stars %d   ·   %.1f km flown\n%s\nPress A / Enter (VR: trigger) to fly again" % [
		level, score, stars_got, distance / 1000.0, "NEW BEST SCORE!" if new_best else "Best: %d" % best], 0.0)


func _check_best() -> bool:
	if score > best:
		best = score
		var cfg := ConfigFile.new()
		cfg.set_value("best", "score", best)
		cfg.save("user://dragon_rider_best.cfg")
		return true
	return false


func _load_best() -> int:
	var cfg := ConfigFile.new()
	cfg.load("user://dragon_rider_best.cfg")
	return int(cfg.get_value("best", "score", 0))


## A / Enter on this machine, or the VR trigger: pressed now but not last frame.
func _confirm_pressed() -> bool:
	var down := Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER)
	for id in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(id, JOY_BUTTON_A):
			down = true
	if not players.is_empty() and players[0].vr_trigger_held():
		down = true
	var pressed := down and not confirm_was
	confirm_was = down
	return pressed


func hud_line() -> String:
	var total: int = course.rings.size() if course != null else 0
	return "LEVEL %d    SCORE %d    STARS %d    RING %d/%d    %.1f km" % [maxi(level, 1), score, stars_got,
		mini(ring_i + 1, total), total, distance / 1000.0]


func next_ring_info() -> Dictionary:
	if course == null or (phase != "intro" and phase != "fly"):
		return {}
	return course.next_ring(ring_i)


# --- Main loop -----------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_to_play or not is_inside_tree():
		return
	if music == null:
		music = MusicScript.new()
		add_child(music)
		music.volume_db = -17.0
	if music.has_method("play_track"):
		music.play_track(maxi(level - 1, 0))
	if mirror_vp:
		mirror_t -= delta
		if mirror_t <= 0.0:
			mirror_t = 1.0 / 30.0
			mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_update_center(delta)
	if net.mode == "client":
		dragon.net_follow(delta)
		for s in get_tree().get_nodes_in_group("dr_sprites"):
			s.ghost_update(delta)
		_check_join(delta)
		if (phase == "over" or phase == "done") and _confirm_pressed():
			net.send_action("restart" if phase == "over" else "next", [])
	else:
		dragon.fly(delta, players[0].steer_input(delta), players[0].flap_held() and phase != "over")
		_host_update(delta)
		if not is_inside_tree():
			return  # "play again" just reloaded the scene
	dragon.animate(delta)
	players[0].place(delta)
	for i in range(1, players.size()):
		players[i].update(delta)
	if course != null:
		course.animate(delta)
		course.update_rings(ring_i)
	_update_arrow(delta)
	world.follow(dragon.global_position, dragon.velocity)
	_party_tick(delta)
	_update_vr(delta)


func _update_arrow(delta: float) -> void:
	var r: Dictionary = next_ring_info()
	arrow.visible = not r.is_empty()
	if r.is_empty():
		return
	var rp: Vector3 = r.pos
	var to := rp - arrow.global_position
	if to.length() < 0.5:
		return
	var want := basis_y_to(to.normalized())
	var q := arrow.global_basis.get_rotation_quaternion().slerp(want.get_rotation_quaternion(), 1.0 - exp(-6.0 * delta))
	arrow.global_basis = Basis(q)
	arrow.position = Vector3(0, 0.6 + sin(Time.get_ticks_msec() * 0.004) * 0.08, -9.0)


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_F11:
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


# --- Players and views -------------------------------------------------------

func _build_players(mode: String) -> void:
	var r := RiderScript.new()
	r.main = self
	r.color = PLAYER_COLORS[0]
	r.ghost = mode == "client"
	add_child(r)
	players.append(r)
	# Every seat exists from the start (core/net.gd drops actions for missing indices); empty ones sleep.
	for i in range(1, MAX_PLAYERS):
		var g := GunnerScript.new()
		g.index = i
		g.main = self
		g.color = PLAYER_COLORS[i]
		g.remote = mode == "host"
		if i == 1 and mode == "local":
			g.key_set = 1  # arrows + Enter (the rider has WASD + mouse)
		elif i == 1 and mode == "client":
			g.key_set = 0
			g.mouse_look = true
		g.active = i == 1 and mode != "host"
		var row := (i - 1) / 2
		var side := -1.0 if (i - 1) % 2 == 0 else 1.0
		g.position = Vector3(0.55 * side, -0.05, 1.7 + row * 1.35)
		g.yaw = -0.6 * side
		dragon.add_child(g)
		players.append(g)


func _is_local(p) -> bool:
	return not p.vr and not p.remote and not p.ghost


func _build_views(mode: String) -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized() and mode == "host":
		xr_interface = xr
		print("VR headset found: player 1 rides the dragon")
		Engine.physics_ticks_per_second = 90
		get_viewport().use_xr = true
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
		players[0].attach_xr(origin, cam, left, right)
		_build_vignette(cam)
		_build_vr_mirror(cam)
	else:
		print("No VR headset: %s" % ("TV gunners" if mode == "client" else "split screen, player 1 flies the dragon"))
	_ensure_views_root()
	for p in players:
		if _is_local(p) and p.active:
			_ensure_view(p)
	_layout_views()


## Comfort: darken the edges of the view while the dragon turns or speeds up.
func _build_vignette(cam: XRCamera3D) -> void:
	vignette = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	sm.radial_segments = 16
	sm.rings = 8
	vignette.mesh = sm
	vignette_mat = ShaderMaterial.new()
	vignette_mat.shader = Shader.new()
	vignette_mat.shader.code = VIGNETTE_SHADER
	vignette_mat.render_priority = 100
	vignette_mat.set_shader_parameter("strength", 0.0)
	vignette.material_override = vignette_mat
	vignette.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cam.add_child(vignette)
	vignette.visible = false


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
	cam.far = 1500.0
	cam.cull_mask = xr_cam.cull_mask
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
	bg.color = Color(0.08, 0.04, 0.1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	views_root = Control.new()
	views_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(views_root)
	views_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ensure_view(p) -> void:
	if p.has_meta("view"):
		return
	_ensure_views_root()
	var container := SubViewportContainer.new()
	p.set_meta("view", container)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.visible = p.active
	views_root.add_child(container)
	var vp := SubViewport.new()
	vp.world_3d = get_world_3d()
	vp.msaa_3d = Viewport.MSAA_2X
	container.add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	p.attach_camera(cam)
	var hud_layer := CanvasLayer.new()
	vp.add_child(hud_layer)
	var hud := HudScript.new()
	hud.player = p
	hud.main = self
	hud_layer.add_child(hud)
	p.hud = hud


## TV split screen grid: 1 full, 2 side by side, 3-4 as 2x2, 5-6 as 3x2. Smaller views render at a
## lower resolution without MSAA, and get a smaller HUD.
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
	view_count = n
	fallback_label.visible = n == 0 and not players[0].vr
	if n == 0:
		return
	var cols := 1
	var rows := 1
	if n == 2:
		cols = 2
	elif n <= 4 and n > 2:
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
		var row := int(floorf(float(k) / cols))
		c.set_anchors_preset(Control.PRESET_TOP_LEFT)
		c.position = Vector2(col * (cell.x + gap), row * (cell.y + gap))
		c.size = cell
		var vp := c.get_child(0) as SubViewport
		if vp != null:
			vp.scaling_3d_scale = res_scale
			vp.msaa_3d = Viewport.MSAA_2X if n <= 2 else Viewport.MSAA_DISABLED
		if p.hud != null:
			p.hud.ui_scale = clampf(minf(cell.x / 1100.0, cell.y / 820.0), 0.45, 1.0)


func _build_fallback_label() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	fallback_label = Label.new()
	fallback_label.add_theme_font_size_override("font_size", 44)
	fallback_label.add_theme_constant_override("outline_size", 10)
	fallback_label.add_theme_color_override("font_outline_color", Color(0.1, 0.03, 0.12))
	fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fallback_label)
	fallback_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# --- Controllers and drop-in join ----------------------------------------------

func _assign_joypads() -> void:
	var pads := Input.get_connected_joypads()
	joy_owner.clear()
	if net.mode == "host":
		if not players[0].vr:
			players[0].joy = pads[0] if pads.size() > 0 else -1
		return
	players[1].joy = pads[0] if pads.size() > 0 else -1
	if net.mode == "local":
		players[0].joy = pads[1] if pads.size() > 1 else -1
	for p in players:
		if p.joy >= 0 and _is_local(p):
			joy_owner[p.joy] = p.index
	for id in pads:
		print("Joypad %d: %s" % [id, Input.get_joy_name(id)])


func _on_joy_changed(device: int, connected: bool) -> void:
	if not ready_to_play or net.mode == "host":
		return
	if connected:
		_on_pad_connected(device)
	else:
		_on_pad_disconnected(device)


func _on_pad_disconnected(device: int) -> void:
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
		p.pad_lost_t = 0.0  # leaves after PAD_LEAVE_TIME unless the controller comes back
		show_center("P%d: controller disconnected" % (idx + 1), 2.0, false)


func _on_pad_connected(device: int) -> void:
	print("Joypad %d connected: %s" % [device, Input.get_joy_name(device)])
	if joy_owner.has(device):
		return
	var pick = null
	for p in players:
		if _is_local(p) and p.joy < 0 and p.get_meta("last_joy", -2) == device:
			pick = p
			break
	if pick == null:
		for p in players:
			if _is_local(p) and p.joy < 0 and p.pad_lost_t >= 0.0:
				pick = p
				break
	if pick == null and players[1].joy < 0 and _is_local(players[1]):
		pick = players[1]
	if pick == null and net.mode == "local" and players[0].joy < 0 and _is_local(players[0]):
		pick = players[0]
	if pick == null:
		return  # unassigned: press A to join as a new gunner
	pick.joy = device
	joy_owner[device] = pick.index
	pick.pad_lost_t = -1.0
	if not pick.active and pick.has_meta("left_by_pad"):
		_request_join(pick)
	elif pick.active:
		show_center("P%d: controller connected" % (pick.index + 1), 1.2, false)


## join_listener: A on a controller that drives nobody joins a new gunner (Start is the pause menu).
func handle_join_input(event: InputEvent) -> bool:
	var pad := event as InputEventJoypadButton
	if pad == null or not pad.pressed or pad.button_index != JOY_BUTTON_A:
		return false
	if not ready_to_play or net.mode == "host" or phase == "over" or get_tree().paused:
		return false
	var device := pad.device
	if joy_owner.has(device):
		var idx: int = joy_owner[device]
		if not players[idx].active and _is_local(players[idx]):
			_request_join(players[idx])
			return true
		return false
	return _join_slot(device) != null


func _next_free_index() -> int:
	var top := MAX_PLAYERS - 1 if net.mode == "client" else MAX_LOCAL_VIEWS - 1
	for i in range(1, top + 1):
		var p = players[i]
		if not _is_local(p) or p.active or p.joy >= 0 or p.pad_lost_t >= 0.0:
			continue
		return i
	return -1


func _join_slot(device: int):
	var idx := _next_free_index()
	if idx < 0:
		show_center("All the dragon's seats are taken!", 1.5, false)
		return null
	var p = players[idx]
	if device >= 0:
		p.joy = device
		joy_owner[device] = idx
		print("Joypad %d joins as P%d" % [device, idx + 1])
	_request_join(p)
	return p


func _request_join(p) -> void:
	p.remove_meta("left_by_pad")
	p.pad_lost_t = -1.0
	if not p.active:
		p.set_active(true)
		_ensure_view(p)
		on_player_activity_changed(p)
		if net.mode == "client":
			net.send_action("join", [p.index], 1)
		else:
			show_center("PLAYER %d CLIMBED ABOARD!" % (p.index + 1), 1.5)
			sound("join", -4.0, 1.2)
	_save_party()


func _leave(p) -> void:
	p.pad_lost_t = -1.0
	p.set_meta("left_by_pad", true)
	if p.active:
		p.set_active(false)
		on_player_activity_changed(p)
		if net.mode == "client":
			net.send_action("leave", [p.index], 1)
		else:
			show_center("PLAYER %d LEFT" % (p.index + 1), 1.5)
	_save_party()


func _update_lost_pads(delta: float) -> void:
	for p in players:
		if p.pad_lost_t >= 0.0 and _is_local(p):
			p.pad_lost_t += delta
			if p.pad_lost_t > PAD_LEAVE_TIME:
				_leave(p)


func _save_party() -> void:
	var party: Array = []
	for p in players:
		if p.index >= 2 and _is_local(p) and p.active:
			party.append([p.index, p.joy])
	Engine.set_meta("dragon_rider_party", {"mode": net.mode, "party": party})


func _restore_party() -> void:
	if net.mode == "host" or not Engine.has_meta("dragon_rider_party"):
		return
	var saved: Dictionary = Engine.get_meta("dragon_rider_party")
	if saved.get("mode", "") != net.mode:
		return
	var pads := Input.get_connected_joypads()
	var party: Array = saved.get("party", [])
	for entry in party:
		var idx: int = entry[0]
		var device: int = entry[1]
		if idx < 2 or idx >= MAX_PLAYERS or (net.mode == "local" and idx >= MAX_LOCAL_VIEWS):
			continue
		if device >= 0 and (not pads.has(device) or joy_owner.has(device)):
			continue
		var p = players[idx]
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


## Test hook: a TV player joins without a controller (index -1: the next free seat).
func debug_join(index: int = -1):
	if not ready_to_play or net.mode == "host":
		return null
	if index < 0:
		return _join_slot(-1)
	_request_join(players[index])
	return players[index]


func active_player_count() -> int:
	var n := 0
	for p in players:
		if p.active:
			n += 1
	return n


func _party_tick(delta: float) -> void:
	_ensure_join_listener()
	if net.mode == "host":
		return
	_update_lost_pads(delta)
	if views_root != null and is_instance_valid(views_root) and views_root.size != last_view_area:
		_layout_views()


func on_player_activity_changed(p) -> void:
	if p.active and _is_local(p):
		_ensure_view(p)
	_layout_views()
	print("Player %d is now %s" % [p.index + 1, "playing" if p.active else "waiting"])


## TV machine: keep telling the host which gunners are aboard (cheap, and survives a lost message).
func _check_join(delta: float) -> void:
	join_t -= delta
	if join_t > 0.0:
		return
	join_t = 2.0
	for i in range(2, players.size()):
		if players[i].active:
			net.send_action("join", [i], 1)


# --- Networked co-op (see docs/GAME_DEV_GUIDE.md) ----------------------------

func on_client_joined() -> void:
	players[1].set_active(true)
	show_center("THE GUNNERS CLIMBED ABOARD!", 1.5)
	sound("join", -2.0)


func on_client_left() -> void:
	for i in range(1, players.size()):
		players[i].set_active(false)
	show_center("The TV gunners left - waiting for them to come back…", 0.0)


func on_p2_action(action: String, args: Array, index: int = 1) -> void:
	if (action == "join" or action == "leave") and args.size() > 0:
		index = int(args[0])  # drop-in seats speak through P2
	if index <= 0 or index >= players.size():
		return
	var g = players[index]
	match action:
		"fire":
			if not g.active:
				g.set_active(true)
			if args.size() >= 2:
				g.yaw = float(args[0])
				g.pitch = float(args[1])
				fire_bubble(index, g.yaw, g.pitch, false)
		"join":
			if not g.active:
				g.set_active(true)
				show_center("PLAYER %d CLIMBED ABOARD!" % (index + 1), 1.5)
				sound("join", -4.0, 1.2)
				print("Net: player %d joined the game" % (index + 1))
		"leave":
			if g.active and index >= 2:
				g.set_active(false)
				show_center("PLAYER %d LEFT" % (index + 1), 1.5)
		"restart":
			if phase == "over":
				get_tree().reload_current_scene()
		"next":
			if phase == "done" and phase_t < DONE_TIME - 1.5:
				phase_t = 0.0
		"pause":
			var paused: bool = args[0]
			_set_pause_banner(paused, "A gunner opened the menu")
			get_tree().paused = paused


func _set_pause_banner(paused: bool, who: String) -> void:
	show_center("PAUSED\n" + who if paused else "", 0.0, false)
	if vr_center != null:
		VrText.snap(vr_center)
	_update_vr(0.0)


func toggle_vr_pause() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	_set_pause_banner(paused, "Wrist RESUME: carry on\nPull the trigger: back to the arcade")
	net.event("remote_pause", [paused])


func on_rider_fitted() -> void:
	if vr_center != null:
		VrText.snap(vr_center)
	if vr_status != null:
		VrText.snap(vr_status)


func make_snapshot() -> Array:
	var sp := []
	for s in get_tree().get_nodes_in_group("dr_sprites"):
		sp.append([s.net_id, s.global_position, s.vel])
	var gone := PackedInt32Array()
	if course != null:
		gone = course.gone_ids()
	return [phase, level, level_seed, course_origin, course_yaw, ring_i, score, stars_got, dragon.lit_mask(), distance,
		[dragon.global_position, dragon.yaw, dragon.velocity, dragon.yaw_rate, dragon.steer, dragon.climb, dragon.flap_power],
		gone, sp, players[0].net_pose(), phase_t, level_rings]


func apply_snapshot(s: Array) -> void:
	if not ready_to_play or s.size() < 16:
		return
	synced = true
	phase = s[0]
	var lv: int = s[1]
	var sd: int = s[2]
	if lv > 0 and (course == null or sd != level_seed or lv != level):
		level = lv
		level_seed = sd
		course_origin = s[3]
		course_yaw = s[4]
		_build_course()
	ring_i = s[5]
	score = s[6]
	stars_got = s[7]
	var before: int = dragon.lit_count()
	dragon.set_lit_mask(s[8])
	if dragon.lit_count() < before:
		_hurt_all()
	distance = s[9]
	var d: Array = s[10]
	dragon.set_net(d[0], d[1], d[2], d[3], d[4], d[5], d[6])
	if course != null:
		var gone: PackedInt32Array = s[11]
		for id in gone:
			course.remove_item(id)
	_sync_sprites(s[12])
	players[0].apply_net_pose(s[13])
	phase_t = s[14]
	level_rings = s[15]


func _sync_sprites(list: Array) -> void:
	var have := {}
	for n in get_tree().get_nodes_in_group("dr_sprites"):
		have[n.net_id] = n
	var seen := {}
	for item in list:
		var id: int = item[0]
		seen[id] = true
		var s: Node3D = have.get(id)
		if s == null:
			s = SpriteScript.new()
			s.net_id = id
			s.main = self
			s.ghost = true
			add_child(s)
			s.global_position = item[1]
		s.net_pos = item[1]
		s.net_vel = item[2]
	for id in have.keys():
		if not seen.has(id):
			var n: Node3D = have[id]
			n.remove_from_group("dr_sprites")
			n.remove_from_group("dr_targets")
			n.queue_free()


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
			show_center(args[0], args[1], false)
		"hit":
			var i: int = args[0]
			if i > 0 and i < players.size() and players[i].hud != null:
				players[i].hud.hit_marker()
		"hurt":
			_hurt_all()
		"remote_pause":
			get_tree().paused = args[0]
			_set_pause_banner(args[0], "The dragon rider paused the game")


# --- Banner, VR text and comfort ------------------------------------------------

func show_center(text: String, duration: float, broadcast: bool = true) -> void:
	if net and broadcast:
		net.event("center", [text, duration])
	center_text = text
	center_alpha = 1.0 if text != "" else 0.0
	center_left = duration
	if fallback_label:
		fallback_label.text = text
	if vr_center != null:
		VrText.snap(vr_center)


func _update_center(delta: float) -> void:
	if center_left > 0.0:
		center_left -= delta
		if center_left <= 0.0:
			center_left = -1.0
	if center_left < 0.0:
		center_alpha = maxf(0.0, center_alpha - delta * 2.0)
	fallback_label.modulate.a = center_alpha


func _vr_label(font: int, width: float) -> Label3D:
	var l := Label3D.new()
	l.font_size = font
	l.outline_size = 26
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	l.width = width
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.pixel_size = 0.0022
	l.modulate = Color(1.0, 0.95, 0.85)
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dragon.add_child(l)  # rides along: world-locked relative to the saddle, never to the headset
	return l


func _update_vr(delta: float) -> void:
	if players.is_empty() or not players[0].vr:
		return
	var cam: XRCamera3D = players[0].xr_camera
	if vr_center == null:
		vr_center = _vr_label(46, 1000.0)
		vr_status = _vr_label(30, 1100.0)
	vr_center.text = center_text
	vr_center.visible = center_alpha > 0.01 and center_text != ""
	vr_center.modulate.a = center_alpha
	vr_center.outline_modulate = Color(0, 0, 0, center_alpha)
	VrText.follow(vr_center, cam, dragon, 0.05, 1.8)
	var lamps := ""
	for l in dragon.lit:
		lamps += "O " if l else "x "
	var hint := ""
	if phase == "wait":
		hint = "Waiting for the gunners…"
	elif phase == "over":
		hint = "Pull the trigger to fly again"
	vr_status.text = "%s\nLANTERNS  %s  %s" % [hud_line(), lamps, hint]
	VrText.follow(vr_status, cam, dragon, 0.58, 1.8)
	if vignette_mat != null and delta > 0.0:
		var turn: float = absf(dragon.yaw_rate) / dragon.MAX_YAW_RATE
		var fast: float = clampf((dragon.speed - dragon.BASE_SPEED) / (dragon.MAX_SPEED - dragon.BASE_SPEED), 0.0, 1.0)
		var vert: float = absf(dragon.vy) / dragon.CLIMB_SPEED
		var target := clampf(turn * 0.55 + fast * 0.35 + vert * 0.2 - 0.12, 0.0, 0.8)
		var cur: float = vignette_mat.get_shader_parameter("strength")
		var v := lerpf(cur, target, 1.0 - exp(-4.0 * delta))
		vignette_mat.set_shader_parameter("strength", v)
		vignette.visible = v > 0.02
