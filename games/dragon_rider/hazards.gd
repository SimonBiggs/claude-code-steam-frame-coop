extends Node3D
## DRAGON RIDER warned sky events (deep.gd events()): told first by core/warn_rings.gd STANDING UP in the sky across the
## route (each tell's WarnRings sits in a frame whose flat plane faces Sunny), then they happen:
##   STORM  red rings: a grumpy grey storm cloud puffs up in them while they are told, then rumbles there for
##          Deep.STAY seconds. Flying through it makes Sunny dizzy (GENTLE: just a giggle).
##   WIND   a teal band across the route with white streaks blowing sideways: when Sunny flies through it, a crosswind
##          pushes her that way for a few seconds.
## The host tells an event when Sunny is `warn` seconds of flight from it (whatever her speed), sends "hazard"
## [packed event, warn] and decides who flew through what (main.gd on_hazard); every machine draws the tells.
##   host: reset(list); due(core, speed, cruise, warn) -> the events whose tell starts now; hits(was, now, warn) -> the
##         live events Sunny just flew into
##   every machine: announce(e, warn); clear(); tells_now() (bots)

const WarnRings := preload("res://core/warn_rings.gd")
const Deep := preload("res://games/dragon_rider/deep.gd")

const STREAKS := 9

var main
var list: Array = []  # host: this stage's events (deep.gd)
var told := {}  # host: index -> seconds since its tell started
var hit := {}  # host: index -> true once Sunny met it
var fired := {}  # host: kind -> tells over the whole session (bots)
var live: Array = []  # every machine: [{e, t, secs, frame, cloud, streaks}]
var seen := 0  # every machine: tells drawn (bots)
var cloud_mesh: Mesh
var cloud_mat: StandardMaterial3D
var streak_mesh: BoxMesh
var streak_mat: StandardMaterial3D


func _ready() -> void:
	name = "Hazards"
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 10
	sm.rings = 5
	cloud_mesh = sm
	cloud_mat = main.color_mat(Deep.CLOUD_COLOR, 0.15)
	streak_mesh = BoxMesh.new()
	streak_mesh.size = Vector3(5.0, 0.18, 0.18)
	streak_mat = main.color_mat(Color(1.0, 1.0, 1.0), 1.2)


## Host: a new stage's events (none between stages).
func reset(new_list: Array) -> void:
	list = new_list.duplicate(true)
	told = {}
	hit = {}


## Host: the events whose tell starts now: Sunny (her middle at core, flying at speed) is warn seconds away.
func due(core: Vector3, speed: float, cruise: float, warn: float, delta: float) -> Array:
	var out: Array = []
	for i in told.keys():
		told[i] = float(told[i]) + delta
	for i in list.size():
		if told.has(i):
			continue
		var e: Dictionary = list[i]
		var to: Vector3 = (e.pos as Vector3) - core
		if to.dot(e.normal) > 0.0 and to.length() <= warn * maxf(speed, cruise):
			told[i] = 0.0
			fired[String(e.kind)] = int(fired.get(String(e.kind), 0)) + 1
			out.append(e)
	return out


## Host: the live events (told, gone off, not over) Sunny's middle just flew into, moving from `was` to `now`.
func hits(was: Vector3, now: Vector3, warn: float) -> Array:
	var out: Array = []
	for i in told.keys():
		var age := float(told[i])
		if hit.has(i) or age < warn - 0.25 or age > warn + Deep.STAY:
			continue
		var e: Dictionary = list[int(i)]
		if Deep.crossed(e, was, now):
			hit[i] = true
			out.append(e)
	return out


## The frame a tell stands in: its flat (x, z) plane faces Sunny (local y = the way she flies), x = sideways, z = up.
static func frame_of(e: Dictionary) -> Transform3D:
	var n: Vector3 = e.normal
	var side: Vector3 = e.side
	var up := side.cross(n).normalized()
	return Transform3D(Basis(side, n, up), e.pos)


## Every machine: draw the tell now; the event happens after `warn` seconds and stays Deep.STAY more.
func announce(e: Dictionary, warn: float) -> void:
	seen += 1
	var frame := Node3D.new()
	frame.name = "Tell_" + String(e.kind)
	add_child(frame)
	frame.global_transform = frame_of(e)
	var rings := WarnRings.new()
	var entry := {"e": e, "t": 0.0, "secs": warn, "frame": frame, "cloud": null, "streaks": []}
	match String(e.kind):
		"storm":  # (built before it joins the tree: the shapes sit in the frame's own plane)
			rings.shape("circle", Vector3.ZERO, Vector3.FORWARD, Vector2(float((e.size as Vector2).x), 0.0), Deep.STORM_COLOR, warn,
				{"style": "rings", "stay": Deep.STAY, "y": 0.0})
			var cloud := Node3D.new()
			for k in 7:
				var a := TAU * k / 6.0
				var m := MeshInstance3D.new()
				m.mesh = cloud_mesh
				m.material_override = cloud_mat
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var r := float((e.size as Vector2).x)
				if k == 6:
					m.scale = Vector3.ONE * r * 0.55
				else:
					m.position = Vector3(cos(a) * r * 0.45, 0.0, sin(a) * r * 0.3)
					m.scale = Vector3.ONE * r * (0.3 + 0.08 * (k % 3))
				cloud.add_child(m)
			cloud.scale = Vector3.ONE * 0.05
			frame.add_child(cloud)
			entry.cloud = cloud
			main.local_sound("thunder", -14.0, 1.4)
		"wind":
			var sz: Vector2 = e.size
			rings.shape("line", Vector3(-sz.x * 0.5, 0.0, 0.0), Vector3.RIGHT, sz, Deep.WIND_COLOR, warn,
				{"style": "disc", "stay": Deep.STAY, "alpha": 0.3, "y": 0.0})
			for k in STREAKS:
				var s := MeshInstance3D.new()
				s.mesh = streak_mesh
				s.material_override = streak_mat
				s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				s.position = Vector3(0.0, 0.6, (float(k) / (STREAKS - 1) - 0.5) * sz.y * 0.8)
				frame.add_child(s)
				(entry.streaks as Array).append(s)
			main.local_sound("whoosh", -8.0, 0.6)
	frame.add_child(rings)
	live.append(entry)


## Every machine: all gone (a new stage).
func clear() -> void:
	for en in live:
		if is_instance_valid(en.frame):
			(en.frame as Node).queue_free()
	live.clear()


## Bots: the tells showing now: [{kind, t (s since told), secs}].
func tells_now() -> Array:
	var out: Array = []
	for en in live:
		out.append({"kind": String(en.e.kind), "t": float(en.t), "secs": float(en.secs), "pos": en.e.pos})
	return out


func _process(delta: float) -> void:
	for i in range(live.size() - 1, -1, -1):
		var en: Dictionary = live[i]
		en.t = float(en.t) + delta
		var t := float(en.t)
		var secs := float(en.secs)
		if t > secs + Deep.STAY + 0.6 or not is_instance_valid(en.frame):
			if is_instance_valid(en.frame):
				(en.frame as Node).queue_free()
			live.remove_at(i)
			continue
		if en.cloud != null:  # the cloud puffs up while it is told, rumbles, then shrinks away
			var c: Node3D = en.cloud
			var grow := clampf(t / secs, 0.05, 1.0)
			var shrink := clampf((secs + Deep.STAY + 0.6 - t) / 0.6, 0.0, 1.0)
			c.scale = Vector3.ONE * grow * shrink
			c.rotation.y = t * 0.3
		var e: Dictionary = en.e
		var sz: Vector2 = e.size
		for k in (en.streaks as Array).size():  # the streaks blow sideways, the way the wind will push
			var s: Node3D = en.streaks[k]
			var along := fmod(t * 14.0 + k * 7.3, sz.x) - sz.x * 0.5
			s.position.x = along * float(e.sign)
			s.visible = t < secs + Deep.STAY


## Bots / main: the colour of a kind's tell (palette.gd reads Deep's).
static func color_of(kind: String) -> Color:
	return Deep.STORM_COLOR if kind == "storm" else Deep.WIND_COLOR
