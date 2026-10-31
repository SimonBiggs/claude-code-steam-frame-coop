extends "res://games/party_board/minigames/mg_base.gd"
## FISH POND (free for all; from the arcade's Fishing Lake): everyone sits at their own spot round the pond with
## a bobber in the water. When YOUR bobber dips and splashes, a fish is biting: press A to reel it in (gold
## fish are worth 3). Press too early and the line just plops back for a moment. Everyone gets the very same
## bites at the very same times (one seeded list), so it's fair for any number of players: no running, no
## pushing, just watch and press - and the bite waits a long time for little hands. The GIANT taps their own
## bobber (or pulls the trigger).

const META := {
	"name": "FISH POND",
	"goal": "When your bobber splashes, press A to catch the fish!",
	"format": "ffa", "time": 24.0, "music": "cosy", "cam": [13.0, 11.0],
	"tv": [["A", "Catch the fish when it bites"]],
	"vr": [["GLOVE", "Tap your bobber when it splashes"]],
	"vr_line": "TAP your bobber when a fish bites!",
	"cue": "pop",
}
const POND_R := 3.2
const SEAT_R := 4.7
const BITE_T := 1.5  ## seconds a fish keeps biting
const OOPS_T := 0.8  ## an early press: the line plops back for this long
const GAP := Vector2(1.5, 2.9)  ## seconds between bites

var fishers: Array[int] = []  ## everyone fishing (walkers and the giant)
var bites: Array = []  ## [time, gold] for the whole round (shared by everyone)
var state := {}  ## pid -> 0 waiting, 1 biting, 2 oops / reeling
var _st_t := {}  ## pid -> seconds left in state 1 / 2
var _next := {}  ## pid -> index of their next bite
var _gold := {}  ## pid -> the biting fish is gold
var _cpu_at := {}  ## pid -> seconds until this CPU presses (-1 = it won't)
var bobbers := {}  ## pid -> Node3D
var _clock := 0.0


func build() -> void:
	arena_r = SEAT_R
	build_island(SEAT_R + 1.4, Color(0.46, 0.74, 0.36))
	var b := MeshKit.Builder.new()
	b.cylinder(POND_R + 0.35, POND_R + 0.45, 0.16, MeshKit.at(Vector3(0, 0.02, 0)), Color(0.62, 0.6, 0.56), 32)
	b.cylinder(POND_R, POND_R, 0.06, MeshKit.at(Vector3(0, 0.1, 0)), Color(0.25, 0.55, 0.85), 32)
	for k in 5:
		var a := k * TAU / 5.0 + 0.4
		b.ellipsoid(Vector3(0.45, 0.04, 0.32), MeshKit.at(Vector3(cos(a) * 1.6, 0.14, sin(a) * 1.6)), Color(0.35, 0.7, 0.35), 8)
	add_child(MeshKit.instance(b.build(), false))
	fishers.clear()
	for p in walkers():
		fishers.append(p)
	if giant:
		fishers.push_front(0)
	for i in fishers.size():
		var p := fishers[i]
		var bn := MeshKit.instance(ResCache.get_or_make("pb_bobber", func() -> Resource:
			var bb := MeshKit.Builder.new()
			bb.sphere(0.2, MeshKit.at(Vector3(0, 0.12, 0)), Color(0.95, 0.25, 0.25), 10)
			bb.dome(0.2, MeshKit.at(Vector3(0, 0.12, 0)), Color(1, 1, 1), 10)
			bb.cylinder(0.025, 0.025, 0.3, MeshKit.at(Vector3(0, 0.38, 0)), Color(0.95, 0.95, 0.95), 4)
			return bb.build()), false)
		bn.position = seat(i) * ((POND_R - 1.0) / SEAT_R) + Vector3(0, 0.12, 0)
		add_child(bn)
		bobbers[p] = bn
		var ring := MeshKit.Builder.new()
		ring.torus(0.34, 0.05, MeshKit.at(Vector3(0, 0.02, 0)), color_of(p), 14, 4, true)
		var rn := MeshKit.instance(ring.build(), false)
		bn.add_child(rn)


## Fisher i's seat round the pond (the giant, first, sits on the VR player's side: +Z).
func seat(i: int) -> Vector3:
	var a := PI * 0.5 + TAU * float(i) / float(maxi(1, fishers.size()))
	return Vector3(cos(a), 0, sin(a)) * SEAT_R


func start_pos(i: int, n: int) -> Vector3:
	var k := i + (1 if giant else 0)
	var a := PI * 0.5 + TAU * float(k) / float(maxi(1, n + (1 if giant else 0)))
	return Vector3(cos(a), 0, sin(a)) * SEAT_R


func _ready() -> void:
	super()
	for p in walkers():
		var a: Node3D = avatars[p]
		Creatures.anim(a).face(-a.position)


## The round's bites (everyone the same), from the minigame's seed.
func on_begin() -> void:
	bites.clear()
	var r := RandomNumberGenerator.new()
	r.seed = int(cfg.get("seed", 1)) * 31 + 7
	var t := 1.2
	while t < time_limit + 30.0:
		bites.append([t, r.randf() < 0.15])
		t += r.randf_range(GAP.x, GAP.y) + BITE_T
	_clock = 0.0
	for p in fishers:
		state[p] = 0
		_st_t[p] = 0.0
		_next[p] = 0
		_cpu_at[p] = -1.0


func play_tick(delta: float) -> void:
	if bites.is_empty():
		on_begin()
	_clock += delta
	var hs := giant_hands()
	for p in fishers:
		var st := int(state.get(p, 0))
		var pressed := false
		if p == 0 and giant:
			# a tap on the biting bobber reels it in (a glove resting there while waiting is no early press)
			var bn: Node3D = bobbers[p]
			for h in hs.size():
				if st == 1 and hs[h].distance_to(bn.position) < HAND_R:
					pressed = true
			if main.vr_rig != null and main.vr_rig.trigger_pressed():
				pressed = true
		elif is_cpu(p):
			pressed = _cpu_press(p, delta)
		else:
			pressed = bool(input_of(p)["pressed"])
		_st_t[p] = float(_st_t.get(p, 0.0)) - delta
		var nb := int(_next.get(p, 0))
		match st:
			0:
				if nb < bites.size() and _clock >= float(bites[nb][0]):
					state[p] = 1
					_st_t[p] = BITE_T
					_gold[p] = bool(bites[nb][1])
					_next[p] = nb + 1
					fx("bite", [p, bool(_gold[p])])
					if is_cpu(p):
						var kid: bool = main.flow != null and main.flow.is_kid()
						_cpu_at[p] = rng.randf_range(0.45, 1.25) if rng.randf() > (0.25 if kid else 0.1) else -1.0
				elif pressed:
					state[p] = 2
					_st_t[p] = OOPS_T
					fx("oops", [p])
			1:
				if pressed:
					var worth := 3 if bool(_gold.get(p, false)) else 1
					add_score(p, worth)
					state[p] = 2
					_st_t[p] = 0.5
					fx("catch", [p, worth])
					if p == 0:
						buzz(1, 0.7, 0.08)
				elif float(_st_t[p]) <= 0.0:
					state[p] = 0
					fx("away", [p])
			2:
				if float(_st_t[p]) <= 0.0:
					state[p] = 0
					# a bite that came while the line was out is skipped (everyone keeps the same list)
					while int(_next[p]) < bites.size() and _clock >= float(bites[int(_next[p])][0]) + BITE_T:
						_next[p] = int(_next[p]) + 1
	_animate()


func _cpu_press(p: int, delta: float) -> bool:
	if int(state.get(p, 0)) != 1:
		return false
	var t := float(_cpu_at.get(p, -1.0))
	if t < 0.0:
		return false
	t -= delta
	_cpu_at[p] = t
	return t <= 0.0


## Bobbers bob (and dip and splash while a fish bites).
func _animate() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i in fishers.size():
		var p := fishers[i]
		var bn: Node3D = bobbers[p]
		var st := int(state.get(p, 0))
		var y := 0.12 + 0.03 * sin(t * 2.0 + i)
		if st == 1:
			y = 0.0 - 0.12 * absf(sin(t * 14.0))
		bn.position.y = y
		bn.scale = Vector3.ONE * (1.25 if st == 1 else 1.0)


func snap_extra() -> Array:
	var s := PackedByteArray()
	for p in fishers:
		s.append(int(state.get(p, 0)))
	return [s]


func unsnap_extra(a: Array) -> void:
	if a.is_empty():
		return
	var s: PackedByteArray = a[0]
	for i in mini(s.size(), fishers.size()):
		state[fishers[i]] = int(s[i])


func _process(delta: float) -> void:
	super(delta)
	if not host:
		_animate()


func on_fx(kind: String, args: Variant) -> void:
	var a: Array = args
	var p := int(a[0])
	if not bobbers.has(p):
		return
	var at: Vector3 = (bobbers[p] as Node3D).position
	match kind:
		"bite":
			burst_at(at, Color(1.0, 0.95, 0.5) if bool(a[1]) else Color(0.6, 0.85, 1.0), 10)
			main.sfx.play("splash", -6.0, 1.3)
		"catch":
			burst_at(at + Vector3(0, 0.6, 0), color_of(p), 14)
			popup_at(at, "+%d" % int(a[1]), color_of(p))
			main.sfx.play("correct" if int(a[1]) == 1 else "fanfare", -4.0, 1.2)
			if avatars.has(p):
				Creatures.anim(avatars[p]).play("cheer", 0.6)
			_jump_fish(at, p, int(a[1]) > 1)
		"oops":
			main.sfx.play("pop", -10.0, 0.7)
		"away":
			main.sfx.play("swish", -12.0, 0.8)


## A fish leaps out of the water towards its fisher.
func _jump_fish(at: Vector3, p: int, gold: bool) -> void:
	var b := MeshKit.Builder.new()
	var c := Color(1.0, 0.82, 0.25) if gold else Color(0.45, 0.7, 1.0)
	b.ellipsoid(Vector3(0.22, 0.18, 0.42), MeshKit.at(Vector3.ZERO), c, 10, gold)
	b.wedge(Vector3(0.05, 0.3, 0.25), MeshKit.at(Vector3(0, 0, -0.45)), c.darkened(0.2))
	var f := MeshKit.instance(b.build(), false)
	add_child(f)
	f.position = at
	var to := at.lerp(where(p) if avatars.has(p) else at * 1.4, 0.8) + Vector3(0, 0.5, 0)
	var tw := f.create_tween()
	tw.tween_method(func(k: float) -> void:
		f.position = at.lerp(to, k) + Vector3(0, sin(k * PI) * 2.0, 0)
		f.rotation.x = -k * TAU, 0.0, 1.0, 0.6)
	tw.tween_callback(f.queue_free)


## Bots (and the arcade's bot players): press while your fish bites.
func cpu_press(pid: int) -> bool:
	return int(state.get(pid, 0)) == 1


func bot_vr_goal() -> Vector3:
	if giant and bobbers.has(0) and int(state.get(0, 0)) == 1:
		return (bobbers[0] as Node3D).position
	return (bobbers[0] as Node3D).position + Vector3(0, 1.2, 0) if giant and bobbers.has(0) else Vector3(0, 2.0, 2.0)


func touch_goal() -> Vector3:
	return ((bobbers[0] as Node3D).position if giant and bobbers.has(0) else Vector3.ZERO) + Vector3(0, 0.6, 0)
