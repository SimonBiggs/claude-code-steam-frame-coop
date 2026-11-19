extends SceneTree
## KART RACE VR steering wheel (games/kart_race/cockpit.gd), no game, no window:
##   godot-test --headless --path . -s res://tests/kart_vr_wheel_test.gd
## Fake hands in the seat frame, like a real Steam Frame driver:
## - a SEATED driver's hands resting on the lap (in front, below the wheel) never hold the wheel, so the
##   stick, the ghost-hand demo and the "grab" glow stay on (2026-11-19: a seated guest's lap "held" it);
## - bare hands on the rim at 9 and 3 hold it, and turning them 40 degrees turns the wheel 40 degrees;
## - either hand alone, squeezing GRIP 11 cm off the rim, holds it (no button: doesn't); TRIGGER (= GO, held all
##   race) holds a bit off the rim (11 cm) but never on the lap;
## - a stick push steers even while hands hold the wheel, and either stick works;
## - the same hand movement gives the same wheel angle at 20, 45, 60 and 90 fps (no frame-rate steering).
## Prints "SCRIPT ERROR: ..." per failure and "KART VR WHEEL: PASS" or "FAIL" (exit code 1).

const Cockpit := preload("res://games/kart_race/cockpit.gd")

var fails := 0


class FakeMain:
	extends RefCounted
	var state := "race"


class FakeKart:
	extends RefCounted
	var item := ""


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("SCRIPT ERROR: KART VR WHEEL: " + what)


func _cockpit() -> Node:
	var c = Cockpit.new()
	c.fake = true
	c.main = FakeMain.new()
	c.kart = FakeKart.new()
	return c


## A point on the rim at angle a (0 = 3 o'clock, + = anticlockwise), out = radial offset, dz = depth.
func _rim(c, a: float, out := 0.0, dz := 0.0) -> Vector3:
	var b: Basis = c.wheel_basis()
	var up: Vector3 = b * Vector3(0, 0, -1)
	var r: float = c.WHEEL_R + out
	return c.wheel_center() + b.x * (r * cos(a)) + up * (r * sin(a)) + b.y * dz


func _step(c, l: Vector3, r: Vector3, dt: float, frames: int) -> void:
	c.fake_l = l
	c.fake_r = r
	for i in frames:
		c.read_input(dt)


func _initialize() -> void:
	# 1. Lap: seated eyes at the seat's EYE point; hands on the thighs ~0.55-0.7 m below the eyes, 0.15-0.35 m ahead.
	var c = _cockpit()
	var eye: Vector3 = c.EYE
	for dy in [-0.55, -0.62, -0.7]:
		for dz in [-0.15, -0.25, -0.35]:
			for dx in [0.0, 0.12, 0.2]:
				var lp: Vector3 = eye + Vector3(-dx, dy, dz)
				var rp: Vector3 = eye + Vector3(dx, dy, dz)
				_step(c, lp, rp, 1.0 / 60.0, 3)
				_check(not c.wheel_held(), "hands on the lap (%.2f, %.2f, %.2f) hold the wheel" % [dx, dy, dz])
	# Hands on the lap pulling both triggers (driving) or squeezing nothing: still not holding.
	c.fake_trigger = 1.0
	c.fake_trigger_l = 1.0
	for dy in [-0.55, -0.62, -0.7]:
		for dz in [-0.15, -0.25, -0.35]:
			_step(c, eye + Vector3(-0.15, dy, dz), eye + Vector3(0.15, dy, dz), 1.0 / 60.0, 3)
			_check(not c.wheel_held(), "hands on the lap pulling the triggers (%.2f, %.2f) hold the wheel" % [dy, dz])
	c.fake_trigger = 0.0
	c.fake_trigger_l = 0.0
	# Hands on the lap + stick: the stick steers.
	c.fake_stick = Vector2(1, 0)
	_step(c, eye + Vector3(-0.15, -0.55, -0.25), eye + Vector3(0.15, -0.55, -0.25), 1.0 / 60.0, 60)
	_check(c.wheel_angle < -0.8, "hands on the lap, left stick right: wheel %.2f (want < -0.8)" % c.wheel_angle)
	c.fake_stick = Vector2.ZERO
	_step(c, eye + Vector3(-0.15, -0.55, -0.25), eye + Vector3(0.15, -0.55, -0.25), 1.0 / 60.0, 90)
	_check(absf(c.wheel_angle) < 0.05, "stick let go: wheel springs back (%.2f)" % c.wheel_angle)
	c.free()

	# 2. Bare hands on the rim at 9 and 3, turned 40 degrees anticlockwise (= left).
	c = _cockpit()
	_step(c, _rim(c, PI), _rim(c, 0.0), 1.0 / 60.0, 10)
	_check(c.grip == "LR", "bare hands at 9 and 3 o'clock: grip '%s' (want LR)" % c.grip)
	var turn := deg_to_rad(40.0)
	for i in 60:
		var a := turn * float(i + 1) / 60.0
		_step(c, _rim(c, PI + a), _rim(c, a), 1.0 / 60.0, 1)
	_step(c, _rim(c, PI + turn), _rim(c, turn), 1.0 / 60.0, 30)
	_check(absf(c.wheel_angle - turn) < 0.05, "both hands turned 40 deg: wheel %.1f deg" % rad_to_deg(c.wheel_angle))
	var steer: float = c.read_input(1.0 / 60.0)[2]
	_check(steer < -0.4, "turned left: steer %.2f (want < -0.4: left)" % steer)
	# The stick wins over held hands.
	c.fake_stick = Vector2(0.9, 0)
	_step(c, _rim(c, PI + turn), _rim(c, turn), 1.0 / 60.0, 60)
	_check(c.wheel_angle < -0.5, "stick right while holding: wheel %.2f (want < -0.5)" % c.wheel_angle)
	c.fake_stick = Vector2.ZERO
	c.free()

	# 3. One hand, a little off the rim, squeezing grip (or trigger), either hand.
	for side in ["L", "R"]:
		for btn in ["grip", "trigger", "none"]:
			c = _cockpit()
			var far := Vector3(5, 5, 5)
			var a0 := PI * 0.85 if side == "L" else PI * 0.15
			var dz := 0.1 if btn != "trigger" else 0.05
			var on := _rim(c, a0, 0.11, dz)  # 11 cm out and in front of the rim: not touching it
			var sq := 1.0 if btn != "none" else 0.0
			if side == "L":
				c.fake_grip_l = sq if btn == "grip" else 0.0
				c.fake_trigger_l = sq if btn == "trigger" else 0.0
			else:
				c.fake_grip_r = sq if btn == "grip" else 0.0
				c.fake_trigger = sq if btn == "trigger" else 0.0
			var lp := on if side == "L" else far
			var rp := on if side == "R" else far
			_step(c, lp, rp, 1.0 / 60.0, 5)
			if btn == "none":
				_check(not c.wheel_held(), "%s hand 11 cm off the rim with no button holds the wheel" % side)
			else:
				_check(c.grip == side, "%s hand squeezing %s near the rim: grip '%s'" % [side, btn, c.grip])
				for i in 45:
					var a := a0 + 0.6 * float(i + 1) / 45.0
					var p := _rim(c, a, 0.11, dz)
					_step(c, p if side == "L" else far, p if side == "R" else far, 1.0 / 60.0, 1)
				_step(c, _rim(c, a0 + 0.6, 0.11, dz) if side == "L" else far, _rim(c, a0 + 0.6, 0.11, dz) if side == "R" else far, 1.0 / 60.0, 30)
				_check(absf(c.wheel_angle - 0.6) < 0.06, "%s hand with %s turned 0.6 rad: wheel %.2f" % [side, btn, c.wheel_angle])
			c.free()

	# 4. The right stick steers too (no hands on the wheel).
	c = _cockpit()
	c.fake_stick_r = Vector2(-1, 0)
	_step(c, Vector3(5, 5, 5), Vector3(5, 5, 5), 1.0 / 60.0, 60)
	_check(c.wheel_angle > 0.8, "right stick left: wheel %.2f (want > 0.8)" % c.wheel_angle)
	c.free()
	# 5. Frame rate: the same hand movement over 1 s gives the same wheel angle at any fps.
	var ends: Array[float] = []
	for fps in [20, 45, 60, 90]:
		c = _cockpit()
		var dt := 1.0 / float(fps)
		_step(c, _rim(c, PI), _rim(c, 0.0), dt, 3)
		var n: int = fps
		for i in n:
			var a := -0.8 * float(i + 1) / float(n)
			_step(c, _rim(c, PI + a), _rim(c, a), dt, 1)
		_step(c, _rim(c, PI - 0.8), _rim(c, -0.8), dt, int(fps * 0.5))
		ends.append(c.wheel_angle)
		c.free()
	for e in ends:
		_check(absf(e - ends[0]) < 0.03, "wheel angle depends on frame rate: %s (20/45/60/90 fps)" % [ends])
	_check(absf(ends[0] + 0.8) < 0.05, "wheel turned -0.8 rad ends at %.2f" % ends[0])

	print("KART VR WHEEL: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)
