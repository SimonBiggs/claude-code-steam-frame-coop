extends Node3D
## ROCKET ROW: Sprocket's space museum behind the launch pad. Every rocket that reaches its planet comes
## home as a little model on a plinth (the plinth is the colour of the planet it visited; TODAY'S ROCKET
## gets a gold star over it). Saved by the host (main.gd museum list) and sent to the TV as compact
## arrays (event "museum"), so it grows and stays over days on every machine. Each model is ONE
## vertex-coloured mesh (main.merged_mesh, cached per look); plinths and stars are MultiMeshes.
## look_parts() also builds the changing parts of the big rocket on the pad (rocket.gd).

const G := preload("res://games/rocket_workshop/rocketgen.gd")
const P := preload("res://games/rocket_workshop/puzzles.gd")

var main
var entries: Array = []  # [[look (6)..., planet], ...] oldest first
var models: Array = []  # MeshInstance3D per shown slot
var plinths: MultiMesh
var stars: MultiMesh
var shown_key := ""
var pop_i := -1  # the newest model bounces in
var pop_t := 1.0
var t := 0.0


func _ready() -> void:
	plinths = MultiMesh.new()
	plinths.transform_format = MultiMesh.TRANSFORM_3D
	plinths.use_colors = true
	plinths.mesh = main.cyl_mesh(0.42, 0.5, 1.0, 12)
	plinths.instance_count = G.museum_size()
	plinths.visible_instance_count = 0
	var pmi := MultiMeshInstance3D.new()
	pmi.multimesh = plinths
	var pm := StandardMaterial3D.new()
	pm.vertex_color_use_as_albedo = true
	pm.roughness = 0.6
	pmi.material_override = pm
	add_child(pmi)
	stars = MultiMesh.new()
	stars.transform_format = MultiMesh.TRANSFORM_3D
	stars.mesh = main.star_mesh()
	stars.instance_count = G.museum_size()
	stars.visible_instance_count = 0
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = stars
	smi.material_override = main.make_material(Color(1.0, 0.82, 0.2), 1.6)
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smi)
	# Three long steps the rows stand on (one mesh each, so the back rows don't float).
	var step_mat: StandardMaterial3D = main.make_material(Color(0.82, 0.78, 0.72), 0.0)
	for row in G.ROW_Z.size():
		if G.ROW_RISE[row] <= 0.0:
			continue
		var st := MeshInstance3D.new()
		st.mesh = main.box_mesh(Vector3(G.ROW_HALF * 2.0 + 1.6, G.ROW_RISE[row], 1.6))
		st.material_override = step_mat
		st.position = Vector3(0, G.ROW_RISE[row] * 0.5, G.ROW_Z[row])
		add_child(st)


## Replace the whole row (host: from the save; TV: from the host's event).
func set_entries(list: Array) -> void:
	var key := var_to_str(list)
	if key == shown_key:
		return
	var grew := shown_key != "" and list.size() == entries.size() + 1  # (not on the first load)
	shown_key = key
	entries = list.duplicate(true)
	_rebuild()
	if grew:
		pop_i = mini(entries.size(), G.museum_size()) - 1
		pop_t = 0.0
		var at := G.museum_slot(pop_i)
		if at != Vector3.INF:
			main.star_burst(at + Vector3(0, 2.0, 0), 16)


func _shown() -> Array:
	var n := G.museum_size()
	return entries.slice(maxi(0, entries.size() - n))


func _rebuild() -> void:
	var shown := _shown()
	for i in shown.size():
		var e: Array = shown[i]
		var look: Array = e.slice(0, 6)
		var planet := int(e[6]) if e.size() > 6 else 0
		var at := G.museum_slot(i)
		if i >= models.size():
			var mi := MeshInstance3D.new()
			mi.material_override = main.vertex_mat()
			add_child(mi)
			models.append(mi)
		var model: MeshInstance3D = models[i]
		model.mesh = main.merged_mesh("look:" + var_to_str(look), look_parts(main, look, true))
		model.position = at + Vector3(0, 0.3, 0)
		model.scale = Vector3.ONE * G.MODEL_SCALE
		model.rotation.y = 0.0
		model.visible = true
		var pc: Color = P.PLANET_COLORS[clampi(planet, 0, P.PLANET_COLORS.size() - 1)]
		plinths.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1, 0.3, 1)), at + Vector3(0, 0.15, 0)))
		plinths.set_instance_color(i, pc)
	for i in range(shown.size(), models.size()):
		(models[i] as MeshInstance3D).visible = false
	plinths.visible_instance_count = shown.size()
	var s := 0
	for i in shown.size():
		var e: Array = shown[i]
		if int(e[G.L_GOLD]) == 1:
			stars.set_instance_transform(s, Transform3D(Basis.from_scale(Vector3.ONE * 0.22), G.museum_slot(i) + Vector3(0, 2.15, 0)))
			s += 1
	stars.visible_instance_count = s


func update_museum(delta: float) -> void:
	t += delta
	if pop_i >= 0 and pop_i < models.size() and pop_t < 1.0:
		pop_t = minf(1.0, pop_t + delta * 1.2)
		var m: MeshInstance3D = models[pop_i]
		var s := clampf(pop_t * 2.5, 0.0, 1.0) * (1.0 + sin(pop_t * PI * 2.0) * (1.0 - pop_t) * 0.5)
		m.scale = Vector3.ONE * G.MODEL_SCALE * maxf(s, 0.001)
		m.rotation.y = (1.0 - pop_t) * TAU * 2.0
	# The gold stars spin gently.
	for i in stars.visible_instance_count:
		var xf := stars.get_instance_transform(i)
		stars.set_instance_transform(i, Transform3D(Basis(Vector3.UP, t * 1.5 + i) * Basis.from_scale(Vector3.ONE * 0.22), xf.origin))


## The parts of a rocket with this look as [[Mesh, Transform3D, Color], ...] in rocket units (the big
## rocket on the pad: body radius 0.62 from y 0.5 to 3.5). with_body: also the body, base band, engine
## and window (the museum models); without: just the parts that change (fins, nose, extras).
static func look_parts(main, look: Array, with_body: bool) -> Array:
	var body: Color = G.BODY_COLORS[clampi(int(look[G.L_BODY]), 0, G.BODY_COLORS.size() - 1)]
	var trim: Color = G.TRIM_COLORS[clampi(int(look[G.L_TRIM]), 0, G.TRIM_COLORS.size() - 1)]
	var out: Array = []
	if with_body:
		out.append([main.cyl_mesh(0.62, 0.62, 3.0, 14), Transform3D(Basis(), Vector3(0, 2.0, 0)), body])
		out.append([main.cyl_mesh(0.64, 0.64, 0.3, 14), Transform3D(Basis(), Vector3(0, 1.2, 0)), trim])
		out.append([main.cyl_mesh(0.35, 0.5, 0.45, 10), Transform3D(Basis(), Vector3(0, 0.3, 0)), Color(0.35, 0.35, 0.4)])
		out.append([main.cyl_mesh(0.3, 0.3, 0.06, 12), Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 2.7, 0.6)), Color(0.5, 0.85, 1.0)])
	match int(look[G.L_NOSE]):
		1:  # bubble
			out.append([main.sphere_mesh(0.62), Transform3D(Basis(), Vector3(0, 3.5, 0)), trim])
		2:  # needle
			out.append([main.cyl_mesh(0.0, 0.62, 2.2, 14), Transform3D(Basis(), Vector3(0, 4.6, 0)), trim])
		_:  # cone
			out.append([main.cyl_mesh(0.0, 0.62, 1.4, 14), Transform3D(Basis(), Vector3(0, 4.2, 0)), trim])
	var fins := int(look[G.L_FINS])
	var count := 4 if fins == 3 else 3
	for i in count:
		var a := TAU * i / count + PI / 3.0
		var face := Basis(Vector3.UP, a)
		var dir := Vector3(sin(a), 0, cos(a))
		match fins:
			1:  # swept: long, leaning back
				out.append([main.box_mesh(Vector3(0.08, 1.4, 0.6)), Transform3D(face * Basis(Vector3.RIGHT, 0.45), dir * 0.85 + Vector3(0, 0.75, 0)), trim])
			2:  # round: a big half disc
				out.append([main.cyl_mesh(0.62, 0.62, 0.08, 14), Transform3D(face * Basis(Vector3.FORWARD, PI / 2.0), dir * 0.62 + Vector3(0, 0.85, 0)), trim])
			3:  # four small fins
				out.append([main.box_mesh(Vector3(0.1, 0.9, 0.6)), Transform3D(face, dir * 0.75 + Vector3(0, 0.65, 0)), trim])
			_:
				out.append([main.box_mesh(Vector3(0.1, 1.1, 0.75)), Transform3D(face, dir * 0.75 + Vector3(0, 0.75, 0)), trim])
	match int(look[G.L_EXTRA]):
		1:  # stripes
			for y in [1.85, 3.2]:
				out.append([main.cyl_mesh(0.635, 0.635, 0.14, 14), Transform3D(Basis(), Vector3(0, y, 0)), trim])
		2:  # side boosters
			for sx in [-1.0, 1.0]:
				out.append([main.cyl_mesh(0.24, 0.24, 1.7, 10), Transform3D(Basis(), Vector3(sx * 0.86, 1.25, 0)), body])
				out.append([main.cyl_mesh(0.0, 0.24, 0.45, 10), Transform3D(Basis(), Vector3(sx * 0.86, 2.32, 0)), trim])
		3:  # a space ring round the middle
			out.append([_ring_mesh(main), Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0, 2.3, 0)), trim])
	if int(look[G.L_GOLD]) == 1:  # TODAY'S ROCKET: a gold band under the window too
		out.append([main.cyl_mesh(0.635, 0.635, 0.1, 14), Transform3D(Basis(), Vector3(0, 2.2, 0)), G.TRIM_COLORS[G.GOLD]])
	return out


static func _ring_mesh(main) -> Mesh:
	if not main.meshes.has("look_ring"):
		var tm := TorusMesh.new()
		tm.inner_radius = 0.95
		tm.outer_radius = 1.15
		tm.rings = 20
		tm.ring_segments = 5
		main.meshes["look_ring"] = tm
	return main.meshes["look_ring"]


## Where the blinking nose light sits for this look (rocket units).
static func nose_tip(look: Array) -> float:
	match int(look[G.L_NOSE]):
		1:
			return 4.12
		2:
			return 5.72
	return 4.92
