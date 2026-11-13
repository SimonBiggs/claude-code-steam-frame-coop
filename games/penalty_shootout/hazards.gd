extends Node3D
## PENALTY SHOOTOUT warned weather (deep.gd hazards()): every machine draws this kick's weather from main.hz_now
## (the host's snapshot on the TV and the Decks), steady from the start of the turn until the next kick:
##   GUST  a pale blue band across the pitch between the goal and the spot (core/warn_rings.gd), three big arrows on
##         the grass and a few wind streaks sliding the way it blows: the ball is blown that way.
##   MUD   a brown patch round the penalty spot with mud splats: this kick is slow and heavy.
## Nothing flashes: the band and the patch glow steadily; the arrows and streaks just slide along. Each kind has its
## own colour (deep.gd GUST_COLOR / MUD_COLOR), never the gold of Leo's star or a pick.
##   show(hz) every frame (cheap: rebuilds only when the kick's weather changes); tells_now() for bots.

const WarnRings := preload("res://core/warn_rings.gd")
const UiKit := preload("res://core/ui_kit.gd")
const Deep := preload("res://games/penalty_shootout/deep.gd")

const STREAKS := 8
const STAY := 600.0  # (the tell stays until the kick is over: clear() takes it away)

var main
var rings: WarnRings
var key := ""
var now := {}
var arrows: Array[MeshInstance3D] = []
var streaks: Array[MeshInstance3D] = []
var mud: Node3D
var t := 0.0
var seen := {}  # kind -> tells drawn (bots)


func _ready() -> void:
	name = "Hazards"
	rings = WarnRings.new()
	add_child(rings)


## Every machine: this kick's weather ({} none) and a key that changes every kick.
func show_now(hz: Dictionary, kick_key: String) -> void:
	var k := "%s|%s" % [kick_key, str(Deep.pack(hz))]
	if k == key:
		return
	key = k
	clear()
	now = hz
	if hz.is_empty():
		return
	seen[String(hz.kind)] = int(seen.get(String(hz.kind), 0)) + 1
	var sp: Vector3 = main.spot
	match String(hz.kind):
		"gust":
			var from := Vector3(-Deep.GUST_W * 0.5, 0.0, Deep.GUST_Z)
			rings.shape("line", from, Vector3.RIGHT, Vector2(Deep.GUST_W, Deep.GUST_LEN), Deep.GUST_COLOR, 0.3,
				{"style": "disc", "stay": STAY, "alpha": 0.32, "y": 0.03})
			var am := _mat(Deep.GUST_COLOR.lightened(0.3), 0.95)
			for i in 3:
				var a := MeshInstance3D.new()
				a.mesh = _arrow_mesh()
				a.material_override = am
				a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				a.position = Vector3((i - 1) * 2.6, 0.05, Deep.GUST_Z + (i - 1) * 1.6)
				a.scale = Vector3(1.5, 1.0, 1.5)
				a.rotation.y = 0.0 if int(hz.sign) > 0 else PI
				add_child(a)
				arrows.append(a)
			var sm := _mat(Color(0.92, 0.98, 1.0), 0.55)
			for i in STREAKS:
				var s := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(1.4, 0.03, 0.03)
				s.mesh = bm
				s.material_override = sm
				s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(s)
				streaks.append(s)
			main.sound("whoosh" if main.SOUNDS.has("whoosh") else "dive", -10.0, 0.6)
		"mud":
			rings.shape("circle", Vector3(sp.x, 0.0, sp.z), Vector3.FORWARD, Vector2(Deep.MUD_R, 0.0), Deep.MUD_COLOR, 0.3,
				{"style": "disc", "stay": STAY, "alpha": 0.5, "y": 0.03})
			mud = Node3D.new()
			mud.name = "Mud"
			var mm := _mat(Deep.MUD_COLOR.darkened(0.25), 1.0, false)
			for i in 7:
				var b := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				var r := 0.18 + 0.1 * float(i % 3)
				cm.top_radius = r
				cm.bottom_radius = r * 1.1
				cm.height = 0.03
				cm.radial_segments = 10
				b.mesh = cm
				b.material_override = mm
				b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var a2 := float(i) * 2.4
				b.position = Vector3(cos(a2) * (0.5 + 0.12 * i), 0.045, sin(a2) * (0.45 + 0.1 * i) + 0.35)
				mud.add_child(b)
			add_child(mud)
			mud.position = Vector3(sp.x, 0.0, sp.z)
			main.sound("glug", -6.0, 0.7)


func clear() -> void:
	rings.clear()
	for n in arrows + streaks:
		if is_instance_valid(n):
			n.queue_free()
	arrows.clear()
	streaks.clear()
	if mud != null and is_instance_valid(mud):
		mud.queue_free()
	mud = null
	now = {}


## Bots: the weather showing now: [{kind, sign, drift}].
func tells_now() -> Array:
	return [] if now.is_empty() else [now.duplicate()]


func _process(delta: float) -> void:
	t += delta
	if now.is_empty():
		return
	var sgn := float(now.get("sign", 1))
	for i in arrows.size():  # the arrows slide a little the way it blows and back (steady colour, never flashing)
		var a := arrows[i]
		a.position.x = (i - 1) * 2.6 + sgn * 0.35 * sin(t * 1.6 + i)
	for i in streaks.size():  # wind streaks drift across the band, over the grass and under the bar
		var s := streaks[i]
		var f := fmod(t * 0.45 + float(i) / STREAKS, 1.0)
		s.position = Vector3(sgn * lerpf(-Deep.GUST_W * 0.5, Deep.GUST_W * 0.5, f),
			0.4 + 1.6 * fmod(float(i) * 0.37, 1.0), Deep.GUST_Z - Deep.GUST_LEN * 0.4 + Deep.GUST_LEN * 0.8 * fmod(float(i) * 0.61, 1.0))
		s.scale = Vector3.ONE * sin(f * PI)


func _mat(col: Color, alpha: float, see_through: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if see_through and alpha < 1.0:
		UiKit.see_through(m)
	return m


## A flat chevron arrow on the grass pointing +x (1.6 m long).
static func _arrow_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(-0.8, 0, -0.25), Vector3(0.2, 0, -0.25), Vector3(0.2, 0, 0.25), Vector3(-0.8, 0, 0.25),
		Vector3(0.2, 0, -0.6), Vector3(0.8, 0, 0.0), Vector3(0.2, 0, 0.6)]
	for tri in [[0, 1, 2], [0, 2, 3], [4, 5, 6]]:
		for j in [0, 2, 1]:
			st.set_normal(Vector3.UP)
			st.add_vertex(pts[tri[j]])
	return st.commit()


## Bots / palette: the colour of a kind's tell.
static func color_of(kind: String) -> Color:
	return Deep.GUST_COLOR if kind == "gust" else Deep.MUD_COLOR