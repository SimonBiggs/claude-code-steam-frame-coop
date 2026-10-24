extends "res://games/party_board/minigames/mg_base.gd"
## SHEEP HERDING (team game, RED vs BLUE): fluffy sheep wander the meadow and run away from
## whoever comes close. Herd them into your team's pen (RED on the left of the TV, BLUE on the
## right). The GIANT can pick a sheep up (glove + TRIGGER), carry it and let go over the pen,
## but sheep wriggle free after a few seconds.

const META := {
	"name": "SHEEP HERDING",
	"goal": "Chase the sheep into your team's pen! They run away from you.",
	"format": "teams", "time": 45.0, "music": "cosy", "cam": [15.0, 13.0],
	"tv": [["L-STICK", "Run behind the sheep to push them"]],
	"vr": [["GLOVE + TRIGGER", "Pick up a sheep"], ["LET GO", "Drop it in your pen"]],
	"vr_line": "Grab sheep with the TRIGGER, drop them in your pen!",
}
const SHEEP := 6
const PEN_X := 5.7
const PEN_IN := 5.0
const PEN_HALF := 1.9
const FLEE_R := 2.3

var vel := {}  # id -> Vector3 (host)
var carried := -1  # sheep id in the giant's glove
var _carry_t := 0.0
var _wander := {}  # id -> Vector3
var _last_p := {}  # id -> Vector3 (every machine: facing)
var _respawn: Array[float] = []  # seconds until each penned sheep is replaced


func build() -> void:
	arena_r = 7.0
	build_island(8.0, Color(0.52, 0.8, 0.4))
	var b := MeshKit.Builder.new()
	for team in 2:
		var sx := pen_x(team)
		var c: Color = main.runner.TEAM_COLORS[team]
		b.box(Vector3(2.6, 0.06, PEN_HALF * 2.0), MeshKit.at(Vector3(sx, 0.03, 0)), c.lightened(0.35))
		# Fence on three sides, open towards the middle.
		var outer := sx + signf(sx) * 1.3
		for k in 6:
			var z := -PEN_HALF + k * (PEN_HALF * 2.0 / 5.0)
			b.box(Vector3(0.14, 0.9, 0.14), MeshKit.at(Vector3(outer, 0.45, z)), Color(0.95, 0.92, 0.85))
		b.box(Vector3(0.08, 0.12, PEN_HALF * 2.0), MeshKit.at(Vector3(outer, 0.75, 0)), Color(0.95, 0.92, 0.85))
		for zs in [-1.0, 1.0]:
			b.box(Vector3(2.6, 0.12, 0.08), MeshKit.at(Vector3(sx, 0.75, zs * PEN_HALF)), Color(0.95, 0.92, 0.85))
			b.box(Vector3(0.14, 0.9, 0.14), MeshKit.at(Vector3(sx - signf(sx) * 1.3, 0.45, zs * PEN_HALF)), Color(0.95, 0.92, 0.85))
		b.box(Vector3(0.1, 1.0, 0.8), MeshKit.at(Vector3(outer, 1.6, 0)), c, true)
	add_child(MeshKit.instance(b.build(), false))


## Team 0 (RED) is on the TV's left (+X), team 1 (BLUE) on the right.
func pen_x(team: int) -> float:
	return PEN_X if team == 0 else -PEN_X


func in_pen(p: Vector3) -> int:
	if absf(p.z) < PEN_HALF and absf(p.x) > PEN_IN:
		return 0 if p.x > 0.0 else 1
	return -1


func make_item(_kind: int) -> Node3D:
	return Creatures.monster("sheep", {"scale": 1.1, "lod": "far"})


func start_pos(i: int, n: int) -> Vector3:
	var ws := walkers()
	var p: int = ws[i] if i < ws.size() else 0
	var team := int(teams.get(p, 0))
	return Vector3(pen_x(team) * 0.55, 0, (float(i) - float(n) * 0.5) * 1.1)


func on_begin() -> void:
	carried = -1
	_respawn.clear()
	for k in SHEEP:
		_new_sheep()


func _new_sheep() -> void:
	var p := Vector3(rng.randf_range(-2.0, 2.0), 0, rng.randf_range(-3.0, 3.0))
	var id := add_item(0, p)
	vel[id] = Vector3.ZERO
	_wander[id] = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))


func play_tick(delta: float) -> void:
	for p in walkers():
		walk(p, delta)
	separate()
	if practice:
		if items.is_empty():
			for k in 3:
				_new_sheep()
	_giant_hands(delta)
	for i in range(_respawn.size() - 1, -1, -1):
		_respawn[i] -= delta
		if _respawn[i] <= 0.0:
			_respawn.remove_at(i)
			_new_sheep()
	for id in items.keys():
		if int(id) == carried:
			continue
		var n: Node3D = items[id]
		var p := n.position
		var v: Vector3 = vel.get(id, Vector3.ZERO)
		var push := Vector3.ZERO
		for w in walkers():
			var d: Vector3 = p - (pos[w] as Vector3)
			d.y = 0.0
			var l := d.length()
			if l < FLEE_R and l > 0.01:
				push += d / l * (FLEE_R - l) * 3.2
		for o in items:
			if o == id or int(o) == carried:
				continue
			var d2: Vector3 = p - (items[o] as Node3D).position
			d2.y = 0.0
			if d2.length() < 1.0 and d2.length() > 0.01:
				push += d2.normalized() * (1.0 - d2.length()) * 4.0
		if randf() < delta * 0.5:
			_wander[id] = Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
		push += (_wander[id] as Vector3) * 0.5
		v = v.lerp(push.limit_length(3.2), 1.0 - exp(-4.0 * delta))
		p += v * delta
		if p.y > 0.0:
			p.y = maxf(0.0, p.y - 9.0 * delta)
		var flat := Vector2(p.x, p.z).limit_length(arena_r - 0.4)
		p = Vector3(flat.x, p.y, flat.y)
		vel[id] = v
		n.position = p
		var team := in_pen(p)
		if team >= 0 and p.y < 0.3 and not practice:
			_score(int(id), team)


## The giant picks a sheep up with a glove + trigger and drops it by letting go.
func _giant_hands(delta: float) -> void:
	if not giant or main.vr_rig == null:
		return
	var hs := giant_hands()
	if hs.size() < 2:
		return
	var rig: Node = main.vr_rig
	if carried >= 0 and items.has(carried):
		_carry_t += delta
		var n: Node3D = items[carried]
		n.position = hs[1] + Vector3(0, -0.9, 0)
		if not rig.trigger_down() or _carry_t > 3.0:
			if _carry_t > 3.0:
				fx("wriggle", [n.position])
			vel[carried] = Vector3.ZERO
			carried = -1
			buzz(1, 0.3, 0.05)
		return
	carried = -1
	if rig.trigger_pressed():
		for id in items:
			if (items[id] as Node3D).position.distance_to(hs[1]) < HAND_R + 0.6:
				carried = int(id)
				_carry_t = 0.0
				buzz(1, 0.6, 0.08)
				sound("boing", -8.0, 0.8)
				break


func _score(id: int, team: int) -> void:
	var p: Vector3 = (items[id] as Node3D).position
	var who := -1
	var bd := INF
	for q in pids:
		if int(teams.get(q, 0)) != team:
			continue
		var d := (where(q) if not (giant and q == 0) else Vector3(0, 0, 9)).distance_to(p)
		if d < bd:
			bd = d
			who = q
	if who >= 0:
		add_score(who, 1)
	fx("penned", [p, team])
	remove_item(id)
	vel.erase(id)
	_wander.erase(id)
	_respawn.append(2.0)


func team_winner() -> int:
	var t := [0.0, 0.0]
	for p in pids:
		t[int(teams.get(p, 0))] += float(score.get(p, 0.0))
	if t[0] == t[1]:
		return -1
	return 0 if t[0] > t[1] else 1


func on_fx(kind: String, args: Variant) -> void:
	var a: Array = args
	match kind:
		"penned":
			var p: Vector3 = a[0]
			var c: Color = main.runner.TEAM_COLORS[int(a[1])]
			burst_at(p + Vector3(0, 1.0, 0), c, 18)
			popup_at(p, "BAA! +1", c)
			main.sfx.play("cheer", -6.0)
			main.sfx.play("ding", -4.0)
		"wriggle":
			popup_at(a[0], "WRIGGLE!", Color(1, 1, 1))


func _process(delta: float) -> void:
	super(delta)
	for id in items:
		var n: Node3D = items[id]
		var prev: Vector3 = _last_p.get(id, n.position)
		var d := n.position - prev
		d.y = 0.0
		var a := Creatures.anim(n)
		if d.length() > 0.002:
			a.face(d)
		a.walk(d.length() / maxf(delta, 0.001))
		_last_p[id] = n.position


func cpu_move(pid: int) -> Vector3:
	var team := int(teams.get(pid, 0))
	var pen := Vector3(pen_x(team), 0, 0)
	var me := where(pid)
	var best := -1
	var bs := INF
	for id in items:
		var p: Vector3 = (items[id] as Node3D).position
		var s := p.distance_to(pen) * 0.6 + p.distance_to(me)
		if s < bs:
			bs = s
			best = int(id)
	if best < 0:
		return me
	var sp: Vector3 = (items[best] as Node3D).position
	var away := sp - pen
	away.y = 0.0
	return sp + away.normalized() * 1.5


func bot_vr_goal() -> Vector3:
	if carried >= 0:
		var team := int(teams.get(0, 0))
		return Vector3(pen_x(team), 2.0, 0)
	var best := Vector3(0, 2, 2)
	var bd := INF
	for id in items:
		var p: Vector3 = (items[id] as Node3D).position
		var d := p.length()
		if d < bd:
			bd = d
			best = p + Vector3(0, 0.8, 0)
	return best
