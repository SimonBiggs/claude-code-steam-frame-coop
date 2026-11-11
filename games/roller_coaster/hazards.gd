extends Node3D
## COASTER CREW warned park weather (deep.gd weather; a child of the park, park-local like the track). Every machine draws
## the ride's weather from the state store ("weather": [[kind, s0, s1], ...], set when the lever is pulled) as steady
## core/warn_rings.gd discs glowing along the track until the ride ends - nothing flashes, each kind its own colour:
##   GUST    sky-blue discs along the stretch: riders with their hands DOWN there hold on (a star each).
##   SLEEPY  a lavender disc where the cart stops for a nap: hands UP wakes it (a star); it wakes by itself after `nap` s.
## The host runs the effects (ride_v / after_move from main._ride) and the bot riders' hands (bot_hands).

const WarnRings := preload("res://core/warn_rings.gd")
const Track := preload("res://games/roller_coaster/track.gd")
const Deep := preload("res://games/roller_coaster/deep.gd")
const STAY := 999.0  # a ride is never this long: the discs glow until clear()

var main
var rings: WarnRings
var shown_key := ""
var list: Array = []  # [{kind, s0, s1}] this ride's weather (every machine)
# Host: per lap and stretch, what happened.
var lap_done := {}  # "lap:i" -> true once its effect is over
var gust_up := {}  # "lap:i" -> bitmask of cars that had hands up inside the gust
var nap_t := -1.0  # >= 0: napping (seconds so far)
var nap_key := ""
var told := 0  # stretches told this session (bots)
var gust_stars := 0
var wakes := 0  # sleepy carts woken by hands (bots, telemetry)
var naps := 0


func _ready() -> void:
	name = "Weather"
	rings = WarnRings.new()
	add_child(rings)


## Every machine: show the weather in the state store.
func show_list(raw: Array) -> void:
	var key := str(raw)
	if key == shown_key:
		return
	shown_key = key
	rings.clear()
	list = []
	for r in raw:
		list.append({"kind": String(r[0]), "s0": float(r[1]), "s1": float(r[2])})
	if list.is_empty() or main.track.is_empty():
		return
	told += list.size()
	for e in list:
		var col := color_of(String(e.kind))
		if String(e.kind) == "gust":
			var s := float(e.s0)
			while s <= float(e.s1) + 0.01:
				_disc(s, Deep.DISC_R, col, 0.38)
				s += Deep.DISC_STEP
		else:
			_disc(Deep.stop_s(e), Deep.DISC_R * 1.6, col, 0.5)


func _disc(s: float, r: float, col: Color, alpha: float) -> void:
	var xf := Track.sample(main.track, s)
	var p := xf.origin - xf.basis.y * 0.12
	rings.shape("circle", p, Vector3.FORWARD, Vector2(r, 0.0), col, 0.3,
		{"style": "disc", "stay": STAY, "alpha": alpha, "y": p.y, "hot": col})


static func color_of(kind: String) -> Color:
	return Deep.GUST_COLOR if kind == "gust" else Deep.SLEEPY_COLOR


func clear() -> void:
	rings.clear()
	shown_key = ""
	list = []


## Host: a new ride starts.
func reset_ride() -> void:
	lap_done = {}
	gust_up = {}
	nap_t = -1.0
	nap_key = ""


func _lap_s(s: float) -> float:
	return fposmod(s, float(main.track.get("length", 1.0)))


func _key(s: float, i: int) -> String:
	return "%d:%d" % [int(floor(s / float(main.track.get("length", 1.0)))), i]


## Host, every ride frame before the train moves: the speed the weather wants (v unchanged when none).
func ride_v(v: float, delta: float) -> float:
	var s: float = main.train_s
	var ls := _lap_s(s)
	for i in list.size():
		var e: Dictionary = list[i]
		if String(e.kind) != "sleepy":
			continue
		var key := _key(s, i)
		if lap_done.has(key):
			continue
		var stop := Deep.stop_s(e)
		var to_go := stop - ls
		if nap_key == key:
			nap_t += delta
			var woken: bool = nap_t > 0.6 and main.hand_bits != 0
			if woken or nap_t >= float(Deep.mode_of(main.mode).nap):
				lap_done[key] = true
				nap_key = ""
				nap_t = -1.0
				_wake(woken)
				return Deep.WAKE_V
			return 0.0
		if to_go > 0.0 and to_go < 4.0:
			if to_go < 0.08:
				nap_key = key
				nap_t = 0.0
				naps += 1
				main.sound("ui_back", -6.0, 0.6)
				main.net.event("sound", ["ui_back"])
				return 0.0
			return minf(v, maxf(0.6, to_go * 1.6))  # slowing down, getting sleepy
	return v


func _wake(by_hands: bool) -> void:
	main.sound("wee", -2.0)
	main.net.event("sound", ["wee"])
	if by_hands:
		wakes += 1
		main.award_riders(main.hand_bits, "wake")


## Host, after the train moved: gust bookkeeping (who had hands up inside), the held-on stars as it leaves.
func after_move() -> void:
	var s: float = main.train_s
	var ls := _lap_s(s)
	for i in list.size():
		var e: Dictionary = list[i]
		if String(e.kind) != "gust":
			continue
		var key := _key(s, i)
		if lap_done.has(key):
			continue
		var inside := ls >= float(e.s0) and ls <= float(e.s1)
		if inside:
			gust_up[key] = int(gust_up.get(key, 0)) | int(main.hand_bits)
			if not gust_up.has(key + "w"):
				gust_up[key + "w"] = true
				main.sound("wee", -8.0, 0.7)
				main.net.event("sound", ["wee"])
		elif ls > float(e.s1) and gust_up.has(key + "w"):
			lap_done[key] = true
			var cars: Array = main.net.state_get("cars", [])
			var held := 0
			for c in cars.size():
				if (int(gust_up.get(key, 0)) >> c) & 1 == 0:
					held |= 1 << c
			gust_stars += main.award_riders(held, "gust")


## Host: a bot rider's hands (car i at distance cs): DOWN in a gust, UP when the cart is napping.
func bot_hands(i: int, cs: float, up: bool) -> bool:
	if nap_key != "" and nap_t > 0.7:
		return true
	var ls := _lap_s(cs)
	for e in list:
		if String(e.kind) == "gust" and ls >= float(e.s0) - 1.0 and ls <= float(e.s1) + 0.5:
			return false
	return up


func napping() -> bool:
	return nap_key != ""


## Bots: the weather showing now.
func tells_now() -> Array:
	return list.duplicate(true)
