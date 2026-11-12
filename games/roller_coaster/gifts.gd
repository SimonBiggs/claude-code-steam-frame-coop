extends Node3D
## COASTER CREW: Buttons' gifts on the track and the train (deep.gd GIFTS; a child of the park, park-local like the track).
## Every machine draws them from the state store:
##   "extras"    [[piece, kind], ...] the track gifts that stay on this coaster:
##               BOOSTER   green arrows glowing on the track: the train shoots out of it (host: boost_v)
##               CORKSCREW rainbow hoops round the track: the cars barrel-roll through (train.rolls)
##               SPLASH    water arches over the track: a splash and a star for every rider (host: after_move)
##   "gift_ride" "" | "rainbow" | "bigstars": this ride's gift (a rainbow train with a sparkly trail and a star for every
##               rider at the end; big easy stars). Cleared when the ride ends.
## One merged mesh for the track gifts (cheap on the Frame), rebuilt only when the gifts or the track change.

const MeshKit := preload("res://core/mesh_kit.gd")
const Track := preload("res://games/roller_coaster/track.gd")
const Deep := preload("res://games/roller_coaster/deep.gd")
const UiKit := preload("res://core/ui_kit.gd")

const HOOP_R := 1.35
const HOOP_STEP := 1.3
const ARROW_STEP := 0.95
const RAINBOW: Array[Color] = [Color(1.0, 0.3, 0.3), Color(1.0, 0.65, 0.2), Color(1.0, 0.95, 0.3), Color(0.4, 0.95, 0.4),
	Color(0.35, 0.7, 1.0), Color(0.7, 0.45, 1.0)]

var main
var mi: MeshInstance3D
var shown_key := ""
var ranges: Array = []  # [[s0, s1, kind], ...] (every machine)
var ride_gift := ""
var trail: CPUParticles3D
var _splash_seen := {}  # every machine: "lap:i" -> true once its water burst played
var splash_stars := 0  # host (bots, telemetry)
var boosts := 0


func _ready() -> void:
	name = "Gifts"
	mi = MeshInstance3D.new()
	mi.name = "TrackGifts"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Every machine: show the track gifts (call when "extras" or the track changes).
func refresh() -> void:
	var extras: Array = main.net.state_get("extras", [])
	var key := "%s|%s" % [str(extras), str(main.pieces)]
	if key == shown_key:
		return
	shown_key = key
	ranges = Deep.gift_ranges(main.track, extras) if not main.track.is_empty() else []
	var rolls: Array = []
	for rg in ranges:
		if String(rg[2]) == "corkscrew":
			rolls.append([float(rg[0]), float(rg[1])])
	main.train.rolls = rolls
	if ranges.is_empty():
		mi.mesh = null
		return
	var b := MeshKit.builder()
	for rg in ranges:
		var s0 := float(rg[0])
		var s1 := float(rg[1])
		match String(rg[2]):
			"booster":
				var s := s0 + 0.4
				while s < s1 - 0.3:
					_arrow(b, Track.sample(main.track, s), Color(0.35, 0.95, 0.45))
					s += ARROW_STEP
			"corkscrew":
				var k := 0
				var s := s0 + 0.5
				while s < s1 - 0.3:
					_hoop(b, Track.sample(main.track, s), HOOP_R, RAINBOW[k % RAINBOW.size()], 0.1)
					s += HOOP_STEP
					k += 1
			"splash":
				for s in [s0 + 0.6, (s0 + s1) * 0.5, s1 - 0.6]:
					_arch(b, Track.sample(main.track, s))
	mi.mesh = b.build()


## A glowing chevron lying on the track, pointing the way the train goes.
func _arrow(b: MeshKit.Builder, xf: Transform3D, col: Color) -> void:
	var f := -xf.basis.z
	var up := xf.basis.y
	var r := xf.basis.x
	var tip := xf.origin + up * 0.12 + f * 0.3
	for side in [-1.0, 1.0]:
		var tail: Vector3 = tip - f * 0.45 + r * 0.42 * side
		b.tube(tail, tip, 0.07, 0.07, col, 4, true)


## A ring round the track (the riders' middle).
func _hoop(b: MeshKit.Builder, xf: Transform3D, r: float, col: Color, thick: float) -> void:
	var basis := Basis(xf.basis.x, xf.basis.z, -xf.basis.y).orthonormalized()
	b.torus(r, thick, Transform3D(basis, xf.origin + xf.basis.y * 0.6), col, 20, 4, true)


## A water arch over the track: two posts and a blue half hoop with white drips.
func _arch(b: MeshKit.Builder, xf: Transform3D) -> void:
	var up := xf.basis.y
	var r := xf.basis.x
	var c := xf.origin + up * 0.4
	for side in [-1.0, 1.0]:
		b.tube(xf.origin + r * 0.95 * side - up * 0.1, c + r * 0.95 * side, 0.08, 0.08, Color(0.85, 0.9, 0.95), 5)
	var k := 9
	for i in k:
		var a0 := PI * float(i) / k
		var a1 := PI * float(i + 1) / k
		var p0 := c + r * cos(a0) * 0.95 + up * sin(a0) * 1.25
		var p1 := c + r * cos(a1) * 0.95 + up * sin(a1) * 1.25
		b.tube(p0, p1, 0.11, 0.11, Color(0.35, 0.7, 1.0), 5, true)
	for side in [-0.5, 0.0, 0.5]:
		b.sphere(0.09, Transform3D(Basis(), c + r * side * 0.95 + up * (1.25 * sqrt(1.0 - side * side) - 0.25)), Color(0.85, 0.95, 1.0), 6, true)


## Every machine: this ride's gift (rainbow train / big stars).
func set_ride_gift(kind: String) -> void:
	if kind == ride_gift:
		return
	ride_gift = kind
	main.train.set_rainbow(kind == "rainbow")
	main.train.place(main.track, main.train_s)
	main.restyle_stars()


func big_stars() -> bool:
	return ride_gift == "bigstars"


func star_reach() -> float:
	return Deep.BIG_REACH if big_stars() else main.STAR_REACH


## Host: the speed a booster wants (v unchanged off it).
func boost_v(v: float) -> float:
	var ls := fposmod(float(main.train_s), float(main.track.get("length", 1.0)))
	for rg in ranges:
		if String(rg[2]) == "booster" and ls >= float(rg[0]) and ls <= float(rg[1]):
			if v < Deep.BOOST_V - 0.5:
				boosts += 1 if v < Deep.BOOST_V - 3.0 else 0
			return maxf(v, Deep.BOOST_V)
	return v


func reset_ride() -> void:
	_splash_seen = {}


## Every machine, every ride frame: the splash bursts (and on the host a star for every rider), the rainbow trail.
func tick(_delta: float) -> void:
	var riding: bool = main.phase == "ride" and not main.track.is_empty()
	if trail != null:
		trail.emitting = riding and ride_gift == "rainbow"
	if riding and ride_gift == "rainbow" and main.train.cars.size() > 0:
		if trail == null:
			_make_trail()
		trail.position = (main.train.cars.back() as Node3D).position + Vector3.UP * 0.5
	if not riding:
		if not _splash_seen.is_empty():
			_splash_seen = {}
		return
	var length := float(main.track.get("length", 1.0))
	var s := float(main.train_s)
	var ls := fposmod(s, length)
	for i in ranges.size():
		var rg: Array = ranges[i]
		if String(rg[2]) != "splash":
			continue
		var mid := (float(rg[0]) + float(rg[1])) * 0.5
		var key := "%d:%d" % [int(floor(s / length)), i]
		if ls >= mid and ls <= float(rg[1]) + 1.0 and not _splash_seen.has(key):
			_splash_seen[key] = true
			var pos := Track.sample(main.track, mid).origin + Vector3.UP * 1.2
			main.burst(pos, Color(0.6, 0.85, 1.0), 40, 7.0)
			main.sfx.play_at("splash", to_global(pos), 3.0, 1.1)
			if main.net.mode != "client":
				var cars: Array = main.net.state_get("cars", [])
				splash_stars += main.award_riders((1 << cars.size()) - 1, "splash")


## Host, when a ride ends: the rainbow train gives every rider a star.
func end_ride() -> void:
	if ride_gift == "rainbow":
		var cars: Array = main.net.state_get("cars", [])
		main.award_riders((1 << cars.size()) - 1, "rainbow")


func _make_trail() -> void:
	trail = CPUParticles3D.new()
	trail.name = "RainbowTrail"
	trail.local_coords = false
	trail.amount = 60
	trail.lifetime = 1.2
	trail.gravity = Vector3(0, -0.6, 0)
	trail.initial_velocity_min = 0.2
	trail.initial_velocity_max = 0.8
	trail.spread = 180.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	g.colors = PackedColorArray(RAINBOW)
	trail.color_initial_ramp = g
	var bm := SphereMesh.new()
	bm.radius = 0.12
	bm.height = 0.24
	bm.radial_segments = 6
	bm.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	bm.material = m
	trail.mesh = bm
	add_child(trail)
