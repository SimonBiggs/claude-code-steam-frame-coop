extends Node3D
## A pirate ship. It sails in from the horizon, circles our ship and fires broadsides at the deck.
## Raiders come in close and send boarders over on ropes; galleons stay further out and hit harder.
## On the client it's a ghost, placed from snapshots.

const World := preload("res://games/cannon_cove/world.gd")

const KINDS := {
	# hp, speed, orbit radius, fire interval, gold, half-size (x, z), sail colour
	"raider": [2.0, 7.0, 17.0, 8.0, 50, Vector2(1.5, 4.2), Color(0.9, 0.15, 0.2)],
	"galleon": [4.0, 4.5, 42.0, 6.0, 100, Vector2(2.2, 6.0), Color(0.45, 0.2, 0.75)],
}

var main
var kind := "raider"
var net_id := 0
var ghost := false
var wave := 1
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
var hull_mat: StandardMaterial3D
var bar_fill: MeshInstance3D
var model: Node3D
var net_target := Vector3.ZERO
var net_started := false


func setup(k: String, w: int, m) -> void:
	kind = k
	wave = w
	main = m
	var d: Array = KINDS[kind]
	max_hp = float(d[0]) + floorf(w / 4.0)
	hp = max_hp
	speed = d[1]
	orbit_r = float(d[2]) + randf_range(-2.0, 6.0)
	fire_every = maxf(3.5, float(d[3]) - w * 0.25)
	gold = d[4]
	half = d[5]
	orbit_dir = 1.0 if randf() < 0.5 else -1.0
	fire_t = randf_range(2.0, 4.0)
	bob = randf() * TAU


func _ready() -> void:
	add_to_group("ships")
	var d: Array = KINDS[kind]
	var sail_color: Color = d[6]
	model = Node3D.new()
	add_child(model)
	hull_mat = World.mat(Color(0.32, 0.2, 0.12))
	hull_mat.emission_enabled = true
	hull_mat.emission = Color(1, 1, 1)
	hull_mat.emission_energy_multiplier = 0.0
	var trim := World.mat(Color(0.15, 0.12, 0.1))
	var white := World.mat(Color(0.95, 0.93, 0.85))
	var sail := World.mat(sail_color)
	var w := half.x
	var l := half.y
	World.box(model, Vector3(w * 2.0, 2.0, l * 2.0 - w), Vector3(0, 0.0, w * 0.5), hull_mat)
	var side := w * sqrt(2.0)
	World.box(model, Vector3(side, 2.0, side), Vector3(0, 0.0, -l + w), hull_mat, Vector3(0, PI / 4.0, 0))
	World.box(model, Vector3(w * 2.0 + 0.05, 0.3, l * 2.0 - w), Vector3(0, 0.6, w * 0.5), sail)
	World.box(model, Vector3(w * 2.0, 1.4, 1.6), Vector3(0, 1.4, l - 0.8), hull_mat)  # stern cabin
	# Gun ports.
	for sx in [-1.0, 1.0]:
		for i in 3:
			World.box(model, Vector3(0.1, 0.35, 0.45), Vector3(sx * (w + 0.02), 0.2, -l * 0.5 + i * l * 0.5), trim)
	var mast_h := 7.0 if kind == "raider" else 9.5
	World.cyl(model, 0.15, 0.22, mast_h, Vector3(0, 1.0 + mast_h * 0.5, -0.3), trim, 6)
	var sw := w * 3.2
	for k in 3:
		var s := World.box(model, Vector3(sw, mast_h * 0.2, 0.08), Vector3(0, 1.0 + mast_h * (0.85 - k * 0.2), 0.0), sail if k != 1 else white)
		s.rotation.x = -0.1
	# Skull flag: a black flag with a white round "skull" and crossbones.
	var flag_pos := Vector3(0, 1.0 + mast_h + 0.5, 0.4)
	World.box(model, Vector3(0.04, 0.8, 1.3), flag_pos, World.mat(Color(0.05, 0.05, 0.06)))
	World.sphere(model, 0.2, flag_pos + Vector3(0.04, 0.08, 0), white, 8)
	World.box(model, Vector3(0.05, 0.08, 0.7), flag_pos + Vector3(0.04, -0.22, 0), white, Vector3(0.6, 0, 0))
	World.box(model, Vector3(0.05, 0.08, 0.7), flag_pos + Vector3(0.04, -0.22, 0), white, Vector3(-0.6, 0, 0))
	# Health bar above the mast (shrinks towards its centre).
	var bar_root := Node3D.new()
	bar_root.position = Vector3(0, 1.0 + mast_h + 1.8, 0)
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
	var fill_mat := World.mat(Color(1.0, 0.25, 0.2), 1.5)
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fill_mat.billboard_keep_scale = true
	fill_mat.render_priority = 1
	bar_fill.material_override = fill_mat
	bar_root.add_child(bar_fill)
	for c in model.get_children():
		if c is GeometryInstance3D:
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func forward() -> Vector3:
	return Basis(Vector3.UP, heading) * Vector3(0, 0, -1)


func _physics_process(delta: float) -> void:
	bob += delta
	flash = maxf(0.0, flash - delta * 4.0)
	hull_mat.emission_energy_multiplier = flash * 2.0
	bar_fill.scale.x = maxf(0.02, hp / max_hp)
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
	_sail(delta)
	_pose(sea)
	_attack(delta)


func _pose(sea: float) -> void:
	rotation.y = heading
	var roll := sin(bob * 1.1) * 0.05
	var y := sea + 0.2 + sin(bob * 1.4) * 0.15
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
	if d > orbit_r + 12.0:
		desired = inward
	else:
		desired = (tangent + inward * clampf((d - orbit_r) / 6.0, -1.0, 1.0)).normalized()
	var want := atan2(-desired.x, -desired.z)
	heading = lerp_angle(heading, want, 1.0 - exp(-0.9 * delta))
	var f := forward()
	position.x += f.x * speed * delta
	position.z += f.z * speed * delta


func _attack(delta: float) -> void:
	var d := Vector2(position.x, position.z).length()
	fire_t -= delta
	if fire_t <= 0.0 and d < orbit_r + 18.0 and not main.game_over:
		fire_t = fire_every * randf_range(0.8, 1.2)
		_fire_broadside()
	if kind == "raider":
		board_t -= delta
		if board_t <= 0.0 and d < orbit_r + 8.0:
			board_t = randf_range(7.0, 10.0)
			var extra: int = main.crew_extra()  # bigger crews get a few more boarders
			if boarders_sent < 2 + wave / 3 + extra / 2 and main.boarder_count() < 2 + wave / 2 + extra:
				boarders_sent += 1
				main.spawn_boarder(self)


func _fire_broadside() -> void:
	var to_ship := -Vector3(position.x, 0.0, position.z).normalized()
	var right := global_basis.x
	var side := right if right.dot(to_ship) > 0.0 else -right
	var origin := global_position + side * (half.x + 0.4) + Vector3.UP * 0.4
	var target := World.random_deck_point()
	var accuracy := minf(0.85, 0.5 + wave * 0.05) * (1.15 if kind == "galleon" else 1.0)
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
	return absf(lp.x) < half.x + 1.0 and absf(lp.z) < half.y + 1.0 and lp.y < 9.0 and lp.y > -2.5


func hit(damage: float) -> void:
	if sinking:
		return
	hp -= damage
	flash = 1.0
	if hp <= 0.0:
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
