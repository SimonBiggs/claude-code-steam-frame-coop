extends Node3D
## MINI GOLF PARTY warned surprises (deep.gd hazards()): every machine draws the surprise showing now from main.hz_now
## (the host's snapshot on the TV and the Decks), steady from the start of the tell until it is over:
##   GUST  a pale blue band across the fairway (core/warn_rings.gd) with three chevron arrows the way it will blow;
##         when it blows, wind streaks slide across the band too (a rolling ball in it is blown along).
##   MOLE  an orange-brown circle beside the aim line with a little heap of earth growing in it; then a mole pops up
##         there (the ball bounces off him) and ducks back down when his time is up.
## Nothing flashes: the band and the circle glow steadily; the arrows and streaks just slide along. Each kind has its
## own colour (deep.gd GUST_COLOR / MOLE_COLOR), never a player's ball colour on the green.
##   show_now(hz, key) every frame (cheap: rebuilds only when the surprise or its phase changes); tells_now() for bots.

const WarnRings := preload("res://core/warn_rings.gd")
const UiKit := preload("res://core/ui_kit.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Deep := preload("res://games/mini_golf_party/deep.gd")

const STREAKS := 6
const STAY := 600.0  # (the tell stays until the surprise is over: clear() takes it away)
const FUR := Color(0.36, 0.26, 0.22)

var main
var rings: WarnRings
var key := ""
var now := {}
var arrows: Array[MeshInstance3D] = []
var streaks: Array[MeshInstance3D] = []
var heap: Node3D
var mole: Node3D
var t := 0.0
var shown_t := 0.0  # seconds this tell has shown (bots: told long enough before it happens)
var seen := {}  # kind -> tells drawn (bots)
var on_seen := {}  # kind -> times it happened (bots)
var early := 0  # (bots) a surprise that went ON before its tell had shown


func _ready() -> void:
	name = "Hazards"
	rings = WarnRings.new()
	add_child(rings)


## Every machine: the surprise showing now ({} none: deep.gd unpack()) and a key that changes every surprise.
func show_now(hz: Dictionary, ev_key: String) -> void:
	var k := "%s|%s|%s" % [ev_key, String(hz.get("kind", "")), String(hz.get("phase", ""))]
	if k == key:
		return
	var same_event := key.begins_with(ev_key + "|" + String(hz.get("kind", "")) + "|") and not hz.is_empty()
	key = k
	if hz.is_empty():
		clear()
		return
	var kind := String(hz.kind)
	if not same_event:  # a new surprise: its tell
		clear()
		shown_t = 0.0
		seen[kind] = int(seen.get(kind, 0)) + 1
		if String(hz.phase) == "on":
			early += 1  # (never: the host always tells first; bots check)
		_tell(hz)
	now = hz
	if String(hz.phase) == "on":
		on_seen[kind] = int(on_seen.get(kind, 0)) + 1
		if kind == "gust":
			_streaks()
			main.sfx.play("wind", -8.0, 1.2)
		else:
			_pop_mole(hz)


func _tell(hz: Dictionary) -> void:
	var p: Vector2 = hz.p
	var dir: Vector2 = hz.dir
	var y := 0.012
	if String(hz.kind) == "gust":
		var from := Vector3(p.x, 0.0, p.y) - Vector3(dir.x, 0.0, dir.y) * float(hz.len) * 0.5
		rings.shape("line", from, Vector3(dir.x, 0.0, dir.y), Vector2(float(hz.len), float(hz.depth)), Deep.GUST_COLOR, 0.3,
			{"style": "disc", "stay": STAY, "alpha": 0.4, "y": y})
		var am := _mat(Deep.GUST_COLOR.lightened(0.35), 0.95)
		var along := Vector2(-dir.y, dir.x)
		for i in 3:
			var a := MeshInstance3D.new()
			a.mesh = _arrow_mesh()
			a.material_override = am
			a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var q := p + dir * (i - 1) * float(hz.len) * 0.28 + along * (i - 1) * 0.12
			a.position = Vector3(q.x, 0.02, q.y)
			a.rotation.y = atan2(-dir.y, dir.x)  # the mesh points +x: turn it to blow along dir
			add_child(a)
			arrows.append(a)
		main.sfx.play("whoosh", -12.0, 0.6)
	else:
		rings.shape("circle", Vector3(p.x, 0.0, p.y), Vector3.FORWARD, Vector2(float(hz.r) + 0.08, 0.0), Deep.MOLE_COLOR, 0.3,
			{"style": "disc", "stay": STAY, "alpha": 0.55, "y": y})
		heap = Node3D.new()
		heap.name = "MoleHeap"
		var b := MeshKit.Builder.new()
		b.dome(float(hz.r) * 0.9, MeshKit.at(Vector3.ZERO, Vector3(1.0, 0.5, 1.0)), Color(0.5, 0.33, 0.2), 10)
		for k in 4:
			var a2 := TAU * k / 4.0 + 0.4
			b.sphere(0.022, MeshKit.at(Vector3(cos(a2) * 0.1, 0.01, sin(a2) * 0.1)), Color(0.42, 0.28, 0.17), 5)
		heap.add_child(MeshKit.instance(b.build(), false))
		heap.position = Vector3(p.x, 0.0, p.y)
		heap.scale = Vector3.ONE * 0.3
		add_child(heap)
		main.sfx.play("pop", -12.0, 0.7)


## The mole pops up out of his heap (a bumper while he's up: course.gd moles on the host).
func _pop_mole(hz: Dictionary) -> void:
	if mole != null and is_instance_valid(mole):
		return
	var p: Vector2 = hz.p
	var r := float(hz.r)
	mole = Node3D.new()
	mole.name = "Mole"
	var b := MeshKit.Builder.new()
	b.cylinder(r * 0.95, r, 0.16, MeshKit.at(Vector3(0, 0.08, 0)), FUR, 12)  # body
	b.sphere(r * 0.95, MeshKit.at(Vector3(0, 0.16, 0), Vector3(1.0, 0.8, 1.0)), FUR, 12)  # head
	b.sphere(0.03, MeshKit.at(Vector3(0, 0.17, -r * 0.9)), Color(1.0, 0.55, 0.65), 8)  # pink nose
	b.sphere(0.014, MeshKit.at(Vector3(0.035, 0.21, -r * 0.8)), Color(0.05, 0.05, 0.05), 6)  # eyes
	b.sphere(0.014, MeshKit.at(Vector3(-0.035, 0.21, -r * 0.8)), Color(0.05, 0.05, 0.05), 6)
	for sx in [-1.0, 1.0]:  # big pink digging paws on the edge of his hole
		b.ellipsoid(Vector3(0.04, 0.012, 0.03), MeshKit.at(Vector3(sx * r * 0.8, 0.09, -r * 0.6)), Color(1.0, 0.7, 0.75), 6)
	mole.add_child(MeshKit.instance(b.build(), false))
	mole.position = Vector3(p.x, -0.2, p.y)
	add_child(mole)
	var to: Vector2 = main.course.tee - p  # his face (-z) towards the tee (where everyone looks from)
	mole.rotation.y = atan2(-to.x, -to.y)
	var tw := create_tween()
	tw.tween_property(mole, "position:y", 0.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	main.sfx.play("boing", -6.0, 1.3)


func clear() -> void:
	rings.clear()
	for n in arrows + streaks:
		if is_instance_valid(n):
			n.queue_free()
	arrows.clear()
	streaks.clear()
	for n in [heap, mole]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	heap = null
	mole = null
	now = {}


## Bots: the surprise showing now: [{kind, phase, p, ...}] and how long its tell has shown.
func tells_now() -> Array:
	return [] if now.is_empty() else [now.duplicate()]


func _streaks() -> void:
	if not streaks.is_empty():
		return
	var sm := _mat(Color(0.92, 0.98, 1.0), 0.6)
	for i in STREAKS:
		var s := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.4, 0.012, 0.012)
		s.mesh = bm
		s.material_override = sm
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
		streaks.append(s)


func _process(delta: float) -> void:
	t += delta
	if now.is_empty():
		return
	shown_t += delta
	var p: Vector2 = now.p
	var dir: Vector2 = now.dir
	if String(now.kind) == "gust":
		var along := Vector2(-dir.y, dir.x)
		for i in arrows.size():  # the arrows slide a little the way it blows and back (steady colour, never flashing)
			var q := p + dir * ((i - 1) * float(now.len) * 0.28 + 0.06 * sin(t * 2.0 + i)) + along * (i - 1) * 0.12
			arrows[i].position = Vector3(q.x, 0.02, q.y)
		for i in streaks.size():  # wind streaks across the band, low over the green
			var f := fmod(t * 0.8 + float(i) / STREAKS, 1.0)
			var q2 := p + dir * lerpf(-0.5, 0.5, f) * float(now.len) + along * (fmod(float(i) * 0.61, 1.0) - 0.5) * float(now.depth)
			streaks[i].position = Vector3(q2.x, 0.06 + 0.12 * fmod(float(i) * 0.37, 1.0), q2.y)
			streaks[i].rotation.y = atan2(-dir.y, dir.x)
			streaks[i].scale = Vector3.ONE * maxf(0.05, sin(f * PI))
	elif heap != null and is_instance_valid(heap):
		heap.scale = heap.scale.lerp(Vector3.ONE, 1.0 - exp(-2.0 * delta))  # the heap grows while he digs up
		if mole == null:
			heap.rotation.y = sin(t * 9.0) * 0.08  # (a little wiggle: he's coming)


func _mat(col: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha < 1.0:
		UiKit.see_through(m)
	return m


## A flat chevron arrow on the grass pointing +x (0.36 m long).
static func _arrow_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(-0.18, 0, -0.05), Vector3(0.05, 0, -0.05), Vector3(0.05, 0, 0.05), Vector3(-0.18, 0, 0.05),
		Vector3(0.05, 0, -0.12), Vector3(0.18, 0, 0.0), Vector3(0.05, 0, 0.12)]
	for tri in [[0, 1, 2], [0, 2, 3], [4, 5, 6]]:
		for j in [0, 2, 1]:
			st.set_normal(Vector3.UP)
			st.add_vertex(pts[tri[j]])
	return st.commit()
