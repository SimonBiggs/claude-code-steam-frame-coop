extends Node3D
## The Titan's cockpit: the pilot's stable frame. It follows the mech's position and yaw only (never
## bobs, pitches or rolls), and the VR rig sits inside it. Contents:
## - Interior (one merged mesh): floor, seat, side consoles, dashboard, canopy struts and roof. The
##   head's outer shell is on Data.LAYER_EXTERIOR, which the VR camera doesn't draw: the pilot looks out
##   through a big open canopy over the city.
## - Holo displays (Data.LAYER_VR_ONLY, world-locked in the cockpit, never billboarded, 2.4-3 m from the
##   eyes): ARMOUR, ENERGY, the boss / objective boards, the arm-tool name, and a message line.
## - The TOOL LEVER on the left console (touch and push it: no buttons), with its knob in the tool colour.
## - Comfort: a head-locked vignette (not text) that darkens the edges while walking, turning and
##   dashing; "rattle" shakes the console instead of the camera; repair sparks at the canopy edge.

const Data := preload("res://games/mech_titans/data.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const UiKit := preload("res://core/ui_kit.gd")

## Lever knob position (cockpit space) and how far a hand pushes it to flip.
const LEVER_BASE := Vector3(-0.5, 0.72, -0.28)
const LEVER_LEN := 0.3
const LEVER_TOUCH := 0.15
const LEVER_PUSH := 0.09

var console: Node3D  ## shakes with rattle
var holo: Node3D
var armour_bar: MeshInstance3D
var energy_bar: MeshInstance3D
var boss_bar: MeshInstance3D
var boss_back: MeshInstance3D
var armour_label: Label3D
var energy_label: Label3D
var boss_label: Label3D
var objective_label: Label3D
var info_label: Label3D
var tool_label: Label3D
var message_label: Label3D
var warning_light: MeshInstance3D
var lever_pivot: Node3D
var lever_knob: MeshInstance3D
var vignette: MeshInstance3D
var _vig_mat: ShaderMaterial
var _rattle := 0.0
var _msg_t := 0.0
var _lever_hand := -1
var _lever_start := Vector3.ZERO
var _lever_angle := 0.0
var _lever_cool := 0.0
var _warn := false
var _t := 0.0
var _sparks: CPUParticles3D


func _ready() -> void:
	_build_interior()
	_build_holo()


func _build_interior() -> void:
	var mesh: ArrayMesh = ResCache.get_or_make("mt_cockpit_v2", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		var dark := Color(0.22, 0.24, 0.3)
		var mid := Color(0.36, 0.4, 0.48)
		var light := Color(0.75, 0.78, 0.85)
		var accent := Color(1.0, 0.75, 0.3)
		b.box(Vector3(2.6, 0.1, 2.4), MeshKit.at(Vector3(0, -0.05, 0.2)), dark)
		b.box(Vector3(2.2, 0.02, 0.08), MeshKit.at(Vector3(0, 0.01, -0.5)), accent)
		# Seat behind the pilot.
		b.rounded_box(Vector3(0.7, 0.18, 0.6), 0.06, MeshKit.at(Vector3(0, 0.5, 0.45)), mid)
		b.rounded_box(Vector3(0.7, 0.9, 0.15), 0.06, MeshKit.at(Vector3(0, 1.0, 0.8)), mid)
		b.box(Vector3(0.12, 0.5, 0.12), MeshKit.at(Vector3(0, 0.25, 0.45)), dark)
		# Side consoles (hip height), clear of the punching space in front.
		for sx in [-1.0, 1.0]:
			b.rounded_box(Vector3(0.35, 0.75, 1.3), 0.05, MeshKit.at(Vector3(sx * 0.95, 0.38, 0.0)), mid)
			b.box(Vector3(0.3, 0.04, 1.2), MeshKit.at(Vector3(sx * 0.95, 0.77, 0.0)), dark)
			for k in 4:
				b.box(Vector3(0.06, 0.03, 0.06), MeshKit.at(Vector3(sx * 0.95 + (k % 2) * 0.08 - 0.04, 0.8, -0.3 + k * 0.15)),
					[Color(1, 0.3, 0.3), Color(0.3, 1, 0.4), Color(0.3, 0.7, 1), Color(1, 0.85, 0.3)][k], true)
		# Front dashboard, below the canopy window.
		b.rounded_box(Vector3(2.4, 0.9, 0.5), 0.08, MeshKit.at(Vector3(0, 0.45, -1.05)), mid)
		b.wedge(Vector3(2.4, 0.25, 0.5), MeshKit.at(Vector3(0, 1.02, -1.05), Vector3.ONE, Vector3(0, PI, 0)), dark)
		b.box(Vector3(1.6, 0.03, 0.3), MeshKit.at(Vector3(0, 0.92, -0.86)), Color(0.1, 0.3, 0.45), true)
		# Canopy frame: a wide window in front and at the sides, roof above.
		var fz := -1.55
		b.box(Vector3(3.0, 0.12, 0.12), MeshKit.at(Vector3(0, 1.15, fz)), light)
		b.box(Vector3(3.0, 0.12, 0.12), MeshKit.at(Vector3(0, 2.55, fz + 0.2)), light)
		for sx2 in [-1.0, 1.0]:
			b.box(Vector3(0.12, 1.5, 0.12), MeshKit.at(Vector3(sx2 * 1.5, 1.85, fz + 0.1), Vector3.ONE, Vector3(-0.12, 0, 0)), light)
			b.box(Vector3(0.1, 0.1, 2.3), MeshKit.at(Vector3(sx2 * 1.5, 2.55, -0.4)), light)
			b.box(Vector3(0.1, 1.4, 0.1), MeshKit.at(Vector3(sx2 * 1.5, 1.85, 0.75)), light)
			b.box(Vector3(0.1, 0.1, 2.3), MeshKit.at(Vector3(sx2 * 1.5, 1.15, -0.4)), light)
			b.box(Vector3(0.08, 0.9, 1.8), MeshKit.at(Vector3(sx2 * 1.52, 0.55, -0.4)), dark)
		b.box(Vector3(3.0, 0.08, 2.4), MeshKit.at(Vector3(0, 2.62, -0.35)), dark)
		b.box(Vector3(0.7, 0.03, 0.7), MeshKit.at(Vector3(0, 2.57, -0.35)), Color(1.0, 0.95, 0.8), true)
		b.box(Vector3(3.0, 2.6, 0.1), MeshKit.at(Vector3(0, 1.3, 0.95)), dark)
		b.box(Vector3(1.8, 0.4, 0.04), MeshKit.at(Vector3(0, 2.0, 0.89)), accent)
		# Lever housing on the left console.
		b.rounded_box(Vector3(0.22, 0.12, 0.3), 0.04, MeshKit.at(LEVER_BASE + Vector3(0, -0.04, 0)), dark)
		return b.build())
	console = Node3D.new()
	console.name = "Console"
	add_child(console)
	var mi := MeshKit.instance(mesh, false)
	console.add_child(mi)
	lever_pivot = Node3D.new()
	lever_pivot.name = "Lever"
	lever_pivot.position = LEVER_BASE
	console.add_child(lever_pivot)
	var stick := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.03
	cm.height = LEVER_LEN
	cm.radial_segments = 8
	cm.rings = 1
	stick.mesh = cm
	stick.material_override = MeshKit.material(Color(0.7, 0.72, 0.78))
	stick.position = Vector3(0, LEVER_LEN * 0.5, 0)
	lever_pivot.add_child(stick)
	lever_knob = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.065
	sm.height = 0.13
	sm.radial_segments = 12
	sm.rings = 6
	lever_knob.mesh = sm
	lever_knob.material_override = MeshKit.material(Color(0.35, 0.75, 1.0), 1.0)
	lever_knob.position = Vector3(0, LEVER_LEN, 0)
	lever_pivot.add_child(lever_knob)
	warning_light = MeshInstance3D.new()
	var wl := SphereMesh.new()
	wl.radius = 0.06
	wl.height = 0.12
	wl.radial_segments = 10
	wl.rings = 5
	warning_light.mesh = wl
	warning_light.material_override = MeshKit.material(Color(1.0, 0.25, 0.2), 3.0)
	warning_light.position = Vector3(0, 2.5, -1.3)
	warning_light.visible = false
	console.add_child(warning_light)
	_sparks = CPUParticles3D.new()
	_sparks.one_shot = true
	_sparks.emitting = false
	_sparks.amount = 16
	_sparks.lifetime = 0.6
	_sparks.explosiveness = 0.9
	_sparks.spread = 180.0
	_sparks.initial_velocity_min = 1.0
	_sparks.initial_velocity_max = 2.5
	_sparks.gravity = Vector3(0, -4.0, 0)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.03, 0.03)
	bm.material = MeshKit.material(Color(0.6, 1.0, 0.6), 3.0)
	_sparks.mesh = bm
	_sparks.local_coords = true
	add_child(_sparks)


## A holo panel facing the eye point (0, 1.55, 0): position in cockpit space.
func _panel(pos: Vector3, size: Vector2, fill: Color) -> Node3D:
	var n := Node3D.new()
	holo.add_child(n)
	n.position = pos
	var to := Vector3(0, 1.55, 0) - pos
	var yaw := atan2(to.x, to.z)
	var pitch := atan2(-to.y, Vector2(to.x, to.z).length()) * 0.85
	n.rotation = Vector3(pitch, yaw, 0)
	var bg := UiKit.panel3d(size, fill, Color(0.4, 0.85, 1.0, 0.45), 0.05)
	bg.layers = Data.LAYER_VR_ONLY
	n.add_child(bg)
	return n


func _label(parent: Node3D, text: String, h: float, color: Variant, pos: Vector3, width: float = 0.0) -> Label3D:
	var l := UiKit.label3d(text, h, color, true, width)
	l.layers = Data.LAYER_VR_ONLY
	l.position = pos
	parent.add_child(l)
	return l


func _bar(parent: Node3D, pos: Vector3, size: Vector2, color: Color) -> MeshInstance3D:
	var back := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	back.mesh = qm
	back.material_override = _flat(Color(0.05, 0.07, 0.12, 0.9), 21)
	back.layers = Data.LAYER_VR_ONLY
	back.position = pos
	parent.add_child(back)
	var fill := MeshInstance3D.new()
	var qm2 := QuadMesh.new()
	qm2.size = size
	qm2.center_offset = Vector3(size.x * 0.5, 0, 0)
	fill.mesh = qm2
	fill.material_override = _flat(color, 22)
	fill.layers = Data.LAYER_VR_ONLY
	fill.position = pos + Vector3(-size.x * 0.5, 0, 0.004)
	parent.add_child(fill)
	return fill


func _flat(c: Color, prio: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.render_priority = prio  # depth-tested: hands in front of the dials must stay in front
	return m


func _build_holo() -> void:
	holo = Node3D.new()
	holo.name = "Holo"
	console.add_child(holo)
	var fill := Color(0.03, 0.08, 0.14, 0.55)
	# Left: armour + tool.
	var left := _panel(Vector3(-1.45, 1.25, -2.25), Vector2(0.95, 0.5), fill)
	left.name = "ArmourBoard"
	_label(left, "ARMOUR", 0.07, "dim", Vector3(-0.2, 0.15, 0.01))
	armour_label = _label(left, "100%", 0.09, "good", Vector3(0.25, 0.15, 0.01))
	armour_bar = _bar(left, Vector3(0, 0.0, 0.01), Vector2(0.8, 0.09), UiKit.GOOD)
	tool_label = _label(left, "TOOL: MEGA FIST", 0.055, Color(0.6, 0.85, 1.0), Vector3(0, -0.15, 0.01))
	# Right: energy + info (city damage / landmark).
	var right_p := _panel(Vector3(1.45, 1.25, -2.25), Vector2(0.95, 0.5), fill)
	right_p.name = "EnergyBoard"
	_label(right_p, "ENERGY", 0.07, "dim", Vector3(-0.2, 0.15, 0.01))
	energy_label = _label(right_p, "100%", 0.09, "info", Vector3(0.25, 0.15, 0.01))
	energy_bar = _bar(right_p, Vector3(0, 0.0, 0.01), Vector2(0.8, 0.09), UiKit.MP)
	info_label = _label(right_p, "CITY OK", 0.055, "dim", Vector3(0, -0.15, 0.01))
	# Top: the boss board (hidden without a boss).
	var top := _panel(Vector3(0, 2.75, -3.0), Vector2(1.7, 0.42), fill)
	top.name = "BossBoard"
	boss_label = _label(top, "", 0.085, Color(1.0, 0.55, 0.45), Vector3(0, 0.1, 0.01), 1.6)
	boss_bar = _bar(top, Vector3(0, -0.08, 0.01), Vector2(1.5, 0.1), Color(1.0, 0.35, 0.3))
	boss_back = top.get_child(0) as MeshInstance3D
	top.visible = false
	# Bottom: objective line.
	var bottom := _panel(Vector3(0, 0.62, -2.5), Vector2(1.8, 0.3), fill)
	bottom.name = "ObjectiveBoard"
	objective_label = _label(bottom, "", 0.065, "text", Vector3(0, 0, 0.01), 1.7)
	# Message line (big feedback words: PERFECT BLOCK!, x3!, DIZZY! PUNCH!).
	message_label = UiKit.label3d("", 0.16, "accent", true, 2.4)
	message_label.layers = Data.LAYER_VR_ONLY
	message_label.position = Vector3(0, 2.05, -3.0)
	message_label.rotation.x = 0.0
	holo.add_child(message_label)
	message_label.visible = false


## SIMPLE_MODE: no number boards, no objective text, no tool lever. What stays: the big headline word,
## the boss's health bar (no name) and the red warning light.
func simplify() -> void:
	for n in ["ArmourBoard", "EnergyBoard", "ObjectiveBoard"]:
		(holo.get_node(n) as Node3D).visible = false
	boss_label.visible = false
	lever_pivot.visible = false


# --- Per-frame values --------------------------------------------------------------------------------

func set_armour(v: float, vmax: float) -> void:
	var f := clampf(v / maxf(vmax, 1.0), 0.0, 1.0)
	armour_bar.scale.x = maxf(f, 0.001)
	armour_label.text = "%d%%" % int(round(f * 100.0))
	var c := UiKit.hp_color(f)
	armour_label.modulate = c
	(armour_bar.material_override as StandardMaterial3D).albedo_color = c
	_warn = f < 0.3


func set_energy(v: float, vmax: float) -> void:
	var f := clampf(v / maxf(vmax, 1.0), 0.0, 1.0)
	energy_bar.scale.x = maxf(f, 0.001)
	energy_label.text = "%d%%" % int(round(f * 100.0))


func set_tool(t: String) -> void:
	var info: Dictionary = Data.TOOL_INFO.get(t, {})
	tool_label.text = "TOOL: " + String(info.get("name", t.to_upper()))
	var c: Color = info.get("color", Color.WHITE)
	tool_label.modulate = c
	(lever_knob.material_override as StandardMaterial3D).albedo_color = c
	(lever_knob.material_override as StandardMaterial3D).emission = c


## Boss board: name (empty hides it) and 0..1 health.
func set_boss(boss_name: String, frac: float) -> void:
	var board := holo.get_node("BossBoard") as Node3D
	board.visible = boss_name != ""
	if boss_name != "":
		boss_label.text = boss_name
		boss_bar.scale.x = maxf(clampf(frac, 0.0, 1.0), 0.001)


func set_objective(text: String) -> void:
	objective_label.text = text


func set_info(text: String, color: Color = UiKit.TEXT_DIM) -> void:
	info_label.text = text
	info_label.modulate = color


## A big word in the middle of the canopy for a moment.
func message(text: String, color: Color = UiKit.ACCENT, time: float = 1.4) -> void:
	message_label.text = text
	message_label.modulate = color
	message_label.visible = true
	message_label.scale = Vector3.ONE * 1.25
	_msg_t = time


## Shake the console (not the camera): 0.2 bump .. 1 big hit.
func rattle(amount: float) -> void:
	_rattle = clampf(maxf(_rattle, amount), 0.0, 1.0)


## Repair sparks at the canopy edge, where the pilot sees them.
func sparks() -> void:
	_sparks.position = Vector3(randf_range(-1.3, 1.3), randf_range(1.2, 2.4), -1.5)
	_sparks.restart()
	_sparks.emitting = true


# --- The tool lever (VR: touch and push) -------------------------------------------------------------------

## Feed hand positions in cockpit space. Returns +1 / -1 when the lever flips forward / back, else 0.
func lever_update(hands_local: Array, delta: float) -> int:
	if not lever_pivot.visible:
		return 0
	_lever_cool = maxf(0.0, _lever_cool - delta)
	var knob := LEVER_BASE + Vector3(0, LEVER_LEN, 0)
	var flip := 0
	if _lever_hand < 0:
		for h in hands_local.size():
			var p: Vector3 = hands_local[h]
			if p.distance_to(knob) < LEVER_TOUCH and _lever_cool <= 0.0:
				_lever_hand = h
				_lever_start = p
		lever_knob.scale = Vector3.ONE
	if _lever_hand >= 0:
		var p2: Vector3 = hands_local[_lever_hand]
		var dz := p2.z - _lever_start.z
		_lever_angle = clampf(dz / LEVER_PUSH, -1.0, 1.0) * 0.5
		lever_knob.scale = Vector3.ONE * 1.25
		if absf(dz) > LEVER_PUSH:
			flip = -1 if dz > 0.0 else 1  # pushed forward (-z) = next tool
			_lever_hand = -1
			_lever_cool = 0.6
		elif p2.distance_to(knob) > LEVER_TOUCH * 2.2:
			_lever_hand = -1
	else:
		_lever_angle = lerpf(_lever_angle, 0.0, 1.0 - exp(-8.0 * delta))
	lever_pivot.rotation.x = -_lever_angle
	return flip


## Is a hand on the lever right now (so its motion isn't a punch)?
func lever_busy() -> bool:
	return _lever_hand >= 0


## Knob position in world space (bots reach for it).
func lever_knob_world() -> Vector3:
	return to_global(LEVER_BASE + Vector3(0, LEVER_LEN, 0))


# --- VR comfort vignette ---------------------------------------------------------------------------------

## Put a vignette sphere on the XR camera (darkens only the edges of the view; no text).
func attach_vignette(cam: Node3D) -> void:
	if vignette != null and is_instance_valid(vignette):
		return
	vignette = MeshInstance3D.new()
	vignette.name = "Vignette"
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	sm.radial_segments = 24
	sm.rings = 12
	vignette.mesh = sm
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, blend_mix, shadows_disabled;
uniform float strength = 0.0;
varying vec3 dir;
void vertex() { dir = VERTEX; }
void fragment() {
	float ang = acos(clamp(-normalize(dir).z, -1.0, 1.0));
	float inner = mix(1.4, 0.55, strength);
	float a = smoothstep(inner, inner + 0.35, ang) * clamp(strength * 1.6, 0.0, 1.0);
	ALBEDO = vec3(0.0);
	ALPHA = a;
}
"""
	_vig_mat = ShaderMaterial.new()
	_vig_mat.shader = sh
	_vig_mat.render_priority = 100
	vignette.material_override = _vig_mat
	vignette.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vignette.layers = Data.LAYER_VR_ONLY
	cam.add_child(vignette)


func set_vignette(strength: float) -> void:
	if _vig_mat != null:
		_vig_mat.set_shader_parameter("strength", clampf(strength, 0.0, 1.0))


func _process(delta: float) -> void:
	_t += delta
	if _rattle > 0.001:
		console.position = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.012 * _rattle
		_rattle = maxf(0.0, _rattle - delta * 2.5)
	else:
		console.position = Vector3.ZERO
	if _msg_t > 0.0:
		_msg_t -= delta
		message_label.scale = message_label.scale.lerp(Vector3.ONE, 1.0 - exp(-10.0 * delta))
		if _msg_t <= 0.0:
			message_label.visible = false
	warning_light.visible = _warn and fmod(_t, 0.6) < 0.3
