extends Node3D
## Player 1: the giant BUILDER standing over the floating course.
## VR (Steam Frame: only the sticks, the right trigger, A and controller positions reach the game):
##   XROrigin3D.world_scale = 8, so the course is a tabletop diorama (a block is 12.5 cm).
##   Right trigger near a block in your tray (low, in front of your right hip): pick it up. Move it over the
##   course (it snaps to the grid, green = OK) and let go to place it. Let go near the tray (or where
##   it can't go) to put it back. Trigger near a placed block picks it up again. A: turn the block.
##   Left stick: walk around the course. Right stick left/right: turn, up/down: raise/lower yourself.
##   Pull the trigger to start / continue on the banners.
## Flat fallback (split screen / no headset): a glove cursor over the course. Mouse or the builder's
##   controller left stick moves it; left click / RT / A places, right click / B removes; Q/E or
##   LB/RB (or 1-4) picks the block; mouse wheel / D-pad up-down raises the layer; R / Y turns it.
## TV (client): a ghost of the builder (big hard-hat head + glove) drawn from the host's snapshots.

const Art := preload("res://games/block_builders/art.gd")

const S := 8.0               # XR world scale: 8 units = 1 real metre
const EYE_ABOVE := 0.78      # metres between the builder's eyes and the course's base level
const VIEW_DIST := 0.85      # metres from the course's centre line to the builder's eyes
const GRAB_LOCAL := Vector3(0.0, -0.01, -0.07)  # grab point in controller space (metres)
const TRAY_GRAB := 0.7       # units
const BLOCK_GRAB := 0.8
## Where the tray sits relative to the head when the headset is fitted (metres: right, down, forward),
## for an adult; shrunk for shorter players (kids, sitting) so it stays within easy reach.
## Low (between belly and hip), forward and off to the right, so grabbing never brings the hand near
## the face (players slapped themselves when it sat at chest height, close in).
const TRAY_OFF := Vector3(0.28, -0.62, -0.38)
const TRAY_TILT := 14.0      # degrees: the far edge tilts up towards the eyes
const SLOT_GAP := 0.95       # units between tray slots
const BALLOON_GRAB := 1.0

var main
var index := 0
var color := Color(1.0, 0.8, 0.25)
var vr := false
var flat := false
var ghost := false
var remote := false
var active := true
var finished := false
var joy := -1
var mouse_on := false

var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var hand_l: XRController3D
var hand_r: XRController3D
var camera: Camera3D
var hud_label: Label
var hint_label: Label

# Shared visuals (world space)
var glove: MeshInstance3D
var held_vis: MeshInstance3D
var preview: MeshInstance3D
var preview_mat: StandardMaterial3D
var drop_line: MeshInstance3D
var head: Node3D
var tray: Node3D
var slot_samples: Array = []
var slot_pips: Array = []
var slot_holders: Array = []
var slot_on: Array = []        # per kind: shown in this level's tray?
var tray_level := -1
var tray_moving := false
var tray_off_t := 0.0
var arrow: MeshInstance3D
var took_this_level := false
var tray_k := 1.0

# State
var held_kind := ""
var held_rot := 0
var grab_point := Vector3.ZERO
var target := Vector3i.ZERO
var target_ok := false
var show_target := false
var hover_cell := Vector3i.ZERO
var hover_block := false
var trig_was := false
var a_was := false
var calibrated := false
var calib_t := 0.0
var height_adjust := 0.0
var snap_ready := true
var hover_slot := -1

# Flat
var cursor := Vector2(-6.0, 0.5)
var sel := 0
var layer_off := 0
var last_col := Vector2i(9999, 9999)
var mouse_delta := Vector2.ZERO
var wheel := 0
var place_was := false
var remove_was := false
var rot_was := false
var kind_was := false
var layer_was := false
var cam_x := -4.0

# Tests
var bot := false
var bot_cell := Vector3i.ZERO
var bot_kind := "plank"
var bot_place := false
var bot_trigger := false

# TV ghost state
var net_vr := false
var net_head := Transform3D()
var net_hand := Transform3D()


func _ready() -> void:
	add_to_group("builder")
	process_priority = 10  # after the XR controllers have their new poses
	_ensure_visuals()


func _ensure_visuals() -> void:
	if glove != null:
		return
	glove = MeshInstance3D.new()
	glove.mesh = Art.glove_mesh(color)
	glove.scale = Vector3.ONE * 1.3
	main.add_child(glove)
	held_vis = MeshInstance3D.new()
	held_vis.visible = false
	main.add_child(held_vis)
	preview = MeshInstance3D.new()
	preview_mat = StandardMaterial3D.new()
	preview_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	preview_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview_mat.albedo_color = Color(0.3, 1.0, 0.4, 0.45)
	preview.material_override = preview_mat
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	preview.visible = false
	main.add_child(preview)
	drop_line = MeshInstance3D.new()
	drop_line.mesh = Art.cyl(0.03, 0.03, 1.0, 6)
	drop_line.material_override = preview_mat
	drop_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drop_line.visible = false
	main.add_child(drop_line)


func setup_vr(origin: XROrigin3D, cam: XRCamera3D, left: XRController3D, right: XRController3D) -> void:
	vr = true
	xr_origin = origin
	xr_camera = cam
	hand_l = left
	hand_r = right
	origin.world_scale = S
	cam.near = 0.05 * S
	cam.far = 120.0 * S
	cam.cull_mask = 0xFFFFF & ~(Art.BODY_LAYER | Art.TV_LAYER)
	glove.reparent(right, false)  # drawn with the freshest controller pose
	glove.transform = Transform3D(Basis().scaled(Vector3.ONE * 1.3), Vector3(0, -0.02, 0.02) * S)
	_build_tray()
	# Until the headset reports a pose: stand at the course's near side.
	origin.global_position = Vector3(0.0, EYE_ABOVE * S - 1.6 * S, VIEW_DIST * S)


func setup_flat(cam: Camera3D, use_mouse: bool) -> void:
	flat = true
	mouse_on = use_mouse
	camera = cam
	camera.fov = 60.0
	camera.near = 0.1
	camera.far = 400.0
	camera.cull_mask = 0xFFFFF & ~Art.BODY_LAYER
	camera.global_position = Vector3(cam_x, 12.0, 12.5)
	camera.look_at(Vector3(cam_x, 0.0, -0.5), Vector3.UP)


func setup_ghost() -> void:
	ghost = true
	_ensure_head()


func _ensure_head() -> void:
	if head != null:
		return
	head = Node3D.new()
	main.add_child(head)
	var face := MeshInstance3D.new()
	face.mesh = Art.sphere(1.0, 16)
	face.material_override = Art.mat(Color(1.0, 0.82, 0.66), 0.0, 0.8)
	head.add_child(face)
	var eyes := MeshInstance3D.new()
	eyes.mesh = Art.box(Vector3(0.9, 0.22, 0.1))
	eyes.material_override = Art.mat(Color(0.1, 0.08, 0.1))
	eyes.position = Vector3(0, 0.15, -0.95)
	head.add_child(eyes)
	var smile := MeshInstance3D.new()
	smile.mesh = Art.box(Vector3(0.5, 0.1, 0.1))
	smile.material_override = Art.mat(Color(0.7, 0.2, 0.2))
	smile.position = Vector3(0, -0.4, -0.9)
	head.add_child(smile)
	var hat := MeshInstance3D.new()
	hat.mesh = Art.sphere(1.05, 14)
	hat.material_override = Art.mat(Color(1.0, 0.82, 0.1), 0.2, 0.4)
	hat.position = Vector3(0, 0.35, 0)
	hat.scale = Vector3(1.0, 0.7, 1.0)
	head.add_child(hat)
	var brim := MeshInstance3D.new()
	brim.mesh = Art.cyl(1.35, 1.35, 0.08, 16)
	brim.material_override = hat.material_override
	brim.position = Vector3(0, 0.35, -0.15)
	head.add_child(brim)
	_set_layers(head, Art.BODY_LAYER)
	head.visible = false


func _set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		node.layers = layers
	for c in node.get_children():
		_set_layers(c, layers)


# --- Tray (VR) ---------------------------------------------------------------------

func _build_tray() -> void:
	tray = Node3D.new()
	tray.name = "Tray"
	xr_origin.add_child(tray)
	var board := MeshInstance3D.new()
	board.mesh = Art.box(Vector3(3.9, 0.18, 1.5))
	board.material_override = Art.mat(Color(0.62, 0.42, 0.26))
	board.position.y = -0.09
	tray.add_child(board)
	var rim := MeshInstance3D.new()
	rim.mesh = Art.box(Vector3(4.0, 0.12, 0.12))
	rim.material_override = Art.mat(Color(1.0, 0.82, 0.25), 0.4)
	rim.position = Vector3(0, 0.02, 0.72)
	tray.add_child(rim)
	var pip_mesh := Art.box(Vector3(0.13, 0.13, 0.13))
	for i in Art.KINDS.size():
		var kind: String = Art.KINDS[i]
		var holder := Node3D.new()
		holder.position = Vector3(0.0, 0.0, -0.15)
		holder.visible = false
		tray.add_child(holder)
		slot_holders.append(holder)
		slot_on.append(false)
		var sample := MeshInstance3D.new()
		sample.mesh = Art.block_mesh(kind)
		sample.scale = Vector3.ONE * 0.6
		holder.add_child(sample)
		slot_samples.append(sample)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = false
		var pm: BoxMesh = pip_mesh.duplicate()
		pm.material = Art.mat(Art.KIND_COLORS[i], 0.6)
		mm.mesh = pm
		mm.instance_count = 16
		mm.visible_instance_count = 0
		for k in 16:
			var col := k % 4
			var row := k / 4
			mm.set_instance_transform(k, Transform3D(Basis(), Vector3(-0.27 + col * 0.18, 0.07 + row * 0.16, 0.55)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		holder.add_child(mmi)
		slot_pips.append(mmi)
	# A bouncing arrow over the tray until the builder has grabbed their first block of the level.
	arrow = MeshInstance3D.new()
	arrow.mesh = Art.cyl(0.0, 0.32, 0.5, 8)
	arrow.material_override = Art.mat(Color(1.0, 0.9, 0.2), 1.5)
	arrow.rotation.x = PI
	arrow.visible = false
	tray.add_child(arrow)
	layout_tray()


## Only the kinds this level uses get a slot, centred on the tray.
func layout_tray() -> void:
	if tray == null:
		return
	tray_level = main.level
	var d: Dictionary = main.level_data()
	var b: Dictionary = d.budget
	for i in Art.KINDS.size():
		slot_on[i] = int(b.get(Art.KINDS[i], 0)) > 0
	_relayout_on()
	took_this_level = false


func _relayout_on() -> void:
	var kinds: Array = []
	for i in Art.KINDS.size():
		if slot_on[i]:
			kinds.append(i)
	for i in Art.KINDS.size():
		var holder: Node3D = slot_holders[i]
		holder.visible = slot_on[i]
	for n in kinds.size():
		var i: int = kinds[n]
		var holder: Node3D = slot_holders[i]
		holder.position = Vector3((n - (kinds.size() - 1) * 0.5) * SLOT_GAP, 0.0, -0.15)


func _place_tray() -> void:
	if tray == null:
		return
	var local := xr_camera.transform
	var eye_h := local.origin.y / S
	tray_k = 0.9 if eye_h < 0.6 else clampf(eye_h / 1.55, 0.72, 1.0)
	var b := Basis(Vector3.UP, local.basis.get_euler().y)
	tray.transform = Transform3D(b * Basis(Vector3.RIGHT, deg_to_rad(TRAY_TILT)), local.origin + b * (TRAY_OFF * tray_k * S))
	tray_moving = false
	tray_off_t = 0.0


## If the builder walks (in the room) well away from the tray, it glides after them (same direction).
func _follow_tray(delta: float) -> void:
	if tray == null or not calibrated:
		return
	var local := xr_camera.transform
	var b := Basis(Vector3.UP, tray.transform.basis.get_euler().y)
	var want := local.origin + b * (TRAY_OFF * tray_k * S)
	var off := want - tray.transform.origin
	off.y = 0.0
	if not tray_moving:
		if off.length() > 0.4 * S and held_kind == "":
			tray_off_t += delta
			if tray_off_t > 1.2:
				tray_moving = true
		else:
			tray_off_t = 0.0
	if tray_moving:
		tray.transform.origin = tray.transform.origin.lerp(want, 1.0 - exp(-4.0 * delta))
		if tray.transform.origin.distance_to(want) < 0.03 * S:
			tray_moving = false
			tray_off_t = 0.0


func slot_world(i: int) -> Vector3:
	var holder: Node3D = slot_holders[i]
	return holder.global_transform * Vector3(0.0, 0.3, 0.0)


func _update_tray(delta: float) -> void:
	if tray == null:
		return
	if tray_level != main.level:
		layout_tray()
	for i in Art.KINDS.size():
		var n: int = main.budget.get(Art.KINDS[i], 0)
		if n > 0 and not slot_on[i]:
			slot_on[i] = true  # a gift brought a new kind: give it a slot
			_relayout_on()
		var sample: MeshInstance3D = slot_samples[i]
		sample.visible = n > 0
		var want := 0.6 * (1.25 + sin(Time.get_ticks_msec() * 0.008) * 0.06 if i == hover_slot else 1.0)
		sample.scale = sample.scale.lerp(Vector3.ONE * want, 1.0 - exp(-12.0 * delta))
		var mmi: MultiMeshInstance3D = slot_pips[i]
		mmi.multimesh.visible_instance_count = clampi(n, 0, 16)
	# The arrow points at the first full slot until the first block of the level is picked up
	# (and again whenever the builder hasn't built anything for a while).
	var show_arrow: bool = main.state == "play" and held_kind == "" and (not took_this_level or main.build_idle() > 25.0)
	var first := -1
	for i in Art.KINDS.size():
		if slot_on[i] and int(main.budget.get(Art.KINDS[i], 0)) > 0:
			first = i
			break
	arrow.visible = show_arrow and first >= 0
	if arrow.visible:
		var hp: Vector3 = (slot_holders[first] as Node3D).position
		arrow.position = hp + Vector3(0.0, 1.25 + absf(sin(Time.get_ticks_msec() * 0.006)) * 0.35, 0.0)


# --- Update -----------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not flat or not mouse_on or get_tree().paused:
		return
	var motion := event as InputEventMouseMotion
	if motion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_delta += motion.relative
	var mb := event as InputEventMouseButton
	if mb and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			wheel += 1
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			wheel -= 1


func _process(delta: float) -> void:
	if ghost:
		_ghost_update(delta)
		return
	if vr:
		_vr_update(delta)
	elif flat:
		_flat_update(delta)
	_update_visuals()


func _vr_update(delta: float) -> void:
	_vr_fit(delta)
	_vr_move(delta)
	_follow_tray(delta)
	grab_point = hand_r.global_transform * (GRAB_LOCAL * S)
	var trig := hand_r.get_float("trigger") > 0.6 or (bot and bot_trigger)
	var trig_up := hand_r.get_float("trigger") < 0.3 and not (bot and bot_trigger)
	var pressed := trig and not trig_was
	var a := hand_r.is_button_pressed("ax_button")
	var a_pressed := a and not a_was
	a_was = a
	if pressed:
		trig_was = true
	elif trig_up:
		trig_was = false
	if main.state != "play":
		if held_kind != "":
			_return_held()
		if pressed or a_pressed:
			main.confirm()
		show_target = false
		hover_slot = -1
		hover_block = false
		_update_tray(delta)
		return
	hover_slot = -1
	hover_block = false
	if held_kind == "" and main.balloon_state == 1 and grab_point.distance_to(main.balloon_pos) < BALLOON_GRAB:
		main.builder_grab_balloon()
		_haptic(0.6, 0.08)
	if held_kind == "":
		show_target = false
		for i in Art.KINDS.size():
			if slot_on[i] and main.budget.get(Art.KINDS[i], 0) > 0 and grab_point.distance_to(slot_world(i)) < TRAY_GRAB:
				hover_slot = i
		if hover_slot < 0:
			var c = _nearest_block(grab_point)
			if c != null:
				hover_block = true
				hover_cell = c
		if not has_meta("hover_was") or int(get_meta("hover_was")) != hover_slot + (100 if hover_block else 0):
			set_meta("hover_was", hover_slot + (100 if hover_block else 0))
			if hover_slot >= 0 or hover_block:
				_haptic(0.15, 0.02)
		if pressed:
			if hover_slot >= 0:
				var kind: String = Art.KINDS[hover_slot]
				if main.take(kind):
					held_kind = kind
					took_this_level = true
					_haptic(0.5, 0.06)
					main.local_sound("pickup", -6.0, 1.1)
			elif hover_block:
				var rot_before: int = main.course.block_rot(hover_cell)
				var kind: String = main.pick_up(hover_cell)
				if kind != "":
					held_kind = kind
					held_rot = rot_before
					_haptic(0.5, 0.06)
	else:
		target = Vector3i(floori(grab_point.x), floori(grab_point.y), floori(grab_point.z))
		var near_tray := grab_point.distance_to(tray.global_transform * Vector3(0, 0.3, 0)) < 2.2
		target_ok = not near_tray and main.can_place(held_kind, target)
		show_target = not near_tray
		if a_pressed:
			held_rot = (held_rot + 1) % 4
			_haptic(0.3, 0.03)
			main.local_sound("click", -8.0, 1.3)
		if not trig and trig_up:
			if target_ok:
				main.put(held_kind, target, held_rot)
				_haptic(0.9, 0.08)
				held_kind = ""
				show_target = false
			else:
				_return_held()
	_update_tray(delta)


func _nearest_block(p: Vector3):
	var best = null
	var bd := BLOCK_GRAB
	var base := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				var c := base + Vector3i(dx, dy, dz)
				if not main.course.has_block(c):
					continue
				var d := p.distance_to(Vector3(c.x + 0.5, c.y + 0.5, c.z + 0.5))
				if d < bd:
					bd = d
					best = c
	return best


func _return_held() -> void:
	if held_kind == "":
		return
	main.refund(held_kind, grab_point)
	held_kind = ""
	show_target = false


## Fit the course to whoever wears the headset: eyes EYE_ABOVE over the course, VIEW_DIST back from it.
## Re-fit (height only) when the head height changes a lot for a while (headset handed to someone else).
func _vr_fit(delta: float) -> void:
	calib_t += delta
	if not calibrated:
		if calib_t > 0.5 and xr_camera.position != Vector3.ZERO:
			calibrated = true
			_fit(true)
		return
	var hy := xr_camera.position.y
	if absf(hy - float(get_meta("calib_y", hy))) > 0.3 * S:
		set_meta("refit_t", float(get_meta("refit_t", 0.0)) + delta)
		if float(get_meta("refit_t", 0.0)) > 3.0:
			_fit(false)
			main.local_sound("pickup", -8.0, 0.7)
	else:
		set_meta("refit_t", 0.0)


func _fit(full: bool) -> void:
	set_meta("calib_y", xr_camera.position.y)
	set_meta("refit_t", 0.0)
	var local := xr_camera.transform
	if full:
		var head_yaw := local.basis.get_euler().y
		var basis := Basis(Vector3.UP, -head_yaw)
		var want := Vector3(0.0, (EYE_ABOVE + height_adjust) * S, VIEW_DIST * S)
		xr_origin.global_transform = Transform3D(basis, want - basis * local.origin)
	else:
		xr_origin.global_position.y += (EYE_ABOVE + height_adjust) * S - xr_camera.global_position.y
	_place_tray()


func _vr_move(delta: float) -> void:
	var mv := hand_l.get_vector2("primary")
	if mv.length() > 0.15:
		var fwd := -xr_camera.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		var step := (right * mv.x + fwd * mv.y) * 0.9 * S * delta
		var p := xr_origin.global_position + step
		var cam := xr_camera.global_position + step
		# Stay near the course.
		if cam.x > -16.0 and cam.x < 16.0 and cam.z > -10.0 and cam.z < 12.0:
			xr_origin.global_position = p
	var rs := hand_r.get_vector2("primary")
	if absf(rs.x) > 0.7 and snap_ready:
		snap_ready = false
		var pivot := xr_camera.global_position
		var rot := Basis(Vector3.UP, -signf(rs.x) * deg_to_rad(30.0))
		var xf := xr_origin.global_transform
		xf.origin = pivot + rot * (xf.origin - pivot)
		xf.basis = rot * xf.basis
		xr_origin.global_transform = xf
		main.local_sound("click", -12.0, 0.7)
	elif absf(rs.x) < 0.3:
		snap_ready = true
	if absf(rs.y) > 0.5 and absf(rs.x) < 0.5:
		var dy := rs.y * 0.35 * delta
		height_adjust = clampf(height_adjust + dy, -0.6, 0.8)
		xr_origin.global_position.y += dy * S


func _haptic(amp: float, dur: float) -> void:
	if vr and hand_r:
		hand_r.trigger_haptic_pulse("haptic", 0.0, amp, dur, 0.0)


## Flat builder: glove cursor over the course.
func _flat_update(delta: float) -> void:
	var place := false
	var remove := false
	var rot_p := false
	var kind_step := 0
	var layer_step := 0
	if bot:
		cursor = Vector2(bot_cell.x + 0.5, bot_cell.z + 0.5)
		sel = maxi(0, Art.KINDS.find(bot_kind))
		place = bot_place
		bot_place = false
	else:
		cursor += mouse_delta * 0.025
		if joy >= 0:
			var s := Vector2(Input.get_joy_axis(joy, JOY_AXIS_LEFT_X), Input.get_joy_axis(joy, JOY_AXIS_LEFT_Y))
			if s.length() > 0.2:
				cursor += s * 7.0 * delta
		cursor.x = clampf(cursor.x, -12.5, 12.5)
		cursor.y = clampf(cursor.y, -4.5, 3.5)
		var lmb := mouse_on and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		var rmb := mouse_on and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		var p_now: bool = lmb or _jb(JOY_BUTTON_A) or (joy >= 0 and Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_RIGHT) > 0.5)
		var r_now: bool = rmb or _jb(JOY_BUTTON_B) or (joy >= 0 and Input.get_joy_axis(joy, JOY_AXIS_TRIGGER_LEFT) > 0.5)
		place = p_now and not place_was
		remove = r_now and not remove_was
		place_was = p_now
		remove_was = r_now
		var ro: bool = (mouse_on and Input.is_physical_key_pressed(KEY_R)) or _jb(JOY_BUTTON_Y)
		rot_p = ro and not rot_was
		rot_was = ro
		var kn := 0
		if mouse_on and Input.is_physical_key_pressed(KEY_E) or _jb(JOY_BUTTON_RIGHT_SHOULDER):
			kn = 1
		elif mouse_on and Input.is_physical_key_pressed(KEY_Q) or _jb(JOY_BUTTON_LEFT_SHOULDER):
			kn = -1
		if kn != 0 and not kind_was:
			kind_step = kn
		kind_was = kn != 0
		if mouse_on:
			var num_keys: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4]
			for k in num_keys.size():
				if Input.is_physical_key_pressed(num_keys[k]):
					sel = k
		var ln := 0
		if _jb(JOY_BUTTON_DPAD_UP) or (mouse_on and Input.is_physical_key_pressed(KEY_X)):
			ln = 1
		elif _jb(JOY_BUTTON_DPAD_DOWN) or (mouse_on and Input.is_physical_key_pressed(KEY_Z)):
			ln = -1
		if ln != 0 and not layer_was:
			layer_step = ln
		layer_was = ln != 0
		layer_step += wheel
	mouse_delta = Vector2.ZERO
	wheel = 0
	if main.state != "play":
		show_target = false
		held_kind = ""
		grab_point = Vector3(cursor.x, 2.2, cursor.y)  # high fives at the flag still work
		if place:
			main.confirm()
		_flat_camera(delta)
		return
	if kind_step != 0:
		for n in Art.KINDS.size():
			sel = (sel + kind_step + Art.KINDS.size()) % Art.KINDS.size()
			if main.budget.get(Art.KINDS[sel], 0) > 0:
				break
		main.local_sound("click", -10.0, 1.0 + sel * 0.1)
	if rot_p:
		held_rot = (held_rot + 1) % 4
		main.local_sound("click", -10.0, 1.4)
	if main.balloon_state == 1 and Vector2(cursor.x - main.balloon_pos.x, cursor.y - main.balloon_pos.z).length() < 1.2:
		main.builder_grab_balloon()
	var col := Vector2i(floori(cursor.x), floori(cursor.y))
	if col != last_col:
		last_col = col
		layer_off = 0
	layer_off = clampi(layer_off + layer_step, -6, 8)
	var layer: int = bot_cell.y if bot else main.course.auto_layer(col.x, col.y) + layer_off
	target = Vector3i(col.x, layer, col.y)
	var kind: String = Art.KINDS[sel]
	held_kind = kind if main.budget.get(kind, 0) > 0 else ""
	target_ok = held_kind != "" and main.can_place(kind, target)
	show_target = true
	grab_point = Vector3(target.x + 0.5, target.y + 2.2, target.z + 0.5)
	if place and main.state_t < 0.3:
		place = false  # the click that started the level
	if place:
		if target_ok and main.take(kind):
			main.put(kind, target, held_rot)
		else:
			main.local_sound("hurt", -10.0, 1.5)
	if remove:
		var c := target
		if not main.course.has_block(c):
			c = Vector3i(9999, 0, 0)
			var layers: Array = main.course.columns.get(col, [])
			var best := -9999
			for y in layers:
				if int(y) > best:
					best = int(y)
			if best > -9999:
				c = Vector3i(col.x, best, col.y)
		if main.course.has_block(c):
			var k: String = main.pick_up(c)
			if k != "":
				main.refund(k, Vector3(c.x + 0.5, c.y + 0.5, c.z + 0.5))
	_flat_camera(delta)


func _jb(b: JoyButton) -> bool:
	return joy >= 0 and Input.is_joy_button_pressed(joy, b)


func _flat_camera(delta: float) -> void:
	if camera == null:
		return
	cam_x = lerpf(cam_x, clampf(cursor.x * 0.75, -6.0, 6.0), 1.0 - exp(-3.0 * delta))
	camera.global_position = Vector3(cam_x, 12.0, 12.5)
	camera.look_at(Vector3(cam_x, 0.0, -0.5), Vector3.UP)


## Glove, held block, placement preview (the same on every machine).
func _update_visuals() -> void:
	if glove == null:
		return
	if not vr:
		glove.visible = (flat and main.state != "intro" and main.state != "failed") or (ghost and net_hand != Transform3D())
		if flat:
			glove.global_transform = Transform3D(Basis(Vector3.RIGHT, -0.5).scaled(Vector3.ONE * 1.3), grab_point + Vector3(0, 0.3, 0.4))
		elif ghost:
			glove.global_transform = Transform3D(net_hand.basis.orthonormalized().scaled(Vector3.ONE * 1.3), net_hand.origin)
	var showing_held := held_kind != "" and (vr or (ghost and net_vr))
	held_vis.visible = showing_held
	if showing_held:
		var m := Art.block_mesh(held_kind)
		if held_vis.mesh != m:
			held_vis.mesh = m
		held_vis.global_transform = Transform3D(Basis(Vector3.UP, -held_rot * PI * 0.5).scaled(Vector3.ONE * 0.92),
			grab_point - Vector3(0, 0.46, 0))
	var show_prev := show_target and held_kind != ""
	if hover_block and held_kind == "" and (vr or (ghost and net_vr)):
		# Highlight the block the hand would pick up.
		var k: String = main.course.block_kind(hover_cell)
		if k != "":
			preview.mesh = Art.block_mesh(k)
			preview.global_transform = Transform3D(Basis().scaled(Vector3.ONE * 1.06), Vector3(hover_cell.x + 0.5, hover_cell.y - 0.03, hover_cell.z + 0.5))
			preview_mat.albedo_color = Color(1.0, 0.95, 0.3, 0.45)
			drop_line.visible = false
			preview.visible = true
			return
	preview.visible = show_prev
	if not show_prev:
		drop_line.visible = false
		return
	preview.mesh = Art.block_mesh(held_kind)
	preview.global_transform = Transform3D(Basis(Vector3.UP, -held_rot * PI * 0.5).scaled(Vector3.ONE * 1.02),
		Vector3(target.x + 0.5, target.y - 0.01, target.z + 0.5))
	var pulse := 0.4 + sin(Time.get_ticks_msec() * 0.01) * 0.1
	preview_mat.albedo_color = Color(0.3, 1.0, 0.45, pulse) if target_ok else Color(1.0, 0.25, 0.2, pulse)
	# A thin line down to whatever is below the block, for depth.
	var below: float = main.course.surface_below(target.x + 0.5, target.z + 0.5, float(target.y), 0.05)
	if below < -20.0:
		below = float(target.y) - 6.0
	var h := float(target.y) - below
	drop_line.visible = h > 0.05
	if drop_line.visible:
		drop_line.global_transform = Transform3D(Basis().scaled(Vector3(1.0, h, 1.0)), Vector3(target.x + 0.5, below + h * 0.5, target.z + 0.5))


# --- Network -----------------------------------------------------------------------

func head_transform() -> Transform3D:
	if vr:
		return xr_camera.global_transform
	return Transform3D()


func hand_transform() -> Transform3D:
	if vr:
		return glove.global_transform.orthonormalized()
	if flat and glove.visible:
		return glove.global_transform.orthonormalized()
	return Transform3D()


func net_state() -> Array:
	return [vr, head_transform(), hand_transform(), held_kind, held_rot, Vector3(target), target_ok, show_target,
		grab_point, hover_block, Vector3(hover_cell)]


func apply_net_state(st: Array) -> void:
	if st.size() < 11:
		return
	net_vr = st[0]
	net_head = st[1]
	net_hand = st[2]
	held_kind = st[3]
	held_rot = st[4]
	var t: Vector3 = st[5]
	target = Vector3i(roundi(t.x), roundi(t.y), roundi(t.z))
	target_ok = st[6]
	show_target = st[7]
	grab_point = st[8]
	hover_block = st[9]
	var hc: Vector3 = st[10]
	hover_cell = Vector3i(roundi(hc.x), roundi(hc.y), roundi(hc.z))


func apply_remote_state(_pos: Vector3, _yaw: float, _pitch: float) -> void:
	pass


func _ghost_update(delta: float) -> void:
	if head != null:
		head.visible = net_vr and net_head != Transform3D()
		if head.visible:
			var k := 1.0 - exp(-20.0 * delta)
			var want := Transform3D(net_head.basis.orthonormalized(), net_head.origin)
			head.global_transform = head.global_transform.interpolate_with(want, k)
	_update_visuals()
