extends RefCounted
## SHEEP ROUND-UP second pass: seasons and weather, the team mode, dog tricks, warned events. Pure data (no nodes):
## main.gd plays it, weather.gd / events.gd draw it, tests/sheep_round_up_gen_test.gd proves it fair over many seeds.
##  - SEASONS (the real calendar) dress the fields: spring blossom, summer sun, autumn leaves, winter snow. Each
##    field's WEATHER is seeded from its own seed and the season: SUNNY, WINDY (sheep drift downwind), RAINY (sheep
##    huddle and dawdle) or SNOWY (everyone a little slower). Weather never changes a field's layout (fieldgen.gd).
##  - MODE: GENTLE / BRAVE / HARD (core/pick_orbs.gd MODES) picked on the shared pick orbs before the first field of
##    a visit. Gentle: a longer clock, one event a field; Hard: a shorter clock, three events. Every number goes
##    Gentle <= Brave <= Hard.
##  - DOG TRICKS before fields 2, 4, 6 and 8 of a visit (three not learned yet; they last the visit): BIG BARK (a
##    bigger bark), ZOOMIES (faster dogs), SPLASH PAWS (no paddling in the stream), SHEEP CALL (sheep wander less).
##    Tricks only make things easier.
##  - EVENTS: a FOX at the fence (it trots in, the sheep near it scatter; a dog or a bark near it sends it home) and a
##    THUNDER clap (unpenned sheep near the strike scatter). Each is told WARN_SECS early by warning rings on the
##    ground (core/warn_rings.gd) on every machine. Every event also adds EVENT_BONUS seconds to the clock, so an
##    event never makes a field less doable; strikes keep away from the pen and the open gates' doorsteps.

const Seeded := preload("res://core/seeded.gd")
const FieldGen := preload("res://games/sheep_round_up/fieldgen.gd")

const SEASONS: Array = ["spring", "summer", "autumn", "winter"]
const SEASON_LOOK := {
	"spring": {"ground": Color(0.5, 0.82, 0.38), "word": "SPRING"},
	"summer": {"ground": Color(0.56, 0.8, 0.3), "word": "SUMMER"},
	"autumn": {"ground": Color(0.66, 0.72, 0.32), "word": "AUTUMN"},
	"winter": {"ground": Color(0.6, 0.76, 0.7), "word": "WINTER"},  # frosty grass: white sheep must still stand out,
}
## Weather chances per season.
const WEATHER_W := {
	"spring": {"sunny": 3.0, "windy": 1.5, "rainy": 2.0},
	"summer": {"sunny": 5.0, "windy": 1.5, "rainy": 0.5},
	"autumn": {"sunny": 2.0, "windy": 3.0, "rainy": 2.0},
	"winter": {"sunny": 2.0, "windy": 1.0, "snowy": 3.0},
}
const WEATHER_ORDER: Array = ["sunny", "windy", "rainy", "snowy"]
## sheep: speed factor; wander: wander factor; dog: dog speed factor; drift: m/s downwind for wandering sheep.
const WEATHER := {
	"sunny": {"sheep": 1.0, "wander": 1.0, "dog": 1.0, "drift": 0.0, "pic": "sun", "line": "A sunny day!"},
	"windy": {"sheep": 1.0, "wander": 1.0, "dog": 1.0, "drift": 0.35, "pic": "cloud", "line": "Windy! Sheep drift!"},
	"rainy": {"sheep": 0.9, "wander": 0.6, "dog": 1.0, "drift": 0.0, "pic": "storm", "line": "Rain! Sheep huddle!"},
	"snowy": {"sheep": 0.85, "wander": 0.8, "dog": 0.9, "drift": 0.0, "pic": "snowflake", "line": "Snow! Brrr!"},
}

const MODES := {
	"gentle": {"time": 1.35, "events": 1},
	"brave": {"time": 1.0, "events": 2},
	"hard": {"time": 0.85, "events": 3},
}
const MODE_ORDER: Array = ["gentle", "brave", "hard"]

const TRICKS := {
	"bigbark": {"name": "BIG BARK", "pic": "bigbark", "color": Color(1.0, 0.75, 0.3)},
	"zoomies": {"name": "ZOOMIES", "pic": "zoomies", "color": Color(0.45, 0.9, 1.0)},
	"splash": {"name": "SPLASH PAWS", "pic": "splashpaws", "color": Color(0.4, 0.65, 1.0)},
	"call": {"name": "SHEEP CALL", "pic": "sheepcall", "color": Color(1.0, 0.55, 0.8)},
}
const TRICK_ORDER: Array = ["bigbark", "zoomies", "splash", "call"]
const TRICK_BEFORE: Array = [2, 4, 6, 8]  ## trick picks come before these fields of a visit
const BIG_BARK := 1.5
const ZOOMIES := 1.25
const CALL_WANDER := 0.5

const EVENT_KINDS: Array = ["fox", "thunder"]
const EVENT_COLORS := {"fox": Color(1.0, 0.55, 0.2), "thunder": Color(0.75, 0.8, 1.0)}
## A dog is its player's colour softened toward a sandy coat (main.gd _ensure_dog; palette.gd checks it).
const DOG_COAT := Color(0.95, 0.85, 0.7)
const DOG_COAT_MIX := 0.1  # (0.35 made the blue dog vanish on frosty grass, the green one on spring grass)
const EVENTS_FROM := 1  ## field level from which events come (the very first field is calm)
const WARN_SECS := 3.0
const FOX_SECS := 9.0  ## a fox stays this long unless a dog sends it home
const FOX_SPEED := 1.8
const FOX_SCARE := 2.2
const THUNDER_R := 3.2
const EVENT_FIRST := 15.0
const EVENT_GAP := 22.0
const EVENT_END := 15.0  ## no event in the last seconds of the clock
const EVENT_BONUS := 8.0  ## seconds added to the clock per event (an event never makes a field less doable)
const CLEAR := 0.8  ## a strike keeps this far (past its edge) from the pen and every open gate's doorstep


## The season on a date ("" = today).
static func season_for(date: String = "") -> String:
	return Seeded.season(date)  # (core/seeded.gd: one season table for every game)


static func season_of_month(month: int) -> String:
	if month == 12 or month <= 2:
		return "winter"
	if month <= 5:
		return "spring"
	if month <= 8:
		return "summer"
	return "autumn"


static func mode_of(id: String) -> String:
	return id if MODES.has(id) else "brave"


## A field's weather (its own seed + the season).
static func weather_for(field_seed: int, season: String) -> String:
	var w: Dictionary = WEATHER_W.get(season, WEATHER_W.summer)
	var keys: Array = w.keys()
	var ws: Array = []
	for k in keys:
		ws.append(float(w[k]))
	return String(keys[Seeded.weighted(Seeded.rng(field_seed, "weather"), ws)])


## The downwind direction of a windy field (a unit vector on the ground, x/z).
static func wind_dir(field_seed: int) -> Vector2:
	var a := Seeded.rng(field_seed, "wind").randf() * TAU
	return Vector2(cos(a), sin(a))


## Trick picks: up to three tricks not learned yet, before field n of a visit ([] when there's no pick).
static func trick_offer(n: int, run_seed: int, learned: Array) -> Array:
	if not TRICK_BEFORE.has(n):
		return []
	var pool: Array = TRICK_ORDER.filter(func(k: String) -> bool: return not learned.has(k))
	return Seeded.shuffled(Seeded.rng(run_seed, "tricks%d" % n), pool).slice(0, 3)


## A field's clock for a mode (before event bonuses).
static func clock(base_time: float, mode: String) -> float:
	return base_time * float(MODES[mode_of(mode)].time)


## The field's events for a mode: [[t, kind, x, z, r], ...]. Hard's list is made first; Brave takes its first two
## and Gentle its first one. t: seconds into the field. f: the field (fieldgen.gd), time: the mode's clock.
static func make_events(f: Dictionary, field_seed: int, mode: String, time: float) -> Array:
	if int(f.get("level", 0)) < EVENTS_FROM:
		return []
	var rng := Seeded.rng(field_seed, "events")
	var all: Array = []
	var t := EVENT_FIRST + rng.randf_range(0.0, 8.0)
	var end := time + float(MODES.hard.events) * EVENT_BONUS - EVENT_END
	var tries := 0
	while all.size() < int(MODES.hard.events) and t <= end and tries < 60:
		tries += 1
		var kind: String = "fox" if rng.randf() < 0.55 else "thunder"
		if kind == "fox":
			var a := snappedf(rng.randf() * TAU, 0.01)
			var p := Vector2(cos(a), sin(a)) * (FieldGen.ARENA - 0.6)
			p = Vector2(snappedf(p.x, 0.01), snappedf(p.y, 0.01))
			if spot_ok(f, p, 1.0):
				all.append([snappedf(t, 0.1), "fox", p.x, p.y, 1.0])
			else:
				continue
		else:
			var r2 := rng.randf_range(2.5, FieldGen.ARENA - 1.5)
			var a2 := rng.randf() * TAU
			var c := Vector2(snappedf(cos(a2) * r2, 0.01), snappedf(sin(a2) * r2, 0.01))
			if spot_ok(f, c, THUNDER_R):
				all.append([snappedf(t, 0.1), "thunder", c.x, c.y, THUNDER_R])
			else:
				continue
		t += EVENT_GAP + rng.randf_range(0.0, 8.0)
	return all.slice(0, int(MODES[mode_of(mode)].events))


## Is a strike / fox spot clear of the pen and every open gate's doorstep, inside the field?
static func spot_ok(f: Dictionary, c: Vector2, r: float) -> bool:
	if c.length() > FieldGen.ARENA - 0.5:
		return false
	var pen := FieldGen.PEN + CLEAR + r
	if absf(c.x) < pen and absf(c.y) < pen:
		return false
	for side in 4:
		if FieldGen.gate_open(int(f.get("gates", 15)), side):
			var g := FieldGen.gate_point(side, 1.0)
			if Vector2(g.x, g.z).distance_to(c) < r + CLEAR + FieldGen.GAP:
				return false
	return true


## Why a field's mode numbers / events are wrong (empty = fine).
static func check_events(f: Dictionary, events: Array, mode: String, time: float) -> Array:
	var out: Array = []
	if not MODES.has(mode):
		return ["unknown mode %s" % mode]
	if events.size() > int(MODES[mode].events):
		out.append("%d events in %s" % [events.size(), mode])
	if int(f.get("level", 0)) < EVENTS_FROM and not events.is_empty():
		out.append("events on the first field")
	var last := -INF
	for e in events:
		var t := float(e[0])
		if not EVENT_KINDS.has(String(e[1])):
			out.append("unknown event %s" % e[1])
		if t < EVENT_FIRST - 0.01:
			out.append("event at %.1f s (too early)" % t)
		if t - last < EVENT_GAP - 0.01:
			out.append("events %.1f s apart" % (t - last))
		if t > time + events.size() * EVENT_BONUS - EVENT_END + 0.01:
			out.append("event at %.1f s too near the end" % t)
		last = t
		if not spot_ok(f, Vector2(float(e[2]), float(e[3])), float(e[4]) if String(e[1]) == "thunder" else 1.0):
			out.append("%s at (%.1f, %.1f) near the pen or a gate" % [e[1], float(e[2]), float(e[3])])
	return out


## Bigger = harder: [1 / seconds per sheep, events].
static func pressure(f: Dictionary, mode: String, base_time: float) -> Array:
	var ev := make_events(f, int(f.get("seed", 0)), mode, clock(base_time, mode))
	var time := clock(base_time, mode) + ev.size() * EVENT_BONUS
	return [100.0 * float((f.get("sheep", []) as Array).size()) / time, float(ev.size())]


static func dog_color(player: Color) -> Color:
	return player.lerp(DOG_COAT, DOG_COAT_MIX)
