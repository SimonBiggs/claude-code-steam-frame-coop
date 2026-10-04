extends "res://games/party_board/minigames/mg_base.gd"
## BALLOON POP (team game, RED vs BLUE): balloons float up out of the meadow. Islanders jump and
## pop the low ones with A; the GIANT swats the ones that get away higher up with a glove. Every
## pop scores for your team (gold balloons score 3). Most pops wins.

const META := {
	"name": "BALLOON POP",
	"goal": "Pop the balloons for your team! Gold ones are worth 3.",
	"format": "teams", "time": 40.0, "music": "party", "cam": [15.0, 13.0],
	"tv": [["L-STICK", "Run to a balloon"], ["A", "Jump and POP it"]],
	"vr": [["GLOVES", "Swat balloons up high"]],
	"vr_line": "SWAT the balloons that float up high!",
}
const LOW := 2.6
const TOP := 9.5
const BALLOON_COLORS := [Color(1.0, 0.35, 0.4), Color(0.4, 0.7, 1.0), Color(0.5, 0.9, 0.4), Color(1.0, 0.6, 0.9), Color(0.75, 0.55, 1.0)]

var _spawn_t := 0.0
var _jump := {}  # pid -> cooldown


func build() -> void:
	arena_r = 6.5
	build_island(7.5, Color(0.5, 0.8, 0.4))


func make_item(kind: int) -> Node3D:
	var b := MeshKit.Builder.new()
	var c: Color = Color(1.0, 0.82, 0.25) if kind == 5 else BALLOON_COLORS[kind % BALLOON_COLORS.size()]
	b.ellipsoid(Vector3(0.6, 0.72, 0.6), MeshKit.at(Vector3(0, 0, 0)), c, 12, kind == 5)
	b.cone(0.12, 0.14, MeshKit.at(Vector3(0, -0.74, 0), Vector3.ONE, Vector3(PI, 0, 0)), c.darkened(0.2), 6)
	b.cylinder(0.015, 0.015, 1.1, MeshKit.at(Vector3(0, -1.35, 0)), Color(0.95, 0.95, 0.95), 4)
	return MeshKit.instance(ResCache.get_or_make("pb_balloon_%d" % kind, b.build), false)


func team_color(pid: int) -> Color:
	return main.runner.TEAM_COLORS[int(teams.get(pid, 0))]


func play_tick(delta: float) -> void:
	for p in walkers():
		var inp := walk(p, delta)
		_jump[p] = float(_jump.get(p, 0.0)) - delta
		if bool(inp["pressed"]) and float(_jump[p]) <= 0.0:
			_jump[p] = 0.45
			fx("jump", [p])
			_try_pop(p)
	separate()
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = rng.randf_range(0.45, 0.8) * (0.8 if walkers().size() > 4 else 1.0)
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.5, arena_r - 0.6)
		add_item(5 if rng.randf() < 0.1 else rng.randi() % 5, Vector3(cos(a) * r, 0.6, sin(a) * r))
	var hs := giant_hands()
	for id in items.keys():
		var n: Node3D = items[id]
		var p := n.position
		p.y += (0.85 if p.y < LOW else 1.5) * delta
		p.x += sin(play_t * 1.3 + float(id)) * 0.25 * delta
		n.position = p
		if p.y > TOP:
			remove_item(int(id))
			continue
		if giant and p.y > LOW - 0.4:
			for h in hs.size():
				if hs[h].distance_to(p) < HAND_R + 0.35:
					_pop(int(id), 0)
					buzz(h, 0.5, 0.05)
					break


func _try_pop(pid: int) -> void:
	var me: Vector3 = pos[pid]
	var best := -1
	var bd := 1.4
	for id in items:
		var p: Vector3 = (items[id] as Node3D).position
		if p.y > LOW:
			continue
		var d := Vector2(p.x - me.x, p.z - me.z).length()
		if d < bd:
			bd = d
			best = int(id)
	if best >= 0:
		_pop(best, pid)


func _pop(id: int, pid: int) -> void:
	var worth := 3 if int(item_kind[id]) == 5 else 1
	add_score(pid, worth)
	fx("pop", [(items[id] as Node3D).position, pid, worth])
	remove_item(id)


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
		"jump":
			if avatars.has(int(a[0])):
				Creatures.anim(avatars[int(a[0])]).play("jump", 0.4)
		"pop":
			var p: Vector3 = a[0]
			var pid: int = a[1]
			burst_at(p, team_color(pid), 12)
			popup_at(p + Vector3(0, -1.0, 0), "+%d" % int(a[2]), team_color(pid))
			main.sfx.play("pop", -2.0, 1.0 + randf() * 0.3)


func _process(delta: float) -> void:
	super(delta)
	if not host:
		return
	for p in walkers():  # hop a little while jumping
		var a: Node3D = avatars[p]
		var cd := float(_jump.get(p, 0.0))
		a.position.y = maxf(0.0, sin(clampf(cd / 0.45, 0.0, 1.0) * PI) * 1.0)


func cpu_move(pid: int) -> Vector3:
	var me := where(pid)
	var best := me
	var bd := INF
	for id in items:
		var p: Vector3 = (items[id] as Node3D).position
		if p.y > LOW - 0.3:
			continue
		var d := Vector2(p.x - me.x, p.z - me.z).length() + p.y
		if d < bd:
			bd = d
			best = Vector3(p.x, 0, p.z)
	return best


func cpu_press(pid: int) -> bool:
	var me := where(pid)
	for id in items:
		var p: Vector3 = (items[id] as Node3D).position
		if p.y < LOW and Vector2(p.x - me.x, p.z - me.z).length() < 1.1:
			return rng.randf() < 0.25
	return false


func bot_vr_goal() -> Vector3:
	var best := Vector3(0, 5, 2)
	var by := -INF
	for id in items:
		var p: Vector3 = (items[id] as Node3D).position
		if p.y > LOW and p.y > by:
			by = p.y
			best = p
	return best
