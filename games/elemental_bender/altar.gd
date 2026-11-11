extends Node3D
## ELEMENTAL BENDER: Kiko's ALTAR, picture-first picks (boons.gd). A row of glowing stones in front of the temple,
## each with a big spinning picture (an element orb for a master, a gift shape for a boon) and a short name.
## Bend at a stone (any shot or punch that hits it) or walk onto it: that's your pick. Little coloured orbs circle a
## stone for every player who took it. The middle stone glows brightest: it is taken for whoever hasn't picked when
## the time runs out. Every machine builds the stones from the host's net state "pick" {n, kind, ids, wait};
## the host decides who took what (main.gd _altar_pick) and shares it in "perks".

const Boons := preload("res://games/elemental_bender/boons.gd")
const Arenas := preload("res://games/elemental_bender/arenas.gd")
const E := preload("res://games/elemental_bender/elem.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

const GAP := 3.5
const TOUCH := 1.2

var stones: Array = []
var info := {}
var _key := ""
var _t := 0.0


## A pick stone: a target for shots (projectile.gd reads hit_radius / hit_height; main skips it when dead).
class Stone extends Node3D:
	var index := 0
	var id := ""
	var kind := ""
	var hit_radius := 0.9
	var hit_height := 1.7
	var dead := false
	var icon: Node3D
	var takers: Node3D
	var shown_takers := ""


static func spot(i: int, n: int) -> Vector3:
	return Vector3((i - (n - 1) * 0.5) * GAP, 0.0, Arenas.ALTAR_Z)


func showing() -> bool:
	return not stones.is_empty()


## Every machine: build (or clear, d = {}) the stones.
func show_pick(d: Dictionary) -> void:
	var key := str(d.get("n", 0)) + str(d.get("ids", []))
	if d.is_empty():
		key = ""
	if key == _key:
		return
	_key = key
	clear()
	info = d
	if d.is_empty():
		return
	var ids: Array = d.get("ids", [])
	var kind := String(d.get("kind", "boon"))
	for i in ids.size():
		var s := Stone.new()
		s.index = i
		s.id = String(ids[i])
		s.kind = kind
		s.name = "Stone_%s" % s.id
		s.add_to_group("eb_enemy")
		add_child(s)
		s.position = spot(i, ids.size())
		var col := Boons.pick_color(kind, s.id)
		var mid := i == int(d.get("def", int(ids.size() / 2)))
		s.add_child(MeshKit.instance(_base_mesh(col, mid), false))
		s.icon = MeshKit.instance(icon_mesh(kind, s.id), false)
		s.icon.position.y = 2.2
		s.icon.scale = Vector3.ONE * 1.4
		s.add_child(s.icon)
		var label := Label3D.new()
		label.text = Boons.pick_name(kind, s.id).replace(" ", "\n")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 0.0105
		label.font_size = 56
		label.outline_size = 12
		label.modulate = col.lightened(0.4)
		label.outline_modulate = Color(0.05, 0.05, 0.1)
		label.position.y = 3.4
		s.add_child(label)
		s.takers = Node3D.new()
		s.takers.position.y = 2.2
		s.add_child(s.takers)
		s.scale = Vector3.ONE * 0.01
		create_tween().tween_property(s, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(i * 0.12)
		stones.append(s)


func clear() -> void:
	for s in stones:
		if is_instance_valid(s):
			(s as Node).queue_free()
	stones.clear()
	info = {}


## Every machine: show who took which stone. taken: {slot: stone index}, colors: {slot: Color}.
func show_takers(taken: Dictionary, colors: Dictionary) -> void:
	for s in stones:
		var st: Stone = s
		var who: Array = []
		for slot in taken:
			if int(taken[slot]) == st.index:
				who.append(int(slot))
		who.sort()
		var key := str(who)
		if key == st.shown_takers:
			continue
		st.shown_takers = key
		for c in st.takers.get_children():
			c.queue_free()
		for k in who.size():
			var orb := MeshInstance3D.new()
			orb.mesh = _orb_mesh()
			orb.material_override = MeshKit.material(colors.get(who[k], Color.WHITE), 3.0)
			var a := k * TAU / maxf(1.0, who.size())
			orb.position = Vector3(cos(a), 0.0, sin(a)) * 1.0
			st.takers.add_child(orb)
		if not who.is_empty():
			var pop := create_tween()
			pop.tween_property(st.icon, "scale", Vector3.ONE * 1.8, 0.12)
			pop.tween_property(st.icon, "scale", Vector3.ONE * 1.4, 0.2)


## Host: the stone a point stands on (-1 = none).
func stone_at(p: Vector3) -> int:
	for s in stones:
		var st: Stone = s
		if Vector2(p.x - st.global_position.x, p.z - st.global_position.z).length() < TOUCH and p.y < 3.0:
			return st.index
	return -1


func _process(delta: float) -> void:
	_t += delta
	for s in stones:
		var st: Stone = s
		if not is_instance_valid(st):
			continue
		st.icon.rotation.y += delta * 1.3
		st.icon.position.y = 2.2 + sin(_t * 2.0 + st.index) * 0.12
		st.takers.rotation.y -= delta * 2.0


static func _orb_mesh() -> SphereMesh:
	return ResCache.get_or_make("eb_taker_orb_v1", func() -> Resource:
		var m := SphereMesh.new()
		m.radius = 0.13
		m.height = 0.26
		m.radial_segments = 8
		m.rings = 4
		return m) as SphereMesh


static func _base_mesh(col: Color, mid: bool) -> ArrayMesh:
	return ResCache.get_or_make("eb_altar_base_%s_%s_v1" % [col.to_html(false), mid], func() -> Resource:
		var b := MeshKit.builder()
		b.cylinder(0.85, 1.0, 0.5, MeshKit.at(Vector3(0, 0.25, 0)), Color(0.62, 0.6, 0.56), 10)
		b.cylinder(0.55, 0.7, 0.7, MeshKit.at(Vector3(0, 0.85, 0)), Color(0.7, 0.68, 0.63), 10)
		b.torus(0.9, 0.08 if not mid else 0.13, MeshKit.at(Vector3(0, 0.52, 0)), col, 20, 4, true)
		b.cylinder(0.5, 0.5, 0.06, MeshKit.at(Vector3(0, 1.22, 0)), col, 12, true)
		return b.build()) as ArrayMesh


## The picture above a stone (about 1 m across).
static func icon_mesh(kind: String, id: String) -> ArrayMesh:
	return ResCache.get_or_make("eb_altar_icon_%s_%s_v1" % [kind, id], func() -> Resource: return _build_icon(kind, id)) as ArrayMesh


static func _build_icon(kind: String, id: String) -> ArrayMesh:
	var b := MeshKit.builder()
	var col := Boons.pick_color(kind, id)
	var white := Color(0.95, 0.95, 1.0)
	var gold := Color(1.0, 0.82, 0.25)
	if kind == "master":
		var e := int(Boons.master(id).get("element", -1))
		if e < 0:  # the spirit master: a white star with the four elements round it
			b.star(5, 0.38, 0.17, 0.12, Transform3D.IDENTITY, Color(1.0, 0.97, 0.85), true)
			for k in 4:
				var a := k * TAU / 4.0
				b.sphere(0.09, MeshKit.at(Vector3(cos(a) * 0.45, sin(a) * 0.45, 0)), E.COLORS[k], 8, true)
			return b.build()
		b.sphere(0.32, MeshKit.at(Vector3.ZERO), col, 14, true)
		match e:
			E.AIR:
				for k in 3:
					b.torus(0.4 + k * 0.08, 0.025, MeshKit.at(Vector3(0, -0.2 + k * 0.2, 0)), white, 16, 4, true)
			E.WATER:
				b.cone(0.2, 0.32, MeshKit.at(Vector3(0, 0.36, 0)), col, 10, true)
			E.EARTH:
				for k in 4:
					var a := k * TAU / 4.0 + 0.4
					b.box(Vector3.ONE * 0.16, MeshKit.at(Vector3(cos(a) * 0.38, -0.25, sin(a) * 0.38), Vector3.ONE, Vector3(0.4, a, 0.3)), Color(0.55, 0.42, 0.28))
			_:
				for k in 3:
					b.cone(0.1, 0.3, MeshKit.at(Vector3(-0.16 + k * 0.16, 0.34 + (0.08 if k == 1 else 0.0), 0)), Color(1.0, 0.75, 0.2), 6, true)
		return b.build()
	match id:
		"big":  # a big fireball and a small one
			b.sphere(0.34, MeshKit.at(Vector3(0.08, 0, 0)), col, 12, true)
			b.sphere(0.14, MeshKit.at(Vector3(-0.38, -0.12, 0)), col.lightened(0.3), 8, true)
		"power":  # a big fist
			b.rounded_box(Vector3(0.5, 0.42, 0.4), 0.1, Transform3D.IDENTITY, col)
			for k in 4:
				b.sphere(0.09, MeshKit.at(Vector3(-0.18 + k * 0.12, 0.18, 0.18)), col.lightened(0.3), 8)
			b.box(Vector3(0.3, 0.3, 0.3), MeshKit.at(Vector3(0, -0.3, -0.05)), white)
		"shield":  # a round rock shield
			b.cylinder(0.42, 0.42, 0.12, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), col, 14)
			b.cylinder(0.15, 0.15, 0.16, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), gold, 10, true)
		"spirit", "spark":  # a glowing star (with sparks for SPIRIT SPARK)
			b.star(5, 0.4, 0.18, 0.12, Transform3D.IDENTITY, col, true)
			if id == "spark":
				for k in 3:
					var a := k * TAU / 3.0 + 0.5
					b.sphere(0.07, MeshKit.at(Vector3(cos(a) * 0.55, sin(a) * 0.55, 0)), gold, 6, true)
		"heal":  # a green heart with rain drops
			b.sphere(0.2, MeshKit.at(Vector3(-0.14, 0.12, 0)), col, 12, true)
			b.sphere(0.2, MeshKit.at(Vector3(0.14, 0.12, 0)), col, 12, true)
			b.cone(0.3, 0.42, MeshKit.at(Vector3(0, -0.2, 0), Vector3.ONE, Vector3(PI, 0, 0)), col, 12, true)
		"swift":  # a winged boot
			b.box(Vector3(0.2, 0.4, 0.22), MeshKit.at(Vector3(0, 0.05, 0)), col)
			b.box(Vector3(0.4, 0.14, 0.24), MeshKit.at(Vector3(0.1, -0.2, 0)), col)
			for k in 3:
				b.box(Vector3(0.3 - k * 0.06, 0.06, 0.04), MeshKit.at(Vector3(-0.25, 0.2 - k * 0.09, 0), Vector3.ONE, Vector3(0, 0, 0.4)), white, true)
		"gale":  # three gusts
			for k in 3:
				b.torus(0.18 + k * 0.1, 0.035, MeshKit.at(Vector3(k * 0.1 - 0.1, 0, 0), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), col, 16, 4, true)
		"chi":  # a blue drop
			b.sphere(0.26, MeshKit.at(Vector3(0, -0.1, 0)), col, 12, true)
			b.cone(0.2, 0.34, MeshKit.at(Vector3(0, 0.25, 0)), col, 10, true)
		"triple":  # three shots in a fan
			for k in 3:
				var a := (k - 1) * 0.5
				b.sphere(0.14, MeshKit.at(Vector3(sin(a) * 0.4, cos(a) * 0.4 - 0.2, 0)), col, 8, true)
		"leaf":  # a big leaf
			b.ellipsoid(Vector3(0.18, 0.4, 0.05), MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(0, 0, 0.5)), col, 10)
			b.box(Vector3(0.03, 0.5, 0.06), MeshKit.at(Vector3(0, 0, 0.02), Vector3.ONE, Vector3(0, 0, 0.5)), col.darkened(0.3))
		_:
			b.sphere(0.3, MeshKit.at(Vector3.ZERO), col, 10, true)
	return b.build()
