extends Node3D
## Starship Crew: everything outside the ship. The ship stays put at the origin (a stable cockpit for
## the VR captain); space slides past instead. "Space coordinates" are the world with the ship's
## sideways offset added: an object at space position p is drawn at to_world(p) = p - (offset.x, offset.y, 0).
## Pieces: speed streaks (one MultiMesh), nebula clouds (cheap noise shader on a few big quads), a planet
## and a landmark station per sector theme, the warp effect, the ship's shield bubble, laser bolts,
## torpedoes, explosions, and the asteroid / storm field (MultiMeshes fed by field.gd).
## Purely visual: the host decides hits and damage (encounters.gd); this draws them on every machine.

const MeshKit := preload("res://core/mesh_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const Models := preload("res://games/starship_crew/models.gd")
const Field := preload("res://games/starship_crew/field.gd")

const STREAKS := 150
const STREAK_Z := Vector2(-240.0, 40.0)
const NEBULA_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform sampler2D noise : repeat_enable, filter_linear;
uniform vec4 col : source_color = vec4(0.5, 0.3, 1.0, 1.0);
uniform float strength = 0.6;
uniform float drift = 0.0;
void fragment() {
	float n = texture(noise, UV * 0.9 + vec2(drift, drift * 0.37)).r;
	float r = length(UV - 0.5) * 2.0;
	float fall = smoothstep(1.0, 0.2, r);
	ALBEDO = col.rgb * n * n * fall * strength;
}
"""
const BUBBLE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(0.3, 0.7, 1.0, 1.0);
uniform float level = 1.0;
uniform float flash = 0.0;
uniform float super_on = 0.0;
uniform vec3 hit_dir = vec3(0.0, 0.0, -1.0);
varying vec3 wnorm;
void vertex() {
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float f = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(f, 3.0) * (0.12 + 0.2 * level);
	float spot = flash * smoothstep(0.55, 1.0, dot(normalize(wnorm), normalize(hit_dir)));
	float hex = 0.5 + 0.5 * sin(UV.x * 220.0) * sin(UV.y * 120.0);
	ALBEDO = col.rgb * (rim + spot * (0.5 + 0.4 * hex) + flash * 0.06 + super_on * (0.08 + 0.1 * hex));
}
"""

## Sector looks: nebula colours, planet colours / place / size, landmark station.
const THEMES := {
	"start": {"neb": [Color(0.3, 0.5, 1.0), Color(0.95, 0.45, 0.8)], "planet": [Color(0.95, 0.72, 0.5), Color(1.0, 0.9, 0.7, 0.8)], "ppos": Vector3(-190, 50, -330), "psize": 70.0, "landmark": "bakery"},
	"pirates": {"neb": [Color(1.0, 0.35, 0.25), Color(0.7, 0.2, 0.55)], "planet": [Color(0.75, 0.35, 0.3), Color(0, 0, 0, 0)], "ppos": Vector3(220, -60, -360), "psize": 85.0, "landmark": ""},
	"asteroids": {"neb": [Color(0.75, 0.55, 0.35), Color(0.4, 0.35, 0.5)], "planet": [Color(0.6, 0.55, 0.5), Color(0.8, 0.7, 0.55, 0.9)], "ppos": Vector3(-240, 30, -300), "psize": 95.0, "landmark": ""},
	"distress": {"neb": [Color(0.3, 0.55, 1.0), Color(0.3, 0.9, 0.8)], "planet": [Color(0.4, 0.6, 0.95), Color(0, 0, 0, 0)], "ppos": Vector3(200, 70, -340), "psize": 60.0, "landmark": ""},
	"storm": {"neb": [Color(0.65, 0.25, 1.0), Color(0.3, 1.0, 0.55)], "planet": [Color(0.45, 0.3, 0.6), Color(0.5, 1.0, 0.6, 0.6)], "ppos": Vector3(-210, -40, -330), "psize": 75.0, "landmark": ""},
	"whale": {"neb": [Color(0.25, 0.85, 0.95), Color(0.45, 0.45, 1.0)], "planet": [Color(0.45, 0.85, 0.75), Color(0.9, 1.0, 1.0, 0.7)], "ppos": Vector3(230, 40, -320), "psize": 80.0, "landmark": ""},
	"shop": {"neb": [Color(1.0, 0.75, 0.3), Color(0.7, 0.4, 1.0)], "planet": [Color(0.95, 0.6, 0.35), Color(1.0, 0.85, 0.5, 0.8)], "ppos": Vector3(-220, 60, -340), "psize": 65.0, "landmark": "trading_post"},
	"boss": {"neb": [Color(1.0, 0.2, 0.35), Color(0.55, 0.15, 0.6)], "planet": [Color(0.35, 0.15, 0.3), Color(1.0, 0.4, 0.3, 0.6)], "ppos": Vector3(250, -30, -350), "psize": 110.0, "landmark": ""},
	"end": {"neb": [Color(1.0, 0.55, 0.8), Color(1.0, 0.85, 0.35)], "planet": [Color(0.6, 0.85, 1.0), Color(1.0, 0.7, 0.85, 0.8)], "ppos": Vector3(-200, 40, -330), "psize": 80.0, "landmark": "party_station"},
}
const LANDMARK_POS := {"bakery": Vector3(48.0, -12.0, -120.0), "trading_post": Vector3(-46.0, 6.0, -105.0), "party_station": Vector3(0.0, -18.0, -150.0)}

var vr := false
var offset := Vector2.ZERO  ## the ship's sideways position in space (x, y)
var speed := 8.0  ## forward speed (m/s): streaks and fields flow past at this rate
var warp := 0.0  ## 0..1 hyperjump streak stretch
var theme := ""
var field: Field  ## current asteroid / storm field (null if none)
var field_s := 0.0  ## metres flown through the field
var field_dead := PackedByteArray()
var shield_level := 1.0  ## 0..1 shield strength (bubble brightness)
var super_shield := 0.0

var _t := 0.0
var _streaks: MultiMeshInstance3D
var _streak_pos := PackedVector3Array()
var _nebulae: Array[MeshInstance3D] = []
var _neb_mats: Array[ShaderMaterial] = []
var _neb_target: Array[Color] = []
var _planet: MeshInstance3D
var _landmark: MeshInstance3D
var _landmark_kind := ""
var _bubble: MeshInstance3D
var _bubble_mat: ShaderMaterial
var _flash := 0.0
var _rocks: MultiMeshInstance3D
var _cells: MultiMeshInstance3D
var _bolts: Array = []  # {"mi", "from", "to", "t", "dur", "burst", "col"}
var _bolt_pool: Array[MeshInstance3D] = []
var _bolt_mats := {}
var _torps: Array = []  # {"node", "from", "target" (Node3D or null), "to", "t", "dur"}


func _ready() -> void:
	_build_streaks()
	_build_nebulae()
	_planet = MeshInstance3D.new()
	_planet.name = "Planet"
	_planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_planet)
	_build_bubble()


# --- Building ------------------------------------------------------------------------------------

func _build_streaks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var xfs: Array = []
	for i in STREAKS:
		var a := rng.randf() * TAU
		var r := rng.randf_range(10.0, 70.0)
		var p := Vector3(cos(a) * r, sin(a) * r * 0.6, rng.randf_range(STREAK_Z.x, STREAK_Z.y))
		_streak_pos.append(p)
		xfs.append(Transform3D(Basis(), p))
	var cols := PackedColorArray()
	for i in STREAKS:
		cols.append(Color(0.7, 0.85, 1.0) if i % 3 != 0 else Color(1.0, 0.85, 0.95))
	_streaks = MeshKit.scatter(Models.streak(), xfs, cols, PackedColorArray(), false)
	_streaks.name = "Streaks"
	add_child(_streaks)


func _build_nebulae() -> void:
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.012
	n.fractal_octaves = 4
	tex.noise = n
	var spots: Array = [[Vector3(-210, 40, -420), Vector2(520, 330), 0.2], [Vector3(230, -50, -400), Vector2(480, 300), -0.3],
		[Vector3(0, 160, -380), Vector2(560, 300), 0.05]]
	var count := 2 if vr else 3
	for k in count:
		var s: Array = spots[k]
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = s[1]
		mi.mesh = q
		var m := ShaderMaterial.new()
		m.shader = Shader.new()
		m.shader.code = NEBULA_SHADER
		m.set_shader_parameter("noise", tex)
		m.set_shader_parameter("strength", 0.0)
		m.render_priority = -10
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = s[0]
		mi.look_at_from_position(s[0], Vector3(0, 0, 0), Vector3.UP)
		mi.rotate_object_local(Vector3.FORWARD, float(s[2]))
		add_child(mi)
		_nebulae.append(mi)
		_neb_mats.append(m)
		_neb_target.append(Color(0.5, 0.5, 1.0))


func _build_bubble() -> void:
	_bubble = MeshInstance3D.new()
	_bubble.name = "ShieldBubble"
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 32
	s.rings = 16
	_bubble.mesh = s
	_bubble_mat = ShaderMaterial.new()
	_bubble_mat.shader = Shader.new()
	_bubble_mat.shader.code = BUBBLE_SHADER
	_bubble_mat.render_priority = 5
	_bubble.material_override = _bubble_mat
	_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubble.position = Vector3(0, 0.4, -1.0)
	_bubble.scale = Vector3(16.0, 5.5, 14.5)
	add_child(_bubble)


# --- Themes and landmarks -------------------------------------------------------------------------

## Switch the sector look (nebula colours blend over a couple of seconds; planet and landmark swap).
func set_theme(name_id: String) -> void:
	if not THEMES.has(name_id) or name_id == theme:
		return
	theme = name_id
	var t: Dictionary = THEMES[name_id]
	var neb: Array = t["neb"]
	for k in _nebulae.size():
		_neb_target[k] = neb[k % neb.size()]
	var pc: Array = t["planet"]
	_planet.mesh = Models.planet(pc[0], pc[1])
	_planet.position = t["ppos"]
	_planet.scale = Vector3.ONE * float(t["psize"])
	_planet.rotation = Vector3(0.25, float(name_id.length()) * 0.7, 0.18)
	set_landmark(String(t["landmark"]))


func set_landmark(kind: String) -> void:
	if kind == _landmark_kind:
		return
	_landmark_kind = kind
	if _landmark != null and is_instance_valid(_landmark):
		_landmark.queue_free()
		_landmark = null
	var mesh: ArrayMesh = null
	match kind:
		"bakery":
			mesh = Models.bakery_station()
		"trading_post":
			mesh = Models.trading_post()
		"party_station":
			mesh = Models.party_station()
	if mesh == null:
		return
	_landmark = MeshKit.instance(mesh, false)
	_landmark.name = "Landmark"
	add_child(_landmark)
	_landmark.position = LANDMARK_POS.get(kind, Vector3(0, 0, -120))


func landmark_node() -> Node3D:
	return _landmark


# --- Coordinates ---------------------------------------------------------------------------------

func to_world(p: Vector3) -> Vector3:
	return Vector3(p.x - offset.x, p.y - offset.y, p.z)


func to_space(w: Vector3) -> Vector3:
	return Vector3(w.x + offset.x, w.y + offset.y, w.z)


# --- Field (asteroids / storm) --------------------------------------------------------------------

## Start drawing a field (or clear it with kind == "").
func set_field(kind: String, seed_value: int, count: int, length: float) -> void:
	if _rocks != null:
		_rocks.queue_free()
		_rocks = null
	if _cells != null:
		_cells.queue_free()
		_cells = null
	field = null
	field_s = 0.0
	field_dead = PackedByteArray()
	if kind == "":
		return
	field = Field.new()
	field.setup(kind, seed_value, count, length)
	field_dead.resize(count)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = count
	if kind == "storm":
		mm.mesh = Models.storm_cell()
		_cells = MultiMeshInstance3D.new()
		_cells.multimesh = mm
		_cells.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_cells)
	else:
		mm.mesh = Models.asteroid(0)
		_rocks = MultiMeshInstance3D.new()
		_rocks.multimesh = mm
		_rocks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_rocks)
	for i in count:
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0, -900, 0)))
		mm.set_instance_color(i, Color.WHITE)


## World position of field object i right now.
func field_world(i: int) -> Vector3:
	if field == null:
		return Vector3.ZERO
	var p: Vector3 = field.pos[i]
	return Vector3(p.x - offset.x, p.y - offset.y, field.z_of(i, field_s))


func _update_field() -> void:
	if field == null:
		return
	var mmi: MultiMeshInstance3D = _cells if field.kind == "storm" else _rocks
	if mmi == null:
		return
	var mm := mmi.multimesh
	for i in field.count():
		var z := field.z_of(i, field_s)
		var dead := i < field_dead.size() and field_dead[i] != 0
		if dead or z > 40.0 or z < -300.0:
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0, -900, 0)))
			continue
		var p: Vector3 = field.pos[i]
		var s: float = field.size[i]
		var b := Basis()
		if field.kind == "storm":
			b = Basis(Vector3.UP, _t * 0.2 + i).scaled(Vector3(s, s * 0.7, s) * (1.0 + 0.06 * sin(_t * 2.0 + i)))
		else:
			var sp: Vector3 = field.spin[i]
			b = Basis(sp.normalized(), _t * sp.length() + i).scaled(Vector3.ONE * s)
		mm.set_instance_transform(i, Transform3D(b, Vector3(p.x - offset.x, p.y - offset.y, z)))
		if field.kind != "storm":
			var cr := field.crystal[i] != 0
			mm.set_instance_color(i, Color(0.55, 1.6, 1.8) if cr else Color.WHITE)
		else:
			var flick := 0.8 + 0.4 * sin(_t * 9.0 + i * 3.1) * sin(_t * 5.3 + i)
			mm.set_instance_color(i, Color(0.8 * flick, 0.55, 1.0 * flick))


# --- Effects --------------------------------------------------------------------------------------

## A laser bolt from `from` to `to` (space coordinates) taking `dur` seconds; burst = pop at the end.
func bolt(from: Vector3, to: Vector3, col: Color, dur: float, burst: bool = true, length: float = 3.0) -> void:
	var mi: MeshInstance3D = null
	while not _bolt_pool.is_empty() and mi == null:
		mi = _bolt_pool.pop_back()
		if not is_instance_valid(mi):
			mi = null
	if mi == null:
		mi = MeshInstance3D.new()
		mi.mesh = Models.bolt()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	var key := col.to_html(false)
	if not _bolt_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col
		m.vertex_color_use_as_albedo = false
		_bolt_mats[key] = m
	mi.material_override = _bolt_mats[key]
	mi.visible = true
	mi.scale = Vector3(1.0, 1.0, length)
	_bolts.append({"mi": mi, "from": from, "to": to, "t": 0.0, "dur": maxf(dur, 0.05), "burst": burst, "col": col})


## A torpedo flying from `from` (world) to a target node (or the fixed world point `to`).
func torpedo(from: Vector3, target: Node3D, to: Vector3, dur: float) -> void:
	var n := Node3D.new()
	var mi := MeshKit.instance(Models.torpedo(), false)
	mi.scale = Vector3.ONE * 2.2
	n.add_child(mi)
	var trail := CPUParticles3D.new()
	trail.amount = 24
	trail.lifetime = 0.5
	trail.local_coords = false
	trail.direction = Vector3(0, 0, 1)
	trail.spread = 12.0
	trail.initial_velocity_min = 1.0
	trail.initial_velocity_max = 2.0
	trail.gravity = Vector3.ZERO
	trail.scale_amount_min = 0.3
	trail.scale_amount_max = 0.6
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = MeshKit.material(Color(1.0, 0.7, 0.3), 2.0)
	trail.mesh = sm
	n.add_child(trail)
	trail.position = Vector3(0, 0, 1.0)
	add_child(n)
	n.position = from
	_torps.append({"node": n, "from": from, "target": target, "to": to, "t": 0.0, "dur": maxf(dur, 0.2)})


## An explosion at a world position (size 1 = a small ship).
func boom(pos: Vector3, size: float = 1.0, col: Color = Color(1.0, 0.6, 0.25)) -> void:
	var flash := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 12
	s.rings = 6
	flash.mesh = s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.95, 0.8, 0.9)
	flash.material_override = m
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash)
	flash.position = pos
	flash.scale = Vector3.ONE * 0.5 * size
	var tw := flash.create_tween().set_parallel()
	tw.tween_property(flash, "scale", Vector3.ONE * 3.2 * size, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.4)
	tw.chain().tween_callback(flash.queue_free)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 18 if vr else 28
	p.lifetime = 0.9
	p.explosiveness = 0.95
	p.spread = 180.0
	p.initial_velocity_min = 4.0 * size
	p.initial_velocity_max = 11.0 * size
	p.gravity = Vector3.ZERO
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = 0.5 * size
	p.scale_amount_max = 1.3 * size
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.4
	bm.material = MeshKit.material(col, 2.5)
	p.mesh = bm
	add_child(p)
	p.position = pos
	p.emitting = true
	get_tree().create_timer(1.4).timeout.connect(p.queue_free)


## A small spray of sparks (hits on the hull, sparking consoles).
func sparks(pos: Vector3, col: Color = Color(1.0, 0.85, 0.4), amount: int = 14) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.spread = 70.0
	p.direction = Vector3.UP
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.06
	bm.material = MeshKit.material(col, 3.0)
	p.mesh = bm
	add_child(p)
	p.position = pos
	p.emitting = true
	get_tree().create_timer(0.9).timeout.connect(p.queue_free)


## The shield bubble flashes where it was hit (dir = from the ship towards the hit, world space).
func shield_hit(dir: Vector3, strength: float = 1.0) -> void:
	_flash = clampf(strength, 0.0, 1.5)
	_bubble_mat.set_shader_parameter("hit_dir", dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD)


# --- Per frame ------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	_t += delta
	# Streaks flow past; the warp stretches them into tunnels.
	var mm := _streaks.multimesh
	var flow := speed * (1.0 + warp * 30.0)
	var stretch := 1.2 + speed * 0.12 + warp * 38.0
	for i in STREAKS:
		var p := _streak_pos[i]
		p.z += flow * delta
		if p.z > STREAK_Z.y:
			p.z -= STREAK_Z.y - STREAK_Z.x
		_streak_pos[i] = p
		var w := Vector3(p.x - offset.x * 0.6, p.y - offset.y * 0.6, p.z)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1.0 + warp * 2.0, 1.0 + warp * 2.0, stretch)), w))
	# Nebulae ease towards the theme colours (and dim during the warp).
	for k in _nebulae.size():
		var m := _neb_mats[k]
		var cur: Color = m.get_shader_parameter("col")
		m.set_shader_parameter("col", cur.lerp(_neb_target[k], 1.0 - exp(-1.5 * delta)))
		var st: float = m.get_shader_parameter("strength")
		m.set_shader_parameter("strength", lerpf(st, 0.85 * (1.0 - warp), 1.0 - exp(-2.0 * delta)))
		m.set_shader_parameter("drift", _t * 0.004 + k * 0.3)
	_planet.rotate_y(delta * 0.01)
	if _landmark != null:
		_landmark.visible = warp < 0.5
		_landmark.rotate_y(delta * 0.05)
	# Shield bubble.
	_flash = maxf(0.0, _flash - delta * 2.2)
	_bubble_mat.set_shader_parameter("flash", _flash)
	_bubble_mat.set_shader_parameter("level", shield_level)
	_bubble_mat.set_shader_parameter("super_on", super_shield)
	_bubble.visible = shield_level > 0.01 or _flash > 0.01 or super_shield > 0.01
	# Bolts.
	for i in range(_bolts.size() - 1, -1, -1):
		var b: Dictionary = _bolts[i]
		var t: float = float(b["t"]) + delta
		b["t"] = t
		var mi: MeshInstance3D = b["mi"]
		var from: Vector3 = b["from"]
		var to: Vector3 = b["to"]
		var dur: float = b["dur"]
		var k := clampf(t / dur, 0.0, 1.0)
		var pw := to_world(from.lerp(to, k))
		var dir := (to - from).normalized()
		if dir.length() > 0.01 and is_instance_valid(mi):
			mi.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD).scaled(Vector3(1, 1, mi.scale.z)), pw)
		if t >= dur:
			if bool(b["burst"]):
				sparks(to_world(to), b["col"], 10)
			if is_instance_valid(mi):
				mi.visible = false
				_bolt_pool.append(mi)
			_bolts.remove_at(i)
	# Torpedoes (they home onto their target node).
	for i in range(_torps.size() - 1, -1, -1):
		var tp: Dictionary = _torps[i]
		var n: Node3D = tp["node"]
		var t2: float = float(tp["t"]) + delta
		tp["t"] = t2
		var target: Node3D = tp["target"]
		var goal: Vector3 = tp["to"]
		if target != null and is_instance_valid(target) and target.is_inside_tree():
			goal = target.global_position
			tp["to"] = goal
		var k2 := clampf(t2 / float(tp["dur"]), 0.0, 1.0)
		var from2: Vector3 = tp["from"]
		var arc := Vector3(0, sin(k2 * PI) * 3.0, 0)
		var pos := from2.lerp(goal, k2 * k2 * (3.0 - 2.0 * k2) * 0.3 + k2 * 0.7) + arc
		if is_instance_valid(n):
			var d := pos - n.position
			if d.length() > 0.01:
				n.basis = Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.98 else Vector3.FORWARD)
			n.position = pos
		if k2 >= 1.0:
			if is_instance_valid(n):
				n.queue_free()
			_torps.remove_at(i)
	_update_field()
