extends Node3D
## TITAN-1, the friendly giant robot (~10.5 m tall). Model (MeshKit, painted per save), walking legs,
## two-bone IK arms that follow fist targets (the VR pilot's hands scaled up), the right-arm tool
## (fist / claw / foam cannon / drill), the chest beam, the block shield, rocket thrusters, reboot pose.
## Movement is heavy and smooth (acceleration + friction, slow turning) and the cockpit never bobs or
## rolls: the cockpit node (and the VR rig inside it) only follows the root's position and yaw.
## The host calls simulate() with an intent from pilot.gd; the TV machine calls apply_net() with
## snapshot values. Gameplay results (hits, damage) are decided in combat.gd.
## Local frame: -Z = forward, +X = right, origin at the feet.

const Data := preload("res://games/mech_titans/data.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const CockpitScript := preload("res://games/mech_titans/cockpit.gd")

const HIP_Y := 4.3
const HIP_X := 1.15
const THIGH := 2.2
const SHIN := 2.2
const SHOULDER := Vector3(2.65, 7.35, 0.15)
const UPPER := 2.3
const FORE := 2.45
const REACH := UPPER + FORE - 0.1
const CHEST := Vector3(0.0, 6.55, -1.5)
const COCKPIT_FLOOR := 7.85
const COCKPIT_Z := -0.3
const RADIUS := 2.6
const WALK_SPEED := 6.5
const ACCEL := 7.0
const TURN_SPEED := 0.85  ## rad/s at full stick (smooth turning)
const TURN_ACCEL := 2.6
const STRIDE := 6.0  ## metres per full step cycle
const DASH_TIME := 0.55

## Called when a foot lands: stomp(foot_world_position, strength 0..1).
signal stomped(pos: Vector3, strength: float)

var paint := "classic"
var armour := 100.0
var armour_max := 100.0
var energy := 100.0
var energy_max := 100.0
var tool := "fist"
var blocking := false
var beam_on := false
var beam_end := Vector3.ZERO
var beam_hot := false  ## the beam is on a painted weak spot (brighter, x3)
var foam_on := false
var rebooting := 0.0
var yaw := 0.0
var velocity := Vector3.ZERO
var turn_vel := 0.0
var dash_t := 0.0
var dash_dir := Vector3.ZERO
var dash_dist := 20.0
var dash_cd := 0.0
var slowed := 0.0
var energy_idle := 0.0
var walk_phase := 0.0
var walk_amp := 0.0
var speed := 0.0
var turning := 0.0  ## -1..1 how hard we are turning (for the vignette)
var claw_closed := false
var grabbed_kind := ""  ## what the claw holds ("" = nothing): visuals only
## Local fist targets (set by the pilot); the fists ease towards them.
var fist_target: Array[Vector3] = [Vector3(-1.6, 5.4, -2.4), Vector3(1.6, 5.4, -2.4)]
var fist_pos: Array[Vector3] = [Vector3(-1.6, 5.4, -2.4), Vector3(1.6, 5.4, -2.4)]
var fist_speed: Array[float] = [0.0, 0.0]
var punch_flash: Array[float] = [0.0, 0.0]
var shield_t := 0.0
var hit_flash := 0.0
var repair_fx := 0.0
var simulated := true  ## false on the TV machine (snapshots drive it)
var bounds := Data.MAP - 4.0
var city: Node  ## city.gd (push_out)
var block_filter: Callable  ## optional func(pos: Vector3, r: float) -> Vector3 (kaiju bodies etc.)

var cockpit: Node3D
var body: Node3D
var torso: MeshInstance3D
var head: MeshInstance3D
var hips: Array[Node3D] = []
var knees: Array[Node3D] = []
var uppers: Array[MeshInstance3D] = []
var fores: Array[MeshInstance3D] = []
var fists: Array[Node3D] = []
var tool_nodes := {}  # tool -> Node3D (on the right fist)
var left_fist_mesh: MeshInstance3D
var beam: MeshInstance3D
var beam_tip: MeshInstance3D
var foam_spray: CPUParticles3D
var shield: MeshInstance3D
var thrusters: Array[MeshInstance3D] = []
var reboot_sign: Label3D
var _prev_foot := [0.0, 0.0]
var _beam_mat: StandardMaterial3D
var _last_pos := Vector3.ZERO
var _net_target := Transform3D()
var _has_net := false


func _ready() -> void:
	name = "Titan"
	_build()
	_last_pos = global_position


# --- Model ----------------------------------------------------------------------------------------

func _colors() -> Dictionary:
	return Data.PAINTS.get(paint, Data.PAINTS["classic"])


## Change the paint job (rebuilds the cached meshes for it).
func set_paint(p: String) -> void:
	if p == paint and body != null:
		return
	paint = p
	if body != null:
		for c in get_children():
			if c != cockpit and c is Node3D and not (c is XROrigin3D):
				c.queue_free()
		hips.clear()
		knees.clear()
		uppers.clear()
		fores.clear()
		fists.clear()
		tool_nodes.clear()
		thrusters.clear()
		_build_parts()


func _build() -> void:
	cockpit = CockpitScript.new()
	cockpit.name = "Cockpit"
	add_child(cockpit)
	cockpit.position = Vector3(0, COCKPIT_FLOOR, COCKPIT_Z)
	_build_parts()


func _mesh(key: String, maker: Callable) -> ArrayMesh:
	return ResCache.get_or_make("mt_mech_%s_%s_v2" % [paint, key], maker)


func _build_parts() -> void:
	var c := _colors()
	var main_c: Color = c["main"]
	var trim: Color = c["trim"]
	var glow: Color = c["glow"]
	var dark := Color(0.28, 0.3, 0.36)
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	torso = MeshKit.instance(_mesh("torso", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		b.rounded_box(Vector3(3.0, 1.3, 2.1), 0.35, MeshKit.at(Vector3(0, 4.5, 0.1)), dark)
		b.rounded_box(Vector3(2.4, 1.0, 0.4), 0.15, MeshKit.at(Vector3(0, 4.5, -0.95)), trim)
		b.rounded_box(Vector3(4.4, 3.3, 2.8), 0.6, MeshKit.at(Vector3(0, 6.35, 0.15)), main_c)
		b.rounded_box(Vector3(3.4, 1.7, 0.4), 0.3, MeshKit.at(Vector3(0, 6.75, -1.25)), trim)
		b.cylinder(0.75, 0.75, 0.3, MeshKit.at(CHEST + Vector3(0, 0, 0.15), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), dark, 16)
		b.cylinder(0.55, 0.55, 0.32, MeshKit.at(CHEST + Vector3(0, 0, 0.12), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), glow, 16, true)
		for k in 3:
			b.rounded_box(Vector3(2.2 - k * 0.3, 0.32, 0.3), 0.1, MeshKit.at(Vector3(0, 5.55 - k * 0.42, -1.18)), dark.lightened(0.15))
		for sx in [-1.0, 1.0]:
			b.rounded_box(Vector3(1.9, 1.3, 2.2), 0.4, MeshKit.at(Vector3(sx * 2.65, 7.75, 0.15)), main_c)
			b.rounded_box(Vector3(1.95, 0.3, 2.25), 0.1, MeshKit.at(Vector3(sx * 2.65, 7.45, 0.15)), trim)
			b.sphere(0.7, MeshKit.at(Vector3(sx * 2.65, 7.35, 0.15)), dark, 12)
			b.sphere(0.55, MeshKit.at(Vector3(sx * HIP_X, HIP_Y, 0.0)), dark, 12)
		# Jet pack and thruster nozzles on the back.
		b.rounded_box(Vector3(2.8, 2.4, 1.0), 0.3, MeshKit.at(Vector3(0, 6.6, 1.95)), dark.lightened(0.1))
		for sx2 in [-0.8, 0.8]:
			b.cylinder(0.45, 0.6, 1.0, MeshKit.at(Vector3(sx2, 5.3, 2.1)), dark, 12)
		b.rounded_box(Vector3(1.4, 0.35, 0.35), 0.1, MeshKit.at(Vector3(0, 7.55, -1.15)), glow, 2, true)
		return b.build()))
	torso.name = "Torso"
	body.add_child(torso)
	head = MeshKit.instance(_mesh("head", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		b.rounded_box(Vector3(2.9, 2.2, 2.9), 0.7, MeshKit.at(Vector3(0, 8.95, -0.15)), main_c)
		b.rounded_box(Vector3(2.4, 1.15, 0.5), 0.4, MeshKit.at(Vector3(0, 9.25, -1.45)), Color(0.12, 0.2, 0.32))
		b.rounded_box(Vector3(2.0, 0.25, 0.3), 0.1, MeshKit.at(Vector3(0, 8.45, -1.55)), trim)
		for sx in [-1.0, 1.0]:
			b.wedge(Vector3(0.3, 1.5, 0.5), MeshKit.at(Vector3(sx * 0.55, 10.45, -1.05), Vector3.ONE, Vector3(0, 0, -sx * 0.6)), Color(1.0, 0.82, 0.3))
			b.sphere(0.35, MeshKit.at(Vector3(sx * 1.5, 9.0, -0.15)), trim, 10)
		b.sphere(0.25, MeshKit.at(Vector3(0, 10.15, -1.2)), Color(1.0, 0.3, 0.3), 10, true)
		return b.build()), false)
	head.name = "HeadShell"
	head.layers = Data.LAYER_EXTERIOR
	body.add_child(head)
	# Legs: hip pivot > thigh, knee pivot > shin + foot.
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var hip := Node3D.new()
		hip.name = "Hip%d" % side
		hip.position = Vector3(sx * HIP_X, HIP_Y, 0)
		add_child(hip)
		var thigh := MeshKit.instance(_mesh("thigh", func() -> ArrayMesh:
			var b := MeshKit.Builder.new()
			b.rounded_box(Vector3(1.35, THIGH, 1.55), 0.35, MeshKit.at(Vector3(0, -THIGH * 0.5, 0)), main_c)
			b.rounded_box(Vector3(1.4, 0.3, 1.6), 0.1, MeshKit.at(Vector3(0, -THIGH * 0.35, 0)), trim)
			return b.build()))
		hip.add_child(thigh)
		var knee := Node3D.new()
		knee.position = Vector3(0, -THIGH, 0)
		hip.add_child(knee)
		var shin := MeshKit.instance(_mesh("shin", func() -> ArrayMesh:
			var b := MeshKit.Builder.new()
			b.sphere(0.6, MeshKit.at(Vector3(0, 0, 0)), dark, 12)
			b.rounded_box(Vector3(1.55, SHIN, 1.8), 0.4, MeshKit.at(Vector3(0, -SHIN * 0.5, 0.05)), main_c)
			b.rounded_box(Vector3(1.0, 1.1, 0.35), 0.15, MeshKit.at(Vector3(0, -SHIN * 0.45, -0.9)), trim)
			b.rounded_box(Vector3(1.9, 0.75, 3.0), 0.3, MeshKit.at(Vector3(0, -SHIN + 0.0, -0.45)), dark.lightened(0.05))
			b.rounded_box(Vector3(1.6, 0.4, 0.6), 0.15, MeshKit.at(Vector3(0, -SHIN + 0.1, -1.85)), trim)
			return b.build()))
		knee.add_child(shin)
		hips.append(hip)
		knees.append(knee)
	# Arms (transforms set every frame by the IK).
	for side in 2:
		var up := MeshKit.instance(_mesh("upper", func() -> ArrayMesh:
			var b := MeshKit.Builder.new()
			b.rounded_box(Vector3(1.1, UPPER, 1.1), 0.35, MeshKit.at(Vector3(0, UPPER * 0.5, 0)), dark.lightened(0.1))
			b.rounded_box(Vector3(1.2, 0.5, 1.2), 0.15, MeshKit.at(Vector3(0, UPPER * 0.55, 0)), main_c)
			return b.build()))
		add_child(up)
		uppers.append(up)
		var fo := MeshKit.instance(_mesh("fore", func() -> ArrayMesh:
			var b := MeshKit.Builder.new()
			b.sphere(0.6, MeshKit.at(Vector3.ZERO), dark, 12)
			b.rounded_box(Vector3(1.35, FORE, 1.35), 0.4, MeshKit.at(Vector3(0, FORE * 0.5, 0)), main_c)
			b.rounded_box(Vector3(1.42, 0.35, 1.42), 0.12, MeshKit.at(Vector3(0, FORE * 0.8, 0)), trim)
			return b.build()))
		add_child(fo)
		fores.append(fo)
		var fist := Node3D.new()
		fist.name = "Fist%d" % side
		add_child(fist)
		fists.append(fist)
	left_fist_mesh = MeshKit.instance(_fist_mesh(), true)
	fists[0].add_child(left_fist_mesh)
	for t in Data.TOOLS:
		var n := Node3D.new()
		n.name = "Tool_" + t
		fists[1].add_child(n)
		tool_nodes[t] = n
		match t:
			"fist":
				n.add_child(MeshKit.instance(_fist_mesh()))
			"claw":
				n.add_child(MeshKit.instance(_mesh("claw_base", func() -> ArrayMesh:
					var b := MeshKit.Builder.new()
					b.cylinder(0.75, 0.85, 0.7, MeshKit.at(Vector3(0, 0.3, 0)), dark, 12)
					b.cylinder(0.5, 0.5, 0.3, MeshKit.at(Vector3(0, 0.7, 0)), Color(1.0, 0.8, 0.3), 12, true)
					return b.build())))
				for k in 3:
					var finger := Node3D.new()
					finger.name = "Finger%d" % k
					finger.rotation.y = k * TAU / 3.0
					n.add_child(finger)
					var pivot := Node3D.new()
					pivot.name = "Pivot"
					pivot.position = Vector3(0, 0.6, 0.55)
					finger.add_child(pivot)
					pivot.add_child(MeshKit.instance(_mesh("claw_finger", func() -> ArrayMesh:
						var b := MeshKit.Builder.new()
						b.rounded_box(Vector3(0.35, 1.4, 0.35), 0.12, MeshKit.at(Vector3(0, 0.7, 0)), Color(1.0, 0.8, 0.3))
						b.rounded_box(Vector3(0.3, 0.8, 0.3), 0.1, MeshKit.at(Vector3(0, 1.5, -0.25), Vector3.ONE, Vector3(-0.7, 0, 0)), dark)
						return b.build())))
			"foam":
				n.add_child(MeshKit.instance(_mesh("foam", func() -> ArrayMesh:
					var b := MeshKit.Builder.new()
					b.cylinder(0.75, 0.75, 1.2, MeshKit.at(Vector3(0, 0.5, 0)), Color(0.95, 0.95, 1.0), 12)
					b.cylinder(0.45, 0.6, 1.2, MeshKit.at(Vector3(0, 1.6, 0)), Color(0.3, 0.75, 1.0), 12)
					b.torus(0.5, 0.12, MeshKit.at(Vector3(0, 2.2, 0)), Color(1.0, 0.85, 0.3), 12, 6)
					return b.build())))
			"drill":
				var spin := Node3D.new()
				spin.name = "Spin"
				n.add_child(spin)
				spin.add_child(MeshKit.instance(_mesh("drill", func() -> ArrayMesh:
					var b := MeshKit.Builder.new()
					b.cylinder(0.8, 0.8, 0.5, MeshKit.at(Vector3(0, 0.25, 0)), dark, 12)
					b.cone(0.75, 2.4, MeshKit.at(Vector3(0, 1.7, 0)), Color(0.85, 0.87, 0.92), 12)
					for k in 4:
						b.torus(0.62 - k * 0.15, 0.08, MeshKit.at(Vector3(0, 0.9 + k * 0.45, 0), Vector3.ONE, Vector3(0.25, k * 0.8, 0)), Color(1.0, 0.45, 0.3), 12, 4)
					return b.build())))
	# Thruster flames on the jet pack.
	for sx in [-0.8, 0.8]:
		var fl := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.55
		cm.bottom_radius = 0.05
		cm.height = 3.0
		cm.radial_segments = 10
		cm.rings = 1
		fl.mesh = cm
		fl.material_override = _additive(Color(0.5, 0.85, 1.0, 0.85))
		fl.position = Vector3(sx, 3.4, 2.1)
		fl.visible = false
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fl)
		thrusters.append(fl)
	# Beam.
	beam = MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.45
	bc.bottom_radius = 0.45
	bc.height = 1.0
	bc.radial_segments = 10
	bc.rings = 1
	beam.mesh = bc
	_beam_mat = _additive(Color(0.4, 0.9, 1.0, 0.95))
	beam.material_override = _beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visible = false
	beam.top_level = true
	add_child(beam)
	beam_tip = MeshInstance3D.new()
	var tip := SphereMesh.new()
	tip.radius = 1.3
	tip.height = 2.6
	tip.radial_segments = 12
	tip.rings = 6
	beam_tip.mesh = tip
	beam_tip.material_override = _beam_mat
	beam_tip.top_level = true
	beam_tip.visible = false
	beam_tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam_tip)
	foam_spray = CPUParticles3D.new()
	foam_spray.amount = 40
	foam_spray.lifetime = 0.9
	foam_spray.local_coords = false
	foam_spray.emitting = false
	foam_spray.spread = 8.0
	foam_spray.initial_velocity_min = 22.0
	foam_spray.initial_velocity_max = 28.0
	foam_spray.gravity = Vector3(0, -12.0, 0)
	foam_spray.scale_amount_min = 0.8
	foam_spray.scale_amount_max = 1.6
	var fsm := SphereMesh.new()
	fsm.radius = 0.6
	fsm.height = 1.2
	fsm.radial_segments = 8
	fsm.rings = 4
	fsm.material = MeshKit.material(Color(0.97, 0.98, 1.0))
	foam_spray.mesh = fsm
	fists[1].add_child(foam_spray)
	foam_spray.position = Vector3(0, 2.3, 0)
	foam_spray.direction = Vector3.UP
	# Shield: a translucent bubble segment in front of the chest.
	shield = MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 4.5
	sp.height = 9.0
	sp.radial_segments = 16
	sp.rings = 8
	sp.is_hemisphere = true
	shield.mesh = sp
	shield.material_override = _additive(Color(glow.r, glow.g, glow.b, 0.28))
	shield.position = Vector3(0, 6.6, -1.2)
	shield.rotation = Vector3(-PI * 0.5, 0, 0)
	shield.scale = Vector3(1.0, 0.45, 1.0)
	shield.visible = false
	shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shield)
	reboot_sign = Label3D.new()
	reboot_sign.text = "REBOOTING..."
	reboot_sign.font_size = 96
	reboot_sign.pixel_size = 0.02
	reboot_sign.outline_size = 22
	reboot_sign.modulate = Color(1.0, 0.85, 0.3)
	reboot_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	reboot_sign.layers = Data.LAYER_TV_ONLY
	reboot_sign.position = Vector3(0, 12.5, 0)
	reboot_sign.visible = false
	add_child(reboot_sign)
	_set_tool_visual()
	_update_arms(0.0, true)


func _fist_mesh() -> ArrayMesh:
	var c := _colors()
	var main_c: Color = c["main"]
	var trim: Color = c["trim"]
	return _mesh("fist", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		b.rounded_box(Vector3(1.55, 1.5, 1.5), 0.45, MeshKit.at(Vector3(0, 0.55, 0)), main_c)
		for k in 4:
			b.rounded_box(Vector3(0.36, 0.42, 0.5), 0.12, MeshKit.at(Vector3(-0.54 + k * 0.36, 1.32, -0.25)), trim)
		b.rounded_box(Vector3(0.45, 0.8, 0.4), 0.15, MeshKit.at(Vector3(0.75, 0.6, -0.45)), trim)
		return b.build())


func _additive(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _set_tool_visual() -> void:
	for t in tool_nodes:
		(tool_nodes[t] as Node3D).visible = t == tool


# --- Queries ---------------------------------------------------------------------------------------

func forward() -> Vector3:
	return -global_basis.z


func right() -> Vector3:
	return global_basis.x


## World position of a fist (0 = left, 1 = right).
func fist_world(i: int) -> Vector3:
	return fists[i].global_transform * Vector3(0, 0.6, 0)


func chest_world() -> Vector3:
	return to_global(CHEST)


func shoulder_local(i: int) -> Vector3:
	return Vector3(SHOULDER.x * (-1.0 if i == 0 else 1.0), SHOULDER.y, SHOULDER.z)


## Guard pose for blocking: forearms crossed low in front of the chest (keeps the canopy view clear).
func guard_target(i: int) -> Vector3:
	return Vector3(0.7 * (-1.0 if i == 0 else 1.0), 5.9, -3.1)


## Resting / walking pose when no pilot hands are driving the arms.
func rest_target(i: int) -> Vector3:
	var sx := -1.0 if i == 0 else 1.0
	var swing := sin(walk_phase + (0.0 if i == 0 else PI)) * walk_amp * 0.9
	return Vector3(sx * 3.0, 4.6, -1.2 + swing)


# --- Host simulation ---------------------------------------------------------------------------------

## intent: move (Vector2 x right / y forward, mech frame) or move_world (Vector3), turn (-1..1, + = right),
## snap (int: +1 right / -1 left), face (Vector3 world dir, TV pilot), dash (bool), block (bool),
## fists ([Vector3, Vector3] local targets; empty = rest pose).
func simulate(delta: float, intent: Dictionary) -> void:
	var down := rebooting > 0.0
	if down:
		rebooting = maxf(0.0, rebooting - delta)
	dash_cd = maxf(0.0, dash_cd - delta)
	slowed = maxf(0.0, slowed - delta)
	var want := Vector3.ZERO
	if not down:
		if intent.has("move_world"):
			want = intent["move_world"]
		elif intent.has("move"):
			var mv: Vector2 = intent["move"]
			want = right() * mv.x + forward() * mv.y
		want.y = 0.0
		if want.length() > 1.0:
			want = want.normalized()
	var max_speed := WALK_SPEED * (0.5 if slowed > 0.0 else 1.0) * (0.35 if blocking else 1.0)
	var target_v := want * max_speed
	velocity = velocity.lerp(target_v, 1.0 - exp(-ACCEL * delta / maxf(max_speed, 0.1) * 2.0))
	# Turning: smooth (eased rate) or snap.
	var turn_in: float = 0.0 if down else float(intent.get("turn", 0.0))
	if intent.has("face") and not down:
		var f: Vector3 = intent["face"]
		f.y = 0.0
		if f.length() > 0.1:
			var target_yaw := atan2(-f.x, -f.z)
			var diff := angle_difference(yaw, target_yaw)
			turn_in = clampf(-diff * 2.0, -1.6, 1.6)
	turn_vel = move_toward(turn_vel, turn_in * TURN_SPEED, TURN_ACCEL * delta)
	yaw -= turn_vel * delta
	var snap: int = 0 if down else int(intent.get("snap", 0))
	if snap != 0:
		yaw -= snap * deg_to_rad(30.0)
	turning = clampf(absf(turn_vel) / TURN_SPEED, 0.0, 1.0)
	# Dash.
	if bool(intent.get("dash", false)) and not down and dash_t <= 0.0 and dash_cd <= 0.0 and energy >= 20.0:
		var d := want if want.length() > 0.2 else forward()
		dash_dir = d.normalized()
		dash_t = DASH_TIME
		dash_cd = 1.1
		use_energy(25.0)
	var step := velocity * delta
	if dash_t > 0.0:
		var k := dash_t / DASH_TIME
		step += dash_dir * (dash_dist / DASH_TIME) * 1.6 * k * delta
		dash_t = maxf(0.0, dash_t - delta)
	var p := position + step
	p.x = clampf(p.x, -bounds, bounds)
	p.z = clampf(p.z, -bounds, bounds)
	if city != null:
		p = city.push_out(p, RADIUS)
	if block_filter.is_valid():
		p = block_filter.call(p, RADIUS)
	p.y = 0.0
	position = p
	rotation = Vector3(0, yaw, 0)
	# Arms.
	blocking = bool(intent.get("block", false)) and not down
	var fl: Array = intent.get("fists", [])
	for i in 2:
		if blocking:
			fist_target[i] = guard_target(i)
		elif down:
			fist_target[i] = Vector3((-1.0 if i == 0 else 1.0) * 2.6, 2.0, -1.0)
		elif fl.size() == 2:
			fist_target[i] = fl[i]
		else:
			fist_target[i] = rest_target(i)
	# Energy regeneration (after a short idle).
	energy_idle += delta
	if energy_idle > 0.8:
		energy = minf(energy_max, energy + 16.0 * delta)
	_animate(delta)


## Spend energy (beam, dash); returns false when empty.
func use_energy(amount: float) -> bool:
	energy_idle = 0.0
	if energy <= 0.0:
		return false
	energy = maxf(0.0, energy - amount)
	return true


## Host: the Titan got hit. Returns the damage actually taken (blocks soak most of it).
func take_damage(amount: float) -> float:
	if rebooting > 0.0:
		return 0.0
	var dmg := amount * (0.2 if blocking else 1.0)
	armour = maxf(0.0, armour - dmg)
	hit_flash = 1.0
	if blocking:
		shield_t = 1.0
	if armour <= 0.0:
		rebooting = 6.0
		beam_on = false
		foam_on = false
	return dmg


func repair(amount: float) -> void:
	armour = minf(armour_max, armour + amount)
	repair_fx = 0.4
	if rebooting > 0.0:
		rebooting = maxf(0.0, rebooting - amount * 0.05)
		if rebooting <= 0.0:
			armour = maxf(armour, armour_max * 0.5)


func finish_reboot_if_due() -> bool:
	if rebooting <= 0.0 and armour <= 0.0:
		armour = armour_max * 0.5
		return true
	return false


# --- Animation (every machine) --------------------------------------------------------------------------

func _animate(delta: float) -> void:
	var moved := global_position - _last_pos
	moved.y = 0.0
	_last_pos = global_position
	speed = moved.length() / maxf(delta, 0.0001)
	var amp_target := clampf(speed / WALK_SPEED, 0.0, 1.0) if dash_t <= 0.0 else 0.15
	walk_amp = lerpf(walk_amp, amp_target, 1.0 - exp(-6.0 * delta))
	if rebooting > 0.0:
		walk_amp = 0.0
	walk_phase += (moved.length() / STRIDE) * TAU if dash_t <= 0.0 else 0.0
	if walk_amp < 0.05:
		walk_phase = lerpf(walk_phase, roundf(walk_phase / PI) * PI, 1.0 - exp(-4.0 * delta))
	var kneel := 1.0 if rebooting > 0.0 else 0.0
	for side in 2:
		var ph := walk_phase + (0.0 if side == 0 else PI)
		var swing := sin(ph) * 0.42 * walk_amp
		var lift := maxf(0.0, -cos(ph)) * 0.9 * walk_amp
		hips[side].rotation = Vector3(-swing - lift * 0.4 - kneel * (0.9 if side == 0 else 0.2), 0, 0)
		knees[side].rotation = Vector3(lift + kneel * (1.6 if side == 0 else 0.4), 0, 0)
		# Foot strike: the phase crossing the "down" point.
		var foot := sin(ph)
		var prev: float = _prev_foot[side]
		if prev < 0.0 and foot >= 0.0 and walk_amp > 0.25:
			var fpos := to_global(Vector3((-1.0 if side == 0 else 1.0) * HIP_X, 0.0, -0.4 + swing * 2.0))
			stomped.emit(fpos, walk_amp)
		_prev_foot[side] = foot
	var bob := absf(sin(walk_phase)) * 0.22 * walk_amp - kneel * 0.7
	body.position = Vector3(0, bob, 0)
	body.rotation = Vector3(-kneel * 0.15 + (0.12 if dash_t > 0.0 else 0.0), 0, sin(walk_phase) * 0.025 * walk_amp)
	for side in 2:
		hips[side].position.y = HIP_Y + bob
	var dashing := dash_t > 0.0
	for t in thrusters:
		t.visible = dashing
		if dashing:
			t.scale = Vector3(1.0, 0.8 + randf() * 0.5, 1.0)
	shield.visible = blocking or shield_t > 0.0
	shield_t = maxf(0.0, shield_t - delta * 2.5)
	if shield.visible:
		var sm := shield.material_override as StandardMaterial3D
		var g: Color = _colors()["glow"]
		sm.albedo_color = Color(g.r, g.g, g.b, 0.22 + shield_t * 0.4)
	hit_flash = maxf(0.0, hit_flash - delta * 3.0)
	repair_fx = maxf(0.0, repair_fx - delta)
	reboot_sign.visible = rebooting > 0.0
	for i in 2:
		punch_flash[i] = maxf(0.0, punch_flash[i] - delta * 3.0)
	_update_arms(delta, false)
	_update_tool(delta)
	_update_beam()


func _update_arms(delta: float, snap_now: bool) -> void:
	for i in 2:
		var tgt := fist_target[i]
		var s := shoulder_local(i)
		var off := tgt - s
		if off.length() > REACH:
			off = off.normalized() * REACH
		tgt = s + off
		# Keep the fists out of the cockpit.
		if tgt.y > 7.4 and absf(tgt.x) < 1.9 and tgt.z > -2.6:
			tgt.z = -2.6
		var prev := fist_pos[i]
		var k := 1.0 if snap_now else 1.0 - exp(-16.0 * delta)
		fist_pos[i] = prev.lerp(tgt, k)
		fist_speed[i] = (fist_pos[i] - prev).length() / maxf(delta, 0.0001) if not snap_now else 0.0
		_place_arm(i)


func _place_arm(i: int) -> void:
	var s := shoulder_local(i)
	var f := fist_pos[i]
	var d := f - s
	var dist := clampf(d.length(), 0.35 * REACH, (UPPER + FORE) * 0.999)
	var dir := d.normalized() if d.length() > 0.001 else Vector3.DOWN
	var sx := -1.0 if i == 0 else 1.0
	var pole := Vector3(sx * 1.0, -0.8, 0.7).normalized()
	pole = (pole - dir * pole.dot(dir)).normalized()
	if pole.length() < 0.01:
		pole = Vector3(sx, 0, 0)
	var a := UPPER
	var b := FORE
	var x := (a * a - b * b + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(a * a - x * x, 0.0))
	var elbow := s + dir * x + pole * h
	var fist_at := s + dir * dist
	uppers[i].transform = Transform3D(_basis_y_to(elbow - s), s)
	fores[i].transform = Transform3D(_basis_y_to(fist_at - elbow), elbow)
	var fb := _basis_y_to(fist_at - elbow)
	fists[i].transform = Transform3D(fb, fist_at - fb.y * 0.15)
	var pf := punch_flash[i]
	if pf > 0.0:
		fists[i].scale = Vector3.ONE * (1.0 + pf * 0.25)


static func _basis_y_to(v: Vector3) -> Basis:
	var y := v.normalized() if v.length() > 0.0001 else Vector3.UP
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _update_tool(delta: float) -> void:
	if tool_nodes.has("drill"):
		var spin := (tool_nodes["drill"] as Node3D).get_node_or_null("Spin") as Node3D
		if spin != null:
			spin.rotation.y += delta * (30.0 if fist_speed[1] > 3.0 or punch_flash[1] > 0.0 else 8.0)
	if tool_nodes.has("claw"):
		var claw: Node3D = tool_nodes["claw"]
		var close := 0.55 if claw_closed else -0.35
		for k in 3:
			var piv := claw.get_node_or_null("Finger%d/Pivot" % k) as Node3D
			if piv != null:
				piv.rotation.x = lerpf(piv.rotation.x, close, 1.0 - exp(-12.0 * delta))
	foam_spray.emitting = foam_on and tool == "foam"


func _update_beam() -> void:
	beam.visible = beam_on
	beam_tip.visible = beam_on
	if not beam_on:
		return
	var from := chest_world()
	var d := beam_end - from
	var l := d.length()
	if l < 0.1:
		beam.visible = false
		return
	var w := (1.5 if beam_hot else 1.0) * (0.9 + 0.2 * sin(Time.get_ticks_msec() * 0.03))
	beam.global_transform = Transform3D(_basis_y_to(d).scaled(Vector3(w, l, w)), from + d * 0.5)
	beam_tip.global_position = beam_end
	beam_tip.scale = Vector3.ONE * w * (1.0 + 0.3 * sin(Time.get_ticks_msec() * 0.05))
	var g: Color = _colors()["glow"]
	_beam_mat.albedo_color = Color(1.0, 0.6, 0.35, 0.95) if beam_hot else Color(g.r, g.g, g.b, 0.9)


## Select an arm tool (visuals; the host decides which are unlocked).
func set_tool(t: String) -> void:
	if t == tool:
		return
	tool = t
	claw_closed = false
	_set_tool_visual()


# --- Networking (host packs, TV machine applies) ----------------------------------------------------------

## 18 floats: pos x/z, yaw, fist L xyz, fist R xyz (local), beam end xyz, armour, energy, flags, tool, rebooting.
func pack_net() -> PackedFloat32Array:
	var flags := (1 if beam_on else 0) | (2 if blocking else 0) | (4 if beam_hot else 0) | (8 if foam_on else 0) \
		| (16 if dash_t > 0.0 else 0) | (32 if claw_closed else 0) | (64 if hit_flash > 0.5 else 0) | (128 if repair_fx > 0.0 else 0)
	return PackedFloat32Array([snappedf(position.x, 0.01), snappedf(position.z, 0.01), snappedf(yaw, 0.001),
		snappedf(fist_pos[0].x, 0.01), snappedf(fist_pos[0].y, 0.01), snappedf(fist_pos[0].z, 0.01),
		snappedf(fist_pos[1].x, 0.01), snappedf(fist_pos[1].y, 0.01), snappedf(fist_pos[1].z, 0.01),
		snappedf(beam_end.x, 0.05), snappedf(beam_end.y, 0.05), snappedf(beam_end.z, 0.05),
		roundf(armour), roundf(energy), float(flags), float(Data.TOOLS.find(tool)), snappedf(rebooting, 0.1), roundf(armour_max)])


func apply_net(a: PackedFloat32Array) -> void:
	if a.size() < 18:
		return
	var tgt_pos := Vector3(a[0], 0.0, a[1])
	if not _has_net:
		_has_net = true
		position = tgt_pos
		yaw = a[2]
	_net_target = Transform3D(Basis(Vector3.UP, a[2]), tgt_pos)
	fist_target[0] = Vector3(a[3], a[4], a[5])
	fist_target[1] = Vector3(a[6], a[7], a[8])
	beam_end = Vector3(a[9], a[10], a[11])
	armour = a[12]
	energy = a[13]
	var flags := int(a[14])
	beam_on = (flags & 1) != 0
	blocking = (flags & 2) != 0
	beam_hot = (flags & 4) != 0
	foam_on = (flags & 8) != 0
	dash_t = 0.2 if (flags & 16) != 0 else 0.0
	claw_closed = (flags & 32) != 0
	if (flags & 64) != 0:
		hit_flash = 1.0
	if (flags & 128) != 0:
		repair_fx = 0.4
	var ti := int(a[15])
	if ti >= 0 and ti < Data.TOOLS.size():
		set_tool(Data.TOOLS[ti])
	rebooting = a[16]
	armour_max = a[17]


## TV machine, every frame: glide towards the last snapshot and animate.
func client_tick(delta: float) -> void:
	if not _has_net:
		return
	var k := 1.0 - exp(-12.0 * delta)
	position = position.lerp(_net_target.origin, k)
	var target_yaw := _net_target.basis.get_euler().y
	yaw = lerp_angle(yaw, target_yaw, k)
	rotation = Vector3(0, yaw, 0)
	_animate(delta)
