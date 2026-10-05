extends Node3D
## The VR driver's seat in kart 0 (players[0]).
## Steering wheel: hold it with both hands (no buttons: a hand near the rim is holding it). The wheel
## turns with your hands RELATIVE TO HOW YOU GRABBED IT: two hands use the line between them, one hand
## its angle around the wheel centre, and whenever a hand lets go or grabs again the wheel carries on
## from where it is (no fixed "rest pose" anywhere). No hands: it springs back to straight (the left
## stick steers too). Right trigger = accelerate, left stick up/down = drive/brake-reverse, A = use your
## item (or the boost when the meter on the wheel is full). Right stick up/down raises or lowers your seat.
## A hard turn held round a bend charges drift sparks; straighten up for a mini-turbo (not in main.SIMPLE_MODE,
## which also hides the boost meter and shows see-through ghost mittens turning the wheel when nobody holds it).
## Comfort: the seat is a stable frame (yaw only: no roll or pitch of the view; height eased over bumps
## and ramps with a speed cap), and the wheel, dash and mittens ride in that same frame so they never
## jump at your face. Soft vignette on boosts, spins and teleports. The seat fits your head height
## (sitting kids too) and re-fits when the headset is handed to someone taller or shorter.
## Readable info sits on two panels about 2.4 m ahead, low left and right (kart-locked, not on your
## head), plus big hints in the middle; the dash near the wheel only has pictures (speed, item).
## `fake` = test mode without a headset: the bot puts the hands (seat-local) where it wants.

const EYE := Vector3(0.0, 1.12, 0.32)  # kart-local eye point when seated
const WHEEL_OFF := Vector3(0.0, -0.38, -0.36)  # wheel centre relative to the eyes (an easy reach for kids)
const WHEEL_R := 0.19
const WHEEL_TILT := 55.0  # degrees: rim faces the driver and up
const HOLD_IN := 0.05  # a hand counts as holding anywhere from here...
const HOLD_OUT := 0.36  # ...to here from the centre (generous: kids hold it all sorts of ways)
const HOLD_DEPTH := 0.22
const FULL_LOCK := 1.5  # radians of wheel turn for full steering
const FRAME_VY := 3.0  # m/s: the most the seat frame moves up or down (ramps and bumps stay gentle)
const PANEL_OFF := Vector3(0.78, -0.6, -2.3)  # text panels, relative to the eyes
const VIGNETTE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, depth_test_disabled, blend_mix;
uniform float strength = 0.0;
varying vec3 lp;
void vertex() {
	lp = VERTEX;
}
void fragment() {
	vec3 d = normalize(lp);
	float edge = 1.0 - smoothstep(0.35, 0.85, -d.z);
	ALBEDO = vec3(0.03, 0.02, 0.06);
	ALPHA = clamp(edge * strength + max(strength - 0.9, 0.0) * 9.0, 0.0, 0.95);
}
"""

var main
var kart
var fake := false
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var hand_l: XRController3D
var hand_r: XRController3D

var fitted := false
var fit_t := 0.7
var fit_xf := Transform3D()
var fit_head_y := 0.0
var refit_t := 0.0
var seat_adj := 0.0
var frame_y := 0.0
var frame_init := false

var wheel_angle := 0.0  # current wheel turn (radians, + = turned left / anticlockwise)
var held_l := false
var held_r := false
var grip := ""  # which hands hold the wheel: "", "L", "R", "LR"
var grip_offset := 0.0
var grip_raw := 0.0  # last measured hand angle (for unwrapping)
var grip_acc := 0.0  # unwrapped hand angle
var unheld_t := 0.0
var a_was := false
var vignette_k := 0.0
var fade_k := 0.0

# Fake VR (tests): seat-local hand positions and buttons.
var fake_l := Vector3.ZERO
var fake_r := Vector3.ZERO
var fake_trigger := 0.0
var fake_a := false
var fake_stick := Vector2.ZERO

var seat: Node3D  # the stable seat frame (yaw only, eased height): wheel, dash, panels and mittens
var wheel_root: Node3D  # seat-local, at the wheel centre, tilted
var wheel_spin: Node3D
var hub_bar: MeshInstance3D
var hub_bar_mat: StandardMaterial3D
var grip_mat: StandardMaterial3D
var needle: Node3D
var item_icon: Node3D
var icon_item := "-"
var panel_l: Label3D
var panel_r: Label3D
var panel_hint: Label3D
var mitten_l: MeshInstance3D
var mitten_r: MeshInstance3D
var ghost_l: MeshInstance3D  # simple mode: see-through mittens that show how to turn the wheel
var ghost_r: MeshInstance3D
var ghost_mat: StandardMaterial3D
var vignette: MeshInstance3D
var vignette_mat: ShaderMaterial


func setup(k, origin: XROrigin3D, cam: XRCamera3D, left: XRController3D, right: XRController3D) -> void:
	kart = k
	xr_origin = origin
	xr_camera = cam
	hand_l = left
	hand_r = right
	fake = origin == null
	kart.cockpit = self
	kart.set_first_person(not fake)
	seat = Node3D.new()
	seat.name = "Seat"
	seat.top_level = true
	kart.add_child(seat)
	_place_seat(0.0)
	_build_wheel()
	_build_dash()
	_build_panels()
	if not fake:
		cam.near = 0.03
		cam.far = 600.0
		_build_vignette(cam)
	mitten_l = _mitten()
	mitten_r = _mitten()
	if main.SIMPLE_MODE:
		hub_bar.visible = false  # no boost meter
		_build_ghost_hands()
	kart.sparks.position = Vector3(0, 0.12, -0.6)  # by the front wheels, where the rider can see them


func _mitten() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = main.sphere_mesh(0.045)
	m.material_override = main.make_material(Color(1.0, 0.85, 0.35), 0.2)
	m.scale = Vector3(0.9, 0.75, 1.3)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	seat.add_child(m)
	return m


func wheel_center() -> Vector3:
	return EYE + WHEEL_OFF


func wheel_basis() -> Basis:
	return Basis(Vector3.RIGHT, deg_to_rad(WHEEL_TILT))


func _build_wheel() -> void:
	wheel_root = Node3D.new()
	seat.add_child(wheel_root)
	wheel_root.position = wheel_center()
	wheel_root.basis = wheel_basis()
	wheel_spin = Node3D.new()
	wheel_root.add_child(wheel_spin)
	var rim := MeshInstance3D.new()
	rim.mesh = main.torus_mesh(WHEEL_R - 0.025, WHEEL_R + 0.025)
	rim.material_override = main.make_material(Color(0.15, 0.15, 0.2), 0.0)
	wheel_spin.add_child(rim)
	# Grips at 9 and 3 o'clock (they glow in the drift-spark colour), a top marker, and spokes.
	grip_mat = StandardMaterial3D.new()
	grip_mat.albedo_color = kart.color
	grip_mat.emission_enabled = true
	grip_mat.emission = kart.color
	grip_mat.emission_energy_multiplier = 0.3
	for x in [-1.0, 1.0]:
		var g := MeshInstance3D.new()
		g.mesh = main.box_mesh(Vector3(0.06, 0.07, 0.1))
		g.material_override = grip_mat
		g.position = Vector3(float(x) * WHEEL_R, 0, 0)
		wheel_spin.add_child(g)
		var spoke := MeshInstance3D.new()
		spoke.mesh = main.box_mesh(Vector3(WHEEL_R, 0.02, 0.03))
		spoke.material_override = rim.material_override
		spoke.position = Vector3(float(x) * WHEEL_R * 0.5, 0, 0)
		wheel_spin.add_child(spoke)
	var top := MeshInstance3D.new()
	top.mesh = main.box_mesh(Vector3(0.04, 0.06, 0.06))
	top.material_override = main.make_material(Color(1.0, 0.9, 0.2), 1.0)
	top.position = Vector3(0, 0, -WHEEL_R)
	wheel_spin.add_child(top)
	var hub := MeshInstance3D.new()
	hub.mesh = main.cyl_mesh(0.06, 0.06, 0.04, 14)
	hub.material_override = main.make_material(Color(0.95, 0.95, 1.0), 0.0)
	wheel_spin.add_child(hub)
	# Boost meter on the hub: grows with the charge, glows when it's ready.
	hub_bar_mat = StandardMaterial3D.new()
	hub_bar_mat.albedo_color = Color(0.3, 0.8, 1.0)
	hub_bar_mat.emission_enabled = true
	hub_bar_mat.emission = Color(0.3, 0.8, 1.0)
	hub_bar = MeshInstance3D.new()
	hub_bar.mesh = main.box_mesh(Vector3(0.1, 0.012, 0.03))
	hub_bar.material_override = hub_bar_mat
	hub_bar.position = Vector3(0, 0.025, 0)
	wheel_spin.add_child(hub_bar)


## A low dashboard behind the wheel with pictures only: a speedometer and your item.
func _build_dash() -> void:
	var dash := Node3D.new()
	seat.add_child(dash)
	dash.position = wheel_center() + Vector3(0, 0.04, -0.2)
	dash.rotation.x = deg_to_rad(35.0)
	var panel := MeshInstance3D.new()
	panel.mesh = main.box_mesh(Vector3(0.56, 0.02, 0.16))
	panel.material_override = main.make_material(Color(0.08, 0.08, 0.12), 0.0)
	dash.add_child(panel)
	var face := MeshInstance3D.new()
	face.mesh = main.cyl_mesh(0.065, 0.065, 0.01, 18)
	face.material_override = main.make_material(Color(0.95, 0.95, 0.85), 0.3)
	face.position = Vector3(-0.17, 0.012, 0)
	dash.add_child(face)
	needle = Node3D.new()
	needle.position = Vector3(-0.17, 0.02, 0)
	dash.add_child(needle)
	var nm := MeshInstance3D.new()
	nm.mesh = main.box_mesh(Vector3(0.006, 0.006, 0.055))
	nm.material_override = main.make_material(Color(1.0, 0.2, 0.15), 1.0)
	nm.position = Vector3(0, 0, -0.026)
	needle.add_child(nm)
	item_icon = Node3D.new()
	item_icon.position = Vector3(0.17, 0.05, 0)
	dash.add_child(item_icon)


func _build_panels() -> void:
	panel_l = _panel(Vector3(-PANEL_OFF.x, PANEL_OFF.y, PANEL_OFF.z), HORIZONTAL_ALIGNMENT_LEFT)
	panel_r = _panel(PANEL_OFF, HORIZONTAL_ALIGNMENT_RIGHT)
	panel_hint = _panel(Vector3(0, -0.22, -2.6), HORIZONTAL_ALIGNMENT_CENTER)
	panel_hint.font_size = 64
	panel_hint.modulate = Color(1.0, 0.92, 0.4)


func _panel(off: Vector3, align: HorizontalAlignment) -> Label3D:
	var l := Label3D.new()
	l.font_size = 56
	l.pixel_size = 0.0034
	l.outline_size = 18
	l.modulate = Color(1, 1, 0.92)
	l.outline_modulate = Color(0, 0, 0)
	l.width = 520.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = align
	l.render_priority = 4
	seat.add_child(l)
	l.position = EYE + off
	var face := -off
	face.y = 0.0
	l.rotation.y = atan2(face.x, face.z)  # turned to look back at the eyes
	return l


func _build_vignette(cam: XRCamera3D) -> void:
	vignette = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	sm.radial_segments = 16
	sm.rings = 8
	vignette.mesh = sm
	vignette_mat = ShaderMaterial.new()
	vignette_mat.shader = Shader.new()
	vignette_mat.shader.code = VIGNETTE_SHADER
	vignette_mat.render_priority = 100
	vignette.material_override = vignette_mat
	vignette.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cam.add_child(vignette)
	vignette.visible = false


## Blink (a teleport, a new race): the view fades for a moment instead of jumping.
func fade() -> void:
	fade_k = 1.0
	frame_init = false


# --- Input -------------------------------------------------------------------------------

## Hand position in the seat frame.
func _hand_local(h: XRController3D) -> Vector3:
	return seat.global_transform.affine_inverse() * h.global_position


func hand_positions() -> Array:
	if fake:
		return [fake_l, fake_r, true, true]
	return [_hand_local(hand_l), _hand_local(hand_r), hand_l.get_has_tracking_data(), hand_r.get_has_tracking_data()]


## Hand position in the wheel's own plane: [x right, y up along the rim, depth].
func _on_wheel(p: Vector3) -> Vector3:
	var b := wheel_basis()
	var d := p - wheel_center()
	return Vector3(d.dot(b.x), d.dot(b * Vector3(0, 0, -1)), d.dot(b.y))


func _holding(w: Vector3) -> bool:
	var r := Vector2(w.x, w.y).length()
	return r > HOLD_IN and r < HOLD_OUT and absf(w.z) < HOLD_DEPTH


func wheel_held() -> bool:
	return grip != ""


## Wheel angle from the hands (+ = anticlockwise = turning left), or NAN when no hand holds it.
## Measured relative to the grip: when the set of holding hands changes, the wheel carries on from
## its current angle.
func wheel_from_hands(pl: Vector3, pr: Vector3, track_l: bool, track_r: bool) -> float:
	var wl := _on_wheel(pl)
	var wr := _on_wheel(pr)
	held_l = track_l and _holding(wl)
	held_r = track_r and _holding(wr)
	if held_l and held_r and Vector2(wr.x - wl.x, wr.y - wl.y).length() < 0.08:
		held_l = false  # both hands in one spot: treat it as one hand
	var key := ("L" if held_l else "") + ("R" if held_r else "")
	if key == "":
		grip = ""
		return NAN
	var m := 0.0
	if held_l and held_r:
		m = atan2(wr.y - wl.y, wr.x - wl.x)
	elif held_r:
		m = atan2(wr.y, wr.x)
	else:
		m = atan2(-wl.y, -wl.x)
	if key != grip:
		grip = key
		grip_raw = m
		grip_acc = m
		grip_offset = wheel_angle - m
	else:
		grip_acc += wrapf(m - grip_raw, -PI, PI)  # unwrap: hands may go round past 9 o'clock
		grip_raw = m
	return grip_acc + grip_offset


## [throttle, brake, steer, item pressed, boost pressed]
func read_input(delta: float) -> Array:
	var hp: Array = hand_positions()
	var want := wheel_from_hands(hp[0], hp[1], hp[2], hp[3])
	var stick := fake_stick
	var trig := fake_trigger
	var a := fake_a
	if not fake:
		stick = hand_l.get_vector2("primary")
		trig = hand_r.get_float("trigger")
		a = hand_r.is_button_pressed("ax_button")
		var rs := hand_r.get_vector2("primary")
		if absf(rs.y) > 0.6:
			seat_adj = clampf(seat_adj - signf(rs.y) * 0.25 * delta, -0.35, 0.35)
	var was_held := has_meta("held")
	if is_nan(want):
		remove_meta("held")
		unheld_t += delta
		var spring := 0.0
		if absf(stick.x) > 0.2:
			spring = -stick.x * FULL_LOCK * 0.8
		wheel_angle = move_toward(wheel_angle, spring, 3.0 * delta)
	else:
		set_meta("held", true)
		unheld_t = 0.0
		if not was_held and not fake:
			(hand_r if held_r else hand_l).trigger_haptic_pulse("haptic", 0.0, 0.3, 0.05, 0.0)
		wheel_angle = lerpf(wheel_angle, clampf(want, -FULL_LOCK * 1.2, FULL_LOCK * 1.2), 1.0 - exp(-14.0 * delta))
	var steer := -wheel_angle / FULL_LOCK
	if absf(steer) < 0.06:
		steer = 0.0
	var throttle := trig
	var brake := 0.0
	if stick.y > 0.3:
		throttle = maxf(throttle, stick.y)
	elif stick.y < -0.3:
		brake = -stick.y
	var press := a and not a_was
	a_was = a
	var use_item: bool = press and kart.item != ""
	var use_boost: bool = press and kart.item == ""
	return [clampf(throttle, 0.0, 1.0), brake, clampf(steer, -1.0, 1.0), use_item, use_boost]


func haptic(amp: float, dur: float = 0.1) -> void:
	if fake:
		return
	hand_l.trigger_haptic_pulse("haptic", 0.0, amp, dur, 0.0)
	hand_r.trigger_haptic_pulse("haptic", 0.0, amp, dur, 0.0)


# --- Per frame (after the kart moved) ----------------------------------------------------

## The seat frame: the kart's position and yaw (never its roll or pitch), height eased with a speed cap.
func _place_seat(delta: float) -> void:
	var kp: Vector3 = kart.global_position
	if not frame_init or absf(kp.y - frame_y) > 3.0:
		frame_init = true
		frame_y = kp.y
	elif delta > 0.0:
		var want := lerpf(frame_y, kp.y, 1.0 - exp(-8.0 * delta))
		frame_y = move_toward(frame_y, want, FRAME_VY * delta)
	seat.global_transform = Transform3D(Basis(Vector3.UP, kart.yaw), Vector3(kp.x, frame_y, kp.z))


func place(delta: float) -> void:
	_place_seat(delta)
	wheel_spin.rotation = Vector3(0, wheel_angle, 0)
	var hp: Array = hand_positions()
	var pl: Vector3 = hp[0]
	var pr: Vector3 = hp[1]
	mitten_l.position = pl
	mitten_r.position = pr
	mitten_l.visible = bool(hp[2])
	mitten_r.visible = bool(hp[3])
	var ch: float = kart.charge
	hub_bar.scale = Vector3(maxf(0.05, ch) * 1.0, 1, 1)
	var ready: bool = ch >= 1.0 and kart.item == ""
	var bc := Color(1.0, 0.85, 0.2) if ready else Color(0.3, 0.8, 1.0)
	hub_bar_mat.albedo_color = bc
	hub_bar_mat.emission = bc
	hub_bar_mat.emission_energy_multiplier = 2.5 + sin(Time.get_ticks_msec() * 0.012) * 1.5 if ready else 0.6
	needle.rotation.y = lerpf(1.3, -1.3, clampf(absf(float(kart.speed)) / 21.0, 0.0, 1.0))
	if kart.drift_t > 0.0:
		grip_mat.emission = kart.SPARK_COLORS[clampi(kart.drift_level, 0, 3)]
		grip_mat.emission_energy_multiplier = 1.5 + 1.0 * sin(Time.get_ticks_msec() * 0.02)
	else:
		grip_mat.emission = kart.color
		grip_mat.emission_energy_multiplier = 0.3
	_update_icon(delta)
	_update_ghost_hands()
	var texts: Array = main.vr_panel_texts(kart)
	panel_l.text = texts[0]
	panel_r.text = texts[1]
	panel_hint.text = texts[2]
	panel_hint.visible = str(texts[2]) != ""
	if fake:
		return
	if xr_origin.world_scale != 1.0:
		xr_origin.world_scale = 1.0
	var cam_local := xr_camera.transform
	if not fitted:
		fit_t -= delta
		if fit_t <= 0.0 and cam_local.origin != Vector3.ZERO:
			_fit(cam_local)
	else:
		if absf(cam_local.origin.y - fit_head_y) > 0.25:
			refit_t += delta
			if refit_t > 1.5:
				print("VR: head height changed %.2f -> %.2f m, re-fitting the seat" % [fit_head_y, cam_local.origin.y])
				_fit(cam_local)
		else:
			refit_t = 0.0
	var sxf := fit_xf
	sxf.origin += Vector3(0, seat_adj, 0)
	xr_origin.global_transform = seat.global_transform * sxf
	# Comfort vignette on boosts, banana spins and hops; a full blink on teleports.
	var want := 0.0
	if kart.boost_t > 0.0:
		want = 0.5
	if kart.slip_t > 0.0:
		want = 0.7
	if not kart.on_ground:
		want = maxf(want, 0.35)
	fade_k = maxf(0.0, fade_k - delta * 2.5)
	vignette_k = lerpf(vignette_k, want, 1.0 - exp(-6.0 * delta))
	var v := maxf(vignette_k, fade_k)
	vignette.visible = v > 0.02
	vignette_mat.set_shader_parameter("strength", v)


## Simple mode: two see-through mittens on the rim turn the wheel left and right whenever nobody
## holds it (the practice, the countdown, or hands off for a moment): grab it like that.
func _build_ghost_hands() -> void:
	ghost_mat = StandardMaterial3D.new()
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.albedo_color = Color(0.7, 0.95, 1.0, 0.45)
	ghost_l = _mitten()
	ghost_r = _mitten()
	for g in [ghost_l, ghost_r]:
		var m: MeshInstance3D = g
		m.material_override = ghost_mat
		m.scale *= 1.15
		m.visible = false


func _update_ghost_hands() -> void:
	if ghost_l == null:
		return
	var vis: bool = unheld_t > 0.8 and not kart.finished and main.state != "results"
	ghost_l.visible = vis
	ghost_r.visible = vis
	if not vis:
		return
	var t := Time.get_ticks_msec() * 0.001
	var a := 0.7 * sin(t * 1.8)
	var b := wheel_basis()
	var up := b * Vector3(0, 0, -1)
	var c := wheel_center()
	ghost_r.position = c + b.x * (WHEEL_R * cos(a)) + up * (WHEEL_R * sin(a))
	ghost_l.position = c + b.x * (WHEEL_R * cos(a + PI)) + up * (WHEEL_R * sin(a + PI))
	ghost_mat.albedo_color.a = 0.3 + 0.2 * sin(t * 4.0)


## The item you hold, as a little model on the dash.
func _update_icon(delta: float) -> void:
	var it: String = kart.item
	if it != icon_item:
		icon_item = it
		for c in item_icon.get_children():
			c.queue_free()
		if it != "":
			main.build_item_model(item_icon, it, 0.07)
	item_icon.rotation.y += delta * 1.5


## Put the eyes at the seat's eye point, facing forward over the wheel.
func _fit(cam_local: Transform3D) -> void:
	fitted = true
	refit_t = 0.0
	fit_head_y = cam_local.origin.y
	var head_yaw := cam_local.basis.get_euler().y
	var r := Basis(Vector3.UP, -head_yaw)
	fit_xf = Transform3D(r, EYE - r * cam_local.origin)
	seat_adj = 0.0
	print("VR: seat fitted, head %.2f m above the floor" % fit_head_y)


## Head pose relative to the kart, for the TV's view of the VR driver.
func head_local() -> Transform3D:
	if fake or xr_camera == null:
		return Transform3D(Basis(), EYE)
	return kart.global_transform.affine_inverse() * xr_camera.global_transform
