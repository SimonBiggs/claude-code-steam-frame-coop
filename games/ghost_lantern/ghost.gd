extends Node3D
## A mischievous ghost. Only visible inside the spirit lantern's light cone (main.ghost_material()).
## Host: simulated here (steal photos, spook players, flee the bell, get stunned and vacuumed).
## Client (`puppet`): drawn from the host's snapshots.

const KINDS := {
	"thief": {"color": Color(0.55, 1.0, 0.72), "radius": 0.42, "speed": 1.7, "tough": 1.0, "points": 100},
	"spooker": {"color": Color(0.78, 0.58, 1.0), "radius": 0.55, "speed": 1.35, "tough": 1.4, "points": 150},
	"sprite": {"color": Color(1.0, 0.62, 0.9), "radius": 0.32, "speed": 2.5, "tough": 0.7, "points": 120},
}
const STUN_TIME := 1.1  # seconds in the lantern beam to stun (half that with a focused beam)

var main
var puppet := false
var net_id := 0
var kind := "thief"
var night := 1
var radius := 0.42
var speed := 1.7
var tough := 1.0
var points := 100
var color := Color.WHITE

var reveal := 0.0  # how much the lantern lights this ghost (host-computed; mirrored to the client)
var capture := 0.0  # vacuum progress 0..1
var beam_t := 0.0
var stun_t := 0.0
var stun_cd := 0.0
var scared_t := 0.0
var sucked_t := 0.0
var flee_t := 0.0
var spook_cd := 1.5
var target_photo := -1
var carrying := -1
var grab_t := 0.0
var exit_point := Vector3.ZERO
var wander_point := Vector3.ZERO
var vel := Vector3.ZERO
var pull_from := Vector3.ZERO
var scare_from := Vector3.ZERO
var t := 0.0
var struggle_t := 0.0
var net_target := Vector3.ZERO
var net_rot := 0.0
var net_started := false

var body: Node3D
var skirt: MeshInstance3D
var meshes: Array[MeshInstance3D] = []
var stars: Node3D
var bar_bg: MeshInstance3D
var bar_fill: MeshInstance3D
var bar_mesh: QuadMesh


func setup(k: String, n: int, m) -> void:
	kind = k
	night = n
	main = m
	var d: Dictionary = KINDS[k]
	color = d.color
	radius = d.radius
	speed = d.speed + 0.1 * (n - 1)
	tough = d.tough * (1.0 + 0.06 * (n - 1))
	points = d.points


func _ready() -> void:
	add_to_group("ghosts")
	t = randf() * 10.0
	_build()
	wander_point = global_position
	net_target = global_position


func _build() -> void:
	var shared: ShaderMaterial = main.ghost_material()
	body = Node3D.new()
	add_child(body)
	var head := _sphere(radius, Vector3.ZERO, 1.0)
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.98
	cm.bottom_radius = radius * 0.3
	cm.height = radius * 1.8
	cm.radial_segments = 14
	cm.rings = 2
	cm.cap_top = false
	skirt = MeshInstance3D.new()
	skirt.mesh = cm
	skirt.position.y = -radius * 0.85
	body.add_child(skirt)
	meshes.append(skirt)
	for sx in [-1.0, 1.0]:
		_sphere(radius * 0.26, Vector3(sx * radius * 1.0, -radius * 0.35, -radius * 0.15), 1.3)
	var dark := Color(0.1, 0.04, 0.16)
	var eyes: Array[MeshInstance3D] = []
	for sx in [-1.0, 1.0]:
		eyes.append(_sphere(radius * 0.17, Vector3(sx * radius * 0.36, radius * 0.18, -radius * 0.86), 1.25))
	var mouth := _sphere(radius * 0.13, Vector3(0, -radius * 0.22, -radius * 0.9), 1.0)
	for mi in meshes:
		mi.material_override = shared
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_instance_shader_parameter("color", color)
	for mi in eyes:
		mi.set_instance_shader_parameter("color", dark)
	mouth.set_instance_shader_parameter("color", Color(0.45, 0.12, 0.3))
	head.set_instance_shader_parameter("color", color)
	# Dizzy stars (always visible: a hint where a stunned ghost is).
	stars = Node3D.new()
	stars.position.y = radius + 0.25
	add_child(stars)
	var star_mat := StandardMaterial3D.new()
	star_mat.albedo_color = Color(1.0, 0.9, 0.3)
	star_mat.emission_enabled = true
	star_mat.emission = Color(1.0, 0.9, 0.3)
	star_mat.emission_energy_multiplier = 3.0
	for i in 3:
		var s := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * 0.08
		s.mesh = bm
		s.material_override = star_mat
		var a := TAU * i / 3.0
		s.position = Vector3(cos(a) * 0.3, 0, sin(a) * 0.3)
		s.rotation = Vector3(0.6, a, 0.6)
		stars.add_child(s)
	stars.visible = false
	# Capture bar (billboard), shown while a vacuum is pulling.
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg_mat.albedo_color = Color(0.05, 0.02, 0.08)
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 5
	var fill_mat: StandardMaterial3D = bg_mat.duplicate()
	fill_mat.albedo_color = Color(0.45, 1.0, 0.6)
	fill_mat.render_priority = 6
	bar_bg = MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(0.9, 0.12)
	bar_bg.mesh = bq
	bar_bg.material_override = bg_mat
	bar_bg.position.y = radius + 0.5
	add_child(bar_bg)
	bar_fill = MeshInstance3D.new()
	bar_mesh = QuadMesh.new()
	bar_mesh.size = Vector2(0.84, 0.08)
	bar_fill.mesh = bar_mesh
	bar_fill.material_override = fill_mat
	bar_fill.position.y = radius + 0.5
	add_child(bar_fill)
	for b in [bar_bg, bar_fill]:
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.visible = false


func _sphere(r: float, pos: Vector3, squash: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0 * squash
	sm.radial_segments = 14
	sm.rings = 7
	mi.mesh = sm
	mi.position = pos
	body.add_child(mi)
	meshes.append(mi)
	return mi


# --- Host simulation ---------------------------------------------------------

func _physics_process(delta: float) -> void:
	if puppet or main == null or main.game_over:
		return
	t += delta
	stun_t -= delta
	stun_cd -= delta
	scared_t -= delta
	flee_t -= delta
	spook_cd -= delta
	reveal = main.lantern_reveal(global_position, radius)
	if reveal > 0.5 and stun_t <= 0.0:
		beam_t += delta * (2.0 if main.players[0].focus else 1.0)
		if beam_t >= STUN_TIME and stun_cd <= 0.0:
			_stun()
	elif reveal <= 0.5:
		beam_t = maxf(0.0, beam_t - delta)
	if sucked_t > 0.0:
		sucked_t -= delta
	else:
		capture = maxf(0.0, capture - delta * 0.3)

	var desired := Vector3.ZERO
	var spd := speed
	var target_y := 1.4
	if stun_t > 0.0:
		spd = 0.0
		target_y = 1.1
	elif sucked_t > 0.0:
		# Struggle: pulled toward the nozzle, wriggling sideways.
		var to := pull_from - global_position
		to.y = 0.0
		var side := Vector3(-to.z, 0.0, to.x).normalized()
		desired = to.normalized() * 0.5 + side * sin(t * 9.0) * 0.8
		spd = 1.2
		target_y = clampf(pull_from.y, 0.9, 1.8)
	elif scared_t > 0.0:
		desired = global_position - scare_from
		desired.y = 0.0
		spd = speed * 1.6
	elif flee_t > 0.0:
		desired = wander_point - global_position
		desired.y = 0.0
	elif kind == "thief":
		var r := _thief(delta)
		desired = Vector3(r.x, 0.0, r.z)
		target_y = r.y
	else:
		desired = _chase()
		target_y = 1.2
	if desired.length() > 0.01:
		desired = desired.normalized()
	if reveal > 0.5:
		spd *= 0.75  # the lantern's light makes ghosts sluggish
	vel = vel.lerp(desired * spd, 1.0 - exp(-3.0 * delta))
	position += vel * delta
	position.y = lerpf(position.y, target_y + sin(t * 2.0) * 0.12, 1.0 - exp(-2.0 * delta))
	if Vector2(vel.x, vel.z).length() > 0.2:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-vel.x, -vel.z), 1.0 - exp(-6.0 * delta))
	if carrying >= 0:
		if absf(position.x) > 22.5 or absf(position.z) > 9.8:
			main.ghost_escaped(self)
			return
	else:
		position.x = clampf(position.x, -24.0, 24.0)
		position.z = clampf(position.z, -11.0, 11.0)
	_check_touch()
	if sucked_t > 0.0:
		struggle_t -= delta
		if struggle_t <= 0.0:
			struggle_t = 0.3
			main.sound("hit", -10.0, 0.8 + capture)


## Returns a direction (x, z) plus the wanted height in y.
func _thief(delta: float) -> Vector3:
	if carrying >= 0:
		var to := exit_point - global_position
		return Vector3(to.x, 1.6, to.z)
	if target_photo < 0 or not main.photo_available(target_photo, self):
		target_photo = main.pick_photo(self)
		grab_t = 0.0
	if target_photo < 0:
		var c := _chase()
		return Vector3(c.x, 1.2, c.z)
	var spot: Vector3 = main.photo_grab_point(target_photo)
	var flat := Vector3(spot.x - global_position.x, 0.0, spot.z - global_position.z)
	if flat.length() < 0.5:
		grab_t += delta
		if grab_t > 1.0:
			carrying = target_photo
			main.grab_photo(self, target_photo)
			exit_point = _pick_exit()
		return Vector3(0.0, spot.y, 0.0)
	grab_t = 0.0
	return Vector3(flat.x, spot.y if flat.length() < 3.0 else 1.5, flat.z)


func _pick_exit() -> Vector3:
	var z := 11.0 if global_position.z > 0.0 else -11.0
	if randf() < 0.35:
		return Vector3(24.0 * signf(global_position.x + 0.01), 1.6, global_position.z)
	return Vector3(global_position.x + randf_range(-3.0, 3.0), 1.6, z)


func _chase() -> Vector3:
	var p = main.nearest_player(global_position)
	if p == null:
		return wander_point - global_position
	var to: Vector3 = p.global_position - global_position
	to.y = 0.0
	return to


func _check_touch() -> void:
	if kind == "thief" or spook_cd > 0.0 or stun_t > 0.0 or scared_t > 0.0 or sucked_t > 0.0:
		return
	for p in main.players:
		if not p.active or p.is_down:
			continue
		var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z)
		if d.length() < radius + 0.45:
			main.spook_player(p, self)
			spook_cd = 3.0
			flee_t = 2.2
			var away := -Vector3(d.x, 0.0, d.y).normalized()
			wander_point = global_position + away * 5.0
			return


func _stun() -> void:
	stun_t = 2.6
	stun_cd = 4.5
	beam_t = 0.0
	drop_photo()
	main.on_ghost_stunned(self)


func drop_photo() -> void:
	if carrying >= 0:
		main.return_photo(carrying, true)
	carrying = -1
	target_photo = -1
	grab_t = 0.0


## The hand bell: flee from `from` for a few seconds and let go of any photo.
func scare(from: Vector3) -> void:
	scared_t = 3.0
	scare_from = from
	drop_photo()


## Host: a vacuum at `from` is pulling this (revealed) ghost.
func suck(from: Vector3, amount: float, by) -> void:
	sucked_t = 0.15
	pull_from = from
	capture += amount * (1.8 if stun_t > 0.0 else 1.0) / tough
	if capture >= 1.0:
		main.capture_ghost(self, by)


func is_stunned() -> bool:
	return stun_t > 0.0


# --- Visuals (both machines) -------------------------------------------------

func _process(delta: float) -> void:
	if puppet:
		t += delta
		global_position = global_position.lerp(net_target, 1.0 - exp(-12.0 * delta))
		body.rotation.y = lerp_angle(body.rotation.y, net_rot, 1.0 - exp(-10.0 * delta))
		stun_t -= delta
	body.position.y = sin(t * 2.3) * 0.05
	skirt.rotation.z = sin(t * 3.1) * 0.12
	skirt.rotation.x = sin(t * 2.7) * 0.1
	var squish := capture * (0.7 + 0.3 * sin(t * 20.0))
	body.scale = Vector3(1.0 - squish * 0.25, 1.0 + squish * 0.2, 1.0 + squish * 0.35)
	if stun_t > 0.0:
		body.rotation.z = sin(t * 6.0) * 0.25
	else:
		body.rotation.z = lerpf(body.rotation.z, 0.0, 1.0 - exp(-5.0 * delta))
	stars.visible = stun_t > 0.0
	if stars.visible:
		stars.rotation.y += delta * 4.0
	var show_bar := capture > 0.02
	bar_bg.visible = show_bar
	bar_fill.visible = show_bar
	if show_bar:
		var w := 0.84 * clampf(capture, 0.0, 1.0)
		bar_mesh.size = Vector2(maxf(w, 0.001), 0.08)
		bar_mesh.center_offset = Vector3(-0.42 + w / 2.0, 0.0, 0.001)
	var flash := capture * 0.8 + (0.5 + 0.5 * sin(t * 12.0)) * 0.3 * float(stun_t > 0.0)
	for mi in meshes:
		mi.set_instance_shader_parameter("flash", flash)


## Client: [id, kind, pos, rot_y, reveal, capture, stunned, scared]
func apply_net(item: Array) -> void:
	net_target = item[2]
	net_rot = item[3]
	reveal = item[4]
	capture = item[5]
	var stunned: bool = item[6]
	stun_t = 0.5 if stunned else 0.0
	if not net_started:
		net_started = true
		global_position = net_target


func net_state() -> Array:
	return [net_id, kind, global_position, body.rotation.y, reveal, capture, stun_t > 0.0, scared_t > 0.0]
