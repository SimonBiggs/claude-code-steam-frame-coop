extends Node3D
## PAPER PLANES warned sky events (deep.gd events()): told first by core/warn_rings.gd STANDING UP in the sky (each
## tell's WarnRings sits in a frame whose flat plane faces the VR deck and the TV camera), then they happen:
##   GUST   teal rings round a patch of sky with white streaks blowing sideways: then the wind blows any plane in it
##          that way (every machine pushes its own planes: main.gd _fly_local; the host its VR paper planes).
##   GEESE  a steady pink band across the sky, a line of brown geese waiting at its end: then they fly along it. A
##          plane in the band bumps (the host decides: main.gd _goose_hits).
## Nothing flashes: the rings and band glow steadily. The host tells an event `t` seconds into a flight and sends
## "hazard" [packed event, warn, stay]; every machine draws the tells and knows which are blowing (live_now()).
##   host: reset(list); due(flight_t) -> the events whose tell starts now
##   every machine: announce(e, warn, stay); clear(); live_now() -> events going off now; tells_now() (bots)

const WarnRings := preload("res://core/warn_rings.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Contrast := preload("res://core/contrast.gd")
const Deep := preload("res://games/paper_planes/deep.gd")

const STREAKS := 8

var main
var list: Array = []  # host: this flight's events (deep.gd)
var told := {}  # host: index -> true once told
var fired := {}  # host: kind -> tells over the whole session (bots)
var live: Array = []  # every machine: [{e, t, secs, stay, frame, streaks, geese}]
var seen := 0  # every machine: tells drawn (bots)
var streak_mesh: BoxMesh
var streak_mat: StandardMaterial3D


func _ready() -> void:
	name = "Hazards"
	streak_mesh = BoxMesh.new()
	streak_mesh.size = Vector3(1.6, 0.08, 0.08)
	streak_mat = MeshKit.material(Color(1.0, 1.0, 1.0), 0.8)


## A brown goose flying along +X (wings out), 0.9 m long: cached, outlined by whoever shows it.
static func goose_mesh() -> ArrayMesh:
	return ResCache.get_or_make("pp_goose_v1", func() -> ArrayMesh:
		var b := MeshKit.Builder.new()
		b.ellipsoid(Vector3(0.36, 0.16, 0.16), MeshKit.at(Vector3.ZERO), Deep.GOOSE_BODY)
		b.ellipsoid(Vector3(0.22, 0.1, 0.12), MeshKit.at(Vector3(-0.04, -0.07, 0.0)), Color(0.85, 0.82, 0.76))
		b.capsule_between(Vector3(0.28, 0.04, 0.0), Vector3(0.5, 0.14, 0.0), 0.05, Deep.GOOSE_NECK)
		b.sphere(0.08, MeshKit.at(Vector3(0.54, 0.16, 0.0)), Deep.GOOSE_NECK)
		b.cone(0.035, 0.12, MeshKit.at(Vector3(0.64, 0.15, 0.0), Vector3.ONE, Vector3(0.0, 0.0, -PI * 0.5)), Color(0.95, 0.65, 0.2))
		b.box(Vector3(0.3, 0.03, 0.9), MeshKit.at(Vector3(0.02, 0.06, 0.0)), Deep.GOOSE_BODY.lightened(0.1))
		return b.build()) as ArrayMesh


## Host: a new flight's events (none while picking).
func reset(new_list: Array) -> void:
	list = new_list.duplicate(true)
	told = {}


## Host: the events whose tell starts now (flight_t seconds into the flight).
func due(flight_t: float) -> Array:
	var out: Array = []
	for i in list.size():
		if told.has(i) or flight_t < float(list[i].t):
			continue
		told[i] = true
		fired[String(list[i].kind)] = int(fired.get(String(list[i].kind), 0)) + 1
		out.append(list[i])
	return out


## The frame a tell stands in: its flat (x, z) plane faces +Z (the VR deck, the TV camera), x = sideways.
static func frame_of(e: Dictionary) -> Transform3D:
	var side := Vector3.RIGHT
	var n := Vector3.BACK
	return Transform3D(Basis(side, n, side.cross(n)), e.pos)


## Every machine: draw the tell now; it goes off after `warn` seconds and lasts `stay` more.
func announce(e: Dictionary, warn: float, stay: float) -> void:
	seen += 1
	var frame := Node3D.new()
	frame.name = "Tell_" + String(e.kind)
	var rings := WarnRings.new()
	var entry := {"e": e, "t": 0.0, "secs": warn, "stay": stay, "frame": frame, "streaks": [], "geese": []}
	var sz: Vector2 = e.size
	match String(e.kind):
		"gust":  # (built before it joins the tree: the shapes sit in the frame's own plane)
			rings.shape("circle", Vector3.ZERO, Vector3.FORWARD, Vector2(sz.x, 0.0), Deep.GUST_COLOR, warn,
				{"style": "rings", "stay": stay, "y": 0.0})
			for k in STREAKS:
				var s := MeshInstance3D.new()
				s.mesh = streak_mesh
				s.material_override = streak_mat
				s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				s.position = Vector3(0.0, 0.0, (float(k) / (STREAKS - 1) - 0.5) * sz.x * 1.4)
				frame.add_child(s)
				(entry.streaks as Array).append(s)
			main.sfx.play("whoosh", -8.0, 0.6)
		"geese":
			rings.shape("line", Vector3(-sz.x * 0.5, 0.0, 0.0), Vector3.RIGHT, sz, Deep.GEESE_COLOR, warn,
				{"style": "disc", "stay": stay, "alpha": 0.3, "y": 0.0})
			for k in Deep.GEESE_N:
				var g := Contrast.outline(MeshKit.instance(goose_mesh(), false)) as MeshInstance3D
				g.name = "Goose"
				frame.add_child(g)
				(entry.geese as Array).append(g)
			main.sfx.play("boing", -10.0, 0.5)
	frame.add_child(rings)
	add_child(frame)
	frame.global_transform = frame_of(e)
	live.append(entry)
	_pose(entry)


## Every machine: all gone (a new flight, a pick).
func clear() -> void:
	for en in live:
		if is_instance_valid(en.frame):
			(en.frame as Node).queue_free()
	live.clear()


## Every machine: the events going off right now (their tell is over, not yet gone).
func live_now() -> Array:
	var out: Array = []
	for en in live:
		if float(en.t) >= float(en.secs) and float(en.t) < float(en.secs) + float(en.stay):
			out.append(en.e)
	return out


## Bots: the tells showing now: [{kind, t (s since told), secs, stay, e}].
func tells_now() -> Array:
	var out: Array = []
	for en in live:
		out.append({"kind": String(en.e.kind), "t": float(en.t), "secs": float(en.secs), "stay": float(en.stay), "e": en.e})
	return out


func _process(delta: float) -> void:
	for i in range(live.size() - 1, -1, -1):
		var en: Dictionary = live[i]
		en.t = float(en.t) + delta
		if float(en.t) > float(en.secs) + float(en.stay) + 0.6 or not is_instance_valid(en.frame):
			if is_instance_valid(en.frame):
				(en.frame as Node).queue_free()
			live.remove_at(i)
			continue
		_pose(en)


## Streaks blow sideways the way the gust will push (slowly while told, fast while it blows); geese wait at the
## band's start, flapping, then fly along it.
func _pose(en: Dictionary) -> void:
	var t := float(en.t)
	var secs := float(en.secs)
	var stay := float(en.stay)
	var e: Dictionary = en.e
	var sz: Vector2 = e.size
	var sgn := float(e.sign)
	var blowing := t >= secs and t < secs + stay
	for k in (en.streaks as Array).size():
		var s: Node3D = en.streaks[k]
		var span := sz.x * 2.0
		var along := fmod(t * (9.0 if blowing else 2.5) + k * 1.7, span) - span * 0.5
		s.position.x = along * sgn
		s.visible = t < secs + stay
	var n := (en.geese as Array).size()
	for k in n:
		var g: Node3D = en.geese[k]
		var start := -sz.x * 0.5 - 1.0 - k * 1.1  # a line of geese queued off the band's start (V-ish)
		var x := start
		if t >= secs:
			x = start + (t - secs) / stay * (sz.x + 2.0 + n * 1.1)
		var wob := sin(t * 3.0 + k) * 0.12
		g.position = Vector3(x * sgn, 0.0, -absf(k - n * 0.5) * 0.25 + wob)
		# The frame's z is world down, its y world +Z: the goose's nose along the way they fly, its back up, wings out.
		var flap := 0.6 + 0.4 * absf(sin(t * 7.0 + k))
		g.basis = Basis(Vector3(sgn, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, sgn * flap, 0.0))
		g.visible = t < secs + stay + 0.4


## Bots / main / palette: the colour of a kind's tell.
static func color_of(kind: String) -> Color:
	return Deep.GUST_COLOR if kind == "gust" else Deep.GEESE_COLOR
