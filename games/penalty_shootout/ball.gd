extends Node3D
## The football. The host (or local game) simulates it: a kick is planned so it lands exactly on the
## striker's reticle after a readable flight (gravity arc plus an optional banana curve that bends back
## onto the target). The keeper's gloves/body, the posts and crossbar, the ground and the net all
## interact with it. On the TV machine it is a ghost that extrapolates the host's snapshots.

const R := 0.11
const G := Vector3(0.0, -9.8, 0.0)
const CURVE_ACC := 7.0  # sideways m/s^2 at full trigger
const GOAL_HALF := 3.66
const GOAL_H := 2.44
const POST_X := 3.72
const BAR_Y := 2.50
const POST_R := 0.06
const NET_D := 2.0
const SUBSTEPS := 4

var main
var ghost := false
var vel := Vector3.ZERO
var acc := Vector3.ZERO  # curve
var flying := false
var live := false  # can still become a goal / save / miss
var in_net := false
var flight_t := 0.0
var curve_on := true
var mesh: MeshInstance3D
var mat: StandardMaterial3D
var shadow: MeshInstance3D
var trail: CPUParticles3D
var glow := 0.0
var net_pos := Vector3.ZERO
var net_vel := Vector3.ZERO
var bounce_t := 0.0


func _ready() -> void:
	mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = R
	sm.height = R * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mesh.mesh = sm
	mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.roughness = 0.45
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.3)
	mat.emission_energy_multiplier = 0.0
	mesh.material_override = mat
	add_child(mesh)
	# Black patches so you can see it spin.
	for i in 4:
		var patch := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = R * 0.35
		pm.height = R * 0.7
		pm.radial_segments = 8
		pm.rings = 4
		patch.mesh = pm
		patch.material_override = main.make_material(Color(0.08, 0.08, 0.1), 0.0)
		var d: Vector3 = [Vector3(1, 0.3, 0), Vector3(-0.6, 0.6, 0.6), Vector3(0, -0.8, -0.6), Vector3(-0.2, 0.1, -1)][i]
		patch.position = d.normalized() * R * 0.78
		patch.scale = Vector3(1, 1, 0.5)
		patch.look_at_from_position(patch.position, Vector3.ZERO, Vector3.UP if absf(d.normalized().y) < 0.9 else Vector3.RIGHT)
		mesh.add_child(patch)
	shadow = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = R * 1.1
	cm.bottom_radius = R * 1.1
	cm.height = 0.004
	cm.radial_segments = 12
	cm.rings = 1
	shadow.mesh = cm
	var sh := StandardMaterial3D.new()
	sh.albedo_color = Color(0, 0, 0, 0.45)
	sh.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sh.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = sh
	shadow.top_level = true
	add_child(shadow)
	trail = CPUParticles3D.new()
	trail.amount = 24
	trail.lifetime = 0.35
	trail.local_coords = false
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_min = 0.0
	trail.initial_velocity_max = 0.1
	trail.scale_amount_min = 0.6
	trail.scale_amount_max = 1.0
	var tm := SphereMesh.new()
	tm.radius = R * 0.6
	tm.height = R * 1.2
	tm.radial_segments = 6
	tm.rings = 3
	trail.mesh = tm
	var trm := StandardMaterial3D.new()
	trm.albedo_color = Color(1.0, 0.95, 0.6, 0.5)
	trm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail.material_override = trm
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	trail.scale_amount_curve = curve
	trail.emitting = false
	add_child(trail)


func place(p: Vector3) -> void:
	position = p
	net_pos = p
	vel = Vector3.ZERO
	net_vel = Vector3.ZERO
	acc = Vector3.ZERO
	flying = false
	live = false
	in_net = false
	flight_t = 0.0
	mesh.rotation = Vector3.ZERO


## Initial velocity and curve acceleration so the ball reaches `target` after a flight at ~`speed`.
static func plan(from: Vector3, target: Vector3, speed: float, curve: float) -> Array:
	var tf: float = maxf(0.25, from.distance_to(target) / maxf(1.0, speed))
	var a := Vector3(curve * CURVE_ACC, 0.0, 0.0)
	var v0: Vector3 = (target - from) / tf - 0.5 * (G + a) * tf
	return [v0, a, tf]


static func point_at(from: Vector3, v0: Vector3, a: Vector3, t: float) -> Vector3:
	return from + v0 * t + 0.5 * (G + a) * t * t


func kick(target: Vector3, speed: float, curve: float) -> void:
	var pl: Array = plan(position, target, speed, curve)
	vel = pl[0]
	acc = pl[1]
	flying = true
	live = true
	in_net = false
	curve_on = true
	flight_t = 0.0


## Host / local: advance the ball. spheres = [[pos, radius, vel, kind], ...] from the keeper.
## Returns "", "post", "bounce", "save:<kind>", "goal", "miss:<reason>" (the first event this step).
func sim(delta: float, spheres: Array) -> String:
	if not flying:
		return ""
	var result := ""
	var h := delta / SUBSTEPS
	flight_t += delta
	for _s in SUBSTEPS:
		var a := G
		if live and curve_on:
			a += acc
		vel += a * h
		var p := position + vel * h
		# Ground.
		if p.y < R:
			p.y = R
			if vel.y < -0.6:
				bounce_t = 0.0
				if result == "":
					result = "bounce"
			if vel.y < 0.0:
				vel.y = -vel.y * 0.5
			vel.x *= 0.97
			vel.z *= 0.97
			curve_on = false
		# Keeper.
		if live:
			for s in spheres:
				var sa: Array = s
				var c: Vector3 = sa[0]
				var rr: float = sa[1]
				var d := p - c
				var dl := d.length()
				if dl < R + rr:
					var n := d / dl if dl > 0.001 else Vector3(0, 0, 1)
					var hv: Vector3 = sa[2]
					var rel := vel - hv
					var vn := rel.dot(n)
					if vn < 0.0:
						vel = vel - 1.5 * vn * n + hv * 0.6
					vel = vel * 0.7
					if vel.z < 2.5:
						vel.z = 2.5 + absf(vel.z) * 0.3  # always knocked back out, away from the goal
					vel.y = maxf(vel.y, 1.0)
					p = c + n * (R + rr + 0.01)
					live = false
					curve_on = false
					result = "save:" + str(sa[3])
					break
		# Posts and crossbar (frame is at z = 0).
		for px in [-POST_X, POST_X]:
			var fx: float = px
			if p.y < BAR_Y + POST_R:
				var d2 := Vector2(p.x - fx, p.z)
				if d2.length() < R + POST_R:
					var n2 := d2.normalized()
					var n3 := Vector3(n2.x, 0.0, n2.y)
					var vn3 := vel.dot(n3)
					if vn3 < 0.0:
						vel -= 1.7 * vn3 * n3
					p = Vector3(fx + n2.x * (R + POST_R + 0.005), p.y, n2.y * (R + POST_R + 0.005))
					curve_on = false
					if result == "" or result == "bounce":
						result = "post"
		if absf(p.x) < POST_X:
			var d3 := Vector2(p.y - BAR_Y, p.z)
			if d3.length() < R + POST_R:
				var n4 := d3.normalized()
				var n5 := Vector3(0.0, n4.x, n4.y)
				var vn5 := vel.dot(n5)
				if vn5 < 0.0:
					vel -= 1.7 * vn5 * n5
				p = Vector3(p.x, BAR_Y + n4.x * (R + POST_R + 0.005), n4.y * (R + POST_R + 0.005))
				curve_on = false
				if result == "" or result == "bounce":
					result = "post"
		# Goal line.
		if live and p.z < -R:
			live = false
			curve_on = false
			if absf(p.x) < GOAL_HALF and p.y < GOAL_H:
				in_net = true
				result = "goal"
			elif p.y >= GOAL_H:
				result = "miss:OVER THE BAR!"
			else:
				result = "miss:WIDE!"
		# The net catches it.
		if in_net:
			if p.z < -NET_D + R:
				p.z = -NET_D + R
				vel *= 0.15
			if absf(p.x) > GOAL_HALF - R:
				p.x = signf(p.x) * (GOAL_HALF - R)
				vel.x *= -0.2
			if p.y > GOAL_H - R:
				p.y = GOAL_H - R
				vel.y = -absf(vel.y) * 0.2
			if p.z > -R:
				p.z = -R
				vel.z = -absf(vel.z) * 0.2
		position = p
	# Spin.
	var sp := Vector3(vel.x, 0.0, vel.z)
	if sp.length() > 0.05:
		mesh.rotate(Vector3(sp.z, 0.0, -sp.x).normalized(), sp.length() * delta / R)
	if live and flight_t > 3.5:
		live = false
		result = "miss:TOO SOFT!"
	if not live and vel.length() < 0.05 and position.y <= R + 0.01:
		flying = false
	return result


func _process(delta: float) -> void:
	if ghost:
		net_pos += net_vel * delta
		if position.distance_to(net_pos) > 2.0:
			position = net_pos
		else:
			position = position.lerp(net_pos, 1.0 - exp(-20.0 * delta))
		var sp := Vector3(net_vel.x, 0.0, net_vel.z)
		if sp.length() > 0.05:
			mesh.rotate(Vector3(sp.z, 0.0, -sp.x).normalized(), sp.length() * delta / R)
	var speed := (net_vel if ghost else vel).length()
	trail.emitting = visible and speed > 4.0
	shadow.visible = visible
	shadow.global_position = Vector3(global_position.x, 0.012, global_position.z)
	var sc := clampf(1.0 - (global_position.y - R) * 0.15, 0.4, 1.0)
	shadow.scale = Vector3(sc, 1.0, sc)
	mat.emission_energy_multiplier = lerpf(mat.emission_energy_multiplier, glow * 1.6, 1.0 - exp(-10.0 * delta))
