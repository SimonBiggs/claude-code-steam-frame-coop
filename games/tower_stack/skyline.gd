extends Node3D
## THE TOWN: every tower the family finishes stands behind the park as a little model with its roof,
## saved and growing over days (towergen.gd town_slot: first right behind the stage, then outwards).
## Entries are compact [seed, level, daily (0/1)]: every machine rebuilds the same models from them
## (main.gd keeps the list in the "town" state). The newest tower pops in with a bounce.

const G := preload("res://games/tower_stack/towergen.gd")
const Looks := preload("res://games/tower_stack/looks.gd")
const MeshKit := preload("res://core/mesh_kit.gd")

var entries: Array = []
var _models: Array[Node3D] = []
var _pop := {}  # model -> seconds since it appeared


func _ready() -> void:
	name = "Town"


## Show these entries (oldest first; the newest TOWN_KEEP fit). Only new ones pop in.
func set_entries(list: Array) -> void:
	var shown := list.slice(maxi(0, list.size() - G.town_size()))
	if var_to_str(shown) == var_to_str(entries):
		return
	var grow := shown.size() == entries.size() + 1 and var_to_str(shown.slice(0, entries.size())) == var_to_str(entries)
	if not grow:
		for m in _models:
			m.queue_free()
		_models.clear()
		_pop.clear()
		entries = []
	for i in range(entries.size(), shown.size()):
		var e: Array = shown[i]
		var m := _make(e, i)
		if m == null:
			continue
		_models.append(m)
		if grow:
			_pop[m] = 0.0
			m.scale = Vector3.ONE * 0.01
	entries = shown


func _make(e: Array, i: int) -> Node3D:
	var at := G.town_slot(i)
	if at == Vector3.INF or e.size() < 3:
		return null
	var s := G.site(int(e[0]), int(e[1]), int(e[2]) == 1)
	var mi := MeshKit.instance(Looks.tower_model(s.plan, s.palette, String(s.building), bool(s.daily)))
	var root := Node3D.new()
	root.position = at
	root.rotation.y = atan2(-at.x, -at.z)  # its faces look at the park
	root.add_child(mi)
	mi.scale = Vector3.ONE * G.TOWN_SCALE
	add_child(root)
	return root


func _process(delta: float) -> void:
	for m in _pop.keys():
		var t: float = float(_pop[m]) + delta
		_pop[m] = t
		if not is_instance_valid(m):
			_pop.erase(m)
			continue
		var k := clampf(t / 0.7, 0.0, 1.0)
		var e := 1.0 + 2.2 * pow(k - 1.0, 3.0) + 1.2 * pow(k - 1.0, 2.0)  # ease-out-back
		(m as Node3D).scale = Vector3.ONE * maxf(0.01, e)
		if k >= 1.0:
			_pop.erase(m)
