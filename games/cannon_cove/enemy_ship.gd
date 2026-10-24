extends Node3D
## A pirate ship. It sails in from the horizon, circles our ship and fires broadsides at the deck.
## Raiders come in close and send boarders over on ropes; galleons stay further out and hit harder.
## Fire ships are little boats with a lit powder keg that try to ram us (sink them, or musket them
## when they get close, and they go KABOOM - taking nearby pirates with them).
## Treasure ships never shoot: they circle once and run - sink one for a GOLDEN cannonball.
## On the client it's a ghost, placed from snapshots.

const World := preload("res://games/cannon_cove/world.gd")

const KINDS := {
	# hp, speed, orbit radius, fire interval, gold, half-size (x, z), sail colour
	"raider": [2.0, 7.0, 17.0, 8.0, 50, Vector2(1.5, 4.2), Color(0.9, 0.15, 0.2)],
	"galleon": [4.0, 4.5, 42.0, 6.0, 100, Vector2(2.2, 6.0), Color(0.45, 0.2, 0.75)],
	"fireship": [1.0, 4.6, 0.0, 0.0, 40, Vector2(0.8, 1.7), Color(0.15, 0.12, 0.12)],
	"treasure": [3.0, 6.5, 28.0, 0.0, 150, Vector2(1.6, 4.4), Color(1.0, 0.8, 0.2)],
}
const TREASURE_STAY := 34.0  # seconds before a treasure ship turns and runs

var main
var kind := "raider"
var net_id := 0
var ghost := false
var wave := 1
var calm := false  # wave 1: slow, gentle shooting and no boarders
var hp := 2.0
var max_hp := 2.0
var speed := 7.0
var orbit_r := 17.0
var orbit_dir := 1.0
var heading := 0.0
var fire_t := 5.0
var fire_every := 8.0
var board_t := 6.0
var boarders_sent := 0
var gold := 50
var half := Vector2(1.5, 4.2)
var sinking := false
var sink_t := 0.0
var bob := 0.0
var flash := 0.0
var age := 0.0
var fleeing := false
var hull_mat: StandardMaterial3D
var bar_fill: MeshInstance3D
var model: Node3D
var mast: Node3D
var flag: Node3D
var crew: Array[Node3D] = []
var smoke_fx: CPUParticles3D
var net_target := Vector3.ZERO
var net_started := false


func setup(k: String, w: int, m) -> void:
	kind = k
	wave = w
	main = m
	var d: Array = KINDS[kind]
	max_hp = float(d[0]) + (floorf(w / 4.0) if kind != "fireship" else 0.0)
	hp = max_hp
	speed = d[1]
	orbit_r = float(d[2]) + randf_range(-2.0, 6.0)
	fire_every = maxf(3.5, float(d[3]) - w * 0.25)
	gold = d[4]
	half = d[5]
	orbit_dir = 1.0 if randf() < 0.5 else -1.0
	fire_t = randf_range(2.0, 4.0)
	bob = randf() * TAU


func mast_height() -> float:
	return 9.5 if kind == "galleon" else 7.0


func is_fireship() -> bool:
	return kind == "fireship"


func _ready() -> void:
	add_to_group("ships")
	if calm:
		fire_every += 4.0
		fire_t += 6.0
	var d: Array = KINDS[kind]
	var sail_color: Color = d[6]
	model = Node3D.new()
	add_child(model)
	hull_mat = World.mat(Color(0.32, 0.2, 0.12) if kind != "treasure" else Color(0.45, 0.28, 0.12))
	hull_mat.emission_enabled = true
	hull_mat.emission = Color(1, 1, 1)
	hull_mat.emission_energy_multiplier = 0.0
	if kind == "fireship":
		_build_fireship()
	else:
		_build_ship(sail_color)
	# Health bar above the mast (shrinks towards its centre).
	var bar_root := Node3D.new()
	bar_root.position = Vector3(0, mast_height() + 2.8 if kind != "fireship" else 3.4, 0)
	add_child(bar_root)
	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(3.0, 0.4)
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
	q2.size = Vector2(2.8, 0.26)
	bar_fill.mesh = q2
	var fill_mat := World.mat(Color(1.0, 0.25, 0.2) if kind != "treasure" else Color(1.0, 0.85, 0.2), 1.5)
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fill_mat.billboard_keep_scale = true
	fill_mat.render_priority = 1
	bar_fill.material_override = fill_mat
	bar_root.add_child(bar_fill)
	bar_root.visible = kind != "fireship"
	# A short white wake behind the stern.
	var wake := CPUParticles3D.new()
	wake.amount = 10
	wake.lifetime = 1.6
	wake.local_coords = false
	wake.position = Vector3(0, -0.6, half.y)
	wake.direction = Vector3.UP
	wake.spread = 60.0
	wake.initial_velocity_min = 0.3
	wake.initial_velocity_max = 0.8
	wake.gravity = Vector3.ZERO
	wake.scale_amount_min = 0.8
	wake.scale_amount_max = 1.6
	var fm := World.sphere_mesh(0.35, 6)
	var foam := World.mat(Color(0.95, 0.98, 1.0, 0.7), 0.3)
	foam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.material = foam
	wake.mesh = fm
	add_child(wake)
	_shadows_off(model)


func _shadows_off(n: Node) -> void:
	if n is GeometryInstance3D:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_shadows_off(c)


func _build_ship(sail_color: Color) -> void:
	var trim := World.mat(Color(0.15, 0.12, 0.1))
	var white := World.mat(Color(0.95, 0.93, 0.85))
	var glow := 0.8 if kind == "treasure" else 0.0
	var sail := World.mat(sail_color, glow)
	var w := half.x
	var l := half.y
	World.box(model, Vector3(w * 2.0, 2.0, l * 2.0 - w), Vector3(0, 0.0, w * 0.5), hull_mat)
	var side := w * sqrt(2.0)
	World.box(model, Vector3(side, 2.0, side), Vector3(0, 0.0, -l + w), hull_mat, Vector3(0, PI / 4.0, 0))
	World.box(model, Vector3(w * 2.0 + 0.05, 0.3, l * 2.0 - w), Vector3(0, 0.6, w * 0.5), sail if kind != "treasure" else World.mat(Color(1.0, 0.8, 0.2), 0.5, 0.3))
	World.box(model, Vector3(w * 2.0, 1.4, 1.6), Vector3(0, 1.4, l - 0.8), hull_mat)  # stern cabin
	World.box(model, Vector3(w * 1.2, 0.35, 0.05), Vector3(0, 1.5, l - 1.62), World.mat(Color(1.0, 0.8, 0.35), 2.0))  # lit cabin window
	var sprit := World.cyl(model, 0.06, 0.12, 3.0, Vector3(0, 1.0, -l - 0.6), trim, 6)
	sprit.rotation.x = -1.2
	# Gun ports.
	for sx in [-1.0, 1.0]:
		for i in 3:
			World.box(model, Vector3(0.1, 0.35, 0.45), Vector3(sx * (w + 0.02), 0.2, -l * 0.5 + i * l * 0.5), trim)
	var mast_h := mast_height()
	mast = Node3D.new()
	mast.position = Vector3(0, 1.0, -0.3)
	model.add_child(mast)
	World.cyl(mast, 0.15, 0.22, mast_h, Vector3(0, mast_h * 0.5, 0), trim, 6)
	var sw := w * 3.2
	for k in 3:
		var s := World.box(mast, Vector3(sw, mast_h * 0.2, 0.08), Vector3(0, mast_h * (0.85 - k * 0.2), 0.3), sail if k != 1 else white)
		s.rotation.x = -0.1
	# Flag: black with a skull (the treasure ship flies a gold one).
	flag = Node3D.new()
	flag.position = Vector3(0, mast_h + 0.5, 0.0)
	mast.add_child(flag)
	World.box(flag, Vector3(0.04, 0.8, 1.3), Vector3(0, 0, 0.7), World.mat(Color(0.05, 0.05, 0.06) if kind != "treasure" else Color(1.0, 0.8, 0.1), 0.0 if kind != "treasure" else 1.0))
	World.sphere(flag, 0.2, Vector3(0.04, 0.08, 0.7), white, 8)
	World.box(flag, Vector3(0.05, 0.08, 0.7), Vector3(0.04, -0.22, 0.7), white, Vector3(0.6, 0, 0))
	# Two little pirates on deck who jump about when their cannons fire.
	var skin := World.mat(Color(1.0, 0.78, 0.6))
	var shirt := World.mat(Color(0.95, 0.95, 0.9) if kind != "galleon" else Color(0.3, 0.3, 0.6))
	for i in 2:
		var p := Node3D.new()
		p.position = Vector3((i - 0.5) * w * 0.9, 1.0, l * 0.15 + i * 0.6)
		model.add_child(p)
		var body := World.cyl(p, 0.22, 0.28, 0.8, Vector3(0, 0.4, 0), shirt, 6)
		body.name = "Body"
		World.sphere(p, 0.2, Vector3(0, 0.95, 0), skin, 8)
		crew.append(p)
	if kind == "treasure":
		# Heaps of treasure on deck and sparkles all around.
		var heap := World.sphere(model, 0.9, Vector3(0, 1.0, 0.8), World.mat(Color(1.0, 0.82, 0.2), 2.0, 0.3), 10)
		heap.scale = Vector3(1.0, 0.45, 1.2)
		var sp := CPUParticles3D.new()
		sp.amount = 10
		sp.lifetime = 1.2
		sp.position = Vector3(0, 2.0, 0)
		sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		sp.emission_box_extents = Vector3(w, 1.5, l)
		sp.gravity = Vector3(0, 0.5, 0)
		sp.initial_velocity_max = 0.3
		var sm := World.sphere_mesh(0.12, 4)
		sm.material = World.mat(Color(1.0, 0.95, 0.5), 4.0)
		sp.mesh = sm
		model.add_child(sp)


## A rowing boat loaded with a big powder keg and a fizzing fuse.
func _build_fireship() -> void:
	var w := half.x
	var l := half.y
	World.box(model, Vector3(w * 2.0, 0.8, l * 2.0 - w), Vector3(0, -0.1, w * 0.5), hull_mat)
	var side := w * sqrt(2.0)
	World.box(model, Vector3(side, 0.8, side), Vector3(0, -0.1, -l + w), hull_mat, Vector3(0, PI / 4.0, 0))
	var keg := World.cyl(model, 0.65, 0.65, 1.2, Vector3(0, 0.85, 0.2), World.mat(Color(0.15, 0.13, 0.13)), 12)
	keg.name = "Keg"
	World.cyl(model, 0.68, 0.68, 0.25, Vector3(0, 0.85, 0.2), World.mat(Color(0.9, 0.12, 0.1), 0.8), 12)
	World.sphere(model, 0.28, Vector3(0, 0.9, -0.48), World.mat(Color(0.95, 0.95, 0.9)), 8)  # skull on the keg
	var fuse := CPUParticles3D.new()
	fuse.amount = 14
	fuse.lifetime = 0.4
	fuse.position = Vector3(0, 1.6, 0.2)
	fuse.direction = Vector3.UP
	fuse.spread = 70.0
	fuse.initial_velocity_min = 1.0
	fuse.initial_velocity_max = 2.5
	fuse.gravity = Vector3(0, -4.0, 0)
	var sm := World.sphere_mesh(0.06, 4)
	sm.material = World.mat(Color(1.0, 0.75, 0.2), 6.0)
	fuse.mesh = sm
	model.add_child(fuse)
	World.sphere(model, 0.12, Vector3(0, 1.55, 0.2), World.mat(Color(1.0, 0.6, 0.1), 5.0), 6)
	mast = Node3D.new()
	mast.position = Vector3(0, 0.3, 1.0)
	model.add_child(mast)
	World.cyl(mast, 0.05, 0.07, 2.4, Vector3(0, 1.2, 0), World.mat(Color(0.2, 0.15, 0.1)), 5)
	flag = Node3D.new()
	flag.position = Vector3(0, 2.2, 0)
	mast.add_child(flag)
	World.box(flag, Vector3(0.03, 0.5, 0.8), Vector3(0, 0, 0.4), World.mat(Color(0.05, 0.05, 0.06)))


func forward() -> Vector3:
	return Basis(Vector3.UP, heading) * Vector3(0, 0, -1)


func _physics_process(delta: float) -> void:
	bob += delta
	age += delta
	flash = maxf(0.0, flash - delta * 4.0)
	hull_mat.emission_energy_multiplier = flash * 2.0
	bar_fill.scale.x = maxf(0.02, hp / max_hp)
	_animate_details(delta)
	var sea: float = main.sea_level
	if ghost:
		if not net_started:
			net_started = true
			position = net_target
		var k := 1.0 - exp(-10.0 * delta)
		position.x = lerpf(position.x, net_target.x, k)
		position.z = lerpf(position.z, net_target.z, k)
		_pose(sea)
		return
	if sinking:
		sink_t += delta
		_pose(sea)
		if sink_t > 3.5:
			queue_free()
		return
	if kind == "fireship":
		_ram(delta)
	else:
		_sail(delta)
	_pose(sea)
	if kind == "raider" or kind == "galleon":
		_attack(delta)


func _animate_details(delta: float) -> void:
	if flag:
		flag.rotation.y = sin(bob * 5.0) * 0.25
	for i in crew.size():
		var c := crew[i]
		c.position.y = 1.0 + absf(sin(bob * 3.0 + i * 1.7)) * (0.35 if flash > 0.0 else 0.08)
	if mast and sinking:
		mast.rotation.z = lerpf(mast.rotation.z, 1.3, 1.0 - exp(-1.5 * delta))  # the mast topples
	# Damaged ships smoke.
	if hp < max_hp and smoke_fx == null and kind != "fireship":
		smoke_fx = CPUParticles3D.new()
		smoke_fx.amount = 10
		smoke_fx.lifetime = 1.8
		smoke_fx.local_coords = false
		smoke_fx.position = Vector3(0, 1.4, -0.5)
		smoke_fx.direction = Vector3.UP
		smoke_fx.spread = 15.0
		smoke_fx.initial_velocity_min = 1.5
		smoke_fx.initial_velocity_max = 2.5
		smoke_fx.gravity = Vector3(0, 0.6, 0)
		smoke_fx.scale_amount_min = 1.0
		smoke_fx.scale_amount_max = 2.2
		var sm := World.sphere_mesh(0.35, 6)
		var smat := World.mat(Color(0.2, 0.18, 0.18, 0.75), 0.0)
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.material = smat
		smoke_fx.mesh = sm
		model.add_child(smoke_fx)
		var fire := World.sphere(model, 0.45, Vector3(0.3, 1.2, -0.5), World.mat(Color(1.0, 0.45, 0.1), 4.0), 8)
		fire.name = "Fire"
	var f := model.get_node_or_null("Fire") as Node3D
	if f:
		f.scale = Vector3.ONE * (0.8 + 0.3 * sin(bob * 17.0))


func _pose(sea: float) -> void:
	rotation.y = heading
	var roll := sin(bob * 1.1) * 0.05
	var y := sea + 0.2 + sin(bob * 1.4) * 0.15
	if kind == "fireship":
		y = sea + 0.25 + sin(bob * 2.2) * 0.12
		roll = sin(bob * 2.0) * 0.1
	if sinking:
		var s := minf(sink_t / 3.5, 1.0)
		roll += s * 0.7
		y -= s * s * 5.0
		model.rotation.x = s * 0.25
	model.rotation.z = roll
	position.y = y


func _sail(delta: float) -> void:
	var flat := Vector3(position.x, 0.0, position.z)
	var d := flat.length()
	var inward := -flat / maxf(d, 0.01)
	var tangent := Vector3(-inward.z, 0.0, inward.x) * orbit_dir
	var desired: Vector3
	if kind == "treasure" and age > TREASURE_STAY:
		if not fleeing:
			fleeing = true
			main.on_treasure_fleeing(self)
		desired = (-inward + tangent * 0.4).normalized()
		if d > 115.0:
			main.on_treasure_escaped(self)
			queue_free()
			return
	elif d > orbit_r + 12.0:
		desired = inward
	else:
		desired = (tangent + inward * clampf((d - orbit_r) / 6.0, -1.0, 1.0)).normalized()
	var want := atan2(-desired.x, -desired.z)
	heading = lerp_angle(heading, want, 1.0 - exp(-0.9 * delta))
	var f := forward()
	var spd := speed * (1.4 if fleeing else 1.0)
	position.x += f.x * spd * delta
	position.z += f.z * spd * delta


## Fire ship: steer for the nearest bit of our hull, weaving a little, and blow up on contact.
func _ram(delta: float) -> void:
	var goal := Vector3(signf(position.x) * (World.HULL_HALF_W + 0.9), 0.0, clampf(position.z * 0.5, -9.0, 8.0))
	var to := goal - Vector3(position.x, 0.0, position.z)
	if to.length() < 1.3:
		main.fireship_boom(self, true)
		return
	var dir := to.normalized()
	var weave := sin(age * 0.9) * 0.35 * clampf(to.length() / 30.0, 0.0, 1.0)
	dir = Basis(Vector3.UP, weave) * dir
	var want := atan2(-dir.x, -dir.z)
	heading = lerp_angle(heading, want, 1.0 - exp(-1.6 * delta))
	var f := forward()
	position.x += f.x * speed * delta
	position.z += f.z * speed * delta
	# Our hull is solid: don't let it slip under the ship.
	if absf(position.x) < World.HULL_HALF_W + 0.6 and position.z > World.BOW_TIP - 1.0 and position.z < World.DECK_STERN + 1.0:
		main.fireship_boom(self, true)


func _attack(delta: float) -> void:
	var d := Vector2(position.x, position.z).length()
	fire_t -= delta
	if fire_t <= 0.0 and d < orbit_r + 18.0 and not main.game_over:
		fire_t = fire_every * randf_range(0.8, 1.2)
		_fire_broadside()
		flash = maxf(flash, 0.01)
	if kind == "raider" and not calm:
		board_t -= delta
		if board_t <= 0.0 and d < orbit_r + 8.0:
			board_t = randf_range(7.0, 10.0)
			var extra: int = main.crew_extra()  # bigger crews get a few more boarders
			if boarders_sent < 2 + wave / 3 + extra / 2 and main.boarder_count() < mini(2 + wave / 2 + extra, main.boarder_cap()):
				boarders_sent += 1
				main.spawn_boarder(self)


func _fire_broadside() -> void:
	var to_ship := -Vector3(position.x, 0.0, position.z).normalized()
	var right := global_basis.x
	var side := right if right.dot(to_ship) > 0.0 else -right
	var origin := global_position + side * (half.x + 0.4) + Vector3.UP * 0.4
	var target := World.random_deck_point()
	var accuracy := minf(0.85, 0.5 + wave * 0.05) * (1.15 if kind == "galleon" else 1.0)
	if calm:
		accuracy = 0.35
	if randf() > accuracy:
		var miss := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
		target += miss * randf_range(6.5, 10.0)
		target.y = main.sea_level
	var dist := origin.distance_to(target)
	var t := clampf(dist / 20.0, 1.3, 3.2)
	var g: float = main.GRAVITY
	var vel := (target - origin) / t + Vector3(0.0, 0.5 * g * t, 0.0)
	main.spawn_ball(origin, vel, true, false)
	main.smoke(origin + side * 0.5, 1.2)
	main.sound("cannon", -6.0, 0.75)


## Host: is the world point p inside this ship (with some slack, to be kind)?
func hit_test(p: Vector3) -> bool:
	if sinking:
		return false
	var lp := global_transform.affine_inverse() * p
	var slack := 1.0 if kind != "fireship" else 1.4
	return absf(lp.x) < half.x + slack and absf(lp.z) < half.y + slack and lp.y < 9.0 and lp.y > -2.5


## Host: musket shots can hit a fire ship's powder keg.
func ray_hit(from: Vector3, dir: Vector3, max_d: float) -> float:
	if kind != "fireship" or sinking:
		return INF
	var c := global_position + Vector3.UP * 0.9
	var t := (c - from).dot(dir)
	if t < 0.0 or t > max_d:
		return INF
	return t if (from + dir * t).distance_to(c) < 1.2 else INF


func hit(damage: float) -> void:
	if sinking:
		return
	hp -= damage
	flash = 1.0
	if hp <= 0.0:
		if kind == "fireship":
			main.fireship_boom(self, false)
			return
		sinking = true
		sink_t = 0.0
		main.on_ship_sunk(self)


## Snapshot: [id, kind, pos, heading, hp, max_hp, sink_t (or -1)]
func net_state() -> Array:
	return [net_id, kind, global_position, heading, hp, max_hp, sink_t if sinking else -1.0]


func apply_net(item: Array) -> void:
	net_target = item[2]
	heading = lerp_angle(heading, item[3], 0.5)
	hp = item[4]
	max_hp = item[5]
	var st: float = item[6]
	if st >= 0.0:
		if not sinking:
			sinking = true
		sink_t = st
	if hp < max_hp and flash <= 0.0 and has_meta("last_hp") and float(get_meta("last_hp")) > hp:
		flash = 1.0
	set_meta("last_hp", hp)
