extends Node3D
## GIANT'S TABLE goblin TRICKS (deep.gd tricks()). Every machine draws the trick in the "hz" state (the host sets it
## when its tell starts and clears it when it is over), steady from the tell until it is over:
##   GOO     a pink circle on the table (core/warn_rings.gd) and a little goblin catapult on the rim aiming at it;
##           as the tell ends the goo ball arcs over and splats in the circle. Knights inside get a bump, goblins in the
##           goo get stuck. The Giant can CATCH the ball (in the catapult or in the air): no splat, a cheer.
##   BARREL  an orange band across the table (in short pieces that follow the hills) with a barrel waiting on the rim;
##           when the tell is over it rolls along the band. Knights in its way get a bump, goblins get bowled over
##           dizzy. The Giant can GRAB the barrel: it stops, a cheer.
## Nothing flashes: the shapes glow steadily in their own colours (deep.gd GOO_COLOR / BARREL_COLOR), never the gold
## of a pick. See-through parts draw under the VR cards (UiKit.VR_PRIO_UNDER_UI). Host: the ball and the barrel are
## grabbable (group "tricks": giant.gd _try_grab), the host plays the bumps; "hz_caught" tells every machine.
##   show_now(hz) / set_caught(on) on every state change; host_begin(list), host_tick(wave_t), host_end(); tells_now()

const WarnRings := preload("res://core/warn_rings.gd")
const UiKit := preload("res://core/ui_kit.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Deep := preload("res://games/giants_table/deep.gd")
const W := preload("res://games/giants_table/world.gd")

const STAY := 600.0  # (the tell stays until the host clears it)
const SEG := 2.2  # a barrel band piece's length (each at its own ground height)

var main
var rings: WarnRings
var key := ""
var now := {}
var age := 0.0  # seconds since this trick's tell began here
var caught := false
var thing: Node3D  # the goo ball or the barrel
var stand: Node3D  # the catapult
var puddle: Node3D
var seen := {}  # kind -> tells drawn (bots)
# Host
var list: Array = []
var next_i := 0
var cur := {}
var fired := false
var hit := {}  # knights / goblins this trick already bumped
var count := 0  # tricks this wave (telemetry)
var catches := 0  # tricks the Giant caught this wave (telemetry)
var bumps := 0  # knights bumped this wave (telemetry)


func _ready() -> void:
	name = "Hazards"
	rings = WarnRings.new()
	add_child(rings)


# --- Every machine --------------------------------------------------------------------------------------------

## The trick showing now ({} none).
func show_now(hz: Dictionary) -> void:
	var k := str(Deep.pack(hz))
	if k == key:
		return
	key = k
	clear()
	now = hz
	age = 0.0
	caught = false
	if hz.is_empty():
		return
	seen[String(hz.kind)] = int(seen.get(String(hz.kind), 0)) + 1
	var col := color_of(String(hz.kind))
	var at := Vector3(float(hz.x), 0.0, float(hz.z))
	match String(hz.kind):
		"goo":
			rings.shape("circle", at, Vector3.FORWARD, Vector2(float(hz.r), 0.0), col, 0.3,
				{"style": "disc", "stay": STAY, "alpha": 0.45, "y": _top(at, float(hz.r)) + 0.06, "hot": col})
			stand = _catapult()
			add_child(stand)
			var cp := Vector3(float(hz.cx), 0.0, float(hz.cz))
			stand.position = cp
			UiKit.look(stand, Vector3(at.x, 0.0, at.z), Vector3.UP)
			thing = _ball()
			add_child(thing)
			thing.position = Deep.goo_at(hz, 0.0)
			main.sound("boing", -6.0, 0.6, false)
		"barrel":
			var dir := Vector3(float(hz.dx), 0.0, float(hz.dz)).normalized()
			var half := Deep.barrel_half(hz)
			var n := maxi(1, ceili(half * 2.0 / SEG))
			for i in n:  # pieces that follow the hills (a flat band would hide under them)
				var a := -half + i * half * 2.0 / n
				var p := at + dir * a
				var mid := at + dir * (a + half / n)
				rings.shape("line", p, dir, Vector2(half * 2.0 / n + 0.05, float(hz.r) * 2.0), col, 0.3,
					{"style": "disc", "stay": STAY, "alpha": 0.42, "y": maxf(_top(p, 0.6), _top(mid, 0.6)) + 0.06, "hot": col})
			thing = _barrel()
			add_child(thing)
			thing.position = _on_ground(Deep.barrel_at(hz, 0.0)) + Vector3.UP * Deep.BARREL_R
			UiKit.look(thing, thing.position + dir, Vector3.UP)
			main.sound("rustle", -4.0, 0.6, false)
	if main.net.mode != "client" and thing != null:
		thing.add_to_group("tricks")  # (host: the Giant can grab it)


func clear() -> void:
	rings.clear()
	for n in [thing, stand, puddle]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	thing = null
	stand = null
	puddle = null
	now = {}


## Every machine: the Giant caught this trick's ball / barrel.
func set_caught(on: bool) -> void:
	if on == caught:
		return
	caught = on
	if on and thing != null and is_instance_valid(thing):
		main.burst(thing.global_position, color_of(String(now.get("kind", "goo"))), 24, 0.25, false)
		main.sound("cheer", -6.0, 1.2, false)
		thing.queue_free()
		thing = null
		rings.clear()


## Bots: the trick showing now: [{kind, x, z, ...}].
func tells_now() -> Array:
	return [] if now.is_empty() else [now.duplicate()]


## Where the ball / barrel is now (Vector3.INF: none).
func thing_pos() -> Vector3:
	return thing.global_position if thing != null and is_instance_valid(thing) and thing.is_inside_tree() else Vector3.INF


func _process(delta: float) -> void:
	if now.is_empty():
		return
	age += delta
	var since := age - float(now.warn)
	if thing != null and is_instance_valid(thing) and not thing.get_meta("held", false):
		if String(now.kind) == "goo":
			var fly := age - (float(now.warn) - Deep.GOO_FLY)
			thing.position = Deep.goo_at(now, maxf(0.0, fly))
			thing.scale = Vector3.ONE * (1.0 + 0.12 * sin(age * 9.0))
			if since >= 0.0:
				_splat()
		else:
			var p := _on_ground(Deep.barrel_at(now, maxf(0.0, since)))
			thing.position = p + Vector3.UP * (Deep.BARREL_R + absf(sin(maxf(0.0, since) * 6.0)) * 0.25 * float(since > 0.0))
			var roll := thing.get_node_or_null("Roll") as Node3D
			if roll != null and since > 0.0:
				roll.rotation.x -= delta * Deep.BARREL_SPEED / Deep.BARREL_R
			thing.visible = since < Deep.barrel_secs(now) + 0.1
	if stand != null and is_instance_valid(stand):
		var arm := stand.get_node_or_null("Arm") as Node3D
		if arm != null:
			arm.rotation.x = -1.2 if age >= float(now.warn) - Deep.GOO_FLY else lerpf(0.0, 0.25, minf(1.0, age))


## The goo ball lands: a pink puddle in the circle (every machine draws its own).
func _splat() -> void:
	var at := Vector3(float(now.x), 0.0, float(now.z))
	main.burst(_on_ground(at) + Vector3.UP * 0.4, Deep.GOO_COLOR, 26, 0.3, false)
	main.sound("splash", -2.0, 0.6, false)
	if thing != null and is_instance_valid(thing):
		thing.queue_free()
	thing = null
	puddle = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = float(now.r) * 0.8
	cm.bottom_radius = float(now.r) * 0.85
	cm.height = 0.08
	cm.radial_segments = 20
	(puddle as MeshInstance3D).mesh = cm
	(puddle as MeshInstance3D).material_override = _mat(Deep.GOO_COLOR.darkened(0.1), 1.0, false)
	(puddle as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(puddle)
	puddle.position = Vector3(at.x, _top(at, float(now.r)) + 0.03, at.z)


# --- Host -----------------------------------------------------------------------------------------------------

## Host: this wave's tricks.
func host_begin(new_list: Array) -> void:
	list = new_list
	next_i = 0
	cur = {}
	count = 0
	catches = 0
	bumps = 0
	main.net.state_set("hz", [])
	main.net.state_set("hz_caught", false)


## Host, every frame of a wave: tell the next trick, play it, clear it.
func host_tick(wave_t: float) -> void:
	if cur.is_empty():
		if next_i < list.size() and wave_t >= float((list[next_i] as Dictionary).t):
			cur = list[next_i]
			next_i += 1
			fired = false
			hit = {}
			count += 1
			main.net.state_set("hz_caught", false)
			main.net.state_set("hz", Deep.pack(cur))
			main.trick_told(cur)
		return
	var since := wave_t - float(cur.t)
	var bump := float(Deep.mode_data(main.mode).bump)
	if not bool(main.net.state_get("hz_caught", false)):
		if String(cur.kind) == "goo":
			if since >= float(cur.warn) and not fired:
				fired = true
				var c := Vector2(float(cur.x), float(cur.z))
				for k in main.knights():
					if k.active and not k.is_down and not k.carried and Vector2(k.global_position.x, k.global_position.z).distance_to(c) < float(cur.r) + Deep.KNIGHT_R:
						_bump_knight(k, bump, Vector3(c.x, 0.0, c.y))
			if fired:  # goblins in the goo are stuck while it lasts
				for g in get_tree().get_nodes_in_group("goblins"):
					if g.held or g.flying or g.floating or g.has_meta("dead"):
						continue
					if Deep.inside(cur, Vector2(g.global_position.x, g.global_position.z)):
						if not hit.has(g):
							hit[g] = true
							g.dizzy_t = maxf(g.dizzy_t, Deep.GOO_DIZZY)
						g.dizzy_t = maxf(g.dizzy_t, 0.4)
		elif since >= float(cur.warn):
			var s := since - float(cur.warn)
			if s <= Deep.barrel_secs(cur):
				var bp := Deep.barrel_at(cur, s)
				var dir := Vector2(float(cur.dx), float(cur.dz)).normalized()
				for k in main.knights():
					if k.active and not k.is_down and not k.carried and not hit.has(k) and _barrel_hits(bp, dir, k.global_position, Deep.KNIGHT_R):
						hit[k] = true
						_bump_knight(k, bump, bp)
				for g in get_tree().get_nodes_in_group("goblins"):
					if g.held or g.flying or g.floating or g.has_meta("dead") or hit.has(g):
						continue
					if _barrel_hits(bp, dir, g.global_position, g.radius):
						hit[g] = true
						g.dizzy_t = maxf(g.dizzy_t, Deep.BARREL_DIZZY)
						main.burst(g.grab_center(), Deep.BARREL_COLOR, 10, 0.15)
						main.sound("boing", -4.0, 0.8)
	if since >= Deep.span(cur):
		cur = {}
		main.net.state_set("hz", [])


## Host: the wave is over (or lost): no trick.
func host_end() -> void:
	list = []
	next_i = 0
	cur = {}
	main.net.state_set("hz", [])


## Host: the Giant grabbed the ball / barrel.
func host_caught() -> void:
	if cur.is_empty() or bool(main.net.state_get("hz_caught", false)):
		return
	catches += 1
	main.net.state_set("hz_caught", true)
	main.trick_caught(cur)


func _barrel_hits(bp: Vector3, dir: Vector2, p: Vector3, r: float) -> bool:
	var q := Vector2(p.x - bp.x, p.z - bp.z)
	var along := absf(q.dot(dir))
	var across := absf(q.x * -dir.y + q.y * dir.x)
	return along < Deep.BARREL_R + r and across < float(cur.r) + r


func _bump_knight(k, bump: float, from: Vector3) -> void:
	bumps += 1
	main.burst(k.global_position + Vector3.UP * 0.6, color_of(String(cur.kind)), 10, 0.15)
	if bump > 0.0:
		main.knight_hurt(k, bump, from)
	else:
		main.sound("boing", -4.0, 1.3)  # GENTLE: just a boing


# --- Looks ----------------------------------------------------------------------------------------------------

## The highest ground within r of p (so a flat tell never hides under a hill).
func _top(p: Vector3, r: float) -> float:
	var top := maxf(W.height(p.x, p.z), -0.3)
	for i in 8:
		var a := i * TAU / 8.0
		for k in [0.5, 1.0]:
			var q: Vector3 = p + Vector3(cos(a), 0.0, sin(a)) * r * k
			var h := W.height(q.x, q.z)
			if h > -50.0:
				top = maxf(top, h)
	return top


func _on_ground(p: Vector3) -> Vector3:
	var h := W.height(p.x, p.z)
	return Vector3(p.x, maxf(h, 0.0) if h > -50.0 else 0.0, p.z)


## A pink goo ball with two googly eyes (grabbable on the host).
func _ball() -> Node3D:
	var n := GrabThing.new()
	n.name = "GooBall"
	n.hazards = self
	n.radius = 0.6
	var b := MeshKit.Builder.new()
	b.sphere(0.6, MeshKit.at(Vector3.ZERO), Deep.GOO_COLOR, 12)
	b.sphere(0.22, MeshKit.at(Vector3(0.25, 0.3, 0.3)), Deep.GOO_COLOR.lightened(0.4), 8)
	for s in [-1.0, 1.0]:
		b.sphere(0.16, MeshKit.at(Vector3(0.2 * s, 0.15, 0.5)), Color(1, 1, 1), 8)
		b.sphere(0.08, MeshKit.at(Vector3(0.2 * s, 0.15, 0.63)), Color(0.1, 0.05, 0.1), 6)
	n.add_child(MeshKit.instance(b.build(), false))
	return n


## A wooden barrel lying on its side (rolls along +Z), grabbable on the host.
func _barrel() -> Node3D:
	var n := GrabThing.new()
	n.name = "Barrel"
	n.hazards = self
	n.radius = Deep.BARREL_R
	var roll := Node3D.new()
	roll.name = "Roll"
	n.add_child(roll)
	var b := MeshKit.Builder.new()
	var len := 1.5
	var side := MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(0, 0, PI * 0.5))  # its axis across the roll
	b.cylinder(Deep.BARREL_R * 0.9, Deep.BARREL_R * 0.9, len, side, Color(0.72, 0.45, 0.22), 14)
	b.cylinder(Deep.BARREL_R, Deep.BARREL_R, len * 0.5, side, Color(0.78, 0.5, 0.25), 14)
	for x in [-0.55, 0.0, 0.55]:
		b.cylinder(Deep.BARREL_R * 1.02, Deep.BARREL_R * 1.02, 0.08, MeshKit.at(Vector3(x, 0, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5)),
			Color(0.3, 0.3, 0.35), 14)
	b.box(Vector3(len + 0.04, 0.12, 0.12), MeshKit.at(Vector3(0, Deep.BARREL_R * 0.75, 0)), Deep.BARREL_COLOR)  # an orange stripe: it reads as the band's
	roll.add_child(MeshKit.instance(b.build(), false))
	return n


## A little goblin catapult (an arm that flings, on a wooden frame), facing +Z towards the circle.
func _catapult() -> Node3D:
	var n := Node3D.new()
	n.name = "Catapult"
	var b := MeshKit.Builder.new()
	var wood := Color(0.55, 0.34, 0.16)
	b.box(Vector3(1.4, 0.2, 1.8), MeshKit.at(Vector3(0, 0.25, 0)), wood)
	for s in [-1.0, 1.0]:
		b.box(Vector3(0.15, 1.1, 0.15), MeshKit.at(Vector3(0.55 * s, 0.85, -0.2)), wood.darkened(0.15))
		b.cylinder(0.28, 0.28, 0.12, MeshKit.at(Vector3(0.75 * s, 0.28, 0.6), Vector3.ONE, Vector3(0, 0, PI * 0.5)), wood.darkened(0.3), 10)
		b.cylinder(0.28, 0.28, 0.12, MeshKit.at(Vector3(0.75 * s, 0.28, -0.6), Vector3.ONE, Vector3(0, 0, PI * 0.5)), wood.darkened(0.3), 10)
	n.add_child(MeshKit.instance(b.build(), false))
	var arm := Node3D.new()
	arm.name = "Arm"
	arm.position = Vector3(0, 1.3, -0.2)
	var ab := MeshKit.Builder.new()
	ab.box(Vector3(0.14, 0.14, 1.6), MeshKit.at(Vector3(0, 0, 0.6)), wood.lightened(0.1))
	ab.cylinder(0.3, 0.2, 0.2, MeshKit.at(Vector3(0, 0.1, 1.35)), wood, 10)
	arm.add_child(MeshKit.instance(ab.build(), false))
	n.add_child(arm)
	return n


func _mat(col: Color, alpha: float, see_through: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if see_through and alpha < 1.0:
		UiKit.see_through(m)
	return m


## Bots / palette: the colour of a kind's tell.
static func color_of(kind: String) -> Color:
	return Deep.GOO_COLOR if kind == "goo" else Deep.BARREL_COLOR


## The ball / barrel as the Giant's hands see it (giant.gd _try_grab: grab_center, radius, can_grab, on_grabbed,
## hold_at, on_released). Grabbing it catches the trick (host).
class GrabThing extends Node3D:
	var hazards
	var radius := 0.6

	func grab_center() -> Vector3:
		return global_position

	func can_grab() -> bool:
		return is_inside_tree() and visible

	func on_grabbed() -> void:
		set_meta("held", true)
		if hazards != null:
			hazards.host_caught()

	func hold_at(p: Vector3, _yaw: float) -> void:
		if is_inside_tree():
			global_position = p

	func on_released(_v: Vector3) -> void:
		queue_free()
