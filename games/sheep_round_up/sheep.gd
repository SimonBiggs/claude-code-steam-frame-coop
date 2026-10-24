extends Node3D
## One fluffy sheep. The host / local game moves it (games/sheep_round_up/main.gd); every machine
## animates it here from how it moved: hopping while it runs, wriggling while held, a happy bounce
## in the pen. One merged mesh (1 draw call) so a big flock stays cheap.

const Creatures := preload("res://core/creatures.gd")

const WALK := 0
const HELD := 1
const FLY := 2

var state := WALK
var penned := false
var vel := Vector3.ZERO
var wander_dir := Vector3.ZERO
var wander_t := 0.0
var last_by := -1  # slot that last pushed / threw it (credit when it gets home)
var touch_cd := 0.0
var net_target := Vector3.ZERO  # TV machine: where the host says it is

var body: Node3D
var _prev := Vector3.ZERO
var _phase := 0.0
var _squash := 0.0
var _happy_t := 0.0


func _ready() -> void:
	body = Creatures.monster("sheep", {"lod": "far", "scale": 0.8, "seed": randi()})
	add_child(body)
	_prev = position
	net_target = position
	_phase = randf() * TAU
	_happy_t = randf_range(1.0, 4.0)


## A bounce: squash then stretch (touched, landed, penned).
func boing(amount: float = 1.0) -> void:
	_squash = maxf(_squash, amount)


func _process(delta: float) -> void:
	if body == null:
		return
	var moved := position - _prev
	moved.y = 0.0
	_prev = position
	var speed := moved.length() / maxf(delta, 0.001)
	if speed > 0.15 and state == WALK:
		var want := atan2(moved.x, moved.z)  # creatures face +Z
		body.rotation.y = lerp_angle(body.rotation.y, want, 1.0 - exp(-10.0 * delta))
	var hop := 0.0
	if state == WALK:
		if speed > 0.3:
			_phase += delta * (6.0 + speed * 3.0)
			hop = absf(sin(_phase)) * minf(0.05 + speed * 0.04, 0.18)
		elif penned:
			_happy_t -= delta
			if _happy_t <= 0.0:
				_happy_t = randf_range(1.5, 4.0)
				boing(0.7)
		body.rotation.z = lerpf(body.rotation.z, 0.0, 1.0 - exp(-8.0 * delta))
	else:
		_phase += delta * 18.0  # wriggle in the air
		body.rotation.z = sin(_phase) * 0.35
	_squash = maxf(0.0, _squash - delta * 2.5)
	var s := sin(_squash * PI * 2.0) * _squash * 0.35
	body.position.y = hop + (_squash * 0.25 if state == WALK else 0.0)
	body.scale = Vector3(1.0 + s, 1.0 - s, 1.0 + s)
	touch_cd = maxf(0.0, touch_cd - delta)
