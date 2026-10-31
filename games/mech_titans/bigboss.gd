extends RefCounted
## MECH TITANS boss kaiju (made rounds): every fifth made round a BIG lost kaiju stomps in wearing a crown.
## Each boss is a giant, tougher version of a kaiju the family knows, with ONE big signature move and a tell
## you can read from across the city: the boss glows in its colour, a crown of sparks pops above its head,
## an alarm plays and a huge warning shape fills the ground for a long moment before it lands.
##   KING SIZZLE    (fire lizard)    KING STOMP  a giant ring all round him
##   MEGA WOBBLES   (jelly)          MEGA FLOP   jumps and lands on a big circle where you stood
##   STORM ZAPPY    (eel-dragon)     STORM RING  a huge lightning ring round itself
##   FROST DUSTY    (giant moth)     FROST GUST  a wide icy wind stripe: slows you down
## Beaten bosses go home to the Kaiju Sanctuary (sanctuary.gd) with their crown on and count triple.
## Pure data: tests/mech_titans_rounds_test.gd proves every boss is fair at every difficulty (check()).

## id -> base: data.gd KAIJU kind; size: height multiplier; hp: health multiplier on top of the round's;
## sig: the signature attack (kaiju_ai.gd ATTACKS has its [range, windup, recover, cooldown]); shape: "circle"
## (round the boss), "target" (a circle where it aims) or "line"; r: radius / half width m; len: line length m;
## dmg: armour it knocks off (before the difficulty's dmg); slow: s the Titan walks slowly after a hit;
## places: where it turns up; color: glow, crown and warning colour.
const LIST := {
	"king_sizzle": {"name": "KING SIZZLE", "base": "lizard", "size": 1.45, "hp": 1.5, "sig": "king_stomp", "shape": "circle",
		"r": 17.0, "len": 0.0, "dmg": 18.0, "slow": 0.0, "places": ["downtown", "volcano"], "color": Color(1.0, 0.5, 0.2)},
	"mega_wobbles": {"name": "MEGA WOBBLES", "base": "jelly", "size": 1.4, "hp": 1.4, "sig": "mega_flop", "shape": "target",
		"r": 12.0, "len": 0.0, "dmg": 16.0, "slow": 0.0, "places": ["downtown", "harbour"], "color": Color(1.0, 0.45, 0.85)},
	"storm_zappy": {"name": "STORM ZAPPY", "base": "eel", "size": 1.35, "hp": 1.5, "sig": "storm_ring", "shape": "circle",
		"r": 19.0, "len": 0.0, "dmg": 16.0, "slow": 1.5, "places": ["powerplant", "harbour", "moon"], "color": Color(0.45, 0.7, 1.0)},
	"frost_dusty": {"name": "FROST DUSTY", "base": "moth", "size": 1.35, "hp": 1.45, "sig": "frost_gust", "shape": "line",
		"r": 6.5, "len": 40.0, "dmg": 10.0, "slow": 3.0, "places": ["snowy", "moon", "volcano"], "color": Color(0.7, 0.92, 1.0)},
}
const ORDER: Array[String] = ["king_sizzle", "mega_wobbles", "storm_zappy", "frost_dusty"]
## The signature moves' timing: [range m, windup s (at tell 1.0), recover s, cooldown s] (kaiju_ai.gd reads it).
const SIG_ATTACKS := {
	"king_stomp": [24.0, 2.0, 1.4, 11.0], "mega_flop": [34.0, 2.0, 1.5, 10.0],
	"storm_ring": [30.0, 2.0, 1.2, 11.0], "frost_gust": [40.0, 1.9, 1.2, 10.0],
}
const MIN_TELL := 1.8  ## a boss move never warns for less than this (seconds)
const REACT := 0.6
const WALK := 6.5  ## mech.gd WALK_SPEED
const DASH := 20.0  ## mech.gd dash_dist (made rounds always have the dash)
const DASH_TIME := 0.55
const TITAN_R := 2.6
const ARMOUR := 100.0
const BLOCK := 0.2  ## mech.gd: a block takes 20%


static func info(id: String) -> Dictionary:
	return LIST.get(id, {})


static func of_sig(sig: String) -> Dictionary:
	for id in LIST:
		if String(LIST[id]["sig"]) == sig:
			return LIST[id]
	return {}


## The bosses that suit a place (every place has at least one; check()).
static func for_place(place: String) -> Array:
	var out: Array = []
	for id in ORDER:
		if (LIST[id]["places"] as Array).has(place):
			out.append(id)
	return out


## Seconds of warning at a difficulty with tell multiplier `tell` (roundgen.gd curve()).
static func tell_time(id: String, tell: float) -> float:
	var sig: Array = SIG_ATTACKS[String(LIST[id]["sig"])]
	return maxf(MIN_TELL, float(sig[1]) * tell)


## The worst escape: standing right in the middle of the warning (a line: in its middle, sideways out).
## Returns [on foot, with the dash].
static func escape_times(id: String) -> Array:
	var b := info(id)
	var out_d := float(b["r"]) + TITAN_R
	return [REACT + out_d / WALK, REACT + DASH_TIME + maxf(0.0, out_d - DASH) / WALK]


## Why boss `id` isn't fair at this curve point (empty = fair): it suits a place; its warning is long enough
## (at gentle the Titan can WALK out, at harder modes it may need the dash); one hit never knocks a full
## Titan over (at gentle not even two in a row); a blocked hit is small; the name is one or two capital words.
static func check(id: String, curve: Dictionary, gentle: bool) -> Array:
	var out: Array = []
	var b := info(id)
	if b.is_empty():
		return ["unknown boss %s" % id]
	if not SIG_ATTACKS.has(String(b["sig"])):
		out.append("%s has no timing for %s" % [id, b["sig"]])
		return out
	var tell := tell_time(id, float(curve.get("tell", 1.0)))
	var esc := escape_times(id)
	if tell < MIN_TELL - 0.001:
		out.append("%s warns for %.2f s" % [b["name"], tell])
	if gentle and tell < float(esc[0]):
		out.append("%s: a gentle Titan can't walk out (%.2f s warning, needs %.2f)" % [b["name"], tell, esc[0]])
	if tell < float(esc[1]):
		out.append("%s: even a dash can't get out (%.2f s warning, needs %.2f)" % [b["name"], tell, esc[1]])
	var hit := float(b["dmg"]) * float(curve.get("dmg", 1.0))
	if hit >= ARMOUR * (0.5 if gentle else 0.9):
		out.append("%s hits for %.0f" % [b["name"], hit])
	if hit * BLOCK > 6.0:
		out.append("%s blocked still hits for %.1f" % [b["name"], hit * BLOCK])
	var cd := float(SIG_ATTACKS[String(b["sig"])][3])
	if cd * float(curve.get("calm", 1.0)) < tell + 4.0:
		out.append("%s's big move comes back too soon" % b["name"])
	if float(b["size"]) > 1.5 or float(b["size"]) < 1.2:
		out.append("%s size %.2f" % [b["name"], b["size"]])
	var words := String(b["name"]).split(" ", false)
	if words.size() > 2 or String(b["name"]) != String(b["name"]).to_upper():
		out.append("boss name '%s' must be one or two capital words" % b["name"])
	return out
