extends "res://games/party_board/minigames/mg_base.gd"
## HOT POTATO (free for all): a fizzing bomb jumps from player to player when they touch.
## Holding it when it goes BOOM = dizzy for a moment, and everyone else scores a point.
## Islanders pass it by running into someone (or press A to toss it to the nearest player).
## The GIANT plays with a big glove-pawn on the island: it follows the right glove (a bit slower than
## your hand), so the giant passes the bomb by touching someone with it, and runs away the same way.

const META := {
	"name": "HOT POTATO",
	"goal": "Don't hold the bomb when it goes BOOM! Touch someone to pass it on.",
	"format": "ffa", "time": 45.0, "music": "tension", "cam": [15.0, 13.0],
	"tv": [["L-STICK", "Run"], ["A", "Toss the bomb to the nearest player"]],
	"vr": [["RIGHT GLOVE", "Move your glove-pawn"], ["TOUCH", "Pass the bomb"]],
	"vr_line": "Move your glove: touch someone to pass the bomb!",
}
const PASS_R := 1.15
const TOSS_R := 3.6

var holder := -1
var fuse := 0.0
var fuse_max := 8.0
var _gap := 0.0  # seconds without a bomb (after a boom)
var _pass_cd := 0.0
var _last_giver := -1
var _giver_t := 0.0
var bomb: Node3D
var _fuse_frac := 0.0  # every machine: for the ticking and flashing
var _tick_t := 0.0
var _flash := 0.0


func build() -> void:
	arena_r = 6.0
	use_pawn = true
	pawn_speed = 7.5
	build_island(arena_r + 1.0, Color(0.62, 0.72, 0.36))
	var b := MeshKit.Builder.new()
	b.sphere(0.55, MeshKit.at(Vector3.ZERO), Color(0.12, 0.12, 0.16), 14)
	b.cylinder(0.14, 0.18, 0.3, MeshKit.at(Vector3(0, 0.6, 0)), Color(0.4, 0.4, 0.45), 8)
	b.sphere(0.13, MeshKit.at(Vector3(0, 0.82, 0)), Color(1.0, 0.6, 0.15), 8, true)
	b.sphere(0.12, MeshKit.at(Vector3(0.22, 0.2, 0.42)), Color(1, 1, 1), 6)
	bomb = MeshKit.instance(b.build(), false)
	bomb.visible = false
	add_child(bomb)


## A player's spot: walkers, or the giant's pawn.
func spot(pid: int) -> Vector3:
	if giant and pid == 0:
		return pawn
	return where(pid)


func on_begin() -> void:
	holder = -1
	_gap = 1.0


func play_tick(delta: float) -> void:
	for p in walkers():
		var inp := walk(p, delta)
		if p == holder and bool(inp["pressed"]):
			_toss(p)
	separate()
	if giant and float(stun.get(0, 0.0)) <= 0.0:
		update_pawn(delta)
	elif giant:
		stun[0] = float(stun[0]) - delta
	_giver_t -= delta
	_pass_cd -= delta
	if holder < 0:
		_gap -= delta
		if _gap <= 0.0:
			var alive: Array = pids.filter(func(p: int) -> bool: return float(stun.get(p, 0.0)) <= 0.0)
			if alive.is_empty():
				alive = pids.duplicate()
			_give(int(alive[rng.randi() % alive.size()]), -1)
			fuse_max = rng.randf_range(6.0, 10.0)
			fuse = fuse_max
			sound("ui_notify", -4.0, 0.8)
		return
	fuse -= delta
	if fuse <= 0.0:
		_boom()
		return
	if _pass_cd <= 0.0:
		var hp := spot(holder)
		for p in pids:
			if p == holder or (p == _last_giver and _giver_t > 0.0) or float(stun.get(p, 0.0)) > 0.0:
				continue
			if Vector2(spot(p).x - hp.x, spot(p).z - hp.z).length() < PASS_R + (0.5 if giant and (p == 0 or holder == 0) else 0.0):
				_give(p, holder)
				break


func _toss(from: int) -> void:
	var best := -1
	var bd := TOSS_R
	for p in pids:
		if p == from or float(stun.get(p, 0.0)) > 0.0:
			continue
		var d := spot(p).distance_to(spot(from))
		if d < bd:
			bd = d
			best = p
	if best >= 0 and _pass_cd <= 0.0:
		_give(best, from)


func _give(to: int, from: int) -> void:
	holder = to
	_last_giver = from
	_giver_t = 0.8
	_pass_cd = 0.3
	if to == 0 and giant:
		buzz(1, 0.6, 0.1)
	if from >= 0:
		sound("boing", -6.0, 1.2)
		fx("pass", [to])


func _boom() -> void:
	var at := spot(holder)
	for p in pids:
		if p != holder:
			add_score(p, 1)
	stun[holder] = 2.0
	if holder == 0 and giant:
		buzz(1, 1.0, 0.3)
	fx("boom", [at, holder])
	sound("explosion", -2.0)
	holder = -1
	_gap = 1.5


func snap_extra() -> Array:
	return [holder, fuse / maxf(fuse_max, 0.1)]


func unsnap_extra(a: Array) -> void:
	if a.size() >= 2:
		holder = int(a[0])
		_fuse_frac = float(a[1])


func on_fx(kind: String, args: Variant) -> void:
	var a: Array = args
	match kind:
		"boom":
			var p: Vector3 = a[0]
			burst_at(p + Vector3(0, 1.0, 0), Color(1.0, 0.55, 0.2), 26)
			burst_at(p + Vector3(0, 1.4, 0), Color(0.3, 0.3, 0.3), 14)
			popup_at(p, "BOOM!", Color(1.0, 0.4, 0.2))
			_flash = 1.0
			if main.cam != null:
				main.cam.shake(0.35)
			var w: int = a[1]
			if avatars.has(w):
				Creatures.anim(avatars[w]).play("hurt", 1.5)
		"pass":
			var to: int = a[0]
			if avatars.has(to):
				Creatures.anim(avatars[to]).play("jump", 0.4)


func _process(delta: float) -> void:
	super(delta)
	if host:
		_fuse_frac = fuse / maxf(fuse_max, 0.1) if holder >= 0 else 0.0
	bomb.visible = holder >= 0
	if holder >= 0:
		var at := pawn_node.position if (giant and holder == 0 and pawn_node != null) else (avatars[holder] as Node3D).position if avatars.has(holder) else Vector3.ZERO
		var want := at + Vector3(0, 1.4 if giant and holder == 0 else 2.6, 0)
		bomb.position = bomb.position.lerp(want, 1.0 - exp(-18.0 * delta))
		var pulse := 1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.001 * (6.0 + 20.0 * (1.0 - _fuse_frac)))
		bomb.scale = Vector3.ONE * 1.25 * pulse
		_tick_t -= delta
		if _tick_t <= 0.0:
			_tick_t = lerpf(0.18, 0.7, clampf(_fuse_frac, 0.0, 1.0))
			main.sfx.play("tick", -12.0, 1.0 + (1.0 - _fuse_frac) * 0.5)


func cpu_move(pid: int) -> Vector3:
	var me := spot(pid)
	if holder == pid:
		var best := Vector3.ZERO
		var bd := INF
		for p in pids:
			if p != pid and float(stun.get(p, 0.0)) <= 0.0:
				var d := spot(p).distance_to(me)
				if d < bd:
					bd = d
					best = spot(p)
		return best
	if holder < 0:
		return me
	var away := me - spot(holder)
	away.y = 0.0
	if away.length() > 5.0:
		return me + Vector3(sin(play_t * 1.3 + pid), 0, cos(play_t + pid)) * 0.8
	var target := me + away.normalized() * 3.0
	if Vector2(target.x, target.z).length() > arena_r - 0.5:  # cornered: slide along the edge
		var t2 := Vector3(-away.z, 0, away.x).normalized() * 3.0
		target = me + t2
	return target


func cpu_press(pid: int) -> bool:
	return holder == pid and rng.randf() < 0.05


func bot_vr_goal() -> Vector3:
	return cpu_move(0) + Vector3(0, 1.0, 0)
