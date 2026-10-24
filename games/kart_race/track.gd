extends Node3D
## A looping race track built from a few control points (Catmull-Rom spline, x/z plus height).
## Karts don't use the physics engine: they ask `locate()` where they are along the track
## (distance s, sideways offset lat, road height), the walls are just a limit on lat, and ramps,
## boost pads and item boxes live in (s, lat) space. Everything is generated in code.
## Each track has a theme: its own sky (sun or moon and stars), props (flowers and hay bales,
## lollipops and gumdrops, cacti, mesas and friendly dinosaurs, lanterns and glowing mushrooms,
## snowy pines, snowmen and falling snow), plus cheering grandstands, bunting and balloons, and
## start lights on the gantry. Repeated props are MultiMeshes; the crowd bobs in a vertex shader.

const WIDTH := 11.0  # road width
const CURB := 0.8  # coloured curb outside the road, then the wall
const WALL_H := 0.8
const STEP := 2.0  # spline sample spacing (m)
const BOX_RESPAWN := 4.0

## name, colours, control points [x, z, height], ramps [fraction, length, height, lat, half width],
## boost pads [fraction, lat], item box rows [fraction], theme (props), night (stars and moon)
const TRACKS := [
	{"name": "SUNNY MEADOW", "theme": "meadow", "sky": Color(0.55, 0.8, 1.0), "sky_top": Color(0.25, 0.5, 0.95),
		"grass": Color(0.42, 0.78, 0.35), "road": Color(0.36, 0.36, 0.42), "wall_a": Color(1.0, 0.35, 0.3), "wall_b": Color(1.0, 1.0, 1.0),
		"earth": Color(0.6, 0.45, 0.3), "trees": [Color(0.25, 0.65, 0.3), Color(0.4, 0.8, 0.3), Color(1.0, 0.6, 0.75)],
		"pts": [[0, 0, 0], [40, 0, 0], [75, -8, 0.5], [92, -35, 1.5], [85, -65, 2.5], [60, -80, 3], [30, -75, 2.5],
			[10, -58, 1.5], [-15, -50, 1], [-40, -62, 1.5], [-62, -55, 1], [-70, -30, 0.5], [-55, -8, 0], [-28, 2, 0]],
		"ramps": [[0.42, 8.0, 1.1, 0.0, 3.0]],
		"pads": [[0.1, 0.0], [0.6, -2.6], [0.83, 2.6]],
		"items": [0.2, 0.5, 0.74]},
	{"name": "CANDY HILLS", "theme": "candy", "sky": Color(1.0, 0.78, 0.88), "sky_top": Color(0.65, 0.55, 1.0),
		"grass": Color(0.62, 0.9, 0.65), "road": Color(0.45, 0.38, 0.5), "wall_a": Color(1.0, 0.45, 0.75), "wall_b": Color(0.55, 0.9, 1.0),
		"earth": Color(0.85, 0.6, 0.7), "trees": [Color(1.0, 0.5, 0.7), Color(0.6, 0.5, 1.0), Color(1.0, 0.9, 0.4)],
		"pts": [[0, 0, 0], [45, 5, 1], [80, -5, 3], [95, -35, 5], [80, -60, 4], [50, -55, 2], [30, -35, 1],
			[5, -40, 2], [-20, -65, 4], [-50, -70, 5], [-75, -50, 3], [-80, -20, 1], [-55, 0, 0], [-25, 0, 0]],
		"ramps": [[0.07, 7.0, 1.0, -2.5, 2.5], [0.62, 8.0, 1.2, 0.0, 3.0]],
		"pads": [[0.3, 0.0], [0.5, 2.6], [0.88, -2.6]],
		"items": [0.16, 0.45, 0.76]},
	{"name": "DINO DESERT", "theme": "desert", "sky": Color(1.0, 0.85, 0.6), "sky_top": Color(0.35, 0.6, 0.95),
		"grass": Color(0.92, 0.78, 0.5), "road": Color(0.45, 0.38, 0.33), "wall_a": Color(1.0, 0.55, 0.2), "wall_b": Color(1.0, 0.95, 0.8),
		"earth": Color(0.8, 0.55, 0.32), "trees": [Color(0.3, 0.65, 0.3)],
		"pts": [[0, 0, 0], [45, 0, 0], [80, -10, 1], [95, -40, 2], [78, -66, 3.5], [48, -62, 2], [25, -82, 1], [-10, -92, 0.5],
			[-45, -78, 1], [-66, -48, 2], [-52, -20, 1], [-26, -5, 0]],
		"ramps": [[0.06, 8.0, 1.2, 0.0, 3.0], [0.46, 7.0, 1.0, 2.0, 2.5]],
		"pads": [[0.22, 0.0], [0.66, -2.4], [0.86, 2.4]],
		"items": [0.14, 0.36, 0.75]},
	{"name": "MOONLIGHT BAY", "theme": "night", "night": true, "sky": Color(0.16, 0.18, 0.4), "sky_top": Color(0.02, 0.03, 0.12),
		"grass": Color(0.2, 0.45, 0.5), "road": Color(0.25, 0.25, 0.35), "wall_a": Color(0.3, 0.9, 1.0), "wall_b": Color(1.0, 0.85, 0.3),
		"earth": Color(0.3, 0.3, 0.45), "trees": [Color(0.3, 0.9, 0.8), Color(0.8, 0.5, 1.0), Color(0.4, 0.7, 1.0)],
		"pts": [[0, 0, 0], [50, 0, 0], [85, 15, 1], [110, 0, 2], [110, -35, 2], [85, -50, 1], [55, -40, 0],
			[30, -55, 1], [5, -75, 2], [-30, -70, 2], [-55, -45, 1], [-50, -15, 0], [-25, -3, 0]],
		"ramps": [[0.27, 8.0, 1.1, 0.0, 3.0], [0.7, 7.0, 1.0, 2.5, 2.5]],
		"pads": [[0.13, 0.0], [0.45, -2.6], [0.9, 0.0]],
		"items": [0.2, 0.55, 0.8]},
	{"name": "SNOWY PEAKS", "theme": "snow", "sky": Color(0.78, 0.86, 1.0), "sky_top": Color(0.35, 0.5, 0.9),
		"grass": Color(0.93, 0.96, 1.0), "road": Color(0.4, 0.42, 0.5), "wall_a": Color(0.3, 0.6, 1.0), "wall_b": Color(1.0, 1.0, 1.0),
		"earth": Color(0.82, 0.88, 0.98), "trees": [Color(0.15, 0.45, 0.3), Color(0.2, 0.5, 0.35)],
		"pts": [[0, 0, 0], [50, 0, 1], [85, -15, 3], [92, -50, 5], [62, -72, 6], [27, -57, 4], [0, -72, 3], [-30, -88, 4],
			[-66, -72, 3], [-82, -40, 2], [-62, -14, 1], [-30, 0, 0]],
		"ramps": [[0.4, 8.0, 1.1, 0.0, 3.0], [0.54, 7.0, 1.0, -2.0, 2.5]],
		"pads": [[0.08, 0.0], [0.64, 2.4], [0.9, -2.4]],
		"items": [0.18, 0.47, 0.72]},
]

const SKY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled;
uniform vec3 top_col = vec3(0.3, 0.55, 0.95);
uniform vec3 horizon_col = vec3(0.78, 0.9, 1.0);
uniform vec3 sun_dir = vec3(0.4, 0.6, -0.7);
uniform float night = 0.0;
varying vec3 dir;
void vertex() {
	dir = normalize(VERTEX);
}
void fragment() {
	vec3 d = normalize(dir);
	float up = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon_col, top_col, pow(up, 0.5));
	float s = max(dot(d, normalize(sun_dir)), 0.0);
	if (night > 0.5) {
		vec3 q = floor(d * 170.0);
		float h = fract(sin(dot(q, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		col += vec3(1.0, 0.97, 0.9) * step(0.996, h) * (0.6 + 0.4 * sin(TIME * 2.0 + h * 50.0)) * smoothstep(0.03, 0.25, d.y);
		col += vec3(1.0, 0.97, 0.85) * (smoothstep(0.9990, 0.9994, s) * 1.3 + pow(s, 30.0) * 0.2);
	} else {
		col += vec3(1.0, 0.95, 0.8) * (pow(s, 500.0) * 3.0 + pow(s, 10.0) * 0.3);
	}
	ALBEDO = col;
}
"""

## Crowd: one merged person mesh (vertex colour R = skin, G = arms), shirt colour and phase in the
## instance custom data; everyone bobs and waves, more when `cheer` goes up.
const CROWD_SHADER := """
shader_type spatial;
uniform float cheer = 0.3;
varying vec3 shirt;
varying float skin;
void vertex() {
	shirt = INSTANCE_CUSTOM.rgb;
	skin = COLOR.r;
	float ph = INSTANCE_CUSTOM.a * 6.2831;
	float hop = max(0.0, sin(TIME * (5.0 + INSTANCE_CUSTOM.a * 3.0) + ph)) * (0.06 + 0.28 * cheer);
	VERTEX.y += hop;
	VERTEX.y += COLOR.g * (0.5 + 0.5 * sin(TIME * 9.0 + ph * 2.0)) * 0.35 * cheer;
}
void fragment() {
	ALBEDO = mix(shirt, vec3(1.0, 0.8, 0.62), skin);
	ROUGHNESS = 0.8;
}
"""

## Balloons and lanterns gently bob (per instance).
const BOB_SHADER := """
shader_type spatial;
uniform float glow = 0.0;
void vertex() {
	VERTEX.y += sin(TIME * 0.9 + float(INSTANCE_ID) * 1.7) * 0.25;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * glow;
	ROUGHNESS = 0.35;
}
"""

var main
var track_i := -1
var info: Dictionary = {}
var pts := PackedVector3Array()  # centre line samples (y = road height)
var tans := PackedVector3Array()  # flat unit tangents
var cum := PackedFloat32Array()  # distance along the track at each sample (size n + 1)
var n := 0
var length := 0.0
var ramps: Array = []  # [s0, len, height, lat, half width]
var pads: Array = []  # [s0, len, lat, half width]
var boxes: Array[Vector3] = []
var box_t: Array[float] = []  # > 0: respawning
var box_nodes: Array[MeshInstance3D] = []
var boxes_on := true  # main: false hides the ? boxes (simple mode: race 1 is just driving)
var box_mat: StandardMaterial3D
var pad_mat: StandardMaterial3D
var built: Node3D
var spin := 0.0
var crowd_mat: ShaderMaterial
var cheer := 0.3
var cheer_want := 0.3
var lights_mats: Array[StandardMaterial3D] = []
var dinos: Array[Node3D] = []
var snow: CPUParticles3D
var sky_mat: ShaderMaterial


static func count() -> int:
	return TRACKS.size()


static func track_name(i: int) -> String:
	var d: Dictionary = TRACKS[posmod(i, TRACKS.size())]
	return str(d["name"])


func wall_limit() -> float:
	return WIDTH * 0.5 + CURB


func is_night() -> bool:
	return bool(info.get("night", false))


# --- Queries -------------------------------------------------------------------------

## Where is p? Returns [sample index, s, lat, road height, tangent]. hint: last index (or -1).
func locate(p: Vector3, hint: int) -> Array:
	var best := -1
	var bd := INF
	if hint >= 0 and hint < n:
		for k in range(-10, 11):
			var i := posmod(hint + k, n)
			var q := pts[i]
			var d := (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z) + (q.y - p.y) * (q.y - p.y) * 0.25
			if d < bd:
				bd = d
				best = i
	if best < 0 or bd > 400.0:
		bd = INF
		for i in n:
			var q := pts[i]
			var d := (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z) + (q.y - p.y) * (q.y - p.y) * 0.25
			if d < bd:
				bd = d
				best = i
	var i0 := best
	var a := pts[i0]
	var b := pts[(i0 + 1) % n]
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var t := Vector2(p.x - a.x, p.z - a.z).dot(ab) / maxf(ab.length_squared(), 0.0001)
	if t < 0.0:
		i0 = (best - 1 + n) % n
		a = pts[i0]
		b = pts[(i0 + 1) % n]
		ab = Vector2(b.x - a.x, b.z - a.z)
		t = Vector2(p.x - a.x, p.z - a.z).dot(ab) / maxf(ab.length_squared(), 0.0001)
	t = clampf(t, 0.0, 1.0)
	var s := cum[i0] + t * (cum[i0 + 1] - cum[i0])
	var h := lerpf(a.y, b.y, t)
	var tg := tans[i0].lerp(tans[(i0 + 1) % n], t).normalized()
	var rt := Vector3(-tg.z, 0.0, tg.x)
	var cx := lerpf(a.x, b.x, t)
	var cz := lerpf(a.z, b.z, t)
	var lat := Vector3(p.x - cx, 0.0, p.z - cz).dot(rt)
	return [best, s, lat, h, tg]


## Road surface height including ramps.
func ground(s: float, lat: float, h: float) -> float:
	return h + ramp_height(s, lat)


func ramp_height(s: float, lat: float) -> float:
	for r in ramps:
		var ra: Array = r
		var s0: float = ra[0]
		var ln: float = ra[1]
		var ds := fposmod(s - s0, length)
		if ds <= ln and absf(lat - float(ra[3])) <= float(ra[4]):
			return float(ra[2]) * ds / ln
	return 0.0


## True right at the lip of a ramp (the kart launches from here).
func at_ramp_lip(s: float, lat: float) -> bool:
	for r in ramps:
		var ra: Array = r
		var ds := fposmod(s - float(ra[0]), length)
		if ds > float(ra[1]) - 1.2 and ds <= float(ra[1]) + 0.5 and absf(lat - float(ra[3])) <= float(ra[4]):
			return true
	return false


func on_pad(s: float, lat: float) -> bool:
	for p in pads:
		var pa: Array = p
		if fposmod(s - float(pa[0]), length) <= float(pa[1]) and absf(lat - float(pa[2])) <= float(pa[3]):
			return true
	return false


## Point on the track at distance s and sideways offset lat: [position, yaw facing along the track].
func point_at(s: float, lat: float) -> Array:
	s = fposmod(s, length)
	var lo := 0
	var hi := n - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	var i0 := lo
	var a := pts[i0]
	var b := pts[(i0 + 1) % n]
	var t := (s - cum[i0]) / maxf(cum[i0 + 1] - cum[i0], 0.0001)
	var tg := tans[i0].lerp(tans[(i0 + 1) % n], t).normalized()
	var rt := Vector3(-tg.z, 0.0, tg.x)
	var c := a.lerp(b, t)
	var pos := c + rt * lat
	pos.y = ground(s, lat, c.y)
	return [pos, atan2(-tg.x, -tg.z), i0]


## Starting grid: two columns behind the start line.
func grid_point(slot: int) -> Array:
	var row := slot / 2
	var col := slot % 2
	var s := length - 5.0 - row * 4.5 - col * 1.6
	return point_at(s, -2.6 if col == 0 else 2.6) + [s - length]


# --- Building --------------------------------------------------------------------------

func build(i: int) -> void:
	i = posmod(i, TRACKS.size())
	if i == track_i and built != null:
		return
	track_i = i
	info = TRACKS[i]
	if built != null:
		built.queue_free()
	built = Node3D.new()
	built.name = "Built"
	add_child(built)
	dinos.clear()
	snow = null
	_sample()
	_features()
	_build_sky()
	_build_road()
	_build_pads()
	_build_boxes()
	_build_gantry()
	_build_scenery()
	_build_crowd()
	_build_theme()
	print("Track %d: %s, %.0f m, %d samples" % [i, info["name"], length, n])


func _cp(i: int) -> Vector3:
	var arr: Array = info["pts"]
	var p: Array = arr[posmod(i, arr.size())]
	return Vector3(float(p[0]), float(p[2]), float(p[1]))


func _sample() -> void:
	pts = PackedVector3Array()
	var arr: Array = info["pts"]
	var m := arr.size()
	for i in m:
		var p0 := _cp(i - 1)
		var p1 := _cp(i)
		var p2 := _cp(i + 1)
		var p3 := _cp(i + 2)
		var seg := Vector2(p2.x - p1.x, p2.z - p1.z).length()
		var k := maxi(2, int(ceilf(seg / STEP)))
		for j in k:
			var t := float(j) / k
			var t2 := t * t
			var t3 := t2 * t
			var v := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
			pts.append(v)
	n = pts.size()
	tans = PackedVector3Array()
	tans.resize(n)
	cum = PackedFloat32Array()
	cum.resize(n + 1)
	var acc := 0.0
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var pa := pts[(i - 1 + n) % n]
		var d := Vector3(b.x - pa.x, 0.0, b.z - pa.z).normalized()
		tans[i] = d
		cum[i] = acc
		acc += Vector2(b.x - a.x, b.z - a.z).length()
	cum[n] = acc
	length = acc


func _features() -> void:
	ramps.clear()
	for r in info["ramps"]:
		var ra: Array = r
		ramps.append([float(ra[0]) * length, float(ra[1]), float(ra[2]), float(ra[3]), float(ra[4])])
	pads.clear()
	for p in info["pads"]:
		var pa: Array = p
		pads.append([float(pa[0]) * length, 5.0, float(pa[1]), 1.6])
	boxes.clear()
	box_t.clear()
	for f in info["items"]:
		var s: float = float(f) * length
		for lat in [-3.6, -1.2, 1.2, 3.6]:
			var pp: Array = point_at(s, float(lat))
			var bp: Vector3 = pp[0]
			boxes.append(bp + Vector3(0, 0.9, 0))
			box_t.append(0.0)


func _vcol_mat(unshaded: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, nrm: Vector3) -> void:
	st.set_color(col)
	st.set_normal(nrm)
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)


func _build_sky() -> void:
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 420.0
	sm.height = 840.0
	sm.radial_segments = 20
	sm.rings = 10
	dome.mesh = sm
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = Shader.new()
	sky_mat.shader.code = SKY_SHADER
	sky_mat.render_priority = -100
	var top: Color = info.get("sky_top", Color(0.3, 0.55, 0.95))
	var hor: Color = info["sky"]
	sky_mat.set_shader_parameter("top_col", Vector3(top.r, top.g, top.b))
	sky_mat.set_shader_parameter("horizon_col", Vector3(hor.r, hor.g, hor.b))
	sky_mat.set_shader_parameter("night", 1.0 if is_night() else 0.0)
	sky_mat.set_shader_parameter("sun_dir", Vector3(-0.35, 0.45, -0.82).normalized() if is_night() else Vector3(0.45, 0.55, -0.7).normalized())
	dome.material_override = sky_mat
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dome.position = Vector3(20, 0, -35)
	built.add_child(dome)
	if is_night():
		return
	# A few puffy clouds (three squashed spheres each, one MultiMesh).
	var rng := RandomNumberGenerator.new()
	rng.seed = 55 + track_i
	var xf: Array[Transform3D] = []
	for i in 12:
		var a := rng.randf() * TAU
		var r := rng.randf_range(200.0, 320.0)
		var c := Vector3(20 + sin(a) * r, rng.randf_range(60.0, 100.0), -35 + cos(a) * r)
		var s := rng.randf_range(1.2, 2.2)
		var along := Vector3(cos(a), 0.0, -sin(a))
		for j in 3:
			xf.append(Transform3D(Basis().scaled(Vector3(11.0, 4.5 + (2.0 if j == 1 else 0.0), 8.0) * s),
				c + along * (float(j) - 1.0) * 10.0 * s + Vector3(0, (2.0 if j == 1 else 0.0) * s, 0)))
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = Color(1, 1, 1) if str(info["theme"]) != "candy" else Color(1.0, 0.92, 0.97)
	_mm(main.sphere_mesh(1.0), cm, xf)


func _build_road() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var road: Color = info["road"]
	var wa: Color = info["wall_a"]
	var wb: Color = info["wall_b"]
	var earth: Color = info["earth"]
	var hw := WIDTH * 0.5
	var wl := wall_limit()
	for i in n:
		var j := (i + 1) % n
		var a := pts[i]
		var b := pts[j]
		var ra := Vector3(-tans[i].z, 0, tans[i].x)
		var rb := Vector3(-tans[j].z, 0, tans[j].x)
		var up := Vector3.UP
		var lift := Vector3(0, 0.02, 0)
		var stripe := road if (i / 3) % 2 == 0 else road.lightened(0.06)
		if cum[i] < 2.5:
			# Start / finish line: a checkered band.
			var cells := 8
			for c in cells:
				var l0 := -hw + WIDTH * c / cells
				var l1 := -hw + WIDTH * (c + 1) / cells
				var dark := (c + i) % 2 == 0
				_quad(st, a + ra * l0 + lift, a + ra * l1 + lift, b + rb * l1 + lift, b + rb * l0 + lift,
					Color(0.1, 0.1, 0.1) if dark else Color(1, 1, 1), up)
		else:
			_quad(st, a - ra * hw + lift, a + ra * hw + lift, b + rb * hw + lift, b - rb * hw + lift, stripe, up)
			# Dashed centre line.
			if (i / 2) % 2 == 0:
				var l2 := Vector3(0, 0.03, 0)
				_quad(st, a - ra * 0.12 + l2, a + ra * 0.12 + l2, b + rb * 0.12 + l2, b - rb * 0.12 + l2, Color(1, 1, 0.85), up)
		var curb := wa if i % 2 == 0 else wb
		for side in [-1.0, 1.0]:
			var sd: float = side
			_quad(st, a + ra * hw * sd + lift, a + ra * wl * sd + lift, b + rb * wl * sd + lift, b + rb * hw * sd + lift, curb, up)
			# Wall: low striped barrier on top of an earth bank down to the ground.
			var wcol := wa if (i / 2) % 2 == 0 else wb
			var ia := a + ra * wl * sd
			var ib := b + rb * wl * sd
			var inward := -ra * sd
			_quad(st, ia, ib, ib + Vector3(0, WALL_H, 0), ia + Vector3(0, WALL_H, 0), wcol, inward)
			_quad(st, Vector3(ia.x, -0.2, ia.z), Vector3(ib.x, -0.2, ib.z), ib, ia, earth, -inward)
			# Wall top.
			var oa := ia + ra * sd * 0.4
			var ob := ib + rb * sd * 0.4
			var hh := Vector3(0, WALL_H, 0)
			_quad(st, ia + hh, ib + hh, ob + hh, oa + hh, wcol.lightened(0.2), up)
			_quad(st, Vector3(oa.x, -0.2, oa.z), Vector3(ob.x, -0.2, ob.z), ob + hh, oa + hh, earth, -inward)
	# Ramps: a sloped deck following the track, with a front face at the lip.
	for r in ramps:
		var ra2: Array = r
		var s0: float = ra2[0]
		var ln: float = ra2[1]
		var rh: float = ra2[2]
		var lc: float = ra2[3]
		var w: float = ra2[4]
		var steps := 6
		var prev_l: Vector3
		var prev_r: Vector3
		for k in steps + 1:
			var s := s0 + ln * k / steps
			var pl: Array = point_at(s, lc - w)
			var pr: Array = point_at(s, lc + w)
			var vl: Vector3 = pl[0]
			var vr: Vector3 = pr[0]
			vl.y += 0.03
			vr.y += 0.03
			if k > 0:
				var col := Color(1.0, 0.8, 0.2) if k % 2 == 0 else Color(1.0, 0.55, 0.15)
				_quad(st, prev_l, prev_r, vr, vl, col, Vector3.UP)
				# Side skirts.
				_quad(st, Vector3(prev_l.x, prev_l.y - (rh * (k - 1) / steps), prev_l.z), Vector3(vl.x, vl.y - rh * k / steps, vl.z), vl, prev_l, Color(0.8, 0.4, 0.1), Vector3.LEFT)
				_quad(st, Vector3(prev_r.x, prev_r.y - (rh * (k - 1) / steps), prev_r.z), Vector3(vr.x, vr.y - rh * k / steps, vr.z), vr, prev_r, Color(0.8, 0.4, 0.1), Vector3.RIGHT)
			if k == steps:
				_quad(st, vl, vr, vr - Vector3(0, rh, 0), vl - Vector3(0, rh, 0), Color(0.75, 0.35, 0.1), Vector3.FORWARD)
			prev_l = vl
			prev_r = vr
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _vcol_mat(false)
	built.add_child(mi)
	# Ground.
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(700, 700)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = info["grass"]
	gm.roughness = 1.0
	g.material_override = gm
	g.position = Vector3(20, -0.15, -35)
	built.add_child(g)


func _build_pads() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in pads:
		var pa: Array = p
		var s0: float = pa[0]
		var ln: float = pa[1]
		var lc: float = pa[2]
		var w: float = pa[3]
		# Three glowing chevrons pointing along the track.
		for c in 3:
			var sa := s0 + ln * (c + 0.1) / 3.0
			var sb := s0 + ln * (c + 0.9) / 3.0
			var l0: Array = point_at(sa, lc - w)
			var r0: Array = point_at(sa, lc + w)
			var tip: Array = point_at(sb, lc)
			var mid: Array = point_at(sa + (sb - sa) * 0.45, lc)
			var lift := Vector3(0, 0.06, 0)
			var col := Color(1.0, 0.6, 0.1) if c % 2 == 0 else Color(1.0, 0.9, 0.2)
			st.set_color(col)
			st.set_normal(Vector3.UP)
			for v in [l0[0], tip[0], mid[0], mid[0], tip[0], r0[0]]:
				var vv: Vector3 = v
				st.add_vertex(vv + lift)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	pad_mat = _vcol_mat(true)
	mi.material_override = pad_mat
	built.add_child(mi)


func _build_boxes() -> void:
	box_nodes.clear()
	box_mat = StandardMaterial3D.new()
	box_mat.albedo_color = Color(1, 0.5, 0.2)
	box_mat.emission_enabled = true
	box_mat.emission = Color(1, 0.5, 0.2)
	box_mat.emission_energy_multiplier = 0.6
	box_mat.roughness = 0.3
	box_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box_mat.albedo_color.a = 0.75
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color(1, 1, 1)
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var bm := BoxMesh.new()
	bm.size = Vector3(1.1, 1.1, 1.1)
	# A "?" made of three little blocks inside each box (one merged mesh).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in [[Vector3(0, 0.2, 0), Vector3(0.32, 0.1, 0.1)], [Vector3(0.12, 0.08, 0), Vector3(0.1, 0.22, 0.1)],
			[Vector3(0, -0.06, 0), Vector3(0.1, 0.12, 0.1)], [Vector3(0, -0.25, 0), Vector3(0.1, 0.1, 0.1)]]:
		var pp: Array = part
		main.add_box(st, pp[0], pp[1], Color(1, 1, 1))
	var qm := st.commit()
	for b in boxes:
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = box_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		built.add_child(mi)
		mi.position = b
		mi.rotation = Vector3(0.6, 0.0, 0.6)
		var core := MeshInstance3D.new()
		core.mesh = qm
		core.material_override = core_mat
		mi.add_child(core)
		box_nodes.append(mi)


func _build_gantry() -> void:
	var g := Node3D.new()
	built.add_child(g)
	var p: Array = point_at(0.0, 0.0)
	g.position = p[0]
	g.rotation.y = float(p[1])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = info["wall_a"]
	var w := wall_limit() + 0.6
	for sd in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.3
		cm.bottom_radius = 0.35
		cm.height = 5.5
		cm.radial_segments = 10
		post.mesh = cm
		post.material_override = mat
		post.position = Vector3(float(sd) * w, 2.75, 0)
		g.add_child(post)
	var bar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w * 2.0 + 0.8, 1.2, 0.5)
	bar.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.1, 0.1, 0.15)
	bar.material_override = bmat
	bar.position = Vector3(0, 5.6, 0)
	g.add_child(bar)
	for face in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = "FINISH" if face > 0.0 else "START"
		l.font_size = 120
		l.pixel_size = 0.01
		l.outline_size = 20
		l.modulate = Color(1.0, 0.95, 0.4)
		l.position = Vector3(0, 5.6, 0.27 * float(face))
		l.rotation.y = 0.0 if face > 0.0 else PI
		g.add_child(l)
	# Start lights facing the grid: three red, then all green at GO.
	lights_mats.clear()
	var housing := MeshInstance3D.new()
	housing.mesh = main.box_mesh(Vector3(2.6, 0.9, 0.3))
	housing.material_override = bmat
	housing.position = Vector3(0, 4.55, 0.35)
	g.add_child(housing)
	for i in 3:
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.25, 0.05, 0.05)
		lm.emission_enabled = true
		lm.emission = Color(1.0, 0.15, 0.1)
		lm.emission_energy_multiplier = 0.0
		var bulb := MeshInstance3D.new()
		bulb.mesh = main.sphere_mesh(0.3)
		bulb.material_override = lm
		bulb.position = Vector3((i - 1) * 0.8, 4.55, 0.55)
		g.add_child(bulb)
		lights_mats.append(lm)


## 0: all off, 1-3: that many red lights, 4: all green (GO!).
func set_lights(k: int) -> void:
	for i in lights_mats.size():
		var lm := lights_mats[i]
		if k >= 4:
			lm.albedo_color = Color(0.1, 0.6, 0.15)
			lm.emission = Color(0.2, 1.0, 0.3)
			lm.emission_energy_multiplier = 3.0
		elif i < k:
			lm.albedo_color = Color(0.6, 0.08, 0.06)
			lm.emission = Color(1.0, 0.15, 0.1)
			lm.emission_energy_multiplier = 3.0
		else:
			lm.albedo_color = Color(0.25, 0.05, 0.05)
			lm.emission_energy_multiplier = 0.0


func _mm(mesh: Mesh, mat: Material, xf: Array[Transform3D], cols: Array[Color] = [], custom: Array[Color] = []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.use_custom_data = not custom.is_empty()
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		if mm.use_colors:
			mm.set_instance_color(i, cols[i % cols.size()])
		if mm.use_custom_data:
			mm.set_instance_custom_data(i, custom[i % custom.size()])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	built.add_child(mi)
	return mi


## Random spots beside the track (outside the walls), between near and far metres from the road.
func _side_spots(rng: RandomNumberGenerator, count_want: int, near: float, far: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var tries := 0
	while out.size() < count_want and tries < count_want * 20:
		tries += 1
		var s := rng.randf() * length
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var lat := side * (wall_limit() + rng.randf_range(near, far))
		var pa: Array = point_at(s, lat)
		var p: Vector3 = pa[0]
		var r: Array = locate(p, -1)
		if absf(float(r[2])) < wall_limit() + near * 0.8:
			continue  # another part of the track runs past here
		if s < 30.0 or s > length - 40.0:
			continue  # the grandstands live by the start
		p.y = -0.1
		out.append(p)
	return out


func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234 + track_i * 77
	var theme := str(info["theme"])
	var cols: Array = info["trees"]
	var spots: Array[Vector3] = []
	var tries := 0
	var want := 70 if theme != "desert" else 0
	while spots.size() < want and tries < 800:
		tries += 1
		var p := Vector3(rng.randf_range(-140, 170), 0, rng.randf_range(-160, 70))
		var r: Array = locate(p, -1)
		var lat: float = r[2]
		var q: Vector3 = pts[int(r[0])]
		var d := Vector2(p.x - q.x, p.z - q.z).length()
		if absf(lat) < wall_limit() + 4.0 or d < wall_limit() + 4.0:
			continue
		spots.append(p)
	if not spots.is_empty():
		var trunk_x: Array[Transform3D] = []
		var crown_x: Array[Transform3D] = []
		var cap_x: Array[Transform3D] = []
		var crown_c: Array[Color] = []
		for i in spots.size():
			var sc := rng.randf_range(0.8, 1.5)
			var p := spots[i]
			trunk_x.append(Transform3D(Basis().scaled(Vector3.ONE * sc), p + Vector3(0, 1.2 * sc, 0)))
			if theme == "snow":
				crown_x.append(Transform3D(Basis().scaled(Vector3(2.2, 5.0, 2.2) * sc), p + Vector3(0, 4.4 * sc, 0)))
				cap_x.append(Transform3D(Basis().scaled(Vector3(1.2, 2.2, 1.2) * sc), p + Vector3(0, 6.2 * sc, 0)))
			else:
				crown_x.append(Transform3D(Basis().scaled(Vector3(sc, sc * 1.15, sc) * 1.6), p + Vector3(0, 3.2 * sc, 0)))
			var c: Color = cols[rng.randi() % cols.size()]
			crown_c.append(c)
		var tm := CylinderMesh.new()
		tm.top_radius = 0.25
		tm.bottom_radius = 0.35
		tm.height = 2.4
		tm.radial_segments = 6
		_mm(tm, main.make_material(Color(0.5, 0.35, 0.22), 0.0), trunk_x)
		var cmat := StandardMaterial3D.new()
		cmat.vertex_color_use_as_albedo = true
		cmat.roughness = 0.8
		if is_night():
			cmat.emission_enabled = true
			cmat.emission = Color(0.12, 0.25, 0.3)
		if theme == "snow":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 1.0
			cone.height = 1.0
			cone.radial_segments = 8
			cone.rings = 1
			_mm(cone, cmat, crown_x, crown_c)
			_mm(cone, main.make_material(Color(0.97, 0.98, 1.0), 0.1), cap_x)
		else:
			_mm(main.sphere_mesh(1.0), cmat, crown_x, crown_c)
	# Far-off hills (snowy mountains on the snow track, mesas in the desert).
	var hill_x: Array[Transform3D] = []
	var hill_c: Array[Color] = []
	var grass: Color = info["grass"]
	for i in 12:
		var a := TAU * i / 12.0 + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(230, 290)
		var sz := rng.randf_range(40, 80)
		var tall := rng.randf_range(0.35, 0.6)
		if theme == "snow":
			tall = rng.randf_range(0.9, 1.4)
		hill_x.append(Transform3D(Basis().scaled(Vector3(sz, sz * tall, sz)), Vector3(20 + cos(a) * r, -5, -35 + sin(a) * r)))
		var hc := grass.darkened(rng.randf_range(0.05, 0.3))
		if theme == "desert":
			hc = Color(0.85, 0.5, 0.3).darkened(rng.randf_range(0.0, 0.2))
		elif theme == "snow":
			hc = Color(0.92, 0.95, 1.0).darkened(rng.randf_range(0.0, 0.15))
		hill_c.append(hc)
	var hmat := StandardMaterial3D.new()
	hmat.vertex_color_use_as_albedo = true
	hmat.roughness = 0.9
	if is_night():
		hmat.emission_enabled = true
		hmat.emission = Color(0.05, 0.08, 0.15)
	_mm(main.sphere_mesh(1.0), hmat, hill_x, hill_c)


## Grandstands with a cheering crowd on both sides of the start, bunting along the walls nearby,
## and smaller crowds by the ramps.
func _build_crowd() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + track_i
	var stands: Array[Transform3D] = []
	var people: Array[Transform3D] = []
	var shirts: Array[Color] = []
	var palette: Array[Color] = [Color(1.0, 0.3, 0.3), Color(0.3, 0.6, 1.0), Color(1.0, 0.85, 0.2), Color(0.4, 0.9, 0.4),
		Color(0.9, 0.5, 1.0), Color(1.0, 0.6, 0.2), Color(1, 1, 1), Color(0.3, 0.9, 0.9)]
	var spots: Array = []  # [s, side, rows, per row]
	spots.append([length - 12.0, -1.0, 3, 9])
	spots.append([length - 12.0, 1.0, 3, 9])
	for r in ramps:
		var ra: Array = r
		spots.append([float(ra[0]) + float(ra[1]), -1.0 if rng.randf() < 0.5 else 1.0, 2, 6])
	for sp in spots:
		var spa: Array = sp
		var s0: float = spa[0]
		var side: float = spa[1]
		var rows: int = spa[2]
		var per: int = spa[3]
		for row in rows:
			var lat := side * (wall_limit() + 2.2 + row * 1.1)
			var h := 0.35 + row * 0.6
			for k in per:
				var s := s0 + (k - per * 0.5) * 1.15
				var pa: Array = point_at(s, lat)
				var p: Vector3 = pa[0]
				var yaw: float = pa[1] + (-PI * 0.5 if side < 0.0 else PI * 0.5)  # face the road
				var base_y := pts[int(pa[2])].y
				people.append(Transform3D(Basis(Vector3.UP, yaw) * Basis().scaled(Vector3.ONE * rng.randf_range(0.85, 1.1)),
					Vector3(p.x, base_y + h, p.z)))
				var sc := palette[rng.randi() % palette.size()]
				shirts.append(Color(sc.r, sc.g, sc.b, rng.randf()))
			# The stand step under this row.
			var mid: Array = point_at(s0, lat + side * 0.2)
			var mp: Vector3 = mid[0]
			var top := pts[int(mid[2])].y + h  # from the ground up to this row's seats
			stands.append(Transform3D(Basis(Vector3.UP, float(mid[1])) * Basis().scaled(Vector3(per * 1.15 + 0.6, top + 0.2, 1.1)),
				Vector3(mp.x, (top - 0.2) * 0.5, mp.z)))
	_mm(main.box_mesh(Vector3.ONE), main.make_material(Color(0.55, 0.5, 0.6), 0.0), stands)
	crowd_mat = ShaderMaterial.new()
	crowd_mat.shader = Shader.new()
	crowd_mat.shader.code = CROWD_SHADER
	_mm(main.person_mesh(), crowd_mat, people, [], shirts)
	# Bunting: little flags strung along both walls around the start.
	var flags: Array[Transform3D] = []
	var flag_c: Array[Color] = []
	var s := length - 40.0
	while s < length + 25.0:
		for side in [-1.0, 1.0]:
			var pa: Array = point_at(s, float(side) * (wall_limit() + 0.2))
			var p: Vector3 = pa[0]
			flags.append(Transform3D(Basis(Vector3.UP, float(pa[1])) * Basis(Vector3.FORWARD, PI).scaled(Vector3(0.45, 0.5, 0.05)),
				Vector3(p.x, pts[int(pa[2])].y + WALL_H + 0.9, p.z)))
			flag_c.append(palette[int(s) % palette.size()])
		s += 1.6
	var fmat := StandardMaterial3D.new()
	fmat.vertex_color_use_as_albedo = true
	fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if is_night():
		fmat.emission_enabled = true
		fmat.emission = Color(0.3, 0.3, 0.3)
	_mm(PrismMesh.new(), fmat, flags, flag_c)
	# Balloons (lanterns at night) floating over the start.
	var balls: Array[Transform3D] = []
	var ball_c: Array[Color] = []
	for i in 14:
		var pa: Array = point_at(length - rng.randf_range(0.0, 50.0), (-1.0 if i % 2 == 0 else 1.0) * (wall_limit() + rng.randf_range(1.0, 7.0)))
		var p: Vector3 = pa[0]
		balls.append(Transform3D(Basis().scaled(Vector3(0.7, 0.85, 0.7)), p + Vector3(0, rng.randf_range(5.0, 9.0), 0)))
		ball_c.append(palette[i % palette.size()])
	var bmat := ShaderMaterial.new()
	bmat.shader = Shader.new()
	bmat.shader.code = BOB_SHADER
	bmat.set_shader_parameter("glow", 1.2 if is_night() else 0.15)
	_mm(main.sphere_mesh(1.0), bmat, balls, ball_c)


## Theme props: what makes each track feel different.
func _build_theme() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4321 + track_i * 13
	match str(info["theme"]):
		"meadow":
			var fl: Array[Transform3D] = []
			var fc: Array[Color] = []
			var petal: Array[Color] = [Color(1.0, 0.35, 0.45), Color(1.0, 0.9, 0.2), Color(0.9, 0.55, 1.0), Color(1, 1, 1)]
			for p in _side_spots(rng, 160, 0.5, 9.0):
				fl.append(Transform3D(Basis().scaled(Vector3(0.22, 0.16, 0.22)), p + Vector3(0, 0.3, 0)))
				fc.append(petal[rng.randi() % petal.size()])
			_mm(main.sphere_mesh(1.0), _vc(0.2), fl, fc)
			var hay: Array[Transform3D] = []
			for p in _side_spots(rng, 18, 3.0, 12.0):
				hay.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5), p + Vector3(0, 0.75, 0)))
			_mm(main.cyl_mesh(0.8, 0.8, 1.4, 12), main.make_material(Color(0.95, 0.8, 0.35), 0.0), hay)
		"candy":
			var sticks: Array[Transform3D] = []
			var discs: Array[Transform3D] = []
			var dc: Array[Color] = []
			var candy: Array[Color] = [Color(1.0, 0.35, 0.6), Color(0.45, 0.8, 1.0), Color(1.0, 0.85, 0.3), Color(0.6, 1.0, 0.5), Color(0.8, 0.5, 1.0)]
			for p in _side_spots(rng, 26, 2.0, 14.0):
				var h := rng.randf_range(3.0, 6.0)
				sticks.append(Transform3D(Basis().scaled(Vector3(1.0, h / 4.0, 1.0)), p + Vector3(0, h * 0.5, 0)))
				var yaw := rng.randf() * TAU
				discs.append(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1.0, 1.0, 1.0) * rng.randf_range(1.0, 1.6)), p + Vector3(0, h + 0.6, 0)))
				dc.append(candy[rng.randi() % candy.size()])
			_mm(main.cyl_mesh(0.12, 0.12, 4.0, 6), main.make_material(Color(1, 1, 1), 0.0), sticks)
			_mm(main.cyl_mesh(1.0, 1.0, 0.3, 16), _vc(0.25), discs, dc)
			var gum: Array[Transform3D] = []
			var gc: Array[Color] = []
			for p in _side_spots(rng, 40, 0.5, 10.0):
				var sc := rng.randf_range(0.5, 1.1)
				gum.append(Transform3D(Basis().scaled(Vector3(sc, sc * 0.8, sc)), p + Vector3(0, sc * 0.3, 0)))
				gc.append(candy[rng.randi() % candy.size()])
			_mm(main.sphere_mesh(1.0), _vc(0.35), gum, gc)
		"desert":
			var trunk: Array[Transform3D] = []
			var arms: Array[Transform3D] = []
			for p in _side_spots(rng, 40, 2.0, 18.0):
				var h := rng.randf_range(2.0, 4.0)
				trunk.append(Transform3D(Basis().scaled(Vector3(1.0, h / 2.0, 1.0)), p + Vector3(0, h * 0.5, 0)))
				var yaw := rng.randf() * TAU
				for side in [-1.0, 1.0]:
					if rng.randf() < 0.75:
						var b := Basis(Vector3.UP, yaw)
						arms.append(Transform3D(b.scaled(Vector3(0.7, 0.55, 0.7)), p + b * Vector3(float(side) * 0.55, h * rng.randf_range(0.45, 0.7), 0)))
			var green: StandardMaterial3D = main.make_material(Color(0.3, 0.62, 0.3), 0.0)
			_mm(main.capsule_mesh(0.35, 2.0), green, trunk)
			_mm(main.capsule_mesh(0.35, 2.0), green, arms)
			var rocks: Array[Transform3D] = []
			for p in _side_spots(rng, 10, 12.0, 40.0):
				var w := rng.randf_range(4.0, 9.0)
				var h := rng.randf_range(6.0, 14.0)
				rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(w, h, w * 0.8)), p + Vector3(0, h * 0.5 - 0.5, 0)))
			_mm(main.cyl_mesh(0.45, 0.55, 1.0, 7), main.make_material(Color(0.82, 0.48, 0.28), 0.0), rocks)
			# Friendly long-neck dinosaurs watching the race (their necks bob).
			for p in _side_spots(rng, 3, 9.0, 16.0):
				_dino(p, rng)
		"night":
			var posts: Array[Transform3D] = []
			var bulbs: Array[Transform3D] = []
			var bc: Array[Color] = []
			var glowc: Array[Color] = [Color(1.0, 0.8, 0.4), Color(0.4, 0.9, 1.0), Color(1.0, 0.5, 0.9)]
			var s := 6.0
			var k := 0
			while s < length - 6.0:
				var side := -1.0 if k % 2 == 0 else 1.0
				var pa: Array = point_at(s, side * (wall_limit() + 0.9))
				var p: Vector3 = pa[0]
				var y := pts[int(pa[2])].y
				posts.append(Transform3D(Basis(), Vector3(p.x, y + 1.3, p.z)))
				bulbs.append(Transform3D(Basis(), Vector3(p.x, y + 2.75, p.z)))
				bc.append(glowc[k % glowc.size()])
				s += 14.0
				k += 1
			_mm(main.cyl_mesh(0.06, 0.08, 2.6, 6), main.make_material(Color(0.2, 0.2, 0.25), 0.0), posts)
			var gm := StandardMaterial3D.new()
			gm.vertex_color_use_as_albedo = true
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_mm(main.sphere_mesh(0.22), gm, bulbs, bc)
			var stems: Array[Transform3D] = []
			var caps: Array[Transform3D] = []
			var cc: Array[Color] = []
			for p in _side_spots(rng, 30, 1.0, 12.0):
				var sc := rng.randf_range(0.6, 1.6)
				stems.append(Transform3D(Basis().scaled(Vector3.ONE * sc), p + Vector3(0, 0.5 * sc, 0)))
				caps.append(Transform3D(Basis().scaled(Vector3(1.0, 0.55, 1.0) * sc), p + Vector3(0, 1.0 * sc, 0)))
				cc.append(glowc[rng.randi() % glowc.size()])
			_mm(main.cyl_mesh(0.15, 0.2, 1.0, 6), main.make_material(Color(0.85, 0.85, 0.8), 0.2), stems)
			_mm(main.sphere_mesh(0.7), gm, caps, cc)
		"snow":
			var snowmen: Array[Transform3D] = []
			for p in _side_spots(rng, 14, 1.5, 12.0):
				snowmen.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.3)), p + Vector3(0, 0.1, 0)))
			var sm := StandardMaterial3D.new()
			sm.vertex_color_use_as_albedo = true
			sm.roughness = 0.8
			_mm(main.snowman_mesh(), sm, snowmen)
			snow = CPUParticles3D.new()
			snow.amount = 220
			snow.lifetime = 4.0
			snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			snow.emission_box_extents = Vector3(18.0, 1.0, 18.0)
			snow.direction = Vector3.DOWN
			snow.spread = 25.0
			snow.gravity = Vector3(0.3, -1.0, 0.0)
			snow.initial_velocity_min = 1.0
			snow.initial_velocity_max = 2.0
			snow.scale_amount_min = 0.6
			snow.scale_amount_max = 1.3
			snow.mesh = main.box_mesh(Vector3.ONE * 0.07)
			var flake := StandardMaterial3D.new()
			flake.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			flake.albedo_color = Color(1, 1, 1)
			snow.material_override = flake
			snow.local_coords = false
			built.add_child(snow)


func _vc(glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.5
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = Color(glow, glow, glow)
	return m


func _dino(p: Vector3, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	built.add_child(root)
	root.position = p
	var to_track: Array = locate(p, -1)
	var q: Vector3 = pts[int(to_track[0])]
	root.rotation.y = atan2(q.x - p.x, q.z - p.z)  # +Z (the head side) looks at the race
	var col := [Color(0.45, 0.75, 0.4), Color(0.55, 0.6, 0.95), Color(0.95, 0.6, 0.35)][rng.randi() % 3] as Color
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	main.add_ellipsoid(st, Vector3(0, 2.0, 0), Vector3(1.6, 1.3, 2.4), col)
	main.add_ellipsoid(st, Vector3(0, 1.9, -2.6), Vector3(0.5, 0.5, 1.6), col.darkened(0.1))  # tail
	for x in [-0.9, 0.9]:
		for z in [-1.2, 1.2]:
			main.add_ellipsoid(st, Vector3(float(x), 0.7, float(z)), Vector3(0.38, 0.9, 0.38), col.darkened(0.15))
	main.add_ellipsoid(st, Vector3(0, 1.6, 0.4), Vector3(1.3, 0.9, 1.6), col.lightened(0.35))  # belly
	var bm := MeshInstance3D.new()
	bm.mesh = st.commit()
	bm.material_override = _vc(0.0)
	root.add_child(bm)
	var neck := Node3D.new()
	neck.position = Vector3(0, 2.6, 1.8)
	root.add_child(neck)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 6:
		var f := float(i) / 5.0
		main.add_ellipsoid(st2, Vector3(0, f * 3.6, f * 1.2), Vector3(0.45, 0.6, 0.45) * (1.0 - f * 0.3), col)
	main.add_ellipsoid(st2, Vector3(0, 4.0, 1.7), Vector3(0.55, 0.45, 0.8), col)
	for x in [-0.3, 0.3]:
		main.add_ellipsoid(st2, Vector3(float(x), 4.15, 2.15), Vector3(0.1, 0.12, 0.1), Color(1, 1, 1))
		main.add_ellipsoid(st2, Vector3(float(x) * 1.15, 4.15, 2.22), Vector3(0.06, 0.07, 0.06), Color(0.05, 0.05, 0.05))
	main.add_ellipsoid(st2, Vector3(0, 3.85, 2.3), Vector3(0.3, 0.06, 0.12), Color(0.9, 0.4, 0.45))  # smile
	var nm := MeshInstance3D.new()
	nm.mesh = st2.commit()
	nm.material_override = bm.material_override
	neck.add_child(nm)
	neck.set_meta("phase", rng.randf() * TAU)
	dinos.append(neck)


# --- Per frame -----------------------------------------------------------------------

func update(delta: float, authority: bool) -> void:
	spin += delta
	if box_mat != null:
		var c := Color.from_hsv(fmod(spin * 0.15, 1.0), 0.65, 1.0)
		box_mat.albedo_color = Color(c.r, c.g, c.b, 0.75)
		box_mat.emission = c
	for i in box_nodes.size():
		var b := box_nodes[i]
		if authority and box_t[i] > 0.0:
			box_t[i] = maxf(0.0, box_t[i] - delta)
		var avail := box_t[i] <= 0.0 and boxes_on
		b.visible = avail
		if avail:
			b.rotation.y = spin * 1.5 + i
			b.position = boxes[i] + Vector3(0, sin(spin * 2.0 + i) * 0.12, 0)
	if pad_mat != null:
		var k := 0.8 + 0.2 * sin(spin * 8.0)
		pad_mat.albedo_color = Color(k, k, k)
	cheer = lerpf(cheer, cheer_want, 1.0 - exp(-2.0 * delta))
	cheer_want = move_toward(cheer_want, 0.3, delta * 0.25)
	if crowd_mat != null:
		crowd_mat.set_shader_parameter("cheer", cheer)
	for d in dinos:
		var ph: float = d.get_meta("phase", 0.0)
		d.rotation.x = sin(spin * 0.8 + ph) * 0.12
		d.rotation.y = sin(spin * 0.5 + ph * 2.0) * 0.25


## The crowd goes wild (GO, finishes, big moments).
func excite(amount: float = 1.0) -> void:
	cheer_want = maxf(cheer_want, amount)


## Falling snow stays around whoever this machine is watching.
func follow_weather(p: Vector3) -> void:
	if snow != null and is_instance_valid(snow):
		snow.global_position = p + Vector3(0, 9.0, 0)


func box_state() -> Array:
	var out: Array = []
	for t in box_t:
		out.append(t > 0.0)
	return out


func apply_box_state(a: Array) -> void:
	for i in mini(a.size(), box_t.size()):
		var taken: bool = a[i]
		box_t[i] = 1.0 if taken else 0.0
