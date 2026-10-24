extends Node3D
## OBSTACLE RUSH: the GIANT (the VR player, host) and the bouncy balls.
## The VR player is a giant (world scale S) standing at the side of the toy course on the table:
##   - RIGHT TRIGGER on a ball in the bucket by your right hip: pick it up; throw it at the runners.
##     A hit is a comical bonk (they tumble and carry on). Balls come back to the bucket by themselves.
##   - Either hand can TOUCH everything: boop a runner (a little hop), hold the spinner still or swipe it
##     round, poke a bounce pad, lift a door, flick the finish flag, bat a flying ball.
##   - Left stick walks along the table, right stick snap-turns.
## Without a VR giant (local split screen, or a host without a headset) a friendly cloud drops a ball
## on the runners now and then instead, so the courses stay lively.
## The host simulates the balls (RigidBody3D); the TV machine draws them from the snapshot and draws
## the giant's head and gloves (giant-sized) from VrRig.pack_pose().

const VrRig := preload("res://core/vr_rig.gd")
const MeshKit := preload("res://core/mesh_kit.gd")

const S := 10.0  ## XR world scale: 10 units = 1 real metre (a runner is 11 cm)
const TABLE_Y := -3.5
const BALLS := 5
const BALL_R := 0.5
const GRAB_R := 1.4
const TOUCH_R := 0.9
const BALL_COLORS: Array[Color] = [Color(1.0, 0.4, 0.45), Color(0.4, 0.7, 1.0), Color(1.0, 0.85, 0.3),
	Color(0.5, 0.9, 0.5), Color(0.85, 0.55, 1.0)]

var main: Node
var rig: VrRig
var host := true
var balls: Array[RigidBody3D] = []  ## host
var ball_vis: Array[MeshInstance3D] = []  ## TV machine
var home: Array[bool] = []
var ball_t: Array[float] = []
var hit_cool := {}  ## "ball:rid" -> seconds
var held := -1
var bucket: Node3D
var bucket_x := 0.0
var drop_t := 4.0
var touch_on := [{}, {}]  ## per hand: kind -> true while touching (react once per touch)
var throws := 0
var last_throw_t := 0.0
var avatar_head: Node3D
var avatar_hands: Array[Node3D] = []
var _pose_target: Array[Transform3D] = []
var rng := RandomNumberGenerator.new()


func setup(m: Node, r: VrRig, is_host: bool) -> void:
	main = m
	rig = r
	host = is_host
	rng.seed = 7
	if rig != null:
		rig.set_scale_of_world(S)
		rig.move_speed = 0.5 * S
		rig.bounds = Rect2(-14.0, 5.0, 28.0, 5.0)
		rig.camera.far = 3000.0
		rig.camera.near = 0.05
		rig.place(feet(), 0.0)
		_build_bucket()
	var mesh := _ball_mesh()
	for i in BALLS:
		home.append(true)
		ball_t.append(0.0)
		if host:
			var b := RigidBody3D.new()
			b.collision_layer = 4
			b.collision_mask = 1 | 4
			b.gravity_scale = 2.6
			b.mass = 0.3
			b.continuous_cd = true
			var pm := PhysicsMaterial.new()
			pm.bounce = 0.55
			pm.friction = 0.6
			b.physics_material_override = pm
			b.linear_damp = 0.15
			b.angular_damp = 0.5
			var cs := CollisionShape3D.new()
			var sp := SphereShape3D.new()
			sp.radius = BALL_R
			cs.shape = sp
			b.add_child(cs)
			var mi := MeshKit.instance(mesh)
			mi.material_override = _ball_mat(i)
			b.add_child(mi)
			add_child(b)
			b.freeze = true
			b.global_position = _home_spot(i)
			balls.append(b)
		else:
			var v := MeshKit.instance(mesh)
			v.material_override = _ball_mat(i)
			v.visible = false
			add_child(v)
			ball_vis.append(v)


## Where the giant's feet go: the near side of the table, facing the course (-Z).
static func feet() -> Vector3:
	return Vector3(0.0, TABLE_Y - 0.8 * S, 7.6)


func _ball_mesh() -> ArrayMesh:
	var b := MeshKit.Builder.new()
	b.sphere(BALL_R, Transform3D.IDENTITY, Color.WHITE, 14)
	for k in 3:  # beach-ball stripes
		var a := TAU * k / 3.0
		b.ellipsoid(Vector3(BALL_R * 1.01, BALL_R * 1.01, BALL_R * 0.32), MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(0, a, 0)), Color(1.0, 0.95, 0.85), 12)
	return b.build()


func _ball_mat(i: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = BALL_COLORS[i % BALL_COLORS.size()].lightened(0.15)
	m.roughness = 0.3
	return m


func _build_bucket() -> void:
	bucket = Node3D.new()
	add_child(bucket)
	var b := MeshKit.Builder.new()
	b.cylinder(1.5, 1.2, 1.3, MeshKit.at(Vector3(0, 0.65, 0)), Color(0.35, 0.65, 1.0), 18, false, false)
	b.cylinder(1.2, 1.2, 0.1, MeshKit.at(Vector3(0, 0.05, 0)), Color(0.3, 0.55, 0.9), 18)
	b.torus(1.5, 0.12, MeshKit.at(Vector3(0, 1.3, 0)), Color(1.0, 0.95, 0.85), 20, 6)
	bucket.add_child(MeshKit.instance(b.build()))
	bucket_x = 3.4
	bucket.position = Vector3(bucket_x, TABLE_Y, 4.6)


func _home_spot(i: int) -> Vector3:
	if bucket == null:
		return Vector3(0.0, -60.0 - i * 2.0, 0.0)  # no giant: parked out of sight
	var a := TAU * i / 4.0
	var p := bucket.position + Vector3(0.0, 1.0, 0.0)
	if i == 0:
		return p + Vector3(0.0, 0.5, 0.0)
	return p + Vector3(cos(a) * 0.75, 0.1, sin(a) * 0.75)


# --- Host -----------------------------------------------------------------------------------------

func step(delta: float) -> void:
	if not host:
		return
	if rig != null:
		_bucket_follow(delta)
		_hands(delta)
	elif String(main.net.state_get("phase", "play")) == "play":
		drop_t -= delta
		if drop_t <= 0.0:
			drop_t = rng.randf_range(4.0, 7.0)
			_cloud_drop()
	for k in hit_cool.keys():
		hit_cool[k] = float(hit_cool[k]) - delta
		if float(hit_cool[k]) <= 0.0:
			hit_cool.erase(k)
	for i in BALLS:
		var b := balls[i]
		if i == held:
			continue
		if home[i]:
			b.global_position = b.global_position.lerp(_home_spot(i), 1.0 - exp(-10.0 * delta))
			continue
		ball_t[i] += delta
		if b.global_position.y < TABLE_Y - 3.0 or ball_t[i] > 7.0 or (ball_t[i] > 2.0 and b.linear_velocity.length() < 0.3):
			_send_home(i)
			continue
		_ball_hits(i, b)


func _bucket_follow(delta: float) -> void:
	var hx := rig.head_position().x
	bucket_x = lerpf(bucket_x, clampf(hx + 3.4, -13.0, 15.0), 1.0 - exp(-2.0 * delta))
	bucket.position.x = bucket_x


func _send_home(i: int) -> void:
	var b := balls[i]
	b.freeze = true
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	home[i] = true
	if bucket != null:
		b.global_position = _home_spot(i) + Vector3(0.0, 2.0, 0.0)
		main.sound_at("pop", _home_spot(i), -10.0, 1.4)
	else:
		b.global_position = _home_spot(i)


## Throw (or drop) ball i from p with velocity v.
func launch(i: int, p: Vector3, v: Vector3) -> void:
	var b := balls[i]
	home[i] = false
	ball_t[i] = 0.0
	b.global_position = p
	b.freeze = false
	b.linear_velocity = v
	b.angular_velocity = Vector3(rng.randf_range(-6, 6), rng.randf_range(-6, 6), rng.randf_range(-6, 6))


func _free_ball() -> int:
	for i in BALLS:
		if home[i] and i != held:
			return i
	return -1


## No giant: a ball drops from the sky just ahead of a runner.
func _cloud_drop() -> void:
	var rs: Array = main.runners_racing()
	if rs.is_empty():
		return
	var i := _free_ball()
	if i < 0:
		return
	var r: Node3D = rs[rng.randi() % rs.size()]
	var p := r.position + Vector3(rng.randf_range(2.0, 4.0), 9.0, rng.randf_range(-1.0, 1.0))
	launch(i, p, Vector3(-2.5, -2.0, 0.0))
	main.sound_at("whoosh", p, -8.0, 0.8)


func _ball_hits(i: int, b: RigidBody3D) -> void:
	var v := b.linear_velocity
	var p := b.global_position
	# The practice target on the first course.
	var t: Vector3 = main.course.target_pos
	if t != Vector3.INF and main.course.target != null and Vector2(p.x - t.x, p.z - t.z).length() < 1.6 and p.y < t.y + 1.2:
		main.target_hit(p)
	if v.length() < 2.5:
		return
	for r in main.runners.values():
		var rn: Node3D = r
		if bool(rn.get("done")):
			continue
		var key := "%d:%d" % [i, int(rn.get("rid"))]
		if hit_cool.has(key):
			continue
		if p.distance_to(rn.position + Vector3(0.0, 0.55, 0.0)) < BALL_R + 0.5:
			hit_cool[key] = 1.0
			main.bonk_runner(int(rn.get("rid")), v, i)
			b.linear_velocity = Vector3(-v.x * 0.3, absf(v.y) * 0.4 + 3.0, -v.z * 0.3)


## The VR hands: grab / throw with the right trigger, touch everything with both.
func _hands(_delta: float) -> void:
	var hr := rig.hand_point(VrRig.RIGHT)
	if held >= 0:
		balls[held].global_position = hr
		if not rig.trigger_down():
			var v := rig.hand_velocity(VrRig.RIGHT) * 0.85
			v = v.limit_length(32.0)
			launch(held, hr, v)
			held = -1
			throws += 1
			last_throw_t = 0.0
			main.on_throw()
			main.sound_at("whoosh", hr, -6.0, 1.2)
			rig.pulse(VrRig.RIGHT, 0.5, 0.05)
	elif rig.trigger_pressed():
		var best := -1
		var bd := GRAB_R
		for i in BALLS:
			var d := balls[i].global_position.distance_to(hr)
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			held = best
			home[best] = false
			balls[best].freeze = true
			main.sound_at("pop", hr, -8.0, 1.0)
			rig.pulse(VrRig.RIGHT, 0.4, 0.04)
	last_throw_t += _delta
	for h in 2:
		var p := rig.hand_point(h)
		var vel := rig.hand_velocity(h)
		var now := {}
		# Bat a flying ball.
		for i in BALLS:
			if i != held and not home[i] and ball_t[i] > 0.4 and balls[i].global_position.distance_to(p) < BALL_R + 0.5:
				now["ball%d" % i] = true
				if not touch_on[h].has("ball%d" % i) and vel.length() > 1.0:
					balls[i].linear_velocity += vel * 0.8
					main.sound_at("ball_hit", p, -6.0, 1.3)
		# Boop a runner.
		for r in main.runners.values():
			var rn: Node3D = r
			if p.distance_to(rn.position + Vector3(0.0, 0.6, 0.0)) < TOUCH_R:
				var k := "r%d" % int(rn.get("rid"))
				now[k] = true
				if not touch_on[h].has(k):
					main.boop_runner(int(rn.get("rid")))
					rig.pulse(h, 0.3, 0.04)
		# The course: spinner, pads, doors, flag.
		var what: String = main.course.touch(p, vel)
		if what != "":
			now[what] = true
			if not touch_on[h].has(what) and what != "hold":
				main.on_course_touch(what, p)
				rig.pulse(h, 0.35, 0.05)
		if main.has_method("touch_extra"):
			main.touch_extra(h, p, now, touch_on[h])
		touch_on[h] = now


# --- Snapshots ------------------------------------------------------------------------------------

func pack() -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in BALLS:
		out.append(balls[i].global_position if (not home[i] or bucket != null) else Vector3(0, -99, 0))
	return out


func unpack(a: PackedVector3Array, delta: float) -> void:
	for i in mini(a.size(), ball_vis.size()):
		var v := ball_vis[i]
		var p := a[i]
		if p.y < -50.0:
			v.visible = false
			continue
		if not v.visible or v.position.distance_to(p) > 6.0:
			v.position = p
		v.visible = true
		v.position = v.position.lerp(p, 1.0 - exp(-20.0 * delta))
		v.rotate_x(delta * 3.0)


## TV machine: the giant's head and gloves, giant-sized, from VrRig.pack_pose().
func make_avatar() -> void:
	var mat := VrRig.vertex_color_material()
	avatar_head = Node3D.new()
	add_child(avatar_head)
	var face := MeshInstance3D.new()
	face.mesh = VrRig.VrRigStatics.head_mesh(Color(0.3, 0.7, 1.0))
	face.material_override = mat
	face.scale = Vector3.ONE * S
	face.layers = VrRig.AVATAR_LAYER
	avatar_head.add_child(face)
	for i in 2:
		var n := Node3D.new()
		add_child(n)
		var g := MeshInstance3D.new()
		g.mesh = VrRig.glove_mesh(i == 0, Color(1.0, 0.86, 0.6), Color.WHITE)
		g.material_override = mat
		g.scale = Vector3.ONE * S
		g.layers = VrRig.AVATAR_LAYER
		n.add_child(g)
		avatar_hands.append(n)
	avatar_head.visible = false
	for n in avatar_hands:
		n.visible = false


func apply_pose(p: PackedFloat32Array, delta: float) -> void:
	if avatar_head == null or p.size() < 21:
		return
	var nodes: Array[Node3D] = [avatar_head, avatar_hands[0], avatar_hands[1]]
	for i in 3:
		var o := i * 7
		var t := Transform3D(Basis(Quaternion(p[o + 3], p[o + 4], p[o + 5], p[o + 6]).normalized()), Vector3(p[o], p[o + 1], p[o + 2]))
		var n := nodes[i]
		if not n.visible:
			n.global_transform = t
			n.visible = true
		else:
			n.global_transform = n.global_transform.interpolate_with(t, 1.0 - exp(-15.0 * delta))
