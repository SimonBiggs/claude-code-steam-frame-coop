extends Node3D
## A player's token on the board: a cute core/creatures.gd character on a coloured base, which hops
## space to space, flies (dragon rides, warps) and cheers / sulks. Moves queue up and play in order,
## so the same code animates the host and the TV machine from the replicated board state.

const Creatures := preload("res://core/creatures.gd")
const MeshKit := preload("res://core/mesh_kit.gd")

## Per player id: character class, hat, hair colour (outfit = the player colour).
const LOOKS := [
	["pilot", "pilot_helmet", Color(0.3, 0.2, 0.14)], ["chef", "chef", Color(0.97, 0.82, 0.46)],
	["princess", "tiara", Color(0.98, 0.58, 0.72)], ["farmer", "straw", Color(0.58, 0.37, 0.2)],
	["astronaut", "none", Color(0.13, 0.11, 0.12)], ["mage", "wizard", Color(0.92, 0.92, 0.95)],
	["pirate", "tricorn", Color(0.88, 0.42, 0.2)],
]
const HOP_TIME := 0.3
const TOKEN_SCALE := 1.25

signal hopped(token: Node3D)
signal landed(token: Node3D)

var pid := 0
var color := Color.WHITE
var body: Node3D
var base: MeshInstance3D
var crown: Node3D
var space := -1  # the space this token is on (or heading to)
var offset := Vector3.ZERO  # spread when several tokens share a space
var _queue: Array = []  # [kind, Vector3 target, float duration]
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _kind := ""
var _t := 0.0
var _dur := 0.0
var _home := Vector3.ZERO  # current rest position (without offset)


func setup(p_pid: int, p_color: Color, main_look: Array = []) -> void:
	pid = p_pid
	color = p_color
	name = "Token%d" % pid
	var look: Array = main_look if not main_look.is_empty() else LOOKS[pid % LOOKS.size()]
	_look_key = var_to_str(look)
	body = Creatures.humanoid({"class": String(look[0]), "hat": String(look[1]), "hair": look[2], "outfit": color,
		"seed": 11 + pid * 7, "scale": TOKEN_SCALE})
	add_child(body)
	var b := MeshKit.Builder.new()
	b.cylinder(0.42, 0.46, 0.08, MeshKit.at(Vector3(0, 0.04, 0)), color, 16)
	b.torus(0.44, 0.04, MeshKit.at(Vector3(0, 0.08, 0)), color.lightened(0.45), 16, 5)
	base = MeshKit.instance(b.build(), false)
	add_child(base)


func anim() -> Creatures.Anim:
	return Creatures.anim(body)


## Jump straight to a spot (late joiners, snapshots).
func place(at: Vector3) -> void:
	_queue.clear()
	_kind = ""
	_home = at
	position = at + offset


## Queue a hop to the next space.
func hop_to(at: Vector3, dur: float = HOP_TIME) -> void:
	_queue.append(["hop", at, dur])


## Queue a long flight (dragon, warp pipe, swap).
func fly_to(at: Vector3, dur: float = 1.3) -> void:
	_queue.append(["fly", at, dur])


func busy() -> bool:
	return _kind != "" or not _queue.is_empty()


## A new look (main.look_of: this party's won hat): the body is rebuilt; its name tag moves across.
var _look_key := ""


func set_look(look: Array) -> void:
	var key := var_to_str(look)
	if key == _look_key or body == null:
		return
	_look_key = key
	var old := body
	body = Creatures.humanoid({"class": String(look[0]), "hat": String(look[1]), "hair": look[2], "outfit": color,
		"seed": 11 + pid * 7, "scale": TOKEN_SCALE})
	add_child(body)
	for c in old.get_children():
		if c is Label3D:
			c.reparent(body, false)
	remove_child(old)
	old.queue_free()
	if crown != null:
		crown.position.y = Creatures.height_of(body) + 0.15


## The item this token holds (boards.gd ITEMS id, "" = none): a little picture bobbing over its head.
var item_node: Node3D
var item_id := ""
var _item_y := 2.0


func set_item(id: String) -> void:
	if id == item_id:
		return
	item_id = id
	if item_node != null:
		item_node.queue_free()
		item_node = null
	if id == "":
		return
	item_node = item_mesh(id)
	item_node.scale = Vector3.ONE * 0.6
	_item_y = Creatures.height_of(body) + 0.75
	item_node.position.y = _item_y
	add_child(item_node)


## A picture of an item (board units, ~1 unit tall): 2 DICE, SWAP arrows or a WARP swirl.
static func item_mesh(id: String) -> Node3D:
	var b := MeshKit.Builder.new()
	match id:
		"double":
			for k in 2:
				var c := Vector3(-0.32 + k * 0.64, 0.0, 0.0)
				b.rounded_box(Vector3(0.5, 0.5, 0.5), 0.08, MeshKit.at(c, Vector3.ONE, Vector3(0.3, 0.5 - k, 0.2)), Color(1, 1, 1))
				b.sphere(0.07, MeshKit.at(c + Basis.from_euler(Vector3(0.3, 0.5 - k, 0.2)) * Vector3(0, 0, 0.26)), Color(0.9, 0.2, 0.25), 6)
		"swap":
			b.box(Vector3(0.8, 0.12, 0.12), MeshKit.at(Vector3(0, 0.18, 0)), Color(0.5, 0.75, 1.0), true)
			b.wedge(Vector3(0.3, 0.3, 0.12), MeshKit.at(Vector3(0.5, 0.18, 0), Vector3.ONE, Vector3(0, 0, -PI * 0.5)), Color(0.5, 0.75, 1.0), true)
			b.box(Vector3(0.8, 0.12, 0.12), MeshKit.at(Vector3(0, -0.18, 0)), Color(1.0, 0.6, 0.3), true)
			b.wedge(Vector3(0.3, 0.3, 0.12), MeshKit.at(Vector3(-0.5, -0.18, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5)), Color(1.0, 0.6, 0.3), true)
		"warp":
			b.torus(0.4, 0.08, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.75, 0.5, 1.0), 16, 5, true)
			b.torus(0.24, 0.07, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.45, 0.9, 1.0), 14, 5, true)
			b.sphere(0.1, MeshKit.at(Vector3.ZERO), Color(1, 1, 1), 6, true)
		_:
			b.sphere(0.3, MeshKit.at(Vector3.ZERO), Color(1, 1, 1), 8)
	return MeshKit.instance(b.build(), false)


func set_crown(on: bool) -> void:
	if on and crown == null:
		var b := MeshKit.Builder.new()
		b.cylinder(0.26, 0.22, 0.2, MeshKit.at(Vector3(0, 0.1, 0)), Color(1.0, 0.82, 0.25), 10, true)
		for k in 5:
			var a := k * TAU / 5.0
			b.cone(0.07, 0.2, MeshKit.at(Vector3(cos(a) * 0.22, 0.28, sin(a) * 0.22)), Color(1.0, 0.85, 0.3), 6, true)
		crown = MeshKit.instance(b.build(), false)
		crown.position.y = Creatures.height_of(body) + 0.15
		add_child(crown)
	elif not on and crown != null:
		crown.queue_free()
		crown = null


func _process(delta: float) -> void:
	if _kind == "" and not _queue.is_empty():
		var q: Array = _queue.pop_front()
		_kind = String(q[0])
		_from = position
		_to = q[1]
		_dur = maxf(0.05, float(q[2]))
		_t = 0.0
		var dir := _to - _from
		if Vector2(dir.x, dir.z).length() > 0.05:
			anim().face(dir)
		if _kind == "fly":
			anim().play("jump", 0.5)
	if _kind != "":
		_t += delta
		var k := clampf(_t / _dur, 0.0, 1.0)
		var target := _to + offset
		var p := _from.lerp(target, k)
		var height := 0.9 if _kind == "hop" else 7.0
		p.y += sin(k * PI) * height
		position = p
		if _kind == "fly":
			rotation.y = k * TAU * 2.0
		if k >= 1.0:
			rotation.y = 0.0
			_home = _to
			position = _to + offset
			var was := _kind
			_kind = ""
			anim().squash(0.25)
			if was == "hop":
				hopped.emit(self)
			if _queue.is_empty():
				landed.emit(self)
	else:
		var want := _home + offset
		position = position.lerp(want, 1.0 - exp(-10.0 * delta))
	if item_node != null:
		item_node.rotation.y += delta * 1.5
		item_node.position.y = _item_y + 0.12 * sin(Time.get_ticks_msec() / 300.0)
