extends Node3D
## Simple mode: stage toys around the VR drummer's kit, all within reach (Simon's rule: "everything
## should be interactable"). They hang off the kit (rig), so they come along when it is recentred and
## fit the player's size like the drums (x / y scale with kit_s, the forward distance doesn't).
##  - COWBELL (left): touch it - TONK, it swings.
##  - MICROPHONE (left, by your cheek): touch it - the crowd cheers, it bobs.
##  - little AMP (left, low): touch it - a big bass DUM, the speaker stacks pump.
##  - SPLASH cymbal (right): touch it - a bright crash, it wobbles.
##  - SPOTLIGHT (right, low): touch it - it spins round, changes colour and so do the stage beams.
##  - two MARACAS (right, by your hip): touch to rattle them; squeeze the right trigger near one to
##    pick it up and shake it (every change of direction is a shake). Let go: it floats back home.
## Only the host's drummer touches things; the TV gets the touches as "prop" events and a held maraca
## in the snapshot. Cheap: one merged mesh per toy (plus the spotlight's lens), no physics engine.

const MeshKit := preload("res://games/rhythm_band/mesh_kit.gd")

const TOUCH_R := 0.11
const REARM_R := 0.16
const GRAB_R := 0.14
const MIN_SPEED := 0.25
const LAYOUT: Array = [
	["cowbell", Vector3(-0.66, -0.30, -0.34)],
	["mic", Vector3(-0.50, -0.06, -0.12)],
	["amp", Vector3(-0.62, -0.80, -0.04)],
	["splash", Vector3(0.68, -0.20, -0.32)],
	["spot", Vector3(0.64, -0.58, -0.06)],
	["maraca", Vector3(0.48, -0.72, 0.02)],
	["maraca", Vector3(0.60, -0.72, 0.08)],
]
const SPOT_COLORS: Array[Color] = [Color(1.0, 0.3, 0.5), Color(0.3, 0.7, 1.0), Color(1.0, 0.85, 0.2),
	Color(0.4, 1.0, 0.5), Color(0.8, 0.4, 1.0)]

var main
var d  # the drummer
var items: Array = []  # Dictionaries: kind, base, node, wob, wob_v, pulse, spin
var kit_s := 1.0
var inside := PackedByteArray()
var prev_tips: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var have_prev := false
var held := -1  # the maraca in the right hand
var grab_was := false
var shake_dir := Vector3.ZERO
var shake_cd := 0.0
var cheer_cd := 0.0
var spot_i := 0
var spot_mat: StandardMaterial3D
var touched := {}  # kind -> count (the bot reads it)
var shakes := 0
var force_grab := false  # bot: hold the first maraca in the right (fake) hand


func build() -> void:
	for e in LAYOUT:
		var kind: String = e[0]
		var node := Node3D.new()
		add_child(node)
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh(kind, items.size())
		mi.material_override = MeshKit.vertex_material(main.mats)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
		var rest := Vector3.ZERO
		match kind:
			"splash":
				rest = Vector3(0.3, 0.0, -0.15)
			"spot":
				rest = Vector3(-0.7, 0.0, 0.0)  # the lens points up and out at the crowd
				var lens := MeshInstance3D.new()
				lens.mesh = main.cyl_mesh(0.05, 0.05, 0.01, 12)
				spot_mat = StandardMaterial3D.new()
				spot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				spot_mat.albedo_color = SPOT_COLORS[0]
				lens.material_override = spot_mat
				lens.position = Vector3(0.0, 0.075, 0.0)
				node.add_child(lens)
		node.rotation = rest
		items.append({"kind": kind, "base": e[1], "node": node, "rest": rest, "wob": Vector2.ZERO,
			"wob_v": Vector2.ZERO, "pulse": 0.0, "spin": 0.0, "yaw": 0.0})
	inside.resize(items.size() * 2)
	layout(1.0)


func _mesh(kind: String, i: int) -> ArrayMesh:
	var parts: Array = []
	var metal := Color(0.6, 0.6, 0.65)
	var dark := Color(0.12, 0.12, 0.14)
	match kind:
		"cowbell":
			parts.append([MeshKit.cyl(0.032, 0.05, 0.11, 10), MeshKit.at(Vector3.ZERO, Vector3(1.0, 1.0, 0.7), Vector3(PI * 0.5, 0, 0)), Color(0.55, 0.55, 0.6)])
			parts.append([MeshKit.cyl(0.006, 0.006, 0.16, 6), MeshKit.at(Vector3(0.09, 0.0, 0.02), Vector3.ONE, Vector3(0, 0, PI * 0.5)), metal])
		"mic":
			parts.append([MeshKit.sphere(0.04, 10), MeshKit.at(Vector3.ZERO, Vector3(1, 1.25, 1)), Color(0.3, 0.3, 0.33)])
			parts.append([MeshKit.cyl(0.042, 0.042, 0.01, 10), MeshKit.at(Vector3(0, -0.02, 0)), Color(0.9, 0.85, 0.3)])
			parts.append([MeshKit.cyl(0.018, 0.012, 0.12, 8), MeshKit.at(Vector3(0, -0.09, 0)), dark])
			parts.append([MeshKit.cyl(0.007, 0.007, 0.3, 6), MeshKit.at(Vector3(-0.12, -0.2, 0.0), Vector3.ONE, Vector3(0, 0, 0.9)), metal])
		"amp":
			parts.append([MeshKit.box(Vector3(0.26, 0.2, 0.14)), MeshKit.at(Vector3.ZERO), Color(0.15, 0.12, 0.1)])
			parts.append([MeshKit.box(Vector3(0.22, 0.14, 0.01)), MeshKit.at(Vector3(0, -0.015, -0.071)), Color(0.3, 0.28, 0.25)])
			parts.append([MeshKit.cyl(0.055, 0.055, 0.012, 12), MeshKit.at(Vector3(0, -0.015, -0.078), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), dark])
			parts.append([MeshKit.box(Vector3(0.26, 0.03, 0.142)), MeshKit.at(Vector3(0, 0.085, 0)), Color(0.85, 0.75, 0.5)])
			for k in 3:
				parts.append([MeshKit.sphere(0.01, 6), MeshKit.at(Vector3(-0.06 + k * 0.06, 0.085, -0.072)), Color(0.95, 0.95, 0.95)])
		"splash":
			parts.append([MeshKit.cyl(0.13, 0.13, 0.01, 20), MeshKit.at(Vector3.ZERO), Color(0.95, 0.75, 0.3)])
			parts.append([MeshKit.sphere(0.03, 10), MeshKit.at(Vector3(0, 0.006, 0), Vector3(1, 0.5, 1)), Color(1.0, 0.85, 0.45)])
		"spot":
			parts.append([MeshKit.cyl(0.06, 0.07, 0.14, 10), MeshKit.at(Vector3.ZERO), dark])
			parts.append([MeshKit.cyl(0.065, 0.065, 0.02, 10), MeshKit.at(Vector3(0, 0.065, 0)), metal])
			parts.append([MeshKit.box(Vector3(0.17, 0.015, 0.02)), MeshKit.at(Vector3(0, -0.02, 0)), metal])
		"maraca":
			var col := Color(1.0, 0.35, 0.3) if i % 2 == 1 else Color(1.0, 0.8, 0.2)
			parts.append([MeshKit.cyl(0.012, 0.015, 0.11, 6), MeshKit.at(Vector3.ZERO), Color(0.7, 0.45, 0.2)])
			parts.append([MeshKit.sphere(0.045, 10), MeshKit.at(Vector3(0, 0.09, 0), Vector3(1, 1.2, 1)), col])
			parts.append([MeshKit.cyl(0.046, 0.046, 0.012, 10), MeshKit.at(Vector3(0, 0.09, 0)), Color(0.3, 0.8, 1.0)])
	return MeshKit.merge(parts)


## Where the toys sit for this player's size (called from the drummer's _layout_kit).
func layout(s: float) -> void:
	kit_s = s
	for k in items.size():
		if k != held:
			var it: Dictionary = items[k]
			(it.node as Node3D).position = _home(it)


func _home(it: Dictionary) -> Vector3:
	var b: Vector3 = it.base
	return Vector3(b.x * kit_s, b.y * kit_s, b.z)


## Where a hand has to be to touch toy k (a maraca's rattle is above its handle).
func _touch_point(k: int) -> Vector3:
	var it: Dictionary = items[k]
	var n: Node3D = it.node
	if it.kind == "maraca":
		return n.global_transform * Vector3(0, 0.08, 0)
	return n.global_position


## Every frame on every machine (wobbles, spins, a held maraca). tips: the two stick tips; touch: true
## only for the host's own drummer (VR or the bot's fake VR).
func tick(delta: float, tips: Array[Vector3], touch: bool) -> void:
	shake_cd -= delta
	cheer_cd -= delta
	for k in items.size():
		var it: Dictionary = items[k]
		var n: Node3D = it.node
		var w: Vector2 = it.wob
		var wv: Vector2 = it.wob_v
		wv += (-w * 60.0 - wv * 3.0) * delta
		w += wv * delta
		it.wob = w
		it.wob_v = wv
		it.pulse = maxf(0.0, float(it.pulse) - delta * 4.0)
		it.spin = float(it.spin) * exp(-1.5 * delta)
		it.yaw = float(it.yaw) + float(it.spin) * delta
		if k == held:
			continue
		var rest: Vector3 = it.rest
		n.rotation = rest + Vector3(w.x, float(it.yaw), w.y)
		n.scale = Vector3.ONE * (1.0 + 0.25 * float(it.pulse))
		if it.kind == "maraca" and n.position.distance_to(_home(it)) > 0.001:
			n.position = n.position.lerp(_home(it), 1.0 - exp(-8.0 * delta))
	if not touch:
		return
	if not have_prev:
		have_prev = true
		prev_tips[0] = tips[0]
		prev_tips[1] = tips[1]
		return
	for h in 2:
		var tip: Vector3 = tips[h]
		var v := (tip - prev_tips[h]) / maxf(delta, 0.001)
		prev_tips[h] = tip
		if h == 1 and held >= 0:
			_shake(v)
			continue
		for k in items.size():
			if k == held:
				continue
			var dist := tip.distance_to(_touch_point(k))
			var slot := h * items.size() + k
			if dist > REARM_R:
				inside[slot] = 0
			elif dist < TOUCH_R and inside[slot] == 0:
				inside[slot] = 1
				if v.length() > MIN_SPEED:
					_touch(k, v, h)
	_grab(tips)


func _touch(k: int, v: Vector3, h: int) -> void:
	var it: Dictionary = items[k]
	var local_v: Vector3 = global_basis.inverse() * v
	it.wob_v = Vector2(it.wob_v) + Vector2(-local_v.z, local_v.x).limit_length(2.0) * 4.0
	main.prop_touched(k)
	if d.vr:
		var hand: XRController3D = d.hand_l if h == 0 else d.hand_r
		hand.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.05, 0.0)


## Right trigger near a maraca: pick it up; let go: it floats home. (The Frame's left trigger doesn't
## reach the game, so only the right hand picks things up; the left hand can still rattle them.)
func _grab(tips: Array[Vector3]) -> void:
	var want := force_grab
	if d.vr:
		var tv: float = d.hand_r.get_float("trigger")
		want = tv > (0.3 if held >= 0 else 0.6)
	var edge := want and not grab_was
	grab_was = want
	if held < 0 and edge:
		var best := -1
		var bd := GRAB_R
		for k in items.size():
			if items[k].kind != "maraca":
				continue
			var dist := tips[1].distance_to(_touch_point(k))
			if dist < bd or force_grab and best < 0:
				bd = dist
				best = k
		if best >= 0:
			held = best
			shake_dir = Vector3.ZERO
			main.prop_touched(best)
			print("Props: picked up a maraca")
	elif held >= 0 and not want:
		print("Props: put the maraca down")
		held = -1
	if held >= 0:
		var n: Node3D = items[held].node
		if d.vr:
			n.global_transform = d.hand_r.global_transform * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -0.04))
		else:
			n.global_position = tips[1]


## Holding a maraca: every sharp change of direction is a shake.
func _shake(v: Vector3) -> void:
	if v.length() < 0.6:
		return
	var dir := v.normalized()
	if shake_dir != Vector3.ZERO and dir.dot(shake_dir) < -0.3 and shake_cd <= 0.0:
		shake_cd = 0.07
		shakes += 1
		main.prop_touched(held)
	shake_dir = dir


## A toy was touched (host: right after the touch; TV: from the "prop" event): its sound and its move.
func react(k: int) -> void:
	if k < 0 or k >= items.size():
		return
	var it: Dictionary = items[k]
	touched[it.kind] = int(touched.get(it.kind, 0)) + 1
	it.pulse = 1.0
	match str(it.kind):
		"cowbell":
			main.inst.toy("cowbell", -3.0)
		"mic":
			if cheer_cd <= 0.0:
				cheer_cd = 1.5
				main.inst.cheer(-4.0)
			main.inst.chime(1.5)
		"amp":
			main.inst.pluck(40, 0.0)
			main.stage.pump()
		"splash":
			main.inst.toy("drum3", -5.0, 1.45)
			it.wob_v = Vector2(it.wob_v) + Vector2(2.5, 1.0)
		"spot":
			main.inst.toy("whoosh", -8.0)
			it.spin = 14.0
			spot_i = (spot_i + 1) % SPOT_COLORS.size()
			spot_mat.albedo_color = SPOT_COLORS[spot_i]
			main.stage.tint(SPOT_COLORS[spot_i])
		"maraca":
			main.inst.toy("shaker", -3.0)
			it.pulse = 0.3


## Snapshot: the held maraca (index and its kit-local transform) so the TV sees it shaken.
func net_state() -> Array:
	if held < 0:
		return [-1]
	return [held, (items[held].node as Node3D).transform]


func apply_net(s: Array) -> void:
	var h: int = int(s[0]) if s.size() > 0 else -1
	if h != held:
		held = h
	if held >= 0 and held < items.size() and s.size() > 1:
		(items[held].node as Node3D).transform = s[1]
