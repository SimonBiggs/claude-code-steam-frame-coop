extends Node3D
## OBSTACLE RUSH: Coach Jelly's warned SURPRISES (deep.gd hazards()). Every machine draws the one in the "hz" state (the
## host sets it when its tell starts and clears it when it is over), steady from the tell until it is over:
##   LOG     an orange band across the course (core/warn_rings.gd "line", disc style) under a big log on ropes, pulled
##           back and trembling; when the tell is over it swings through the band and settles.
##   WATER   a blue band across the course; when the tell is over water rises there for a moment and sinks again.
##           Runners in it wade slowly (deep.gd MODES wade) on whatever machine runs them.
## Nothing flashes: the bands glow steadily in their own colours (deep.gd LOG_COLOR / WATER_COLOR), never the gold of a
## star. See-through parts draw under the VR cards (UiKit.VR_PRIO_UNDER_UI; core/warn_rings.gd fill_material). The host
## starts a tell when a runner comes deep.gd TRIGGER near it, never two at once; a runner caught: GENTLE a little hop,
## BRAVE / HARD a comical tumble back (a BUBBLE pops instead: runner.gd).
##   show_now(hz) on every state change; host_begin(list), host_tick(delta), host_end(), busy(); tells_now(),
##   wade_at(p), wait_for(p) (CPU runners and bots wait just before a told band)

const WarnRings := preload("res://core/warn_rings.gd")
const UiKit := preload("res://core/ui_kit.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Deep := preload("res://games/obstacle_rush/deep.gd")

const STAY := 600.0  # (the tell stays until the host clears it)
const LOG_DROP := 3.9  # the log hangs this far under its bar
const LOG_PULL := 1.1  # radians it is pulled back during the tell
const WATER_UP := 0.65  # how high the water rises over the floor

var main
var rings: WarnRings
var key := ""
var now := {}
var age := 0.0  # seconds since this tell began here
var went := false  # it went off here
var mode := "brave"  # every machine (main's "deep" state)
var half_w := 3.0
var log_pivot: Node3D
var frame: MeshInstance3D
var water: Node3D  # the water band (scaled up as it rises)
var seen := {}  # kind -> tells drawn (bots)
# Host
var list: Array = []
var next_i := 0
var cur := {}
var cur_t := 0.0
var gap_t := 0.0
var hit := {}  # runners this surprise already caught
var count := 0  # surprises this course (telemetry)
var bumps := 0  # runners caught this course (telemetry)


func _ready() -> void:
	name = "Hazards"
	rings = WarnRings.new()
	add_child(rings)


# --- Every machine --------------------------------------------------------------------------------------------

## The surprise showing now ({} none).
func show_now(hz: Dictionary, course_half_w: float) -> void:
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
	half_w = course_half_w
	seen[String(hz.kind)] = int(seen.get(String(hz.kind), 0)) + 1
	var col := color_of(String(hz.kind))
	var y := float(hz.y)
	rings.shape("line", Vector3(float(hz.x), 0.0, -half_w - 0.3), Vector3.BACK, Vector2(half_w * 2.0 + 0.6, float(hz.w) * 2.0),
		col, 0.3, {"style": "disc", "stay": STAY, "alpha": 0.42, "y": y + 0.07, "hot": col})
	if String(hz.kind) == "log":
		_build_log(Vector3(float(hz.x), y, 0.0))
		main.sfx.play_at("whoosh", Vector3(float(hz.x), y + 2.0, 0.0), -6.0, 0.6)
	else:
		_build_water(Vector3(float(hz.x), y, 0.0), float(hz.w))
		main.sfx.play_at("splash", Vector3(float(hz.x), y + 1.0, 0.0), -8.0, 1.2)


func clear() -> void:
	rings.clear()
	for n in [log_pivot, frame, water]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	log_pivot = null
	frame = null
	water = null
	now = {}


## Bots: the surprise showing now: [{kind, x, y, w, warn}].
func tells_now() -> Array:
	return [] if now.is_empty() else [now.duplicate()]


## Has the surprise showing now gone off (every machine's own clock)?
func going() -> bool:
	return not now.is_empty() and age >= float(now.warn)


## Running speed here for a runner whose feet are at p (the water slows them; 1.0 elsewhere).
func wade_at(p: Vector3) -> float:
	if now.is_empty() or String(now.kind) != "water" or not going() or age > Deep.span(now):
		return 1.0
	return float(Deep.mode_data(mode).wade) if Deep.inside(now, p, 0.0) else 1.0


## Should a runner at p wait (a band is told just in front of it)?
func wait_for(p: Vector3) -> bool:
	return not now.is_empty() and age < Deep.span(now) and Deep.wait_before(now, p)


func _process(delta: float) -> void:
	if now.is_empty():
		return
	age += delta
	var since := age - float(now.warn)
	if not went and since >= 0.0:
		went = true
		if String(now.kind) == "log":
			main.sfx.play_at("whoosh", Vector3(float(now.x), float(now.y) + 2.0, 0.0), -2.0, 0.8)
		else:
			main.sfx.play_at("splash", Vector3(float(now.x), float(now.y) + 0.5, 0.0), -2.0, 0.8)
			main.confetti(Vector3(float(now.x), float(now.y) + 0.3, 0.0), Deep.WATER_COLOR.lightened(0.4), 24)
	if log_pivot != null:
		if since < 0.0:  # pulled back, trembling
			log_pivot.rotation.z = -LOG_PULL + sin(age * 30.0) * 0.03
		else:  # swings through the band, then settles
			log_pivot.rotation.z = -LOG_PULL * cos(since * PI / 0.9) * exp(-since * 1.4)
	if water != null:
		var h := 0.0
		if since >= 0.0:
			var out_t := Deep.after(now) - since
			h = clampf(since / 0.5, 0.0, 1.0) * clampf(out_t / 0.5, 0.0, 1.0)
		water.visible = h > 0.01
		water.scale.y = maxf(0.01, h * WATER_UP)


func _build_log(at: Vector3) -> void:
	var len := half_w * 2.0 + 0.4
	var b := MeshKit.Builder.new()
	for s in [-1.0, 1.0]:  # the frame: two posts and a bar over the band
		b.cylinder(0.12, 0.15, LOG_DROP + 0.8, MeshKit.at(Vector3(0.0, (LOG_DROP + 0.8) * 0.5, s * (half_w + 0.45))), Color(0.55, 0.35, 0.2), 8)
	b.cylinder(0.1, 0.1, half_w * 2.0 + 1.2, MeshKit.at(Vector3(0.0, LOG_DROP + 0.8, 0.0), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), Color(0.55, 0.35, 0.2), 8)
	frame = MeshKit.instance(b.build(), false)
	frame.name = "LogFrame"
	frame.position = at
	add_child(frame)
	log_pivot = Node3D.new()
	log_pivot.name = "Log"
	log_pivot.position = at + Vector3(0.0, LOG_DROP + 0.8, 0.0)
	add_child(log_pivot)
	var lb := MeshKit.Builder.new()
	lb.cylinder(0.38, 0.38, len, MeshKit.at(Vector3(0.0, -LOG_DROP, 0.0), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), Color(0.62, 0.4, 0.22), 12)
	for s in [-1.0, 1.0]:
		lb.cylinder(0.3, 0.3, 0.04, MeshKit.at(Vector3(0.0, -LOG_DROP, s * len * 0.5), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), Color(0.9, 0.75, 0.5), 12)
		lb.cylinder(0.03, 0.03, LOG_DROP, MeshKit.at(Vector3(0.0, -LOG_DROP * 0.5, s * (len * 0.5 - 0.3))), Color(0.95, 0.9, 0.75), 4)
	var mi := MeshKit.instance(lb.build(), false)
	log_pivot.add_child(mi)
	log_pivot.rotation.z = -LOG_PULL


func _build_water(at: Vector3, w: float) -> void:
	water = Node3D.new()
	water.name = "WaterBand"
	water.position = at
	water.visible = false
	add_child(water)
	var mi := MeshInstance3D.new()  # a unit box, its bottom on the floor: the band scales it
	mi.mesh = ResCache.get_or_make("rush_water_box", func() -> Resource:
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		UiKit.see_through(m)
		m.albedo_color = Color(Deep.WATER_COLOR.r, Deep.WATER_COLOR.g, Deep.WATER_COLOR.b, 0.5)
		bm.material = m
		return bm) as Mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, 0.5, 0.0)
	water.add_child(mi)
	water.scale = Vector3(w * 2.0, 0.01, half_w * 2.0 + 0.2)


# --- Host -----------------------------------------------------------------------------------------------------

## Host: this course's surprises (by place along the course).
func host_begin(new_list: Array) -> void:
	list = new_list
	next_i = 0
	cur = {}
	cur_t = 0.0
	gap_t = 0.0
	count = 0
	bumps = 0
	main.net.state_set("hz", [])


## Host: a surprise is being told or going off.
func busy() -> bool:
	return not cur.is_empty()


## Host, every frame of a course: tell the next surprise when a runner comes near it, catch runners, clear it.
func host_tick(delta: float) -> void:
	if cur.is_empty():
		gap_t -= delta
		if gap_t > 0.0 or main.course_t < Deep.FIRST_T:
			return
		while next_i < list.size() and _all_past(list[next_i]):
			next_i += 1  # (everyone ran past before it was told)
		if next_i < list.size() and _someone_near(list[next_i]):
			cur = list[next_i]
			next_i += 1
			cur_t = 0.0
			hit = {}
			count += 1
			main.net.state_set("hz", Deep.pack(cur))
			main.hazard_told(cur)
		return
	cur_t += delta
	if cur_t >= float(cur.warn) and cur_t <= Deep.span(cur):
		for rid in main.runners:
			var r = main.runners[rid]
			if hit.has(rid) or r.done:
				continue
			if Deep.inside(cur, r.position):
				hit[rid] = true
				bumps += 1
				main.hazard_hit(int(rid), cur)
	if cur_t >= Deep.span(cur):
		cur = {}
		gap_t = Deep.WAIT_GAP
		main.net.state_set("hz", [])


## Host: the course is over: no surprise.
func host_end() -> void:
	list = []
	next_i = 0
	cur = {}
	main.net.state_set("hz", [])


func _all_past(e: Dictionary) -> bool:
	for r in main.runners.values():
		if not r.done and r.position.x < float(e.x) + float(e.w) + 0.5:
			return false
	return true


func _someone_near(e: Dictionary) -> bool:
	for r in main.runners.values():
		var p: Vector3 = r.position
		if not r.done and p.x > float(e.x) - float(e.w) - Deep.TRIGGER and p.x < float(e.x) + float(e.w) and absf(p.y - float(e.y)) < 2.0:
			return true
	return false


## Bots / palette: the colour of a kind's tell.
static func color_of(kind: String) -> Color:
	return Deep.LOG_COLOR if kind == "log" else Deep.WATER_COLOR