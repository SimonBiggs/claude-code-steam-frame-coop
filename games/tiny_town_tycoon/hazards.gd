extends Node3D
## TINY TOWN TYCOON: Benny's warned WEATHER (deep.gd weather()). Every machine draws the weather in the "hz" state (the
## host sets it when its tell starts and clears it when it is over), steady from the tell until it is over:
##   GUST  an orange band across the island (core/warn_rings.gd "line", disc style); when the tell is over a gust of
##         leaves blows along it and the vehicles in it spin round (BRAVE / HARD: stopped a moment).
##   FOG   a purple circle; when the tell is over sleepy fog settles in it and vehicles crawl through it until it lifts.
## Nothing flashes: the shapes glow steadily in their own colours (deep.gd GUST_COLOR / FOG_COLOR), never the gold of a
## pick. See-through parts draw under the VR cards (UiKit.VR_PRIO_UNDER_UI: core/warn_rings.gd fill_material, the fog
## puffs). What it does (deep.gd effect(): the mode, SUNNY DAY softer) happens on the machine that drives each vehicle
## (a TV player's own machine, the host for the AI), so it reacts at once everywhere.
##   show_now(hz) on every state change; slow_at(p), steer(p, goal) (AI drivers, bots); host_begin(list),
##   host_tick(delta), host_end(), busy(); tells_now() (bots)

const WarnRings := preload("res://core/warn_rings.gd")
const UiKit := preload("res://core/ui_kit.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Defs := preload("res://games/tiny_town_tycoon/defs.gd")
const Deep := preload("res://games/tiny_town_tycoon/deep.gd")

const STAY := 900.0  # (the tell stays until the host clears it)
const RING_Y := Defs.GROUND_Y + 0.004

var main
var rings: WarnRings
var key := ""
var now := {}
var age := 0.0  # seconds since this weather's tell began here
var went := false  # it went off here (the gust blew / the fog settled)
var fx_node: CPUParticles3D
var seen := {}  # kind -> tells drawn (bots)
var spun := 0  # vehicles this machine spun in gusts (bots)
var _field := PackedInt32Array()  # cells -> steps to the nearest drivable cell outside the weather (-1: none), for steer()
var _field_key := ""
# Host
var list: Array = []
var next_i := 0
var cur := {}
var clock := 0.0
var count := 0  # weathers this day (telemetry)
var hits := 0  # vehicles caught (telemetry)


func _ready() -> void:
	name = "Hazards"
	rings = WarnRings.new()
	add_child(rings)


# --- Every machine --------------------------------------------------------------------------------------------

## The weather showing now ({} none).
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
	var col := color_of(String(hz.kind))
	var o := {"style": "disc", "stay": STAY, "alpha": 0.58, "y": RING_Y, "hot": col}
	if String(hz.kind) == "gust":
		var from := Vector3(-Defs.HALF - 0.02, 0.0, float(hz.z))
		rings.shape("line", from, Vector3.RIGHT, Vector2(Defs.HALF * 2.0 + 0.04, float(hz.w) * 2.0), col, 0.3, o)
		main.sound("whoosh", -8.0, 0.6)
	else:
		rings.shape("circle", Vector3(float(hz.x), 0.0, float(hz.z)), Vector3.FORWARD, Vector2(float(hz.w), 0.0), col, 0.3, o)
		main.sound("swish", -6.0, 0.5)


func clear() -> void:
	rings.clear()
	if fx_node != null and is_instance_valid(fx_node):
		fx_node.queue_free()
	fx_node = null
	now = {}


## Bots: the weather showing now: [{kind, x, z, w, warn, t, after}].
func tells_now() -> Array:
	return [] if now.is_empty() else [now.duplicate()]


## Has the weather showing now gone off (every machine's own clock)?
func going() -> bool:
	return not now.is_empty() and age >= float(now.warn)


## A vehicle's speed factor here from the fog (1: none).
func slow_at(p: Vector3) -> float:
	if not going() or String(now.kind) != "fog" or not Deep.inside(now, Vector2(p.x, p.z)):
		return 1.0
	return float(Deep.effect(main.deep_mode, main.deep_gift).slow)


## Where a careful driver at p heading for goal should go while weather is told or blowing: Vector3.INF = on its way,
## p itself = wait here (the way on goes into it), else a point just outside it (drive out!).
func steer(p: Vector3, goal: Vector3) -> Vector3:
	if now.is_empty():
		return Vector3.INF
	var p2 := Vector2(p.x, p.z)
	if Deep.inside(now, p2, Deep.HIT_PAD + 0.004):
		var nxt := _next_cell_out(p)
		if nxt != Vector3.INF:
			return Vector3(nxt.x, p.y, nxt.z)
		var o := Deep.way_out(now, p2)
		return Vector3(o.x, p.y, o.y)
	var d := Vector2(goal.x - p.x, goal.z - p.z)
	if d.length() > 0.001:
		var ahead := p2 + d.normalized() * minf(d.length(), Defs.CELL * 1.2)
		if Deep.inside(now, ahead, Deep.HIT_PAD + 0.01):
			return p
	return Vector3.INF


## The middle of the next cell on the shortest drivable way (round buildings, water and rocks) out of the weather
## showing now, from p; INF when there is none.
func _next_cell_out(p: Vector3) -> Vector3:
	var town = main.town
	var n := Defs.GRID
	var k := "%s %d" % [key, int(town.version)]
	if k != _field_key:
		_field_key = k
		_field.resize(n * n)
		_field.fill(-1)
		var queue: Array[int] = []
		for i in n * n:
			var c := Defs.cell_center(i % n, i / n)
			if town._drivable(i % n, i / n) and Deep.depth(now, Vector2(c.x, c.z)) < -(Deep.HIT_PAD + Deep.ESCAPE_PAD):
				_field[i] = 0
				queue.append(i)
		var head := 0
		while head < queue.size():
			var i: int = queue[head]
			head += 1
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var x: int = i % n + d.x
				var z: int = i / n + d.y
				if x < 0 or z < 0 or x >= n or z >= n or _field[z * n + x] >= 0 or not town._drivable(x, z):
					continue
				_field[z * n + x] = _field[i] + 1
				queue.append(z * n + x)
	var c0 := Defs.world_cell(p)
	if not Defs.inside(c0.x, c0.y) or _field[c0.y * n + c0.x] < 0:
		return Vector3.INF
	var here := _field[c0.y * n + c0.x]
	var best := c0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c: Vector2i = c0 + d
		if Defs.inside(c.x, c.y) and _field[c.y * n + c.x] >= 0 and _field[c.y * n + c.x] < here:
			here = _field[c.y * n + c.x]
			best = c
	if best == c0:  # already in a safe cell, still too near its edge: on outwards
		return Vector3.INF
	return Defs.cell_center(best.x, best.y)


func _process(delta: float) -> void:
	if now.is_empty():
		return
	age += delta
	if not went and age >= float(now.warn):
		went = true
		if String(now.kind) == "gust":
			_gust()
		else:
			_fog()
	if fx_node != null and is_instance_valid(fx_node) and fx_node.emitting and age - float(now.warn) >= maxf(float(now.get("after", 1.0)) - 1.0, 0.8):
		fx_node.emitting = false


## The gust blows: leaves race along the band; every vehicle this machine drives that is in it spins (and stops a moment).
func _gust() -> void:
	main.sound("whoosh", 0.0, 0.8)
	var fx := Deep.effect(main.deep_mode, main.deep_gift)
	for vid in main.fleet.vehicles:
		var v: Node3D = main.fleet.vehicles[vid]
		if not _drives_here(v) or not Deep.inside(now, Vector2(v.position.x, v.position.z)):
			continue
		v.set("yaw", float(v.get("yaw")) + PI * (0.6 if float(fx.stall) <= 0.0 else 1.0))
		v.set("stall_t", float(fx.stall))
		v.set("_bounce", 1.0)
		spun += 1
		if int(vid) >= 1 and int(vid) < 100 and main.party.is_local(int(vid)):
			main.party.rumble(int(vid), 0.4, 0.2, 0.2)
	var p := _particles(60, 1.4, _leaf_mesh(), Color(0.95, 0.75, 0.3))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.02, 0.01, float(now.w))
	p.position = Vector3(-Defs.HALF, Defs.GROUND_Y + 0.025, float(now.z))
	p.direction = Vector3.RIGHT
	p.spread = 8.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.2
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0


## The fog settles: soft see-through puffs drift in the circle until it lifts.
func _fog() -> void:
	main.sound("swish", -4.0, 0.4)
	var p := _particles(36, 3.0, _puff_mesh(), Color(1.0, 1.0, 1.0, 0.5))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = float(now.w) * 0.8
	p.position = Vector3(float(now.x), Defs.GROUND_Y + 0.02, float(now.z))
	p.direction = Vector3.UP
	p.spread = 60.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.01
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	p.scale = Vector3(1.0, 0.35, 1.0)


func _particles(amount: int, life: float, mesh: Mesh, col: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "WeatherFx"
	p.amount = amount
	p.lifetime = life
	p.mesh = mesh
	p.color = col
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.emitting = true
	fx_node = p
	return p


static func _leaf_mesh() -> Mesh:
	return ResCache.get_or_make("town_gust_leaf", func() -> Resource:
		var q := QuadMesh.new()
		q.size = Vector2(0.012, 0.008)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		q.material = m
		return q) as Mesh


static func _puff_mesh() -> Mesh:
	return ResCache.get_or_make("town_fog_puff", func() -> Resource:
		var sm := SphereMesh.new()
		sm.radius = 0.03
		sm.height = 0.06
		sm.radial_segments = 10
		sm.rings = 5
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.albedo_color = Color(0.92, 0.9, 1.0, 1.0)
		m.render_priority = UiKit.VR_PRIO_UNDER_UI  # see-through: under the VR cards
		sm.material = m
		return sm) as Mesh


## Is vehicle v simulated on this machine (a TV player's own vehicle here, or the AI on the host)?
func _drives_here(v: Node3D) -> bool:
	if bool(v.get("mirror")):
		return false
	return not main.fleet.is_ai(int(v.get("vid"))) or main.net.mode != "client"


# --- Host -----------------------------------------------------------------------------------------------------

## Host: the rest of today's weather (times from now).
func host_begin(new_list: Array) -> void:
	list = new_list
	next_i = 0
	cur = {}
	clock = 0.0
	count = 0
	main.net.state_set("hz", [])


## Host: weather is being told or blowing.
func busy() -> bool:
	return not cur.is_empty()


## Host, every frame of play (not while a pick is up): tell the next weather, play it, clear it.
func host_tick(delta: float) -> void:
	if list.is_empty() and cur.is_empty():
		return
	clock += delta
	if cur.is_empty():
		if next_i < list.size() and clock >= float((list[next_i] as Dictionary).t):
			cur = list[next_i]
			next_i += 1
			count += 1
			main.net.state_set("hz", Deep.pack(cur))
			main.weather_told(cur)
		return
	var since := clock - float(cur.t)
	if since >= float(cur.warn) and since - delta < float(cur.warn):
		for vid in main.fleet.vehicles:
			var v: Node3D = main.fleet.vehicles[vid]
			if Deep.inside(cur, Vector2(v.position.x, v.position.z)):
				hits += 1
	if since >= Deep.span(cur):
		cur = {}
		main.net.state_set("hz", [])


## Host: no more weather (a new town, the day is over).
func host_end() -> void:
	list = []
	next_i = 0
	cur = {}
	main.net.state_set("hz", [])


## Bots / palette: the colour of a kind's tell.
static func color_of(kind: String) -> Color:
	return Deep.GUST_COLOR if kind == "gust" else Deep.FOG_COLOR
