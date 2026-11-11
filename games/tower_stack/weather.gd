extends Node3D
## WEATHER EVENTS (Tower Stack, second pass): a job's GUSTs and QUAKEs (towergen.gd site.events, seeded, inside the
## plan's tipping limit). Each one is announced first: WARN_SECS early a warning ring pulses round the stage
## (core/warn_rings.gd, on every machine), Wren shows a picture card (a blowing cloud / a shaking stage), and the
## wind sock jiggles; then for EVENT_SECS the gust pushes the tower's blocks harder (main.gd _weather) or the jelly
## stage shakes. The host runs the clock (the job's seconds) and sends "weather" events; every machine draws.
##   weather.reset(site)    host: weather.tick(job_t) -> starts warnings    weather.extra(job_t) -> Vector2(gust, quake)
##   every machine: weather.announce(kind, secs)

const G := preload("res://games/tower_stack/towergen.gd")
const WarnRings := preload("res://core/warn_rings.gd")

const COLORS := {"gust": Color(0.55, 0.85, 1.0), "quake": Color(1.0, 0.6, 0.25)}
const RING_R := 1.75  # just outside the stage (main.gd BASE_R 1.2)

var main: Node
var rings: WarnRings
var events: Array = []
var warned := {}  # event index -> true (host)
var fired := 0  # events that warned this job (telemetry)
var shake_t := 0.0  # every machine: the wind sock jiggles while > 0


func _ready() -> void:
	name = "Weather"
	rings = WarnRings.new()
	add_child(rings)


func reset(s: Dictionary) -> void:
	events = (s.get("events", []) as Array).duplicate(true)
	warned = {}


## Host: start the warning for any event WARN_SECS away. Returns the kinds that started warning now.
func tick(job_t: float) -> Array:
	var out: Array = []
	for i in events.size():
		var e: Array = events[i]
		if not warned.has(i) and job_t >= float(e[0]) - G.WARN_SECS and job_t < float(e[0]) + G.EVENT_SECS:
			warned[i] = true
			fired += 1
			out.append(String(e[1]))
	return out


## Host: the extra wind (x, m/s^2) and stage tilt (y, radians) of the event happening at job_t (warned ones only).
func extra(job_t: float) -> Vector2:
	var v := Vector2.ZERO
	for i in events.size():
		var e: Array = events[i]
		var dt := job_t - float(e[0])
		if warned.has(i) and dt >= 0.0 and dt < G.EVENT_SECS:
			var k := sin(dt / G.EVENT_SECS * PI)  # builds up and dies down
			if String(e[1]) == "gust":
				v.x = maxf(v.x, float(e[2]) * k)
			else:
				v.y = maxf(v.y, float(e[2]) * k)
	return v


## Every machine: the warning (ring round the stage for the warning and the event itself).
func announce(kind: String) -> void:
	rings.warn(Vector3.ZERO, RING_R, COLORS.get(kind, Color.WHITE), G.WARN_SECS + G.EVENT_SECS, 0.06)
	shake_t = G.WARN_SECS + G.EVENT_SECS


func _process(delta: float) -> void:
	if shake_t > 0.0:
		shake_t -= delta
