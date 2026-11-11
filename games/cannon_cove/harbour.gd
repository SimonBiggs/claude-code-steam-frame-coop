extends Node3D
## POLLY'S HARBOUR (deep.gd HARBOUR): a little island off the bow where a new piece appears every Deep.HARBOUR_EVERY
## treasures (saved: it only grows). Every machine builds it from the piece count (the "deep" event). The newest piece
## pops up with a bounce; the harbour tree wears the season's colours.

const Deep := preload("res://games/cannon_cove/deep.gd")
const World := preload("res://games/cannon_cove/world.gd")

const SAND := Color(0.96, 0.84, 0.56)
const GRASS := Color(0.36, 0.72, 0.32)
const WOOD := Color(0.6, 0.42, 0.24)
const ROOF := Color(0.85, 0.25, 0.2)
const WALL := Color(0.97, 0.94, 0.86)
const LAMP := Color(1.0, 0.88, 0.45)

var shown := -1
var shown_season := ""
var island: Node3D
var pieces: Node3D


func _ready() -> void:
	name = "Harbour"
	position = Deep.HARBOUR_AT + Vector3(0.0, World.BASE_SEA - 0.3, 0.0)
	island = Node3D.new()
	add_child(island)
	var r := Deep.HARBOUR_R
	var sand := World.sphere(island, 1.0, Vector3.ZERO, World.mat(SAND), 20)
	sand.scale = Vector3(r, r * 0.12, r)
	var hill := World.sphere(island, 1.0, Vector3(0.0, 0.2, -r * 0.15), World.mat(GRASS), 16)
	hill.scale = Vector3(r * 0.7, r * 0.18, r * 0.6)
	pieces = Node3D.new()
	add_child(pieces)
	for c in island.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Every machine: n pieces in `season`'s colours (the newest pops up when it grew).
func build(n: int, season: String) -> void:
	if n == shown and season == shown_season:
		return
	var grew := shown >= 0 and n > shown
	shown = n
	shown_season = season
	for c in pieces.get_children():
		pieces.remove_child(c)
		c.queue_free()
	for i in mini(n, Deep.HARBOUR.size()):
		var p := _piece(String(Deep.HARBOUR[i]), season)
		p.position = Deep.harbour_spot(i) - Deep.HARBOUR_AT + Vector3(0.0, 1.2, 0.0)
		p.rotation.y = atan2(-p.position.x, -p.position.z) + PI  # faces our ship (at the island's +z side)
		pieces.add_child(p)
		for g in p.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if grew and i == n - 1:
			p.scale = Vector3.ONE * 0.05
			p.create_tween().tween_property(p, "scale", Vector3.ONE, 1.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## One harbour piece (a few metres tall: seen from the ship 60+ m away).
func _piece(kind: String, season: String) -> Node3D:
	var root := Node3D.new()
	root.name = kind
	var wood := World.mat(WOOD)
	match kind:
		"jetty":
			World.box(root, Vector3(2.4, 0.3, 9.0), Vector3(0.0, -0.6, 3.5), wood)
			for k in 4:
				for sx in [-1.0, 1.0]:
					World.cyl(root, 0.18, 0.18, 2.0, Vector3(sx * 1.1, -1.2, 0.5 + k * 2.6), wood, 6)
		"hut":
			World.box(root, Vector3(3.6, 2.6, 3.0), Vector3(0.0, 1.3, 0.0), World.mat(WALL))
			var roof := World.cyl(root, 0.0, 3.0, 1.8, Vector3(0.0, 3.5, 0.0), World.mat(ROOF), 4)
			roof.rotation.y = PI / 4.0
			World.box(root, Vector3(0.9, 1.5, 0.1), Vector3(0.0, 0.75, 1.52), wood)
		"beacon":
			World.cyl(root, 0.8, 1.2, 7.0, Vector3(0.0, 3.5, 0.0), World.mat(WALL), 10)
			World.cyl(root, 1.0, 1.0, 0.9, Vector3(0.0, 2.5, 0.0), World.mat(ROOF), 10)
			World.sphere(root, 0.8, Vector3(0.0, 7.6, 0.0), World.mat(LAMP, 3.0), 10)
			World.cyl(root, 0.1, 1.0, 0.8, Vector3(0.0, 8.6, 0.0), World.mat(ROOF), 10)
		"boat":
			var hull := World.sphere(root, 1.0, Vector3(0.0, 0.0, 0.0), World.mat(Color(0.25, 0.55, 0.95)), 12)
			hull.scale = Vector3(1.2, 0.5, 2.6)
			World.cyl(root, 0.08, 0.08, 3.0, Vector3(0.0, 1.6, 0.0), wood, 6)
			var sail := World.box(root, Vector3(0.05, 2.0, 1.4), Vector3(0.0, 1.9, 0.5), World.mat(WALL))
			sail.rotation.x = 0.1
		"tree":
			World.cyl(root, 0.25, 0.4, 3.0, Vector3(0.0, 1.5, 0.0), wood, 6)
			var crown := World.sphere(root, 1.7, Vector3(0.0, 3.8, 0.0), World.mat(Deep.season_data(season).tree), 12)
			crown.scale = Vector3(1.0, 0.85, 1.0)
		"crane":
			World.box(root, Vector3(0.5, 6.0, 0.5), Vector3(0.0, 3.0, 0.0), wood)
			World.box(root, Vector3(0.4, 0.4, 5.0), Vector3(0.0, 5.8, 2.0), wood)
			World.box(root, Vector3(0.05, 2.0, 0.05), Vector3(0.0, 4.6, 4.3), World.mat(Color(0.2, 0.2, 0.2)))
			World.box(root, Vector3(1.0, 0.8, 1.0), Vector3(0.0, 3.3, 4.3), World.mat(Color(0.95, 0.75, 0.3)))
		"market":
			for k in 3:
				var col: Color = [Color(1.0, 0.45, 0.45), Color(1.0, 0.85, 0.3), Color(0.45, 0.7, 1.0)][k]
				World.box(root, Vector3(1.6, 1.0, 1.2), Vector3((k - 1) * 1.9, 0.5, 0.0), wood)
				var awning := World.box(root, Vector3(1.8, 0.12, 1.5), Vector3((k - 1) * 1.9, 2.0, 0.2), World.mat(col))
				awning.rotation.x = 0.25
				World.cyl(root, 0.06, 0.06, 1.0, Vector3((k - 1) * 1.9, 1.5, -0.4), wood, 5)
		"windmill":
			World.cyl(root, 0.9, 1.3, 5.0, Vector3(0.0, 2.5, 0.0), World.mat(WALL), 10)
			World.cyl(root, 0.0, 1.2, 1.4, Vector3(0.0, 5.7, 0.0), World.mat(ROOF), 10)
			var sails := Node3D.new()
			sails.name = "Sails"
			sails.position = Vector3(0.0, 4.6, 1.3)
			root.add_child(sails)
			for k in 4:
				var b := World.box(sails, Vector3(0.6, 3.2, 0.08), Vector3(0.0, 1.6, 0.0), World.mat(Color(0.95, 0.9, 0.8)))
				var pivot := Node3D.new()
				pivot.rotation.z = k * PI / 2.0
				sails.add_child(pivot)
				b.reparent(pivot, false)
		"bell":
			World.box(root, Vector3(0.3, 3.0, 0.3), Vector3(-1.0, 1.5, 0.0), wood)
			World.box(root, Vector3(0.3, 3.0, 0.3), Vector3(1.0, 1.5, 0.0), wood)
			World.box(root, Vector3(2.4, 0.3, 0.3), Vector3(0.0, 3.0, 0.0), wood)
			World.cyl(root, 0.25, 0.6, 0.9, Vector3(0.0, 2.3, 0.0), World.mat(Color(1.0, 0.8, 0.25), 0.4), 10)
		_:  # flags: bunting between two poles
			for sx in [-1.0, 1.0]:
				World.cyl(root, 0.1, 0.1, 4.5, Vector3(sx * 2.5, 2.25, 0.0), wood, 6)
			for k in 7:
				var fc: Color = [Color(0.95, 0.2, 0.15), Color(1.0, 0.85, 0.2), Color(0.2, 0.45, 1.0), Color(0.2, 0.8, 0.3)][k % 4]
				var f := World.box(root, Vector3(0.5, 0.6, 0.05), Vector3(-2.1 + k * 0.7, 3.9 - sin(k / 6.0 * PI) * 0.6, 0.0), World.mat(fc))
				f.rotation.z = PI / 4.0
	return root


func _process(delta: float) -> void:
	for w in pieces.get_children():
		var s := w.get_node_or_null("Sails") as Node3D
		if s != null:
			s.rotation.z += delta * 0.8
