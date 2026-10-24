extends Node3D
## SIMPLE_MODE toys in the VR builder's reach (Simon's rule: everything you can reach does something).
## Touch them with either hand:
##   - a little toy cloud by your LEFT hip (mirroring the tray on the right) holds five toy blocks:
##     poke them over, stack them, or grab one with the right trigger and throw it (they land on the
##     islands, and pop back onto the cloud if they fall into the sky);
##   - three balloons tied to the toy cloud pop (and grow back);
##   - a bird sits on the toy cloud and another on the flag: they flap away and come back;
##   - fluffy clouds float beside you and overhead: they puff and bounce away;
##   - the flag waves wildly (it also waves when a runner gets there).
## Runners get a gentle boop from the giant's hand (main._check_boops).
## Cheap for the Frame: the clouds are one MultiMesh, the rest is a handful of small meshes, and five
## physics boxes on the host only. The host simulates; touches go to the TV as "prop" events and the toy
## blocks' poses go in the snapshot.

const Art := preload("res://games/block_builders/art.gd")

const TOUCH := 0.9               # units (1 unit = 12.5 cm in VR)
const SHELF := Vector3(-2.4, 1.6, 4.3)   # the toy cloud: left of the builder's default spot, at hip height
const SHELF_SIZE := Vector3(3.0, 0.3, 1.5)
const TOYS := 5
const TOY := 0.62
const CLOUD_SPOTS: Array[Vector3] = [Vector3(-4.6, 3.6, 5.6), Vector3(4.8, 3.4, 5.4), Vector3(0.3, 6.1, 3.4)]
const TOY_COLORS: Array[Color] = [Color(1.0, 0.4, 0.35), Color(1.0, 0.85, 0.25), Color(0.4, 0.85, 0.45),
	Color(0.35, 0.65, 1.0), Color(0.85, 0.5, 1.0)]

var main
var t := 0.0
var shelf: MeshInstance3D
var cloud_mm: MultiMesh
var cloud_off: Array[Vector3] = []    # drift after a puff (springs back)
var cloud_vel: Array[Vector3] = []
var cloud_puff: Array[float] = []
var balloons: Array[MeshInstance3D] = []
var strings: Array[MeshInstance3D] = []
var balloon_gone: Array[float] = []   # seconds until it grows back (0 = there)
var birds: Array[Node3D] = []
var bird_fly: Array[float] = []       # 0 perched, >0 flying (seconds left)
var toys: Array[RigidBody3D] = []
var toy_target: Array[Transform3D] = []
var held := -1
var ground_body: StaticBody3D
var hand_last := [Vector3.ZERO, Vector3.ZERO]
var hand_vel := [Vector3.ZERO, Vector3.ZERO]
var touching := {}                    # prop key -> true while a hand is on it (one reaction per touch)
var touched := {}                     # prop kind -> true once ever (bots)
var flag_kick := 0.0


func _ready() -> void:
	_build_shelf()
	_build_clouds()
	_build_balloons()
	_build_birds()
	_build_toys()


func _is_host() -> bool:
	return main.net == null or main.net.mode != "client"


# --- Building ----------------------------------------------------------------------------

func _build_shelf() -> void:
	# A fluffy toy cloud: one flattened sphere (cheap) with a flat top the toys sit on.
	shelf = MeshInstance3D.new()
	shelf.mesh = Art.sphere(1.0, 14)
	shelf.material_override = Art.mat(Color(1.0, 1.0, 1.0), 0.25, 1.0)
	shelf.scale = Vector3(SHELF_SIZE.x * 0.6, 0.35, SHELF_SIZE.z * 0.65)
	shelf.position = SHELF + Vector3(0, -0.2, 0)
	shelf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shelf)


func _build_clouds() -> void:
	var puff := Art.sphere(1.0, 12)
	puff.material = Art.mat(Color(1.0, 1.0, 1.0), 0.2, 1.0)
	cloud_mm = MultiMesh.new()
	cloud_mm.transform_format = MultiMesh.TRANSFORM_3D
	cloud_mm.mesh = puff
	cloud_mm.instance_count = CLOUD_SPOTS.size() * 3
	for i in CLOUD_SPOTS.size():
		cloud_off.append(Vector3.ZERO)
		cloud_vel.append(Vector3.ZERO)
		cloud_puff.append(0.0)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = cloud_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_update_clouds(0.0)


func _build_balloons() -> void:
	var cols: Array[Color] = [Color(1.0, 0.3, 0.4), Color(1.0, 0.85, 0.2), Color(0.35, 0.7, 1.0)]
	var smesh := Art.cyl(0.02, 0.02, 1.0, 4)
	var smat := Art.mat(Color(0.95, 0.95, 0.95))
	for i in 3:
		var b := MeshInstance3D.new()
		b.mesh = Art.sphere(0.32, 12)
		b.material_override = Art.mat(cols[i], 0.3, 0.25)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(b)
		balloons.append(b)
		balloon_gone.append(0.0)
		var s := MeshInstance3D.new()
		s.mesh = smesh
		s.material_override = smat
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
		strings.append(s)


func _build_birds() -> void:
	for i in 2:
		var b := Node3D.new()
		add_child(b)
		var m := MeshInstance3D.new()
		m.mesh = Art.bird_mesh()
		m.scale = Vector3.ONE * 0.9
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.name = "Mesh"
		b.add_child(m)
		birds.append(b)
		bird_fly.append(0.0)


func _build_toys() -> void:
	var box := Art.box(Vector3.ONE * TOY)
	for i in TOYS:
		var rb := RigidBody3D.new()
		rb.mass = 0.3
		rb.gravity_scale = 6.0  # the world is a tabletop at VR scale: snappy falls
		rb.angular_damp = 1.0
		rb.linear_damp = 0.3
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3.ONE * TOY
		cs.shape = sh
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = Art.mat(TOY_COLORS[i], 0.15, 0.6)
		rb.add_child(mi)
		add_child(rb)
		rb.global_transform = _toy_home(i)
		if not _is_host():
			rb.freeze = true
		toys.append(rb)
		toy_target.append(rb.global_transform)
	if _is_host():
		ground_body = StaticBody3D.new()
		add_child(ground_body)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = SHELF_SIZE
		cs.shape = sh
		cs.position = SHELF + Vector3(0, -SHELF_SIZE.y * 0.5, 0)
		ground_body.add_child(cs)


func _toy_home(i: int) -> Transform3D:
	# Two little stacks and one on its own, ready to be knocked over.
	var spots: Array[Vector3] = [Vector3(-0.9, 0, 0.1), Vector3(-0.9, 1, 0.1), Vector3(0.1, 0, -0.1), Vector3(0.1, 1, -0.1),
		Vector3(1.0, 0, 0.25)]
	var s: Vector3 = spots[i % spots.size()]
	return Transform3D(Basis(Vector3.UP, 0.15 * i), SHELF + Vector3(s.x, TOY * 0.5 + s.y * TOY + 0.01, s.z))


## A new level: toys back on the cloud, islands get collision for thrown toys.
func on_level() -> void:
	for i in toys.size():
		_toy_reset(i, false)
	if ground_body == null:
		return
	for c in ground_body.get_children():
		if c.has_meta("island"):
			c.queue_free()
	for g in main.course.grounds:
		var cs := CollisionShape3D.new()
		cs.set_meta("island", true)
		var sh := BoxShape3D.new()
		var x0: float = g[0]
		var x1: float = g[1]
		var z0: float = g[2]
		var z1: float = g[3]
		var top: float = g[4]
		var bottom: float = g[5]
		sh.size = Vector3(x1 - x0, top - bottom, z1 - z0)
		cs.shape = sh
		cs.position = Vector3((x0 + x1) * 0.5, (top + bottom) * 0.5, (z0 + z1) * 0.5)
		ground_body.add_child(cs)


func _toy_reset(i: int, fx: bool) -> void:
	var rb := toys[i]
	if fx:
		main.burst(rb.global_position, TOY_COLORS[i], 8, 0.08)
	if held == i:
		held = -1
	rb.global_transform = _toy_home(i)
	if _is_host():
		rb.freeze = false
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
	toy_target[i] = rb.global_transform
	if fx:
		main.burst(rb.global_position, Color(1, 1, 1), 8, 0.07)
		main.sound("poof", -8.0, 1.3)


# --- Per frame -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	t += delta
	_update_clouds(delta)
	_update_balloons(delta)
	_update_birds(delta)
	if flag_kick > 0.0:
		flag_kick = maxf(0.0, flag_kick - delta)
		var fc = main.course.flag_cloth
		if fc != null and is_instance_valid(fc):
			fc.rotation.y += sin(t * 22.0) * flag_kick * 0.5
	if not _is_host():
		for i in toys.size():
			toys[i].global_transform = toys[i].global_transform.interpolate_with(toy_target[i], 1.0 - exp(-15.0 * delta))
		return
	for i in toys.size():
		if i != held and toys[i].global_position.y < -14.0:
			_toy_reset(i, true)
	_touches(delta)


## Where the hands are (VR builder only), and how fast they move.
func _hands(delta: float) -> Array:
	var b = main.builder
	if b == null or not b.vr:
		return []
	var out: Array = [b.grab_point]
	if b.hand_l != null:
		out.append(b.hand_l.global_transform * (b.GRAB_LOCAL * b.S))
	for k in out.size():
		var p: Vector3 = out[k]
		hand_vel[k] = (p - hand_last[k]) / maxf(delta, 0.001)
		hand_last[k] = p
	return out


func _touches(delta: float) -> void:
	var hands := _hands(delta)
	if hands.is_empty():
		return
	var now_touch := {}
	for k in hands.size():
		var hp: Vector3 = hands[k]
		for i in CLOUD_SPOTS.size():
			if hp.distance_to(_cloud_pos(i)) < TOUCH * 1.4:
				now_touch["cloud%d" % i] = ["cloud", i]
		for i in balloons.size():
			if balloon_gone[i] <= 0.0 and hp.distance_to(balloons[i].global_position) < TOUCH * 0.8:
				now_touch["balloon%d" % i] = ["balloon", i]
		for i in birds.size():
			if bird_fly[i] <= 0.0 and hp.distance_to(birds[i].global_position) < TOUCH * 1.3:
				now_touch["bird%d" % i] = ["bird", i]
		var fp: Vector3 = main.course.flag_pos + Vector3(0.4, 1.6, 0.0)
		if hp.distance_to(fp) < TOUCH * 1.3:
			now_touch["flag"] = ["flag", 0]
		# Toy blocks: a moving hand knocks them about.
		var hv: Vector3 = hand_vel[k]
		for i in toys.size():
			if i == held:
				continue
			var rb := toys[i]
			if hp.distance_to(rb.global_position) < TOY * 0.9 and hv.length() > 1.0:
				rb.apply_central_impulse(hv.limit_length(12.0) * 0.04)
				if not touching.has("toy%d" % i):
					main.sound("clack", -10.0, randf_range(0.9, 1.3))
					touched["toy"] = true
				now_touch["toy%d" % i] = ["toy", i]
	for key in now_touch:
		if not touching.has(key):
			var v: Array = now_touch[key]
			if v[0] != "toy":
				react(str(v[0]), int(v[1]), true)
	touching = now_touch


## A touch reaction. Host: also the sound and the TV event. TV: just the visual.
func react(kind: String, i: int, host: bool) -> void:
	touched[kind] = true
	match kind:
		"cloud":
			if i < 0 or i >= cloud_puff.size():
				return
			cloud_puff[i] = 1.0
			var away := (_cloud_pos(i) - _hand_hint()).normalized()
			cloud_vel[i] += away * 3.0 + Vector3.UP * 1.0
			if host:
				main.sound("poof", -4.0, randf_range(0.8, 1.1))
				main.burst(_cloud_pos(i), Color(1, 1, 1), 10, 0.12)
		"balloon":
			if i < 0 or i >= balloons.size():
				return
			if host:
				main.sound("pop", -2.0, randf_range(0.9, 1.2))
				main.burst(balloons[i].global_position, (balloons[i].material_override as StandardMaterial3D).albedo_color, 14, 0.09)
			balloon_gone[i] = 4.0
		"bird":
			if i < 0 or i >= birds.size():
				return
			bird_fly[i] = 3.2
			if host:
				main.sound("tweet", -6.0, randf_range(0.9, 1.2))
		"flag":
			flag_kick = 1.5
			if host:
				main.sound("flag", -6.0, randf_range(1.0, 1.2))
				main.burst(main.course.flag_pos + Vector3(0.4, 1.9, 0.0), Color(1.0, 0.4, 0.4), 10, 0.08)
				if bird_fly[1] <= 0.0:
					react("bird", 1, true)
	if host and main.net != null:
		main.net.event("prop", [kind, i])


## The flag flaps (a runner reached it, a level was cleared).
func wave_flag() -> void:
	flag_kick = 1.5
	if bird_fly.size() > 1 and bird_fly[1] <= 0.0:
		bird_fly[1] = 3.2


func _hand_hint() -> Vector3:
	return hand_last[0]


func _cloud_pos(i: int) -> Vector3:
	return CLOUD_SPOTS[i] + cloud_off[i] + Vector3(0, sin(t * 0.8 + i * 2.0) * 0.12, 0)


func _update_clouds(delta: float) -> void:
	for i in CLOUD_SPOTS.size():
		# Spring back home after a puff.
		cloud_vel[i] += -cloud_off[i] * 3.0 * delta
		cloud_vel[i] *= exp(-1.8 * delta)
		cloud_off[i] += cloud_vel[i] * delta
		cloud_puff[i] = maxf(0.0, cloud_puff[i] - delta * 1.5)
		var p := _cloud_pos(i)
		var s := 1.0 + 0.35 * sin(cloud_puff[i] * PI)
		for j in 3:
			var off := Vector3((j - 1) * 0.55, (0.15 if j == 1 else 0.0), 0.0) * s
			var r := (0.55 if j == 1 else 0.42) * s
			cloud_mm.set_instance_transform(i * 3 + j, Transform3D(Basis().scaled(Vector3(r, r * 0.8, r)), p + off))


func _update_balloons(delta: float) -> void:
	for i in balloons.size():
		var anchor := SHELF + Vector3(-1.2 + i * 0.35, 0.0, -0.55)
		var bp := anchor + Vector3(-0.3 + i * 0.3 + sin(t * 1.1 + i) * 0.08, 2.0 + i * 0.3, sin(t * 0.9 + i * 2.0) * 0.08)
		var b := balloons[i]
		if balloon_gone[i] > 0.0:
			balloon_gone[i] = maxf(0.0, balloon_gone[i] - delta)
			var grow := clampf(1.0 - balloon_gone[i] / 1.0, 0.0, 1.0)  # grows back in the last second
			b.scale = Vector3(grow, grow * 1.15, grow)
			b.visible = grow > 0.01
		else:
			b.scale = Vector3(1.0, 1.15, 1.0)
			b.visible = true
		b.global_position = bp
		var s := strings[i]
		var d := bp - Vector3(0, 0.36, 0) - anchor
		s.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, d.normalized())).scaled(Vector3(1, d.length(), 1)), anchor + d * 0.5)
		s.visible = b.visible


func _bird_home(i: int) -> Transform3D:
	if i == 0:
		return Transform3D(Basis(Vector3.UP, 0.6), SHELF + Vector3(1.25, 0.12, 0.45))
	return Transform3D(Basis(Vector3.UP, -0.4), main.course.flag_pos + Vector3(0.0, 2.42, 0.0))


func _update_birds(delta: float) -> void:
	for i in birds.size():
		var b := birds[i]
		var home := _bird_home(i)
		var m := b.get_node("Mesh") as Node3D
		if bird_fly[i] > 0.0:
			bird_fly[i] = maxf(0.0, bird_fly[i] - delta)
			var k := 1.0 - bird_fly[i] / 3.2   # 0..1 over the flight
			var a := k * TAU
			var loop := Vector3(sin(a) * 1.6, sin(k * PI) * 2.2, (1.0 - cos(a)) * -0.9)
			var pos := home.origin + loop
			var fwd := Vector3(cos(a) * 1.6, cos(k * PI) * 2.2 * PI / TAU, sin(a) * -0.9)
			if fwd.length() > 0.01:
				b.global_transform = Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), pos)
			m.scale = Vector3(0.9 * (1.0 + sin(t * 26.0) * 0.4), 0.9, 0.9)
		else:
			b.global_transform = home
			# A little hop now and then while perched.
			var hop := maxf(0.0, sin(t * 2.3 + i * 3.0)) ** 8
			b.global_position.y += hop * 0.12
			m.scale = Vector3.ONE * 0.9


# --- Grabbing a toy block (VR, right trigger) ------------------------------------------------

## Called by builder.gd with the right hand. Returns true while it's busy with a toy (so the trigger
## doesn't also pick up blocks or press "continue").
func vr_hand(grab: Vector3, trig: bool, pressed: bool, delta: float) -> bool:
	if not _is_host():
		return false
	if held >= 0:
		var rb := toys[held]
		if trig:
			rb.global_transform = Transform3D(rb.global_basis, grab - Vector3(0, TOY * 0.45, 0))
			return true
		rb.freeze = false
		rb.linear_velocity = (hand_vel[0] as Vector3).limit_length(30.0)
		rb.angular_velocity = Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))
		held = -1
		main.sound("whoosh", -10.0, 1.4)
		return true
	if not pressed:
		return false
	var best := -1
	var bd := TOY * 1.1
	for i in toys.size():
		var d := grab.distance_to(toys[i].global_position)
		if d < bd:
			bd = d
			best = i
	if best < 0:
		return false
	held = best
	touched["grab"] = true
	var rb2 := toys[best]
	rb2.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	rb2.freeze = true
	main.sound("pickup", -8.0, 1.5)
	return true


# --- Network -------------------------------------------------------------------------------

func net_state() -> Array:
	var out: Array = []
	for rb in toys:
		out.append(rb.global_position)
		out.append(rb.global_basis.get_rotation_quaternion())
	return out


func apply_net_state(st: Array) -> void:
	for i in mini(toys.size(), st.size() / 2):
		var p: Vector3 = st[i * 2]
		var q: Quaternion = st[i * 2 + 1]
		toy_target[i] = Transform3D(Basis(q), p)


## Tests: where to poke each kind of toy.
func bot_targets() -> Array:
	return [["cloud", _cloud_pos(0)], ["balloon", balloons[0].global_position], ["bird", birds[0].global_position],
		["toy", toys[4].global_position]]
