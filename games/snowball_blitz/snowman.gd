extends Node3D
## A mischievous snowman. Host: waddles to its fort wall segment, bashes it, lobs snowballs at the
## players, and squeezes in through a breach. Collapses into a pile when hit enough.
## Client: a visual ghost placed from snapshots (animated locally).
## Kinds: snowman, sled rider, giant, the SNOW KING, snow bunnies (tiny, fast, in threes), balloon
## snowmen (float over the walls until their balloons are popped), shield snowmen (an ice shield blocks
## flat throws from the front - lob over it, hit it from the side, or break it) and the YETI finale boss.

const KINDS := {
	"snowman": {"hp": 3.0, "speed": 1.8, "scale": 1.0, "wall_dps": 6.0, "throw_cd": 3.8, "ball_dmg": 8.0, "ball_r": 0.14, "points": 100, "cocoa": 0.08},
	"sled": {"hp": 2.0, "speed": 5.0, "scale": 0.8, "crash": 24.0, "points": 150, "cocoa": 0.12},
	"giant": {"hp": 12.0, "speed": 1.15, "scale": 1.9, "wall_dps": 14.0, "throw_cd": 4.4, "ball_dmg": 15.0, "ball_r": 0.26, "points": 400, "cocoa": 0.5},
	"king": {"hp": 70.0, "speed": 0.85, "scale": 2.6, "wall_dps": 18.0, "throw_cd": 3.2, "ball_dmg": 12.0, "ball_r": 0.22, "points": 3000, "cocoa": 1.0, "volley": 3},
	"bunny": {"hp": 1.0, "speed": 3.4, "scale": 0.55, "wall_dps": 4.0, "points": 80, "cocoa": 0.04},
	"balloon": {"hp": 2.0, "speed": 1.5, "scale": 0.9, "wall_dps": 6.0, "points": 250, "cocoa": 0.15, "balloons": 3},
	"shield": {"hp": 4.0, "speed": 1.45, "scale": 1.1, "wall_dps": 8.0, "points": 300, "cocoa": 0.2, "shield": 3},
	# Simple mode's practice snowman: stands still, glows, one hit knocks it over.
	"target": {"hp": 1.0, "speed": 0.0, "scale": 0.85, "points": 0, "cocoa": 0.0},
	"yeti": {"hp": 110.0, "speed": 0.8, "scale": 2.2, "wall_dps": 20.0, "throw_cd": 4.2, "ball_dmg": 14.0, "ball_r": 0.42, "points": 6000, "cocoa": 1.0},
}
const BALLOON_COLORS: Array[Color] = [Color(1.0, 0.3, 0.35), Color(0.35, 0.7, 1.0), Color(1.0, 0.85, 0.25), Color(0.5, 1.0, 0.45)]
const FLOAT_HEIGHT := 3.6
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
var balloons := 0  # balloon snowmen: balloons left (floats while > 0)
var balloon_nodes: Array[Node3D] = []
var shield_hp := 0
var shield_node: Node3D
var eyes: Array[MeshInstance3D] = []
var arms: Array[MeshInstance3D] = []
var blink_t := 2.0
var stomp_t := 6.0
var melt := 0.0  # sunshine event: shrinks a little
var glow: Node3D  # practice target: a glowing ring and a bouncing arrow
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
	balloons = d.get("balloons", 0)
	shield_hp = d.get("shield", 0)
	if kind == "sled":
		lift = 0.25


func _ready() -> void:
	add_to_group("snowmen")
	if d.is_empty():
		d = KINDS[kind]
		s = d.scale
		height = 2.2 * s
		lift = 0.25 if kind == "sled" else 0.0
		balloons = d.get("balloons", 0)
		shield_hp = d.get("shield", 0)
	blink_t = randf_range(1.0, 4.0)
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
	if kind == "yeti":
		_build_yeti()
		return
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
		eyes.append(_part(main.sphere_mesh(0.035), main.mat("coal"), Vector3(x, y0 + 1.7, -0.23)))
	# A coal smile and coal buttons.
	for i in 5:
		var a := -0.5 + i * 0.25
		_part(main.sphere_mesh(0.018), main.mat("coal"), Vector3(sin(a) * 0.12, y0 + 1.53 - cos(a) * 0.03 + 0.03, -0.24 + absf(a) * 0.03))
	for i in 3:
		_part(main.sphere_mesh(0.03), main.mat("coal"), Vector3(0, y0 + 0.98 + i * 0.13, -0.355 + absf(i - 1) * 0.02))
	# Stick arms (they wave while walking).
	var arm := BoxMesh.new()
	arm.size = Vector3(0.62, 0.04, 0.04)
	for side in [-1.0, 1.0]:
		var a := _part(arm, main.mat("stick"), Vector3(side * 0.55, y0 + 1.22, 0), Vector3(0, 0, side * 0.45))
		a.set_meta("side", side)
		arms.append(a)
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
	elif kind != "bunny":
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
	if kind == "bunny":
		# Long floppy ears instead of a tall hat look cute on the little ones.
		var ear := CapsuleMesh.new()
		ear.radius = 0.06
		ear.height = 0.45
		ear.radial_segments = 8
		ear.rings = 2
		for side in [-1.0, 1.0]:
			_part(ear, main.mat("snow"), Vector3(side * 0.11, y0 + 2.1, 0.0), Vector3(0, 0, side * 0.25))
	if kind == "balloon":
		for i in balloons:
			var bn := Node3D.new()
			var a := TAU * i / balloons
			bn.position = Vector3(cos(a) * 0.35, y0 + 2.75 + (i % 2) * 0.2, sin(a) * 0.35)
			body.add_child(bn)
			var ball := MeshInstance3D.new()
			ball.mesh = main.sphere_mesh(0.24)
			ball.material_override = main.make_material(BALLOON_COLORS[i % BALLOON_COLORS.size()], 0.6)
			ball.scale = Vector3(1.0, 1.2, 1.0)
			bn.add_child(ball)
			var cord := MeshInstance3D.new()
			var sm := CylinderMesh.new()
			sm.top_radius = 0.006
			sm.bottom_radius = 0.006
			sm.height = 0.8
			sm.radial_segments = 4
			sm.rings = 1
			cord.mesh = sm
			cord.material_override = main.mat("stick")
			cord.position = Vector3(0, -0.6, 0)
			bn.add_child(cord)
			balloon_nodes.append(bn)
	if kind == "shield":
		shield_node = Node3D.new()
		shield_node.position = Vector3(0.0, y0 + 1.05, -0.52)
		body.add_child(shield_node)
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.42
		cm.bottom_radius = 0.48
		cm.height = 0.06
		cm.radial_segments = 16
		cm.rings = 1
		disc.mesh = cm
		disc.material_override = main.mat("ice")
		disc.rotation.x = PI / 2.0
		shield_node.add_child(disc)
		var boss := MeshInstance3D.new()
		boss.mesh = main.sphere_mesh(0.08)
		boss.material_override = main.mat("gem")
		boss.position.z = -0.05
		shield_node.add_child(boss)
	if kind == "target":
		_build_target_glow()
	if kind == "sled":
		var deck := BoxMesh.new()
		deck.size = Vector3(0.9, 0.12, 1.5)
		_part(deck, main.mat("sled"), Vector3(0, 0.2, 0))
		var runner := BoxMesh.new()
		runner.size = Vector3(0.06, 0.06, 1.7)
		for x in [-0.38, 0.38]:
			_part(runner, main.mat("stick"), Vector3(x, 0.05, -0.05))
	for c in body.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if s > 1.5 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Practice target: a golden ring on the snow and a golden arrow bobbing over its hat ("hit me!").
func _build_target_glow() -> void:
	glow = Node3D.new()
	add_child(glow)
	var gm: StandardMaterial3D = main.make_material(Color(1.0, 0.82, 0.3), 3.0)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.62
	tm.outer_radius = 0.78
	tm.rings = 20
	tm.ring_segments = 4
	ring.mesh = tm
	ring.material_override = gm
	ring.position.y = 0.04
	glow.add_child(ring)
	var arrow := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.16
	cm.bottom_radius = 0.0
	cm.height = 0.32
	cm.radial_segments = 8
	cm.rings = 1
	arrow.mesh = cm
	arrow.material_override = gm
	arrow.position.y = 2.75 * s
	arrow.name = "Arrow"
	glow.add_child(arrow)
	for c in glow.get_children():
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The YETI: a big fluffy blue-white beast with horns, a dark face and huge eyes.
func _build_yeti() -> void:
	var fur := main.make_material(Color(0.82, 0.9, 1.0), 0.05) as StandardMaterial3D
	fur.roughness = 1.0
	var face := main.make_material(Color(0.25, 0.35, 0.6), 0.0) as StandardMaterial3D
	_part(main.sphere_mesh(0.62), fur, Vector3(0, 0.62, 0))
	_part(main.sphere_mesh(0.48), fur, Vector3(0, 1.35, 0))
	var f := _part(main.sphere_mesh(0.3), face, Vector3(0, 1.45, -0.28))
	f.scale = Vector3(1.0, 0.9, 0.55)
	for x in [-0.12, 0.12]:
		var w := _part(main.sphere_mesh(0.09), main.mat("snow"), Vector3(x, 1.55, -0.42))
		w.scale = Vector3(1.0, 1.0, 0.6)
		eyes.append(_part(main.sphere_mesh(0.045), main.mat("coal"), Vector3(x, 1.55, -0.48)))
	var mouth := _part(main.sphere_mesh(0.09), main.make_material(Color(0.6, 0.15, 0.25), 0.3), Vector3(0, 1.33, -0.43))
	mouth.scale = Vector3(1.4, 0.7, 0.5)
	for side in [-1.0, 1.0]:
		var horn := CylinderMesh.new()
		horn.top_radius = 0.0
		horn.bottom_radius = 0.08
		horn.height = 0.35
		horn.radial_segments = 8
		horn.rings = 1
		_part(horn, main.mat("lid"), Vector3(side * 0.32, 1.78, 0.0), Vector3(0, 0, -side * 0.6))
		var arm := CapsuleMesh.new()
		arm.radius = 0.16
		arm.height = 0.9
		arm.radial_segments = 8
		arm.rings = 2
		var a := _part(arm, fur, Vector3(side * 0.62, 1.1, -0.05), Vector3(0, 0, side * 0.35))
		a.set_meta("side", side)
		arms.append(a)
		_part(main.sphere_mesh(0.2), fur, Vector3(side * 0.28, 0.12, -0.1))  # feet
	var crown := CylinderMesh.new()
	crown.top_radius = 0.2
	crown.bottom_radius = 0.16
	crown.height = 0.18
	crown.radial_segments = 10
	crown.cap_top = false
	_part(crown, main.mat("crown"), Vector3(0, 1.92, 0))
	for c in body.get_children():
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Does a ball at p (radius r) touch this snowman? Tests its three body spheres.
func hit_test(p: Vector3, r: float) -> bool:
	var local := p - global_position
	if local.y > (lift + 2.2) * s + r and balloons <= 0:
		return false
	for sp in SPHERES:
		var c := Vector3(0, (lift + float(sp[0])) * s, 0)
		if local.distance_to(c) < float(sp[1]) * s + r:
			return true
	return false


## Which balloon (if any) a ball at p touches, or -1.
func balloon_hit(p: Vector3, r: float) -> int:
	if glow != null:
		var k := 1.0 + 0.12 * sin(t * 5.0)
		glow.scale = Vector3(k, 1.0, k)
		var arrow := glow.get_node("Arrow") as Node3D
		arrow.position.y = 2.75 * s + absf(sin(t * 3.5)) * 0.25
		arrow.scale = Vector3.ONE / k
		if not ghost:
			body.rotation.z = sin(t * 2.5) * 0.06  # a cheeky wobble
	for i in balloon_nodes.size():
		var bn := balloon_nodes[i]
		if bn.visible and bn.global_position.distance_to(p) < 0.3 * s + r:
			return i
	return -1


## Host: a balloon popped. With none left the snowman tumbles down.
func pop_balloon(i: int) -> void:
	if i < 0 or i >= balloon_nodes.size() or not balloon_nodes[i].visible:
		return
	balloon_nodes[i].visible = false
	balloons = maxi(0, balloons - 1)
	main.puff(balloon_nodes[i].global_position, BALLOON_COLORS[i % BALLOON_COLORS.size()], 14, 0.07)
	main.sound("hit", -2.0, 1.9)
	main.popup(balloon_nodes[i].global_position + Vector3.UP * 0.4, "POP!", BALLOON_COLORS[i % BALLOON_COLORS.size()])


## Does the ice shield stop a ball flying with velocity vel? (Flat throws from the front.)
func shield_blocks(vel: Vector3) -> bool:
	if shield_hp <= 0 or shield_node == null:
		return false
	var facing := Basis(Vector3.UP, rotation.y) * Vector3(0, 0, -1)
	var flat := Vector3(vel.x, 0.0, vel.z)
	if flat.length() < 0.1:
		return false
	var head_on := (-flat.normalized()).dot(facing) > 0.35
	var steep := vel.y < -0.75 * flat.length()  # a high lob drops in over the shield
	return head_on and not steep


func hit_shield(big: bool) -> void:
	shield_hp = 0 if big else shield_hp - 1
	squash = 0.6
	if shield_hp <= 0:
		if shield_node:
			shield_node.visible = false
		main.burst(global_position + Vector3.UP * 1.2 * s, Color(0.7, 0.9, 1.0), 20, 0.09)
		main.popup(global_position + Vector3.UP * (height + 0.5), "SHIELD BROKEN!", Color(0.7, 0.9, 1.0))
		main.sound("big_kill", -4.0, 1.8)
	else:
		main.popup(global_position + Vector3.UP * (height + 0.4), "BLOCKED! (%d)" % shield_hp, Color(0.7, 0.9, 1.0))
		main.sound("zap", -6.0, 1.4)


## Host: the small extra state the TV draws (balloons left, shield up).
func net_aux() -> int:
	return balloons * 10 + shield_hp


func radius() -> float:
	return 0.5 * s


# --- Host simulation ---------------------------------------------------------

func _physics_process(delta: float) -> void:
	if ghost or dead:
		return
	if main.game_over:
		bashing = false
		return
	if kind == "target":
		t += delta
		return  # practice targets just stand there and wobble
	t += delta
	spawn_grace -= delta
	throw_cd -= delta
	var pos := global_position
	var target := pos
	bashing = false
	var R: float = main.fort_r
	var seg_up: bool = main.seg_hp[seg] > 0.0
	var flat_r := Vector2(pos.x, pos.z).length()
	var weather: String = main.director().event_name
	if weather == "sunshine":
		# The sun melts them a little (bosses barely notice).
		hp -= max_hp * (0.012 if kind in ["king", "yeti"] else 0.06) * delta
		melt = minf(1.0, melt + delta * 0.2)
		if hp <= 0.0:
			main.popup(global_position + Vector3.UP * height, "MELTED!", Color(1.0, 0.85, 0.4))
			_collapse(-1)
			return
	var floating := balloons > 0 and not inside
	if floating:
		# Balloon snowmen drift right over the walls into the fort.
		target = Vector3.ZERO
		if flat_r < R - 1.2:
			inside = true
	elif not inside:
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
	var spd := speed * (0.55 if weather == "blizzard" else 1.0)
	if to.length() > 0.05:
		step = to.normalized() * minf(spd * delta, to.length())
	for other in get_tree().get_nodes_in_group("snowmen"):
		if other == self or other.ghost:
			continue
		var away: Vector3 = pos - other.global_position
		away.y = 0.0
		var min_d: float = radius() + other.radius() + 0.1
		var dl := away.length()
		if dl < min_d and dl > 0.001:
			step += away / dl * (min_d - dl) * 0.2
	var want_y := FLOAT_HEIGHT if floating else 0.0
	global_position = pos + step
	global_position.y = move_toward(pos.y, want_y, delta * (1.2 if want_y > pos.y else 5.0))
	if kind == "yeti" and bashing:
		stomp_t -= delta
		if stomp_t <= 0.0:
			stomp_t = 5.0
			for k in [-1, 0, 1]:
				main.damage_segment(posmod(seg + k, main.segments), 14.0)
			main.burst(global_position + Vector3.UP * 0.3, Color(0.85, 0.92, 1.0), 30, 0.14)
			main.sound("big_kill", 0.0, 0.5)
			main.yeti_stomp(global_position)
	var face := to if to.length() > 0.1 else -pos
	if face.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), 1.0 - exp(-6.0 * delta))
	if kind == "king" or kind == "yeti":
		summon_cd -= delta
		if summon_cd <= 0.0 and spawn_grace <= 0.0:
			summon_cd = 9.0 if kind == "king" else 12.0
			main.summon_minions(global_position, 2, "snowman" if kind == "king" else "bunny")
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
	if item.size() > 6 or balloons > 0 or shield_hp > 0:
		var aux: int = item[6] if item.size() > 6 else 0
		var b := aux / 10
		while balloons > b and balloons > 0:
			var i := balloons - 1
			if i < balloon_nodes.size() and balloon_nodes[i].visible:
				balloon_nodes[i].visible = false
				main.puff(balloon_nodes[i].global_position, BALLOON_COLORS[i % BALLOON_COLORS.size()], 14, 0.07)
			balloons -= 1
		var sh := aux % 10
		if sh <= 0 and shield_node != null and shield_node.visible:
			shield_node.visible = false
		shield_hp = sh


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
		var m := 1.0 - melt * 0.15
		body.scale = Vector3(1.0 + sq, (1.0 - sq) * m, 1.0 + sq) * s
	if main.director().event_name != "sunshine":
		melt = maxf(0.0, melt - delta * 0.5)
	elif ghost:
		melt = minf(1.0, melt + delta * 0.2)
	blink_t -= delta
	var shut := blink_t < 0.12
	if blink_t <= 0.0:
		blink_t = randf_range(2.0, 5.0)
	for e in eyes:
		e.scale.y = 0.2 if shut else 1.0
	for a in arms:
		var side: float = a.get_meta("side")
		var wave_amt := 0.5 if bashing else 0.25 * move_amt
		a.rotation.z = side * (0.45 + sin(t * 6.0 + side) * wave_amt)
	if glow != null:
		var k := 1.0 + 0.12 * sin(t * 5.0)
		glow.scale = Vector3(k, 1.0, k)
		var arrow := glow.get_node("Arrow") as Node3D
		arrow.position.y = 2.75 * s + absf(sin(t * 3.5)) * 0.25
		arrow.scale = Vector3.ONE / k
		if not ghost:
			body.rotation.z = sin(t * 2.5) * 0.06  # a cheeky wobble
	for i in balloon_nodes.size():
		var bn := balloon_nodes[i]
		bn.rotation.z = sin(t * 1.7 + i) * 0.15
