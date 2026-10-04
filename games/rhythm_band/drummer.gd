extends Node3D
## Player 1: the DRUMMER. Four floating drums (hi-hat, snare, tom, crash) hang around them; glowing
## balls fly down a lane into each drum and a shrinking ring shows when to hit. GOLD balls are star
## notes: they charge STAR POWER, and the CRASH sets it off when it's ready.
## VR (Steam Frame): swing either hand into a drum (the glowing stick tip) - hand speed + being at the
## drum = a hit; no buttons. Left stick: walk around the stage (the kit comes along). Right stick:
## snap turn. A: bring the kit back in front of you. The kit fits your height at the start and again
## when someone shorter or taller takes the headset (it is measured from your head, not a rest pose).
## In the SETLIST menu the drums are buttons: hi-hat EASY, snare NORMAL, tom ROCK, crash START.
## The crowd meter, star meter and combo float far ahead between the lanes (easy to focus on, never in
## a ball's way); short messages float above them (main.gd).
## Flat (split screen / non-VR host): A S D F or mouse left/right; controller X A B Y (or LB / RB).
## Bot "fake VR": the bot moves fake_tips and the same swing detection as VR runs.
## On the TV machine this is a ghost: the kit, a head and two sticks drawn from the host's snapshots.

const MeshKit := preload("res://games/rhythm_band/mesh_kit.gd")

const HIT_R := 0.13  # metres from the stick tip to a drum's centre
const REARM_R := 0.17
const MIN_SPEED := 0.45  # m/s: resting a hand on a drum doesn't play it
const PAD_OFFSETS: Array[Vector3] = [Vector3(-0.36, -0.36, -0.30), Vector3(-0.16, -0.50, -0.38),
	Vector3(0.16, -0.50, -0.38), Vector3(0.36, -0.34, -0.30)]
const PAD_COLORS: Array[Color] = [Color(1.0, 0.85, 0.2), Color(1.0, 0.3, 0.35), Color(0.3, 0.6, 1.0), Color(0.35, 0.95, 0.45)]
const PAD_NAMES: Array[String] = ["HI-HAT", "SNARE", "TOM", "CRASH"]
const MENU_NAMES: Array[String] = ["EASY", "NORMAL", "ROCK", "START!"]
const GOLD := Color(1.0, 0.82, 0.25)
const NOTE_TRAVEL := 2.6
const POOL := 24
const FLAT_HEAD := 1.45
const DASH := Vector3(0.0, 0.0, -2.4)  # the crowd meter / combo panel, kit-relative (between the lanes)
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
var lane_tags: Array[Label3D] = []
var flash := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var notes_mm: MultiMesh
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
var av_body: MeshInstance3D
var av_hands: Array[MeshInstance3D] = []
var dash: Node3D
var status_label: Label3D
var meter_fill: MeshInstance3D
var meter_mat: StandardMaterial3D
var star_fill: MeshInstance3D
var star_mat: StandardMaterial3D

var fitted := false
var fit_t := 0.8
var fit_head := 0.0
var refit_t := 0.0
var away_t := 0.0
var a_was := false
var trig_was := false
var trig_block := false
var turn_ready := true

var hits := 0
var misses := 0
var streak := 0
var miss_run := 0
var swings := 0
var tour := {}  # tour stats: hits, misses, perfects, best_streak, stars

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
	reset_tour()
	_build_rig()
	_build_avatar()


# --- Building ------------------------------------------------------------------------

func _pad_mesh(i: int) -> ArrayMesh:
	var cym := i == 0 or i == 3
	var parts: Array = []
	if cym:
		var brass := Color(0.9, 0.72, 0.3)
		parts.append([MeshKit.cyl(0.14, 0.14, 0.012, 20), MeshKit.at(Vector3.ZERO), brass])
		parts.append([MeshKit.sphere(0.03, 10), MeshKit.at(Vector3(0, 0.008, 0), Vector3(1, 0.5, 1)), brass.lightened(0.2)])
	else:
		var shell := Color(0.85, 0.15, 0.25) if i == 1 else Color(0.2, 0.35, 0.85)
		parts.append([MeshKit.cyl(0.12, 0.12, 0.08, 20), MeshKit.at(Vector3.ZERO), shell])
		parts.append([MeshKit.cyl(0.125, 0.125, 0.012, 20), MeshKit.at(Vector3(0, 0.036, 0)), Color(0.85, 0.85, 0.9)])
		parts.append([MeshKit.cyl(0.125, 0.125, 0.012, 20), MeshKit.at(Vector3(0, -0.036, 0)), Color(0.85, 0.85, 0.9)])
		for k in 6:
			var a := TAU * k / 6.0
			parts.append([MeshKit.box(Vector3(0.015, 0.05, 0.015)), MeshKit.at(Vector3(cos(a) * 0.123, 0, sin(a) * 0.123)), Color(0.9, 0.9, 0.95)])
	return MeshKit.merge(parts)


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
	for i in 4:
		var cym := i == 0 or i == 3
		var pad := Node3D.new()
		rig.add_child(pad)
		var r := 0.14 if cym else 0.12
		var h := 0.02 if cym else 0.08
		var body := MeshInstance3D.new()
		body.mesh = _pad_mesh(i)
		body.material_override = MeshKit.vertex_material(main.mats)
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
		# Far labels at the start of each lane (VR menu: what each drum chooses).
		var lt := Label3D.new()
		lt.font_size = 48
		lt.pixel_size = 0.0034
		lt.outline_size = 16
		lt.modulate = PAD_COLORS[i]
		lt.visible = false
		rig.add_child(lt)
		lane_tags.append(lt)
	notes_mm = MultiMesh.new()
	notes_mm.transform_format = MultiMesh.TRANSFORM_3D
	notes_mm.use_colors = true
	notes_mm.mesh = main.sphere_mesh(0.05)
	notes_mm.instance_count = POOL
	notes_mm.visible_instance_count = 0
	var nmi := MultiMeshInstance3D.new()
	nmi.multimesh = notes_mm
	var nm := StandardMaterial3D.new()
	nm.vertex_color_use_as_albedo = true
	nm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	nmi.material_override = nm
	nmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(nmi)
	# The dashboard (VR): crowd meter, star meter and combo, far ahead between the lanes.
	dash = Node3D.new()
	rig.add_child(dash)
	status_label = Label3D.new()
	status_label.font_size = 40
	status_label.pixel_size = 0.0032
	status_label.outline_size = 14
	status_label.position = Vector3(0, 0.1, 0)
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	dash.add_child(status_label)
	var back := MeshInstance3D.new()
	back.mesh = main.box_mesh(Vector3(0.62, 0.07, 0.02))
	back.material_override = main.make_material(Color(0.1, 0.1, 0.12), 0.0)
	back.position = Vector3(0, 0.04, -0.01)
	dash.add_child(back)
	meter_fill = MeshInstance3D.new()
	meter_fill.mesh = main.box_mesh(Vector3(0.6, 0.05, 0.02))
	meter_mat = StandardMaterial3D.new()
	meter_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	meter_fill.material_override = meter_mat
	dash.add_child(meter_fill)
	var sback := MeshInstance3D.new()
	sback.mesh = main.box_mesh(Vector3(0.62, 0.035, 0.02))
	sback.material_override = main.make_material(Color(0.1, 0.1, 0.12), 0.0)
	sback.position = Vector3(0, -0.03, -0.01)
	dash.add_child(sback)
	star_fill = MeshInstance3D.new()
	star_fill.mesh = main.box_mesh(Vector3(0.6, 0.022, 0.02))
	star_mat = StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.albedo_color = GOLD
	star_fill.material_override = star_mat
	dash.add_child(star_fill)
	dash.visible = false
	_layout_kit()


## Puts the drums, lanes, lane labels and the dashboard where they belong for this player's size.
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
		lane_tags[i].position = p + dir * NOTE_TRAVEL + Vector3(0, 0.16, 0)
	dash.position = DASH  # not scaled: always far enough to focus on, and clear of the lanes


func lane_dir(i: int) -> Vector3:
	return Vector3(PAD_OFFSETS[i].x * 1.4, 0.45, -1.0).normalized()


## The drummer as the TV sees them (flat / ghost): one merged body, a head with headphones, hands
## with sticks.
func _build_avatar() -> void:
	avatar = Node3D.new()
	main.add_child(avatar)
	av_head = Node3D.new()
	avatar.add_child(av_head)
	var skin := Color(1.0, 0.82, 0.65)
	var hparts: Array = [
		[MeshKit.sphere(0.15, 14), MeshKit.at(Vector3.ZERO), skin],
		[MeshKit.sphere(0.155, 12), MeshKit.at(Vector3(0, 0.05, 0.03), Vector3(1.05, 0.8, 1.05)), Color(0.3, 0.18, 0.08)],
		[MeshKit.box(Vector3(0.22, 0.06, 0.05)), MeshKit.at(Vector3(0, 0.02, -0.13)), Color(0.15, 0.15, 0.2)],
		[MeshKit.cyl(0.05, 0.05, 0.05, 10), MeshKit.at(Vector3(-0.15, 0, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(1.0, 0.3, 0.4)],
		[MeshKit.cyl(0.05, 0.05, 0.05, 10), MeshKit.at(Vector3(0.15, 0, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(1.0, 0.3, 0.4)],
		[MeshKit.box(Vector3(0.32, 0.025, 0.04)), MeshKit.at(Vector3(0, 0.16, 0)), Color(0.2, 0.2, 0.25)],
	]
	var face := MeshInstance3D.new()
	face.mesh = MeshKit.merge(hparts)
	face.material_override = MeshKit.vertex_material(main.mats)
	av_head.add_child(face)
	var bparts: Array = [
		[MeshKit.cyl(0.18, 0.21, 0.55, 10), MeshKit.at(Vector3(0, 0.0, 0)), Color(1.0, 0.85, 0.55)],
		[MeshKit.box(Vector3(0.3, 0.08, 0.3)), MeshKit.at(Vector3(0, 0.2, 0)), Color(0.2, 0.2, 0.25)],
		[MeshKit.cyl(0.07, 0.065, 0.5, 8), MeshKit.at(Vector3(-0.09, -0.5, 0)), Color(0.15, 0.15, 0.2)],
		[MeshKit.cyl(0.07, 0.065, 0.5, 8), MeshKit.at(Vector3(0.09, -0.5, 0)), Color(0.15, 0.15, 0.2)],
	]
	av_body = MeshInstance3D.new()
	av_body.mesh = MeshKit.merge(bparts)
	av_body.material_override = MeshKit.vertex_material(main.mats)
	av_body.name = "Body"
	avatar.add_child(av_body)
	var sparts: Array = [
		[MeshKit.sphere(0.04, 8), MeshKit.at(Vector3.ZERO), skin],
		[MeshKit.cyl(0.01, 0.012, 0.3, 6), MeshKit.at(Vector3(0, 0, -0.12), Vector3.ONE, Vector3(-PI * 0.5, 0, 0)), Color(0.95, 0.85, 0.6)],
		[MeshKit.sphere(0.016, 6), MeshKit.at(Vector3(0, 0, -0.27)), Color(1.0, 1.0, 0.85)],
	]
	var hand_mesh := MeshKit.merge(sparts)
	for h in 2:
		var hand := MeshInstance3D.new()
		hand.mesh = hand_mesh
		hand.material_override = MeshKit.vertex_material(main.mats)
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
	dash.visible = true
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
	return vr and hand_r.get_float("trigger") > 0.6 and not trig_block


func vr_a() -> bool:
	return vr and hand_r.is_button_pressed("ax_button")


func _process(delta: float) -> void:
	if ghost:
		_ghost_update(delta)
	elif vr:
		_vr_update(delta)
	else:
		_flat_update(delta)
	var star_on: bool = main.star_active()
	for i in 4:
		flash[i] = maxf(0.0, flash[i] - delta * 4.0)
		top_mats[i].emission_energy_multiplier = 0.4 + flash[i] * 3.5 + (0.6 if star_on else 0.0)
		top_mats[i].emission = GOLD if star_on and i == 3 and main.star_ready() else (PAD_COLORS[i].lerp(GOLD, 0.6) if star_on else PAD_COLORS[i])
		pads[i].scale = Vector3.ONE * (1.0 + flash[i] * 0.12)
	_update_notes()
	_update_tags()
	if vr:
		_update_status()


func _vr_update(delta: float) -> void:
	if xr_origin.world_scale != 1.0:
		xr_origin.world_scale = 1.0
	if trig_block and hand_r.get_float("trigger") < 0.3:
		trig_block = false
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
	av_body.global_position = head + Vector3(0.0, -0.55, 0.05)
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

## Balls flying down each drum's lane (one MultiMesh); a ring shrinks onto the drum as its next ball
## arrives. Gold = star note; notes above the drummer's level aren't shown.
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
		var travel: float = main.drum_travel_beats() * g.spb
		var n: int = g.d_t.size()
		while note_cursor < n and float(g.d_t[note_cursor]) < st - 0.4:
			note_cursor += 1
		var judged: PackedByteArray = main.d_judged
		var star_on: bool = main.star_active()
		var i := note_cursor
		while i < n and used < POOL:
			var tn: float = g.d_t[i]
			var dt := tn - st
			if dt > travel:
				break
			var j: int = judged[i] if i < judged.size() else 0
			i += 1
			if j == 1 or j == 2 or j == 4 or dt < -0.3:
				continue
			var pad: int = g.d_pad[i - 1]
			var gold: bool = g.d_star[i - 1] == 1
			var col := Color(0.35, 0.35, 0.4) if j == 3 else (GOLD if gold or star_on else PAD_COLORS[pad])
			var pos := pads[pad].position + lane_dir(pad) * NOTE_TRAVEL * (dt / travel)
			var sc := (1.0 if dt > 0.0 else maxf(0.3, 1.0 + dt * 3.0)) * (0.8 + 0.4 * kit_s) * (1.25 if gold else 1.0)
			notes_mm.set_instance_transform(used, Transform3D(Basis().scaled(Vector3.ONE * sc), pos))
			notes_mm.set_instance_color(used, col)
			used += 1
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
	notes_mm.visible_instance_count = used


## In the SETLIST menu the drums are buttons: their lane labels say what they pick.
func _update_tags() -> void:
	var menu: bool = main.state == "menu"
	for i in 4:
		var lt := lane_tags[i]
		lt.visible = menu and (vr or fake_vr)
		if lt.visible:
			lt.text = MENU_NAMES[i]
			var chosen: bool = i < 3 and int(main.drum_level) == i
			lt.modulate = PAD_COLORS[i].lightened(0.4) if chosen else PAD_COLORS[i]
			lt.text = ("> %s <" % MENU_NAMES[i]) if chosen else MENU_NAMES[i]
		if not vr:
			flat_tags[i].text = MENU_NAMES[i] if menu else PAD_NAMES[i]


func _update_status() -> void:
	var crowd: float = main.crowd
	meter_fill.scale = Vector3(maxf(0.01, crowd), 1.0, 1.0)
	meter_fill.position = Vector3(-0.3 * (1.0 - crowd), 0.04, 0.0)
	var c := Color(1.0, 0.3, 0.3).lerp(Color(1.0, 0.9, 0.2), clampf(crowd * 2.0, 0.0, 1.0))
	if crowd > 0.5:
		c = Color(1.0, 0.9, 0.2).lerp(Color(0.3, 1.0, 0.4), (crowd - 0.5) * 2.0)
	meter_mat.albedo_color = c
	var sm: float = main.star_meter_value()
	star_fill.scale = Vector3(maxf(0.01, sm), 1.0, 1.0)
	star_fill.position = Vector3(-0.3 * (1.0 - sm), -0.03, 0.0)
	star_mat.albedo_color = GOLD.lightened(0.4 * absf(sin(Time.get_ticks_msec() * 0.008))) if main.star_ready() or main.star_active() else GOLD.darkened(0.2)
	status_label.text = main.drummer_status(self)


func flash_pad(pad: int) -> void:
	if pad >= 0 and pad < 4:
		flash[pad] = 1.0


func record(q: int, star: bool = false) -> void:
	if q < 2:
		hits += 1
		streak += 1
		miss_run = 0
		tour["hits"] = int(tour["hits"]) + 1
		if q == 0:
			tour["perfects"] = int(tour["perfects"]) + 1
		if star:
			tour["stars"] = int(tour["stars"]) + 1
		tour["best_streak"] = maxi(int(tour["best_streak"]), streak)
	else:
		misses += 1
		streak = 0
		miss_run += 1
		tour["misses"] = int(tour["misses"]) + 1


func reset_stats() -> void:
	hits = 0
	misses = 0
	streak = 0
	miss_run = 0
	swings = 0


func reset_tour() -> void:
	tour = {"hits": 0, "misses": 0, "perfects": 0, "best_streak": 0, "stars": 0}


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
	av_body.global_position = av_head.global_position + Vector3(0.0, -0.55, 0.05)
	for h in 2:
		av_hands[h].global_position = av_hands[h].global_position.lerp(net_tips[h] + Vector3(0.0, 0.0, 0.12), k)
