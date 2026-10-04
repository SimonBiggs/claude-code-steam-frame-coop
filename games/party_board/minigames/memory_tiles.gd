extends "res://games/party_board/minigames/mg_base.gd"
## MEMORY TILES (free for all): nine coloured tiles show their colours for a moment, then turn
## white. A colour is called: stand on (islanders) or touch (the GIANT, with a glove) the tile that
## had it before the time runs out. Right = a point. The colours shuffle every round and the
## peeking time gets shorter.

const META := {
	"name": "MEMORY TILES",
	"goal": "Remember the colours! When a colour is called, get to its tile before time runs out.",
	"format": "ffa", "time": 45.0, "music": "quiz", "cam": [16.0, 11.0],
	"tv": [["L-STICK", "Walk onto the tile"]],
	"vr": [["GLOVE", "Touch the tile"]],
	"vr_line": "Remember the colours, then TOUCH the right tile!",
}
const STEP := 2.9
const TILE := 2.55
const COLORS := [Color(0.95, 0.25, 0.25), Color(0.25, 0.5, 1.0), Color(1.0, 0.85, 0.2), Color(0.3, 0.85, 0.35),
	Color(0.7, 0.4, 1.0), Color(1.0, 0.55, 0.15), Color(1.0, 0.5, 0.8), Color(0.35, 0.9, 0.9), Color(0.55, 0.35, 0.2)]
const COLOR_NAMES := ["RED", "BLUE", "YELLOW", "GREEN", "PURPLE", "ORANGE", "PINK", "CYAN", "BROWN"]

var tiles: Array[MeshInstance3D] = []
var colors := PackedInt32Array()  # tile -> colour index
var stage_i := 0  # 0 wait, 1 show, 2 hidden, 3 ask, 4 reveal
var target := -1  # colour index
var stage_t := 0.0
var round_i := 0
var cpu_pick := {}
var giant_tile := -1
var sign_node: MeshInstance3D
var sign_label: Label3D
var _shown_stage := -1


func build() -> void:
	arena_r = 5.4
	build_island(6.6, Color(0.55, 0.7, 0.45))
	var bm := BoxMesh.new()
	bm.size = Vector3(TILE, 0.4, TILE)
	for i in 9:
		var t := MeshInstance3D.new()
		t.mesh = bm
		t.position = tile_pos(i) + Vector3(0, 0.05, 0)
		t.material_override = MeshKit.material(Color(0.95, 0.95, 0.92))
		add_child(t)
		tiles.append(t)
	var sm := SphereMesh.new()
	sm.radius = 0.9
	sm.height = 1.8
	sm.radial_segments = 16
	sm.rings = 8
	sign_node = MeshInstance3D.new()
	sign_node.mesh = sm
	sign_node.position = Vector3(0, 6.0, 4.6)
	sign_node.visible = false
	add_child(sign_node)
	sign_label = UiKit.label3d("", 1.1, "text", true)
	sign_label.outline_size = 24
	sign_label.position = Vector3(0, 7.6, 4.6)
	sign_label.rotation.y = PI  # read from the north (the TV) side
	if main.vr_rig != null:
		sign_label.rotation.y = 0.0  # the giant looks from the south
	add_child(sign_label)
	colors.resize(9)
	for i in 9:
		colors[i] = i


func tile_pos(i: int) -> Vector3:
	return Vector3((i % 3 - 1) * STEP, 0.0, (i / 3 - 1) * STEP)


func tile_at(p: Vector3) -> int:
	var cx := int(round(p.x / STEP)) + 1
	var cz := int(round(p.z / STEP)) + 1
	if cx < 0 or cx > 2 or cz < 0 or cz > 2:
		return -1
	var i := cz * 3 + cx
	var c := tile_pos(i)
	if absf(p.x - c.x) > TILE * 0.5 + 0.15 or absf(p.z - c.z) > TILE * 0.5 + 0.15:
		return -1
	return i


func start_pos(i: int, n: int) -> Vector3:
	var a := TAU * float(i) / float(maxi(1, n))
	return Vector3(cos(a), 0, sin(a)) * 1.2


func on_begin() -> void:
	round_i = 0
	_new_round()


func _new_round() -> void:
	round_i += 1
	var order: Array = range(9)
	order.shuffle()
	for i in 9:
		colors[i] = int(order[i])
	target = int(colors[rng.randi() % 9])
	stage_i = 1
	stage_t = maxf(1.6, 3.2 - round_i * 0.3)
	sound("reveal", -6.0)


func play_tick(delta: float) -> void:
	for p in walkers():
		walk(p, delta)
	separate(0.7)
	if practice:
		stage_i = 1
		return
	stage_t -= delta
	if stage_t > 0.0:
		return
	match stage_i:
		1:
			stage_i = 2
			stage_t = 0.7
			sound("whoosh", -6.0, 0.8)
		2:
			stage_i = 3
			stage_t = 3.6
			cpu_pick.clear()
			var right := colors.find(target)
			for p in walkers():
				if is_cpu(p):
					var smart := 0.6 if (main.flow != null and main.flow.is_kid()) else 0.72
					cpu_pick[p] = right if rng.randf() < smart else rng.randi() % 9
			sound("ding", -2.0)
		3:
			_judge()
			stage_i = 4
			stage_t = 1.8
		4:
			_new_round()


func _judge() -> void:
	var right := colors.find(target)
	var winners: Array = []
	for p in walkers():
		if tile_at(pos[p]) == right:
			winners.append(p)
	if giant:
		giant_tile = _giant_tile()
		if giant_tile == right:
			winners.append(0)
			buzz(1, 0.6, 0.1)
	for w in winners:
		add_score(w, 1)
	fx("judge", [right, winners])
	sound("correct" if not winners.is_empty() else "wrong", -2.0)


## The tile under the giant's lower glove (touching or hovering just above it).
func _giant_tile() -> int:
	var best := -1
	var by := INF
	for h in giant_hands():
		if h.y < 3.0 and h.y < by:
			var t := tile_at(h)
			if t >= 0:
				best = t
				by = h.y
	return best


func snap_extra() -> Array:
	return [stage_i, colors, target]


func unsnap_extra(a: Array) -> void:
	if a.size() >= 3:
		stage_i = int(a[0])
		colors = a[1]
		target = int(a[2])


func on_fx(kind: String, args: Variant) -> void:
	if kind == "judge":
		var a: Array = args
		var right: int = a[0]
		burst_at(tile_pos(right) + Vector3(0, 0.6, 0), COLORS[target], 20)
		for w in a[1]:
			var p: int = w
			if avatars.has(p):
				Creatures.anim(avatars[p]).play("cheer", 1.0)
				popup_at((avatars[p] as Node3D).position, "+1", color_of(p))
			elif p == 0:
				popup_at(tile_pos(right), "GIANT +1", color_of(0))


func _process(delta: float) -> void:
	super(delta)
	var show := stage_i == 1 or stage_i == 4
	for i in 9:
		var t := tiles[i]
		var c: Color = COLORS[colors[i]] if show else Color(0.95, 0.95, 0.92)
		var y := 0.05
		if stage_i == 4 and colors[i] != target:
			y = -0.35
		t.position.y = lerpf(t.position.y, y, 1.0 - exp(-8.0 * delta))
		t.material_override = MeshKit.material(c, 0.6 if stage_i == 4 and colors[i] == target else 0.0)
	var asking := stage_i == 3 or stage_i == 4
	sign_node.visible = asking and target >= 0
	if sign_node.visible:
		sign_node.material_override = MeshKit.material(COLORS[target], 0.4)
		sign_node.position.y = 6.0 + 0.3 * sin(Time.get_ticks_msec() * 0.004)
	sign_label.text = ("FIND %s!" % COLOR_NAMES[target]) if asking and target >= 0 else ("REMEMBER!" if stage_i == 1 else "")
	sign_label.modulate = COLORS[target] if asking and target >= 0 else Color(1, 1, 1)
	if stage_i != _shown_stage:
		_shown_stage = stage_i
		if stage_i == 3 and main.tv_ui != null:
			HudKit.toast(main.tv_ui, "FIND %s!" % COLOR_NAMES[target], {"color": COLORS[target], "duration": 2.5})


func cpu_move(pid: int) -> Vector3:
	if stage_i == 3 and cpu_pick.has(pid):
		return tile_pos(int(cpu_pick[pid]))
	if stage_i == 3:  # a human seat driven by a bot
		return tile_pos(colors.find(target))
	return where(pid)


func bot_vr_goal() -> Vector3:
	if stage_i == 3:
		return tile_pos(colors.find(target)) + Vector3(0, 0.6, 0)
	return Vector3(0, 4.0, 3.0)
