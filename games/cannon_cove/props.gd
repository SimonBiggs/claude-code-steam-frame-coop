extends Node3D
## Simple mode: touchable things right beside each cannon, within the VR gunner's reach (Simon's rule:
## "everything should be interactable"). Each cannon has
##  - a little ship's BELL on a post (touch it: DING, it swings), with Polly's perch on top (poke her: SQUAWK),
##  - a ROPE hanging from the rigging (touch it and it swings; squeeze to pull it about),
##  - a BARREL that wobbles when touched (or bumped by a deckhand) with two spare CANNONBALLS on top.
##    Squeeze (trigger or grip) to pick up a ball or the whole barrel and throw it: over the side it goes,
##    SPLASH. A thrown ball can BONK a boarder overboard or SPLAT a tentacle. They come back by themselves.
## The host runs it all; the TV gets the swings as "prop" events and thrown things in the snapshot.
## Cheap: 8 small meshes per cannon, no shadows, no physics engine (a few lines of ballistics).

const World := preload("res://games/cannon_cove/world.gd")

const TOUCH_R := 0.15
const GRAB_R := 0.17
const BALL_R := 0.1
const BARREL_R := 0.2
const BARREL_H := 0.7
const ROPE_TOP := 5.0
const ROPE_BOTTOM := 1.25

var main
var items: Array = []  # one Dictionary per prop (see _add)
var hand_prev := {}  # tracker -> Vector3
var hand_vel := {}  # tracker -> Vector3
var squeeze_was := {}  # tracker -> bool
var _perches: Array = []
var poke_cool := 0.0
var announced := {}


func _ready() -> void:
	var wood := World.mat(Color(0.5, 0.32, 0.16))
	var brass := World.mat(Color(1.0, 0.78, 0.25), 0.4, 0.3)
	brass.metallic = 0.6
	var rope_m := World.mat(Color(0.78, 0.65, 0.42))
	var iron := World.mat(Color(0.12, 0.12, 0.14), 0.0, 0.35)
	iron.metallic = 0.6
	var barrel_m := World.mat(Color(0.62, 0.4, 0.2))
	for c in main.cannons:
		# Cannon-local layout: -Z out to sea, +Z inboard (the gunner stands at +1.45), +X the ammo-rack side.
		var post_pos := _at(c, 0.62, 0.0, 1.25)
		var post := World.cyl(self, 0.045, 0.05, 1.45, post_pos + Vector3.UP * 0.725, wood, 8)
		_plain(post)
		var arm_dir: Vector3 = (_at(c, 0.62, 0.0, 1.05) - post_pos)
		var arm := World.box(self, Vector3(0.05, 0.05, 0.26), post_pos + Vector3.UP * 1.43 + arm_dir * 0.5, wood)
		arm.rotation.y = atan2(arm_dir.x, arm_dir.z)
		_plain(arm)
		_perches.append(post_pos + Vector3.UP * 1.47)
		# Bell: hangs from the arm and swings.
		var bell_pivot := Node3D.new()
		bell_pivot.position = post_pos + arm_dir + Vector3.UP * 1.42
		add_child(bell_pivot)
		_plain(World.cyl(bell_pivot, 0.05, 0.11, 0.17, Vector3(0, -0.11, 0), brass, 10))
		_add({"kind": "bell", "node": bell_pivot, "hanging": true, "len": 0.12, "k": 40.0, "damp": 1.6})
		# Rope: from the rigging high above down to a knot at about hand height.
		var rope_pivot := Node3D.new()
		var rope_xz := _at(c, -0.55, 0.0, 0.95)
		rope_pivot.position = rope_xz + Vector3.UP * ROPE_TOP
		add_child(rope_pivot)
		var rl := ROPE_TOP - ROPE_BOTTOM
		_plain(World.cyl(rope_pivot, 0.022, 0.022, rl, Vector3(0, -rl * 0.5, 0), rope_m, 6))
		_plain(World.sphere(rope_pivot, 0.06, Vector3(0, -rl, 0), rope_m, 8))
		_add({"kind": "rope", "node": rope_pivot, "hanging": true, "len": rl, "k": 9.8 / rl, "damp": 0.35})
		# Barrel (wobbles; can be lifted and thrown) with two spare cannonballs on top.
		var barrel := Node3D.new()
		barrel.position = _at(c, -0.68, 0.0, 1.38)
		add_child(barrel)
		var body := World.cyl(barrel, BARREL_R, BARREL_R, BARREL_H, Vector3(0, BARREL_H * 0.5, 0), barrel_m, 10)
		_plain(body)
		var bi := _add({"kind": "barrel", "node": barrel, "hanging": false, "len": BARREL_H, "k": 70.0, "damp": 5.0,
			"throw": true, "radius": 0.0})
		for s in [-1.0, 1.0]:
			var ball := World.sphere(self, BALL_R, barrel.position + Vector3.UP * (BARREL_H + BALL_R)
				+ (_at(c, 0.0, 0.0, 0.09 * s) - _at(c, 0.0, 0.0, 0.0)), iron, 10)
			_plain(ball)
			_add({"kind": "ball", "node": ball, "throw": true, "radius": BALL_R, "on": bi})


## A point in cannon c's frame, on the deck (y is world height).
func _at(c, x: float, y: float, z: float) -> Vector3:
	var yaw := atan2(-c.outboard.x, -c.outboard.z)
	var p: Vector3 = Basis(Vector3.UP, yaw) * Vector3(x, 0.0, z)
	return Vector3(c.position.x + p.x, y, c.position.z + p.z)


func _plain(m: GeometryInstance3D) -> void:
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add(d: Dictionary) -> int:
	var n: Node3D = d.node
	d["home"] = n.transform
	d["swing"] = Vector2.ZERO
	d["swing_v"] = Vector2.ZERO
	d["cool"] = 0.0
	d["state"] = "home"  # throwables: home, held, flying, rest, gone
	d["hand"] = null
	d["offset"] = Vector3.ZERO
	d["vel"] = Vector3.ZERO
	d["spin"] = Vector3.ZERO
	d["t"] = 0.0
	items.append(d)
	return items.size() - 1


## Where Polly perches next to each cannon (on top of the bell post).
func perches() -> Array:
	return _perches


func is_holding(h) -> bool:
	for d in items:
		if d.state == "held" and d.hand == h:
			return true
	return false


## True when hand h is close enough to pick something up (so a squeeze there isn't a "missed the handle").
func near_grabbable(h) -> bool:
	var p: Vector3 = h.global_position
	for d in items:
		if d.get("throw", false) and d.state == "home" and _grab_dist(d, p) < GRAB_R:
			return true
	for d in items:
		if d.kind == "rope" and _touch_point(d).distance_to(p) < GRAB_R + 0.05:
			return true
	return false


func _grab_dist(d: Dictionary, p: Vector3) -> float:
	var n: Node3D = d.node
	if d.kind == "barrel":
		var flat := Vector2(p.x - n.position.x, p.z - n.position.z).length() - BARREL_R
		var dy := maxf(0.0, p.y - (n.position.y + BARREL_H)) + maxf(0.0, n.position.y + 0.1 - p.y)
		return maxf(flat, 0.0) + dy
	return n.global_position.distance_to(p) - BALL_R


## The bit of a swinging prop a hand touches: the bell itself, the knot, the top of the barrel.
func _touch_point(d: Dictionary) -> Vector3:
	var n: Node3D = d.node
	if d.hanging:
		return n.global_transform * Vector3(0, -d.len, 0)
	return n.global_transform * Vector3(0, d.len * 0.75, 0)


# --- Per frame -------------------------------------------------------------------------

func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	poke_cool = maxf(0.0, poke_cool - delta)
	var host: bool = main.net.mode != "client"
	var g = main.players[0] if not main.players.is_empty() else null
	if host and g != null and (g.vr or g.fake_vr) and not g.ghost and not main.get_tree().paused:
		for h in [g.hand_r, g.hand_l]:
			_hand(g, h, delta)
	if host:
		_deckhand_bumps()
	for i in items.size():
		var d: Dictionary = items[i]
		d.cool = maxf(0.0, d.cool - delta)
		if d.has("k") and d.state == "home":
			_swing(d, delta)
		if host and d.get("throw", false):
			_throwable(i, d, delta)


func _swing(d: Dictionary, delta: float) -> void:
	var sw: Vector2 = d.swing
	var sv: Vector2 = d.swing_v
	sv += (-sw * float(d.k) - sv * float(d.damp)) * delta
	sw += sv * delta
	var lim := 0.2 if d.kind == "barrel" else 1.0
	if sw.length() > lim:
		sw = sw.normalized() * lim
		sv *= 0.5
	d.swing = sw
	d.swing_v = sv
	var n: Node3D = d.node
	var home: Transform3D = d.home
	# sw = how far the bottom (hanging) / top (standing) has swung in world x and z, as angles.
	var rot := Vector3(-sw.y, 0.0, sw.x) if d.hanging else Vector3(sw.y, 0.0, -sw.x)
	n.transform = Transform3D(Basis.from_euler(rot) * home.basis, home.origin)


## A hand moving into a prop: push it (and ring / squawk / wobble), or pick it up.
func _hand(g, h: XRController3D, delta: float) -> void:
	var p: Vector3 = h.global_position
	var key: String = str(h.tracker)
	var prev: Vector3 = hand_prev.get(key, p)
	hand_prev[key] = p
	var v: Vector3 = hand_vel.get(key, Vector3.ZERO)
	v = v.lerp((p - prev) / delta, 0.5)
	hand_vel[key] = v
	var squeeze: bool = g._trig(h) or g._grip(h)
	var edge: bool = squeeze and not squeeze_was.get(key, true)
	squeeze_was[key] = squeeze
	var held = null
	for d in items:
		if d.state == "held" and d.hand == h:
			held = d
	if held != null:
		if not squeeze:
			_release(items.find(held), held, v)
		return
	if g.grab_hand == h:
		return  # busy aiming the cannon
	var speed := v.length()
	# Pick up: the nearest ball (or the barrel) under a fresh squeeze.
	if edge:
		var best = null
		var best_d := GRAB_R
		for d in items:
			if not d.get("throw", false) or d.state != "home":
				continue
			var gd := _grab_dist(d, p)
			if d.kind == "barrel":
				gd += 0.05  # the balls on top win
			if gd < best_d:
				best_d = gd
				best = d
		if best != null:
			_pick_up(best, h)
			return
	for i in items.size():
		var d: Dictionary = items[i]
		if not d.has("k") or d.state != "home":
			continue
		var tp := _touch_point(d)
		var r := TOUCH_R + (BARREL_R if d.kind == "barrel" else 0.0)
		if d.kind == "barrel":
			var flat := Vector2(p.x - tp.x, p.z - tp.z).length()
			if flat > r or p.y > tp.y + 0.3 or p.y < 0.1:
				continue
		elif tp.distance_to(p) > r + (0.05 if d.kind == "rope" else 0.0):
			continue
		if d.kind == "rope" and squeeze:
			# Holding the rope: the knot follows the hand (a bit).
			var top: Vector3 = (d.home as Transform3D).origin
			var off := p - top
			var ang := Vector2(off.x, off.z) / maxf(0.5, -off.y)
			d.swing = ang.limit_length(0.6)
			d.swing_v = Vector2(v.x, v.z) / float(d.len)
			if d.cool <= 0.0:
				d.cool = 0.6
				main.sound("rope", -8.0, randf_range(0.8, 1.1))
			continue
		if speed < 0.15 or d.cool > 0.0:
			continue
		var push := Vector2(v.x, v.z)
		if push.length() < 0.3:
			push = Vector2(p.x - tp.x, p.z - tp.z).normalized() * -0.3
		var imp: Vector2 = push.limit_length(3.0) * {"bell": 3.0, "rope": 0.35, "barrel": 0.9}[d.kind]
		_impulse(i, imp)
		d.cool = 0.35
		match d.kind:
			"bell":
				main.sound("bell", -4.0, 1.5 + randf_range(-0.05, 0.05))
				h.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.08, 0.0)
				_note("bell")
			"rope":
				main.sound("rope", -8.0, randf_range(0.8, 1.1))
				h.trigger_haptic_pulse("haptic", 0.0, 0.2, 0.05, 0.0)
				_note("rope")
			"barrel":
				main.sound("creak", -10.0, randf_range(1.4, 1.7))
				h.trigger_haptic_pulse("haptic", 0.0, 0.35, 0.06, 0.0)
				_note("barrel")
	# Poke Polly.
	var parrot = main.parrot
	if parrot != null and is_instance_valid(parrot) and parrot.visible and poke_cool <= 0.0 and speed > 0.1:
		if (parrot.global_position + Vector3.UP * 0.25).distance_to(p) < 0.2:
			poke_cool = 1.0
			parrot.poke()
			main.net.event("prop", [-1, Vector2.ZERO])
			h.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.05, 0.0)
			_note("parrot")


func _impulse(i: int, imp: Vector2) -> void:
	var d: Dictionary = items[i]
	d.swing_v = (d.swing_v as Vector2) + imp
	main.net.event("prop", [i, imp])


func _note(what: String) -> void:
	if not announced.has(what):
		announced[what] = true
		print("Prop touched: %s" % what)


## Host: deckhands walking into a barrel make it wobble.
func _deckhand_bumps() -> void:
	for i in items.size():
		var d: Dictionary = items[i]
		if d.kind != "barrel" or d.state != "home" or d.cool > 0.0:
			continue
		var bp: Vector3 = (d.home as Transform3D).origin
		for p in main.deckhands():
			var off: Vector3 = bp - p.global_position
			off.y = 0.0
			if off.length() < 0.6:
				_impulse(i, Vector2(off.x, off.z).normalized() * 0.8)
				d.cool = 0.8
				main.sound("creak", -12.0, 1.5)
				break


# --- Throwables (host) -------------------------------------------------------------------

func _pick_up(d: Dictionary, h) -> void:
	var n: Node3D = d.node
	d.state = "held"
	d.hand = h
	d.offset = (n.global_position - h.global_position).limit_length(0.12 if d.kind == "ball" else 0.35)
	d.swing = Vector2.ZERO
	d.swing_v = Vector2.ZERO
	h.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.05, 0.0)
	main.sound("pickup", -6.0, 1.1 if d.kind == "ball" else 0.7)
	if d.kind == "barrel":
		# The balls on top tumble off.
		var bi := items.find(d)
		for o in items:
			if o.get("on", -1) == bi and o.state == "home":
				o.state = "flying"
				o.vel = Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5))
				o.t = 0.0
	_note("pick up " + d.kind)


func _release(_i: int, d: Dictionary, v: Vector3) -> void:
	d.state = "flying"
	d.hand = null
	d.t = 0.0
	d.vel = v * 1.35 + Vector3.UP * 0.4  # a little boost: kids' throws are short
	d.spin = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	if v.length() > 1.0:
		main.sound("rope", -10.0, 1.6)  # whoosh


func _throwable(i: int, d: Dictionary, delta: float) -> void:
	var n: Node3D = d.node
	d.t = float(d.t) + delta
	match d.state:
		"held":
			var h: Node3D = d.hand
			if h == null or not is_instance_valid(h):
				d.state = "flying"
				return
			n.global_position = h.global_position + d.offset
		"flying":
			_fly(i, d, delta)
		"rest":
			if d.t > 2.5:
				main.smoke(n.global_position + Vector3.UP * 0.2, 0.4)
				_go_home(d)
		"gone":
			if d.t > 2.0:
				_go_home(d)


func _fly(_i: int, d: Dictionary, delta: float) -> void:
	var n: Node3D = d.node
	var vel: Vector3 = d.vel
	vel.y -= main.GRAVITY * delta
	var pos := n.global_position + vel * delta
	n.global_position = pos
	n.rotation += (d.spin as Vector3) * delta
	var r: float = d.radius
	if d.kind == "ball" and vel.length() > 2.0:
		# A thrown ball can bonk a boarder or splat a tentacle.
		for b in main.get_tree().get_nodes_in_group("boarders"):
			if b.alive() and (b.global_position + Vector3.UP * 1.0).distance_to(pos) < 0.65:
				main.prop_bonk(b, pos)
				vel = Vector3(-vel.x * 0.3, 1.0, -vel.z * 0.3)
				_note("bonk boarder")
		var target = main.ball_hit_test(pos)
		if target != null and not target.is_in_group("targets"):
			main.on_ball_hit(target, pos)
			_note("hit " + str(target.get_groups()))
			_vanish(d)
			return
	d.vel = vel
	if World.on_deck(pos, 0.1):
		if pos.y <= r and vel.y < 0.0:
			if vel.y < -1.6:
				vel.y = -vel.y * 0.35
				vel.x *= 0.6
				vel.z *= 0.6
				d.vel = vel
				d.spin = (d.spin as Vector3) * 0.5
				main.sound("hammer", -10.0, 0.5)
			else:
				n.global_position.y = r
				d.state = "rest"
				d.t = 0.0
		return
	if pos.y < main.sea_level:
		main.splash(Vector3(pos.x, main.sea_level, pos.z), 1.2 if d.kind == "barrel" else 0.7)
		main.sound("splash", -2.0, 1.4 if d.kind == "ball" else 0.9)
		if not announced.has("splash"):
			announced["splash"] = true
			print("Prop thrown overboard: SPLASH (%s)" % d.kind)
		_vanish(d)
	elif d.t > 6.0:
		_vanish(d)


func _vanish(d: Dictionary) -> void:
	(d.node as Node3D).visible = false
	d.state = "gone"
	d.t = 0.0


func _go_home(d: Dictionary) -> void:
	var on: int = d.get("on", -1)
	if on >= 0 and items[on].state != "home":
		d.t = 0.0  # wait for the barrel to come back first
		(d.node as Node3D).visible = false
		d.state = "gone"
		return
	var n: Node3D = d.node
	n.transform = d.home
	n.visible = true
	n.scale = Vector3.ONE * 0.05
	n.create_tween().tween_property(n, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	d.state = "home"
	d.vel = Vector3.ZERO
	main.sound("load", -10.0, 1.6)


# --- Networking -------------------------------------------------------------------------

## Snapshot: [[index, position, visible], ...] for the thrown / carried things that aren't at home.
func net_state() -> Array:
	var out := []
	for i in items.size():
		var d: Dictionary = items[i]
		if d.get("throw", false) and d.state != "home":
			var n: Node3D = d.node
			out.append([i, n.global_position, n.visible])
	return out


func apply_net(list: Array) -> void:
	var seen := {}
	for it in list:
		var i: int = it[0]
		if i < 0 or i >= items.size():
			continue
		seen[i] = true
		var n: Node3D = items[i].node
		n.global_position = it[1]
		n.visible = it[2]
		items[i].state = "away"
	for i in items.size():
		var d: Dictionary = items[i]
		if d.get("throw", false) and d.state == "away" and not seen.has(i):
			d.state = "home"
			var n: Node3D = d.node
			n.transform = d.home
			n.visible = true


## TV: a swing (bell, rope, barrel) or a poke (Polly, index -1) happened on the host.
func apply_event(args: Array) -> void:
	var i: int = args[0]
	if i < 0:
		if main.parrot and is_instance_valid(main.parrot):
			main.parrot.poke()
		return
	if i < items.size():
		var d: Dictionary = items[i]
		d.swing_v = (d.swing_v as Vector2) + (args[1] as Vector2)
