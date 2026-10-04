extends Node3D
## CRYSTAL SAGA: the VR player IS the Hero (host / local with core/vr_rig.gd only).
## - A real sword in the right hand (blade along the controller's pointing direction) and a small
##   round shield on the left glove (kept clear of the wrist MENU button).
## - A little status panel on the sword's crossguard: HP / MP, the CRYSTAL gauge and what to do now.
##   It's where the player always looks, it's held at arm's length, and it's never on the face.
## - Comfort: a soft vignette while the stick moves you or you snap-turn, and a black fade for
##   battle transitions and area changes (the only thing attached to the camera).
## - Battle, real time:
##     point the sword at a monster to target it;
##     when the blade glows (your turn), SWING - in the gold of the timing ring = critical hit;
##     hold the trigger and DRAW a rune: circle = Fire, zigzag = Thunder, a line UP = Cure;
##     when a monster winds up at you, RAISE your left hand (shield) - just in time = perfect parry;
##     when the CRYSTAL gauge is full, raise BOTH hands up high to call a giant guardian.
## Every gesture is measured relative to the head (no calibrated rest pose) with generous margins.

const VrRig := preload("res://core/vr_rig.gd")
const UiKit := preload("res://core/ui_kit.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Data := preload("res://games/crystal_saga/data.gd")

const VIGNETTE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, depth_test_disabled, blend_mix, fog_disabled;
uniform float strength = 0.0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	vec3 d = normalize(lp);
	float edge = 1.0 - smoothstep(0.42, 0.88, -d.z);
	ALBEDO = vec3(0.02, 0.02, 0.05);
	ALPHA = clamp(edge * strength, 0.0, 0.9);
}
"""
const SWING_SPEED := 2.6  # sword tip m/s that counts as a swing
const SWING_COOLDOWN := 0.45
const BLOCK_DROP := 0.5  # left hand within this much below the eyes = shield up
const SUMMON_HOLD := 0.45

var main: Node
var rig: VrRig
var sword: Node3D
var sword_mesh: MeshInstance3D
var shield: Node3D
var shield_glow: MeshInstance3D
var hilt: Label3D
var vignette_mat: ShaderMaterial
var fader: MeshInstance3D
var fader_mat: StandardMaterial3D
var trail_mi: MeshInstance3D
var trail_im: ImmediateMesh
var trail: PackedVector3Array = PackedVector3Array()  # world points of the rune being drawn
var drawing := false
var charged_look := false
var turn_flash := 0.0
var _swing_cd := 0.0
var _tip_prev := Vector3.ZERO
var _tip_fast := 0
var _raised := false
var raised_since := -10.0
var _summon_hold := 0.0
var _clock := 0.0
var _hilt_t := 0.0
var _full_t := 0.0
var _last_snap_x := 0.0
var swings := 0  # stats for bots
var runes_cast := 0
var parries := 0


func _ready() -> void:
	rig = main.vr_rig
	rig.camera.cull_mask = 0xFFFFF & ~VrRig.AVATAR_LAYER  # never see your own TV body
	sword = Node3D.new()
	sword.name = "Sword"
	rig.hand_r.add_child(sword)
	sword.rotation = Vector3(-0.12, 0, 0)  # a touch upwards, like a held sword
	sword_mesh = MeshKit.instance(main.fx.sword_mesh(false), false)
	sword.add_child(sword_mesh)
	hilt = UiKit.label3d("", 0.017, "text", true, 0.2)
	hilt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hilt.position = Vector3(0, 0.05, -0.02)
	hilt.rotation = Vector3(-1.05, 0, 0)  # faces up and back towards the eyes
	sword.add_child(hilt)
	shield = Node3D.new()
	shield.name = "Shield"
	rig.hand_l.add_child(shield)
	shield.add_child(MeshKit.instance(main.fx.shield_mesh(), false))
	shield_glow = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.17
	sm.height = 0.06
	sm.radial_segments = 16
	sm.rings = 4
	shield_glow.mesh = sm
	shield_glow.rotation.x = PI * 0.5
	shield_glow.position = Vector3(0, 0, -0.07)
	shield_glow.material_override = MeshKit.material(Color(0.5, 0.85, 1.0, 0.45), 2.5)
	shield_glow.visible = false
	shield.add_child(shield_glow)
	_build_vignette()
	_build_fader()
	trail_im = ImmediateMesh.new()
	trail_mi = MeshInstance3D.new()
	trail_mi.mesh = trail_im
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.vertex_color_use_as_albedo = true
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	tm.disable_fog = true
	trail_mi.material_override = tm
	trail_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trail_mi)


func _build_vignette() -> void:
	var v := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	sm.radial_segments = 16
	sm.rings = 8
	v.mesh = sm
	vignette_mat = ShaderMaterial.new()
	vignette_mat.shader = Shader.new()
	vignette_mat.shader.code = VIGNETTE_SHADER
	vignette_mat.render_priority = 90
	vignette_mat.set_shader_parameter("strength", 0.0)
	v.material_override = vignette_mat
	v.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	v.layers = 1
	rig.camera.add_child(v)


func _build_fader() -> void:
	fader = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	sm.radial_segments = 12
	sm.rings = 6
	fader.mesh = sm
	fader_mat = StandardMaterial3D.new()
	fader_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fader_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fader_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	fader_mat.no_depth_test = true
	fader_mat.render_priority = 120
	fader_mat.disable_fog = true
	fader_mat.albedo_color = Color(0, 0, 0, 0)
	fader.material_override = fader_mat
	fader.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fader.visible = false
	rig.camera.add_child(fader)


## Fade the view to `alpha` (0 clear .. 1 black) over `time` seconds.
func fade(alpha: float, time: float, color: Color = Color(0, 0, 0)) -> void:
	fader.visible = true
	fader_mat.albedo_color = Color(color.r, color.g, color.b, fader_mat.albedo_color.a)
	var tw := fader.create_tween()
	tw.tween_property(fader_mat, "albedo_color:a", alpha, time)
	if alpha <= 0.01:
		tw.tween_callback(func() -> void: fader.visible = false)


# --- Per frame --------------------------------------------------------------------------------------

func update(delta: float) -> void:
	_clock += delta
	_comfort(delta)
	_hilt_t -= delta
	if _hilt_t <= 0.0:
		_hilt_t = 0.2
		_update_hilt()
	var in_battle: bool = main.phase() == "battle" and main.battle.active
	if in_battle:
		_battle(delta)
	else:
		if drawing:
			_end_rune(false)
		shield_glow.visible = false
		_set_charged(false)
		_track_tip(delta)


func _comfort(delta: float) -> void:
	var stick := rig.stick_left().length() if main.phase() == "explore" else 0.0
	var sx := rig.stick_right().x
	if absf(sx) > 0.7 and absf(_last_snap_x) <= 0.7 and rig.turn_mode == "snap":
		turn_flash = 0.55
	_last_snap_x = sx
	turn_flash = maxf(0.0, turn_flash - delta * 2.2)
	var target := clampf(stick * 0.6 + turn_flash, 0.0, 0.75)
	var cur: float = vignette_mat.get_shader_parameter("strength")
	vignette_mat.set_shader_parameter("strength", lerpf(cur, target, 1.0 - exp(-8.0 * delta)))


func _update_hilt() -> void:
	var m: Dictionary = main.member(0)
	if m.is_empty():
		hilt.text = ""
		return
	var s: Dictionary = Data.stats(m)
	var hp := int(m.get("hp", 0))
	var mhp := int(s["mhp"])
	var line1 := "HP %d/%d   MP %d" % [hp, mhp, int(m.get("mp", 0))]
	var cr := int(main.net.state_get("crystal", 0))
	var line2 := "CRYSTAL %d%%" % cr if cr < 100 else "CRYSTAL FULL!"
	var line3 := ""
	if main.phase() == "battle" and main.battle.active:
		if bool(m.get("ko", false)):
			line3 = "KO... friends can help!"
		elif main.battle.hero_ready():
			line3 = "SWING or DRAW!"
		else:
			line3 = "charging..."
	elif main.phase() == "explore":
		var obj: Array = main.net.state_get("objective", [])
		if not obj.is_empty():
			line3 = String(obj[obj.size() - 1])
	hilt.text = line1 + "\n" + line2 + ("\n" + line3 if line3 != "" else "")
	hilt.modulate = UiKit.HP_LOW.lightened(0.2) if hp < mhp * 0.3 else UiKit.TEXT


func _set_charged(on: bool) -> void:
	if on == charged_look:
		return
	charged_look = on
	sword_mesh.mesh = main.fx.sword_mesh(on)
	if on:
		rig.pulse(VrRig.RIGHT, 0.6, 0.12)
		main.sfx.play("power_up", -10.0, 1.4)


# --- Battle -----------------------------------------------------------------------------------------

func _battle(delta: float) -> void:
	var b: Node = main.battle
	var ko := bool(main.member(0).get("ko", false))
	_set_charged(b.hero_ready() and not ko)
	_update_target()
	# Rune drawing: hold the trigger.
	if rig.trigger_down() and not ko:
		if not drawing:
			drawing = true
			trail = PackedVector3Array()
		var p := rig.hand_point(VrRig.RIGHT)
		if trail.is_empty() or trail[trail.size() - 1].distance_to(p) > 0.012:
			if trail.size() < 160:
				trail.append(p)
		_draw_trail()
	elif drawing:
		_end_rune(true)
	# Sword swings (not while drawing).
	_swing_cd = maxf(0.0, _swing_cd - delta)
	var fast := _track_tip(delta)
	if fast and not drawing and _swing_cd <= 0.0 and not ko:
		_swing_cd = SWING_COOLDOWN
		swings += 1
		if b.hero_ready():
			b.hero_slash()
			rig.pulse(VrRig.RIGHT, 0.9, 0.1)
		else:
			main.sfx.play("swish", -8.0)
			main.hint_vr("wait_glow", "Wait until your sword GLOWS, then swing!")
	# Shield: left hand raised (relative to the eyes) = blocking.
	var head := rig.head_position()
	var up := rig.hand_l.global_position.y > head.y - BLOCK_DROP
	if up and not _raised:
		raised_since = _clock
	_raised = up
	var threatened: bool = b.hero_threatened()
	shield_glow.visible = threatened or (_raised and _clock - raised_since < 0.6)
	if threatened and not _raised:
		rig.pulse(VrRig.LEFT, 0.25, 0.03)
	# Summon: both hands up high.
	var both := rig.hand_l.global_position.y > head.y - 0.02 and rig.hand_r.global_position.y > head.y - 0.02
	if b.can_summon() and not ko:
		_full_t += delta
		if _full_t > 1.0:
			main.hint_vr("summon_pose", "CRYSTAL FULL! Raise BOTH hands up high to call a guardian!")
		if both:
			_summon_hold += delta
			if _summon_hold > SUMMON_HOLD:
				_summon_hold = 0.0
				rig.pulse(VrRig.LEFT, 1.0, 0.25)
				rig.pulse(VrRig.RIGHT, 1.0, 0.25)
				b.summon(0)
		else:
			_summon_hold = 0.0
	else:
		_full_t = 0.0
		_summon_hold = 0.0


## True on the frame the sword tip starts moving fast enough to count as a swing.
func _track_tip(delta: float) -> bool:
	var tip := sword.global_transform * Vector3(0, 0, -0.8)
	var v := (tip - _tip_prev).length() / maxf(delta, 0.001)
	_tip_prev = tip
	if v > SWING_SPEED:
		_tip_fast += 1
	else:
		_tip_fast = 0
	return _tip_fast == 2


## Point the sword at a monster to target it (hysteresis so it doesn't flicker).
func _update_target() -> void:
	var b: Node = main.battle
	var from := rig.hand_r.global_position
	var dir := -sword.global_basis.z
	var best := -1
	var best_a := deg_to_rad(28.0)
	var cur: int = b.hero_target
	var cur_a := INF
	for uid in b.alive_enemy_ids():
		var c: Vector3 = main.bview.enemy_center(int(uid))
		var a := dir.angle_to(c - from)
		if int(uid) == cur:
			cur_a = a
		if a < best_a:
			best_a = a
			best = int(uid)
	if best >= 0 and best != cur and (cur_a == INF or best_a < cur_a - deg_to_rad(6.0)):
		b.set_hero_target(best)


## The block quality right now: "perfect" (shield raised just in time), "block" or "none".
func block_result() -> String:
	if not _raised:
		return "none"
	if _clock - raised_since < 0.65:
		parries += 1
		return "perfect"
	return "block"


# --- Runes ------------------------------------------------------------------------------------------

func _draw_trail() -> void:
	trail_im.clear_surfaces()
	if trail.size() < 2:
		return
	var cam := rig.head_position()
	var col := Color(1.0, 0.85, 0.4) if main.battle.hero_ready() else Color(0.55, 0.6, 0.8)
	trail_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(trail.size() - 1):
		var a := trail[i]
		var b := trail[i + 1]
		var seg := b - a
		var side := seg.cross(cam - a).normalized() * 0.012
		var c := Color(col.r, col.g, col.b, 0.35 + 0.65 * float(i) / trail.size())
		for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
			trail_im.surface_set_color(c)
			trail_im.surface_add_vertex(v)
	trail_im.surface_end()


func _end_rune(cast: bool) -> void:
	drawing = false
	var pts := trail
	trail = PackedVector3Array()
	trail_im.clear_surfaces()
	if not cast or pts.size() < 4:
		return
	var rune := recognize(pts, rig.head_forward())
	var centre := Vector3.ZERO
	for p in pts:
		centre += p
	centre /= float(pts.size())
	if rune == "":
		main.sfx.play("miss", -6.0)
		main.hint_vr("rune_help", "Runes: a CIRCLE = Fire, a ZIGZAG = Thunder, a line UP = Cure!")
		return
	var b: Node = main.battle
	if not b.hero_ready():
		main.sfx.play("ui_error", -6.0)
		main.hint_vr("wait_glow", "Wait until your sword GLOWS, then draw your rune!")
		return
	var skill := String(Data.HERO_RUNES[rune])
	if int(main.member(0).get("mp", 0)) < int(Data.SKILLS[skill]["mp"]):
		main.sfx.play("ui_error", -4.0)
		main.notify_vr("Not enough MP! Swing your sword instead.")
		return
	runes_cast += 1
	main.fx_all("rune", [centre, rune])
	rig.pulse(VrRig.RIGHT, 0.8, 0.2)
	b.hero_cast(skill)


## Recognise a rune from world points: "circle", "zigzag", "up" or "". Generous on purpose.
## The points are flattened onto the plane facing the player (x = right, y = up).
static func recognize(pts: PackedVector3Array, forward: Vector3) -> String:
	if pts.size() < 4:
		return ""
	var right := Vector3(-forward.z, 0, forward.x).normalized()
	var p2 := PackedVector2Array()
	var o := pts[0]
	for p in pts:
		var d := p - o
		p2.append(Vector2(d.dot(right), d.y))
	var path := 0.0
	var mn := p2[0]
	var mx := p2[0]
	for i in range(1, p2.size()):
		path += p2[i].distance_to(p2[i - 1])
		mn = mn.min(p2[i])
		mx = mx.max(p2[i])
	var size := mx - mn
	var span := maxf(size.x, size.y)
	if path < 0.12 or span < 0.08:
		return ""
	var end := p2[p2.size() - 1]
	var disp := end - p2[0]
	# A line UP.
	if disp.y > 0.14 and absf(disp.x) < disp.y * 0.65 and path < disp.length() * 1.6:
		return "up"
	# Resample to even steps for the turning / reversal tests.
	var rs := PackedVector2Array([p2[0]])
	var acc := 0.0
	for i in range(1, p2.size()):
		acc += p2[i].distance_to(p2[i - 1])
		if acc >= 0.025:
			rs.append(p2[i])
			acc = 0.0
	if rs.size() < 4:
		return ""
	var turn := 0.0
	var abs_turn := 0.0
	for i in range(1, rs.size() - 1):
		var a := rs[i] - rs[i - 1]
		var b := rs[i + 1] - rs[i]
		if a.length() > 0.0001 and b.length() > 0.0001:
			var ang := a.angle_to(b)
			turn += ang
			abs_turn += absf(ang)
	var closed := disp.length() < maxf(0.14, span * 0.45)
	var aspect := size.x / maxf(size.y, 0.001)
	if closed and size.x > 0.09 and size.y > 0.09 and aspect > 0.35 and aspect < 2.8 and absf(turn) > 3.8:
		return "circle"
	# Zigzag: the horizontal direction flips at least twice with real strokes in between.
	var flips := 0
	var dir_sign := 0
	var run := 0.0
	for i in range(1, rs.size()):
		var dx := rs[i].x - rs[i - 1].x
		if absf(dx) < 0.004:
			continue
		var sgn := 1 if dx > 0.0 else -1
		if sgn == dir_sign:
			run += absf(dx)
		else:
			if dir_sign != 0 and run > 0.045:
				flips += 1
			dir_sign = sgn
			run = absf(dx)
	if run > 0.045 and dir_sign != 0 and flips >= 1:
		pass
	if flips >= 2:
		return "zigzag"
	if abs_turn > 6.0 and closed:
		return "circle"
	return ""


## Rune trail points for the TV view (resampled to at most 24, world space).
func trail_points() -> PackedVector3Array:
	if not drawing or trail.size() < 2:
		return PackedVector3Array()
	var out := PackedVector3Array()
	var step := maxi(1, trail.size() / 24)
	for i in range(0, trail.size(), step):
		out.append(Vector3(snappedf(trail[i].x, 0.005), snappedf(trail[i].y, 0.005), snappedf(trail[i].z, 0.005)))
	return out
