extends "res://games/party_board/minigames/mg_base.gd"
## MOLE BOP (free for all; from the arcade's Whack-a-Mole): moles pop up out of the holes in the garden. Run
## onto a mole to BOP it (gold moles are worth 3) - just the stick, no buttons, so the littlest can play. The
## GIANT bops them with a glove. More players = more moles up at once (everyone gets about the same chances,
## tests/party_board_mg_test.gd), and a mole stays up long enough for a slow little runner.

const META := {
	"name": "MOLE BOP",
	"goal": "Run onto the moles to bop them! Gold moles are worth 3.",
	"format": "ffa", "time": 25.0, "music": "party", "cam": [14.0, 12.0],
	"tv": [["L-STICK", "Run onto a mole"]],
	"vr": [["GLOVE", "Bop the moles"]],
	"vr_line": "BOP the moles with your gloves!",
	"cue": "catch",
}
const HOLE_R := 2.6  ## the ring of holes
const UP_T := 2.4  ## seconds a mole stays up
const BOP_R := 0.95
const DOWN_Y := -0.9
const UP_Y := 0.05

var holes: Array[Vector3] = []
var _up := {}  # item id -> [hole index, seconds left]
var _spawn_t := 0.0
var _hole_busy := {}  # hole index -> item id
var _giant_cd := 0.0
const GIANT_CD := 1.1


func build() -> void:
	arena_r = 5.6
	walk_speed = 5.0
	build_island(arena_r + 1.0, Color(0.48, 0.76, 0.36))
	holes.clear()
	holes.append(Vector3.ZERO)
	for k in 8:
		var a := k * TAU / 8.0 + 0.2
		holes.append(Vector3(cos(a), 0, sin(a)) * HOLE_R)
	for k in 4:
		var a := k * TAU / 4.0 + 0.8
		holes.append(Vector3(cos(a), 0, sin(a)) * (HOLE_R + 2.1))
	var b := MeshKit.Builder.new()
	for h in holes:
		b.cylinder(0.62, 0.7, 0.12, MeshKit.at(h + Vector3(0, 0.02, 0)), Color(0.55, 0.38, 0.22), 14)
		b.cylinder(0.45, 0.45, 0.06, MeshKit.at(h + Vector3(0, 0.07, 0)), Color(0.12, 0.08, 0.06), 14)
	add_child(MeshKit.instance(b.build(), false))


func start_pos(i: int, n: int) -> Vector3:
	var a := TAU * float(i) / float(maxi(1, n)) + 0.6
	return Vector3(cos(a), 0, sin(a)) * 4.0


func make_item(kind: int) -> Node3D:
	return MeshKit.instance(ResCache.get_or_make("pb_mole_%d" % kind, func() -> Resource:
		var b := MeshKit.Builder.new()
		var fur := Color(1.0, 0.8, 0.25) if kind == 1 else Color(0.5, 0.36, 0.28)
		b.capsule_between(Vector3(0, -0.2, 0), Vector3(0, 0.55, 0), 0.38, fur, 10)
		b.sphere(0.16, MeshKit.at(Vector3(0, 0.45, 0.33)), Color(1.0, 0.6, 0.65), 8)
		b.sphere(0.07, MeshKit.at(Vector3(-0.15, 0.68, 0.3)), Color(0.1, 0.08, 0.1), 6)
		b.sphere(0.07, MeshKit.at(Vector3(0.15, 0.68, 0.3)), Color(0.1, 0.08, 0.1), 6)
		b.box(Vector3(0.14, 0.12, 0.05), MeshKit.at(Vector3(0, 0.3, 0.37)), Color(1, 1, 1))
		if kind == 1:
			for k in 3:
				b.cone(0.07, 0.18, MeshKit.at(Vector3(-0.14 + k * 0.14, 0.98, 0)), Color(1.0, 0.95, 0.5), 5, true)
		return b.build()), false)


func on_begin() -> void:
	_up.clear()
	_hole_busy.clear()
	_spawn_t = 0.0


## How many moles are up at once: more players, more moles (about two per player's worth of chances).
func want_up() -> int:
	return clampi(1 + (walkers().size() + (1 if giant else 0) + 1) / 2, 2, 5)


func play_tick(delta: float) -> void:
	for p in walkers():
		walk(p, delta)
	separate()
	_spawn_t -= delta
	if _spawn_t <= 0.0 and _up.size() < want_up():
		_spawn_t = 0.35
		var free: Array = []
		for i in holes.size():
			if not _hole_busy.has(i):
				free.append(i)
		if not free.is_empty():
			var hi: int = free[rng.randi() % free.size()]
			var lag := lagging_walker()
			if main.simple and lag >= 0 and rng.randf() < 0.5:  # SIMPLE: half pop up near whoever is behind
				var lp: Vector3 = pos.get(lag, Vector3.ZERO)
				free.sort_custom(func(a: int, b: int) -> bool: return holes[a].distance_to(lp) < holes[b].distance_to(lp))
				hi = free[0]
			var id := add_item(1 if rng.randf() < 0.12 else 0, holes[hi] + Vector3(0, DOWN_Y, 0))
			_up[id] = [hi, UP_T]
			_hole_busy[hi] = id
	var hs := giant_hands()
	for id in _up.keys():
		var u: Array = _up[id]
		u[1] = float(u[1]) - delta
		var n: Node3D = items[id]
		var t := float(u[1])
		var k := clampf(minf(UP_T - t, t) / 0.25, 0.0, 1.0)  # pops up, waits, ducks down
		n.position.y = lerpf(DOWN_Y, UP_Y, k)
		if t <= 0.0:
			_down(int(id))
			continue
		if k < 0.6:
			continue
		var hp: Vector3 = holes[int(u[0])]
		var who := -1
		var best := 1.0  # the nearest, measured in each walker's own reach (whoever is behind reaches further)
		for p in walkers():
			var d := Vector2((pos[p] as Vector3).x - hp.x, (pos[p] as Vector3).z - hp.z).length() / catch_reach(p, BOP_R)
			if d < best and float(stun.get(p, 0.0)) <= 0.0:
				best = d
				who = p
		_giant_cd -= delta
		if who < 0 and giant and _giant_cd <= 0.0:  # (the giant's arm waits a moment between bops)
			for h in hs.size():
				if hs[h].distance_to(hp + Vector3(0, 0.4, 0)) < HAND_R:
					who = 0
					_giant_cd = GIANT_CD
					buzz(h, 0.6, 0.06)
					break
		if who >= 0:
			var worth := 3 if int(item_kind[id]) == 1 else 1
			add_score(who, worth)
			fx("bop", [hp, who, worth])
			_down(int(id))


func _down(id: int) -> void:
	if _up.has(id):
		_hole_busy.erase(int((_up[id] as Array)[0]))
	_up.erase(id)
	remove_item(id)


func on_fx(kind: String, args: Variant) -> void:
	var a: Array = args
	if kind == "bop":
		var p: Vector3 = a[0]
		var pid := int(a[1])
		burst_at(p + Vector3(0, 0.5, 0), color_of(pid), 12)
		popup_at(p, "+%d" % int(a[2]), color_of(pid))
		main.sfx.play("boing", -2.0, 1.1 + randf() * 0.3)
		if avatars.has(pid):
			Creatures.anim(avatars[pid]).play("jump", 0.4)


func cpu_move(pid: int) -> Vector3:
	var me := where(pid)
	var best := me
	var bd := INF
	for id in _up:
		var hp: Vector3 = holes[int((_up[id] as Array)[0])]
		var d := Vector2(hp.x - me.x, hp.z - me.z).length() - float((_up[id] as Array)[1]) * 0.5
		if d < bd:
			bd = d
			best = hp
	return best


func bot_vr_goal() -> Vector3:
	for id in _up:
		return holes[int((_up[id] as Array)[0])] + Vector3(0, 0.4, 0)
	return Vector3(0, 2.0, 1.5)


func touch_goal() -> Vector3:
	var g := bot_vr_goal()
	return g + Vector3(0, 1.0, 0)
