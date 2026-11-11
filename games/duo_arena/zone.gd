extends Node3D
## DUO ARENA zone: what arenagen.gd describes, built the same on every machine.
## - setup(layout, mode): the zone's colours (floor base + the director's resting mood colour), its seeded cover
##   pillars and hazard pads. Pads TELL (pulse bright for tell seconds; main sends "pad" [i, tell]), then BURST
##   (a plume; the host hurts and pushes players and monsters inside: main.on_pad_burst).
## - warn(pos, r, colour, secs): a pulsing ring on the floor that stays until a boss's attack lands (its TELL).
## - show_orbs(stage, ids, wait): the PICK orbs (picks.gd) in a row in front of the start: a glowing ball, a big
##   picture and a short name. Shoot one (Orb.hit) or walk into it (host: touch_step). take(i, slot) adds a little
##   coloured dot circling it. The middle orb glows brightest (taken for whoever doesn't choose).
## - NOVA, the little light-bot, floats over the middle (cheer() makes her bounce).
## - City lights (keepsakes): LIGHTS pylons far round the arena; one more is lit for every wave the family has ever
##   cleared (set_keepsakes), and a trophy orb on a plinth for every boss kind beaten.

const Gen := preload("res://games/duo_arena/arenagen.gd")
const Picks := preload("res://games/duo_arena/picks.gd")
const Bosses := preload("res://games/duo_arena/bosses.gd")
const StoryCard := preload("res://core/story_card.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const WorldScript := preload("res://games/duo_arena/world.gd")
const DecorScript := preload("res://games/duo_arena/decor.gd")

const ORB_Z := -3.5
const ORB_Y := 1.4
const ORB_GAP := 2.6
const TOUCH := 1.3
const PYLON_R := 27.0

var main
var lay := {}
var zone_id := ""
var mode := "brave"
var built: Node3D
var pad_rings: Array[MeshInstance3D] = []
var pad_clock: Array[float] = []
var pad_told: Array[bool] = []
var pad_glow: Array[float] = []
var orbs: Array = []
var orb_stage := ""
var nova: Node3D
var _warns: Array = []
var _t := 0.0
var _cheer := 0.0
var _keep_key := ""
var _keep_root: Node3D


## A pick orb: shots hit it (bullet.gd calls hit on bodies), the host decides.
class Orb extends StaticBody3D:
	var zone
	var index := 0
	var id := ""
	var ball: MeshInstance3D
	var dots: Node3D
	var shown := ""

	func hit(_dmg = 0.0, _dir = Vector3.ZERO, _k = 1.0, by = null) -> void:
		if zone != null and by != null:
			zone.main.on_orb_hit(index, by)


func _ready() -> void:
	name = "Zone"
	_build_nova()


func setup(new_lay: Dictionary, new_mode: String) -> void:
	lay = new_lay
	mode = new_mode
	zone_id = String(lay.get("zone", "neon"))
	var z := Gen.zone(zone_id)
	main.set_meta("zone_col", Vector3(z.line.r, z.line.g, z.line.b))
	var floor_mat: ShaderMaterial = main.get_meta("floor_mat") if main.has_meta("floor_mat") else null
	if floor_mat != null:
		floor_mat.set_shader_parameter("base_color", Vector3(z.base.r, z.base.g, z.base.b))
	if built != null:
		built.queue_free()
	built = Node3D.new()
	built.name = "Built"
	add_child(built)
	var accent: Color = z.line
	for p in lay.get("pillars", []):
		WorldScript.add_pillar(main, p, accent, built)
	pad_rings.clear()
	pad_clock.clear()
	pad_told.clear()
	pad_glow.clear()
	var col := pad_color()
	for d in lay.get("pads", []):
		var mi := MeshInstance3D.new()
		mi.mesh = _pad_mesh()
		mi.material_override = MeshKit.material(col, 1.2)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = (d.p as Vector3) + Vector3.UP * 0.04
		mi.scale = Vector3(float(d.r), 1.0, float(d.r))
		built.add_child(mi)
		pad_rings.append(mi)
		pad_clock.append(float(d.offset))
		pad_told.append(false)
		pad_glow.append(0.0)


func pad_color() -> Color:
	return Gen.hazard_numbers(String(Gen.zone(zone_id).hazard), mode).color


static func _pad_mesh() -> ArrayMesh:
	return ResCache.get_or_make("da_pad_v1", func() -> Resource:
		var b := MeshKit.builder()
		b.torus(0.92, 0.08, MeshKit.at(Vector3.ZERO), Color.WHITE, 28, 4)
		b.disc(0.75, MeshKit.at(Vector3.UP * 0.01), Color(0.55, 0.55, 0.55), 20)
		for k in 8:
			var a := k * TAU / 8.0
			b.sphere(0.06, MeshKit.at(Vector3(cos(a) * 0.5, 0.04, sin(a) * 0.5)), Color.WHITE, 6)
		return b.build()) as ArrayMesh


static func _ring_mesh() -> ArrayMesh:
	return ResCache.get_or_make("da_warn_ring_v1", func() -> Resource:
		var b := MeshKit.builder()
		b.torus(1.0, 0.07, MeshKit.at(Vector3.ZERO), Color.WHITE, 40, 4)
		b.torus(0.6, 0.04, MeshKit.at(Vector3.ZERO), Color.WHITE, 28, 4)
		b.torus(0.25, 0.03, MeshKit.at(Vector3.ZERO), Color.WHITE, 16, 4)
		return b.build()) as ArrayMesh


## Host / local: run the pad clocks while a wave fights.
func host_step(delta: float, active: bool) -> void:
	if not active or pad_rings.is_empty():
		return
	var tell := float(Gen.hazard_numbers(String(Gen.zone(zone_id).hazard), mode).tell)
	var pads: Array = lay.get("pads", [])
	for i in pads.size():
		pad_clock[i] -= delta
		if not pad_told[i] and pad_clock[i] <= tell:
			pad_told[i] = true
			main.on_pad_tell(i, tell)
		if pad_clock[i] <= 0.0:
			pad_clock[i] += float(pads[i].period)
			pad_told[i] = false
			main.on_pad_burst(i)


## Every machine: pad i glows for `secs` (about to burst).
func tell(i: int, secs: float) -> void:
	if i >= 0 and i < pad_glow.size():
		pad_glow[i] = secs


## Every machine: pad i bursts (a plume of the zone's colour).
func burst_fx(i: int) -> void:
	var pads: Array = lay.get("pads", [])
	if i < 0 or i >= pads.size():
		return
	var d: Dictionary = pads[i]
	var col := pad_color()
	var plume := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.4
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 16
	plume.mesh = cyl
	var mat := MeshKit.material(col, 3.0).duplicate() as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plume.material_override = mat
	plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plume.position = (d.p as Vector3)
	plume.scale = Vector3(float(d.r), 0.2, float(d.r))
	built.add_child(plume)
	var tw := plume.create_tween().set_parallel()
	tw.tween_property(plume, "scale", Vector3(float(d.r) * 0.8, 4.5, float(d.r) * 0.8), 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_property(plume, "position:y", 2.2, 0.25)
	tw.chain().tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tw.chain().tween_callback(plume.queue_free)
	main.burst((d.p as Vector3) + Vector3.UP * 0.5, col, 20, 0.18)


## Every machine: a pulsing warning ring at pos until the attack lands (secs).
func warn(pos: Vector3, radius: float, col: Color, secs: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh()
	mi.material_override = MeshKit.material(col, 3.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(pos.x, 0.08, pos.z)
	mi.scale = Vector3(radius * 0.2, 1.0, radius * 0.2)
	add_child(mi)
	_warns.append([mi, 0.0, maxf(secs, 0.3), radius])


# --- Pick orbs -------------------------------------------------------------------------------------------------

static func orb_spot(i: int, n: int) -> Vector3:
	return Vector3((i - (n - 1) * 0.5) * ORB_GAP, ORB_Y, ORB_Z)


func show_orbs(stage: String, ids: Array) -> void:
	clear_orbs()
	orb_stage = stage
	var mid := ids.size() / 2
	for i in ids.size():
		var d := Picks.find(stage, String(ids[i]))
		var col: Color = d.get("color", Color.WHITE)
		var o := Orb.new()
		o.zone = self
		o.index = i
		o.id = String(ids[i])
		o.name = "Orb%d" % i
		o.collision_layer = 4
		o.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.75
		cs.shape = sh
		o.add_child(cs)
		o.ball = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.6
		sm.height = 1.2
		sm.radial_segments = 16
		sm.rings = 8
		o.ball.mesh = sm
		var mat := MeshKit.material(col, 2.6 if i == mid else 1.2).duplicate() as StandardMaterial3D
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.55
		o.ball.material_override = mat
		o.ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		o.add_child(o.ball)
		o.add_child(_picture(String(d.get("pic", "star")), col))
		var l := Label3D.new()
		l.text = String(d.get("name", o.id))
		l.font_size = 64
		l.outline_size = 14
		l.pixel_size = 0.005
		l.modulate = col.lightened(0.4)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = Vector3(0, -0.95, 0)
		o.add_child(l)
		o.dots = Node3D.new()
		o.add_child(o.dots)
		o.position = orb_spot(i, ids.size())
		add_child(o)
		orbs.append(o)


## A billboard picture (StoryCard picture drawn into a small viewport).
func _picture(pic: String, col: Color) -> Sprite3D:
	const PX := 192
	var vp := SubViewport.new()
	vp.size = Vector2i(PX, PX)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var c := StoryCard.picture(pic, PX, col)
	vp.add_child(c)
	var s := Sprite3D.new()
	s.add_child(vp)
	s.texture = vp.get_texture()
	s.pixel_size = 1.0 / PX
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.no_depth_test = false
	s.render_priority = 2
	s.position = Vector3(0, 0, 0)
	return s


func clear_orbs() -> void:
	for o in orbs:
		if is_instance_valid(o):
			o.queue_free()
	orbs.clear()
	orb_stage = ""


## Every machine: slot took orb i (a dot in the slot's colour circles it).
func take(i: int, slot: int) -> void:
	if i < 0 or i >= orbs.size() or not is_instance_valid(orbs[i]):
		return
	var o: Orb = orbs[i]
	var dot := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	sm.radial_segments = 8
	sm.rings = 4
	dot.mesh = sm
	dot.material_override = MeshKit.material(main.PLAYER_COLORS[slot % main.PLAYER_COLORS.size()], 3.0)
	dot.set_meta("k", o.dots.get_child_count())
	o.dots.add_child(dot)
	o.ball.scale = Vector3.ONE * 1.25
	main.burst(o.global_position, (o.ball.material_override as StandardMaterial3D).albedo_color, 14, 0.12)


## Host: players touching an orb take it (walk into it). Returns [[orb index, player], ...].
func touches(players: Array) -> Array:
	var out: Array = []
	for p in players:
		if not p.active or p.is_down:
			continue
		for o in orbs:
			if not is_instance_valid(o):
				continue
			var d := Vector2(p.global_position.x - o.position.x, p.global_position.z - o.position.z)
			if d.length() < TOUCH:
				out.append([o.index, p])
	return out


# --- Nova and the keepsakes ------------------------------------------------------------------------------------

func _build_nova() -> void:
	nova = Node3D.new()
	nova.name = "Nova"
	var mi := MeshInstance3D.new()
	mi.mesh = ResCache.get_or_make("da_nova_v1", func() -> Resource:
		var b := MeshKit.builder()
		var c := Color(0.35, 0.85, 1.0)
		b.sphere(0.5, MeshKit.at(Vector3.ZERO), c, 16)
		b.disc(0.34, MeshKit.at(Vector3(0, 0.02, 0.47), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.08, 0.09, 0.16), 20)
		b.sphere(0.07, MeshKit.at(Vector3(-0.12, 0.08, 0.5)), Color(0.7, 0.95, 1.0), 8, true)
		b.sphere(0.07, MeshKit.at(Vector3(0.12, 0.08, 0.5)), Color(0.7, 0.95, 1.0), 8, true)
		b.box(Vector3(0.16, 0.03, 0.02), MeshKit.at(Vector3(0, -0.1, 0.51)), Color(0.7, 0.95, 1.0), true)
		b.cylinder(0.025, 0.025, 0.35, MeshKit.at(Vector3(0, 0.62, 0)), Color(0.8, 0.85, 0.95), 6)
		b.sphere(0.08, MeshKit.at(Vector3(0, 0.82, 0)), Color(1.0, 0.9, 0.3), 8, true)
		b.sphere(0.12, MeshKit.at(Vector3(-0.55, 0, 0)), c, 8)
		b.sphere(0.12, MeshKit.at(Vector3(0.55, 0, 0)), c, 8)
		b.cone(0.15, 0.3, MeshKit.at(Vector3(0, -0.6, 0), Vector3.ONE, Vector3(PI, 0, 0)), Color(1.0, 0.6, 0.2), 8, true)
		return b.build())
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	nova.add_child(mi)
	add_child(nova)


func cheer() -> void:
	_cheer = 1.0


## Every machine: the city lights (waves cleared ever) and trophies (boss kinds beaten).
func set_keepsakes(waves_total: int, bosses: Dictionary) -> void:
	var lit := Gen.lights(waves_total)
	var key := "%d/%s" % [lit, var_to_str(bosses)]
	if key == _keep_key:
		return
	_keep_key = key
	if _keep_root != null:
		_keep_root.queue_free()
	_keep_root = Node3D.new()
	_keep_root.name = "Keepsakes"
	add_child(_keep_root)
	var poles: Array[Transform3D] = []
	var lamps: Array[Transform3D] = []
	var lamp_cols: Array[Color] = []
	var beams: Array[Transform3D] = []
	var beam_cols: Array[Color] = []
	for i in Gen.LIGHTS:
		var a := TAU * i / float(Gen.LIGHTS) + PI * 0.5
		var at := Vector3(cos(a) * PYLON_R, 0.0, sin(a) * PYLON_R)
		poles.append(Transform3D(Basis.from_scale(Vector3(0.35, 7.0, 0.35)), at + Vector3.UP * 3.5))
		var on := i < lit
		var col := Color.from_hsv(fmod(i * 0.13, 1.0), 0.7, 1.0) if on else Color(0.12, 0.12, 0.18)
		lamps.append(Transform3D(Basis.from_scale(Vector3.ONE * (1.1 if on else 0.7)), at + Vector3.UP * 7.4))
		lamp_cols.append(col)
		if on:
			beams.append(Transform3D(Basis.from_scale(Vector3(0.18, 14.0, 0.18)), at + Vector3.UP * 14.5))
			beam_cols.append(col)
	var dark: StandardMaterial3D = main.make_material(Color(0.12, 0.12, 0.17), 0.0)
	_keep_root.add_child(DecorScript.multimesh(BoxMesh.new(), dark, poles, []))
	var sphere := SphereMesh.new()
	sphere.radial_segments = 10
	sphere.rings = 5
	_keep_root.add_child(DecorScript.multimesh(sphere, DecorScript.glow_material(3.0), lamps, lamp_cols))
	if not beams.is_empty():
		var cyl := CylinderMesh.new()
		cyl.radial_segments = 6
		cyl.top_radius = 0.5
		cyl.bottom_radius = 0.5
		_keep_root.add_child(DecorScript.multimesh(cyl, DecorScript.glow_material(1.2), beams, beam_cols))
	# A trophy orb on a plinth for every boss kind beaten (behind the start, on the far side of the stands).
	var k := 0
	for kind in Bosses.KINDS:
		if int(bosses.get(kind, 0)) <= 0:
			continue
		var at := Vector3(-6.0 + k * 6.0, 0.0, PYLON_R - 2.0)
		var plinth := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(2.0, 3.0, 2.0)
		plinth.mesh = box
		plinth.material_override = dark
		plinth.position = at + Vector3.UP * 1.5
		_keep_root.add_child(plinth)
		var orb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.9
		sm.height = 1.8
		orb.mesh = sm
		orb.material_override = main.make_material(Bosses.info(kind).color, 2.5)
		orb.position = at + Vector3.UP * 4.0
		_keep_root.add_child(orb)
		k += 1


func _process(delta: float) -> void:
	_t += delta
	_cheer = maxf(0.0, _cheer - delta * 1.5)
	if nova != null:
		var a := _t * 0.25
		nova.position = Vector3(sin(a) * 2.5, 5.6 + 0.15 * sin(_t * 2.0) + 0.8 * sin(_cheer * PI), -1.0 + cos(a) * 1.0)
		nova.rotation.y = 0.35 * sin(_t * 0.5) + _cheer * TAU
	for i in pad_rings.size():
		var r := pad_rings[i]
		var d: Dictionary = lay.pads[i]
		if pad_glow[i] > 0.0:
			pad_glow[i] -= delta
			var k := 1.0 + 0.15 * sin(_t * 22.0)
			r.scale = Vector3(float(d.r) * k, 1.0 + 2.0 * absf(sin(_t * 11.0)), float(d.r) * k)
			r.material_override = MeshKit.material(pad_color().lightened(0.3), 5.0)
			if pad_glow[i] <= 0.0:
				r.material_override = MeshKit.material(pad_color(), 1.2)
				r.scale = Vector3(float(d.r), 1.0, float(d.r))
		else:
			var s := float(d.r) * (1.0 + 0.04 * sin(_t * 2.0 + i))
			r.scale = Vector3(s, 1.0, s)
	for o in orbs:
		if not is_instance_valid(o):
			continue
		o.position.y = ORB_Y + 0.12 * sin(_t * 2.2 + o.index)
		o.ball.scale = o.ball.scale.lerp(Vector3.ONE, minf(1.0, delta * 4.0))
		var n: int = o.dots.get_child_count()
		for j in n:
			var a := _t * 2.0 + j * TAU / maxf(1.0, n)
			(o.dots.get_child(j) as Node3D).position = Vector3(cos(a) * 0.85, 0.25 * sin(a * 2.0), sin(a) * 0.85)
	var keep: Array = []
	for w in _warns:
		var n: MeshInstance3D = w[0]
		w[1] = float(w[1]) + delta
		if float(w[1]) >= float(w[2]) or not is_instance_valid(n):
			if is_instance_valid(n):
				n.queue_free()
			continue
		var grow := minf(1.0, float(w[1]) / 0.3)
		var k := (0.9 + 0.1 * absf(sin(float(w[1]) * 12.0))) * grow
		n.scale = Vector3(float(w[3]) * k, 1.0, float(w[3]) * k)
		keep.append(w)
	_warns = keep
