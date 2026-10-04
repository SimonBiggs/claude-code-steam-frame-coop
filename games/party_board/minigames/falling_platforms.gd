extends "res://games/party_board/minigames/mg_base.gd"
## FALLING PLATFORMS (giant vs islanders): round stepping stones over bubbling lava.
## The GIANT pokes a stone with a glove: it wobbles, then drops into the lava (and comes back up
## later). Islanders hop between the stones; standing on nothing = splash, you're out.
## The islanders win together if anyone is still standing at the end; the giant wins by
## knocking everyone off. Without a giant it's a free-for-all and the stones fall by themselves.
## Fairness (family play-test: the giant won easily and a kid asked "can we not do this?"): a poked
## stone glows and wobbles for 2 s before it drops (time to hop off), the giant can only have
## MAX_DOWN stones wobbling / down at once and must wait POKE_CD between pokes, dropped stones come
## back sooner, each islander gets a second chance (landing on a safe stone the giant can't poke for
## a moment), and the round is shorter.

const META := {
	"name": "FALLING PLATFORMS",
	"goal": "Stay on the stones! They wobble and drop into the lava.",
	"format": "giant", "time": 30.0, "music": "boss", "cam": [16.0, 12.0],
	"tv": [["L-STICK", "Hop between the stones"]],
	"vr": [["GLOVE", "Poke a stone to drop it"]],
	"vr_line": "POKE a stone: it glows, wobbles, then drops!",
}
const STONE_R := 1.05
const SHAKE_T := 2.0  ## warning wobble before a poked stone drops (was 1.25)
const POKE_CD := 1.5  ## seconds between the giant's pokes (was 0.75)
const DOWN_T := 3.5  ## seconds a stone stays in the lava (was 5)
const MAX_DOWN := 4  ## the giant can only have this many stones wobbling / down at once
const SAFE_T := 2.5  ## a second-chance landing stone can't be poked for this long
const FEET_MARGIN := 0.4  ## an islander still stands on a stone this far past its edge
const COYOTE_T := 0.3  ## seconds over lava before the splash

var stones: Array[Vector3] = []
var stone_nodes: Array[Node3D] = []
var state := PackedByteArray()  # 0 up, 1 wobbling, 2 down
var timer: Array[float] = []
var _poke_cd := 0.0
var _auto_t := 0.0
var _alive_t := {}  # pid -> seconds survived
var lives := {}  # pid -> extra lives left (giant game: one second chance each)
var _respawn := {}  # pid -> seconds until back on a stone
var _off_t := {}  # pid -> seconds over lava (falls after COYOTE_T)
var _safe: Array[float] = []  # per stone: seconds it can't be poked (a second-chance landing)
var warn_nodes: Array[Node3D] = []  # per stone: the glowing warning ring while it wobbles


func build() -> void:
	arena_r = 6.6
	# Lava pool with a rocky rim (one mesh).
	var b := MeshKit.Builder.new()
	b.cylinder(arena_r + 2.6, arena_r + 3.0, 1.4, MeshKit.at(Vector3(0, -1.0, 0)), Color(0.35, 0.3, 0.3), 32)
	b.disc(arena_r + 1.6, MeshKit.at(Vector3(0, -0.6, 0)), Color(1.0, 0.45, 0.1), 32, true)
	for k in 14:
		var a := k * TAU / 14.0
		b.sphere(0.9, MeshKit.at(Vector3(cos(a), 0, sin(a)) * (arena_r + 2.2) + Vector3(0, -0.2, 0), Vector3(1.2, 0.7, 1.0)), Color(0.3, 0.26, 0.25), 8)
	add_child(MeshKit.instance(b.build(), false))
	var sb := MeshKit.Builder.new()
	sb.cylinder(STONE_R, STONE_R * 0.8, 0.7, MeshKit.at(Vector3(0, -0.3, 0)), Color(0.62, 0.58, 0.55), 14)
	sb.cylinder(STONE_R * 0.92, STONE_R * 0.95, 0.12, MeshKit.at(Vector3(0, 0.03, 0)), Color(0.45, 0.75, 0.4), 14)
	var mesh := sb.build()
	stones.append(Vector3.ZERO)
	for ring in [1, 2]:
		var n: int = 6 * ring
		for k in n:
			var a := TAU * float(k) / float(n) + (0.0 if ring == 1 else 0.26)
			stones.append(Vector3(cos(a), 0, sin(a)) * 2.35 * float(ring))
	var rb := MeshKit.Builder.new()
	rb.cylinder(STONE_R * 1.08, STONE_R * 1.08, 0.06, MeshKit.at(Vector3(0, 0.1, 0)), Color(1.0, 0.25, 0.1), 14)
	var ring_mesh := rb.build()
	for p in stones:
		var mi := MeshKit.instance(mesh, false)
		mi.position = p
		add_child(mi)
		stone_nodes.append(mi)
		timer.append(0.0)
		_safe.append(0.0)
		# Show, don't tell: a poked stone glows red under the islander's feet before it drops.
		var ring := MeshKit.instance(ring_mesh, false)
		ring.visible = false
		mi.add_child(ring)
		warn_nodes.append(ring)
	state.resize(stones.size())
	state.fill(0)


func start_pos(i: int, n: int) -> Vector3:
	return stones[1 + (i * 6 / maxi(1, n)) % 6]


func on_begin() -> void:
	state.fill(0)
	for i in timer.size():
		timer[i] = 0.0
		_safe[i] = 0.0
	_alive_t.clear()
	lives.clear()
	_respawn.clear()
	_off_t.clear()
	for p in walkers():
		lives[p] = 1 if giant else 0


func stone_under(p: Vector3, margin: float = 0.15) -> int:
	for i in stones.size():
		if state[i] != 2 and Vector2(p.x - stones[i].x, p.z - stones[i].z).length() < STONE_R + margin:
			return i
	return -1


func play_tick(delta: float) -> void:
	for p in walkers():
		if out.has(p) or _respawn.has(p):
			var fp: Vector3 = pos[p]
			if fp.y > -8.0:
				fp.y -= 9.0 * delta
				pos[p] = fp
				(avatars[p] as Node3D).position = fp
			if _respawn.has(p):
				_respawn[p] = float(_respawn[p]) - delta
				if float(_respawn[p]) <= 0.0:
					_respawn.erase(p)
					var s := _safest_stone()
					state[s] = 0
					timer[s] = 0.0
					_safe[s] = SAFE_T
					pos[p] = stones[s]
					(avatars[p] as Node3D).position = stones[s]
					fx("back", [p, stones[s]])
			continue
		walk(p, delta, 5.0)
		if not practice:
			_alive_t[p] = float(_alive_t.get(p, 0.0)) + delta
			score[p] = floorf(float(_alive_t[p]))
			# Forgiving feet: the gaps between stones (and a shove from a friend) aren't deadly; only
			# standing over lava for a moment is (kids hop across with a stick).
			if stone_under(pos[p], FEET_MARGIN) < 0:
				_off_t[p] = float(_off_t.get(p, 0.0)) + delta
				if float(_off_t[p]) > COYOTE_T:
					_off_t.erase(p)
					_fall(p)
			else:
				_off_t.erase(p)
	separate(0.7)
	# Stones: wobble -> down -> back up.
	for i in stones.size():
		_safe[i] = maxf(0.0, _safe[i] - delta)
		if state[i] == 0:
			continue
		timer[i] -= delta
		if timer[i] <= 0.0:
			if state[i] == 1:
				state[i] = 2
				timer[i] = DOWN_T
				fx("drop", [i])
			else:
				state[i] = 0
	if practice:
		return
	if giant:
		_poke_cd -= delta
		if _poke_cd <= 0.0 and _busy_stones() < MAX_DOWN:
			for h in giant_hands().size():
				var hp: Vector3 = giant_hands()[h]
				if hp.y < 1.6:
					var s := stone_under(hp)
					if s >= 0 and state[s] == 0 and _safe[s] <= 0.0:
						_wobble(s)
						_poke_cd = POKE_CD
						buzz(h, 0.6, 0.08)
						break
	else:
		_auto_t -= delta
		if _auto_t <= 0.0:
			_auto_t = maxf(0.3, 0.9 - play_t * 0.03)
			var up: Array = []
			for i in stones.size():
				if state[i] == 0:
					up.append(i)
			if up.size() > 3:
				# Half the time the stone under someone wobbles: keep everybody hopping.
				var ws: Array = walkers().filter(func(p: int) -> bool: return not out.has(p))
				var s := -1
				if not ws.is_empty() and rng.randf() < 0.5:
					s = stone_under(pos[int(ws[rng.randi() % ws.size()])])
				if s < 0 or state[s] != 0:
					s = int(up[rng.randi() % up.size()])
				_wobble(s)


## Stones wobbling or down right now (the giant's cap is MAX_DOWN).
func _busy_stones() -> int:
	var n := 0
	for i in stones.size():
		if state[i] != 0:
			n += 1
	return n


## A second chance lands on the standing stone furthest from the giant's hands.
func _safest_stone() -> int:
	var hs: Array[Vector3] = []
	if giant:
		hs = giant_hands()
	var best := 0
	var bs := -INF
	for i in stones.size():
		if state[i] != 0:
			continue
		var sc := rng.randf() * 0.5
		for h in hs:
			sc += minf(6.0, Vector2(h.x - stones[i].x, h.z - stones[i].z).length())
		if sc > bs:
			bs = sc
			best = i
	return best


func _wobble(i: int) -> void:
	state[i] = 1
	timer[i] = SHAKE_T
	sound("crash", -12.0, 1.6)


func _fall(p: int) -> void:
	if int(lives.get(p, 0)) > 0:
		lives[p] = int(lives[p]) - 1
		_respawn[p] = 1.6
	else:
		out[p] = true
	if giant:
		add_score(0, 1)
	fx("fall", [p, pos[p]])
	sound("splash", -2.0, 0.8)


func finished() -> bool:
	var alive := 0
	for p in walkers():
		if not out.has(p):
			alive += 1
	return alive == 0 or (not giant and alive <= 1 and walkers().size() > 1)


func team_winner() -> int:
	if not giant:
		return -2
	for p in walkers():
		if not out.has(p):
			return 1
	return 0


func snap_extra() -> Array:
	var lv := PackedInt32Array()
	for p in walkers():
		lv.append(int(lives.get(p, 0)))
	return [state, lv]


func unsnap_extra(a: Array) -> void:
	if a.size() >= 2:
		state = a[0]
		var lv: PackedInt32Array = a[1]
		var ws := walkers()
		for i in mini(lv.size(), ws.size()):
			lives[ws[i]] = lv[i]


func on_fx(kind: String, args: Variant) -> void:
	var a: Array = args
	match kind:
		"drop":
			burst_at(stones[int(a[0])] + Vector3(0, -0.2, 0), Color(1.0, 0.5, 0.15), 10)
		"back":
			burst_at(a[1] + Vector3(0, 1.0, 0), Color(1.0, 1.0, 0.7), 12)
			popup_at(a[1], "SECOND CHANCE!", color_of(int(a[0])))
		"fall":
			var p: Vector3 = a[1]
			burst_at(p + Vector3(0, -0.4, 0), Color(1.0, 0.4, 0.1), 22)
			popup_at(p, "SPLASH!", Color(1.0, 0.5, 0.2))
			if avatars.has(int(a[0])):
				Creatures.anim(avatars[int(a[0])]).play("hurt", 1.0)


func _process(delta: float) -> void:
	super(delta)
	var t := Time.get_ticks_msec() * 0.001
	for i in stone_nodes.size():
		var n := stone_nodes[i]
		var want := 0.0
		var off := Vector3.ZERO
		var warn: Node3D = warn_nodes[i] if i < warn_nodes.size() else null
		if warn != null:
			warn.visible = state[i] == 1
		if state[i] == 1:
			# Gentle at first, harder just before it drops.
			var k: float = 0.04 + 0.08 * clampf(1.0 - timer[i] / SHAKE_T, 0.0, 1.0) if host else 0.08
			off = Vector3(sin(t * 47.0 + i) * k, 0, cos(t * 41.0 + i) * k)
			if warn != null:
				warn.scale = Vector3.ONE * (1.0 + 0.06 * sin(t * 12.0))
		elif state[i] == 2:
			want = -6.0
		n.position.y = lerpf(n.position.y, want, 1.0 - exp(-(3.0 if want < 0.0 else 6.0) * delta))
		n.position.x = stones[i].x + off.x
		n.position.z = stones[i].z + off.z
		n.visible = n.position.y > -5.5


func cpu_move(pid: int) -> Vector3:
	var me := where(pid)
	var here := stone_under(me)
	var hs: Array[Vector3] = []
	if host:
		hs = giant_hands()
	var best := here
	var bs := -INF
	for i in stones.size():
		if state[i] != 0:
			continue
		var s := -stones[i].distance_to(me) * 0.6
		for h in hs:
			s += minf(4.0, Vector2(h.x - stones[i].x, h.z - stones[i].z).length()) * 0.8
		if i == here:
			s += 0.8
		if s > bs:
			bs = s
			best = i
	if best < 0:
		return Vector3.ZERO
	return stones[best]


func status_of(pid: int) -> String:
	if out.has(pid):
		return "OUT"
	return "+1 LIFE" if int(lives.get(pid, 0)) > 0 else ""


func bot_vr_goal() -> Vector3:
	var best := Vector3(0, 3, 3)
	var bd := INF
	for p in walkers():
		if out.has(p):
			continue
		var d := where(p).length()
		if d < bd:
			bd = d
			best = where(p) + Vector3(0, 0.5, 0)
	return best
