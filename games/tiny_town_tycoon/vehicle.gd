extends Node3D
## One toy vehicle on the island: a TV player's (driven by their stick, simulated on the machine
## whose controller drives it, so it reacts instantly), an AI driver's (host: follows A* paths to
## its job), or a mirror of either (the other machine: smoothed towards snapshot positions).
## Kid-friendly driving: push the stick where you want to go and the vehicle turns and drives
## there; roads are fast, grass slower, woods slowest; buildings and water stop you gently.

const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const Art := preload("res://games/tiny_town_tycoon/art.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Town := preload("res://games/tiny_town_tycoon/town.gd")

const MAX_SPEED := 0.21  ## metres per second on a road
const ACCEL := 0.75
const TURN := 7.0  ## radians per second
const RIDE_Y := Defs.GROUND_Y + 0.0012

var vid := 0
var slot := -1  ## driver's party slot, -1 = AI
var kind := "truck"
var accent := Color(1, 1, 1)
var is_player := false
var job_id := 0
var cargo := ""
var spraying := false
var spray_target := Vector3.ZERO
var speed := 0.0
var yaw := 0.0
var honks := 0  ## counts up on every honk (snapshots carry it so both machines play it)
var odometer := 0.0
## Mirror mode: drawn from snapshots / send_state (not simulated here).
var mirror := false
var net_pos := Vector3.ZERO
var net_yaw := 0.0

# AI
var path: Array[Vector2i] = []
var path_i := 0
var path_goal := Vector3(INF, 0, INF)
var repath_t := 0.0
var stuck_t := 0.0
var arrived := false

var body: MeshInstance3D
var cargo_mi: MeshInstance3D
var shadow: MeshInstance3D
var spray_fx: CPUParticles3D
var _shown_cargo := "?"
var _bounce := 0.0
var _lean := 0.0
var _prev_speed := 0.0
var _built_look := ""


func setup(p_kind: String, p_vid: int, p_slot: int, p_accent: Color) -> void:
	kind = p_kind
	vid = p_vid
	slot = p_slot
	accent = p_accent
	is_player = p_slot >= 0
	name = "Vehicle%d" % p_vid
	if is_inside_tree():
		_build_look()


func _ready() -> void:
	_build_look()
	position.y = RIDE_Y


func _build_look() -> void:
	var look := "%s_%s" % [kind, accent.to_html(false)]
	if look == _built_look:
		return
	_built_look = look
	if body == null:
		body = MeshInstance3D.new()
		body.name = "Body"
		add_child(body)
		shadow = MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = Defs.CELL * 0.42
		disc.bottom_radius = Defs.CELL * 0.42
		disc.height = 0.0004
		disc.radial_segments = 14
		disc.rings = 1
		shadow.mesh = disc
		shadow.material_override = Art.ghost_mat(Color(0.0, 0.0, 0.05, 0.28))
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shadow.scale = Vector3(0.75, 1.0, 1.15)
		shadow.position.y = -0.0008
		add_child(shadow)
		cargo_mi = MeshInstance3D.new()
		cargo_mi.visible = false
		body.add_child(cargo_mi)
	body.mesh = Art.vehicle_mesh(kind, accent)
	body.scale = Vector3.ONE * Defs.CELL
	_shown_cargo = "?"


func set_kind(p_kind: String) -> void:
	if p_kind == kind:
		return
	kind = p_kind
	cargo = ""
	_build_look()


# --- Driving -----------------------------------------------------------------------------------------

## Drive towards a world XZ direction (length 0..1 = throttle).
func drive(dir: Vector2, delta: float, town: Town) -> void:
	var want := minf(dir.length(), 1.0)
	if want > 0.05:
		var target_yaw := atan2(dir.x, dir.y)
		var diff := wrapf(target_yaw - yaw, -PI, PI)
		var rate := TURN * (1.6 if absf(diff) > 2.4 else 1.0)
		yaw += clampf(diff, -rate * delta, rate * delta)
		# slow down for sharp turns so cars don't skid round corners
		want *= clampf(1.15 - absf(diff) / PI, 0.25, 1.0)
	var top := MAX_SPEED * town.speed_at(position) * want
	speed = move_toward(speed, top, ACCEL * delta * (1.6 if top < speed else 1.0))
	_move(delta, town)


func _move(delta: float, town: Town) -> void:
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var step := fwd * speed * delta
	if step.length_squared() < 1e-12:
		_finish_move()
		return
	var from := position
	var stuck_inside := not town.drivable_at(from)
	var np := from + step
	if stuck_inside or _free(np, fwd, town):
		position = np
	else:
		var px := from + Vector3(step.x, 0.0, 0.0)
		var pz := from + Vector3(0.0, 0.0, step.z)
		if absf(step.x) > absf(step.z) * 0.3 and _free(px, fwd, town):
			position = px
			speed *= 0.9
		elif absf(step.z) > absf(step.x) * 0.3 and _free(pz, fwd, town):
			position = pz
			speed *= 0.9
		else:
			if speed > MAX_SPEED * 0.5:
				_bounce = 1.0
			speed = 0.0
	odometer += position.distance_to(from)
	_finish_move()


func _finish_move() -> void:
	var lim := Defs.HALF + Defs.CELL
	position.x = clampf(position.x, -lim, lim)
	position.z = clampf(position.z, -lim, lim)
	position.y = RIDE_Y
	rotation.y = yaw


func _free(p: Vector3, fwd: Vector3, town: Town) -> bool:
	if not town.drivable_at(p):
		return false
	return town.drivable_at(p + fwd * Defs.CELL * 0.32)


## Push this vehicle out of another one (soft bumpers).
func separate(other_pos: Vector3, town: Town) -> void:
	var d := Vector2(position.x - other_pos.x, position.z - other_pos.z)
	var min_d := Defs.CELL * 0.62
	var l := d.length()
	if l >= min_d:
		return
	if l < 0.0001:
		d = Vector2(cos(vid * 1.7), sin(vid * 1.7))
		l = 0.0001
	var push := d / l * (min_d - l) * 0.5
	var np := position + Vector3(push.x, 0.0, push.y)
	if town.drivable_at(np):
		position = np


# --- AI driver ------------------------------------------------------------------------------------------

## Drive along roads to `goal` (re-plans when the goal moves or it gets stuck). Returns true on arrival.
func ai_drive(goal: Vector3, delta: float, town: Town) -> bool:
	repath_t -= delta
	var goal_moved := Vector2(goal.x - path_goal.x, goal.z - path_goal.z).length() > Defs.CELL * 0.6
	if goal_moved or repath_t <= 0.0:
		path = town.find_path(Defs.world_cell(position), Defs.world_cell(goal))
		path_i = 0
		path_goal = goal
		repath_t = 3.0
	var target := goal
	while path_i < path.size():
		var c := path[path_i]
		var cp := Defs.cell_center(c.x, c.y)
		if Vector2(cp.x - position.x, cp.z - position.z).length() < Defs.CELL * 0.5:
			path_i += 1
			continue
		target = cp
		break
	var to := Vector2(target.x - position.x, target.z - position.z)
	var last_leg := path_i >= path.size() - 1
	if last_leg and Vector2(goal.x - position.x, goal.z - position.z).length() < Defs.CELL * 0.3:
		drive(Vector2.ZERO, delta, town)
		arrived = true
		return true
	arrived = false
	var throttle := 1.0
	if last_leg:
		throttle = clampf(to.length() / (Defs.CELL * 1.2), 0.35, 1.0)
	var before := position
	drive(to.normalized() * throttle if to.length() > 0.0001 else Vector2.ZERO, delta, town)
	if position.distance_to(before) < MAX_SPEED * 0.05 * delta:
		stuck_t += delta
		if stuck_t > 1.2:
			stuck_t = 0.0
			repath_t = 0.0
			yaw += randf_range(-1.2, 1.2)
	else:
		stuck_t = 0.0
	return false


## Park gently (no job): slow to a stop.
func idle(delta: float, town: Town) -> void:
	drive(Vector2.ZERO, delta, town)


# --- Honk and looks ----------------------------------------------------------------------------------------

func honk() -> void:
	honks += 1
	_bounce = 0.6


## Mirror: smooth towards the latest snapshot / send_state pose.
func mirror_update(delta: float) -> void:
	var k := 1.0 - exp(-14.0 * delta)
	var before := position
	if position.distance_to(net_pos) > Defs.CELL * 4.0:
		position = net_pos
	else:
		position = position.lerp(net_pos, k)
	yaw = lerp_angle(yaw, net_yaw, k)
	rotation.y = yaw
	speed = position.distance_to(before) / maxf(delta, 0.0001)


func _process(delta: float) -> void:
	if body == null:
		return
	# bounce on bumps and honks, lean on acceleration
	var accel := (speed - _prev_speed) / maxf(delta, 0.0001)
	_prev_speed = speed
	_lean = lerpf(_lean, clampf(-accel * 0.4, -0.12, 0.12), 1.0 - exp(-8.0 * delta))
	_bounce = maxf(0.0, _bounce - delta * 3.0)
	var hop := sin(_bounce * PI * 2.0) * _bounce * 0.006
	var rumble := sin(Time.get_ticks_msec() * 0.05 + vid) * 0.0003 * clampf(speed / MAX_SPEED, 0.0, 1.0)
	body.position = Vector3(0.0, maxf(0.0, hop) + rumble, 0.0)
	body.rotation = Vector3(_lean, 0.0, 0.0)
	if cargo != _shown_cargo:
		_shown_cargo = cargo
		_show_cargo()
	_update_spray()


func _show_cargo() -> void:
	if cargo == "" or kind == "bus" or kind == "fire" or kind == "police":
		cargo_mi.visible = false
		return
	cargo_mi.mesh = Art.cargo_mesh(cargo)
	cargo_mi.visible = true
	cargo_mi.position = Vector3(0.0, 0.42, -0.12) if kind == "truck" else Vector3(0.0, 0.28, -0.32)


func _update_spray() -> void:
	if not spraying:
		if spray_fx != null:
			spray_fx.emitting = false
		return
	if spray_fx == null:
		spray_fx = CPUParticles3D.new()
		spray_fx.amount = 28
		spray_fx.lifetime = 0.45
		spray_fx.spread = 8.0
		spray_fx.gravity = Vector3(0, -0.6, 0)
		spray_fx.initial_velocity_min = 0.18
		spray_fx.initial_velocity_max = 0.24
		spray_fx.scale_amount_min = 0.6
		spray_fx.scale_amount_max = 1.2
		var sm := SphereMesh.new()
		sm.radius = 0.0025
		sm.height = 0.005
		sm.radial_segments = 6
		sm.rings = 3
		sm.material = MeshKit.material(Color(0.55, 0.82, 1.0, 0.85), 0.6)
		spray_fx.mesh = sm
		spray_fx.local_coords = false
		add_child(spray_fx)
		spray_fx.position = Vector3(0.0, Defs.CELL * 0.4, Defs.CELL * 0.1)
	spray_fx.emitting = true
	var to := spray_target - spray_fx.global_position
	to.y = 0.0
	if to.length() > 0.001:
		var dir := (to.normalized() + Vector3.UP * 0.55).normalized()
		spray_fx.direction = global_basis.inverse() * dir
