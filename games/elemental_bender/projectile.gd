extends Node3D
## ELEMENTAL BENDER: a bending attack in flight (fire blast, water whip, boulder, air gust), or a
## Shadow Raider's dark-cored shot.
## `real` shots (host / local) deal damage through main.projectile_hit(); every other copy is a
## visual ghost (the TV machine's own shots, and copies of the host's shots sent as "shots" events)
## that only bursts when it touches what it would hit there. Shots fly straight (plus gravity);
## earth boulders first rise out of the ground for `rise` seconds.

const E := preload("res://games/elemental_bender/elem.gd")
const Looks := preload("res://games/elemental_bender/looks.gd")
const MeshKit := preload("res://core/mesh_kit.gd")

var game: Node
var real := true
var owner_slot := -1  ## who fired it (-1 = a raider)
var element := E.FIRE
var team := 0  ## 0 = the benders' shot (hits raiders), 1 = a raider's shot (hits benders)
var velocity := Vector3.ZERO
var damage := 10.0
var knockback := 6.0
var radius := 0.5
var life := 1.5
var pierce := false
var effect := ""
var gravity := 0.0
var rise := 0.0
var rise_from := Vector3.ZERO
var rise_to := Vector3.ZERO

var _hit := {}
var _puff_t := 0.0
var _model: MeshInstance3D
var _age := 0.0


## Fill in from a shot dictionary (elem.gd's recipes / unpack_shot).
func configure(p: Dictionary) -> void:
	element = int(p.get("element", E.FIRE))
	team = int(p.get("team", 0))
	position = p.get("pos", Vector3.ZERO)
	velocity = p.get("vel", Vector3.ZERO)
	damage = float(p.get("damage", 10.0))
	knockback = float(p.get("knockback", 6.0))
	radius = float(p.get("radius", 0.5))
	life = float(p.get("life", 1.5))
	pierce = bool(p.get("pierce", false))
	effect = String(p.get("effect", ""))
	gravity = float(p.get("gravity", 0.0))
	if p.has("rise"):
		rise = float(p["rise"])
		rise_from = p["rise_from"]
		rise_to = p["pos"]
		position = rise_from


func _ready() -> void:
	_model = MeshKit.instance(Looks.shot(element, snappedf(radius, 0.05), team == 1), false)
	add_child(_model)
	if velocity.length() > 0.1:
		var up := Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT
		basis = Basis.looking_at(velocity.normalized(), up)


func _physics_process(delta: float) -> void:
	_age += delta
	if rise > 0.0:
		var k := minf(_age / rise, 1.0)
		global_position = rise_from.lerp(rise_to, k)
		_model.rotate_y(delta * 8.0)
		if k < 1.0:
			return
		rise = 0.0
	life -= delta
	velocity.y -= gravity * delta
	global_position += velocity * delta
	match element:
		E.AIR:
			_model.rotate_z(delta * 18.0)
			_model.scale = Vector3.ONE * (1.0 + _age * 1.5)
		E.EARTH:
			_model.rotate_x(delta * 6.0)
	_puff_t -= delta
	if _puff_t <= 0.0:
		_puff_t = float(game.get("trail_interval"))
		_trail()
	if life <= 0.0 or global_position.y < -0.1:
		_burst()
		queue_free()
		return
	var reach := radius * (_model.scale.x if element == E.AIR else 1.0)
	var targets: Array = game.call("targets_for", team)
	for t in targets:
		if not is_instance_valid(t) or _hit.has(t):
			continue
		var tn: Node3D = t
		var centre: Vector3 = tn.global_position + Vector3.UP * float(tn.get("hit_height"))
		if global_position.distance_to(centre) < reach + float(tn.get("hit_radius")):
			_hit[tn] = true
			if real:
				var push := velocity.normalized() * knockback
				push.y = 0.0
				game.call("projectile_hit", self, tn, push)
			if not pierce:
				_burst()
				queue_free()
				return


func _trail() -> void:
	var fx: Node = game.get("fx")
	var p := global_position + Vector3(randf_range(-0.15, 0.15), randf_range(-0.15, 0.15), randf_range(-0.15, 0.15))
	match element:
		E.FIRE:
			fx.call("puff", p, Color(1.0, randf_range(0.2, 0.7), 0.05), radius * 0.9, 0.3, Vector3.UP * 1.5)
		E.WATER:
			fx.call("puff", p, Color(0.5, 0.8, 1.0), radius * 0.5, 0.35, Vector3.DOWN * 2.0)
		E.EARTH:
			fx.call("puff", p, Color(0.6, 0.5, 0.35), radius * 0.5, 0.5, Vector3.ZERO)
		_:
			fx.call("puff", p, Color(1, 1, 1), radius * 0.5 * _model.scale.x, 0.25, Vector3.ZERO)


func _burst() -> void:
	var c: Color = E.COLORS[element] if element != E.EARTH else E.ROCK
	game.get("fx").call("burst", global_position, c, 8, 4.0, radius * 0.6, 0.4)
