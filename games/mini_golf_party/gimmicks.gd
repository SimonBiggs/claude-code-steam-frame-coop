extends RefCounted
## MINI GOLF PARTY: the moving and scripted course pieces. Every gimmick is a Node3D child of its
## hole (so its spec coordinates are hole-local) driven ONLY by the hole clock `t` (update(t)), which
## the host sends to the TV machine: both machines show the same windmill angle without syncing nodes.
## Moving bodies are AnimatableBody3D on the obstacle layer with meta "mgp_owner" -> the gimmick, so
## the ball physics can ask velocity_at(point) for a proper bounce off a moving blade or hull.
##   windmill  4 sails turning in front of a tunnel through the mill (gate: clear_at(t))
##   cannon    a funnel into the breech; the hole launches captured balls on an arc to `target`
##   ship      a pirate ship sailing between a and b
##   mover     a post / box / sphere sliding between a and b (kraken tentacles rise and sink)
##   orbit     a sphere circling a centre (asteroids)
##   spinner   bars turning round a hub
##   loop      a loop-the-loop rail the hole moves balls along (with real speed loss / roll-back)
##   portal    a pair of rings: in at a, out at b
##   powerup   a spinning "?" box (party mode)

const Defs := preload("res://games/mini_golf_party/defs.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const UiKit := preload("res://core/ui_kit.gd")
const Me := preload("res://games/mini_golf_party/gimmicks.gd")


static func make(g: Dictionary, theme: String) -> Gimmick:
	var n: Gimmick
	match String(g.get("type", "")):
		"windmill":
			n = Windmill.new()
		"cannon":
			n = Cannon.new()
		"ship":
			n = Ship.new()
		"mover":
			n = Mover.new()
		"orbit":
			n = Orbit.new()
		"spinner":
			n = Spinner.new()
		"loop":
			n = Loop.new()
		"portal":
			n = Portal.new()
		_:
			n = Gimmick.new()
	n.g = g
	n.theme = theme
	n.build()
	return n


## A body on the obstacle layer that points back at its gimmick (for velocity_at).
static func mover_body(owner: Node3D) -> AnimatableBody3D:
	var b := AnimatableBody3D.new()
	b.sync_to_physics = false
	b.collision_layer = Defs.L_MOVER
	b.collision_mask = 0
	b.set_meta("mgp_owner", owner)
	return b


static func box_shape(size: Vector3, xf: Transform3D = Transform3D.IDENTITY) -> CollisionShape3D:
	var s := BoxShape3D.new()
	s.size = size
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.transform = xf
	return cs


static func cyl_shape(r: float, h: float, xf: Transform3D = Transform3D.IDENTITY) -> CollisionShape3D:
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.transform = xf
	return cs


static func sphere_shape(r: float, xf: Transform3D = Transform3D.IDENTITY) -> CollisionShape3D:
	var s := SphereShape3D.new()
	s.radius = r
	var cs := CollisionShape3D.new()
	cs.shape = s
	cs.transform = xf
	return cs


static func cached(key: String, maker: Callable) -> ArrayMesh:
	return ResCache.get_or_make("mgp_" + key + "_v1", maker) as ArrayMesh


## 0 -> 1 -> 0 smoothly over a period (ping-pong), offset by phase (0..1).
static func swing(t: float, period: float, phase: float) -> float:
	return 0.5 - 0.5 * cos(TAU * (t / maxf(period, 0.01) + phase))


static func swing_rate(t: float, period: float, phase: float) -> float:
	var p := maxf(period, 0.01)
	return 0.5 * sin(TAU * (t / p + phase)) * TAU / p


# =================================================================================================

class Gimmick extends Node3D:
	var g: Dictionary = {}
	var theme := "pirate"
	## The hole time of the last update() (velocity_at uses it).
	var cur_t := 0.0

	func build() -> void:
		pass

	## Set everything from the hole clock (seconds since the hole started).
	func update(_t: float) -> void:
		pass

	## World velocity of the moving surface at a world point (for bounces).
	func velocity_at(_p: Vector3) -> Vector3:
		return Vector3.ZERO

	## True if a ball at this world point should stay awake (something may push it).
	func influence(_p: Vector3) -> bool:
		return false

	## Gates (windmill, ship): is the way through clear at hole time t?
	func clear_at(_t: float) -> bool:
		return true

	func space() -> bool:
		return theme == "space"


# --- Windmill ------------------------------------------------------------------------------------

class Windmill extends Gimmick:
	var blades: AnimatableBody3D
	var hub := Vector3.ZERO
	var speed := 1.0
	var count := 4
	var blade_len := 0.78
	var gap := 0.34

	func build() -> void:
		var at: Vector3 = g.get("at", Vector3.ZERO)
		position = at
		rotation.y = float(g.get("yaw", 0.0))
		speed = float(g.get("speed", 1.0))
		gap = float(g.get("gap", 0.34))
		var w := float(g.get("w", 1.3))
		var depth := float(g.get("depth", 0.8))
		var tunnel_h := 0.3
		var space_look := space()
		var stone := Color(0.93, 0.88, 0.78) if not space_look else Color(0.62, 0.66, 0.74)
		var roof := Color(0.85, 0.3, 0.25) if not space_look else Color(0.3, 0.42, 0.62)
		var key := "windmill_%s_%.2f_%.2f_%.2f" % [theme, w, depth, gap]
		var mesh := Me.cached(key, func() -> Resource:
			var b := MeshKit.Builder.new()
			var side := (w - gap) * 0.5
			for s in [-1.0, 1.0]:
				var sx: float = s
				b.box(Vector3(side, tunnel_h, depth), MeshKit.at(Vector3(sx * (gap * 0.5 + side * 0.5), tunnel_h * 0.5, 0.0)), stone)
				b.box(Vector3(0.03, tunnel_h, depth), MeshKit.at(Vector3(sx * (gap * 0.5 + 0.015), tunnel_h * 0.5, 0.0)), stone.darkened(0.55))
			var tower_xf := Transform3D(Basis.from_scale(Vector3(1.0, 1.0, depth / w)) * Basis(Vector3.UP, PI * 0.25), Vector3(0.0, tunnel_h + 0.625, 0.0))
			b.cylinder(w * 0.5, w * 0.72, 1.25, tower_xf, stone, 4)
			b.box(Vector3(gap + 0.08, 0.06, depth + 0.02), MeshKit.at(Vector3(0.0, tunnel_h + 0.03, 0.0)), stone.darkened(0.25))
			b.cone(w * 0.62, 0.7, Transform3D(Basis.from_scale(Vector3(1.0, 1.0, maxf(depth / w, 0.75))) * Basis(Vector3.UP, PI * 0.25), Vector3(0.0, tunnel_h + 1.6, 0.0)), roof, 4)
			for wy in [0.75, 1.1]:
				var face_z := depth * (0.51 - float(wy) / 1.25 * 0.156) + 0.012
				b.box(Vector3(0.14, 0.18, 0.02), MeshKit.at(Vector3(0.0, tunnel_h + float(wy), face_z)), Color(1.0, 0.85, 0.45), true)
			b.cylinder(0.05, 0.05, 0.2, MeshKit.at(Vector3(0.0, tunnel_h + 0.52, depth * 0.47 + 0.06), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), Color(0.35, 0.25, 0.18), 8)
			return b.build())
		add_child(MeshKit.instance(mesh))
		var body := StaticBody3D.new()
		body.collision_layer = Defs.L_OBST
		body.collision_mask = 0
		var side_w := (w - gap) * 0.5
		for s in [-1.0, 1.0]:
			var sx: float = s
			body.add_child(Me.box_shape(Vector3(side_w, 0.6, depth), Transform3D(Basis(), Vector3(sx * (gap * 0.5 + side_w * 0.5), 0.3, 0.0))))
		add_child(body)
		hub = Vector3(0.0, tunnel_h + 0.52, depth * 0.5 + 0.16)
		blade_len = hub.y - 0.04
		blades = Me.mover_body(self)
		blades.position = hub
		add_child(blades)
		var sail_key := "windmill_sails_%s_%.2f" % [theme, blade_len]
		var sails := Me.cached(sail_key, func() -> Resource:
			var b := MeshKit.Builder.new()
			for k in count:
				var a := TAU * float(k) / count
				var dir := Vector3(sin(a), cos(a), 0.0)
				var xf := Transform3D(Basis(Vector3.BACK, -a), Vector3.ZERO)
				b.box(Vector3(0.035, blade_len, 0.03), xf * MeshKit.at(Vector3(0.0, blade_len * 0.5, 0.0)), Color(0.45, 0.3, 0.2))
				b.box(Vector3(0.13, blade_len * 0.78, 0.012), xf * MeshKit.at(Vector3(0.07, blade_len * 0.56, 0.0)), Color(0.98, 0.97, 0.92) if not theme == "space" else Color(0.75, 0.9, 1.0))
				var _unused := dir
			b.sphere(0.07, MeshKit.at(Vector3.ZERO), Color(0.8, 0.2, 0.2), 10)
			return b.build())
		blades.add_child(MeshKit.instance(sails))
		for k in count:
			var a := TAU * float(k) / count
			var xf := Transform3D(Basis(Vector3.BACK, -a), Vector3.ZERO) * Transform3D(Basis(), Vector3(0.035, blade_len * 0.55, 0.0))
			blades.add_child(Me.box_shape(Vector3(0.15, blade_len * 0.9, 0.05), xf))

	func angle(t: float) -> float:
		return speed * t + float(g.get("phase", 0.0))

	func update(t: float) -> void:
		blades.rotation = Vector3(0.0, 0.0, -angle(t))

	func velocity_at(p: Vector3) -> Vector3:
		var axis := -blades.global_basis.z.normalized()
		return axis.cross(p - blades.global_position) * speed

	func influence(p: Vector3) -> bool:
		return p.distance_to(blades.global_position) < blade_len + 0.25

	## Is the tunnel free of sails at hole time t (with a safety margin)?
	func clear_at(t: float) -> bool:
		var half := atan((gap * 0.5 + Defs.BALL_R + 0.09) / maxf(hub.y - 0.05, 0.1)) + deg_to_rad(9.0)
		for k in count:
			var a := fposmod(angle(t) + TAU * float(k) / count, TAU)
			if absf(a - PI) < half:
				return false
		return true


# --- Cannon --------------------------------------------------------------------------------------

class Cannon extends Gimmick:
	var barrel: Node3D
	var kick := 0.0

	func build() -> void:
		position = g.get("at", Vector3.ZERO)
		rotation.y = float(g.get("yaw", 0.0))
		var mesh := Me.cached("cannon_" + theme, func() -> Resource:
			var b := MeshKit.Builder.new()
			var wood := Color(0.55, 0.36, 0.22)
			b.box(Vector3(0.5, 0.16, 0.7), MeshKit.at(Vector3(0.0, 0.2, 0.05)), wood)
			for s in [-1.0, 1.0]:
				var sx: float = s
				for wz in [-0.22, 0.28]:
					b.cylinder(0.13, 0.13, 0.06, MeshKit.at(Vector3(sx * 0.28, 0.13, float(wz)), Vector3.ONE, Vector3(0.0, 0.0, PI * 0.5)), Color(0.35, 0.22, 0.14), 12)
			# funnel mouth (the breech) the ball rolls into
			b.cylinder(0.2, 0.2, 0.05, MeshKit.at(Vector3(0.0, 0.006, 0.0)), Color(0.08, 0.08, 0.1), 16)
			b.torus(0.2, 0.025, MeshKit.at(Vector3(0.0, 0.02, 0.0)), Color(0.85, 0.7, 0.3), 16, 6)
			return b.build())
		add_child(MeshKit.instance(mesh))
		barrel = Node3D.new()
		barrel.position = Vector3(0.0, 0.42, -0.05)
		barrel.rotation.x = deg_to_rad(28.0)
		add_child(barrel)
		var bm := Me.cached("cannon_barrel", func() -> Resource:
			var b := MeshKit.Builder.new()
			b.cylinder(0.11, 0.15, 0.95, MeshKit.at(Vector3(0.0, 0.0, -0.3), Vector3.ONE, Vector3(-PI * 0.5, 0.0, 0.0)), Color(0.16, 0.16, 0.18), 14)
			b.torus(0.12, 0.03, MeshKit.at(Vector3(0.0, 0.0, -0.77), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), Color(0.25, 0.25, 0.28), 14, 6)
			b.sphere(0.16, MeshKit.at(Vector3(0.0, 0.0, 0.2)), Color(0.16, 0.16, 0.18), 12)
			b.disc(0.09, MeshKit.at(Vector3(0.0, 0.0, -0.785), Vector3.ONE, Vector3(PI * 0.5, 0.0, 0.0)), Color(0.02, 0.02, 0.02), 12)
			return b.build())
		barrel.add_child(MeshKit.instance(bm))
		var body := StaticBody3D.new()
		body.collision_layer = Defs.L_OBST
		body.collision_mask = 0
		body.add_child(Me.box_shape(Vector3(0.5, 0.3, 0.45), Transform3D(Basis(), Vector3(0.0, 0.15, -0.38))))
		add_child(body)

	## World position of the muzzle (where balls fly out).
	func muzzle() -> Vector3:
		return barrel.global_transform * Vector3(0.0, 0.0, -0.8)

	## Recoil + smoke (both machines).
	func fire_fx() -> void:
		kick = 1.0

	func update(_t: float) -> void:
		var dt := get_process_delta_time()
		kick = maxf(0.0, kick - dt * 3.0)
		barrel.position.z = -0.05 + kick * 0.12

	func influence(p: Vector3) -> bool:
		return p.distance_to(global_position) < 0.6


# --- Pirate ship ---------------------------------------------------------------------------------

class Ship extends Gimmick:
	var body: AnimatableBody3D
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	var period := 8.0
	var phase := 0.0
	var size := Vector3(0.6, 0.5, 1.7)

	func build() -> void:
		a = g.get("a", Vector3.ZERO)
		b = g.get("b", Vector3(0.0, 0.0, -2.0))
		period = float(g.get("period", 8.0))
		phase = float(g.get("phase", 0.0))
		size = g.get("size", size)
		body = Me.mover_body(self)
		add_child(body)
		var d := b - a
		body.rotation.y = atan2(-d.x, -d.z)
		var sz := size
		var mesh := Me.cached("ship_%.2f_%.2f" % [sz.x, sz.z], func() -> Resource:
			var mb := MeshKit.Builder.new()
			var hull := Color(0.5, 0.3, 0.18)
			mb.rounded_box(Vector3(sz.x, sz.y, sz.z), 0.12, MeshKit.at(Vector3(0.0, sz.y * 0.5 - 0.08, 0.0)), hull)
			mb.wedge(Vector3(sz.x * 0.98, sz.y * 0.9, 0.4), MeshKit.at(Vector3(0.0, sz.y * 0.5 - 0.06, -sz.z * 0.5 - 0.18), Vector3.ONE, Vector3(0.0, PI, 0.0)), hull.darkened(0.1))
			mb.box(Vector3(sz.x * 0.9, 0.04, sz.z * 0.95), MeshKit.at(Vector3(0.0, sz.y - 0.06, 0.0)), Color(0.75, 0.6, 0.4))
			mb.box(Vector3(sz.x * 0.9, 0.18, 0.35), MeshKit.at(Vector3(0.0, sz.y + 0.05, sz.z * 0.38)), hull.lightened(0.1))
			mb.cylinder(0.035, 0.045, 1.5, MeshKit.at(Vector3(0.0, sz.y + 0.7, -0.05)), Color(0.4, 0.27, 0.16), 8)
			mb.box(Vector3(sz.x * 1.25, 0.6, 0.03), MeshKit.at(Vector3(0.0, sz.y + 0.75, -0.02)), Color(0.97, 0.95, 0.88))
			mb.box(Vector3(sz.x * 0.9, 0.35, 0.03), MeshKit.at(Vector3(0.0, sz.y + 1.25, -0.02)), Color(0.97, 0.95, 0.88))
			mb.box(Vector3(0.22, 0.14, 0.01), MeshKit.at(Vector3(0.12, sz.y + 1.5, -0.05)), Color(0.08, 0.08, 0.1))
			mb.sphere(0.035, MeshKit.at(Vector3(0.1, sz.y + 1.51, -0.06)), Color(0.95, 0.95, 0.95), 8)
			for k in 3:
				for s in [-1.0, 1.0]:
					mb.cylinder(0.04, 0.04, 0.02, MeshKit.at(Vector3(float(s) * sz.x * 0.5, sz.y * 0.55, -0.35 + k * 0.35), Vector3.ONE, Vector3(0.0, 0.0, PI * 0.5)), Color(0.1, 0.1, 0.12), 10)
			return mb.build())
		body.add_child(MeshKit.instance(mesh))
		body.add_child(Me.box_shape(Vector3(size.x, 0.5, size.z + 0.3), Transform3D(Basis(), Vector3(0.0, 0.2, -0.1))))

	func pos_at(t: float) -> Vector3:
		return a.lerp(b, Me.swing(t, period, phase))

	func update(t: float) -> void:
		cur_t = t
		body.position = pos_at(t) + Vector3.UP * (sin(t * 1.7) * 0.015)
		body.rotation.z = sin(t * 1.3) * 0.04

	func velocity_at(_p: Vector3) -> Vector3:
		var local_v := (b - a) * Me.swing_rate(cur_t, period, phase)
		return global_basis * local_v

	func influence(p: Vector3) -> bool:
		return p.distance_to(body.global_position) < size.z + 0.6

	## Is the ship well away from the crossing point `g.cross` at hole time t?
	func clear_at(t: float) -> bool:
		var cross: Vector3 = g.get("cross", (a + b) * 0.5)
		var p := pos_at(t)
		return Vector2(p.x - cross.x, p.z - cross.z).length() > size.z * 0.5 + 0.55


# --- Mover (tentacles, sliding blocks) -------------------------------------------------------------

class Mover extends Gimmick:
	var body: AnimatableBody3D
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	var period := 3.0
	var phase := 0.0

	func build() -> void:
		a = g.get("a", Vector3.ZERO)
		b = g.get("b", Vector3.ZERO)
		period = float(g.get("period", 3.0))
		phase = float(g.get("phase", 0.0))
		body = Me.mover_body(self)
		add_child(body)
		var look := String(g.get("look", "tentacle"))
		var r := float(g.get("r", 0.09))
		var h := float(g.get("h", 0.55))
		match look:
			"tentacle":
				var tm := Me.cached("tentacle_%.2f_%.2f" % [r, h], func() -> Resource:
					var mb := MeshKit.Builder.new()
					var c := Color(0.62, 0.3, 0.72)
					mb.cylinder(r * 0.8, r, h * 0.7, MeshKit.at(Vector3(0.0, h * 0.35, 0.0)), c, 10)
					mb.capsule_between(Vector3(0.0, h * 0.68, 0.0), Vector3(r * 0.6, h * 0.95, 0.0), r * 0.7, c, 10)
					mb.sphere(r * 0.55, MeshKit.at(Vector3(r * 1.1, h * 1.0, 0.0)), c.lightened(0.1), 8)
					for k in 5:
						var ang := float(k) * 1.3
						mb.sphere(r * 0.22, MeshKit.at(Vector3(cos(ang) * r * 0.95, 0.08 + k * h * 0.13, sin(ang) * r * 0.95)), Color(1.0, 0.7, 0.8), 6)
					return mb.build())
				body.add_child(MeshKit.instance(tm))
				body.add_child(Me.cyl_shape(r, h, Transform3D(Basis(), Vector3(0.0, h * 0.5, 0.0))))
			"block":
				var sz: Vector3 = g.get("size", Vector3(0.4, 0.2, 0.25))
				var bm := Me.cached("slider_%s_%.2f_%.2f_%.2f" % [theme, sz.x, sz.y, sz.z], func() -> Resource:
					var mb := MeshKit.Builder.new()
					mb.rounded_box(sz, 0.04, MeshKit.at(Vector3(0.0, sz.y * 0.5, 0.0)), Color(0.55, 0.6, 0.7) if theme == "space" else Color(0.6, 0.42, 0.26))
					mb.box(Vector3(sz.x * 1.01, 0.03, sz.z * 1.01), MeshKit.at(Vector3(0.0, sz.y * 0.7, 0.0)), Color(1.0, 0.8, 0.2), theme == "space")
					return mb.build())
				body.add_child(MeshKit.instance(bm))
				body.add_child(Me.box_shape(sz, Transform3D(Basis(), Vector3(0.0, sz.y * 0.5, 0.0))))
			_:
				var am := Me.cached("asteroid_%.2f" % r, func() -> Resource: return Me.asteroid_mesh(r))
				body.add_child(MeshKit.instance(am))
				body.add_child(Me.sphere_shape(r))

	func update(t: float) -> void:
		cur_t = t
		body.position = a.lerp(b, Me.swing(t, period, phase))
		if String(g.get("look", "")) == "asteroid":
			body.rotation = Vector3(t * 0.7, t * 0.4, 0.0)
		elif String(g.get("look", "")) == "tentacle":
			body.rotation.y = sin(t * 2.0 + phase * 7.0) * 0.6

	func velocity_at(_p: Vector3) -> Vector3:
		return global_basis * ((b - a) * Me.swing_rate(cur_t, period, phase))

	func influence(p: Vector3) -> bool:
		return p.distance_to(body.global_position) < 0.8 + a.distance_to(b) * 0.5

	func clear_at(t: float) -> bool:
		# Tentacles: clear while sunk (below the green).
		return a.lerp(b, Me.swing(t, period, phase)).y < -0.3 if a.y != b.y else true


static func asteroid_mesh(r: float) -> ArrayMesh:
	var mb := MeshKit.Builder.new()
	var rock := Color(0.55, 0.48, 0.42)
	mb.sphere(r, MeshKit.at(Vector3.ZERO, Vector3(1.0, 0.9, 1.05)), rock, 10)
	for k in 6:
		var a := float(k) * 2.1
		var d := Vector3(cos(a), sin(a * 1.7) * 0.6, sin(a)).normalized()
		mb.sphere(r * 0.42, MeshKit.at(d * r * 0.72), rock.darkened(0.12 + 0.05 * (k % 2)), 8)
	mb.sphere(r * 0.18, MeshKit.at(Vector3(0.0, r * 0.95, 0.0)), Color(1.0, 0.5, 0.2), 6, true)
	return mb.build()


# --- Orbit (asteroids circling) -----------------------------------------------------------------

class Orbit extends Gimmick:
	var body: AnimatableBody3D
	var center := Vector3.ZERO
	var radius := 1.0
	var period := 6.0
	var phase := 0.0
	var r := 0.18

	func build() -> void:
		center = g.get("center", Vector3.ZERO)
		radius = float(g.get("radius", 1.0))
		period = float(g.get("period", 6.0))
		phase = float(g.get("phase", 0.0))
		r = float(g.get("r", 0.18))
		body = Me.mover_body(self)
		add_child(body)
		var rr := r
		var am := Me.cached("asteroid_%.2f" % rr, func() -> Resource: return Me.asteroid_mesh(rr))
		body.add_child(MeshKit.instance(am))
		body.add_child(Me.sphere_shape(r))
		# a faint orbit ring painted on the floor
		var ring := Me.cached("orbit_ring_%.2f" % radius, func() -> Resource:
			var mb := MeshKit.Builder.new()
			mb.torus(radius, 0.012, MeshKit.at(Vector3(0.0, 0.004, 0.0), Vector3(1.0, 0.1, 1.0)), Color(0.4, 0.7, 1.0), 32, 4, true)
			return mb.build())
		var ri := MeshKit.instance(ring, false)
		ri.position = Vector3(center.x, 0.0, center.z)
		add_child(ri)

	func ang(t: float) -> float:
		return TAU * (t / period + phase)

	func update(t: float) -> void:
		cur_t = t
		var a := ang(t)
		body.position = center + Vector3(cos(a), 0.0, sin(a)) * radius + Vector3.UP * r * 0.85
		body.rotation = Vector3(t * 0.9, t * 0.5, 0.0)

	func velocity_at(_p: Vector3) -> Vector3:
		var a := ang(cur_t)
		var w := TAU / period
		return global_basis * (Vector3(-sin(a), 0.0, cos(a)) * radius * w)

	func influence(p: Vector3) -> bool:
		return p.distance_to(to_global(center)) < radius + r + 0.4


# --- Spinner -------------------------------------------------------------------------------------

class Spinner extends Gimmick:
	var body: AnimatableBody3D
	var speed := 0.9
	var arm := 1.0

	func build() -> void:
		position = g.get("at", Vector3.ZERO)
		speed = float(g.get("speed", 0.9))
		arm = float(g.get("len", 1.0))
		var arms := int(g.get("arms", 2))
		body = Me.mover_body(self)
		add_child(body)
		var ln := arm
		var sp := theme == "space"
		var mesh := Me.cached("spinner_%s_%.2f_%d" % [theme, ln, arms], func() -> Resource:
			var mb := MeshKit.Builder.new()
			mb.cylinder(0.12, 0.14, 0.3, MeshKit.at(Vector3(0.0, 0.15, 0.0)), Color(0.4, 0.45, 0.55) if sp else Color(0.5, 0.33, 0.2), 12)
			mb.sphere(0.08, MeshKit.at(Vector3(0.0, 0.32, 0.0)), Color(1.0, 0.3, 0.3), 10, sp)
			for k in arms:
				var a := PI * float(k) / arms
				var d := Vector3(cos(a), 0.0, sin(a))
				mb.box(Vector3(ln * 2.0, 0.09, 0.06), Transform3D(Basis(Vector3.UP, -a), Vector3(0.0, 0.08, 0.0)), Color(0.75, 0.8, 0.9) if sp else Color(0.65, 0.45, 0.28))
				mb.box(Vector3(ln * 1.96, 0.025, 0.065), Transform3D(Basis(Vector3.UP, -a), Vector3(0.0, 0.11, 0.0)), Color(0.3, 0.9, 1.0) if sp else Color(0.9, 0.75, 0.3), sp)
				var _u := d
			return mb.build())
		body.add_child(MeshKit.instance(mesh))
		body.add_child(Me.cyl_shape(0.13, 0.3, Transform3D(Basis(), Vector3(0.0, 0.15, 0.0))))
		for k in arms:
			var a := PI * float(k) / arms
			body.add_child(Me.box_shape(Vector3(arm * 2.0, 0.12, 0.07), Transform3D(Basis(Vector3.UP, -a), Vector3(0.0, 0.07, 0.0))))

	func update(t: float) -> void:
		body.rotation.y = speed * t + float(g.get("phase", 0.0))

	func velocity_at(p: Vector3) -> Vector3:
		return (Vector3.UP * speed).cross(p - body.global_position)

	func influence(p: Vector3) -> bool:
		return p.distance_to(body.global_position) < arm + 0.3


# --- Loop-the-loop ---------------------------------------------------------------------------------

class Loop extends Gimmick:
	## Hole-local path: a straight run-in, a circle that drifts sideways by `shift`, a run-out.
	var r := 0.3
	var radius := 0.26  # of the ball centre's path
	var shift := 0.26
	var len_in := 0.35
	var len_out := 0.35
	var fwd := Vector3.FORWARD
	var right := Vector3.RIGHT
	var start := Vector3.ZERO

	func build() -> void:
		start = g.get("at", Vector3.ZERO)
		var yaw := float(g.get("yaw", 0.0))
		fwd = Basis(Vector3.UP, yaw) * Vector3.FORWARD
		right = Basis(Vector3.UP, yaw) * Vector3.RIGHT
		r = float(g.get("r", 0.3))
		radius = r - Defs.BALL_R
		shift = float(g.get("shift", 0.26))
		len_in = float(g.get("in", 0.35))
		len_out = float(g.get("out", 0.35))
		var b := MeshKit.Builder.new()
		var steps := 28
		var metal := Color(0.75, 0.8, 0.88)
		var glow := Color(0.3, 0.95, 1.0) if space() else Color(1.0, 0.75, 0.3)
		for i in steps:
			var s0 := len_in + TAU * radius * float(i) / steps
			var s1 := len_in + TAU * radius * float(i + 1) / steps
			var p0 := point(s0) - start
			var p1 := point(s1) - start
			var n0 := inward(s0)
			# track bed (outside the ball) + two side rims
			var bed0 := p0 - n0 * (Defs.BALL_R + 0.015)
			var bed1 := p1 - inward(s1) * (Defs.BALL_R + 0.015)
			b.tube(bed0, bed1, 0.018, 0.018, metal, 6)
			for sd in [-1.0, 1.0]:
				var o: Vector3 = right * float(sd) * 0.065
				b.tube(bed0 + o + n0 * 0.03, bed1 + o + inward(s1) * 0.03, 0.011, 0.011, glow, 5, space())
		for leg in [-1.0, 1.0]:
			var base := fwd * (len_in + 0.0) + right * (shift * 0.5 + float(leg) * 0.32)
			b.tube(base, base + Vector3.UP * (r * 2.0 + 0.1) - right * float(leg) * 0.2, 0.02, 0.02, metal.darkened(0.2), 6)
		var mi := MeshKit.instance(b.build())
		mi.position = start
		add_child(mi)

	func total() -> float:
		return len_in + TAU * radius + len_out

	## Hole-local position of the ball centre at path distance s.
	func point(s: float) -> Vector3:
		var base := start + Vector3.UP * Defs.BALL_R
		if s <= len_in:
			return base + fwd * s
		var circ := TAU * radius
		if s >= len_in + circ:
			return base + fwd * (len_in + (s - len_in - circ)) + right * shift
		var phi := (s - len_in) / radius
		var c := base + fwd * len_in + Vector3.UP * radius
		return c + fwd * radius * sin(phi) - Vector3.UP * radius * cos(phi) + right * shift * (phi / TAU)

	## Unit direction of travel at s (hole-local).
	func tangent(s: float) -> Vector3:
		if s <= len_in or s >= len_in + TAU * radius:
			return fwd
		var phi := (s - len_in) / radius
		return (fwd * cos(phi) + Vector3.UP * sin(phi) + right * shift / (TAU * radius)).normalized()

	## Towards the loop centre (the way the track pushes).
	func inward(s: float) -> Vector3:
		if s <= len_in or s >= len_in + TAU * radius:
			return Vector3.UP
		var phi := (s - len_in) / radius
		return -fwd * sin(phi) + Vector3.UP * cos(phi)

	## Does the track hold a ball moving at speed v at s? (False near the top when too slow.)
	func holds(s: float, v: float) -> bool:
		if s <= len_in or s >= len_in + TAU * radius:
			return true
		var phi := (s - len_in) / radius
		var c := cos(phi)
		return c >= 0.0 or v * v / radius >= -Defs.GRAVITY * c * 0.92


# --- Portals -------------------------------------------------------------------------------------

class Portal extends Gimmick:
	var spin: Array[Node3D] = []

	func build() -> void:
		var a: Vector3 = g.get("a", Vector3.ZERO)
		var b: Vector3 = g.get("b", Vector3.ZERO)
		var ends: Array = [[a, float(g.get("a_yaw", 0.0)), Color(1.0, 0.55, 0.15)], [b, float(g.get("b_yaw", 0.0)), Color(0.3, 0.7, 1.0)]]
		for e in ends:
			var arr: Array = e
			var p: Vector3 = arr[0]
			var col: Color = arr[2]
			var key := "portal_%s" % col.to_html(false)
			var mesh := Me.cached(key, func() -> Resource:
				var mb := MeshKit.Builder.new()
				mb.torus(0.26, 0.04, MeshKit.at(Vector3(0.0, 0.0, 0.0)), col, 20, 6, true)
				mb.torus(0.2, 0.012, MeshKit.at(Vector3(0.0, 0.005, 0.0)), col.lightened(0.4), 20, 4, true)
				mb.disc(0.2, MeshKit.at(Vector3(0.0, 0.002, 0.0)), Color(0.05, 0.03, 0.12), 20)
				return mb.build())
			var n := Node3D.new()
			n.position = p + Vector3.UP * 0.01
			add_child(n)
			n.add_child(MeshKit.instance(mesh, false))
			var swirl := Me.cached("portal_swirl_%s" % col.to_html(false), func() -> Resource:
				var mb := MeshKit.Builder.new()
				for k in 3:
					var a0 := TAU * float(k) / 3.0
					mb.box(Vector3(0.16, 0.004, 0.025), Transform3D(Basis(Vector3.UP, a0), Vector3(cos(a0), 0.0, -sin(a0)) * 0.08), col.lightened(0.3), true)
				return mb.build())
			var sw := MeshKit.instance(swirl, false)
			sw.position.y = 0.008
			n.add_child(sw)
			spin.append(sw)
			var arrow := Me.cached("portal_arrow_%s" % col.to_html(false), func() -> Resource:
				var mb := MeshKit.Builder.new()
				mb.polygon(PackedVector2Array([Vector2(-0.08, 0.0), Vector2(0.0, 0.1), Vector2(0.08, 0.0), Vector2(0.03, 0.0), Vector2(0.03, -0.08), Vector2(-0.03, -0.08), Vector2(-0.03, 0.0)]), 0.004,
					MeshKit.at(Vector3(0.0, 0.006, -0.36), Vector3.ONE, Vector3(-PI * 0.5, 0.0, 0.0)), col, true)
				return mb.build())
			var ar := MeshKit.instance(arrow, false)
			ar.rotation.y = float(arr[1])
			n.add_child(ar)

	func update(t: float) -> void:
		for s in spin:
			s.rotation.y = t * 2.5


# =================================================================================================

## A party-mode "?" box: spins and bobs; hidden once taken.
class PowerBox extends Node3D:
	var taken := false
	var box: Node3D

	func _ready() -> void:
		box = Node3D.new()
		add_child(box)
		var mesh := Me.cached("powerbox", func() -> Resource:
			var mb := MeshKit.Builder.new()
			mb.rounded_box(Vector3(0.16, 0.16, 0.16), 0.035, MeshKit.at(Vector3.ZERO), Color(1.0, 0.78, 0.2))
			for k in 4:
				var a := PI * 0.5 * float(k)
				mb.box(Vector3(0.17, 0.035, 0.03), Transform3D(Basis(Vector3.UP, a), Vector3(0.0, 0.0, 0.0)) * MeshKit.at(Vector3(0.0, 0.0, 0.07)), Color(1.0, 0.45, 0.85), true)
			return mb.build())
		box.add_child(MeshKit.instance(mesh, false))
		for k in 2:
			var l := UiKit.label3d("?", 0.09, Color(0.25, 0.12, 0.02), true)
			l.no_depth_test = false
			l.outline_size = 6
			l.outline_modulate = Color(1.0, 1.0, 1.0, 0.9)
			l.position = Vector3(0.0, 0.0, 0.082 if k == 0 else -0.082)
			l.rotation.y = 0.0 if k == 0 else PI
			box.add_child(l)

	func _process(delta: float) -> void:
		if box == null:
			return
		box.rotation.y += delta * 1.8
		box.position.y = 0.17 + sin(Time.get_ticks_msec() * 0.003 + position.x) * 0.03

	func take() -> void:
		if taken:
			return
		taken = true
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector3.ONE * 1.6, 0.1)
		tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.18)
		tw.tween_callback(func() -> void: visible = false)

