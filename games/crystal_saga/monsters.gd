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
## saga-deep: the monsters wear the region's look (skins: e.g. frogs and ghosts in the fen, crabs on the dunes)
## and the giant is the region's CRYSTAL GUARDIAN (sagagen.gd guardian()): besides the STOMP it may make CRYSTAL
## RAIN (blue circles on the ground, then crystals drop there), ROLL (an orange lane, then he rolls down it and
## sits dizzy a moment: hits count extra then) or CALL helpers (green sparkle rings, then little slimes pop up).
## Every attack shows its tell first, for sagagen.gd's fair warn time; tells() are drawn on every machine.

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
var speed := 1.0  ## the journey's tier makes monsters a little quicker (sagagen.gd plan.speed)
var stomp_gap: Array = [4.5, 6.5]  ## seconds between the giant's stomps (plan.stomp)
var giant_look: Array = []  ## [body, glow] colours of this journey's giant (plan.giant)
var stomps: Array = []  ## host: [Vector3] stomps that happened this step
var windups: Array = []  ## host: [Vector3] wind-ups that started this step
var skins: Array = ["slime", "mushroom", "bat"]  ## Creatures kinds for SLIME, MUSHY, BAT (the region's look)
var guardian: Dictionary = {}  ## plan.guardian (sagagen.gd): attacks, warn, gap ... (empty = stomps only)
var new_tells: Array = []  ## host: tells that started this step: [attack, data (Array), warn]
var landed: Array = []  ## host: [attack, data] attacks that landed this step (rain, roll: effects)
var _tell_nodes: Array = []  ## every machine: [node, seconds left]
var _calls: Array = []  ## host: helpers to pop up after this step [Vector3]
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
			var fk := String(skins[2]) if skins.size() == 3 else "bat"
			node = Creatures.monster(fk, {"color": Color(0.55, 0.4, 0.8), "seed": id} if fk == "bat" else {"seed": id})
		MUSHY:
			var wk := String(skins[1]) if skins.size() == 3 else "mushroom"
			node = Creatures.monster(wk, {"color": Color(0.95, 0.35, 0.4), "seed": id} if wk == "mushroom" else {"seed": id})
		GIANT:
			var body_col: Color = giant_look[0] if giant_look.size() == 2 else Color(0.5, 0.45, 0.6)
			var glow_col: Color = giant_look[1] if giant_look.size() == 2 else Color(0.8, 0.4, 1.0)
			var inner := Creatures.monster("golem", {"color": body_col, "color2": glow_col, "boss": true})
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
			var hk := String(skins[0]) if skins.size() == 3 else "slime"
			node = Creatures.monster(hk, {"color": SLIME_COLORS[id % SLIME_COLORS.size()]} if hk == "slime" else {"seed": id})
			if hk != "slime":
				node.scale = Vector3.ONE * 0.8
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
		"stomp": 2.0, "wind": 0.0, "aura": aura, "ring": ring, "ice": 0.0, "atk": "", "atk_i": 0, "tell": [],
		"rest": 0.0, "roll": 0.0, "roll_to": p, "down": false, "minion": false}
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


## Host: ICE: a monster stands still (can't bump anyone) for `secs`.
func freeze(id: int, secs: float) -> void:
	if mons.has(id):
		mons[id]["ice"] = maxf(float(mons[id]["ice"]), secs)
		mons[id]["hop"] = 0.0
		mons[id]["wind"] = 0.0


func frozen(id: int) -> bool:
	return mons.has(id) and float(mons[id]["ice"]) > 0.0


## Host: a hit. Returns "poof" (gone), "hit" (the Giant's mist shrank) or "" (too soon again).
## power: how much the Giant's mist shrinks (the MIGHTY sword trick makes it more).
func hit(id: int, power: float = 1.0) -> String:
	if not mons.has(id):
		return ""
	var m: Dictionary = mons[id]
	if int(m["kind"]) != GIANT:
		remove(id)
		return "poof"
	if float(m["cd"]) > 0.0:
		return ""
	m["cd"] = 0.45
	if float(m["rest"]) > 0.0:
		power *= 1.5  # sitting dizzy after a roll: hits count extra
	m["hits"] = float(m["hits"]) + maxf(1.0, power)
	m["sz"] = maxf(0.0, 1.0 - float(m["hits"]) / float(giant_hits))
	m["anim"].hurt(Color(1, 1, 1))
	if float(m["hits"]) >= giant_hits - 0.01:
		remove(id)
		return "poof"
	return "hit"


## Host: move everyone. targets: Array of [Vector3 feet, key] (heroes, and the VR hero with key -1).
## Returns bumps: [id, key] for each monster touching a target (stomps add everyone in the ring).
func step(delta: float, targets: Array) -> Array:
	var bumps: Array = []
	stomps.clear()
	windups.clear()
	new_tells.clear()
	landed.clear()
	_calls.clear()
	for id in mons:
		var m: Dictionary = mons[id]
		var kind: int = m["kind"]
		var p: Vector3 = m["p"]
		m["cd"] = maxf(0.0, float(m["cd"]) - delta)
		var zone: int = m["zone"]
		if float(m["ice"]) > 0.0:
			m["ice"] = float(m["ice"]) - delta
			continue
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
			m["v"] = dir * (1.4 if kind == MUSHY else 1.7) * speed
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
	for cp in _calls:
		var mid := spawn(SLIME, cp)
		mons[mid]["minion"] = true
	return bumps


static func _zone_clamp(p: Vector3, zone: int, r: float) -> Vector3:
	var c := World.center(zone)
	return Vector3(clampf(p.x, -World.HALF_W + r, World.HALF_W - r), p.y,
		clampf(p.z, c.z - World.HALF_L + r + 0.5, c.z + World.HALF_L - r - 0.5))


func _giant(m: Dictionary, delta: float, best: Vector3, targets: Array, bumps: Array, id: int) -> void:
	var p: Vector3 = m["p"]
	var zone := int(m["zone"])
	if float(m["roll"]) > 0.0:  # rolling down the lane
		var left := float(m["roll"])
		var to: Vector3 = m["roll_to"]
		var step := minf(1.0, delta / left)
		m["p"] = p.lerp(to, step)
		m["roll"] = left - delta
		m["hop"] = 1.0
		return
	if float(m["rest"]) > 0.0:  # sitting dizzy after a roll
		m["rest"] = float(m["rest"]) - delta
		m["hop"] = 0.0
		return
	var wind: float = m["wind"]
	if wind > 0.0:
		wind -= delta
		m["wind"] = wind
		if wind <= 0.0:
			_land(m, targets, bumps, id)
		m["hop"] = 0.0
		return
	m["stomp"] = float(m["stomp"]) - delta
	if float(m["stomp"]) <= 0.0:
		var a := _next_attack(m, best, p)
		if a != "":
			m["stomp"] = randf_range(float(stomp_gap[0]), float(stomp_gap[1]))
			_start(m, a, best, targets, p, zone)
			return
	var moving := 0.0
	if best != Vector3.INF:
		var to2 := Vector3(best.x - p.x, 0.0, best.z - p.z)
		m["yaw"] = lerp_angle(float(m["yaw"]), atan2(to2.x, to2.z), 1.0 - exp(-3.0 * delta))
		if to2.length() > 2.2:
			p += to2.normalized() * 0.9 * speed * delta
			moving = 1.0
	m["p"] = _zone_clamp(p, zone, 1.2)
	m["hop"] = moving


func _attacks() -> Array:
	var a: Array = guardian.get("attacks", ["stomp"])
	return a if not a.is_empty() else ["stomp"]


func warn_of(a: String) -> float:
	var w: Dictionary = guardian.get("warn", {})
	return float(w.get(a, WIND_TIME))


## The next attack in turn that makes sense now ("" = none yet: nobody near enough to stomp, helpers full).
func _next_attack(m: Dictionary, best: Vector3, p: Vector3) -> String:
	if best == Vector3.INF:
		return ""
	var list := _attacks()
	for k in list.size():
		var a := String(list[(int(m["atk_i"]) + k) % list.size()])
		if a == "stomp" and best.distance_to(p) > STOMP_R + 1.5:
			continue
		if a == "call" and _minions() >= int(guardian.get("call_cap", 2)):
			continue
		m["atk_i"] = int(m["atk_i"]) + k + 1
		return a
	return ""


func _minions() -> int:
	var n := 0
	for id in mons:
		n += 1 if bool(mons[id]["minion"]) else 0
	return n


## Start an attack: its tell shows for warn seconds (host: new_tells for main to send to every machine).
func _start(m: Dictionary, a: String, best: Vector3, targets: Array, p: Vector3, zone: int) -> void:
	var w := warn_of(a)
	m["atk"] = a
	m["wind"] = w
	windups.append(p)
	var data: Array = []
	var c := World.center(zone)
	match a:
		"rain":
			var n := int(guardian.get("rain_n", 3))
			for tg in targets:
				if data.size() >= n:
					break
				var tp: Vector3 = tg[0]
				if World.zone_of(tp) == zone:
					data.append(_zone_clamp(Vector3(tp.x, 0.0, tp.z), zone, 0.6))
			while data.size() < n:
				var q := p + Vector3(randf_range(-3.5, 3.5), 0.0, randf_range(-3.5, 3.5))
				data.append(_zone_clamp(Vector3(q.x, 0.0, q.z), zone, 0.6))
		"roll":
			var dir := Vector3(best.x - p.x, 0.0, best.z - p.z)
			dir = dir.normalized() if dir.length() > 0.1 else Vector3(0.0, 0.0, 1.0)
			var to := _zone_clamp(p + dir * float(guardian.get("roll_len", 7.0)), zone, 1.2)
			to.y = 0.0
			data = [Vector3(p.x, 0.0, p.z), to]
			m["yaw"] = atan2(dir.x, dir.z)
		"call":
			var n2 := mini(int(guardian.get("call_n", 1)), int(guardian.get("call_cap", 2)) - _minions())
			for k in 8:
				if data.size() >= n2:
					break
				var ang := randf() * TAU
				var q2 := _zone_clamp(p + Vector3(cos(ang) * 2.6, 0.0, sin(ang) * 2.6), zone, 0.6)
				var clear := true
				for tg2 in targets:
					if Vector2((tg2[0] as Vector3).x - q2.x, (tg2[0] as Vector3).z - q2.z).length() < 1.6:
						clear = false
				if clear:
					q2.y = 0.0
					data.append(q2)
			if data.is_empty():
				data.append(_zone_clamp(c + Vector3(0.0, 0.0, -6.0), zone, 0.6))
	m["tell"] = data
	if a != "stomp":
		new_tells.append([a, data, w])
		show_tell(a, data, w)


## The attack lands (after its tell): bump everyone in it.
func _land(m: Dictionary, targets: Array, bumps: Array, id: int) -> void:
	var a := String(m["atk"])
	var p: Vector3 = m["p"]
	var data: Array = m["tell"]
	match a:
		"rain":
			var r := float(guardian.get("rain_r", 0.9))
			for spot in data:
				var sp: Vector3 = spot
				for tg in targets:
					var tp: Vector3 = tg[0]
					if Vector2(tp.x - sp.x, tp.z - sp.z).length() < r:
						bumps.append([id, tg[1]])
			landed.append([a, data])
		"roll":
			var a0: Vector3 = data[0]
			var a1: Vector3 = data[1]
			var hw := float(guardian.get("roll_w", 1.5)) * 0.5
			for tg2 in targets:
				var tp2: Vector3 = tg2[0]
				var flat := Vector3(tp2.x, 0.0, tp2.z)
				if Geometry3D.get_closest_point_to_segment(flat, a0, a1).distance_to(flat) < hw:
					bumps.append([id, tg2[1]])
			m["roll"] = 0.45
			m["roll_to"] = Vector3(a1.x, 0.0, a1.z)
			m["rest"] = float(guardian.get("roll_rest", 2.0))
			landed.append([a, data])
		"call":
			for spot2 in data:
				_calls.append(spot2)
			landed.append([a, data])
		_:
			stomps.append(p)
			for tg3 in targets:
				var tp3: Vector3 = tg3[0]
				if Vector2(tp3.x - p.x, tp3.z - p.z).length() < STOMP_R:
					bumps.append([id, tg3[1]])
	m["atk"] = ""


## Every machine: draw a tell on the ground for `secs`: blue circles (rain), an orange lane (roll), green sparkle
## rings (call). They grow brighter until the attack lands.
func show_tell(a: String, data: Array, secs: float) -> void:
	var b := MeshKit.Builder.new()
	var col: Color = TELL_COLORS.get(a, Color.WHITE)
	match a:
		"rain":
			var r := float(guardian.get("rain_r", 0.9))
			for spot in data:
				var sp: Vector3 = spot
				b.torus(r, 0.06, MeshKit.at(sp + Vector3(0.0, 0.06, 0.0)), col, 28, 4, true)
				b.cylinder(r * 0.95, r * 0.95, 0.02, MeshKit.at(sp + Vector3(0.0, 0.04, 0.0)), Color(col.r, col.g, col.b) * 0.6, 20, true)
				b.prism(6, 0.22, 0.8, MeshKit.at(sp + Vector3(0.0, 4.5, 0.0), Vector3.ONE, Vector3(PI, 0.0, 0.0)), col, true)
		"roll":
			var a0: Vector3 = data[0]
			var a1: Vector3 = data[1]
			var mid := (a0 + a1) * 0.5
			var d := a1 - a0
			var w := float(guardian.get("roll_w", 1.5))
			var xf := Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)), mid + Vector3(0.0, 0.05, 0.0))
			b.box(Vector3(w, 0.02, d.length()), xf, Color(col.r, col.g, col.b) * 0.7, true)
			var n := int(d.length() / 1.4)
			for k in n:
				var at := a0 + d * ((k + 0.7) / float(n + 0.5))
				b.cone(w * 0.35, 0.5, Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)) * Basis(Vector3.RIGHT, PI * 0.5), at + Vector3(0.0, 0.1, 0.0)), col, 3, true)
		"call":
			for spot2 in data:
				var sp2: Vector3 = spot2
				b.torus(0.55, 0.05, MeshKit.at(sp2 + Vector3(0.0, 0.06, 0.0)), col, 20, 4, true)
				b.star(4, 0.2, 0.08, 0.04, MeshKit.at(sp2 + Vector3(0.0, 0.5, 0.0)), col, true)
	var mi := MeshKit.instance(b.build(), false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_tell_nodes.append([mi, secs, secs, a])


const TELL_COLORS := {"stomp": Color(1.0, 0.5, 0.9), "rain": Color(0.45, 0.8, 1.0), "roll": Color(1.0, 0.6, 0.2),
	"call": Color(0.5, 1.0, 0.5)}


func clear_tells() -> void:
	for t in _tell_nodes:
		(t[0] as Node3D).queue_free()
	_tell_nodes.clear()


func _bat(m: Dictionary, delta: float, targets: Array) -> void:
	var c := World.center(int(m["zone"]))
	m["ang"] = float(m["ang"]) + delta * 0.6 * speed
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
	var keep: Array = []
	for t in _tell_nodes:
		var n0: Node3D = t[0]
		t[1] = float(t[1]) - delta
		if float(t[1]) <= 0.0:
			n0.queue_free()
			continue
		var k0 := 1.0 - float(t[1]) / float(t[2])
		n0.scale = Vector3(1.0, 1.0 + 0.6 * sin(k0 * TAU * 3.0) * 0.1, 1.0)
		n0.visible = k0 < 0.6 or fmod(k0 * 12.0, 1.0) < 0.75  # blinks faster near the end
		keep.append(t)
	_tell_nodes = keep
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
			var wind: float = m["wind"] if String(m["atk"]) in ["stomp", ""] else 0.0
			ring.visible = wind > 0.0
			if wind > 0.0:
				var k := clampf(1.0 - wind / warn_of("stomp"), 0.0, 1.0)
				ring.scale = Vector3.ONE * lerpf(0.5, STOMP_R, k)
				if not m["anim"].is_busy():
					m["anim"].play("cast", warn_of("stomp"))
			var down := float(m["rest"]) > 0.0 and float(m["roll"]) <= 0.0
			if down != bool(m["down"]):
				m["down"] = down
				if down:
					m["anim"].faint()
				else:
					m["anim"].revive()
			m["anim"].walk(0.9 if float(m["hop"]) > 0.0 and not down else 0.0)
			continue
		m["anim"].walk(1.5 if float(m["hop"]) > 0.0 or kind == BAT else 0.0)


# --- Network -------------------------------------------------------------------------------------

func pack() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for id in mons:
		var m: Dictionary = mons[id]
		var p: Vector3 = m["p"]
		out.append_array([float(id), float(m["kind"]), snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01),
			snappedf(float(m["yaw"]), 0.02), snappedf(float(m["sz"]), 0.01), float(m["hop"]) if int(m["kind"]) != GIANT else _giant_code(m)])
	return out


## The giant's last packed number: 2 + wind while a STOMP winds up (the ring), -rest while he sits dizzy, else hop.
static func _giant_code(m: Dictionary) -> float:
	if float(m["wind"]) > 0.0 and String(m["atk"]) == "stomp":
		return 2.0 + float(m["wind"])
	if float(m["rest"]) > 0.0 and float(m["roll"]) <= 0.0:
		return -maxf(0.05, float(m["rest"]))
	return float(m["hop"])


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
			m["rest"] = 0.0
		elif int(m["kind"]) == GIANT and h < 0.0:
			m["rest"] = -h
			m["wind"] = 0.0
			m["hop"] = 0.0
		else:
			if int(m["kind"]) == GIANT:
				m["rest"] = 0.0
			m["wind"] = 0.0
			m["hop"] = h
		i += 8
	for id in mons.keys():
		if not seen.has(id):
			remove(int(id))
