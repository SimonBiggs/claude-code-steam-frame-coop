extends Node3D
## PAINT AND GUESS: the studio's warned SURPRISES on the canvas (deep.gd spot / kind_at). Every machine draws the
## surprise in the "hz" state (the host sets it when its tell starts and clears it when it is over), steady from the
## tell until it is over, with core/warn_rings.gd laid flat on the canvas (a node turned to lie on the board):
##   DRIP  an orange circle; when the tell is over a drop of paint drips down from the top of the easel into it and
##         its puddle dries away (see-through, never over paint).
##   WIND  a blue band; when the tell is over a gust from the window blows wind streaks across it.
## Nothing flashes: the shapes glow steadily in their own colours (deep.gd DRIP_COLOR / WIND_COLOR). See-through parts
## draw under the VR cards (core/warn_rings.gd fill_material and the puddle use UiKit.VR_PRIO_UNDER_UI). From the tell
## until it is over the brush can't paint inside (blocks(): main.gd lifts the brush), so the place stays bare and
## nobody's painting is ever covered or moved.
##   show_now(hz) on every state change; host_begin(...), host_tick(delta, time_left), host_end(), blocks(a, b, hw)

const WarnRings := preload("res://core/warn_rings.gd")
const UiKit := preload("res://core/ui_kit.gd")
const Deep := preload("res://games/paint_and_guess/deep.gd")

const STAY := 600.0  # (the tell stays until the host clears it)
const LIFT := 0.006  # the tells sit this far in front of the board (under the paint's sparkles, over the board)

var main
var plane: Node3D  # lies on the canvas: local x = canvas x, local -z = canvas y, local +y = out of the board
var rings: WarnRings
var key := ""
var now := {}
var age := 0.0  # seconds since this surprise's tell began here
var went := false
var drop: MeshInstance3D
var puddle: MeshInstance3D
var streaks: CPUParticles3D
var seen := {}  # kind -> tells drawn (bots)
var stopped := 0  # brush moves blocked here (bots, telemetry)
# Host
var seed_value := 0
var mode := "brave"
var every := 32.0
var next_t := INF
var k := 0
var cur := {}
var cur_t := 0.0
var round_t := 0.0  # seconds of painting this round (its own clock: a NEW ONE restarts the round's)
var count := 0


func _ready() -> void:
	name = "Hazards"
	plane = Node3D.new()
	plane.name = "CanvasTells"
	plane.basis = Basis(Vector3.RIGHT, PI * 0.5)
	main.canvas.board_root.add_child(plane)
	rings = WarnRings.new()
	plane.add_child(rings)


static func to_plane(p: Vector2, y: float = LIFT) -> Vector3:
	return Vector3(p.x, y, -p.y)


# --- Every machine ----------------------------------------------------------------------------------------

func show_now(hz: Dictionary) -> void:
	var nk := str(Deep.pack(hz))
	if nk == key:
		return
	key = nk
	clear()
	now = hz
	age = 0.0
	went = false
	if hz.is_empty():
		return
	seen[String(hz.kind)] = int(seen.get(String(hz.kind), 0)) + 1
	var col := Deep.color_of(String(hz.kind))
	var dim := col.darkened(Deep.TELL_DIM)  # the inside: a dim glow (never mistaken for paint) ...
	var c := Vector2(float(hz.x), float(hz.y))
	if String(hz.kind) == "wind":
		var from := c - Vector2(float(hz.w), 0.0)
		_flat("line", from, Vector3.RIGHT, Vector2(float(hz.w) * 2.0, float(hz.h) * 2.0), dim)
		for s in [-1.0, 1.0]:  # ... with bright edges in the tell's own colour
			_flat("line", from + Vector2(0.0, s * float(hz.h)), Vector3.RIGHT, Vector2(float(hz.w) * 2.0, Deep.TELL_EDGE), col)
		main.sound("whoosh", -8.0, 0.6)
	else:
		_flat("circle", c, Vector3.FORWARD, Vector2(float(hz.w), 0.0), dim, col)
		main.sound("pop", -10.0, 0.5)


## One steady tell shape flat on the canvas (core/warn_rings.gd; edge: the circle's ring colour).
func _flat(kind: String, at: Vector2, dir: Vector3, size: Vector2, col: Color, edge: Color = Color(0, 0, 0, 0)) -> void:
	var n := rings.shape(kind, to_plane(at), dir, size, edge if edge.a > 0.0 else col, 0.3,
		{"style": "disc", "stay": STAY, "alpha": 0.42, "y": LIFT, "hot": col})
	n.position = to_plane(at)


func clear() -> void:
	rings.clear()
	for nd in [drop, puddle, streaks]:
		if nd != null and is_instance_valid(nd):
			(nd as Node).queue_free()
	drop = null
	puddle = null
	streaks = null
	now = {}


## Bots: the surprise showing now.
func tells_now() -> Array:
	return [] if now.is_empty() else [now.duplicate()]


func going() -> bool:
	return not now.is_empty() and age >= float(now.warn)


## Every machine: may paint go from a to b (a brush of half width hw)? Never into a told surprise.
func blocks(a: Vector2, b: Vector2, hw: float = Deep.MAX_HALF_W) -> bool:
	if now.is_empty():
		return false
	if Deep.blocks(now, a, b, hw):
		stopped += 1
		return true
	return false


func _process(delta: float) -> void:
	if now.is_empty():
		return
	age += delta
	if not went and age >= float(now.warn):
		went = true
		if String(now.kind) == "wind":
			_wind_fx()
		else:
			_drip_fx()
	var after := age - float(now.warn)
	if drop != null and is_instance_valid(drop):  # the drop falls from the top of the easel into the circle
		var k2 := clampf(after / 0.45, 0.0, 1.0)
		var top: float = main.canvas.H * 0.5 + 0.04
		drop.position = to_plane(Vector2(float(now.x), lerpf(top, float(now.y), k2 * k2)), 0.02)
		if k2 >= 1.0:
			drop.queue_free()
			drop = null
			main.sound("pop", -6.0, 0.7)
			main.puff(main.canvas.canvas_to_world(Vector2(float(now.x), float(now.y)), 0.03), Deep.DRIP_COLOR, 12)
	if puddle != null and is_instance_valid(puddle):  # the puddle grows in, then dries away
		var grow := clampf((after - 0.45) / 0.3, 0.0, 1.0)
		var dry := clampf((after - 0.45) / maxf(0.1, float(now.after) - 0.45), 0.0, 1.0)
		var r := float(now.w) * 0.85 * maxf(0.01, grow)
		puddle.scale = Vector3(r, 1.0, r)
		puddle.transparency = 0.35 + 0.65 * dry
	if streaks != null and is_instance_valid(streaks) and streaks.emitting and after > float(now.after) - 0.6:
		streaks.emitting = false


## The drip: a drop of paint and its puddle (see-through, drying away).
func _drip_fx() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Deep.DRIP_COLOR.lightened(0.15)
	drop = MeshInstance3D.new()
	drop.name = "Drop"
	var sm := SphereMesh.new()
	sm.radius = 0.022
	sm.height = 0.05
	sm.radial_segments = 10
	sm.rings = 5
	drop.mesh = sm
	drop.material_override = m
	drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plane.add_child(drop)
	drop.position = to_plane(Vector2(float(now.x), main.canvas.H * 0.5 + 0.04), 0.02)
	puddle = MeshInstance3D.new()
	puddle.name = "Puddle"
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.002
	cm.radial_segments = 20
	cm.rings = 1
	puddle.mesh = cm
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.albedo_color = Color(Deep.DRIP_COLOR.r, Deep.DRIP_COLOR.g, Deep.DRIP_COLOR.b, 0.6)
	pm.render_priority = UiKit.VR_PRIO_UNDER_UI  # see-through: under the VR cards
	puddle.material_override = pm
	puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puddle.scale = Vector3(0.01, 1.0, 0.01)
	plane.add_child(puddle)
	puddle.position = to_plane(Vector2(float(now.x), float(now.y)), LIFT + 0.004)
	main.sound("drip", -4.0, 1.0)


## The gust: wind streaks fly across the band (from the window side).
func _wind_fx() -> void:
	main.sound("whoosh", -2.0, 0.9)
	var p := CPUParticles3D.new()
	p.name = "WindStreaks"
	p.amount = 18
	p.lifetime = 0.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.01, 0.005, float(now.h) * 0.8)
	p.direction = Vector3.RIGHT
	p.spread = 3.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = float(now.w) * 4.0
	p.initial_velocity_max = float(now.w) * 5.0
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.008)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.9, 0.97, 1.0, 0.8)
	m.render_priority = UiKit.VR_PRIO_UNDER_UI  # see-through: under the VR cards
	q.material = m
	p.mesh = q
	p.local_coords = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plane.add_child(p)
	p.position = to_plane(Vector2(float(now.x) - float(now.w), float(now.y)), LIFT + 0.006)
	p.rotation = Vector3(-PI * 0.5, 0.0, 0.0)  # (the quads lie on the board)
	streaks = p
	p.emitting = true


# --- Host -------------------------------------------------------------------------------------------------

## Host: a round's surprises (allowed false: none). first: seconds before the first one.
func host_begin(allowed: bool, new_seed: int, new_mode: String, first: float) -> void:
	seed_value = new_seed
	mode = new_mode
	every = float(Deep.mode_data(mode).every)
	next_t = first if allowed else INF
	round_t = 0.0
	k = 0
	cur = {}
	count = 0
	main.net.state_set("hz", [])


func busy() -> bool:
	return not cur.is_empty()


## Host, every frame of a painting round: tell the next surprise on bare canvas, play it, clear it.
func host_tick(delta: float, time_left: float) -> void:
	round_t += delta
	if cur.is_empty():
		if round_t < next_t:
			return
		var md := Deep.mode_data(mode)
		if time_left < float(md.warn) + float(md.after) + Deep.END_GAP:
			next_t = INF  # (too near the end: none this round)
			return
		var kind := Deep.kind_at(seed_value, k)
		var strokes: Array = main.canvas.export_strokes()
		var avoid: Array = main.brush_points()
		var e := {}
		for want in [kind, "wind" if kind == "drip" else "drip"]:
			e = Deep.spot(strokes, String(want), mode, seed_value, k, avoid)
			if not e.is_empty():
				break
		if e.is_empty():
			next_t = round_t + Deep.RETRY
			return
		cur = e
		cur_t = round_t
		k += 1
		count += 1
		main.net.state_set("hz", Deep.pack(cur))
		main.hazard_told(cur)
		return
	if round_t - cur_t >= Deep.span(cur):
		cur = {}
		main.net.state_set("hz", [])
		next_t = round_t + every * _jitter(seed_value, k)


static func _jitter(s: int, n: int) -> float:
	return 0.85 + 0.35 * float(absi(hash("%d/%d" % [s, n])) % 1000) / 1000.0


func host_end() -> void:
	cur = {}
	next_t = INF
	main.net.state_set("hz", [])
