extends Node3D
## Starship Crew: the captain's cockpit on the bridge (front of the ship, facing -Z).
## A stable seated cockpit: the ship never rolls or pitches the camera; the world outside slides.
## Controls (world-space, built for a seated player whose eyes the VrRig fits to EYE):
##  - FLIGHT STICK (right of the seat): grab with the right trigger (or rest the left hand on it).
##    Steering is the hand's movement relative to where it grabbed the handle (no rest pose):
##    left/right slides the ship sideways, raising/lowering the hand moves it up/down.
##  - THROTTLE (left of the seat): grab with the right trigger or rest the left hand on the knob and
##    push forward / pull back. It stays where it is left.
##  - Big buttons on the dashboard, pressed by touching them with either glove: TORPEDO (red),
##    SHIELDS (blue), HYPERJUMP (big, glows when ready), HORN (purple), and four small CREW CALL buttons.
##  - Thumbstick fallbacks: left stick steers, right stick up/down moves the throttle, A fires a torpedo.
## Shows: four dials, a holographic radar, an aiming reticle and the window HUD (world-locked text about
## 3 m away on the window, VR layer only). VR comfort: a camera-attached vignette that darkens the edges
## on fast sideways motion, and a full fade used by hyperjumps.
## The flat captain (local play without a headset) uses the same cockpit through a TV camera at EYE.

signal button_pressed(id: String)

const MeshKit := preload("res://core/mesh_kit.gd")
const UiKit := preload("res://core/ui_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")
const Models := preload("res://games/starship_crew/models.gd")

## Render layer for VR-only things (window HUD, reticle): TV deck cameras leave it out.
const VR_LAYER := 1 << 1
const EYE := Vector3(0.0, 1.2, -8.6)
const SEAT := Vector3(0.0, 0.0, -8.6)
const DASH_XF := Transform3D(Basis(Vector3.RIGHT, 0.32), Vector3(0.0, 0.9, -9.35))
const STICK_BASE := Vector3(0.34, 0.6, -9.0)
const THROTTLE_BASE := Vector3(-0.36, 0.6, -9.0)
const LEVER := 0.22
const STICK_RANGE := 0.09  # metres of hand travel for full steering
const THROTTLE_RANGE := 0.26  # metres of hand travel from idle to full
const GRAB_R := 0.14
const TOUCH_GRAB_R := 0.1
## Buttons: id -> [dashboard-local (x, z), radius, colour, hover text].
const BUTTONS := {
	"jump": [Vector2(0.0, 0.04), 0.075, Color(1.0, 0.92, 0.45), "HYPERJUMP: jump when it glows (throttle all the way up!)"],
	"torpedo": [Vector2(-0.27, 0.06), 0.06, Color(1.0, 0.25, 0.25), "TORPEDO: fire at the target in the ring"],
	"shields": [Vector2(0.27, 0.06), 0.06, Color(0.3, 0.6, 1.0), "SHIELDS: raise a super shield for a moment"],
	"horn": [Vector2(0.0, 0.2), 0.04, Color(0.8, 0.45, 1.0), "HORN: honk!"],
	"call_power": [Vector2(-0.69, -0.09), 0.036, Color(1.0, 0.85, 0.3), "CALL CREW: we need POWER!"],
	"call_torpedo": [Vector2(-0.53, -0.09), 0.036, Color(1.0, 0.35, 0.3), "CALL CREW: load TORPEDOES!"],
	"call_scan": [Vector2(-0.69, 0.08), 0.036, Color(0.45, 1.0, 0.55), "CALL CREW: SCAN the enemy!"],
	"call_repair": [Vector2(-0.53, 0.08), 0.036, Color(1.0, 0.6, 0.25), "CALL CREW: REPAIRS needed!"],
}
const RADAR_LOCAL := Vector2(0.6, -0.04)
const RADAR_R := 0.15
const RADAR_RANGE := 130.0
const MAX_BLIPS := 28
const VIGNETTE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, depth_test_disabled, depth_draw_never, blend_mix, fog_disabled;
uniform float strength = 0.0;
uniform float fade = 0.0;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 fade_tint : source_color = vec4(0.75, 0.9, 1.0, 1.0);
varying vec3 vdir;
void vertex() {
	vdir = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 d = normalize(vdir);
	float c = -d.z;
	float edge = smoothstep(0.9, 0.5, c) * strength;
	ALBEDO = mix(tint.rgb, fade_tint.rgb, step(edge, fade));
	ALPHA = clamp(max(edge, fade), 0.0, 1.0);
}
"""

var paint_id := "classic"
## Current control values (host: from hands / pads; TV machine: from snapshots).
var steer := Vector2.ZERO
var throttle := 0.35
var stick_hand := -1  # VrRig.LEFT / RIGHT holding the stick, -1 = nobody
var throttle_hand := -1
var hover_text := ""

var stick_pivot: Node3D
var throttle_pivot: Node3D
var buttons := {}  # id -> {"node", "mat", "top" (world), "r", "down_t", "latched", "state"}
var needles: Array[Node3D] = []
var radar_root: Node3D
var radar_blips: MultiMeshInstance3D
var radar_ring: MeshInstance3D
var reticle: Node3D
var hud := {}  # name -> Label3D
var vignette: MeshInstance3D
var vignette_mat: ShaderMaterial
var light: OmniLight3D
var frame_mi: MeshInstance3D

var _grab_hand_pos := Vector3.ZERO
var _grab_throttle := 0.0
var _left_touch := {"stick": 0.0, "throttle": 0.0}
var _t := 0.0
var _hud_cache := {}
var _vig := 0.0
var _fade := 0.0
var _fade_target := 0.0


func _ready() -> void:
	_build()


# --- Building ------------------------------------------------------------------------------------

func _build() -> void:
	frame_mi = MeshKit.instance(_static_mesh(), false)
	frame_mi.name = "CockpitMesh"
	add_child(frame_mi)
	stick_pivot = Node3D.new()
	stick_pivot.name = "Stick"
	stick_pivot.position = STICK_BASE
	add_child(stick_pivot)
	stick_pivot.add_child(MeshKit.instance(Models.flight_stick(), false))
	throttle_pivot = Node3D.new()
	throttle_pivot.name = "Throttle"
	throttle_pivot.position = THROTTLE_BASE
	add_child(throttle_pivot)
	throttle_pivot.add_child(MeshKit.instance(Models.throttle_lever(), false))
	for id in BUTTONS:
		var def: Array = BUTTONS[id]
		var local: Vector2 = def[0]
		var r: float = def[1]
		var col: Color = def[2]
		var n := Node3D.new()
		n.name = "Button_" + str(id)
		n.transform = DASH_XF * Transform3D(Basis(), Vector3(local.x, 0.03, local.y))
		add_child(n)
		var mi := MeshKit.instance(Models.push_button(r, col), false)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.albedo_color = Color(0.6, 0.6, 0.6)
		mi.material_override = mat
		n.add_child(mi)
		buttons[id] = {"node": n, "mesh": mi, "mat": mat, "top": n.position + n.basis.y * 0.035, "r": r, "down_t": 0.0,
			"latched": false, "state": "idle", "text": def[3]}
	_build_dials()
	_build_radar()
	_build_reticle()
	_build_hud()
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.9, 0.78)
	light.light_energy = 0.8
	light.omni_range = 4.0
	light.shadow_enabled = false
	light.position = Vector3(0.0, 2.1, -9.0)
	add_child(light)


func _static_mesh() -> ArrayMesh:
	var p := Models.paint(paint_id)
	var trim: Color = p["trim"]
	var hull: Color = p["hull"]
	var b := MeshKit.Builder.new()
	var dark := Color(0.22, 0.24, 0.3)
	var panel := Color(0.36, 0.39, 0.48)
	# Captain's chair.
	b.rounded_box(Vector3(0.62, 0.14, 0.6), 0.06, MeshKit.at(SEAT + Vector3(0, 0.48, 0.05)), Color(0.85, 0.3, 0.28), 2)
	b.rounded_box(Vector3(0.62, 0.8, 0.14), 0.07, MeshKit.at(SEAT + Vector3(0, 0.9, 0.36), Vector3.ONE, Vector3(-0.12, 0, 0)), Color(0.85, 0.3, 0.28), 2)
	b.rounded_box(Vector3(0.4, 0.22, 0.12), 0.05, MeshKit.at(SEAT + Vector3(0, 1.38, 0.42), Vector3.ONE, Vector3(-0.12, 0, 0)), Color(0.95, 0.4, 0.36), 2)
	b.cylinder(0.08, 0.12, 0.42, MeshKit.at(SEAT + Vector3(0, 0.21, 0.05)), dark, 10)
	b.cylinder(0.32, 0.36, 0.06, MeshKit.at(SEAT + Vector3(0, 0.03, 0.05)), dark, 14)
	# Pedestals for the stick and throttle.
	for base in [STICK_BASE, THROTTLE_BASE]:
		var bp: Vector3 = base
		b.rounded_box(Vector3(0.16, bp.y, 0.2), 0.04, MeshKit.at(Vector3(bp.x, bp.y * 0.5, bp.z)), panel, 1)
		b.cylinder(0.06, 0.07, 0.04, MeshKit.at(bp + Vector3(0, -0.01, 0)), dark, 12)
	# Throttle slot plate with idle/full ticks.
	b.box(Vector3(0.05, 0.012, 0.24), MeshKit.at(THROTTLE_BASE + Vector3(0, 0.004, -0.02)), dark)
	b.box(Vector3(0.09, 0.014, 0.012), MeshKit.at(THROTTLE_BASE + Vector3(0, 0.006, 0.09)), Color(0.4, 1.0, 0.5), true)
	b.box(Vector3(0.09, 0.014, 0.012), MeshKit.at(THROTTLE_BASE + Vector3(0, 0.006, -0.13)), Color(1.0, 0.5, 0.3), true)
	# Dashboard: a sloped desk on a body, with side wings.
	b.rounded_box(Vector3(1.66, 0.06, 0.6), 0.025, DASH_XF, panel, 1)
	b.rounded_box(Vector3(1.6, 0.86, 0.32), 0.05, MeshKit.at(Vector3(0, 0.43, -9.55)), dark, 1)
	b.box(Vector3(1.62, 0.025, 0.012), DASH_XF * MeshKit.at(Vector3(0, 0.03, 0.296)), trim)
	# Gauge cluster along the far edge of the desk.
	b.rounded_box(Vector3(1.5, 0.17, 0.08), 0.03, MeshKit.at(Vector3(0, 1.06, -9.66), Vector3.ONE, Vector3(-0.25, 0, 0)), dark, 1)
	# Radar projector.
	var rp := DASH_XF * Vector3(RADAR_LOCAL.x, 0.03, RADAR_LOCAL.y)
	b.cylinder(0.05, 0.07, 0.035, MeshKit.at(rp + Vector3(0, 0.015, 0)), Color(0.3, 0.35, 0.45), 14)
	b.disc(0.045, MeshKit.at(rp + Vector3(0, 0.034, 0)), Color(0.3, 0.9, 1.0), 14, true)
	# Window frame: sill, side posts and an arched top (thin struts keep the view open).
	b.rounded_box(Vector3(6.6, 0.25, 0.5), 0.08, MeshKit.at(Vector3(0, 0.92, -11.0)), hull, 1)
	b.box(Vector3(6.5, 0.05, 0.08), MeshKit.at(Vector3(0, 1.06, -10.8)), trim, true)
	var arch: Array[Vector3] = []
	for k in 9:
		var a := PI * float(k) / 8.0
		arch.append(Vector3(-cos(a) * 3.25, 0.95 + sin(a) * 2.3, -11.0 + sin(a) * 0.6))
	for k in 8:
		b.capsule_between(arch[k], arch[k + 1], 0.07, hull.darkened(0.05), 8)
	b.capsule_between(Vector3(-2.0, 0.95, -11.0), arch[3], 0.035, hull.darkened(0.1), 6)
	b.capsule_between(Vector3(2.0, 0.95, -11.0), arch[5], 0.035, hull.darkened(0.1), 6)
	# Side consoles along the bridge walls (decoration with blinking-looking lights).
	for sx in [-1.0, 1.0]:
		var s: float = sx
		b.rounded_box(Vector3(0.5, 0.8, 1.6), 0.06, MeshKit.at(Vector3(s * 2.75, 0.4, -10.0)), dark, 1)
		b.wedge(Vector3(0.5, 0.25, 1.6), MeshKit.at(Vector3(s * 2.75, 0.92, -10.0), Vector3.ONE, Vector3(0, s * PI * 0.5, 0)), panel)
		for k in 4:
			b.sphere(0.03, MeshKit.at(Vector3(s * 2.6, 0.93, -10.6 + k * 0.38)), [Color(1, 0.4, 0.3), Color(0.4, 1, 0.5), Color(1, 0.85, 0.3), Color(0.4, 0.8, 1)][k], 6, true)
	return b.build()


func _build_dials() -> void:
	var cols: Array[Color] = [Color(0.4, 1.0, 0.5), Color(0.4, 0.7, 1.0), Color(1.0, 0.85, 0.3), Color(0.95, 0.95, 1.0)]
	var face := MeshKit.Builder.new()
	for k in 4:
		var x := -0.54 + k * 0.36
		var xf := Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(x, 1.065, -9.615))
		face.disc(0.068, xf * MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.1, 0.1, 0.14), 18)
		face.torus(0.068, 0.008, xf * MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), cols[k], 18, 4, true)
		# coloured arc marks (low end red)
		for j in 5:
			var a := lerpf(2.2, -2.2, float(j) / 4.0)
			var c := cols[k] if j > 0 else Color(1.0, 0.3, 0.3)
			face.box(Vector3(0.008, 0.02, 0.004), xf * Transform3D(Basis(Vector3.BACK, a), Vector3(0, 0, 0.003)) * MeshKit.at(Vector3(0, 0.05, 0)), c, true)
		var needle := Node3D.new()
		needle.transform = xf * Transform3D(Basis(), Vector3(0, 0, 0.006))
		add_child(needle)
		var nb := MeshKit.Builder.new()
		nb.box(Vector3(0.008, 0.055, 0.004), MeshKit.at(Vector3(0, 0.025, 0)), Color(1.0, 0.95, 0.85), true)
		nb.sphere(0.01, MeshKit.at(Vector3.ZERO), Color(0.9, 0.9, 0.95), 8)
		needle.add_child(MeshKit.instance(nb.build(), false))
		needles.append(needle)
	add_child(MeshKit.instance(face.build(), false))


func _build_radar() -> void:
	radar_root = Node3D.new()
	radar_root.name = "Radar"
	var rp := DASH_XF * Vector3(RADAR_LOCAL.x, 0.03, RADAR_LOCAL.y)
	radar_root.position = rp + Vector3(0, 0.12, 0)
	add_child(radar_root)
	var disc := MeshKit.Builder.new()
	disc.disc(RADAR_R, MeshKit.at(Vector3.ZERO), Color(0.1, 0.35, 0.5), 28, false, true)
	disc.torus(RADAR_R, 0.003, MeshKit.at(Vector3.ZERO), Color(0.3, 0.9, 1.0), 28, 3)
	disc.torus(RADAR_R * 0.5, 0.002, MeshKit.at(Vector3.ZERO), Color(0.2, 0.6, 0.8), 24, 3)
	disc.box(Vector3(0.004, 0.002, RADAR_R * 2.0), MeshKit.at(Vector3.ZERO), Color(0.2, 0.6, 0.8))
	disc.box(Vector3(RADAR_R * 2.0, 0.002, 0.004), MeshKit.at(Vector3.ZERO), Color(0.2, 0.6, 0.8))
	disc.cone(0.012, 0.03, MeshKit.at(Vector3(0, 0.005, 0), Vector3(1, 1, 1.4), Vector3(-PI * 0.5, 0, 0)), Color(0.4, 1.0, 0.6))
	radar_ring = MeshKit.instance(disc.build(MeshKit.additive_material()), false)
	radar_root.add_child(radar_ring)
	var blip := SphereMesh.new()
	blip.radius = 0.008
	blip.height = 0.016
	blip.radial_segments = 8
	blip.rings = 4
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.vertex_color_use_as_albedo = true
	blip.material = bm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = blip
	mm.instance_count = MAX_BLIPS
	mm.visible_instance_count = 0
	radar_blips = MultiMeshInstance3D.new()
	radar_blips.multimesh = mm
	radar_blips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	radar_root.add_child(radar_blips)


func _build_reticle() -> void:
	reticle = Node3D.new()
	reticle.name = "Reticle"
	var b := MeshKit.Builder.new()
	b.torus(0.16, 0.012, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.45, 0.4), 24, 4, true)
	for k in 4:
		var a := k * PI * 0.5
		b.box(Vector3(0.02, 0.09, 0.01), MeshKit.at(Vector3(cos(a) * 0.22, sin(a) * 0.22, 0), Vector3.ONE, Vector3(0, 0, a + PI * 0.5)), Color(1.0, 0.45, 0.4), true)
	var mi := MeshKit.instance(b.build(), false)
	mi.layers = VR_LAYER
	reticle.add_child(mi)
	reticle.visible = false
	add_child(reticle)


## World-locked text on the window, about 3 m from the eyes, facing them. VR layer only.
func _build_hud() -> void:
	var defs := {
		"objective": [Vector3(0.0, 2.3, -11.55), 0.095, "accent", true, 2.6],
		"alert": [Vector3(0.0, 2.04, -11.55), 0.075, Color(1.0, 0.55, 0.45), true, 2.6],
		"left": [Vector3(-1.75, 1.8, -11.3), 0.068, "text", true, 1.3],
		"right": [Vector3(1.75, 1.8, -11.3), 0.068, "text", true, 1.3],
		"hover": [Vector3(0.0, 1.0, -11.4), 0.06, Color(0.7, 0.95, 1.0), false, 2.4],
	}
	for k in defs:
		var d: Array = defs[k]
		var l := UiKit.label3d("", float(d[1]), d[2], bool(d[3]), float(d[4]))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = d[0]
		l.rotation.y = atan2(EYE.x - l.position.x, EYE.z - l.position.z)
		l.layers = VR_LAYER
		add_child(l)
		hud[k] = l


## Camera-attached comfort vignette + fade (VR only; harmless without a headset).
func attach_vignette(cam: Node3D) -> void:
	if vignette != null or cam == null:
		return
	vignette = MeshInstance3D.new()
	vignette.name = "ComfortVignette"
	var s := SphereMesh.new()
	s.radius = 0.35
	s.height = 0.7
	s.radial_segments = 24
	s.rings = 12
	vignette.mesh = s
	vignette_mat = ShaderMaterial.new()
	vignette_mat.shader = Shader.new()
	vignette_mat.shader.code = VIGNETTE_SHADER
	vignette_mat.render_priority = 100
	vignette.material_override = vignette_mat
	vignette.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vignette.layers = VR_LAYER
	vignette.visible = false
	cam.add_child(vignette)


## Repaint the window frame trim.
func set_paint(id: String) -> void:
	if id == paint_id:
		return
	paint_id = id
	if frame_mi != null:
		frame_mi.mesh = _static_mesh()


# --- Input: VR -------------------------------------------------------------------------------------

## Host with a VrRig: read the gloves and the controller. Returns the buttons pressed this frame.
func update_vr(delta: float, rig: VrRig) -> Array[String]:
	var pressed: Array[String] = []
	var to_local := global_transform.affine_inverse()
	var hands: Array[Vector3] = [to_local * rig.hand_point(VrRig.LEFT), to_local * rig.hand_point(VrRig.RIGHT)]
	# --- flight stick ---
	var stick_top := _stick_handle()
	if stick_hand == VrRig.RIGHT and not rig.trigger_down():
		_release_stick(rig)
	elif stick_hand == VrRig.LEFT and hands[0].distance_to(stick_top) > 0.2:
		_release_stick(rig)
	if stick_hand < 0:
		if rig.trigger_pressed() and hands[1].distance_to(stick_top) < GRAB_R and throttle_hand != VrRig.RIGHT:
			_grab_stick(rig, VrRig.RIGHT, hands[1])
		elif _dwell("stick", hands[0].distance_to(stick_top) < TOUCH_GRAB_R, delta) and throttle_hand != VrRig.LEFT:
			_grab_stick(rig, VrRig.LEFT, hands[0])
	if stick_hand >= 0:
		var d := hands[stick_hand] - _grab_hand_pos
		var target := Vector2(_axis(d.x), _axis(d.y))
		steer = steer.lerp(target, 1.0 - exp(-18.0 * delta))
		rig.pulse(stick_hand, 0.05 + 0.15 * steer.length(), 0.02)
	else:
		var sv := rig.stick_left()
		steer = steer.lerp(sv, 1.0 - exp(-10.0 * delta))
	# --- throttle ---
	var knob := _throttle_knob()
	if throttle_hand == VrRig.RIGHT and not rig.trigger_down():
		_release_throttle(rig)
	elif throttle_hand == VrRig.LEFT and hands[0].distance_to(knob) > 0.2:
		_release_throttle(rig)
	if throttle_hand < 0:
		if rig.trigger_pressed() and hands[1].distance_to(knob) < GRAB_R and stick_hand != VrRig.RIGHT:
			_grab_throttle_with(rig, VrRig.RIGHT, hands[1])
		elif _dwell("throttle", hands[0].distance_to(knob) < TOUCH_GRAB_R, delta) and stick_hand != VrRig.LEFT:
			_grab_throttle_with(rig, VrRig.LEFT, hands[0])
	if throttle_hand >= 0:
		var before := throttle
		throttle = clampf(_grab_throttle - (hands[throttle_hand].z - _grab_hand_pos.z) / THROTTLE_RANGE, 0.0, 1.0)
		if int(before * 10.0) != int(throttle * 10.0):
			rig.pulse(throttle_hand, 0.25, 0.02)
	else:
		var ry := rig.stick_right().y
		if absf(ry) > 0.2:
			throttle = clampf(throttle + ry * delta * 0.7, 0.0, 1.0)
	# --- buttons (touch with either glove) ---
	for id in buttons:
		var bt: Dictionary = buttons[id]
		var top: Vector3 = bt["top"]
		var r: float = bt["r"]
		var near := -1
		for h in 2:
			if hands[h].distance_to(top) < r + 0.035:
				near = h
		if near >= 0 and not bool(bt["latched"]) and (near != stick_hand and near != throttle_hand):
			bt["latched"] = true
			bt["down_t"] = 0.25
			pressed.append(str(id))
			rig.pulse(near, 0.6, 0.06)
		elif near < 0 and bool(bt["latched"]):
			var far := true
			for h in 2:
				if hands[h].distance_to(top) < r + 0.07:
					far = false
			if far:
				bt["latched"] = false
	if rig.a_pressed():
		pressed.append("torpedo")
	# --- hover help on the window ---
	hover_text = ""
	var best := 0.16
	for id in buttons:
		var bt2: Dictionary = buttons[id]
		for h in 2:
			var dd: float = hands[h].distance_to(bt2["top"])
			if dd < best:
				best = dd
				hover_text = String(bt2["text"])
	for h in 2:
		if hands[h].distance_to(stick_top) < best and stick_hand < 0:
			best = hands[h].distance_to(stick_top)
			hover_text = "FLIGHT STICK: hold the TRIGGER (or rest your hand) and move it to steer"
		if hands[h].distance_to(knob) < best and throttle_hand < 0:
			best = hands[h].distance_to(knob)
			hover_text = "THROTTLE: grab it and push forward to go faster"
	if stick_hand >= 0:
		hover_text = "STEERING  -  let go to stop"
	elif throttle_hand >= 0:
		hover_text = "THROTTLE %d%%" % int(round(throttle * 100.0))
	for p in pressed:
		button_pressed.emit(p)
	return pressed


func _axis(v: float) -> float:
	var a := absf(v)
	if a < 0.012:
		return 0.0
	return signf(v) * clampf((a - 0.012) / (STICK_RANGE - 0.012), 0.0, 1.0)


func _dwell(which: String, inside: bool, delta: float) -> bool:
	var t: float = _left_touch[which]
	t = t + delta if inside else 0.0
	_left_touch[which] = t
	return t > 0.18


func _grab_stick(rig: VrRig, h: int, at: Vector3) -> void:
	stick_hand = h
	_grab_hand_pos = at
	rig.pulse(h, 0.5, 0.05)
	UiKit.sound("ui_toggle", -6.0)


func _release_stick(rig: VrRig) -> void:
	if stick_hand >= 0:
		rig.pulse(stick_hand, 0.2, 0.03)
	stick_hand = -1
	_left_touch["stick"] = -0.6  # don't instantly re-grab with a resting left hand


func _grab_throttle_with(rig: VrRig, h: int, at: Vector3) -> void:
	throttle_hand = h
	_grab_hand_pos = at
	_grab_throttle = throttle
	rig.pulse(h, 0.5, 0.05)
	UiKit.sound("ui_toggle", -6.0)


func _release_throttle(rig: VrRig) -> void:
	if throttle_hand >= 0:
		rig.pulse(throttle_hand, 0.2, 0.03)
	throttle_hand = -1
	_left_touch["throttle"] = -0.6


## Drop anything held (pause, hyperjump, a new screen).
func release_all() -> void:
	stick_hand = -1
	throttle_hand = -1


func _stick_handle() -> Vector3:
	return STICK_BASE + stick_pivot.basis * Vector3(0, 0.23, 0)


func _throttle_knob() -> Vector3:
	return THROTTLE_BASE + throttle_pivot.basis * Vector3(0, LEVER, 0)


# --- Input: flat captain (a TV seat in local play) ------------------------------------------------

## Pad / keyboard: left stick steers, RT / LT throttle, A torpedo, X shields, Y hyperjump, B horn,
## d-pad crew calls. Returns the buttons pressed.
func update_flat(delta: float, party: Node, slot: int) -> Array[String]:
	var pressed: Array[String] = []
	var mv: Vector2 = party.stick(slot, "move")
	steer = steer.lerp(Vector2(mv.x, -mv.y), 1.0 - exp(-10.0 * delta))
	var up: float = party.trigger(slot, "rt") - party.trigger(slot, "lt")
	throttle = clampf(throttle + up * delta * 0.6, 0.0, 1.0)
	var map := {"accept": "torpedo", "x": "shields", "y": "jump", "back": "horn", "up": "call_power", "right": "call_torpedo",
		"left": "call_scan", "down": "call_repair"}
	for action in map:
		if party.just_pressed(slot, action):
			var id: String = map[action]
			pressed.append(id)
			var bt: Dictionary = buttons[id]
			bt["down_t"] = 0.25
	for p in pressed:
		button_pressed.emit(p)
	return pressed


# --- Showing state (every machine) ---------------------------------------------------------------

## Animate the levers and buttons, and the vignette/fade (lateral = how fast the ship slides, 0..1).
func tick(delta: float, lateral: float) -> void:
	_t += delta
	stick_pivot.basis = Basis.from_euler(Vector3(steer.y * 0.38, 0.0, -steer.x * 0.38))
	var a := lerpf(0.45, -0.6, throttle)
	throttle_pivot.basis = Basis(Vector3.RIGHT, a)
	for id in buttons:
		var bt: Dictionary = buttons[id]
		var dt: float = bt["down_t"]
		if dt > 0.0:
			dt = maxf(0.0, dt - delta)
			bt["down_t"] = dt
		var mi: MeshInstance3D = bt["mesh"]
		mi.position.y = -0.018 if dt > 0.0 else 0.0
		var m: StandardMaterial3D = bt["mat"]
		var lvl := 0.55
		match String(bt["state"]):
			"ready":
				lvl = 1.05 + 0.35 * sin(_t * 7.0)
			"off":
				lvl = 0.22
			"busy":
				lvl = 0.8
		if dt > 0.0:
			lvl = 1.6
		m.albedo_color = Color(lvl, lvl, lvl)
	if radar_ring != null:
		radar_ring.rotation.y = 0.0
	# Comfort vignette: darken the edges while the outside slides fast, and the warp fade.
	_vig = lerpf(_vig, clampf(lateral, 0.0, 1.0), 1.0 - exp(-4.0 * delta))
	_fade = move_toward(_fade, _fade_target, delta * 1.6)
	if vignette != null:
		vignette.visible = _vig > 0.02 or _fade > 0.01
		vignette_mat.set_shader_parameter("strength", _vig * 0.75)
		vignette_mat.set_shader_parameter("fade", _fade)


## Fade the VR view (hyperjump): 0 = clear, 1 = full fade to light blue.
func set_fade(target: float) -> void:
	_fade_target = clampf(target, 0.0, 1.0)


func button_state(id: String, state: String) -> void:
	if buttons.has(id):
		(buttons[id] as Dictionary)["state"] = state


## Show that a button was pressed (TV machine mirrors, flat captain).
func flash_button(id: String) -> void:
	if buttons.has(id):
		(buttons[id] as Dictionary)["down_t"] = 0.25


## Dials: hull, shields, hyperdrive charge, speed (each 0..1).
func set_dials(vals: Array) -> void:
	for k in mini(vals.size(), needles.size()):
		var f := clampf(float(vals[k]), 0.0, 1.0)
		var target := lerpf(2.2, -2.2, f)
		var n := needles[k]
		var cur := n.rotation.z
		n.rotation.z = lerpf(cur, target, 0.2)


## Radar blips: [Vector3 position relative to the ship (world units), Color] pairs.
func set_blips(blips: Array) -> void:
	var mm := radar_blips.multimesh
	var n := mini(blips.size(), MAX_BLIPS)
	for i in n:
		var b: Array = blips[i]
		var p: Vector3 = b[0]
		var c: Color = b[1]
		var v := Vector3(p.x, p.y * 0.4, p.z) / RADAR_RANGE * RADAR_R
		var flat := Vector2(v.x, v.z)
		if flat.length() > RADAR_R:
			flat = flat.normalized() * RADAR_R
		var s := 1.6 if b.size() > 2 and bool(b[2]) else 1.0
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), Vector3(flat.x, clampf(v.y, -0.04, 0.06), flat.y)))
		mm.set_instance_color(i, c)
	mm.visible_instance_count = n


## The aiming reticle (torpedo lock) in the steering direction, about 4 m out. Hidden if !on.
func set_reticle(on: bool, locked: bool) -> void:
	reticle.visible = on
	if on:
		var dir := aim_dir()
		reticle.position = EYE + dir * 4.0
		reticle.basis = Basis.looking_at(-dir, Vector3.UP)
		reticle.scale = Vector3.ONE * (0.8 if locked else 1.0)


## Where the captain is aiming: forward, tilted by the steering (for torpedo locks).
func aim_dir() -> Vector3:
	return Vector3(steer.x * 0.32, steer.y * 0.22, -1.0).normalized()


## Window HUD text (only changed lines are touched).
func set_hud(key: String, text: String, color: Variant = null) -> void:
	if not hud.has(key):
		return
	var l: Label3D = hud[key]
	var cache_key := text + (str(color) if color != null else "")
	if String(_hud_cache.get(key, "\u0001")) == cache_key:
		return
	_hud_cache[key] = cache_key
	l.text = text
	if color != null:
		l.modulate = UiKit.color_of(color)


func set_alert_light(alert: int) -> void:
	if light == null:
		return
	if alert == 2:
		light.light_color = Color(1.0, 0.35, 0.3).lerp(Color(1.0, 0.85, 0.75), 0.5 + 0.5 * sin(_t * 6.0))
	elif alert == 1:
		light.light_color = Color(1.0, 0.8, 0.5)
	else:
		light.light_color = Color(1.0, 0.9, 0.78)
