extends RefCounted
## OBSTACLE RUSH obstacle kit. Every moving obstacle is a node with a `phase` (its own clock, or an
## angle) that the host simulates and the TV machine mirrors from snapshots, so both machines see the
## same sweep at the same moment. Hits are analytic (a runner's capsule against a bar, a hammer head,
## a ball...), which is cheap, identical everywhere and gives a juicy knock direction.
##   Sweeper    spinning bar(s) round a hub (jump the low ones)
##   Hammer     pendulum hammer swinging across a lane
##   Spinner    rotating disc platform (carries runners: AnimatableBody3D)
##   Seesaw     plank that tips towards whoever stands on it
##   TiltDeck   platform the Game Master's wheel tilts
##   Conveyor   belt that pushes runners along (a static body with "belt" metadata)
##   DoorRow    a wall of doors: real ones burst open, fake ones go BOING
##   HexField   layers of hexagon tiles that drop after you step on them
##   FoamBlob   a foam-cannon shot (deterministic arc, same on both machines)
##   Ball       beach ball / team ball (rigid body on the host, a mirrored ghost on the TV)
##   Pad        the Game Master's helpers: bounce pad, speed strip, bridge
## Layers: everything solid is on physics layer 1 ("world"); runners only collide with layer 1.

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
## This script (inner classes call the static helpers through it).
const Obs := preload("res://games/obstacle_rush/obstacles.gd")

const L_WORLD := 1
const RUNNER_R := 0.36
const RUNNER_H := 1.12
const VERSION := "v1"
const RED := Color(1.0, 0.3, 0.35)
const WHITE := Color(0.98, 0.97, 0.95)
const PINK := Color(1.0, 0.5, 0.75)
const YELLOW := Color(1.0, 0.85, 0.3)
const BLUE := Color(0.35, 0.65, 1.0)
const MINT := Color(0.45, 0.95, 0.7)
const PURPLE := Color(0.7, 0.5, 1.0)


## A static collision box (on layer 1) as a child of `parent`, centred at `xf.origin`.
static func static_box(parent: Node, size: Vector3, xf: Transform3D, meta: Dictionary = {}) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = L_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	for k in meta:
		body.set_meta(str(k), meta[k])
	parent.add_child(body)
	body.transform = xf
	return body


## Wrap an angle to 0..TAU.
static func wrap_tau(a: float) -> float:
	return fposmod(a, TAU)


## Closest distance from point p to segment a-b.
static func seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


# --------------------------------------------------------------------------------------------------

class Obstacle extends Node3D:
	## Base class. `phase` advances by dt * speed_mult on both machines; on the TV machine it is also
	## pulled towards the host's value from the snapshot (set_net_phase).
	var phase := 0.0
	var speed_mult := 1.0
	var _net := 0.0
	var _has_net := false
	## Can a runner jump over it? (CPU runners jump low bars and wait for hammers.)
	var jumpable := false

	func tick(dt: float) -> void:
		phase += dt * speed_mult
		if _has_net:
			_net += dt * speed_mult
			var diff := _net - phase
			if absf(diff) > 2.0:
				phase = _net
			else:
				phase += diff * (1.0 - exp(-6.0 * dt))
		_apply()

	## Host: the value mirrored to the TV machine (the phase; angles / masks for some obstacles).
	func net_value() -> float:
		return phase

	## TV machine: the host's value from a snapshot.
	func set_net_phase(p: float) -> void:
		_net = p
		if not _has_net:
			phase = p
		_has_net = true

	func _apply() -> void:
		pass

	## Knock impulse for a runner touching this obstacle now (Vector3.ZERO: no hit).
	func hit(_r: Node3D) -> Vector3:
		return Vector3.ZERO

	## Would a runner standing at `feet` be hit `t_ahead` seconds from now? (CPU / bot planning.)
	func threat(_feet: Vector3, _t_ahead: float) -> bool:
		return false


# --------------------------------------------------------------------------------------------------

class Sweeper extends Obstacle:
	## Bars spinning round a hub at `height` above the hub's base. Low bars are jumped; high bars
	## pass over your head unless you jump into them.
	var arms := 2
	var length := 6.0
	var height := 0.55
	var thick := 0.26
	var omega := 1.2
	var start := 0.0
	var color := RED
	var bar: Node3D

	func setup(hub_height: float = 1.6) -> void:
		jumpable = height < 1.0
		# The hub: a solid post (collides), with a candy-striped cap.
		var hb := MeshKit.Builder.new()
		hb.cylinder(0.45, 0.6, hub_height, MeshKit.at(Vector3(0, hub_height * 0.5, 0)), WHITE, 14)
		for k in 3:
			hb.torus(0.52, 0.06, MeshKit.at(Vector3(0, 0.25 + k * hub_height * 0.3, 0)), color, 14, 5)
		hb.sphere(0.4, MeshKit.at(Vector3(0, hub_height + 0.1, 0)), YELLOW, 12)
		add_child(MeshKit.instance(hb.build()))
		var post := StaticBody3D.new()
		post.collision_layer = L_WORLD
		post.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.55
		cyl.height = hub_height
		cs.shape = cyl
		cs.position.y = hub_height * 0.5
		post.add_child(cs)
		post.set_meta("kind", "bumper")
		add_child(post)
		bar = Node3D.new()
		bar.position.y = height
		add_child(bar)
		var key := "or_sweep_%d_%.2f_%.2f_%s_%s" % [arms, length, thick, color.to_html(false), VERSION]
		var mesh: ArrayMesh = ResCache.get_or_make(key, func() -> Resource:
			var b := MeshKit.Builder.new()
			for k in arms:
				var a := TAU * k / arms
				var d := Basis(Vector3.UP, a) * Vector3.RIGHT
				var segs := int(ceil(length / 1.0))
				for s in segs:
					var a0 := d * (0.4 + (length - 0.4) * float(s) / segs)
					var a1 := d * (0.4 + (length - 0.4) * float(s + 1) / segs)
					b.capsule_between(a0, a1, thick, color if s % 2 == 0 else WHITE, 10)
				b.sphere(thick * 1.5, MeshKit.at(d * length), YELLOW, 10)
			b.cylinder(0.55, 0.55, thick * 2.4, MeshKit.at(Vector3.ZERO), color.darkened(0.2), 14)
			return b.build())
		var mi := MeshKit.instance(mesh)
		bar.add_child(mi)
		_apply()

	func angle_at(ph: float) -> float:
		return start + omega * ph

	func _apply() -> void:
		if bar != null:
			bar.rotation.y = angle_at(phase)

	func hit(r: Node3D) -> Vector3:
		return _hit_at(r.global_position, phase, true)

	func threat(feet: Vector3, t_ahead: float) -> bool:
		return _hit_at(feet, phase + t_ahead * speed_mult, false) != Vector3.ZERO

	func _hit_at(p: Vector3, ph: float, full: bool) -> Vector3:
		var c := global_position
		var bar_y := c.y + height
		if p.y > bar_y + thick or p.y + RUNNER_H < bar_y - thick:
			return Vector3.ZERO
		var rel := Vector3(p.x - c.x, 0.0, p.z - c.z)
		if rel.length() > length + RUNNER_R + thick:
			return Vector3.ZERO
		var a0 := angle_at(ph)
		for k in arms:
			var d := Basis(Vector3.UP, a0 + TAU * k / arms) * Vector3.RIGHT
			var s := clampf(rel.dot(d), 0.0, length)
			var off := rel - d * s
			if off.length() < thick + RUNNER_R:
				if not full:
					return Vector3.UP
				var w := omega * speed_mult
				var tang := Vector3.UP.cross(d) * signf(w)
				var spd := clampf(absf(w) * maxf(s, 1.5) * 1.15, 6.5, 13.0)
				var away := off.normalized() if off.length() > 0.01 else tang
				return tang * spd + away * 1.5 + Vector3.UP * 5.5
		return Vector3.ZERO


# --------------------------------------------------------------------------------------------------

class Hammer extends Obstacle:
	## A pendulum hammer. The pivot is this node's position; it swings in the plane across `facing`
	## (the lane direction), so the head sweeps sideways over the lane.
	var arm := 4.6
	var amp := 1.15
	var omega := 1.7
	var offset := 0.0
	var head_r := 0.7
	var head_len := 1.7
	var color := PINK
	var swing: Node3D

	func setup() -> void:
		swing = Node3D.new()
		add_child(swing)
		var key := "or_hammer_%.2f_%.2f_%.2f_%s_%s" % [arm, head_r, head_len, color.to_html(false), VERSION]
		var mesh: ArrayMesh = ResCache.get_or_make(key, func() -> Resource:
			var b := MeshKit.Builder.new()
			b.cylinder(0.12, 0.12, arm, MeshKit.at(Vector3(0, -arm * 0.5, 0)), Color(0.85, 0.85, 0.9), 8)
			b.sphere(0.28, MeshKit.at(Vector3.ZERO), Color(0.5, 0.5, 0.6), 10)
			var hx := MeshKit.at(Vector3(0, -arm, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5))
			b.cylinder(head_r, head_r, head_len, hx, color, 16)
			for side in [-1.0, 1.0]:
				var sd: float = side
				b.cylinder(head_r * 1.06, head_r * 1.06, 0.18, MeshKit.at(Vector3(sd * head_len * 0.42, -arm, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5)), WHITE, 16)
				b.dome(head_r * 0.55, MeshKit.at(Vector3(sd * head_len * 0.5, -arm, 0), Vector3.ONE, Vector3(0, 0, -sd * PI * 0.5)), YELLOW, 12)
			return b.build())
		swing.add_child(MeshKit.instance(mesh))
		_apply()

	func angle_at(ph: float) -> float:
		return amp * sin(omega * ph + offset)

	func _apply() -> void:
		if swing != null:
			swing.rotation.z = angle_at(phase)

	func _head(ph: float) -> Array:
		var basis_w := global_basis * Basis(Vector3.BACK, angle_at(ph))
		var head := global_position + basis_w * Vector3(0, -arm, 0)
		var tang := (basis_w * Vector3.RIGHT).normalized()
		return [head, tang]

	func hit(r: Node3D) -> Vector3:
		return _hit_at(r.global_position, phase, true)

	func threat(feet: Vector3, t_ahead: float) -> bool:
		return _hit_at(feet, phase + t_ahead * speed_mult, false) != Vector3.ZERO

	func _hit_at(p: Vector3, ph: float, full: bool) -> Vector3:
		var ht := _head(ph)
		var head: Vector3 = ht[0]
		var tang: Vector3 = ht[1]
		var c := p + Vector3.UP * RUNNER_H * 0.5
		var a := head - tang * head_len * 0.5
		var b := head + tang * head_len * 0.5
		# capsule (runner) vs capsule (head): distance between the runner's spine and the head axis
		var best := INF
		for k in 3:
			var q := p + Vector3.UP * (0.25 + 0.31 * k)
			best = minf(best, Obs.seg_dist(q, a, b))
		if best > head_r + RUNNER_R * 0.9:
			return Vector3.ZERO
		if not full:
			return Vector3.UP
		var dth := amp * omega * cos(omega * ph + offset) * speed_mult
		var dir := tang * signf(dth)
		var flat_dir := Vector3(dir.x, 0.0, dir.z)
		if flat_dir.length() < 0.2:
			flat_dir = Vector3(c.x - head.x, 0.0, c.z - head.z)
		flat_dir = flat_dir.normalized()
		var spd := clampf(absf(dth) * arm * 0.9, 7.0, 13.0)
		return flat_dir * spd + Vector3.UP * 6.0


# --------------------------------------------------------------------------------------------------

class Spinner extends Obstacle:
	## A rotating disc platform. Runners standing on it are carried round (AnimatableBody3D).
	var radius := 3.5
	var thick := 0.6
	var omega := 0.6
	var color := BLUE
	var body: AnimatableBody3D
	var bumps := 0  # little bumpers on the rim

	func setup() -> void:
		body = AnimatableBody3D.new()
		body.collision_layer = L_WORLD
		body.collision_mask = 0
		body.sync_to_physics = true
		add_child(body)
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = radius
		cyl.height = thick
		cs.shape = cyl
		cs.position.y = -thick * 0.5
		body.add_child(cs)
		var key := "or_spinner_%.2f_%.2f_%s_%d_%s" % [radius, thick, color.to_html(false), bumps, VERSION]
		var mesh: ArrayMesh = ResCache.get_or_make(key, func() -> Resource:
			var b := MeshKit.Builder.new()
			b.cylinder(radius, radius * 0.92, thick, MeshKit.at(Vector3(0, -thick * 0.5, 0)), color, 24)
			for k in 6:
				var a := TAU * k / 6.0
				var d := Basis(Vector3.UP, a) * Vector3.RIGHT
				b.box(Vector3(radius * 0.9, 0.04, 0.5), MeshKit.at(d * radius * 0.48 + Vector3(0, 0.01, 0), Vector3.ONE, Vector3(0, a, 0)), WHITE)
			b.cylinder(0.7, 0.7, 0.08, MeshKit.at(Vector3(0, 0.03, 0)), YELLOW, 16)
			b.torus(radius - 0.08, 0.1, MeshKit.at(Vector3(0, 0.0, 0)), WHITE, 24, 5)
			return b.build())
		body.add_child(MeshKit.instance(mesh))
		_apply()

	func _apply() -> void:
		if body != null:
			body.rotation.y = omega * phase


# --------------------------------------------------------------------------------------------------

class Seesaw extends Obstacle:
	## A long plank (along local -Z) on a pivot; it tips sideways towards whoever stands on it.
	## The host simulates the tilt from the runners on it; the TV mirrors the angle (phase = angle).
	var size := Vector3(4.0, 0.5, 9.0)
	var max_angle := 0.38
	var color := YELLOW
	var body: AnimatableBody3D
	var angle := 0.0
	var ang_v := 0.0
	var host := true
	## Set by the course each frame on the host: lateral offsets of runners standing on it.
	var loads: Array[float] = []

	func setup() -> void:
		body = AnimatableBody3D.new()
		body.collision_layer = L_WORLD
		body.collision_mask = 0
		body.sync_to_physics = true
		body.set_meta("slippery", true)
		add_child(body)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		body.add_child(cs)
		var key := "or_seesaw_%s_%s_%s" % [size, color.to_html(false), VERSION]
		var mesh: ArrayMesh = ResCache.get_or_make(key, func() -> Resource:
			var b := MeshKit.Builder.new()
			b.rounded_box(size, 0.12, MeshKit.at(Vector3.ZERO), color, 1)
			var n := int(size.z / 1.5)
			for k in n:
				var z := -size.z * 0.5 + (k + 0.5) * size.z / n
				b.box(Vector3(size.x * 0.96, 0.03, 0.18), MeshKit.at(Vector3(0, size.y * 0.5, z)), WHITE)
			b.box(Vector3(0.12, 0.04, size.z * 0.96), MeshKit.at(Vector3(0, size.y * 0.5 + 0.01, 0)), RED)
			return b.build())
		body.add_child(MeshKit.instance(mesh))
		# the pivot block underneath (visual + solid)
		var pv := MeshKit.Builder.new()
		pv.cylinder(0.3, 0.3, size.z * 0.85, MeshKit.at(Vector3(0, -size.y * 0.5 - 0.25, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.55, 0.55, 0.65), 10)
		for e in [-1.0, 1.0]:
			var ez: float = e
			pv.box(Vector3(0.5, 2.5, 0.5), MeshKit.at(Vector3(0, -size.y * 0.5 - 1.5, ez * size.z * 0.38)), Color(0.5, 0.5, 0.6))
		add_child(MeshKit.instance(pv.build()))

	func tick(dt: float) -> void:
		if host:
			var torque := 0.0
			for off in loads:
				torque += off
			loads.clear()
			# tip towards the load, settle back slowly when empty
			ang_v += (-torque * 0.9 - angle * 1.6 - ang_v * 2.2) * dt
			angle = clampf(angle + ang_v * dt, -max_angle, max_angle)
			if absf(angle) >= max_angle:
				ang_v = 0.0
			phase = angle
		else:
			angle = lerpf(angle, _net, 1.0 - exp(-10.0 * dt))
			phase = angle
		_apply()

	func net_value() -> float:
		return angle

	func set_net_phase(p: float) -> void:
		_net = p
		_has_net = true
		host = false

	func _apply() -> void:
		if body != null:
			body.rotation.z = angle

	## Lateral offset of a world point across the plank (+ = towards local +X).
	func lateral(p: Vector3) -> float:
		return (global_transform.affine_inverse() * p).x

	## Is a point above the plank (within its footprint)?
	func over(p: Vector3) -> bool:
		var l := global_transform.affine_inverse() * p
		return absf(l.x) < size.x * 0.5 + 0.2 and absf(l.z) < size.z * 0.5 + 0.2 and l.y > -0.5 and l.y < 2.0


# --------------------------------------------------------------------------------------------------

class TiltDeck extends Obstacle:
	## A platform the Game Master's TILT wheel tips (phase = angle, set by the course from the wheel).
	var size := Vector3(10.0, 0.6, 8.0)
	var max_angle := 0.3
	var color := MINT
	var axis := "z"  # tilt round local Z (sideways) or X (front/back)
	var body: AnimatableBody3D
	var target := 0.0  # -1..1 from the wheel (host)
	var angle := 0.0
	var host := true
	var wobble := 0.0  # extra gentle rocking amplitude (radians)

	func setup() -> void:
		body = AnimatableBody3D.new()
		body.collision_layer = L_WORLD
		body.collision_mask = 0
		body.sync_to_physics = true
		body.set_meta("slippery", true)
		add_child(body)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		body.add_child(cs)
		var key := "or_tilt_%s_%s_%s" % [size, color.to_html(false), VERSION]
		var mesh: ArrayMesh = ResCache.get_or_make(key, func() -> Resource:
			var b := MeshKit.Builder.new()
			b.rounded_box(size, 0.15, MeshKit.at(Vector3.ZERO), color, 1)
			for i in 3:
				for j in 3:
					if (i + j) % 2 == 0:
						b.box(Vector3(size.x / 3.0 - 0.2, 0.03, size.z / 3.0 - 0.2), MeshKit.at(Vector3((i - 1) * size.x / 3.0, size.y * 0.5, (j - 1) * size.z / 3.0)), WHITE)
			return b.build())
		body.add_child(MeshKit.instance(mesh))
		var pv := MeshKit.Builder.new()
		pv.cylinder(0.5, 0.9, 2.5, MeshKit.at(Vector3(0, -size.y * 0.5 - 1.25, 0)), Color(0.55, 0.55, 0.65), 10)
		add_child(MeshKit.instance(pv.build()))

	func tick(dt: float) -> void:
		if host:
			var want := clampf(target, -1.0, 1.0) * max_angle + sin(phase * 0.9) * wobble
			phase += dt * speed_mult
			angle = lerpf(angle, want, 1.0 - exp(-2.5 * dt))
		else:
			angle = lerpf(angle, _net, 1.0 - exp(-10.0 * dt))
		_apply()

	## Mirrored value is the angle itself.
	func net_value() -> float:
		return angle

	func set_net_phase(p: float) -> void:
		_net = p
		_has_net = true
		host = false

	func _apply() -> void:
		if body == null:
			return
		if axis == "z":
			body.rotation.z = angle
		else:
			body.rotation.x = angle


# --------------------------------------------------------------------------------------------------

class Conveyor extends Obstacle:
	## A belt. Runners on it get `dir * speed * speed_mult` added (static body with "belt" meta).
	var size := Vector3(4.0, 0.5, 10.0)
	var speed := 3.5
	var dir := Vector3.BACK  # world push direction (horizontal)
	var body: StaticBody3D
	var mat: ShaderMaterial

	const SHADER := """
shader_type spatial;
uniform vec4 col_a : source_color = vec4(0.25, 0.25, 0.32, 1.0);
uniform vec4 col_b : source_color = vec4(1.0, 0.82, 0.3, 1.0);
uniform vec3 dir = vec3(0.0, 0.0, 1.0);
uniform float speed = 3.0;
uniform float shift = 0.0;
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float s = fract(dot(wp, dir) * 0.6 - shift * 0.6);
	float chev = step(0.5, fract(s + abs(dot(wp, cross(dir, vec3(0.0, 1.0, 0.0)))) * 0.35));
	vec3 c = mix(col_a.rgb, col_b.rgb, chev * step(0.5, wn.y));
	if (wn.y < 0.5) { c = col_a.rgb * 0.8; }
	ALBEDO = c;
	ROUGHNESS = 0.6;
}
"""

	func setup() -> void:
		body = Obs.static_box(self, size, Transform3D.IDENTITY, {"kind": "belt"})
		body.set_meta("belt_obj", self)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mat = ResCache.get_or_make("or_belt_mat_%s_%s" % [dir, VERSION], func() -> Resource:
			var sh := Shader.new()
			sh.code = SHADER
			var m := ShaderMaterial.new()
			m.shader = sh
			return m) as ShaderMaterial
		mat = mat.duplicate() as ShaderMaterial
		mat.set_shader_parameter("dir", dir.normalized())
		mi.material_override = mat
		add_child(mi)
		# rollers at both ends
		var rb := MeshKit.Builder.new()
		var along := (global_basis.inverse() * dir).normalized() if is_inside_tree() else Vector3.BACK
		var across := Vector3.UP.cross(along).normalized()
		for e in [-1.0, 1.0]:
			var ee: float = e
			var p := along * (absf(along.dot(size)) * 0.5) * ee + Vector3(0, -0.05, 0)
			rb.cylinder(size.y * 0.55, size.y * 0.55, absf(across.dot(size)) + 0.2, Transform3D(Basis(across.cross(Vector3.UP).normalized(), across, Vector3.UP).orthonormalized(), p), Color(0.3, 0.3, 0.38), 12)
		add_child(MeshKit.instance(rb.build()))

	func velocity() -> Vector3:
		return dir.normalized() * speed * speed_mult

	func _apply() -> void:
		if mat != null:
			mat.set_shader_parameter("shift", phase * speed)


# --------------------------------------------------------------------------------------------------

class DoorRow extends Obstacle:
	## A wall with `count` doors across it. `real` lists which doors burst open; the rest are fake and
	## bounce runners back. Door state is a bit mask (replicated as `phase`).
	var count := 5
	var width := 14.0
	var height := 3.2
	var thick := 0.6
	var real: Array[int] = []
	var open_mask := 0
	var doors: Array[StaticBody3D] = []
	var panels: Array[Node3D] = []
	var fly := {}  # index -> seconds since it burst
	var wall_color := Color(0.98, 0.6, 0.75)

	func setup() -> void:
		var dw := width / count
		var door_w := dw - 0.7
		var wb := MeshKit.Builder.new()
		for i in count + 1:
			# pillars between doors (solid)
			var x := -width * 0.5 + i * dw
			var pw := 0.7 if i > 0 and i < count else 0.35
			var px := x + (0.175 if i == 0 else (-0.175 if i == count else 0.0))
			Obs.static_box(self, Vector3(pw, height, thick), Transform3D(Basis(), Vector3(px, height * 0.5, 0)))
			wb.rounded_box(Vector3(pw, height, thick + 0.1), 0.08, MeshKit.at(Vector3(px, height * 0.5, 0)), wall_color, 1)
			wb.sphere(0.32, MeshKit.at(Vector3(px, height + 0.25, 0)), YELLOW, 10)
		wb.rounded_box(Vector3(width, 0.5, thick + 0.15), 0.1, MeshKit.at(Vector3(0, height + 0.05, 0)), wall_color.darkened(0.1), 1)
		Obs.static_box(self, Vector3(width, 0.5, thick), Transform3D(Basis(), Vector3(0, height + 0.05, 0)))
		add_child(MeshKit.instance(wb.build()))
		for i in count:
			var x := -width * 0.5 + (i + 0.5) * dw
			var is_real := real.has(i)
			var body := Obs.static_box(self, Vector3(door_w, height - 0.1, 0.3), Transform3D(Basis(), Vector3(x, (height - 0.1) * 0.5, 0)),
				{"kind": "door" if is_real else "fake_door", "door_row": self, "door_index": i})
			doors.append(body)
			var panel := Node3D.new()
			panel.position = Vector3(x, (height - 0.1) * 0.5, 0)
			add_child(panel)
			var key := "or_door_%.2f_%.2f_%s" % [door_w, height, VERSION]
			var mesh: ArrayMesh = ResCache.get_or_make(key, func() -> Resource:
				var b := MeshKit.Builder.new()
				b.rounded_box(Vector3(door_w, height - 0.1, 0.3), 0.1, MeshKit.at(Vector3.ZERO), Color(0.55, 0.85, 1.0), 1)
				b.rounded_box(Vector3(door_w * 0.7, (height - 0.1) * 0.35, 0.36), 0.08, MeshKit.at(Vector3(0, 0.5, 0)), WHITE, 1)
				b.rounded_box(Vector3(door_w * 0.7, (height - 0.1) * 0.25, 0.36), 0.08, MeshKit.at(Vector3(0, -0.6, 0)), WHITE, 1)
				b.sphere(0.12, MeshKit.at(Vector3(door_w * 0.32, -0.1, 0.0), Vector3(1, 1, 2.0)), YELLOW, 8)
				return b.build())
			panel.add_child(MeshKit.instance(mesh))
			panels.append(panel)

	func is_open(i: int) -> bool:
		return (open_mask >> i) & 1 == 1

	## Burst a real door open (both machines; the host's mask is mirrored).
	func open_door(i: int) -> bool:
		if i < 0 or i >= count or is_open(i) or not real.has(i):
			return false
		open_mask |= 1 << i
		(doors[i].get_child(0) as CollisionShape3D).set_deferred("disabled", true)
		fly[i] = 0.0
		return true

	func tick(dt: float) -> void:
		for i in fly.keys():
			var t: float = float(fly[i]) + dt
			fly[i] = t
			var p := panels[int(i)]
			if t < 1.2:
				p.position.z = -t * 9.0
				p.position.y = (height - 0.1) * 0.5 + t * 3.0 - t * t * 6.0
				p.rotation.x = -t * 4.0
				p.scale = Vector3.ONE * maxf(0.01, 1.0 - t * 0.6)
			else:
				p.visible = false
				fly.erase(i)

	func net_value() -> float:
		return float(open_mask)

	func set_net_phase(p: float) -> void:
		var m := int(p)
		for i in count:
			if (m >> i) & 1 == 1 and not is_open(i):
				open_door(i)


# --------------------------------------------------------------------------------------------------

class HexField extends Node3D:
	## Layers of hexagon tiles. A tile someone stands on wobbles, then drops. Tile states (0 solid,
	## 1 wobbling, 2 gone) are host-decided and mirrored as one byte per tile.
	var layers := 3
	var ring := 4
	var tile_r := 1.45
	var layer_gap := 6.0
	var fall_delay := 0.75
	var colors: Array[Color] = [Color(1.0, 0.55, 0.75), Color(0.45, 0.8, 1.0), Color(1.0, 0.85, 0.35)]
	var centers: Array[Vector3] = []  # per tile
	var tile_layer := PackedInt32Array()
	var tile_state := PackedByteArray()
	var tile_t := PackedFloat32Array()  # seconds in the current state
	var shapes: Array[CollisionShape3D] = []
	var mms: Array[MultiMesh] = []
	var axial := {}  # Vector3i(layer, q, r) -> tile index
	var dropped := 0

	func setup() -> void:
		var shape := ConvexPolygonShape3D.new()
		var pts := PackedVector3Array()
		for k in 6:
			var a := TAU * k / 6.0
			pts.append(Vector3(cos(a) * (tile_r - 0.06), 0.0, sin(a) * (tile_r - 0.06)))
			pts.append(Vector3(cos(a) * (tile_r - 0.06), -0.5, sin(a) * (tile_r - 0.06)))
		shape.points = pts
		var key := "or_hex_%.2f_%s" % [tile_r, VERSION]
		var mesh: ArrayMesh = ResCache.get_or_make(key, func() -> Resource:
			var b := MeshKit.Builder.new()
			b.prism(6, tile_r - 0.07, 0.5, MeshKit.at(Vector3(0, -0.25, 0)), Color.WHITE)
			b.prism(6, tile_r - 0.35, 0.04, MeshKit.at(Vector3(0, 0.005, 0)), Color(1.0, 1.0, 1.0).darkened(0.12))
			return b.build())
		for l in layers:
			var body := StaticBody3D.new()
			body.collision_layer = L_WORLD
			body.collision_mask = 0
			body.set_meta("kind", "hex")
			add_child(body)
			var xfs: Array = []
			var cols := PackedColorArray()
			for q in range(-ring, ring + 1):
				for r in range(-ring, ring + 1):
					if absi(q + r) > ring:
						continue
					var c := Vector3(1.5 * tile_r * q, -layer_gap * l, sqrt(3.0) * tile_r * (r + q * 0.5))
					var idx := centers.size()
					centers.append(c)
					tile_layer.append(l)
					tile_state.append(0)
					tile_t.append(0.0)
					axial[Vector3i(l, q, r)] = idx
					var cs := CollisionShape3D.new()
					cs.shape = shape
					cs.position = c
					body.add_child(cs)
					shapes.append(cs)
					xfs.append(Transform3D(Basis(), c))
					var base: Color = colors[l % colors.size()]
					cols.append(base.lightened(0.15) if (q + r * 2) % 3 == 0 else base)
			var mmi := MeshKit.scatter(mesh, xfs, cols)
			add_child(mmi)
			mms.append(mmi.multimesh)

	## Tile index under a world point (or -1).
	func tile_at(p: Vector3) -> int:
		var lp := p - global_position
		var l := int(round(-lp.y / layer_gap))
		if l < 0 or l >= layers or absf(lp.y + l * layer_gap) > 0.9:
			return -1
		var qf := lp.x / (1.5 * tile_r)
		var rf := lp.z / (sqrt(3.0) * tile_r) - qf * 0.5
		var sf := -qf - rf
		var q := roundf(qf)
		var r := roundf(rf)
		var s := roundf(sf)
		var dq := absf(q - qf)
		var dr := absf(r - rf)
		var ds := absf(s - sf)
		if dq > dr and dq > ds:
			q = -r - s
		elif dr > ds:
			r = -q - s
		var key := Vector3i(l, int(q), int(r))
		return int(axial.get(key, -1))

	## Host: someone is standing at p: start the wobble.
	func step_on(p: Vector3) -> void:
		var i := tile_at(p)
		if i >= 0 and tile_state[i] == 0:
			tile_state[i] = 1
			tile_t[i] = 0.0

	## Every machine: wobble / drop animation; on the host also the timers.
	func tick(dt: float, host: bool) -> void:
		for i in tile_state.size():
			var st := tile_state[i]
			if st == 0:
				continue
			tile_t[i] += dt
			if host and st == 1 and tile_t[i] >= fall_delay:
				_set_state(i, 2)
				st = 2
			_draw_tile(i)

	func _set_state(i: int, st: int) -> void:
		if tile_state[i] == st:
			return
		if st == 2:
			shapes[i].set_deferred("disabled", true)
			dropped += 1
		tile_state[i] = st
		tile_t[i] = 0.0

	func _draw_tile(i: int) -> void:
		var l := tile_layer[i]
		var mm := mms[l]
		var local_idx := i
		for k in l:
			local_idx -= mms[k].instance_count
		var c := centers[i]
		var t := tile_t[i]
		match tile_state[i]:
			1:
				var w := sin(t * 40.0) * 0.06 * minf(1.0, t * 3.0)
				mm.set_instance_transform(local_idx, Transform3D(Basis(Vector3(1, 0, 1).normalized(), w), c + Vector3(0, -t * 0.12, 0)))
			2:
				if t < 1.2:
					var sc := maxf(0.02, 1.0 - t * 0.8)
					mm.set_instance_transform(local_idx, Transform3D(Basis(Vector3.RIGHT, t * 1.5).scaled(Vector3.ONE * sc), c + Vector3(0, -t * t * 9.0 - 0.1, 0)))
				else:
					mm.set_instance_transform(local_idx, Transform3D(Basis().scaled(Vector3.ONE * 0.001), c + Vector3(0, -40, 0)))

	func bits() -> PackedByteArray:
		return tile_state

	## TV machine: mirror the host's tile states.
	func apply_bits(b: PackedByteArray) -> void:
		for i in mini(b.size(), tile_state.size()):
			var st := b[i]
			if st != tile_state[i] and st > tile_state[i]:
				_set_state(i, st)
				_draw_tile(i)

	## Solid tiles left on layer l.
	func solid_on(l: int) -> int:
		var n := 0
		for i in tile_state.size():
			if tile_layer[i] == l and tile_state[i] == 0:
				n += 1
		return n

	## A random solid tile centre (world) on layer l near `near` (for CPU runners), or Vector3.INF.
	func safe_tile(l: int, near: Vector3, rng: RandomNumberGenerator) -> Vector3:
		var best := Vector3.INF
		var best_score := INF
		for k in 14:
			var i := rng.randi() % tile_state.size()
			if tile_layer[i] != l or tile_state[i] != 0:
				continue
			var w := global_position + centers[i]
			var score := w.distance_to(near) + rng.randf() * 3.0
			# avoid tiles next to holes
			var holes := 0
			for j in tile_state.size():
				if tile_layer[j] == l and tile_state[j] != 0 and centers[j].distance_to(centers[i]) < tile_r * 2.0:
					holes += 1
			score += holes * 2.5
			if score < best_score and w.distance_to(near) > 1.0:
				best_score = score
				best = w
		return best


# --------------------------------------------------------------------------------------------------

class FoamBlob extends Node3D:
	## A foam-cannon shot: a deterministic arc (origin + velocity + gravity), the same on both machines.
	## It knocks runners it touches and splats where it lands.
	var origin := Vector3.ZERO
	var vel := Vector3.ZERO
	var t := 0.0
	var life := 3.2
	var radius := 0.85
	var splat_y := -INF
	var done := false

	func _ready() -> void:
		var b := MeshKit.Builder.new()
		for k in 7:
			var a := TAU * k / 7.0
			b.sphere(0.4 + 0.12 * sin(k * 2.3), MeshKit.at(Vector3(cos(a) * 0.32, sin(k * 1.7) * 0.25, sin(a) * 0.32)), Color(0.95, 0.98, 1.0) if k % 2 == 0 else Color(0.8, 0.95, 1.0), 8)
		b.sphere(0.5, MeshKit.at(Vector3.ZERO), Color.WHITE, 10)
		var mi := MeshKit.instance(ResCache.get_or_make("or_foam_" + VERSION, b.build))
		add_child(mi)
		global_position = origin

	func pos_at(tt: float) -> Vector3:
		return origin + vel * tt + Vector3.DOWN * 9.0 * tt * tt

	func step(dt: float) -> void:
		t += dt
		var p := pos_at(t)
		global_position = p
		rotation += Vector3(dt * 3.0, dt * 2.0, 0.0)
		scale = Vector3.ONE * (1.0 + 0.15 * sin(t * 18.0))
		if t > life or p.y < splat_y:
			done = true

	func hit(r: Node3D) -> Vector3:
		if done:
			return Vector3.ZERO
		var c := r.global_position + Vector3.UP * RUNNER_H * 0.5
		if c.distance_to(global_position) > radius + RUNNER_R + 0.2:
			return Vector3.ZERO
		var v := vel + Vector3.DOWN * 18.0 * t
		var flat := Vector3(v.x, 0.0, v.z)
		if flat.length() < 0.5:
			flat = Vector3(c.x - global_position.x, 0.0, c.z - global_position.z)
		return flat.normalized() * 8.5 + Vector3.UP * 5.0


# --------------------------------------------------------------------------------------------------

class Ball extends Node3D:
	## A big ball. On the host (and in local play) it is a RigidBody3D; on the TV machine a ghost that
	## follows snapshots. kind "beach" (knocks runners) or "team" (pushed into goals).
	var kind := "beach"
	var radius := 1.3
	var ball_id := 0
	var host := true
	var body: RigidBody3D
	var ghost: Node3D
	var vis: Node3D
	var vel := Vector3.ZERO  # estimated on the TV machine
	var _target := Vector3.ZERO
	var _has_target := false
	var _last := Vector3.ZERO
	var age := 0.0
	var team_color := Color.WHITE

	func setup(at: Vector3) -> void:
		var key := "or_ball_%s_%.2f_%s" % [kind, radius, VERSION]
		var mesh: ArrayMesh = ResCache.get_or_make(key, func() -> Resource:
			var b := MeshKit.Builder.new()
			var cols: Array[Color] = [RED, WHITE, BLUE, YELLOW, WHITE, MINT] if kind == "beach" else [Color(1.0, 0.95, 0.85), Color(0.95, 0.5, 0.3)]
			if kind == "beach":
				b.sphere(radius, MeshKit.at(Vector3.ZERO), WHITE, 18)
				for k in 3:
					var a := PI * k / 3.0
					b.torus(radius * 0.97, radius * 0.2, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, a, 0)), cols[k * 2], 24, 6)
				for e in [-1.0, 1.0]:
					var ey: float = e
					b.sphere(radius * 0.22, MeshKit.at(Vector3(0, ey * radius * 0.93, 0), Vector3(1, 0.4, 1)), YELLOW, 10)
			else:
				b.sphere(radius, MeshKit.at(Vector3.ZERO), cols[0], 18)
				for k in 5:
					var a2 := TAU * k / 5.0
					b.sphere(radius * 0.33, MeshKit.at(Vector3(cos(a2), 0.3 * (k % 2) - 0.15, sin(a2)).normalized() * radius * 0.88, Vector3(1, 1, 0.45)), cols[1], 10)
				b.sphere(radius * 0.33, MeshKit.at(Vector3(0, radius * 0.88, 0), Vector3(1, 0.45, 1)), cols[1], 10)
				b.sphere(radius * 0.33, MeshKit.at(Vector3(0, -radius * 0.88, 0), Vector3(1, 0.45, 1)), cols[1], 10)
			return b.build())
		if host:
			body = RigidBody3D.new()
			body.collision_layer = 8
			body.collision_mask = L_WORLD | 8
			body.mass = 2.5 if kind == "beach" else 4.0
			body.continuous_cd = true
			var pm := PhysicsMaterial.new()
			pm.bounce = 0.55 if kind == "beach" else 0.25
			pm.friction = 0.6
			body.physics_material_override = pm
			body.linear_damp = 0.15 if kind == "beach" else 0.5
			body.angular_damp = 0.4
			var cs := CollisionShape3D.new()
			var sp := SphereShape3D.new()
			sp.radius = radius
			cs.shape = sp
			body.add_child(cs)
			add_child(body)
			body.global_position = at
			vis = MeshKit.instance(mesh)
			body.add_child(vis)
		else:
			ghost = Node3D.new()
			add_child(ghost)
			ghost.global_position = at
			vis = MeshKit.instance(mesh)
			ghost.add_child(vis)
			_last = at
		_target = at

	func center() -> Vector3:
		if body != null:
			return body.global_position
		if ghost != null:
			return ghost.global_position
		return global_position

	func velocity() -> Vector3:
		if body != null:
			return body.linear_velocity
		return vel

	func set_net(p: Vector3) -> void:
		_target = p
		if not _has_target and ghost != null:
			ghost.global_position = p
		_has_target = true

	func step(dt: float) -> void:
		age += dt
		if ghost != null:
			var p := ghost.global_position
			var to := _target + vel * 0.05
			if p.distance_to(_target) > 6.0:
				p = _target
			else:
				p = p.lerp(to, 1.0 - exp(-14.0 * dt))
			var v := (p - _last) / maxf(dt, 0.001)
			vel = vel.lerp(v, 1.0 - exp(-10.0 * dt))
			_last = p
			ghost.global_position = p
			# roll the ghost visually
			var flat := Vector3(vel.x, 0.0, vel.z)
			if flat.length() > 0.05:
				var ax := Vector3.UP.cross(flat.normalized())
				vis.rotate(ax.normalized(), flat.length() * dt / radius)

	## Knock for a runner hit by a fast beach ball.
	func hit(r: Node3D) -> Vector3:
		if kind != "beach":
			return Vector3.ZERO
		var c := r.global_position + Vector3.UP * RUNNER_H * 0.5
		var bc := center()
		if c.distance_to(bc) > radius + RUNNER_R + 0.15:
			return Vector3.ZERO
		var v := velocity()
		if v.length() < 2.0:
			return Vector3.ZERO
		var away := Vector3(c.x - bc.x, 0.0, c.z - bc.z)
		if away.length() < 0.05:
			away = Vector3(v.x, 0.0, v.z)
		return away.normalized() * 7.0 + Vector3(v.x, 0.0, v.z) * 0.5 + Vector3.UP * 5.5


# --------------------------------------------------------------------------------------------------

class Pad extends Node3D:
	## A Game Master helper: "bounce" (springs you high), "boost" (a speed strip), "bridge" (a plank over
	## a gap). Created on both machines from the replicated pad list.
	var kind := "bounce"
	var pad_id := 0
	var length := 6.0
	var life := 0.0
	var age := 0.0
	var vis: Node3D
	var body: StaticBody3D

	func setup() -> void:
		vis = Node3D.new()
		add_child(vis)
		match kind:
			"bounce":
				body = Obs.static_box(self, Vector3(2.4, 0.3, 2.4), Transform3D(Basis(), Vector3(0, 0.15, 0)), {"kind": "bounce", "pad": self})
				var m: ArrayMesh = ResCache.get_or_make("or_pad_bounce_" + VERSION, func() -> Resource:
					var b := MeshKit.Builder.new()
					b.cylinder(1.25, 1.35, 0.25, MeshKit.at(Vector3(0, 0.12, 0)), Color(0.3, 0.3, 0.4), 16)
					b.cylinder(1.1, 1.1, 0.12, MeshKit.at(Vector3(0, 0.3, 0)), MINT, 16, true)
					for k in 3:
						b.torus(0.35 + k * 0.28, 0.04, MeshKit.at(Vector3(0, 0.37, 0)), WHITE, 16, 4)
					return b.build())
				vis.add_child(MeshKit.instance(m))
			"boost":
				body = Obs.static_box(self, Vector3(2.6, 0.06, 5.0), Transform3D(Basis(), Vector3(0, 0.03, 0)), {"kind": "boost", "pad": self})
				var m2: ArrayMesh = ResCache.get_or_make("or_pad_boost_" + VERSION, func() -> Resource:
					var b := MeshKit.Builder.new()
					b.box(Vector3(2.6, 0.06, 5.0), MeshKit.at(Vector3(0, 0.03, 0)), Color(0.2, 0.25, 0.4))
					for k in 3:
						var z := 1.4 - k * 1.4
						var pts := PackedVector2Array([Vector2(-0.9, -0.45), Vector2(0.0, 0.55), Vector2(0.9, -0.45)])
						b.polygon(pts, 0.04, MeshKit.at(Vector3(0, 0.07, z), Vector3.ONE, Vector3(-PI * 0.5, 0, 0)), Color(0.4, 0.95, 1.0), true)
					return b.build())
				vis.add_child(MeshKit.instance(m2))
			"bridge":
				body = Obs.static_box(self, Vector3(2.6, 0.35, length), Transform3D(Basis(), Vector3(0, -0.17, 0)), {"kind": "bridge", "pad": self})
				var key := "or_pad_bridge_%.1f_%s" % [length, VERSION]
				var m3: ArrayMesh = ResCache.get_or_make(key, func() -> Resource:
					var b := MeshKit.Builder.new()
					var n := int(length / 0.6)
					for k in n:
						var z := -length * 0.5 + (k + 0.5) * length / n
						b.box(Vector3(2.6, 0.18, length / n - 0.06), MeshKit.at(Vector3(0, -0.1, z)), Color(0.85, 0.6, 0.35) if k % 2 == 0 else Color(0.95, 0.72, 0.45))
					for side in [-1.0, 1.0]:
						var sd: float = side
						b.box(Vector3(0.1, 0.1, length), MeshKit.at(Vector3(sd * 1.25, 0.45, 0)), YELLOW, true)
						for k2 in int(length / 1.5) + 1:
							b.cylinder(0.05, 0.05, 0.55, MeshKit.at(Vector3(sd * 1.25, 0.2, -length * 0.5 + k2 * 1.5)), WHITE, 6)
					return b.build())
				vis.add_child(MeshKit.instance(m3))
		vis.scale = Vector3.ONE * 0.05
		var tw := create_tween()
		tw.tween_property(vis, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func _process(delta: float) -> void:
		age += delta
		if kind == "bounce" and vis != null:
			vis.position.y = absf(sin(age * 4.0)) * 0.05
		if life > 0.0 and age > life - 1.5 and vis != null:
			vis.visible = fmod(age * 8.0, 1.0) < 0.6  # blink before it goes

