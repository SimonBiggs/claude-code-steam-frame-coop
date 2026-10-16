extends Node3D
## Jelly wobble for one block's mesh: watches its parent's motion and squashes / jiggles on bumps.
## Purely visual, runs on every machine (host bodies and TV-machine ghosts alike).

## Called with (position, strength 0..1) when the block lands hard (sound).
var on_bump: Callable

var _sq := 0.0
var _sq_v := 0.0
var _tilt := Vector2.ZERO
var _tilt_v := Vector2.ZERO
var _last := Vector3.ZERO
var _last_v := Vector3.ZERO
var _started := false
var _bump_cd := 0.0


## Give it a jiggle (a hand poke, a boing).
func poke(amount: float) -> void:
	_sq_v += amount * 8.0
	_tilt_v += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amount * 6.0


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	var p: Vector3 = (get_parent() as Node3D).global_position
	if not _started:
		_started = true
		_last = p
		return
	var v := (p - _last) / delta
	var dv := v - _last_v
	_bump_cd -= delta
	# A sudden stop (landing, hitting something) squashes the jelly.
	if dv.length() > 3.5 and _last_v.length() > 2.0:
		var k := clampf(dv.length() / 10.0, 0.15, 1.0)
		_sq_v += k * 7.0
		_tilt_v += Vector2(dv.x, dv.z).limit_length(6.0) * 0.6
		if _bump_cd <= 0.0 and on_bump.is_valid():
			_bump_cd = 0.15
			on_bump.call(p, k)
	_last = p
	_last_v = v
	# Springs.
	_sq_v += (-_sq * 140.0 - _sq_v * 7.0) * delta
	_sq += _sq_v * delta
	_sq = clampf(_sq, -0.35, 0.35)
	_tilt_v += (-_tilt * 110.0 - _tilt_v * 6.0) * delta
	_tilt += _tilt_v * delta
	_tilt = _tilt.limit_length(0.3)
	scale = Vector3(1.0 + _sq * 0.5, 1.0 - _sq, 1.0 + _sq * 0.5)
	rotation = Vector3(_tilt.y, 0.0, -_tilt.x)
