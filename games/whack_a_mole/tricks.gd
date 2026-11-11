extends Node3D
## WHACK-A-MOLE warned mole tricks (deep.gd tricks()): told first by core/warn_rings.gd on every machine, then they
## happen.
##   GOLD      a gold disc throbs on a hole; a golden mole pops out there (worth 5).
##   STAMPEDE  a red band flashes across a row of holes; in its last moment a line of little moles scampers along it,
##             then they all pop up in the row at once. Hammer-kids standing in the band are bumped.
## The host sends "trick" [kind, data, warn] when a warning starts; every machine draws the tell and the scampering
## moles; only the host pops the moles and decides who is bumped (main.gd on_trick).
##   host: reset(list); tick(elapsed, warn) -> the tricks whose warning starts now
##   every machine: announce(kind, data, warn); clear(); tells_now() (bots)

const WarnRings := preload("res://core/warn_rings.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const Deep := preload("res://games/whack_a_mole/deep.gd")
const Props := preload("res://games/whack_a_mole/props.gd")
const RoundGen := preload("res://games/whack_a_mole/roundgen.gd")

const RUN := 0.8  # the last seconds of a STAMPEDE warning: the little moles are seen running along the row

var main
var rings: WarnRings
var list: Array = []  # host: this round's tricks
var warned := {}
var fired := {}  # host: kind -> count over the whole session (bots)
var live: Array = []  # every machine: [{kind, data, t (s to go), nodes}]
var seen := 0  # every machine: tells drawn (bots)


func _ready() -> void:
	name = "Tricks"
	rings = WarnRings.new()
	add_child(rings)


## Host: a new round's tricks (picks / results: none).
func reset(new_list: Array) -> void:
	list = new_list.duplicate(true)
	warned = {}


## Host: the tricks whose warning starts now (round seconds `elapsed`).
func tick(elapsed: float, warn: float) -> Array:
	var out: Array = []
	for i in list.size():
		var e: Array = list[i]
		if not warned.has(i) and elapsed >= float(e[0]) - warn:
			warned[i] = true
			fired[String(e[1])] = int(fired.get(String(e[1]), 0)) + 1
			out.append(e)
	return out


## Every machine: draw the tell now; the trick happens after `warn` seconds.
func announce(kind: String, data: int, warn: float, mode: String) -> void:
	seen += 1
	var y := Props.TABLE_Y + 0.012
	var entry := {"kind": kind, "data": data, "t": warn, "nodes": [], "mode": mode}
	match kind:
		"gold":
			var p: Vector3 = main.holes[clampi(data, 0, main.holes.size() - 1)]
			rings.warn(p, Deep.GOLD_R, Deep.GOLD_COLOR, warn, y, {"style": "disc", "stay": Deep.STAY})
			main.sfx.play_at("sparkle", p, -4.0, 1.4)
		"stampede":
			var b := Deep.band(data)
			rings.shape("line", b[0], b[1], b[2], Deep.HERD_COLOR, warn, {"style": "flash", "y": y, "stay": Deep.STAY, "alpha": 0.5})
			var runners := Node3D.new()
			runners.visible = false
			var mesh: Mesh = main.kind_mesh_of(RoundGen.NORMAL)
			for k in Deep.herd_holes(data, mode).size():
				var m := MeshKit.instance(mesh, false)
				m.scale = Vector3.ONE * 0.45
				m.position = Vector3(-0.32 * k, 0.0, 0.0)
				m.rotation.y = PI * 0.5  # (running along the row, towards +x)
				runners.add_child(m)
			runners.position = b[0]
			add_child(runners)
			(entry.nodes as Array).append(runners)
			main.sound("ui_notify", -4.0, 0.7)
	live.append(entry)


## Every machine: all gone (a new round, the results).
func clear() -> void:
	rings.clear()
	for e in live:
		for n in e.nodes:
			if is_instance_valid(n):
				(n as Node).queue_free()
	live.clear()


## Bots: the tells showing now: [{kind, data, t}].
func tells_now() -> Array:
	var out: Array = []
	for e in live:
		out.append({"kind": e.kind, "data": e.data, "t": e.t})
	return out


func _process(delta: float) -> void:
	for i in range(live.size() - 1, -1, -1):
		var e: Dictionary = live[i]
		e.t = float(e.t) - delta
		var t := float(e.t)
		if String(e.kind) == "stampede":  # the little moles scamper along the row in the last RUN seconds
			var k := clampf(1.0 - t / RUN, 0.0, 1.0)
			var b := Deep.band(int(e.data))
			for n in e.nodes:
				if is_instance_valid(n):
					var nd: Node3D = n
					nd.visible = t < RUN
					nd.position = (b[0] as Vector3) + Vector3.RIGHT * ((b[2] as Vector2).x + 1.0) * k + Vector3.UP * absf(sin(k * 30.0)) * 0.05
		if t <= 0.0:
			_go_off(e)
			for n in e.nodes:
				if is_instance_valid(n):
					(n as Node).queue_free()
			live.remove_at(i)


## Every machine: the trick happens (a sparkle burst / a dusty rumble); the host pops the moles and bumps the kids.
func _go_off(e: Dictionary) -> void:
	match String(e.kind):
		"gold":
			var p: Vector3 = main.holes[clampi(int(e.data), 0, main.holes.size() - 1)]
			main.burst_at(p, Color(1.0, 0.85, 0.3))
			main.sfx.play_at("kaching", p, -2.0, 1.2)
		"stampede":
			for h in Deep.herd_holes(int(e.data), String(e.mode)):
				main.burst_at(main.holes[int(h)], Color(0.7, 0.5, 0.3))
			main.sound("land", 0.0, 0.6)
			main.sound("boing", -4.0, 0.8)
	if main.net.mode != "client":
		main.on_trick(String(e.kind), int(e.data))