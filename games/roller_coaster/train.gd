extends Node3D
## COASTER CREW: the coaster train (drawn on every machine; the host decides where it is). One car per
## rider: a TV player (their colour, a little rider with their look), a guest the builder plopped in,
## or a bot rider so the VR player always sees a full train racing round. Hands go up while the rider
## holds A (bit flags), with a bit of a wobble so it reads from far away.

const MeshKit := preload("res://core/mesh_kit.gd")
const Creatures := preload("res://core/creatures.gd")
const Party := preload("res://core/party.gd")
const Track := preload("res://games/roller_coaster/track.gd")

const GAP := 1.75  # distance between car centres
const BOT_LOOKS: Array[String] = ["villager", "farmer", "chef", "bard", "pirate", "athlete", "golfer"]
const LOOKS: Array[String] = ["knight", "astronaut", "pirate", "chef", "mage", "athlete", "bard"]

var cars: Array[Node3D] = []
var riders: Array[Node3D] = []
var occupants: Array = []
var hands_t: Array[float] = []
var hide_slot0 := false


## occ: per car, slot >= 0 (a player), -1 (a bot rider), <= -2 (guest -2 - g).
func set_cars(occ: Array) -> void:
	if occ == occupants and cars.size() == occ.size():
		return
	occupants = occ.duplicate()
	for c in cars:
		c.queue_free()
	cars.clear()
	riders.clear()
	hands_t.clear()
	for i in occ.size():
		var code := int(occ[i])
		var col := Party.COLORS[code % Party.COLORS.size()] if code >= 0 else Color(0.95, 0.85, 0.3) if code == -1 else Color(0.6, 0.85, 0.5)
		var car := Node3D.new()
		car.name = "Car%d" % i
		add_child(car)
		car.add_child(MeshKit.instance(_car_mesh(col, i == 0), false))
		var opts := {"seed": 7 + i, "scale": 0.62}
		if code >= 0:
			opts["class"] = LOOKS[code % LOOKS.size()]
			opts["outfit"] = col
		elif code == -1:
			opts["class"] = BOT_LOOKS[i % BOT_LOOKS.size()]
		else:
			opts["class"] = "villager"
			opts["seed"] = 40 + (-2 - code)
		var r := Creatures.humanoid(opts)
		r.position = Vector3(0, 0.12, 0.1)
		r.rotation.y = PI  # humanoids face +Z; the car drives along -Z
		car.add_child(r)
		cars.append(car)
		riders.append(r)
		hands_t.append(0.0)


func _car_mesh(col: Color, front: bool) -> ArrayMesh:
	var b := MeshKit.builder()
	b.rounded_box(Vector3(1.05, 0.5, 1.45), 0.15, Transform3D(Basis(), Vector3(0, 0.15, 0)), col)
	b.box(Vector3(0.9, 0.12, 0.6), Transform3D(Basis(), Vector3(0, 0.42, 0.05)), col.darkened(0.45))
	b.box(Vector3(1.0, 0.35, 0.12), Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, 0.55, 0.55)), col.lightened(0.25))
	b.box(Vector3(0.8, 0.06, 0.06), Transform3D(Basis(), Vector3(0, 0.62, -0.32)), Color(0.85, 0.85, 0.9))
	if front:
		b.wedge(Vector3(1.0, 0.4, 0.5), Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.2, -0.95)), col.lightened(0.2))
		b.sphere(0.1, Transform3D(Basis(), Vector3(-0.3, 0.3, -0.98)), Color(1, 1, 0.7), 8, true)
		b.sphere(0.1, Transform3D(Basis(), Vector3(0.3, 0.3, -0.98)), Color(1, 1, 0.7), 8, true)
	for x in [-0.42, 0.42]:
		for z in [-0.5, 0.5]:
			b.cylinder(0.13, 0.13, 0.1, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x, -0.12, z)), Color(0.2, 0.2, 0.25), 8)
	return b.build()


## Put the train on the track: the front car at distance s.
func place(tr: Dictionary, s: float) -> void:
	if tr.is_empty():
		return
	for i in cars.size():
		var xf := Track.sample(tr, s - i * GAP)
		xf.origin += xf.basis.y * 0.22
		cars[i].transform = xf


func car_s(s: float, i: int) -> float:
	return s - i * GAP


## Hands up / down per car (bit i = car i), and a happy wave while they're up.
func set_hands(bits: int, delta: float) -> void:
	for i in riders.size():
		var up := (bits >> i) & 1 == 1
		var r := riders[i]
		if up:
			hands_t[i] -= delta
			if hands_t[i] <= 0.0:
				hands_t[i] = 0.55
				Creatures.anim(r).play("cheer", 0.6)
		else:
			hands_t[i] = 0.0
		if i == 0:
			r.visible = not hide_slot0
