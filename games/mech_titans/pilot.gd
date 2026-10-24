extends RefCounted
## Turns the pilot's input into what the Titan should do this frame (an intent for mech.gd) plus
## one-off actions (punches, tool swaps, throws) for combat.gd. Three kinds of pilot:
## - "vr": core/vr_rig.gd in the cockpit. The arms mirror the hands relative to the HEAD (no calibrated
##   rest pose: the shoulders are estimated from where the head is, every frame), scaled up. A punch is
##   a fast forward hand movement (velocity, generous thresholds). Both hands up = block. Right trigger =
##   beam (aimed with the right hand), A = rocket dash, left stick = walk, right stick = turn (smooth,
##   or 30-degree snaps), the lever on the left console = swap tools (touch + push).
## - "pad": slot 0 on a TV seat (local play without a headset): third person, camera-relative.
## - "auto": nobody is piloting (or a TV-only test): a simple autopilot so the game still works.

const Data := preload("res://games/mech_titans/data.gd")
const VrRig := preload("res://core/vr_rig.gd")

## Hand offsets from the estimated shoulder are multiplied by these to get the mech fist offset.
const ARM_SCALE := Vector3(5.6, 6.2, 7.2)
const PUNCH_FWD := 1.35  ## m/s forward hand speed that counts as a punch
const PUNCH_SPEED := 1.7
const REARM_SPEED := 0.9

var mode := "auto"
var rig: VrRig
var party: Node
var slot := 0
var cam: Camera3D  ## the TV pilot's camera (aim + camera-relative walking)
var turn_mode := "smooth"  ## VR: "smooth" or "snap"

var _armed: Array[bool] = [true, true]
var _cool: Array[float] = [0.0, 0.0]
var _block_on := false
var _block_t := 0.0
var _snap_ready := true
var _pad_punch_hand := 0
var _pad_punch_t: Array[float] = [0.0, 0.0]
var _auto_t := 0.0
var _auto_hand := 0
var _auto_block_t := 0.0


## Returns {"intent": Dictionary for mech.simulate, "punches": [[hand, strength], ...], "beam": bool,
## "aim_from": Vector3, "aim_dir": Vector3, "tool": int (+1 / -1 swap), "throw_vel": Vector3 (VR: right
## hand velocity in world space, scaled), "lever": bool}.
func update(delta: float, mech: Node3D, ctx: Node) -> Dictionary:
	for i in 2:
		_cool[i] = maxf(0.0, _cool[i] - delta)
	match mode:
		"vr":
			return _vr(delta, mech)
		"pad":
			return _pad(delta, mech, ctx)
	return _auto(delta, mech, ctx)


# --- VR -----------------------------------------------------------------------------------------------

func _vr(delta: float, mech: Node3D) -> Dictionary:
	var out := {"punches": [], "beam": false, "tool": 0}
	var cockpit: Node3D = mech.get("cockpit")
	var head := cockpit.to_local(rig.camera.global_position)
	var hands: Array[Vector3] = [cockpit.to_local(rig.hand_point(VrRig.LEFT)), cockpit.to_local(rig.hand_point(VrRig.RIGHT))]
	var intent := {}
	var mv := rig.stick_left()
	intent["move"] = mv
	var rs := rig.stick_right()
	if turn_mode == "snap":
		if absf(rs.x) < 0.3:
			_snap_ready = true
		elif absf(rs.x) > 0.7 and _snap_ready:
			_snap_ready = false
			intent["snap"] = 1 if rs.x > 0.0 else -1
	else:
		intent["turn"] = rs.x
	intent["dash"] = rig.a_pressed()
	# Block: both hands raised to about head height, in front (never towards the face).
	var up_l := hands[0].y > head.y - 0.3 and hands[0].z < head.z - 0.05
	var up_r := hands[1].y > head.y - 0.3 and hands[1].z < head.z - 0.05
	if up_l and up_r:
		_block_t += delta
	else:
		_block_t = 0.0
	if _block_on:
		_block_on = hands[0].y > head.y - 0.42 and hands[1].y > head.y - 0.42
	elif _block_t > 0.08:
		_block_on = true
	intent["block"] = _block_on
	# Arms follow the hands relative to shoulders estimated from the head.
	var fl: Array[Vector3] = []
	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		var shoulder := head + Vector3(sx * 0.19, -0.28, 0.06)
		var off := hands[i] - shoulder
		var ms: Vector3 = mech.call("shoulder_local", i)
		fl.append(ms + Vector3(off.x * ARM_SCALE.x, off.y * ARM_SCALE.y, off.z * ARM_SCALE.z) + Vector3(0, -0.4, -0.9))
	intent["fists"] = fl
	# Lever (touch + push), then punches (not while that hand is on the lever).
	var flip: int = cockpit.call("lever_update", [hands[0], hands[1]], delta)
	out["tool"] = flip
	out["lever"] = cockpit.call("lever_busy")
	if not _block_on:
		for i in 2:
			var v := rig.hand_velocity(i)
			var vl: Vector3 = cockpit.global_basis.inverse() * v
			var fwd := -vl.z
			var spd := v.length()
			if spd < REARM_SPEED:
				_armed[i] = true
			if _armed[i] and _cool[i] <= 0.0 and fwd > PUNCH_FWD and spd > PUNCH_SPEED and not bool(out["lever"]):
				_armed[i] = false
				_cool[i] = 0.3
				var strength := clampf((spd - 1.4) / 2.6, 0.15, 1.0)
				(out["punches"] as Array).append([i, strength])
	out["beam"] = rig.trigger_down()
	var hr := rig.hand_r
	out["aim_from"] = hr.global_position
	out["aim_dir"] = -hr.global_basis.z
	out["throw_vel"] = rig.hand_velocity(VrRig.RIGHT) * 7.0
	out["intent"] = intent
	return out


# --- TV pilot (pad) ------------------------------------------------------------------------------------------

func _pad(delta: float, mech: Node3D, ctx: Node) -> Dictionary:
	var out := {"punches": [], "beam": false, "tool": 0}
	var intent := {}
	var busy: bool = ctx.call("slot_busy", slot)
	var mv: Vector2 = Vector2.ZERO if busy else party.stick(slot, "move")
	var f := Vector3.FORWARD
	if cam != null:
		f = -cam.global_basis.z
		f.y = 0.0
		f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	var r := Vector3(-f.z, 0.0, f.x)
	intent["move_world"] = r * mv.x - f * mv.y
	intent["face"] = f
	if not busy:
		intent["dash"] = party.just_pressed(slot, "accept")
		intent["block"] = party.pressed(slot, "lb")
		if party.just_pressed(slot, "x"):
			var h := _pad_punch_hand
			_pad_punch_hand = 1 - h
			_pad_punch_t[h] = 0.3
			(out["punches"] as Array).append([h, 0.8])
		if party.just_pressed(slot, "y"):
			out["tool"] = 1
		out["beam"] = party.trigger(slot, "rt") > 0.5 or party.pressed(slot, "rb")
	var fl: Array[Vector3] = []
	for i in 2:
		_pad_punch_t[i] = maxf(0.0, _pad_punch_t[i] - delta)
		var sx := -1.0 if i == 0 else 1.0
		if _pad_punch_t[i] > 0.0:
			fl.append(Vector3(sx * 1.0, 6.6, -5.2))
		elif bool(out["beam"]) and i == 1:
			fl.append(Vector3(1.8, 6.4, -3.8))
		else:
			fl.append(mech.call("rest_target", i))
	intent["fists"] = fl
	if cam != null:
		out["aim_from"] = cam.global_position
		out["aim_dir"] = -cam.global_basis.z
	else:
		out["aim_from"] = mech.call("chest_world")
		out["aim_dir"] = mech.call("forward")
	out["throw_vel"] = (out["aim_dir"] as Vector3) * 26.0 + Vector3(0, 8, 0)
	out["intent"] = intent
	return out


# --- Autopilot ----------------------------------------------------------------------------------------------

func _auto(delta: float, mech: Node3D, ctx: Node) -> Dictionary:
	var out := {"punches": [], "beam": false, "tool": 0}
	var intent := {}
	var target: Node3D = ctx.call("auto_target", mech.global_position)
	_auto_t -= delta
	_auto_block_t = maxf(0.0, _auto_block_t - delta)
	var fl: Array[Vector3] = [mech.call("rest_target", 0), mech.call("rest_target", 1)]
	if target != null:
		var to := target.global_position - mech.global_position
		to.y = 0.0
		var dist := to.length()
		var reach: float = float(target.get("radius")) + 6.0
		intent["face"] = to
		if dist > reach:
			intent["move_world"] = to.normalized()
		elif dist < reach - 3.0:
			intent["move_world"] = -to.normalized() * 0.5
		if dist < reach + 1.5 and _auto_t <= 0.0 and bool(target.get("can_punch")):
			_auto_t = 1.0
			var h := _auto_hand
			_auto_hand = 1 - h
			(out["punches"] as Array).append([h, 0.7])
			_pad_punch_t[h] = 0.3
		var aim: Vector3 = target.call("aim_point")
		if dist > 10.0 or bool(target.get("high")):
			out["beam"] = mech.get("energy") > 25.0 or bool(ctx.call("is_beaming"))
		out["aim_from"] = mech.call("chest_world")
		out["aim_dir"] = (aim - (out["aim_from"] as Vector3)).normalized()
		if bool(ctx.call("mech_threatened")) and _auto_block_t <= 0.0 and randf() < 0.02:
			_auto_block_t = 1.2
		intent["block"] = _auto_block_t > 0.4
	else:
		out["aim_from"] = mech.call("chest_world")
		out["aim_dir"] = mech.call("forward")
	for i in 2:
		_pad_punch_t[i] = maxf(0.0, _pad_punch_t[i] - delta)
		if _pad_punch_t[i] > 0.0:
			fl[i] = Vector3((-1.0 if i == 0 else 1.0) * 1.0, 6.6, -5.2)
	intent["fists"] = fl
	out["throw_vel"] = mech.call("forward") * 24.0 + Vector3(0, 8, 0)
	out["intent"] = intent
	return out
