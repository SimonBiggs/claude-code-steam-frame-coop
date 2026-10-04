extends Node3D
## CRYSTAL SAGA visual effects: sparkle poofs, spell bursts (fire, ice, thunder, cure, earth, water,
## holy), sword slash waves, arrows, music notes, level-up pillars, the crystal shattering, wind streaks
## and the meshes of the hero's sword and shield. Everything is short-lived CPUParticles3D / tweened
## meshes with shared cached materials: cheap on the Frame's phone-class GPU (modest particle counts).
## play(kind, args) is the network-safe entry point: main.fx_all() runs it here and sends the same
## call to the TV machine as an event.

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const HudKit := preload("res://core/hud_kit.gd")
const UiKit := preload("res://core/ui_kit.gd")
const Data := preload("res://games/crystal_saga/data.gd")

var main: Node


## Run an effect by name (used for network events too). Positions are world space.
func play(kind: String, args: Array) -> void:
	match kind:
		"poof":
			poof(args[0], args[1])
		"spell":
			spell(String(args[0]), args[1], float(args[2]) if args.size() > 2 else 1.0)
		"slash":
			slash(args[0], args[1], bool(args[2]))
		"arrow":
			arrow(args[0], args[1])
		"notes":
			notes(args[0], args[1])
		"levelup":
			level_up(args[0])
		"shatter":
			shatter(args[0])
		"beam":
			beam(args[0], args[1])
		"dmg":
			_popup(args)
		"sound":
			sound_at(String(args[0]), args[1] if args.size() > 1 else null, float(args[2]) if args.size() > 2 else 0.0)
		"burst":
			burst(args[0], args[1], int(args[2]), float(args[3]))
		"rune":
			rune_flash(args[0], String(args[1]))


## Sound at a position (or flat when pos is null).
func sound_at(sound_name: String, pos: Variant, vol: float = 0.0) -> void:
	if main == null or main.sfx == null:
		return
	if pos is Vector3:
		main.sfx.play_at(sound_name, pos, vol)
	else:
		main.sfx.play(sound_name, vol)


func _popup(args: Array) -> void:
	var pos: Vector3 = args[0]
	var text := String(args[1])
	var style := String(args[2])
	var size := float(args[3]) if args.size() > 3 else 1.0
	HudKit.popup(self, pos, text, {"style": style, "size": size})


# --- Materials --------------------------------------------------------------------------------------

func _spark_mat() -> StandardMaterial3D:
	return ResCache.get_or_make("cs_spark_mat", func() -> Resource:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.disable_fog = true
		return m)


func _quad(size: float) -> QuadMesh:
	var key := "cs_quad_%.3f" % size
	var cached := ResCache.fetch(key) as QuadMesh
	if cached != null:
		return cached
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _spark_mat()
	ResCache.put(key, q)
	return q


func _star_mesh(size: float) -> Mesh:
	var key := "cs_star_%.3f" % size
	var cached := ResCache.fetch(key) as Mesh
	if cached != null:
		return cached
	var b := MeshKit.Builder.new()
	b.star(4, size, size * 0.35, size * 0.1, Transform3D.IDENTITY, Color.WHITE, true)
	var m := b.build(null, _spark_mat())
	ResCache.put(key, m)
	return m


func _gradient(c: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(c.r, c.g, c.b, 1.0))
	g.set_color(1, Color(c.r, c.g, c.b, 0.0))
	return g


## A one-shot particle burst. dir: main direction (ZERO = all around); gravity in m/s^2 (y).
func particles(pos: Vector3, color: Color, amount: int, speed: float, life: float, size: float, dir: Vector3 = Vector3.ZERO,
		gravity: float = -2.0, spread: float = 180.0, stars: bool = false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.explosiveness = 0.92
	p.direction = dir.normalized() if dir != Vector3.ZERO else Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.damping_min = 1.0
	p.damping_max = 2.5
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.mesh = _star_mesh(size * 0.6) if stars else _quad(size)
	p.color_ramp = _gradient(color)
	p.local_coords = false
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.3, false).timeout.connect(p.queue_free)
	return p


func burst(pos: Vector3, color: Color, amount: int = 16, speed: float = 3.0) -> void:
	particles(pos, color, amount, speed, 0.7, 0.12)


## The kid-friendly monster defeat / arrival: a puff of stars and sparkles.
func poof(pos: Vector3, color: Color) -> void:
	particles(pos, Color(1, 1, 1), 10, 2.5, 0.6, 0.18, Vector3.UP, -1.0, 180.0, true)
	particles(pos, color.lightened(0.3), 16, 3.5, 0.8, 0.1, Vector3.UP, -3.0)
	if main != null and main.sfx != null:
		main.sfx.play_at("sparkle", pos, -4.0)


# --- Spells -----------------------------------------------------------------------------------------

## A spell landing at pos: fire, ice, thunder, cure, holy, earth, water, poison, sleep, buff, shadow, steal.
func spell(kind: String, pos: Vector3, power: float = 1.0) -> void:
	var s := clampf(power, 0.5, 3.0)
	match kind:
		"fire":
			particles(pos, Color(1.0, 0.55, 0.15), int(28 * s), 3.0 * s, 0.8, 0.22 * s, Vector3.UP, 2.5, 60.0)
			particles(pos, Color(1.0, 0.9, 0.3), int(12 * s), 2.0 * s, 0.5, 0.14 * s, Vector3.UP, 3.0, 90.0)
			_flash_sphere(pos, Color(1.0, 0.5, 0.2), 0.9 * s)
			sound_at("fire", pos)
		"ice":
			_ice_spikes(pos, s)
			particles(pos, Color(0.7, 0.9, 1.0), int(18 * s), 2.0, 0.9, 0.1, Vector3.UP, -1.0)
			sound_at("ice", pos)
		"thunder":
			_bolt(pos + Vector3.UP * 7.0, pos, Color(1.0, 0.95, 0.45))
			particles(pos, Color(1.0, 0.95, 0.5), int(20 * s), 4.0, 0.4, 0.1, Vector3.UP, -4.0)
			_flash_sphere(pos, Color(1.0, 0.95, 0.6), 0.7 * s)
			sound_at("zap", pos, 2.0)
			sound_at("explosion", pos, -8.0)
		"cure", "heal":
			particles(pos, Color(0.5, 1.0, 0.6), 18, 1.4, 1.1, 0.14, Vector3.UP, 1.5, 30.0, true)
			_ring_rise(pos, Color(0.5, 1.0, 0.65))
			sound_at("heal", pos)
		"holy":
			_ring_rise(pos, Color(1.0, 0.95, 0.7))
			particles(pos, Color(1.0, 0.95, 0.75), 24, 2.0, 1.0, 0.16, Vector3.UP, 1.0, 40.0, true)
			sound_at("magic", pos)
		"earth":
			_rocks(pos, s)
			particles(pos, Color(0.75, 0.55, 0.3), int(24 * s), 4.0, 0.9, 0.18, Vector3.UP, -8.0, 50.0)
			sound_at("explosion", pos, -2.0)
		"water":
			particles(pos, Color(0.4, 0.75, 1.0), int(36 * s), 5.0, 1.0, 0.2, Vector3.UP, -9.0, 40.0)
			_ring_rise(pos, Color(0.4, 0.7, 1.0))
			sound_at("splash", pos)
		"poison":
			particles(pos, Color(0.7, 0.4, 1.0), 12, 1.0, 1.0, 0.14, Vector3.UP, 0.8, 40.0)
			sound_at("debuff", pos, -4.0)
		"sleep":
			HudKit.popup(self, pos + Vector3.UP * 0.4, "Zzz", {"style": "xp", "size": 1.1})
			particles(pos, Color(0.6, 0.75, 1.0), 8, 0.8, 1.2, 0.12, Vector3.UP, 0.5, 30.0, true)
		"buff":
			_ring_rise(pos, Color(1.0, 0.85, 0.35))
			particles(pos, Color(1.0, 0.9, 0.5), 14, 1.2, 0.9, 0.12, Vector3.UP, 1.5, 25.0, true)
			sound_at("buff", pos, -3.0)
		"shield":
			_flash_sphere(pos + Vector3.UP * 0.2, Color(0.5, 0.85, 1.0), 1.0)
			sound_at("buff", pos, -3.0)
		"shadow":
			particles(pos, Color(0.45, 0.2, 0.7), int(30 * s), 3.0 * s, 1.0, 0.25 * s, Vector3.UP, 0.5)
			_flash_sphere(pos, Color(0.5, 0.2, 0.8), 1.0 * s)
			sound_at("debuff", pos)
		"steal":
			particles(pos, Color(1.0, 0.85, 0.3), 12, 2.0, 0.6, 0.12, Vector3.UP, -2.0, 60.0, true)
			sound_at("coin", pos)
		"hit":
			particles(pos, Color(1.0, 0.95, 0.8), 10, 3.0, 0.35, 0.1)
		"crit":
			particles(pos, Color(1.0, 0.85, 0.3), 22, 5.0, 0.5, 0.14, Vector3.ZERO, -3.0, 180.0, true)
			_flash_sphere(pos, Color(1.0, 0.9, 0.5), 0.8)
		"block":
			particles(pos, Color(0.6, 0.9, 1.0), 14, 3.0, 0.35, 0.1)
		"parry":
			particles(pos, Color(1.0, 0.95, 0.6), 26, 5.0, 0.45, 0.12, Vector3.ZERO, -2.0, 180.0, true)
			_flash_sphere(pos, Color(1.0, 1.0, 0.8), 0.6)


## A white flash sphere that pops and fades.
func _flash_sphere(pos: Vector3, color: Color, r: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 14
	sm.rings = 7
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(color.r, color.g, color.b, 0.8)
	mat.disable_fog = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.3
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE * 1.4, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tw.chain().tween_callback(mi.queue_free)


func _ring_rise(pos: Vector3, color: Color) -> void:
	for k in 2:
		var mi := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.55
		tm.outer_radius = 0.68
		tm.rings = 20
		tm.ring_segments = 4
		mi.mesh = tm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
		mat.disable_fog = true
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = pos + Vector3.UP * 0.05
		mi.scale = Vector3(1.0, 0.2, 1.0)
		var tw := mi.create_tween().set_parallel()
		tw.tween_property(mi, "global_position:y", pos.y + 1.8, 0.9).set_delay(k * 0.18)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.9).set_delay(k * 0.18)
		tw.chain().tween_callback(mi.queue_free)


func _ice_spikes(pos: Vector3, s: float) -> void:
	var b := MeshKit.Builder.new()
	for k in 7:
		var a := k * TAU / 7.0
		var dir := Vector3(cos(a) * 0.4, 1.0, sin(a) * 0.4).normalized()
		var h := (0.6 + 0.3 * float(k % 3)) * s
		b.cylinder(0.0, 0.12 * s, h, MeshKit.aim(Vector3(cos(a), 0, sin(a)) * 0.25 * s + dir * h * 0.5, dir), Color(0.7, 0.92, 1.0), 6, true)
	var mi := MeshKit.instance(b.build(), false)
	add_child(mi)
	mi.global_position = pos - Vector3.UP * 0.3
	mi.scale = Vector3(1.0, 0.1, 1.0)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	tw.tween_property(mi, "scale", Vector3(1.3, 0.01, 1.3), 0.25)
	tw.tween_callback(mi.queue_free)


func _rocks(pos: Vector3, s: float) -> void:
	var b := MeshKit.Builder.new()
	for k in 6:
		var a := k * TAU / 6.0
		b.cone(0.35 * s, 1.1 * s, MeshKit.at(Vector3(cos(a), 0.4, sin(a)) * 0.7 * s), Color(0.6, 0.48, 0.35), 6)
	var mi := MeshKit.instance(b.build(), false)
	add_child(mi)
	mi.global_position = pos - Vector3.UP * 0.6
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position:y", pos.y, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.6)
	tw.tween_property(mi, "global_position:y", pos.y - 1.5, 0.4)
	tw.tween_callback(mi.queue_free)


## A jagged lightning bolt from a to b.
func _bolt(a: Vector3, b: Vector3, color: Color) -> void:
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.disable_fog = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = [a]
	for k in range(1, 8):
		var t := float(k) / 8.0
		pts.append(a.lerp(b, t) + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5)))
	pts.append(b)
	for k in range(pts.size() - 1):
		var p0 := pts[k]
		var p1 := pts[k + 1]
		var w := Vector3(0.09, 0, 0.09)
		for quad in [[p0 - w, p0 + w, p1 + w], [p0 - w, p1 + w, p1 - w]]:
			for v in quad:
				im.surface_add_vertex(v)
		var w2 := Vector3(0.09, 0, -0.09)
		for quad2 in [[p0 - w2, p0 + w2, p1 + w2], [p0 - w2, p1 + w2, p1 - w2]]:
			for v2 in quad2:
				im.surface_add_vertex(v2)
	im.surface_end()
	var tw := mi.create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(func() -> void: mi.visible = false)
	tw.tween_interval(0.05)
	tw.tween_callback(func() -> void: mi.visible = true)
	tw.tween_interval(0.12)
	tw.tween_callback(mi.queue_free)


## A sword slash: a glowing crescent flying from `from` to `to`.
func slash(from: Vector3, to: Vector3, crit: bool) -> void:
	var col := Color(1.0, 0.85, 0.35) if crit else Color(0.75, 0.9, 1.0)
	var b := MeshKit.Builder.new()
	b.torus(0.5, 0.05, MeshKit.at(Vector3.ZERO, Vector3(1.0, 1.0, 0.25)), col, 18, 4, true)
	var mi := MeshKit.instance(b.build(), false)
	add_child(mi)
	mi.global_position = from
	var dir := to - from
	if dir.length() > 0.01:
		mi.look_at(to, Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.FORWARD)
	mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	mi.rotate_object_local(Vector3.UP, randf_range(-0.6, 0.6))
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", to, 0.18)
	tw.tween_callback(mi.queue_free)
	particles(to, col, 12 if not crit else 22, 4.0, 0.4, 0.1)


## An arrow from `from` to `to`.
func arrow(from: Vector3, to: Vector3) -> void:
	var b := MeshKit.Builder.new()
	b.cylinder(0.015, 0.015, 0.7, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.6, 0.45, 0.3), 5)
	b.cone(0.05, 0.12, MeshKit.at(Vector3(0, 0, -0.4), Vector3.ONE, Vector3(-PI * 0.5, 0, 0)), Color(0.8, 0.85, 0.9), 6)
	var mi := MeshKit.instance(b.build(), false)
	add_child(mi)
	mi.global_position = from
	if (to - from).length() > 0.01:
		mi.look_at(to, Vector3.UP)
	var mid := (from + to) * 0.5 + Vector3.UP * 0.8
	var tw := mi.create_tween()
	tw.tween_method(func(t: float) -> void:
		var p := from.lerp(mid, t).lerp(mid.lerp(to, t), t)
		mi.global_position = p, 0.0, 1.0, 0.28)
	tw.tween_callback(mi.queue_free)
	sound_at("bow", from, -2.0)


## Music notes floating up (bard songs).
func notes(pos: Vector3, color: Color) -> void:
	for k in 4:
		var l := UiKit.label3d("*" if k % 2 == 0 else "~", 0.18, color, true)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(l)
		l.global_position = pos + Vector3(randf_range(-0.4, 0.4), 0.5 + k * 0.15, randf_range(-0.4, 0.4))
		var tw := l.create_tween().set_parallel()
		tw.tween_property(l, "global_position:y", l.global_position.y + 1.4, 1.2).set_delay(k * 0.1)
		tw.tween_property(l, "modulate:a", 0.0, 1.2).set_delay(k * 0.1)
		tw.chain().tween_callback(l.queue_free)
	sound_at("magic", pos, -6.0)


## A golden pillar of light and rising stars (level up).
func level_up(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.6
	cm.height = 4.0
	cm.radial_segments = 14
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.85, 0.35, 0.6)
	mat.disable_fog = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos + Vector3.UP * 2.0
	mi.scale = Vector3(0.2, 1.0, 0.2)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.8)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tw.tween_callback(mi.queue_free)
	particles(pos + Vector3.UP * 0.3, Color(1.0, 0.9, 0.5), 20, 2.5, 1.2, 0.14, Vector3.UP, 1.0, 25.0, true)


## The Crystal of Light shatters: shards fly off in four directions.
func shatter(pos: Vector3) -> void:
	_flash_sphere(pos, Color(1.0, 1.0, 1.0), 2.0)
	particles(pos, Color(0.7, 0.95, 1.0), 60, 9.0, 1.4, 0.14, Vector3.ZERO, -3.0, 180.0, true)
	var dirs: Array[Vector3] = [Vector3(-1, 0.6, -0.4), Vector3(1, 0.7, -0.5), Vector3(0.2, 0.9, -1), Vector3(-0.3, 1.0, 0.6)]
	var cols: Array[Color] = [Color(0.85, 0.6, 0.3), Color(1.0, 0.6, 0.3), Color(0.3, 0.6, 1.0), Color(0.7, 0.5, 1.0)]
	for k in 4:
		var b := MeshKit.Builder.new()
		b.cylinder(0.0, 0.18, 0.5, MeshKit.at(Vector3(0, 0.25, 0)), cols[k], 5, true)
		b.cylinder(0.18, 0.0, 0.3, MeshKit.at(Vector3(0, -0.15, 0)), cols[k], 5, true)
		var mi := MeshKit.instance(b.build(), false)
		add_child(mi)
		mi.global_position = pos
		var to := pos + dirs[k].normalized() * 40.0
		var tw := mi.create_tween().set_parallel()
		tw.tween_property(mi, "global_position", to, 2.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(mi, "rotation", Vector3(8, 12, 4), 2.2)
		tw.chain().tween_callback(mi.queue_free)
	sound_at("crash", pos)
	sound_at("explosion", pos, -6.0)


## A beam of light from the sky onto pos (shards, save crystals).
func beam(pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.9
	cm.bottom_radius = 0.6
	cm.height = 20.0
	cm.radial_segments = 12
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.0)
	mat.disable_fog = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos + Vector3.UP * 10.0
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.55, 0.4)
	tw.tween_interval(1.4)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.8)
	tw.tween_callback(mi.queue_free)
	particles(pos + Vector3.UP * 0.5, color.lightened(0.3), 30, 3.0, 1.5, 0.14, Vector3.UP, 1.5, 30.0, true)


## A glowing rune shape flashing where it was drawn (VR spell cast).
func rune_flash(pos: Vector3, rune: String) -> void:
	var col: Color = Data.ELEMENT_COLORS.get({"circle": "fire", "zigzag": "thunder", "up": "holy"}.get(rune, ""), Color.WHITE)
	if rune == "up":
		col = Color(0.5, 1.0, 0.6)
	particles(pos, col, 30, 2.0, 0.7, 0.12, Vector3.ZERO, 0.0, 180.0, true)
	_flash_sphere(pos, col, 0.35)
	sound_at("magic", pos)


# --- Meshes -----------------------------------------------------------------------------------------

## The hero's sword, held in the right hand: blade along -Z (the controller's aim), guard and grip.
## glow = the blade is a glowing surface (the charged look).
func sword_mesh(glow: bool) -> ArrayMesh:
	var key := "cs_sword_%s" % glow
	var cached := ResCache.fetch(key) as ArrayMesh
	if cached != null:
		return cached
	var b := MeshKit.Builder.new()
	var steel := Color(0.85, 0.9, 1.0) if not glow else Color(0.75, 0.92, 1.0)
	b.box(Vector3(0.055, 0.012, 0.72), MeshKit.at(Vector3(0, 0, -0.44)), steel, glow)
	b.cylinder(0.0, 0.039, 0.09, MeshKit.at(Vector3(0, 0, -0.845), Vector3(1.0, 1.0, 0.3), Vector3(-PI * 0.5, 0, 0)), steel, 4, glow)
	b.box(Vector3(0.012, 0.016, 0.62), MeshKit.at(Vector3(0, 0.006, -0.42)), Color(0.6, 0.75, 1.0) if not glow else Color(1.0, 0.9, 0.5), glow)
	b.rounded_box(Vector3(0.2, 0.035, 0.035), 0.012, MeshKit.at(Vector3(0, 0, -0.07)), Color(1.0, 0.8, 0.3))
	b.sphere(0.022, MeshKit.at(Vector3(0, 0.0, -0.07)), Color(0.4, 0.8, 1.0), 8, true)
	b.cylinder(0.018, 0.02, 0.13, MeshKit.at(Vector3(0, 0, 0.0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.45, 0.28, 0.18), 8)
	b.sphere(0.026, MeshKit.at(Vector3(0, 0, 0.075)), Color(1.0, 0.8, 0.3), 8)
	var m := b.build()
	ResCache.put(key, m)
	return m


## The hero's round shield on the left hand (face towards -Z, the hand's forward), small enough to
## keep the wrist MENU button clear.
func shield_mesh() -> ArrayMesh:
	var cached := ResCache.fetch("cs_shield") as ArrayMesh
	if cached != null:
		return cached
	var b := MeshKit.Builder.new()
	var face := MeshKit.at(Vector3(0, 0.0, -0.06), Vector3.ONE, Vector3(PI * 0.5, 0, 0))
	b.cylinder(0.13, 0.13, 0.025, face, Color(0.25, 0.42, 0.9), 18)
	b.torus(0.13, 0.014, MeshKit.at(Vector3(0, 0, -0.06), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.82, 0.3), 18, 5)
	b.star(4, 0.07, 0.03, 0.012, MeshKit.at(Vector3(0, 0, -0.078)), Color(1.0, 0.85, 0.35), true)
	var m := b.build()
	ResCache.put("cs_shield", m)
	return m
