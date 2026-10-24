extends Node3D
## DUNGEON DELVE: the cute monsters. The host simulates them; the TV machine mirrors the snapshot.
##  - SLIME: hops towards the nearest hero; a bump makes that hero dizzy for a moment.
##  - BAT: flutters round the room up high (the VR knight's sword reaches it) and now and then
##    swoops down low, where the TV heroes can bonk it. Bats never hurt anyone.
##  - KING: the big Slime King. Every bop makes him a bit smaller (that's his "health", no bar);
##    now and then a little slime pops out; the last bop and he poofs into confetti.
## Any hit (sword, bonk, thrown pot) poofs a slime or a bat at once.

const Creatures := preload("res://core/creatures.gd")
const Dungeon := preload("res://games/dungeon_delve/dungeon.gd")

enum { SLIME, BAT, KING }
const KING_HITS := 6
const SLIME_COLORS: Array[Color] = [Color(0.45, 0.9, 0.45), Color(1.0, 0.55, 0.75), Color(0.45, 0.75, 1.0), Color(0.75, 0.55, 1.0)]

var mons := {}  ## id -> Dictionary
var next_id := 1
var _heights := {}  ## kind -> height at scale 1


func clear() -> void:
	for id in mons:
		(mons[id]["node"] as Node3D).queue_free()
	mons.clear()


func count() -> int:
	return mons.size()


func spawn(kind: int, p: Vector3, room: int) -> int:
	var id := next_id
	next_id += 1
	_make(id, kind, p, room)
	return id


func _make(id: int, kind: int, p: Vector3, room: int) -> Dictionary:
	var node: Node3D
	match kind:
		BAT:
			node = Creatures.monster("bat", {"color": Color(0.55, 0.4, 0.75), "seed": id})
		KING:
			node = Creatures.monster("slime", {"color": Color(0.5, 0.85, 1.0), "boss": true})
		_:
			node = Creatures.monster("slime", {"color": SLIME_COLORS[id % SLIME_COLORS.size()]})
	add_child(node)
	node.position = p
	var an: Variant = Creatures.anim(node)
	if kind == BAT:
		an.flying = true
	if not _heights.has(kind):
		_heights[kind] = maxf(0.3, Creatures.height_of(node))
	var m := {"kind": kind, "room": room, "p": p, "v": Vector3.ZERO, "yaw": 0.0, "t": randf_range(0.3, 1.2),
		"hop": 0.0, "hits": 0, "node": node, "anim": an, "h": float(_heights[kind]), "sz": 1.0,
		"ang": randf() * TAU, "swoop": randf_range(2.0, 5.0), "dive": 0.0, "goal": p, "cd": 0.0}
	mons[id] = m
	return m


## Where to aim at a monster, and how big it is.
func center_of(id: int) -> Vector3:
	var m: Dictionary = mons[id]
	var s := float(m["sz"])
	var h := float(m["h"]) * s
	if int(m["kind"]) == BAT:
		return (m["node"] as Node3D).position + Vector3(0.0, h * 0.4, 0.0)
	return (m["node"] as Node3D).position + Vector3(0.0, h * 0.5, 0.0)


func radius_of(id: int) -> float:
	var m: Dictionary = mons[id]
	var r := float(m["h"]) * float(m["sz"]) * 0.5
	return maxf(r, 0.3) if int(m["kind"]) != BAT else 0.35


func remove(id: int) -> void:
	if mons.has(id):
		(mons[id]["node"] as Node3D).queue_free()
		mons.erase(id)


## Host: a hit. Returns "poof" (gone), "hit" (the King got smaller) or "" (too soon again).
func hit(id: int) -> String:
	if not mons.has(id):
		return ""
	var m: Dictionary = mons[id]
	if int(m["kind"]) != KING:
		remove(id)
		return "poof"
	if float(m["cd"]) > 0.0:
		return ""
	m["cd"] = 0.45
	m["hits"] = int(m["hits"]) + 1
	if int(m["hits"]) >= KING_HITS:
		remove(id)
		return "poof"
	m["anim"].hurt(Color(1, 1, 1))
	m["v"] = -(m["v"] as Vector3) * 0.5
	return "hit"


static func king_size(hits: int) -> float:
	return 1.4 - hits * 0.12


## Host: move everyone. targets: Array of [Vector3 feet, key] the slimes chase (heroes and the
## VR knight). Returns bumps: [id, key] for each slime touching a target.
func step(delta: float, targets: Array) -> Array:
	var bumps: Array = []
	for id in mons:
		var m: Dictionary = mons[id]
		var kind: int = m["kind"]
		var p: Vector3 = m["p"]
		m["cd"] = maxf(0.0, float(m["cd"]) - delta)
		var room: int = m["room"]
		if kind == KING:
			m["sz"] = king_size(int(m["hits"]))
		if kind == BAT:
			_bat(m, delta, targets)
			continue
		# Slimes and the King hop.
		m["t"] = float(m["t"]) - delta
		var hop_len := 0.75 if kind == KING else 0.55
		if float(m["t"]) <= 0.0:
			m["t"] = randf_range(1.6, 2.4) if kind == KING else randf_range(0.9, 1.7)
			var best := Vector3.INF
			for tg in targets:
				var tp: Vector3 = tg[0]
				if Dungeon.room_of(tp) == room and (best == Vector3.INF or tp.distance_to(p) < best.distance_to(p)):
					best = tp
			var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			if best != Vector3.INF and randf() < 0.8:
				dir = Vector3(best.x - p.x, 0.0, best.z - p.z).normalized()
			m["v"] = dir * (1.5 if kind == KING else 1.8)
			m["hop"] = hop_len
			m["yaw"] = atan2(dir.x, dir.z)
		var hop: float = m["hop"]
		var y := 0.0
		if hop > 0.0:
			hop = maxf(0.0, hop - delta)
			m["hop"] = hop
			p += (m["v"] as Vector3) * delta
			y = sin(PI * (1.0 - hop / hop_len)) * (0.5 if kind == KING else 0.35)
		var r := radius_of(id) * 0.8
		p = Dungeon.room_clamp(p, room, r)
		p.y = y
		m["p"] = p
		# Bumps (only while hopping, so a slime that just bounced off doesn't stick).
		for tg in targets:
			var tp2: Vector3 = tg[0]
			var reach := 0.55 + (radius_of(id) - 0.3 if kind == KING else 0.0)
			if Vector2(tp2.x - p.x, tp2.z - p.z).length() < reach and hop > 0.0:
				bumps.append([id, tg[1]])
				m["v"] = -(m["v"] as Vector3)
	return bumps


func _bat(m: Dictionary, delta: float, targets: Array) -> void:
	var c := Dungeon.center(int(m["room"]))
	m["ang"] = float(m["ang"]) + delta * 0.7
	var a: float = m["ang"]
	var home := c + Vector3(cos(a) * 2.6, 1.7 + 0.25 * sin(a * 3.0), sin(a) * 2.6)
	m["swoop"] = float(m["swoop"]) - delta
	var dive: float = m["dive"]
	if float(m["swoop"]) <= 0.0 and dive <= 0.0:
		m["swoop"] = randf_range(3.5, 6.0)
		var pick: Array = []
		for tg in targets:
			if Dungeon.room_of(tg[0]) == int(m["room"]):
				pick.append(tg[0])
		if not pick.is_empty():
			var g: Vector3 = pick[randi() % pick.size()]
			m["goal"] = g + Vector3(randf_range(-0.6, 0.6), 0.55, randf_range(-0.6, 0.6))
			m["dive"] = 2.6
			dive = 2.6
	var want := home
	if dive > 0.0:
		dive -= delta
		m["dive"] = dive
		var k := sin(PI * clampf(1.0 - dive / 2.6, 0.0, 1.0))
		want = home.lerp(m["goal"], k)
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
		var s: float = m["sz"]
		n.scale = n.scale.lerp(Vector3.ONE * s, 1.0 - exp(-8.0 * delta))
		m["anim"].walk(1.5 if float(m["hop"]) > 0.0 or int(m["kind"]) == BAT else 0.0)


# --- Network -------------------------------------------------------------------------------------

func pack() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for id in mons:
		var m: Dictionary = mons[id]
		var p: Vector3 = m["p"]
		out.append_array([float(id), float(m["kind"]), snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01),
			snappedf(float(m["yaw"]), 0.02), snappedf(float(m["sz"]), 0.01), 1.0 if float(m["hop"]) > 0.0 else 0.0])
	return out


func unpack(a: PackedFloat32Array) -> void:
	var seen := {}
	var i := 0
	while i + 7 < a.size():
		var id := int(a[i])
		var p := Vector3(a[i + 2], a[i + 3], a[i + 4])
		seen[id] = true
		if not mons.has(id):
			_make(id, int(a[i + 1]), p, Dungeon.room_of(p))
		var m: Dictionary = mons[id]
		m["p"] = p
		m["yaw"] = a[i + 5]
		m["sz"] = a[i + 6]
		m["hop"] = a[i + 7]
		i += 8
	for id in mons.keys():
		if not seen.has(id):
			remove(int(id))
