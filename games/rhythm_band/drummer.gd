extends Node3D
## Player 1: the DRUMMER. Four floating drums (hi-hat, snare, tom, crash) hang around them; glowing
## balls fly down a lane into each drum and a shrinking ring shows when to hit.
## VR (Steam Frame): swing either hand into a drum (the glowing stick tip) - hand speed + being at the
## drum = a hit; no buttons. Left stick: walk around the stage (the kit comes along). Right stick:
## snap turn. A: bring the kit back in front of you. The kit fits your height at the start and again
## when someone shorter or taller takes the headset (it is measured from your head, not a rest pose).
## Flat (split screen / non-VR host): A S D F or mouse left/right; controller X A B Y (or LB / RB).
## Bot "fake VR": the bot moves fake_tips and the same swing detection as VR runs.
## On the TV machine this is a ghost: the kit, a head and two sticks drawn from the host's snapshots.

const HIT_R := 0.13  # metres from the stick tip to a drum's centre
const REARM_R := 0.17
const MIN_SPEED := 0.45  # m/s: resting a hand on a drum doesn't play it
const PAD_OFFSETS: Array[Vector3] = [Vector3(-0.36, -0.36, -0.30), Vector3(-0.16, -0.50, -0.38),
	Vector3(0.16, -0.50, -0.38), Vector3(0.36, -0.34, -0.30)]
const PAD_COLORS: Array[Color] = [Color(1.0, 0.85, 0.2), Color(1.0, 0.3, 0.35), Color(0.3, 0.6, 1.0), Color(0.35, 0.95, 0.45)]
const PAD_NAMES: Array[String] = ["HI-HAT", "SNARE", "TOM", "CRASH"]
const FLAT_KEYS: Array[String] = ["A", "S", "D", "F"]
const NOTE_TRAVEL := 2.6
const TRAVEL_BEATS := 3.0
const POOL := 20
const FLAT_HEAD := 1.45
const STAGE_LIMIT := Rect2(-4.0, -2.0, 8.0, 4.6)  # where the VR player may walk (x, z)

var index := 0
var main
var vr := false
var ghost := false
var remote := false
var active := true
var fake_vr := false
var joy := -1
var key_set := 0
var color := Color(1.0, 0.85, 0.55)
var hand_l: XRController3D
var hand_r: XRController3D
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var camera: Camera3D
var hud: Control
var hud_label: Label
var highway: Control
var pad_lost_t := -1.0

var rig: Node3D
var kit_s := 1.0
var pads: Array[Node3D] = []
var top_mats: Array[StandardMaterial3D] = []
var approach: Array[MeshInstance3D] = []
var guides: Array[MeshInstance3D] = []
var flat_tags: Array[Label3D] = []
var flash := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var notes: Array[MeshInstance3D] = []
var note_mats: Array[StandardMaterial3D] = []
var miss_mat: StandardMaterial3D
var note_cursor := 0
var cursor_serial := -1
var tips: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var prev_tips: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var tip_speed := PackedFloat32Array([0.0, 0.0])
var inside := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0])
var tips_ready := false
var fake_tips: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var hand_anim := PackedFloat32Array([0.0, 0.0])
var hand_pad := PackedInt32Array([1, 2])

var avatar: Node3D
var av_head: Node3D
var av_hands: Array[MeshInstance3D] = []
var status_label: Label3D
var meter_fill: MeshInstance3D
var meter_mat: StandardMaterial3D

var fitted := false
var fit_t := 0.8
var fit_head := 0.0
var refit_t := 0.0
var away_t := 0.0
var a_was := false
var trig_was := false
var turn_ready := true

var hits := 0
var misses := 0
var streak := 0
var miss_run := 0
var swings := 0

var net_rig := Transform3D()
var net_head := Transform3D()
var net_tips: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var net_s := 1.0


func set_active(on: bool) -> void:
	active = on


func is_local() -> bool:
	return not ghost and not remote


func apply_remote_state(_pos: Vector3, _yaw: float, _pitch: float) -> void:
	pass


func _ready() -> void:
	_build_rig()
	_build_avatar()


# --- Building ------------------------------------------------------------------------

func _build_rig() -> void:
	rig = Node3D.new()
	rig.name = "DrumKit"
	main.add_child(rig)
	rig.position = main.DRUM_SPOT + Vector3(0.0, FLAT_HEAD, 0.0)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.115
	torus.outer_radius = 0.135
	torus.rings = 16
	torus.ring_segments = 6
	miss_mat = main.make_material(Color(0.35, 0.35, 0.4), 0.0)
	for i in 4:
		var cym := i == 0 or i == 3
		var pad := Node3D.new()
		rig.add_child(pad)
		var r := 0.14 if cym else 0.12
		var h := 0.02 if cym else 0.08
		var body := MeshInstance3D.new()
		body.mesh = main.cyl_mesh(r, r, h, 16)
		body.material_override = main.make_material(Color(0.85, 0.7, 0.3) if cym else Color(0.9, 0.9, 0.95), 0.0)
		pad.add_child(body)
		var top := MeshInstance3D.new()
		top.mesh = main.cyl_mesh(r * 0.85, r * 0.85, 0.012, 16)
		var tm := StandardMaterial3D.new()
		tm.albedo_color = PAD_COLORS[i]
		tm.emission_enabled = true
		tm.emission = PAD_COLORS[i]
		tm.emission_energy_multiplier = 0.4
		top.material_override = tm
		top.position.y = h * 0.5 + 0.004
		pad.add_child(top)
		top_mats.append(tm)
		var app := MeshInstance3D.new()
		app.mesh = torus
		app.material_override = main.make_material(PAD_COLORS[i], 1.5)
		app.position.y = h * 0.5 + 0.012
		app.visible = false
		pad.add_child(app)
		approach.append(app)
		var stand := MeshInstance3D.new()
		stand.mesh = main.cyl_mesh(0.012, 0.012, 0.9, 6)
		stand.material_override = main.make_material(Color(0.5, 0.5, 0.55), 0.0)
		stand.position = Vector3(0.0, -0.47, 0.0)
		pad.add_child(stand)
		pad.rotation.x = 0.25 if cym else 0.4
		pads.append(pad)
		var guide := MeshInstance3D.new()
		guide.mesh = main.cyl_mesh(0.025, 0.025, NOTE_TRAVEL, 6)
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.albedo_color = Color(PAD_COLORS[i].r, PAD_COLORS[i].g, PAD_COLORS[i].b, 0.18)
		guide.material_override = gm
		guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(guide)
		guides.append(guide)
		var nm := StandardMaterial3D.new()
		nm.albedo_color = PAD_COLORS[i]
		nm.emission_enabled = true
		nm.emission = PAD_COLORS[i]
		nm.emission_energy_multiplier = 1.2
		note_mats.append(nm)
		var tag := Label3D.new()
		tag.text = PAD_NAMES[i]
		tag.font_size = 40
		tag.pixel_size = 0.0012
		tag.outline_size = 12
		tag.modulate = PAD_COLORS[i]
		tag.position = Vector3(0.0, 0.05, 0.16)
		tag.rotation.x = -0.6
		pad.add_child(tag)
		flat_tags.append(tag)
	for k in POOL:
		var m := MeshInstance3D.new()
		m.mesh = main.sphere_mesh(0.05)
		m.visible = false
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(m)
		notes.append(m)
	# Status on the kit itself (VR): the crowd meter and combo, right where the player looks.
	status_label = Label3D.new()
	status_label.font_size = 36
	status_label.pixel_size = 0.0011
	status_label.outline_size = 12
	status_label.width = 520.0
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rig.add_child(status_label)
	var back := MeshInstance3D.new()
	back.name = "MeterBack"
	back.mesh = main.box_mesh(Vector3(0.38, 0.03, 0.01))
	back.material_override = main.make_material(Color(0.1, 0.1, 0.12), 0.0)
	rig.add_child(back)
	meter_fill = MeshInstance3D.new()
	meter_fill.mesh = main.box_mesh(Vector3(0.37, 0.024, 0.012))
	meter_mat = StandardMaterial3D.new()
	meter_mat.emission_enabled = true
	meter_mat.emission_energy_multiplier = 1.0
	meter_fill.material_override = meter_mat
	rig.add_child(meter_fill)
	status_label.visible = false
	back.visible = false
	meter_fill.visible = false
	_layout_kit()


## Puts the drums, lanes and status where they belong for this player's size (kit_s).
func _layout_kit() -> void:
	for i in 4:
		var p := PAD_OFFSETS[i] * kit_s
		pads[i].position = p
		var dir := lane_dir(i)
		guides[i].position = p + dir * NOTE_TRAVEL * 0.5
		guides[i].basis = main.basis_y_to(dir)
		var stand := pads[i].get_child(3) as MeshInstance3D
		if stand != null:
			stand.visible = not vr  # floating drums in VR (the floor height is unknown)
	status_label.position = Vector3(0.0, -0.25, -0.72) * kit_s
	var back := rig.get_node_or_null("MeterBack") as MeshInstance3D
	if back != null:
		back.position = Vector3(0.0, -0.31, -0.72) * kit_s
	meter_fill.position = Vector3(0.0, -0.31, -0.715) * kit_s


func lane_dir(i: int) -> Vector3:
	return Vector3(PAD_OFFSETS[i].x * 1.4, 0.45, -1.0).normalized()


func _build_avatar() -> void:
	avatar = Node3D.new()
	main.add_child(avatar)
	av_head = Node3D.new()
	avatar.add_child(av_head)
	var face := MeshInstance3D.new()
	face.mesh = main.sphere_mesh(0.15)
	face.material_override = main.make_material(Color(1.0, 0.82, 0.65), 0.0)
	av_head.add_child(face)
	var visor := MeshInstance3D.new()
	visor.mesh = main.box_mesh(Vector3(0.22, 0.08, 0.06))
	visor.material_override = main.make_material(Color(0.2, 0.2, 0.25), 0.0)
	visor.position = Vector3(0, 0.02, -0.13)
	av_head.add_child(visor)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.2
	cap.height = 0.8
	cap.radial_segments = 10
	cap.rings = 3
	body.mesh = cap
	body.material_override = main.make_material(Color(1.0, 0.85, 0.55), 0.1)
	body.name = "Body"
	avatar.add_child(body)
	for h in 2:
		var hand := MeshInstance3D.new()
		hand.mesh = main.sphere_mesh(0.04)
		hand.material_override = main.make_material(Color(1.0, 0.82, 0.65), 0.0)
		var stick := MeshInstance3D.new()
		stick.mesh = main.cyl_mesh(0.01, 0.012, 0.3, 6)
		stick.material_override = main.make_material(Color(0.95, 0.85, 0.6), 0.2)
		stick.rotation.x = -PI * 0.5
		stick.position = Vector3(0, 0, -0.12)
		hand.add_child(stick)
		avatar.add_child(hand)
		av_hands.append(hand)


# --- VR ------------------------------------------------------------------------------

func attach_xr(origin: XROrigin3D, cam: XRCamera3D, left: XRController3D, right: XRController3D) -> void:
	vr = true
	xr_origin = origin
	xr_camera = cam
	hand_l = left
	hand_r = right
	cam.near = 0.02
	avatar.visible = false
	rig.reparent(origin, false)
	for tag in flat_tags:
		tag.visible = false
	status_label.visible = true
	meter_fill.visible = true
	var back := rig.get_node_or_null("MeterBack") as MeshInstance3D
	if back != null:
		back.visible = true
	for h in [left, right]:
		var hh: XRController3D = h
		var stick := MeshInstance3D.new()
		stick.mesh = main.cyl_mesh(0.008, 0.012, 0.16, 6)
		stick.material_override = main.make_material(Color(0.95, 0.85, 0.6), 0.2)
		stick.rotation.x = -PI * 0.5
		stick.position = Vector3(0, 0, -0.05)
		hh.add_child(stick)
		var tip := MeshInstance3D.new()
		tip.mesh = main.sphere_mesh(0.025)
		tip.material_override = main.make_material(Color(1.0, 1.0, 0.8), 1.5)
		tip.position = Vector3(0, 0, -0.13)
		hh.add_child(tip)
	_layout_kit()


func vr_trigger() -> bool:
	return vr and hand_r.get_float("trigger") > 0.6


func vr_a() -> bool:
	return vr and hand_r.is_button_pressed("ax_button")


func _process(delta: float) -> void:
	if ghost:
		_ghost_update(delta)
	elif vr:
		_vr_update(delta)
	else:
		_flat_update(delta)
	for i in 4:
		flash[i] = maxf(0.0, flash[i] - delta * 4.0)
		top_mats[i].emission_energy_multiplier = 0.4 + flash[i] * 3.5
		pads[i].scale = Vector3.ONE * (1.0 + flash[i] * 0.12)
	_update_notes()
	if vr:
		_update_status()


func _vr_update(delta: float) -> void:
	if xr_origin.world_scale != 1.0:
		xr_origin.world_scale = 1.0
	_fit(delta)
	# Left stick: walk around the stage (relative to where you look, flattened). The kit comes along.
	var s := hand_l.get_vector2("primary")
	if s.length() > 0.2:
		var fwd := -xr_camera.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		var move := (right * s.x + fwd * s.y) * 1.6 * delta
		var head := xr_camera.global_position + move
		var hx := clampf(head.x, STAGE_LIMIT.position.x, STAGE_LIMIT.end.x)
		var hz := clampf(head.z, STAGE_LIMIT.position.y, STAGE_LIMIT.end.y)
		xr_origin.global_position += Vector3(hx - xr_camera.global_position.x, 0.0, hz - xr_camera.global_position.z)
	# Right stick: snap turn around the head.
	var r := hand_r.get_vector2("primary")
	if absf(r.x) > 0.7 and turn_ready:
		turn_ready = false
		var head := xr_camera.global_position
		var rot := Basis(Vector3.UP, -signf(r.x) * deg_to_rad(30.0))
		xr_origin.global_transform = Transform3D(rot * xr_origin.global_basis, head + rot * (xr_origin.global_position - head))
	elif absf(r.x) < 0.3:
		turn_ready = true
	var a := vr_a()
	if a and not a_was:
		recenter_kit()
		main.inst.chime(1.5)
	a_was = a
	# Walked away from the kit for a while: it glides back in front of you.
	var hp := xr_camera.global_position
	var rp := rig.global_position
	if Vector2(hp.x - rp.x, hp.z - rp.z).length() > 0.5:
		away_t += delta
		if away_t > 1.5:
			var tgt := Vector3(hp.x, rp.y, hp.z)
			rig.global_position = rp.lerp(tgt, 1.0 - exp(-4.0 * delta))
	else:
		away_t = 0.0
	tips[0] = hand_l.global_transform * Vector3(0, 0, -0.13)
	tips[1] = hand_r.global_transform * Vector3(0, 0, -0.13)
	_swing_check(delta)


## Fits the kit to the player a moment after starting (standing, sitting or a short kid), and again
## when the headset is clearly on a different head (height changed a lot for a few seconds).
func _fit(delta: float) -> void:
	var head := xr_camera.global_position
	if not fitted:
		fit_t -= delta
		if fit_t <= 0.0 and xr_camera.position != Vector3.ZERO:
			_do_fit()
		return
	if absf(head.y - fit_head) > 0.28:
		refit_t += delta
		if refit_t > 2.5:
			_refit_height()
	else:
		refit_t = 0.0


func _do_fit() -> void:
	fitted = true
	refit_t = 0.0
	# Face the crowd (-Z) and stand on the drum rug.
	var head := xr_camera.global_position
	var rot := Basis(Vector3.UP, -xr_camera.global_rotation.y)
	xr_origin.global_transform = Transform3D(rot * xr_origin.global_basis, head + rot * (xr_origin.global_position - head))
	head = xr_camera.global_position
	xr_origin.global_position += Vector3(main.DRUM_SPOT.x - head.x, 0.0, main.DRUM_SPOT.z - head.z)
	recenter_kit()
	print("VR: fitted the drums to head height %.2f m (kit scale %.2f)" % [fit_head - xr_origin.global_position.y, kit_s])


func _refit_height() -> void:
	refit_t = 0.0
	var head := xr_camera.global_position
	fit_head = head.y
	kit_s = clampf((head.y - xr_origin.global_position.y) / 1.55, 0.7, 1.15)
	rig.global_position.y = head.y
	_layout_kit()
	print("VR: new player height %.2f m - kit refitted (scale %.2f)" % [head.y - xr_origin.global_position.y, kit_s])


## A: the kit jumps back in front of you, facing where you look, at your height.
func recenter_kit() -> void:
	if not vr:
		return
	var head := xr_camera.global_position
	var yaw := xr_camera.global_rotation.y
	fit_head = head.y
	kit_s = clampf((head.y - xr_origin.global_position.y) / 1.55, 0.7, 1.15)
	rig.global_transform = Transform3D(Basis(Vector3.UP, yaw), head)
	_layout_kit()


## Hand speed + reaching a drum = a hit. A hand must leave a drum before it can play it again.
func _swing_check(delta: float) -> void:
	if not tips_ready:
		tips_ready = true
		prev_tips[0] = tips[0]
		prev_tips[1] = tips[1]
		return
	for h in 2:
		var tip := tips[h]
		var v := (tip - prev_tips[h]).length() / maxf(delta, 0.001)
		tip_speed[h] = lerpf(tip_speed[h], v, 0.6)
		prev_tips[h] = tip
		var bestp := -1
		var bd := 9.0
		for p in 4:
			var d := tip.distance_to(pads[p].global_position)
			if d > REARM_R:
				inside[h * 4 + p] = 0
			if d < bd:
				bd = d
				bestp = p
		if bestp >= 0 and bd < HIT_R and inside[h * 4 + bestp] == 0:
			inside[h * 4 + bestp] = 1
			if tip_speed[h] > MIN_SPEED:
				swings += 1
				main.drum_hit(bestp, maxf(tip_speed[h], 1.0))
				if vr:
					var hand: XRController3D = hand_l if h == 0 else hand_r
					hand.trigger_haptic_pulse("haptic", 0.0, 0.7, 0.06, 0.0)


# --- Flat ----------------------------------------------------------------------------

func attach_camera(cam: Camera3D) -> void:
	camera = cam
	camera.fov = 70.0


func _input(event: InputEvent) -> void:
	if vr or ghost or fake_vr or get_tree().paused:
		return
	var pad := -1
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and key_set == 0:
		match k.physical_keycode:
			KEY_A:
				pad = 0
			KEY_S:
				pad = 1
			KEY_D:
				pad = 2
			KEY_F:
				pad = 3
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and key_set == 0:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			pad = 1
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			pad = 2
	var jb := event as InputEventJoypadButton
	if jb and jb.pressed and joy >= 0 and jb.device == joy:
		match jb.button_index:
			JOY_BUTTON_X, JOY_BUTTON_LEFT_SHOULDER:
				pad = 0
			JOY_BUTTON_A, JOY_BUTTON_DPAD_DOWN:
				pad = 1
			JOY_BUTTON_B, JOY_BUTTON_DPAD_RIGHT:
				pad = 2
			JOY_BUTTON_Y, JOY_BUTTON_RIGHT_SHOULDER:
				pad = 3
	if pad >= 0:
		flat_hit(pad)


func flat_hit(pad: int) -> void:
	var h := 0 if pad <= 1 else 1
	hand_pad[h] = pad
	hand_anim[h] = 1.0
	swings += 1
	main.drum_hit(pad, 1.6)


func _flat_update(delta: float) -> void:
	if camera != null:
		var from := rig.to_global(Vector3(0.0, 0.6, 0.6))
		camera.global_transform = Transform3D(Basis(), from).looking_at(rig.to_global(Vector3(0.0, -0.4, -1.6)), Vector3.UP)
	var head := rig.global_position
	av_head.global_position = head
	var body := avatar.get_node("Body") as MeshInstance3D
	body.global_position = head + Vector3(0.0, -0.6, 0.05)
	if fake_vr:
		tips[0] = fake_tips[0]
		tips[1] = fake_tips[1]
		_swing_check(delta)
		for h in 2:
			av_hands[h].global_position = tips[h] + Vector3(0.0, 0.0, 0.12)
		return
	for h in 2:
		hand_anim[h] = maxf(0.0, hand_anim[h] - delta * 6.0)
		var rest := rig.to_global(Vector3(-0.2 if h == 0 else 0.2, -0.55, -0.12))
		var hit := pads[hand_pad[h]].global_position + Vector3(0.0, 0.03, 0.12)
		var k := sin(hand_anim[h] * PI * 0.5)
		av_hands[h].global_position = rest.lerp(hit, k)


# --- Notes and status ----------------------------------------------------------------

## Pooled balls flying down each drum's lane; a ring shrinks onto the drum as its next ball arrives.
func _update_notes() -> void:
	var g = main.song
	var used := 0
	var ring_dt: Array[float] = [99.0, 99.0, 99.0, 99.0]
	var playing: bool = main.state == "play"
	if g != null and playing:
		if cursor_serial != main.song_serial:
			cursor_serial = main.song_serial
			note_cursor = 0
		var st: float = main.song_t
		var travel: float = TRAVEL_BEATS * g.spb
		var n: int = g.d_t.size()
		while note_cursor < n and float(g.d_t[note_cursor]) < st - 0.4:
			note_cursor += 1
		var judged: PackedByteArray = main.d_judged
		var i := note_cursor
		while i < n and used < POOL:
			var tn: float = g.d_t[i]
			var dt := tn - st
			if dt > travel:
				break
			var j: int = judged[i] if i < judged.size() else 0
			i += 1
			if j == 1 or j == 2 or dt < -0.3:
				continue
			var pad: int = g.d_pad[i - 1]
			var m := notes[used]
			used += 1
			m.visible = true
			m.material_override = miss_mat if j == 3 else note_mats[pad]
			m.position = pads[pad].position + lane_dir(pad) * NOTE_TRAVEL * (dt / travel)
			var sc := 1.0 if dt > 0.0 else maxf(0.3, 1.0 + dt * 3.0)
			m.scale = Vector3.ONE * sc * (0.8 + 0.4 * kit_s)
			if j == 0 and dt >= -0.05 and dt < ring_dt[pad]:
				ring_dt[pad] = dt
		for p in 4:
			var win: float = 1.2 * g.spb
			var rd := ring_dt[p]
			approach[p].visible = rd < win
			if rd < win:
				approach[p].scale = Vector3.ONE * (1.0 + 1.8 * maxf(0.0, rd) / win)
	else:
		for p in 4:
			approach[p].visible = false
	for k in range(used, POOL):
		notes[k].visible = false


func _update_status() -> void:
	var crowd: float = main.crowd
	meter_fill.scale = Vector3(maxf(0.01, crowd), 1.0, 1.0)
	meter_fill.position.x = -0.185 * kit_s * (1.0 - crowd)
	meter_fill.scale.x *= kit_s
	var c := Color(1.0, 0.3, 0.3).lerp(Color(1.0, 0.9, 0.2), clampf(crowd * 2.0, 0.0, 1.0))
	if crowd > 0.5:
		c = Color(1.0, 0.9, 0.2).lerp(Color(0.3, 1.0, 0.4), (crowd - 0.5) * 2.0)
	meter_mat.albedo_color = c
	meter_mat.emission = c
	status_label.text = main.drummer_status(self)


func flash_pad(pad: int) -> void:
	if pad >= 0 and pad < 4:
		flash[pad] = 1.0


func record(q: int) -> void:
	if q < 2:
		hits += 1
		streak += 1
		miss_run = 0
	else:
		misses += 1
		streak = 0
		miss_run += 1


func reset_stats() -> void:
	hits = 0
	misses = 0
	streak = 0
	miss_run = 0
	swings = 0


## Player 1's continue button: VR trigger / A; flat: Space / Enter / controller A.
func action_pressed() -> bool:
	if vr:
		return vr_trigger() or vr_a()
	if joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_A):
		return true
	return key_set == 0 and Input.is_physical_key_pressed(KEY_SPACE)


# --- Networked co-op -----------------------------------------------------------------

func rig_transform() -> Transform3D:
	return rig.global_transform


func head_transform() -> Transform3D:
	if vr:
		return xr_camera.global_transform
	return Transform3D(Basis(), rig.global_position)


func tip(h: int) -> Vector3:
	if vr or fake_vr:
		return tips[h]
	return av_hands[h].global_position


## TV machine: the kit, head and sticks follow the host's snapshots.
func _ghost_update(delta: float) -> void:
	if net_rig == Transform3D():
		return
	var k := 1.0 - exp(-15.0 * delta)
	rig.global_transform = rig.global_transform.interpolate_with(net_rig.orthonormalized(), k)
	if absf(net_s - kit_s) > 0.005:
		kit_s = net_s
		_layout_kit()
	av_head.global_transform = av_head.global_transform.interpolate_with(net_head.orthonormalized(), k)
	var body := avatar.get_node("Body") as MeshInstance3D
	body.global_position = av_head.global_position + Vector3(0.0, -0.6, 0.05)
	for h in 2:
		av_hands[h].global_position = av_hands[h].global_position.lerp(net_tips[h] + Vector3(0.0, 0.0, 0.12), k)
