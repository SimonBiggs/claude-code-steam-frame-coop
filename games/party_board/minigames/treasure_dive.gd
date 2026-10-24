extends "res://games/party_board/minigames/mg_base.gd"
## TREASURE DIVE (giant vs islanders): treasure sparkles on the lagoon. Islanders swim over a
## sparkle and press A to DIVE for it (gems 1, chests 3). A shark fin patrols the water: the GIANT
## steers it with a glove (it follows your hand, a bit slower). A surfaced swimmer the shark
## bumps drops a gem and gets dizzy; divers under water are safe.
## Islanders win together with more treasure than twice the giant's bumps. Without a giant the
## shark swims by itself and it's a free-for-all.

const META := {
	"name": "TREASURE DIVE",
	"goal": "Swim to the sparkles and DIVE for treasure! Watch out for the shark: diving keeps you safe.",
	"format": "giant", "time": 40.0, "music": "mystery", "cam": [15.0, 13.0],
	"tv": [["L-STICK", "Swim"], ["A", "Dive (grab treasure, hide from the shark)"]],
	"vr": [["GLOVE", "Steer the shark fin"]],
	"vr_line": "Steer the shark with your glove: bump the swimmers!",
}
const BoardView := preload("res://games/party_board/board_view.gd")
const DIVE_T := 0.9
const BUMP_R := 1.25
const SWIM_Y := -0.55

var shark := Vector3(0, 0, 4.0)
var shark_node: Node3D
var _shark_target := Vector3.ZERO
var diving := {}  # pid -> seconds left under water
var _bump_cd := {}
var _spawn_t := 0.0
var _ai_t := 0.0
var _ai_goal := Vector3.ZERO


func build() -> void:
	arena_r = 6.4
	walk_speed = 4.4
	var mat := ResCache.get_or_make("pb_td_water", func() -> Resource:
		var sh := Shader.new()
		sh.code = BoardView.WATER_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("island_r", 4.0)
		return m)
	var b := MeshKit.Builder.new()
	b.cylinder(arena_r + 2.4, arena_r + 2.8, 1.2, MeshKit.at(Vector3(0, -0.9, 0)), Color(0.93, 0.84, 0.6), 36)
	b.cylinder(arena_r + 1.0, arena_r + 1.0, 0.6, MeshKit.at(Vector3(0, -2.2, 0)), Color(0.85, 0.78, 0.55), 36)
	for k in 10:
		var a := k * TAU / 10.0
		b.sphere(0.7, MeshKit.at(Vector3(cos(a), 0, sin(a)) * (arena_r + 1.9) + Vector3(0, -0.1, 0), Vector3(1.3, 0.6, 1.0)), Color(0.55, 0.52, 0.5), 8)
	add_child(MeshKit.instance(b.build(), false))
	var water := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = arena_r + 1.5
	disc.bottom_radius = arena_r + 1.5
	disc.height = 0.05
	disc.radial_segments = 36
	water.mesh = disc
	water.material_override = mat
	water.position.y = -0.3
	add_child(water)
	add_child(MeshKit.scatter_random(MeshKit.prop("palm"), 5, Vector3.ZERO, arena_r + 2.6, arena_r + 2.0, 0.8, 1.0, PackedColorArray(), 13))
	var fb := MeshKit.Builder.new()
	fb.cone(0.55, 1.3, MeshKit.at(Vector3(0, 0.3, 0), Vector3(0.35, 1.0, 1.0)), Color(0.45, 0.52, 0.6), 8)
	fb.ellipsoid(Vector3(0.6, 0.12, 1.3), MeshKit.at(Vector3(0, -0.25, 0)), Color(0.5, 0.58, 0.66), 10)
	shark_node = MeshKit.instance(fb.build(), false)
	add_child(shark_node)


func make_item(kind: int) -> Node3D:
	var n := Node3D.new()
	var mi := MeshKit.instance(MeshKit.prop("chest" if kind == 1 else "gem"), false)
	mi.scale = Vector3.ONE * (0.9 if kind == 1 else 1.4)
	mi.position.y = -0.2
	n.add_child(mi)
	var ring := MeshKit.Builder.new()
	ring.torus(0.75, 0.06, MeshKit.at(Vector3(0, -0.2, 0)), Color(1, 1, 0.8), 14, 4, true)
	n.add_child(MeshKit.instance(ResCache.get_or_make("pb_td_ring", ring.build), false))
	return n


func start_pos(i: int, n: int) -> Vector3:
	var a := PI + TAU * float(i) / float(maxi(1, n))
	return Vector3(cos(a) * 3.5, SWIM_Y, sin(a) * 3.5 - 1.0)


func on_begin() -> void:
	diving.clear()
	shark = Vector3(0, 0, 4.0)
	for k in 4:
		_spawn()


func _spawn() -> void:
	var a := rng.randf() * TAU
	var r := rng.randf_range(0.8, arena_r - 0.8)
	add_item(1 if rng.randf() < 0.15 else 0, Vector3(cos(a) * r, 0, sin(a) * r))


func play_tick(delta: float) -> void:
	for p in walkers():
		if diving.has(p):
			diving[p] = float(diving[p]) - delta
			var dp: Vector3 = pos[p]
			dp.y = SWIM_Y - 1.4 * sin(clampf(float(diving[p]) / DIVE_T, 0.0, 1.0) * PI)
			pos[p] = dp
			(avatars[p] as Node3D).position = dp
			if float(diving[p]) <= 0.0:
				diving.erase(p)
				_grab(p)
			continue
		var inp := walk(p, delta)
		var wp: Vector3 = pos[p]
		wp.y = SWIM_Y
		pos[p] = wp
		(avatars[p] as Node3D).position = wp
		if bool(inp["pressed"]):
			diving[p] = DIVE_T
			fx("dive", [p, wp])
	separate()
	_spawn_t -= delta
	if _spawn_t <= 0.0 and items.size() < 3 + walkers().size() / 2:
		_spawn_t = 1.0
		_spawn()
	_move_shark(delta)
	if practice:
		return
	for p in walkers():
		_bump_cd[p] = float(_bump_cd.get(p, 0.0)) - delta
		if diving.has(p) or float(_bump_cd[p]) > 0.0 or float(stun.get(p, 0.0)) > 0.0:
			continue
		var wp: Vector3 = pos[p]
		if Vector2(wp.x - shark.x, wp.z - shark.z).length() < BUMP_R:
			_bump_cd[p] = 2.5
			stun[p] = 1.2
			if float(score.get(p, 0.0)) > 0.0:
				score[p] = float(score[p]) - 1.0
			if giant:
				add_score(0, 1)
				buzz(1, 0.8, 0.12)
			fx("bump", [p, wp])
			sound("splash", -2.0, 1.3)


func _move_shark(delta: float) -> void:
	var target := shark
	var speed := 6.0
	if giant:
		var hs := giant_hands()
		if hs.size() >= 2:
			target = Vector3(hs[1].x, 0, hs[1].z)
	else:
		speed = 3.6
		_ai_t -= delta
		if _ai_t <= 0.0:
			_ai_t = 0.8
			var bd := INF
			for p in walkers():
				if diving.has(p):
					continue
				var d := (pos[p] as Vector3).distance_to(shark)
				if d < bd:
					bd = d
					_ai_goal = pos[p]
		target = _ai_goal
	var flat := Vector2(target.x, target.z).limit_length(arena_r)
	target = Vector3(flat.x, 0, flat.y)
	var step := target - shark
	if step.length() > 0.05:
		shark_node.rotation.y = atan2(step.x, step.z)
	shark = shark.move_toward(target, speed * delta)
	shark_node.position = shark


## A diver comes up: the treasure they were over is theirs.
func _grab(p: int) -> void:
	var wp: Vector3 = pos[p]
	for id in items.keys():
		var ip: Vector3 = (items[id] as Node3D).position
		if Vector2(ip.x - wp.x, ip.z - wp.z).length() < 1.2:
			var worth := 3 if int(item_kind[id]) == 1 else 1
			add_score(p, worth)
			fx("treasure", [p, ip, worth])
			remove_item(int(id))
			return


func team_winner() -> int:
	if not giant:
		return -2
	var isl := 0.0
	for p in walkers():
		isl += float(score.get(p, 0.0))
	var g := float(score.get(0, 0.0)) * 2.0
	if isl == g:
		return -1
	return 1 if isl > g else 0


func snap_extra() -> Array:
	return [shark, shark_node.rotation.y]


func unsnap_extra(a: Array) -> void:
	if a.size() >= 2:
		_shark_target = a[0]
		shark_node.rotation.y = lerp_angle(shark_node.rotation.y, float(a[1]), 0.5)


func on_fx(kind: String, args: Variant) -> void:
	var a: Array = args
	match kind:
		"dive":
			burst_at(a[1] + Vector3(0, 0.6, 0), Color(0.75, 0.9, 1.0), 10)
			main.sfx.play("splash", -8.0, 1.4)
		"treasure":
			var p: int = a[0]
			popup_at(a[1], "+%d" % int(a[2]), color_of(p))
			burst_at(a[1] + Vector3(0, 0.5, 0), Color(1.0, 0.9, 0.4), 14)
			main.sfx.play("chest" if int(a[2]) > 1 else "coin", -3.0)
		"bump":
			var p: int = a[0]
			popup_at(a[1], "BUMP!", Color(0.6, 0.8, 1.0))
			burst_at(a[1] + Vector3(0, 0.5, 0), Color(0.8, 0.9, 1.0), 16)
			if avatars.has(p):
				Creatures.anim(avatars[p]).play("hurt", 1.0)


func _process(delta: float) -> void:
	super(delta)
	if not host:
		shark_node.position = shark_node.position.lerp(_shark_target, 1.0 - exp(-12.0 * delta))
	var t := Time.get_ticks_msec() * 0.001
	for id in items:
		var n: Node3D = items[id]
		n.rotation.y = t * 1.5 + float(id)
		n.position.y = 0.08 * sin(t * 3.0 + float(id))


func cpu_move(pid: int) -> Vector3:
	var me := where(pid)
	var best := me
	var bs := INF
	for id in items:
		var ip: Vector3 = (items[id] as Node3D).position
		var s := ip.distance_to(me) - maxf(0.0, 4.0 - ip.distance_to(shark if host else shark_node.position)) * 1.2
		if s < bs:
			bs = s
			best = Vector3(ip.x, 0, ip.z)
	var sh := shark if host else shark_node.position
	var away := Vector3(me.x - sh.x, 0, me.z - sh.z)
	if away.length() < 2.2:
		best = me + away.normalized() * 2.0
	return best


func cpu_press(pid: int) -> bool:
	var me := where(pid)
	var sh := shark if host else shark_node.position
	if Vector2(me.x - sh.x, me.z - sh.z).length() < 1.8 and rng.randf() < 0.15:
		return true  # dive to hide
	for id in items:
		var ip: Vector3 = (items[id] as Node3D).position
		if Vector2(ip.x - me.x, ip.z - me.z).length() < 0.8:
			return rng.randf() < 0.3
	return false


func bot_vr_goal() -> Vector3:
	var best := Vector3(0, 1, 3)
	var bd := INF
	for p in walkers():
		var d := where(p).distance_to(shark)
		if d < bd and not diving.has(p):
			bd = d
			best = where(p) + Vector3(0, 1.0, 0)
	return best
