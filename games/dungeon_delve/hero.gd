extends Node3D
## DUNGEON DELVE: a TV hero (one per TV player). A cute chibi adventurer in the player's colour
## with a coloured ring under the feet. Left stick walks, A bonks whatever is in front.
## When a slime bumps them they get dizzy for a moment (fall over, stars spin round their head) and
## pop back up: no health, no failure.
## The machine whose pad drives the hero moves it (instant, client-side); the others mirror it.

const Creatures := preload("res://core/creatures.gd")
const MeshKit := preload("res://core/mesh_kit.gd")

const SPEED := 3.4
const RADIUS := 0.32
const DIZZY_TIME := 2.0
const LOOKS: Array[String] = ["knight", "mage", "healer", "thief", "archer", "bard", "viking"]
const WEAPONS: Array[String] = ["hammer", "wand", "staff", "dagger", "club", "lute", "axe"]

var slot := 0
var owned := false
var body: Node3D
var anim: Variant
var ring: MeshInstance3D
var stars: Node3D
var dizzy_t := 0.0
var safe_t := 0.0  ## can't be bumped again right after popping up
var bonk_cd := 0.0
var moving := 0.0
var _target := Vector3.ZERO
var _target_yaw := 0.0
var _has_target := false


func setup(s: int, col: Color) -> void:
	slot = s
	body = Creatures.humanoid({"class": LOOKS[s % LOOKS.size()], "outfit": col, "seed": 11 + s * 7,
		"weapon": WEAPONS[s % WEAPONS.size()]})
	add_child(body)
	anim = Creatures.anim(body)
	var b := MeshKit.Builder.new()
	b.torus(0.45, 0.05, Transform3D.IDENTITY, col, 20, 4, true)
	ring = MeshKit.instance(b.build(), false)
	ring.position.y = 0.03
	add_child(ring)
	stars = Node3D.new()
	stars.position.y = 1.25
	var sb := MeshKit.Builder.new()
	for i in 3:
		var a := TAU * i / 3.0
		sb.star(5, 0.09, 0.04, 0.03, MeshKit.at(Vector3(cos(a) * 0.3, 0.0, sin(a) * 0.3)), Color(1.0, 0.9, 0.3), true)
	stars.add_child(MeshKit.instance(sb.build(), false))
	stars.visible = false
	add_child(stars)


## Owner: walk (dir is world-space, length 0..1), kept inside the dungeon by clamp (from, to) -> to.
func step(delta: float, dir: Vector3, clamp: Callable) -> void:
	bonk_cd = maxf(0.0, bonk_cd - delta)
	if dizzy_t > 0.0:
		dir = Vector3.ZERO
	var to := position + dir * SPEED * delta
	to = clamp.call(position, to)
	moving = (to - position).length() / maxf(delta, 0.0001)
	position = to
	if dir.length() > 0.2:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-14.0 * delta))


## Mirror: where the owner says the hero is.
func set_remote(p: Vector3, yaw: float, down: bool) -> void:
	if not _has_target or p.distance_to(position) > 4.0:
		position = p
	_target = p
	_target_yaw = yaw
	_has_target = true
	if down and dizzy_t <= 0.0:
		get_dizzy()
	elif not down and dizzy_t > 0.0:
		dizzy_t = 0.01


func get_dizzy() -> void:
	if dizzy_t > 0.0:
		return
	dizzy_t = DIZZY_TIME
	anim.faint()
	stars.visible = true


func bonk_anim() -> void:
	anim.play("attack", 0.35)


func animate(delta: float) -> void:
	safe_t = maxf(0.0, safe_t - delta)
	if not owned and _has_target:
		var k := 1.0 - exp(-14.0 * delta)
		var before := position
		position = position.lerp(_target, k)
		rotation.y = lerp_angle(rotation.y, _target_yaw, k)
		moving = (position - before).length() / maxf(delta, 0.0001)
	if dizzy_t > 0.0:
		dizzy_t -= delta
		stars.rotation.y += delta * 6.0
		if dizzy_t <= 0.0:
			dizzy_t = 0.0
			safe_t = 2.0
			stars.visible = false
			anim.revive()
	anim.walk(moving if dizzy_t <= 0.0 else 0.0)
	ring.scale = Vector3.ONE * (1.0 + (0.15 * sin(Time.get_ticks_msec() * 0.01) if safe_t > 0.0 else 0.0))
