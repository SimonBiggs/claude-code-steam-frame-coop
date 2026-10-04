extends Node3D
## Something floating on the sea for the gunner to shoot:
##  practice - a red-and-white bullseye raft (target practice before the pirates come)
##  supply   - a barrel of cannonballs: shoot it and every cannon gets a free ball
##  chest    - a treasure chest bobbing on a raft: shoot it for gold
## On the client it's a ghost placed from snapshots.

const World := preload("res://games/cannon_cove/world.gd")

const RADIUS := {"practice": 2.4, "supply": 2.0, "chest": 2.0}
const LIFE := {"practice": 9999.0, "supply": 28.0, "chest": 28.0}

var main
var kind := "practice"
var net_id := 0
var ghost := false
var drift := Vector3.ZERO
var age := 0.0
var bob := 0.0
var model: Node3D
var ring_mat: StandardMaterial3D
var label: Label3D
var gone := false


func _ready() -> void:
	add_to_group("targets")
	bob = randf() * TAU
	model = Node3D.new()
	add_child(model)
	var wood := World.mat(Color(0.6, 0.42, 0.22))
	World.cyl(model, 1.3, 1.4, 0.35, Vector3(0, 0.0, 0), wood, 14)  # the raft
	match kind:
		"practice":
			# A bullseye board standing on the raft, facing our ship, with a little flag.
			var board := Node3D.new()
			board.position = Vector3(0, 1.5, 0)
			model.add_child(board)
			var cols := [Color(0.95, 0.15, 0.12), Color(0.97, 0.97, 0.95), Color(0.95, 0.15, 0.12), Color(0.97, 0.97, 0.95)]
			for k in 4:
				var r := 1.2 - k * 0.3
				var disc := World.cyl(board, r, r, 0.08 + k * 0.03, Vector3.ZERO, World.mat(cols[k], 0.25), 16)
				disc.rotation.x = PI / 2.0
			ring_mat = World.mat(Color(1.0, 0.85, 0.2), 2.5)
			var eye := World.cyl(board, 0.22, 0.22, 0.22, Vector3.ZERO, ring_mat, 12)
			eye.rotation.x = PI / 2.0
			World.box(model, Vector3(0.12, 1.0, 0.12), Vector3(0, 0.6, 0.15), wood)
		"supply":
			var barrel := World.cyl(model, 0.75, 0.75, 1.5, Vector3(0, 0.9, 0), World.mat(Color(0.55, 0.33, 0.15)), 12)
			barrel.rotation.z = 0.15
			for y in [0.4, 1.4]:
				World.cyl(model, 0.78, 0.78, 0.1, Vector3(0, y, 0), World.mat(Color(0.2, 0.2, 0.22), 0.0, 0.4), 12)
			ring_mat = World.mat(Color(0.4, 1.0, 0.5), 2.0)
			for k in 3:
				World.sphere(model, 0.22, Vector3(-0.25 + k * 0.25, 1.75, 0), World.mat(Color(0.12, 0.12, 0.14), 0.0, 0.3), 8)
			World.cyl(model, 0.82, 0.82, 0.08, Vector3(0, 0.9, 0), ring_mat, 12)
		_:
			var chest := World.box(model, Vector3(1.4, 0.8, 0.9), Vector3(0, 0.6, 0), World.mat(Color(0.5, 0.26, 0.1)))
			chest.rotation.y = 0.3
			World.box(model, Vector3(1.45, 0.12, 0.95), Vector3(0, 0.95, 0), World.mat(Color(1.0, 0.78, 0.2), 0.6, 0.3))
			ring_mat = World.mat(Color(1.0, 0.85, 0.2), 3.0)
			var coins := World.sphere(model, 0.55, Vector3(0, 1.05, 0), ring_mat, 10)
			coins.scale = Vector3(1.0, 0.35, 0.65)
	for c in model.get_children():
		if c is GeometryInstance3D:
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label = Label3D.new()
	label.text = {"practice": "TARGET", "supply": "FREE AMMO!", "chest": "TREASURE!"}[kind]
	label.font_size = 96
	label.outline_size = 28
	label.pixel_size = 0.012
	label.modulate = {"practice": Color(1.0, 0.9, 0.4), "supply": Color(0.5, 1.0, 0.55), "chest": Color(1.0, 0.85, 0.3)}[kind]
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.position.y = 3.6
	add_child(label)
	if kind != "practice" and main != null and main.simple:
		label.visible = false  # simple mode: a chest bobbing by needs no words


func _physics_process(delta: float) -> void:
	age += delta
	bob += delta
	var sea: float = main.sea_level
	if not ghost:
		position += drift * delta
		if age > float(LIFE[kind]):
			if kind != "practice":
				main.splash(Vector3(position.x, sea, position.z), 1.0)
			queue_free()
			return
	position.y = sea + 0.15 + sin(bob * 1.6) * 0.18
	model.rotation.z = sin(bob * 1.2) * 0.08
	model.rotation.x = sin(bob * 0.9) * 0.06
	# The practice board turns to face our ship.
	if kind == "practice":
		var to := -Vector3(position.x, 0.0, position.z)
		model.rotation.y = atan2(to.x, to.z)
	else:
		model.rotation.y += delta * 0.3
	if ring_mat:
		ring_mat.emission_energy_multiplier = 1.5 + sin(age * 6.0) * 1.0
	label.position.y = 3.6 + sin(age * 3.0) * 0.2


## Host: did a cannonball at p hit it? (generous, kids are aiming)
func hit_test(p: Vector3) -> bool:
	if gone:
		return false
	var d := p - global_position
	return Vector2(d.x, d.z).length() < float(RADIUS[kind]) and d.y < 4.5 and d.y > -1.5


## Snapshot: [id, kind, pos]
func net_state() -> Array:
	return [net_id, kind, global_position]


func apply_net(item: Array) -> void:
	var p: Vector3 = item[2]
	position.x = lerpf(position.x, p.x, 0.5)
	position.z = lerpf(position.z, p.z, 0.5)
