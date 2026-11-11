extends Node3D
## ELEMENTAL BENDER island hazards and danger rings (built the same on every machine).
## - VENTS (arenas.gd layout().vents: frost geysers, lava vents, wind spouts): a glowing ring in the ground. Every
##   `period` seconds a vent TELLS (it pulses bright and hisses for `tell` seconds), then BURSTS (a plume: fighters
##   and raiders inside are hurt / pushed by the host, main.gd on_vent_burst). Only while a wave is fighting.
##   Host / local: host_step() runs the clocks and calls main.on_vent_tell(i) / main.on_vent_burst(i); main sends
##   the tell to the TV machines as the event "vent" [i, tell], and every machine plays tell(i) + the burst.
## - WARN rings (bosses' tells): warn(pos, radius, colour, secs) a pulsing ring on the ground where it will hit.

const Arenas := preload("res://games/elemental_bender/arenas.gd")
const MeshKit := preload("res://core/mesh_kit.gd")
const ResCache := preload("res://core/res_cache.gd")

var main: Node
var hazard := ""
var vents: Array = []
var clocks: Array[float] = []
var told: Array[bool] = []
var _rings: Array[MeshInstance3D] = []
var _glow: Array[float] = []  # seconds of tell left (every machine)
var _warns: Array = []  # [node, t, secs]
var _t := 0.0


func setup(lay: Dictionary, hazard_id: String) -> void:
	hazard = hazard_id
	vents = lay.get("vents", []) if hazard != "" else []
	var col := color()
	for i in vents.size():
		var v: Dictionary = vents[i]
		var mi := MeshInstance3D.new()
		mi.mesh = _vent_mesh(hazard)
		mi.material_override = MeshKit.material(col, 1.2)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = (v.p as Vector3) + Vector3.UP * 0.03
		mi.scale = Vector3(float(v.r), 1.0, float(v.r))
		add_child(mi)
		_rings.append(mi)
		_glow.append(0.0)
		clocks.append(float(v.offset))
		told.append(false)


func color() -> Color:
	return Arenas.HAZARDS[hazard].color if Arenas.HAZARDS.has(hazard) else Color.WHITE


static func _vent_mesh(kind: String) -> ArrayMesh:
	return ResCache.get_or_make("eb_vent_%s_v1" % kind, func() -> Resource:
		var b := MeshKit.builder()
		b.torus(0.92, 0.08, MeshKit.at(Vector3.ZERO), Color.WHITE, 24, 4)
		b.disc(0.6, MeshKit.at(Vector3.UP * 0.01), Color(0.6, 0.6, 0.6), 16)
		for k in 6:
			var a := k * TAU / 6.0
			b.sphere(0.07, MeshKit.at(Vector3(cos(a) * 0.45, 0.04, sin(a) * 0.45)), Color.WHITE, 6)
		return b.build()) as ArrayMesh


static func _ring_mesh() -> ArrayMesh:
	return ResCache.get_or_make("eb_warn_ring_v1", func() -> Resource:
		var b := MeshKit.builder()
		b.torus(1.0, 0.06, MeshKit.at(Vector3.ZERO), Color.WHITE, 32, 4)
		b.torus(0.55, 0.04, MeshKit.at(Vector3.ZERO), Color.WHITE, 24, 4)
		return b.build()) as ArrayMesh


## Host / local: run the vent clocks (`active` while a wave fights). gentle: a longer warning.
func host_step(delta: float, active: bool, gentle: bool) -> void:
	if not active:
		return
	var tell := tell_time(gentle)
	for i in vents.size():
		clocks[i] -= delta
		if not told[i] and clocks[i] <= tell:
			told[i] = true
			main.call("on_vent_tell", i, tell)
		if clocks[i] <= 0.0:
			clocks[i] += float(vents[i].period)
			told[i] = false
			main.call("on_vent_burst", i)


static func tell_time(gentle: bool) -> float:
	return Arenas.GENTLE_TELL if gentle else Arenas.MIN_TELL + 0.2


## Every machine: vent i glows for `secs` (it is about to burst).
func tell(i: int, secs: float) -> void:
	if i >= 0 and i < _glow.size():
		_glow[i] = secs


## Every machine: the warning ring of a boss attack (or anything) at `pos`.
func warn(pos: Vector3, radius: float, col: Color, secs: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh()
	mi.material_override = MeshKit.material(col, 2.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(pos.x, maxf(pos.y, 0.0) + 0.06, pos.z)
	mi.scale = Vector3(radius, 1.0, radius)
	add_child(mi)
	_warns.append([mi, 0.0, maxf(secs, 0.2), radius])


func _process(delta: float) -> void:
	_t += delta
	for i in _rings.size():
		var r := _rings[i]
		var v: Dictionary = vents[i]
		if _glow[i] > 0.0:
			_glow[i] -= delta
			var k := 1.0 + 0.15 * sin(_t * 22.0)
			r.scale = Vector3(float(v.r) * k, 1.0 + 2.0 * absf(sin(_t * 11.0)), float(v.r) * k)
			r.material_override = MeshKit.material(color().lightened(0.3), 5.0)
			if _glow[i] <= 0.0:
				r.material_override = MeshKit.material(color(), 1.2)
				r.scale = Vector3(float(v.r), 1.0, float(v.r))
		else:
			var s := float(v.r) * (1.0 + 0.04 * sin(_t * 2.0 + i))
			r.scale = Vector3(s, 1.0, s)
	var keep: Array = []
	for w in _warns:
		var n: MeshInstance3D = w[0]
		w[1] = float(w[1]) + delta
		if float(w[1]) >= float(w[2]) or not is_instance_valid(n):
			if is_instance_valid(n):
				n.queue_free()
			continue
		var k := 0.85 + 0.15 * absf(sin(float(w[1]) * 10.0))
		var grow := minf(1.0, float(w[1]) / 0.25)
		n.scale = Vector3(float(w[3]) * k * grow, 1.0, float(w[3]) * k * grow)
		keep.append(w)
	_warns = keep
