extends "res://games/party_board/minigames/mg_base.gd"
## KART DASH (free for all): a drag race of little push-karts. Mash A to go faster (islanders);
## the GIANT pumps a glove up and down like a handcar (or mashes the trigger). Karts that fall
## behind get a little tailwind, so everyone stays in the race. First over the line wins.

const META := {
	"name": "KART DASH",
	"goal": "Race to the chequered flag! The faster you mash, the faster you go.",
	"format": "ffa", "time": 30.0, "music": "race", "cam": [11.0, 14.0],
	"tv": [["A", "MASH to speed up!"]],
	"vr": [["GLOVE", "Pump up and down"], ["TRIGGER", "Or mash it"]],
	"vr_line": "PUMP your glove up and down to race!",
}
const START_X := 7.5
const FINISH_X := -7.5
const VMAX := 1.25
const PUMP := 1.1  # arena units a glove must travel for one pump

var karts := {}  # pid -> Node3D
var prog := {}  # pid -> 0..1
var rate := {}  # pid -> presses per second (decaying)
var order: Array = []  # finish order
var _first_t := -1.0
var _pump_dir := 0
var _pump_from := 0.0
var _cpu_next := {}
var _bot_t := 0.0


func build() -> void:
	arena_r = 9.0
	build_island(9.0, Color(0.5, 0.74, 0.38))
	var b := MeshKit.Builder.new()
	var n := pids.size()
	for i in n:
		var z := lane_z(i, n)
		b.box(Vector3(START_X - FINISH_X + 2.0, 0.06, 1.15), MeshKit.at(Vector3((START_X + FINISH_X) * 0.5, 0.03, z)), Color(0.42, 0.42, 0.46) if i % 2 == 0 else Color(0.48, 0.48, 0.52))
	# Chequered finish line + start line + flags.
	var w := float(n) * 1.25 + 0.4
	for k in 10:
		for r in 2:
			b.box(Vector3(0.3, 0.07, w / 10.0), MeshKit.at(Vector3(FINISH_X - r * 0.3, 0.05, -w * 0.5 + (k + 0.5) * w / 10.0)),
				Color(1, 1, 1) if (k + r) % 2 == 0 else Color(0.1, 0.1, 0.1))
	b.box(Vector3(0.18, 0.07, w), MeshKit.at(Vector3(START_X + 0.6, 0.05, 0)), Color(1, 1, 1))
	for s in [-1.0, 1.0]:
		b.cylinder(0.08, 0.08, 3.0, MeshKit.at(Vector3(FINISH_X - 0.3, 1.5, s * (w * 0.5 + 0.3))), Color(0.9, 0.9, 0.9), 8)
		b.box(Vector3(0.05, 0.8, 1.1), MeshKit.at(Vector3(FINISH_X - 0.3, 2.6, s * (w * 0.5 + 0.3) - s * 0.55)), Color(0.15, 0.15, 0.15))
	add_child(MeshKit.instance(b.build(), false))
	for i in n:
		var p: int = pids[i]
		var k := _make_kart(p)
		k.position = Vector3(START_X, 0, lane_z(i, n))
		add_child(k)
		karts[p] = k
		prog[p] = 0.0
		rate[p] = 0.0


func lane_z(i: int, n: int) -> float:
	return (float(i) - float(n - 1) * 0.5) * 1.25


func _make_kart(pid: int) -> Node3D:
	var b := MeshKit.Builder.new()
	var c := color_of(pid)
	b.rounded_box(Vector3(1.5, 0.45, 0.85), 0.15, MeshKit.at(Vector3(0, 0.45, 0)), c)
	b.box(Vector3(0.3, 0.5, 0.75), MeshKit.at(Vector3(0.55, 0.85, 0)), c.darkened(0.25))
	for wx in [-0.5, 0.5]:
		for wz in [-0.45, 0.45]:
			b.cylinder(0.24, 0.24, 0.16, MeshKit.at(Vector3(wx, 0.24, wz), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(0.12, 0.12, 0.12), 10)
	if giant and pid == 0:  # the giant's kart has a big pump handle instead of a driver
		b.cylinder(0.06, 0.06, 1.2, MeshKit.at(Vector3(0, 1.2, 0)), Color(0.5, 0.35, 0.2), 6)
		b.box(Vector3(0.12, 0.12, 1.0), MeshKit.at(Vector3(0, 1.8, 0)), Color(0.5, 0.35, 0.2))
		b.sphere(0.25, MeshKit.at(Vector3(0, 1.2, 0)), color_of(0), 8, true)
	return MeshKit.instance(b.build(), false)


func start_pos(i: int, _n: int) -> Vector3:
	var ws := walkers()
	var p: int = ws[i] if i < ws.size() else 0
	return Vector3(START_X, 0.35, lane_z(pids.find(p), pids.size()))


func on_begin() -> void:
	order.clear()
	_first_t = -1.0
	for p in pids:
		prog[p] = 0.0
		rate[p] = 0.0


func _press(pid: int) -> void:
	rate[pid] = float(rate.get(pid, 0.0)) + 1.0
	if karts.has(pid) and rng.randf() < 0.3:
		fx("puff", [pid])


func play_tick(delta: float) -> void:
	if practice:
		# Practice: mashing revs the engines on the spot.
		for p in walkers():
			if bool(input_of(p)["pressed"]):
				_press(p)
		_giant_pump()
		for p in pids:
			rate[p] = float(rate[p]) * exp(-2.5 * delta)
		return
	for p in walkers():
		if is_cpu(p):
			_cpu_next[p] = float(_cpu_next.get(p, 0.0)) - delta
			if float(_cpu_next[p]) <= 0.0:
				var kid: bool = main.flow != null and main.flow.is_kid()
				_cpu_next[p] = 1.0 / rng.randf_range(3.6 if kid else 4.2, 5.4 if kid else 6.2)
				_press(p)
		elif bool(input_of(p)["pressed"]):
			_press(p)
	_giant_pump()
	var lead := 0.0
	for p in pids:
		lead = maxf(lead, float(prog[p]))
	for p in pids:
		rate[p] = float(rate[p]) * exp(-2.5 * delta)
		if order.has(p):
			continue
		# rate settles near presses/s / 2.5: 6 presses/s ~ top speed.
		var v := VMAX * clampf(float(rate[p]) / 2.4, 0.0, 1.0)
		v *= 1.0 + clampf((lead - float(prog[p])) * 2.0, 0.0, 0.25)  # tailwind for the karts behind
		prog[p] = minf(1.0, float(prog[p]) + v * delta / (START_X - FINISH_X))
		if float(prog[p]) >= 1.0:
			order.append(p)
			add_score(p, 100 - 10 * order.size())
			fx("finish", [p, order.size()])
			if _first_t < 0.0:
				_first_t = play_t
		score[p] = float(int(float(prog[p]) * 50.0)) + (100.0 - 10.0 * (order.find(p) + 1) if order.has(p) else 0.0)
	for p in walkers():
		var i := pids.find(p)
		var x := lerpf(START_X, FINISH_X, float(prog[p]))
		pos[p] = Vector3(x, 0.35, lane_z(i, pids.size()))
		(avatars[p] as Node3D).position = pos[p]
		(avatars[p] as Node3D).rotation.y = -PI * 0.5


## The giant: one pump = the glove travels PUMP units up then down (or a trigger pull).
func _giant_pump() -> void:
	if not giant:
		return
	var hs := giant_hands()
	if hs.size() < 2:
		return
	var y: float = hs[1].y
	if _pump_dir >= 0:
		if y > _pump_from:
			_pump_from = y
		elif _pump_from - y > PUMP:
			_pump_dir = -1
			_pump_from = y
			_press(0)
			buzz(1, 0.35, 0.03)
	else:
		if y < _pump_from:
			_pump_from = y
		elif y - _pump_from > PUMP:
			_pump_dir = 1
			_pump_from = y
	if main.vr_rig != null and main.vr_rig.trigger_pressed():
		_press(0)
		buzz(1, 0.25, 0.02)


func finished() -> bool:
	return order.size() >= pids.size() or (_first_t >= 0.0 and play_t - _first_t > 4.0)


func snap_extra() -> Array:
	var pr := PackedFloat32Array()
	for p in pids:
		pr.append(float(prog[p]))
	return [pr]


func unsnap_extra(a: Array) -> void:
	if a.is_empty():
		return
	var pr: PackedFloat32Array = a[0]
	for i in mini(pr.size(), pids.size()):
		prog[pids[i]] = pr[i]


func on_fx(kind: String, args: Variant) -> void:
	var a: Array = args
	match kind:
		"puff":
			if karts.has(int(a[0])):
				var k: Node3D = karts[int(a[0])]
				burst_at(k.position + Vector3(0.9, 0.3, 0), Color(0.85, 0.85, 0.85), 4)
		"finish":
			var p: int = a[0]
			var place: int = a[1]
			var k: Node3D = karts.get(p, null)
			if k != null:
				burst_at(k.position + Vector3(0, 1.0, 0), color_of(p), 20)
				popup_at(k.position, HudKit.ordinal(place) + "!", color_of(p))
			main.sfx.play("fanfare" if place == 1 else "ding", -4.0)
			if avatars.has(p):
				Creatures.anim(avatars[p]).play("victory" if place == 1 else "cheer", 2.0)


func _process(delta: float) -> void:
	super(delta)
	var n := pids.size()
	for i in n:
		var p: int = pids[i]
		var k: Node3D = karts[p]
		var want := Vector3(lerpf(START_X, FINISH_X, float(prog[p])), 0, lane_z(i, n))
		k.position = k.position.lerp(want, 1.0 - exp(-12.0 * delta))
		k.rotation.z = -0.04 * clampf(float(rate.get(p, 0.0)) / 2.4, 0.0, 1.0) * sin(Time.get_ticks_msec() * 0.03)


func cpu_move(_pid: int) -> Vector3:
	return Vector3.ZERO


func cpu_press(_pid: int) -> bool:
	return true


func bot_vr_goal() -> Vector3:
	_bot_t += get_process_delta_time()
	var k: Node3D = karts.get(0, null)
	var base := k.position if k != null else Vector3.ZERO
	return base + Vector3(0, 3.0 + 1.2 * signf(sin(_bot_t * 8.0)), 2.0)
