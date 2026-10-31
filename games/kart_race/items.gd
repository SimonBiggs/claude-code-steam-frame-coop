extends RefCounted
## KART RACE power-ups: a small, fair set of seven, all INSTANT (a ? box does its thing at once: no buttons, so the
## little ones get them too; a picture pops up to show what it was). Who gets what depends on your place, so the
## karts at the back get the zoomy catch-up things and the leaders get the defensive ones:
##   ZOOM      a speed burst                                    anyone
##   TRIPLE    three zooms in a row                             middle and back
##   STAR      rainbow star: fast, bumps others, beats hazards  back half
##   BUBBLE    a bubble shield (bananas, bumpers, puddles, honks bounce off)   front and middle
##   BANANA    dropped behind you for the karts that follow     front half only
##   HONK      the silly honk: karts nearby wobble              never the leader
##   ROCKET    a long rocket ride that steers itself (VR: a long zoom, no steering)   last third, people only
## GENTLE adds a little extra catch-up at the back; ZOOM halves the rocket. TIME TRIAL has no boxes.
## check() is part of the validator (tests/kart_trackgen_test.gd): leaders never get the catch-up items, the last
## kart never drops bananas on nobody, every item turns up somewhere, and the back gets more zoom than the front.

const ORDER: Array[String] = ["zoom", "triple", "star", "bubble", "banana", "honk", "rocket"]
const PICS := {"zoom": "mushroom", "triple": "mushrooms", "star": "star", "bubble": "bubble", "banana": "banana", "honk": "horn",
	"rocket": "rocket"}
const COLORS := {"zoom": Color(1.0, 0.35, 0.3), "triple": Color(1.0, 0.45, 0.3), "star": Color(1.0, 0.9, 0.3), "bubble": Color(0.5, 0.85, 1.0),
	"banana": Color(1.0, 0.9, 0.3), "honk": Color(1.0, 0.55, 0.85), "rocket": Color(0.95, 0.4, 0.3)}
## Seconds of speed boost each one is worth (for the catch-up check).
const BOOST := {"zoom": 1.8, "triple": 5.4, "star": 5.0, "bubble": 0.0, "banana": 0.0, "honk": 0.0, "rocket": 3.2}
const ROCKET_TIME := 3.2


## Weights for a kart at `behind` (0 = leading .. 1 = last), for a person or a CPU, at speed `mode_id`.
static func weights(behind: float, human: bool, mode_id: String) -> Dictionary:
	var b := clampf(behind, 0.0, 1.0)
	var w := {"zoom": 30.0,
		"triple": 30.0 * b if b >= 0.34 else 0.0,
		"star": 24.0 * b if b >= 0.5 else 0.0,
		"bubble": 24.0 * (1.0 - b) if b < 0.85 else 0.0,
		"banana": 26.0 * (1.0 - b) if b <= 0.5 else 0.0,
		"honk": 14.0 * b,
		"rocket": 30.0 * (b - 0.5) if b >= 0.67 and human else 0.0}
	if mode_id == "gentle" and b >= 0.67:
		w["star"] = float(w.star) * 1.5
		w["rocket"] = float(w.rocket) * 1.5
	elif mode_id == "zoom":
		w["rocket"] = float(w.rocket) * 0.5
	return w


## Pick one from weights with a 0..1 roll.
static func pick(w: Dictionary, roll: float) -> String:
	var total := 0.0
	for k in ORDER:
		total += float(w.get(k, 0.0))
	var r := roll * total
	for k in ORDER:
		r -= float(w.get(k, 0.0))
		if r <= 0.0 and float(w.get(k, 0.0)) > 0.0:
			return k
	return "zoom"


## How far back a kart is: 0 leading .. 1 last (alone: 0.5).
static func behind_of(place: int, racers: int) -> float:
	if racers <= 1:
		return 0.5
	return clampf(float(place - 1) / float(racers - 1), 0.0, 1.0)


## Expected seconds of boost from a box at `behind`.
static func expected_boost(behind: float, human: bool, mode_id: String) -> float:
	var w := weights(behind, human, mode_id)
	var total := 0.0
	var e := 0.0
	for k in ORDER:
		total += float(w[k])
		e += float(w[k]) * float(BOOST[k])
	return e / maxf(total, 0.001)


## Problems with the item set (empty = fair).
static func check(has_picture: Callable) -> Array[String]:
	var why: Array[String] = []
	if ORDER.size() < 6 or ORDER.size() > 8:
		why.append("6-8 power-ups (%d)" % ORDER.size())
	var seen := {}
	for m in ["gentle", "zoom"]:
		for i in 11:
			var b := i / 10.0
			for human in [true, false]:
				var w := weights(b, human, m)
				var total := 0.0
				for k in ORDER:
					total += float(w[k])
					if float(w[k]) > 0.0:
						seen[k] = true
				if total <= 0.0:
					why.append("%s: nothing to give at %.1f" % [m, b])
		var lead := weights(0.0, true, m)
		for k in ["triple", "star", "rocket", "honk"]:
			if float(lead[k]) > 0.0:
				why.append("%s: the leader can get %s" % [m, k])
		var last := weights(1.0, true, m)
		for k in ["banana", "bubble"]:
			if float(last[k]) > 0.0:
				why.append("%s: the last kart can get %s" % [m, k])
		if float(weights(1.0, false, m).rocket) > 0.0:
			why.append("%s: CPUs get rockets" % m)
		# Catch-up: the further back, the more zoom a box is worth (never less).
		var prev := -1.0
		for i in 11:
			var e := expected_boost(i / 10.0, true, m)
			if e < prev - 0.001:
				why.append("%s: less zoom further back (%.1f)" % [m, i / 10.0])
				break
			prev = e
	if expected_boost(1.0, true, "gentle") < expected_boost(1.0, true, "zoom"):
		why.append("gentle helps the back less than zoom")
	for k in ORDER:
		if not seen.has(k):
			why.append("%s is never given" % k)
		if not has_picture.call(String(PICS.get(k, ""))):
			why.append("%s: no picture" % k)
	return why
