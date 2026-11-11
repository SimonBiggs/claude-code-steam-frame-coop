extends "res://core/pick_orbs.gd"
## ELEMENTAL BENDER: Kiko's ALTAR, picture-first picks (boons.gd) on the shared PICK ORBS (core/pick_orbs.gd). A row
## of glowing stones in front of the temple (opts.body), each with a big spinning picture (opts.icon: an element orb
## for a master, a gift shape for a boon) and a short name. Bend at a stone (any shot or punch near it: projectile.gd
## reads the orb's hit_radius / hit_height) or walk onto it (at_point): that's your pick. Little coloured orbs circle a
## stone for every player who took it (show_takers). The middle stone glows brightest: it is taken for whoever hasn't
## picked when the time runs out. Every machine builds the stones from the host's net state "pick"
## {n, kind, ids, wait, def}; the host decides who took what (main.gd _altar_pick) and shares it in "taken" / "perks".

const Boons := preload("res://games/elemental_bender/boons.gd")
const Arenas := preload("res://games/elemental_bender/arenas.gd")
const E := preload("res://games/elemental_bender/elem.gd")
const ResCache := preload("res://core/res_cache.gd")

const GAP := 3.5
const STONE_TOUCH := 1.2

var info := {}
var _key := ""


func _init() -> void:
	collision_layer = 0  # shots test distance (projectile.gd); fighters walk onto the stones


## Every machine: build (or clear, d = {}) the stones.
func show_pick(d: Dictionary) -> void:
	var key := "" if d.is_empty() else str(d.get("n", 0)) + str(d.get("ids", []))
	if key == _key:
		return
	_key = key
	clear()
	if d.is_empty():
		return
	var kind := String(d.get("kind", "boon"))
	var list: Array = []
	for id in d.get("ids", []):
		list.append({"id": String(id), "name": Boons.pick_name(kind, String(id)), "color": Boons.pick_color(kind, String(id))})
	show_orbs(kind, list, Vector3(0, 0, Arenas.ALTAR_Z), GAP, 0.0, {
		"def": int(d.get("def", list.size() / 2)),
		"body": func(e: Dictionary, mid: bool) -> Node3D: return MeshKit.instance(_base_mesh(e.color, mid), false),
		"icon": func(e: Dictionary) -> Node3D: return MeshKit.instance(icon_mesh(kind, String(e.id)), false),
		"spin": 1.3, "icon_y": 2.2, "icon_scale": 1.4, "bob": 0.12, "label_y": 3.4, "label_px": 0.0105, "font": 56,
		"two_lines": true, "pop": true, "group": "eb_enemy", "touch": STONE_TOUCH, "max_y": 3.0,
		"hit_r": 0.9, "hit_height": 1.7, "dot_y": 2.2, "dot_r": 1.0, "dot_size": 0.13, "punch": 1.3})
	info = d
	for o in orbs:
		(o as Node3D).name = "Stone_%s" % (o as Orb).id


func clear() -> void:
	super.clear()
	info = {}


## Host: the stone a point stands on (-1 = none).
func stone_at(p: Vector3) -> int:
	return at_point(p)


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
