extends Node3D
## CRYSTAL SAGA road surprises (saga-deep2; sagagen.gd road()): falling and rolling things on the way, each TOLD
## first on the ground by the shared warning shapes (core/warn_rings.gd), for sagagen.gd's fair warn time:
##  - forest PINECONES (acorns in autumn, snow clumps in winter) / cave CRYSTAL DROPS: amber / aqua circles under
##    the heroes, then the thing drops out of the sky right on the circle;
##  - forest ROLLING LOG: an orange lane across the path, then a log rolls along it;
##  - cave BOULDER: a red lane down the path, then a boulder rolls along it.
## The host times them (host_step: only while a place is being fought through, never in its first seconds) and
## sends each tell to every machine (main.gd "hazard" event -> show()); a bump is a harmless "boing".

const WarnRings := preload("res://core/warn_rings.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const World := preload("res://games/crystal_saga/world.gd")
const Realm := preload("res://games/crystal_saga/realm.gd")

const DROP_FROM := 7.0  ## the falling things start this high
const FALL_SECS := 0.55  ## ... and take this long to land (they land as the tell ends)
const ROLL_SECS := 0.6  ## a log / boulder rolls the lane in this long (it crosses the middle as the tell ends)

var rings: WarnRings
var season := ""
var gem := Color(0.55, 1.0, 0.95)  ## the cave's gem colour (the crystal drops)
var tells_shown := {}  ## every machine: kind -> tells drawn (bots)
# Host
var timers := {}  ## zone -> seconds to the next surprise
var pending: Array = []  ## [kind, data, seconds left, size]
var new_tells: Array = []  ## this step: [kind, data, warn, size] (main sends them)
var landed: Array = []  ## this step: [kind, data] (main: sounds, sparkles)
var _fx: Array = []  ## every machine: {"node", "kind", "from", "to", "t", "end"}


func _ready() -> void:
	rings = WarnRings.new()
	add_child(rings)


func clear() -> void:
	timers.clear()
	pending.clear()
	if rings != null:
		rings.clear()
	for f in _fx:
		(f["node"] as Node3D).queue_free()
	_fx.clear()


## The plan's surprise in a zone ({} = none).
static func hazard_of(plan: Dictionary, zone: int) -> Dictionary:
	for h in (plan.get("road", {}) as Dictionary).get("hazards", []):
		if int(h.zone) == zone:
			return h
	return {}


## Host: time the zone's surprise (fighting: monsters are out in it) and land the told ones. targets: [feet, key].
## Returns the keys bumped this step.
func host_step(delta: float, plan: Dictionary, zone: int, fighting: bool, targets: Array) -> Array:
	new_tells.clear()
	landed.clear()
	var bumps: Array = []
	for i in range(pending.size() - 1, -1, -1):
		var pd: Array = pending[i]
		pd[2] = float(pd[2]) - delta
		if float(pd[2]) > 0.0:
			continue
		pending.remove_at(i)
		landed.append([pd[0], pd[1]])
		for tg in targets:
			if hits(String(pd[0]), pd[1], pd[3], tg[0]) and not bumps.has(tg[1]):
				bumps.append(tg[1])
	var h := hazard_of(plan, zone)
	if h.is_empty() or not fighting:
		return bumps
	if not timers.has(zone):
		timers[zone] = float(h.first)
	timers[zone] = float(timers[zone]) - delta
	if float(timers[zone]) > 0.0 or not pending.is_empty():
		return bumps
	var near: Array = []
	for tg2 in targets:
		if World.zone_of(tg2[0]) == zone:
			near.append(tg2[0])
	if near.is_empty():
		return bumps
	timers[zone] = randf_range(float(h.gap[0]), float(h.gap[1]))
	var data := aim(h, zone, near)
	var w := float(h.warn)
	pending.append([String(h.kind), data, w, h.size])
	new_tells.append([String(h.kind), data, w, h.size])
	show_tell(String(h.kind), data, w, h.size)
	return bumps


## Where a surprise lands: circles under the heroes (and near them), a log's lane across the path where a hero
## stands, a boulder's lane down the path through a hero.
static func aim(h: Dictionary, zone: int, near: Array) -> Array:
	var c := World.center(zone)
	var z_lo := c.z - World.HALF_L + 1.0
	var z_hi := c.z + World.HALF_L - 1.0
	var kind := String(h.kind)
	var s: Vector2 = h.size
	var who: Vector3 = near[randi() % near.size()]
	var out: Array = []
	match kind:
		"log":
			var z := clampf(who.z + randf_range(-0.3, 0.3), z_lo, z_hi)
			var side := -1.0 if randf() < 0.5 else 1.0
			out = [Vector3(side * s.x * 0.5, 0.0, z), Vector3(-side * s.x * 0.5, 0.0, z)]
		"boulder":
			var x := clampf(who.x + randf_range(-0.3, 0.3), -World.HALF_W + s.y * 0.5, World.HALF_W - s.y * 0.5)
			var mid := clampf(who.z, z_lo + s.x * 0.5, z_hi - s.x * 0.5)
			out = [Vector3(x, 0.0, mid - s.x * 0.5), Vector3(x, 0.0, mid + s.x * 0.5)]  # rolls from the far end towards the heroes
		_:
			var pool := near.duplicate()
			pool.shuffle()
			for k in int(h.n):
				var base: Vector3 = pool[k] if k < pool.size() else (who + Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0)))
				var p := base + Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
				out.append(Vector3(clampf(p.x, -World.HALF_W + s.x * 0.6, World.HALF_W - s.x * 0.6), 0.0, clampf(p.z, z_lo, z_hi)))
	return out


## Is a hero's feet in a surprise as it lands?
static func hits(kind: String, data: Array, size: Vector2, feet: Vector3) -> bool:
	var f := Vector3(feet.x, 0.0, feet.z)
	if kind in ["log", "boulder"]:
		var a0: Vector3 = data[0]
		var a1: Vector3 = data[1]
		return Geometry3D.get_closest_point_to_segment(f, a0, a1).distance_to(f) < size.y * 0.5
	for spot in data:
		if (spot as Vector3).distance_to(f) < size.x:
			return true
	return false


## Every machine: draw the tell, then drop / roll the thing so it arrives as the tell ends.
func show_tell(kind: String, data: Array, secs: float, size: Vector2) -> void:
	tells_shown[kind] = int(tells_shown.get(kind, 0)) + 1
	var col: Color = Realm.TELL_COLORS.get(kind, Color.WHITE)
	if kind in ["log", "boulder"]:
		var a0: Vector3 = data[0]
		var a1: Vector3 = data[1]
		rings.shape("line", a0, a1 - a0, Vector2(a0.distance_to(a1), size.y), col, secs, {"style": "flash", "alpha": 0.6})
		var n := MeshKit.instance(_log_mesh() if kind == "log" else _boulder_mesh(), false)
		n.visible = false
		add_child(n)
		var r := size.y * 0.4
		_fx.append({"node": n, "kind": kind, "from": a0 + Vector3(0.0, r, 0.0), "to": a1 + Vector3(0.0, r, 0.0), "t": 0.0,
			"start": secs - ROLL_SECS * 0.5, "end": secs + ROLL_SECS * 0.5})
		return
	for spot in data:
		rings.warn(spot, size.x, col, secs, 0.06, {"style": "disc"})
		var n2 := MeshKit.instance(_drop_mesh(kind), false)
		n2.visible = false
		add_child(n2)
		_fx.append({"node": n2, "kind": kind, "from": (spot as Vector3) + Vector3(0.0, DROP_FROM, 0.0), "to": (spot as Vector3) + Vector3(0.0, 0.15, 0.0),
			"t": 0.0, "start": secs - FALL_SECS, "end": secs})


func _process(delta: float) -> void:
	for i in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[i]
		f["t"] = float(f["t"]) + delta
		var n: Node3D = f["node"]
		var t := float(f["t"])
		var t0 := float(f["start"])
		var t1 := float(f["end"])
		if t < t0:
			continue
		n.visible = true
		var k := clampf((t - t0) / maxf(0.01, t1 - t0), 0.0, 1.0)
		if String(f["kind"]) in ["log", "boulder"]:
			n.position = (f["from"] as Vector3).lerp(f["to"], k)
			var d: Vector3 = (f["to"] as Vector3) - (f["from"] as Vector3)
			n.rotation.y = atan2(d.x, d.z)
			n.rotation.x = -k * 9.0
			if t > t1:
				n.scale = Vector3.ONE * maxf(0.01, 1.0 - (t - t1) * 3.0)
		else:
			n.position = (f["from"] as Vector3).lerp(f["to"], k * k)
			n.rotation.y += delta * 4.0
			if t > t1:
				n.scale = Vector3.ONE * maxf(0.01, 1.0 - (t - t1) * 2.0)
		if t > t1 + 0.5:
			n.queue_free()
			_fx.remove_at(i)


# --- Looks (built once) ----------------------------------------------------------------------------------

static var _meshes := {}


func _drop_mesh(kind: String) -> ArrayMesh:
	var key := kind + ("/" + season if kind == "cones" else "/" + gem.to_html())
	if _meshes.has(key):
		return _meshes[key]
	var b := MeshKit.Builder.new()
	if kind == "drips":
		b.prism(6, 0.18, 0.7, MeshKit.at(Vector3(0.0, 0.2, 0.0), Vector3.ONE, Vector3(PI, 0.0, 0.0)), gem, true)
		b.cone(0.18, 0.25, MeshKit.at(Vector3(0.0, -0.27, 0.0), Vector3.ONE, Vector3(PI, 0.0, 0.0)), gem.lightened(0.3), 6, true)
	elif season == "winter":  # a snow clump
		b.sphere(0.3, MeshKit.at(Vector3.ZERO), Color(0.97, 0.98, 1.0), 10)
		b.sphere(0.2, MeshKit.at(Vector3(0.18, 0.12, 0.05)), Color(0.94, 0.96, 1.0), 8)
	elif season == "autumn":  # an acorn
		b.ellipsoid(Vector3(0.2, 0.26, 0.2), MeshKit.at(Vector3(0.0, -0.05, 0.0)), Color(0.75, 0.5, 0.25), 10)
		b.dome(0.23, MeshKit.at(Vector3(0.0, 0.1, 0.0), Vector3(1.0, 0.7, 1.0)), Color(0.45, 0.3, 0.18), 10)
		b.cylinder(0.03, 0.03, 0.12, MeshKit.at(Vector3(0.0, 0.3, 0.0)), Color(0.4, 0.28, 0.16), 4)
	else:  # a pinecone: stacked scales
		for k in 5:
			var w := 0.2 - absf(k - 1.5) * 0.04
			b.cone(w, 0.16, MeshKit.at(Vector3(0.0, 0.2 - k * 0.11, 0.0), Vector3.ONE, Vector3(PI, 0.0, 0.0)), Color(0.55, 0.35, 0.2).lerp(Color(0.7, 0.48, 0.28), (k % 2) * 0.6), 8)
	_meshes[key] = b.build()
	return _meshes[key]


static func _log_mesh() -> ArrayMesh:
	if _meshes.has("log"):
		return _meshes["log"]
	var b := MeshKit.Builder.new()
	var side := Vector3(0.0, 0.0, PI * 0.5)
	b.cylinder(0.45, 0.45, 1.6, MeshKit.at(Vector3.ZERO, Vector3.ONE, side), Color(0.55, 0.36, 0.2), 12)
	for sx in [-0.81, 0.81]:
		b.cylinder(0.4, 0.4, 0.04, MeshKit.at(Vector3(sx, 0.0, 0.0), Vector3.ONE, side), Color(0.9, 0.75, 0.5), 12)
	b.sphere(0.12, MeshKit.at(Vector3(0.2, 0.45, 0.0)), Color(0.4, 0.7, 0.3), 6)
	_meshes["log"] = b.build()
	return _meshes["log"]


static func _boulder_mesh() -> ArrayMesh:
	if _meshes.has("boulder"):
		return _meshes["boulder"]
	var b := MeshKit.Builder.new()
	b.sphere(0.6, MeshKit.at(Vector3.ZERO, Vector3(1.0, 0.92, 1.0)), Color(0.55, 0.52, 0.56), 10)
	b.sphere(0.25, MeshKit.at(Vector3(0.35, 0.3, 0.2)), Color(0.6, 0.58, 0.62), 6)
	b.prism(6, 0.1, 0.35, MeshKit.at(Vector3(-0.3, 0.45, 0.1), Vector3.ONE, Vector3(0.0, 0.0, 0.4)), Color(0.6, 0.9, 1.0), true)
	_meshes["boulder"] = b.build()
	return _meshes["boulder"]
