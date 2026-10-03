extends Node3D
## One planting spot, drawn from its state (the same code on the host and the TV):
## st = {kind (-1 empty), growth 0..1, water 0..1, bloom, ready (pollen), fruit (-1 none, 0..1 ripe), bug}

const W := preload("res://games/bee_garden/world.gd")

var spot := 0
var mound: MeshInstance3D
var stem: MeshInstance3D
var leaves: Array[MeshInstance3D] = []
var head: Node3D
var petals: MeshInstance3D
var center: MeshInstance3D
var bud: MeshInstance3D
var fruit: MeshInstance3D
var drop: MeshInstance3D
var kind := -2
var open := 0.0     # petal opening animation 0..1
var fruit_s := 0.0
var t := 0.0
var was_bloom := false
var golden_shown := false


static func head_pos(i: int, st: Dictionary) -> Vector3:
	var k: int = st.get("kind", -1)
	if k < 0:
		return W.spot_pos(i)
	var kd: Dictionary = W.KINDS[k]
	var g: float = st.get("growth", 0.0)
	return W.spot_pos(i) + Vector3(0.0, float(kd.h) * maxf(g, 0.08) + 0.06, 0.0)


func _ready() -> void:
	position = W.spot_pos(spot)
	var soil := W.cmat(Color(0.3, 0.2, 0.13))
	mound = W.mesh_node(self, W.sphere(0.22, 10), soil, Vector3(0, 0.0, 0), Vector3(1.0, 0.3, 1.0))
	var green := W.cmat(Color(0.3, 0.68, 0.28))
	stem = W.mesh_node(self, W.cyl(0.035, 0.045, 1.0, 6), green, Vector3.ZERO)
	for side in [-1.0, 1.0]:
		var lf := W.mesh_node(self, W.sphere(0.14, 8), W.cmat(Color(0.35, 0.75, 0.3)), Vector3.ZERO, Vector3(1.4, 0.25, 0.6))
		lf.set_meta("side", side)
		leaves.append(lf)
	head = Node3D.new()
	add_child(head)
	petals = W.mesh_node(head, W.cyl(0.26, 0.26, 0.04, 10), W.cmat(Color.WHITE), Vector3.ZERO)
	center = W.mesh_node(head, W.sphere(0.1, 10), W.cmat(Color.YELLOW), Vector3(0, 0.03, 0), Vector3(1.0, 0.6, 1.0))
	bud = W.mesh_node(head, W.sphere(0.1, 8), W.cmat(Color(0.35, 0.7, 0.3)), Vector3(0, 0.02, 0), Vector3(0.8, 1.3, 0.8))
	fruit = W.mesh_node(head, W.sphere(0.2, 12), W.cmat(Color.RED), Vector3(0, -0.12, 0.08))
	drop = W.mesh_node(self, W.sphere(0.07, 8), W.cmat(Color(0.35, 0.65, 1.0), 0.8), Vector3.ZERO, Vector3(0.8, 1.2, 0.8))
	update_from({"kind": -1}, 0.0)


func update_from(st: Dictionary, delta: float) -> void:
	t += delta
	var k: int = st.get("kind", -1)
	var show := k >= 0
	mound.visible = show
	stem.visible = show
	head.visible = show
	drop.visible = false
	for lf in leaves:
		lf.visible = show
	if not show:
		kind = -1
		open = 0.0
		fruit_s = 0.0
		was_bloom = false
		return
	var kd: Dictionary = W.KINDS[k]
	var golden: bool = st.get("golden", false)
	if k != kind or golden != golden_shown:
		if k != kind:
			open = 0.0
		kind = k
		golden_shown = golden
		# The rare golden flower: shiny gold petals (golden pollen for the bees).
		petals.material_override = W.cmat(Color(1.0, 0.85, 0.2), 1.6) if golden else W.cmat(kd.petal, 0.5 if k == 2 else 0.1)
		fruit.material_override = W.cmat(kd.fruit_color, 0.3 if k == 2 else 0.05)
	var g: float = st.get("growth", 0.0)
	var water: float = st.get("water", 0.0)
	var bloom: bool = st.get("bloom", false)
	var ready: bool = st.get("ready", false)
	var fr: float = st.get("fruit", -1.0)
	var bug: bool = st.get("bug", false)
	var h: float = float(kd.h) * maxf(g, 0.08)
	var thirsty := water < 0.12 or (k == 2 and g >= 1.0 and not bloom and water < float(kd.thirst))
	var droop := 0.35 if water < 0.05 else 0.0
	stem.scale = Vector3(1.0, h, 1.0)
	stem.position.y = h * 0.5
	stem.rotation.z = lerpf(stem.rotation.z, droop * 0.4, 1.0 - exp(-3.0 * delta))
	for lf in leaves:
		var side: float = lf.get_meta("side")
		var ls := clampf(g * 1.5, 0.2, 1.0)
		lf.scale = Vector3(1.4, 0.25, 0.6) * ls
		lf.position = Vector3(side * 0.13 * ls, h * 0.35, 0.0)
		lf.rotation.z = side * (-0.35 - droop)
	var sway := sin(t * 1.3 + spot * 1.7) * 0.06 + (sin(t * 22.0) * 0.06 if bug else 0.0)
	head.position = Vector3(sin(stem.rotation.z) * -h, h + 0.06, 0.0)
	head.rotation = Vector3(0.35 + droop, 0.0, sway)  # tilted towards the gardener
	open = move_toward(open, 1.0 if bloom else 0.0, delta * 2.5)
	if bloom and not was_bloom and delta > 0.0:
		open = 0.01
	was_bloom = bloom
	petals.visible = open > 0.02
	var pop := 1.0 + sin(open * PI) * 0.25
	petals.scale = Vector3(open * pop, 1.0, open * pop) * (1.25 if k == 1 else 1.0) * ((1.3 + sin(t * 4.0) * 0.06) if golden_shown else 1.0)
	center.visible = open > 0.02
	var cglow := 1.4 + sin(t * 5.0) * 0.5 if ready else 0.0
	center.material_override = W.cmat(kd.center, snappedf(cglow, 0.25))
	center.scale = Vector3(1.0, 0.6, 1.0) * (1.25 if k == 1 else 1.0) * (1.15 if ready else 0.9)
	bud.visible = not petals.visible and g >= 0.3
	bud.scale = Vector3(0.8, 1.3, 0.8) * clampf(g, 0.3, 1.0)
	fruit_s = move_toward(fruit_s, 0.0 if fr < 0.0 else 0.25 + fr * 0.75, delta * 1.5)
	fruit.visible = fruit_s > 0.01
	if fruit.visible:
		var ripe_pulse := 1.0 + (sin(t * 6.0) * 0.08 if fr >= 1.0 else 0.0)
		fruit.scale = Vector3.ONE * fruit_s * ripe_pulse
	drop.visible = thirsty
	if thirsty:
		drop.position = Vector3(0.0, h + 0.55 + sin(t * 4.0) * 0.06, 0.0)
