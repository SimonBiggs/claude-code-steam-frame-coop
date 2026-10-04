extends CharacterBody3D
## A golf ball. Two modes:
## - SIMULATED (host / local play): a custom roller on top of move_and_collide. The game calls
##   step(dt) for every ball in slot order each physics tick, so a roll plays out the same way every
##   time (fixed tick, no RigidBody solver). Rolling resistance + a little drag on the felt, bounces
##   off rails (springy bumpers, moving windmill sails and ships via their velocity_at()), gentle
##   ball-to-ball knocks, ramps and jumps under gravity, and a scripted rail for loop-the-loops.
##   Things that happen (wall hits, landings, knocks) are queued in `events` for the game to turn
##   into sounds and network events.
## - MIRROR (the TV machine): no physics; it smoothly interpolates the host's snapshots.
## The visual (a coloured ball with a white band, a blob shadow, a power-up aura) rolls with the
## motion on both machines.

const Defs := preload("res://games/mini_golf_party/defs.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const Me := preload("res://games/mini_golf_party/ball.gd")

var slot := 0
var color := Color.WHITE
var mirror := false
## The hole this ball is on (zones, the loop rail, local <-> world).
var hole: Node3D
## "off" (not on the course), "play", "cup" (holed), "held" (in a cannon / being reset).
var state := "off"
var vel := Vector3.ZERO
var asleep := true
var grounded := false
var ground_n := Vector3.UP
## Power-up for the current roll: "", "sticky", "bouncy", "mega", "ghost".
var mod := ""
## Set by the hole's zones every tick before step().
var gscale := 1.0
var decel_mult := 1.0
var push := Vector3.ZERO
var keep_awake := false
## Where the current stroke was played from (water / out-of-bounds resets go back here).
var last_rest := Vector3.ZERO
var roll_t := 0.0
var still_t := 0.0
var portal_cool := 0.0
var events: Array = []
## Loop rail (a gimmicks.gd Loop) while riding it.
var rail: Node3D = null
var rail_s := 0.0
var rail_v := 0.0
var bounces := 0

var visual: Node3D
var spin_node: MeshInstance3D
var shadow: MeshInstance3D
var aura: MeshInstance3D
var _last_vis := Vector3.INF
var _buf: Array = []  # mirror: [[t, pos], ...]
var _ray: PhysicsRayQueryParameters3D


func _ready() -> void:
	collision_layer = 0 if mirror else Defs.L_BALL
	collision_mask = 0 if mirror else Defs.MASK_ALL
	var shape := SphereShape3D.new()
	shape.radius = Defs.BALL_R
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)
	_build_visual()
	set_state(state)


func _build_visual() -> void:
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	spin_node = MeshInstance3D.new()
	var light := color.get_luminance() > 0.8
	var key := "mgp_ball_%s_v2" % color.to_html(false)
	var col := color
	spin_node.mesh = ResCache.get_or_make(key, func() -> Resource:
		var b := MeshKit.Builder.new()
		b.sphere(Defs.BALL_R, MeshKit.at(Vector3.ZERO), col.lightened(0.12), 16)
		b.torus(Defs.BALL_R * 0.97, Defs.BALL_R * 0.16, MeshKit.at(Vector3.ZERO), Color(0.25, 0.27, 0.35) if light else Color(1, 1, 1), 16, 4)
		return b.build())
	spin_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(spin_node)
	shadow = MeshInstance3D.new()
	shadow.mesh = ResCache.get_or_make("mgp_ball_shadow_v1", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.disc(Defs.BALL_R * 1.25, MeshKit.at(Vector3.ZERO), Color(0.0, 0.0, 0.0, 0.42), 14)
		return b.build(MeshKit.vertex_material(true, true)))
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.top_level = true
	add_child(shadow)


## "off" hides the ball and takes it out of the physics; "play" puts it on the course.
func set_state(s: String) -> void:
	state = s
	var on := s == "play" or s == "cup"
	visible = s != "off" and s != "held"
	if shadow != null:
		shadow.visible = s == "play"
	if not mirror:
		collision_layer = Defs.L_BALL if s == "play" else 0
		collision_mask = (Defs.MASK_GHOST if mod == "ghost" else Defs.MASK_ALL) if s == "play" else 0
	if not on:
		vel = Vector3.ZERO
		rail = null


## Put the ball down at rest (tee, after a splash).
func place(p: Vector3) -> void:
	global_position = p
	vel = Vector3.ZERO
	asleep = true
	grounded = true
	ground_n = Vector3.UP
	rail = null
	last_rest = p
	_last_vis = Vector3.INF
	_buf.clear()


## A putt: velocity (world, horizontal) and the power-up for this roll.
func strike(v: Vector3, power_mod: String) -> void:
	mod = power_mod
	set_state("play")
	last_rest = global_position
	vel = v
	asleep = false
	roll_t = 0.0
	still_t = 0.0
	bounces = 0
	_update_aura()


func wake() -> void:
	if state == "play" and asleep:
		asleep = false
		still_t = 0.0


## At rest (or as good as: not moving for a moment) and not riding anything.
func settled() -> bool:
	if state != "play":
		return true
	if rail != null:
		return false
	return asleep or still_t > 0.6


func speed() -> float:
	return vel.length()


# --- Simulation (host / local) ------------------------------------------------------------------------

func step(dt: float) -> void:
	if mirror or state != "play":
		return
	portal_cool = maxf(0.0, portal_cool - dt)
	if rail != null:
		_rail_step(dt)
		return
	if asleep and not keep_awake and push.length_squared() < 0.0001:
		return
	asleep = false
	roll_t += dt
	var g := Defs.GRAVITY * gscale
	vel.y -= g * dt
	vel += push * dt
	if grounded:
		var n := ground_n
		var vn := vel.dot(n)
		var vt := vel - n * vn
		var sp := vt.length()
		if sp > 0.00001:
			var res := Defs.ROLL_DECEL * decel_mult * maxf(gscale, 0.35)
			if mod == "sticky":
				res *= 2.4
			elif mod == "bouncy":
				res *= 0.85
			var ns := maxf(0.0, sp - (res + Defs.DRAG * sp) * dt)
			vel = n * vn + vt * (ns / sp)
	var was_grounded := grounded
	grounded = false
	var motion := vel * dt
	for i in 4:
		if motion.length_squared() < 1e-12:
			break
		var col := move_and_collide(motion, false, 0.001, true)
		if col == null:
			break
		var n := col.get_normal()
		var other := col.get_collider()
		if other is Me:
			_knock(other as Me, n)
			motion = col.get_remainder().slide(n)
			continue
		var cv := Vector3.ZERO
		var bumper := false
		if other is Object:
			var o := other as Object
			if o.has_meta("mgp_owner"):
				var owner: Object = o.get_meta("mgp_owner")
				if is_instance_valid(owner) and owner.has_method("velocity_at"):
					cv = owner.call("velocity_at", col.get_position())
			bumper = o.has_meta("mgp_bumper")
		var is_floor := n.y > 0.55
		if is_floor:
			grounded = true
			ground_n = n
		var rel := vel - cv
		var vn := rel.dot(n)
		if vn < 0.0:
			var e := 0.0
			if is_floor:
				e = Defs.FLOOR_BOUNCE if -vn > 0.9 and mod != "sticky" else 0.0
				if -vn > 1.4:
					events.append(["land", global_position, -vn])
			else:
				e = Defs.WALL_BOUNCE
				if bumper:
					e = Defs.BUMPER_BOUNCE
				if mod == "bouncy":
					e = maxf(e, 1.0)
				elif mod == "sticky":
					e = 0.12
				var rt := rel - n * vn
				rel -= rt * 0.06  # a little rail friction
				if -vn > 0.2:
					bounces += 1
					events.append(["bumper" if bumper else "wall", global_position, -vn])
			rel -= n * vn * (1.0 + e)
			vel = rel + cv
		var rem := col.get_remainder()
		motion = rem.slide(n) if is_floor else vel.normalized() * rem.length() * 0.9
	# Stay glued to the green over small crests and dips while rolling.
	if not grounded and was_grounded and vel.y < 0.5:
		var snap := move_and_collide(Vector3.DOWN * 0.025, true, 0.001, false)
		if snap != null and snap.get_normal().y > 0.55:
			global_position += snap.get_travel()
			grounded = true
			ground_n = snap.get_normal()
			vel -= ground_n * minf(vel.dot(ground_n), 0.0)
	var sp2 := vel.length()
	if sp2 < 0.07:
		still_t += dt
	else:
		still_t = 0.0
	if grounded and sp2 < Defs.STOP_SPEED and push.length_squared() < 0.0001:
		var slope_pull := Defs.GRAVITY * gscale * sqrt(maxf(0.0, 1.0 - ground_n.y * ground_n.y))
		if slope_pull < Defs.ROLL_DECEL * decel_mult * 0.9 or still_t > 1.5:
			vel = Vector3.ZERO
			if not keep_awake:
				asleep = true
	if roll_t > Defs.MAX_ROLL_TIME:
		vel = Vector3.ZERO
		asleep = true


## Equal-mass knock between two balls (normal points from `o` to this ball).
func _knock(o: Me, n: Vector3) -> void:
	var rel := vel - o.vel
	var vn := rel.dot(n)
	if vn >= 0.0:
		return
	var j := -(1.0 + 0.8) * vn * 0.5
	vel += n * j
	o.vel -= n * j
	o.wake()
	events.append(["knock", global_position, -vn, o.slot])


## Ride the loop-the-loop: speed changes with height (gravity) and rolling loss; too slow near
## the top = fall off, too slow on the way up = roll back out.
func _rail_step(dt: float) -> void:
	var loop: Node3D = rail
	var tan_l: Vector3 = loop.call("tangent", rail_s)
	rail_v -= (Defs.GRAVITY * tan_l.y + (Defs.ROLL_DECEL + Defs.DRAG * absf(rail_v)) * signf(rail_v)) * dt
	rail_s += rail_v * dt
	var total: float = loop.call("total")
	if rail_s >= total or rail_s <= 0.0:
		var s_end := clampf(rail_s, 0.0, total)
		global_position = hole.to_global(loop.call("point", s_end))
		vel = hole.global_basis * (loop.call("tangent", s_end) as Vector3) * rail_v
		rail = null
		grounded = true
		ground_n = Vector3.UP
		events.append(["rail_off", global_position, absf(rail_v)])
		return
	if not bool(loop.call("holds", rail_s, rail_v)):
		vel = hole.global_basis * (loop.call("tangent", rail_s) as Vector3) * rail_v
		rail = null
		grounded = false
		events.append(["rail_fall", global_position, 0.0])
		return
	global_position = hole.to_global(loop.call("point", rail_s))
	vel = hole.global_basis * tan_l * rail_v


func start_rail(loop: Node3D, s: float, v: float) -> void:
	rail = loop
	rail_s = s
	rail_v = v
	asleep = false
	events.append(["rail_on", global_position, v])


# --- Mirror (TV machine) -------------------------------------------------------------------------

## A snapshot position arrived (TV machine).
func push_snapshot(p: Vector3) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _buf.is_empty() or p.distance_to(_buf[_buf.size() - 1][1]) > 2.5:
		_buf.clear()
		global_position = p
	_buf.append([now, p])
	while _buf.size() > 8:
		_buf.pop_front()


func _mirror_follow() -> void:
	if _buf.is_empty():
		return
	var render_t := Time.get_ticks_msec() / 1000.0 - 0.1
	var n := _buf.size()
	var target: Vector3 = _buf[n - 1][1]
	for i in range(n - 1, 0, -1):
		var t1: float = _buf[i][0]
		var t0: float = _buf[i - 1][0]
		if render_t >= t0:
			var p0: Vector3 = _buf[i - 1][1]
			var p1: Vector3 = _buf[i][1]
			target = p0.lerp(p1, clampf((render_t - t0) / maxf(t1 - t0, 0.001), 0.0, 1.0))
			break
		if i == 1:
			target = _buf[0][1]
	global_position = target


# --- Visual -----------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if mirror:
		_mirror_follow()
	if visual == null:
		return
	var p := global_position
	if _last_vis != Vector3.INF:
		var d := p - _last_vis
		d.y = 0.0
		var dist := d.length()
		if dist > 0.0001 and dist < 1.0:
			var axis := Vector3.UP.cross(d / dist)
			spin_node.global_basis = Basis(axis, dist / Defs.BALL_R) * spin_node.global_basis.orthonormalized()
	_last_vis = p
	if shadow.visible:
		var floor_y := _floor_below(p)
		shadow.visible = not is_nan(floor_y)
		if not is_nan(floor_y):
			var h := clampf((p.y - floor_y) * 3.0, 0.0, 1.0)
			shadow.global_position = Vector3(p.x, floor_y + 0.004, p.z)
			shadow.scale = Vector3.ONE * (1.0 + h * 0.6)
	if aura != null and aura.visible:
		aura.rotation.y += _delta * 3.0


func _floor_below(p: Vector3) -> float:
	if grounded and not mirror and state == "play":
		return p.y - Defs.BALL_R
	if _ray == null:
		_ray = PhysicsRayQueryParameters3D.new()
		_ray.collision_mask = Defs.L_FLOOR
	_ray.from = p + Vector3.UP * 0.02
	_ray.to = p + Vector3.DOWN * 1.5
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		return NAN
	return (hit.position as Vector3).y


## Show / hide the power-up glow (both machines; the host sends the mod with the putt event).
func set_mod_visual(m: String) -> void:
	mod = m
	_update_aura()


func _update_aura() -> void:
	if visual == null:
		return
	if mod == "":
		if aura != null:
			aura.visible = false
		spin_node.transparency = 0.0
		return
	if aura == null:
		aura = MeshInstance3D.new()
		aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.add_child(aura)
	var c: Color = Defs.POWERUP_COLORS.get(mod, Color.WHITE)
	aura.mesh = ResCache.get_or_make("mgp_aura_%s_v1" % mod, func() -> Resource:
		var b := MeshKit.Builder.new()
		b.torus(Defs.BALL_R * 1.5, Defs.BALL_R * 0.18, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(0.4, 0.0, 0.0)), c, 16, 4, true)
		b.torus(Defs.BALL_R * 1.5, Defs.BALL_R * 0.18, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(-0.4, 0.0, 1.2)), c, 16, 4, true)
		return b.build())
	aura.visible = true
	spin_node.transparency = 0.55 if mod == "ghost" else 0.0
	if not mirror and state == "play":
		collision_mask = Defs.MASK_GHOST if mod == "ghost" else Defs.MASK_ALL


## End of a roll: power-ups last one stroke.
func clear_mod() -> void:
	if mod != "":
		mod = ""
		_update_aura()
		if not mirror and state == "play":
			collision_mask = Defs.MASK_ALL
