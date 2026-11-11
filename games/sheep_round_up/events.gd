extends Node3D
## SHEEP ROUND-UP EVENTS (second pass, seasons.gd): a FOX at the fence and THUNDER. Each one is told first:
## Seasons.WARN_SECS early warning rings pulse on the ground where it will happen (core/warn_rings.gd, every machine)
## and Bo shows a picture card. Then the fox trots in towards the nearest loose sheep (sheep near it scatter) until a
## dog runs at it or barks near it (it dashes home) or Seasons.FOX_SECS pass; a thunder clap scatters the loose sheep
## near the strike. The host runs the clock (the field's seconds, events made per field) and sends "sev"
## [kind, x, z, r]; the fox's place is the "fox" state [x, z, yaw, on]. Every machine draws.

const Seasons := preload("res://games/sheep_round_up/seasons.gd")
const WarnRings := preload("res://core/warn_rings.gd")
const Creatures := preload("res://core/creatures.gd")

var main: Node
var rings: WarnRings
var events: Array = []  # host: this field's [t, kind, x, z, r]
var warned := {}
var fired := 0  # host: events told this field (telemetry)
var chased := 0  # host: foxes a dog sent home
var pending: Array = []  # every machine: [secs left, kind, Vector3, r]
var fox: Node3D
var fox_on := false
var fox_t := 0.0  # host: seconds the fox has left
var fox_leaving := false
var flash: OmniLight3D
var flash_t := 0.0


func _ready() -> void:
	name = "SheepEvents"
	rings = WarnRings.new()
	add_child(rings)
	fox = Creatures.monster("fox", {"lod": "far"})
	fox.scale = Vector3.ONE * 0.9
	fox.visible = false
	add_child(fox)
	flash = OmniLight3D.new()
	flash.omni_range = 9.0
	flash.light_color = Color(0.85, 0.9, 1.0)
	flash.light_energy = 0.0
	flash.shadow_enabled = false
	add_child(flash)


## Host: a new field's events.
func reset(list: Array) -> void:
	events = list.duplicate(true)
	warned = {}
	fired = 0
	chased = 0


## Every machine: all gone (a new field).
func clear() -> void:
	rings.clear()
	pending.clear()
	fox_on = false
	fox.visible = false


## Host: start the warning for any event WARN_SECS away. Returns the events that start warning now.
func tick(field_t: float) -> Array:
	var out: Array = []
	for i in events.size():
		var e: Array = events[i]
		if not warned.has(i) and field_t >= float(e[0]) - Seasons.WARN_SECS:
			warned[i] = true
			fired += 1
			out.append(e)
	return out


## Every machine: the rings now, the fox / the strike after the warning.
func announce(kind: String, x: float, z: float, r: float) -> void:
	var at := Vector3(x, 0.0, z)
	if kind == "thunder":
		rings.warn(at, r, Seasons.EVENT_COLORS.thunder, Seasons.WARN_SECS, 0.05)
	else:
		rings.warn(at, r, Seasons.EVENT_COLORS.fox, Seasons.WARN_SECS, 0.05, {"style": "disc"})
	pending.append([Seasons.WARN_SECS, kind, at, r])
	main.sound("whistle" if kind == "fox" else "wave", -6.0, 0.7 if kind == "thunder" else 1.3)


## Host: how hard a loose sheep at pos is pushed away from the fox (zero when it's far or gone).
func push_at(pos: Vector3) -> Vector3:
	if not fox_on or fox_leaving:
		return Vector3.ZERO
	var away := pos - fox.position
	away.y = 0.0
	var d := away.length()
	if d >= Seasons.FOX_SCARE or d < 0.001:
		return Vector3.ZERO
	return away / d * (1.0 - d / Seasons.FOX_SCARE) * 1.6


func _process(delta: float) -> void:
	var host: bool = main.net.mode != "client"
	for i in range(pending.size() - 1, -1, -1):
		var pe: Array = pending[i]
		pe[0] = float(pe[0]) - delta
		if float(pe[0]) > 0.0:
			continue
		pending.remove_at(i)
		var at: Vector3 = pe[2]
		if String(pe[1]) == "thunder":
			_strike(at, float(pe[3]), host)
		elif host:
			fox_on = true
			fox_leaving = false
			fox_t = Seasons.FOX_SECS
			fox.position = at
	if flash_t > 0.0:
		flash_t -= delta
		flash.light_energy = maxf(0.0, flash_t) * 12.0
	if host:
		_fox_host(delta)
	else:
		var st: Array = main.net.state_get("fox", [0.0, 0.0, 0.0, false])
		fox_on = bool(st[3])
		if fox_on:
			var to := Vector3(float(st[0]), 0.0, float(st[1]))
			fox.position = fox.position.lerp(to, 1.0 - exp(-12.0 * delta)) if fox.visible else to
			fox.rotation.y = float(st[2])
	fox.visible = fox_on


## Every machine: a flash and a boom; the host scatters the loose sheep near the strike.
func _strike(at: Vector3, r: float, host: bool) -> void:
	flash.position = at + Vector3.UP * 4.0
	flash_t = 0.35
	main.sound("explosion", -6.0, 0.6)
	main.burst(at + Vector3.UP * 0.3, Color(0.85, 0.9, 1.0), 24)
	if not host:
		return
	for s in main.sheep:
		if bool(s.get("penned")) or int(s.get("state")) != 0:
			continue
		var away: Vector3 = s.position - at
		away.y = 0.0
		var d := away.length()
		if d < r:
			var dir := away / d if d > 0.01 else Vector3.RIGHT
			s.set("vel", dir * 4.5 * (1.0 - d / r * 0.5))
	print("Thunder at (%.1f, %.1f)" % [at.x, at.z])


## Host: the fox trots to the nearest loose sheep; a dog close by (or a bark) sends it home.
func _fox_host(delta: float) -> void:
	if not fox_on:
		if main.net.state_get("fox", [0, 0, 0, false])[3]:
			main.net.state_set("fox", [0.0, 0.0, 0.0, false])
		return
	fox_t -= delta
	var target := Vector3.ZERO
	if not fox_leaving:
		for slot in main.dogs:
			var dp: Vector3 = (main.dogs[slot] as Node3D).position
			var near := Vector2(dp.x - fox.position.x, dp.z - fox.position.z).length()
			if near < 1.4 or (float(main.bark_t.get(slot, 0.0)) > 0.0 and near < main.BARK_R):
				fox_leaving = true
				chased += 1
				main.fox_chased(int(slot), fox.position)
				break
		if fox_t <= 0.0:
			fox_leaving = true
	var spd := Seasons.FOX_SPEED
	if fox_leaving:
		var out := Vector3(fox.position.x, 0.0, fox.position.z)
		target = out.normalized() * (main.ARENA + 3.0) if out.length() > 0.1 else Vector3(main.ARENA + 3.0, 0, 0)
		spd *= 2.2
		if Vector2(fox.position.x, fox.position.z).length() > main.ARENA + 1.5:
			fox_on = false
	else:
		var best := INF
		target = fox.position
		for s in main.sheep:
			if bool(s.get("penned")):
				continue
			var dd: float = s.position.distance_to(fox.position)
			if dd < best:
				best = dd
				target = s.position
	var step := target - fox.position
	step.y = 0.0
	if step.length() > 0.3:
		fox.position += step.normalized() * minf(spd * delta, step.length())
		if not fox_leaving and main.field.size() > 0:
			fox.position = main.FieldGen.move_dog(main.field, fox.position)
		Creatures.face_now(fox, step)
	main.net.state_set("fox", [snappedf(fox.position.x, 0.01), snappedf(fox.position.z, 0.01), snappedf(fox.rotation.y, 0.01), fox_on])
