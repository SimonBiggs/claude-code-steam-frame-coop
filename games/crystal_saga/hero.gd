extends Node3D
## CRYSTAL SAGA: a TV hero, the VR hero's party (one per TV player). A chibi hero (classes.gd: knight, mage, archer,
## healer, bard: picked at the statues in Willowbrook) in the player's colour
## with a coloured ring under the feet. Left stick walks, A shoots a magic spark or an arrow
## (or pokes the thing in front). Slot 0 (local play without a headset) is a little knight.
## When a monster bumps them they get dizzy for a moment (fall over, stars spin round their head) and
## pop back up: no health, no failure.
## The machine whose pad drives the hero moves it (instant, client-side); the others mirror it.

const Creatures := preload("res://core/creatures.gd")
const Classes := preload("res://games/crystal_saga/classes.gd")
const MeshKit := preload("res://core/mesh_kit.gd")

const SPEED := 3.6
const RADIUS := 0.32
const DIZZY_TIME := 2.0

var slot := 0
var cls := ""  ## classes.gd hero id (knight, mage, archer, healer, bard)
var dizzy_mult := 1.0  ## main.gd: the class and HEALING make dizzy spells shorter
var safe_bonus := 0.0  ## main.gd: BUBBLE keeps a hero safe longer after popping up
var owned := false
var _col := Color.WHITE
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


func setup(s: int, col: Color, hero_class: String = "") -> void:
	slot = s
	_col = col
	set_class(hero_class if Classes.valid(hero_class) else Classes.default_for(s))
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


## Become another hero (a new body in the seat's colour; the ring, stars and position stay).
func set_class(id: String) -> void:
	if id == cls and body != null:
		return
	cls = id
	if body != null:
		body.queue_free()
	var inf := Classes.info(id)
	body = Creatures.humanoid({"class": String(inf.look), "outfit": _col, "seed": 11 + slot * 7, "weapon": String(inf.weapon)})
	add_child(body)
	anim = Creatures.anim(body)
	if dizzy_t > 0.0:
		anim.faint()


func shot() -> String:
	return String(Classes.info(cls).shot)


## Owner: walk (dir is world-space, length 0..1), kept inside the dungeon by clamp (from, to) -> to.
func step(delta: float, dir: Vector3, clamp: Callable) -> void:
	bonk_cd = maxf(0.0, bonk_cd - delta)
	if dizzy_t > 0.0:
		dir = Vector3.ZERO
	var to := position + dir * SPEED * float(Classes.info(cls).speed) * delta
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
	dizzy_t = DIZZY_TIME * dizzy_mult
	anim.faint()
	stars.visible = true


## Wake up at once (a healer's spark): a moment of safety after.
func wake() -> void:
	if dizzy_t > 0.0:
		dizzy_t = 0.01


func bonk_anim() -> void:
	anim.play("cast" if shot() in ["magic", "heal", "note"] else "attack", 0.35)


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
			safe_t = 2.0 + safe_bonus
			stars.visible = false
			anim.revive()
	anim.walk(moving if dizzy_t <= 0.0 else 0.0)
	ring.scale = Vector3.ONE * (1.0 + (0.15 * sin(Time.get_ticks_msec() * 0.01) if safe_t > 0.0 else 0.0))
