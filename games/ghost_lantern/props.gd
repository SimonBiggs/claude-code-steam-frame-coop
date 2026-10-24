extends Node3D
## Simple mode: everything around the lantern-bearer's starting spot reacts to touch (Simon's rule).
## Real-size things within arm's reach of the VR player (who starts at (0, 0, 3) facing -Z):
##  - two CANDLES on a little table (left): touch one to light it, touch it again to puff it out.
##  - a MUSIC BOX on the same table: the lid opens, a tiny ghost dancer twirls, it plays a tune.
##  - a bubbling CAULDRON (right): touch the potion - BLOOP! big bubbles and it changes colour.
##  - a CUCKOO CLOCK on a post (front left): the bird pops out - cuckoo, cuckoo!
##  - a PORTRAIT on an easel (front right): the lady winks and blushes.
##  - a COBWEB on the easel's corner: it wobbles and the little spider drops down and climbs back.
##  - a creaky CUPBOARD (behind left): the door creaks open, a pumpkin grins inside, it bumps shut.
## The VR hands touch them; TV players (and a flat lantern-bearer) bump them by walking into them.
## The host (or local game) checks the touches and sends a "prop" event so the TV plays the same thing.
## Cheap: about 60 small meshes, no lights, no shadows, no physics.

const WorldScript := preload("res://games/ghost_lantern/world.gd")
const TOUCH := {
	# name: [touch point, hand radius, floor spot TV players bump (or null)]
	"candle_a": [Vector3(-0.95, 0.92, 2.5), 0.12, null],
	"candle_b": [Vector3(-0.68, 0.92, 2.45), 0.12, null],
	"music_box": [Vector3(-0.8, 0.86, 2.76), 0.14, Vector3(-0.8, 0.0, 2.6)],
	"cauldron": [Vector3(0.85, 0.62, 2.55), 0.3, Vector3(0.85, 0.0, 2.55)],
	"cuckoo": [Vector3(-1.05, 1.45, 1.9), 0.2, Vector3(-1.05, 0.0, 1.9)],
	"portrait": [Vector3(1.05, 1.35, 1.9), 0.24, Vector3(1.05, 0.0, 1.9)],
	"cobweb": [Vector3(0.92, 1.6, 1.8), 0.14, null],
	"door": [Vector3(-0.95, 0.95, 3.38), 0.25, Vector3(-1.15, 0.0, 3.45)],
}
const TUNE := [1.0, 1.26, 1.5, 2.0, 1.5, 1.26, 1.33, 1.0]
const POTIONS: Array[Color] = [Color(0.45, 1.0, 0.45), Color(0.75, 0.45, 1.0), Color(1.0, 0.5, 0.8), Color(0.45, 0.85, 1.0)]

var main
var t := 0.0
var cool := {}
var touched := {}  # name -> count (the bot reads it)
var flames := {}  # candle name -> MeshInstance3D
var lit := {"candle_a": false, "candle_b": true}
var flame_pop := {}
var lid: Node3D
var dancer: Node3D
var box_t := 0.0
var note_i := 99
var note_t := 0.0
var potion: MeshInstance3D
var potion_mat: StandardMaterial3D
var potion_i := 0
var bubbles: Array[MeshInstance3D] = []
var bloop_t := 0.0
var bird: Node3D
var cuckoo_t := 0.0
var wink_eye: Node3D
var cheeks: Array[Node3D] = []
var wink_t := 0.0
var web: Node3D
var web_ang := 0.0
var web_vel := 0.0
var spider: Node3D
var spider_t := 0.0
var door: Node3D
var door_t := 0.0
var pumpkin_mat: StandardMaterial3D


func _ready() -> void:
	name = "Props"
	_build_table()
	_build_cauldron()
	_build_cuckoo()
	_build_portrait()
	_build_cupboard()


# --- Building ------------------------------------------------------------------

func _mat(c: Color, glow: float = 0.0) -> StandardMaterial3D:
	return main.make_material(c, glow)


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _mi(parent, bm, pos, m)


func _cyl(parent: Node3D, top: float, bottom: float, h: float, pos: Vector3, m: Material, seg: int = 10) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	return _mi(parent, cm, pos, m)


func _ball(parent: Node3D, r: float, pos: Vector3, m: Material, squash: float = 1.0) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0 * squash
	sm.radial_segments = 10
	sm.rings = 5
	return _mi(parent, sm, pos, m)


func _mi(parent: Node3D, mesh: Mesh, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A node at `pos` turned to face the lantern-bearer's starting spot (its front is +Z).
func _facing(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	var to := Vector3(0.0, 0.0, 3.0) - pos
	n.rotation.y = atan2(to.x, to.z)
	add_child(n)
	return n


func _build_table() -> void:
	var wood := _mat(Color(0.32, 0.18, 0.12))
	_cyl(self, 0.32, 0.32, 0.04, Vector3(-0.8, 0.78, 2.6), wood, 16)
	_cyl(self, 0.04, 0.05, 0.76, Vector3(-0.8, 0.38, 2.6), wood, 8)
	_cyl(self, 0.2, 0.22, 0.03, Vector3(-0.8, 0.015, 2.6), wood, 12)
	for c in ["candle_a", "candle_b"]:
		var p: Vector3 = TOUCH[c][0]
		_cyl(self, 0.03, 0.035, 0.12, Vector3(p.x, 0.86, p.z), _mat(Color(0.95, 0.92, 0.82)), 8)
		_cyl(self, 0.05, 0.05, 0.01, Vector3(p.x, 0.805, p.z), _mat(Color(0.8, 0.65, 0.3)), 10)
		flames[c] = _ball(self, 0.025, Vector3(p.x, 0.95, p.z), _mat(Color(1.0, 0.75, 0.3), 6.0), 1.7)
	# Music box: a little painted chest; the lid hinges at the back.
	var box := _facing(Vector3(-0.8, 0.8, 2.76))
	_box(box, Vector3(0.16, 0.08, 0.11), Vector3(0, 0.04, 0), _mat(Color(0.55, 0.25, 0.45)))
	_box(box, Vector3(0.165, 0.012, 0.115), Vector3(0, 0.05, 0), _mat(Color(0.95, 0.8, 0.35), 0.6))
	lid = Node3D.new()
	lid.position = Vector3(0, 0.08, -0.055)
	box.add_child(lid)
	_box(lid, Vector3(0.16, 0.02, 0.11), Vector3(0, 0.01, 0.055), _mat(Color(0.6, 0.3, 0.5)))
	_ball(lid, 0.015, Vector3(0, 0.025, 0.055), _mat(Color(1.0, 0.85, 0.4), 1.5))
	dancer = Node3D.new()
	dancer.position = Vector3(0, 0.06, 0)
	box.add_child(dancer)
	var ghostie := _mat(Color(0.85, 1.0, 0.9), 1.2)
	_ball(dancer, 0.022, Vector3(0, 0.03, 0), ghostie)
	_cyl(dancer, 0.02, 0.008, 0.035, Vector3(0, 0.005, 0), ghostie, 8)
	_ball(dancer, 0.008, Vector3(0, 0.055, 0), _mat(Color(1.0, 0.45, 0.7), 1.0))  # a little bow
	dancer.visible = false


func _build_cauldron() -> void:
	var iron := _mat(Color(0.12, 0.12, 0.14))
	var base := Vector3(0.85, 0.0, 2.55)
	_ball(self, 0.32, base + Vector3(0, 0.36, 0), iron, 0.85)
	_cyl(self, 0.3, 0.3, 0.06, base + Vector3(0, 0.6, 0), iron, 14)
	for i in 3:
		var a := TAU * i / 3.0
		_cyl(self, 0.03, 0.02, 0.14, base + Vector3(cos(a) * 0.2, 0.07, sin(a) * 0.2), iron, 6)
	potion_mat = _mat(POTIONS[0], 1.6)
	potion = _cyl(self, 0.27, 0.27, 0.02, base + Vector3(0, 0.6, 0), potion_mat, 14)
	for i in 4:
		var b := _ball(self, 0.04, base + Vector3(0, 0.62, 0), potion_mat)
		b.set_meta("phase", i * 0.25)
		bubbles.append(b)
	# A few glowing embers underneath.
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		_ball(self, 0.05, base + Vector3(cos(a) * 0.1, 0.03, sin(a) * 0.1), _mat(Color(1.0, 0.45, 0.15), 2.5), 0.6)


func _build_cuckoo() -> void:
	var wood := _mat(Color(0.35, 0.2, 0.12))
	_cyl(self, 0.03, 0.04, 1.3, Vector3(-1.05, 0.65, 1.9), wood, 8)
	_cyl(self, 0.16, 0.18, 0.03, Vector3(-1.05, 0.015, 1.9), wood, 10)
	var house := _facing(Vector3(-1.05, 1.45, 1.9))
	_box(house, Vector3(0.24, 0.26, 0.12), Vector3.ZERO, _mat(Color(0.5, 0.3, 0.18)))
	for s in [-1.0, 1.0]:
		var roof := _box(house, Vector3(0.18, 0.02, 0.15), Vector3(s * 0.07, 0.16, 0), _mat(Color(0.25, 0.4, 0.2)))
		roof.rotation.z = -s * 0.6
	var face := _cyl(house, 0.07, 0.07, 0.01, Vector3(0, -0.04, 0.062), _mat(Color(0.95, 0.9, 0.75), 0.6), 14)
	face.rotation.x = PI / 2.0
	for k in 2:
		var hand := _box(house, Vector3(0.008, 0.06, 0.004), Vector3(0, -0.04, 0.07), _mat(Color(0.1, 0.08, 0.06)))
		hand.rotation.z = 0.0 if k == 0 else 1.9
	_box(house, Vector3(0.07, 0.07, 0.01), Vector3(0, 0.07, 0.061), _mat(Color(0.1, 0.06, 0.04)))  # the little door
	bird = Node3D.new()
	bird.position = Vector3(0, 0.07, 0.0)
	house.add_child(bird)
	var yellow := _mat(Color(1.0, 0.8, 0.25), 0.8)
	_ball(bird, 0.03, Vector3(0, 0, 0), yellow)
	_ball(bird, 0.02, Vector3(0, 0.025, 0.02), yellow)
	_box(bird, Vector3(0.01, 0.008, 0.02), Vector3(0, 0.022, 0.045), _mat(Color(1.0, 0.45, 0.15)))
	for i in 2:
		var weight := _cyl(house, 0.015, 0.015, 0.06, Vector3(-0.04 + i * 0.08, -0.32 - i * 0.05, 0.02), _mat(Color(0.8, 0.65, 0.25), 0.4), 6)
		weight.set_meta("chain", true)


func _build_portrait() -> void:
	var wood := _mat(Color(0.3, 0.17, 0.1))
	var easel := _facing(Vector3(1.05, 0.0, 1.9))
	for s in [-1.0, 1.0]:
		var leg := _box(easel, Vector3(0.03, 1.5, 0.03), Vector3(s * 0.2, 0.75, -0.05), wood)
		leg.rotation.z = s * -0.08
	var back := _box(easel, Vector3(0.03, 1.4, 0.03), Vector3(0, 0.7, -0.3), wood)
	back.rotation.x = 0.2
	_box(easel, Vector3(0.5, 0.03, 0.06), Vector3(0, 1.08, 0), wood)
	var pic := Node3D.new()
	pic.position = Vector3(0, 1.35, 0.0)
	easel.add_child(pic)
	_box(pic, Vector3(0.46, 0.56, 0.03), Vector3.ZERO, _mat(Color(0.8, 0.6, 0.22), 0.4))
	_box(pic, Vector3(0.38, 0.48, 0.01), Vector3(0, 0, 0.016), _mat(Color(0.3, 0.45, 0.55)))
	# A friendly old lady with a big grey bun.
	var skin := _mat(Color(1.0, 0.85, 0.75))
	_ball(pic, 0.11, Vector3(0, 0.0, 0.025), skin, 0.35)
	_ball(pic, 0.07, Vector3(0, 0.12, 0.022), _mat(Color(0.75, 0.75, 0.8)), 0.4)
	_box(pic, Vector3(0.26, 0.1, 0.01), Vector3(0, -0.19, 0.024), _mat(Color(0.6, 0.3, 0.55)))
	var dark := _mat(Color(0.12, 0.08, 0.1))
	_ball(pic, 0.016, Vector3(-0.04, 0.02, 0.064), dark, 0.6)
	wink_eye = _ball(pic, 0.016, Vector3(0.04, 0.02, 0.064), dark, 0.6)
	var smile := _box(pic, Vector3(0.06, 0.01, 0.01), Vector3(0, -0.045, 0.062), _mat(Color(0.75, 0.3, 0.35)))
	smile.rotation.z = 0.0
	for s in [-1.0, 1.0]:
		var ch := _ball(pic, 0.022, Vector3(s * 0.065, -0.02, 0.06), _mat(Color(1.0, 0.45, 0.55), 0.6), 0.5)
		ch.visible = false
		cheeks.append(ch)
	# The cobweb in the frame's top-left corner, with a little spider.
	web = Node3D.new()
	web.position = Vector3(-0.23, 0.28, 0.03)
	pic.add_child(web)
	var q := QuadMesh.new()
	q.size = Vector2(0.24, 0.24)
	q.center_offset = Vector3(0.12, -0.12, 0.0)
	var wm := MeshInstance3D.new()
	wm.mesh = q
	wm.material_override = WorldScript.shader_mat(WorldScript.WEB_SHADER)  # web centred on UV (0, 0): the corner
	wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	web.add_child(wm)
	spider = Node3D.new()
	spider.position = Vector3(0.0, -0.06, 0.01)
	web.add_child(spider)
	var black := _mat(Color(0.1, 0.08, 0.12))
	_ball(spider, 0.018, Vector3.ZERO, black)
	for s in [-1.0, 1.0]:
		_ball(spider, 0.006, Vector3(s * 0.007, 0.004, 0.016), _mat(Color(1, 1, 1), 1.0))
		for k in 3:
			var leg := _box(spider, Vector3(0.03, 0.003, 0.003), Vector3(s * 0.022, -0.004, -0.008 + k * 0.008), black)
			leg.rotation.z = s * -0.5
	var thread := _box(spider, Vector3(0.002, 0.3, 0.002), Vector3(0, 0.15, 0), _mat(Color(0.9, 0.9, 0.95), 0.3))
	thread.name = "Thread"


func _build_cupboard() -> void:
	var c := _facing(Vector3(-1.15, 0.0, 3.45))
	var wood := _mat(Color(0.3, 0.16, 0.2))
	# The back, sides, top and bottom; the door is on the +Z side, hinged on the left.
	_box(c, Vector3(0.5, 1.4, 0.03), Vector3(0, 0.9, -0.2), wood)
	for s in [-1.0, 1.0]:
		_box(c, Vector3(0.03, 1.4, 0.4), Vector3(s * 0.235, 0.9, 0), wood)
	_box(c, Vector3(0.5, 0.03, 0.4), Vector3(0, 1.6, 0), wood)
	_box(c, Vector3(0.5, 0.03, 0.4), Vector3(0, 0.2, 0), wood)
	_box(c, Vector3(0.44, 0.02, 0.36), Vector3(0, 0.8, 0), wood)
	for s in [-1.0, 1.0]:
		_box(c, Vector3(0.04, 0.2, 0.04), Vector3(s * 0.2, 0.1, s * 0.15), wood)
	# A little jack-o'-lantern inside, grinning when the door opens.
	pumpkin_mat = _mat(Color(1.0, 0.85, 0.2), 0.5)
	_ball(c, 0.11, Vector3(0, 0.91, 0.0), _mat(Color(1.0, 0.45, 0.08), 0.4), 0.8)
	_box(c, Vector3(0.1, 0.025, 0.02), Vector3(0, 0.88, 0.1), pumpkin_mat)
	for s in [-1.0, 1.0]:
		_box(c, Vector3(0.025, 0.025, 0.02), Vector3(s * 0.035, 0.93, 0.1), pumpkin_mat)
	door = Node3D.new()
	door.position = Vector3(-0.25, 0.9, 0.2)
	c.add_child(door)
	_box(door, Vector3(0.5, 1.38, 0.025), Vector3(0.25, 0, 0), _mat(Color(0.38, 0.2, 0.25)))
	_ball(door, 0.025, Vector3(0.44, 0.05, 0.025), _mat(Color(0.95, 0.8, 0.35), 0.8))


# --- Touching ------------------------------------------------------------------

func _process(delta: float) -> void:
	t += delta
	for k in cool.keys():
		cool[k] = float(cool[k]) - delta
	if main != null and main.ready_to_play and main.net.mode != "client" and not get_tree().paused:
		_check_touches()
	_animate(delta)


func _check_touches() -> void:
	var hands: Array[Vector3] = []
	var feet: Array[Vector3] = []
	for p in main.players:
		if not p.active or p.ghost:
			continue
		if p.vr:
			hands.append(p.hand_l.global_position)
			hands.append(p.hand_r.global_position)
		elif not p.remote or main.net.connected:
			feet.append(p.global_position)
	for n in TOUCH:
		if float(cool.get(n, 0.0)) > 0.0:
			continue
		var d: Array = TOUCH[n]
		var hit := false
		for h in hands:
			if h.distance_to(d[0]) < float(d[1]) + 0.05:
				hit = true
		if d[2] != null and not hit:
			for f in feet:
				var spot: Vector3 = d[2]
				if Vector2(f.x - spot.x, f.z - spot.z).length() < 0.6:
					hit = true
		if hit:
			touch(n)


## Host / local: someone touched prop `n`.
func touch(n: String) -> void:
	cool[n] = 1.4 if n != "door" else 3.5
	touched[n] = int(touched.get(n, 0)) + 1
	play(n)
	main.net.event("prop", [n])
	for p in main.players:
		if p.vr and p.active:
			p.hand_l.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.08, 0.0)
			p.hand_r.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.08, 0.0)


## Both machines: what the prop does.
func play(n: String) -> void:
	var host: bool = main.net.mode != "client"
	var p: Vector3 = TOUCH.get(n, [Vector3.ZERO])[0]
	match n:
		"candle_a", "candle_b":
			lit[n] = not lit[n]
			flame_pop[n] = 0.0
			if lit[n]:
				main.local_sound("magic", -10.0, 1.6)
				if host:
					main.burst(p + Vector3.UP * 0.05, Color(1.0, 0.8, 0.35), 8, 0.012)
			else:
				main.local_sound("puff", -6.0, 1.4)
				if host:
					main.burst(p + Vector3.UP * 0.05, Color(0.75, 0.75, 0.8), 8, 0.015)
		"music_box":
			box_t = 4.0
			note_i = 0
			note_t = 0.3
		"cauldron":
			bloop_t = 1.2
			potion_i = (potion_i + 1) % POTIONS.size()
			main.local_sound("bloop", -4.0, 0.8)
			if host:
				main.burst(p + Vector3.UP * 0.1, POTIONS[potion_i], 12, 0.03)
		"cuckoo":
			cuckoo_t = 1.6
			main.local_sound("cuckoo", -4.0, 1.0)
		"portrait":
			wink_t = 1.4
			main.local_sound("giggle", -4.0, 1.4)
		"cobweb":
			web_vel += 6.0
			spider_t = 2.4
			main.local_sound("swish", -8.0, 1.5)
		"door":
			door_t = 3.2
			main.local_sound("creak", -4.0, 1.0)


func _animate(delta: float) -> void:
	# Candles: a lit flame flickers; lighting one pops it up big for a moment.
	for n in flames:
		var f: MeshInstance3D = flames[n]
		var pop: float = flame_pop.get(n, 1.0)
		pop = minf(1.0, pop + delta * 2.5)
		flame_pop[n] = pop
		var s := 0.0
		if lit[n]:
			s = (1.0 + 0.15 * sin(t * 13.0 + f.position.x * 9.0)) * (1.0 + (1.0 - pop) * 1.2)
		else:
			s = maxf(0.0, 1.0 - pop * 4.0)
		f.scale = Vector3.ONE * maxf(s, 0.001)
		f.visible = s > 0.01
	# Music box: the lid opens, the ghost dancer rises and twirls, one note at a time.
	box_t = maxf(0.0, box_t - delta)
	var open := clampf(box_t * 2.0, 0.0, 1.0)
	lid.rotation.x = -1.6 * open
	dancer.visible = open > 0.05
	dancer.scale = Vector3.ONE * maxf(open, 0.01)
	dancer.rotation.y += delta * 6.0
	if note_i < TUNE.size():
		note_t -= delta
		if note_t <= 0.0:
			note_t = 0.38
			main.local_sound("note", -10.0, TUNE[note_i])
			note_i += 1
	# Cauldron: bubbles rise and pop; touching it boils it up and changes the colour.
	bloop_t = maxf(0.0, bloop_t - delta)
	potion_mat.albedo_color = potion_mat.albedo_color.lerp(POTIONS[potion_i], 1.0 - exp(-3.0 * delta))
	potion_mat.emission = potion_mat.albedo_color
	var boil := 1.0 + bloop_t * 3.0
	for b in bubbles:
		var k := fmod(t * 0.6 * boil + float(b.get_meta("phase")), 1.0)
		var a := float(b.get_meta("phase")) * TAU * 1.3 + t * 0.4
		b.position = Vector3(0.85 + cos(a) * 0.14, 0.6 + k * (0.08 + bloop_t * 0.15), 2.55 + sin(a) * 0.14)
		b.scale = Vector3.ONE * (0.4 + k * 0.8) * (1.0 + bloop_t * 0.8)
	potion.position.y = 0.6 + sin(t * 5.0) * 0.004 * boil
	# Cuckoo: the bird pops out twice.
	if cuckoo_t > 0.0:
		var before := cuckoo_t
		cuckoo_t = maxf(0.0, cuckoo_t - delta)
		if before > 0.8 and cuckoo_t <= 0.8:
			main.local_sound("cuckoo", -4.0, 0.84)
	var out := 0.0
	if cuckoo_t > 0.0:
		out = absf(sin((1.6 - cuckoo_t) / 0.8 * PI))
	bird.position.z = 0.02 + out * 0.1
	bird.rotation.x = -out * 0.3
	# Portrait: a wink and rosy cheeks.
	wink_t = maxf(0.0, wink_t - delta)
	wink_eye.scale.y = 0.15 if wink_t > 0.5 else 0.6
	for ch in cheeks:
		ch.visible = wink_t > 0.0
	# Cobweb: wobbles on a spring; the spider abseils down and climbs back up.
	web_vel += (-web_ang * 60.0 - web_vel * 4.0) * delta
	web_ang += web_vel * delta
	web.rotation.x = web_ang * 0.15
	web.rotation.y = web_ang * 0.1
	spider_t = maxf(0.0, spider_t - delta)
	var drop := sin(clampf(spider_t / 2.4, 0.0, 1.0) * PI) * 0.22
	spider.position.y = -0.06 - drop
	var thread := spider.get_node_or_null("Thread") as Node3D
	if thread != null:
		thread.scale.y = (0.06 + drop) / 0.3
		thread.position.y = (0.06 + drop) * 0.5
	spider.rotation.y = sin(t * 3.0) * 0.3 * float(spider_t > 0.0)
	# Cupboard: the door creaks open, the pumpkin grins, then it bumps shut.
	var was_open := door_t > 0.0
	door_t = maxf(0.0, door_t - delta)
	var swing := clampf(door_t * 1.5, 0.0, 1.0) if door_t < 1.0 else clampf((3.2 - door_t) * 2.0, 0.0, 1.0)
	door.rotation.y = -1.7 * ease(swing, -1.6)
	pumpkin_mat.emission_energy_multiplier = 0.5 + swing * 4.0
	if was_open and door_t <= 0.0:
		main.local_sound("door", -8.0, 1.3)
