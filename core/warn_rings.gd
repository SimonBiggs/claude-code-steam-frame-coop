extends Node3D
## WARNING RINGS (shared by every game that tells an attack or a hazard on the ground: Duo Arena, Snowball Blitz,
## Elemental Bender, Mech Titans, Dungeon Delve, Crystal Saga ...): a glowing shape on the ground that shows where
## something will land, then goes away (or glows "hot" for `stay` seconds while it goes off). Every machine draws its
## own (the host sends the numbers in an event), so a tell reads the same on the TV, the Decks and in VR.
##   var rings := WarnRings.new(); add_child(rings)
##   rings.warn(pos, radius, colour, secs)                       # pulsing rings that grow in (the classic boss tell)
##   rings.warn(pos, radius, colour, secs, y, {"style": "disc"})  # a see-through disc with a bright edge, pulsing
##   rings.shape("line", from, dir, Vector2(length, width), colour, secs, {"style": "flash", "stay": 0.3})
##   WarnRings.inside(kind, pos, dir, size, point, pad) -> is the point in it (host hit tests, bots)
##   count() -> tells showing now      clear() -> all gone (a new room / round)
##   tells() -> [{kind, pos, dir, size, t, secs, stay}] the tells showing now (bots read them to dodge)
## Shapes: "circle" (size.x = radius), "ring" (a shockwave band: it grows to size.x while it goes off), "line"
## (size.x = length from pos along dir, size.y = width), "sector" (size.x = radius, size.y = half angle, radians).
## Styles (a game keeps its own look through these, never its own ring code: tests/shared_picks_test.gd):
##   "rings" (circle only) three rings that grow in and throb      "disc" a filled shape (+ an edge ring) that pulses
##   "flash" a filled shape that flashes faster and faster, then turns `hot` for `stay` seconds
## Options: style, stay (s after secs, default 0), hot (Color while it goes off), alpha (fill, default 0.35 disc /
## 0.45 flash), grow (s to grow in; rings 0.3), y (shape(): ground height, default 0.08).

const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const UiKit := preload("res://core/ui_kit.gd")

const KINDS: Array[String] = ["circle", "ring", "line", "sector"]
const STYLES: Array[String] = ["rings", "disc", "flash"]

var _warns: Array[Dictionary] = []  # {node, t, secs, stay, style, kind, pos, dir, size, grow, hot, edge}


func _ready() -> void:
	if name.is_empty() or name.begins_with("@"):
		name = "WarnRings"


static func ring_mesh() -> ArrayMesh:
	return ResCache.get_or_make("warn_ring_v1", func() -> Resource:
		var b := MeshKit.builder()
		b.torus(1.0, 0.07, MeshKit.at(Vector3.ZERO), Color.WHITE, 40, 4)
		b.torus(0.6, 0.04, MeshKit.at(Vector3.ZERO), Color.WHITE, 28, 4)
		b.torus(0.25, 0.03, MeshKit.at(Vector3.ZERO), Color.WHITE, 16, 4)
		return b.build()) as ArrayMesh


## Flat unit shapes for the filled styles (circle: radius 1; ring: band 0.82..1; line: z 0..1, width 1; sector:
## +-1 radian round +Z, radius 1; edge: a thin ring at radius 1).
static func flat_mesh(kind: String) -> Mesh:
	return ResCache.get_or_make("warn_flat_%s_v1" % kind, func() -> Resource:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		match kind:
			"circle":
				for i in 32:
					var a0 := TAU * i / 32.0
					var a1 := TAU * (i + 1) / 32.0
					st.add_vertex(Vector3.ZERO)
					st.add_vertex(Vector3(cos(a1), 0.0, sin(a1)))
					st.add_vertex(Vector3(cos(a0), 0.0, sin(a0)))
			"ring", "edge":
				var inner := 0.82 if kind == "ring" else 0.93
				for i in 40:
					var a0 := TAU * i / 40.0
					var a1 := TAU * (i + 1) / 40.0
					var o0 := Vector3(cos(a0), 0.0, sin(a0))
					var o1 := Vector3(cos(a1), 0.0, sin(a1))
					st.add_vertex(o0 * inner)
					st.add_vertex(o1)
					st.add_vertex(o0)
					st.add_vertex(o0 * inner)
					st.add_vertex(o1 * inner)
					st.add_vertex(o1)
			"line":
				st.add_vertex(Vector3(-0.5, 0.0, 0.0))
				st.add_vertex(Vector3(0.5, 0.0, 1.0))
				st.add_vertex(Vector3(0.5, 0.0, 0.0))
				st.add_vertex(Vector3(-0.5, 0.0, 0.0))
				st.add_vertex(Vector3(-0.5, 0.0, 1.0))
				st.add_vertex(Vector3(0.5, 0.0, 1.0))
			"sector":
				for i in 16:
					var a0 := -1.0 + 2.0 * i / 16.0
					var a1 := -1.0 + 2.0 * (i + 1) / 16.0
					st.add_vertex(Vector3.ZERO)
					st.add_vertex(Vector3(sin(a0), 0.0, cos(a0)))
					st.add_vertex(Vector3(sin(a1), 0.0, cos(a1)))
		st.generate_normals()
		return st.commit())


## A see-through glowing fill (shared per colour: few materials, few draw-call changes).
static func fill_material(col: Color, alpha: float) -> StandardMaterial3D:
	var c := Color(col.r, col.g, col.b, alpha)
	return ResCache.get_or_make("warn_fill_%s_v2" % c.to_html(true), func() -> Resource:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		UiKit.see_through(m)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = c
		return m) as StandardMaterial3D


## Every machine: a round tell at pos (on the ground at ground_y) for secs. Returns its node.
func warn(pos: Vector3, radius: float, col: Color, secs: float, ground_y: float = 0.08, o: Dictionary = {}) -> Node3D:
	var opts := o.duplicate()
	opts["y"] = ground_y
	return shape("circle", pos, Vector3.FORWARD, Vector2(radius, 0.0), col, secs, opts)


## Every machine: a tell of any shape (see the header). Returns its node.
func shape(kind: String, pos: Vector3, dir: Vector3, size: Vector2, col: Color, secs: float, o: Dictionary = {}) -> Node3D:
	if not kind in KINDS:
		push_warning("WarnRings: unknown shape %s (circle)" % kind)
		kind = "circle"
	var style := String(o.get("style", "rings" if kind == "circle" else "flash"))
	if style == "rings" and kind != "circle":
		style = "disc"
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var edge: MeshInstance3D = null
	if style == "rings":
		mi.mesh = ring_mesh()
		mi.material_override = MeshKit.material(col, 3.0)
	else:
		mi.mesh = flat_mesh(kind)
		mi.material_override = fill_material(col, float(o.get("alpha", 0.35 if style == "disc" else 0.45)))
		if style == "disc" and kind == "circle":
			edge = MeshInstance3D.new()
			edge.mesh = flat_mesh("edge")
			edge.material_override = fill_material(col, 0.9)
			edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			edge.position.y = 0.01
			mi.add_child(edge)
	add_child(mi)
	var y := float(o.get("y", 0.08)) + _warns.size() * 0.002  # (stacked tells never z-fight)
	var at := Vector3(pos.x, y, pos.z)
	var yaw := atan2(dir.x, dir.z) if Vector2(dir.x, dir.z).length() > 0.01 else 0.0
	if is_inside_tree():
		mi.global_position = at
	else:
		mi.position = at
	mi.rotation = Vector3(0.0, yaw, 0.0)
	var w := {"node": mi, "t": 0.0, "secs": maxf(secs, 0.2), "stay": float(o.get("stay", 0.0)), "style": style,
		"kind": kind, "pos": pos, "dir": dir, "size": size, "grow": float(o.get("grow", 0.3 if style == "rings" else 0.0)), "edge": edge,
		"hot": fill_material(o.get("hot", col.lightened(0.3)), 0.75) if style != "rings" else null}
	_warns.append(w)
	_shape_scale(w, 1.0)
	return mi


func count() -> int:
	return _warns.size()


## The tells showing now (copies: {kind, pos, dir, size, t, secs, stay}); t < secs = still warning, not gone off.
func tells() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for w in _warns:
		out.append({"kind": w.kind, "pos": w.pos, "dir": w.dir, "size": w.size, "t": w.t, "secs": w.secs, "stay": w.stay})
	return out


func clear() -> void:
	for w in _warns:
		if is_instance_valid(w.node):
			(w.node as Node).queue_free()
	_warns.clear()


## Is point p inside a tell's shape (host: who gets hit; bots: where not to stand)?
static func inside(kind: String, pos: Vector3, dir: Vector3, size: Vector2, p: Vector3, pad: float = 0.0) -> bool:
	var d := Vector2(p.x - pos.x, p.z - pos.z)
	match kind:
		"circle", "ring":
			return d.length() <= size.x + pad
		"line":
			var fwd := Vector2(dir.x, dir.z).normalized()
			var along := d.dot(fwd)
			var across := absf(d.dot(Vector2(-fwd.y, fwd.x)))
			return along >= -pad and along <= size.x + pad and across <= size.y * 0.5 + pad
		"sector":
			if d.length() > size.x + pad:
				return false
			if d.length() < 0.3:
				return true
			var fwd2 := Vector2(dir.x, dir.z).normalized()
			return absf(fwd2.angle_to(d.normalized())) <= size.y + 0.1
	return false


func _shape_scale(w: Dictionary, k: float) -> void:
	var n: Node3D = w.node
	var s: Vector2 = w.size
	match String(w.kind):
		"circle", "ring":
			n.scale = Vector3(s.x * k, 1.0, s.x * k)
		"line":
			n.scale = Vector3(s.y, 1.0, s.x * k)
		"sector":  # the unit fan spans +-1 rad: squeeze x for a narrower one (about right)
			n.scale = Vector3(s.x * sin(minf(s.y, 1.5)) / sin(1.0) * k, 1.0, s.x * k)


func _process(delta: float) -> void:
	var i := 0
	while i < _warns.size():
		var w: Dictionary = _warns[i]
		var n: MeshInstance3D = w.node
		w.t = float(w.t) + delta
		var t: float = w.t
		var secs: float = w.secs
		if t >= secs + float(w.stay) or not is_instance_valid(n):
			if is_instance_valid(n):
				n.queue_free()
			_warns.remove_at(i)
			continue
		i += 1
		var grow := minf(1.0, t / float(w.grow)) if float(w.grow) > 0.0 else 1.0
		if t >= secs:  # going off: hot, a ring shockwave grows out
			n.visible = true
			if w.hot != null:
				n.material_override = w.hot
			var k2 := clampf((t - secs) / maxf(float(w.stay), 0.01), 0.0, 1.0)
			_shape_scale(w, k2 if String(w.kind) == "ring" else 1.0)
			continue
		match String(w.style):
			"rings":
				_shape_scale(w, (0.9 + 0.1 * absf(sin(t * 12.0))) * grow)
			"disc":
				n.transparency = 0.35 + 0.35 * sin(t * 14.0)
				_shape_scale(w, grow if String(w.kind) != "ring" else 0.25 * grow)
			"flash":
				var k := t / maxf(secs, 0.01)
				n.visible = fmod(t * lerpf(4.0, 16.0, k), 1.0) < 0.65 or k < 0.3
				_shape_scale(w, grow if String(w.kind) != "ring" else 0.25 * grow)