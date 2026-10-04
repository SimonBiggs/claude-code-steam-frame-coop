extends Node3D
## DUNGEON DELVE projectiles: arrows, magic bolts, fireballs, notes, monster spores, bones, coins...
## Straight lines at constant speed, so the TV machine flies the very same shot from the spawn event
## (no per-frame network traffic); the host decides what each shot hits and sends "pend" when it
## ends. All shots are drawn by ONE MultiMesh (stretched glowing blobs, coloured per instance).
## Monster shots can be blocked (and reflected!) by the VR paladin's shield.

const Data := preload("res://games/dungeon_delve/data.gd")
const MAX_SHOTS := 160

var main: Node
var shots := {}  # id -> Dictionary
var next_id := 1
var mm: MultiMeshInstance3D


func _ready() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 10
	mesh.rings = 5
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.use_colors = true
	m.mesh = mesh
	m.instance_count = MAX_SHOTS
	m.visible_instance_count = 0
	mm = MultiMeshInstance3D.new()
	mm.multimesh = m
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mm.name = "Shots"
	add_child(mm)


## Host / local: fire a shot. team "hero" (slot = shooter) or "enemy" (slot = monster id).
## opts: pierce (int), life (s), size (visual/hit scale), aoe (radius: explode at the end), dmg_kind.
func spawn(kind: String, pos: Vector3, dir: Vector3, speed: float, team: String, slot: int, dmg: float, opts: Dictionary = {}) -> int:
	if shots.size() >= MAX_SHOTS:
		return -1
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() < 0.001:
		d = Vector3.FORWARD
	d = d.normalized()
	var id := next_id
	next_id += 1
	var life := float(opts.get("life", 1.6 if team == "hero" else 3.2))
	var size := float(opts.get("size", 1.0))
	_add(id, kind, pos, d * speed, team, slot, life, size)
	var s: Dictionary = shots[id]
	s["dmg"] = dmg
	s["pierce"] = int(opts.get("pierce", 0))
	s["aoe"] = float(opts.get("aoe", 0.0))
	s["hit"] = {}
	s["crit"] = bool(opts.get("crit", false))
	s["effects"] = opts.get("effects", [])
	main.net.event("proj", [id, kind, pos, d * speed, team, slot, life, size])
	return id


func _add(id: int, kind: String, pos: Vector3, vel: Vector3, team: String, slot: int, life: float, size: float) -> void:
	var def: Dictionary = Data.PROJECTILES.get(kind, Data.PROJECTILES["orb"])
	shots[id] = {"id": id, "kind": kind, "pos": pos, "vel": vel, "team": team, "slot": slot, "life": life,
		"r": float(def["r"]) * size, "size": size, "color": def["color"], "len": float(def["len"]), "t": 0.0}


## TV machine: a shot the host fired.
func spawn_remote(args: Array) -> void:
	_add(int(args[0]), String(args[1]), args[2], args[3], String(args[4]), int(args[5]), float(args[6]), float(args[7]))


## Remove a shot (both machines); hit = it hit something (sparks).
func end_shot(id: int, pos: Vector3, hit: bool) -> void:
	if not shots.has(id):
		return
	var s: Dictionary = shots[id]
	shots.erase(id)
	if hit:
		main.fx.spark(pos, s["color"], String(s["kind"]) == "fireball")
	if main.net.mode != "client":
		main.net.event("pend", [id, pos, hit])


func clear() -> void:
	shots.clear()
	mm.multimesh.visible_instance_count = 0


func _process(delta: float) -> void:
	if not main.ready_to_play or main.layout == null:
		return
	var host: bool = main.net.mode != "client"
	for id in shots.keys():
		var s: Dictionary = shots[id]
		var p: Vector3 = s["pos"]
		var v: Vector3 = s["vel"]
		var np := p + v * delta
		s["pos"] = np
		s["t"] = float(s["t"]) + delta
		s["life"] = float(s["life"]) - delta
		if not host:
			if float(s["life"]) < -0.6 or not main.layout.walkable_at(np):
				shots.erase(id)  # the host's "pend" may still arrive: harmless
			continue
		if not main.layout.walkable_at(np):
			_explode(s, np)
			end_shot(int(id), p, true)
			continue
		if String(s["team"]) == "hero":
			if _hero_hits(s, np):
				continue
		else:
			if _enemy_hits(s, np):
				continue
		if float(s["life"]) <= 0.0:
			_explode(s, np)
			end_shot(int(id), np, float(s["aoe"]) > 0.0)
	_draw()


## Host: a hero's shot. True if it ended.
func _hero_hits(s: Dictionary, p: Vector3) -> bool:
	var id := int(s["id"])
	var r: float = s["r"]
	var hit_dict: Dictionary = s["hit"]
	if main.hit_props(p, r + 0.2, int(s["slot"])):
		_explode(s, p)
		end_shot(id, p, true)
		return true
	var ids: Array = main.enemies.query(p, r, hit_dict)
	for eid in ids:
		hit_dict[int(eid)] = true
		var dir: Vector3 = (s["vel"] as Vector3).normalized()
		main.damage_enemy(int(eid), float(s["dmg"]), int(s["slot"]), dir, {"crit": bool(s["crit"]), "effects": s["effects"], "ranged": true})
		if float(s["aoe"]) > 0.0:
			_explode(s, p)
			end_shot(id, p, true)
			return true
		s["pierce"] = int(s["pierce"]) - 1
		if int(s["pierce"]) < 0:
			end_shot(id, p, true)
			return true
	return false


## Host: a monster's shot. True if it ended.
func _enemy_hits(s: Dictionary, p: Vector3) -> bool:
	var id := int(s["id"])
	var r: float = s["r"]
	# The VR paladin's shield blocks (and reflects) it.
	var refl: Vector3 = main.shield_block(p, r, s["vel"])
	if refl != Vector3.ZERO:
		end_shot(id, p, true)
		var speed := maxf(10.0, (s["vel"] as Vector3).length() * 1.6)
		spawn(String(s["kind"]), p, refl, speed, "hero", 0, float(s["dmg"]) * 2.0, {"pierce": 1, "life": 1.5})
		return true
	for slot in main.players_near(p, r + 0.35):
		if main.hurt_player(int(slot), float(s["dmg"]), p - (s["vel"] as Vector3).normalized(), "shot"):
			end_shot(id, p, true)
			return true
	return false


## Fireballs (and other aoe shots) burst where they end.
func _explode(s: Dictionary, p: Vector3) -> void:
	var aoe := float(s["aoe"])
	if aoe <= 0.0 or String(s["team"]) != "hero":
		return
	s["aoe"] = 0.0
	main.explode(p, aoe, float(s["dmg"]) * 0.8, int(s["slot"]), s["color"])


func _draw() -> void:
	var m := mm.multimesh
	var n := 0
	for id in shots:
		if n >= MAX_SHOTS:
			break
		var s: Dictionary = shots[id]
		var p: Vector3 = s["pos"]
		var v: Vector3 = s["vel"]
		var r: float = s["r"] * 0.75
		var stretch: float = s["len"]
		var basis := Basis()
		if v.length() > 0.01:
			var f := v.normalized()
			var up := Vector3.UP if absf(f.y) < 0.95 else Vector3.RIGHT
			basis = Basis.looking_at(f, up)
		var wob := 1.0 + 0.12 * sin(float(s["t"]) * 30.0)
		basis = basis.scaled(Vector3(r * wob, r * wob, r * stretch))
		m.set_instance_transform(n, Transform3D(basis, p))
		var c: Color = s["color"]
		m.set_instance_color(n, Color(c.r * 1.4, c.g * 1.4, c.b * 1.4))
		n += 1
	m.visible_instance_count = n
