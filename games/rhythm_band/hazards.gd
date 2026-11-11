extends Node3D
## RHYTHM BAND warned changes (deep.gd changes()): every machine draws the song's changes from main.hz_list and its
## own song clock (the host's snapshot keeps them in step), steady from `warn` seconds before a change until it ends:
##   FAST  an orange disc on the stage floor round the band and orange chase arrows round its edge: faster bars.
##   SLOW  a sky-blue disc round the band with slow-drifting dots: slower bars.
##   SOLO  a pale gold disc under the soloist, then a soft spotlight beam on them while the solo plays.
## The stage's light beams take the tell's colour too (the TV views see them over the crowd).
## Nothing flashes: the discs glow steadily (core/warn_rings.gd "disc", held with `stay`); the arrows just turn. Each
## kind has its own colour (deep.gd FAST_COLOR / SLOW_COLOR / SOLO_COLOR). A picture card (speedup / snail /
## spotlight) comes up when the tell starts. tells_now() for bots.

const WarnRings := preload("res://core/warn_rings.gd")
const UiKit := preload("res://core/ui_kit.gd")
const Deep := preload("res://games/rhythm_band/deep.gd")
const Stage := preload("res://games/rhythm_band/stage.gd")

const BAND_AT := Vector3(0.0, Stage.STAGE_Y, -0.3)  # the middle of the band on the stage
const STAY := 600.0  # (held until the change ends: clear() takes it away)
const ARROWS := 8

var main
var rings: WarnRings
var key := ""
var now := {}  # the change showing ({} none)
var phase := ""  # "warn" | "on"
var who := -1  # the soloist (a player index)
var arrows: Array[MeshInstance3D] = []
var beam: MeshInstance3D
var t := 0.0
var seen := {}  # kind -> tells drawn (bots)
var told_at := {}  # change key -> song time its tell came up (bots: told before it starts)


func _ready() -> void:
	name = "Hazards"
	rings = WarnRings.new()
	add_child(rings)


## Every machine, every frame: the change showing at the song clock (cheap: rebuilds only when it changes).
func update(delta: float) -> void:
	t += delta
	var found: Array = []
	if main.state == "play" and main.song != null and not main.hz_list.is_empty():
		found = Deep.change_at(main.hz_list, float(main.song.spb), float(main.song_t), main.warn_secs() * main.rate_now())
	var k := ""
	if not found.is_empty():
		var e: Dictionary = found[0]
		k = "%d|%d|%s" % [int(main.song_serial), int(e.bar), String(e.kind)]
		if phase != String(found[1]) and k == key:
			phase = String(found[1])
			_phase_changed()
	if k != key:
		key = k
		clear()
		if not found.is_empty():
			_show(found[0], String(found[1]))
	_animate()


func _show(e: Dictionary, ph: String) -> void:
	now = e
	phase = ph
	var kind := String(e.kind)
	seen[kind] = int(seen.get(kind, 0)) + 1
	told_at[key] = float(main.song_t)
	var col := color_of(kind)
	if kind == "solo":
		who = main.soloist(e)
		rings.shape("circle", solo_spot(who), Vector3.FORWARD, Vector2(Deep.SOLO_R, 0.0), col, 0.3,
			{"style": "disc", "stay": STAY, "alpha": 0.45, "y": Stage.STAGE_Y + 0.03, "hot": col})
	else:
		rings.shape("circle", BAND_AT, Vector3.FORWARD, Vector2(Deep.BAND_R, 0.0), col, 0.3,
			{"style": "disc", "stay": STAY, "alpha": 0.28, "y": Stage.STAGE_Y + 0.025, "hot": col})
		var am := _mat(col.lightened(0.25), 0.95)
		for i in ARROWS:
			var a := MeshInstance3D.new()
			a.mesh = _arrow_mesh() if kind == "fast" else _dot_mesh()
			a.material_override = am
			a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(a)
			arrows.append(a)
	if ph == "warn":
		match kind:
			"fast":
				main.story_now("Faster!", "speedup", col)
			"slow":
				main.story_now("Slower...", "snail", col)
			_:
				main.story_now("Solo time!", "spotlight", col)
		main.sound("ready", -8.0, 1.4 if kind == "fast" else (0.7 if kind == "slow" else 1.1))
	_phase_changed()


## The solo's spotlight beam comes on when the solo starts.
func _phase_changed() -> void:
	if String(now.get("kind", "")) != "solo" or phase != "on" or beam != null:
		return
	beam = MeshInstance3D.new()
	beam.name = "Spotlight"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = Deep.SOLO_R
	cm.height = 4.5
	cm.radial_segments = 20
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	beam.material_override = _mat(Deep.SOLO_COLOR, 0.16)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	beam.global_position = solo_spot(who) + Vector3(0.0, 2.25, 0.0)


## Where the soloist stands (the floor under them).
func solo_spot(i: int) -> Vector3:
	if i <= 0 or main.stage == null or i - 1 >= main.stage.avatars.size():
		var d = main.players[0]
		var at: Vector3 = d.rig.global_position if d.rig != null and d.rig.is_inside_tree() else Stage.DRUM_SPOT
		return Vector3(at.x, Stage.STAGE_Y, at.z)
	var av: Node3D = main.stage.avatars[i - 1]
	return Vector3(av.position.x, Stage.STAGE_Y, av.position.z)


func clear() -> void:
	rings.clear()
	for n in arrows:
		if is_instance_valid(n):
			n.queue_free()
	arrows.clear()
	if beam != null and is_instance_valid(beam):
		beam.queue_free()
	beam = null
	now = {}
	phase = ""
	who = -1


## Bots: the change showing now: [{kind, bar, phase, who}].
func tells_now() -> Array:
	return [] if now.is_empty() else [{"kind": now.kind, "bar": now.bar, "phase": phase, "who": who}]


func _animate() -> void:
	if now.is_empty():
		return
	var kind := String(now.kind)
	# The stage's light beams glow the tell's colour all the way through (steady: the TV views see the beams even
	# when the crowd hides the floor).
	if main.stage != null:
		main.stage.tint_col = color_of(kind)
		main.stage.tint_k = 1.0
	# Fast: arrows chase round the disc's edge (turning, never flashing); slow: dots drift slowly round it.
	var spd := 0.9 if kind == "fast" else 0.25
	for i in arrows.size():
		var a := arrows[i]
		var ang := t * spd + float(i) * TAU / arrows.size()
		var r := Deep.BAND_R - 0.3
		a.position = BAND_AT + Vector3(cos(ang) * r, 0.05, sin(ang) * r)
		a.rotation.y = -ang - PI * 0.5  # pointing along the way round
	if beam != null and who >= 0:
		beam.global_position = solo_spot(who) + Vector3(0.0, 2.25, 0.0)


func _mat(col: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.render_priority = UiKit.VR_PRIO_UNDER_UI  # see-through: under VR cards
	return m


## A flat chevron on the floor pointing +x (0.5 m long).
static func _arrow_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(-0.25, 0, -0.08), Vector3(0.05, 0, -0.08), Vector3(0.05, 0, 0.08), Vector3(-0.25, 0, 0.08),
		Vector3(0.05, 0, -0.2), Vector3(0.25, 0, 0.0), Vector3(0.05, 0, 0.2)]
	for tri in [[0, 1, 2], [0, 2, 3], [4, 5, 6]]:
		for j in [0, 2, 1]:
			st.set_normal(Vector3.UP)
			st.add_vertex(pts[tri[j]])
	return st.commit()


static func _dot_mesh() -> Mesh:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.12
	cm.height = 0.02
	cm.radial_segments = 12
	return cm


## Bots / palette: the colour of a kind's tell.
static func color_of(kind: String) -> Color:
	match kind:
		"fast":
			return Deep.FAST_COLOR
		"slow":
			return Deep.SLOW_COLOR
	return Deep.SOLO_COLOR
