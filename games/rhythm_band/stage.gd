extends Node3D
## The concert: a stage with a disco floor, light beams and speakers that pump on the beat, a bouncing
## crowd (one MultiMesh) and the guitarists' avatars. The drummer stands at the back (DRUM_SPOT,
## facing -Z towards the crowd); the guitarists stand in front of them; the TV cameras are in the crowd.

const STAGE_Y := 0.8
const DRUM_SPOT := Vector3(0.0, 0.8, 1.2)
const AVATAR_X: Array[float] = [-1.15, 1.15, -2.3, 2.3, -3.3, 3.3]
const CROWD_COLS := 18
const CROWD_ROWS := 4
const TILE_COLS := 9
const TILE_ROWS := 4
const BEAM_COLORS: Array[Color] = [Color(1.0, 0.3, 0.5), Color(0.3, 0.7, 1.0), Color(1.0, 0.85, 0.2),
	Color(0.4, 1.0, 0.5), Color(0.8, 0.4, 1.0), Color(1.0, 0.55, 0.2)]

var main
var t := 0.0
var beat_flash := 0.0
var bar_n := 0
var beat_n := 0
var crowd_mm: MultiMesh
var crowd_base := PackedVector3Array()
var crowd_ph := PackedFloat32Array()
var crowd_s := PackedFloat32Array()
var tiles_mm: MultiMesh
var beam_pivots: Array[Node3D] = []
var beam_mats: Array[StandardMaterial3D] = []
var speakers: Array[MeshInstance3D] = []
var key_light: OmniLight3D
var avatars: Array[Node3D] = []
var guitars: Array[Node3D] = []
var guitar_mats: Array[StandardMaterial3D] = []
var heads: Array[Node3D] = []
var tags: Array[Label3D] = []
var strum_t := PackedFloat32Array()
var song_label: Label3D
var stars_root: Node3D
var star_meshes: Array[MeshInstance3D] = []
var star_on := PackedByteArray()
var stars_shown := 0
var star_anim := 0.0


func build() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.04, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.65, 0.9)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(160.0), 0.0)
	sun.light_energy = 0.55
	sun.shadow_enabled = false
	add_child(sun)
	key_light = OmniLight3D.new()
	key_light.position = Vector3(0.0, 4.0, -1.5)
	key_light.omni_range = 9.0
	key_light.light_energy = 1.2
	add_child(key_light)
	# Ground, stage, backdrop, truss and speakers.
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	ground.mesh = pm
	ground.material_override = main.make_material(Color(0.12, 0.1, 0.16), 0.0)
	add_child(ground)
	_box(Vector3(9.4, STAGE_Y, 5.6), Vector3(0.0, STAGE_Y * 0.5, 0.45), Color(0.18, 0.16, 0.24), 0.0)
	_box(Vector3(9.5, 0.06, 0.1), Vector3(0.0, STAGE_Y - 0.02, -2.36), Color(1.0, 0.4, 0.8), 1.5)  # glowing lip
	_box(Vector3(1.8, 0.02, 1.6), Vector3(DRUM_SPOT.x, STAGE_Y + 0.01, DRUM_SPOT.z), Color(0.5, 0.15, 0.2), 0.0)  # drum rug
	_box(Vector3(10.0, 5.0, 0.2), Vector3(0.0, 3.3, 3.3), Color(0.12, 0.08, 0.22), 0.0)
	_box(Vector3(10.0, 0.18, 0.18), Vector3(0.0, 5.2, -0.6), Color(0.35, 0.35, 0.4), 0.0)
	var sign_l := Label3D.new()
	sign_l.text = "RHYTHM BAND"
	sign_l.font_size = 200
	sign_l.pixel_size = 0.004
	sign_l.outline_size = 30
	sign_l.modulate = Color(1.0, 0.85, 0.3)
	sign_l.position = Vector3(0.0, 4.4, 3.18)
	sign_l.rotation.y = PI
	add_child(sign_l)
	song_label = Label3D.new()
	song_label.font_size = 96
	song_label.pixel_size = 0.004
	song_label.outline_size = 20
	song_label.modulate = Color(0.6, 0.9, 1.0)
	song_label.position = Vector3(0.0, 3.55, 3.18)
	song_label.rotation.y = PI
	add_child(song_label)
	for sx in [-4.3, 4.3]:
		var sxf: float = sx
		_box(Vector3(0.9, 2.2, 0.8), Vector3(sxf, STAGE_Y + 1.1, -1.6), Color(0.08, 0.08, 0.1), 0.0)
		for k in 2:
			var cone := MeshInstance3D.new()
			cone.mesh = main.cyl_mesh(0.3 - k * 0.1, 0.3 - k * 0.1, 0.05, 16)
			cone.material_override = main.make_material(Color(0.25, 0.25, 0.3), 0.0)
			cone.rotation.x = PI * 0.5
			cone.position = Vector3(sxf, STAGE_Y + 0.6 + k * 0.95, -2.02)
			add_child(cone)
			speakers.append(cone)
	_build_floor()
	_build_beams()
	_build_crowd()
	for i in AVATAR_X.size():
		_build_avatar(i + 1)
	strum_t.resize(7)
	_build_stars()


func _box(size: Vector3, pos: Vector3, color: Color, glow: float) -> MeshInstance3D:
	var b := MeshInstance3D.new()
	b.mesh = main.box_mesh(size)
	b.material_override = main.make_material(color, glow)
	b.position = pos
	add_child(b)
	return b


func _build_floor() -> void:
	tiles_mm = MultiMesh.new()
	tiles_mm.transform_format = MultiMesh.TRANSFORM_3D
	tiles_mm.use_colors = true
	tiles_mm.mesh = main.box_mesh(Vector3(0.9, 0.02, 0.5))
	tiles_mm.instance_count = TILE_COLS * TILE_ROWS
	for r in TILE_ROWS:
		for c in TILE_COLS:
			var i := r * TILE_COLS + c
			tiles_mm.set_instance_transform(i, Transform3D(Basis(), Vector3((c - 4) * 0.95, STAGE_Y + 0.012, -2.0 + r * 0.55)))
			tiles_mm.set_instance_color(i, Color(0.2, 0.2, 0.3))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = tiles_mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	add_child(mi)


func _build_beams() -> void:
	var xs: Array[float] = [-3.6, -2.2, -0.8, 0.8, 2.2, 3.6]
	for i in xs.size():
		var pivot := Node3D.new()
		pivot.position = Vector3(xs[i], 5.1, -0.6)
		add_child(pivot)
		var beam := MeshInstance3D.new()
		beam.mesh = main.cyl_mesh(0.05, 0.45, 5.0, 10)
		beam.position = Vector3(0.0, -2.5, 0.0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var c := BEAM_COLORS[i]
		m.albedo_color = Color(c.r, c.g, c.b, 0.1)
		beam.material_override = m
		pivot.add_child(beam)
		var lamp := MeshInstance3D.new()
		lamp.mesh = main.sphere_mesh(0.12)
		lamp.material_override = main.make_material(c, 2.0)
		pivot.add_child(lamp)
		beam_pivots.append(pivot)
		beam_mats.append(m)


func _build_crowd() -> void:
	crowd_mm = MultiMesh.new()
	crowd_mm.transform_format = MultiMesh.TRANSFORM_3D
	crowd_mm.use_colors = true
	var cm := CapsuleMesh.new()
	cm.radius = 0.2
	cm.height = 1.0
	cm.radial_segments = 8
	cm.rings = 2
	crowd_mm.mesh = cm
	crowd_mm.instance_count = CROWD_COLS * CROWD_ROWS
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var shirt: Array[Color] = [Color(1.0, 0.4, 0.4), Color(0.4, 0.7, 1.0), Color(1.0, 0.85, 0.3), Color(0.5, 1.0, 0.5),
		Color(0.9, 0.5, 1.0), Color(1.0, 0.6, 0.3), Color(0.9, 0.9, 0.95)]
	for r in CROWD_ROWS:
		for c in CROWD_COLS:
			var i := r * CROWD_COLS + c
			var s := rng.randf_range(0.8, 1.15)
			var pos := Vector3((c - (CROWD_COLS - 1) * 0.5) * 0.5 + rng.randf_range(-0.12, 0.12) + (r % 2) * 0.25,
				0.5 * s, -3.0 - r * 0.6 + rng.randf_range(-0.1, 0.1))
			crowd_base.append(pos)
			crowd_ph.append(rng.randf())
			crowd_s.append(s)
			crowd_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), pos))
			crowd_mm.set_instance_color(i, shirt[rng.randi_range(0, shirt.size() - 1)])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = crowd_mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.8
	mi.material_override = m
	add_child(mi)


func _build_avatar(i: int) -> void:
	var color: Color = main.PLAYER_COLORS[i]
	var root := Node3D.new()
	var x := AVATAR_X[i - 1]
	root.position = Vector3(x, STAGE_Y, -0.7 - absf(x) * 0.1)
	root.rotation.y = x * 0.06  # face the crowd, angled a little to the middle
	add_child(root)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.2
	cap.height = 0.85
	cap.radial_segments = 10
	cap.rings = 3
	body.mesh = cap
	body.material_override = main.make_material(color, 0.15)
	body.position = Vector3(0, 0.5, 0)
	root.add_child(body)
	var head := Node3D.new()
	head.position = Vector3(0, 1.12, 0)
	root.add_child(head)
	var face := MeshInstance3D.new()
	face.mesh = main.sphere_mesh(0.17)
	face.material_override = main.make_material(Color(1.0, 0.82, 0.65), 0.0)
	head.add_child(face)
	for sx in [-0.06, 0.06]:
		var eye := MeshInstance3D.new()
		eye.mesh = main.sphere_mesh(0.03)
		eye.material_override = main.make_material(Color(0.05, 0.05, 0.1), 0.0)
		eye.position = Vector3(float(sx), 0.03, -0.15)
		head.add_child(eye)
	var hat := MeshInstance3D.new()
	hat.mesh = main.cyl_mesh(0.12, 0.18, 0.1, 12)
	hat.material_override = main.make_material(color.darkened(0.35), 0.0)
	hat.position = Vector3(0, 0.15, 0)
	head.add_child(hat)
	var guitar := Node3D.new()
	guitar.position = Vector3(0.0, 0.5, -0.24)
	guitar.rotation.z = 0.5
	root.add_child(guitar)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = color.lightened(0.3)
	gm.emission_enabled = true
	gm.emission = color
	gm.emission_energy_multiplier = 0.2
	var gbody := MeshInstance3D.new()
	gbody.mesh = main.box_mesh(Vector3(0.34, 0.26, 0.07))
	gbody.material_override = gm
	guitar.add_child(gbody)
	var neck := MeshInstance3D.new()
	neck.mesh = main.box_mesh(Vector3(0.48, 0.05, 0.04))
	neck.material_override = main.make_material(Color(0.4, 0.25, 0.12), 0.0)
	neck.position = Vector3(0.38, 0.0, 0.0)
	guitar.add_child(neck)
	var tag := Label3D.new()
	tag.text = "P%d" % (i + 1)
	tag.font_size = 64
	tag.pixel_size = 0.004
	tag.outline_size = 16
	tag.modulate = color
	tag.position = Vector3(0, 1.55, 0)
	root.add_child(tag)
	root.visible = false
	avatars.append(root)
	guitars.append(guitar)
	guitar_mats.append(gm)
	heads.append(head)
	tags.append(tag)


## A flat five-pointed star (both faces), shared by the result stars.
func _star_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	for k in 10:
		var a := -PI * 0.5 + k * PI / 5.0
		var r := 0.32 if k % 2 == 0 else 0.13
		pts.append(Vector3(cos(a) * r, -sin(a) * r, 0.0))
	for k in 10:
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(pts[k])
		st.add_vertex(pts[(k + 1) % 10])
	return st.commit()


func _build_stars() -> void:
	stars_root = Node3D.new()
	stars_root.position = Vector3(0.0, 3.4, -1.2)
	add_child(stars_root)
	var mesh := _star_mesh()
	for k in 5:
		var m := MeshInstance3D.new()
		m.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.3, 0.3, 0.35)
		m.material_override = mat
		m.position = Vector3((k - 2) * 0.8, 0.0, 0.0)
		m.visible = false
		stars_root.add_child(m)
		star_meshes.append(m)


func show_stars(n: int) -> void:
	stars_shown = n
	star_anim = 0.0
	for k in 5:
		var m := star_meshes[k]
		m.visible = true
		m.scale = Vector3.ONE * 0.01
		var mat: StandardMaterial3D = m.material_override
		mat.albedo_color = Color(1.0, 0.85, 0.2) if k < n else Color(0.3, 0.3, 0.35)


func hide_stars() -> void:
	stars_shown = -1
	for m in star_meshes:
		m.visible = false


func set_song_title(text: String) -> void:
	if song_label != null:
		song_label.text = text


func set_avatar_visible(i: int, on: bool) -> void:
	if i >= 1 and i <= avatars.size():
		avatars[i - 1].visible = on


## VR: name tags face the drummer behind them. Flat views: they turn to the camera.
func set_tags_for_vr(vr: bool) -> void:
	for tag in tags:
		tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED if vr else BaseMaterial3D.BILLBOARD_ENABLED
		tag.rotation.y = PI if vr else 0.0


func strum(i: int, good: bool) -> void:
	if i >= 1 and i < strum_t.size():
		strum_t[i] = 1.0 if good else 0.4


## TV camera for guitarist i: in the crowd, looking up at the band with your own avatar near the middle.
func tv_camera(i: int) -> Transform3D:
	var ax := AVATAR_X[clampi(i - 1, 0, AVATAR_X.size() - 1)]
	var pos := Vector3(ax * 0.5, 1.8, -6.6)
	return Transform3D(Basis(), pos).looking_at(Vector3(ax * 0.35, 1.75, 0.5), Vector3.UP)


func on_beat(b: int, crowd: float) -> void:
	beat_n = b
	beat_flash = 1.0
	if b % 4 == 0:
		bar_n = b / 4
	# Disco floor: a different pattern every beat.
	var pattern := b % 4
	for r in TILE_ROWS:
		for c in TILE_COLS:
			var on := false
			match pattern:
				0:
					on = (r + c) % 2 == 0
				1:
					on = c % 3 == (b / 4) % 3
				2:
					on = (r + c) % 2 == 1
				_:
					on = r == (b / 4) % TILE_ROWS
			var col := BEAM_COLORS[(c + bar_n) % BEAM_COLORS.size()]
			tiles_mm.set_instance_color(r * TILE_COLS + c, col * (0.5 + 0.7 * crowd) if on else Color(0.12, 0.1, 0.2))
	for sp in speakers:
		sp.scale = Vector3(1.25, 1.0, 1.25)


func update(delta: float, beat_pos: float, crowd: float, playing: bool) -> void:
	t += delta
	beat_flash = maxf(0.0, beat_flash - delta * 3.5)
	var energy := crowd if playing else 0.35
	for i in beam_pivots.size():
		var pv := beam_pivots[i]
		var k := float(i)
		pv.rotation.z = sin(t * (0.6 + k * 0.07) + k * 1.3) * 0.55
		pv.rotation.x = 0.45 + sin(t * 0.5 + k) * 0.25
		var c := BEAM_COLORS[(i + bar_n) % BEAM_COLORS.size()]
		beam_mats[i].albedo_color = Color(c.r, c.g, c.b, 0.05 + 0.2 * beat_flash * (0.4 + energy))
	key_light.light_energy = 1.0 + beat_flash * 0.8 * (0.3 + energy)
	key_light.light_color = BEAM_COLORS[bar_n % BEAM_COLORS.size()].lerp(Color.WHITE, 0.6)
	for sp in speakers:
		sp.scale = sp.scale.lerp(Vector3.ONE, 1.0 - exp(-12.0 * delta))
	# Crowd: bounce on the beat; the happier they are, the higher and more in sync they jump.
	var hop := 0.03 + 0.32 * energy * energy
	for i in crowd_base.size():
		var ph := crowd_ph[i] * (1.0 - energy * 0.8)
		var j := pow(absf(sin(PI * (beat_pos + ph))), 2.0) * hop
		var s := crowd_s[i]
		var base := crowd_base[i]
		crowd_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s * (1.0 + j * 0.3), s)), base + Vector3(0, j, 0)))
	# Guitarists: bob to the beat, swing the guitar when they hit a note.
	for i in avatars.size():
		var av := avatars[i]
		if not av.visible:
			continue
		var bob := absf(sin(PI * beat_pos)) * 0.05
		av.position.y = STAGE_Y + bob
		heads[i].rotation.x = -absf(sin(PI * beat_pos)) * 0.15
		var st := strum_t[i + 1]
		strum_t[i + 1] = maxf(0.0, st - delta * 4.0)
		guitars[i].rotation.x = -st * 0.4
		guitar_mats[i].emission_energy_multiplier = 0.2 + st * 2.5
	# Result stars pop in one by one.
	if stars_shown >= 0 and not star_meshes.is_empty() and star_meshes[0].visible:
		star_anim += delta
		for k in 5:
			var sk := clampf((star_anim - k * 0.35) * 4.0, 0.0, 1.0)
			var wob := 1.0 + 0.15 * sin(t * 6.0 + k) if k < stars_shown else 1.0
			star_meshes[k].scale = Vector3.ONE * maxf(0.01, sk * wob)
			star_meshes[k].rotation.y = sin(t * 1.5 + k) * 0.4
