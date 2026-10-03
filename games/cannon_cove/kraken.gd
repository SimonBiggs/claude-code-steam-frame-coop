extends Node3D
## THE KRAKEN - the final wave's boss. Its huge head rises off one side of our ship and it sends
## tentacles to smash the deck. While it has tentacles its eyes stay shut and cannonballs just bounce
## off ("CLANG!"): the deckhands' muskets and the gunner knock the tentacles away, then the Kraken
## roars, OPENS ITS EYES and the gunner has a few seconds to hit it. Three rounds of that (it dives and
## comes up on the other side each time) and it sinks for good. A golden cannonball stuns it open.
## On the client it's a ghost placed from snapshots.

const World := preload("res://games/cannon_cove/world.gd")

const RISE_TIME := 2.5
const GUARD_MAX := 32.0  # it opens its eyes anyway after this long (so a small crew can't get stuck)
const OPEN_TIME := 10.0
const DIVE_TIME := 2.4
const HITS_PER_ROUND := 3
const HEAD_R := 3.4
const DIST := 26.0

var main
var net_id := 0
var ghost := false
var side := 1.0
var hp := 9.0
var max_hp := 9.0
var state := "rise"  # rise, guard, open, dive, dying
var state_t := 0.0
var rise := 0.0
var eye_open := 0.0
var round_hits := 0
var rounds := 0
var tentacles: Array = []
var roar_t := 7.0
var flash := 0.0
var blink := 0.0
var t := 0.0

var head: Node3D
var skin: StandardMaterial3D
var lids: Array[MeshInstance3D] = []
var irises: Array[MeshInstance3D] = []
var iris_mat: StandardMaterial3D
var label: Label3D
var bar_fill: MeshInstance3D
var foam: MeshInstance3D


func _ready() -> void:
	add_to_group("krakens")
	head = Node3D.new()
	add_child(head)
	skin = World.mat(Color(0.5, 0.2, 0.62), 0.0, 0.45)
	skin.emission_enabled = true
	skin.emission = Color(1.0, 0.5, 0.6)
	skin.emission_energy_multiplier = 0.0
	var spot := World.mat(Color(0.75, 0.4, 0.85))
	var dome := World.sphere(head, HEAD_R, Vector3.ZERO, skin, 20)
	dome.scale = Vector3(1.0, 1.25, 0.95)
	for sp in [Vector3(1.6, 2.6, 1.4), Vector3(-1.8, 2.2, 1.2), Vector3(0.3, 3.6, 0.9), Vector3(-0.6, 1.4, 2.6)]:
		var s := World.sphere(head, 0.55, sp, spot, 8)
		s.scale = Vector3(1.0, 0.5, 1.0)
	# Eyes look towards our ship (local -Z).
	var white := World.mat(Color(0.98, 0.97, 0.9))
	iris_mat = World.mat(Color(1.0, 0.85, 0.1), 0.5)
	var pupil_mat := World.mat(Color(0.03, 0.02, 0.05))
	for ex in [-1.3, 1.3]:
		var e := World.sphere(head, 0.95, Vector3(ex, 0.9, -2.75), white, 14)
		var iris := World.sphere(e, 0.55, Vector3(0, 0, -0.8), iris_mat, 12)
		iris.scale = Vector3(1.0, 1.0, 0.5)
		World.sphere(iris, 0.3, Vector3(0, 0, -0.35), pupil_mat, 8)
		irises.append(iris)
		var lid := World.sphere(head, 1.18, Vector3(ex, 0.9, -2.7), skin, 14)
		lids.append(lid)
		var brow := World.box(head, Vector3(1.6, 0.35, 0.5), Vector3(ex, 2.05, -2.85), World.mat(Color(0.35, 0.12, 0.45)))
		brow.rotation.z = 0.35 * signf(ex)
	var beak := World.cyl(head, 0.0, 0.7, 1.4, Vector3(0, -0.6, -3.2), World.mat(Color(1.0, 0.75, 0.3)), 8)
	beak.rotation.x = PI
	for c in head.get_children():
		if c is GeometryInstance3D:
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	foam = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = HEAD_R * 0.95
	tm.outer_radius = HEAD_R * 1.45
	tm.rings = 20
	tm.ring_segments = 4
	foam.mesh = tm
	var fm := World.mat(Color(0.95, 0.98, 1.0, 0.6), 0.4)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foam.material_override = fm
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	foam.scale = Vector3(1.0, 0.15, 1.0)
	add_child(foam)
	label = Label3D.new()
	label.font_size = 110
	label.outline_size = 32
	label.pixel_size = 0.02
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.no_depth_test = true
	add_child(label)
	# Health bar.
	var bar_root := Node3D.new()
	bar_root.name = "Bar"
	add_child(bar_root)
	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(7.0, 0.6)
	bg.mesh = q
	var bg_mat := World.mat(Color(0, 0, 0, 0.6))
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg_mat.billboard_keep_scale = true
	bg.material_override = bg_mat
	bar_root.add_child(bg)
	bar_fill = MeshInstance3D.new()
	var q2 := QuadMesh.new()
	q2.size = Vector2(6.7, 0.4)
	bar_fill.mesh = q2
	var fill_mat := World.mat(Color(0.85, 0.35, 1.0), 2.0)
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fill_mat.billboard_keep_scale = true
	fill_mat.render_priority = 1
	bar_fill.material_override = fill_mat
	bar_root.add_child(bar_fill)
	_update_pose(0.0)


func head_center() -> Vector3:
	return head.global_position + Vector3.UP * 0.6


func vulnerable() -> bool:
	return state == "open" and eye_open > 0.4


func _physics_process(delta: float) -> void:
	t += delta
	flash = maxf(0.0, flash - delta * 3.0)
	if not ghost:
		_think(delta)
	_update_pose(delta)


func _think(delta: float) -> void:
	state_t += delta
	match state:
		"rise":
			rise = minf(1.0, state_t / RISE_TIME)
			eye_open = 0.0
			if state_t >= RISE_TIME:
				_set_state("guard")
				main.kraken_summon(self)
		"guard":
			eye_open = maxf(0.0, eye_open - delta * 2.0)
			roar_t -= delta
			if roar_t <= 0.0:
				roar_t = randf_range(8.0, 12.0)
				main.kraken_roar(self)
			var alive := 0
			for tn in tentacles:
				if is_instance_valid(tn) and tn.alive():
					alive += 1
			if alive == 0 or state_t > GUARD_MAX:
				open_eyes()
		"open":
			eye_open = minf(1.0, eye_open + delta * 3.0)
			if state_t >= OPEN_TIME or round_hits >= HITS_PER_ROUND:
				_set_state("dive")
				main.kraken_dive(self)
		"dive":
			eye_open = maxf(0.0, eye_open - delta * 3.0)
			rise = maxf(0.0, 1.0 - state_t / DIVE_TIME)
			if state_t >= DIVE_TIME:
				side = -side
				position = Vector3(side * DIST, position.y, randf_range(-4.0, 5.0))
				_set_state("rise")
		"dying":
			eye_open = maxf(0.0, eye_open - delta)
			rise = maxf(0.0, 1.0 - state_t / 4.0)
			if state_t > 4.5:
				queue_free()


func _set_state(s: String) -> void:
	state = s
	state_t = 0.0


## Its tentacles are gone (or the golden ball stunned it): eyes open, the gunner's chance.
func open_eyes() -> void:
	if state == "open" or state == "dying":
		return
	_set_state("open")
	round_hits = 0
	main.kraken_eyes_open(self)


## Host: a cannonball hit the head. Returns "hurt", "clang" or "dead".
func hit(damage: float, mega: bool) -> String:
	if state == "dying":
		return "clang"
	if not vulnerable():
		if mega:
			open_eyes()
			hp -= 1.0
			flash = 1.0
			return "hurt"
		return "clang"
	hp -= damage
	round_hits += 1
	flash = 1.0
	if hp <= 0.0:
		hp = 0.0
		_set_state("dying")
		return "dead"
	return "hurt"


func _update_pose(delta: float) -> void:
	var sea: float = main.sea_level
	var e := rise * rise * (3.0 - 2.0 * rise)
	var sway := sin(t * 0.8) * 0.12
	head.position = Vector3(0, -HEAD_R * 2.2 + e * (HEAD_R * 2.2 + 2.4) + sin(t * 1.3) * 0.25, 0)
	head.rotation = Vector3(sin(t * 0.6) * 0.05, sway, sin(t * 0.9) * 0.06)
	global_position.y = sea
	# Face our ship.
	var to := -Vector3(global_position.x, 0.0, global_position.z)
	if to.length() > 0.1:
		rotation.y = atan2(-to.x, -to.z)
	# Eyelids: closed (covering the eyes) while guarding, slide up when open; blink now and then.
	blink -= delta
	if blink < -3.5:
		blink = 0.18
	var closed := 1.0 - eye_open
	if blink > 0.0 and eye_open > 0.5:
		closed = 1.0
	for lid in lids:
		lid.scale = Vector3(1.0, lerpf(0.25, 1.0, closed), 1.0)
		lid.position.y = 0.9 + (1.0 - closed) * 0.85
	iris_mat.emission_energy_multiplier = 0.5 + eye_open * (3.0 + 2.0 * sin(t * 10.0))
	for iris in irises:
		var look := sin(t * 1.7) * 0.25
		iris.position.x = look
	skin.emission_energy_multiplier = flash * 1.8
	foam.visible = rise > 0.05
	foam.position = Vector3(0, 0.1 + sin(t * 2.0) * 0.05, 0)
	foam.rotation.y = t * 0.3
	label.position = Vector3(0, head.position.y + HEAD_R * 1.25 + 2.2, 0)
	label.visible = rise > 0.8 and state != "dying"
	if state == "open":
		label.text = "FIRE AT THE EYES!"
		label.modulate = Color(1.0, 0.9, 0.2) if int(t * 4.0) % 2 == 0 else Color(1.0, 0.5, 0.2)
	else:
		label.text = "SHOOT ITS TENTACLES!"
		label.modulate = Color(0.85, 0.6, 1.0)
	var bar := get_node("Bar") as Node3D
	bar.position = Vector3(0, label.position.y + 1.6, 0)
	bar.visible = rise > 0.8
	bar_fill.scale.x = maxf(0.02, hp / max_hp)


## Snapshot: [id, pos, state, hp, max_hp, eye_open, rise, side]
func net_state() -> Array:
	return [net_id, global_position, state, hp, max_hp, eye_open, rise, side]


func apply_net(item: Array) -> void:
	var p: Vector3 = item[1]
	position.x = p.x
	position.z = p.z
	var s: String = item[2]
	state = s
	var new_hp: float = item[3]
	if new_hp < hp:
		flash = 1.0
	hp = new_hp
	max_hp = item[4]
	eye_open = item[5]
	rise = item[6]
	side = item[7]
