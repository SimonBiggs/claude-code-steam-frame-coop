extends Node3D
## CRYSTAL SAGA: the cute monsters. The host simulates them; the TV machine mirrors the snapshot.
##  - SLIME and MUSHY (a walking mushroom): hop towards the nearest hero; a bump makes a TV hero
##    dizzy for a moment, and gives the VR hero a sparkly "boing" (no damage anywhere).
##  - BAT: flutters round the cave up high (the VR hero's sword and spells reach it) and now and then
##    swoops down low past the TV heroes.
##  - GIANT: the Stone Giant, big and grumpy inside a cloud of dark mist. He plods after the party and
##    now and then lifts his arms (a glowing ring grows on the ground) and STOMPS: everyone in the ring
##    gets bounced. Every hit shrinks the dark mist (that's his "health", no bar); when it is gone he
##    is friendly again (main.gd swaps him for the waving FRIEND prop).
## Any hit poofs a slime, mushy or bat at once.

const Creatures := preload("res://core/creatures.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const World := preload("res://games/crystal_saga/world.gd")

enum { SLIME, MUSHY, BAT, GIANT }
const GIANT_SCALE := 2.3
const STOMP_R := 3.4
const WIND_TIME := 1.3
const SLIME_COLORS: Array[Color] = [Color(0.45, 0.9, 0.45), Color(1.0, 0.55, 0.75), Color(0.45, 0.75, 1.0), Color(0.75, 0.55, 1.0)]

var mons := {}  ## id -> Dictionary
var next_id := 1
var giant_hits := 12  ## set by main for the party size
var stomps: Array = []  ## host: [Vector3] stomps that happened this step
var windups: Array = []  ## host: [Vector3] wind-ups that started this step
var _heights := {}
var _ring_mat: StandardMaterial3D


func clear() -> void:
	for id in mons:
		(mons[id]["node"] as Node3D).queue_free()
	mons.clear()


func count() -> int:
	return mons.size()


func spawn(kind: int, p: Vector3) -> int:
	var id := next_id
	next_id += 1
	_make(id, kind, p)
	return id


func _make(id: int, kind: int, p: Vector3) -> Dictionary:
	var node: Node3D
	var aura: MeshInstance3D = null
	var ring: MeshInstance3D = null
	match kind:
		BAT:
			node = Creatures.monster("bat", {"color": Color(0.55, 0.4, 0.8), "seed": id})
		MUSHY:
			node = Creatures.monster("mushroom", {"color": Color(0.95, 0.35, 0.4), "seed": id})
		GIANT:
			var inner := Creatures.monster("golem", {"color": Color(0.5, 0.45, 0.6), "color2": Color(0.8, 0.4, 1.0), "boss": true})
			inner.scale = Vector3.ONE * GIANT_SCALE
			node = Node3D.new()
			node.add_child(inner)
			aura = _aura_mesh()
			aura.position.y = 1.6
			node.add_child(aura)
			ring = _ring_mesh()
			ring.visible = false
			node.add_child(ring)
		_:
			node = Creatures.monster("slime", {"color": SLIME_COLORS[id % SLIME_COLORS.size()]})
	add_child(node)
	node.position = p
	var body: Node3D = node.get_child(0) if kind == GIANT else node
	var an: Variant = Creatures.anim(body)
	if kind == BAT:
		an.flying = true
	if not _heights.has(kind):
		_heights[kind] = maxf(0.3, Creatures.height_of(body) * (GIANT_SCALE if kind == GIANT else 1.0))
	var m := {"kind": kind, "zone": World.zone_of(p), "p": p, "v": Vector3.ZERO, "yaw": 0.0, "t": randf_range(0.3, 1.2),
		"hop": 0.0, "hits": 0, "node": node, "anim": an, "h": float(_heights[kind]), "sz": 1.0,
		"ang": randf() * TAU, "swoop": randf_range(2.0, 5.0), "dive": 0.0, "goal": p, "cd": 0.0,
		"stomp": 2.0, "wind": 0.0, "aura": aura, "ring": ring}
	mons[id] = m
	return m


func _aura_mesh() -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 14
	sm.rings = 7
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.35, 0.1, 0.5, 0.35)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * 2.2
	return mi


func _ring_mesh() -> MeshInstance3D:
	var b := MeshKit.Builder.new()
	b.torus(1.0, 0.06, Transform3D.IDENTITY, Color(1.0, 0.5, 0.9), 32, 4, true)
	var mi := MeshKit.instance(b.build(), false)
	mi.position.y = 0.05
	return mi


## Where to aim at a monster, and how big it is.
func center_of(id: int) -> Vector3:
	var m: Dictionary = mons[id]
	var h := float(m["h"])
	if int(m["kind"]) == BAT:
		return (m["node"] as Node3D).position + Vector3(0.0, h * 0.4, 0.0)
	return (m["node"] as Node3D).position + Vector3(0.0, h * 0.5, 0.0)


func radius_of(id: int) -> float:
	var m: Dictionary = mons[id]
	match int(m["kind"]):
		BAT:
			return 0.38
		GIANT:
			return 1.1
	return maxf(float(m["h"]) * 0.5, 0.32)


func remove(id: int) -> void:
	if mons.has(id):
		(mons[id]["node"] as Node3D).queue_free()
		mons.erase(id)


func giant_id() -> int:
	for id in mons:
		if int(mons[id]["kind"]) == GIANT:
			return int(id)
	return -1


## Host: a hit. Returns "poof" (gone), "hit" (the Giant's mist shrank) or "" (too soon again).
func hit(id: int) -> String:
	if not mons.has(id):
		return ""
	var m: Dictionary = mons[id]
	if int(m["kind"]) != GIANT:
		remove(id)
		return "poof"
	if float(m["cd"]) > 0.0:
		return ""
	m["cd"] = 0.45
	m["hits"] = int(m["hits"]) + 1
	m["sz"] = maxf(0.0, 1.0 - float(m["hits"]) / float(giant_hits))
	m["anim"].hurt(Color(1, 1, 1))
	if int(m["hits"]) >= giant_hits:
		remove(id)
		return "poof"
	return "hit"


## Host: move everyone. targets: Array of [Vector3 feet, key] (heroes, and the VR hero with key -1).
## Returns bumps: [id, key] for each monster touching a target (stomps add everyone in the ring).
func step(delta: float, targets: Array) -> Array:
	var bumps: Array = []
	stomps.clear()
	windups.clear()
	for id in mons:
		var m: Dictionary = mons[id]
		var kind: int = m["kind"]
		var p: Vector3 = m["p"]
		m["cd"] = maxf(0.0, float(m["cd"]) - delta)
		var zone: int = m["zone"]
		if kind == BAT:
			_bat(m, delta, targets)
			continue
		var best := Vector3.INF
		for tg in targets:
			var tp: Vector3 = tg[0]
			if World.zone_of(tp) == zone and (best == Vector3.INF or tp.distance_to(p) < best.distance_to(p)):
				best = tp
		if kind == GIANT:
			_giant(m, delta, best, targets, bumps, int(id))
			continue
		m["t"] = float(m["t"]) - delta
		var hop_len := 0.55
		if float(m["t"]) <= 0.0:
			m["t"] = randf_range(1.0, 1.9)
			var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			if best != Vector3.INF and randf() < 0.75:
				dir = Vector3(best.x - p.x, 0.0, best.z - p.z).normalized()
			m["v"] = dir * (1.4 if kind == MUSHY else 1.7)
			m["hop"] = hop_len
			m["yaw"] = atan2(dir.x, dir.z)
		var hop: float = m["hop"]
		var y := 0.0
		if hop > 0.0:
			hop = maxf(0.0, hop - delta)
			m["hop"] = hop
			p += (m["v"] as Vector3) * delta
			y = sin(PI * (1.0 - hop / hop_len)) * (0.15 if kind == MUSHY else 0.35)
		p = _zone_clamp(p, zone, 0.35)
		p.y = y
		m["p"] = p
		for tg in targets:
			var tp2: Vector3 = tg[0]
			if Vector2(tp2.x - p.x, tp2.z - p.z).length() < 0.55 and hop > 0.0:
				bumps.append([id, tg[1]])
				m["v"] = -(m["v"] as Vector3)
	return bumps


static func _zone_clamp(p: Vector3, zone: int, r: float) -> Vector3:
	var c := World.center(zone)
	return Vector3(clampf(p.x, -World.HALF_W + r, World.HALF_W - r), p.y,
		clampf(p.z, c.z - World.HALF_L + r + 0.5, c.z + World.HALF_L - r - 0.5))


func _giant(m: Dictionary, delta: float, best: Vector3, targets: Array, bumps: Array, id: int) -> void:
	var p: Vector3 = m["p"]
	var wind: float = m["wind"]
	if wind > 0.0:
		wind -= delta
		m["wind"] = wind
		if wind <= 0.0:
			stomps.append(p)
			for tg in targets:
				var tp: Vector3 = tg[0]
				if Vector2(tp.x - p.x, tp.z - p.z).length() < STOMP_R:
					bumps.append([id, tg[1]])
		m["hop"] = 0.0
		return
	m["stomp"] = float(m["stomp"]) - delta
	if float(m["stomp"]) <= 0.0 and best != Vector3.INF and best.distance_to(p) < STOMP_R + 1.5:
		m["stomp"] = randf_range(4.5, 6.5)
		m["wind"] = WIND_TIME
		windups.append(p)
		return
	var moving := 0.0
	if best != Vector3.INF:
		var to := Vector3(best.x - p.x, 0.0, best.z - p.z)
		m["yaw"] = lerp_angle(float(m["yaw"]), atan2(to.x, to.z), 1.0 - exp(-3.0 * delta))
		if to.length() > 2.2:
			p += to.normalized() * 0.9 * delta
			moving = 1.0
	m["p"] = _zone_clamp(p, int(m["zone"]), 1.2)
	m["hop"] = moving


func _bat(m: Dictionary, delta: float, targets: Array) -> void:
	var c := World.center(int(m["zone"]))
	m["ang"] = float(m["ang"]) + delta * 0.6
	var a: float = m["ang"]
	var home := c + Vector3(cos(a) * 3.4, 1.9 + 0.3 * sin(a * 3.0), sin(a) * 4.5)
	m["swoop"] = float(m["swoop"]) - delta
	var dive: float = m["dive"]
	if float(m["swoop"]) <= 0.0 and dive <= 0.0:
		m["swoop"] = randf_range(3.5, 6.0)
		var pick: Array = []
		for tg in targets:
			if World.zone_of(tg[0]) == int(m["zone"]):
				pick.append(tg[0])
		if not pick.is_empty():
			var g: Vector3 = pick[randi() % pick.size()]
			m["goal"] = g + Vector3(randf_range(-0.6, 0.6), 0.6, randf_range(-0.8, -0.3))
			m["dive"] = 2.6
			dive = 2.6
	var want := home
	if dive > 0.0:
		dive -= delta
		m["dive"] = dive
		want = home.lerp(m["goal"], sin(PI * clampf(1.0 - dive / 2.6, 0.0, 1.0)))
	var p: Vector3 = m["p"]
	var np := p.lerp(want, 1.0 - exp(-3.0 * delta))
	var d := np - p
	if Vector2(d.x, d.z).length() > 0.001:
		m["yaw"] = atan2(d.x, d.z)
	m["p"] = np


## Every machine: draw.
func animate(delta: float) -> void:
	for id in mons:
		var m: Dictionary = mons[id]
		var n: Node3D = m["node"]
		var target: Vector3 = m["p"]
		if n.position.distance_to(target) > 3.0:
			n.position = target
		else:
			n.position = n.position.lerp(target, 1.0 - exp(-18.0 * delta))
		n.rotation.y = lerp_angle(n.rotation.y, float(m["yaw"]), 1.0 - exp(-10.0 * delta))
		var kind: int = m["kind"]
		if kind == GIANT:
			var aura: MeshInstance3D = m["aura"]
			var want := 2.2 * (0.35 + 0.65 * float(m["sz"]))
			aura.scale = aura.scale.lerp(Vector3.ONE * want * (1.0 + 0.04 * sin(Time.get_ticks_msec() * 0.004)), 1.0 - exp(-6.0 * delta))
			var ring: MeshInstance3D = m["ring"]
			var wind: float = m["wind"]
			ring.visible = wind > 0.0
			if wind > 0.0:
				var k := 1.0 - wind / WIND_TIME
				ring.scale = Vector3.ONE * lerpf(0.5, STOMP_R, k)
				if not m["anim"].is_busy():
					m["anim"].play("cast", WIND_TIME)
			m["anim"].walk(0.9 if float(m["hop"]) > 0.0 else 0.0)
			continue
		m["anim"].walk(1.5 if float(m["hop"]) > 0.0 or kind == BAT else 0.0)


# --- Network -------------------------------------------------------------------------------------

func pack() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for id in mons:
		var m: Dictionary = mons[id]
		var p: Vector3 = m["p"]
		out.append_array([float(id), float(m["kind"]), snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01),
			snappedf(float(m["yaw"]), 0.02), snappedf(float(m["sz"]), 0.01), float(m["hop"]) if int(m["kind"]) != GIANT else (2.0 + float(m["wind"]) if float(m["wind"]) > 0.0 else float(m["hop"]))])
	return out


func unpack(a: PackedFloat32Array) -> void:
	var seen := {}
	var i := 0
	while i + 7 < a.size():
		var id := int(a[i])
		var p := Vector3(a[i + 2], a[i + 3], a[i + 4])
		seen[id] = true
		if not mons.has(id):
			_make(id, int(a[i + 1]), p)
		var m: Dictionary = mons[id]
		m["p"] = p
		m["yaw"] = a[i + 5]
		m["sz"] = a[i + 6]
		var h := a[i + 7]
		if int(m["kind"]) == GIANT and h >= 2.0:
			m["wind"] = h - 2.0
			m["hop"] = 0.0
		else:
			m["wind"] = 0.0
			m["hop"] = h
		i += 8
	for id in mons.keys():
		if not seen.has(id):
			remove(int(id))
