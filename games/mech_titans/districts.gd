extends RefCounted
## MECH TITANS city districts (made rounds): every place on the island (data.gd PLACES: its own ground, walls,
## trees, sky and water; the streets come from the round's seed, city.gd) has its own HAZARD that pops up
## now and then while the Titans play. Every hazard is TELEGRAPHED like a kaiju attack: a glowing circle (or
## a stripe for the harbour's wave) appears on the ground first and only then does the thing land there, so
## the Titan always has time to step out (or dash, or raise both hands to block).
##   DOWNTOWN      WATER SPOUT   a fire hydrant bursts: a splash that pushes (no hurt)
##   HARBOUR       BIG WAVE      a wave washes in from the sea along a stripe: a push and a splash
##   POWER PLANT   ZAP SPARK     a sparky circle: slows the Titan for a moment
##   SNOWY PEAKS   SNOWBALL      a giant snowball lands: slows and bumps
##   VOLCANO       LAVA ROCK     two hot rocks: bumps, and buildings may catch fire
##   MOON BASE     METEOR        a little meteor: a bump (the moon's low gravity makes dashes longer)
## How often and how aimed depends on the difficulty (roundgen.gd MODES: gentle aims away from the Titan).
## Pure data so tests/mech_titans_rounds_test.gd can prove every district is fair (check()).

## hazard: id; name (2 words at most, the story card); shape "circle" / "line"; r: radius (or half width) m;
## tell: seconds the warning shows before it lands (at gentle; never shorter than MIN_TELL in any mode);
## dmg: armour knocked off the Titan (0 = just a push); slow: seconds the Titan walks slowly; push: m;
## count: how many land at once; fx: fx.gd burst kind; color: the warning's colour; pic: story picture;
## dash: dash distance multiplier in this district (the moon's low gravity).
const LIST := {
	"downtown": {"hazard": "spout", "name": "WATER SPOUT", "shape": "circle", "r": 5.0, "tell": 1.8, "dmg": 0.0, "slow": 0.0,
		"push": 6.0, "count": 1, "fx": "splash", "color": Color(0.4, 0.75, 1.0), "pic": "wave", "dash": 1.0, "sfx": "splash"},
	"harbour": {"hazard": "wave", "name": "BIG WAVE", "shape": "line", "r": 4.0, "tell": 2.2, "dmg": 0.0, "slow": 0.0,
		"push": 8.0, "count": 1, "fx": "splash", "color": Color(0.3, 0.6, 1.0), "pic": "wave", "dash": 1.0, "sfx": "splash"},
	"powerplant": {"hazard": "zap", "name": "ZAP SPARK", "shape": "circle", "r": 6.0, "tell": 2.0, "dmg": 5.0, "slow": 2.0,
		"push": 0.0, "count": 1, "fx": "zap", "color": Color(1.0, 0.95, 0.3), "pic": "storm", "dash": 1.0, "sfx": "zap"},
	"snowy": {"hazard": "snowball", "name": "SNOWBALL", "shape": "circle", "r": 6.0, "tell": 2.0, "dmg": 4.0, "slow": 2.5,
		"push": 3.0, "count": 1, "fx": "dust", "color": Color(0.85, 0.95, 1.0), "pic": "snowman", "dash": 1.0, "sfx": "land"},
	"volcano": {"hazard": "lava", "name": "LAVA ROCK", "shape": "circle", "r": 5.0, "tell": 2.0, "dmg": 6.0, "slow": 0.0,
		"push": 2.0, "count": 2, "fx": "fire", "color": Color(1.0, 0.45, 0.15), "pic": "storm", "dash": 1.0, "sfx": "explosion"},
	"moon": {"hazard": "meteor", "name": "METEOR", "shape": "circle", "r": 7.0, "tell": 2.2, "dmg": 6.0, "slow": 0.0,
		"push": 3.0, "count": 1, "fx": "sparks", "color": Color(0.8, 0.6, 1.0), "pic": "rocket", "dash": 1.3, "sfx": "explosion"},
}
const MIN_TELL := 1.5  ## no hazard ever warns for less than this (seconds)
const REACT := 0.6  ## seconds a player needs to notice the warning before moving
const WALK := 6.5  ## mech.gd WALK_SPEED (m/s), copied so this file stays pure data
const SLOW_WALK := 0.5  ## mech.gd: slowed Titans walk at half speed
const TITAN_R := 2.6  ## mech.gd RADIUS


static func info(place: String) -> Dictionary:
	return LIST.get(place, LIST["downtown"])


## The hazard plan of a round: {every: seconds between hazards (0 = none), tell, aim (true: at the Titan),
## count} for this place at this difficulty curve point (roundgen.gd curve()).
static func plan(place: String, curve: Dictionary) -> Dictionary:
	var h := info(place)
	var every := float(curve.get("haz_every", 0.0))
	return {"every": every, "tell": maxf(MIN_TELL, float(h["tell"]) * float(curve.get("tell", 1.0))),
		"aim": bool(curve.get("haz_aim", false)), "count": int(h["count"]) * int(curve.get("haz_count", 1)),
		"dmg": float(h["dmg"]) * float(curve.get("dmg", 1.0)), "slow": float(h["slow"])}


## The worst time the Titan needs to get out of a warning, standing right in its middle (slowed, if this
## hazard slows): half the warning across plus its own radius, walking.
static func escape_time(place: String, slowed: bool) -> float:
	var h := info(place)
	var spd := WALK * (SLOW_WALK if slowed else 1.0)
	return REACT + (float(h["r"]) + TITAN_R) / spd


## Why this district's hazards aren't fair at this curve point (empty = fair). A Titan in the middle of a
## warning can always walk out in time (even still slowed from the last one in a gentle round); a slowing
## hazard never comes again before its slow wears off; hazards alone never knock a gentle Titan over in a
## minute (armour 100; it also refills between rounds).
static func check(place: String, curve: Dictionary, gentle: bool) -> Array:
	var out: Array = []
	if not LIST.has(place):
		return ["no district for %s" % place]
	var h := info(place)
	var p := plan(place, curve)
	if float(p["every"]) <= 0.0:
		return out
	if float(p["tell"]) < MIN_TELL - 0.001:
		out.append("%s warns for %.2f s" % [h["name"], p["tell"]])
	if float(p["tell"]) < escape_time(place, false):
		out.append("%s: the Titan can't walk out in %.2f s (needs %.2f)" % [h["name"], p["tell"], escape_time(place, false)])
	if float(h["slow"]) > 0.0 and float(p["every"]) <= float(h["slow"]) + 1.0:
		out.append("%s comes again before its slow wears off" % h["name"])
	if gentle:
		if float(p["tell"]) < escape_time(place, float(h["slow"]) > 0.0):
			out.append("%s: a slowed Titan can't walk out at gentle" % h["name"])
		if bool(p["aim"]):
			out.append("%s aims at the Titan at gentle" % h["name"])
		var per_min := 60.0 / float(p["every"]) * float(p["count"]) * float(p["dmg"])
		if per_min >= 40.0:
			out.append("%s knocks %.0f armour a minute at gentle" % [h["name"], per_min])
	if float(p["every"]) < 5.0:
		out.append("%s every %.1f s is too often" % [h["name"], p["every"]])
	var words := String(h["name"]).split(" ", false)
	if words.size() > 2 or String(h["name"]) != String(h["name"]).to_upper():
		out.append("hazard name '%s' must be one or two capital words" % h["name"])
	return out
