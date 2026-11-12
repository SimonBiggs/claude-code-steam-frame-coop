extends Node3D
## SOFT DODGEBALL: TumTum's warned TRICKS (deep.gd tricks()). Every machine draws the trick in the "hz" state (the host
## sets it when its tell starts and clears it when it is over), steady from the tell until it is over:
##   STOMP   a red band across the court (core/warn_rings.gd "line", disc style); when the tell is over TumTum stomps,
##           his belly wobbles and a wobbly wave of dust rolls along the band. Runners in it get a bump.
##   SHOWER  a purple circle on the court; when the tell is over soft balls rain down in it for a moment. Runners in it
##           get a bump.
## Nothing flashes: the shapes glow steadily in their own colours (deep.gd STOMP_COLOR / SHOWER_COLOR), never the gold
## of a pick or a star. See-through parts draw under the VR cards (UiKit.VR_PRIO_UNDER_UI: core/warn_rings.gd fill_material). A bump: GENTLE just a
## boing and a hop; BRAVE / HARD out for deep.gd MODES out seconds (a BUBBLE SHIELD pops instead: main.trick_hit).
##   show_now(hz) on every state change; host_begin(list), host_tick(round_t), host_end(), busy(); tells_now() (bots)

const WarnRings := preload("res://core/warn_rings.gd")
const UiKit := preload("res://core/ui_kit.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Deep := preload("res://games/dodge_ball/deep.gd")

const STAY := 600.0  # (the tell stays until the host clears it)

var main
var rings: WarnRings
var key := ""
var now := {}
var age := 0.0  # seconds since this trick's tell began here
var went := false  # it went off here (the stomp wave / the shower started)
var rain: CPUParticles3D
var seen := {}  # kind -> tells drawn (bots)
# Host
var list: Array = []
var next_i := 0
var cur := {}
var hit := {}  # runners this trick already bumped
var count := 0  # tricks this round (telemetry)
var bumps := 0  # runners bumped this round (telemetry)


func _ready() -> void:
	name = "Hazards"
	rings = WarnRings.new()
	add_child(rings)


# --- Every machine --------------------------------------------------------------------------------------------

## The trick showing now ({} none).
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
	if String(hz.kind) == "stomp":
		var from := Vector3(-Deep.COURT_X - 0.4, 0.0, float(hz.z))
		rings.shape("line", from, Vector3.RIGHT, Vector2(Deep.COURT_X * 2.0 + 0.8, float(hz.w) * 2.0), col, 0.3,
			{"style": "disc", "stay": STAY, "alpha": 0.42, "y": 0.06, "hot": col})
		main.sfx.play("boing", -6.0, 0.55)
	else:
		rings.shape("circle", Vector3(float(hz.x), 0.0, float(hz.z)), Vector3.FORWARD, Vector2(float(hz.w), 0.0), col, 0.3,
			{"style": "disc", "stay": STAY, "alpha": 0.42, "y": 0.06, "hot": col})
		main.sfx.play("whoosh", -6.0, 0.6)


func clear() -> void:
	rings.clear()
	if rain != null and is_instance_valid(rain):
		rain.queue_free()
	rain = null
	now = {}


## Bots: the trick showing now: [{kind, x, z, w, warn, t}].
func tells_now() -> Array:
	return [] if now.is_empty() else [now.duplicate()]


## Has the trick showing now gone off (every machine's own clock)?
func going() -> bool:
	return not now.is_empty() and age >= float(now.warn)


func _process(delta: float) -> void:
	if now.is_empty():
		return
	age += delta
	if not went and age >= float(now.warn):
		went = true
		if String(now.kind) == "stomp":
			_stomp_fx()
		else:
			_shower_fx()


## The stomp goes off: TumTum's belly wobbles, a thud, dust puffs roll along the band.
func _stomp_fx() -> void:
	main.world.wobble_belly()
	main.sfx.play("boing", 0.0, 0.45)
	main.sfx.play("crowd_oh", -10.0)
	var z := float(now.z)
	for i in 7:
		var x := -Deep.COURT_X + Deep.COURT_X * 2.0 * float(i) / 6.0
		get_tree().create_timer(0.08 * i).timeout.connect(func() -> void:
			if is_inside_tree():
				main.burst(Vector3(x, 0.3, z), Color(0.95, 0.85, 0.7), 10, 0.14))


## The shower goes off: soft balls rain into the circle for deep.gd AFTER seconds.
func _shower_fx() -> void:
	main.sfx.play("whoosh", -2.0, 0.8)
	var p := CPUParticles3D.new()
	p.name = "BallRain"
	p.amount = 40
	p.lifetime = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = float(now.w) * 0.85
	p.direction = Vector3.DOWN
	p.spread = 5.0
	p.gravity = Vector3(0.0, -9.0, 0.0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 3.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	p.color = Deep.SHOWER_COLOR.lightened(0.35)
	p.mesh = ResCache.get_or_make("dodge_rain_ball", func() -> Resource:
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		sm.radial_segments = 10
		sm.rings = 5
		var m := MeshKit.material(Color.WHITE, 0.4)
		m = m.duplicate() as StandardMaterial3D
		m.vertex_color_use_as_albedo = true
		sm.material = m
		return sm)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(float(now.x), 4.5, float(now.z))
	add_child(p)
	rain = p
	p.emitting = true
	get_tree().create_timer(Deep.after(now)).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.emitting = false)


# --- Host -----------------------------------------------------------------------------------------------------

## Host: this round's tricks.
func host_begin(new_list: Array) -> void:
	list = new_list
	next_i = 0
	cur = {}
	count = 0
	bumps = 0
	main.net.state_set("hz", [])


## Host: a trick is being told or going off (the CPU giant holds its throws).
func busy() -> bool:
	return not cur.is_empty()


## Host, every frame of a round: tell the next trick, play it, clear it.
func host_tick(round_t: float) -> void:
	if cur.is_empty():
		if next_i < list.size() and round_t >= float((list[next_i] as Dictionary).t):
			cur = list[next_i]
			next_i += 1
			hit = {}
			count += 1
			main.net.state_set("hz", Deep.pack(cur))
			main.trick_told(cur)
		return
	var since := round_t - float(cur.t)
	if since >= float(cur.warn) and since <= Deep.span(cur):
		for id in main.avatars:
			if hit.has(id) or main.out.has(id) or main.safe.has(id):
				continue
			var a: Node3D = main.avatars[id]
			if Deep.inside(cur, Vector2(a.position.x, a.position.z)):
				hit[id] = true
				bumps += 1
				main.trick_hit(int(id), cur)
	if since >= Deep.span(cur):
		cur = {}
		main.net.state_set("hz", [])


## Host: the round is over: no trick.
func host_end() -> void:
	list = []
	next_i = 0
	cur = {}
	main.net.state_set("hz", [])


## Bots / palette: the colour of a kind's tell.
static func color_of(kind: String) -> Color:
	return Deep.STOMP_COLOR if kind == "stomp" else Deep.SHOWER_COLOR
