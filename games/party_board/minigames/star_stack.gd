extends "res://games/party_board/minigames/mg_base.gd"
## STAR STACK (free for all; from the arcade's Tower Stack): everyone has their own tower. A candy block swings
## left and right above it: press A to drop it. Close enough to the top and it stacks (the tower may lean a
## little); too far off and it tumbles away and a new block comes. The tallest tower wins. Everyone's block
## swings the same way at the same speed (it speeds up a little as the tower grows) and the landing spot is
## generous, so it's fair for any number of players and a little one can build a fine tower. The GIANT drops
## with the trigger or by tapping the swinging block.

const META := {
	"name": "STAR STACK",
	"goal": "Press A to drop the block on your tower. The tallest tower wins!",
	"format": "ffa", "time": 25.0, "music": "party", "cam": [9.5, 12.5],
	"tv": [["A", "Drop the block"]],
	"vr": [["GLOVE", "Tap the swinging block"]],
	"vr_line": "TAP the block to drop it on your tower!",
	"cue": "pop",
}
const GAP := 2.1  ## between towers
const BLOCK := Vector3(1.0, 0.42, 1.0)
const SWING := 1.15  ## how far the block swings either side
const TOL := 0.55  ## how far off the top a block may land and still stack
const BASE_SPEED := 2.0  ## radians per second of swing
const SPEED_UP := 0.08  ## more per block in the tower
const DROP_T := 0.3
const MAX_H := 16
const GIANT_SWING := 1.35  ## the giant (a grown-up) gets a quicker block and a longer wait between drops
const GIANT_WAIT := 1.1

var builders: Array[int] = []  ## everyone stacking (the giant first when there is one)
var towers := {}  ## pid -> Array of x offsets (one per stacked block)
var phase := {}  ## pid -> swing phase
var dropping := {}  ## pid -> [seconds left, x] while a block falls
var _cool := {}  ## pid -> seconds before they may drop again
var _nodes := {}  ## pid -> Node3D holding the stacked blocks (every machine)
var _swing_nodes := {}  ## pid -> the swinging block (every machine)
var _shown := {}  ## pid -> tower size shown
var _cpu_wait := {}


func build() -> void:
	arena_r = 6.5
	build_island(7.4, Color(0.52, 0.78, 0.42))
	builders.clear()
	if giant:
		builders.append(0)
	for p in walkers():
		builders.append(p)
	var plinth := ResCache.get_or_make("pb_stack_plinth", func() -> Resource:
		var b := MeshKit.Builder.new()
		b.rounded_box(Vector3(1.3, 0.3, 1.3), 0.06, MeshKit.at(Vector3(0, 0.15, 0)), Color(0.85, 0.82, 0.78))
		return b.build())
	for i in builders.size():
		var p := builders[i]
		var base := Node3D.new()
		base.position = tower_pos(i)
		add_child(base)
		base.add_child(MeshKit.instance(plinth, false))
		var ring := MeshKit.Builder.new()
		ring.torus(0.7, 0.06, MeshKit.at(Vector3(0, 0.31, 0)), color_of(p), 16, 4, true)
		base.add_child(MeshKit.instance(ring.build(), false))
		var stack := Node3D.new()
		base.add_child(stack)
		_nodes[p] = stack
		var sw := _block(p, true)
		base.add_child(sw)
		_swing_nodes[p] = sw
		towers[p] = []
		phase[p] = 0.0


func tower_pos(i: int) -> Vector3:
	var n := builders.size()
	return Vector3((float(i) - (n - 1) * 0.5) * GAP, 0.0, 0.5)


func _block(p: int, glow: bool) -> Node3D:
	var c: Color = color_of(p).lightened(0.25)
	var mesh := ResCache.get_or_make("pb_stack_block_%s_%d" % [c.to_html(), int(glow)], func() -> Resource:
		var b := MeshKit.Builder.new()
		b.rounded_box(BLOCK, 0.08, MeshKit.at(Vector3.ZERO), c, glow)
		b.star(5, 0.24, 0.11, 0.06, MeshKit.at(Vector3(0, 0, BLOCK.z * 0.5 + 0.02)), Color(1.0, 0.9, 0.4), true)
		return b.build())
	return MeshKit.instance(mesh, false)


func start_pos(i: int, n: int) -> Vector3:
	var k := i + (1 if giant else 0)
	var m := n + (1 if giant else 0)
	return Vector3((float(k) - (m - 1) * 0.5) * GAP, 0.0, -1.5)  # in front of their tower, seen from the TV


func on_begin() -> void:
	for p in builders:
		towers[p] = []
		phase[p] = 0.0
		dropping.erase(p)
		_cool[p] = 0.0


func top_y(p: int) -> float:
	return 0.3 + BLOCK.y * ((towers[p] as Array).size() + 0.5)


func swing_x(p: int) -> float:
	return sin(float(phase[p])) * SWING


func top_off(p: int) -> float:
	var t: Array = towers[p]
	return float(t[-1]) if not t.is_empty() else 0.0


func play_tick(delta: float) -> void:
	var hs := giant_hands()
	for p in builders:
		var h := (towers[p] as Array).size()
		# (the block swings slower for whoever is behind: SIMPLE catch-up)
		phase[p] = float(phase[p]) + delta * (BASE_SPEED + SPEED_UP * h) * (1.0 - 0.35 * catch_up(p)) * (GIANT_SWING if p == 0 and giant else 1.0)
		_cool[p] = float(_cool.get(p, 0.0)) - delta
		if dropping.has(p):
			var d: Array = dropping[p]
			d[0] = float(d[0]) - delta
			if float(d[0]) <= 0.0:
				dropping.erase(p)
				_land(p, float(d[1]))
			continue
		var pressed := false
		if p == 0 and giant:
			var sw := (_swing_nodes[p] as Node3D)
			for k in hs.size():
				if hs[k].distance_to(to_local(sw.global_position)) < HAND_R * 0.45:  # hold a glove over the tower: the block swings into it
					pressed = true
			if main.vr_rig != null and main.vr_rig.trigger_pressed():
				pressed = true
		elif is_cpu(p):
			pressed = _cpu_drop(p, delta)
		else:
			pressed = bool(input_of(p)["pressed"])
		if pressed and float(_cool[p]) <= 0.0 and h < MAX_H:
			dropping[p] = [DROP_T, swing_x(p)]
			_cool[p] = DROP_T + (GIANT_WAIT if p == 0 and giant else 0.25)
			phase[p] = 0.0 if rng.randf() < 0.5 else PI  # the next block starts from the middle
	_place()


func _land(p: int, x: float) -> void:
	var t: Array = towers[p]
	if absf(x - top_off(p)) <= catch_reach(p, TOL):
		t.append(snappedf(clampf(x, -SWING, SWING), 0.01))
		add_score(p, 1)
		fx("stack", [p, t.size()])
		if p == 0:
			buzz(1, 0.5, 0.05)
	else:
		fx("tumble", [p, x])


## CPU builders wait for the block to be over their tower (kid-gentle CPUs aim worse and wait longer).
func _cpu_drop(p: int, delta: float) -> bool:
	var w := float(_cpu_wait.get(p, 0.0)) - delta
	_cpu_wait[p] = w
	if w > 0.0:
		return false
	var kid: bool = main.flow != null and main.flow.is_kid()
	if absf(swing_x(p) - top_off(p)) < (0.75 if kid else 0.25) and rng.randf() < (0.07 if kid else 0.35):
		_cpu_wait[p] = rng.randf_range(0.2, 0.7) if kid else 0.15
		return true
	return false


## Every machine: the stacked blocks and the swinging block.
func _place() -> void:
	for i in builders.size():
		var p := builders[i]
		var t: Array = towers.get(p, [])
		var stack: Node3D = _nodes[p]
		if int(_shown.get(p, -1)) != t.size():
			_shown[p] = t.size()
			for c in stack.get_children():
				c.queue_free()
			for k in t.size():
				var bl := _block(p, false)
				bl.position = Vector3(float(t[k]), 0.3 + BLOCK.y * (k + 0.5), 0)
				stack.add_child(bl)
		var sw: Node3D = _swing_nodes[p]
		var h := t.size()
		if dropping.has(p):
			var d: Array = dropping[p]
			var k := 1.0 - float(d[0]) / DROP_T
			sw.position = Vector3(float(d[1]), lerpf(top_y(p) + 1.4, top_y(p), k * k), 0)
		else:
			sw.position = Vector3(swing_x(p), top_y(p) + 1.4, 0)
		sw.visible = h < MAX_H


func snap_extra() -> Array:
	var out: Array = []
	for p in builders:
		out.append([PackedFloat32Array(towers[p]), float(phase[p]), dropping.get(p, [])])
	return [out]


func unsnap_extra(a: Array) -> void:
	if a.is_empty():
		return
	var rows: Array = a[0]
	for i in mini(rows.size(), builders.size()):
		var p := builders[i]
		var r: Array = rows[i]
		var arr: Array = []
		for v in (r[0] as PackedFloat32Array):
			arr.append(v)
		towers[p] = arr
		phase[p] = float(r[1])
		if (r[2] as Array).is_empty():
			dropping.erase(p)
		else:
			dropping[p] = r[2]


func _process(delta: float) -> void:
	super(delta)
	if not host:
		_place()


func on_fx(kind: String, args: Variant) -> void:
	var a: Array = args
	var p := int(a[0])
	var i := builders.find(p)
	if i < 0:
		return
	var base := tower_pos(i)
	match kind:
		"stack":
			var y := 0.3 + BLOCK.y * float(a[1])
			burst_at(base + Vector3(top_off(p), y, 0), color_of(p), 10)
			main.sfx.play("block", -4.0, 0.9 + 0.04 * float(a[1]))
			if avatars.has(p):
				Creatures.anim(avatars[p]).play("cheer", 0.4)
		"tumble":
			main.sfx.play("boing", -6.0, 0.8)
			var bl := _block(p, false)
			add_child(bl)
			var from := base + Vector3(float(a[1]), top_y(p), 0)
			bl.position = from
			var side := 1.0 if float(a[1]) >= top_off(p) else -1.0
			var tw := bl.create_tween()
			tw.tween_method(func(k: float) -> void:
				bl.position = from + Vector3(side * k * 1.5, -k * k * (top_y(p) + 0.5), 0)
				bl.rotation.z = -side * k * 2.5, 0.0, 1.0, 0.6)
			tw.tween_callback(bl.queue_free)


## Bots: press when the block is over the top of your tower.
func cpu_press(pid: int) -> bool:
	return towers.has(pid) and absf(swing_x(pid) - top_off(pid)) < 0.25


func bot_vr_goal() -> Vector3:
	if giant and _swing_nodes.has(0):  # over the middle of the giant's tower: the block swings into the glove
		return tower_pos(0) + Vector3(top_off(0), top_y(0) + 1.4, 0)
	return Vector3(0, 3.0, 1.0)


func touch_goal() -> Vector3:
	return bot_vr_goal() + Vector3(0, 0.5, 0)
