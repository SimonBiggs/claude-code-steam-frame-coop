extends "res://games/party_board/minigames/mg_base.gd"
## COIN CATCH (free for all): a big money tree in the middle of the island drops coins.
## Islanders run under the falling coins (or over coins on the ground) to grab them.
## The GIANT shakes the tree with a glove (shake hard = a shower of coins) and catches falling
## coins with either glove. Gold coins are worth 3. The tree also drops coins by itself.

const META := {
	"name": "COIN CATCH",
	"goal": "Coins fall from the money tree: grab as many as you can! Gold coins are worth 3.",
	"format": "ffa", "time": 40.0, "music": "party", "cam": [15.0, 13.0],
	"tv": [["L-STICK", "Run under the coins"]],
	"vr": [["GLOVE", "Shake the tree"], ["GLOVES", "Catch falling coins"]],
	"vr_line": "Shake the tree, catch the coins!",
}
const CANOPY := Vector3(0, 6.0, 0)
const CANOPY_R := 3.4
const GRAVITY := 8.0
const GROUND_TIME := 2.5

var tree: Node3D
var vel := {}  # id -> Vector3 (host)
var age := {}  # id -> float (host)
var _auto_t := 0.0
var _shake_t := 0.0
var _prev_hands: Array[Vector3] = []
var _wobble := 0.0
var _bot_t := 0.0


func build() -> void:
	arena_r = 6.5
	build_island(arena_r + 1.0, Color(0.5, 0.78, 0.38))
	tree = Node3D.new()
	var b := MeshKit.Builder.new()
	b.cylinder(0.45, 0.75, 5.0, MeshKit.at(Vector3(0, 2.5, 0)), Color(0.5, 0.33, 0.2), 10)
	b.sphere(2.6, MeshKit.at(CANOPY), Color(0.3, 0.62, 0.28), 14)
	b.sphere(1.8, MeshKit.at(CANOPY + Vector3(1.9, -0.4, 0.4)), Color(0.36, 0.7, 0.3), 12)
	b.sphere(1.8, MeshKit.at(CANOPY + Vector3(-1.8, -0.3, -0.5)), Color(0.33, 0.66, 0.3), 12)
	b.sphere(1.6, MeshKit.at(CANOPY + Vector3(0.2, 1.3, -1.2)), Color(0.36, 0.72, 0.32), 12)
	for k in 9:
		var a := k * TAU / 9.0
		b.sphere(0.32, MeshKit.at(CANOPY + Vector3(cos(a) * 2.4, -0.6 + sin(k * 1.7) * 0.8, sin(a) * 2.4)), Color(1.0, 0.82, 0.25), 8, true)
	tree.add_child(MeshKit.instance(b.build(), false))
	add_child(tree)


func start_pos(i: int, n: int) -> Vector3:
	var a := TAU * float(i) / float(maxi(1, n)) + 0.3
	return Vector3(cos(a), 0, sin(a)) * 4.0


func make_item(kind: int) -> Node3D:
	var mi := MeshKit.instance(MeshKit.prop("coin"), false)
	mi.scale = Vector3.ONE * (2.2 if kind == 1 else 1.6)
	if kind == 1:
		mi.material_override = MeshKit.glow_material()
	return mi


func play_tick(delta: float) -> void:
	for p in walkers():
		walk(p, delta)
	separate()
	# The tree drops coins by itself (more often without a giant to shake it).
	_auto_t -= delta
	if _auto_t <= 0.0:
		_auto_t = 0.5 if giant else 0.3
		_drop(1)
	_giant_shake(delta)
	_fall(delta)


func _drop(n: int) -> void:
	for i in n:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.5, CANOPY_R)
		var p := CANOPY + Vector3(cos(a) * r, rng.randf_range(-1.0, 0.5), sin(a) * r)
		var kind := 1 if rng.randf() < 0.12 else 0
		var id := add_item(kind, p)
		var out_dir := Vector3(cos(a), 0, sin(a))
		vel[id] = out_dir * rng.randf_range(0.8, 3.2) + Vector3(0, rng.randf_range(0.5, 2.5), 0)
		age[id] = 0.0


## The giant shakes the tree: a glove moving fast inside the leaves showers coins.
func _giant_shake(delta: float) -> void:
	var hs := giant_hands()
	if hs.is_empty():
		return
	var shaking := false
	for h in hs.size():
		if _prev_hands.size() == hs.size():
			var speed := hs[h].distance_to(_prev_hands[h]) / maxf(delta, 0.001)
			if hs[h].distance_to(CANOPY) < CANOPY_R + 0.8 and speed > 9.0:
				shaking = true
				if fmod(play_t, 0.2) < delta:
					buzz(h, 0.35, 0.04)
	_prev_hands = hs.duplicate()
	if shaking:
		_shake_t -= delta
		if _shake_t <= 0.0:
			_shake_t = 0.16
			_drop(1)
			fx("shake")
			if rng.randf() < 0.15:
				sound("whoosh", -12.0, 1.4)


func _fall(delta: float) -> void:
	var hs := giant_hands()
	for id in items.keys():
		var n: Node3D = items[id]
		age[id] = float(age.get(id, 0.0)) + delta
		var v: Vector3 = vel.get(id, Vector3.ZERO)
		var p := n.position
		if p.y > 0.25:
			v.y -= GRAVITY * delta
			p += v * delta
			var flat := Vector2(p.x, p.z).limit_length(arena_r)
			p = Vector3(flat.x, p.y, flat.y)
			if p.y <= 0.25:
				p.y = 0.25
				v = Vector3.ZERO
				age[id] = 0.0
				if rng.randf() < 0.3:
					sound("bounce", -14.0, 1.6)
			vel[id] = v
			n.position = p
		elif float(age[id]) > GROUND_TIME:
			_remove(int(id))
			continue
		n.rotation.y += delta * 4.0
		var worth := 3 if int(item_kind[id]) == 1 else 1
		# Gloves catch coins in the air (not the ones just shaken loose).
		if giant and p.y > 0.8 and float(age[id]) > 0.35:
			for h in hs.size():
				if hs[h].distance_to(p) < HAND_R + 0.3:
					_collect(int(id), 0, worth)
					buzz(h, 0.5, 0.05)
					break
			if not items.has(id):
				continue
		for w in walkers():
			var wp: Vector3 = pos[w]
			if p.y < 2.2 and Vector2(wp.x - p.x, wp.z - p.z).length() < 0.95:
				_collect(int(id), w, worth)
				break


func _collect(id: int, pid: int, worth: int) -> void:
	var p: Vector3 = (items[id] as Node3D).position
	add_score(pid, worth)
	fx("got", [p, pid, worth])
	_remove(id)


func _remove(id: int) -> void:
	remove_item(id)
	vel.erase(id)
	age.erase(id)


func on_fx(kind: String, args: Variant) -> void:
	match kind:
		"shake":
			_wobble = 1.0
		"got":
			var a: Array = args
			var p: Vector3 = a[0]
			popup_at(p, "+%d" % int(a[2]), color_of(int(a[1])))
			burst_at(p, Color(1.0, 0.85, 0.3), 8)
			main.sfx.play("coin", -4.0, 1.0 + randf() * 0.2 + (0.3 if int(a[2]) > 1 else 0.0))


func _process(delta: float) -> void:
	super(delta)
	_wobble = maxf(0.0, _wobble - delta * 2.5)
	if tree != null:
		tree.rotation.z = sin(Time.get_ticks_msec() * 0.03) * 0.06 * _wobble
		tree.rotation.x = cos(Time.get_ticks_msec() * 0.027) * 0.04 * _wobble


func cpu_move(pid: int) -> Vector3:
	var me := where(pid)
	var best := Vector3.ZERO
	var bd := INF
	for id in items:
		var p: Vector3 = (items[id] as Node3D).position
		var d := Vector2(p.x - me.x, p.z - me.z).length() + p.y * 0.4
		if d < bd:
			bd = d
			best = Vector3(p.x, 0, p.z)
	if bd == INF:
		return Vector3(sin(play_t + pid) * 3.0, 0, cos(play_t * 0.7 + pid) * 3.0)
	return best


func bot_vr_goal() -> Vector3:
	_bot_t += get_process_delta_time()
	return CANOPY + Vector3(sin(_bot_t * 9.0) * 2.0, 0.0, 1.5)
