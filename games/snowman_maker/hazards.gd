extends Node3D
## SNOWMAN MAKER warned surprises (deep.gd hazards()): every machine draws the surprise in the "hz" state (the host
## sets it when its tell starts and clears it when it is over), steady from the tell until it is over:
##   SUNBEAM  a warm orange circle on the snow (core/warn_rings.gd) with a soft beam of sunlight coming down onto it:
##            snowballs left in it melt smaller (the host shrinks them) - roll them out into the shade!
##   SLIDE    a violet band across the garden with a giant snowball waiting at its end; when the tell is over it
##            rolls along the band (every machine rolls its own from the same numbers), knocks loose snowballs aside
##            and makes anyone in its way dizzy.
## Nothing flashes: the circle and the band glow steadily in their own colours (deep.gd SUN_COLOR / SLIDE_COLOR), never
## the gold of a pick. See-through parts draw under the VR cards (UiKit.VR_PRIO_UNDER_UI).
##   show_now(hz) on every "hz" change; tells_now() for bots.

const WarnRings := preload("res://core/warn_rings.gd")
const UiKit := preload("res://core/ui_kit.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Deep := preload("res://games/snowman_maker/deep.gd")
const Snowman := preload("res://games/snowman_maker/snowman.gd")

const STAY := 600.0  # (the tell stays until the host clears it)

var main
var rings: WarnRings
var key := ""
var now := {}
var age := 0.0  # seconds since this surprise's tell began here
var boulder: Node3D  # the slide's giant snowball
var boulder_ball: MeshInstance3D
var beam: MeshInstance3D  # the sunbeam's light
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
		"sun":
			rings.shape("circle", at, Vector3.FORWARD, Vector2(float(hz.r), 0.0), col, 0.3,
				{"style": "disc", "stay": STAY, "alpha": 0.42, "y": 0.03, "hot": col})
			beam = MeshInstance3D.new()
			beam.name = "Sunbeam"
			var cm := CylinderMesh.new()
			cm.top_radius = float(hz.r) * 0.55
			cm.bottom_radius = float(hz.r)
			cm.height = 7.0
			cm.radial_segments = 20
			cm.rings = 1
			cm.cap_top = false
			cm.cap_bottom = false
			beam.mesh = cm
			beam.material_override = _mat(Color(1.0, 0.85, 0.45), 0.16)
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(beam)
			beam.position = at + Vector3.UP * 3.5
			main.sfx.play_at("sparkle", at, -6.0, 0.6)
		"slide":
			var dir := Vector3(float(hz.dx), 0.0, float(hz.dz)).normalized()
			var half := Deep.slide_half(hz)
			rings.shape("line", at - dir * half, dir, Vector2(half * 2.0, float(hz.r) * 2.0), col, 0.3,
				{"style": "disc", "stay": STAY, "alpha": 0.4, "y": 0.03, "hot": col})
			boulder = Node3D.new()
			boulder.name = "SlideBall"
			boulder_ball = MeshInstance3D.new()
			boulder_ball.mesh = Snowman.ball_mesh()
			boulder_ball.material_override = Snowman.snow_material()
			Snowman.outline_ball(boulder_ball)
			boulder_ball.scale = Vector3.ONE * Deep.SLIDE_R
			boulder.add_child(boulder_ball)
			add_child(boulder)
			boulder.position = Deep.slide_at(hz, 0.0)
			main.sfx.play_at("whoosh", boulder.position, -4.0, 0.6)


func clear() -> void:
	rings.clear()
	for n in [boulder, beam]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	boulder = null
	boulder_ball = null
	beam = null
	now = {}


## Bots: the surprise showing now: [{kind, x, z, ...}].
func tells_now() -> Array:
	return [] if now.is_empty() else [now.duplicate()]


## Where the slide's giant snowball is now (Vector3.INF: none rolling).
func slide_pos() -> Vector3:
	return boulder.position if boulder != null and is_instance_valid(boulder) and boulder.visible else Vector3.INF


func _process(delta: float) -> void:
	if now.is_empty():
		return
	age += delta
	if boulder != null and is_instance_valid(boulder):
		var roll := age - float(now.warn)
		var before := boulder.position
		boulder.position = Deep.slide_at(now, maxf(0.0, roll))
		if roll < 0.0:  # it rocks at the top, waiting
			boulder.position.y += absf(sin(age * 5.0)) * 0.05
		var d := boulder.position - before
		d.y = 0.0
		if d.length() > 0.0001:
			var axis := Vector3(d.z, 0.0, -d.x) / d.length()
			boulder_ball.basis = (Basis(axis, d.length() / Deep.SLIDE_R) * boulder_ball.basis).orthonormalized()
		boulder.visible = roll < Deep.slide_secs(now) + 0.2
	if beam != null and is_instance_valid(beam):
		beam.rotation.y += delta * 0.3  # the light turns slowly (steady colour, never flashing)


func _mat(col: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	UiKit.see_through(m)
	return m


## Bots / palette: the colour of a kind's tell.
static func color_of(kind: String) -> Color:
	return Deep.SUN_COLOR if kind == "sun" else Deep.SLIDE_COLOR
