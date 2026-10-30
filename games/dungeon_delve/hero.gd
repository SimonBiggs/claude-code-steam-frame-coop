extends Node3D
## DUNGEON DELVE: a TV hero (one per TV player). A cute chibi adventurer in the player's colour
## with a coloured ring under the feet. Left stick walks, A bonks whatever is in front.
## When a slime bumps them they get dizzy for a moment (fall over, stars spin round their head) and
## pop back up: no health, no failure.
## The machine whose pad drives the hero moves it (instant, client-side); the others mirror it.
## BRAVE / HEROIC (deep.gd): heroes have hearts. At zero they are knocked out (lying down, a ring of
## lights round them fills while a friend stands close, then they pop back up); pushes (dash, shield
## bash, knock-back) slide them; their look follows what they carry (bow, shield) and their hat.

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
var down := false  ## knocked out (deep)
var hurt_t := 0.0  ## blinking after a hit
var push_v := Vector3.ZERO
var push_t := 0.0
var look := {}  ## hat / weapon / offhand overrides (deep)
var revive_ring: Node3D
var revive_pips: Array[MeshInstance3D] = []
var _col := Color.WHITE
var speed_mul := 1.0  ## deep: the hero class / SPEEDY BOOTS relic
var bubble: Node3D  ## deep: the BUBBLE SHIELD relic (pops on the next hit)


func setup(s: int, col: Color) -> void:
	slot = s
	_col = col
	_build_body()
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


func _build_body() -> void:
	if body != null:
		body.queue_free()
	var o := {"class": LOOKS[slot % LOOKS.size()], "outfit": _col, "seed": 11 + slot * 7,
		"weapon": WEAPONS[slot % WEAPONS.size()]}
	for k in look:
		if String(look[k]) != "":
			o[k] = look[k]
	body = Creatures.humanoid(o)
	add_child(body)
	anim = Creatures.anim(body)
	if down:
		anim.faint()


## Deep: hat / weapon / offhand ("" = the class default). Rebuilds the body only when it changes.
func set_look(want: Dictionary) -> void:
	if want == look:
		return
	look = want.duplicate()
	_build_body()


## Deep: knocked out or back up.
func set_down(on: bool) -> void:
	if on == down:
		return
	down = on
	if on:
		anim.faint()
		dizzy_t = 0.0
		stars.visible = false
	else:
		anim.revive()
		anim.play("cheer", 0.8)
		hurt_t = 1.5
	if revive_ring == null and on:
		revive_ring = Node3D.new()
		revive_ring.position.y = 0.05
		add_child(revive_ring)
		var pm := MeshKit.Builder.new()
		pm.sphere(0.07, Transform3D.IDENTITY, Color(1.0, 1.0, 1.0), 6, true)
		var mesh := pm.build()
		for i in 10:
			var a := TAU * i / 10.0
			var pip := MeshKit.instance(mesh, false)
			pip.position = Vector3(cos(a) * 0.7, 0.0, sin(a) * 0.7)
			revive_ring.add_child(pip)
			revive_pips.append(pip)
	if revive_ring != null:
		revive_ring.visible = on
	ring.visible = not on


## Deep: how far a friend got helping them up (0..1): the pips light up one by one.
func set_revive(k: float) -> void:
	if revive_ring == null:
		return
	var lit := int(k * 10.0 + 0.001)
	for i in revive_pips.size():
		revive_pips[i].scale = Vector3.ONE * (1.6 if i < lit else 0.8)
		revive_pips[i].visible = i < lit or fmod(Time.get_ticks_msec() * 0.002, 1.0) < 0.7


## Deep: ouch (a red flash, then blink for a moment).
func hurt() -> void:
	anim.hurt(Color(1.0, 0.3, 0.3))
	hurt_t = 1.0


## Owner: slide for a moment (dash, shield bash, knock-back).
func push(v: Vector3, secs: float) -> void:
	push_v = v
	push_t = secs


## Owner: walk (dir is world-space, length 0..1), kept inside the dungeon by clamp (from, to) -> to.
func step(delta: float, dir: Vector3, clamp: Callable) -> void:
	bonk_cd = maxf(0.0, bonk_cd - delta)
	if dizzy_t > 0.0 or down:
		dir = Vector3.ZERO
	var to := position + dir * SPEED * speed_mul * delta
	if push_t > 0.0:
		push_t -= delta
		to += push_v * delta
	to = clamp.call(position, to)
	moving = (to - position).length() / maxf(delta, 0.0001)
	position = to
	if dir.length() > 0.2:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-14.0 * delta))


## Mirror: where the owner says the hero is.
func set_remote(p: Vector3, yaw: float, dizzy: bool) -> void:
	if not _has_target or p.distance_to(position) > 4.0:
		position = p
	_target = p
	_target_yaw = yaw
	_has_target = true
	if dizzy and dizzy_t <= 0.0:
		get_dizzy()
	elif not dizzy and dizzy_t > 0.0:
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
	anim.walk(moving if dizzy_t <= 0.0 and not down else 0.0)
	if hurt_t > 0.0:
		hurt_t = maxf(0.0, hurt_t - delta)
		body.visible = hurt_t <= 0.0 or fmod(hurt_t, 0.16) > 0.06
	ring.scale = Vector3.ONE * (1.0 + (0.15 * sin(Time.get_ticks_msec() * 0.01) if safe_t > 0.0 else 0.0))


## Deep: a glowing bubble round the hero while the BUBBLE SHIELD is up.
func set_bubble(on: bool) -> void:
	if on == (bubble != null):
		return
	if not on:
		bubble.queue_free()
		bubble = null
		return
	var b := MeshKit.Builder.new()
	var col := Color(0.55, 0.8, 1.0)
	b.torus(0.62, 0.025, Transform3D.IDENTITY, col, 24, 4, true)
	b.torus(0.62, 0.025, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, 0, 0)), col, 24, 4, true)
	b.torus(0.62, 0.025, MeshKit.at(Vector3.ZERO, Vector3.ONE, Vector3(PI * 0.5, PI * 0.5, 0)), col, 24, 4, true)
	bubble = MeshKit.instance(b.build(), false)
	bubble.position.y = 0.6
	add_child(bubble)
