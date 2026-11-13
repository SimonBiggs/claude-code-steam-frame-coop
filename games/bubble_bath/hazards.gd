extends Node3D
## BUBBLE BATH warned surprises (deep.gd hazards()): every machine draws the surprise in the "hz" state (the host
## sets it when its tell starts and clears it when it is over), steady from the tell until it is over:
##   WALLY   a purple circle on the water (core/warn_rings.gd) with Wally the squirty whale's tail peeking up in its
##           middle; when the tell is over he pops up, squirts a fountain and makes big waves: every boat in the circle
##           is pushed out (main.gd hz_go) and a train caught inside scatters (host).
##   SHOWER  an orange band across the tub with a shower head on the wall at its start; when the tell is over it
##           sprays along the band (droplets) and pushes boats and ducks along it (main.gd hz_spray, every frame).
## Nothing flashes: the circle and the band glow steadily in their own colours (deep.gd WHALE_COLOR / SPRAY_COLOR).
##   show_now(hz) on every "hz" change; tells_now() for bots; fired() once the surprise has gone off.

const WarnRings := preload("res://core/warn_rings.gd")
const UiKit := preload("res://core/ui_kit.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Deep := preload("res://games/bubble_bath/deep.gd")

const STAY := 600.0  # (the tell stays until the host clears it)

var main
var rings: WarnRings
var key := ""
var now := {}
var age := 0.0  # seconds since this surprise's tell began here
var went := false  # it went off here (main.hz_go ran)
var whale: Node3D
var head: Node3D
var spray: CPUParticles3D
var seen := {}  # kind -> tells drawn (bots)


func _ready() -> void:
	name = "Hazards"
	rings = WarnRings.new()
	add_child(rings)


## Every machine: the surprise showing now ({} none).
func show_now(hz: Dictionary) -> void:
	var k := str(Deep.pack(hz))
	if k == key:
		return
	key = k
	clear()
	now = hz
	age = 0.0
	went = false
	if hz.is_empty():
		return
	seen[String(hz.kind)] = int(seen.get(String(hz.kind), 0)) + 1
	var y: float = main.WATER_Y + 0.03
	var at := Vector3(float(hz.x), 0.0, float(hz.z))
	var col := color_of(String(hz.kind))
	match String(hz.kind):
		"whale":
			rings.shape("circle", at, Vector3.FORWARD, Vector2(float(hz.r), 0.0), col, 0.3,
				{"style": "disc", "stay": STAY, "alpha": 0.45, "y": y, "hot": col})
			whale = _whale_node()
			add_child(whale)
			whale.position = Vector3(at.x, main.WATER_Y - 0.55, at.z)  # just the tail peeks up while it is told
			main.sfx.play_at("honk", Vector3(at.x, main.WATER_Y, at.z), -6.0, 0.55)
		"spray":
			var dir := Vector3(float(hz.dx), 0.0, float(hz.dz)).normalized()
			rings.shape("line", at, dir, Vector2(Deep.spray_len(hz), float(hz.r) * 2.0), col, 0.3,
				{"style": "disc", "stay": STAY, "alpha": 0.4, "y": y, "hot": col})
			head = _shower_head(col)
			add_child(head)
			head.position = Vector3(at.x, main.RIM_Y + 0.55, at.z) - dir * 0.15
			UiKit.look(head, head.position + dir, Vector3.UP)
			main.sfx.play_at("whoosh", head.position, -6.0, 0.7)


func clear() -> void:
	rings.clear()
	for n in [whale, head, spray]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	whale = null
	head = null
	spray = null
	now = {}


## Bots: the surprise showing now: [{kind, x, z, ...}].
func tells_now() -> Array:
	return [] if now.is_empty() else [now.duplicate()]


func _process(delta: float) -> void:
	if now.is_empty():
		return
	age += delta
	var go := age - float(now.warn)
	if go >= 0.0 and not went:
		went = true
		main.hz_go(now)
		if String(now.kind) == "spray" and head != null:
			spray = _spray_fx(now)
			add_child(spray)
	if String(now.kind) == "spray" and went and go < Deep.SPRAY_SECS:
		main.hz_spray(now, delta)
	if whale != null and is_instance_valid(whale):
		var wy: float = main.WATER_Y - 0.55
		if go >= 0.0:
			var k := go / Deep.WHALE_SECS
			wy = main.WATER_Y - 0.5 + sin(minf(1.0, k) * PI) * 0.75  # up he pops, then back down
		else:
			whale.rotation.z = sin(age * 3.0) * 0.12  # the tail waggles while it is told
		whale.position.y = wy


## Wally: a friendly purple whale with a white tummy, facing +Z, his tail up behind.
func _whale_node() -> Node3D:
	var n := Node3D.new()
	n.name = "Wally"
	var b := MeshKit.Builder.new()
	var c := Deep.WHALE_COLOR
	var belly := Color(0.95, 0.92, 1.0)
	var k := Color(0.12, 0.1, 0.18)
	b.ellipsoid(Vector3(0.42, 0.36, 0.55), MeshKit.at(Vector3(0, 0.3, 0)), c, 14)
	b.ellipsoid(Vector3(0.34, 0.2, 0.42), MeshKit.at(Vector3(0, 0.12, 0.08)), belly, 12)
	for s in [-1.0, 1.0]:
		b.sphere(0.06, MeshKit.at(Vector3(0.24 * s, 0.42, 0.36)), Color.WHITE, 8)
		b.sphere(0.035, MeshKit.at(Vector3(0.26 * s, 0.43, 0.41)), k, 6)
		b.ellipsoid(Vector3(0.16, 0.04, 0.09), MeshKit.at(Vector3(0.42 * s, 0.18, 0.1), Vector3.ONE, Vector3(0, 0, 0.4 * s)), c, 8)
	b.tube(Vector3(0, 0.4, -0.45), Vector3(0, 0.8, -0.75), 0.12, 0.06, c, 8)
	for s in [-1.0, 1.0]:
		b.ellipsoid(Vector3(0.22, 0.04, 0.1), MeshKit.at(Vector3(0.15 * s, 0.84, -0.78), Vector3.ONE, Vector3(0, 0, 0.35 * s)), c, 8)
	n.add_child(MeshKit.instance(b.build(), false))
	n.scale = Vector3.ONE * 1.2
	return n


## The shower head on its arm over the rim (faces -Z of its own, aimed along the band by UiKit.look).
func _shower_head(col: Color) -> Node3D:
	var n := Node3D.new()
	n.name = "Shower"
	var b := MeshKit.Builder.new()
	var chrome := Color(0.8, 0.85, 0.92)
	b.cylinder(0.18, 0.12, 0.1, MeshKit.at(Vector3(0, 0, -0.1), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), chrome)
	b.cylinder(0.15, 0.15, 0.02, MeshKit.at(Vector3(0, 0, -0.16), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), col)
	b.tube(Vector3(0, 0, 0.0), Vector3(0, -0.6, 0.05), 0.04, 0.04, chrome, 6)
	n.add_child(MeshKit.instance(b.build(), false))
	n.scale = Vector3.ONE * 1.4
	return n


## Droplets spraying along the band (one particle node for the whole spray).
func _spray_fx(hz: Dictionary) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var dir := Vector3(float(hz.dx), 0.0, float(hz.dz)).normalized()
	var span_m := Deep.spray_len(hz)
	p.amount = 90
	p.lifetime = 0.7
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	var across := Vector3(-dir.z, 0.0, dir.x)
	p.emission_box_extents = (dir * span_m * 0.5).abs() + across.abs() * float(hz.r) * 0.8 + Vector3(0, 0.05, 0)
	p.direction = Vector3.DOWN + dir * 0.6
	p.spread = 15.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -6.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = MeshKit.material(Color(0.7, 0.9, 1.0), 0.6)
	p.mesh = sm
	p.position = Vector3(float(hz.x), main.WATER_Y + 0.9, float(hz.z)) + dir * span_m * 0.5
	p.emitting = true
	return p


## Bots / palette: the colour of a kind's tell.
static func color_of(kind: String) -> Color:
	return Deep.WHALE_COLOR if kind == "whale" else Deep.SPRAY_COLOR