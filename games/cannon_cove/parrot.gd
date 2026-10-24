extends Node3D
## Polly, the ship's parrot. She perches on the rail next to whichever cannon the gunner is manning,
## bobs, blinks, flaps and squawks short cheers and warnings in a speech bubble. Purely visual: each
## machine runs its own Polly (the host sends what she says as a "parrot" event).

const World := preload("res://games/cannon_cove/world.gd")

var main
var perches: Array = []
var perch := -1
var hop_from := Vector3.ZERO
var hop_to := Vector3.ZERO
var hop_t := 1.0
var t := 0.0
var blink_t := 2.0
var talk_t := 0.0
var flap := 0.0
var body: Node3D
var head: Node3D
var wings: Array[Node3D] = []
var eyes: Array[MeshInstance3D] = []
var bubble: Label3D
var poke_t := 0.0


func _ready() -> void:
	body = Node3D.new()
	add_child(body)
	var green := World.mat(Color(0.2, 0.8, 0.3))
	var red := World.mat(Color(0.95, 0.2, 0.15))
	var yellow := World.mat(Color(1.0, 0.85, 0.2))
	var blue := World.mat(Color(0.2, 0.45, 1.0))
	var torso := World.sphere(body, 0.13, Vector3(0, 0.16, 0), red, 10)
	torso.scale = Vector3(0.9, 1.25, 0.9)
	var belly := World.sphere(body, 0.09, Vector3(0, 0.13, -0.07), yellow, 8)
	belly.scale = Vector3(0.9, 1.2, 0.6)
	head = Node3D.new()
	head.position = Vector3(0, 0.36, -0.02)
	body.add_child(head)
	World.sphere(head, 0.1, Vector3.ZERO, red, 10)
	var beak := World.cyl(head, 0.0, 0.045, 0.1, Vector3(0, -0.02, -0.12), yellow, 6)
	beak.rotation.x = -PI / 2.0 - 0.5
	for ex in [-0.055, 0.055]:
		var e := World.sphere(head, 0.03, Vector3(ex, 0.03, -0.08), World.mat(Color.WHITE), 6)
		World.sphere(e, 0.017, Vector3(0, 0, -0.018), World.mat(Color.BLACK), 4)
		eyes.append(e)
	for sx in [-1.0, 1.0]:
		var w := Node3D.new()
		w.position = Vector3(sx * 0.1, 0.24, 0.02)
		body.add_child(w)
		var feather := World.box(w, Vector3(0.06, 0.22, 0.16), Vector3(sx * 0.03, -0.08, 0.02), green)
		feather.rotation.z = sx * 0.15
		World.box(w, Vector3(0.05, 0.08, 0.14), Vector3(sx * 0.03, -0.2, 0.04), blue)
		wings.append(w)
	var tail := World.box(body, Vector3(0.08, 0.04, 0.28), Vector3(0, 0.04, 0.16), blue)
	tail.rotation.x = 0.7
	for fx in [-0.04, 0.04]:
		World.box(body, Vector3(0.025, 0.06, 0.06), Vector3(fx, -0.02, -0.02), yellow)
	for c in body.get_children():
		if c is GeometryInstance3D:
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bubble = Label3D.new()
	# Small and above the rail: the VR gunner stands about two metres away (no big text in their face).
	bubble.font_size = 36
	bubble.outline_size = 14
	bubble.pixel_size = 0.002
	bubble.modulate = Color(1.0, 1.0, 0.85)
	bubble.outline_modulate = Color(0.05, 0.1, 0.2, 0.95)
	bubble.position = Vector3(0, 0.8, 0)
	bubble.width = 360.0
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.visible = false
	bubble.rotation.y = PI  # readable from inboard (never billboarded)
	add_child(bubble)
	visible = false


func say(text: String) -> void:
	bubble.text = text
	bubble.visible = text != ""
	talk_t = 2.6 + text.length() * 0.03
	flap = 1.0
	body.scale = Vector3(1.25, 0.8, 1.25)  # squash
	if main:
		main._sfx().play("squawk", -6.0, randf_range(0.9, 1.25))


## Poked by the VR gunner's hand: SQUAWK, a flap and a startled little hop (simple mode).
func poke() -> void:
	flap = 1.0
	body.scale = Vector3(0.8, 1.35, 0.8)
	poke_t = 1.0  # a startled little jump, back down onto the perch
	if main:
		main._sfx().play("squawk", -3.0, randf_range(1.2, 1.5))


func _process(delta: float) -> void:
	t += delta
	if perches.is_empty() or main == null or main.cannons.is_empty():
		return
	var want := -1
	for c in main.cannons:
		if c.manned:
			want = c.index
	if want < 0:
		want = 1
	if want != perch:
		hop_from = position if perch >= 0 else perches[want]
		perch = want
		hop_to = perches[want]
		hop_t = 0.0 if visible else 1.0
		visible = true
		flap = 1.0
	# Hop (a flying arc) between perches.
	if hop_t < 1.0:
		hop_t = minf(1.0, hop_t + delta / 0.9)
		position = hop_from.lerp(hop_to, hop_t) + Vector3.UP * sin(hop_t * PI) * 1.6
		flap = 1.0
	else:
		poke_t = maxf(0.0, poke_t - delta * 2.5)
		position = hop_to + Vector3.UP * sin(poke_t * PI) * 0.25
	# Face inboard (towards the gunner), with a little head-tilt and look-around.
	var inboard := Vector3(-signf(position.x), 0.0, 0.0)
	rotation.y = atan2(-inboard.x, -inboard.z)
	head.rotation = Vector3(sin(t * 1.3) * 0.15, sin(t * 0.7) * 0.5, sin(t * 2.1) * 0.12)
	body.position.y = absf(sin(t * 2.5)) * 0.02
	body.scale = body.scale.lerp(Vector3.ONE, 1.0 - exp(-8.0 * delta))
	flap = maxf(0.0, flap - delta * 1.2)
	var wing_a := sin(t * 28.0) * 0.9 * flap + 0.05
	for i in wings.size():
		wings[i].rotation.z = wing_a * (1.0 if i == 0 else -1.0)
	blink_t -= delta
	var closed := blink_t < 0.0
	if blink_t < -0.14:
		blink_t = randf_range(1.5, 4.0)
	for e in eyes:
		e.scale = Vector3(1.0, 0.15 if closed else 1.0, 1.0)
	if talk_t > 0.0:
		talk_t -= delta
		head.rotation.x = -0.3 + sin(t * 18.0) * 0.15
		if talk_t <= 0.0:
			bubble.visible = false
