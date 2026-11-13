extends Node3D
## STARSHIP CREW warned space surprises (deep.gd hazards()): every machine draws the surprise in the "hz" state (the
## host sets it when its tell starts and clears it when it is over), steady from the tell until it is over, STANDING
## UP in space ahead of the ship (deep.gd TELL_Z) in a frame whose flat plane faces the pilot (core/warn_rings.gd shapes
## are flat, so they are built in the frame before it joins the tree, like Dragon Rider's sky tells). The frame
## slides with space (the ship's sideways place), so "straight ahead" means "in it":
##   ROCK STREAM  an orange band (up-and-down or side-to-side); when the tell is over a stream of space rocks pours
##                through it past the ship (every machine flies its own from the same numbers; the first rocks are
##                already coming from far away while it is told).
##   SOLAR FLARE  a pink circle with a little hot sun far behind it; when the tell is over a beam of sunlight blasts
##                through it past the ship.
## Nothing flashes: the shapes glow steadily in their own colours (deep.gd STREAM_COLOR / FLARE_COLOR), never the gold
## of a star or the cyan of a ring. See-through parts draw under the VR cards (UiKit.VR_PRIO_UNDER_UI).
##   show_now(hz) on every "hz" change; tells_now() for bots.

const WarnRings := preload("res://core/warn_rings.gd")
const UiKit := preload("res://core/ui_kit.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Art := preload("res://games/starship_crew/art.gd")
const Deep := preload("res://games/starship_crew/deep.gd")
const Space := preload("res://games/starship_crew/space.gd")

const STAY := 600.0  # (the tell stays until the host clears it)
const ROCKS := 18
const ROCK_SPEED := 40.0  # m/s: the stream's rocks
const BAND_LONG := Vector2(Space.LIMIT.x * 2.0 + 8.0, Space.LIMIT.y * 2.0 + 6.0)  # a band reaches past space's edges

var main
var key := ""
var now := {}
var age := 0.0  # seconds since this surprise's tell began here
var frame: Node3D
var rocks: MultiMeshInstance3D
var beam: MeshInstance3D
var sun: MeshInstance3D
var seen := {}  # kind -> tells drawn (bots)


func _ready() -> void:
	name = "Hazards"


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
	var col := color_of(String(hz.kind))
	frame = Node3D.new()
	frame.name = "Tell_" + String(hz.kind)
	var rings := WarnRings.new()
	var o := {"style": "disc", "stay": STAY, "alpha": 0.32, "y": 0.0, "hot": col}
	# (frame: local x = right, local z = down, local y = towards the ship)
	match String(hz.kind):
		"stream":
			var ink := {"style": "disc", "stay": STAY, "alpha": 0.9, "y": 0.01, "hot": Deep.INK}
			if int(hz.vert) == 1:
				rings.shape("line", Vector3(0.0, 0.0, BAND_LONG.y * 0.5), Vector3.FORWARD, Vector2(BAND_LONG.y, float(hz.w) * 2.0), col, 0.3, o)
				for sx in [-1.0, 1.0]:  # ink edges: the band reads on a bright planet too
					rings.shape("line", Vector3(sx * float(hz.w), 0.0, BAND_LONG.y * 0.5), Vector3.FORWARD, Vector2(BAND_LONG.y, Deep.INK_W), Deep.INK, 0.3, ink)
			else:
				rings.shape("line", Vector3(-BAND_LONG.x * 0.5, 0.0, 0.0), Vector3.RIGHT, Vector2(BAND_LONG.x, float(hz.w) * 2.0), col, 0.3, o)
				for sz in [-1.0, 1.0]:
					rings.shape("line", Vector3(-BAND_LONG.x * 0.5, 0.0, sz * float(hz.w)), Vector3.RIGHT, Vector2(BAND_LONG.x, Deep.INK_W), Deep.INK, 0.3, ink)
			rocks = _stream_rocks()
			add_child(rocks)
			main.sfx.play("whoosh", -6.0, 0.6)
		"flare":
			rings.shape("circle", Vector3.ZERO, Vector3.FORWARD, Vector2(float(hz.w), 0.0), col, 0.3, o)
			var edge := MeshInstance3D.new()  # an ink edge round the circle: it reads on a bright planet too
			var tm := TorusMesh.new()
			tm.inner_radius = float(hz.w)
			tm.outer_radius = float(hz.w) + Deep.INK_W
			tm.rings = 32
			tm.ring_segments = 4
			edge.mesh = tm
			edge.material_override = _mat(Deep.INK, 0.9)
			edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			edge.scale = Vector3(1.0, 0.05, 1.0)
			frame.add_child(edge)
			sun = MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 1.0
			sm.height = 2.0
			sm.radial_segments = 16
			sm.rings = 8
			sun.mesh = sm
			sun.material_override = _mat(Color(1.0, 0.85, 0.6), 1.0, false)
			sun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(sun)
			beam = MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 1.0
			cm.bottom_radius = 1.0
			cm.height = 1.0
			cm.radial_segments = 20
			cm.rings = 1
			cm.cap_top = false
			cm.cap_bottom = false
			beam.mesh = cm
			beam.material_override = _mat(col.lightened(0.45), 0.45)
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			beam.visible = false
			add_child(beam)
			main.sfx.play("power_up", -8.0, 0.5)
	frame.add_child(rings)
	add_child(frame)
	_place()


func clear() -> void:
	for n in [frame, rocks, beam, sun]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	frame = null
	rocks = null
	beam = null
	sun = null
	now = {}


## Bots: the surprise showing now: [{kind, x, y, w, vert, warn, t}].
func tells_now() -> Array:
	return [] if now.is_empty() else [now.duplicate()]


## True while the rocks pour / the flare blasts (after the tell).
func going_off() -> bool:
	return not now.is_empty() and age >= float(now.warn)


func _process(delta: float) -> void:
	if now.is_empty():
		return
	age += delta
	_place()


## Everything slides with space: the frame, the rocks, the sun and the beam.
func _place() -> void:
	if now.is_empty() or main.space == null:
		return
	var off: Vector2 = main.space.off
	var c := Vector3(float(now.x) - off.x, float(now.y) - off.y + Space.SHIP_Y, 0.0)
	if String(now.kind) == "stream":
		if int(now.vert) == 1:
			c.y = Space.SHIP_Y - off.y
		else:
			c.x = -off.x
	if frame != null and is_instance_valid(frame):
		frame.transform = Transform3D(Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN), Vector3(c.x, c.y, Deep.TELL_Z))
	var fly := age - float(now.warn)
	if rocks != null and is_instance_valid(rocks):
		var mm := rocks.multimesh
		for k in ROCKS:
			var pass_t := Deep.AFTER * float(k) / float(ROCKS)  # when rock k passes the ship (after the tell)
			var z := (fly - pass_t) * ROCK_SPEED
			var across := (float((k * 7) % ROCKS) / float(ROCKS - 1) * 2.0 - 1.0)
			var lane := (float((k * 5 + 3) % 7) / 6.0 * 2.0 - 1.0) * float(now.w) * 0.8
			var p := Vector3(float(now.x) + lane - off.x, across * (Space.LIMIT.y + 1.0) - off.y + Space.SHIP_Y, z) if int(now.vert) == 1 \
				else Vector3(across * (Space.LIMIT.x + 2.0) - off.x, float(now.y) + lane - off.y + Space.SHIP_Y, z)
			var show := z > -130.0 and z < 1.0  # (gone once past the ship: never into the TV camera)
			var s := (0.5 + 0.08 * float(k % 4)) if show else 0.0001
			mm.set_instance_transform(k, Transform3D(Basis.from_euler(Vector3(age * 2.0 + k, age * 1.3 + k * 0.7, 0.0)).scaled(Vector3.ONE * s), p))
	if sun != null and is_instance_valid(sun):
		sun.position = Vector3(c.x, c.y, -160.0)
		sun.scale = Vector3.ONE * (2.0 + minf(age / maxf(0.1, float(now.warn)), 1.0) * 3.0)
	if beam != null and is_instance_valid(beam):
		beam.visible = fly >= 0.0 and fly < Deep.AFTER
		var r := float(now.w)
		beam.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(r, 170.0, r)), Vector3(c.x, c.y, -75.0))


## The stream's rocks: one multimesh of little space rocks (art.gd rock).
func _stream_rocks() -> MultiMeshInstance3D:
	var xfs: Array = []
	for k in ROCKS:
		xfs.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3(0, -50, -200)))
	var mi := MeshKit.scatter(Art.rock(0), xfs, PackedColorArray(), PackedColorArray(), false)
	mi.name = "StreamRocks"
	return mi


func _mat(col: Color, alpha: float, see_through: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if see_through and alpha < 1.0:
		UiKit.see_through(m)
	return m


## Bots / palette: the colour of a kind's tell.
static func color_of(kind: String) -> Color:
	return Deep.STREAM_COLOR if kind == "stream" else Deep.FLARE_COLOR