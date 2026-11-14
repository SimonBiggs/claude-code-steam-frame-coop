extends RefCounted
## SKY BOTS: a robot that plays by itself, following the island's route (levelgen.gd "route"): CPU buddies BIP and BOP
## (solo VR: the giant plays with them) and the test bots' pads (tests/sky_bots_bot.gd turns out_move into a stick).
## Walks to each step, hops at a floor's edge or up a step, waits for a mover to come close and a lift to come down
## (then rides it up), waits while a zap pad ahead flashes or buzzes, punches grumbles in front of it, punches the
## cracked wall open and grabs the gold gear, and on Crab Cove keeps clear of Cranky Crab's stomp and punches it while
## it's dizzy. out_* are this frame's wishes; the robot (or the bot's pad) does the moving.

const G := preload("res://games/sky_bots/levelgen.gd")

var k := 0  ## route step
var out_move := Vector3.ZERO
var out_jump := false
var out_hold := false
var out_punch := false
var stuck_t := 0.0
var step_t := 0.0
var warps := 0  ## times a CPU buddy was so stuck it hopped ahead (host; telemetry, bots)
var _last := Vector3.INF
var _punch_cd := 0.0
var _wait_t := 0.0


func reset() -> void:
	k = 0
	stuck_t = 0.0
	step_t = 0.0
	_last = Vector3.INF


## After a pop-back to checkpoint cp: back to the first step on that flag's floor.
func respawned(lv: Dictionary, cp: int) -> void:
	var cps: Array = lv.get("cps", [])
	if cp < 0 or cp >= cps.size():
		k = 0
		return
	var plat := int(cps[cp][0])
	var cx := float((cps[cp][1] as Vector3).x)
	var route: Array = lv.route
	for i in route.size():
		var st: Dictionary = route[i]
		if int(st.p) == plat or float((st.to as Vector3).x) >= cx:
			k = i
			return


## The point of route step i right now (a mover's / lift's middle rides along with it).
func target(level: Node, i: int) -> Vector3:
	var st: Dictionary = level.lv.route[i]
	var p := int(st.p)
	if level.movers.has(p):
		return level.plat_pos(p)
	return st.to


func think(r: Node3D, level: Node, boss: Node, delta: float) -> void:
	out_move = Vector3.ZERO
	out_jump = false
	out_hold = false
	out_punch = false
	_punch_cd = maxf(0.0, _punch_cd - delta)
	var lv: Dictionary = level.lv
	var route: Array = lv.get("route", [])
	if route.is_empty():
		return
	k = clampi(k, 0, route.size() - 1)
	var st: Dictionary = route[k]
	var plats: Array = lv.plats
	var tp := target(level, k)
	var pos := r.position
	var on: int = level.support(pos + Vector3.UP * 0.05, 0.3, 0.3) if r.is_on_floor() else -1
	var want := int(st.p)
	var act := String(st.act)
	step_t += delta
	# Stuck? (no headway for a while) hop; a CPU buddy that's really stuck hops ahead to its next step.
	if _last == Vector3.INF or pos.distance_to(_last) > 0.6:
		_last = pos
		stuck_t = 0.0
	else:
		stuck_t += delta
	_punch_grumbles(r, level)
	if act == "boss" and on == want and boss != null and boss.alive():
		_fight(r, level, boss, delta)
		return
	if on == want:
		var flat := Vector3(tp.x - pos.x, 0.0, tp.z - pos.z)
		var arrived := flat.length() < 0.45
		match act:
			"board":  # on the mover: stay in its middle until it reaches the far side
				out_move = _toward(flat, 0.3)
				var p: Dictionary = plats[want]
				if level.plat_pos(want).distance_to(p.b) < 0.35:
					_next(route)
				return
			"ride_up":  # on the lift: wait for the top
				out_move = _toward(flat, 0.3)
				var p2: Dictionary = plats[want]
				if level.plat_pos(want).y >= float((p2.b as Vector3).y) - 0.15:
					_next(route)
				return
			"punch":
				out_move = _toward(flat, 0.2)
				if arrived or flat.length() < 0.9:
					r.rotation.y = lerp_angle(r.rotation.y, PI, 0.5)  # face the wall (-Z)
					if _punch_cd <= 0.0:
						out_punch = true
						_punch_cd = 0.5
					if level.wall_broken:
						_next(route)
				return
			"gear":
				out_move = _toward(flat, 0.1)
				if level.gear_got or arrived or step_t > 6.0:
					_next(route)
				return
			"goal":
				out_move = _toward(flat, 0.0)
				return
		out_move = _toward(flat, 0.0)
		if _zap_wait(pos, flat, level):
			out_move = Vector3.ZERO
		if arrived:
			_next(route)
		return
	# Not on the step's floor yet: get there.
	if not r.is_on_floor():
		var f := Vector3(tp.x - pos.x, 0.0, tp.z - pos.z)
		out_move = _toward(f, 0.5 if level.support(Vector3(tp.x, tp.y + 0.05, tp.z), 0.3, 0.3) == want else 0.0)
		out_hold = tp.y > pos.y - 0.2 or f.length() > 1.5
		return
	var dir := Vector3(tp.x - pos.x, 0.0, tp.z - pos.z)
	var p3: Dictionary = plats[want]
	var tgt: Vector3 = level.plat_pos(want)
	# A mover or lift must come to us first: wait near our edge.
	if level.movers.has(want) and on >= 0:
		var ready := false
		var s3: Vector2 = p3.s
		if String(p3.k) == "lift":
			ready = tgt.y <= float((p3.c as Vector3).y) + 0.2 and absf(tgt.y - pos.y) < 0.3
		else:
			ready = absf(tgt.x - pos.x) - s3.x * 0.5 < 1.6 and absf(tgt.y - pos.y) < 0.3
		if not ready:
			var edge := _edge_point(level, on, dir)
			out_move = _toward(Vector3(edge.x - pos.x, 0.0, edge.z - pos.z), 0.3)
			return
	out_move = _toward(dir, 0.0)
	if _zap_wait(pos, dir, level):
		out_move = Vector3.ZERO
		return
	# Hop: no ground just ahead, or the next floor is higher and close.
	var ahead := pos + dir.normalized() * 0.55
	var ground: int = level.support(ahead + Vector3.UP * 0.05, 0.3, 0.6)
	var s4: Vector2 = p3.s
	var near_edge := maxf(absf(tgt.x - pos.x) - s4.x * 0.5, absf(tgt.z - pos.z) - s4.y * 0.5)
	if ground < 0 or (tgt.y > pos.y + 0.3 and near_edge < 1.3) or stuck_t > 2.5:
		out_jump = true
		out_hold = true
		stuck_t = 0.0 if stuck_t > 2.5 else stuck_t


func _next(route: Array) -> void:
	k = mini(k + 1, route.size() - 1)
	step_t = 0.0


func _toward(flat: Vector3, slow_within: float) -> Vector3:
	var d := flat.length()
	if d < 0.05:
		return Vector3.ZERO
	var v := flat / d
	if slow_within > 0.0 and d < slow_within + 0.4:
		v *= clampf(d / (slow_within + 0.4), 0.25, 1.0)
	return v


## Our floor's edge towards dir (where to wait for a mover / lift).
func _edge_point(level: Node, plat: int, dir: Vector3) -> Vector3:
	var p: Dictionary = level.lv.plats[plat]
	var c: Vector3 = level.plat_pos(plat)
	var s: Vector2 = p.s
	if absf(dir.x) >= absf(dir.z):
		return Vector3(c.x + signf(dir.x) * (s.x * 0.5 - 0.45), c.y, c.z)
	return Vector3(c.x, c.y, c.z + signf(dir.z) * (s.y * 0.5 - 0.45))


## Wait while a zap pad just ahead flashes or buzzes (never stop on one: keep going if we're on it).
func _zap_wait(pos: Vector3, dir: Vector3, level: Node) -> bool:
	if dir.length() < 0.05:
		return false
	var d := dir.normalized()
	for z in level.lv.zaps:
		var zp: Vector3 = z.pos
		var rel := Vector3(zp.x - pos.x, 0.0, zp.z - pos.z)
		var dist := rel.length()
		if absf(zp.y - pos.y) > 0.7:
			continue
		if dist < float(z.r) + 0.2:
			return false  # on it: get off
		var along := rel.dot(d)
		var side := (rel - d * along).length()
		if along > 0.0 and along < float(z.r) + 1.6 and side < float(z.r) + 0.3:
			var c := fposmod(level.t / G.ZAP_PERIOD + float(z.ph), 1.0)
			if c < G.ZAP_TELL + G.ZAP_HOT + 0.02 or c > 0.9:
				return true
	return false


func _punch_grumbles(r: Node3D, level: Node) -> void:
	for i in level.grumbles.size():
		if not level.grumble_alive(i):
			continue
		var gp: Vector3 = level.grumble_pos(i)
		var rel := gp - r.position
		if absf(rel.y) < 0.8 and Vector2(rel.x, rel.z).length() < 1.7 and _punch_cd <= 0.0:
			r.rotation.y = atan2(rel.x, rel.z)
			out_punch = true
			_punch_cd = 0.45


## Crab Cove: keep clear of a stomp, punch while it's dizzy, hover round it otherwise.
func _fight(r: Node3D, level: Node, boss: Node, _delta: float) -> void:
	var c: Vector3 = boss.arena
	var bp: Vector3 = boss.position
	var rel := Vector3(r.position.x - bp.x, 0.0, r.position.z - bp.z)
	var dist := rel.length()
	var away := rel / maxf(dist, 0.01)
	var st := String(boss.state)
	if st == "dizzy":
		out_move = _toward(-rel, 1.0)
		if dist < 1.9 and _punch_cd <= 0.0:
			r.rotation.y = atan2(-rel.x, -rel.z)
			out_punch = true
			_punch_cd = 0.35
	elif st == "tell" or st == "stomp":
		var safe := float(boss.stomp_r) + 1.4
		if dist < safe:
			var to := bp + away * safe
			var lim := float(boss.arena_r) - 0.8
			var off := Vector3(to.x - c.x, 0.0, to.z - c.z)
			if off.length() > lim:  # (never off the arena: round the edge instead)
				to = c + off.normalized() * lim + Vector3(-away.z, 0, away.x) * 1.5
			out_move = _toward(Vector3(to.x - r.position.x, 0.0, to.z - r.position.z), 0.0)
	else:
		var want_d := float(boss.stomp_r) + 1.8
		var to2 := bp + away.rotated(Vector3.UP, 0.4) * want_d
		var off2 := Vector3(to2.x - c.x, 0.0, to2.z - c.z)
		if off2.length() > float(boss.arena_r) - 0.8:
			to2 = c + off2.normalized() * (float(boss.arena_r) - 0.8)
		out_move = _toward(Vector3(to2.x - r.position.x, 0.0, to2.z - r.position.z), 0.6)
