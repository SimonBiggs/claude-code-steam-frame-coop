extends Node3D
## One deck cannon. The gunner swings it by its handle (VR) or with the stick/mouse (flat) and fires;
## deckhands keep it loaded. Shows its ammo above it and, while manned, a faint trajectory arc.

const World := preload("res://games/cannon_cove/world.gd")

const MAX_AMMO := 4
const MUZZLE_SPEED := 30.0
const RELOAD := 1.1
const YAW_LIMIT := 1.2  # radians either side of straight out
const PITCH_MIN := -0.14
const PITCH_MAX := 0.7
const SIDE_NAMES := ["PORT", "PORT", "STARBOARD", "STARBOARD"]

var main
var index := 0
var outboard := Vector3.LEFT
var aim_yaw := 0.0  # relative to straight out
var aim_pitch := 0.12
var ammo := 2
var reload_t := 0.0
var manned := false
var hover := false  # VR hand is near the handle
var grabbed := false

var barrel_pivot: Node3D
var barrel_root: Node3D  # slides back on recoil
var handle: Node3D
var handle_mat: StandardMaterial3D
var rack_balls: Array[MeshInstance3D] = []
var label: Label3D
var arc: MeshInstance3D
var arc_mesh: ImmediateMesh
var arc_mat: StandardMaterial3D
var land_ring: MeshInstance3D
var recoil := 0.0


func _ready() -> void:
	rotation.y = atan2(-outboard.x, -outboard.z)  # local -Z points out to sea
	var wood := World.mat(Color(0.55, 0.3, 0.15))
	var iron := World.mat(Color(0.16, 0.16, 0.2), 0.0, 0.35)
	iron.metallic = 0.7
	var gold := World.mat(Color(1.0, 0.78, 0.2), 0.3, 0.4)
	# Carriage with wheels (fixed); barrel on a pivot.
	World.box(self, Vector3(0.9, 0.45, 1.3), Vector3(0, -0.55, 0.15), wood)
	for sx in [-0.5, 0.5]:
		for sz in [-0.35, 0.6]:
			var w := World.cyl(self, 0.2, 0.2, 0.12, Vector3(sx, -0.62, sz), wood, 10)
			w.rotation.z = PI / 2.0
	barrel_pivot = Node3D.new()
	add_child(barrel_pivot)
	barrel_root = Node3D.new()
	barrel_pivot.add_child(barrel_root)
	var barrel := World.cyl(barrel_root, 0.17, 0.25, 1.9, Vector3(0, 0, -0.35), iron, 12)
	barrel.rotation.x = -PI / 2.0  # narrow end (top) points out to sea
	var ring := World.cyl(barrel_root, 0.22, 0.22, 0.12, Vector3(0, 0, -1.25), gold, 12)
	ring.rotation.x = PI / 2.0
	var ring2 := World.cyl(barrel_root, 0.27, 0.27, 0.1, Vector3(0, 0, 0.4), gold, 12)
	ring2.rotation.x = PI / 2.0
	# The handle: a bar sticking back from the breech with a knob the VR player grabs.
	handle = Node3D.new()
	handle.position = Vector3(0, 0.0, 0.95)
	barrel_root.add_child(handle)
	var bar := World.cyl(barrel_root, 0.045, 0.045, 0.5, Vector3(0, 0, 0.72), wood, 6)
	bar.rotation.x = PI / 2.0
	handle_mat = World.mat(Color(1.0, 0.65, 0.2), 0.5, 0.5)
	World.sphere(handle, 0.09, Vector3.ZERO, handle_mat, 10)
	var grip := World.cyl(handle, 0.05, 0.05, 0.36, Vector3.ZERO, handle_mat, 6)
	grip.rotation.z = PI / 2.0
	# Ammo rack: a little row of balls next to the carriage.
	var ball_mat := World.mat(Color(0.1, 0.1, 0.12), 0.0, 0.35)
	for i in MAX_AMMO:
		rack_balls.append(World.sphere(self, 0.13, Vector3(0.75, -0.65, 0.9 - i * 0.3), ball_mat, 8))
	label = Label3D.new()
	label.font_size = 64
	label.outline_size = 26
	label.pixel_size = 0.0055
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, 1.3, 0.3)
	add_child(label)
	# Trajectory preview.
	arc_mesh = ImmediateMesh.new()
	arc = MeshInstance3D.new()
	arc.mesh = arc_mesh
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arc.top_level = true
	arc_mat = StandardMaterial3D.new()
	arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arc_mat.albedo_color = Color(1.0, 0.95, 0.6, 0.55)
	add_child(arc)
	land_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.4
	tm.outer_radius = 1.7
	tm.rings = 20
	tm.ring_segments = 4
	land_ring.mesh = tm
	var lr_mat := World.mat(Color(1.0, 0.9, 0.4), 2.0)
	lr_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	land_ring.material_override = lr_mat
	land_ring.top_level = true
	land_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(land_ring)
	_apply_aim()


func side_name() -> String:
	return SIDE_NAMES[index]


func muzzle_pos() -> Vector3:
	return barrel_pivot.global_transform * Vector3(0, 0, -1.4)


func aim_dir() -> Vector3:
	return -barrel_pivot.global_basis.z


func handle_world() -> Vector3:
	return handle.global_position


## Where the gunner stands to man this cannon (on the deck, inboard of the handle).
func stand_pos() -> Vector3:
	var p := global_position - outboard * 1.75
	return Vector3(p.x, 0.0, p.z)


func base_yaw() -> float:
	return rotation.y


func set_aim(yaw_rel: float, pitch: float) -> void:
	aim_yaw = clampf(yaw_rel, -YAW_LIMIT, YAW_LIMIT)
	aim_pitch = clampf(pitch, PITCH_MIN, PITCH_MAX)
	_apply_aim()


## VR: the barrel points from the gunner's hand through the pivot (push the handle left, it swings right).
func aim_from_handle(hand_pos: Vector3, delta: float) -> void:
	var d := global_basis.inverse() * (global_position - hand_pos)
	var flat := Vector2(d.x, d.z).length()
	if flat < 0.15:
		return
	var want_yaw := atan2(-d.x, -d.z)
	var want_pitch := atan2(d.y, flat) * 1.6  # a little leverage so small hand moves lift it nicely
	var k := 1.0 - exp(-14.0 * delta)
	set_aim(lerp_angle(aim_yaw, want_yaw, k), lerpf(aim_pitch, want_pitch, k))


func _apply_aim() -> void:
	if barrel_pivot:
		barrel_pivot.rotation = Vector3(aim_pitch, aim_yaw, 0.0)


## Host: fire if loaded and ready. Returns true when a ball flew.
func fire() -> bool:
	if reload_t > 0.0:
		return false
	if ammo <= 0:
		main.sound("dry", -2.0)
		main.popup(global_position + Vector3.UP * 1.8, "EMPTY!", Color(1.0, 0.4, 0.3))
		reload_t = 0.4
		return false
	ammo -= 1
	reload_t = RELOAD
	main.spawn_ball(muzzle_pos(), aim_dir() * MUZZLE_SPEED, false, false)
	main.smoke(muzzle_pos() + aim_dir() * 0.4, 1.0)
	main.sound("cannon", 0.0, randf_range(0.9, 1.1))
	main.add_shake(global_position, 0.25)
	fire_fx()
	main.net.event("cannon_fx", [index])
	return true


## Barrel recoil (the smoke and bang are broadcast separately).
func fire_fx() -> void:
	recoil = 1.0


func _process(delta: float) -> void:
	reload_t = maxf(0.0, reload_t - delta)
	recoil = maxf(0.0, recoil - delta * 2.5)
	if barrel_root:
		barrel_root.position.z = recoil * recoil * 0.45
	for i in rack_balls.size():
		rack_balls[i].visible = i < ammo
	handle_mat.emission_energy_multiplier = 2.5 if (grabbed or hover) else (0.9 if manned else 0.3)
	if ammo <= 0:
		label.text = "%s\nEMPTY!\nBring cannonballs!" % side_name()
		label.modulate = Color(1.0, 0.35 + 0.25 * sin(Time.get_ticks_msec() * 0.01), 0.3)
	else:
		label.text = "%s\nAMMO %d/%d" % [side_name(), ammo, MAX_AMMO]
		label.modulate = Color(1.0, 0.95, 0.6) if ammo > 1 else Color(1.0, 0.7, 0.3)
	_draw_arc()


## Faint dotted arc of where the ball will fly, with a ring where it meets the sea.
func _draw_arc() -> void:
	arc_mesh.clear_surfaces()
	arc.visible = manned
	land_ring.visible = manned
	if not manned:
		return
	arc_mat.albedo_color = Color(1.0, 0.95, 0.6, 0.5) if ammo > 0 else Color(1.0, 0.3, 0.25, 0.35)
	var p := muzzle_pos()
	var v := aim_dir() * MUZZLE_SPEED
	var sea: float = main.sea_level
	var g: float = main.GRAVITY
	var dt := 0.07
	arc_mesh.surface_begin(Mesh.PRIMITIVE_LINES, arc_mat)
	var landed := p
	for i in 90:
		var np := p + v * dt
		v.y -= g * dt
		if i % 2 == 0:
			arc_mesh.surface_add_vertex(p)
			arc_mesh.surface_add_vertex(np)
		p = np
		landed = p
		if p.y < sea:
			break
	arc_mesh.surface_end()
	land_ring.global_position = Vector3(landed.x, sea + 0.15, landed.z)


## Snapshot: [yaw, pitch, ammo, manned, reload]
func net_state() -> Array:
	return [aim_yaw, aim_pitch, ammo, manned, reload_t]


func apply_net(st: Array) -> void:
	aim_yaw = lerp_angle(aim_yaw, st[0], 0.6)
	aim_pitch = lerpf(aim_pitch, st[1], 0.6)
	ammo = st[2]
	manned = st[3]
	reload_t = st[4]
	_apply_aim()
