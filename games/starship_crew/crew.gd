extends Node3D
## CAPTAIN WHISKERS' CREW FRIENDS (deep.gd CREW): every CREW_EVERY finished missions a new friend joins for good - a
## PUPPY, a ROBOT, an ALIEN, a PENGUIN, an OWL, a FROG, a BUNNY and a KITTEN - and flies in a little pod beside the
## ship (deep.gd CREW_SPOTS: left and right in turn, clear of the wing turrets, the pilot's view ahead and the TV
## camera's edges, Deck-wide too). Every machine builds the same from the friend count (the "deep" state). The newest
## friend pops in and waves. One merged mesh per pod; they bob gently.
##   set_count(n, pop)

const MeshKit := preload("res://core/mesh_kit.gd")
const Deep := preload("res://games/starship_crew/deep.gd")
const Art := preload("res://games/starship_crew/art.gd")

var main
var count := -1
var pods: Array = []  # Node3D
var _t := 0.0


func set_count(n: int, pop: bool = false) -> void:
	n = clampi(n, 0, Deep.CREW.size())
	if n == count:
		return
	var grew := count >= 0 and n > count
	count = n
	for p in pods:
		if is_instance_valid(p):
			(p as Node).queue_free()
	pods = []
	for i in n:
		var pod := MeshKit.instance(_pod(Deep.CREW[i]), false)
		pod.name = "CrewPod%d" % i
		add_child(pod)
		pod.position = Deep.CREW_SPOTS[i]
		pod.rotation.y = 0.35 * signf(Deep.CREW_SPOTS[i].x)  # turned a little towards the ship
		pods.append(pod)
	if grew and pop and n > 0:
		var last: Node3D = pods[n - 1]
		last.scale = Vector3.ONE * 0.05
		last.create_tween().tween_property(last, "scale", Vector3.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		main.confetti(last.position + Vector3(0, 0.8, 0), Deep.CREW[n - 1].color, 40)
		main.sfx.play_at("sparkle", last.position, -2.0, 1.0)


## A little round pod (white hull, orange trim, a glowing engine) with a friend's head poking out of the top, facing
## the way the ship flies (-Z) and a little back at the camera.
func _pod(friend: Dictionary) -> ArrayMesh:
	var b := MeshKit.Builder.new()
	var col: Color = friend.color
	var dark := Color(0.08, 0.08, 0.12)
	b.ellipsoid(Vector3(0.75, 0.35, 0.9), MeshKit.at(Vector3(0, 0, 0)), Art.HULL, 14)
	b.cylinder(0.78, 0.78, 0.08, MeshKit.at(Vector3(0, 0.02, 0)), Art.TRIM, 16)
	b.cylinder(0.22, 0.28, 0.25, MeshKit.at(Vector3(0, 0, 0.85), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Art.DARK, 10)
	b.sphere(0.17, MeshKit.at(Vector3(0, 0, 0.98)), Color(0.4, 0.95, 1.0), 8, true)
	var head := Vector3(0, 0.55, 0.05)
	b.sphere(0.36, MeshKit.at(head), col, 12)
	var face := Vector3(0, 0, 0.3)  # the face looks back at the camera (+Z): kids see the friend
	for s in [-1.0, 1.0]:
		b.sphere(0.07, MeshKit.at(head + face + Vector3(0.13 * s, 0.07, 0.0)), Color(1, 1, 1), 8)
		b.sphere(0.04, MeshKit.at(head + face + Vector3(0.13 * s, 0.07, 0.05)), dark, 6)
	match String(friend.id):
		"puppy":  # floppy ears, a black nose
			for s in [-1.0, 1.0]:
				b.ellipsoid(Vector3(0.1, 0.22, 0.08), MeshKit.at(head + Vector3(0.33 * s, -0.02, 0.0)), col.darkened(0.3), 8)
			b.sphere(0.06, MeshKit.at(head + face + Vector3(0, -0.06, 0.05)), dark, 6)
		"robot":  # an antenna with a light
			b.cylinder(0.02, 0.02, 0.25, MeshKit.at(head + Vector3(0, 0.45, 0)), Art.DARK, 6)
			b.sphere(0.07, MeshKit.at(head + Vector3(0, 0.6, 0)), Color(1.0, 0.3, 0.3), 8, true)
		"alien":  # two bobbly antennae
			for s in [-1.0, 1.0]:
				b.tube(head + Vector3(0.1 * s, 0.3, 0), head + Vector3(0.22 * s, 0.6, 0), 0.025, 0.02, col.darkened(0.2), 5)
				b.sphere(0.06, MeshKit.at(head + Vector3(0.22 * s, 0.62, 0)), Color(1.0, 0.6, 0.9), 6)
		"penguin":  # a white face and an orange beak
			b.ellipsoid(Vector3(0.25, 0.22, 0.1), MeshKit.at(head + face + Vector3(0, -0.04, -0.04)), Color(0.97, 0.97, 1.0), 10)
			b.cone(0.06, 0.12, MeshKit.at(head + face + Vector3(0, -0.06, 0.06), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.6, 0.1), 6)
		"owl":  # ear tufts and a little beak
			for s in [-1.0, 1.0]:
				b.cone(0.08, 0.2, MeshKit.at(head + Vector3(0.2 * s, 0.33, 0)), col.darkened(0.25), 6)
			b.cone(0.04, 0.1, MeshKit.at(head + face + Vector3(0, -0.06, 0.04), Vector3.ONE, Vector3(PI * 0.5, 0, 0)), Color(1.0, 0.75, 0.2), 6)
		"frog":  # big eyes on top
			for s in [-1.0, 1.0]:
				b.sphere(0.12, MeshKit.at(head + Vector3(0.16 * s, 0.3, 0.1)), col, 8)
				b.sphere(0.06, MeshKit.at(head + Vector3(0.16 * s, 0.33, 0.2)), dark, 6)
		"bunny":  # long ears
			for s in [-1.0, 1.0]:
				b.ellipsoid(Vector3(0.07, 0.3, 0.05), MeshKit.at(head + Vector3(0.13 * s, 0.55, 0)), col, 8)
				b.ellipsoid(Vector3(0.04, 0.22, 0.03), MeshKit.at(head + Vector3(0.13 * s, 0.55, 0.03)), Color(1.0, 0.7, 0.8), 6)
		_:  # kitten: pointy ears and a pink nose
			for s in [-1.0, 1.0]:
				b.cone(0.1, 0.18, MeshKit.at(head + Vector3(0.2 * s, 0.32, 0)), col, 6)
			b.sphere(0.04, MeshKit.at(head + face + Vector3(0, -0.04, 0.05)), Color(1.0, 0.55, 0.65), 6)
	return b.build()


func _process(delta: float) -> void:
	if pods.is_empty():
		return
	_t += delta
	for i in pods.size():
		var p: Node3D = pods[i]
		if is_instance_valid(p):
			p.position = Deep.CREW_SPOTS[i] + Vector3(0.0, sin(_t * 1.3 + i * 1.7) * 0.18, 0.0)
			p.rotation.z = sin(_t * 0.9 + i) * 0.08