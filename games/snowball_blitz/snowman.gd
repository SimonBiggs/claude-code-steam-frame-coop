extends Node3D
## A mischievous snowman. Host: waddles to its fort wall segment, bashes it, lobs snowballs at the
## players, and squeezes in through a breach. Collapses into a pile when hit enough.
## Client: a visual ghost placed from snapshots (animated locally).

const KINDS := {
	"snowman": {"hp": 3.0, "speed": 1.8, "scale": 1.0, "wall_dps": 6.0, "throw_cd": 3.8, "ball_dmg": 8.0, "ball_r": 0.14, "points": 100, "cocoa": 0.08},
	"sled": {"hp": 2.0, "speed": 5.0, "scale": 0.8, "crash": 24.0, "points": 150, "cocoa": 0.12},
	"giant": {"hp": 12.0, "speed": 1.15, "scale": 1.9, "wall_dps": 14.0, "throw_cd": 4.4, "ball_dmg": 15.0, "ball_r": 0.26, "points": 400, "cocoa": 0.5},
	"king": {"hp": 70.0, "speed": 0.85, "scale": 2.6, "wall_dps": 18.0, "throw_cd": 3.2, "ball_dmg": 12.0, "ball_r": 0.22, "points": 3000, "cocoa": 1.0, "volley": 3},
}
## Body spheres in unscaled units: [height of centre, radius]
const SPHERES := [[0.45, 0.5], [1.12, 0.37], [1.62, 0.27]]

var main
var kind := "snowman"
var d: Dictionary
var hp := 3.0
var max_hp := 3.0
var speed := 1.8
var s := 1.0
var height := 2.0
var seg := 0
var throw_cd := 2.0
var summon_cd := 8.0
var spawn_grace := 0.8
var dead := false
var inside := false
var bashing := false
var last_hitter := -1
var t := 0.0
var squash := 0.0
var lift := 0.0  # sled riders sit higher
var body: Node3D
var last_pos := Vector3.ZERO
var move_amt := 0.0
# Networked: ghosts on the client.
var ghost := false
var net_id := 0
var net_target := Vector3.ZERO
var net_rot := 0.0
var net_hp := 1.0


func setup(k: String, wave: int, main_node, seg_index: int) -> void:
	kind = k
	main = main_node
	seg = seg_index
	d = KINDS[k]
	max_hp = float(d.hp) * (1.0 + (wave - 1) * 0.1)
	hp = max_hp
	speed = float(d.speed) * (1.0 + minf(wave, 12) * 0.025)
	s = d.scale
	height = 2.2 * s
	throw_cd = randf_range(1.5, float(d.get("throw_cd", 3.0)))
	if kind == "sled":
		lift = 0.25


func _ready() -> void:
	add_to_group("snowmen")
	if d.is_empty():
		d = KINDS[kind]
		s = d.scale
		height = 2.2 * s
		lift = 0.25 if kind == "sled" else 0.0
	net_target = position
	last_pos = position
	body = Node3D.new()
	add_child(body)
	_build()
	body.scale = Vector3.ONE * 0.05
	create_tween().tween_property(body, "scale", Vector3.ONE * s, spawn_grace).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _part(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	body.add_child(mi)
	return mi


func _build() -> void:
	var y0 := lift
	for sp in SPHERES:
		_part(main.sphere_mesh(sp[1]), main.mat("snow"), Vector3(0, y0 + sp[0], 0))
	# Carrot nose (points along -Z, the way the snowman faces).
	var carrot := CylinderMesh.new()
	carrot.top_radius = 0.0
	carrot.bottom_radius = 0.05
	carrot.height = 0.32
	carrot.radial_segments = 8
	carrot.rings = 1
	_part(carrot, main.mat("carrot"), Vector3(0, y0 + 1.62, -0.38), Vector3(-PI / 2.0, 0, 0))
	for x in [-0.09, 0.09]:
		_part(main.sphere_mesh(0.035), main.mat("coal"), Vector3(x, y0 + 1.7, -0.23))
	# Stick arms.
	var arm := BoxMesh.new()
	arm.size = Vector3(0.62, 0.04, 0.04)
	for side in [-1.0, 1.0]:
		_part(arm, main.mat("stick"), Vector3(side * 0.55, y0 + 1.22, 0), Vector3(0, 0, side * 0.45))
	# Cosy scarf in a random colour.
	var scarf := TorusMesh.new()
	scarf.inner_radius = 0.17
	scarf.outer_radius = 0.29
	scarf.rings = 12
	scarf.ring_segments = 6
	_part(scarf, main.mat("scarf%d" % (randi() % 5)), Vector3(0, y0 + 1.38, 0))
	if kind == "king":
		var crown := CylinderMesh.new()
		crown.top_radius = 0.26
		crown.bottom_radius = 0.2
		crown.height = 0.24
		crown.radial_segments = 10
		crown.cap_top = false
		_part(crown, main.mat("crown"), Vector3(0, y0 + 1.95, 0))
		_part(main.sphere_mesh(0.05), main.mat("gem"), Vector3(0, y0 + 1.95, -0.22))
	else:
		var brim := CylinderMesh.new()
		brim.top_radius = 0.3
		brim.bottom_radius = 0.3
		brim.height = 0.04
		brim.radial_segments = 12
		_part(brim, main.mat("hat"), Vector3(0, y0 + 1.84, 0))
		var top := CylinderMesh.new()
		top.top_radius = 0.19
		top.bottom_radius = 0.19
		top.height = 0.32
		top.radial_segments = 12
		_part(top, main.mat("hat"), Vector3(0, y0 + 2.02, 0))
	if kind == "sled":
		var deck := BoxMesh.new()
		deck.size = Vector3(0.9, 0.12, 1.5)
		_part(deck, main.mat("sled"), Vector3(0, 0.2, 0))
		var runner := BoxMesh.new()
		runner.size = Vector3(0.06, 0.06, 1.7)
		for x in [-0.38, 0.38]:
			_part(runner, main.mat("stick"), Vector3(x, 0.05, -0.05))
	for c in body.get_children():
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if s > 1.5 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Does a ball at p (radius r) touch this snowman? Tests its three body spheres.
func hit_test(p: Vector3, r: float) -> bool:
	var local := p - global_position
	if local.y > (lift + 2.2) * s + r:
		return false
	for sp in SPHERES:
		var c := Vector3(0, (lift + float(sp[0])) * s, 0)
		if local.distance_to(c) < float(sp[1]) * s + r:
			return true
	return false


func radius() -> float:
	return 0.5 * s


# --- Host simulation ---------------------------------------------------------

func _physics_process(delta: float) -> void:
	if ghost or dead:
		return
	if main.game_over:
		bashing = false
		return
	t += delta
	spawn_grace -= delta
	throw_cd -= delta
	var pos := global_position
	var target := pos
	bashing = false
	var R: float = main.fort_r
	var seg_up: bool = main.seg_hp[seg] > 0.0
	var flat_r := Vector2(pos.x, pos.z).length()
	if not inside:
		var wall_point: Vector3 = main.seg_center(seg) * ((R + 0.5 + radius() + 0.1) / R)
		if seg_up:
			target = wall_point
			if Vector2(pos.x - wall_point.x, pos.z - wall_point.z).length() < 0.35:
				target = pos
				if kind == "sled":
					main.damage_segment(seg, float(d.crash))
					main.sound("big_kill", -4.0, 1.6)
					_collapse(-1)
					return
				bashing = true
				main.damage_segment(seg, float(d.wall_dps) * delta)
		else:
			target = Vector3.ZERO
			if flat_r < R - 1.0:
				inside = true
	else:
		var p = main.nearest_player(pos)
		if p != null:
			target = p.global_position
			var dist := Vector2(target.x - pos.x, target.z - pos.z).length()
			if dist < radius() + 0.7:
				target = pos
				if kind == "sled":
					p.take_damage(22.0, pos)
					_collapse(-1)
					return
				p.take_damage(18.0 * delta, pos)
				bashing = true
		elif flat_r < 0.6 and kind == "sled":
			_collapse(-1)
			return
	# Walk (sleds zoom), keeping a little personal space from other snowmen.
	var to := target - pos
	to.y = 0.0
	var step := Vector3.ZERO
	if to.length() > 0.05:
		step = to.normalized() * minf(speed * delta, to.length())
	for other in get_tree().get_nodes_in_group("snowmen"):
		if other == self or other.ghost:
			continue
		var away: Vector3 = pos - other.global_position
		away.y = 0.0
		var min_d: float = radius() + other.radius() + 0.1
		var dl := away.length()
		if dl < min_d and dl > 0.001:
			step += away / dl * (min_d - dl) * 0.2
	global_position = pos + step
	var face := to if to.length() > 0.1 else -pos
	if face.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), 1.0 - exp(-6.0 * delta))
	if kind == "king":
		summon_cd -= delta
		if summon_cd <= 0.0 and spawn_grace <= 0.0:
			summon_cd = 9.0
			main.summon_minions(global_position, 2)
	if d.has("throw_cd") and throw_cd <= 0.0 and spawn_grace <= 0.0:
		_try_throw()


func _try_throw() -> void:
	var p = main.nearest_player(global_position)
	if p == null:
		throw_cd = 1.0
		return
	var aim: Vector3 = p.aim_point()
	if aim.distance_to(global_position) > 24.0:
		throw_cd = 1.0
		return
	throw_cd = float(d.throw_cd) * randf_range(1.1, 1.6)  # family feedback: fewer incoming snowballs
	squash = -0.6  # wind-up stretch
	var from := global_position + Vector3(0, (lift + 1.3) * s, 0) + Basis(Vector3.UP, rotation.y) * Vector3(0.4 * s, 0, -0.3 * s)
	var count: int = d.get("volley", 1)
	for i in count:
		var miss := Vector3(randf_range(-1.0, 1.0), randf_range(-0.2, 0.4), randf_range(-1.0, 1.0))
		if count > 1:
			miss += Basis(Vector3.UP, rotation.y) * Vector3((i - (count - 1) / 2.0) * 1.6, 0, 0)
		var v: Vector3 = main.lob_velocity(from, aim + miss, 10.0)
		main.spawn_ball(from, v, float(d.ball_r), float(d.ball_dmg), "e", -1)
	main.sound("spit", -6.0, 0.7 if s > 1.5 else 1.1)


## A player's snowball landed: squish, nudge back, maybe collapse.
func take_hit(dmg: float, vel: Vector3, who: int) -> void:
	if dead:
		return
	hp -= dmg
	squash = 1.0
	last_hitter = who
	var push := Vector3(vel.x, 0, vel.z).normalized() * 0.18 * dmg / s
	global_position += push
	if hp <= 0.0:
		_collapse(who)


func _collapse(who: int) -> void:
	if dead:
		return
	dead = true
	main.on_snowman_collapsed(self, who)
	queue_free()


# --- Both machines: animation ------------------------------------------------

func apply_net(item: Array) -> void:
	net_target = item[2]
	net_rot = item[3]
	var frac: float = item[4]
	if frac < net_hp - 0.001:
		squash = 1.0
	net_hp = frac
	bashing = item[5]


func _process(delta: float) -> void:
	if ghost:
		t += delta
		global_position = global_position.lerp(net_target, 1.0 - exp(-12.0 * delta))
		rotation.y = lerp_angle(rotation.y, net_rot, 1.0 - exp(-10.0 * delta))
	move_amt = lerpf(move_amt, clampf((global_position - last_pos).length() / maxf(delta, 0.001) / maxf(speed, 0.5), 0.0, 1.0), 1.0 - exp(-8.0 * delta))
	last_pos = global_position
	if body == null:
		return
	squash = move_toward(squash, 0.0, delta * 4.0)
	var hop := 0.0 if kind == "sled" else absf(sin(t * 7.0)) * 0.1 * move_amt
	body.position.y = hop * s
	body.rotation.z = (sin(t * 7.0) * 0.09 * move_amt) if kind != "sled" else sin(t * 20.0) * 0.03
	body.rotation.x = sin(t * 10.0) * 0.22 if bashing else 0.0
	if t > spawn_grace:
		var sq := squash * 0.25
		body.scale = Vector3(1.0 + sq, 1.0 - sq, 1.0 + sq) * s
