extends Node3D
## MARBLE MAZE told events (worlds.gd events()): a child of the board, so the rings tilt with it.
##   TILT QUAKE   a flashing orange stripe across the board shows which way, then the board wobbles and every marble
##                is pushed that way for a moment (board.quake; HEAVY / STICKY marbles hardly feel it).
##   CLOSING GATE a red disc pulses on a narrow doorway, then a striped gate pops up there (board.event_gate: a wall)
##                for a few seconds and sinks again. A marble on the doorway is pushed off it to one side.
## Each is told first for the mode's `warn` seconds with core/warn_rings.gd (every machine draws its own: the host
## sends "mev" [kind, a, b, warn, secs, strength] when the warning starts).
##   host: list = def.events; tick(level_t) -> the events whose warning starts now
##   every machine: announce(kind, a, b, warn, secs, strength); clear()

const WarnRings := preload("res://core/warn_rings.gd")
const Worlds := preload("res://games/marble_maze/worlds.gd")
const UiKit := preload("res://core/ui_kit.gd")

var main
var board
var rings: WarnRings
var list: Array = []  # host: this maze's [t, kind, a, b]
var warned := {}
var fired := 0  # host: events told this maze (telemetry)
var zones: Array = []  # every machine: [{kind, a, b, t (s to go), left, strength, node}]
var gate_node: Node3D
var shake := 0.0  # 0..1 while a quake shakes the board (main.gd adds a wobble to the board's tilt)


func _ready() -> void:
	name = "MazeEvents"
	rings = WarnRings.new()
	add_child(rings)


## Host: a new maze's events (lessons, the pick board: none).
func reset(new_list: Array) -> void:
	list = new_list.duplicate(true)
	warned = {}
	fired = 0


## Host: the events whose warning starts now (play seconds `level_t`).
func tick(level_t: float, warn: float) -> Array:
	var out: Array = []
	for i in list.size():
		var e: Array = list[i]
		if not warned.has(i) and level_t >= float(e[0]) - warn:
			warned[i] = true
			fired += 1
			out.append(e)
	return out


## Every machine: rings now, the quake / gate after `warn` seconds.
func announce(kind: String, a: float, b: float, warn: float, secs: float, strength: float) -> void:
	var col: Color = Worlds.EVENT_COLORS.get(kind, Color.WHITE)
	if kind == "gate":
		var c := Vector2i(int(a), int(b))
		var p: Vector2 = board.center(c.x, c.y)
		rings.warn(Vector3(p.x, 0.0, p.y), board.CELL * 0.6, col, warn, 0.004, {"style": "disc", "alpha": 0.5})
	else:
		var dir := Vector2(a, b).normalized()
		var from := -dir * 0.3
		rings.shape("line", Vector3(from.x, 0.0, from.y), Vector3(dir.x, 0.0, dir.y), Vector2(0.6, 0.16), col, warn,
			{"style": "flash", "y": 0.004})
	zones.append({"kind": kind, "a": a, "b": b, "t": warn, "left": secs, "secs": secs, "strength": strength})
	main.sound("tick", -4.0, 0.7 if kind == "gate" else 0.5)


## Every machine: all gone (a new maze, the pick board).
func clear() -> void:
	rings.clear()
	zones.clear()
	shake = 0.0
	if board != null:
		board.quake = Vector2.ZERO
		board.event_gate = Vector2i(-99, -99)
	if gate_node != null and is_instance_valid(gate_node):
		gate_node.queue_free()
	gate_node = null


## Is an event going off (bots)?
func active_kinds() -> Array:
	var out: Array = []
	for z in zones:
		if float(z.t) <= 0.0:
			out.append(String(z.kind))
	return out


func _process(delta: float) -> void:
	var quake := Vector2.ZERO
	var gate := Vector2i(-99, -99)
	shake = 0.0
	for i in range(zones.size() - 1, -1, -1):
		var z: Dictionary = zones[i]
		if float(z.t) > 0.0:
			z.t = float(z.t) - delta
			if float(z.t) <= 0.0:
				main.sound("whirr" if z.kind == "quake" else "gate", -3.0, 0.6 if z.kind == "quake" else 1.4)
			continue
		z.left = float(z.left) - delta
		if z.kind == "quake":
			quake += Vector2(float(z.a), float(z.b)).normalized() * float(z.strength)
			shake = maxf(shake, clampf(float(z.left) / 0.4, 0.0, 1.0))
		else:
			gate = Vector2i(int(z.a), int(z.b))
		if float(z.left) <= 0.0:
			zones.remove_at(i)
	board.quake = quake
	board.event_gate = gate
	_draw_gate(gate, delta)


## The striped gate: pops up from the floor, sinks when it goes.
func _draw_gate(gate: Vector2i, delta: float) -> void:
	if gate.x < 0:
		if gate_node != null and is_instance_valid(gate_node):
			gate_node.scale.y = maxf(0.01, gate_node.scale.y - delta * 4.0)
			if gate_node.scale.y <= 0.02:
				gate_node.queue_free()
				gate_node = null
		return
	var p: Vector2 = board.center(gate.x, gate.y)
	if gate_node == null or not is_instance_valid(gate_node):
		gate_node = Node3D.new()
		add_child(gate_node)
		var h: float = board.WALL_H * 1.1
		for j in 3:  # red / white stripes
			var mi := MeshInstance3D.new()
			mi.mesh = main.box_mesh(Vector3(board.CELL * 0.98, h / 3.0, board.CELL * 0.98))
			mi.material_override = main.make_material(Color(1.0, 0.25, 0.3) if j % 2 == 0 else Color(1, 1, 1), 0.4)
			mi.position.y = h / 6.0 + j * h / 3.0
			gate_node.add_child(mi)
		gate_node.scale.y = 0.05
		main.burst(main.board_world(p, 0.03), Color(1.0, 0.3, 0.3), 12, false)
	gate_node.position = Vector3(p.x, 0.0, p.y)
	gate_node.scale.y = minf(1.0, gate_node.scale.y + delta * 5.0)
