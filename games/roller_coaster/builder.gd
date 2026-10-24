extends Node3D
## COASTER CREW: the VR builder (host only). The player is a giant (world scale WS) at a tabletop park.
## - A tray of track pieces floats on a shelf to their right (never near the face). Squeeze the right
##   trigger on a piece to pick it up; bring it near the glowing end of the track and a full-size glowing
##   GHOST shows where it will go; let go and it snaps on with a click. Let go elsewhere: it flies home.
## - The glowing knob at the end of the track: squeeze and pull up / down to make hills (ratchet clicks).
## - A star jar on the tray: drop a star near the track for the riders to grab.
## - On the left shelf: the big green START lever (push it), the glowing "close the loop" button and
##   a little RIDE car (touch it to ride along next time). A = take the last piece off.
## - Right stick turns the table; left stick shuffles about a little.
## - Opt-in ride: world scale 1, sitting in the front car, level horizon (loops are ridden flat), a
##   comfort vignette, gentle speed; the trigger stops it at once.
## Everything goes through main's functions (add_piece, set_end_height, ...) - the same ones the bot uses.

const MeshKit := preload("res://core/mesh_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")
const Track := preload("res://games/roller_coaster/track.gd")

const WS := 18.0  # the giant: 1 real metre = 18 park metres
const TABLE_H := 0.75  # real table height
const TRAY_R := 6.5  # tray arc radius round the head (world units, ~36 cm)
const TRAY_Y := 1.9  # tray height above the table top (world units, ~11 cm)
const ITEM_SCALE := 0.38
const GRAB_R := 1.3
const TOUCH_R := 1.1
const SNAP_R := 4.3
const TRAY_ITEMS: Array[String] = ["straight", "up", "down", "left", "right", "loop", "splash", "star"]

var main
var rig: VrRig
var feet := Vector3.ZERO
var bench: Node3D
var items: Array[Node3D] = []  # tray models, same order as TRAY_ITEMS
var homes: Array[Vector3] = []
var held := {}  # {kind: "piece"/"star"/"knob"/"guest", ...}
var ghost: MeshInstance3D
var ghost_type := ""
var spot: MeshInstance3D  # glowing ring at the track end (practice + while holding a piece)
var knob: MeshInstance3D
var lever: Node3D
var lever_t := 0.0
var close_btn: Node3D
var seat: Node3D
var seat_on := false
var touch_cool := {}
var glow_t := 0.0
var flying: Array = []  # [node, from, to, t]
var riding := false
var ride_ref := Vector3.ZERO
var ride_view_y := 0.0
var vignette: MeshInstance3D
var headline: Label3D
var headline_t := 0.0


func setup(m, r: VrRig) -> void:
	main = m
	rig = r
	rig.turn_mode = "none"  # the right stick turns the TABLE (comfortable: the world stays still)
	rig.set_scale_of_world(WS)
	rig.move_speed = 0.35 * WS
	feet = Vector3(0.0, -TABLE_H * WS, Track.TABLE_R + 0.15 * WS)
	rig.bounds = Rect2(-0.3 * WS, feet.z - 0.2 * WS, 0.6 * WS, 0.4 * WS)
	rig.place(feet, 0.0)
	rig.camera.far = 4000.0
	_build_bench()
	_build_ghosts()


func head_flat() -> Vector3:
	return Vector3(0.0, 0.0, feet.z)


## A point on the shelf arc round where the player stands (angle: 0 = straight ahead, + = right).
func arc(angle_deg: float, y: float, r: float = TRAY_R) -> Vector3:
	var a := deg_to_rad(angle_deg)
	return Vector3(sin(a) * r, y, feet.z - cos(a) * r)


func _build_bench() -> void:
	bench = Node3D.new()
	bench.name = "Bench"
	add_child(bench)
	var b := MeshKit.builder()
	for side in [1.0, -1.0]:
		for k in 11:
			var a: float = (45.0 + k * 10.0) * side
			var p := arc(a, TRAY_Y - 0.35)
			b.box(Vector3(1.3, 0.12, 1.5), Transform3D(Basis(Vector3.UP, -deg_to_rad(a)), p), Color(0.62, 0.42, 0.25))
		var leg := arc(90.0 * side, 0.0)
		b.cylinder(0.12, 0.12, 6.0, Transform3D(Basis(), leg + Vector3(0, TRAY_Y - 3.4, 0)), Color(0.5, 0.33, 0.2), 6)
	bench.add_child(MeshKit.instance(b.build(), false))
	for i in TRAY_ITEMS.size():
		var t := TRAY_ITEMS[i]
		var n := Node3D.new()
		var mi: MeshInstance3D
		if t == "star":
			mi = MeshKit.instance(MeshKit.prop("star"), false)
			mi.material_override = MeshKit.glow_material()
			mi.scale = Vector3.ONE * 0.7
		else:
			mi = MeshInstance3D.new()
			mi.mesh = Track.piece_mesh(t, 0.0, Color(0.95, 0.3, 0.32))
			mi.scale = Vector3.ONE * ITEM_SCALE
			var c := mi.mesh.get_aabb().get_center()
			mi.position = -c * ITEM_SCALE
		mi.name = "Model"
		n.add_child(mi)
		var home := arc(48.0 + i * 12.0, TRAY_Y)
		n.position = home
		n.rotation.y = -deg_to_rad(48.0 + i * 12.0) + PI * 0.5
		bench.add_child(n)
		items.append(n)
		homes.append(home)
	# Left shelf: START lever, close-the-loop button, the RIDE car.
	lever = Node3D.new()
	lever.position = arc(-58.0, TRAY_Y - 0.3)
	bench.add_child(lever)
	var lb := MeshKit.builder()
	lb.box(Vector3(1.0, 0.3, 0.8), Transform3D(Basis(), Vector3(0, 0, 0)), Color(0.3, 0.3, 0.35))
	lever.add_child(MeshKit.instance(lb.build(), false))
	var stick := Node3D.new()
	stick.name = "Stick"
	lever.add_child(stick)
	var sb := MeshKit.builder()
	sb.cylinder(0.08, 0.08, 1.4, Transform3D(Basis(), Vector3(0, 0.7, 0)), Color(0.85, 0.85, 0.9), 8)
	sb.sphere(0.32, Transform3D(Basis(), Vector3(0, 1.45, 0)), Color(0.25, 0.95, 0.35), 12, true)
	stick.add_child(MeshKit.instance(sb.build(), false))
	stick.rotation.x = -0.5
	close_btn = Node3D.new()
	close_btn.position = arc(-80.0, TRAY_Y - 0.3)
	bench.add_child(close_btn)
	var cb := MeshKit.builder()
	cb.cylinder(0.55, 0.6, 0.2, Transform3D(), Color(0.3, 0.3, 0.35), 16)
	cb.cylinder(0.42, 0.42, 0.22, Transform3D(Basis(), Vector3(0, 0.15, 0)), Color(0.3, 0.75, 1.0), 16, true)
	cb.torus(0.42, 0.06, Transform3D(Basis(), Vector3(0, 0.3, 0)), Color(1, 1, 1), 16, 4, true)
	close_btn.add_child(MeshKit.instance(cb.build(), false))
	seat = Node3D.new()
	seat.position = arc(-102.0, TRAY_Y - 0.2)
	seat.rotation.y = PI * 0.5
	bench.add_child(seat)
	var car := MeshKit.builder()
	car.rounded_box(Vector3(0.7, 0.35, 0.95), 0.1, Transform3D(Basis(), Vector3(0, 0.1, 0)), Color(0.3, 0.7, 1.0))
	car.box(Vector3(0.6, 0.08, 0.4), Transform3D(Basis(), Vector3(0, 0.3, 0.05)), Color(0.15, 0.3, 0.5))
	car.sphere(0.13, Transform3D(Basis(), Vector3(0, 0.55, 0.05)), Color(1.0, 0.85, 0.7), 10)
	var sm := MeshKit.instance(car.build(), false)
	sm.name = "Model"
	seat.add_child(sm)


func _build_ghosts() -> void:
	ghost = MeshInstance3D.new()
	ghost.material_override = _glow_mat(Color(0.5, 1.0, 0.7, 0.55))
	ghost.visible = false
	main.park.add_child(ghost)
	spot = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.75
	tm.outer_radius = 1.0
	tm.rings = 16
	tm.ring_segments = 6
	spot.mesh = tm
	spot.material_override = _glow_mat(Color(1.0, 0.9, 0.3, 0.8))
	main.park.add_child(spot)
	knob = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.38
	sm.height = 0.76
	sm.radial_segments = 12
	sm.rings = 6
	knob.mesh = sm
	knob.material_override = _glow_mat(Color(1.0, 0.85, 0.3, 0.9))
	main.park.add_child(knob)
	vignette = MeshInstance3D.new()
	var vs := SphereMesh.new()
	vs.radius = 0.25
	vs.height = 0.5
	vs.radial_segments = 16
	vs.rings = 8
	vignette.mesh = vs
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_front, depth_test_disabled, blend_mix;
uniform float strength = 0.0;
varying float fwd;
void vertex() { fwd = -normalize(VERTEX).z; }
void fragment() { ALBEDO = vec3(0.0); ALPHA = strength * smoothstep(0.75, 0.35, fwd); }
"""
	var vm := ShaderMaterial.new()
	vm.shader = sh
	vm.render_priority = 120
	vignette.material_override = vm
	vignette.visible = false
	rig.camera.add_child(vignette)


func _glow_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	return m


# --- Every frame --------------------------------------------------------------------------

func tick(delta: float) -> void:
	glow_t += delta
	for k in touch_cool.keys():
		touch_cool[k] = float(touch_cool[k]) - delta
	_fly(delta)
	_headline(delta)
	if riding:
		_ride(delta)
		return
	var turn := rig.stick_right().x
	if absf(turn) > 0.2:
		main.turn_table(-turn * 1.1 * delta)
	var building := String(main.phase) == "build"
	_tray_look(building)
	_end_markers(building)
	if building and rig.a_pressed():
		main.undo_piece()
		rig.pulse(VrRig.RIGHT, 0.3, 0.05)
	var hp := rig.hand_point(VrRig.RIGHT)
	if held.is_empty():
		if rig.trigger_pressed():
			_try_grab(hp)
	else:
		_hold(hp, delta)
		if not rig.trigger_down():
			_release(hp)
	_touches()


func _tray_look(building: bool) -> void:
	var want: String = main.practice_piece()
	for i in items.size():
		var n := items[i]
		if held.get("item", -1) == i or _is_flying(n):
			continue
		var t := TRAY_ITEMS[i]
		n.visible = building and (want == "" or t == want) and not (t == "star" and want != "")
		var glow := want != "" and t == want
		var s := 1.0 + (0.18 * sin(glow_t * 6.0) if glow else 0.0)
		n.scale = Vector3.ONE * s
		n.position = homes[i] + Vector3.UP * (0.25 + 0.15 * sin(glow_t * 4.0) if glow else 0.0)
	close_btn.visible = building and not main.closed and main.pieces.size() > 0 and main.practice_piece() == ""
	lever.visible = true
	var stick: Node3D = lever.get_node("Stick")
	lever_t = maxf(0.0, lever_t - 1.0 / 60.0)
	stick.rotation.x = lerpf(-0.5, 0.6, minf(1.0, lever_t * 3.0)) if lever_t > 0.0 else -0.5 + (0.08 * sin(glow_t * 5.0) if main.lever_glows() else 0.0)
	lever.scale = Vector3.ONE * (1.0 + (0.12 * absf(sin(glow_t * 4.0)) if main.lever_glows() else 0.0))
	seat.get_node("Model").position.y = 0.25 * absf(sin(glow_t * 5.0)) if seat_on else 0.0
	seat.visible = main.practice_piece() == ""


## The glowing knob and ring at the end of the track (in the park, so they turn with the table).
func _end_markers(building: bool) -> void:
	var end: Array = main.track.get("end", [Track.station_end(), 0.0])
	var ep: Vector3 = end[0]
	var eyaw: float = end[1]
	knob.visible = building and main.pieces.size() > 0 and held.get("kind", "") != "piece"
	if held.get("kind", "") != "knob":
		knob.position = ep + Vector3.UP * 0.6
	var practice: String = main.practice_piece()
	spot.visible = building and (practice != "" or held.get("kind", "") == "piece")
	spot.position = ep + Track.fwd(eyaw) * 1.2 + Vector3.UP * 0.2
	spot.scale = Vector3.ONE * (1.0 + 0.2 * sin(glow_t * 6.0))
	if practice != "" and held.is_empty():
		_show_ghost(practice, ep, eyaw, true)
	elif held.get("kind", "") != "piece":
		ghost.visible = false


func _show_ghost(t: String, ep: Vector3, eyaw: float, ok: bool) -> void:
	if ghost_type != t:
		ghost_type = t
		ghost.mesh = Track.piece_mesh(t, 0.0, Color.WHITE)
	ghost.visible = true
	ghost.transform = Transform3D(Basis(Vector3.UP, eyaw), ep - Vector3(0, 1, 0).rotated(Vector3.UP, eyaw))
	var m: StandardMaterial3D = ghost.material_override
	var a := 0.35 + 0.25 * absf(sin(glow_t * 5.0))
	m.albedo_color = Color(0.5, 1.0, 0.65, a) if ok else Color(1.0, 0.55, 0.3, a)


func _try_grab(hp: Vector3) -> void:
	var building := String(main.phase) == "build"
	if building:
		var best := -1
		var bd := GRAB_R
		for i in items.size():
			var d := items[i].global_position.distance_to(hp)
			if items[i].visible and d < bd:
				bd = d
				best = i
		if best >= 0:
			held = {"kind": "star" if TRAY_ITEMS[best] == "star" else "piece", "item": best, "type": TRAY_ITEMS[best]}
			rig.pulse(VrRig.RIGHT, 0.4, 0.04)
			main.sound("ui_select", -6.0, 1.3)
			return
		if knob.visible and knob.global_position.distance_to(hp) < GRAB_R * 1.2:
			held = {"kind": "knob", "y0": hp.y, "h0": main.last_height(), "h": main.last_height()}
			rig.pulse(VrRig.RIGHT, 0.4, 0.04)
			return
	var g: int = main.nearest_guest(hp, GRAB_R * 1.3)
	if g >= 0:
		held = {"kind": "guest", "guest": g}
		main.hold_guest(g, hp)
		rig.pulse(VrRig.RIGHT, 0.4, 0.05)


func _hold(hp: Vector3, _delta: float) -> void:
	match String(held.kind):
		"piece", "star":
			var n := items[int(held.item)]
			n.global_position = hp + Vector3.UP * 0.2
			if held.kind == "piece":
				var end: Array = main.track.get("end", [Track.station_end(), 0.0])
				var ep: Vector3 = end[0]
				var near: bool = main.park.to_global(ep).distance_to(hp) < SNAP_R
				held["snap"] = near
				if near:
					_show_ghost(String(held.type), ep, float(end[1]), main.can_add(String(held.type)))
				else:
					ghost.visible = false
		"knob":
			var dh := (hp.y - float(held.y0)) * 1.0
			var h := clampf(snappedf(float(held.h0) + dh, 0.5), -3.0, 4.0)
			if h != float(held.h):
				held["h"] = h
				main.set_end_height(h)
				rig.pulse(VrRig.RIGHT, 0.25, 0.02)
			knob.global_position = hp
		"guest":
			main.hold_guest(int(held.guest), hp)


func _release(hp: Vector3) -> void:
	match String(held.kind):
		"piece":
			var n := items[int(held.item)]
			var t := String(held.type)
			if held.get("snap", false) and main.can_add(t):
				main.add_piece(t)
				rig.pulse(VrRig.RIGHT, 0.7, 0.08)
				n.global_position = homes[int(held.item)]
			else:
				flying.append([n, n.position, homes[int(held.item)], 0.0])
				main.sound("whoosh", -8.0, 1.4)
			ghost.visible = false
		"star":
			var n := items[int(held.item)]
			var placed: bool = main.place_star_at(main.park.to_local(hp))
			if placed:
				rig.pulse(VrRig.RIGHT, 0.6, 0.06)
				n.position = homes[int(held.item)]
			else:
				flying.append([n, n.position, homes[int(held.item)], 0.0])
		"knob":
			main.sound("ui_select", -6.0, 0.8)
		"guest":
			main.drop_guest(int(held.guest), rig.hand_velocity(VrRig.RIGHT))
	held = {}


func _is_flying(n: Node3D) -> bool:
	for f in flying:
		if (f as Array)[0] == n:
			return true
	return false


func _fly(delta: float) -> void:
	for f in flying.duplicate():
		var a: Array = f
		a[3] = float(a[3]) + delta * 2.5
		var k: float = minf(1.0, a[3])
		var n: Node3D = a[0]
		n.position = (a[1] as Vector3).lerp(a[2], k) + Vector3.UP * sin(k * PI) * 1.5
		if k >= 1.0:
			flying.erase(f)


## Either hand: the lever, the close button, the RIDE car, and everything in the park.
func _touches() -> void:
	for h in [VrRig.LEFT, VrRig.RIGHT]:
		var hp := rig.hand_point(h)
		if not held.is_empty() and h == VrRig.RIGHT:
			continue
		if h == VrRig.RIGHT and rig.in_wrist_zone(hp):
			continue  # the right hand is pressing the wrist MENU
		if lever.visible and _touch("lever", hp, lever.global_position + Vector3.UP * 1.3, TOUCH_R * 1.3):
			lever_t = 0.6
			rig.pulse(h, 0.8, 0.1)
			main.pull_lever()
		if close_btn.visible and _touch("close", hp, close_btn.global_position, TOUCH_R):
			rig.pulse(h, 0.6, 0.08)
			main.close_loop()
		if seat.visible and _touch("seat", hp, seat.global_position, TOUCH_R):
			seat_on = not seat_on
			rig.pulse(h, 0.5, 0.06)
			main.sound("honk" if seat_on else "ui_back", -4.0, 1.2)
			main.set_vr_ride(seat_on)
		main.vr_touch(h, hp)


## True once per touch (a short cooldown, and the hand must leave first).
func _touch(key: String, hp: Vector3, at: Vector3, r: float) -> bool:
	var inside := hp.distance_to(at) < r
	var k := key + ("_in")
	if not inside:
		touch_cool.erase(k)
		return false
	if touch_cool.has(k):
		return false
	touch_cool[k] = 0.0
	return true


# --- The opt-in ride ------------------------------------------------------------------------

func start_ride() -> void:
	if riding:
		return
	riding = true
	held = {}
	ghost.visible = false
	rig.set_scale_of_world(1.0)
	rig.locomotion = false
	rig.refit()
	ride_ref = rig.camera.position
	ride_view_y = 0.0
	vignette.visible = true
	rig.guard_trigger()
	show_headline("RIDE!")


func stop_ride() -> void:
	if not riding:
		return
	riding = false
	vignette.visible = false
	rig.set_scale_of_world(WS)
	rig.locomotion = true
	rig.global_transform = Transform3D(Basis(), rig.global_position)
	rig.place(feet, 0.0)
	rig.refit()
	rig.guard_trigger()


func _ride(delta: float) -> void:
	if rig.trigger_pressed() or String(main.phase) != "ride":
		main.set_vr_ride(false)
		seat_on = false
		stop_ride()
		return
	var tr: Dictionary = main.track
	var s: float = main.train_s
	var xf := Track.sample(tr, s)
	var pos := xf.origin
	for r in tr.get("loops", []):
		var ra: Array = r
		if s >= float(ra[0]) and s <= float(ra[1]):
			var a := Track.sample(tr, float(ra[0])).origin
			var b := Track.sample(tr, float(ra[1])).origin
			pos = a.lerp(b, (s - float(ra[0])) / maxf(0.01, float(ra[1]) - float(ra[0])))
	var f := -xf.basis.z
	if absf(f.y) < 0.95 and not Track.in_ranges(tr.get("loops", []), s):
		var target := atan2(-f.x, -f.z)
		ride_view_y = lerp_angle(ride_view_y, target, 1.0 - exp(-4.0 * delta))
	var park_xf: Transform3D = main.park.global_transform
	var eye := park_xf * (pos + Vector3.UP * 1.05)
	var yaw: float = ride_view_y + main.park.rotation.y
	var b := Basis(Vector3.UP, yaw)
	rig.global_transform = Transform3D(b, eye - b * ride_ref)
	var vm: ShaderMaterial = vignette.material_override
	vm.set_shader_parameter("strength", clampf(0.35 + float(main.train_v) / 14.0, 0.35, 0.95))


func show_headline(text: String) -> void:
	if headline == null:
		headline = Label3D.new()
		headline.font_size = 96
		headline.outline_size = 26
		headline.modulate = Color(1.0, 0.9, 0.3)
		headline.outline_modulate = Color(0, 0, 0, 0.95)
		headline.double_sided = false
		add_child(headline)
	headline.text = text
	headline.visible = true
	headline_t = 2.5
	var ws := float(rig.world_scale)
	var cam := rig.camera
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	headline.pixel_size = 0.0035 * ws
	headline.global_position = cam.global_position + fwd * 2.8 * ws + Vector3.UP * 0.25 * ws
	var d := headline.global_position - cam.global_position
	headline.global_basis = Basis(Vector3.UP, atan2(-d.x, -d.z)).scaled(Vector3.ONE)


func _headline(delta: float) -> void:
	if headline == null or not headline.visible:
		return
	headline_t -= delta
	if riding:
		# Keep it with the moving car (in the car's frame, not the head's).
		pass
	headline.visible = headline_t > 0.0
