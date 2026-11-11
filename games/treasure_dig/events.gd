extends Node3D
## TREASURE DIG warned events (deep.gd events()): told first by core/warn_rings.gd on every machine, then they happen.
##   TIDE  a blue band from the shore flashes, then the sea rolls over it (splash): diggers in it are knocked over.
##   DROP  round rings: coconuts (snowballs / lava rocks) drop from the sky and bonk whoever stands there.
##   GOLD  a gold disc: Polly drops a golden gem there (a loose gem anyone can grab, the giant too).
## The host sends "event" [kind, data, warn] when a warning starts; every machine draws the tell and the falling
## things; only the host decides who is bonked and makes the treasure (main.gd on_event_hit).
## The rings live in the world (not under the beach): positions and sizes go through main.beach / main.S.
##   host: reset(list); tick(elapsed, warn) -> the events whose warning starts now
##   every machine: announce(kind, data, warn); clear(); hits_now() (bots)

const WarnRings := preload("res://core/warn_rings.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Deep := preload("res://games/treasure_dig/deep.gd")
const Props := preload("res://games/treasure_dig/props.gd")
const Contrast := preload("res://core/contrast.gd")

const FALL := 0.7  # the last seconds of a DROP / GOLD warning: the thing is seen falling

var main
var rings: WarnRings
var list: Array = []  # host: this round's events
var warned := {}
var fired := {}  # host: kind -> count over the whole session (bots)
var live: Array = []  # every machine: [{kind, data, t (s to go), node}]
var seen := 0  # every machine: tells drawn (bots)


func _ready() -> void:
	name = "Events"
	rings = WarnRings.new()
	add_child(rings)


## Host: a new round's events (picks / results: none).
func reset(new_list: Array) -> void:
	list = new_list.duplicate(true)
	warned = {}


## Host: the events whose warning starts now (round seconds `elapsed`).
func tick(elapsed: float, warn: float) -> Array:
	var out: Array = []
	for i in list.size():
		var e: Array = list[i]
		if not warned.has(i) and elapsed >= float(e[0]) - warn:
			warned[i] = true
			fired[String(e[1])] = int(fired.get(String(e[1]), 0)) + 1
			out.append(e)
	return out


func _g(local: Vector3) -> Vector3:
	return main.beach.to_global(local)


## Every machine: draw the tell now; the event happens after `warn` seconds.
func announce(kind: String, data: Variant, warn: float, look: String = "coconut") -> void:
	seen += 1
	var s: float = main.S
	var y: float = main.BEACH_Y + 0.02
	var entry := {"kind": kind, "data": data, "t": warn, "nodes": [], "look": look}
	match kind:
		"tide":
			var band := Deep.tide_band(float(data))
			var sz: Vector2 = band[2]
			rings.shape("line", _g(band[0]), band[1], sz * s, Deep.TIDE_COLOR, warn, {"style": "flash", "y": y, "stay": Deep.STAY})
			main.sound("whoosh", -6.0, 0.6)
		"drop":
			for p in data:
				rings.warn(_g(p), Deep.DROP_R * s, Deep.DROP_COLOR, warn, y, {"stay": Deep.STAY})
				var ball := Contrast.outline(MeshKit.instance(Props.falling(look), false), Props.RELIC_OUTLINE, Props.FALL_OUTLINE) as Node3D
				ball.position = (p as Vector3) + Vector3.UP * 30.0
				ball.visible = false
				main.beach.add_child(ball)
				(entry.nodes as Array).append(ball)
			main.sound("ui_notify", -4.0, 0.7)
		"gold":
			rings.warn(_g(data), Deep.GOLD_R * s, Deep.GOLD_COLOR, warn, y, {"style": "disc", "stay": Deep.STAY})
			var star := MeshKit.instance(Props.gold_star(), false)
			star.position = (data as Vector3) + Vector3.UP * 30.0
			star.visible = false
			main.beach.add_child(star)
			(entry.nodes as Array).append(star)
			main.sound("sparkle", -2.0, 1.2)
	live.append(entry)


## Every machine: all gone (a new round, the results).
func clear() -> void:
	rings.clear()
	for e in live:
		for n in e.nodes:
			if is_instance_valid(n):
				(n as Node).queue_free()
	live.clear()


## Bots: the tells showing now (beach-local): [{kind, data, t}].
func hits_now() -> Array:
	var out: Array = []
	for e in live:
		out.append({"kind": e.kind, "data": e.data, "t": e.t})
	return out


func _process(delta: float) -> void:
	for i in range(live.size() - 1, -1, -1):
		var e: Dictionary = live[i]
		e.t = float(e.t) - delta
		var t := float(e.t)
		# Falling coconuts / the golden star: seen for the last FALL seconds.
		var k := clampf(1.0 - t / FALL, 0.0, 1.0)
		var pts: Array = e.data if String(e.kind) == "drop" else ([e.data] if String(e.kind) == "gold" else [])
		for j in (e.nodes as Array).size():
			var n: Node3D = e.nodes[j]
			if not is_instance_valid(n) or j >= pts.size():
				continue
			n.visible = t < FALL
			n.position = (pts[j] as Vector3) + Vector3.UP * (30.0 * (1.0 - k * k) + 0.5)
			n.rotation.y += delta * 6.0
		if t <= 0.0:
			_go_off(e)
			for n in e.nodes:
				if is_instance_valid(n):
					(n as Node).queue_free()
			live.remove_at(i)


## Every machine: the event happens (splash, thump, sparkle); the host decides who is hit.
func _go_off(e: Dictionary) -> void:
	match String(e.kind):
		"tide":
			var band := Deep.tide_band(float(e.data))
			var from: Vector3 = band[0]
			var dir: Vector3 = band[1]
			var side := Vector3(-dir.z, 0.0, dir.x)
			for k in 5:
				main.burst_at(from + dir * (1.0 + k * 0.6) + side * (float(k % 3) - 1.0) * 2.0, Color(0.55, 0.8, 1.0), 26)
			main.sound("splash", 0.0, 0.8)
			main.sound("wind", -6.0, 1.3)
		"drop":
			for p in e.data:
				main.burst_at(p, Color(0.95, 0.82, 0.55), 22)
			main.sound("land", 0.0, 0.7)
			main.sound("boing", -4.0, 0.6)
		"gold":
			main.burst_at(e.data, Color(1.0, 0.85, 0.3), 26)
			main.sound("kaching", -2.0, 1.2)
	if main.net.mode != "client":
		main.on_event_hit(String(e.kind), e.data)
