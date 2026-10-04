extends Node3D
## Base for every Party Board minigame. A minigame is a little diorama built under main.stage (board
## units, so the VR player sees it on the table and plays it with their hands as THE GIANT, while the
## TV sees it full size). mg_runner.gd creates it on every machine from the "mg" state, then:
##   host / local: tick(delta) simulates (practice during the how-to card, then the real round), and
##                 snapshot() is sent 30 times a second;  results come from scores() / team_winner().
##   TV machine:   apply_snapshot() mirrors it; one-off effects arrive through on_fx().
## Subclasses override: build(), on_begin(), play_tick(delta), cpu_move(pid), cpu_press(pid),
## snap_extra() / unsnap_extra(a), on_fx(kind, args), bot_vr_goal(), finished(), team_winner().
## Positions are local to this node ("arena units" = board units). pid 0 is the GIANT when `giant` is
## true (the VR player plays with their gloves and has no walker); everyone else is a walker.

const Creatures := preload("res://core/creatures.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const UiKit := preload("res://core/ui_kit.gd")
const HudKit := preload("res://core/hud_kit.gd")
const ResCache := preload("res://core/res_cache.gd")
const TokenScript := preload("res://games/party_board/token.gd")

const AVATAR_SCALE := 1.15
const HAND_R := 1.1  ## how close (arena units) a glove must be to touch something

var main: Node
var cfg: Dictionary = {}
var host := false
var pids: Array[int] = []
var teams := {}  ## pid -> 0 / 1 (team games)
var giant := false  ## pid 0 plays with VR hands
var rng := RandomNumberGenerator.new()
var avatars := {}  ## pid -> Node3D (walkers)
var pos := {}  ## pid -> Vector3 (walkers, arena-local)
var score := {}  ## pid -> float
var out := {}  ## pid -> true: knocked out (survival games)
var practice := true
var play_t := 0.0
var time_limit := 40.0
var walk_speed := 5.5
var arena_r := 6.0
var _targets := {}  ## TV machine: pid -> [Vector3, yaw]
var _last := {}  ## pid -> Vector3 (walk animation)
var _cpu_goal := {}  ## pid -> Vector3
var _cpu_t := {}  ## pid -> float
var stun := {}  ## pid -> seconds left: can't move (host)
## Synced props (coins, balloons, sheep...): id -> Node3D, id -> kind. The host adds / moves / removes
## them; snapshots carry them to the TV machine (items_snap / items_apply, done by the base).
var items := {}
var item_kind := {}
var _next_item := 0
## The giant's PAWN (games where the giant's glove is a piece on the arena, e.g. a shark fin): it
## follows the right glove projected onto the ground, at a capped speed. use_pawn = true to enable.
var use_pawn := false
var pawn_speed := 9.0
var pawn := Vector3.ZERO
var pawn_node: Node3D
var _pawn_target := Vector3.ZERO


## Called by mg_runner before the node enters the tree.
func setup(p_main: Node, p_cfg: Dictionary, p_host: bool) -> void:
	main = p_main
	cfg = p_cfg
	host = p_host
	rng.seed = int(cfg.get("seed", 1))
	for p in cfg.get("pids", []):
		pids.append(int(p))
	var tm: Dictionary = cfg.get("teams", {})
	for k in tm:
		teams[int(k)] = int(tm[k])
	giant = bool(cfg.get("giant", false))
	for p in pids:
		score[p] = 0.0


func _ready() -> void:
	build()
	for p in walkers():
		_make_avatar(p)
	if use_pawn and giant:
		pawn_node = make_pawn()
		pawn_node.name = "Pawn"
		add_child(pawn_node)
		pawn = Vector3(0, 0, arena_r * 0.5)
		_pawn_target = pawn
		pawn_node.position = pawn


# --- Virtuals ---------------------------------------------------------------------------------------------

## Build the diorama (every machine). Walkers are added afterwards by the base.
func build() -> void:
	build_island(arena_r + 1.0, Color(0.45, 0.75, 0.38))


## Start position of walker number `i` of `n`.
func start_pos(i: int, n: int) -> Vector3:
	var a := PI + TAU * (float(i) + 0.5) / float(maxi(1, n)) * 0.5 - PI * 0.5
	return Vector3(cos(a), 0.0, sin(a)) * arena_r * 0.5


## The real round starts (scores were reset).
func on_begin() -> void:
	pass


## Host: one simulation step (also runs during practice).
func play_tick(_delta: float) -> void:
	pass


## Host: where a CPU walker wants to go (arena-local point).
func cpu_move(_pid: int) -> Vector3:
	return Vector3.ZERO


## Host: does a CPU walker press A now?
func cpu_press(_pid: int) -> bool:
	return false


func snap_extra() -> Array:
	return []


## Every machine: the mesh for a synced item of `kind`.
func make_item(_kind: int) -> Node3D:
	return MeshKit.instance(MeshKit.prop("coin"), false)


## Every machine: the giant's pawn (when use_pawn).
func make_pawn() -> Node3D:
	var b := MeshKit.Builder.new()
	b.cylinder(1.0, 1.15, 0.25, MeshKit.at(Vector3(0, 0.12, 0)), Color(0.98, 0.95, 0.85), 20)
	b.torus(1.05, 0.12, MeshKit.at(Vector3(0, 0.25, 0)), color_of(0), 20, 6)
	return MeshKit.instance(b.build(), false)


func unsnap_extra(_a: Array) -> void:
	pass


## Every machine: an effect sent with fx().
func on_fx(_kind: String, _args: Variant) -> void:
	pass


## Bots: where the fake VR right hand should go (arena-local), or Vector3.INF.
func bot_vr_goal() -> Vector3:
	return Vector3.INF


## True when the round is over before the clock (everyone out...).
func finished() -> bool:
	return false


## Giant / team games: the winning team (0 / 1), -1 for a draw, -2 = not a team game (use scores).
func team_winner() -> int:
	return -2


## Short status for the scores line, e.g. "OUT".
func status_of(pid: int) -> String:
	return "OUT" if out.has(pid) else ""


# --- Helpers ----------------------------------------------------------------------------------------------

func walkers() -> Array[int]:
	var w: Array[int] = []
	for p in pids:
		if not (giant and p == 0):
			w.append(p)
	return w


## Where a walker is (host: the simulation; TV machine: the mirrored avatar).
func where(pid: int) -> Vector3:
	if host:
		return pos.get(pid, Vector3.ZERO)
	return (avatars[pid] as Node3D).position if avatars.has(pid) else Vector3.ZERO


## Host: add a synced item; returns its id.
func add_item(kind: int, p: Vector3) -> int:
	_next_item += 1
	_spawn_item(_next_item, kind, p)
	return _next_item


func _spawn_item(id: int, kind: int, p: Vector3) -> Node3D:
	var n := make_item(kind)
	n.position = p
	add_child(n)
	items[id] = n
	item_kind[id] = kind
	return n


## Host: remove a synced item (the TV machine drops it at the next snapshot).
func remove_item(id: int) -> void:
	if items.has(id):
		(items[id] as Node).queue_free()
	items.erase(id)
	item_kind.erase(id)


func items_snap() -> Array:
	var ids := PackedInt32Array()
	var kinds := PackedInt32Array()
	var ps := PackedVector3Array()
	for id in items:
		ids.append(int(id))
		kinds.append(int(item_kind[id]))
		ps.append((items[id] as Node3D).position)
	return [ids, kinds, ps]


func items_apply(a: Array) -> void:
	if a.size() < 3:
		return
	var ids: PackedInt32Array = a[0]
	var kinds: PackedInt32Array = a[1]
	var ps: PackedVector3Array = a[2]
	var seen := {}
	for i in ids.size():
		var id := ids[i]
		seen[id] = true
		if not items.has(id) or int(item_kind.get(id, -1)) != kinds[i]:
			if items.has(id):
				(items[id] as Node).queue_free()
			_spawn_item(id, kinds[i], ps[i])
		else:
			var n: Node3D = items[id]
			n.position = n.position.lerp(ps[i], 0.6)
	for id in items.keys():
		if not seen.has(id):
			(items[id] as Node).queue_free()
			items.erase(id)
			item_kind.erase(id)


## Host: move the giant's pawn towards the right glove (projected on the ground), speed-capped.
func update_pawn(delta: float) -> void:
	var hs := giant_hands()
	if hs.size() < 2:
		return
	var h: Vector3 = hs[1]
	var t := Vector3(h.x, 0.0, h.z)
	var flat := Vector2(t.x, t.z).limit_length(arena_r)
	t = Vector3(flat.x, 0.0, flat.y)
	pawn = pawn.move_toward(t, pawn_speed * delta)
	if pawn_node != null:
		pawn_node.position = pawn


func is_cpu(pid: int) -> bool:
	return main.is_cpu(pid)


func name_of(pid: int) -> String:
	return main.name_of(pid)


func color_of(pid: int) -> Color:
	return main.color_of(pid)


func add_score(pid: int, n: float = 1.0) -> void:
	if practice:
		return
	score[pid] = float(score.get(pid, 0.0)) + n


func _make_avatar(pid: int) -> void:
	var look: Array = TokenScript.LOOKS[pid % TokenScript.LOOKS.size()]
	var a := Creatures.humanoid({"class": String(look[0]), "hat": String(look[1]), "hair": look[2], "outfit": color_of(pid),
		"seed": 11 + pid * 7, "scale": AVATAR_SCALE})
	a.name = "Walker%d" % pid
	add_child(a)
	var ws := walkers()
	var p := start_pos(ws.find(pid), ws.size())
	a.position = p
	pos[pid] = p
	_last[pid] = p
	# A coloured ring under each walker, so everyone finds themselves quickly.
	var b := MeshKit.Builder.new()
	b.torus(0.55, 0.07, MeshKit.at(Vector3(0, 0.06, 0)), color_of(pid), 16, 5)
	var ring := MeshKit.instance(ResCache.get_or_make("pb_ring_%s" % color_of(pid).to_html(), b.build), false)
	a.add_child(ring)
	if main.vr_rig == null:
		HudKit.nameplate(a, name_of(pid), color_of(pid), 1.9, 0.38)
	avatars[pid] = a


## Host: everybody's input for this frame: {move: Vector3 (arena), pressed, held}.
func input_of(pid: int) -> Dictionary:
	if is_cpu(pid):
		var goal := cpu_goal(pid)
		var d: Vector3 = goal - (pos.get(pid, Vector3.ZERO) as Vector3)
		d.y = 0.0
		var mv := d / 1.2 if d.length() < 1.2 else d.normalized()
		var pr := cpu_press(pid)
		return {"move": mv, "pressed": pr, "held": pr}
	return main.pad_input(pid)


## CPU walkers re-think a few times a second (with a little hesitation, so kids can win).
func cpu_goal(pid: int) -> Vector3:
	var t := float(_cpu_t.get(pid, 0.0)) - get_process_delta_time()
	if t <= 0.0 or not _cpu_goal.has(pid):
		t = rng.randf_range(0.25, 0.7) * (1.4 if main.flow != null and main.flow.is_kid() else 1.0)
		_cpu_goal[pid] = cpu_move(pid)
	_cpu_t[pid] = t
	return _cpu_goal[pid]


## Host: move a walker by its stick (or CPU goal) and keep it in the arena circle.
func walk(pid: int, delta: float, speed: float = -1.0, limit_r: float = -1.0) -> Dictionary:
	var inp := input_of(pid)
	if out.has(pid):
		return inp
	if float(stun.get(pid, 0.0)) > 0.0:
		stun[pid] = float(stun[pid]) - delta
		inp["pressed"] = false
		inp["held"] = false
		return inp
	var mv: Vector3 = inp["move"]
	var p: Vector3 = pos[pid]
	if mv.length() > 0.05:
		p += mv.limit_length(1.0) * (walk_speed if speed < 0.0 else speed) * delta
		Creatures.anim(avatars[pid]).face(mv)
	var r := arena_r if limit_r < 0.0 else limit_r
	var flat := Vector2(p.x, p.z).limit_length(r)
	p = Vector3(flat.x, p.y, flat.y)
	pos[pid] = p
	(avatars[pid] as Node3D).position = p
	return inp


## Push walkers apart so they don't stand inside each other.
func separate(min_d: float = 0.9) -> void:
	var ws := walkers()
	for i in ws.size():
		for j in range(i + 1, ws.size()):
			var a: int = ws[i]
			var b: int = ws[j]
			if out.has(a) or out.has(b):
				continue
			var pa: Vector3 = pos[a]
			var pb: Vector3 = pos[b]
			var d := Vector2(pb.x - pa.x, pb.z - pa.z)
			if d.length() < min_d and d.length() > 0.001:
				var push := d.normalized() * (min_d - d.length()) * 0.5
				pos[a] = pa - Vector3(push.x, 0, push.y)
				pos[b] = pb + Vector3(push.x, 0, push.y)


## Host: the VR gloves in arena units (palm points), [] without a giant.
func giant_hands() -> Array[Vector3]:
	var hs: Array[Vector3] = []
	if giant and main.vr_rig != null:
		for h in 2:
			hs.append(to_local(main.vr_rig.hand_point(h)))
	elif giant and main.giant != null:
		for h in 2:
			hs.append(main.giant.hand_pos(h) - position)
	return hs


## Host: which glove (0 / 1) touches the arena point, -1 = none.
func glove_touching(p: Vector3, r: float = HAND_R) -> int:
	var hs := giant_hands()
	for h in hs.size():
		if hs[h].distance_to(p) < r:
			return h
	return -1


## Host: a haptic buzz on the giant's glove.
func buzz(hand: int, amp: float = 0.5, t: float = 0.06) -> void:
	if main.vr_rig != null and hand >= 0:
		main.vr_rig.pulse(hand, amp, t)


## Host: an effect here and on the TV machine.
func fx(kind: String, args: Variant = null) -> void:
	main.fx("mg_fx", [kind, args])


## Host: a sound everywhere.
func sound(snd: String, db: float = 0.0, pitch: float = 1.0) -> void:
	main.fx("sfx", [snd, db, pitch])


## Every machine: sparkles at an arena point.
func burst_at(p: Vector3, color: Color, amount: int = 14) -> void:
	main.burst(position + p, color, amount)


## Every machine: a "+1" over an arena point.
func popup_at(p: Vector3, text: String, color: Color) -> void:
	var size := 1.2 if main.vr_rig == null else 0.4
	HudKit.popup(main, main.to_world(position + p + Vector3(0, 1.6, 0)), text, {"style": "score", "color": color, "size": size,
		"rise": 1.5 if main.vr_rig == null else 0.06})


## A thick round island with a sandy rim, sitting in a ring of water (one mesh).
func build_island(r: float, grass: Color, sand: Color = Color(0.93, 0.84, 0.6)) -> void:
	var key := "pb_mg_island_%d_%s_%s" % [int(r * 10.0), grass.to_html(), sand.to_html()]
	var mesh: Resource = ResCache.get_or_make(key, func() -> Resource:
		var b := MeshKit.Builder.new()
		b.cylinder(r + 1.6, r + 2.2, 1.2, MeshKit.at(Vector3(0, -0.75, 0)), Color(0.3, 0.6, 0.85), 40)
		b.cylinder(r + 0.6, r + 0.9, 1.0, MeshKit.at(Vector3(0, -0.45, 0)), sand, 40)
		b.cylinder(r, r + 0.3, 0.5, MeshKit.at(Vector3(0, -0.2, 0)), grass, 40)
		return b.build())
	add_child(MeshKit.instance(mesh, false))
	var pal := PackedColorArray([Color(1.0, 0.5, 0.6), Color(1.0, 0.9, 0.4), Color(0.7, 0.6, 1.0)])
	add_child(MeshKit.scatter_random(MeshKit.prop("palm"), 6, Vector3.ZERO, r + 0.6, r - 0.2, 0.7, 1.0, PackedColorArray(), 7))
	add_child(MeshKit.scatter_random(MeshKit.prop("flower"), 14, Vector3.ZERO, r - 0.2, r - 1.2, 0.6, 1.0, pal, 8))


# --- Runner interface -------------------------------------------------------------------------------------

## Host: practice -> the real round. Scores and knock-outs reset, walkers go back to their spots.
func begin_play() -> void:
	practice = false
	play_t = 0.0
	out.clear()
	stun.clear()
	for id in items.keys():
		remove_item(int(id))
	for p in pids:
		score[p] = 0.0
	var ws := walkers()
	for i in ws.size():
		var p: int = ws[i]
		pos[p] = start_pos(i, ws.size())
		(avatars[p] as Node3D).position = pos[p]
	on_begin()


## Host: one frame.
func tick(delta: float) -> void:
	if not practice:
		play_t += delta
	play_tick(delta)


## Every machine: animate the walkers (walk cycle from how far they moved).
func _process(delta: float) -> void:
	if not host:
		for p in _targets:
			if not avatars.has(p):
				continue
			var tg: Array = _targets[p]
			var a: Node3D = avatars[p]
			a.position = a.position.lerp(tg[0], 1.0 - exp(-14.0 * delta))
			a.rotation.y = lerp_angle(a.rotation.y, float(tg[1]), 1.0 - exp(-12.0 * delta))
	if not host and pawn_node != null:
		pawn_node.position = pawn_node.position.lerp(_pawn_target, 1.0 - exp(-14.0 * delta))
	for p in avatars:
		var a: Node3D = avatars[p]
		a.visible = not out.has(p) or a.position.y > -6.0  # knocked out: shown while falling, then hidden
		var prev: Vector3 = _last.get(p, a.position)
		var v := Vector2(a.position.x - prev.x, a.position.z - prev.z).length() / maxf(delta, 0.001)
		Creatures.anim(a).walk(v if v > 0.4 else 0.0)
		_last[p] = a.position


## Host, 30 Hz: walkers + scores + the minigame's own data.
func snapshot() -> Array:
	var w := PackedFloat32Array()
	for p in walkers():
		var a: Node3D = avatars[p]
		w.append_array([snappedf(a.position.x, 0.01), snappedf(a.position.y, 0.01), snappedf(a.position.z, 0.01),
			snappedf(a.rotation.y, 0.01), 1.0 if out.has(p) else 0.0])
	var sc := PackedInt32Array()
	for p in pids:
		sc.append(int(score.get(p, 0.0)))
	return [w, sc, snap_extra(), items_snap(), pawn]


## TV machine: mirror the host.
func apply_snapshot(s: Array) -> void:
	if s.size() < 3:
		return
	var w: PackedFloat32Array = s[0]
	var ws := walkers()
	for i in ws.size():
		var o := i * 5
		if o + 4 >= w.size():
			break
		var p: int = ws[i]
		_targets[p] = [Vector3(w[o], w[o + 1], w[o + 2]), w[o + 3]]
		if w[o + 4] > 0.5:
			out[p] = true
		else:
			out.erase(p)
	var sc: PackedInt32Array = s[1]
	for i in mini(sc.size(), pids.size()):
		score[pids[i]] = float(sc[i])
	unsnap_extra(s[2])
	if s.size() >= 5:
		items_apply(s[3])
		_pawn_target = s[4]
