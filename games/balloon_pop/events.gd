extends Node3D
## BALLOON POP wind gusts (skies.gd gusts()): told first by core/warn_rings.gd, then every balloon drifts that way.
##   WIND GUST  a wide pale-blue stripe flashes across the park the way the wind will blow (and a whoosh), then for
##              the mode's gust_secs every balloon drifts that way (main.gd _simulate adds gust_velocity()).
## Every machine draws its own rings (the host sends "gust" [dx, dz, warn, secs, speed] when the warning starts);
## only the host moves balloons (snapshots carry them).
##   host: reset(list); tick(elapsed, warn) -> the gusts whose warning starts now
##   every machine: announce(dx, dz, warn, secs, speed); clear(); gust_velocity()

const WarnRings := preload("res://core/warn_rings.gd")
const Skies := preload("res://games/balloon_pop/skies.gd")
const WaveGen := preload("res://games/balloon_pop/wavegen.gd")

var main
var rings: WarnRings
var list: Array = []  # host: this round's [t, dx, dz]
var warned := {}
var fired := 0  # host: gusts told this round (telemetry)
var zones: Array = []  # every machine: [{dir, t (s to go), left, speed}]
var leaves: CPUParticles3D


func _ready() -> void:
	name = "Gusts"
	rings = WarnRings.new()
	add_child(rings)


## Host: a new round's gusts (practice / picks: none).
func reset(new_list: Array) -> void:
	list = new_list.duplicate(true)
	warned = {}
	fired = 0


## Host: the gusts whose warning starts now (round seconds `elapsed`).
func tick(elapsed: float, warn: float) -> Array:
	var out: Array = []
	for i in list.size():
		var g: Array = list[i]
		if not warned.has(i) and elapsed >= float(g[0]) - warn:
			warned[i] = true
			fired += 1
			out.append(g)
	return out


## Every machine: the stripe now, the wind after `warn` seconds.
func announce(dx: float, dz: float, warn: float, secs: float, speed: float) -> void:
	var dir := Vector3(dx, 0.0, dz).normalized()
	var from := -dir * (WaveGen.ARENA - 0.5)
	rings.shape("line", from, dir, Vector2((WaveGen.ARENA - 0.5) * 2.0, 2.4), Skies.GUST_COLOR, warn,
		{"style": "flash", "y": 0.04, "stay": secs, "alpha": Skies.GUST_ALPHA})
	zones.append({"dir": dir, "t": warn, "left": secs, "speed": speed})
	main.sound("whoosh", -6.0, 0.6)


## Every machine: all gone (a new round, the results).
func clear() -> void:
	rings.clear()
	zones.clear()
	if leaves != null:
		leaves.emitting = false


## Host: the wind's push on every balloon now (m/s).
func gust_velocity() -> Vector3:
	var v := Vector3.ZERO
	for z in zones:
		if float(z.t) <= 0.0:
			v += (z.dir as Vector3) * float(z.speed)
	return v


## Is a gust blowing / being told (bots)?
func blowing() -> bool:
	return gust_velocity() != Vector3.ZERO


func _process(delta: float) -> void:
	for i in range(zones.size() - 1, -1, -1):
		var z: Dictionary = zones[i]
		if float(z.t) > 0.0:
			z.t = float(z.t) - delta
			if float(z.t) <= 0.0:
				main.sound("wind", -2.0, 1.0)
				_blow(z.dir as Vector3, float(z.left))
			continue
		z.left = float(z.left) - delta
		if float(z.left) <= 0.0:
			zones.remove_at(i)


## Leaves (or snowflakes, petals: the season's flower colours) whoosh across the park while it blows.
func _blow(dir: Vector3, secs: float) -> void:
	if leaves == null:
		leaves = CPUParticles3D.new()
		leaves.amount = 60
		leaves.lifetime = 2.0
		leaves.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		leaves.emission_box_extents = Vector3(WaveGen.ARENA, 1.5, WaveGen.ARENA)
		leaves.gravity = Vector3(0.0, -0.3, 0.0)
		leaves.spread = 10.0
		leaves.initial_velocity_min = 3.0
		leaves.initial_velocity_max = 5.0
		leaves.scale_amount_min = 0.7
		leaves.scale_amount_max = 1.3
		var qm := QuadMesh.new()
		qm.size = Vector2(0.12, 0.08)
		var m := StandardMaterial3D.new()
		m.albedo_color = main.leaf_color()
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		qm.material = m
		leaves.mesh = qm
		leaves.position = Vector3(0.0, 2.0, 0.0)
		add_child(leaves)
	leaves.direction = dir
	leaves.one_shot = false
	leaves.emitting = true
	get_tree().create_timer(maxf(0.5, secs)).timeout.connect(func() -> void:
		if is_instance_valid(leaves):
			leaves.emitting = false)
