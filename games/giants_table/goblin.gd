extends "res://games/giants_table/toss.gd"
## A goblin marching on the campfire. Kinds:
##  "goblin"  - anyone can beat it (sword, crossbow, squash, throw, drop off the table)
##  "armored" - spiky armour: the giant can't hold it and boulders only stun it; knights must beat it
##  "ogre"    - too big for the knights: the giant must lift it and throw it off the table (or drop it hard twice)

const KINDS := {
	"goblin": {"hp": 2.0, "speed": 2.2, "scale": 1.0, "color": Color(0.45, 0.78, 0.3), "points": 10},
	"armored": {"hp": 6.0, "speed": 1.7, "scale": 1.1, "color": Color(0.5, 0.72, 0.35), "points": 25},
	"ogre": {"hp": 2.0, "speed": 1.15, "scale": 2.3, "color": Color(0.62, 0.5, 0.82), "points": 50},
}
const SQUASH_SPEED := 14.0
const OGRE_HURT_SPEED := 18.0

var kind := "goblin"
var hp := 2.0
var speed := 2.2
var sc := 1.0
var color := Color.GREEN
var carrying := false
var dizzy_t := 0.0
var attack_cd := 0.0
var hop := false        # hopping up onto the table when spawned
var flee_target := Vector3.ZERO
var walk_t := 0.0
var flash_t := 0.0
var too_big_t := 0.0
var stuck_check := Vector3.ZERO
var stuck_t := 0.0
var detour_t := 0.0
var detour := Vector3.ZERO

var pivot: Node3D
var body_mat: StandardMaterial3D
var ember_orb: MeshInstance3D
var stars: Node3D
var arm_l: Node3D
var arm_r: Node3D


func setup(k: String, m) -> void:
	kind = k
	main = m
	var d: Dictionary = KINDS[k]
	hp = d.hp
	speed = d.speed
	sc = d.scale
	color = d.color
	radius = 0.35 * sc
	center_h = 0.4 * sc


func _ready() -> void:
	add_to_group("goblins")
	pivot = Node3D.new()
	add_child(pivot)
	pivot.scale = Vector3.ONE * sc
	body_mat = W.mat(color)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.2
	cap.height = 0.5
	cap.radial_segments = 10
	cap.rings = 3
	body.mesh = cap
	body.material_override = body_mat if kind != "armored" else W.mat(Color(0.62, 0.64, 0.7), 0.0, 0.3)
	body.position.y = 0.25
	pivot.add_child(body)
	var head := MeshInstance3D.new()
	head.mesh = W.sphere(0.19, 10)
	head.material_override = body_mat
	head.position.y = 0.6
	pivot.add_child(head)
	for side in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		ear.mesh = W.cyl(0.0, 0.07, 0.3, 4)
		ear.material_override = body_mat
		ear.position = Vector3(side * 0.2, 0.66, 0.0)
		ear.rotation.z = -side * 1.2
		pivot.add_child(ear)
	var eyes := MeshInstance3D.new()
	eyes.mesh = W.box(Vector3(0.22, 0.06, 0.04))
	eyes.material_override = W.mat(Color(1.0, 0.9, 0.3), 2.5)
	eyes.position = Vector3(0, 0.63, -0.17)
	pivot.add_child(eyes)
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.22, 0.4, 0)
		pivot.add_child(arm)
		var am := MeshInstance3D.new()
		am.mesh = W.cyl(0.05, 0.05, 0.3, 5)
		am.material_override = body_mat
		am.position.y = -0.13
		arm.add_child(am)
		if side < 0.0:
			arm_l = arm
		else:
			arm_r = arm
	if kind == "goblin":
		# a little wooden club
		var club := MeshInstance3D.new()
		club.mesh = W.cyl(0.07, 0.035, 0.35, 5)
		club.material_override = W.mat(Color(0.5, 0.32, 0.17))
		club.position = Vector3(0, -0.3, -0.1)
		club.rotation.x = -1.2
		arm_r.add_child(club)
	elif kind == "armored":
		var helm := MeshInstance3D.new()
		helm.mesh = W.sphere(0.215, 10)
		var steel := W.mat(Color(0.75, 0.77, 0.82), 0.0, 0.25)
		steel.metallic = 0.8
		helm.material_override = steel
		helm.position.y = 0.66
		helm.scale = Vector3(1.0, 0.75, 1.0)
		pivot.add_child(helm)
		var spike := MeshInstance3D.new()
		spike.mesh = W.cyl(0.0, 0.06, 0.22, 5)
		spike.material_override = steel
		spike.position.y = 0.88
		pivot.add_child(spike)
		var shield := MeshInstance3D.new()
		shield.mesh = W.cyl(0.18, 0.18, 0.04, 10)
		shield.material_override = W.mat(Color(0.7, 0.25, 0.2))
		shield.rotation.x = PI / 2.0
		shield.position = Vector3(-0.08, -0.15, -0.12)
		arm_l.add_child(shield)
	else:
		# ogre: a big belly, a tuft of hair and a log club
		var belly := MeshInstance3D.new()
		belly.mesh = W.sphere(0.24, 10)
		belly.material_override = W.mat(Color(0.8, 0.68, 0.55))
		belly.position = Vector3(0, 0.25, -0.08)
		pivot.add_child(belly)
		var log_club := MeshInstance3D.new()
		log_club.mesh = W.cyl(0.08, 0.05, 0.45, 6)
		log_club.material_override = W.mat(Color(0.45, 0.28, 0.15))
		log_club.position = Vector3(0, -0.35, -0.1)
		log_club.rotation.x = -1.0
		arm_r.add_child(log_club)
	ember_orb = MeshInstance3D.new()
	ember_orb.mesh = W.sphere(0.16, 8)
	ember_orb.material_override = W.mat(Color(1.0, 0.55, 0.15), 4.0)
	ember_orb.position.y = 0.95
	ember_orb.visible = false
	ember_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(ember_orb)
	stars = Node3D.new()
	stars.position.y = 0.95
	stars.visible = false
	pivot.add_child(stars)
	for i in 3:
		var st := MeshInstance3D.new()
		st.mesh = W.box(Vector3(0.09, 0.09, 0.09))
		st.material_override = W.mat(Color(1.0, 0.95, 0.4), 3.0)
		var a := TAU * i / 3.0
		st.position = Vector3(cos(a) * 0.25, 0, sin(a) * 0.25)
		stars.add_child(st)
	for c in pivot.get_children():
		if c is GeometryInstance3D and c != pivot.get_child(0):
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func can_grab() -> bool:
	return kind != "armored"


func on_grabbed() -> void:
	super.on_grabbed()
	hop = false
	dizzy_t = 0.0


func _physics_process(delta: float) -> void:
	flash_t -= delta
	too_big_t -= delta
	body_mat.emission_enabled = flash_t > 0.0
	body_mat.emission = Color.WHITE
	body_mat.emission_energy_multiplier = 1.5
	walk_t += delta
	ember_orb.visible = carrying
	stars.visible = dizzy_t > 0.0
	if stars.visible:
		stars.rotation.y += delta * 6.0
	if ghost:
		ghost_update(delta)
		_animate(delta, global_position.distance_to(net_target) > 0.02)
		return
	if held:
		_animate(delta, true)
		arm_l.rotation.z = sin(walk_t * 20.0) * 1.2 - 1.0
		arm_r.rotation.z = -sin(walk_t * 20.0) * 1.2 + 1.0
		return
	if flying:
		pivot.rotation.x += delta * 8.0 if not hop else 0.0
		var before := vel
		fly(delta)
		if is_instance_valid(self) and flying and before.length() > 9.0 and not hop:
			_bowl(before)
		return
	pivot.rotation.x = 0.0
	if dizzy_t > 0.0:
		dizzy_t -= delta
		return
	_think(delta)


func _animate(_delta: float, moving: bool) -> void:
	if moving:
		pivot.rotation.z = sin(walk_t * 12.0) * 0.18
		pivot.position.y = absf(sin(walk_t * 12.0)) * 0.06 * sc
		arm_l.rotation.x = sin(walk_t * 12.0) * 0.8
		arm_r.rotation.x = -sin(walk_t * 12.0) * 0.8
	else:
		pivot.rotation.z = lerpf(pivot.rotation.z, 0.0, 0.2)
		pivot.position.y = 0.0


func _think(delta: float) -> void:
	attack_cd -= delta
	var pos := global_position
	# Fight a knight that's right next to us (unless we're running off with an ember).
	if not carrying:
		var reach := radius + 0.55 + (0.5 if kind == "ogre" else 0.0)
		for k in main.knights():
			if not k.active or k.is_down or k.carried:
				continue
			var kp: Vector3 = k.global_position
			if Vector2(kp.x - pos.x, kp.z - pos.z).length() < reach and absf(kp.y - pos.y) < 1.2 * sc:
				rotation.y = atan2(-(kp.x - pos.x), -(kp.z - pos.z))
				if attack_cd <= 0.0:
					attack_cd = 2.0 if kind == "ogre" else 1.2
					arm_r.rotation.x = -1.8
					var tw := create_tween()
					tw.tween_property(arm_r, "rotation:x", 0.6, 0.15)
					main.knight_hurt(k, 26.0 if kind == "ogre" else 10.0, pos)
				_animate(delta, false)
				return
	# Where to?
	var target := Vector3.ZERO
	if carrying:
		target = flee_target
	else:
		var best_d := 5.0
		for e in get_tree().get_nodes_in_group("embers"):
			if e.held or e.flying:
				continue
			var d: float = e.global_position.distance_to(pos)
			if d < best_d:
				best_d = d
				target = e.global_position
				if d < radius + 0.45:
					main.goblin_takes_loose_ember(self, e)
					return
	var to := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	var dist := to.length()
	if not carrying and target == Vector3.ZERO and dist < W.FIRE_R + radius + 0.35:
		main.goblin_steals(self)
		return
	var dir := to / maxf(dist, 0.001)
	# Heading for the fire or the edge: follow the flow field around the village.
	var on_flow := false
	if carrying or target == Vector3.ZERO:
		var fd := W.flow_dir(pos, kind == "ogre", carrying)
		if fd != Vector3.ZERO:
			dir = fd
			on_flow = true
	# Not getting anywhere? Wander off sideways for a moment.
	stuck_t += delta
	if stuck_t > 1.5:
		if pos.distance_to(stuck_check) < 0.4 and detour_t <= 0.0:
			detour_t = 1.2
			var s := 1.0 if randf() < 0.5 else -1.0
			detour = Vector3(-dir.z * s, 0.0, dir.x * s) - dir * 0.3
		stuck_t = 0.0
		stuck_check = pos
	if detour_t > 0.0:
		detour_t -= delta
		dir = (dir * 0.2 + detour).normalized()
	# Steer around trees, cottages and boulders that are in the way.
	var side := Vector3(-dir.z, 0.0, dir.x)
	var steer := Vector3.ZERO
	var statics: Array = W.obstacles()
	if kind == "ogre":
		statics = statics.filter(func(o: Array) -> bool: return o[2] > W.TREE_R)  # ogres trample trees
	var blockers: Array = [] if on_flow else statics.duplicate()
	var n_static := blockers.size()
	for b in get_tree().get_nodes_in_group("boulders"):
		if not b.held and not b.flying:
			var bp: Vector3 = b.global_position
			blockers.append([bp.x, bp.z, b.radius])
	for o in blockers:
		var off := Vector3(o[0] - pos.x, 0.0, o[1] - pos.z)
		var ahead := off.dot(dir)
		if ahead < 0.0 or ahead > 2.5 or ahead > dist:
			continue
		var lateral := off.dot(side)
		var clear: float = o[2] + radius + 0.25
		if absf(lateral) < clear:
			steer -= side * signf(lateral if absf(lateral) > 0.01 else 1.0) * (clear - absf(lateral)) * (2.6 - ahead)
	for g in get_tree().get_nodes_in_group("goblins"):
		if g == self or g.held or g.flying:
			continue
		var off: Vector3 = pos - g.global_position
		off.y = 0.0
		var d := off.length()
		var min_d: float = radius + g.radius + 0.1
		if d < min_d and d > 0.001:
			steer += off / d * (min_d - d) * 4.0
	var move := (dir + steer).normalized()
	var spd := speed * (0.85 if carrying else 1.0)
	if W.in_water(pos.x, pos.z):
		spd *= 0.5
	var np := pos + move * spd * delta
	if kind == "ogre":
		for o in statics:
			var off := Vector2(np.x - o[0], np.z - o[1])
			var min_d: float = o[2] + radius
			if off.length() < min_d and off.length() > 0.001:
				off = off.normalized() * min_d
				np.x = o[0] + off.x
				np.z = o[1] + off.y
	else:
		np = W.push_out(np, radius)
	for o in blockers.slice(n_static):
		var off := Vector2(np.x - o[0], np.z - o[1])
		var min_d: float = o[2] + radius
		if off.length() < min_d and off.length() > 0.001:
			off = off.normalized() * min_d
			np.x = o[0] + off.x
			np.z = o[1] + off.y
	var g_h := W.height(np.x, np.z)
	np.y = g_h if g_h > -50.0 else pos.y
	global_position = np
	rotation.y = lerp_angle(rotation.y, atan2(-move.x, -move.z), 1.0 - exp(-10.0 * delta))
	_animate(delta, true)
	if carrying and Vector2(np.x, np.z).length() > W.EDGE - 0.35:
		main.goblin_escaped(self)


## A thrown goblin bowls over the goblins it flies into.
func _bowl(v: Vector3) -> void:
	for g in get_tree().get_nodes_in_group("goblins"):
		if g == self or g.held or g.flying:
			continue
		if g.grab_center().distance_to(grab_center()) < radius + g.radius + 0.15:
			g.hit_by_object(v, self)


## Hit by a flying boulder or goblin.
func hit_by_object(v: Vector3, by) -> void:
	if kind == "armored":
		dizzy_t = 2.0
		main.popup(grab_center() + Vector3.UP * 0.6, "CLANG!", Color(0.8, 0.85, 1.0))
		main.sound("hit", -2.0, 0.6)
		global_position += Vector3(v.x, 0.0, v.z).normalized() * 0.5
		return
	if kind == "ogre":
		hp -= 1.0
		flash_t = 0.15
		if hp <= 0.0:
			main.goblin_defeated(self, "boulder", by)
		else:
			dizzy_t = 2.5
			main.popup(grab_center() + Vector3.UP * 1.2, "OOF!", Color(1.0, 0.8, 0.4))
			main.sound("hit", 0.0, 0.5)
		return
	main.goblin_defeated(self, "squash", by)


## Hit by a knight's sword or crossbow bolt.
func hit_by_knight(damage: float, dir: Vector3, knight) -> void:
	if kind == "ogre":
		global_position = W.push_out(global_position + dir * 0.15, radius)
		if too_big_t <= 0.0:
			too_big_t = 2.0
			main.popup(grab_center() + Vector3.UP * 1.4, "TOO BIG!\nGiant, throw me!", Color(1.0, 0.75, 0.45))
		main.sound("hit", -6.0, 0.5)
		return
	hp -= damage
	flash_t = 0.12
	main.sound("hit", -6.0, 1.3 if kind == "goblin" else 0.8)
	if hp <= 0.0:
		main.goblin_defeated(self, "knight", knight)
		return
	if not flying and not held:
		var np := W.push_out(global_position + dir * 0.45, radius)
		var gh := W.height(np.x, np.z)
		if gh > -50.0:
			np.y = gh
			global_position = np


func _landed(impact: float) -> void:
	super._landed(impact)
	if hop:
		hop = false
		return
	if kind == "ogre":
		if impact > OGRE_HURT_SPEED:
			hp -= 1.0
			flash_t = 0.15
			main.add_thud(global_position, impact)
			if hp <= 0.0:
				main.goblin_defeated(self, "slam", null)
				return
			main.popup(grab_center() + Vector3.UP * 1.2, "OOF! Once more!", Color(1.0, 0.8, 0.4))
		dizzy_t = 2.5
		return
	if impact > SQUASH_SPEED:
		main.goblin_defeated(self, "squash", null)
	else:
		dizzy_t = 1.4
		main.sound("hit", -10.0, 1.6)


func _fell_off() -> void:
	main.goblin_defeated(self, "fell", null)


func net_item() -> Array:
	return [net_id, kind, global_position, rotation.y, flags(), hp]


func flags() -> int:
	return int(carrying) | (int(held) << 1) | (int(dizzy_t > 0.0) << 2) | (int(flying) << 3)


func apply_net(item: Array) -> void:
	super.apply_net(item)
	var f: int = item[4]
	carrying = f & 1 != 0
	held = f & 2 != 0
	dizzy_t = 1.0 if f & 4 != 0 else 0.0
	flying = f & 8 != 0
	var new_hp: float = item[5]
	if new_hp < hp - 0.01:
		flash_t = 0.12
	hp = new_hp
