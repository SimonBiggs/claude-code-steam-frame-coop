extends Node3D
## KITCHEN EVENTS (second pass, nights.gd): OVEN SMOKE puffs out in front of the stove and SPILLS splash on the floor.
## Each is told first: Nights.WARN_SECS early warning rings pulse on the floor where it will be (core/warn_rings.gd,
## every machine), Gran shows a picture card, then for Nights.EVENT_SECS the smoke cloud / puddle is there and runners
## inside it move at Nights.SLOW speed (SKATES glide over spills). The host runs the clock (the round's seconds,
## events from round_info) and sends "kev" [kind, x, z, r]; every machine draws and slows its own runners.
##   host: events.reset(list); events.tick(round_t) -> the events that start warning now
##   every machine: events.announce(kind, x, z, r); events.slow_at(pos, skates) -> speed factor

const Nights := preload("res://games/kitchen_rush/nights.gd")
const WarnRings := preload("res://core/warn_rings.gd")
const UiKit := preload("res://core/ui_kit.gd")

var main: Node
var rings: WarnRings
var events: Array = []  # host: this round's [t, kind, x, z, r]
var warned := {}  # host: index -> true
var fired := 0  # host: events warned this round (telemetry)
var zones: Array = []  # every machine: [{kind, c: Vector2, r, t (s until it starts), left, node}]
var _smoke_mat: StandardMaterial3D
var _spill_mat: StandardMaterial3D


func _ready() -> void:
	name = "KitchenEvents"
	rings = WarnRings.new()
	add_child(rings)
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_mat.albedo_color = Color(0.82, 0.82, 0.86, 0.55)
	_smoke_mat.render_priority = UiKit.VR_PRIO_UNDER_UI  # see-through smoke never washes out a VR card
	_spill_mat = StandardMaterial3D.new()
	_spill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spill_mat.albedo_color = Color(0.45, 0.75, 1.0, 0.7)
	_spill_mat.metallic_specular = 1.0
	_spill_mat.roughness = 0.05
	_spill_mat.render_priority = UiKit.VR_PRIO_UNDER_UI


## Host: a new round's events.
func reset(list: Array) -> void:
	events = list.duplicate(true)
	warned = {}
	fired = 0


## Host: start the warning for any event WARN_SECS away. Returns the events that start warning now.
func tick(round_t: float) -> Array:
	var out: Array = []
	for i in events.size():
		var e: Array = events[i]
		if not warned.has(i) and round_t >= float(e[0]) - Nights.WARN_SECS and round_t < float(e[0]) + Nights.EVENT_SECS:
			warned[i] = true
			fired += 1
			out.append(e)
	return out


## Every machine: rings now, the smoke / puddle after the warning.
func announce(kind: String, x: float, z: float, r: float) -> void:
	var col: Color = Nights.EVENT_COLORS.get(kind, Color.WHITE)
	rings.warn(Vector3(x, 0.0, z), r, col, Nights.WARN_SECS, 0.04)
	zones.append({"kind": kind, "c": Vector2(x, z), "r": r, "t": Nights.WARN_SECS, "left": Nights.EVENT_SECS, "node": null})
	main.sfx_local("spit" if kind == "smoke" else "wave", -6.0, 0.6 if kind == "smoke" else 1.5)


## Every machine: all gone (a new round, the practice).
func clear() -> void:
	rings.clear()
	for z in zones:
		if z.node != null and is_instance_valid(z.node):
			z.node.queue_free()
	zones.clear()


## How fast a runner at pos may move (1 = normal). Skates glide over spills (smoke still slows).
func slow_at(pos: Vector3, skates: bool) -> float:
	for z in zones:
		if float(z.t) > 0.0:
			continue
		if skates and String(z.kind) == "spill":
			continue
		if Vector2(pos.x, pos.z).distance_to(z.c) < float(z.r):
			return Nights.SLOW
	return 1.0


## Is a zone on (for bots / the cue)?
func active_kinds() -> Array:
	var out: Array = []
	for z in zones:
		if float(z.t) <= 0.0:
			out.append(String(z.kind))
	return out


func _process(delta: float) -> void:
	for i in range(zones.size() - 1, -1, -1):
		var z: Dictionary = zones[i]
		if float(z.t) > 0.0:
			z.t = float(z.t) - delta
			if float(z.t) <= 0.0:
				z.node = _make(String(z.kind), z.c, float(z.r))
				add_child(z.node)
				main.sfx_local("hit" if z.kind == "smoke" else "pickup", -4.0, 0.5 if z.kind == "smoke" else 0.7)
			continue
		z.left = float(z.left) - delta
		var n: Node3D = z.node
		if n != null and is_instance_valid(n):
			var grow := clampf((Nights.EVENT_SECS - float(z.left)) / 0.5, 0.05, 1.0) * clampf(float(z.left) / 0.8, 0.05, 1.0)
			n.scale = Vector3(grow, 1.0 if z.kind == "spill" else grow, grow)
			if z.kind == "smoke":
				for j in n.get_child_count():
					var puff := n.get_child(j) as Node3D
					puff.position.y = 0.6 + 0.35 * sin(Time.get_ticks_msec() * 0.0015 + j * 1.7)
					puff.rotation.y += delta * (0.3 + 0.1 * j)
		if float(z.left) <= 0.0:
			if n != null and is_instance_valid(n):
				n.queue_free()
			zones.remove_at(i)


func _make(kind: String, c: Vector2, r: float) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(c.x, 0.0, c.y)
	if kind == "smoke":
		# Soft grey puffs filling the circle (knee to head height: runners walk through it slowly).
		for j in 7:
			var a := TAU * j / 7.0
			var rr := 0.0 if j == 0 else r * 0.55
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = r * (0.6 if j == 0 else 0.45)
			sm.height = sm.radius * 1.5
			sm.radial_segments = 12
			sm.rings = 6
			mi.mesh = sm
			mi.material_override = _smoke_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(cos(a) * rr, 0.6, sin(a) * rr)
			root.add_child(mi)
	else:
		# A shiny puddle (a squashed blob) with a tipped-over bucket at its edge.
		for j in 4:
			var mi2 := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			var pr := r * (1.0 if j == 0 else 0.45)
			cm.top_radius = pr
			cm.bottom_radius = pr
			cm.height = 0.012
			cm.radial_segments = 24
			cm.rings = 1
			mi2.mesh = cm
			mi2.material_override = _spill_mat
			mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var a2 := TAU * j / 3.0
			mi2.position = Vector3(0.0, 0.012, 0.0) if j == 0 else Vector3(cos(a2) * r * 0.7, 0.014, sin(a2) * r * 0.7)
			root.add_child(mi2)
		var bucket := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.2
		bm.bottom_radius = 0.15
		bm.height = 0.35
		bucket.mesh = bm
		bucket.material_override = main.mat(Color(0.95, 0.75, 0.2))
		bucket.position = Vector3(r * 0.9, 0.17, 0.0)
		bucket.rotation.z = PI / 2.0
		root.add_child(bucket)
	return root
