extends Node3D
## SPROCKET: the little robot engineer who builds the rockets (Rocket Workshop's character). Rolls about
## next to the launch pad on two wheels: a teal body, an orange hard hat, a round screen face with two
## glowing eyes and a smile, a blinking antenna and a spanner in one hand. No words: everything is in
## how he moves, driven by (phase, launch time) on every machine, plus a few one-off moods from events:
##   work: taps the rocket with his spanner and looks round at the crew and the pilot now and then
##   ready: waves both arms towards the pilot (pull the lever!)
##   launch: hops on the spot during the countdown, then cheers with both arms up and spins
##   oops(): shakes his head with squinty eyes (a wrong press)
##   proud(): turns to ROCKET ROW and points while a new model pops in, then turns back
##   party(): a new part unlocked (spins and jumps, antenna flashing)
## Each part is one merged vertex-coloured mesh (body, head, arm), so he is a handful of draw calls.

const HOME := Vector3(2.9, 0, -8.3)
const TEAL := Color(0.25, 0.75, 0.8)
const HAT := Color(1.0, 0.6, 0.15)

var main
var body: Node3D
var head: Node3D
var eyes: MeshInstance3D
var arm_l: Node3D
var arm_r: Node3D
var bulb_mat: StandardMaterial3D
var t := 0.0
var mood := ""
var mood_t := 0.0
var glance_t := 3.0
var glance_yaw := 0.0
var yaw := 0.0


func _ready() -> void:
	position = HOME
	body = Node3D.new()
	add_child(body)
	var dark := Color(0.22, 0.22, 0.27)
	var wheel_b := Basis(Vector3.FORWARD, PI / 2.0)
	var torso: Array = [
		[main.cyl_mesh(0.16, 0.16, 0.12, 14), Transform3D(wheel_b, Vector3(-0.22, 0.16, 0)), dark],
		[main.cyl_mesh(0.16, 0.16, 0.12, 14), Transform3D(wheel_b, Vector3(0.22, 0.16, 0)), dark],
		[main.cyl_mesh(0.06, 0.06, 0.34, 8), Transform3D(wheel_b, Vector3(0, 0.16, 0)), Color(0.6, 0.6, 0.65)],
		[main.box_mesh(Vector3(0.5, 0.5, 0.36)), Transform3D(Basis(), Vector3(0, 0.55, 0)), TEAL],
		[main.box_mesh(Vector3(0.3, 0.2, 0.02)), Transform3D(Basis(), Vector3(0, 0.58, 0.19)), Color(0.95, 0.9, 0.75)],
		[main.sphere_mesh(0.035), Transform3D(Basis(), Vector3(-0.07, 0.6, 0.2)), Color(1.0, 0.35, 0.3)],
		[main.sphere_mesh(0.035), Transform3D(Basis(), Vector3(0.0, 0.6, 0.2)), Color(1.0, 0.85, 0.2)],
		[main.sphere_mesh(0.035), Transform3D(Basis(), Vector3(0.07, 0.6, 0.2)), Color(0.35, 0.9, 0.4)],
		[main.cyl_mesh(0.05, 0.05, 0.12, 8), Transform3D(Basis(), Vector3(0, 0.85, 0)), Color(0.6, 0.6, 0.65)],
	]
	_mesh(body, "sprocket_body", torso)
	head = Node3D.new()
	head.position = Vector3(0, 0.98, 0)
	body.add_child(head)
	_mesh(head, "sprocket_head", [
		[main.box_mesh(Vector3(0.46, 0.36, 0.34)), Transform3D(Basis(), Vector3(0, 0.12, 0)), TEAL.lightened(0.15)],
		[main.box_mesh(Vector3(0.38, 0.26, 0.02)), Transform3D(Basis(), Vector3(0, 0.12, 0.17)), Color(0.08, 0.12, 0.18)],
		[main.box_mesh(Vector3(0.14, 0.025, 0.01)), Transform3D(Basis(), Vector3(0, 0.04, 0.185)), Color(0.4, 1.0, 0.9)],
		[main.sphere_mesh(0.27), Transform3D(Basis.from_scale(Vector3(1.0, 0.75, 1.0)), Vector3(0, 0.3, 0)), HAT],
		[main.cyl_mesh(0.3, 0.3, 0.03, 16), Transform3D(Basis(), Vector3(0, 0.3, 0.06)), HAT.darkened(0.1)],
		[main.box_mesh(Vector3(0.05, 0.08, 0.5)), Transform3D(Basis(), Vector3(0, 0.48, 0)), HAT.lightened(0.15)],
		[main.cyl_mesh(0.012, 0.012, 0.2, 6), Transform3D(Basis(), Vector3(0.16, 0.5, 0)), Color(0.6, 0.6, 0.65)],
	])
	eyes = MeshInstance3D.new()
	eyes.mesh = main.merged_mesh("sprocket_eyes", [
		[main.sphere_mesh(0.045), Transform3D(Basis(), Vector3(-0.08, 0.15, 0.18)), Color(0.5, 1.0, 0.95)],
		[main.sphere_mesh(0.045), Transform3D(Basis(), Vector3(0.08, 0.15, 0.18)), Color(0.5, 1.0, 0.95)]])
	var em: StandardMaterial3D = main.make_material(Color(0.5, 1.0, 0.95), 2.0)
	eyes.material_override = em
	head.add_child(eyes)
	bulb_mat = main.make_material(Color(1.0, 0.3, 0.3), 2.0)
	var bulb := MeshInstance3D.new()
	bulb.mesh = main.sphere_mesh(0.04)
	bulb.material_override = bulb_mat
	bulb.position = Vector3(0.16, 0.62, 0)
	head.add_child(bulb)
	arm_l = _arm(-1.0, false)
	arm_r = _arm(1.0, true)


func _mesh(parent: Node3D, key: String, parts: Array) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = main.merged_mesh(key, parts)
	mi.material_override = main.vertex_mat()
	parent.add_child(mi)
	return mi


## An arm hanging from the shoulder (pivot), rotated about x to swing forward / up.
func _arm(side: float, spanner: bool) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(0.31 * side, 0.74, 0)
	body.add_child(pivot)
	var parts: Array = [
		[main.capsule_mesh(0.055, 0.36), Transform3D(Basis(), Vector3(0, -0.16, 0)), TEAL.darkened(0.15)],
		[main.sphere_mesh(0.075), Transform3D(Basis(), Vector3(0, -0.36, 0)), Color(0.85, 0.85, 0.9)],
	]
	if spanner:
		parts.append([main.box_mesh(Vector3(0.04, 0.04, 0.3)), Transform3D(Basis(), Vector3(0, -0.38, 0.14)), Color(0.75, 0.75, 0.8)])
		parts.append([main.box_mesh(Vector3(0.1, 0.05, 0.06)), Transform3D(Basis(), Vector3(0, -0.38, 0.3)), Color(0.75, 0.75, 0.8)])
	_mesh(pivot, "sprocket_arm%d" % int(spanner), parts)
	return pivot


func oops() -> void:
	_set_mood("oops", 1.2)


func proud() -> void:
	_set_mood("proud", 3.0)


func party() -> void:
	_set_mood("party", 2.5)


func _set_mood(m: String, secs: float) -> void:
	mood = m
	mood_t = secs


func _yaw_to(target: Vector3) -> float:
	var d := target - position
	return atan2(d.x, d.z)


## Called every frame on every machine.
func update_sprocket(phase: String, launch_t: float, delta: float) -> void:
	t += delta
	mood_t -= delta
	if mood_t <= 0.0:
		mood = ""
	var desk := _yaw_to(Vector3(0, 0, 0))
	var want_yaw := desk
	var hop := 0.0
	var arm_l_x := 0.0
	var arm_r_x := 0.0
	var arm_l_z := 0.0
	var arm_r_z := 0.0
	var head_yaw := 0.0
	var head_roll := 0.0
	var eye_sy := 1.0 if fmod(t, 3.7) > 0.12 else 0.15  # blinks
	var spin := 0.0
	bulb_mat.emission_energy_multiplier = 3.0 if fmod(t, 1.0) < 0.5 else 0.4
	match mood:
		"oops":
			head_yaw = sin(t * 18.0) * 0.45
			eye_sy = 0.25
			arm_l_x = -0.4
			arm_r_x = -0.4
		"proud":
			want_yaw = _yaw_to(Vector3(position.x * 0.3, 0, -19.0))
			arm_r_x = -2.3  # pointing at Rocket Row
			arm_l_z = 0.3
			hop = absf(sin(t * 6.0)) * 0.05
		"party":
			spin = t * 9.0
			hop = absf(sin(t * 8.0)) * 0.25
			arm_l_x = -2.8
			arm_r_x = -2.8
			bulb_mat.emission_energy_multiplier = 3.0 if fmod(t, 0.2) < 0.1 else 0.3
		_:
			match phase:
				"launch":
					want_yaw = _yaw_to(main.PAD_POS)
					if launch_t < 3.0:
						hop = absf(sin(t * 9.0)) * 0.12
						arm_l_x = -1.2
						arm_r_x = -1.2
					else:
						hop = absf(sin(t * 7.0)) * 0.3
						arm_l_x = -2.9 + sin(t * 10.0) * 0.2
						arm_r_x = -2.9 - sin(t * 10.0) * 0.2
						head_roll = sin(t * 5.0) * 0.2
						if launch_t > 5.0:
							want_yaw = desk
							spin = 0.0
				"ready":
					arm_l_x = -2.6 + sin(t * 8.0) * 0.4
					arm_r_x = -2.6 - sin(t * 8.0) * 0.4
					arm_l_z = -0.3
					arm_r_z = 0.3
					hop = absf(sin(t * 5.0)) * 0.06
				_:
					# Working: tap the rocket with the spanner, glance round now and then.
					glance_t -= delta
					if glance_t <= 0.0:
						glance_t = 2.5 + fmod(t * 7.3, 3.0)
						glance_yaw = [0.0, 0.6, -0.6, 0.0][int(t * 3.0) % 4]
					want_yaw = _yaw_to(main.PAD_POS) * 0.6 + desk * 0.4
					head_yaw = glance_yaw
					arm_r_x = -1.3 + sin(t * 7.0) * 0.35
					arm_l_x = sin(t * 2.0) * 0.1
					hop = absf(sin(t * 3.5)) * 0.02
	yaw = lerp_angle(yaw, want_yaw, 1.0 - exp(-5.0 * delta))
	rotation.y = yaw + spin
	body.position.y = hop
	arm_l.rotation = Vector3(lerpf(arm_l.rotation.x, arm_l_x, 1.0 - exp(-10.0 * delta)), 0.0, lerpf(arm_l.rotation.z, arm_l_z, 1.0 - exp(-10.0 * delta)))
	arm_r.rotation = Vector3(lerpf(arm_r.rotation.x, arm_r_x, 1.0 - exp(-10.0 * delta)), 0.0, lerpf(arm_r.rotation.z, arm_r_z, 1.0 - exp(-10.0 * delta)))
	head.rotation = Vector3(0.0, lerpf(head.rotation.y, head_yaw, 1.0 - exp(-8.0 * delta)), head_roll)
	eyes.scale = Vector3(1.0, eye_sy, 1.0)
