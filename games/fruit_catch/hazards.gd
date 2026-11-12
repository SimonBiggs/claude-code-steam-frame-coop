extends Node3D
## FRUIT CATCH warned surprises (deep.gd hazards()): every machine draws the surprise in the "hz" state (the host
## sets it when its tell starts and clears it when it is over), steady from the tell until it is over:
##   WINDFALL  a brown circle on the grass (core/warn_rings.gd) with a ring of little rotten apples round its edge:
##             a shower of rotten apples lands inside it (the host drops them; they are ordinary fruit).
##   WASP      a yellow band across the park with a stripy wasp waiting at its end; when the tell is over it buzzes
##             along the band (every machine flies its own from the same numbers) and bumps anyone in its way.
## Nothing flashes: the circle and the band glow steadily in their own colours (deep.gd WINDFALL_COLOR / WASP_COLOR),
## never the gold of a pick or a dish. See-through parts draw under the VR cards (UiKit.VR_PRIO_UNDER_UI).
##   show_now(hz) on every "hz" change; tells_now() for bots.

const WarnRings := preload("res://core/warn_rings.gd")
const UiKit := preload("res://core/ui_kit.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Deep := preload("res://games/fruit_catch/deep.gd")

const STAY := 600.0  # (the tell stays until the host clears it)

var main
var rings: WarnRings
var key := ""
var now := {}
var age := 0.0  # seconds since this surprise's tell began here
var wasp: Node3D
var marks: Node3D
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
	if hz.is_empty():
		return
	seen[String(hz.kind)] = int(seen.get(String(hz.kind), 0)) + 1
	var at := Vector3(float(hz.x), 0.0, float(hz.z))
	var col := color_of(String(hz.kind))
	match String(hz.kind):
		"windfall":
			rings.shape("circle", at, Vector3.FORWARD, Vector2(float(hz.r), 0.0), col, 0.3,
				{"style": "disc", "stay": STAY, "alpha": 0.45, "y": 0.03, "hot": col})
			marks = Node3D.new()
			marks.name = "WindfallMarks"
			var m := _mat(col.darkened(0.3), 1.0, false)
			for i in 8:  # little rotten apples round the edge: "apples will land here"
				var b := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.09
				sm.height = 0.15
				sm.radial_segments = 8
				sm.rings = 4
				b.mesh = sm
				b.material_override = m
				b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var a := float(i) * TAU / 8.0
				b.position = Vector3(cos(a), 0.0, sin(a)) * (float(hz.r) + 0.15) + Vector3(0, 0.07, 0)
				marks.add_child(b)
			add_child(marks)
			marks.position = at
			main.sound("spit", -6.0, 0.6)
		"wasp":
			var dir := Vector3(float(hz.dx), 0.0, float(hz.dz)).normalized()
			var half := Deep.wasp_half(hz)
			rings.shape("line", at - dir * half, dir, Vector2(half * 2.0, float(hz.r) * 2.0), col, 0.3,
				{"style": "disc", "stay": STAY, "alpha": 0.4, "y": 0.03, "hot": col})
			wasp = _wasp_node()
			add_child(wasp)
			wasp.position = Deep.wasp_at(hz, 0.0)
			UiKit.look(wasp, wasp.position + dir, Vector3.UP)
			main.sound("whoosh", -4.0, 1.9)


func clear() -> void:
	rings.clear()
	for n in [wasp, marks]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	wasp = null
	marks = null
	now = {}


## Bots: the surprise showing now: [{kind, x, z, ...}].
func tells_now() -> Array:
	return [] if now.is_empty() else [now.duplicate()]


## Where the wasp is now (Vector3.INF: none flying).
func wasp_pos() -> Vector3:
	return wasp.position if wasp != null and is_instance_valid(wasp) else Vector3.INF


func _process(delta: float) -> void:
	if now.is_empty():
		return
	age += delta
	if wasp != null and is_instance_valid(wasp):
		var fly := age - float(now.warn)
		var p := Deep.wasp_at(now, maxf(0.0, fly))
		p.y += sin(age * 9.0) * 0.08  # it hovers, then buzzes along
		wasp.position = p
		var wings := wasp.get_node_or_null("Wings") as Node3D
		if wings != null:
			wings.scale.y = 0.4 + 0.6 * absf(sin(age * 60.0))
		wasp.visible = fly < Deep.wasp_secs(now) + 0.2
	if marks != null and is_instance_valid(marks):
		marks.rotation.y += delta * 0.4  # the little apples circle slowly (steady colour, never flashing)


## A friendly cartoon wasp (stripy body, see-through wings), facing +Z.
func _wasp_node() -> Node3D:
	var n := Node3D.new()
	n.name = "Wasp"
	var b := MeshKit.Builder.new()
	var y := Deep.WASP_COLOR
	var k := Color(0.12, 0.1, 0.08)
	b.ellipsoid(Vector3(0.16, 0.15, 0.24), MeshKit.at(Vector3(0, 0, -0.12)), y, 12)
	for i in 3:
		b.ellipsoid(Vector3(0.165, 0.155, 0.03), MeshKit.at(Vector3(0, 0, -0.2 + i * 0.09)), k, 12)
	b.sphere(0.12, MeshKit.at(Vector3(0, 0.03, 0.15)), y, 10)
	for s in [-1.0, 1.0]:
		b.sphere(0.04, MeshKit.at(Vector3(0.06 * s, 0.07, 0.24)), k, 6)
		b.tube(Vector3(0.04 * s, 0.13, 0.2), Vector3(0.09 * s, 0.25, 0.26), 0.012, 0.01, k, 4)
	b.cone(0.04, 0.12, MeshKit.at(Vector3(0, 0, -0.4), Vector3.ONE, Vector3(-PI * 0.5, 0, 0)), k, 6)
	var body := MeshKit.instance(b.build(), false)
	n.add_child(body)
	var wings := Node3D.new()
	wings.name = "Wings"
	wings.position = Vector3(0, 0.14, 0.0)
	var wm := _mat(Color(0.9, 0.97, 1.0), 0.55)
	for s in [-1.0, 1.0]:
		var w := MeshInstance3D.new()
		var q := SphereMesh.new()
		q.radius = 0.16
		q.height = 0.04
		q.radial_segments = 10
		q.rings = 3
		w.mesh = q
		w.material_override = wm
		w.position = Vector3(0.15 * s, 0.04, 0.0)
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wings.add_child(w)
	n.add_child(wings)
	n.scale = Vector3.ONE * 1.6  # big enough to see coming from across the park
	return n


func _mat(col: Color, alpha: float, see_through: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if see_through and alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.render_priority = UiKit.VR_PRIO_UNDER_UI  # see-through: under VR cards
	return m


## Bots / palette: the colour of a kind's tell.
static func color_of(kind: String) -> Color:
	return Deep.WINDFALL_COLOR if kind == "windfall" else Deep.WASP_COLOR
