extends Node3D
## A visiting flock (seasons.gd FLOCKS): flies in over `tell` seconds while the warn ring shows, lands in the
## ring with a splash, paddles about for Seasons.SIT_SECS, then flies off and frees itself. Looks only: every
## machine makes its own from the host's "flock" event; the host does the splash's effects (main.gd).

const FishScript := preload("res://games/fishing_lake/fish.gd")
const Seasons := preload("res://games/fishing_lake/seasons.gd")

var center := Vector3.ZERO
var radius := 2.6
var tell := 3.0
var t := 0.0
var birds: Array[Node3D] = []
var wings: Array = []  # per bird [left, right]
var starts: Array[Vector3] = []
var seats: Array[Vector3] = []
var leaves: Array[Vector3] = []


func setup(pos: Vector3, r: float, season: String, tell_secs: float) -> void:
	center = Vector3(pos.x, 0.0, pos.z)
	radius = r
	tell = maxf(tell_secs, 0.5)
	var f := Seasons.flock(season)
	var n := int(f.n)
	var come := Vector3(sin(float(hash(str(pos))) * 0.001), 0.0, cos(float(hash(str(pos))) * 0.001)).normalized()
	for i in n:
		var b := _bird(f, i == 0)
		add_child(b)
		birds.append(b)
		var a := TAU * float(i) / float(n) + 0.4
		var seat := center + Vector3(cos(a), 0.0, sin(a)) * radius * (0.35 + 0.25 * float(i % 2))
		seats.append(seat)
		starts.append(seat + come * 26.0 + Vector3(float(i) * 0.8, 10.0 + float(i) * 0.5, 0.0))
		leaves.append(seat - come * 30.0 + Vector3(0.0, 14.0, float(i)))
		b.position = starts[i]


func _bird(f: Dictionary, lead: bool) -> Node3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body: Color = f.body
	FishScript._ellipsoid(st, Vector3(0, 0.12, 0), Vector3(0.16, 0.12, 0.26), -1, 10, 5, body)
	FishScript._ellipsoid(st, Vector3(0, 0.22, 0.2), Vector3(0.04, 0.1, 0.04), -1, 6, 3, body)  # neck
	FishScript._ellipsoid(st, Vector3(0, 0.34, 0.24), Vector3(0.08, 0.075, 0.09), -1, 8, 4, f.head)
	FishScript._ellipsoid(st, Vector3(0, 0.32, 0.34), Vector3(0.03, 0.02, 0.06), -1, 6, 3, f.beak)
	for s in [-1.0, 1.0]:
		FishScript._ellipsoid(st, Vector3(float(s) * 0.055, 0.36, 0.3), Vector3(0.013, 0.015, 0.013), -1, 5, 3, Color(0.05, 0.05, 0.05))
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var root := Node3D.new()
	root.add_child(m)
	var pair: Array = []
	for s in [-1.0, 1.0]:
		var wt := SurfaceTool.new()
		wt.begin(Mesh.PRIMITIVE_TRIANGLES)
		FishScript._ellipsoid(wt, Vector3(float(s) * 0.2, 0.0, 0.0), Vector3(0.2, 0.025, 0.12), -1, 8, 3, body.darkened(0.1))
		var w := MeshInstance3D.new()
		w.mesh = wt.commit()
		w.material_override = mat
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.position = Vector3(float(s) * 0.1, 0.18, 0.0)
		root.add_child(w)
		pair.append(w)
	wings.append(pair)
	root.scale = Vector3.ONE * float(f.size) * (1.15 if lead else 1.0)
	return root


func landed() -> bool:
	return t >= tell


func _process(delta: float) -> void:
	t += delta
	var sit_end := tell + Seasons.SIT_SECS
	for i in birds.size():
		var b := birds[i]
		var prev := b.position
		var flap := 0.0
		if t < tell:  # gliding in (a little late each, landing as the ring goes off)
			var u := clampf(t / tell, 0.0, 1.0)
			var e := 1.0 - pow(1.0 - u, 2.0)
			b.position = starts[i].lerp(seats[i], e) + Vector3(0, sin(u * PI) * 1.5, 0)
			flap = sin(t * 14.0 + i) * 0.9
		elif t < sit_end:  # paddling round inside the ring
			var a := (t - tell) * 0.35 + TAU * float(i) / float(birds.size())
			var rr := radius * (0.4 + 0.2 * float(i % 2))
			b.position = center + Vector3(cos(a) * rr, sin(t * 2.0 + i) * 0.015, sin(a) * rr)
			flap = 0.15 * sin(t * 3.0 + i) if t - tell < 0.6 else 0.0
		else:  # flying off
			var u := clampf((t - sit_end) / 3.0, 0.0, 1.0)
			var from := center + Vector3(cos(TAU * float(i) / float(birds.size())), 0.0, sin(TAU * float(i) / float(birds.size()))) * radius * 0.5
			b.position = from.lerp(leaves[i], u * u)
			flap = sin(t * 16.0 + i) * 1.0
		var mv := b.position - prev
		mv.y = 0.0
		if mv.length() > 0.0005:
			b.rotation.y = lerp_angle(b.rotation.y, atan2(mv.x, mv.z), 1.0 - exp(-6.0 * delta))
		var pair: Array = wings[i]
		(pair[0] as Node3D).rotation.z = flap
		(pair[1] as Node3D).rotation.z = -flap
	if t > sit_end + 3.2:
		queue_free()
