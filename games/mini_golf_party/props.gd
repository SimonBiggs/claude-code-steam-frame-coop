extends Node3D
## Toys round the tee for the VR golfer (Simon's rule: everything you can reach does something):
##   - a bucket of spare balls on a stand: grab one with the right trigger and throw it (they bounce
##     on the lawn and pop back into the bucket a few seconds later);
##   - a rubber duck on a little pond: touch it and it quacks and hops (it also cheers every sink);
##   - two round bushes: touch them and they wobble and rustle;
##   - (in course.gd) the flag at the cup waves when touched and the windmill sails spin faster.
## Host simulates; touches go to the TV as "prop" events and the spare balls' positions ride in the
## snapshot. Cheap: one merged mesh per toy.

const MeshKit := preload("res://core/mesh_kit.gd")
const VrRig := preload("res://core/vr_rig.gd")

const SPARES := 3
const BUCKET := Vector3(-0.8, 0.0, 0.3)  # from the tee
const POND := Vector3(1.3, 0.0, -0.2)
const BUSHES: Array[Vector3] = [Vector3(-1.15, 0.0, -0.9), Vector3(1.2, 0.0, -1.5)]
const SPARE_COLORS: Array[Color] = [Color(1.0, 0.95, 0.4), Color(1.0, 0.55, 0.8), Color(0.55, 0.95, 1.0)]

var main
var anchor := Vector3.ZERO
var spares: Array[MeshInstance3D] = []
var spare_vel: Array[Vector3] = []
var spare_t: Array[float] = []  # seconds since thrown (-1 = in the bucket)
var held := -1
var duck: Node3D
var duck_hop := 0.0
var bushes: Array[Node3D] = []
var bush_wob: Array[float] = []
var touched := {}  # kind -> true once (bots)
var _touching := {}
var _t := 0.0


func _ready() -> void:
	var b := MeshKit.Builder.new()
	# Bucket stand (hip height, so nobody has to bend down) and the pond.
	b.cylinder(0.03, 0.04, 0.62, MeshKit.at(BUCKET + Vector3(0.0, 0.31, 0.0)), Color(0.6, 0.4, 0.25), 8)
	b.cylinder(0.13, 0.1, 0.12, MeshKit.at(BUCKET + Vector3(0.0, 0.68, 0.0)), Color(0.35, 0.6, 1.0), 12)
	b.cylinder(0.45, 0.45, 0.02, MeshKit.at(POND + Vector3(0.0, 0.01, 0.0)), Color(0.35, 0.7, 1.0), 16)
	b.torus(0.46, 0.04, MeshKit.at(POND + Vector3(0.0, 0.02, 0.0)), Color(0.75, 0.72, 0.68), 16, 5)
	add_child(MeshKit.instance(b.build()))
	for i in SPARES:
		var sb := MeshKit.Builder.new()
		sb.sphere(0.045, MeshKit.at(Vector3.ZERO), SPARE_COLORS[i], 12)
		var mi := MeshKit.instance(sb.build())
		add_child(mi)
		spares.append(mi)
		spare_vel.append(Vector3.ZERO)
		spare_t.append(-1.0)
	duck = Node3D.new()
	var db := MeshKit.Builder.new()
	db.ellipsoid(Vector3(0.1, 0.075, 0.13), MeshKit.at(Vector3(0.0, 0.07, 0.0)), Color(1.0, 0.88, 0.2), 12)
	db.sphere(0.06, MeshKit.at(Vector3(0.0, 0.17, -0.08)), Color(1.0, 0.9, 0.25), 12)
	db.cone(0.03, 0.06, MeshKit.at(Vector3(0.0, 0.16, -0.15), Vector3.ONE, Vector3(-PI * 0.5, 0.0, 0.0)), Color(1.0, 0.5, 0.15), 8)
	db.sphere(0.012, MeshKit.at(Vector3(0.03, 0.19, -0.12)), Color.BLACK, 6)
	db.sphere(0.012, MeshKit.at(Vector3(-0.03, 0.19, -0.12)), Color.BLACK, 6)
	duck.add_child(MeshKit.instance(db.build()))
	duck.scale = Vector3.ONE * 1.4
	add_child(duck)
	for i in BUSHES.size():
		var n := Node3D.new()
		n.position = BUSHES[i]
		var bb := MeshKit.Builder.new()
		bb.sphere(0.32, MeshKit.at(Vector3(0.0, 0.3, 0.0)), Color(0.25, 0.62, 0.3), 12)
		bb.sphere(0.22, MeshKit.at(Vector3(0.2, 0.42, 0.08)), Color(0.3, 0.7, 0.35), 10)
		bb.sphere(0.045, MeshKit.at(Vector3(-0.15, 0.5, -0.2)), Color(1.0, 0.4, 0.5), 6)
		bb.sphere(0.045, MeshKit.at(Vector3(0.12, 0.6, -0.15)), Color(1.0, 0.85, 0.3), 6)
		n.add_child(MeshKit.instance(bb.build()))
		add_child(n)
		bushes.append(n)
		bush_wob.append(0.0)
	_reset_spares()


## Move the toys to the new hole's tee.
func move_to(tee: Vector3) -> void:
	anchor = tee
	position = tee
	held = -1
	_reset_spares()


func _reset_spares() -> void:
	for i in spares.size():
		spares[i].position = BUCKET + Vector3((i - 1) * 0.06, 0.76, 0.0)
		spare_vel[i] = Vector3.ZERO
		spare_t[i] = -1.0


func _is_host() -> bool:
	return main.net.mode != "client"


func _process(delta: float) -> void:
	_t += delta
	duck_hop = maxf(0.0, duck_hop - delta)
	var hop := sin(duck_hop / 0.6 * PI) if duck_hop > 0.0 else 0.0
	duck.position = POND + Vector3(sin(_t * 0.4) * 0.15, 0.02 + hop * 0.15 + sin(_t * 2.0) * 0.005, cos(_t * 0.4) * 0.12)
	duck.rotation.y = -_t * 0.4 + hop * TAU
	for i in bushes.size():
		bush_wob[i] = maxf(0.0, bush_wob[i] - delta)
		var w := bush_wob[i]
		bushes[i].rotation.z = sin(_t * 16.0) * w * 0.25
		bushes[i].scale = Vector3.ONE * (1.0 + sin(_t * 20.0) * w * 0.06)
	if not _is_host():
		return
	var rig = main.vr_rig
	if rig != null:
		_touches(rig)
		_grab(rig)
	_fly(delta)


func _touches(rig) -> void:
	_touch("duck", duck.global_position + Vector3.UP * 0.15, 0.2, rig)
	for i in bushes.size():
		_touch("bush%d" % i, bushes[i].global_position + Vector3.UP * 0.35, 0.38, rig)
	var c = main.course
	if c != null and c.flag != null:
		_touch("flag", c.flag.global_position + Vector3(0.15, -0.1, 0.0), 0.2, rig)
	if c != null and c.sails != null:
		_touch("mill", c.sails.global_position, 0.6, rig)


func _touch(key: String, p: Vector3, r: float, rig) -> void:
	var hand: int = rig.touching_any(p, r)
	if hand < 0:
		_touching.erase(key)
		return
	if _touching.has(key):
		return
	_touching[key] = true
	rig.pulse(hand, 0.4, 0.06)
	poke(key)
	main.net.event("prop", [key])


## Every machine: a toy was touched.
func poke(key: String) -> void:
	touched[key.rstrip("0123456789")] = true
	match key:
		"duck":
			cheer()
		"flag":
			if main.course != null:
				main.course.flag_wave = 1.5
			main.sfx.play("swish", -4.0, 1.3)
		"mill":
			if main.course != null:
				main.course.mill_boost = 3.0
			main.sfx.play("whoosh", -4.0)
		_:
			if key.begins_with("bush"):
				var i := int(key.substr(4))
				if i >= 0 and i < bush_wob.size():
					bush_wob[i] = 0.8
				main.sfx.play("swish", -6.0, 0.8)


## The duck hops and quacks (a touch, or someone sank a putt).
func cheer() -> void:
	duck_hop = 0.6
	main.sfx.play("honk", -4.0, 1.5)


func _grab(rig) -> void:
	if held >= 0:
		var hp: Vector3 = rig.hand_point(VrRig.RIGHT)
		spares[held].global_position = hp
		if not rig.trigger_down():
			spare_vel[held] = rig.hand_velocity(VrRig.RIGHT) * 1.3
			spare_t[held] = 0.0
			main.sfx.play("whoosh", -6.0)
			held = -1
			main.on_spare_released()
		return
	if not rig.trigger_pressed():
		return
	for i in spares.size():
		if rig.touching(VrRig.RIGHT, spares[i].global_position, 0.16):
			held = i
			spare_t[i] = -2.0
			touched["spare"] = true
			rig.pulse(VrRig.RIGHT, 0.5, 0.05)
			main.sfx.play("pickup", -6.0)
			main.on_spare_grabbed()
			return


## True while a spare ball is in the hand (the putter hides).
func holding() -> bool:
	return held >= 0


func _fly(delta: float) -> void:
	for i in spares.size():
		if spare_t[i] < 0.0:
			continue
		spare_t[i] += delta
		if spare_t[i] > 6.0:
			spares[i].position = BUCKET + Vector3((i - 1) * 0.06, 0.76, 0.0)
			spare_t[i] = -1.0
			continue
		var v := spare_vel[i]
		v.y -= 9.8 * delta
		var p := spares[i].global_position + v * delta
		if p.y < 0.045:
			p.y = 0.045
			if v.y < -0.8:
				main.sfx.play_at("bounce", p, -10.0)
			v.y = -v.y * 0.45
			v.x *= 0.8
			v.z *= 0.8
		spares[i].global_position = p
		spare_vel[i] = v


func spare_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for s in spares:
		out.append(s.position)
	return out


func set_spare_positions(p: PackedVector3Array) -> void:
	for i in mini(p.size(), spares.size()):
		spares[i].position = spares[i].position.lerp(p[i], 0.5)
