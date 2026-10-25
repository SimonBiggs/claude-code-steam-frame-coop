extends Node
## The deep-dungeon brain for tests/dungeon_delve_bot.gd (BRAVE / HEROIC). Each local TV hero:
##  - drinks a potion when low; steps out of glowing floor warnings; helps knocked-out friends up;
##  - fights: healers first, else the nearest monster; goes round the back of shield bearers (and the
##    Bone Lord's shield phase); uses its ability (bow / dash / bash) and bombs on bosses;
##  - between fights: picks up loot, opens chests, stands on puzzle plates / bonks levers (bot k takes
##    switch k), breaks cracked walls, takes keys to locked doors, explores unseen rooms, then stairs;
##  - in the shop buys what it can afford, then the stairs.
## The fake VR knight walks to monsters and swings the sword, holds the blade up to swat orbs, and
## follows the heroes otherwise. Navigation: room routes through open doors (floorgen.route), door
## waypoints, and a side-step when a pillar is in the way.

const FloorGen := preload("res://games/dungeon_delve/floorgen.gd")
const Foes := preload("res://games/dungeon_delve/foes.gd")
const Tele := preload("res://games/dungeon_delve/tele.gd")
const Loot := preload("res://games/dungeon_delve/loot.gd")
const VrRig := preload("res://core/vr_rig.gd")

var kit: Node
var main: Node
var cd := {}  ## slot -> {action: seconds}
var stuck := {}  ## slot -> {"p", "t", "side", "dodge"}
var bought := {}
var swing_side := 1.0
var _wp_cache := {}
var stall := {}


func deep() -> Node:
	return main.deep


func _cd(slot: int, k: String) -> float:
	return float((cd.get(slot, {}) as Dictionary).get(k, 0.0))


func _set_cd(slot: int, k: String, v: float) -> void:
	if not cd.has(slot):
		cd[slot] = {}
	(cd[slot] as Dictionary)[k] = v


func tick(delta: float) -> void:
	for s in cd:
		var d: Dictionary = cd[s]
		for k in d.keys():
			d[k] = float(d[k]) - delta


func _stats(slot: int) -> Dictionary:
	return (main.net.state_get("d_stats", {}) as Dictionary).get(slot, {})


func _press(slot: int, action: String, k: String, again: float) -> void:
	if _cd(slot, k) <= 0.0:
		_set_cd(slot, k, again)
		kit.slot_press(main.party, slot, action)


func _stick(slot: int, v: Vector2) -> void:
	kit.slot_stick(main.party, slot, "left", v.limit_length(1.0))


## A TV hero.
func hero(slot: int, delta: float, index: int) -> void:
	var dp := deep()
	if not main.heroes.has(slot) or dp.f.is_empty():
		return
	var h: Node3D = main.heroes[slot]
	var pos := h.position
	var st := _stats(slot)
	if st.is_empty() or bool(st.get("down", false)) or String(main.net.state_get("d_phase", "")) != "play":
		_stick(slot, Vector2.ZERO)
		return
	var f: Dictionary = dp.f
	var my_room := FloorGen.room_at(f, pos)
	# Stalled for a while (cornered, a pillar, a stand-off)? wander a bit.
	var sv: Dictionary = stall.get(slot, {"p": pos, "t": 0.0, "go": 0.0, "dir": Vector2.ZERO})
	stall[slot] = sv
	if float(sv["go"]) > 0.0:
		sv["go"] = float(sv["go"]) - delta
		_stick(slot, sv["dir"])
		return
	sv["t"] = float(sv["t"]) + delta
	if float(sv["t"]) > 5.0:
		if (sv["p"] as Vector3).distance_to(pos) < 0.5 and dp.foes.count_in(my_room) > 0:
			sv["go"] = 1.2
			sv["dir"] = Vector2.from_angle(randf() * TAU)
		sv["t"] = 0.0
		sv["p"] = pos
	# Potions.
	if int(st.get("hp", 5)) <= 2 and int(st.get("pot", 0)) > 0:
		_press(slot, "y", "y", 1.0)
	# Danger on the floor: step out.
	var away := _danger_escape(pos)
	if away != Vector3.ZERO:
		_stick(slot, Vector2(away.x, away.z).normalized())
		return
	if OS.has_environment("BOT_DEBUG") and Engine.get_process_frames() % 120 == 0:
		print("HERO %d pos %s room %d escape %s foe %d" % [slot, pos.snappedf(0.1), my_room, _danger_escape(pos), _pick_foe(pos, my_room)])
	if _incoming(slot, h):
		return
	# Monsters in my room.
	var foe := _pick_foe(pos, my_room)
	if foe >= 0:
		_fight(slot, h, foe, st, delta)
		return
	# A friend knocked out nearby.
	for s2 in main.heroes:
		var sd: Dictionary = _stats(int(s2))
		if int(s2) != slot and bool(sd.get("down", false)):
			var fp: Vector3 = (main.heroes[s2] as Node3D).position
			if FloorGen.room_at(f, fp) == my_room or my_room < 0:
				_go(slot, h, fp, 0.6, delta)
				return
	var kd: Dictionary = _stats(0)
	if main.vr_rig != null and bool(kd.get("down", false)):
		var kp: Vector3 = dp._feet_of(0)
		_go(slot, h, kp, 0.6, delta)
		return
	var goal := _goal(slot, pos, my_room, index)
	if goal.is_empty():
		_stick(slot, Vector2.ZERO)
		return
	var gp: Vector3 = goal["p"]
	var near: float = goal.get("near", 0.35)
	if _go(slot, h, gp, near, delta) and bool(goal.get("bonk", false)):
		_face_press(slot, h, goal.get("at", gp))


## Walk towards p through doors; true once within `near`.
func _go(slot: int, h: Node3D, p: Vector3, near: float, delta: float) -> bool:
	var dp := deep()
	var f: Dictionary = dp.f
	var pos := h.position
	var a := FloorGen.room_at(f, pos)
	var b := FloorGen.room_at(f, p)
	var wp := p
	if a >= 0 and b >= 0 and a != b:
		var r: Array = FloorGen.route(f, a, b, dp.view.pass_bits)
		if not r.is_empty():
			var di: int = r[0]
			var inside := FloorGen.door_inside(f, di, a, 1.0)
			var d := FloorGen.door_world(f, di)
			var lateral := Vector2(pos.x - d.x, pos.z - d.z)
			var dd: Dictionary = (f["doors"] as Array)[di]
			var across := absf(lateral.x) if int(dd["dir"]) % 2 == 0 else absf(lateral.y)
			if pos.distance_to(inside) > 0.5 and across > 0.45:
				wp = inside
			else:
				var o: int = FloorGen.other_side(dd, a)
				wp = FloorGen.door_inside(f, di, o, 1.4)
	var to := Vector3(wp.x - pos.x, 0.0, wp.z - pos.z)
	if wp == p and to.length() < near:
		_stick(slot, Vector2.ZERO)
		return true
	var step := steer(pos, wp)
	to = Vector3(step.x - pos.x, 0.0, step.z - pos.z)
	if OS.has_environment("BOT_DEBUG") and Engine.get_process_frames() % 120 == 0:
		print("GO slot %d pos %s p %s wp %s step %s clear %s" % [slot, pos.snappedf(0.1), p.snappedf(0.1), wp.snappedf(0.1), step.snappedf(0.1), _clear(pos, wp)])
	var dir := Vector2(to.x, to.z).normalized()
	# Stuck on a pillar? side-step for a moment.
	var sk: Dictionary = stuck.get(slot, {"p": pos, "t": 0.0, "side": 0.0, "dodge": 0.0})
	stuck[slot] = sk
	if float(sk["dodge"]) > 0.0:
		sk["dodge"] = float(sk["dodge"]) - delta
		dir = (dir + Vector2(-dir.y, dir.x) * float(sk["side"]) * 1.5).normalized()
	else:
		sk["t"] = float(sk["t"]) + delta
		if float(sk["t"]) > 0.6:
			if (sk["p"] as Vector3).distance_to(pos) < 0.25:
				sk["dodge"] = 0.7
				sk["side"] = 1.0 if randf() < 0.5 else -1.0
			sk["t"] = 0.0
			sk["p"] = pos
	_stick(slot, dir)
	return false


## Round pillars: straight at `to` when the way is clear, else the next cell of a grid search.
func steer(from: Vector3, to: Vector3) -> Vector3:
	var dp := deep()
	if _clear(from, to):
		return to
	var cell := 0.5
	var key := "%d,%d>%d,%d" % [int(round(from.x / cell)), int(round(from.z / cell)), int(round(to.x / cell)), int(round(to.z / cell))]
	if _wp_cache.has(key):
		return _wp_cache[key]
	var start := Vector2i(int(round(from.x / cell)), int(round(from.z / cell)))
	var goal := Vector2i(int(round(to.x / cell)), int(round(to.z / cell)))
	var prev := {start: start}
	var q: Array[Vector2i] = [start]
	var found := false
	var guard := 0
	var nearest := start
	while not q.is_empty() and guard < 3000:
		guard += 1
		var c: Vector2i = q.pop_front()
		if c.distance_squared_to(goal) < nearest.distance_squared_to(goal):
			nearest = c
		if c.distance_squared_to(goal) <= 1:
			goal = c
			found = true
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var n: Vector2i = c + d
			if prev.has(n):
				continue
			var wp := Vector3(n.x * cell, 0.0, n.y * cell)
			if not FloorGen.walkable(dp.view.rects, dp.view.obst, wp, 0.36):
				continue
			prev[n] = c
			q.append(n)
	if not found and nearest != start:
		goal = nearest  # the goal itself is in a pillar's shadow: get as close as we can
		found = true
	var out := to
	if found:
		# Walk back to the furthest cell we can see straight from here.
		var path: Array[Vector2i] = []
		var cur := goal
		while cur != start:
			path.push_front(cur)
			cur = prev[cur]
		for c2 in path:
			var w := Vector3(c2.x * cell, 0.0, c2.y * cell)
			if _clear(from, w):
				out = w
			else:
				break
		if out == to and not path.is_empty():
			out = Vector3(path[0].x * cell, 0.0, path[0].y * cell)
	if _wp_cache.size() > 2000:
		_wp_cache.clear()
	_wp_cache[key] = out
	return out


func _clear(a: Vector3, b: Vector3) -> bool:
	var dp := deep()
	var d := Vector2(b.x - a.x, b.z - a.z).length()
	var n := int(d / 0.25) + 1
	for i in range(1, n + 1):
		var p := a.lerp(b, float(i) / n)
		if not FloorGen.walkable(dp.view.rects, dp.view.obst, Vector3(p.x, 0.0, p.z), 0.33):
			return false
	return true


func _face_press(slot: int, h: Node3D, at: Vector3) -> void:
	var to := Vector3(at.x - h.position.x, 0.0, at.z - h.position.z)
	if to.length() > 0.05:
		_stick(slot, Vector2(to.x, to.z).normalized() * 0.45)
	var fwd := Vector3(sin(h.rotation.y), 0.0, cos(h.rotation.y))
	if to.length() < 0.3 or fwd.dot(to.normalized()) > 0.6:
		_press(slot, "accept", "a", 0.36)


func _danger_escape(pos: Vector3) -> Vector3:
	var dp := deep()
	for it in dp.tele.items:
		var d: Dictionary = it
		if float(d["t"]) > float(d["warn"]):
			continue
		if Tele.inside(String(d["shape"]), d["pos"], d["dir"], d["size"], pos, 0.5):
			var c: Vector3 = d["pos"]
			var out := Vector3(pos.x - c.x, 0.0, pos.z - c.z)
			if String(d["shape"]) == "line":
				var fwd: Vector3 = (d["dir"] as Vector3).normalized()
				out = out - fwd * out.dot(fwd)
				if out.length() < 0.1:
					out = Vector3(-fwd.z, 0.0, fwd.x)
			if out.length() < 0.1:
				out = Vector3(1, 0, 0)
			return out.normalized()
	# Spikes about to come up under me: off the band.
	for t in dp.view.traps:
		var td: Dictionary = t
		if String(td["kind"]) == "spikes" and float(td["s"]) >= 0.5:
			for w in td["tiles"]:
				var wp: Vector3 = w
				if absf(pos.x - wp.x) < FloorGen.TILE * 0.6 and absf(pos.z - wp.z) < FloorGen.TILE * 0.6:
					var c2 := FloorGen.room_center(dp.f, int(td["room"]))
					var first: Vector3 = td["tiles"][0]
					var last: Vector3 = td["tiles"][td["tiles"].size() - 1]
					var along := (last - first).normalized()
					var off := Vector3(pos.x - c2.x, 0.0, pos.z - c2.z)
					var side := off - along * off.dot(along)
					return side.normalized() if side.length() > 0.2 else Vector3(-along.z, 0.0, along.x)
	return Vector3.ZERO


## A goo ball coming at me: swat it when close, else step aside.
func _incoming(slot: int, h: Node3D) -> bool:
	if main.net.mode == "client":
		return false
	var pos := h.position
	for sid in deep().foes.shots:
		var s: Dictionary = deep().foes.shots[sid]
		if int(s.get("owner", 0)) == -2 or not s.has("v") or String(s["kind"]) == "bomb":
			continue
		var sp: Vector3 = s["p"]
		var v: Vector3 = s["v"]
		var to := Vector3(pos.x - sp.x, 0.0, pos.z - sp.z)
		var d := to.length()
		if d > 3.0 or Vector3(v.x, 0, v.z).normalized().dot(to.normalized()) < 0.85:
			continue
		if d < 1.4:
			_face_press(slot, h, sp)
		else:
			var side := Vector3(-v.z, 0.0, v.x).normalized()
			_stick(slot, Vector2(side.x, side.z))
		return true
	return false


func _pick_foe(pos: Vector3, room: int) -> int:
	var foes: Node = deep().foes
	var best := -1
	var bd := INF
	for id in foes.mons:
		var m: Dictionary = foes.mons[id]
		if int(m["room"]) != room or int(m["st"]) == Foes.SLEEP:
			continue
		var p: Vector3 = m["p"]
		var d := Vector2(p.x - pos.x, p.z - pos.z).length()
		if int(m["kind"]) == FloorGen.F_HEALER:
			d -= 3.0
		if d < bd:
			bd = d
			best = int(id)
	return best


func _fight(slot: int, h: Node3D, id: int, st: Dictionary, delta: float) -> void:
	var foes: Node = deep().foes
	var m: Dictionary = foes.mons[id]
	var p: Vector3 = m["p"]
	var kind: int = m["kind"]
	var yaw: float = m["yaw"]
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var pos := h.position
	var abil := String(st.get("abil", ""))
	var reach: float = 0.85 + foes.radius_of(id) * 0.8
	var shielded := kind == FloorGen.F_SHIELD or (kind == FloorGen.B_BONE and int(m["phase"]) >= 2)
	var goal := p
	if shielded and int(m["st"]) != Foes.STUN:
		goal = p - fwd * (reach * 0.9)
		var to_me := Vector3(pos.x - p.x, 0.0, pos.z - p.z)
		if to_me.normalized().dot(fwd) > -0.3:
			# Circle round instead of walking into the shield.
			var side := Vector3(-fwd.z, 0.0, fwd.x)
			if side.dot(to_me) < 0.0:
				side = -side
			goal = p + side * (reach + 0.6) - fwd * 0.5
	if abil == "bow" and not shielded:
		var d := Vector2(p.x - pos.x, p.z - pos.z).length()
		if d < 7.0 and d > 2.0:
			var to2 := Vector3(p.x - pos.x, 0.0, p.z - pos.z).normalized()
			var hf := Vector3(sin(h.rotation.y), 0.0, cos(h.rotation.y))
			_stick(slot, Vector2(to2.x, to2.z) * 0.45)
			if hf.dot(to2) > 0.8:
				_press(slot, "x", "x", 0.5)
			return
	if Foes.is_boss(kind) and int(st.get("bomb", 0)) > 0 and Vector2(p.x - pos.x, p.z - pos.z).length() < 3.2:
		_press(slot, "back", "b", 2.5)
	var dist := Vector2(goal.x - pos.x, goal.z - pos.z).length()
	if dist > 0.4 and not (not shielded and Vector2(p.x - pos.x, p.z - pos.z).length() < reach):
		_go(slot, h, goal, 0.35, delta)
		if abil == "bash" and Vector2(p.x - pos.x, p.z - pos.z).length() < 2.0:
			_press(slot, "x", "x", 1.5)
		return
	_face_press(slot, h, p)


## What to do when the room is quiet.
func _goal(slot: int, pos: Vector3, room: int, index: int) -> Dictionary:
	var dp := deep()
	var f: Dictionary = dp.f
	var walk: int = dp.view.pass_bits
	var reach_rooms := _reachable(room, walk)
	# Shop.
	if String(f["kind"]) == "shop":
		var shop: Array = main.net.state_get("d_shop", [])
		var gold := int(main.net.state_get("d_gold", 0))
		for i in shop.size():
			var it: Array = shop[i]
			var tries_key := "%s/%d/%d" % [dp.built_key, slot, i]
			if int(it[2]) == 0 and int(it[1]) <= gold and int(bought.get(tries_key, 0)) < 40:
				var sp := FloorGen.to_world(f, 0, dp.SHOP_SPOTS[i]) + Vector3(0, 0, 0.9)
				if Vector2(sp.x - pos.x, sp.z - pos.z).length() < 0.45:
					bought[tries_key] = int(bought.get(tries_key, 0)) + 1  # can't use it? give up after a while
				return {"p": sp, "near": 0.3, "bonk": true, "at": sp - Vector3(0, 0, 0.9)}
		return {"p": dp.view.stairs_at, "near": 0.4}
	# Loot nearby (same room).
	var picks: Dictionary = dp.pickups if main.net.mode != "client" else dp._mirror_picks
	var best := {}
	var bd := INF
	for id in picks:
		var pk: Dictionary = picks[id]
		var pp: Vector3 = pk["p"]
		if FloorGen.room_at(f, pp) != room:
			continue
		var d := pos.distance_to(Vector3(pp.x, 0, pp.z))
		if d < bd and _useful(slot, int(pk["kind"])):
			bd = d
			best = {"p": Vector3(pp.x, 0, pp.z), "near": 0.3}
	if not best.is_empty():
		return best
	for cid in dp.view.chests.size():
		if not dp.view.chest_open(cid) and int(dp.view.chests[cid]["room"]) in reach_rooms:
			var cp: Vector3 = dp.view.chests[cid]["p"]
			return {"p": cp, "near": 0.85, "bonk": true, "at": cp}
	for pid in dp.view.pots.size():
		if not dp.view.pot_broken(pid) and int(dp.view.pots[pid]["room"]) == room:
			return {"p": dp.view.pots[pid]["p"], "near": 0.7, "bonk": true, "at": dp.view.pots[pid]["p"]}
	# Puzzle doors.
	var doors: Array = f["doors"]
	var ob := int(main.net.state_get("d_open", 0))
	for di in doors.size():
		var dd: Dictionary = doors[di]
		if int(dd["type"]) != FloorGen.PUZZLE or ob & (1 << di) != 0:
			continue
		var sws: Array = dd["switches"]
		if sws.is_empty() or not int(((f["switches"] as Array)[sws[0]] as Dictionary)["room"]) in reach_rooms:
			continue
		var n := maxi(1, main.party.local_slots().size())
		var mine: int = sws[index % sws.size()]
		if n == 1 or main.party.local_slots().size() < 2:
			# Alone: do them in turn (each stays on for a while).
			mine = sws[0]
			var sw_state: Array = dp.view.switches
			for sid in sws:
				if float(sw_state[int(sid)]["on"]) <= 0.15:
					mine = int(sid)
					break
		var s: Dictionary = (f["switches"] as Array)[mine]
		var wp := FloorGen.to_world(f, int(s["room"]), s["p"])
		if String(s["kind"]) == "lever":
			var into := FloorGen.room_center(f, int(s["room"])) - wp
			into.y = 0.0
			return {"p": wp + into.normalized() * 0.7, "near": 0.35, "bonk": true, "at": wp}
		return {"p": wp, "near": 0.25}
	# Cracked walls.
	for di in doors.size():
		var dd2: Dictionary = doors[di]
		if int(dd2["type"]) == FloorGen.SECRET and ob & (1 << di) == 0 and int(dd2["a"]) in reach_rooms:
			var inside := FloorGen.door_inside(f, di, int(dd2["a"]), 0.75)
			return {"p": inside, "near": 0.3, "bonk": true, "at": FloorGen.door_world(f, di)}
	# Keys to locked doors.
	if int(main.net.state_get("d_keys", 0)) > 0:
		for di in doors.size():
			var dd3: Dictionary = doors[di]
			if int(dd3["type"]) in [FloorGen.LOCKED, FloorGen.BOSS] and ob & (1 << di) == 0:
				for side in [int(dd3["a"]), int(dd3["b"])]:
					if side in reach_rooms:
						return {"p": FloorGen.door_inside(f, di, side, 0.6), "near": 0.4}
	# Keys lying somewhere reachable.
	for id in picks:
		var pk2: Dictionary = picks[id]
		if int(pk2["kind"]) == Loot.KEY and FloorGen.room_at(f, pk2["p"]) in reach_rooms:
			var kp: Vector3 = pk2["p"]
			return {"p": Vector3(kp.x, 0, kp.z), "near": 0.3}
	# Unexplored rooms.
	var seen := int(main.net.state_get("d_seen", 1))
	var cleared := int(main.net.state_get("d_cleared", 1))
	var bestr := -1
	var bestd := INF
	for r in reach_rooms:
		if seen & (1 << int(r)) == 0 or cleared & (1 << int(r)) == 0:
			var d2 := pos.distance_to(FloorGen.room_center(f, int(r)))
			if d2 < bestd:
				bestd = d2
				bestr = int(r)
	if bestr >= 0:
		return {"p": FloorGen.room_center(f, bestr) + Vector3(0.5 * (index % 3 - 1), 0, 0.5), "near": 0.8}
	# Stairs / the portal.
	var portal: Variant = main.net.state_get("d_portal", null)
	if portal is Vector3:
		return {"p": portal, "near": 0.4}
	if dp.view.stairs_at != Vector3.INF:
		return {"p": dp.view.stairs_at + Vector3(0.4 * (index % 3 - 1), 0, 0.3 * (index % 2)), "near": 0.3}
	return {}


func _useful(slot: int, k: int) -> bool:
	var st := _stats(slot)
	match k:
		Loot.HEART:
			return int(st.get("hp", 0)) < int(st.get("max", 0))
		Loot.POTION:
			return int(st.get("pot", 0)) < 5
		Loot.BOMBS:
			return int(st.get("bomb", 0)) < 9
		Loot.DASH, Loot.BASH, Loot.BOW:
			return String(st.get("abil", "")) == ""
	return true


func _reachable(room: int, walk: int) -> Array:
	var f: Dictionary = deep().f
	var out: Array = []
	if room < 0:
		return out
	var seen := {room: true}
	var q: Array = [room]
	while not q.is_empty():
		var r: int = q.pop_front()
		out.append(r)
		var ds: Dictionary = ((f["rooms"] as Array)[r] as Dictionary)["doors"]
		for d in ds:
			var di: int = ds[d]
			if walk & (1 << di) == 0:
				continue
			var o: int = FloorGen.other_side((f["doors"] as Array)[di], r)
			if not seen.has(o):
				seen[o] = true
				q.append(o)
	return out


## The fake VR knight in the deep dungeon.
func knight(delta: float) -> void:
	var rig: Node = main.vr_rig
	var dp := deep()
	rig.camera.position = Vector3(0.0, 1.5, 0.0)
	var head: Vector3 = rig.head_position()
	var feet := Vector3(head.x, 0.0, head.z)
	kit.vr_stick(rig, Vector2.ZERO)
	var rest_r: Vector3 = head + Vector3(0.25, -0.5, -0.25)
	if dp.f.is_empty() or not dp._alive(0):
		kit.vr_reach(rig, VrRig.RIGHT, rest_r, 2.0, delta)
		return
	var f: Dictionary = dp.f
	var room := FloorGen.room_at(f, feet)
	# Swat orbs and goo balls coming close.
	for sid in dp.foes.shots:
		var s: Dictionary = dp.foes.shots[sid]
		if String(s["kind"]) in ["orb", "ball"] and int(s.get("owner", 0)) != -2:
			var sp: Vector3 = s["p"]
			if sp.distance_to(head) < 2.6:
				kit.vr_reach(rig, VrRig.RIGHT, sp + Vector3(swing_side * 0.3, 0.0, 0.0), 7.0, delta)
				if rig.hand_point(VrRig.RIGHT).distance_to(sp + Vector3(swing_side * 0.3, 0, 0)) < 0.05:
					swing_side = -swing_side
				return
	var foe := _pick_foe(feet, room)
	var goal := Vector3.INF
	if foe >= 0:
		var c: Vector3 = dp.foes.center_of(foe)
		var r: float = dp.foes.radius_of(foe)
		goal = c + (feet - Vector3(c.x, 0, c.z)).normalized() * (0.55 + r)
		if feet.distance_to(Vector3(goal.x, 0, goal.z)) < 1.2:
			var p := c + Vector3(swing_side * 0.5, 0.0, 0.0)
			if kit.vr_reach(rig, VrRig.RIGHT, p, 6.0, delta):
				swing_side = -swing_side
	else:
		kit.vr_reach(rig, VrRig.RIGHT, rest_r, 2.0, delta)
		# Follow the first hero.
		for s2 in main.heroes:
			var hp: Vector3 = (main.heroes[s2] as Node3D).position
			if feet.distance_to(hp) > 2.0:
				goal = hp
			break
		if main.heroes.is_empty():
			var g := _goal(0, feet, room, 0)
			if OS.has_environment("BOT_DEBUG") and Engine.get_process_frames() % 120 == 0:
				print("KNIGHT feet %s room %d goal %s" % [feet.snappedf(0.1), room, str(g)])
			if not g.is_empty():
				goal = g["p"]
				if bool(g.get("bonk", false)) and feet.distance_to(Vector3(goal.x, 0, goal.z)) < 1.3:
					var aim: Vector3 = (g.get("at", goal) as Vector3) + Vector3(swing_side * 0.2, 0.3, 0.0)
					kit.vr_reach(rig, VrRig.RIGHT, aim, 6.0, delta)
					if rig.hand_point(VrRig.RIGHT).distance_to(aim) < 0.08:
						swing_side = -swing_side
					if feet.distance_to(Vector3(goal.x, 0, goal.z)) < 0.9:
						goal = Vector3.INF
	if goal == Vector3.INF:
		return
	var b := FloorGen.room_at(f, goal)
	var wp := goal
	if room >= 0 and b >= 0 and room != b:
		var rt: Array = FloorGen.route(f, room, b, dp.view.pass_bits)
		if not rt.is_empty():
			var di: int = rt[0]
			var inside := FloorGen.door_inside(f, di, room, 1.0)
			var dd: Dictionary = (f["doors"] as Array)[di]
			var dw := FloorGen.door_world(f, di)
			var across := absf(feet.x - dw.x) if int(dd["dir"]) % 2 == 0 else absf(feet.z - dw.z)
			wp = inside if feet.distance_to(inside) > 0.5 and across > 0.4 else FloorGen.door_inside(f, di, FloorGen.other_side(dd, room), 1.4)
	var stp := steer(feet, wp)
	var to := Vector3(stp.x - feet.x, 0.0, stp.z - feet.z)
	if OS.has_environment("BOT_DEBUG") and Engine.get_process_frames() % 120 == 0:
		print("KSTEER wp %s stp %s walk %s loco %s" % [wp.snappedf(0.1), stp.snappedf(0.1), FloorGen.walkable(dp.view.rects, dp.view.obst, feet, 0.25), rig.locomotion])
	if to.length() > (0.3 if stp == wp else 0.05):
		kit.vr_stick(rig, Vector2(to.x, -to.z).normalized())
