extends Node3D
## DUNGEON DELVE deep monsters (BRAVE / HEROIC). The host simulates them; other machines mirror the
## snapshot (pack / unpack) and draw the same tells. Every attack has a clear WIND-UP first (the
## monster flashes and a red "!" pops over its head; big attacks also glow on the floor), so kids can
## learn to read them:
##  - SLIME hops at you (a bump hurts).               - SPITTER keeps away and spits slow goo balls
##  - SHIELD bearer turns slowly: hits on its shield     (hit a ball back with a bonk / the sword!).
##    go TINK, so go round the back. It shoves.       - SWARM: little fast flyers, one hit each.
##  - HEALER hangs back and heals its friends (green glow first): get it first.
##  - MIMIC looks like a chest (a toothy one) and bites when you get close.
##  - CHARGER scrapes, a red lane shows where it'll run, then dashes; into a wall it gets dizzy.
##  - BOMBER lobs bombs: a red circle shows where it'll pop (bombs hurt monsters too).
##  - ELITES are bigger, gold-ringed and tougher.
## Bosses (one per zone, three phases each, they love to aim at the VR knight):
##  - SLIME KING: big jumps (a circle shows where he lands), goo fans, a royal goo ORB at the knight
##    (swing it back for big damage!), splits slimes off, then goo rain.
##  - BONE LORD: sword sweeps (a glowing fan in front), summons skeletons, bone ORBS; from phase 2 his
##    shield is up: hit him from behind. Bone rain.
##  - FORGE GOLEM: stomps (a ring), fire breath (a lane), charges (into a wall: dizzy, hit him!), lava
##    pools, magma ORBS.
## main/deep calls: deep.hurt(key, dmg, from, blockable), deep.hazard(...), deep.sound_at(...),
## deep.foe_died(id, m), deep.boss_phase(id, phase).

const FloorGen := preload("res://games/dungeon_delve/floorgen.gd")
const Creatures := preload("res://core/creatures.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const Tele := preload("res://games/dungeon_delve/tele.gd")

enum { IDLE, MOVE, WIND, ACT, STUN, SLEEP, RECOVER, FLY }
const BOSSES: Array[int] = [FloorGen.B_SLIME, FloorGen.B_BONE, FloorGen.B_FORGE]
const BOSS_NAMES := {FloorGen.B_SLIME: "SLIME KING", FloorGen.B_BONE: "BONE LORD", FloorGen.B_FORGE: "FORGE GOLEM"}
const BASE_HP := {FloorGen.F_SLIME: 2.0, FloorGen.F_SPITTER: 2.0, FloorGen.F_SHIELD: 4.0, FloorGen.F_SWARM: 1.0,
	FloorGen.F_HEALER: 3.0, FloorGen.F_MIMIC: 6.0, FloorGen.F_CHARGER: 4.0, FloorGen.F_BOMBER: 3.0,
	FloorGen.B_SLIME: 30.0, FloorGen.B_BONE: 42.0, FloorGen.B_FORGE: 54.0}
const GOLD := {FloorGen.F_SLIME: 1, FloorGen.F_SPITTER: 2, FloorGen.F_SHIELD: 3, FloorGen.F_SWARM: 1,
	FloorGen.F_HEALER: 3, FloorGen.F_MIMIC: 15, FloorGen.F_CHARGER: 4, FloorGen.F_BOMBER: 3,
	FloorGen.B_SLIME: 40, FloorGen.B_BONE: 60, FloorGen.B_FORGE: 80}

var deep: Node  ## host: the rules (deep.gd); null on mirrors
var f: Dictionary = {}
var zone := 0
var cfg := {"hp": 1.0, "dmg": 0, "spd": 1.0, "boss_hp": 1.0}  ## host scaling (deep.gd sets it per room)
var mons := {}  ## id -> Dictionary
var shots := {}  ## id -> {"kind", "p", "v", "t", "owner": foe id or -2 (reflected by players), "r"}
var next_id := 1
var next_shot := 1
var room_rects: Array = []  ## per room: walk rects for monsters (their own room only)
var obst: Array = []
var _heights := {}
var _bang_mesh: ArrayMesh
var _shot_meshes := {}
var _shot_nodes := {}
var _t := 0.0


func set_floor(fl: Dictionary) -> void:
	clear()
	f = fl
	zone = int(f["zone"]) % FloorGen.ZONES.size()
	room_rects.clear()
	for r in f["rooms"]:
		var c := FloorGen.cell_center((r as Dictionary)["cell"])
		room_rects.append([[c.x - FloorGen.HALF, c.z - FloorGen.HALF, c.x + FloorGen.HALF, c.z + FloorGen.HALF, 0]])
	obst = FloorGen.obstacle_rects(f)


func clear() -> void:
	for id in mons:
		(mons[id]["node"] as Node3D).queue_free()
	mons.clear()
	for id in _shot_nodes:
		(_shot_nodes[id] as Node3D).queue_free()
	_shot_nodes.clear()
	shots.clear()


func count_in(room: int) -> int:
	var n := 0
	for id in mons:
		if int(mons[id]["room"]) == room and int(mons[id]["st"]) != SLEEP:
			n += 1
	return n


func sleepers_in(room: int) -> int:
	var n := 0
	for id in mons:
		if int(mons[id]["room"]) == room and int(mons[id]["st"]) == SLEEP:
			n += 1
	return n


static func is_boss(kind: int) -> bool:
	return kind >= FloorGen.B_SLIME


func spawn(kind: int, p: Vector3, room: int, elite: bool = false) -> int:
	var id := next_id
	next_id += 1
	var m := _make(id, kind, p, room, elite)
	var hp: float = float(BASE_HP[kind]) * (float(cfg["boss_hp"]) if is_boss(kind) else float(cfg["hp"])) * (2.5 if elite else 1.0)
	m["hp"] = maxf(1.0, round(hp))
	m["max"] = m["hp"]
	if kind == FloorGen.F_MIMIC:
		m["st"] = SLEEP
	m["t"] = randf_range(0.4, 1.4)
	m["cd"] = randf_range(1.0, 2.5)
	return id


func _look(kind: int, id: int) -> Node3D:
	var z := zone
	match kind:
		FloorGen.F_SLIME:
			var cols: Array[Color] = [Color(0.45, 0.9, 0.45), Color(0.7, 0.5, 1.0), Color(1.0, 0.55, 0.25)]
			return Creatures.monster("slime", {"color": cols[z]})
		FloorGen.F_SPITTER:
			if z == 0:
				return Creatures.monster("frog", {"color": Color(0.55, 0.85, 0.35), "seed": id})
			if z == 1:
				return Creatures.monster("skeleton", {"weapon": "bow", "seed": id, "eye_color": Color(1.0, 0.6, 0.3)})
			return Creatures.monster("dragon", {"color": Color(1.0, 0.45, 0.25), "scale": 0.45, "seed": id})
		FloorGen.F_SHIELD:
			var n: Node3D
			if z == 0:
				n = Creatures.monster("crab", {"color": Color(1.0, 0.5, 0.4), "seed": id})
			elif z == 1:
				n = Creatures.monster("skeleton", {"weapon": "sword", "offhand": "none", "seed": id})
			else:
				n = Creatures.monster("robot", {"color": Color(0.6, 0.6, 0.7), "seed": id})
			n.add_child(_shield_node())
			return n
		FloorGen.F_SWARM:
			if z == 2:
				return Creatures.monster("bee", {"color": Color(1.0, 0.6, 0.2), "seed": id})
			return Creatures.monster("bat", {"color": Color(0.55, 0.4, 0.75) if z == 0 else Color(0.4, 0.4, 0.55), "seed": id})
		FloorGen.F_HEALER:
			if z == 0:
				return Creatures.monster("mushroom", {"color": Color(0.4, 0.9, 0.6), "seed": id})
			return Creatures.monster("ghost", {"color": Color(0.7, 1.0, 0.8) if z == 1 else Color(1.0, 0.85, 0.5), "seed": id})
		FloorGen.F_MIMIC:
			return Creatures.monster("mimic", {"seed": id})
		FloorGen.F_CHARGER:
			if z == 2:
				return Creatures.monster("golem", {"color": Color(0.55, 0.4, 0.35), "seed": id})
			return Creatures.monster("wolf", {"color": Color(0.55, 0.55, 0.6) if z == 0 else Color(0.45, 0.45, 0.6), "seed": id})
		FloorGen.F_BOMBER:
			return Creatures.monster("goblin", {"weapon": "none", "seed": id, "color": Color(0.5, 0.78, 0.35) if z != 2 else Color(0.85, 0.5, 0.35)})
		FloorGen.B_SLIME:
			return Creatures.monster("slime", {"color": Color(0.5, 0.85, 1.0), "boss": true, "scale": 1.5})
		FloorGen.B_BONE:
			var b := Creatures.monster("skeleton", {"boss": true, "weapon": "sword", "offhand": "none", "scale": 1.5, "eye_color": Color(0.6, 0.4, 1.0)})
			b.add_child(_shield_node(1.6))
			return b
		FloorGen.B_FORGE:
			return Creatures.monster("golem", {"boss": true, "color": Color(0.45, 0.32, 0.3), "eye_color": Color(1.0, 0.5, 0.1)})
	return Creatures.monster("slime", {})


## A big round shield in front of a monster (the "hit me from behind" tell).
func _shield_node(s: float = 1.0) -> Node3D:
	var b := MeshKit.Builder.new()
	b.cylinder(0.32, 0.32, 0.06, MeshKit.at(Vector3(0, 0, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.55, 0.6, 0.75), 14)
	b.torus(0.32, 0.035, MeshKit.at(Vector3(0, 0, 0.02), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.8, 0.3), 14, 4)
	b.sphere(0.07, MeshKit.at(Vector3(0, 0, 0.05)), Color(1.0, 0.8, 0.3), 8)
	var mi := MeshKit.instance(b.build(), false)
	mi.position = Vector3(0.0, 0.45, 0.42) * s
	mi.scale = Vector3.ONE * s
	mi.name = "Shield"
	return mi


func _bang() -> MeshInstance3D:
	if _bang_mesh == null:
		var b := MeshKit.Builder.new()
		b.box(Vector3(0.09, 0.26, 0.05), MeshKit.at(Vector3(0, 0.2, 0)), Color(1.0, 0.25, 0.2), true)
		b.box(Vector3(0.09, 0.09, 0.05), MeshKit.at(Vector3(0, -0.02, 0)), Color(1.0, 0.25, 0.2), true)
		_bang_mesh = b.build()
	var mi := MeshKit.instance(_bang_mesh, false)
	mi.visible = false
	return mi


func _make(id: int, kind: int, p: Vector3, room: int, elite: bool) -> Dictionary:
	var node := _look(kind, id)
	add_child(node)
	node.position = p
	var an: Variant = Creatures.anim(node)
	if kind == FloorGen.F_SWARM or kind == FloorGen.F_HEALER and zone > 0:
		an.flying = true
	if not _heights.has(kind):
		_heights[kind] = maxf(0.3, Creatures.height_of(node))
	var sz := 1.0
	if elite:
		sz = 1.35
	if kind == FloorGen.F_SWARM:
		sz = 0.75
	var bang := _bang()
	bang.position = Vector3(0.0, float(_heights[kind]) + 0.35, 0.0)
	node.add_child(bang)
	if elite:
		var rb := MeshKit.Builder.new()
		rb.torus(0.55, 0.05, Transform3D.IDENTITY, Color(1.0, 0.82, 0.25), 20, 4, true)
		var ring := MeshKit.instance(rb.build(), false)
		ring.position.y = 0.04
		node.add_child(ring)
	var m := {"kind": kind, "room": room, "p": p, "v": Vector3.ZERO, "yaw": randf() * TAU, "hp": 1.0, "max": 1.0,
		"elite": elite, "st": IDLE, "t": 0.5, "cd": 1.0, "hop": 0.0, "node": node, "anim": an, "bang": bang,
		"h": float(_heights[kind]), "sz": sz, "goal": p, "dir": Vector3.FORWARD, "hit": {}, "phase": 1, "pat": 0,
		"inv": 0.0, "kb": Vector3.ZERO, "frac": 1.0, "flash": 0.0, "fly": 0.0, "from": p, "to": p, "count": 0}
	if is_boss(kind):
		var bar := HudKit.bar3d(node, {"max": 1.0, "value": 1.0, "width": 1.6, "offset": Vector3(0, float(_heights[kind]) + 0.5, 0), "name": BOSS_NAMES[kind]})
		m["bar"] = bar
	mons[id] = m
	return m


func center_of(id: int) -> Vector3:
	var m: Dictionary = mons[id]
	var n: Node3D = m["node"]
	return n.position + Vector3(0.0, float(m["h"]) * float(m["sz"]) * 0.5, 0.0)


func radius_of(id: int) -> float:
	var m: Dictionary = mons[id]
	var r := float(m["h"]) * float(m["sz"]) * 0.45
	if is_boss(int(m["kind"])):
		return maxf(r, 0.9)
	return clampf(r, 0.3, 0.7)


func remove(id: int) -> void:
	if mons.has(id):
		(mons[id]["node"] as Node3D).queue_free()
		mons.erase(id)


# --- Host: damage -------------------------------------------------------------------------------

## Host: something hits monster id for dmg from world point `from`. Returns "kill", "hit", "block"
## (shield in the way), "" (nothing: asleep-proof or just hit). pierce = ignores shields (bombs).
func hit(id: int, dmg: float, from: Vector3, pierce: bool = false) -> String:
	if not mons.has(id):
		return ""
	var m: Dictionary = mons[id]
	if float(m["inv"]) > 0.0:
		return ""
	var kind: int = m["kind"]
	if kind == FloorGen.F_MIMIC and int(m["st"]) == SLEEP:
		_wake(m)
	if not pierce and _shield_blocks(m, from):
		m["inv"] = 0.12
		return "block"
	if int(m["st"]) == STUN:
		dmg *= 2.0
	m["hp"] = float(m["hp"]) - dmg
	m["inv"] = 0.12 if not is_boss(kind) else 0.18
	m["anim"].hurt(Color(1, 1, 1))
	if not is_boss(kind):
		var away := Vector3(m["p"]) - from
		away.y = 0.0
		m["kb"] = away.normalized() * (2.5 if kind != FloorGen.F_SHIELD else 1.0)
	if float(m["hp"]) <= 0.0:
		return "kill"
	if is_boss(kind):
		var frac := float(m["hp"]) / float(m["max"])
		var ph := 1 if frac > 0.66 else (2 if frac > 0.33 else 3)
		if ph > int(m["phase"]):
			m["phase"] = ph
			m["st"] = RECOVER
			m["t"] = 1.6
			m["inv"] = 1.6
			if deep != null:
				deep.boss_phase(id, ph)
	return "hit"


func _shield_blocks(m: Dictionary, from: Vector3) -> bool:
	var kind: int = m["kind"]
	var shielded := kind == FloorGen.F_SHIELD or (kind == FloorGen.B_BONE and int(m["phase"]) >= 2)
	if not shielded or int(m["st"]) == STUN:
		return false
	var p: Vector3 = m["p"]
	var to := Vector2(from.x - p.x, from.z - p.z)
	if to.length() < 0.05:
		return false
	var yaw: float = m["yaw"]
	var fwd := Vector2(sin(yaw), cos(yaw))
	return fwd.dot(to.normalized()) > 0.25


func heal(id: int, amount: float) -> void:
	if mons.has(id):
		var m: Dictionary = mons[id]
		m["hp"] = minf(float(m["max"]), float(m["hp"]) + amount)


func _wake(m: Dictionary) -> void:
	m["st"] = RECOVER
	m["t"] = 0.5
	m["anim"].play("jump", 0.5)
	if deep != null:
		deep.sound_at("chest", m["p"], 0.0, 0.7)
		deep.sound_at("boing", m["p"], -2.0, 0.6)


# --- Host: simulation ---------------------------------------------------------------------------

func _walk(m: Dictionary, step: Vector3, rad: float) -> void:
	var p: Vector3 = m["p"]
	var to := p + Vector3(step.x, 0.0, step.z)
	var room: int = m["room"]
	var np := FloorGen.clamp_move(room_rects[room], obst, p, to, rad)
	var want := Vector2(step.x, step.z).length()
	if want > 0.001 and Vector2(np.x - p.x, np.z - p.z).length() < want * 0.3 and int(m["st"]) != ACT:
		# Blocked by a pillar: follow its edge (keep turning the same way for a while).
		var side: float = m.get("side", 1.0)
		var turned := Vector3(-step.z, 0.0, step.x) * side
		var np2 := FloorGen.clamp_move(room_rects[room], obst, p, p + turned, rad)
		if Vector2(np2.x - p.x, np2.z - p.z).length() < want * 0.3:
			m["side"] = -side
		else:
			np = np2
	np.y = p.y
	m["p"] = np


func _bumped_wall(m: Dictionary, want: Vector3) -> bool:
	var p: Vector3 = m["p"]
	return Vector2(p.x - want.x, p.z - want.z).length() > 0.02


func _face(m: Dictionary, to: Vector3, rate: float, delta: float) -> void:
	var p: Vector3 = m["p"]
	var d := to - p
	if Vector2(d.x, d.z).length() < 0.01:
		return
	var want := atan2(d.x, d.z)
	var yaw: float = m["yaw"]
	var diff := wrapf(want - yaw, -PI, PI)
	m["yaw"] = yaw + clampf(diff, -rate * delta, rate * delta)


func _nearest(p: Vector3, targets: Array, room: int) -> Dictionary:
	var best := {}
	var bd := INF
	for t in targets:
		var tp: Vector3 = (t as Dictionary)["p"]
		if FloorGen.room_at(f, tp) != room:
			continue
		var d := Vector2(tp.x - p.x, tp.z - p.z).length()
		if d < bd:
			bd = d
			best = t
	return best


## Bosses like the knight: half the time they pick him when he's in the room.
func _boss_target(p: Vector3, targets: Array, room: int) -> Dictionary:
	var here: Array = []
	var knight := {}
	for t in targets:
		if FloorGen.room_at(f, (t as Dictionary)["p"]) == room:
			here.append(t)
			if bool((t as Dictionary)["knight"]):
				knight = t
	if here.is_empty():
		return {}
	if not knight.is_empty() and randf() < 0.55:
		return knight
	return here[randi() % here.size()]


func _wind(m: Dictionary, secs: float) -> void:
	m["st"] = WIND
	m["t"] = secs
	m["count"] = 0


## Host: one step. targets: Array of {"p": feet, "key": slot (-1 knight), "knight": bool}.
func step(delta: float, targets: Array, active_room: int) -> void:
	_t += delta
	for id in mons.keys():
		if not mons.has(id):
			continue
		var m: Dictionary = mons[id]
		m["inv"] = maxf(0.0, float(m["inv"]) - delta)
		var kb: Vector3 = m["kb"]
		if kb.length() > 0.05:
			_walk(m, kb * delta, radius_of(id) * 0.8)
			m["kb"] = kb.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))
		if int(m["room"]) != active_room and int(m["st"]) != SLEEP:
			continue  # monsters rest until their room's doors shut (sleeping mimics still watch)
		var spd: float = float(cfg["spd"]) * (1.15 if bool(m["elite"]) else 1.0)
		m["cd"] = float(m["cd"]) - delta
		m["t"] = float(m["t"]) - delta
		match int(m["kind"]):
			FloorGen.F_SLIME:
				_slime(id, m, delta, targets, spd)
			FloorGen.F_SPITTER:
				_spitter(id, m, delta, targets, spd)
			FloorGen.F_SHIELD:
				_shield(id, m, delta, targets, spd)
			FloorGen.F_SWARM:
				_swarm(id, m, delta, targets, spd)
			FloorGen.F_HEALER:
				_healer(id, m, delta, targets, spd)
			FloorGen.F_MIMIC:
				_mimic(id, m, delta, targets, spd)
			FloorGen.F_CHARGER:
				_charger(id, m, delta, targets, spd)
			FloorGen.F_BOMBER:
				_bomber(id, m, delta, targets, spd)
			FloorGen.B_SLIME:
				_boss_slime(id, m, delta, targets, spd)
			FloorGen.B_BONE:
				_boss_bone(id, m, delta, targets, spd)
			FloorGen.B_FORGE:
				_boss_forge(id, m, delta, targets, spd)
	_step_shots(delta, targets)


func _dmg(base: int, m: Dictionary) -> int:
	return base + int(cfg["dmg"]) + (1 if bool(m["elite"]) and base > 0 else 0)


func _touch(id: int, m: Dictionary, targets: Array, reach: float, dmg: int, once: bool) -> void:
	var p: Vector3 = m["p"]
	for t in targets:
		var tp: Vector3 = (t as Dictionary)["p"]
		var key: int = (t as Dictionary)["key"]
		if Vector2(tp.x - p.x, tp.z - p.z).length() < reach + radius_of(id) * 0.6:
			if once and (m["hit"] as Dictionary).has(key):
				continue
			if deep.hurt(key, _dmg(dmg, m), p, true) != "":
				(m["hit"] as Dictionary)[key] = true


func _slime(id: int, m: Dictionary, delta: float, targets: Array, spd: float) -> void:
	var hop: float = m["hop"]
	if float(m["t"]) <= 0.0 and hop <= 0.0:
		m["t"] = randf_range(0.8, 1.5) / spd
		var tg := _nearest(m["p"], targets, int(m["room"]))
		var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		if not tg.is_empty() and randf() < 0.85:
			var tp: Vector3 = tg["p"]
			dir = Vector3(tp.x - Vector3(m["p"]).x, 0.0, tp.z - Vector3(m["p"]).z).normalized()
		m["v"] = dir * 2.0 * spd
		m["yaw"] = atan2(dir.x, dir.z)
		m["hop"] = 0.55
		m["hit"] = {}
	if hop > 0.0:
		hop = maxf(0.0, hop - delta)
		m["hop"] = hop
		_walk(m, Vector3(m["v"]) * delta, radius_of(id) * 0.8)
		var p: Vector3 = m["p"]
		p.y = sin(PI * (1.0 - hop / 0.55)) * 0.35
		m["p"] = p
		_touch(id, m, targets, 0.45, 1, true)
	else:
		var p2: Vector3 = m["p"]
		p2.y = 0.0
		m["p"] = p2


func _keep_range(id: int, m: Dictionary, delta: float, tp: Vector3, near: float, far: float, speed: float) -> void:
	var p: Vector3 = m["p"]
	var to := Vector3(tp.x - p.x, 0.0, tp.z - p.z)
	var d := to.length()
	var dir := Vector3.ZERO
	if d < near:
		dir = -to.normalized()
	elif d > far:
		dir = to.normalized()
	else:
		var side := Vector3(-to.z, 0.0, to.x).normalized()
		dir = side * (1.0 if int(id) % 2 == 0 else -1.0) * 0.4
	_walk(m, dir * speed * delta, radius_of(id) * 0.8)


func _spitter(id: int, m: Dictionary, delta: float, targets: Array, spd: float) -> void:
	var tg := _nearest(m["p"], targets, int(m["room"]))
	if tg.is_empty():
		return
	var tp: Vector3 = tg["p"]
	var st: int = m["st"]
	if st == WIND:
		_face(m, tp, 6.0, delta)
		if float(m["t"]) <= 0.0:
			var p: Vector3 = m["p"]
			var from := p + Vector3(0.0, 0.6, 0.0)
			var aim := (tp + Vector3(0.0, 0.7, 0.0) - from).normalized()
			shoot("ball", from, aim * (5.0 + zone * 0.6) * spd, id)
			deep.sound_at("spit" if zone != 1 else "bow", p, -2.0, 1.1)
			m["st"] = IDLE
			m["cd"] = randf_range(2.2, 3.2) / spd
		return
	_face(m, tp, 5.0, delta)
	_keep_range(id, m, delta, tp, 3.5, 6.5, 1.5 * spd)
	if float(m["cd"]) <= 0.0:
		_wind(m, 0.8)


func _shield(id: int, m: Dictionary, delta: float, targets: Array, spd: float) -> void:
	var tg := _nearest(m["p"], targets, int(m["room"]))
	if tg.is_empty():
		return
	var tp: Vector3 = tg["p"]
	var p: Vector3 = m["p"]
	var st: int = m["st"]
	match st:
		WIND:
			if float(m["t"]) <= 0.0:
				m["st"] = ACT
				m["t"] = 0.28
				m["hit"] = {}
				deep.sound_at("whoosh", p, -2.0, 0.8)
		ACT:
			var yaw: float = m["yaw"]
			_walk(m, Vector3(sin(yaw), 0.0, cos(yaw)) * 6.5 * delta, radius_of(id) * 0.8)
			_touch(id, m, targets, 0.6, 1, true)
			if float(m["t"]) <= 0.0:
				m["st"] = RECOVER
				m["t"] = 0.9
		RECOVER:
			if float(m["t"]) <= 0.0:
				m["st"] = MOVE
		_:
			_face(m, tp, 1.5 * spd, delta)
			var yaw2: float = m["yaw"]
			var fwd := Vector3(sin(yaw2), 0.0, cos(yaw2))
			var d := Vector2(tp.x - p.x, tp.z - p.z).length()
			if d > 1.3:
				_walk(m, fwd * 1.3 * spd * delta, radius_of(id) * 0.8)
			var facing := fwd.dot(Vector3(tp.x - p.x, 0.0, tp.z - p.z).normalized())
			if d < 1.9 and facing > 0.8 and float(m["cd"]) <= 0.0:
				_wind(m, 0.7)
				m["cd"] = 2.2 / spd


func _swarm(id: int, m: Dictionary, delta: float, targets: Array, spd: float) -> void:
	var tg := _nearest(m["p"], targets, int(m["room"]))
	var p: Vector3 = m["p"]
	var want := p
	if not tg.is_empty():
		var tp: Vector3 = tg["p"]
		want = tp + Vector3(sin(_t * 3.0 + id) * 1.2, 0.0, cos(_t * 2.3 + id) * 1.2)
		if float(m["cd"]) <= 0.0:
			want = tp
	var v: Vector3 = m["v"]
	var to := Vector3(want.x - p.x, 0.0, want.z - p.z)
	v = v.lerp(to.normalized() * 3.4 * spd, 1.0 - exp(-3.0 * delta))
	m["v"] = v
	_walk(m, v * delta, 0.3)
	var np: Vector3 = m["p"]
	np.y = 0.75 + 0.2 * sin(_t * 5.0 + id)
	m["p"] = np
	if v.length() > 0.1:
		m["yaw"] = atan2(v.x, v.z)
	if float(m["cd"]) <= 0.0 and not tg.is_empty():
		var tp2: Vector3 = tg["p"]
		if Vector2(tp2.x - np.x, tp2.z - np.z).length() < 0.6:
			if deep.hurt(int(tg["key"]), _dmg(1, m), np, true) != "":
				m["cd"] = 1.6
				m["v"] = -v
			else:
				m["cd"] = 0.5


func _healer(id: int, m: Dictionary, delta: float, targets: Array, spd: float) -> void:
	var p: Vector3 = m["p"]
	var room: int = m["room"]
	var st: int = m["st"]
	if st == WIND:
		if float(m["t"]) <= 0.0:
			var healed := 0
			for oid in mons:
				if int(oid) == id or int(mons[oid]["room"]) != room or is_boss(int(mons[oid]["kind"])):
					continue
				var om: Dictionary = mons[oid]
				if Vector3(om["p"]).distance_to(p) < 6.0 and float(om["hp"]) < float(om["max"]):
					heal(int(oid), 2.0)
					healed += 1
					deep.heal_fx(center_of(int(oid)))
			deep.sound_at("heal", p, -2.0)
			m["st"] = IDLE
			m["cd"] = randf_range(4.0, 5.0) / spd
		return
	# Stay behind friends, away from heroes.
	var tg := _nearest(p, targets, room)
	var friends := Vector3.ZERO
	var nf := 0
	for oid in mons:
		if int(oid) != id and int(mons[oid]["room"]) == room:
			friends += Vector3(mons[oid]["p"])
			nf += 1
	var dir := Vector3.ZERO
	if not tg.is_empty():
		var tp: Vector3 = tg["p"]
		var away := Vector3(p.x - tp.x, 0.0, p.z - tp.z)
		if away.length() < 4.0:
			dir += away.normalized()
		_face(m, tp, 4.0, delta)
	if nf > 0:
		var fc := friends / nf
		var to := Vector3(fc.x - p.x, 0.0, fc.z - p.z)
		if to.length() > 2.5:
			dir += to.normalized() * 0.7
	_walk(m, dir.limit_length(1.0) * 1.6 * spd * delta, radius_of(id) * 0.8)
	var np: Vector3 = m["p"]
	if zone > 0:
		np.y = 0.3 + 0.1 * sin(_t * 2.0 + id)
		m["p"] = np
	if float(m["cd"]) <= 0.0:
		var needs := false
		for oid in mons:
			if int(oid) != id and int(mons[oid]["room"]) == room and float(mons[oid]["hp"]) < float(mons[oid]["max"]):
				needs = true
		if needs:
			_wind(m, 1.2)
		else:
			m["cd"] = 1.0


func _mimic(id: int, m: Dictionary, delta: float, targets: Array, spd: float) -> void:
	var p: Vector3 = m["p"]
	var st: int = m["st"]
	var tg := _nearest(p, targets, int(m["room"]))
	if st == SLEEP:
		if not tg.is_empty() and Vector3(tg["p"]).distance_to(Vector3(p.x, 0.0, p.z)) < 2.0:
			_wake(m)
		return
	if tg.is_empty():
		return
	var tp: Vector3 = tg["p"]
	match st:
		WIND:
			_face(m, tp, 3.0, delta)
			if float(m["t"]) <= 0.0:
				m["st"] = ACT
				m["t"] = 0.3
				m["hit"] = {}
				deep.sound_at("chest", p, -2.0, 0.6)
		ACT:
			var yaw: float = m["yaw"]
			_walk(m, Vector3(sin(yaw), 0.0, cos(yaw)) * 5.5 * delta, radius_of(id) * 0.8)
			_touch(id, m, targets, 0.55, 1, true)
			if float(m["t"]) <= 0.0:
				m["st"] = RECOVER
				m["t"] = 0.8
		RECOVER:
			if float(m["t"]) <= 0.0:
				m["st"] = MOVE
		_:
			_face(m, tp, 5.0, delta)
			var to := Vector3(tp.x - p.x, 0.0, tp.z - p.z)
			if to.length() > 1.2:
				_walk(m, to.normalized() * 2.5 * spd * delta, radius_of(id) * 0.8)
			elif float(m["cd"]) <= 0.0:
				_wind(m, 0.5)
				m["cd"] = 1.4


func _charger(id: int, m: Dictionary, delta: float, targets: Array, spd: float) -> void:
	var p: Vector3 = m["p"]
	var st: int = m["st"]
	match st:
		WIND:
			if float(m["t"]) <= 0.0:
				m["st"] = ACT
				m["t"] = 0.8
				m["hit"] = {}
				deep.sound_at("whoosh", p, 0.0, 0.6)
		ACT:
			var dir: Vector3 = m["dir"]
			var want := p + dir * 9.0 * spd * delta
			_walk(m, dir * 9.0 * spd * delta, radius_of(id) * 0.8)
			_touch(id, m, targets, 0.6, 1, true)
			if _bumped_wall(m, want):
				m["st"] = STUN
				m["t"] = 2.2
				deep.sound_at("crash", p, -2.0, 0.8)
				deep.shake(0.3)
			elif float(m["t"]) <= 0.0:
				m["st"] = RECOVER
				m["t"] = 0.9
		STUN, RECOVER:
			if float(m["t"]) <= 0.0:
				m["st"] = MOVE
				m["cd"] = randf_range(1.5, 2.5) / spd
		_:
			var tg := _nearest(p, targets, int(m["room"]))
			if tg.is_empty():
				return
			var tp: Vector3 = tg["p"]
			_face(m, tp, 4.0, delta)
			_keep_range(id, m, delta, tp, 2.5, 5.5, 1.4 * spd)
			if float(m["cd"]) <= 0.0:
				_wind(m, 1.0 / maxf(0.8, spd))
				var dir2 := Vector3(tp.x - p.x, 0.0, tp.z - p.z).normalized()
				m["dir"] = dir2
				m["yaw"] = atan2(dir2.x, dir2.z)
				deep.telegraph("line", p, dir2, Vector2(7.2 * spd, 1.1), float(m["t"]))
				deep.sound_at("footstep", p, 0.0, 0.6)


func _bomber(id: int, m: Dictionary, delta: float, targets: Array, spd: float) -> void:
	var tg := _nearest(m["p"], targets, int(m["room"]))
	if tg.is_empty():
		return
	var tp: Vector3 = tg["p"]
	var p: Vector3 = m["p"]
	if int(m["st"]) == WIND:
		_face(m, tp, 6.0, delta)
		if float(m["t"]) <= 0.0:
			var land := tp + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
			land = FloorGen.room_clamp(f, int(m["room"]), land, 0.5)
			lob("bomb", p + Vector3(0.0, 1.0, 0.0), land, 0.7, id)
			deep.hazard("circle", land, Vector3.ZERO, Vector2(1.5, 0.0), 1.7, 0.3, _dmg(1, m), true)
			deep.sound_at("whoosh", p, -4.0, 1.3)
			m["st"] = IDLE
			m["cd"] = randf_range(3.0, 4.0) / spd
		return
	_face(m, tp, 5.0, delta)
	_keep_range(id, m, delta, tp, 4.0, 6.5, 1.5 * spd)
	if float(m["cd"]) <= 0.0:
		_wind(m, 0.6)


# --- Bosses -------------------------------------------------------------------------------------

func _boss_slime(id: int, m: Dictionary, delta: float, targets: Array, spd: float) -> void:
	var p: Vector3 = m["p"]
	var room: int = m["room"]
	var ph: int = m["phase"]
	var fast := 1.0 + 0.2 * (ph - 1)
	var st: int = m["st"]
	match st:
		FLY:
			var k := 1.0 - clampf(float(m["t"]) / float(m["fly"]), 0.0, 1.0)
			var a: Vector3 = m["from"]
			var b: Vector3 = m["to"]
			var np := a.lerp(b, k)
			np.y = sin(PI * k) * 3.0
			m["p"] = np
			if float(m["t"]) <= 0.0:
				m["p"] = Vector3(b.x, 0.0, b.z)
				deep.sound_at("crash", b, 0.0, 0.6)
				deep.shake(0.6)
				if ph >= 2:
					for k2 in 2:
						var sp := FloorGen.room_clamp(f, room, b + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0)), 0.6)
						spawn(FloorGen.F_SLIME, sp, room)
				m["st"] = RECOVER
				m["t"] = 1.3 / fast
		WIND:
			if float(m["t"]) <= 0.0:
				_boss_slime_attack(id, m, targets, ph)
		RECOVER:
			if float(m["t"]) <= 0.0:
				m["st"] = MOVE
				m["t"] = randf_range(1.2, 2.2) / fast
		ACT:
			if float(m["t"]) <= 0.0:
				m["st"] = RECOVER
				m["t"] = 0.8
		_:
			# Hop about towards someone, then pick an attack.
			var tg := _nearest(p, targets, room)
			if not tg.is_empty():
				var tp: Vector3 = tg["p"]
				_face(m, tp, 3.0, delta)
				var to := Vector3(tp.x - p.x, 0.0, tp.z - p.z)
				if to.length() > 2.5:
					_walk(m, to.normalized() * 1.2 * spd * delta, 1.0)
			p = m["p"]
			p.y = absf(sin(_t * 4.0)) * 0.25
			m["p"] = p
			if float(m["t"]) <= 0.0:
				var pats: Array = ["jump", "spit", "jump"]
				if ph >= 2:
					pats.append("orb")
				if ph >= 3:
					pats.append("rain")
					pats.append("orb")
				m["next"] = pats[int(m["pat"]) % pats.size()]
				m["pat"] = int(m["pat"]) + 1 + randi() % 2
				_wind(m, (0.9 if String(m["next"]) == "orb" else 0.7) / fast)
				deep.sound_at("boing", p, 0.0, 0.5)


func _boss_slime_attack(id: int, m: Dictionary, targets: Array, ph: int) -> void:
	var p: Vector3 = m["p"]
	var room: int = m["room"]
	var tg := _boss_target(p, targets, room)
	var tp: Vector3 = p + Vector3(0, 0, 1) if tg.is_empty() else Vector3(tg["p"])
	match String(m.get("next", "jump")):
		"jump":
			var land := FloorGen.room_clamp(f, room, Vector3(tp.x, 0.0, tp.z), 1.3)
			var fly := 1.25 - 0.1 * (ph - 1)
			deep.hazard("circle", land, Vector3.ZERO, Vector2(2.1, 0.0), fly, 0.3, _dmg(2, m), false)
			m["st"] = FLY
			m["t"] = fly
			m["fly"] = fly
			m["from"] = p
			m["to"] = land
			deep.sound_at("jump", p, 0.0, 0.5)
		"spit":
			var n := 3 if ph < 3 else 5
			var aim := Vector3(tp.x - p.x, 0.0, tp.z - p.z).normalized()
			for k in n:
				var a := (k - (n - 1) * 0.5) * 0.32
				shoot("ball", p + Vector3(0.0, 1.0, 0.0), aim.rotated(Vector3.UP, a) * 5.5, id)
			deep.sound_at("spit", p, 0.0, 0.7)
			m["st"] = ACT
			m["t"] = 0.4
		"orb":
			var from := p + Vector3(0.0, 1.6, 0.0)
			var head := tp + Vector3(0.0, 1.3 if tg.is_empty() or bool(tg["knight"]) else 0.7, 0.0)
			if not tg.is_empty() and bool(tg["knight"]):
				head = deep.knight_head()
			shoot("orb", from, (head - from).normalized() * 3.6, id)
			deep.sound_at("magic", p, 0.0, 0.6)
			m["st"] = ACT
			m["t"] = 0.6
		"rain":
			for k in 6:
				var c := FloorGen.room_center(f, room) + Vector3(randf_range(-4.5, 4.5), 0.0, randf_range(-4.5, 4.5))
				deep.hazard("circle", c, Vector3.ZERO, Vector2(1.1, 0.0), 1.5 + k * 0.15, 0.25, _dmg(1, m), false)
			deep.sound_at("bubbles", p, 0.0)
			m["st"] = ACT
			m["t"] = 1.4


func _boss_bone(id: int, m: Dictionary, delta: float, targets: Array, spd: float) -> void:
	var p: Vector3 = m["p"]
	var room: int = m["room"]
	var ph: int = m["phase"]
	var fast := 1.0 + 0.18 * (ph - 1)
	var st: int = m["st"]
	match st:
		WIND:
			if float(m["t"]) <= 0.0:
				_boss_bone_attack(id, m, targets, ph)
		ACT:
			if int(m["count"]) > 0 and float(m["t"]) <= 0.0:
				# More bone orbs in a row.
				m["count"] = int(m["count"]) - 1
				var tg := _boss_target(p, targets, room)
				if not tg.is_empty():
					var from := p + Vector3(0.0, 1.9, 0.0)
					var head: Vector3 = deep.knight_head() if bool(tg["knight"]) else Vector3(tg["p"]) + Vector3(0.0, 0.7, 0.0)
					shoot("orb", from, (head - from).normalized() * 3.8, id)
					deep.sound_at("magic", p, -2.0, 0.8)
				m["t"] = 0.6
			elif float(m["t"]) <= 0.0:
				m["st"] = RECOVER
				m["t"] = 1.0 / fast
		RECOVER:
			if float(m["t"]) <= 0.0:
				m["st"] = MOVE
				m["t"] = randf_range(1.0, 2.0) / fast
		_:
			var tg2 := _nearest(p, targets, room)
			if not tg2.is_empty():
				var tp: Vector3 = tg2["p"]
				_face(m, tp, 1.1 * fast, delta)
				var to := Vector3(tp.x - p.x, 0.0, tp.z - p.z)
				if to.length() > 2.2:
					var yaw: float = m["yaw"]
					_walk(m, Vector3(sin(yaw), 0.0, cos(yaw)) * 1.2 * spd * delta, 0.9)
			if float(m["t"]) <= 0.0:
				var pats: Array = ["sweep", "orbs", "sweep", "summon"]
				if ph >= 3:
					pats = ["sweep", "rain", "orbs", "sweep", "summon", "rain"]
				m["next"] = pats[int(m["pat"]) % pats.size()]
				m["pat"] = int(m["pat"]) + 1
				var w := {"sweep": 1.0, "orbs": 0.9, "summon": 1.2, "rain": 1.0}
				_wind(m, float(w[String(m["next"])]) / fast)
				deep.sound_at("dice", p, 0.0, 0.5)
				if String(m["next"]) == "sweep":
					var tg3 := _nearest(p, targets, room)
					var dir := Vector3(sin(float(m["yaw"])), 0.0, cos(float(m["yaw"])))
					if not tg3.is_empty():
						dir = (Vector3(tg3["p"]) - p).normalized()
						dir.y = 0.0
						m["yaw"] = atan2(dir.x, dir.z)
					m["dir"] = dir
					deep.hazard("sector", p, dir, Vector2(3.6, 1.0), float(m["t"]), 0.25, _dmg(2, m), false)


func _boss_bone_attack(id: int, m: Dictionary, targets: Array, ph: int) -> void:
	var p: Vector3 = m["p"]
	var room: int = m["room"]
	match String(m.get("next", "sweep")):
		"sweep":
			m["anim"].play("attack", 0.5)
			deep.sound_at("sword", p, 0.0, 0.6)
			m["st"] = RECOVER
			m["t"] = 0.9
		"orbs":
			m["st"] = ACT
			m["count"] = 3 if ph < 3 else 4
			m["t"] = 0.0
		"summon":
			var n := 2 if ph < 3 else 3
			for k in n:
				var sp := FloorGen.room_clamp(f, room, p + Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0)), 0.8)
				spawn(FloorGen.F_SHIELD if k % 2 == 0 else FloorGen.F_SPITTER, sp, room)
				deep.poof(sp + Vector3(0, 0.5, 0), Color(0.7, 0.6, 1.0), 20)
			deep.sound_at("magic", p, 0.0, 0.5)
			m["anim"].play("cast", 0.8)
			m["st"] = RECOVER
			m["t"] = 1.0
		"rain":
			for k in 7:
				var c := FloorGen.room_center(f, room) + Vector3(randf_range(-4.5, 4.5), 0.0, randf_range(-4.5, 4.5))
				deep.hazard("circle", c, Vector3.ZERO, Vector2(1.0, 0.0), 1.4 + k * 0.12, 0.25, _dmg(1, m), false)
			m["anim"].play("cast", 0.8)
			m["st"] = RECOVER
			m["t"] = 1.2


func _boss_forge(id: int, m: Dictionary, delta: float, targets: Array, spd: float) -> void:
	var p: Vector3 = m["p"]
	var room: int = m["room"]
	var ph: int = m["phase"]
	var fast := 1.0 + 0.18 * (ph - 1)
	var st: int = m["st"]
	match st:
		WIND:
			if float(m["t"]) <= 0.0:
				_boss_forge_attack(id, m, targets, ph)
		ACT:
			if String(m.get("next", "")) == "charge":
				var dir: Vector3 = m["dir"]
				var want := p + dir * 10.0 * delta
				_walk(m, dir * 10.0 * delta, 1.0)
				_touch(id, m, targets, 0.9, 2, true)
				if _bumped_wall(m, want):
					m["st"] = STUN
					m["t"] = 3.0
					deep.sound_at("crash", p, 2.0, 0.5)
					deep.shake(1.0)
					deep.boss_stunned(id)
					return
			if float(m["t"]) <= 0.0:
				m["st"] = RECOVER
				m["t"] = 1.0 / fast
		STUN, RECOVER:
			if float(m["t"]) <= 0.0:
				m["st"] = MOVE
				m["t"] = randf_range(1.2, 2.0) / fast
		_:
			var tg := _nearest(p, targets, room)
			if not tg.is_empty():
				var tp: Vector3 = tg["p"]
				_face(m, tp, 1.6, delta)
				var to := Vector3(tp.x - p.x, 0.0, tp.z - p.z)
				if to.length() > 2.6:
					_walk(m, to.normalized() * 1.0 * spd * delta, 1.0)
			if float(m["t"]) <= 0.0:
				var pats: Array = ["stomp", "breath", "charge"]
				if ph >= 2:
					pats = ["stomp", "breath", "lava", "charge"]
				if ph >= 3:
					pats = ["breath", "orb", "stomp", "lava", "charge", "orb"]
				m["next"] = pats[int(m["pat"]) % pats.size()]
				m["pat"] = int(m["pat"]) + 1
				var w := {"stomp": 0.9, "breath": 1.0, "charge": 1.2, "lava": 0.9, "orb": 0.9}
				_wind(m, float(w[String(m["next"])]) / fast)
				var tg2 := _boss_target(p, targets, room)
				var tp2: Vector3 = p + Vector3(0, 0, 1) if tg2.is_empty() else Vector3(tg2["p"])
				var dir2 := Vector3(tp2.x - p.x, 0.0, tp2.z - p.z).normalized()
				m["dir"] = dir2
				m["aim"] = tp2
				m["aim_knight"] = not tg2.is_empty() and bool(tg2["knight"])
				match String(m["next"]):
					"stomp":
						deep.hazard("ring", p, Vector3.ZERO, Vector2(3.4, 0.0), float(m["t"]), 0.35, _dmg(2, m), false)
						deep.sound_at("footstep", p, 0.0, 0.4)
					"breath":
						m["yaw"] = atan2(dir2.x, dir2.z)
						deep.hazard("line", p, dir2, Vector2(9.0, 1.7), float(m["t"]), 0.6, _dmg(2, m), false)
						deep.sound_at("fire", p, 0.0, 0.6)
					"charge":
						m["yaw"] = atan2(dir2.x, dir2.z)
						deep.telegraph("line", p, dir2, Vector2(11.0, 2.0), float(m["t"]))
						deep.sound_at("footstep", p, 2.0, 0.4)
					_:
						deep.sound_at("fire", p, -2.0, 0.8)


func _boss_forge_attack(id: int, m: Dictionary, targets: Array, ph: int) -> void:
	var p: Vector3 = m["p"]
	var room: int = m["room"]
	match String(m.get("next", "stomp")):
		"stomp":
			deep.sound_at("crash", p, 0.0, 0.5)
			deep.shake(0.6)
			m["st"] = RECOVER
			m["t"] = 1.0
		"breath":
			deep.sound_at("fire", p, 2.0, 0.5)
			m["st"] = RECOVER
			m["t"] = 1.0
		"charge":
			m["st"] = ACT
			m["t"] = 1.4
			m["hit"] = {}
			deep.sound_at("whoosh", p, 0.0, 0.4)
		"lava":
			for k in 3:
				var c := FloorGen.room_center(f, room) + Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0))
				deep.hazard("circle", c, Vector3.ZERO, Vector2(1.3, 0.0), 1.2, 6.0, _dmg(1, m), false, 1.0)
			m["st"] = RECOVER
			m["t"] = 0.8
		"orb":
			var from := p + Vector3(0.0, 2.0, 0.0)
			var head: Vector3 = deep.knight_head() if bool(m.get("aim_knight", false)) else Vector3(m["aim"]) + Vector3(0.0, 0.7, 0.0)
			shoot("orb", from, (head - from).normalized() * 4.0, id)
			deep.sound_at("magic", p, 0.0, 0.5)
			m["st"] = RECOVER
			m["t"] = 0.8


# --- Projectiles ---------------------------------------------------------------------------------

## Host: a straight shot. kind "ball" (1 heart), "orb" (big, 2 hearts; hit it back at the boss!),
## "arrow" (a hero's bow: owner -2, hurts monsters).
func shoot(kind: String, from: Vector3, v: Vector3, owner: int) -> int:
	var id := next_shot
	next_shot += 1
	shots[id] = {"kind": kind, "p": from, "v": v, "t": 0.0, "owner": owner, "r": 0.45 if kind == "orb" else 0.25}
	return id


## Host: a lobbed bomb (just the look: deep.hazard does the bang).
func lob(kind: String, from: Vector3, to: Vector3, secs: float, owner: int) -> int:
	var id := next_shot
	next_shot += 1
	shots[id] = {"kind": kind, "p": from, "v": Vector3.ZERO, "t": 0.0, "owner": owner, "r": 0.2,
		"from": from, "to": to, "fly": secs, "life": secs + 1.0}
	return id


## Host: send a shot back (sword / bonk). Returns true if it was reflectable.
func reflect(sid: int, toward: Vector3) -> bool:
	if not shots.has(sid):
		return false
	var s: Dictionary = shots[sid]
	if String(s["kind"]) not in ["ball", "orb"] or int(s["owner"]) == -2:
		return false
	var p: Vector3 = s["p"]
	var speed := Vector3(s["v"]).length() * 1.6
	var src: int = s["owner"]
	var aim := toward
	if mons.has(src):
		aim = center_of(src)
	s["v"] = (aim - p).normalized() * maxf(speed, 6.0)
	s["owner"] = -2
	s["t"] = 0.0
	return true


func _step_shots(delta: float, targets: Array) -> void:
	for sid in shots.keys():
		var s: Dictionary = shots[sid]
		s["t"] = float(s["t"]) + delta
		var t: float = s["t"]
		if String(s["kind"]) == "bomb":
			var k := clampf(t / float(s["fly"]), 0.0, 1.0)
			var a: Vector3 = s["from"]
			var b: Vector3 = s["to"]
			var np := a.lerp(b + Vector3(0.0, 0.2, 0.0), k)
			np.y += sin(PI * k) * 2.0
			s["p"] = np
			if t > float(s["life"]):
				shots.erase(sid)
			continue
		var p: Vector3 = s["p"]
		var v: Vector3 = s["v"]
		var np2 := p + v * delta
		s["p"] = np2
		var gone := t > 6.0
		var room := FloorGen.room_at(f, np2)
		if room < 0 or not FloorGen.walkable(room_rects[room], obst, np2, 0.05):
			gone = true
		var r: float = s["r"]
		if not gone and int(s["owner"]) == -2:
			for mid in mons.keys():
				if mons.has(mid) and center_of(mid).distance_to(np2) < radius_of(mid) + r:
					var dmg := 2.0 if String(s["kind"]) != "orb" else maxf(3.0, float(mons[mid]["max"]) * 0.08)
					if String(s["kind"]) == "arrow":
						dmg = float(s.get("dmg", 1.0))
					deep.shot_hits_foe(int(mid), dmg, p, String(s["kind"]))
					gone = true
					break
		elif not gone:
			for tg in targets:
				var tp: Vector3 = (tg as Dictionary)["p"]
				var hy := 1.2 if bool((tg as Dictionary)["knight"]) else 0.5
				var aim := tp + Vector3(0.0, hy, 0.0)
				if bool((tg as Dictionary)["knight"]):
					aim = deep.knight_head() + Vector3(0.0, -0.35, 0.0)
				if aim.distance_to(np2) < r + (0.45 if bool((tg as Dictionary)["knight"]) else 0.4):
					var dmg2 := 2 if String(s["kind"]) == "orb" else 1
					deep.hurt(int((tg as Dictionary)["key"]), dmg2 + int(cfg["dmg"]), np2, true)
					gone = true
					break
		if gone:
			deep.shot_gone(int(sid), np2, String(s["kind"]))
			shots.erase(sid)


# --- Every machine: drawing ------------------------------------------------------------------------

func animate(delta: float) -> void:
	for id in mons:
		var m: Dictionary = mons[id]
		var n: Node3D = m["node"]
		var target: Vector3 = m["p"]
		if n.position.distance_to(target) > 3.5:
			n.position = target
		else:
			n.position = n.position.lerp(target, 1.0 - exp(-18.0 * delta))
		n.rotation.y = lerp_angle(n.rotation.y, float(m["yaw"]), 1.0 - exp(-12.0 * delta))
		var st: int = m["st"]
		var s: float = m["sz"]
		var squash := 1.0
		if st == WIND:
			squash = 1.0 + 0.12 * sin(_t * 30.0)
			if fmod(_t, 0.25) < delta * 1.5:
				m["anim"].flash(Color(1.0, 0.5, 0.2), 0.12)
		n.scale = n.scale.lerp(Vector3(s * squash, s / squash, s * squash), 1.0 - exp(-14.0 * delta))
		(m["bang"] as Node3D).visible = st == WIND and fmod(_t, 0.2) < 0.14
		var moving := st in [MOVE, IDLE, ACT, FLY] and st != SLEEP
		m["anim"].walk(1.6 if moving and int(m["kind"]) != FloorGen.F_MIMIC else (0.8 if moving else 0.0))
		if st == STUN and not bool(m.get("dizzy", false)):
			m["dizzy"] = true
			m["anim"].faint()
		elif st != STUN and bool(m.get("dizzy", false)):
			m["dizzy"] = false
			m["anim"].revive()
		if m.has("bar"):
			m["bar"].set_value(float(m["frac"]), 1.0)
		var sh: Node = n.get_node_or_null("Shield")
		if sh != null and int(m["kind"]) == FloorGen.B_BONE:
			(sh as Node3D).visible = int(m["phase"]) >= 2
	_t += delta if deep == null else 0.0
	_animate_shots(delta)


func _shot_mesh(kind: String) -> ArrayMesh:
	if not _shot_meshes.has(kind):
		var b := MeshKit.Builder.new()
		match kind:
			"orb":
				var cols: Array[Color] = [Color(0.4, 0.8, 1.0), Color(0.7, 0.5, 1.0), Color(1.0, 0.5, 0.15)]
				b.sphere(0.4, Transform3D.IDENTITY, cols[zone], 12, true)
				b.torus(0.48, 0.04, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 1.0, 1.0), 16, 4, true)
			"bomb":
				b.sphere(0.2, Transform3D.IDENTITY, Color(0.15, 0.15, 0.2), 10)
				b.cylinder(0.03, 0.03, 0.12, MeshKit.at(Vector3(0, 0.22, 0)), Color(0.6, 0.45, 0.3), 6)
				b.sphere(0.05, MeshKit.at(Vector3(0, 0.3, 0)), Color(1.0, 0.7, 0.2), 6, true)
			"arrow":
				b.cylinder(0.025, 0.025, 0.6, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.75, 0.55, 0.3), 6)
				b.cone(0.06, 0.14, MeshKit.at(Vector3(0, 0, 0.36), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.85, 0.9, 1.0), 6, true)
			_:
				var cols2: Array[Color] = [Color(0.5, 1.0, 0.4), Color(1.0, 0.85, 0.5), Color(1.0, 0.55, 0.2)]
				b.sphere(0.22, Transform3D.IDENTITY, cols2[zone], 10, true)
		_shot_meshes[kind] = b.build()
	return _shot_meshes[kind]


func _animate_shots(delta: float) -> void:
	for sid in shots:
		var s: Dictionary = shots[sid]
		if not _shot_nodes.has(sid):
			var mi := MeshKit.instance(_shot_mesh(String(s["kind"])), false)
			add_child(mi)
			mi.position = s["p"]
			_shot_nodes[sid] = mi
		var n: Node3D = _shot_nodes[sid]
		var p: Vector3 = s["p"]
		var mv := p - n.position
		n.position = n.position.lerp(p, 1.0 - exp(-25.0 * delta)) if mv.length() < 3.0 else p
		if String(s["kind"]) == "arrow" and mv.length() > 0.001:
			n.rotation.y = atan2(mv.x, mv.z)
		elif String(s["kind"]) == "orb":
			n.rotation.y += delta * 4.0
	for sid in _shot_nodes.keys():
		if not shots.has(sid):
			(_shot_nodes[sid] as Node3D).queue_free()
			_shot_nodes.erase(sid)


# --- Network -------------------------------------------------------------------------------------

func pack() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for id in mons:
		var m: Dictionary = mons[id]
		var p: Vector3 = m["p"]
		var frac := float(m["hp"]) / maxf(1.0, float(m["max"]))
		var flags := int(m["st"]) | (16 if bool(m["elite"]) else 0) | (int(m["phase"]) << 5)
		out.append_array([float(id), float(m["kind"]) + float(m["room"]) * 32.0, snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01),
			snappedf(float(m["yaw"]), 0.02), float(flags), snappedf(frac, 0.01)])
	return out


func unpack(a: PackedFloat32Array) -> void:
	var seen := {}
	var i := 0
	while i + 7 < a.size():
		var id := int(a[i])
		var kr := int(a[i + 1])
		var p := Vector3(a[i + 2], a[i + 3], a[i + 4])
		var flags := int(a[i + 6])
		seen[id] = true
		if not mons.has(id):
			_make(id, kr % 32, p, kr / 32, flags & 16 != 0)
		var m: Dictionary = mons[id]
		m["p"] = p
		m["yaw"] = a[i + 5]
		m["st"] = flags & 15
		m["phase"] = flags >> 5
		m["frac"] = a[i + 7]
		i += 8
	for id in mons.keys():
		if not seen.has(id):
			remove(int(id))


func pack_shots() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var kinds := ["ball", "orb", "bomb", "arrow"]
	for sid in shots:
		var s: Dictionary = shots[sid]
		var p: Vector3 = s["p"]
		out.append_array([float(sid), float(kinds.find(String(s["kind"]))), snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
	return out


func unpack_shots(a: PackedFloat32Array) -> void:
	var kinds := ["ball", "orb", "bomb", "arrow"]
	var seen := {}
	var i := 0
	while i + 4 < a.size():
		var sid := int(a[i])
		seen[sid] = true
		var p := Vector3(a[i + 2], a[i + 3], a[i + 4])
		if not shots.has(sid):
			shots[sid] = {"kind": kinds[clampi(int(a[i + 1]), 0, 3)], "p": p}
		else:
			shots[sid]["p"] = p
		i += 5
	for sid in shots.keys():
		if not seen.has(sid):
			shots.erase(sid)
