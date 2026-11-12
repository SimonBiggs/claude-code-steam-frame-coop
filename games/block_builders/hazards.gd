extends Node3D
## BLOCK BUILDERS: the sky's warned SURPRISES (deep.gd spots / kind_at). Every machine draws the surprise in the "hz"
## state (the host sets it when its tell starts and clears it when it is over), steady from the tell until it is over:
##   WIND    a blue band across an island (core/warn_rings.gd "line", disc style); when the tell is over a gust
##           blows: wind streaks fly along it and runners in it are pushed towards the island's front edge.
##   WOBBLE  an orange-red circle on an island; when the tell is over the ground wobbles: dust puffs and runners in it hop
##           (BRAVE / HARD: dizzy for a moment, deep.gd MODES dizzy).
## Nothing flashes: the shapes glow steadily in their own colours (deep.gd WIND_COLOR / WOBBLE_COLOR), never the gold of
## a pick or the hint block. See-through parts draw under the VR cards (core/warn_rings.gd fill_material uses
## UiKit.VR_PRIO_UNDER_UI). Each machine moves only the runners it runs itself (its own TV runners; the host its buddy);
## STICKY BRICKS: nobody moves.
##   show_now(hz) on every state change; host_begin(...), host_tick(level_t), host_end(), steer(r, move) (buddy, bots)

const WarnRings := preload("res://core/warn_rings.gd")
const UiKit := preload("res://core/ui_kit.gd")
const Deep := preload("res://games/block_builders/deep.gd")

const STAY := 600.0  # (the tell stays until the host clears it)

var main
var rings: WarnRings
var key := ""
var now := {}
var age := 0.0  # seconds since this surprise's tell began here
var went := false
var hopped := {}  # runner index -> true (this wobble already hopped it)
var streaks: CPUParticles3D
var seen := {}  # kind -> tells drawn (bots)
var hits := 0  # runners moved here this course (telemetry)
var hits_all := 0  # ... in all (bots)
# Host
var list: Array = []  # fair spots on this course
var seed_value := 0
var season := "spring"
var every := 30.0
var next_t := INF
var k := 0
var cur := {}
var cur_t := 0.0
var count := 0


func _ready() -> void:
	name = "Hazards"
	rings = WarnRings.new()
	add_child(rings)


# --- Every machine --------------------------------------------------------------------------------------------

func show_now(hz: Dictionary) -> void:
	var nk := str(Deep.pack(hz))
	if nk == key:
		return
	key = nk
	clear()
	now = hz
	age = 0.0
	went = false
	hopped = {}
	if hz.is_empty():
		return
	seen[String(hz.kind)] = int(seen.get(String(hz.kind), 0)) + 1
	var col := color_of(String(hz.kind))
	var y := float(hz.y) + 0.04
	if String(hz.kind) == "wind":
		rings.shape("line", Vector3(float(hz.x), y, float(hz.z0)), Vector3.BACK, Vector2(float(hz.z1) - float(hz.z0), float(hz.w) * 2.0),
			col, 0.3, {"style": "disc", "stay": STAY, "alpha": 0.42, "y": y, "hot": col})
		main.local_sound("whoosh", -8.0, 0.6)
	else:
		rings.shape("circle", Vector3(float(hz.x), y, float(hz.z)), Vector3.FORWARD, Vector2(float(hz.w), 0.0), col, 0.3,
			{"style": "disc", "stay": STAY, "alpha": 0.42, "y": y, "hot": col})
		main.local_sound("boing", -8.0, 0.55)


func clear() -> void:
	rings.clear()
	if streaks != null and is_instance_valid(streaks):
		streaks.queue_free()
	streaks = null
	now = {}


## Bots: the surprise showing now.
func tells_now() -> Array:
	return [] if now.is_empty() else [now.duplicate()]


func going() -> bool:
	return not now.is_empty() and age >= float(now.warn)


func _process(delta: float) -> void:
	if now.is_empty():
		_settle()
		return
	age += delta
	if not went and age >= float(now.warn):
		went = true
		if String(now.kind) == "wind":
			_wind_fx()
		else:
			main.local_sound("land", -2.0, 0.6)
			for i in 8:
				var a := TAU * float(i) / 8.0
				main.burst(Vector3(float(now.x) + cos(a) * float(now.w) * 0.7, float(now.y) + 0.2, float(now.z) + sin(a) * float(now.w) * 0.7),
					Color(0.9, 0.8, 0.65), 6, 0.1)
	var on := went and age - float(now.warn) <= Deep.after(now)
	if streaks != null and is_instance_valid(streaks) and streaks.emitting and not on:
		streaks.emitting = false
	var sticky := Deep.sticky(main.gift)
	var md := Deep.mode_data(main.mode)
	for r in main.runners():
		if not r.active or r.remote or r.finished:
			continue
		r.hz_push = Vector3.ZERO
		if not on or sticky or not Deep.inside(now, r.global_position):
			continue
		if String(now.kind) == "wind":
			r.hz_push = Vector3(0.0, 0.0, float(md.wind))
			if not hopped.has(r.index):
				hopped[r.index] = true
				hits += 1
				hits_all += 1
		elif not hopped.has(r.index) and r.on_ground:
			hopped[r.index] = true
			hits += 1
			hits_all += 1
			r.vy = Deep.HOP
			r.on_ground = false
			r.dizzy_t = float(md.dizzy)
			r.squash = -0.4
			main.local_sound("boing", -6.0, 0.8)


## No surprise: nobody is pushed.
func _settle() -> void:
	if main == null or main.players.is_empty():
		return
	for r in main.runners():
		if not r.remote:
			r.hz_push = Vector3.ZERO


## The gust: wind streaks fly along the band towards the front edge.
func _wind_fx() -> void:
	main.local_sound("whoosh", -2.0, 0.8)
	var p := CPUParticles3D.new()
	p.name = "WindStreaks"
	p.amount = 30
	p.lifetime = 0.7
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(float(now.w), 0.5, 0.3)
	p.direction = Vector3.BACK
	p.spread = 4.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 7.0
	p.initial_velocity_max = 9.0
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.9, 0.97, 1.0, 0.7)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.render_priority = UiKit.VR_PRIO_UNDER_UI  # see-through: under the VR cards
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(float(now.x), float(now.y) + 0.6, float(now.z0) - 0.3)
	add_child(p)
	streaks = p
	p.emitting = true


# --- Host -----------------------------------------------------------------------------------------------------

## Host: a course's surprises (empty spots: none). first: seconds before the first one.
func host_begin(spots: Array, new_seed: int, new_season: String, mode: String, first: float) -> void:
	list = spots
	seed_value = new_seed
	season = new_season
	every = float(Deep.mode_data(mode).every)
	next_t = first if not spots.is_empty() else INF
	k = 0
	cur = {}
	count = 0
	main.net.state_set("hz", [])


func busy() -> bool:
	return not cur.is_empty()


## Host, every frame of play: tell the next surprise where a runner is near, play it, clear it.
func host_tick(level_t: float) -> void:
	if cur.is_empty():
		if level_t < next_t:
			return
		var kind := Deep.kind_at(seed_value, k, season)
		var e := {}
		for want in [kind, "wobble" if kind == "wind" else "wind"]:
			for r in main.runners():
				if r.active and not r.finished:
					e = Deep.pick_spot(list, String(want), r.global_position)
					if not e.is_empty():
						break
			if not e.is_empty():
				break
		if e.is_empty():
			next_t = level_t + Deep.RETRY
			return
		cur = e
		cur_t = level_t
		k += 1
		count += 1
		main.net.state_set("hz", Deep.pack(cur))
		main.hazard_told(cur)
		return
	if level_t - cur_t >= Deep.span(cur):
		cur = {}
		main.net.state_set("hz", [])
		next_t = level_t + every * _jitter(seed_value, k)


static func _jitter(s: int, n: int) -> float:
	return 0.85 + 0.35 * float(absi(hash("%d/%d" % [s, n])) % 1000) / 1000.0


func host_end() -> void:
	list = []
	cur = {}
	next_t = INF
	main.net.state_set("hz", [])


## The buddy runner and the bots: walk out of a told zone, and wait outside one until it's over.
func steer(r, move: Vector3) -> Vector3:
	if now.is_empty() or Deep.sticky(main.gift):
		return move
	var p: Vector3 = r.global_position
	var esc := Deep.escape_to(main.level_data(), now, p)
	if esc != Vector3.INF:
		var d := Vector3(esc.x - p.x, 0.0, esc.z - p.z)
		return d.normalized() if d.length() > 0.05 else Vector3.ZERO
	if move != Vector3.ZERO and Deep.inside(now, p + move.normalized() * 0.7, Deep.HIT_PAD + Deep.ESCAPE_PAD):
		return Vector3.ZERO
	return move


static func color_of(kind: String) -> Color:
	return Deep.WIND_COLOR if kind == "wind" else Deep.WOBBLE_COLOR
