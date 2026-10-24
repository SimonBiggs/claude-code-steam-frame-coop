extends Node3D
## STARSHIP CREW: everything out in space: rings to fly through, space rocks and silly alien saucers
## to zap, the space station at the end, streaming space dust and a big planet far away.
## The ship never moves: it sits at the world origin (a rock-steady cockpit for the VR pilot) and space
## slides past instead. Objects keep a "space" position: x/y are absolute (the ship's sideways position
## is `off`), z is the distance ahead (negative) and grows as the ship flies on.
## Host: moves everything and reports what happened (step() returns events). TV machine: mirrors from
## snapshots (pack()/unpack()).

const Art := preload("res://games/starship_crew/art.gd")
const MeshKit := preload("res://core/mesh_kit.gd")

enum { RING, ROCK, UFO, STATION }
const SHIP_Y := 1.1  ## world height of the ship's centre line (the pilot's eyes)
const LIMIT := Vector2(8.0, 4.0)  ## how far the ship may slide sideways / up and down
const RING_R := 2.4  ## fly within this of a ring's centre and it counts
const SPAWN_Z := -110.0
const GONE_Z := 14.0
const DUST := 90
const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.9, 0.4, 1.0);
void fragment() {
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	ALBEDO = col.rgb;
	ALPHA = clamp(rim * 1.6, 0.0, 1.0) * col.a;
}
"""

var off := Vector2.ZERO  ## the ship's sideways position (host: steered; TV machine: mirrored)
var speed := 10.0  ## forward speed (m/s)
## id -> {"kind": int, "p": Vector3 (space), "v": Vector3, "held": bool, "t": float, "base": Vector3,
##        "node": Node3D, "r": float (zap radius)}
var objs := {}
var next_id := 1
var rng := RandomNumberGenerator.new()

var _dust: MultiMeshInstance3D
var _dust_p := PackedVector3Array()
var _planet: MeshInstance3D
var _glow_mat: ShaderMaterial
var _ring_mat: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	rng.seed = 4242
	var xfs: Array = []
	for i in DUST:
		var p := Vector3(rng.randf_range(-30.0, 30.0), rng.randf_range(-16.0, 18.0), rng.randf_range(-150.0, GONE_Z))
		_dust_p.append(p)
		xfs.append(Transform3D(Basis(), p))
	_dust = MeshKit.scatter(Art.streak(), xfs, PackedColorArray(), PackedColorArray(), false)
	add_child(_dust)
	_planet = MeshInstance3D.new()
	_planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_planet)
	var sh := Shader.new()
	sh.code = GLOW_SHADER
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = sh
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.vertex_color_use_as_albedo = true
	_ring_mat.albedo_color = Color(0.5, 1.0, 0.95)


## A big planet far away; a different one for every mission.
func set_planet(i: int) -> void:
	var cols: Array[Color] = [Color(1.0, 0.6, 0.4), Color(0.5, 0.75, 1.0), Color(0.75, 0.5, 1.0), Color(0.5, 0.95, 0.6)]
	var rings: Array[Color] = [Color(1.0, 0.9, 0.6), Color(0, 0, 0, 0), Color(1.0, 0.7, 0.9), Color(0.9, 1.0, 0.8)]
	_planet.mesh = Art.planet(cols[i % 4], rings[i % 4])
	var spots: Array[Vector3] = [Vector3(-160, 60, -420), Vector3(170, -30, -400), Vector3(-120, -50, -380), Vector3(140, 70, -420)]
	_planet.position = spots[i % 4]
	_planet.scale = Vector3.ONE * 70.0


func world_of(p: Vector3) -> Vector3:
	return Vector3(p.x - off.x, p.y - off.y + SHIP_Y, p.z)


func world_pos(id: int) -> Vector3:
	return world_of(objs[id]["p"]) if objs.has(id) else Vector3.ZERO


# --- Making things (every machine builds the same look from the kind) -------------------------

func add(kind: int, p: Vector3, held: bool = false, id: int = -1) -> int:
	if id < 0:
		id = next_id
		next_id += 1
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var r := 0.0
	match kind:
		RING:
			mi.mesh = Art.ring()
			mi.material_override = _ring_mat if not held else null
		ROCK:
			mi.mesh = Art.rock(id % 3)
			r = 0.8 + float((id * 37) % 6) * 0.12
			mi.scale = Vector3.ONE * r
		UFO:
			mi.mesh = Art.ufo()
			r = 1.6
		STATION:
			mi.mesh = Art.station()
	n.add_child(mi)
	if held:  # a practice target: a soft glowing shell round it
		var g := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 3.1 if kind == RING else r * 1.5
		sm.height = sm.radius * 2.0
		sm.radial_segments = 16
		sm.rings = 8
		g.mesh = sm
		if kind == RING:
			g.scale = Vector3(1.0, 1.0, 0.25)
		g.material_override = _glow_mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.name = "Glow"
		n.add_child(g)
	add_child(n)
	n.position = world_of(p)
	objs[id] = {"kind": kind, "p": p, "v": Vector3.ZERO, "held": held, "t": 0.0, "base": p, "node": n, "r": r}
	return id


func remove(id: int) -> void:
	if objs.has(id):
		(objs[id]["node"] as Node).queue_free()
		objs.erase(id)


func clear() -> void:
	for id in objs.keys():
		remove(int(id))


## Host: ids of the things the crew can zap.
func zappables() -> Array[int]:
	var out: Array[int] = []
	for id in objs:
		var k: int = objs[id]["kind"]
		if (k == ROCK or k == UFO) and float((objs[id]["p"] as Vector3).z) > -95.0 and float((objs[id]["p"] as Vector3).z) < -3.0:
			out.append(int(id))
	return out


## Host: the nearest ring still ahead (or -1).
func next_ring() -> int:
	var best := -1
	var bz := -INF
	for id in objs:
		if int(objs[id]["kind"]) == RING:
			var z: float = (objs[id]["p"] as Vector3).z
			if z < -1.0 and z > bz:
				bz = z
				best = int(id)
	return best


# --- Host -----------------------------------------------------------------------------------------

## Move everything; returns events: ["ring", id, hit] when a ring passes the ship, ["bump", id] when a
## rock bonks the ship's shield, ["ufo_gone", id] when an alien flies off by itself.
func step(delta: float) -> Array:
	var ev: Array = []
	for id in objs.keys():
		var o: Dictionary = objs[id]
		var p: Vector3 = o["p"]
		var v: Vector3 = o["v"]
		var k: int = o["kind"]
		o["t"] = float(o["t"]) + delta
		var t: float = o["t"]
		var was_z := p.z
		if bool(o["held"]):
			pass
		elif k == UFO:
			var base: Vector3 = o["base"]
			if t < 16.0:
				base.z = minf(-32.0, base.z + (speed + 6.0) * delta)
				o["base"] = base
				p = base + Vector3(sin(t * 1.1 + id) * 3.5, sin(t * 2.3) * 1.2, 0.0)
			else:
				p += Vector3(0.0, 14.0, -10.0) * delta
				if t > 19.0:
					ev.append(["ufo_gone", int(id)])
					remove(int(id))
					continue
		else:
			p += (Vector3(0.0, 0.0, speed) + v) * delta
		o["p"] = p
		if was_z < -0.3 and p.z >= -0.3:
			var d := Vector2(p.x - off.x, p.y - off.y).length()
			if k == RING:
				ev.append(["ring", int(id), d < RING_R])
			elif k == ROCK and d < float(o["r"]) + 1.7:
				ev.append(["bump", int(id)])
				var away := Vector2(p.x - off.x, p.y - off.y)
				away = away.normalized() if away.length() > 0.1 else Vector2(1.0, 0.0)
				o["v"] = Vector3(away.x * 9.0, away.y * 9.0 + 3.0, 2.0)
		if p.z > GONE_Z:
			remove(int(id))
	return ev


## Host: a practice target (held still) lets go and flies on.
func release(id: int, extra_speed: float = 0.0) -> void:
	if objs.has(id):
		objs[id]["held"] = false
		objs[id]["v"] = Vector3(0.0, 0.0, extra_speed)
		var g := (objs[id]["node"] as Node).get_node_or_null("Glow")
		if g != null:
			g.queue_free()


# --- Every machine: drawing -------------------------------------------------------------------------

func animate(delta: float) -> void:
	_t += delta
	for id in objs:
		var o: Dictionary = objs[id]
		var n: Node3D = o["node"]
		n.position = world_of(o["p"])
		match int(o["kind"]):
			ROCK:
				n.rotate_x(delta * (0.4 + float(int(id) % 5) * 0.15))
				n.rotate_y(delta * 0.3)
			UFO:
				n.rotation = Vector3(sin(_t * 3.0 + id) * 0.25, _t * 2.0, cos(_t * 2.6 + id) * 0.2)
		if bool(o["held"]):
			n.scale = Vector3.ONE * (1.0 + sin(_t * 5.0) * 0.08)
	# Space dust: streams past, wraps around ahead of the ship.
	var mm := _dust.multimesh
	var stretch := clampf(speed * 0.3, 0.3, 4.0)
	for i in DUST:
		var p := _dust_p[i]
		p.z += speed * delta
		if p.z > GONE_Z:
			p = Vector3(off.x + rng.randf_range(-30.0, 30.0), off.y + rng.randf_range(-16.0, 18.0), -150.0)
		_dust_p[i] = p
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1.0, 1.0, stretch)), world_of(p)))


# --- Snapshots ----------------------------------------------------------------------------------------

func pack() -> Array:
	var ids := PackedInt32Array()
	var kinds := PackedByteArray()
	var pos := PackedVector3Array()
	for id in objs:
		ids.append(int(id))
		kinds.append(int(objs[id]["kind"]) + (8 if bool(objs[id]["held"]) else 0))
		pos.append(objs[id]["p"])
	return [ids, kinds, pos]


func unpack(a: Array, delta: float) -> void:
	if a.size() < 3:
		return
	var ids: PackedInt32Array = a[0]
	var kinds: PackedByteArray = a[1]
	var pos: PackedVector3Array = a[2]
	var seen := {}
	for i in ids.size():
		var id := ids[i]
		seen[id] = true
		var held := kinds[i] >= 8
		if objs.has(id) and bool(objs[id]["held"]) and not held:
			release(id)
		if not objs.has(id):
			add(kinds[i] % 8, pos[i], held, id)
		var o: Dictionary = objs[id]
		var cur: Vector3 = o["p"]
		o["p"] = pos[i] if cur.distance_to(pos[i]) > 12.0 else cur.lerp(pos[i], 1.0 - exp(-20.0 * delta))
	for id in objs.keys():
		if not seen.has(id):
			remove(int(id))
