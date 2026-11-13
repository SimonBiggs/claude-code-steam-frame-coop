extends Node3D
## A cannonball on a ballistic arc. Ours hit pirate ships and tentacles; theirs punch leaks in our deck.
## On the client every ball is visual only (the host decides hits and sends the effects).

const World := preload("res://games/cannon_cove/world.gd")
const Contrast := preload("res://core/contrast.gd")
const Looks := preload("res://games/cannon_cove/looks.gd")
const UiKit := preload("res://core/ui_kit.gd")

var main
var vel := Vector3.ZERO
var enemy := false
var mega := false  # a golden cannonball: bigger, glowing, explodes in a huge blast
var visual_only := false
var bounced := false  # BOUNCY BALLS: this one already skipped off the sea once
var age := 0.0


func _ready() -> void:
	var m := World.mat(Looks.BALL if not enemy else Looks.ENEMY_BALL, 0.0, 0.3)
	if mega:
		m = World.mat(Looks.MEGA_BALL, 3.0, 0.2)
	var s := World.sphere(self, 0.24 if not mega else 0.4, Vector3.ZERO, m, 10)
	if not enemy and main.ball_slack() > 0.0:
		s.scale = Vector3.ONE * main.Deep.BIG_SCALE  # BIG BARREL: fat cannonballs
	if mega:
		Contrast.outline(s, Looks.OUTLINE)
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A short smoke trail so the ball is easy to follow against the sea.
	var trail := CPUParticles3D.new()
	trail.amount = 10
	trail.lifetime = 0.45
	trail.local_coords = false
	trail.direction = Vector3.UP
	trail.spread = 30.0
	trail.initial_velocity_min = 0.2
	trail.initial_velocity_max = 0.6
	trail.gravity = Vector3.ZERO
	trail.scale_amount_min = 0.6
	trail.scale_amount_max = 1.2
	var tm := SphereMesh.new()
	tm.radius = 0.16
	tm.height = 0.32
	tm.radial_segments = 6
	tm.rings = 3
	var smoke := World.mat(Looks.SMOKE if not enemy else Looks.ENEMY_SMOKE, 0.6)
	if mega:
		smoke = World.mat(Looks.MEGA_SMOKE, 3.0)
		trail.amount = 16
	UiKit.see_through(smoke)
	smoke.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.material = smoke
	trail.mesh = tm
	add_child(trail)


func _physics_process(delta: float) -> void:
	age += delta
	var g: float = main.GRAVITY
	vel.y -= g * delta
	var next := position + vel * delta
	if enemy:
		if next.y <= 0.15 and vel.y < 0.0 and World.on_deck(next):
			if not visual_only:
				main.enemy_ball_hit_deck(Vector3(next.x, 0.0, next.z))
			queue_free()
			return
	else:
		var target = main.ball_hit_test(next)
		if target != null:
			if not visual_only:
				main.on_ball_hit(target, next, mega)
			queue_free()
			return
	var sea: float = main.sea_level
	if next.y < sea:
		if not visual_only:
			if not enemy and main.ball_bounce(self, Vector3(next.x, sea, next.z)):
				queue_free()  # BOUNCY BALLS: it skipped off the sea (a new ball flies on)
				return
			main.splash(Vector3(next.x, sea, next.z), 1.0 if not mega else 2.0)
			if not enemy:
				main.on_ball_splash(Vector3(next.x, sea, next.z))
		queue_free()
		return
	position = next
	if age > 14.0:
		queue_free()
