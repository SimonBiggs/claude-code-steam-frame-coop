extends Node3D
## A looping race track built from a few control points (Catmull-Rom spline, x/z plus height).
## Karts don't use the physics engine: they ask `locate()` where they are along the track
## (distance s, sideways offset lat, road height), the walls are just a limit on lat, and ramps,
## boost pads and item boxes live in (s, lat) space. Everything is generated in code.

const WIDTH := 11.0  # road width
const CURB := 0.8  # coloured curb outside the road, then the wall
const WALL_H := 0.8
const STEP := 2.0  # spline sample spacing (m)
const BOX_RESPAWN := 4.0

## name, colours, control points [x, z, height], ramps [fraction, length, height, lat, half width],
## boost pads [fraction, lat], item box rows [fraction]
const TRACKS := [
	{"name": "SUNNY MEADOW", "sky": Color(0.55, 0.8, 1.0), "grass": Color(0.42, 0.78, 0.35),
		"road": Color(0.36, 0.36, 0.42), "wall_a": Color(1.0, 0.35, 0.3), "wall_b": Color(1.0, 1.0, 1.0),
		"earth": Color(0.6, 0.45, 0.3), "trees": [Color(0.25, 0.65, 0.3), Color(0.4, 0.8, 0.3), Color(1.0, 0.6, 0.75)],
		"pts": [[0, 0, 0], [40, 0, 0], [75, -8, 0.5], [92, -35, 1.5], [85, -65, 2.5], [60, -80, 3], [30, -75, 2.5],
			[10, -58, 1.5], [-15, -50, 1], [-40, -62, 1.5], [-62, -55, 1], [-70, -30, 0.5], [-55, -8, 0], [-28, 2, 0]],
		"ramps": [[0.42, 8.0, 1.1, 0.0, 3.0]],
		"pads": [[0.1, 0.0], [0.6, -2.6], [0.83, 2.6]],
		"items": [0.2, 0.5, 0.74]},
	{"name": "CANDY HILLS", "sky": Color(1.0, 0.78, 0.88), "grass": Color(0.62, 0.9, 0.65),
		"road": Color(0.45, 0.38, 0.5), "wall_a": Color(1.0, 0.45, 0.75), "wall_b": Color(0.55, 0.9, 1.0),
		"earth": Color(0.85, 0.6, 0.7), "trees": [Color(1.0, 0.5, 0.7), Color(0.6, 0.5, 1.0), Color(1.0, 0.9, 0.4)],
		"pts": [[0, 0, 0], [45, 5, 1], [80, -5, 3], [95, -35, 5], [80, -60, 4], [50, -55, 2], [30, -35, 1],
			[5, -40, 2], [-20, -65, 4], [-50, -70, 5], [-75, -50, 3], [-80, -20, 1], [-55, 0, 0], [-25, 0, 0]],
		"ramps": [[0.07, 7.0, 1.0, -2.5, 2.5], [0.62, 8.0, 1.2, 0.0, 3.0]],
		"pads": [[0.3, 0.0], [0.5, 2.6], [0.88, -2.6]],
		"items": [0.16, 0.45, 0.76]},
	{"name": "MOONLIGHT BAY", "sky": Color(0.16, 0.18, 0.4), "grass": Color(0.2, 0.45, 0.5),
		"road": Color(0.25, 0.25, 0.35), "wall_a": Color(0.3, 0.9, 1.0), "wall_b": Color(1.0, 0.85, 0.3),
		"earth": Color(0.3, 0.3, 0.45), "trees": [Color(0.3, 0.9, 0.8), Color(0.8, 0.5, 1.0), Color(0.4, 0.7, 1.0)],
		"pts": [[0, 0, 0], [50, 0, 0], [85, 15, 1], [110, 0, 2], [110, -35, 2], [85, -50, 1], [55, -40, 0],
			[30, -55, 1], [5, -75, 2], [-30, -70, 2], [-55, -45, 1], [-50, -15, 0], [-25, -3, 0]],
		"ramps": [[0.27, 8.0, 1.1, 0.0, 3.0], [0.7, 7.0, 1.0, 2.5, 2.5]],
		"pads": [[0.13, 0.0], [0.45, -2.6], [0.9, 0.0]],
		"items": [0.2, 0.55, 0.8]},
]

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
var box_mat: StandardMaterial3D
var pad_mat: StandardMaterial3D
var built: Node3D
var spin := 0.0


static func count() -> int:
	return TRACKS.size()


static func track_name(i: int) -> String:
	var d: Dictionary = TRACKS[posmod(i, TRACKS.size())]
	return str(d["name"])


func wall_limit() -> float:
	return WIDTH * 0.5 + CURB


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
	_sample()
	_features()
	_build_road()
	_build_pads()
	_build_boxes()
	_build_gantry()
	_build_scenery()
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
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color(1, 1, 1)
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var bm := BoxMesh.new()
	bm.size = Vector3(1.1, 1.1, 1.1)
	var cm := BoxMesh.new()
	cm.size = Vector3(0.45, 0.45, 0.45)
	for b in boxes:
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = box_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		built.add_child(mi)
		mi.position = b
		mi.rotation = Vector3(0.6, 0.0, 0.6)
		var core := MeshInstance3D.new()
		core.mesh = cm
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


func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234 + track_i * 77
	var cols: Array = info["trees"]
	var spots: Array[Vector3] = []
	var tries := 0
	while spots.size() < 70 and tries < 800:
		tries += 1
		var p := Vector3(rng.randf_range(-140, 170), 0, rng.randf_range(-160, 70))
		var r: Array = locate(p, -1)
		var lat: float = r[2]
		var q: Vector3 = pts[int(r[0])]
		var d := Vector2(p.x - q.x, p.z - q.z).length()
		if absf(lat) < wall_limit() + 4.0 or d < wall_limit() + 4.0:
			continue
		spots.append(p)
	var trunk := MultiMesh.new()
	trunk.transform_format = MultiMesh.TRANSFORM_3D
	var tm := CylinderMesh.new()
	tm.top_radius = 0.25
	tm.bottom_radius = 0.35
	tm.height = 2.4
	tm.radial_segments = 6
	trunk.mesh = tm
	trunk.instance_count = spots.size()
	var crown := MultiMesh.new()
	crown.transform_format = MultiMesh.TRANSFORM_3D
	crown.use_colors = true
	var sm := SphereMesh.new()
	sm.radius = 1.6
	sm.height = 3.2
	sm.radial_segments = 10
	sm.rings = 6
	crown.mesh = sm
	crown.instance_count = spots.size()
	for i in spots.size():
		var sc := rng.randf_range(0.8, 1.5)
		var p := spots[i]
		trunk.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * sc), p + Vector3(0, 1.2 * sc, 0)))
		crown.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(sc, sc * 1.15, sc)), p + Vector3(0, 3.2 * sc, 0)))
		var c: Color = cols[rng.randi() % cols.size()]
		crown.set_instance_color(i, c)
	var tmi := MultiMeshInstance3D.new()
	tmi.multimesh = trunk
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.5, 0.35, 0.22)
	tmi.material_override = tmat
	tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	built.add_child(tmi)
	var cmi := MultiMeshInstance3D.new()
	cmi.multimesh = crown
	var cmat := StandardMaterial3D.new()
	cmat.vertex_color_use_as_albedo = true
	cmat.roughness = 0.8
	cmi.material_override = cmat
	cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	built.add_child(cmi)
	# Far-off hills all around.
	var hills := MultiMesh.new()
	hills.transform_format = MultiMesh.TRANSFORM_3D
	hills.use_colors = true
	var hm := SphereMesh.new()
	hm.radius = 1.0
	hm.height = 2.0
	hm.radial_segments = 12
	hm.rings = 6
	hills.mesh = hm
	hills.instance_count = 12
	var grass: Color = info["grass"]
	for i in 12:
		var a := TAU * i / 12.0 + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(230, 290)
		var sz := rng.randf_range(40, 80)
		hills.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(sz, sz * rng.randf_range(0.35, 0.6), sz)),
			Vector3(20 + cos(a) * r, -5, -35 + sin(a) * r)))
		hills.set_instance_color(i, grass.darkened(rng.randf_range(0.05, 0.3)))
	var hmi := MultiMeshInstance3D.new()
	hmi.multimesh = hills
	hmi.material_override = cmat
	hmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	built.add_child(hmi)


# --- Per frame -----------------------------------------------------------------------

func update(delta: float, authority: bool) -> void:
	spin += delta
	if box_mat != null:
		var c := Color.from_hsv(fmod(spin * 0.15, 1.0), 0.65, 1.0)
		box_mat.albedo_color = c
		box_mat.emission = c
	for i in box_nodes.size():
		var b := box_nodes[i]
		if authority and box_t[i] > 0.0:
			box_t[i] = maxf(0.0, box_t[i] - delta)
		var avail := box_t[i] <= 0.0
		b.visible = avail
		if avail:
			b.rotation.y = spin * 1.5 + i
			b.position = boxes[i] + Vector3(0, sin(spin * 2.0 + i) * 0.12, 0)
	if pad_mat != null:
		var k := 0.8 + 0.2 * sin(spin * 8.0)
		pad_mat.albedo_color = Color(k, k, k)


func box_state() -> Array:
	var out: Array = []
	for t in box_t:
		out.append(t > 0.0)
	return out


func apply_box_state(a: Array) -> void:
	for i in mini(a.size(), box_t.size()):
		var taken: bool = a[i]
		box_t[i] = 1.0 if taken else 0.0
